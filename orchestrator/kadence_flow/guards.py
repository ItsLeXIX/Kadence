"""Hard enforcement of CONTEXT.md's rules.

Prompts are advice; these are walls. Two layers:
  1. can_use_tool -> deny the write before it happens
  2. post-run git scope check -> revert anything that slipped through
"""
from __future__ import annotations

import fnmatch
import re
import subprocess
from pathlib import Path
from typing import Any, Iterable

# ---------------------------------------------------------------- scope table

WRITE_SCOPE: dict[str, list[str]] = {
    # design agent: the spec, and nothing else
    "DA": ["design/**"],
    # coding agent: the Swift target, tests, screenshots + the gap channel
    "CA": ["Kadence/**", "KadenceTests/**", "KadenceUITests/**",
           "screenshots/**", "Scripts/**", "design/GAPS.md",
           "STATUS.md", "DEVIATIONS.md"],
}

# Never writable by any agent, whatever the scope says.
FORBIDDEN: list[str] = [
    "DECISIONS.md",                       # Parsa's file, CONTEXT.md
    "Kadence/DesignSystem/Tokens.swift",  # generated, never hand-edited
    ".git/**",
    "orchestrator/**",                    # the agents do not edit the harness
]

# CA may only *append* to GAPS.md, never rewrite it.
APPEND_ONLY: dict[str, list[str]] = {"CA": ["design/GAPS.md"]}

WRITE_TOOLS = {"Write", "Edit", "MultiEdit", "NotebookEdit"}

# git is the orchestrator's job, not the agent's
BASH_DENY = [
    r"\bgit\s+(commit|push|reset|rebase|checkout|switch|clean|stash|cherry-pick|revert)\b",
    r"\brm\s+-rf\s+/",
    r"\bsudo\b",
    r">\s*/dev/sd",
]


def _match(path: str, patterns: Iterable[str]) -> bool:
    p = path.lstrip("./")
    for pat in patterns:
        if fnmatch.fnmatch(p, pat) or fnmatch.fnmatch(p, pat.replace("/**", "")):
            return True
        if pat.endswith("/**") and p.startswith(pat[:-3] + "/"):
            return True
    return False


def relpath(repo: Path, raw: str) -> str:
    try:
        return str(Path(raw).resolve().relative_to(repo.resolve()))
    except (ValueError, OSError):
        return raw


def check_write(agent: str, path: str) -> tuple[bool, str]:
    if _match(path, FORBIDDEN):
        return False, f"{path} is off-limits to every agent (CONTEXT.md)."
    allowed = WRITE_SCOPE.get(agent, [])
    if not _match(path, allowed):
        return False, (f"{agent} may only write to {', '.join(allowed)}. "
                       f"{path} is outside that. If you need a change there, "
                       f"record it as a gap instead.")
    return True, ""


def make_permission_hook(agent: str, repo: Path):
    """Returns a can_use_tool callback for ClaudeAgentOptions."""
    try:
        from claude_agent_sdk.types import (PermissionResultAllow,
                                            PermissionResultDeny)
    except ImportError:          # dry runs / stubbed agents
        return None

    async def can_use_tool(tool_name: str, input_data: dict[str, Any], context):
        if tool_name in WRITE_TOOLS:
            raw = input_data.get("file_path") or input_data.get("notebook_path") or ""
            rel = relpath(repo, raw)
            ok, why = check_write(agent, rel)
            if not ok:
                return PermissionResultDeny(message=why)
            if tool_name == "Write" and _match(rel, APPEND_ONLY.get(agent, [])):
                return PermissionResultDeny(
                    message=f"{rel} is append-only for {agent}. Use Edit to add an "
                            f"entry at the end; do not rewrite the file.")
        if tool_name == "Bash":
            cmd = input_data.get("command", "")
            for pat in BASH_DENY:
                if re.search(pat, cmd):
                    return PermissionResultDeny(
                        message="git history and destructive commands are the "
                                "orchestrator's job. Just leave your changes in "
                                "the working tree.")
        return PermissionResultAllow(updated_input=input_data)

    return can_use_tool


# ------------------------------------------------------------------- git side

def _git(repo: Path, *args: str, timeout: int = 60) -> subprocess.CompletedProcess:
    return subprocess.run(["git", *args], cwd=repo, capture_output=True,
                          text=True, timeout=timeout)


def head(repo: Path) -> str:
    return _git(repo, "rev-parse", "HEAD").stdout.strip()


def changed_files(repo: Path) -> list[str]:
    out = _git(repo, "status", "--porcelain", "-uall").stdout.splitlines()
    files: list[str] = []
    for line in out:
        if not line.strip():
            continue
        path = line[3:].strip()
        if " -> " in path:            # rename
            path = path.split(" -> ", 1)[1]
        files.append(path.strip('"'))
    return files


def is_dirty(repo: Path) -> bool:
    return bool(changed_files(repo))


def scope_violations(repo: Path, agent: str) -> list[str]:
    bad = []
    for f in changed_files(repo):
        ok, why = check_write(agent, f)
        if not ok:
            bad.append(f"{f}: {why}")
    return bad


def revert_paths(repo: Path, paths: list[str]) -> None:
    """Undo out-of-scope changes so a bad turn cannot poison the tree."""
    for p in paths:
        f = p.split(":")[0].strip()
        target = repo / f
        r = _git(repo, "ls-files", "--error-unmatch", f)
        if r.returncode == 0:
            _git(repo, "checkout", "--", f)     # tracked -> restore
        elif target.is_file() or target.is_symlink():
            target.unlink()                     # untracked -> remove
        elif target.is_dir():
            # -uall means git lists files, not dirs; never rmtree blindly
            continue


def ensure_branch(repo: Path, branch: str) -> None:
    cur = _git(repo, "rev-parse", "--abbrev-ref", "HEAD").stdout.strip()
    if cur == branch:
        return
    if _git(repo, "rev-parse", "--verify", branch).returncode == 0:
        _git(repo, "checkout", branch)
    else:
        _git(repo, "checkout", "-b", branch)


def commit_all(repo: Path, message: str) -> str | None:
    """Snapshot the tree. Never pushes. Returns the sha, or None if nothing to do."""
    if not is_dirty(repo):
        return None
    _git(repo, "add", "-A")
    r = _git(repo, "commit", "-m", message, "--no-verify")
    if r.returncode != 0:
        return None
    return head(repo)
