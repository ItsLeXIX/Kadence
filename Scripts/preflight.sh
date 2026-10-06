#!/bin/bash
#
# preflight.sh — the UI-script pre-flight, run fresh before EVERY UI script or
# live capture (Phase 2 closeout). Exits 1, sending no input anywhere, if the
# screen is locked or any app has a window in full screen. Same two checks as
# capture-p2f25.sh's own pre-flight, factored out so the check-*.sh scripts
# that don't carry one get the same gate (Scripts/run-ui-checks.sh).
set -uo pipefail
LOCK_STATE=$(swift -e '
  import CoreGraphics
  import Foundation
  if let d = CGSessionCopyCurrentDictionary() as NSDictionary? { print((d["CGSSessionScreenIsLocked"] as? Int) ?? 0) } else { print(0) }
' 2>/dev/null)
[[ "$LOCK_STATE" == "1" ]] && { echo "PREFLIGHT FAIL: screen is locked."; exit 1; }
FULL=$(osascript -e 'tell application "System Events"
  set out to ""
  repeat with p in (every process whose background only is false)
    try
      repeat with w in windows of p
        try
          if (value of attribute "AXFullScreen" of w) is true then set out to out & (name of p) & " "
        end try
      end repeat
    end try
  end repeat
  return out
end tell' 2>/dev/null)
[[ -n "${FULL// /}" ]] && { echo "PREFLIGHT FAIL: an app is in full screen ($FULL)."; exit 1; }
echo "preflight: unlocked, no full screen"
