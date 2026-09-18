#!/bin/bash
# Keep the orchestrator running across recoverable stops.
#
#   ./supervise.sh                 # start supervising (foreground)
#   nohup caffeinate -i ./supervise.sh >/dev/null 2>&1 &   # and overnight
#   touch state/STOP               # kill switch: stops after the current task
#
# Agents reach Claude through whatever ANTHROPIC_BASE_URL says. Pointed at the
# OmniRoute gateway they run against its pool of accounts and a usage limit
# rolls onto the next one (config.json: on_quota=rotate); pointed at Anthropic
# directly there is nothing to roll onto. Because that is inherited from the
# launching shell, a supervise.sh started from a bare Terminal would silently
# lose rotation — so source the gateway env here if it is not already set.
#
# It restarts only on stops that a restart can actually fix. Phase done,
# BLOCKED, budget ceiling and a dead login all need a human, so it stops and
# says so rather than spinning.

cd "$(dirname "$0")" || exit 1
PY=.venv/bin/python
LOG=state/supervisor.log
MAX_RESTARTS=${MAX_RESTARTS:-8}
BACKOFF_UNIT=${BACKOFF_UNIT:-60}   # seconds; restart N waits N*unit
POLL=${POLL:-60}                  # seconds between checks while a run is alive

say() { printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" | tee -a "$LOG"; }

mkdir -p state

# Gateway credentials live outside the repo and are never committed. Create
# this file (chmod 600) exporting ANTHROPIC_BASE_URL and ANTHROPIC_AUTH_TOKEN
# if you want to launch from a shell that does not already have them.
OMNIROUTE_ENV=${OMNIROUTE_ENV:-$HOME/.config/omniroute/env}
if [ -z "${ANTHROPIC_BASE_URL:-}" ] && [ -r "$OMNIROUTE_ENV" ]; then
    set -a; . "$OMNIROUTE_ENV"; set +a
fi
case "${ANTHROPIC_BASE_URL:-}" in
    "")               say "WARNING: no ANTHROPIC_BASE_URL — going direct to Anthropic, so a usage limit cannot roll onto another account. Create $OMNIROUTE_ENV or export it before launching." ;;
    *api.anthropic.com*) say "WARNING: ANTHROPIC_BASE_URL is Anthropic direct — no account pool to rotate onto." ;;
    *)                say "gateway: $ANTHROPIC_BASE_URL" ;;
esac
rm -f state/STOP
say "supervisor up (pid $$), max $MAX_RESTARTS restarts"

n=0
while :; do
    [ -f state/STOP ] && { say "STOP file present — standing down"; exit 0; }

    # Never start a second orchestrator alongside one that is already working.
    if pgrep -f "run\.py (run|resume)" >/dev/null; then
        sleep "$POLL"
        continue
    fi

    if [ -f state/checkpoints.sqlite ]; then CMD=resume; else CMD=run; fi
    say "starting: run.py $CMD"
    # No --on-quota here on purpose: config.json owns that policy (rotate).
    "$PY" run.py "$CMD" >> state/supervisor.out 2>&1
    code=$?

    case $code in
        0)  say "exit 0 — phase done. Nothing left to supervise."; exit 0 ;;
        10) say "exit 10 — BLOCKED, MA needs a decision from Parsa."; exit 10 ;;
        20) say "exit 20 — cycle/budget ceiling reached."; exit 20 ;;
        # run.py already rotated through the pool and then slept out its
        # max_quota_waits. Restarting here would only reset that counter and
        # sleep again, so this needs a human, not another loop.
        75) say "exit 75 — every account in the pool is limited and not recovering. Resume when capacity is back: python3 run.py resume"; exit 75 ;;
        30) say "exit 30 — claude CLI not logged in. Run: claude  (then /login)"; exit 30 ;;
        2)  say "exit 2 — another orchestrator holds the lock. Standing down."; exit 2 ;;
        *)
            n=$((n + 1))
            if [ "$n" -ge "$MAX_RESTARTS" ]; then
                say "exit $code — $n restarts without finishing, giving up."
                exit 1
            fi
            back=$((BACKOFF_UNIT * n))
            say "exit $code — restart $n/$MAX_RESTARTS in ${back}s"
            sleep "$back"
            ;;
    esac
done
