"""Calling Claude. One place, so retry/backoff/quota handling exists once."""
from __future__ import annotations

import asyncio
import json
import os
import re
import time
from pathlib import Path
from typing import Any, Callable, Optional

from .errors import (AuthExpired, ContractError, MaxTurnsReached,
                     OrchestratorError, QuotaExhausted, TransientError,
                     classify)
from . import guards

BACKOFF = [10, 30, 90]          # seconds, transient errors only
JSON_BLOCK = re.compile(r"```json\s*(\{.*?\})\s*```", re.S)


# --------------------------------------------------------------- JSON parsing

def extract_json(text: str) -> dict[str, Any]:
    """Pull the last ```json block. Falls back to the last balanced {...}."""
    blocks = JSON_BLOCK.findall(text or "")
    for raw in reversed(blocks):
        try:
            return json.loads(raw)
        except json.JSONDecodeError:
            continue
    depth, start, best = 0, None, None
    for i, ch in enumerate(text or ""):
        if ch == "{":
            if depth == 0:
                start = i
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0 and start is not None:
                best = (text or "")[start:i + 1]
    if best:
        try:
            return json.loads(best)
        except json.JSONDecodeError:
            pass
    raise ContractError("no parsable JSON block in the agent's reply")


# ------------------------------------------------------------------ SDK call

class AgentRun:
    def __init__(self, text: str, cost_usd: float, num_turns: int,
                 session_id: Optional[str] = None,
                 usage: Optional[dict[str, Any]] = None):
        self.text = text
        # NB: the SDK computes cost_usd locally from a bundled price table at
        # API list rates. On a Claude subscription nothing is billed per token,
        # so this is a relative measure of work, never money.
        self.cost_usd = cost_usd
        self.num_turns = num_turns
        self.session_id = session_id
        self.usage = usage or {}

    @property
    def tokens(self) -> dict[str, int]:
        u = self.usage
        return {"in": int(u.get("input_tokens", 0) or 0),
                "out": int(u.get("output_tokens", 0) or 0),
                "cache_read": int(u.get("cache_read_input_tokens", 0) or 0),
                "cache_write": int(u.get("cache_creation_input_tokens", 0) or 0)}

    @property
    def json(self) -> dict[str, Any]:
        return extract_json(self.text)


async def _once(prompt: str, *, system_prompt: str, cwd: Path,
                allowed_tools: list[str], permission_mode: str,
                max_turns: int, model: Optional[str],
                can_use_tool=None, hooks=None,
                max_budget_usd: Optional[float] = None,
                on_event: Optional[Callable[[str], None]] = None) -> AgentRun:
    from claude_agent_sdk import (AssistantMessage, ClaudeAgentOptions,
                                  ResultMessage, TextBlock, ToolUseBlock, query)

    options = ClaudeAgentOptions(
        system_prompt=system_prompt,
        cwd=str(cwd),
        allowed_tools=allowed_tools,
        permission_mode=permission_mode,
        max_turns=max_turns,
        model=model,
        # under bypassPermissions the SDK auto-approves before can_use_tool is
        # consulted, so passing it there is dead weight and warns; the
        # PreToolUse hook is what actually gates.
        can_use_tool=None if permission_mode == "bypassPermissions" else can_use_tool,
        hooks=hooks,
        max_budget_usd=max_budget_usd,
        setting_sources=["project"],
    )

    chunks: list[str] = []
    cost, turns, usage = 0.0, 0, {}
    failure: str | None = None
    async for message in query(prompt=prompt, options=options):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock):
                    chunks.append(block.text)
                elif isinstance(block, ToolUseBlock) and on_event:
                    on_event(f"    · {block.name}")
        elif isinstance(message, ResultMessage):
            cost = message.total_cost_usd or 0.0
            turns = message.num_turns or 0
            usage = message.usage or {}
            if message.is_error:
                res = message.result
                text = res if isinstance(res, str) else json.dumps(res or {})
                failure = (f"{message.subtype or ''} "
                           f"{message.terminal_reason or ''} {text}").strip()
    # Raise only after the generator has closed. Throwing from inside the
    # async-for leaves the SDK's generator mid-flight and buries the real
    # error under "aclose(): asynchronous generator is already running".
    if failure is not None:
        c = classify(failure)
        if c.kind == "auth":
            raise AuthExpired(failure)
        if c.kind == "max_turns":
            raise MaxTurnsReached(failure, "\n".join(chunks), cost, turns, usage)
        if c.kind == "quota":
            raise QuotaExhausted(failure, c.reset_at)
        if c.kind == "transient":
            raise TransientError(failure)
        raise OrchestratorError(failure)
    return AgentRun("\n".join(chunks), cost, turns, usage=usage)


def run_agent(prompt: str, *, system_prompt: str, cwd: Path,
              allowed_tools: list[str], permission_mode: str = "bypassPermissions",
              max_turns: int = 60, model: Optional[str] = None,
              can_use_tool=None, hooks=None,
              max_budget_usd: Optional[float] = None,
              on_event: Optional[Callable[[str], None]] = None) -> AgentRun:
    """Synchronous wrapper with backoff. Quota errors are NOT retried --
    they propagate so the run loop can checkpoint and stop cleanly."""
    last: Exception | None = None
    for attempt, wait in enumerate([0, *BACKOFF]):
        if wait:
            if on_event:
                on_event(f"    transient failure, retrying in {wait}s "
                         f"({attempt}/{len(BACKOFF)})")
            time.sleep(wait)
        try:
            return asyncio.run(_once(
                prompt, system_prompt=system_prompt, cwd=cwd,
                allowed_tools=allowed_tools, permission_mode=permission_mode,
                max_turns=max_turns, model=model, can_use_tool=can_use_tool,
                hooks=hooks, max_budget_usd=max_budget_usd, on_event=on_event))
        except (QuotaExhausted, AuthExpired, MaxTurnsReached):
            raise
        except TransientError as e:
            last = e
            continue
        except Exception as e:                     # noqa: BLE001
            # ResultError/ProcessError carry the reason in their message; a
            # cause chain often holds the more specific one.
            text = " ".join(str(x) for x in (e, getattr(e, "__cause__", None))
                            if x is not None)
            c = classify(text)
            if c.kind == "max_turns":
                raise MaxTurnsReached(text) from e
            if c.kind == "auth":
                raise AuthExpired(text) from e
            if c.kind == "quota":
                raise QuotaExhausted(text, c.reset_at) from e
            if c.kind == "transient":
                last = e
                continue
            raise
    raise TransientError(f"gave up after {len(BACKOFF)} retries: {last}")


# ----------------------------------------------------------- tool allow-lists

READ_ONLY = ["Read", "Grep", "Glob"]
DESIGNER_TOOLS = READ_ONLY + ["Write", "Edit", "Bash"]
CODER_TOOLS = READ_ONLY + ["Write", "Edit", "Bash"]


def tools_for(agent: str) -> list[str]:
    return DESIGNER_TOOLS if agent == "DA" else CODER_TOOLS


def permission_for(agent: str, repo: Path):
    return guards.make_permission_hook(agent, repo)


def hooks_for(agent: str, repo: Path):
    return guards.make_pretool_hooks(agent, repo)
