#!/usr/bin/env python3
"""Kadence agent orchestrator.

    python3 run.py run      [--phase 3] [--goal "..."] [--fresh]
    python3 run.py resume
    python3 run.py status
    python3 run.py dry                 # stub agents, no tokens spent
    python3 run.py reset               # wipe checkpoints (not your git branch)

Exit codes: 0 phase done · 10 blocked (needs Parsa) · 20 budget/cycle stop
            75 token limit hit, resumable
"""
from __future__ import annotations

import argparse
import atexit
import json
import os
import shutil
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from kadence_flow import agents, graph as graph_mod, guards, persist  # noqa: E402
from kadence_flow.config import Config  # noqa: E402
from kadence_flow.errors import AuthExpired, QuotaExhausted  # noqa: E402

CONFIG_PATH = HERE / "config.json"
LOCK = HERE / "state" / "orchestrator.lock"
EXIT = {"phase_done": 0, "blocked": 10, "budget_stop": 20,
        "auth_stop": 30, "quota_stop": 75}


def _acquire_lock() -> None:
    """One orchestrator per repo. Two sharing a checkpoint, a branch and a
    working tree race each other's app launches and interleave commits —
    that is what corrupted the ledger on 2026-09-11."""
    if LOCK.exists():
        try:
            pid = int(LOCK.read_text().split()[0])
        except (ValueError, IndexError, OSError):
            pid = -1
        alive = False
        if pid > 0:
            try:
                os.kill(pid, 0)          # signal 0 = "does this pid exist?"
                alive = True
            except ProcessLookupError:
                alive = False            # gone; the lock is stale
            except PermissionError:
                alive = True             # exists, just owned by another user
            except OSError:
                alive = False
        if alive:
            print(f"An orchestrator is already running (pid {pid}).\n"
                  f"Two at once corrupt the checkpoint and race the app under "
                  f"test.\nStop it first, or remove {LOCK} if that pid is dead.")
            sys.exit(2)
        LOCK.unlink(missing_ok=True)     # stale
    LOCK.parent.mkdir(parents=True, exist_ok=True)
    LOCK.write_text(f"{os.getpid()} {datetime.now().isoformat(timespec='seconds')}\n")
    atexit.register(_release_lock)


def _release_lock() -> None:
    try:
        if LOCK.exists() and LOCK.read_text().split()[0] == str(os.getpid()):
            LOCK.unlink()
    except (OSError, IndexError):
        pass


def _thread(cfg: Config) -> str:
    return f"kadence-phase-{cfg.phase}"


def _initial(cfg: Config) -> dict:
    return {
        "phase": cfg.phase, "goal": cfg.goal, "cycle": 0,
        "max_cycles": cfg.max_cycles, "status": "running", "stop_reason": "",
        "ledger": [], "cost_usd": 0.0, "max_cost_usd": cfg.max_cost_usd,
        "consecutive_failures": 0, "thread_id": _thread(cfg),
        "started_at": datetime.now(timezone.utc).isoformat(),
        "work_branch": cfg.work_branch,
    }


def _rescue(cfg: Config, state: dict, reason: str, reset_at=None) -> None:
    """Nothing an agent wrote is ever lost, even mid-task."""
    task_id = (state.get("task") or {}).get("task_id", "unknown")
    if guards.is_dirty(cfg.repo):
        guards.ensure_branch(cfg.repo, cfg.work_branch)
        sha = guards.commit_all(cfg.repo, f"wip: {task_id} — interrupted ({reason})")
        if sha:
            persist.log(f"  saved partial work as {sha[:8]} on {cfg.work_branch}")
    path = persist.write_resume(state, reason, reset_at, _thread(cfg))
    persist.log(f"  wrote {path}")


def _tokens(state: dict) -> str:
    t = state.get("tokens") or {}
    if not t:
        return "not recorded"
    def k(n):
        return f"{n/1000:.0f}k" if n >= 1000 else str(n)
    return (f"{k(t.get('in', 0))} in · {k(t.get('out', 0))} out · "
            f"{k(t.get('cache_read', 0))} cache-read")


def _summarise(state: dict) -> None:
    print("\n" + "=" * 62)
    print(f"status      : {state.get('status')}")
    print(f"reason      : {state.get('stop_reason')}")
    print(f"cycles      : {state.get('cycle')}")
    print(f"usage       : {_tokens(state)}")
    print(f"              (SDK estimate ~${state.get('cost_usd', 0):.2f} at API list"
          f" prices — not billed on a subscription)")
    print(f"work branch : {state.get('work_branch')}")
    led = state.get("ledger") or []
    if led:
        print("\ntasks this run:")
        for e in led:
            t, v = e.get("task", {}), e.get("verification", {})
            mark = "✓" if v.get("ok") else "✗"
            print(f"  {mark} {t.get('task_id'):<10} {t.get('agent'):<3} "
                  f"{t.get('title', '')[:44]:<46} {v.get('summary', '')[:40]}")
    print("=" * 62)


def _invoke(cfg: Config, fresh_input) -> dict:
    g = graph_mod.build(cfg)
    with persist.checkpointer() as saver:
        app = g.compile(checkpointer=saver)
        conf = {"configurable": {"thread_id": _thread(cfg)},
                "recursion_limit": cfg.max_cycles * 4 + 12}
        state = app.invoke(fresh_input, conf)
        persist.mirror(state)
        return state


