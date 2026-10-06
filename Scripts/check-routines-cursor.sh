#!/bin/bash
#
# check-routines-cursor.sh — task P2-C3's live check of the Routines canvas
# cursor (interactions.md §1, amended 2026-10-07; §11.1; G-050):
#
#   1. on open the canvas is focused with nothing selected → cursor mode,
#      AX value `07:00` (default 06:00 scroll, first whole hour below);
#   2. the P2-SF1 ⇥ walk: ⇥ → the editor inspector's toggle row (canvas
#      value empty — not cursor mode), ⇥ → back to the canvas → `07:00`
#      (the last cursor time, still in view); frames of both for a look;
#   3. ↓ → 07:15, ↑ ↑ → 06:45, ← → → unchanged;
#   4. ↑ to the clamp → 00:00, ↓ to the clamp → 23:45 (the canvas scrolls
#      to keep the line in view: frames at both ends for a look);
#   5. an empty-canvas click on Monday (active) at the 10:00 line → `10:00`;
#      on Tuesday (inactive) at the 11:00 line → `11:00`, and no block was
#      created by either (the AX block titles are unchanged);
#   6. ⎋ in cursor mode → the canvas is unfocused (no value);
#   7. click a block (selection mode, no value), ⎋ → cursor mode again;
#   8. click a block, ⌘] (Windows mode drops the selection) → cursor mode
#      with the canvas still focused; ⌘[ back.
#
# Same method and helpers as capture-p2f25.sh (copied): pre-flight (refuses
# if the screen is locked or any app is in full screen), a fresh store,
# input only while Kadence is frontmost, every click through
# Scripts/lib/kadence-guard.swift.
# Usage: Scripts/check-routines-cursor.sh [FRAMEDIR]   (frames to a temp dir by default)
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-$(mktemp -d)}"
mkdir -p "$OUT"
SUFFIX="${SUFFIX:-check}"

# ---------------------------------------------------------------- pre-flight
LOCK_STATE=$(swift -e '
  import CoreGraphics
  import Foundation
  if let d = CGSessionCopyCurrentDictionary() as NSDictionary? { print((d["CGSSessionScreenIsLocked"] as? Int) ?? 0) } else { print(0) }
' 2>/dev/null)
[[ "$LOCK_STATE" == "1" ]] && { echo "SKIP: screen is locked."; exit 1; }
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
[[ -n "${FULL// /}" ]] && { echo "SKIP: an app is in full screen ($FULL)."; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# -------------------------------------------------------------- helpers (Swift)
cat > "$WORK/hid.swift" <<'SWIFT'
import CoreGraphics
import Foundation
// hid click X Y | hid key CODE [cmd] [opt] [shift] | hid scroll X Y DY
let a = CommandLine.arguments
let src = CGEventSource(stateID: .hidSystemState)
switch a[1] {
case "click":
    let pt = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
    func post(_ t: CGEventType) {
        let e = CGEvent(mouseEventSource: src, mouseType: t, mouseCursorPosition: pt, mouseButton: .left)!
        e.flags = []
        e.post(tap: .cghidEventTap)
    }
    post(.mouseMoved); usleep(150_000)
    post(.leftMouseDown); usleep(60_000)
    post(.leftMouseUp)
case "key":
    var flags: CGEventFlags = []
    if a.contains("cmd") { flags.insert(.maskCommand) }
    if a.contains("opt") { flags.insert(.maskAlternate) }
    if a.contains("shift") { flags.insert(.maskShift) }
    let code = UInt16(a[2])!
    let down = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)!
    down.flags = flags; down.post(tap: .cghidEventTap)
    usleep(60_000)
    let up = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)!
    up.flags = flags; up.post(tap: .cghidEventTap)
case "scroll":
    let pt = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
    let move = CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: pt, mouseButton: .left)!
    move.flags = []; move.post(tap: .cghidEventTap)
    usleep(100_000)
    // Negative DY scrolls the content up (reveals later hours).
    let e = CGEvent(scrollWheelEvent2Source: src, units: .pixel, wheelCount: 1,
                    wheel1: Int32(a[4])!, wheel2: 0, wheel3: 0)!
    e.flags = []
    e.post(tap: .cghidEventTap)
