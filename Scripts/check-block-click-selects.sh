#!/bin/bash
#
# check-block-click-selects.sh — drive a REAL mouse click at a block and assert
# the block becomes selected. interactions.md §6: "Clicking a block selects it;
# clicking empty grid deselects."
#
# Why this exists: P2-T02. `.contentShape` was applied after `.offset` in
# DayColumnView.blockStack, which collapsed every block's hit region onto its
# day column's top-left corner. Blocks still *drew* correctly, so no screenshot
# review could catch it, and no unit test can see modifier ordering. The only
# way to know is to click the running app and look at what happened.
#
# Sibling of check-block-hit-regions.sh. That one asserts the hit *geometry* is
# where it should be; this one asserts a click actually lands and selects.
#
# WHY A CGEvent AND NOT `System Events ... click at {x, y}`:
# `click at` does NOT synthesise a mouse event. It resolves the accessibility
# element at that screen point and sends it AXPress. That bypasses hit-testing
# entirely — it passed happily against the broken build — so it is useless as a
# regression test for this defect. This script posts a genuine CGEvent
# mouseDown/mouseUp pair through the HID event tap instead, which is the same
# path a human click takes.
#
# Selection is read back as the AXSelected attribute, which SwiftUI vends from
# the `.isSelected` trait GridBlockView adds when `presentation` contains
# `.selected`.
#
# KNOWN CONFOUND, handled: one block ("Statistik übung" in the mock data)
# reports AXSelected=true at a pristine launch with nothing selected. That is an
# AppKit AX-bridge artifact, not our trait — it reproduces with the
# `.accessibilityAddTraits(.isSelected)` line deleted from GridBlockView
# entirely. See DEVIATIONS.md A24. This script therefore only ever picks a
# target that reads NOT selected at baseline, and asserts on the transition.
#
# It needs Accessibility + Automation permission for whatever runs it.
#
# Usage:  Scripts/check-block-click-selects.sh          # builds, launches, checks, quits
#         Scripts/check-block-click-selects.sh --keep   # leaves the app running
#
set -uo pipefail
cd "$(dirname "$0")/.."

KEEP=0
[[ "${1:-}" == "--keep" ]] && KEEP=1

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# ---------------------------------------------------------------- the clicker
cat > "$WORK/click.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let a = CommandLine.arguments
guard a.count >= 3, let x = Double(a[1]), let y = Double(a[2]) else {
    FileHandle.standardError.write("usage: click X Y\n".data(using: .utf8)!); exit(2)
}
let pt = CGPoint(x: x, y: y)
let src = CGEventSource(stateID: .hidSystemState)
// Move first: a click with no preceding move can land before SwiftUI has
// updated its hover/hit state.
CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
        mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(150_000)
CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
        mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
usleep(60_000)
CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
        mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
SWIFT
echo "compiling clicker…"
swiftc -O "$WORK/click.swift" -o "$WORK/kclick" 2>"$WORK/swiftc.log" || {
  echo "FAIL: could not compile the click helper — see $WORK/swiftc.log"
  cat "$WORK/swiftc.log"; exit 1; }

# ------------------------------------------------------------------ the build
echo "building…"
xcodebuild -scheme Kadence -destination 'platform=macOS' build >/tmp/kadence-click-build.log 2>&1 || {
  echo "FAIL: build failed — see /tmp/kadence-click-build.log"; exit 1; }

APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/Kadence-*/Build/Products/Debug/Kadence.app 2>/dev/null | head -1)
[[ -z "$APP" ]] && { echo "FAIL: no built app found"; exit 1; }

# Same pid-targeting discipline as check-accessibility.sh: System Events resolves
# `process "Kadence"` by NAME, so a wedged instance with no window will happily
# answer accessibility queries on behalf of the healthy one.
for PID in $(pgrep -f "Kadence.app/Contents/MacOS/Kadence"); do kill -9 "$PID" 2>/dev/null; done
sleep 2
# Park the pointer away from the window so nothing is hovered at baseline.
"$WORK/kclick" 5 5 >/dev/null 2>&1
open -n "$APP"
sleep 9

