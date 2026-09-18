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
python3 tests/test_failsafes.py     # 64 checks, no tokens spent
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
`75` every account limited and not recovering, resumable.

A blocked run (`10`) stays blocked until you answer MA. Write the answer to
`state/UNBLOCK` — the next resume consumes it once, folds it into the goal MA
re-reads each cycle, and carries on.

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

### Rolling onto the next account (`on_quota: "rotate"`, the default here)

Agents reach Claude through whatever `ANTHROPIC_BASE_URL` says. Pointed at the
OmniRoute gateway on `localhost:20128`, one usage limit is not the end of the
sitting: the gateway holds a pool of accounts and providers and picks a healthy
one per request, so *re-issuing the call* is what moving to the next account
looks like from in here. The orchestrator never names an account itself.

    usage limit  →  re-issue up to quota_rotations× (30s, 90s, 180s, 300s)
                 →  still limited every time? the pool is dry, not one account
                 →  sleep until the earliest reset (or quota_blind_wait_s when
                    no reset time is quoted) and carry on
                 →  after max_quota_waits sleeps with no recovery, exit 75

The waits are longer than the transient `BACKOFF` on purpose. The gateway
already retries inside a single request and only errors once its own retry
budget is gone, so these exist to let its circuit breakers half-open and its
per-model lockouts lapse — not to hammer a pool that just said no.

Rotation is skipped automatically, with a warning in the log, when the run is
pointed straight at Anthropic: there is nothing to roll onto, so `rotate`
degrades to `wait`. Because the base URL is inherited from the launching shell,
`supervise.sh` sources `~/.config/omniroute/env` (override with `$OMNIROUTE_ENV`)
when it is not already set, and says which gateway it got. That file holds the
credentials, lives outside the repo, and is never committed.

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
behaviour (`on_quota`, `quota_rotations`, `quota_backoff`, `quota_blind_wait_s`,
`max_quota_waits`, `gateway_url`). `kadence_flow/prompts/{manager,designer,coder}.md` — the three system
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
tests/test_failsafes.py    64 checks, temp repo, stubbed agents
state/                     checkpoints + logs (gitignored)
```

## Known limits

- One task at a time. DA and CA never run in parallel — that is deliberate
  (`design/` freeze), not a missing feature.
- MA's context is a digest: recent ledger, GAPS tail, STATUS tail, git log. It can
  read more with Read/Grep, but it does not see full chat history from earlier runs.
- Screenshot capture is a CA task and review is a DA task, both dispatched by MA;
  nothing automates the screen capture itself yet.
