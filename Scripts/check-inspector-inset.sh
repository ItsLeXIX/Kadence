#!/bin/bash
#
# check-inspector-inset.sh — task P2-F02 (DEVIATIONS B20; layouts.md §6 and
# components.md §14.2, both amended 2026-10-05).
#
# Asserts, live, in the main window at 1500pt (inspector docked):
#   1. the canvas (its scroll area, scroller included) ends at or before the
#      inspector's leading edge — nothing is drawn over the inspector;
#   2. every text and button in the inspector starts ≥ spacing.xl (16) inside its leading
#      edge and ends ≥ 16 inside its trailing edge;
#   3. no full-height focus-ring line is drawn at the canvas/inspector boundary
#      (pixel check of a window capture);
# first with a block selected (ordinary mode), then in conflict mode (the
# needs-attention row).
#
# Input goes ONLY to Kadence, after a frontmost check before every event.
# Usage: Scripts/check-inspector-inset.sh
set -uo pipefail
cd "$(dirname "$0")/.."

LOCK_STATE=$(swift -e '
  import CoreGraphics
  import Foundation
  if let d = CGSessionCopyCurrentDictionary() as NSDictionary? { print((d["CGSSessionScreenIsLocked"] as? Int) ?? 0) } else { print(0) }
' 2>/dev/null)
[[ "$LOCK_STATE" == "1" ]] && { echo "SKIP: screen is locked."; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
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
let index = CommandLine.arguments.count > 2 ? (CommandLine.arguments[2] == "main" ? -1 : Int(CommandLine.arguments[2])!) : 0
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
// Index -1 (or "main") = the window with the largest area: AXWindows' order
// changes between launches, so a fixed index can land on a popover or the
// Routines window.
func area(_ w: AXUIElement) -> CGFloat {
    var s = CGSize.zero
    if let sv = attr(w, "AXSize") { AXValueGetValue(sv as! AXValue, .cgSize, &s) }
    return s.width * s.height
}
if index < 0, let biggest = windows.max(by: { area($0) < area($1) }) { walk(biggest, 0) }
else if index >= 0 && index < windows.count { walk(windows[index], 0) }
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

echo "building…"
xcodebuild -scheme Kadence -destination 'platform=macOS' build >"$WORK/build.log" 2>&1 || { echo "FAIL: build"; exit 1; }
APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/Kadence-*/Build/Products/Debug/Kadence.app | head -1)
STORE="$HOME/Library/Containers/XIX.Kadence/Data/Library/Application Support/default.store"
quit_app() { for p in $(pgrep -f "Kadence.app/Contents/MacOS/Kadence"); do kill "$p" 2>/dev/null; done; sleep 2; }
quit_app; rm -f "$STORE" "$STORE-wal" "$STORE-shm"
open -n "$APP" --args -ApplePersistenceIgnoreState YES
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
"$WORK/wins" | awk '$4 == 1500 { f = 1 } END { exit !f }' || { echo "FAIL: the main window is not 1500pt wide — the resize did not take"; quit_app; exit 1; }

front() {
  osascript -e "tell application \"System Events\" to set frontmost of (first process whose unix id is $PID) to true" >/dev/null 2>&1
  sleep 0.5
  local name; name=$(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)
  [[ "$name" == "Kadence" ]] || { echo "STOP: frontmost is '$name', not Kadence — no input sent."; quit_app; exit 1; }
}
click() { front; "$WORK/kguard" check "$PID" "$1" "$2" || { echo "STOP: a click at $1,$2 would not reach Kadence."; quit_app; exit 1; }; "$WORK/hid" click "$1" "$2"; sleep 1.5; }
find() {  # find PATTERN → "x y" of the first (leftmost) element whose text contains PATTERN
  "$WORK/axq" "$PID" main > "$WORK/ax.txt"
  python3 - "$WORK/ax.txt" "$1" <<'PY'
import sys
hits = []
for line in open(sys.argv[1]).read().splitlines():
    p = line.split("~")
    if len(p) != 9: continue
    x, y, w, h = map(float, p[5:9])
    if sys.argv[2].lower() in " ".join(p[1:5]).lower() and w > 0 and h > 0: hits.append((x, y, w, h))
hits.sort()
if not hits: sys.exit(1)
x, y, w, h = hits[0]; print(int(x + w / 2), int(y + h / 2))
PY
}

FAILS=0
check() {  # check LABEL
  "$WORK/axq" "$PID" main > "$WORK/ax-$1.txt"
  local wid; wid=$("$WORK/wins" | awk '$4 == 1500 { print $1; exit }')
  screencapture -x -o -l "$wid" "$WORK/shot-$1.png"
  python3 - "$WORK/ax-$1.txt" "$WORK/shot-$1.png" "$1" <<'PY' || FAILS=$((FAILS + 1))
import sys, struct, zlib
ax, shot, label = sys.argv[1:4]
rows = []
for line in open(ax).read().splitlines():
    p = line.split("~")
    if len(p) != 9: continue
    try: x, y, w, h = map(float, p[5:9])
    except ValueError: continue
    rows.append(dict(role=p[0], text=" ".join(p[1:5]).strip(), x=x, y=y, w=w, h=h))
areas = sorted([r for r in rows if r["role"] == "AXScrollArea" and r["w"] > 300], key=lambda r: r["x"])
if len(areas) < 2:
    print(f"FAIL [{label}]: expected canvas + inspector scroll areas, found {len(areas)}"); sys.exit(1)
canvas, insp = areas[-2], areas[-1]
ok = True
cr, ix, ir = canvas["x"] + canvas["w"], insp["x"], insp["x"] + insp["w"]
if cr > ix:
    print(f"FAIL [{label}]: canvas ends at {cr:.0f}, {cr - ix:.0f}pt past the inspector's edge {ix:.0f}"); ok = False
else:
    print(f"ok   [{label}]: canvas ends at {cr:.0f} ≤ inspector edge {ix:.0f}")
texts = [r for r in rows if r["role"] in ("AXStaticText", "AXButton") and 0 < r["w"] < insp["w"]
         and ix <= r["x"] + r["w"] / 2 <= ir and insp["y"] <= r["y"] <= insp["y"] + insp["h"]]
if not texts:
    print(f"FAIL [{label}]: no inspector text found"); ok = False
if label == "conflict" and not any(r["role"] == "AXButton" for r in texts):
    print(f"FAIL [{label}]: the conflict panel's blocks and option rows weren't found"); ok = False
for r in texts:
    if r["x"] < ix + 16 or r["x"] + r["w"] > ir - 16:
        print(f"FAIL [{label}]: '{r['text'][:40]}' at x {r['x']:.0f}…{r['x'] + r['w']:.0f}, inspector {ix:.0f}…{ir:.0f}"); ok = False
first = min(texts, key=lambda r: (r["y"], r["x"])) if texts else None
if first: print(f"     [{label}]: {len(texts)} texts/buttons inside the inset; first '{first['text'][:30]}' at x {first['x']:.0f} (edge + {first['x'] - ix:.0f})")
# Pixel check: a focus-ring-blue column running most of the window's height
# within 6pt of the boundary. PNG decoded with zlib only (no PIL dependency).
def png(path):
    data = open(path, "rb").read(); pos = 8; idat = b""; W = H = 0
    while pos < len(data):
        n, typ = struct.unpack(">I4s", data[pos:pos + 8]); body = data[pos + 8:pos + 8 + n]
        if typ == b"IHDR": W, H, depth, ctype = struct.unpack(">IIBB", body[:10])
        if typ == b"IDAT": idat += body
        pos += 12 + n
    bpp = 4 if ctype == 6 else 3; raw = zlib.decompress(idat); stride = W * bpp; out = []; prev = bytearray(stride); i = 0
    for _ in range(H):
        f = raw[i]; line = bytearray(raw[i + 1:i + 1 + stride]); i += 1 + stride
        for k in range(stride):
            a = line[k - bpp] if k >= bpp else 0; b = prev[k]; c = prev[k - bpp] if k >= bpp else 0
            if f == 1: line[k] = (line[k] + a) & 255
            elif f == 2: line[k] = (line[k] + b) & 255
            elif f == 3: line[k] = (line[k] + (a + b) // 2) & 255
            elif f == 4:
                pa, pb, pc = abs(b - c), abs(a - c), abs(a + b - 2 * c)
                line[k] = (line[k] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        out.append(bytes(line)); prev = line
    return W, H, bpp, out
W, H, bpp, px = png(shot)
scale = W / 1500.0
def accent_column(center):
    c = int((center - 34) * scale)
    for x in range(max(0, c - int(6 * scale)), min(W, c + int(6 * scale))):
        n = 0
        for y in range(0, H, 8):
            r, g, b = px[y][x * bpp:x * bpp + 3]
            if b > r + 60 and b > 120 and g < b: n += 1
        if n > (H // 8) * 0.6: return x
    return None
# P2-F15: activation now previews the recommended option, so in conflict
# mode the canvas carries components.md §14.4's inset accent border on ALL
# its edges. That complete border is spec; a ONE-edge line is the defect.
# An accent column at the boundary is a failure only if the canvas's leading
# edge has none.
x = accent_column(ix)
if x is not None and accent_column(canvas["x"]) is None:
    print(f"FAIL [{label}]: full-height accent line at x {x / scale + 34:.0f} (the boundary is {ix:.0f})"); ok = False
elif x is not None:
    print(f"     [{label}]: accent at both canvas edges — the §14.4 preview border, not an edge ring")
sys.exit(0 if ok else 1)
PY
}

XY=$(find "morning review, 08:15") || { echo "FAIL: no Morning review block"; quit_app; exit 1; }
click $XY
check selected
XY=$(find "id:needs-attention-row") || { echo "FAIL: no needs-attention row"; quit_app; exit 1; }
click $XY
check conflict
quit_app
if [[ $FAILS -eq 0 ]]; then echo "PASS: inspector content inset, nothing drawn over it, no edge line (selected + conflict)."; exit 0; fi
echo "FAIL: $FAILS check(s) failed."; exit 1
