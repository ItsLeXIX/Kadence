"""MA -> (DA|CA) -> verify -> MA, as a LangGraph state machine."""
from __future__ import annotations

import json
import subprocess
import textwrap
from typing import Any

from langgraph.graph import END, START, StateGraph

from . import agents, guards, persist, verify as verifier
from .config import Config
from .errors import ContractError, QuotaExhausted
from .state import OrchestratorState

MAX_LEDGER_IN_PROMPT = 6


def _ret(state: dict, upd: dict) -> dict:
    """Return a node update, mirroring the merged state to disk first so a
    crash mid-node still leaves a legible record of where we were."""
    persist.mirror({**state, **upd})
    return upd


# ------------------------------------------------------------- context for MA

def _tail(path, n: int = 40) -> str:
    try:
        return "\n".join(path.read_text().splitlines()[-n:])
    except OSError:
        return "(missing)"


def _ledger_digest(state: OrchestratorState) -> str:
    entries = (state.get("ledger") or [])[-MAX_LEDGER_IN_PROMPT:]
    if not entries:
        return "(nothing yet — this is the first cycle of the run)"
    out = []
    for e in entries:
        t, r, v = e.get("task", {}), e.get("report", {}), e.get("verification", {})
        out.append(textwrap.dedent(f"""
        - cycle {e.get('cycle')} · `{t.get('task_id')}` · {t.get('agent')} · {t.get('title')}
          agent said: {(r.get('summary') or '')[:400]}
          agent claimed done: {r.get('done')}
          gaps opened: {r.get('gaps_opened') or []} · closed: {r.get('gaps_closed') or []}
          VERIFICATION: {'PASS' if v.get('ok') else 'FAIL'} — {v.get('summary')}
          failing detail: {_failing_detail(v)}
        """).strip())
    return "\n\n".join(out)


def _failing_detail(v: dict[str, Any]) -> str:
    bad = [c for c in (v.get("checks") or []) if not c.get("ok")]
    return " | ".join(f"{c['name']}: {(c.get('detail') or '')[:300]}" for c in bad) or "—"


def _git_context(repo) -> str:
    def g(*a):
        return subprocess.run(["git", *a], cwd=repo, capture_output=True,
                              text=True).stdout.strip()
    return (f"branch: {g('rev-parse', '--abbrev-ref', 'HEAD')}\n"
            f"recent commits:\n{g('log', '--oneline', '-8')}\n"
            f"uncommitted: {guards.changed_files(repo) or 'clean'}")


def _manager_prompt(state: OrchestratorState, cfg: Config) -> str:
    repo = cfg.repo
    return textwrap.dedent(f"""
    # Cycle {state.get('cycle', 0) + 1} of at most {cfg.max_cycles}

    ## Phase goal (set by Parsa)
    Phase {cfg.phase}: {cfg.goal or '(see STATUS.md — continue the current phase)'}

    ## Repository state
    {_git_context(repo)}

    ## Recent ledger — machine verification included
    {_ledger_digest(state)}

    ## Tail of design/GAPS.md
    ```
    {_tail(repo / 'design/GAPS.md', 45)}
    ```

    ## Tail of STATUS.md
    ```
    {_tail(repo / 'STATUS.md', 30)}
    ```

    Read whatever else you need with Read/Grep/Glob, then decide the single next
    action and end with the JSON block.
    """).strip()


# -------------------------------------------------------------------- nodes

