#!/usr/bin/env python3
"""Self-contained checks for the parts you cannot afford to have wrong.

    python3 tests/test_failsafes.py

Builds a throwaway git repo in /tmp, stubs the agents (no tokens spent, no
network), and asserts: routing, write-scope enforcement, gap-closure rule,
error classification, and quota-stop -> resume.
"""
from __future__ import annotations

import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

ORCH = pathlib.Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ORCH))

PASS, FAIL = [], []


def check(name: str, cond, detail: str = "") -> None:
    (PASS if cond else FAIL).append(name)
    print(f"  {'✓' if cond else '✗'} {name}{'' if cond else '  ← ' + detail}")


def sandbox() -> pathlib.Path:
    root = pathlib.Path(tempfile.mkdtemp(prefix="kadence-orch-"))
    (root / "design").mkdir()
    (root / "Kadence").mkdir()
    (root / "KadenceTests").mkdir()
    (root / "design/tokens.json").write_text("{}\n")
    (root / "design/GAPS.md").write_text("# Design gaps\n")
    for f in ("STATUS.md", "CONTEXT.md", "DECISIONS.md"):
        (root / f).write_text(f"# {f}\n")
    (root / "Kadence/.keep").write_text("")
    (root / ".gitignore").write_text("orchestrator/\n")
    shutil.copytree(ORCH, root / "orchestrator",
                    ignore=shutil.ignore_patterns("state", "__pycache__", ".venv"))
    for a in (["init", "-qb", "main"], ["config", "user.email", "t@t"],
              ["config", "user.name", "test"], ["add", "-A"],
              ["commit", "-qm", "init"]):
        subprocess.run(["git", *a], cwd=root, check=True, capture_output=True)
    return root


