"""Durability. If the run dies mid-phase, nothing is lost and `resume` works."""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Optional

STATE_DIR = Path(__file__).resolve().parent.parent / "state"
DB = STATE_DIR / "checkpoints.sqlite"
LOG = STATE_DIR / "run.log"
MIRROR = STATE_DIR / "last_state.json"
RESUME = STATE_DIR / "RESUME.md"


def _now() -> str:
    return datetime.now(timezone.utc).astimezone().strftime("%Y-%m-%d %H:%M:%S")


def ensure() -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)


def log(line: str, *, echo: bool = True) -> None:
    ensure()
    with LOG.open("a") as f:
        f.write(f"[{_now()}] {line}\n")
    if echo:
        print(line, flush=True)


def mirror(state: dict[str, Any]) -> None:
    """A plain-JSON copy of state next to the sqlite checkpoint, so the run is
    still legible if the checkpoint db is unreadable."""
    ensure()
    try:
        MIRROR.write_text(json.dumps(state, indent=2, default=str))
    except (TypeError, OSError):
        pass


def checkpointer():
    """SqliteSaver context manager; falls back to in-memory if the extra
    package is missing (the run still works, resume does not)."""
    ensure()
    try:
        from langgraph.checkpoint.sqlite import SqliteSaver
        return SqliteSaver.from_conn_string(str(DB))
    except ImportError:
        from contextlib import nullcontext
        from langgraph.checkpoint.memory import MemorySaver
        log("! langgraph-checkpoint-sqlite not installed — resume disabled")
        return nullcontext(MemorySaver())


def write_resume(state: dict[str, Any], reason: str,
                 reset_at: Optional[datetime] = None,
                 thread_id: str = "") -> Path:
    ensure()
    task = state.get("task") or {}
    ver = state.get("verification") or {}
    lines = [
        "# Run interrupted",
        "",
        f"- when: {_now()}",
        f"- why: **{reason}**",
    ]
    if reset_at:
        local = reset_at.astimezone()
        lines.append(f"- limit resets: **{local:%Y-%m-%d %H:%M %Z}**")
    lines += [
        f"- phase: {state.get('phase', '?')}",
        f"- cycle: {state.get('cycle', 0)}",
        f"- spent this run: ${state.get('cost_usd', 0):.2f}",
        f"- thread: `{thread_id or state.get('thread_id', '')}`",
        f"- work branch: `{state.get('work_branch', '')}`",
        "",
        "## Where it stopped",
        f"- last task: `{task.get('task_id', '—')}` → {task.get('agent', '—')} — "
        f"{task.get('title', '—')}",
        f"- last verification: {ver.get('summary', 'not run')}",
        "",
        "## To continue",
        "```",
        "python3 run.py resume",
        "```",
        "Everything the agents wrote is committed on the work branch, including any "
        "half-finished task (as a `wip:` commit). Nothing is on `main`.",
    ]
    RESUME.write_text("\n".join(lines))
    return RESUME