def build(cfg: Config):
    repo = cfg.repo

    # ---------------------------------------------------------------- manager
    def manager(state: OrchestratorState) -> dict[str, Any]:
        cycle = state.get("cycle", 0) + 1
        persist.log(f"\n── cycle {cycle} · MA deciding ──")
        prompt = _manager_prompt(state, cfg)
        try:
            run = agents.run_agent(
                prompt, system_prompt=cfg.prompt("manager"), cwd=repo,
                allowed_tools=agents.READ_ONLY, permission_mode="dontAsk",
                max_turns=cfg.manager_max_turns, model=cfg.manager_model,
                on_event=lambda s: persist.log(s, echo=True))
            data = run.json
        except ContractError:
            persist.log("  MA returned no JSON — asking once more, strictly")
            run = agents.run_agent(
                prompt + "\n\nYour previous reply had no valid JSON block. "
                         "Reply with the JSON block only.",
                system_prompt=cfg.prompt("manager"), cwd=repo,
                allowed_tools=agents.READ_ONLY, permission_mode="dontAsk",
                max_turns=4, model=cfg.manager_model)
            try:
                data = run.json
            except ContractError as e:
                return _ret(state, {
                    "cycle": cycle, "decision": "BLOCKED", "status": "blocked",
                    "stop_reason": f"MA broke its output contract: {e}",
                    "cost_usd": state.get("cost_usd", 0.0) + run.cost_usd})

        decision = data.get("next", "BLOCKED")
        task = {
            "task_id": data.get("task_id") or f"P{cfg.phase}-C{cycle}",
            "agent": decision if decision in ("DA", "CA") else "",
            "title": data.get("title", ""),
            "instruction": data.get("instruction", ""),
            "acceptance": data.get("acceptance") or [],
            "files_expected": data.get("files_expected") or [],
        }
        persist.log(f"  MA → {decision}: {task['title'] or data.get('blocker', '')}")
        persist.log(f"  why: {(data.get('reasoning') or '')[:300]}")
        persist.mirror({**state, "cycle": cycle, "task": task, "decision": decision})

        upd: dict[str, Any] = {
            "cycle": cycle, "decision": decision, "task": task,
            "cost_usd": state.get("cost_usd", 0.0) + run.cost_usd,
        }
        if decision == "PHASE_DONE":
            upd["status"] = "phase_done"
            upd["stop_reason"] = data.get("reasoning", "phase complete")
        elif decision == "BLOCKED":
            upd["status"] = "blocked"
            upd["stop_reason"] = data.get("blocker") or data.get("reasoning") or "blocked"
        return _ret(state, upd)

    # ----------------------------------------------------------------- worker
    def _worker(state: OrchestratorState, agent: str) -> dict[str, Any]:
        task = state.get("task", {})
        guards.ensure_branch(repo, cfg.work_branch)
        base = guards.head(repo)
        persist.log(f"  {agent} working: {task.get('task_id')} — {task.get('title')}")

        resumed = _resumed_note(repo, task.get("task_id", ""))
        prompt = textwrap.dedent(f"""
        # Task {task.get('task_id')} — {task.get('title')}

        {task.get('instruction')}

        ## Acceptance — you are done when all of these are true
        {chr(10).join('- ' + a for a in task.get('acceptance', [])) or '- (none given)'}

        ## Files the manager expects you to touch
        {', '.join(task.get('files_expected', [])) or '(unspecified)'}
        {resumed}
        Work in the repository at {repo}. End with your JSON report block.
        """).strip()

        run = agents.run_agent(
            prompt, system_prompt=cfg.prompt("designer" if agent == "DA" else "coder"),
            cwd=repo, allowed_tools=agents.tools_for(agent),
            permission_mode="bypassPermissions",
            max_turns=cfg.worker_max_turns,
            model=cfg.designer_model if agent == "DA" else cfg.coder_model,
            can_use_tool=agents.permission_for(agent, repo),
            max_budget_usd=cfg.worker_budget_usd or None,
            on_event=lambda s: persist.log(s, echo=True))

        try:
            report = run.json
        except ContractError:
            report = {"summary": "agent gave no JSON report", "done": False}
        report.setdefault("task_id", task.get("task_id", ""))
        report["agent"] = agent
        report["cost_usd"] = run.cost_usd
        report["num_turns"] = run.num_turns
        report["raw_tail"] = run.text[-1500:]
        report["_base_sha"] = base
        persist.log(f"  {agent} done={report.get('done')} "
                    f"turns={run.num_turns} cost=${run.cost_usd:.2f}")
        return _ret(state, {"report": report,
                            "cost_usd": state.get("cost_usd", 0.0) + run.cost_usd})

    def designer(state: OrchestratorState) -> dict[str, Any]:
        return _worker(state, "DA")

    def coder(state: OrchestratorState) -> dict[str, Any]:
        return _worker(state, "CA")

    # ----------------------------------------------------------------- verify
    def verify_node(state: OrchestratorState) -> dict[str, Any]:
        task = state.get("task", {})
        report = state.get("report", {})
        agent = task.get("agent") or report.get("agent") or "CA"
        persist.log("  verifying (build, tests, scope, gap rule)…")

        v = verifier.verify(repo, agent, report, report.get("_base_sha", "HEAD"),
                            skip_build=cfg.skip_build)

        if v["scope_violations"]:
            persist.log(f"  ! reverting out-of-scope writes: {v['scope_violations']}")
            guards.revert_paths(repo, v["scope_violations"])

        status = "ok" if v["ok"] else "FAILED"
        sha = guards.commit_all(
            repo, f"{agent} {task.get('task_id')}: {task.get('title')} [{status}]"
                  f"\n\n{(report.get('summary') or '')[:800]}")
        persist.log(f"  verification: {v['summary']}" + (f" · {sha[:8]}" if sha else ""))

        fails = 0 if v["ok"] else state.get("consecutive_failures", 0) + 1
        entry = {"cycle": state.get("cycle", 0), "task": task,
                 "report": {k: x for k, x in report.items() if k != "raw_tail"},
                 "verification": v, "commit": sha}
        upd: dict[str, Any] = {
            "verification": v,
            "consecutive_failures": fails,
            "ledger": (state.get("ledger") or []) + [entry],
        }
        cost = state.get("cost_usd", 0.0)
        if fails >= cfg.max_consecutive_failures:
            upd["status"] = "blocked"
            upd["stop_reason"] = (
                f"{cfg.max_consecutive_failures} verifications failed in a row on "
                f"{task.get('task_id')} — this needs a human")
        elif state.get("cycle", 0) >= cfg.max_cycles:
            upd["status"] = "budget_stop"
            upd["stop_reason"] = f"reached max_cycles ({cfg.max_cycles})"
        elif cfg.max_cost_usd and cost >= cfg.max_cost_usd:
            upd["status"] = "budget_stop"
            upd["stop_reason"] = f"reached max_cost_usd (${cost:.2f})"
        if "stop_reason" in upd:
            persist.log(f"  ■ stopping: {upd['stop_reason']}")
        return _ret(state, upd)

    # ---------------------------------------------------------------- routing
    def after_manager(state: OrchestratorState) -> str:
        d = state.get("decision")
        return {"DA": "designer", "CA": "coder"}.get(d, END)

    def after_verify(state: OrchestratorState) -> str:
        return END if state.get("status") in (
            "blocked", "budget_stop", "phase_done") else "manager"

    g = StateGraph(OrchestratorState)
    g.add_node("manager", manager)
    g.add_node("designer", designer)
    g.add_node("coder", coder)
    g.add_node("verify", verify_node)
    g.add_edge(START, "manager")
    g.add_conditional_edges("manager", after_manager,
                            {"designer": "designer", "coder": "coder", END: END})
    g.add_edge("designer", "verify")
    g.add_edge("coder", "verify")
    g.add_conditional_edges("verify", after_verify, {"manager": "manager", END: END})
    return g


def _resumed_note(repo, task_id: str) -> str:
    """If a previous run died mid-task, its partial work is a wip commit."""
    if not task_id:
        return ""
    out = subprocess.run(["git", "log", "--oneline", "-30"], cwd=repo,
                         capture_output=True, text=True).stdout
    if f"wip: {task_id}" in out:
        return ("\n## Note\nA previous run of this exact task was cut short "
                "(token limit). Its partial work is already in the working tree "
                "— read what is there before writing, and continue rather than "
                "starting over.\n")
    return ""
