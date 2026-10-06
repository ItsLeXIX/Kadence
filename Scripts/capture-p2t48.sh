#!/bin/bash
#
# capture-p2t48.sh — components.md §17 items 4, 5, 6/7, 13, 14, 15, 16, 17, 18
# into screenshots/2/*-p2t48.png (task P2-T48).
#
# Same method as the earlier batches: a fresh store each run (deleted, so
# MockData reseeds relative to today), real HID clicks and keys sent ONLY
# while Kadence is frontmost (checked before every event), the tree read
# through the AX API (System Events can't read SwiftUI names on macOS 26.6,
# STATUS.md §41), and `screencapture -l` of the window's own id, or `-R` of
# its real bounds when a popover hangs off it. Items 11 and 12 are NOT here:
# they need fixed clock times and the popover, which is rendered by
# KadenceTests/PopoverCaptureTests.swift instead (screenshots/2/INDEX.md).
#
# Runs:
#   1. fresh store              → 5 (three detached instances, one selected),
#                                 4 (Re-sync popover), 13 (wide + 780pt),
#                                 14 (Windows mode), 15 (Errands selected)
#   2. -KadenceConflictUnderTest "Supervisor meeting"
#                               → 6/7 (three options, chip on row 2), 18 (skip focused)
#   3. -KadenceConflictUnderTest "Errands"
#                               → 16 (template panel, Routines window)
#   4. store edited: Training ±15, Supervisor meeting 16:45–18:45
#                               → 17 (single option, no chip)
#
# Usage: Scripts/capture-p2t48.sh [OUTDIR]   (default screenshots/2)
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-screenshots/2}"
mkdir -p "$OUT"

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
// khid click X Y | khid key CODE [cmd] [opt] [shift]
let a = CommandLine.arguments
let src = CGEventSource(stateID: .hidSystemState)
switch a[1] {
case "click":
    let pt = CGPoint(x: Double(a[2])!, y: Double(a[3])!)
    CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(150_000)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(60_000)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
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
default: exit(2)
}
SWIFT
cat > "$WORK/axq.swift" <<'SWIFT'
import ApplicationServices
import Foundation
// axq PID [windowIndex]: role~title~desc~value~help~x~y~w~h for every element of that window
let pid = pid_t(CommandLine.arguments[1])!
let index = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 0
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
        let line = [str(attr(c, "AXRole")), str(attr(c, "AXTitle")), desc, val, str(attr(c, "AXHelp")),
                    "\(Int(p.x))", "\(Int(p.y))", "\(Int(s.width))", "\(Int(s.height))"].joined(separator: "~")
        print(line)
        walk(c, d + 1)
    }
}
let windows = (attr(app, "AXWindows") as? [AXUIElement]) ?? []
if index < windows.count { walk(windows[index], 0) }
SWIFT
cat > "$WORK/wins.swift" <<'SWIFT'
import CoreGraphics
// wins: id x y w h for Kadence's onscreen layer-0 windows
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w[kCGWindowOwnerName as String] as? String) == "Kadence" && (w[kCGWindowLayer as String] as? Int) == 0 {
    let b = w[kCGWindowBounds as String] as! [String: Any]
    print(w[kCGWindowNumber as String]!, Int(b["X"] as! Double), Int(b["Y"] as! Double), Int(b["Width"] as! Double), Int(b["Height"] as! Double))
}
SWIFT
for t in hid axq wins; do
  swiftc -O "$WORK/$t.swift" -o "$WORK/$t" 2>"$WORK/$t.log" || { echo "FAIL: helper $t"; cat "$WORK/$t.log"; exit 1; }
done
# P2-F21: every pointer event goes through this guard (Scripts/lib/kadence-guard.swift):
# it is sent only if Kadence is frontmost AND the window under the point is Kadence's.
swiftc -O Scripts/lib/kadence-guard.swift -o "$WORK/kguard" 2>"$WORK/kguard.log" || { echo "FAIL: helper kguard"; cat "$WORK/kguard.log"; exit 1; }

