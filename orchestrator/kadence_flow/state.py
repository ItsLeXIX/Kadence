"""Graph state for the Kadence MA -> (DA|CA) -> verify -> MA loop."""
from __future__ import annotations

from typing import Any, Literal, Optional, TypedDict

Agent = Literal["DA", "CA"]
Decision = Literal["DA", "CA", "PHASE_DONE", "BLOCKED"]


class Task(TypedDict, total=False):
    task_id: str
    agent: Agent
    title: str
    instruction: str
    acceptance: list[str]
    files_expected: list[str]


class Report(TypedDict, total=False):
    task_id: str
    agent: str
    summary: str
    files_changed: list[str]
    gaps_opened: list[str]
    gaps_closed: list[str]
    decisions_proposed: list[str]
    done: bool
    raw_tail: str
    cost_usd: float
    num_turns: int


class Verification(TypedDict, total=False):
    task_id: str
    ok: bool
    checks: list[dict[str, Any]]   # {name, ok, detail}
    scope_violations: list[str]
    summary: str


class LedgerEntry(TypedDict, total=False):
    cycle: int
    task: Task
    report: Report
    verification: Verification
    commit: Optional[str]


class OrchestratorState(TypedDict, total=False):
    # goal
    phase: str
    goal: str

    # loop control
    cycle: int
    max_cycles: int
    status: Literal["running", "phase_done", "blocked", "budget_stop", "quota_stop"]
    stop_reason: str

    # current step
    decision: Decision
    task: Task
    report: Report
    verification: Verification
    consecutive_failures: int

    # history (compact; MA sees a trimmed view)
    ledger: list[LedgerEntry]

    # accounting. cost_usd is the SDK's local estimate at API list prices —
    # on a subscription it is a relative measure of work, not money billed.
    cost_usd: float
    max_cost_usd: float
    tokens: dict[str, int]

    # bookkeeping
    thread_id: str
    started_at: str
    work_branch: str
