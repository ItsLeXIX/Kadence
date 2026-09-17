#!/bin/bash
#
# check-routines-window.sh — task P2-T10's UI-level regression check: the
# Routines window (layouts.md §8) actually opens, the seeded demo template's
# blocks reach the accessibility tree, and clicking one selects it and changes
# what the inspector shows.
#
# Sibling of check-block-click-selects.sh and check-accessibility.sh — same
# CGEvent-click and System-Events-query techniques, same reasons (see those
# scripts' headers for why a CGEvent and not `click at`, and why block
# elements need .combine + a trait to reach the tree at all).
#
# What this does NOT try to assert: that a block sits in the geometrically
# correct weekday column. That is covered at the pure-function level instead —
# KadenceTests/RoutineWeekLayoutTests.swift asserts the seeded template's
# blocks are only produced for its active weekdays and are positioned by
# DayLayoutEngine at exactly their own start time — because a script reading
# screen coordinates back through AppleScript has no reliable way to know
# which x-coordinate belongs to which weekday column without duplicating the
# window's own layout math.
#
# It needs Accessibility + Automation permission for whatever runs it.
#
# Usage:  Scripts/check-routines-window.sh          # builds, launches, checks, quits
#         Scripts/check-routines-window.sh --keep   # leaves the app running
#
set -uo pipefail
cd "$(dirname "$0")/.."

KEEP=0
[[ "${1:-}" == "--keep" ]] && KEEP=1

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

cat > "$WORK/click.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let a = CommandLine.arguments
guard a.count >= 3, let x = Double(a[1]), let y = Double(a[2]) else {
    FileHandle.standardError.write("usage: click X Y\n".data(using: .utf8)!); exit(2)
}
let pt = CGPoint(x: x, y: y)
let src = CGEventSource(stateID: .hidSystemState)
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

echo "building…"
xcodebuild -scheme Kadence -destination 'platform=macOS' build >/tmp/kadence-routines-build.log 2>&1 || {
  echo "FAIL: build failed — see /tmp/kadence-routines-build.log"; exit 1; }

APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/Kadence-*/Build/Products/Debug/Kadence.app 2>/dev/null | head -1)
[[ -z "$APP" ]] && { echo "FAIL: no built app found"; exit 1; }

for PID in $(pgrep -f "Kadence.app/Contents/MacOS/Kadence"); do kill -9 "$PID" 2>/dev/null; done
sleep 2
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
echo "driving pid $TARGET"

BEFORE_COUNT=$(osascript -e "tell application \"System Events\" to tell (first process whose unix id is $TARGET) to count windows")
echo "windows before ⌘⌥R: $BEFORE_COUNT"

# ⌘⌥R — the same shortcut KadenceCommands.swift binds to "Routines".
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $TARGET) to keystroke \"r\" using {command down, option down}" >/dev/null 2>&1
sleep 3

AFTER_COUNT=$(osascript -e "tell application \"System Events\" to tell (first process whose unix id is $TARGET) to count windows")
echo "windows after ⌘⌥R:  $AFTER_COUNT"

if [[ "$AFTER_COUNT" -le "$BEFORE_COUNT" ]]; then
  echo
  echo "FAIL: ⌘⌥R did not open a new window (before=$BEFORE_COUNT after=$AFTER_COUNT)."
  [[ $KEEP -eq 0 ]] && pkill -f "Kadence.app/Contents/MacOS/Kadence" 2>/dev/null
  exit 1
fi
echo "PASS: ⌘⌥R opened a new window."

# The window System Events just activated is frontmost, i.e. window 1.
osascript -e "tell application \"System Events\" to tell (first process whose unix id is $TARGET) to set size of window 1 to {1000, 700}" >/dev/null 2>&1
sleep 2

cat > "$WORK/query.applescript" <<EOF
on collect(el, depth)
  set acc to {}
  if depth > 16 then return acc
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
        set val to ""
        try
          set val to (value of attribute "AXValue" of c) as string
        end try
        if (lbl is not "" and lbl is not "missing value") or (val is not "" and val is not "missing value") then
          set p to {0, 0}
          set sz to {0, 0}
          try
            set p to position of c
          end try
          try
            set sz to size of c
          end try
          set selv to "no"
          try
            set selv to (value of attribute "AXSelected" of c) as string
          end try
          set end of acc to lbl & "~~" & val & "|" & (item 1 of p as string) & "|" & ¬
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

query > "$WORK/before.txt"

python3 - "$WORK/before.txt" "$WORK/plan.txt" <<'PY'
import re, sys

before, planfile = sys.argv[1], sys.argv[2]

