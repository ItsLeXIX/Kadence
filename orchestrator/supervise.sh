#!/bin/bash
# Keep the orchestrator running across recoverable stops.
#
#   ./supervise.sh                 # start supervising (foreground)
#   nohup caffeinate -i ./supervise.sh >/dev/null 2>&1 &   # and overnight
#   touch state/STOP               # kill switch: stops after the current task
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
    "$PY" run.py "$CMD" --on-quota wait >> state/supervisor.out 2>&1
    code=$?

    case $code in
        0)  say "exit 0 — phase done. Nothing left to supervise."; exit 0 ;;
        10) say "exit 10 — BLOCKED, MA needs a decision from Parsa."; exit 10 ;;
        20) say "exit 20 — cycle/budget ceiling reached."; exit 20 ;;
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