def main() -> int:
    root = sandbox()
    os.chdir(root)
    sys.path.insert(0, str(root / "orchestrator"))
    import run as R
    from kadence_flow import agents, guards, persist, verify as V
    from kadence_flow.config import Config
    from kadence_flow.errors import QuotaExhausted, classify

    # Sections below swap agents.run_agent for stubs, so grab the real one now
    # — by the time the rotation section runs, the attribute is a stub.
    REAL_RUN_AGENT = agents.run_agent

    persist.STATE_DIR = root / "orchestrator/state"
    persist.DB = persist.STATE_DIR / "checkpoints.sqlite"
    persist.LOG = persist.STATE_DIR / "run.log"
    persist.MIRROR = persist.STATE_DIR / "last_state.json"
    persist.RESUME = persist.STATE_DIR / "RESUME.md"

    cfg = Config.load(ORCH / "config.json")
    cfg.repo, cfg.skip_build, cfg.max_cycles = root, True, 6
    cfg.phase, cfg.work_branch = "test", "auto/phase-test"

    def agent_run(payload, cost=0.0, turns=1):
        return agents.AgentRun(f"reasoning…\n```json\n{payload}\n```", cost, turns)

    # ---------------------------------------------------------- 1. scope walls
    print("\nwrite scope")
    for a, f in [("DA", "Kadence/X.swift"), ("DA", "STATUS.md"),
                 ("DA", "DEVIATIONS.md"), ("CA", "DECISIONS.md"),
                 ("CA", "design/components.md"), ("CA", "CONTEXT.md"),
                 ("CA", "Kadence/DesignSystem/Tokens.swift")]:
        ok, _ = guards.check_write(a, f)
        check(f"{a} refused {f}", not ok)
    for a, f in [("DA", "design/tokens.json"), ("CA", "design/GAPS.md"),
                 ("CA", "Kadence/Views/DayView.swift"),
                 ("CA", "KadenceTests/ATests.swift"),
                 ("CA", "STATUS.md"), ("CA", "DEVIATIONS.md"),
                 ("CA", "screenshots/3/INDEX.md"), ("CA", "INDEX.md")]:
        ok, why = guards.check_write(a, f)
        check(f"{a} allowed {f}", ok, why)

    print("\nPreToolUse gate (the layer that runs under bypassPermissions)")
    from kadence_flow.guards import judge
    for a, tool, inp, want in [
            ("DA", "Write", {"file_path": str(root / "Kadence/X.swift")}, False),
            ("DA", "Edit", {"file_path": str(root / "design/layouts.md")}, True),
            ("CA", "Write", {"file_path": str(root / "design/GAPS.md")}, False),
            ("CA", "Edit", {"file_path": str(root / "design/GAPS.md")}, True),
            ("CA", "Write", {"file_path": str(root / "STATUS.md")}, True),
            ("CA", "Bash", {"command": "git commit -m x"}, False),
            ("CA", "Bash", {"command": "git checkout -- ."}, False),
            ("CA", "Bash", {"command": "xcodebuild -scheme Kadence build"}, True),
            ("DA", "Read", {"file_path": "/etc/hosts"}, True)]:
        ok, why = judge(a, tool, inp, root)
        check(f"{a} {tool} {'allowed' if want else 'denied'}: "
              f"{str(list(inp.values())[0])[-38:]}", ok == want, why)

    # ------------------------------------------- 2. a rogue write is reverted
    print("\nrogue writes are undone, and the task fails")
    MA = ('{"reasoning":"go","next":"DA","task_id":"T-01","title":"spec",'
          '"instruction":"x","acceptance":["a"],"files_expected":[]}')
    STOP = '{"reasoning":"stop","next":"BLOCKED","blocker":"end of test"}'
    n = {"i": 0}

    def rogue(prompt, **kw):
        n["i"] += 1
        if n["i"] == 1:
            return agent_run(MA)
        if n["i"] == 2:
            (root / "Kadence/Rogue.swift").write_text("// nope\n")
            (root / "DECISIONS.md").write_text("# tampered\n")
            return agent_run('{"task_id":"T-01","summary":"x","done":true}')
        return agent_run(STOP)

    agents.run_agent = rogue
    R._drive(cfg, R._initial(cfg))
    check("out-of-scope Swift file removed", not (root / "Kadence/Rogue.swift").exists())
    check("DECISIONS.md restored",
          (root / "DECISIONS.md").read_text().strip() == "# DECISIONS.md")
    state = R._last_state()
    led = state.get("ledger") or []
    check("task recorded as failed", led and not led[-1]["verification"]["ok"])

    # ------------------------- 2b. Parsa's own uncommitted work is not touched
    print("\nedits made by a human before the agent started are left alone")
    # On 2026-09-18 the guard reverted a live edit to orchestrator/run.py and
    # deleted an untracked directory, neither of which any agent had written:
    # it judged the whole dirty tree and could not tell whose work it was.
    (root / "orchestrator").mkdir(exist_ok=True)
    mine = root / "orchestrator" / "run.py"
    mine.write_text("# Parsa was editing this while the agent ran\n")
    stray = root / "scratch-notes.txt"
    stray.write_text("untracked human scratch\n")
    n2 = {"i": 0}

    def polite(prompt, **kw):
        n2["i"] += 1
        if n2["i"] == 1:
            return agent_run(MA)
        if n2["i"] == 2:
            return agent_run('{"task_id":"T-02","summary":"x","done":true}')
        return agent_run(STOP)

    agents.run_agent = polite
    R._drive(cfg, R._initial(cfg))
    check("human's edit to an off-limits file survives",
          mine.exists() and "Parsa was editing" in mine.read_text())
    check("human's untracked file is not deleted", stray.exists())
    state = R._last_state()
    led = state.get("ledger") or []
    check("and the task is not failed for the human's edits",
          led and led[-1]["verification"]["ok"],
          str(led[-1]["verification"]["summary"]) if led else "no ledger")
    mine.unlink(missing_ok=True)
    stray.unlink(missing_ok=True)

    # ------------------------------------------------------ 3. gap-closure rule
    print("\ngap closure rule (spec edit AND a closed GAPS entry with a §ref)")
    (root / "design/GAPS.md").write_text(
        "# Design gaps\n\n"
        "## 2026-09-10 — G-014 — divider elevation\nNeeds a value.\n\n"
        "## 2026-09-10 — G-015 — badge padding — CLOSED\n"
        "Resolved in components.md §4.2 — badge inset is 6pt.\n")
    check("closed gap accepted", V.gap_closures(root, ["G-015"])["ok"])
    check("open gap rejected", not V.gap_closures(root, ["G-014"])["ok"])
    check("invented gap id rejected", not V.gap_closures(root, ["G-099"])["ok"])

    # ------------------------------------------------- 4. error classification
    print("\nerror classification")
    cases = [("Claude usage limit reached, resets at 2026-09-10T18:00:00Z", "quota"),
             ("429 Too Many Requests", "quota"),
             ("Your credit balance is too low", "quota"),
             ("529 overloaded_error", "transient"),
             ("connection reset by peer", "transient"),
             ("TypeError: object is not callable", "fatal"),
             ("Failed to authenticate: OAuth session expired", "auth"),
             ("401 Unauthorized", "auth"),
             ("error_max_turns max_turns {}", "max_turns"),
             ("Claude Code returned an error result: Reached maximum number "
              "of turns (120) (exit code: 1)", "max_turns"),
             ("You've hit your session limit · resets 1:20pm (Europe/Vienna)",
              "quota")]
    for text, want in cases:
        got = classify(text).kind
        check(f"{want:<9} ← {text[:38]}", got == want, f"got {got}")
    check("clock-style reset parsed",
          classify("You've hit your session limit · resets 1:20pm "
                   "(Europe/Vienna)").reset_at is not None)
    check("reset time parsed",
          classify("Claude usage limit reached, resets at 2026-09-10T18:00:00Z").reset_at is not None)

    # --------------------------------------------- 5. quota stop, then resume
    print("\ntoken limit: stop cleanly, lose nothing, resume")
    # Pin the policy: this section is about checkpoint/rescue/resume, and it
    # must not change meaning because config.json switched to rotate.
    prior_on_quota, cfg.on_quota = cfg.on_quota, "stop"
    subprocess.run(["git", "checkout", "-q", "main"], cwd=root)
    subprocess.run(["git", "branch", "-D", "-q", cfg.work_branch], cwd=root,
                   capture_output=True)
    persist.DB.unlink(missing_ok=True)
    m = {"i": 0}
    MA2 = ('{"reasoning":"go","next":"DA","task_id":"T-77","title":"spec the block",'
           '"instruction":"x","acceptance":["a"],"files_expected":["design/components.md"]}')

    def dies(prompt, **kw):
        m["i"] += 1
        if m["i"] == 1:
            return agent_run(MA2, 0.02, 2)
        (root / "design/components.md").write_text("# half-written\n")
        raise QuotaExhausted("Claude usage limit reached. resets at 2026-09-10T18:00:00Z")

    agents.run_agent = dies
    code = R._drive(cfg, R._initial(cfg))
    check("exit code 75 (resumable)", code == 75, str(code))
    check("RESUME.md written", persist.RESUME.exists())
    check("partial work preserved", (root / "design/components.md").exists())
    log = subprocess.run(["git", "log", "--oneline", "-3"], cwd=root,
                         capture_output=True, text=True).stdout
    check("partial work committed as wip", "wip: T-77" in log, log)
    check("tree left clean", not guards.is_dirty(root))
    check("nothing landed on main", "wip:" not in subprocess.run(
        ["git", "log", "--oneline", "-5", "main"], cwd=root,
        capture_output=True, text=True).stdout)

    def recovered(prompt, **kw):
        if "Task T-77" in prompt:
            check("resumed task sees its earlier partial work",
                  "previous run of this exact task was cut short" in prompt)
            return agent_run('{"task_id":"T-77","summary":"finished it",'
                             '"files_changed":["design/components.md"],"done":true}', 0.02, 3)
        return agent_run('{"reasoning":"green","next":"PHASE_DONE","task_id":"T-78"}', 0.01, 1)

    agents.run_agent = recovered
    code = R._drive(cfg, None)
    check("resume finishes the phase", code == 0, str(code))
    cfg.on_quota = prior_on_quota

    # ------------------------------------------- 5b. gateway account rotation
    print("\nusage limit behind the gateway: rotate, then wait, then stop")
    from kadence_flow.errors import QuotaExhausted as QE
    from kadence_flow.errors import TransientError

    # run_agent's rotation loop: a limit re-issues the call so the gateway can
    # serve it from the next account. Zero waits so the test does not sleep.
    real_once = agents._run_once_with_backoff
    agents.run_agent = REAL_RUN_AGENT
    agents.configure_quota_rotation(3, [0, 0, 0])
    n = {"i": 0}

    def limited_twice(prompt, **kw):
        n["i"] += 1
        if n["i"] <= 2:
            raise QE("Claude usage limit reached")
        return agent_run('{"ok":true}', 0.0, 1)

    agents._run_once_with_backoff = limited_twice
    agents.run_agent("p")
    check("rotates onto the next account after a limit", n["i"] == 3, str(n["i"]))

    n["i"] = 0

    def always_limited(prompt, **kw):
        n["i"] += 1
        raise QE("Claude usage limit reached")

    agents._run_once_with_backoff = always_limited
    try:
        agents.run_agent("p")
        check("dry pool still raises", False, "no exception")
    except QE:
        check("dry pool raises after every rotation", n["i"] == 4, str(n["i"]))

    def boom(prompt, **kw):
        raise TransientError("503 overloaded")

    agents._run_once_with_backoff = boom
    try:
        agents.run_agent("p")
        check("non-quota errors are not rotated", False, "no exception")
    except TransientError:
        check("non-quota errors are not rotated", True)

    agents.configure_quota_rotation(0)
    agents._run_once_with_backoff = real_once

    # _drive under rotate: a dry pool waits for capacity instead of ending the
    # run, but cannot sleep forever — max_quota_waits bounds it.
    subprocess.run(["git", "checkout", "-q", "main"], cwd=root)
    subprocess.run(["git", "branch", "-D", "-q", cfg.work_branch], cwd=root,
                   capture_output=True)
    persist.DB.unlink(missing_ok=True)
    prior = (cfg.on_quota, cfg.quota_blind_wait_s, cfg.max_quota_waits)
    cfg.on_quota, cfg.quota_blind_wait_s, cfg.max_quota_waits = "rotate", 0, 2
    waits = {"n": 0}

    def dry(prompt, **kw):
        waits["n"] += 1
        if waits["n"] == 1:
            return agent_run(MA2, 0.02, 2)
        raise QE("Claude usage limit reached")

    agents.run_agent = dry
    code = R._drive(cfg, R._initial(cfg))
    check("dry pool waits for capacity, then stops at 75", code == 75, str(code))
    check("bounded by max_quota_waits, did not sleep forever",
          waits["n"] <= 6, str(waits["n"]))
    cfg.on_quota, cfg.quota_blind_wait_s, cfg.max_quota_waits = prior

    # ------------------------------------- 6. running out of turns is not a crash
    print("\nturn ceiling: salvage, do not crash")
    from kadence_flow.errors import MaxTurnsReached
    subprocess.run(["git", "checkout", "-q", "main"], cwd=root)
    subprocess.run(["git", "branch", "-D", "-q", cfg.work_branch], cwd=root,
                   capture_output=True)
    persist.DB.unlink(missing_ok=True)

    MA3 = ('{"reasoning":"go","next":"DA","task_id":"T-90","title":"spec it",'
           '"instruction":"x","acceptance":["a"],"files_expected":[]}')
    seen = {"decide_now": False, "n": 0}

    def out_of_turns(prompt, **kw):
        seen["n"] += 1
        if seen["n"] == 1:                      # MA burns its budget
            raise MaxTurnsReached("error_max_turns max_turns {}", "", 0.02, 40)
        if seen["n"] == 2:                      # MA asked to decide on what it has
            seen["decide_now"] = "Stop investigating" in prompt
            return agent_run(MA3, 0.01, 1)
        if seen["n"] == 3:                      # DA runs out mid-task
            (root / "design/layouts.md").write_text("# partial spec\n")
            raise MaxTurnsReached("error_max_turns max_turns {}",
                                  "half a report", 0.5, 120)
        return agent_run('{"reasoning":"stop","next":"BLOCKED",'
                         '"blocker":"end of test"}')

    agents.run_agent = out_of_turns
    R._drive(cfg, R._initial(cfg))
    check("MA is asked to decide rather than crashing", seen["decide_now"])
    st = R._last_state()
    led = st.get("ledger") or []
    check("the worker's partial work survives",
          (root / "design/layouts.md").read_text().startswith("# partial"))
    check("partial task is recorded, not done",
          bool(led) and led[-1]["report"].get("done") is False,
          str(led[-1]["report"].get("done")) if led else "no ledger entry")
    check("its summary says it ran out of turns",
          bool(led) and "RAN OUT OF TURNS" in (led[-1]["report"].get("summary") or ""))
    check("verification still ran on it", bool(led) and "ok" in led[-1]["verification"])

    print(f"\n{len(PASS)} passed, {len(FAIL)} failed")
    if FAIL:
        print("failed: " + ", ".join(FAIL))
    shutil.rmtree(root, ignore_errors=True)
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
