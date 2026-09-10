# Kadence orchestrator

Replaces the copy-paste loop (you → MA → you → DA/CA → you → MA) with a
LangGraph state machine that runs the same loop by itself.

```
        ┌──────────────┐
        │  MA manager  │◄─────────────┐
        └──────┬───────┘              │
          next action?                │
        ┌──────┴───────┐              │
        ▼              ▼              │
   ┌────────┐     ┌────────┐          │
   │   DA   │     │   CA   │          │
   │ design/│     │Kadence/│          │
   └────┬───┘     └───┬────┘          │
        └──────┬──────┘               │
               ▼                      │
        verification  ────────────────┘
   (xcodebuild · tests · tokens --check
    · write scope · gap rule · git commit)
```

MA never touches files; CA keeps `STATUS.md` and `DEVIATIONS.md` current.
DA and CA never talk to each other — they talk through
`design/GAPS.md`, exactly as `CONTEXT.md` says. Verification is **not** an agent:
it is `subprocess` running your real build, so no agent can talk its way to green.

## Setup (on the Mac, once)

```bash
cd ~/codes/Kadence/orchestrator
python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt
python3 tests/test_failsafes.py     # 30 checks, no tokens spent
```

Needs the `claude` CLI logged in (the SDK drives it, so this runs on your
subscription, not an API key).

## Running

```bash
python3 run.py run --phase 3 --goal "Moodle + timetable import into SwiftData"
python3 run.py resume        # after a stop, for any reason
python3 run.py status        # where did it get to
python3 run.py dry           # stub agents: proves the wiring, costs nothing
python3 run.py reset         # drop checkpoints (your branch is untouched)
```

Exit codes: `0` phase done · `10` blocked, needs you · `20` cycle/cost ceiling ·
`75` token limit, resumable.

Everything lands on `auto/phase-<n>`, one commit per task, never on `main`.
Review the branch when it stops; merge what you like.

## When your tokens run out

This is designed for, not patched around:

1. Every node boundary is checkpointed to `state/checkpoints.sqlite`.
2. A usage/rate-limit error is recognised (not retried — retrying a quota error
   just burns the next window), and it stops the run cleanly.
3. Whatever the agent had already written is committed as `wip: <task-id>` on the
   work branch. Nothing is ever left only in an unsaved buffer.
4. `state/RESUME.md` records where it stopped and when the limit resets.
5. `python3 run.py resume` re-enters the graph at the interrupted node. The task is
   re-dispatched with a note that its own half-finished work is already in the tree,
   so the agent continues rather than starting over.

Set `"on_quota": "wait"` in `config.json` (or `--on-quota wait`) and it sleeps until
the reset time and carries on unattended instead of exiting.

Transient failures (5xx, overloaded, dropped connections) are retried three times
with 10s/30s/90s backoff — those are separate from quota and never confused with it.

## The walls

Prompts are advice; these are enforced in code and cannot be talked around:

| Rule (`CONTEXT.md`) | Enforcement |
|---|---|
| DA writes only `design/` | `can_use_tool` denies the write; `git status` re-checks afterwards |
| CA writes only `Kadence/`, `KadenceTests/`, `Scripts/`, `screenshots/`, `STATUS.md`, `DEVIATIONS.md` + appends to `GAPS.md` | same |
| `DECISIONS.md` is yours alone | forbidden to both agents, and checked after every task |
| `Tokens.swift` is generated, never hand-edited | forbidden to write + `generate-tokens --check` |
| A gap is closed only with a spec edit **and** a closed `GAPS.md` entry with a §ref | `verify.gap_closures` |
| `design/` frozen while CA runs | the graph is sequential; DA and CA never run at once |
| Agents don't own git | `git commit/push/reset/checkout` denied in Bash; the orchestrator commits |
| Tests are `-only-testing:KadenceTests` | hard-coded; the empty UITest target is never run |

Anything out of scope is reverted before the commit, and the task is marked failed so
MA has to deal with it.

## Stopping conditions

- `PHASE_DONE` — MA says so *and* verification was green.
- `BLOCKED` — MA needs a `DECISIONS.md` ruling from you, or two specs contradict.
- three failed verifications in a row on the same task.
- `max_cycles` (default 12) or `max_cost_usd` (default: no ceiling).

### A note on the cost figures

The run prints token usage and, beside it, the SDK's `total_cost_usd`. That number
is a **client-side estimate**: the SDK prices tokens locally from a bundled table at
API list rates. On a Claude subscription nothing is billed per token, so treat it as
a relative measure of how much work a cycle did, never as money. The real limit is
your plan's usage cap — when you hit it the run stops with exit 75 and resumes later.
`max_cycles` is the ceiling that actually bounds a sitting.

## Tuning

`config.json` — models per agent, turn limits, cycle and cost ceilings, quota
behaviour. `kadence_flow/prompts/{manager,designer,coder}.md` — the three system
prompts.

**These prompts were reconstructed from `CONTEXT.md`, the two briefs and the
conventions visible in `DECISIONS.md` / `DEVIATIONS.md` / `GAPS.md` — not from your
actual Phase 1–2 chats.** Read them before the first real run; anything your real
agents do that these don't say, add it there.

## Layout

```
run.py                     CLI, quota rescue, resume
config.json                everything tunable
kadence_flow/
  graph.py                 the four nodes and the routing
  agents.py                Claude Agent SDK calls, backoff, JSON contract
  guards.py                write scope, forbidden paths, git
  verify.py                build, tests, tokens, gap rule — no LLM
  errors.py                quota vs transient vs fatal
  persist.py               checkpoints, run log, RESUME.md
  prompts/                 MA / DA / CA system prompts
tests/test_failsafes.py    30 checks, temp repo, stubbed agents
state/                     checkpoints + logs (gitignored)
```

## Known limits

- One task at a time. DA and CA never run in parallel — that is deliberate
  (`design/` freeze), not a missing feature.
- MA's context is a digest: recent ledger, GAPS tail, STATUS tail, git log. It can
  read more with Read/Grep, but it does not see full chat history from earlier runs.
- Screenshot capture is a CA task and review is a DA task, both dispatched by MA;
  nothing automates the screen capture itself yet.
