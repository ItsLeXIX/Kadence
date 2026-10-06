#!/bin/bash
#
# check-resync-escape.sh — task P2-B2: components.md §13.4 (amended
# 2026-10-06, G-040; DEVIATIONS B34). `⎋` dismisses the Routines window's
# Re-sync popover wherever focus is inside it, writes nothing, and focus
# returns to `Re-sync`; `↩` still re-syncs. A regression check so B34 can't
# come back.
#
# Same method and helpers as capture-p2f20.sh (copied from it): a fresh
# store, the pre-flight (refuses if the screen is locked or any app is in
# full screen), real HID input sent only while Kadence is frontmost, every
# click through Scripts/lib/kadence-guard.swift, the tree read through the
# AX API.
#
# Steps: detach three `Morning review` instances on the main grid (⌥↓, as
# item 5's capture does) → ⌘⌥R → click `Re-sync`:
#   1. ⎋ with focus where the click left it (the default button) → popover
#      gone, `3 instances edited` still shown, focus on `Re-sync`;
#   2. reopen, click a date row inside the popover, ⎋ → gone, still 3;
#   3. reopen, ↩ → re-synced (the count row is gone).
#
# Usage: Scripts/check-resync-escape.sh
set -uo pipefail
cd "$(dirname "$0")/.."
SUFFIX="unused"

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


