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
    coder_model: str | None = "opus"
    manager_max_turns: int = 15
    worker_max_turns: int = 90
    max_cycles: int = 12
    max_cost_usd: float = 0.0          # 0 = no ceiling (subscription runs)
    worker_budget_usd: float = 0.0     # per-task ceiling, 0 = none
    max_consecutive_failures: int = 3
    skip_build: bool = False           # true off-Mac / for dry runs
    on_quota: str = "stop"             # "stop" | "wait"
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