default: exit(2)
}
SWIFT
cat > "$WORK/axq.swift" <<'SWIFT'
import ApplicationServices
import Foundation
// axq PID: role~title~desc~value~help~x~y~w~h for every element of every window
let pid = pid_t(CommandLine.arguments[1])!
let app = AXUIElementCreateApplication(pid)
func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v }
func str(_ o: AnyObject?) -> String { guard let o else { return "" }; return "\(o)".replacingOccurrences(of: "~", with: " ").replacingOccurrences(of: "\n", with: " ") }
func walk(_ e: AXUIElement, _ d: Int) {
    if d > 18 { return }
    for c in (attr(e, "AXChildren") as? [AXUIElement]) ?? [] {
        var p = CGPoint.zero, s = CGSize.zero
        if let pv = attr(c, "AXPosition") { AXValueGetValue(pv as! AXValue, .cgPoint, &p) }
        if let sv = attr(c, "AXSize") { AXValueGetValue(sv as! AXValue, .cgSize, &s) }
        var desc = str(attr(c, "AXDescription"))
        let ident = str(attr(c, "AXIdentifier"))
        if !ident.isEmpty { desc += " id:" + ident }
        let raw = attr(c, "AXValue")
        let val = (raw is String || raw is NSNumber) ? str(raw) : ""
        print([str(attr(c, "AXRole")), str(attr(c, "AXTitle")), desc, val, str(attr(c, "AXHelp")),
               "\(Int(p.x))", "\(Int(p.y))", "\(Int(s.width))", "\(Int(s.height))"].joined(separator: "~"))
        walk(c, d + 1)
    }
}
for w in (attr(app, "AXWindows") as? [AXUIElement]) ?? [] { walk(w, 0) }
SWIFT
cat > "$WORK/wins.swift" <<'SWIFT'
import CoreGraphics
// wins: id x y w h layer for Kadence's on-screen windows
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerName as String] as? String) == "Kadence" {
    let b = w[kCGWindowBounds as String] as! [String: Any]
    print(w[kCGWindowNumber as String]!, Int(b["X"] as! Double), Int(b["Y"] as! Double),
          Int(b["Width"] as! Double), Int(b["Height"] as! Double), w[kCGWindowLayer as String] as? Int ?? 0)
}
SWIFT
for t in hid axq wins; do
  swiftc -O "$WORK/$t.swift" -o "$WORK/$t" 2>"$WORK/$t.log" || { echo "FAIL: helper $t"; cat "$WORK/$t.log"; exit 1; }
done
# P2-F21: every pointer event goes through this guard (Scripts/lib/kadence-guard.swift):
# it is sent only if Kadence is frontmost AND the window under the point is Kadence's.
swiftc -O Scripts/lib/kadence-guard.swift -o "$WORK/kguard" 2>"$WORK/kguard.log" || { echo "FAIL: helper kguard"; cat "$WORK/kguard.log"; exit 1; }

KVK_DOWN=125; KVK_RIGHT=124; KVK_ESC=53; KVK_R=15; KVK_RBRACKET=30; KVK_LBRACKET=33

echo "building…"
xcodebuild -scheme Kadence -destination 'platform=macOS' build >"$WORK/build.log" 2>&1 || { echo "FAIL: build"; exit 1; }
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/Kadence-*/Build/Products/Debug/Kadence.app | head -1)
STORE="$HOME/Library/Containers/XIX.Kadence/Data/Library/Application Support/default.store"
PID=""

