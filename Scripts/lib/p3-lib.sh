#!/bin/bash
#
# p3-lib.sh — helpers for the Phase 3 capture script (sourced, not run).
# Copied from check-resync-escape.sh: the same HID sender, AX reader, window
# lister and focus reader, and every pointer event through
# Scripts/lib/kadence-guard.swift (P2-F21). Nothing here is sent to any app
# but Kadence: `front` refuses to send keys unless Kadence is frontmost, and
# `click` asks the guard first.
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
case "type":
    // Types a string as Unicode key events (layout-independent).
    for scalar in a[2].unicodeScalars {
        var unit = Array(String(scalar).utf16)
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: down)!
            e.keyboardSetUnicodeString(stringLength: unit.count, unicodeString: &unit)
            e.flags = []
            e.post(tap: .cghidEventTap)
            usleep(15_000)
        }
    }
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

APP_STORE="$HOME/Library/Containers/XIX.Kadence/Data/Library/Application Support/default.store"
PID=""
quit_app() { for p in $(pgrep -f "Kadence.app/Contents/MacOS/Kadence"); do kill "$p" 2>/dev/null; done; sleep 2; }
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
find_el() {
  local i
  for i in 1 2 3; do
    "$WORK/axq" "$PID" > "$WORK/ax.txt"
    python3 - "$WORK/ax.txt" "$1" "${2:-0}" <<'PY2' && return 0
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
PY2
    sleep 1
  done
  return 1
}
has() { "$WORK/axq" "$PID" > "$WORK/has.txt"; grep -qi -- "$1" "$WORK/has.txt"; }
# launch ARGS… — a fresh store, then Kadence with the given arguments.
launch_fresh() {
  quit_app
  rm -f "$APP_STORE" "$APP_STORE-wal" "$APP_STORE-shm"
  open -n "$APP" --args -ApplePersistenceIgnoreState YES "$@"
  sleep 9
  PID=$(pgrep -f "Kadence.app/Contents/MacOS/Kadence" | head -1)
  [[ -z "$PID" ]] && { echo "FAIL: Kadence did not start"; exit 1; }
  for _ in $(seq 1 15); do
    N=$(osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to count windows" 2>/dev/null)
    [[ "${N:-0}" -ge 1 ]] && break; sleep 2
  done
  osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to set size of window 1 to {1500, 900}" >/dev/null 2>&1
  osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to set position of window 1 to {34, 70}" >/dev/null 2>&1
  sleep 2
  front; "$WORK/kguard" park "$PID" || { echo "STOP: could not park the pointer inside Kadence."; quit_app; exit 1; }
}
# window_id WIDTH — the id of Kadence's on-screen normal window that wide (or the first non-main one with "other").
window_id() {
  "$WORK/wins" | awk -v want="$1" '$6 == 0 && (want == "other" ? $4 != 1500 : $4 == want) { print $1; exit }'
}
shoot_window() {  # shoot_window ID FILE
  [[ -z "$1" ]] && { echo "  (no window for $2)"; return 1; }
  screencapture -x -o -l "$1" "$OUT/$2"; echo "  captured $2"
}

type_text() { front; "$WORK/hid" type "$1"; sleep 0.8; }
# The id of Kadence's on-screen window with this exact width (the sheet: 440).
window_of_width() { "$WORK/wins" | awk -v want="$1" '$4 == want { print $1; exit }'; }
