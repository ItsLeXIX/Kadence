#!/bin/bash
#
# check-accessibility.sh — assert that calendar blocks actually reach the
# macOS accessibility tree.
#
# Why this is a script and not a unit test: SwiftUI on macOS builds its
# accessibility tree lazily and vends it only to an out-of-process client. An
# NSHostingView inside a unit test reports zero accessibility children even for
# a plain `Text`, so a test built that way passes while the app is broken —
# which is exactly the failure mode this guards (DEVIATIONS.md A20).
#
# It drives the built app through System Events, so it needs Automation
# permission for whatever runs it (Terminal/Xcode) the first time.
#
# Usage:  Scripts/check-accessibility.sh          # builds, launches, checks, quits
#         Scripts/check-accessibility.sh --keep   # leaves the app running
#
set -uo pipefail
cd "$(dirname "$0")/.."

KEEP=0
[[ "${1:-}" == "--keep" ]] && KEEP=1

echo "building…"
xcodebuild -scheme Kadence -destination 'platform=macOS' build >/tmp/kadence-a11y-build.log 2>&1 || {
  echo "FAIL: build failed — see /tmp/kadence-a11y-build.log"; exit 1; }

APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/Kadence-*/Build/Products/Debug/Kadence.app 2>/dev/null | head -1)
[[ -z "$APP" ]] && { echo "FAIL: no built app found"; exit 1; }

# Kill by pid, and check. A wedged instance that ignores SIGKILL is not
# hypothetical: one survived 28 minutes of kill -9 during the 2026-09-09 session
# and, because System Events resolves `process "Kadence"` by NAME, answered every
# accessibility query on behalf of the real app — reporting zero blocks while the
# app was perfectly healthy. Cost an hour. Hence the pid-targeting below.
for PID in $(pgrep -f "Kadence.app/Contents/MacOS/Kadence"); do kill -9 "$PID" 2>/dev/null; done
sleep 2
open -n "$APP"
sleep 9

# Query the instance that actually has a window, never the one that merely has
# the right name.
TARGET=""
for PID in $(pgrep -f "Kadence.app/Contents/MacOS/Kadence"); do
  N=$(osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to count windows" 2>/dev/null)
  if [[ "${N:-0}" -ge 1 ]]; then TARGET=$PID; break; fi
done
if [[ -z "$TARGET" ]]; then
  echo "FAIL: no Kadence process has a window — the app did not come up."
  echo "      (If a stale instance is wedged, note that it answers to the app's"
  echo "       name in System Events even with no window.)"
  exit 1
fi
echo "querying pid $TARGET"

SCPT=/tmp/kadence-a11y-$$.applescript
cat > "$SCPT" <<'EOF'
on collect(el, depth)
  set acc to {}
  if depth > 14 then return acc
  tell application "System Events"
    set kids to {}
    try
      set kids to UI elements of el
    end try
    repeat with c in kids
      try
        set blob to ""
        repeat with attrName in {"AXTitle", "AXDescription", "AXHelp"}
          try
            set av to (value of attribute (attrName as string) of c) as string
            if av is not "" and av is not "missing value" then set blob to blob & (attrName as string) & "=" & av & " ~~ "
          end try
        end repeat
        if blob is not "" then set end of acc to blob
      end try
      try
        set acc to acc & my collect(c, depth + 1)
      end try
    end repeat
  end tell
  return acc
end collect
tell application "System Events"
  tell (first process whose unix id is (system attribute "KADENCE_PID") as integer)
    set found to my collect(window 1, 0)
    -- Join by hand: `text item delimiters` inside a `tell process` block would
    -- try to set the delimiters *on the process*, which errors.
    set out to ""
    repeat with f in found
      set out to out & (f as string) & linefeed
    end repeat
    return out
  end tell
end tell
EOF

LABELS=$(KADENCE_PID="$TARGET" osascript "$SCPT")
rm -f "$SCPT"

[[ $KEEP -eq 0 ]] && pkill -f "Kadence.app/Contents/MacOS/Kadence" 2>/dev/null

# Two separate things have to hold, and they broke independently (A20):
#
#   1. block elements reach the tree at all;
#   2. the element carries the components.md §11 label, in order.
#
# (1) is the hard gate — losing it means VoiceOver sees no calendar at all.
# (2) is currently KNOWN BROKEN (A20b): the elements arrive as AXButton carrying
#     only the §3.4 hover-help string, and the explicit .accessibilityLabel does
#     not stick. It warns rather than fails so this script stays usable as a
#     regression gate; remove the warning branch once A20b is fixed.

PRESENT=$(printf '%s\n' "$LABELS" | grep -c '[0-9][0-9]:[0-9][0-9].[0-9][0-9]:[0-9][0-9]' || true)
LABELLED=$(printf '%s\n' "$LABELS" | grep -cE 'AX(Title|Description)=[^~]* to [0-9][0-9]:[0-9][0-9],' || true)

echo "block-shaped elements in the tree: $PRESENT"
echo "carrying the §11 label:            $LABELLED"
printf '%s\n' "$LABELS" | grep '[0-9][0-9]:[0-9][0-9].[0-9][0-9]:[0-9][0-9]' | head -3 | sed 's/^/  /'

if [[ "$PRESENT" -lt 5 ]]; then
  echo
  echo "FAIL: expected at least 5 block elements in the accessibility tree, found $PRESENT."
  echo "      components.md §11 requires each block to be one accessibility element."
  echo "      .accessibilityElement(children:) alone does NOT reach the tree — the"
  echo "      element needs .combine plus a trait. See DEVIATIONS.md A20."
  exit 1
fi

if [[ "$LABELLED" -lt 5 ]]; then
  echo
  echo "WARN: blocks are in the tree, but $LABELLED carry the §11 label."
  echo "      Known open defect A20b — VoiceOver reads the hover-help string"
  echo "      instead of 'title, time, kind, source, status'."
fi

echo "PASS (elements present)"
