"""Failure classification. The whole point: tell 'you ran out of tokens'
apart from 'the network hiccuped' apart from 'the code is wrong'."""
from __future__ import annotations

import re
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from typing import Optional


class OrchestratorError(Exception):
    pass


class QuotaExhausted(OrchestratorError):
    """Subscription / rate limit hit. Recoverable, but only by waiting."""

    def __init__(self, message: str, reset_at: Optional[datetime] = None):
        super().__init__(message)
        self.reset_at = reset_at


class AuthExpired(OrchestratorError):
    """The claude CLI is not logged in. Only a human can fix it."""


class MaxTurnsReached(OrchestratorError):
    """The agent used its whole turn budget without finishing. Not a crash:
    whatever it did is still on disk, and the caller decides what to salvage."""

    def __init__(self, message: str, text: str = "", cost_usd: float = 0.0,
                 num_turns: int = 0, usage: Optional[dict] = None):
        super().__init__(message)
        self.text = text
        self.cost_usd = cost_usd
        self.num_turns = num_turns
        self.usage = usage or {}


class TransientError(OrchestratorError):
    """Network / 5xx. Retry with backoff."""


class ContractError(OrchestratorError):
    """An agent did not return the JSON block we require."""


_QUOTA_PATTERNS = [
    r"usage limit",
    r"session limit",
    r"limit reached",
    r"hit your .{0,20}limit",
    r"claude usage limit",
    r"rate[_ ]?limit",
    r"\b429\b",
    r"quota",
    r"credit balance is too low",
    r"insufficient_quota",
    r"exceeded your current quota",
    r"out of (?:tokens|credits)",
    r"weekly limit",
    r"opus limit",
]

_AUTH_PATTERNS = [
    r"oauth session expired",
    r"failed to authenticate",
    r"\bunauthorized\b",
    r"\b401\b",
    r"invalid[_ ]api[_ ]key",
    r"authentication[_ ]error",
    r"please run .{0,12}login",
    r"not logged in",
]

_MAX_TURNS_PATTERNS = [r"error_max_turns", r"\bmax[_ ]turns\b"]

_TRANSIENT_PATTERNS = [
    r"\b50[0234]\b",
    r"overloaded",
    r"connection reset",
    r"connection aborted",
    r"broken pipe",
    r"temporarily unavailable",
    r"timed? ?out",
    r"eof occurred",
]

# "resets at 2026-09-10T18:00:00Z" / "resets 6pm" / epoch seconds
_RESET_ISO = re.compile(r"resets?\s+(?:at\s+)?(\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}(?::\d{2})?Z?)", re.I)
_RESET_EPOCH = re.compile(r"resets?[^0-9]{0,12}(\d{10})\b", re.I)
# the CLI's own wording: "resets 1:20pm (Europe/Vienna)"
_RESET_CLOCK = re.compile(
    r"resets?\s+(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*([ap])\.?m\.?"
    r"(?:\s*\(([A-Za-z_]+/[A-Za-z_]+)\))?", re.I)


def parse_reset_at(text: str) -> Optional[datetime]:
    m = _RESET_ISO.search(text)
    if m:
        raw = m.group(1).replace(" ", "T").rstrip("Z")
        try:
            return datetime.fromisoformat(raw).replace(tzinfo=timezone.utc)
        except ValueError:
            pass
    m = _RESET_EPOCH.search(text)
    if m:
        try:
            return datetime.fromtimestamp(int(m.group(1)), tz=timezone.utc)
        except (ValueError, OSError):
            pass
    m = _RESET_CLOCK.search(text)
    if m:
        hour = int(m.group(1)) % 12
        if m.group(3).lower() == "p":
            hour += 12
        minute = int(m.group(2) or 0)
        tz = None
        if m.group(4):
            try:
                from zoneinfo import ZoneInfo
                tz = ZoneInfo(m.group(4))
            except Exception:            # noqa: BLE001 — unknown zone name
                tz = None
        now = datetime.now(tz) if tz else datetime.now().astimezone()
        reset = now.replace(hour=hour, minute=minute, second=0, microsecond=0)
        if reset <= now:                 # already past today -> tomorrow
            reset += timedelta(days=1)
        return reset.astimezone(timezone.utc)
    return None


@dataclass
class Classified:
    kind: str  # "quota" | "transient" | "fatal"
    text: str
    reset_at: Optional[datetime] = None


def classify(text: str) -> Classified:
    low = (text or "").lower()
    for p in _AUTH_PATTERNS:
        if re.search(p, low):
            return Classified("auth", text)
    for p in _MAX_TURNS_PATTERNS:
        if re.search(p, low):
            return Classified("max_turns", text)
    for p in _QUOTA_PATTERNS:
        if re.search(p, low):
            return Classified("quota", text, parse_reset_at(text))
    for p in _TRANSIENT_PATTERNS:
        if re.search(p, low):
            return Classified("transient", text)
    return Classified("fatal", text)


def raise_for(text: str) -> None:
    """Turn an error string from the SDK into the right exception type."""
    c = classify(text)
    if c.kind == "auth":
        raise AuthExpired(c.text)
    if c.kind == "max_turns":
        raise MaxTurnsReached(c.text)
    if c.kind == "quota":
        raise QuotaExhausted(c.text, c.reset_at)
    if c.kind == "transient":
        raise TransientError(c.text)
    raise OrchestratorError(c.text)