TARGET=""
for PID in $(pgrep -f "Kadence.app/Contents/MacOS/Kadence"); do
  N=$(osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to count windows" 2>/dev/null)
  if [[ "${N:-0}" -ge 1 ]]; then TARGET=$PID; break; fi
done
if [[ -z "$TARGET" ]]; then
  echo "FAIL: no Kadence process has a window — the app did not come up."
  echo "      (If TextEdit also reports 0 windows, that is the machine, not this code.)"
  exit 1
fi

osascript -e "tell application \"System Events\" to tell (first process whose unix id is $TARGET) to set size of window 1 to {1500, 900}" >/dev/null 2>&1
sleep 2
echo "driving pid $TARGET"

# ------------------------------------------------------------------ the query
cat > "$WORK/query.applescript" <<EOF
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
          set sz to size of c
          set selv to "no"
          try
            set selv to (value of attribute "AXSelected" of c) as string
          end try
          set end of acc to lbl & "|" & (item 1 of p as string) & "|" & ¬
            (item 2 of p as string) & "|" & (item 1 of sz as string) & "|" & ¬
            (item 2 of sz as string) & "|" & selv
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
  tell (first process whose unix id is $TARGET)
    set found to my collect(window 1, 0)
    set out to ""
    repeat with f in found
      set out to out & (f as string) & linefeed
    end repeat
    return out
  end tell
end tell
EOF

query() { osascript "$WORK/query.applescript"; }

# ------------------------------------------------- pick a target, click, check
query > "$WORK/before.txt"

python3 - "$WORK/before.txt" "$WORK/plan.txt" <<'PY'
import re, sys

before, planfile = sys.argv[1], sys.argv[2]

def parse(path):
    rows = []
    for line in open(path).read().splitlines():
        parts = line.split("|")
        if len(parts) != 6:
            continue
        label, x, y, w, h, sel = parts
        if not re.search(r"\d\d:\d\d.\d\d:\d\d", label):
            continue        # all-day chips and window chrome carry no time range
        try:
            x, y, w, h = int(x), int(y), int(w), int(h)
        except ValueError:
            continue
        title = label.split("·")[0].strip()
        rows.append(dict(title=title, x=x, y=y, w=w, h=h,
                         sel=(sel.strip().lower() == "true")))
    # A block can be reported more than once; keep one row per title.
    seen, out = set(), []
    for r in rows:
        if r["title"] in seen:
            continue
        seen.add(r["title"]); out.append(r)
    return out

rows = parse(before)
print("blocks found:            %d" % len(rows))
if len(rows) < 5:
    print("\nFAIL: expected at least 5 timed blocks, found %d — the app did not"
          "\n      come up with the mock data, or blocks stopped reaching the"
          "\n      accessibility tree (see check-accessibility.sh)." % len(rows))
    sys.exit(1)

preselected = [r["title"] for r in rows if r["sel"]]
print("selected at baseline:    %s" % (", ".join(preselected) or "none"))

# Fail fast and loudly on the P2-T02 signature. Under that bug every block in a
# column reports the SAME position, so the click-target search below would fail
# with a confusing "no unambiguous block" instead of naming the real defect.
positions = {(r["x"], r["y"]) for r in rows}
print("distinct positions:      %d of %d blocks" % (len(positions), len(rows)))
if len(positions) * 2 < len(rows):
    print("\nFAIL: blocks are piled on top of each other in the accessibility"
          "\n      tree — %d distinct positions for %d blocks. Hit regions are not"
          "\n      tracking their laid-out frames."
          "\n      This is the P2-T02 signature: .contentShape applied AFTER"
          "\n      .offset in DayColumnView.blockStack collapses every block's hit"
          "\n      region onto its day column's top-left corner, so clicking a"
          "\n      block does nothing. .contentShape must come BEFORE .offset."
          "\n      See STATUS.md 1.6." % (len(positions), len(rows)))
    sys.exit(1)

def centre(r):
    return (r["x"] + r["w"] / 2.0, r["y"] + r["h"] / 2.0)

def covered_by_other(r, pt):
    """True if any OTHER block's rect also contains pt (an overlap cascade)."""
    for o in rows:
        if o["title"] == r["title"]:
            continue
        if o["x"] <= pt[0] <= o["x"] + o["w"] and o["y"] <= pt[1] <= o["y"] + o["h"]:
            return True
    return False

# The target must (a) read NOT selected at baseline, so the assertion is a real
# transition, (b) be tall enough to click confidently, and (c) not sit under any
# other block at the click point — z-order in an overlap is unspecified
# (design/GAPS.md G-024), so a cascade would make this test ambiguous.
candidates = []
for r in rows:
    if r["sel"] or r["h"] < 20 or r["w"] < 40:
        continue
    pt = centre(r)
    if covered_by_other(r, pt):
        continue
    candidates.append((r, pt))

if not candidates:
    print("\nFAIL: no unambiguous, unselected, comfortably-sized block to click.")
    sys.exit(1)

# Prefer the tallest — most margin for error.
candidates.sort(key=lambda c: -c[0]["h"])
target, pt = candidates[0]
print("target block:            %s  (%dx%d at %d,%d)"
      % (target["title"], target["w"], target["h"], target["x"], target["y"]))

# An empty-grid point: same column, at least 25pt clear of every block rect.
col_x = pt[0]
blocked = [(r["y"] - 25, r["y"] + r["h"] + 25) for r in rows
           if r["x"] - 25 <= col_x <= r["x"] + r["w"] + 25]
ys = [r["y"] for r in rows] + [r["y"] + r["h"] for r in rows]
empty_y = None
for cand in range(min(ys), max(ys)):
    if all(not (lo <= cand <= hi) for lo, hi in blocked):
        empty_y = cand
        break
if empty_y is None:
    print("empty-grid point:        none found (deselect check will be skipped)")
else:
    print("empty-grid point:        %d,%d" % (col_x, empty_y))

with open(planfile, "w") as f:
    f.write("%s\n%d\n%d\n%s\n" % (target["title"], int(pt[0]), int(pt[1]),
                                  "" if empty_y is None else "%d %d" % (int(col_x), empty_y)))
PY
[[ $? -ne 0 ]] && { [[ $KEEP -eq 0 ]] && pkill -f "Kadence.app/Contents/MacOS/Kadence" 2>/dev/null; exit 1; }

TITLE=$(sed -n '1p' "$WORK/plan.txt")
CX=$(sed -n '2p' "$WORK/plan.txt")
CY=$(sed -n '3p' "$WORK/plan.txt")
EMPTY=$(sed -n '4p' "$WORK/plan.txt")

echo ""
echo "clicking \"$TITLE\" at $CX,$CY …"
"$WORK/kclick" "$CX" "$CY"
sleep 2
query > "$WORK/after.txt"

if [[ -n "$EMPTY" ]]; then
  echo "clicking empty grid at ${EMPTY/ /,} …"
  "$WORK/kclick" ${EMPTY}
  sleep 2
  query > "$WORK/after-empty.txt"
else
  : > "$WORK/after-empty.txt"
fi

[[ $KEEP -eq 0 ]] && pkill -f "Kadence.app/Contents/MacOS/Kadence" 2>/dev/null

python3 - "$WORK/after.txt" "$WORK/after-empty.txt" "$TITLE" <<'PY'
import re, sys

after, after_empty, title = sys.argv[1], sys.argv[2], sys.argv[3]

def sel_of(path, want):
    for line in open(path).read().splitlines():
        parts = line.split("|")
        if len(parts) != 6:
            continue
        label, sel = parts[0], parts[5]
        if not re.search(r"\d\d:\d\d.\d\d:\d\d", label):
            continue
        if label.split("·")[0].strip() == want:
            return sel.strip().lower() == "true"
    return None

print("")
ok = True

got = sel_of(after, title)
if got is None:
    print("FAIL: \"%s\" vanished from the accessibility tree after the click." % title)
    ok = False
elif got:
    print("PASS: clicking \"%s\" selected it (AXSelected true)." % title)
else:
    print("FAIL: clicking \"%s\" did NOT select it — AXSelected is still false." % title)
    print("      This is the P2-T02 signature: the click never reached the block.")
    print("      Check that .contentShape comes BEFORE .offset in")
    print("      DayColumnView.blockStack, and see STATUS.md 1.6.")
    ok = False

body = open(after_empty).read().strip()
if not body:
    print("SKIP: no empty-grid point was available, deselect not checked.")
else:
    got2 = sel_of(after_empty, title)
    if got2 is False:
        print("PASS: clicking empty grid deselected it (interactions.md 6).")
    else:
        print("FAIL: clicking empty grid left \"%s\" selected (%r)." % (title, got2))
        ok = False
    print("      (The time cursor that a grid click also places is not vended to")
    print("       accessibility, so only the deselect half is asserted here.)")

sys.exit(0 if ok else 1)
PY
STATUS=$?
exit "$STATUS"