# focused element of the app: role~title~desc, then (stderr-free) detail
# for the log: value, frame, the focused window's title, the parent roles.
cat > "$WORK/focus.swift" <<'SWIFT'
import ApplicationServices
let app = AXUIElementCreateApplication(pid_t(CommandLine.arguments[1])!)
func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v }
func s(_ o: AnyObject?) -> String { o.map { "\($0)" } ?? "" }
guard let f = attr(app, "AXFocusedUIElement") else { print("none"); exit(0) }
let e = f as! AXUIElement
var p = CGPoint.zero, z = CGSize.zero
if let v = attr(e, "AXPosition") { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
if let v = attr(e, "AXSize") { AXValueGetValue(v as! AXValue, .cgSize, &z) }
var chain: [String] = []
var cur: AXUIElement? = e
for _ in 0..<6 { guard let c = cur, let par = attr(c, "AXParent") else { break }; let pe = par as! AXUIElement; chain.append(s(attr(pe, "AXRole"))); cur = pe }
let win = attr(app, "AXFocusedWindow").map { s(attr($0 as! AXUIElement, "AXTitle")) } ?? ""
print([s(attr(e, "AXRole")), s(attr(e, "AXTitle")), s(attr(e, "AXDescription"))].joined(separator: "~")
      + "  [value '\(s(attr(e, "AXValue")))' at \(Int(p.x)),\(Int(p.y)) \(Int(z.width))x\(Int(z.height)); window '\(win)'; parents \(chain.joined(separator: ">"))]")
SWIFT
swiftc -O "$WORK/focus.swift" -o "$WORK/focus" 2>"$WORK/focus.log" || { echo "FAIL: helper focus"; cat "$WORK/focus.log"; exit 1; }
KVK_RETURN=36

fail() { echo "FAIL: $1"; quit_app; exit 1; }

# "Focus returns to Re-sync" is only observable with macOS keyboard
# navigation on (System Settings › Keyboard; `AppleKeyboardUIMode` bit 2):
# with it off, buttons never take key focus — ⇥ visits only the canvas and
# the weekday toggle row (P2-B2, measured live). This script reads the
# setting (never writes it) and asserts accordingly: on → the focused element
# after ⎋ is the Re-sync button; off → focus is back on the element that had
# it before the popover opened (nothing lost to the closed popover).
KBNAV=$(( $(defaults read -g AppleKeyboardUIMode 2>/dev/null || echo 0) & 2 ))
echo "keyboard navigation: $([[ $KBNAV -ne 0 ]] && echo on || echo off)"
fresh_launch
DET=0
for page in 0 1; do
  while [[ $DET -lt 3 ]]; do
    XY=$(find "morning review, 08:15") || break
    click $XY
    key $KVK_DOWN opt
    DET=$((DET + 1))
  done
  [[ $DET -ge 3 ]] && break
  key $KVK_RIGHT cmd
done
[[ $DET -eq 3 ]] || fail "could only detach $DET Morning review instances"
echo "detached 3 Morning review instances"

key $KVK_R cmd opt
sleep 2
size_routines 1400
has "3 instances edited" || fail "the Routines inspector doesn't show '3 instances edited'"

popover_open() { has "re-sync 3 instances"; }
open_popover() {
  local xy; xy=$(find "re-sync") || fail "no Re-sync button"
  click $xy; sleep 1
  popover_open || fail "clicking Re-sync didn't open the popover"
}

# 1. ⎋ with focus on the default button.
BEFORE=$("$WORK/focus" "$PID")
echo "before opening, focus: $BEFORE"
open_popover
echo "popover open; focus: $("$WORK/focus" "$PID")"
key $KVK_ESC; sleep 1
popover_open && fail "⎋ left the popover open (B34)"
has "3 instances edited" || fail "⎋ wrote something: '3 instances edited' is gone"
FOCUS=$("$WORK/focus" "$PID")
echo "after ⎋, focus: $FOCUS"
if [[ $KBNAV -ne 0 ]]; then
  [[ "$FOCUS" == "AXButton~Re-sync~"* ]] || fail "focus is not on the Re-sync button after ⎋ ($FOCUS)"
  echo "PASS: ⎋ closed the popover, nothing written, focus on Re-sync."
else
  [[ "$FOCUS" == "$BEFORE" ]] || fail "focus after ⎋ isn't where it was before the popover opened ($FOCUS)"
  echo "PASS: ⎋ closed the popover, nothing written, focus back where it was (keyboard navigation off: buttons can't hold focus, so Re-sync can't be checked)."
fi

# 2. ⎋ after clicking inside the popover's date list.
open_popover
"$WORK/axq" "$PID" > "$WORK/ax.txt"
XY=$(python3 - "$WORK/ax.txt" <<'PY'
import re, sys
rows, button = [], None
for line in open(sys.argv[1]).read().splitlines():
    p = line.split("~")
    if len(p) != 9: continue
    x, y, w, h = map(float, p[5:9])
    if p[0] == "AXButton" and "re-sync 3 instances" in " ".join(p[1:5]).lower(): button = (x, y, w, h)
    text = p[3] or p[1]
    if p[0] == "AXStaticText" and re.fullmatch(r"(Mon|Tue|Wed|Thu|Fri|Sat|Sun) \d{1,2}", text.strip()) and w > 0:
        rows.append((x, y, w, h))
if not button: sys.exit(1)
bx, by, bw, bh = button
# A date row in the popover: above its button, within the popover's width.
near = [r for r in rows if r[1] < by and by - r[1] < 200 and abs(r[0] - bx) < 120]
if not near: sys.exit(1)
x, y, w, h = min(near, key=lambda r: by - r[1])
print(int(x + w / 2), int(y + h / 2))
PY
) || fail "no date row found inside the popover"
click $XY; sleep 1
popover_open || fail "clicking a date row closed the popover (can't test ⎋ from there)"
echo "clicked a date row inside the popover; focus: $("$WORK/focus" "$PID")"
key $KVK_ESC; sleep 1
popover_open && fail "⎋ after a click in the date list left the popover open"
has "3 instances edited" || fail "⎋ wrote something: '3 instances edited' is gone"
echo "PASS: ⎋ from inside the date list closed it, nothing written."

# 3. ↩ still re-syncs.
open_popover
key $KVK_RETURN; sleep 2
popover_open && fail "↩ left the popover open"
has "instances edited" && fail "↩ didn't re-sync: the count row is still there"
echo "PASS: ↩ re-synced (the count row is gone)."
quit_app
echo "PASS: check-resync-escape — ⎋ dismisses the Re-sync popover (§13.4, G-040)."
