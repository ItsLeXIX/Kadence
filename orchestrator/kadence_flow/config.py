from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parent.parent.parent
PROMPTS = Path(__file__).resolve().parent / "prompts"


@dataclass
class Config:
    repo: Path = REPO
    phase: str = "3"
    goal: str = ""
    manager_model: str | None = "sonnet"
    designer_model: str | None = "opus"
    coder_model: str | None = "sonnet"
    fallback_model: str | None = "sonnet"
    manager_max_turns: int = 15
    worker_max_turns: int = 90
    max_cycles: int = 12
    max_cost_usd: float = 0.0          # 0 = no ceiling (subscription runs)
    worker_budget_usd: float = 0.0     # per-task ceiling, 0 = none
    max_consecutive_failures: int = 3
    max_buffer_mb: int = 32            # per-JSON-message transport cap
    skip_build: bool = False           # true off-Mac / for dry runs
    on_quota: str = "stop"             # "stop" | "wait" | "rotate"
    # "rotate" is for running behind a gateway (OmniRoute) that holds a pool of
    # accounts: a usage limit re-issues the call so the gateway serves it from
    # the next healthy account. Only once every rotation comes back limited is
    # the pool really dry, and then rotate falls back to "wait" — sleep until
    # the earliest reset and carry on, rather than ending the run.
    quota_rotations: int = 4
    quota_backoff: list[int] = field(default_factory=lambda: [30, 90, 180, 300])
    # Where the gateway listens. Used to check the run is actually pointed at it
    # before promising rotation; empty means "whatever ANTHROPIC_BASE_URL says".
    gateway_url: str = ""
    # Wait this long when the pool is dry but no reset time could be parsed.
    quota_blind_wait_s: int = 900
    # Give up after this many consecutive dry-pool waits that produced no work,
    # so an overnight run cannot sleep forever against a permanently dead pool.
    max_quota_waits: int = 8
    work_branch: str = ""              # default: auto/phase-<phase>

    @classmethod
    def load(cls, path: Path) -> "Config":
        data: dict[str, Any] = {}
        if path.exists():
            data = json.loads(path.read_text())
        data.pop("_comment", None)
        cfg = cls(**{k: v for k, v in data.items() if k in cls.__annotations__})
        cfg.repo = Path(data.get("repo", REPO)).expanduser().resolve()
        if not cfg.work_branch:
            cfg.work_branch = f"auto/phase-{cfg.phase}"
        return cfg

    def prompt(self, name: str) -> str:
        return (PROMPTS / f"{name}.md").read_text()