rows = []
for line in open(before).read().splitlines():
    parts = line.split("|")
    if len(parts) != 6:
        continue
    label, x, y, w, h, sel = parts
    help_part, value_part = (label.split("~~", 1) + [""])[:2]
    if not re.search(r"routine block", help_part):
        continue
    m = re.search(r"\d\d:\d\d.\d\d:\d\d", help_part)
    if not m:
        continue
    try:
        x, y, w, h = int(float(x)), int(float(y)), int(float(w)), int(float(h))
    except ValueError:
        continue
    title = help_part.split("·")[0].strip()
    rows.append(dict(title=title, x=x, y=y, w=w, h=h, sel=(sel.strip().lower() == "true")))

seen, unique = set(), []
for r in rows:
    key = (r["title"], r["x"], r["y"])
    if key in seen:
        continue
    seen.add(key)
    unique.append(r)

print("routine block elements found: %d" % len(unique))
for r in unique:
    print("  %-20s %dx%d at %d,%d  selected=%s" % (r["title"], r["w"], r["h"], r["x"], r["y"], r["sel"]))

if len(unique) < 3:
    print("\nFAIL: expected at least 3 routine-block elements (the seeded demo template"
          "\n      has 3 blocks on each of its active weekdays), found %d. Either the"
          "\n      window did not render the seeded template, or blocks are not"
          "\n      reaching the accessibility tree the way GridBlockView normally does."
          % len(unique))
    sys.exit(1)

candidates = [r for r in unique if not r["sel"] and r["h"] >= 10 and r["w"] >= 20]
if not candidates:
    print("\nFAIL: every block already reads selected at baseline — no clean transition to assert.")
    sys.exit(1)

target = candidates[0]
cx, cy = target["x"] + target["w"] / 2.0, target["y"] + target["h"] / 2.0
print("\ntarget block: %s at %d,%d" % (target["title"], int(cx), int(cy)))

with open(planfile, "w") as f:
    f.write("%s\n%d\n%d\n" % (target["title"], int(cx), int(cy)))
PY
STATUS=$?
if [[ $STATUS -ne 0 ]]; then
  [[ $KEEP -eq 0 ]] && pkill -f "Kadence.app/Contents/MacOS/Kadence" 2>/dev/null
  exit 1
fi

TITLE=$(sed -n '1p' "$WORK/plan.txt")
CX=$(sed -n '2p' "$WORK/plan.txt")
CY=$(sed -n '3p' "$WORK/plan.txt")

echo ""
echo "clicking \"$TITLE\" at $CX,$CY …"
"$WORK/kclick" "$CX" "$CY"
sleep 2
query > "$WORK/after.txt"

[[ $KEEP -eq 0 ]] && pkill -f "Kadence.app/Contents/MacOS/Kadence" 2>/dev/null

python3 - "$WORK/before.txt" "$WORK/after.txt" "$TITLE" <<'PY'
import re, sys

before, after, title = sys.argv[1], sys.argv[2], sys.argv[3]

def block_selected(path, want):
    for line in open(path).read().splitlines():
        parts = line.split("|")
        if len(parts) != 6:
            continue
        label, sel = parts[0], parts[5]
        help_part = label.split("~~", 1)[0]
        if not re.search(r"routine block", help_part):
            continue
        if not re.search(r"\d\d:\d\d.\d\d:\d\d", help_part):
            continue
        if help_part.split("·")[0].strip() == want:
            return sel.strip().lower() == "true"
    return None

def static_values(path):
    out = set()
    for line in open(path).read().splitlines():
        parts = line.split("|")
        if len(parts) != 6:
            continue
        value_part = parts[0].split("~~", 1)[-1]
        if value_part and value_part != "missing value":
            out.add(value_part.strip())
    return out

ok = True

got = block_selected(after, title)
if got is None:
    print("FAIL: \"%s\" vanished from the accessibility tree after the click." % title)
    ok = False
elif got:
    print("PASS: clicking \"%s\" selected it (AXSelected true)." % title)
else:
    print("FAIL: clicking \"%s\" did NOT select it — AXSelected is still false." % title)
    ok = False

before_values = static_values(before)
after_values = static_values(after)
gained = after_values - before_values

# The inspector's block-detail title is rendered as a plain Text with the
# block's own title (RoutinesWindow.swift's RoutineInspectorView.blockDetails)
# — it was not on screen before the click (nothing was selected, so the
# inspector showed the template summary instead) and should be present after.
if any(title in v for v in gained):
    print("PASS: the inspector's static text gained \"%s\" after the click "
          "(the block-detail view replaced the template summary)." % title)
else:
    print("FAIL: no new static text containing \"%s\" appeared after the click — "
          "the inspector does not appear to have switched to the block detail view." % title)
    print("      New static text values seen: %r" % sorted(gained))
    ok = False

sys.exit(0 if ok else 1)
PY
STATUS=$?
exit "$STATUS"
