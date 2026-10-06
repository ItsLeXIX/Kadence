#!/bin/bash
#
# capture-p2f20.sh — PHASE2-REVIEW.md §6 item 20: recapture components.md §17
# items 1, 4, 5, 6 (both halves), 7, 8 (both halves), 13 (wide + 780), 14, 15,
# 16, 17, 18 into screenshots/2/*-p2f20.png. Item 11's four frames are
# offscreen renders (KadenceTests/PopoverCaptureTests.swift); items 9, 10 and
# 12 are not recaptured (review §6 item 20).
#
# Method (components.md §17.2): a fresh store per run (MockData reseeds
# relative to today), real HID input sent ONLY while Kadence is frontmost
# (checked before every event), the tree read through the AX API, and
# `screencapture -l` of a window's own id — or `-R` of the union of
# Kadence's on-screen windows when a system popover hangs off one (item 4:
# a popover is its own window, so `-l` alone can't show it).
#
# Conflicts are reached by STEPPING with the footer's `Next conflict` button
# (layouts.md §10), never by -KadenceConflictUnderTest. Activation focuses
# the recommended option and scrolls the conflict into view
# (interactions.md §10.1), so no extra click is needed for that.
#
# Differences from capture-p2t48.sh: no click at screen (5,5) before launch
# (it lands outside Kadence); the frontmost check re-activates Kadence only
# when it isn't already frontmost (re-activating raised the main window over
# the Routines window); mouse events carry empty modifier flags.
#
# Written during P2-F20 while the screen was locked; first run 2026-10-06
# (STATUS §79), which fixed: the item-5 loop, `has` under pipefail, the
# Re-sync popover left open (B34), duplicate frames for items 7/8. Still:
# check every frame by eye before indexing it.
#
# Usage: Scripts/capture-p2f20.sh [OUTDIR]   (default screenshots/2)
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-screenshots/2}"
mkdir -p "$OUT"
SUFFIX="p2f20"

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

# ===================================================================== run A
echo "run A: fresh store — items 5, 4, 1, 13, 14, 15"
fresh_launch
# Item 5: three Morning reviews moved with ⌥↓ (detaches them); the last
# stays selected — the item asks for a selected detached instance. Always
# the first instance still at 08:15 (a moved one reads 08:30); when this week
# runs out (instances exist from today on, so a late weekday has fewer than
# three), page to next week with ⌘→. (P2-F20, first run: the old loop took
# the n-th 08:15 and missed after the first move.)
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
echo "  detached $DET Morning review instances"
shoot_main "detached-instance-inspector"

key $KVK_R cmd opt
sleep 2
size_routines 1400
# Item 4: nothing selected, the count and the Re-sync popover (its own window).
# The popover must be gone before the next frame. (P2-F20, first runs:
# item 13's wide frame caught it in its inactive look — ⎋ hadn't closed it.
# It isn't a separate entry in CGWindowList here, so its own default button
# in the AX tree is what says it's open.) ⎋ first; if it's still there, a
# click on the inspector's static "Daily routine" heading — inside Kadence,
# no action of its own — which closes a transient popover.
popover_open() { has "re-sync 3 instances"; }
XY=$(find "re-sync") && { click $XY; sleep 1; shoot_union "resync-popover"; } || echo "  Re-sync not found"
if popover_open; then
  key $KVK_ESC; sleep 1
  if popover_open; then
    echo "  ⎋ left the popover open; clicking the inspector heading"
    "$WORK/axq" "$PID" > "$WORK/ax.txt"
    # The rightmost static text that is exactly "Daily routine": the Routines
    # inspector's heading (the picker and the main window's sidebar row are
    # further left, and the picker would open a menu).
    XY=$(python3 - "$WORK/ax.txt" <<'PY2'
import sys
hits = []
for line in open(sys.argv[1]).read().splitlines():
    p = line.split("~")
    if len(p) == 9 and p[0] == "AXStaticText" and "Daily routine" in (p[1], p[3]):
        x, y, w, h = map(float, p[5:9])
        if w > 0 and h > 0: hits.append((x, y, w, h))
if not hits: sys.exit(1)
x, y, w, h = max(hits)
print(int(x + w / 2), int(y + h / 2))
PY2
) && click $XY
    sleep 1
  fi
  popover_open && { echo "STOP: the Re-sync popover would not close"; quit_app; exit 1; }
  echo "  popover closed"