quit_app() { for p in $(pgrep -f "Kadence.app/Contents/MacOS/Kadence"); do kill "$p" 2>/dev/null; done; sleep 2; }
launch() {
  quit_app
  open -n "$APP" --args -ApplePersistenceIgnoreState YES "$@"
  sleep 9
  PID=$(pgrep -f "Kadence.app/Contents/MacOS/Kadence" | head -1)
  [[ -z "$PID" ]] && { echo "FAIL: Kadence did not start"; exit 1; }
  # Poll for the first window (a cold launch has taken ~17s to vend one) and
  # check the resize took: a resize sent before the window exists is silently
  # lost, and every later step looks for the 1500pt-wide window.
  for _ in $(seq 1 15); do
    N=$(osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to count windows" 2>/dev/null)
    [[ "${N:-0}" -ge 1 ]] && break; sleep 2
  done
  osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to set size of window 1 to {1500, 900}" >/dev/null 2>&1
  osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to set position of window 1 to {34, 70}" >/dev/null 2>&1
  sleep 2
  [[ -n "$(window_line 1500)" ]] || { echo "FAIL: the main window is not 1500pt wide — the resize did not take"; quit_app; exit 1; }
  # Park the pointer inside Kadence's own window (P2-F21), so nothing is hovered.
  front; "$WORK/kguard" park "$PID" || { echo "STOP: could not park the pointer inside Kadence."; quit_app; exit 1; }
}
fresh_launch() { quit_app; rm -f "$STORE" "$STORE-wal" "$STORE-shm"; launch "$@"; }

# Kadence must be frontmost before ANY input; re-activated only if it isn't.
front() {
  local cur; cur=$(osascript -e 'tell application "System Events" to get unix id of first process whose frontmost is true' 2>/dev/null)
  if [[ "$cur" != "$PID" ]]; then
    osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $PID) to true" >/dev/null 2>&1
    sleep 0.5
  fi
  local name; name=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)
  [[ "$name" == "Kadence" ]] || { echo "STOP: frontmost is '$name', not Kadence — no input sent."; quit_app; exit 1; }
}
click() { front; "$WORK/kguard" check "$PID" "$1" "$2" || { echo "STOP: a click at $1,$2 would not reach Kadence."; quit_app; exit 1; }; "$WORK/hid" click "$1" "$2"; sleep 1.5; }
key() { front; "$WORK/hid" key "$@"; sleep 1.2; }
scroll() { front; "$WORK/kguard" check "$PID" "$1" "$2" || { echo "STOP: a scroll at $1,$2 would not reach Kadence."; quit_app; exit 1; }; "$WORK/hid" scroll "$1" "$2" "$3"; sleep 1.2; }

# find PATTERN [NTH] → "x y" of the NTH (0-based, left-to-right then top-down)
# element across all windows whose text contains PATTERN (case-insensitive).
find() {
  local i
  for i in 1 2 3; do
    "$WORK/axq" "$PID" > "$WORK/ax.txt"
    python3 - "$WORK/ax.txt" "$1" "${2:-0}" <<'PY' && return 0
import sys
path, pat, nth = sys.argv[1], sys.argv[2].lower(), int(sys.argv[3])
hits = []
for line in open(path).read().splitlines():
    p = line.split("~")
    if len(p) != 9: continue
    x, y, w, h = map(float, p[5:9])
    if pat in " ".join(p[1:5]).lower() and w > 0 and h > 0: hits.append((x, y, w, h))
hits.sort()
if len(hits) <= nth: sys.exit(1)
x, y, w, h = hits[nth]
print(int(x + w / 2), int(y + h / 2))
PY
    sleep 1
  done
  return 1
}
# Via a file, not a pipe: under `set -o pipefail`, `grep -q` exiting on its
# first match kills the writer with SIGPIPE and the pipeline reads as a
# failure — a match reported as "absent" (P2-F20, first run: the template
# conflict was on screen and `has` said no).
has() { "$WORK/axq" "$PID" > "$WORK/has.txt"; grep -qi -- "$1" "$WORK/has.txt"; }

