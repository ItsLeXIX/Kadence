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

# --- quota rotation -------------------------------------------------------
# Talking straight to Anthropic, a usage limit is terminal: there is nothing to
# roll over to, so QuotaExhausted propagates and the run stops or sleeps until
# the window resets. Behind a gateway (OmniRoute) the same error means only
# "this target is spent". The gateway keeps a pool of accounts/providers and
# picks a different healthy one per request, so simply *re-issuing* the call is
# what "move on to the next account" looks like from in here — we never name an
# account ourselves.
#
# The gateway already does cooldown-aware retries inside a single request and
# only surfaces an error once its own retry budget is gone, so these waits are
# deliberately longer than BACKOFF: they exist to let circuit breakers half-open
# and per-model lockouts lapse, not to hammer a pool that just said no.
#
# Zero keeps the original behaviour, so this is inert until run.py turns it on.
QUOTA_ROTATIONS = 0
QUOTA_BACKOFF = [30, 90, 180, 300]


def configure_quota_rotation(rotations: int,
                             backoff: Optional[list[int]] = None) -> None:
    """Set once at startup by run.py. Module-level because run_agent is called
    from five places in graph.py and threading a knob through all of them buys
    nothing — the orchestrator lock already guarantees one run per process."""
    global QUOTA_ROTATIONS, QUOTA_BACKOFF
    QUOTA_ROTATIONS = max(0, int(rotations))
    if backoff:
        QUOTA_BACKOFF = [int(b) for b in backoff]


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


def _typed(text: str, chunks: str = "", cost: float = 0.0, turns: int = 0,
           usage: Optional[dict[str, Any]] = None) -> Exception:
    """One place that turns an error string into the right exception."""
    c = classify(text)
    if c.kind == "auth":
        return AuthExpired(text)
    if c.kind == "max_turns":
        return MaxTurnsReached(text, chunks, cost, turns, usage or {})
    if c.kind == "quota":
        return QuotaExhausted(text, c.reset_at)
    if c.kind == "transient":
        return TransientError(text)
    return OrchestratorError(text)


async def _once(prompt: str, *, system_prompt: str, cwd: Path,
                allowed_tools: list[str], permission_mode: str,
                max_turns: int, model: Optional[str],
                fallback_model: Optional[str] = None,
                can_use_tool=None, hooks=None,
                max_budget_usd: Optional[float] = None,
                max_buffer_size: int = 32 * 1024 * 1024,
                on_event: Optional[Callable[[str], None]] = None) -> AgentRun:
    from claude_agent_sdk import (AssistantMessage, ClaudeAgentOptions,
                                  ResultMessage, TextBlock, ToolUseBlock, query)

    # The CLI writes the real reason for a hard exit to stderr, and
    # ProcessError arrives saying only "Check stderr output for details".
    # Collect it so a session limit is not indistinguishable from a crash.
    stderr_lines: list[str] = []

    options = ClaudeAgentOptions(
        system_prompt=system_prompt,
        stderr=stderr_lines.append,
        cwd=str(cwd),
        allowed_tools=allowed_tools,
        permission_mode=permission_mode,
        max_turns=max_turns,
        model=model,
        # if the primary model is rate-limited, drop a tier rather than die
        fallback_model=fallback_model,
        # under bypassPermissions the SDK auto-approves before can_use_tool is
        # consulted, so passing it there is dead weight and warns; the
        # PreToolUse hook is what actually gates.
        can_use_tool=None if permission_mode == "bypassPermissions" else can_use_tool,
        hooks=hooks,
        max_budget_usd=max_budget_usd,
        # The default is 1MB per JSON message. A diagnose task that cats a
        # build log or a big spec into one tool result blows straight past it
        # and the transport dies mid-run, which is not worth losing a task for.
        max_buffer_size=max_buffer_size,
        setting_sources=["project"],
    )

    chunks: list[str] = []
    cost, turns, usage = 0.0, 0, {}
    failure: str | None = None
    try:
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
    except Exception as e:                            # noqa: BLE001
        # A hard CLI exit raises instead of yielding an error result. The
        # reason lives on stderr and one level down the cause chain.
        raise _typed(" ".join(str(x) for x in
                              (e, getattr(e, "__cause__", None)) if x is not None)
                     + "\n" + "\n".join(stderr_lines[-40:]),
                     "\n".join(chunks), cost, turns, usage) from e

    # Raise only after the generator has closed. Throwing from inside the
    # async-for leaves the SDK's generator mid-flight and buries the real
    # error under "aclose(): asynchronous generator is already running".
    if failure is not None:
        raise _typed(failure + "\n" + "\n".join(stderr_lines[-40:]),
                     "\n".join(chunks), cost, turns, usage)
    return AgentRun("\n".join(chunks), cost, turns, usage=usage)


def _run_once_with_backoff(prompt: str, *, system_prompt: str, cwd: Path,
              allowed_tools: list[str], permission_mode: str = "bypassPermissions",
              max_turns: int = 60, model: Optional[str] = None,
              fallback_model: Optional[str] = None,
              can_use_tool=None, hooks=None,
              max_budget_usd: Optional[float] = None,
              max_buffer_size: int = 32 * 1024 * 1024,
              on_event: Optional[Callable[[str], None]] = None) -> AgentRun:
    """One agent call, with transient-error backoff. Quota errors are NOT
    retried here -- they propagate to run_agent, which decides whether there is
    another account to roll onto."""
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
                max_turns=max_turns, model=model,
                fallback_model=fallback_model, can_use_tool=can_use_tool,
                hooks=hooks, max_budget_usd=max_budget_usd,
                max_buffer_size=max_buffer_size, on_event=on_event))
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


def run_agent(prompt: str, **kw) -> AgentRun:
    """Synchronous entry point. Transient failures retry inside; a quota error
    rotates onto the gateway's next account if rotation is configured, and
    otherwise propagates so the run loop can checkpoint and stop cleanly."""
    on_event = kw.get("on_event")
    last: QuotaExhausted | None = None
    for rotation in range(QUOTA_ROTATIONS + 1):
        if rotation:
            wait = QUOTA_BACKOFF[min(rotation - 1, len(QUOTA_BACKOFF) - 1)]
            if on_event:
                on_event(f"    usage limit hit — rotating to the next account "
                         f"via the gateway in {wait}s "
                         f"({rotation}/{QUOTA_ROTATIONS})")
            time.sleep(wait)
        try:
            return _run_once_with_backoff(prompt, **kw)
        except QuotaExhausted as e:
            last = e
            continue
    if last is not None:
        # Every rotation came back limited: the pool is dry, not one account.
        raise last
    raise OrchestratorError("run_agent: unreachable")


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