KVK_RETURN=36; KVK_DOWN=125; KVK_ESC=53; KVK_R=15; KVK_RBRACKET=30; KVK_LBRACKET=33

echo "building…"
xcodebuild -scheme Kadence -destination 'platform=macOS' build >"$WORK/build.log" 2>&1 || { echo "FAIL: build"; exit 1; }
APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/Kadence-*/Build/Products/Debug/Kadence.app | head -1)
STORE_DIR="$HOME/Library/Containers/XIX.Kadence/Data/Library/Application Support"
STORE="$STORE_DIR/default.store"
PID=""

quit_app() { for p in $(pgrep -f "Kadence.app/Contents/MacOS/Kadence"); do kill "$p" 2>/dev/null; done; sleep 2; }

launch() {   # launch [extra args…]
  quit_app
  open -n "$APP" --args -ApplePersistenceIgnoreState YES "$@"
  sleep 9
  PID=$(pgrep -f "Kadence.app/Contents/MacOS/Kadence" | head -1)
  [[ -z "$PID" ]] && { echo "FAIL: Kadence did not start"; exit 1; }
  osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to set size of window 1 to {1500, 900}" >/dev/null 2>&1
  osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to set position of window 1 to {34, 70}" >/dev/null 2>&1
  sleep 2
  # Park the pointer inside Kadence's own window, so nothing is hovered at
  # baseline (P2-F21; was a click at screen 5,5 — the menu bar, outside Kadence).
  front; "$WORK/kguard" park "$PID" || { echo "STOP: could not park the pointer inside Kadence."; quit_app; exit 1; }
}

fresh_launch() { quit_app; rm -f "$STORE" "$STORE-wal" "$STORE-shm"; launch "$@"; }

# Kadence must be frontmost before ANY click or key; otherwise stop.
front() {
  osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $PID) to true" >/dev/null 2>&1
  sleep 0.5
  local name
  name=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)
  [[ "$name" == "Kadence" ]] || { echo "STOP: frontmost is '$name', not Kadence — no input sent."; quit_app; exit 1; }
}
click() { front; "$WORK/kguard" check "$PID" "$1" "$2" || { echo "STOP: a click at $1,$2 would not reach Kadence."; quit_app; exit 1; }; "$WORK/hid" click "$1" "$2"; sleep 1.5; }
key() { front; "$WORK/hid" key "$@"; sleep 1.2; }

# find WINDOWINDEX PATTERN [NTH] → "x y" centre of the NTH (0-based) element
# whose text (title/desc/value/help, lower-cased) contains PATTERN, ordered
# left-to-right then top-to-bottom.
find() {
  "$WORK/axq" "$PID" "$1" > "$WORK/ax.txt"
  python3 - "$WORK/ax.txt" "$2" "${3:-0}" <<'PY'
import sys
path, pat, nth = sys.argv[1], sys.argv[2].lower(), int(sys.argv[3])
hits = []
for line in open(path).read().splitlines():
    p = line.split("~")
    if len(p) != 9: continue
    blob = " ".join(p[1:5]).lower()
    x, y, w, h = map(float, p[5:9])
    if pat in blob and w > 0 and h > 0: hits.append((x, y, w, h))
hits.sort()
if len(hits) <= nth: sys.exit(1)
x, y, w, h = hits[nth]
print(int(x + w / 2), int(y + h / 2))
PY
}