def _drive(cfg: Config, fresh_input) -> int:
    """Run, and survive a token limit: checkpoint, then stop or wait."""
    while True:
        state: dict = {}
        if fresh_input:
            persist.mirror(fresh_input)
        try:
            state = _invoke(cfg, fresh_input)
        except AuthExpired as e:
            state = _last_state()
            persist.log(f"\n■ NOT LOGGED IN: {str(e)[:200]}")
            _rescue(cfg, state, "the claude CLI is not logged in")
            print("\nThe Claude CLI session has expired. In a terminal run:\n"
                  "    claude            (then /login)\n"
                  "then:  python3 run.py resume")
            return EXIT["auth_stop"]
        except QuotaExhausted as e:
            state = _last_state()
            reset = e.reset_at
            persist.log(f"\n■ TOKEN LIMIT: {str(e)[:300]}")
            _rescue(cfg, state, "token/usage limit reached", reset)
            if cfg.on_quota == "wait" and reset:
                nap = max(60, (reset - datetime.now(timezone.utc)).total_seconds() + 60)
                persist.log(f"  waiting {nap/60:.0f} min for the limit to reset "
                            f"({reset.astimezone():%H:%M})…")
                time.sleep(nap)
                fresh_input = None          # resume from checkpoint
                continue
            print("\nResume later with:  python3 run.py resume")
            return EXIT["quota_stop"]
        except KeyboardInterrupt:
            state = _last_state()
            persist.log("\n■ interrupted by you")
            _rescue(cfg, state, "you pressed ctrl-c")
            return EXIT["quota_stop"]
        except Exception as e:                      # noqa: BLE001
            state = _last_state()
            persist.log(f"\n■ unexpected failure: {type(e).__name__}: {e}")
            _rescue(cfg, state, f"unexpected failure: {type(e).__name__}")
            raise
        _summarise(state)
        if state.get("status") == "blocked":
            print("\nMA needs a decision from you:\n  "
                  f"{state.get('stop_reason')}\n")
        return EXIT.get(state.get("status", ""), 1)


def _last_state() -> dict:
    try:
        return json.loads(persist.MIRROR.read_text())
    except (OSError, json.JSONDecodeError):
        return {}


# ----------------------------------------------------------------- dry runner

def _install_stubs() -> None:
    """Prove the wiring — routing, guards, verify, checkpoint, resume —
    without spending a single token."""
    seq = iter([
        ('{"reasoning":"stub","next":"DA","task_id":"P0-T01","title":"stub design task",'
         '"instruction":"do nothing","acceptance":["nothing"],"files_expected":[]}'),
        '{"task_id":"P0-T01","summary":"stub designer did nothing","files_changed":[],'
        '"gaps_opened":[],"gaps_closed":[],"done":true}',
        ('{"reasoning":"stub","next":"CA","task_id":"P0-T02","title":"stub code task",'
         '"instruction":"do nothing","acceptance":["nothing"],"files_expected":[]}'),
        '{"task_id":"P0-T02","summary":"stub coder did nothing","files_changed":[],'
        '"gaps_opened":[],"gaps_closed":[],"done":true}',
        '{"reasoning":"stub says finished","next":"PHASE_DONE","task_id":"P0-T03",'
        '"title":"","instruction":"","acceptance":[],"blocker":null}',
    ])

    def stub(prompt, **kw):
        try:
            payload = next(seq)
        except StopIteration:
            payload = '{"reasoning":"exhausted","next":"BLOCKED","blocker":"stub end"}'
        return agents.AgentRun(f"stub\n```json\n{payload}\n```", 0.0, 1)

    agents.run_agent = stub


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["run", "resume", "status", "dry", "reset"])
    ap.add_argument("--phase")
    ap.add_argument("--goal")
    ap.add_argument("--max-cycles", type=int)
    ap.add_argument("--fresh", action="store_true",
                    help="discard the checkpoint for this phase and start over")
    ap.add_argument("--on-quota", choices=["stop", "wait"])
    ap.add_argument("--skip-build", action="store_true")
    a = ap.parse_args()

    cfg = Config.load(CONFIG_PATH)
    if a.phase:
        cfg.phase = a.phase
        cfg.work_branch = f"auto/phase-{a.phase}"
    if a.goal:
        cfg.goal = a.goal
    if a.max_cycles:
        cfg.max_cycles = a.max_cycles
    if a.on_quota:
        cfg.on_quota = a.on_quota
    if a.skip_build:
        cfg.skip_build = True

    persist.ensure()

    if a.command == "status":
        s = _last_state()
        if not s:
            print("no run recorded yet")
            return 0
        _summarise(s)
        if persist.RESUME.exists():
            print("\n" + persist.RESUME.read_text())
        return 0

    if a.command == "reset":
        for p in (persist.DB, persist.MIRROR, persist.RESUME):
            if p.exists():
                p.unlink()
        print("checkpoints cleared. your git branch is untouched.")
        return 0

    if a.command == "dry":
        _install_stubs()
        cfg.skip_build = True
        cfg.max_cycles = min(cfg.max_cycles, 4)
        persist.log("dry run — stub agents, no tokens, no build")
        return _drive(cfg, _initial(cfg))

    if a.command == "resume":
        _acquire_lock()
        if not persist.DB.exists():
            print("nothing to resume — no checkpoint for this phase")
            return 1
        persist.log(f"resuming {_thread(cfg)}")
        return _drive(cfg, None)

    # run
    _acquire_lock()
    if a.fresh and persist.DB.exists():
        persist.DB.unlink()
    if not shutil.which("git"):
        print("git not found"); return 1
    persist.log(f"starting phase {cfg.phase} on branch {cfg.work_branch}")
    guards.ensure_branch(cfg.repo, cfg.work_branch)
    return _drive(cfg, _initial(cfg))


if __name__ == "__main__":
    sys.exit(main())
