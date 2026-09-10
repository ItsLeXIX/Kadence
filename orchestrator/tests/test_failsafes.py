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
                 ("CA", "screenshots/3/INDEX.md")]:
        ok, why = guards.check_write(a, f)
        check(f"{a} allowed {f}", ok, why)

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
             ("401 Unauthorized", "auth")]
    for text, want in cases:
        got = classify(text).kind
        check(f"{want:<9} ← {text[:38]}", got == want, f"got {got}")
    check("reset time parsed",
          classify("Claude usage limit reached, resets at 2026-09-10T18:00:00Z").reset_at is not None)

    # --------------------------------------------- 5. quota stop, then resume
    print("\ntoken limit: stop cleanly, lose nothing, resume")
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

    print(f"\n{len(PASS)} passed, {len(FAIL)} failed")
    if FAIL:
        print("failed: " + ", ".join(FAIL))
    shutil.rmtree(root, ignore_errors=True)
    return 1 if FAIL else 0


if __name__ == "__main__":
    sys.exit(main())
