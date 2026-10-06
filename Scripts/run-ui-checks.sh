#!/bin/bash
#
# run-ui-checks.sh — the four UI regression scripts every closeout task must
# pass, each preceded by a fresh Scripts/preflight.sh. Stops at the first
# failed pre-flight (a locked screen means no more UI work this run).
# Usage: Scripts/run-ui-checks.sh [script-name ...]   (default: all four)
set -uo pipefail
cd "$(dirname "$0")/.."
SCRIPTS=("$@")
[[ ${#SCRIPTS[@]} -eq 0 ]] && SCRIPTS=(check-routines-window check-conflict-apply-return check-inspector-inset check-block-click-selects)
LOGS="${KADENCE_LOG_DIR:-$(mktemp -d)}"; echo "logs: $LOGS"
rc=0
for s in "${SCRIPTS[@]}"; do
  Scripts/preflight.sh || { echo "STOPPED before $s: pre-flight failed"; exit 2; }
  if Scripts/"$s".sh > "$LOGS/$s.log" 2>&1; then
    echo "$s: PASS"
  else
    echo "$s: FAIL (exit $?) — last lines:"; tail -8 "$LOGS/$s.log"; rc=1
  fi
done
exit $rc
