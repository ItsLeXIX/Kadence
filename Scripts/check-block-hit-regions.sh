#!/bin/bash
#
# check-block-hit-regions.sh — assert that a block's hit region is actually
# *at the block*, not at its day column's top-left corner.
#
# Why this exists: P2-T02. `.contentShape` was applied after `.offset` in
# DayColumnView.blockStack. `.offset` translates rendering but leaves the layout
# frame where it was, so a `.contentShape` applied afterwards describes the hit
# region in the un-offset layout space. Every block still *drew* in the right
# place, so screenshots looked perfect, while every block's hit region collapsed
# onto its column's top-left corner. Clicking a block did nothing: the click
# fell through to the create surface, which deselected instead.
#
# Nothing in KadenceTests can see this. SwiftUI resolves hit regions only in a
# real window, and the rendering — the part a screenshot review would catch —
# was never wrong. The accessibility frame is the one place the resolved
# geometry is observable from outside the process, so that is what this asserts.
#
# The invariant: within a day column, ordering blocks by start time must give
# non-decreasing accessibility y. Under the bug every y in a column was
# identical, so the check fails loudly.
#
# It drives the built app through System Events, so it needs Automation
# permission for whatever runs it (Terminal/Xcode) the first time.
#
# Usage:  Scripts/check-block-hit-regions.sh          # builds, launches, checks, quits
#         Scripts/check-block-hit-regions.sh --keep   # leaves the app running
#
set -uo pipefail
cd "$(dirname "$0")/.."

KEEP=0
[[ "${1:-}" == "--keep" ]] && KEEP=1

echo "building…"
xcodebuild -scheme Kadence -destination 'platform=macOS' build >/tmp/kadence-hit-build.log 2>&1 || {
  echo "FAIL: build failed — see /tmp/kadence-hit-build.log"; exit 1; }

APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/Kadence-*/Build/Products/Debug/Kadence.app 2>/dev/null | head -1)
[[ -z "$APP" ]] && { echo "FAIL: no built app found"; exit 1; }

# Same pid-targeting discipline as check-accessibility.sh: System Events resolves
# `process "Kadence"` by NAME, so a wedged instance with no window will happily
# answer accessibility queries on behalf of the healthy one.
for PID in $(pgrep -f "Kadence.app/Contents/MacOS/Kadence"); do kill -9 "$PID" 2>/dev/null; done
sleep 2
# -ApplePersistenceIgnoreState YES: see check-accessibility.sh for why. This
# Mac's window-restoration has reopened a previously-used window (e.g. the
# Routines window) as "window 1" ahead of the main window, or produced no
# window at all for 40+ seconds, on a plain `open -n`. Suppressing restoration
# makes the main window the only one that can ever appear.
open -n "$APP" --args -ApplePersistenceIgnoreState YES
sleep 9

# Poll rather than check once — even with restoration suppressed, a cold
# launch has been observed taking ~17s to vend its first window.
TARGET=""
for ATTEMPT in $(seq 1 10); do
  for PID in $(pgrep -f "Kadence.app/Contents/MacOS/Kadence"); do
    N=$(osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to count windows" 2>/dev/null)
    if [[ "${N:-0}" -ge 1 ]]; then TARGET=$PID; break 2; fi
  done
  sleep 2
done
if [[ -z "$TARGET" ]]; then
  echo "FAIL: no Kadence process has a window — the app did not come up."
  echo "      (If TextEdit also reports 0 windows, that is the machine, not this code.)"
  exit 1
fi

# A wider window keeps today's column clear of the inspector overlay, so more
# than one column's worth of blocks is vended.
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $TARGET) to set size of window 1 to {1500, 900}" >/dev/null 2>&1
sleep 2
echo "querying pid $TARGET"

SCPT=/tmp/kadence-hit-$$.applescript
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
        set lbl to ""
        try
          set lbl to (value of attribute "AXHelp" of c) as string
        end try
        if lbl is not "" and lbl is not "missing value" then
          set p to position of c
          set end of acc to lbl & "|" & (item 1 of p as string) & "|" & (item 2 of p as string)
        end if
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
    set out to ""
    repeat with f in found
      set out to out & (f as string) & linefeed
    end repeat
    return out
  end tell
end tell
EOF

RAW=$(KADENCE_PID="$TARGET" osascript "$SCPT")
rm -f "$SCPT"

[[ $KEEP -eq 0 ]] && pkill -f "Kadence.app/Contents/MacOS/Kadence" 2>/dev/null

printf '%s\n' "$RAW" | KADENCE_OUT=1 python3 -c '
import re, sys

rows = []
for line in sys.stdin.read().splitlines():
    parts = line.split("|")
    if len(parts) != 3:
        continue
    label, xs, ys = parts
    m = re.search(r"(\d\d):(\d\d).(\d\d):(\d\d)", label)
    if not m:
        continue            # all-day chips and window chrome carry no time range
    try:
        x, y = int(xs), int(ys)
    except ValueError:
        continue
    start = int(m.group(1)) * 60 + int(m.group(2))
    title = label.split("·")[0].strip()
    rows.append((x, y, start, title))

# One AX element per block, but a block can be reported more than once.
rows = sorted(set(rows))
print("timed block elements found: %d" % len(rows))

if len(rows) < 5:
    print("")
    print("FAIL: expected at least 5 timed block elements, found %d." % len(rows))
    print("      Either the app did not come up with the mock data, or blocks")
    print("      stopped reaching the accessibility tree (see check-accessibility.sh).")
    sys.exit(1)

distinct_y = {r[1] for r in rows}
print("distinct y positions:       %d" % len(distinct_y))

# Group into columns by x, then assert chronological order matches y order.
cols = {}
for x, y, start, title in rows:
    cols.setdefault(x, []).append((start, y, title))

failures = []
checked = 0
for x, items in sorted(cols.items()):
    items = sorted(set(items))
    if len({i[0] for i in items}) < 2:
        continue            # need two distinct start times to say anything
    checked += 1
    for (s1, y1, t1), (s2, y2, t2) in zip(items, items[1:]):
        if s2 - s1 < 15:
            continue        # too close in time; y could legitimately round equal
        # A block starting >=15 min later must sit strictly lower. Under the bug
        # every block in a column reported an IDENTICAL y, which a
        # non-decreasing test would wave through — hence strict.
        if y2 <= y1:
            failures.append(
                "  column x=%d: %s (%02d:%02d) y=%d  vs  %s (%02d:%02d) y=%d"
                % (x, t1, s1 // 60, s1 % 60, y1, t2, s2 // 60, s2 % 60, y2))

print("columns checked:            %d" % checked)

if checked == 0:
    print("")
    print("FAIL: no column had two distinct start times, so the ordering")
    print("      invariant could not be checked at all.")
    sys.exit(1)

if failures:
    print("")
    print("FAIL: blocks that start later do not sit lower in the accessibility")
    print("      tree — hit regions are not tracking their laid-out positions.")
    print("      This is the P2-T02 signature: .contentShape applied AFTER")
    print("      .offset in DayColumnView.blockStack collapses each blocks")
    print("      hit region onto its day column corner, so clicking a block")
    print("      does nothing. .contentShape must come BEFORE .offset.")
    for f in failures[:10]:
        print(f)
    sys.exit(1)

print("PASS (hit regions track laid-out positions)")
'
STATUS=${PIPESTATUS[1]}
exit "$STATUS"
