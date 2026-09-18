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
# -ApplePersistenceIgnoreState YES: this Mac's window-restoration machinery has
# repeatedly reopened a *previously used* window (the Routines window, opened
# by hand during P2-T10/P2-T11/P2-T12 verification) as "window 1" ahead of the
# freshly-launched main window on a plain `open -n`, and on at least one
# reproduction produced no window at all for 40+ seconds while the process sat
# idle in mach_msg2_trap (alive, not crashed, not spinning — sampled and
# confirmed). The flag suppresses restoration entirely so the only window that
# can ever appear is the one this script means to query. See STATUS.md §8 and
# the follow-up task that applied this fix.
open -n "$APP" --args -ApplePersistenceIgnoreState YES
sleep 9

# Query the instance that actually has a window, never the one that merely has
# the right name. Poll rather than check once: even with restoration
# suppressed, a cold launch has been observed taking ~17s to vend its first
# window to System Events, longer than the original single 9s sleep allowed.
TARGET=""
for ATTEMPT in $(seq 1 10); do
  for PID in $(pgrep -f "Kadence.app/Contents/MacOS/Kadence"); do
    N=$(osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to count windows" 2>/dev/null)
    if [[ "${N:-0}" -ge 1 ]]; then TARGET=$PID; break 2; fi
  done
  sleep 2
done
if [[ -z "$TARGET" ]]; then
  # Before blaming the app: query a control process that is always running
  # (Finder) the exact same way. This machine has twice before (P2-T01,
  # P2-T07) gone through stretches where the accessibility API vends 0
  # windows for *every* process, Kadence included — most concretely, a
  # locked screen session blocks AX window enumeration session-wide while
  # WindowServer keeps the real window alive underneath it (confirmed via
  # `CGSSessionCopyCurrentDictionary`'s `CGSSessionScreenIsLocked` and
  # `CGWindowListCopyWindowInfo` showing a correctly-sized Kadence window
  # during the P2-T15 follow-up investigation that added this check — see
  # STATUS.md). Finder reporting 0 windows too is the same control the CA
  # brief itself asks for ("if TextEdit also reports 0 windows, that is the
  # machine, not your code"); this makes the script perform that control
  # itself instead of leaving it to whoever reads the failure by hand.
  FINDER_WINDOWS=$(osascript -e 'tell application "System Events" to tell process "Finder" to count windows' 2>/dev/null)
  if [[ "${FINDER_WINDOWS:-0}" == "0" ]]; then
    echo "FAIL: no Kadence process has a window — but Finder reports 0 windows too."
    echo "      This is the accessibility API failing session-wide, not a Kadence"
    echo "      defect: the most common cause is a locked screen (the login window"
    echo "      blocks AX window enumeration for every process while the real"
    echo "      windows stay alive underneath it — WindowServer still has them,"
    echo "      System Events just cannot see them). Unlock the screen and re-run."
    echo "      (A revoked Automation/Accessibility permission for whatever is"
    echo "       running this script is the other known cause — check System"
    echo "       Settings ▸ Privacy & Security ▸ Accessibility if unlocking the"
    echo "       screen does not fix it.)"
  else
    echo "FAIL: no Kadence process has a window — the app did not come up."
    echo "      (If a stale instance is wedged, note that it answers to the app's"
    echo "       name in System Events even with no window.)"
  fi
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
