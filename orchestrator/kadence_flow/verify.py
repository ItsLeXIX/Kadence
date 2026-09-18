"""Deterministic verification. No LLM here on purpose: an agent's report that
something passes is a claim, CONTEXT.md says to verify it."""
from __future__ import annotations

import json
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, Iterable, Optional

from . import guards

SCHEME = "Kadence"
DEST = "platform=macOS"


def _run(cmd: list[str], repo: Path, timeout: int) -> tuple[bool, str]:
    try:
        r = subprocess.run(cmd, cwd=repo, capture_output=True, text=True,
                           timeout=timeout)
    except subprocess.TimeoutExpired:
        return False, f"timed out after {timeout}s: {' '.join(cmd[:3])}"
    except FileNotFoundError:
        return False, f"not found: {cmd[0]}"
    tail = (r.stdout + r.stderr).strip().splitlines()[-25:]
    return r.returncode == 0, "\n".join(tail)


def _check(name: str, ok: bool, detail: str = "") -> dict[str, Any]:
    return {"name": name, "ok": ok, "detail": detail[:2000]}


def _macos() -> bool:
    return sys.platform == "darwin" and shutil.which("xcodebuild") is not None


# --------------------------------------------------------------------- checks

def tokens_in_sync(repo: Path) -> dict[str, Any]:
    if not (repo / "Scripts/generate-tokens.swift").exists():
        return _check("tokens --check", True, "script absent, skipped")
    if not shutil.which("swift"):
        return _check("tokens --check", True, "swift absent, skipped")
    ok, out = _run(["swift", "Scripts/generate-tokens.swift", "--check"], repo, 300)
    return _check("tokens --check", ok, out)


def tokens_json_valid(repo: Path) -> dict[str, Any]:
    p = repo / "design/tokens.json"
    if not p.exists():
        return _check("tokens.json parses", False, "design/tokens.json missing")
    try:
        json.loads(p.read_text())
        return _check("tokens.json parses", True)
    except json.JSONDecodeError as e:
        return _check("tokens.json parses", False, str(e))


def accessibility(repo: Path) -> dict[str, Any]:
    """ADVISORY. This launches the app and asks whether it is vending windows,
    which a detached background process cannot ask reliably — it flaps between
    "no window" and "0 blocks" for reasons that have nothing to do with the
    code. Across P2-T12 and P2-T15 it failed four tasks that were correct and
    burned 57% of that period's budget on retries. It still runs and its output
    is still reported; it just no longer fails a task on its own."""
    s = repo / "Scripts/check-accessibility.sh"
    if not s.exists() or not _macos():
        return _check("check-accessibility.sh (advisory)", True,
                      "skipped (not macOS)")
    ok, out = _run(["bash", str(s)], repo, 600)
    return _check("check-accessibility.sh (advisory)", True,
                  ("PASS" if ok else "ADVISORY FAIL — not blocking: ") + out[:600])


def build(repo: Path) -> dict[str, Any]:
    if not _macos():
        return _check("xcodebuild build", True, "skipped (not macOS)")
    ok, out = _run(["xcodebuild", "-scheme", SCHEME, "-destination", DEST,
                    "build"], repo, 1800)
    return _check("xcodebuild build", ok, out)


def unit_tests(repo: Path) -> dict[str, Any]:
    """-only-testing:KadenceTests -- a plain `test` runs the empty UI template
    whose runner cannot start on this Mac (STATUS.md)."""
    if not _macos():
        return _check("KadenceTests", True, "skipped (not macOS)")
    ok, out = _run(["xcodebuild", "-scheme", SCHEME, "-destination", DEST,
                    "-only-testing:KadenceTests", "test"], repo, 2400)
    m = re.search(r"Executed (\d+) tests?, with (\d+) failures?", out)
    detail = m.group(0) if m else out
    return _check("KadenceTests", ok, detail)


def gap_closures(repo: Path, claimed: list[str]) -> dict[str, Any]:
    """CONTEXT.md: a gap is closed only when the resolution is written into the
    spec file AND GAPS.md records it closed with a section reference."""
    if not claimed:
        return _check("gap closures", True, "none claimed")
    gaps = (repo / "design/GAPS.md")
    if not gaps.exists():
        return _check("gap closures", False, "design/GAPS.md missing")
    text = gaps.read_text()
    bad = []
    for gid in claimed:
        block = ""
        m = re.search(rf"^(#+).*\b{re.escape(gid)}\b.*$", text, re.M)
        if m:
            rest = text[m.end():]
            nxt = re.search(rf"^#{{1,{len(m.group(1))}}} ", rest, re.M)
            block = m.group(0) + (rest[:nxt.start()] if nxt else rest)
        if not block:
            bad.append(f"{gid}: no entry in GAPS.md")
            continue
        if not re.search(r"\bclosed\b", block, re.I):
            bad.append(f"{gid}: entry is not marked closed")
            continue
        ref = re.search(r"(components|layouts|interactions|tokens)\.(md|json)\s*(§|#)?\s*[\d.]+",
                        block, re.I)
        if not ref:
            bad.append(f"{gid}: closed without a spec section reference")
    return _check("gap closures", not bad, "; ".join(bad))


def decisions_untouched(repo: Path, base_sha: str) -> dict[str, Any]:
    r = subprocess.run(["git", "diff", "--name-only", base_sha, "--", "DECISIONS.md"],
                       cwd=repo, capture_output=True, text=True)
    touched = bool(r.stdout.strip()) or "DECISIONS.md" in guards.changed_files(repo)
    return _check("DECISIONS.md untouched", not touched,
                  "" if not touched else
                  "an agent edited DECISIONS.md; only Parsa writes it")


# ------------------------------------------------------------------ entrypoint

def verify(repo: Path, agent: str, report: dict[str, Any], base_sha: str,
           *, skip_build: bool = False,
           pre_dirty: Optional[Iterable[str]] = None) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []

    # pre_dirty: files already modified before the agent started, i.e. not its
    # work. See guards.scope_violations.
    violations = guards.scope_violations(repo, agent, exempt=pre_dirty)
    checks.append(_check("write scope", not violations, "; ".join(violations)))
    checks.append(decisions_untouched(repo, base_sha))

    if agent == "DA":
        checks.append(tokens_json_valid(repo))
        swift = [f for f in guards.changed_files(repo) if f.endswith(".swift")]
        checks.append(_check("no Swift touched", not swift, ", ".join(swift)))
    else:
        checks.append(gap_closures(repo, report.get("gaps_closed") or []))
        if not skip_build:
            checks.append(tokens_in_sync(repo))
            b = build(repo)
            checks.append(b)
            if b["ok"]:
                checks.append(unit_tests(repo))
                checks.append(accessibility(repo))
            else:
                checks.append(_check("KadenceTests", False, "skipped, build failed"))

    ok = all(c["ok"] for c in checks)
    failed = [c["name"] for c in checks if not c["ok"]]
    return {
        "task_id": report.get("task_id", ""),
        "ok": ok,
        "checks": checks,
        "scope_violations": violations,
        "summary": "all checks passed" if ok else "FAILED: " + ", ".join(failed),
    }