fi

# Item 13: Blocks mode, nothing selected, wide and at 780.
shoot_routines "inactive-weekdays-wide"
size_routines 780
shoot_routines "inactive-weekdays-780"
size_routines 1400

# Item 14 (also items 2 and 3's Windows half): Windows mode.
key $KVK_RBRACKET cmd
shoot_routines "inactive-weekdays-windows-mode"
key $KVK_LBRACKET cmd

# Item 1: Gym 07:00, Morning review 08:15 and Reading 21:00 in one frame —
# scroll the canvas down six hours (6 × 44pt).
LINE=$(routines_line); RX=$(echo "$LINE" | cut -d' ' -f2); RY=$(echo "$LINE" | cut -d' ' -f3)
scroll $((RX + 300)) $((RY + 400)) -264
shoot_routines "routine-template-flexibility"
scroll $((RX + 300)) $((RY + 400)) 264

# Item 15: Errands selected (the item asks for its inspector line).
XY=$(find "errands, 12:30") && { click $XY; shoot_routines "routine-refusal-errands"; } || echo "  Errands not found"

# ===================================================================== run B
echo "run B: stepping with the footer — items 6, 7, 8, 18, 16"
fresh_launch
XY=$(find "id:needs-attention-row") || { echo "  needs-attention row not found"; quit_app; exit 1; }
click $XY
sleep 2
# Walk the list once, 1 → N, with `Next conflict`, capturing each frame when
# its conflict comes up — the order depends on today's weekday, so no
# conflict is assumed to come before another.
GOT_TWO=0; GOT_THREE=0
for n in $(seq 1 16); do
  # Item 6, two-option half: Focus review × Client call.
  if [[ $GOT_TWO -eq 0 ]] && has "shorten focus review"; then
    shoot_main "conflict-panel-two-options"; GOT_TWO=1
  fi
  # Items 6 (three options), 7 (chip on row 2), 8 (preview active, row 2
  # focused, block in view) and 18 (the skip row focused): Training ×
  # Supervisor meeting.
  # (One frame serves 6, 7 and 8: activation already focuses and previews
  # the recommended row 2, so a second "preview" capture would be the same.)
  if [[ $GOT_THREE -eq 0 ]] && has "shift training 75 min later"; then
    shoot_main "conflict-panel-three-options"
    XY=$(find "skip training today") && { click $XY; shoot_main "conflict-skip-today-preview"; }
    GOT_THREE=1
  fi
  # Item 16 and item 8's Routines half: past the last day conflict the
  # Routines window opens on the template conflict, recommendation focused
  # and previewed.
  if has "remove errands from this routine"; then
    sleep 3
    size_routines 1400
    shoot_routines "template-conflict-panel"   # also item 8's Routines half
    break
  fi
  echo "  step $n: $("$WORK/axq" "$PID" | grep -oE 'Conflict [0-9]+ of [0-9]+' | sort -u | tr '\n' ' ')"
  XY=$(find "next conflict") || { echo "  no Next conflict button"; break; }
  click $XY
done

# ===================================================================== run C
echo "run C: single option — item 17 (Training ±15, Supervisor 16:45–18:45)"
quit_app
sqlite3 "$STORE" "UPDATE ZROUTINEBLOCK SET ZSHIFTABLEMINUTES = 15 WHERE ZTITLE = 'Training';
                  UPDATE ZEVENT SET ZSTART = ZSTART - 2700, ZEND = ZEND + 1800 WHERE ZTITLE = 'Supervisor meeting';" \
  || { echo "  sqlite edit failed"; exit 1; }
launch
XY=$(find "id:needs-attention-row") || { echo "  needs-attention row not found"; quit_app; exit 1; }
click $XY
sleep 2
step_until "skip training today" && shoot_main "conflict-single-option"

quit_app
echo "done"