# Window id/bounds by exact width: the main window is sized 1500 wide, the
# Routines window 1400 (or 780 for item 13's narrow shot), so a popover's
# own small window can never be mistaken for either.
MAIN_W=1500; ROUTINES_W=1400
window_line() {
  local want; case "$1" in main) want=$MAIN_W ;; routines) want=$ROUTINES_W ;; *) want=$1 ;; esac
  "$WORK/wins" | awk -v want="$want" '$4 == want { print; exit }'
}
size_front() { osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to set size of window 1 to {$1, 900}" >/dev/null 2>&1; sleep 1.5; }
shoot_window() {  # shoot_window main|routines FILE
  local line; line=$(window_line "$1")
  [[ -z "$line" ]] && { echo "  (no $1 window to capture for $2)"; return 1; }
  screencapture -x -o -l "$(echo "$line" | cut -d' ' -f1)" "$OUT/$2"
  echo "  captured $2"
}

# ===================================================================== run 1
echo "run 1: fresh store"
fresh_launch
# Item 5 — three detached instances: Morning review on three days, each
# selected and moved 15 min with ⌥↓ (interactions.md §2), which detaches it.
for n in 0 1 2; do
  XY=$(find 0 "morning review ·" "$n") || { echo "  morning review #$n not found"; continue; }
  click $XY
  key $KVK_DOWN opt
done
shoot_window main "detached-instance-inspector-p2t48.png"

# Item 4 — the Routines window, nothing selected: the count and Re-sync.
key $KVK_R cmd opt
sleep 2
size_front $ROUTINES_W
# The popover shows inside the window capture. A click on the inspector's
# template title closes it (it is transient) without selecting anything.
XY=$(find 0 "re-sync") && { click $XY; sleep 1; shoot_window routines "resync-popover-p2t48.png"
  XY=$(find 0 "daily routine" 1) && click $XY; } || echo "  Re-sync button not found"

# Item 13 — Blocks mode, wide and at size.routineEditorMinWidth (780).
shoot_window routines "inactive-weekdays-wide-p2t48.png"
size_front 780
shoot_window 780 "inactive-weekdays-780-p2t48.png"
size_front $ROUTINES_W

# Item 14 — Windows mode (⌘]).
key $KVK_RBRACKET cmd
shoot_window routines "inactive-weekdays-windows-mode-p2t48.png"
key $KVK_LBRACKET cmd

# Item 15 — Errands selected: conflicted in Mon/Wed/Fri + "Will not run —".
XY=$(find 0 "errands ·") && { click $XY; shoot_window routines "routine-refusal-errands-p2t48.png"; } \
  || echo "  Errands block not found"

# ===================================================================== run 2
echo "run 2: Training × Supervisor meeting"
fresh_launch -KadenceConflictUnderTest "Supervisor meeting"
XY=$(find 0 "id:needs-attention-row") || { echo "  needs-attention row not found"; exit 1; }
click $XY
shoot_window main "conflict-panel-three-options-p2t48.png"
XY=$(find 0 "skip training today") && { click $XY; shoot_window main "conflict-skip-today-preview-p2t48.png"; } \
  || echo "  skip row not found"

# ===================================================================== run 3
echo "run 3: Errands × Lunch (template conflict)"
fresh_launch -KadenceConflictUnderTest "Errands"
XY=$(find 0 "id:needs-attention-row") || { echo "  needs-attention row not found"; exit 1; }
click $XY
sleep 3
size_front $ROUTINES_W
shoot_window routines "template-conflict-panel-p2t48.png"
key $KVK_DOWN
shoot_window routines "template-conflict-preview-p2t48.png"

# ===================================================================== run 4
echo "run 4: single option (Training ±15, Supervisor meeting 16:45–18:45)"
quit_app
sqlite3 "$STORE" "UPDATE ZROUTINEBLOCK SET ZSHIFTABLEMINUTES = 15 WHERE ZTITLE = 'Training';
                  UPDATE ZEVENT SET ZSTART = ZSTART - 2700, ZEND = ZEND + 1800 WHERE ZTITLE = 'Supervisor meeting';" \
  || { echo "  sqlite edit failed"; exit 1; }
launch -KadenceConflictUnderTest "Supervisor meeting"
XY=$(find 0 "id:needs-attention-row") || { echo "  needs-attention row not found"; exit 1; }
click $XY
shoot_window main "conflict-single-option-p2t48.png"

quit_app
echo "done"