window_line() { "$WORK/wins" | awk -v want="$1" '$6 == 0 && $4 == want { print; exit }'; }
routines_line() { "$WORK/wins" | awk '$6 == 0 && $4 != 1500 { print; exit }'; }
shoot_line() {  # shoot_line "<wins line>" FILE
  [[ -z "$1" ]] && { echo "  (no window for $2)"; return 1; }
  screencapture -x -o -l "$(echo "$1" | cut -d' ' -f1)" "$OUT/$2"; echo "  captured $2"
}
shoot_main() { shoot_line "$(window_line 1500)" "$1-$SUFFIX.png"; }
shoot_routines() { shoot_line "$(routines_line)" "$1-$SUFFIX.png"; }
# The union of every on-screen Kadence window (a system popover included).
shoot_union() {
  local rect; rect=$("$WORK/wins" | python3 -c '
import sys
r = [list(map(int, l.split()[1:5])) for l in sys.stdin if l.strip() and l.split()[3] != "1500"]
x0 = min(a[0] for a in r); y0 = min(a[1] for a in r)
x1 = max(a[0] + a[2] for a in r); y1 = max(a[1] + a[3] for a in r)
print(f"{x0},{y0},{x1 - x0},{y1 - y0}")')
  screencapture -x -R "$rect" "$OUT/$1-$SUFFIX.png"; echo "  captured $1-$SUFFIX.png ($rect)"
}
size_routines() { osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to set size of window 1 to {$1, 900}" >/dev/null 2>&1; sleep 1.5; }
step_until() {  # step_until PATTERN — click `Next conflict` until PATTERN is in the tree
  local n
  for n in $(seq 1 16); do
    has "$1" && return 0
    local xy; xy=$(find "next conflict") || { echo "  no Next conflict button"; return 1; }
    click $xy
  done
  has "$1"
}

# ===================================================================== run
FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

# The canvas's AX value: the element that is not static text, wider than
# 300pt, whose value is a time (`HH:mm`) — or "" when it has none.
canvas_value() {
  "$WORK/axq" "$PID" > "$WORK/cv.txt"
  python3 - "$WORK/cv.txt" <<'PY'
import re, sys
best = ""
for line in open(sys.argv[1]).read().splitlines():
    p = line.split("~")
    if len(p) != 9 or p[0] == "AXStaticText": continue
    if float(p[7]) > 300 and re.fullmatch(r"\d\d:\d\d", p[3]): best = p[3]
print(best)
PY
}
expect_value() {  # expect_value WANT WHAT
  local v; v=$(canvas_value)
  if [[ "$v" == "$1" ]]; then pass "$2 (value '$v')"; else fail "$2 — value '$v', want '$1'"; fi
}
block_titles() {
  "$WORK/axq" "$PID" | grep -E 'Gym|Morning review|Training|Reading|Errands|Lunch walk|New block' | cut -d'~' -f1-3 | sort | md5
}
# The Routines window's screen rect "x y w h" — every lookup below is
# limited to it: the main window, open behind, has its own `Training`,
# hour labels and weekday headers (found live: a block click landed on the
# Routines gutter because the main window's `Training` sorted first).
rw() { routines_line | awk '{print $2, $3, $4, $5}'; }
# A block's centre inside the Routines window, by title (leftmost).
find_block() {
  "$WORK/axq" "$PID" > "$WORK/fb.txt"
  python3 - "$WORK/fb.txt" "$1" $(rw) <<'PY'
import sys
path, pat = sys.argv[1], sys.argv[2].lower()
X, Y, W, H = map(float, sys.argv[3:7])
hits = []
for line in open(path).read().splitlines():
    p = line.split("~")
    if len(p) != 9 or p[0] != "AXButton": continue
    x, y, w, h = map(float, p[5:9])
    if pat in p[2].lower() and w > 0 and X <= x and x + w <= X + W and Y <= y and y + h <= Y + H:
        hits.append((x, y, w, h))
if not hits: sys.exit(1)
x, y, w, h = sorted(hits)[0]
print(int(x + w / 2), int(y + h / 2))
PY
}
# Screen y of an hour line, from its gutter label (drawn at line + 2pt).
hour_line_y() {
  "$WORK/axq" "$PID" > "$WORK/hl.txt"
  python3 - "$WORK/hl.txt" "$1" $(rw) <<'PY'
import sys
X, Y, W, H = map(float, sys.argv[3:7])
for line in open(sys.argv[1]).read().splitlines():
    p = line.split("~")
    if len(p) == 9 and p[0] == "AXStaticText" and (p[1] == sys.argv[2] or p[3] == sys.argv[2]) and float(p[7]) < 80 \
            and X <= float(p[5]) < X + W and Y <= float(p[6]) < Y + H:
        print(int(float(p[6])) - 2); break
PY
}
# Screen x centre of a weekday column, from its header text (e.g. "Tue").
column_x() {
  "$WORK/axq" "$PID" > "$WORK/cx.txt"
  python3 - "$WORK/cx.txt" "$1" $(rw) <<'PY'
import sys
X, Y, W, H = map(float, sys.argv[3:7])
for line in open(sys.argv[1]).read().splitlines():
    p = line.split("~")
    if len(p) == 9 and p[0] == "AXStaticText" and (p[3] or p[1]).strip().lower().startswith(sys.argv[2].lower()) and float(p[8]) < 30 \
            and X <= float(p[5]) < X + W and Y <= float(p[6]) < Y + H:
        print(int(float(p[5]) + float(p[7]) / 2)); break
PY
}
fast_keys() {  # fast_keys CODE N — N presses, Kadence checked frontmost first
  front; local i; for i in $(seq 1 "$2"); do "$WORK/hid" key "$1"; sleep 0.12; done; sleep 1.2
}
KVK_UP=126; KVK_LEFT=123; KVK_TAB=48

echo "run: fresh store — Routines window"
fresh_launch
key $KVK_R cmd opt
sleep 3
size_routines 1400
sleep 1
expect_value "07:00" "open: canvas focused, nothing selected → cursor at 07:00"

key $KVK_TAB
shoot_routines "routines-cursor-tab-inspector"
expect_value "" "⇥ → the inspector: the canvas is not in cursor mode"
key $KVK_TAB
shoot_routines "routines-cursor-tab-canvas"
expect_value "07:00" "⇥ back → the canvas: cursor restored at 07:00"

key $KVK_DOWN
expect_value "07:15" "↓ → 07:15"
key $KVK_UP; key $KVK_UP
expect_value "06:45" "↑ ↑ → 06:45"
key $KVK_LEFT; key $KVK_RIGHT
expect_value "06:45" "← → change nothing"

fast_keys $KVK_UP 32
expect_value "00:00" "↑ to the clamp → 00:00"
shoot_routines "routines-cursor-top"
fast_keys $KVK_DOWN 100
expect_value "23:45" "↓ to the clamp → 23:45"
shoot_routines "routines-cursor-bottom"

BEFORE=$(block_titles)
# Back to the morning: the lines must be on screen to click them.
# 23:45 → 08:45. Not 09:45: a cursor there is within 12pt of 10:00, whose
# gutter label §7 then suppresses — the label this step clicks by.
fast_keys $KVK_UP 60
LINE10=$(hour_line_y "10:00"); MONX=$(column_x "Mon")
if [[ -n "$LINE10" && -n "$MONX" ]]; then
  click "$MONX" $((LINE10 + 3))
  expect_value "10:00" "click on Monday's empty canvas at 10:00 → cursor 10:00"
else fail "could not find the 10:00 line or Monday's column ($LINE10 / $MONX)"; fi
LINE11=$(hour_line_y "11:00"); TUEX=$(column_x "Tue")
if [[ -n "$LINE11" && -n "$TUEX" ]]; then
  click "$TUEX" $((LINE11 + 3))
  expect_value "11:00" "click on Tuesday (inactive) at 11:00 → cursor 11:00"
else fail "could not find the 11:00 line or Tuesday's column ($LINE11 / $TUEX)"; fi
AFTER=$(block_titles)
[[ "$BEFORE" == "$AFTER" ]] && pass "no block created by either click" || fail "the block set changed after the clicks"

key $KVK_ESC
expect_value "" "⎋ in cursor mode → the canvas is unfocused"

XY=$(find_block "Training") || XY=""
if [[ -n "$XY" ]]; then
  click $XY
  expect_value "" "click Training → selection mode (no cursor)"
  key $KVK_ESC
  expect_value "11:00" "⎋ from selection → cursor mode, last time restored"
  XY=$(find_block "Training")
  click $XY
  expect_value "" "click Training again → selection mode"
  key $KVK_RBRACKET cmd
  expect_value "11:00" "⌘] drops the selection, canvas focused → cursor mode"
  shoot_routines "routines-cursor-windows-mode"
  key $KVK_LBRACKET cmd
else fail "no Training block in the tree"; fi

quit_app
echo "frames: $OUT"
if [[ $FAILS -eq 0 ]]; then echo "check-routines-cursor: PASS"; exit 0; fi
echo "check-routines-cursor: FAIL ($FAILS)"; exit 1
