#!/bin/bash
#
# check-conflict-apply-return.sh — drive a REAL HID Return keypress at the
# conflict panel while the INSPECTOR (not the grid) holds real SwiftUI focus,
# and assert the focused/previewed option's resolution actually commits to
# the store. interactions.md line 71 / §10.1's last paragraph: "↩ applies the
# focused option" while the conflict panel is focused.
#
# Why this exists (P2-T37): `MainWindow.swift`'s `handleKey` has always had a
# correct `.return` case for this (P2-T17,  lines ~488-490 of the fixed file:
# `case .return where state.focusedRegion == .inspector &&
# state.selectedConflictID != nil && state.selectedConflictOptionID != nil`)
# — but it was DEAD CODE whenever the inspector held real focus, because the
# `inspector` view's own `.onKeyPress(keys: [...], action: handleKey)` hook
# was filtered to `[.upArrow, .downArrow, .escape]` and never forwarded
# `.return`. SwiftUI only dispatches a key event to the `.onKeyPress` hooks
# along the FOCUSED view's own chain, so when the inspector (a sibling of the
# grid) held focus, the key never reached `handleKey` at all — `↩` silently
# did nothing, matching the "applying with ↩... did not visibly commit"
# finding in screenshots/2/INDEX.md's Batch 4 and STATUS.md/DEVIATIONS.md's
# P2-T32 notes. The fix adds `.return` to that forwarded key list.
#
# `KadenceTests/ConflictApplyTests.swift` could not and did not catch this —
# it drives `CalendarState.applyFocusedConflictOption` directly, bypassing
# the SwiftUI key-routing layer this defect lived in entirely. This script
# exercises the actual `.onKeyPress` wiring the unit test cannot reach, same
# reasoning as check-accessibility.sh (SwiftUI's real accessibility/focus/key
# plumbing only exists out-of-process, never inside an XCTest host).
#
# WHY A CGEvent AND NOT `System Events ... keystroke`: `keystroke` posts
# through a different, higher-level path than a genuine HID key event and,
# per this repo's own established precedent (check-block-click-selects.sh),
# is not trustworthy as a regression test for a real dispatch-layer defect.
# This script posts genuine CGEvent keyDown/keyUp pairs through the HID event
# tap, the same path a human keypress takes.
#
# Fixture: MockData.swift's "Client call" (manual, 19:50–20:20 today) /
# "Focus review" (routine, .fixed, 20:00–21:00 today) pair, added by P2-T29.
# `ConflictEngine` gives this pair exactly two ranked options (§14.3.4 copy
# since P2-T45) — "Shorten Focus review to 40 min" (recommended: it keeps
# 40 of 60, at least half; disturbance 20) first, "Skip Focus review today"
# (disturbance 60) second. The app is launched with
# `-KadenceConflictUnderTest "Focus review"` (P2-T41), so activating the
# needs-attention row opens THIS pair explicitly. Before that the script
# relied on it sorting first, which failed whenever a clock-dependent fixture
# conflict started earlier (DEVIATIONS.md B18).
# `ConflictEngine.shortenOption` keeps "Focus review"'s back half — new
# start 20:20, new end 21:00 (`CalendarState.applyFocusedConflictOption`'s
# `.shorten` case calls `EventStore.resize`) — a +1200-second (20-minute)
# move of `ZSTART` for the `Focus review` row, checked directly against the
# real SwiftData store below (`ZEVENT`/`ZTITLE`/`ZSTART`, the schema
# STATUS.md's P2-T35 entry already documents; `ZSTART` is Core Data
# reference-date seconds, epoch 2001-01-01 UTC — the exact offset does not
# matter here, only the +1200s delta does).
#
# Per this task's own brief: step 0 is the SAME lock probe
# check-accessibility.sh uses (`CGSSessionScreenIsLocked` via
# `CGSSessionCopyCurrentDictionary()`). If the screen is locked, this script
# stops BEFORE building or launching anything and says so — it does not fake
# a result. A locked screen blocks accessibility window enumeration AND
# reliable HID event delivery session-wide (this machine's own established
# precedent — STATUS.md §15/§16 and the P2-T35 entry), so there is nothing
# useful this script could do differently.
#
# Usage:  Scripts/check-conflict-apply-return.sh          # builds, launches, checks, quits
#         Scripts/check-conflict-apply-return.sh --keep   # leaves the app running
#
set -uo pipefail
cd "$(dirname "$0")/.."

KEEP=0
[[ "${1:-}" == "--keep" ]] && KEEP=1

# --------------------------------------------------------------- step 0: lock probe
echo "checking session lock state…"
LOCK_STATE=$(swift -e '
  import CoreGraphics
  import Foundation
  if let cfDict = CGSessionCopyCurrentDictionary() {
      let dict = cfDict as NSDictionary
      print((dict["CGSSessionScreenIsLocked"] as? Int) ?? 0)
  } else {
      print(0)
  }
' 2>/dev/null)

if [[ "$LOCK_STATE" == "1" ]]; then
  echo "SKIP: screen is LOCKED (CGSSessionScreenIsLocked=1)."
  echo "      Per this machine's established precedent (check-accessibility.sh,"
  echo "      STATUS.md §15/§16/§35), accessibility window enumeration and"
  echo "      driven HID input are unreliable session-wide while locked — the"
  echo "      real app is very likely fine underneath (WindowServer keeps it"
  echo "      alive), System Events and this script's clicks/keys just cannot"
  echo "      reliably reach it. This is environmental, not a code defect."
  echo "      Stopping BEFORE building or launching, exactly as directed."
  echo "      Unlock the screen and re-run for a live result."
  exit 1
fi
echo "screen is unlocked, continuing."

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# --------------------------------------------------------- HID click+key helper
cat > "$WORK/hid.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let a = CommandLine.arguments
let src = CGEventSource(stateID: .hidSystemState)

func usage() -> Never {
    FileHandle.standardError.write("usage: khid click X Y | khid key VIRTUALKEYCODE\n".data(using: .utf8)!)
    exit(2)
}
guard a.count >= 2 else { usage() }

switch a[1] {
case "click":
    guard a.count >= 4, let x = Double(a[2]), let y = Double(a[3]) else { usage() }
    let pt = CGPoint(x: x, y: y)
    // Move first: a click with no preceding move can land before SwiftUI has
    // updated its hover/hit state (same discipline as check-block-click-selects.sh).
    CGEvent(mouseEventSource: src, mouseType: .mouseMoved,
            mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(150_000)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
            mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(60_000)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
            mouseCursorPosition: pt, mouseButton: .left)?.post(tap: .cghidEventTap)
case "key":
    guard a.count >= 3, let code = UInt16(a[2]) else { usage() }
    CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
    usleep(60_000)
    CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
default:
    usage()
}
SWIFT
echo "compiling HID helper…"
swiftc -O "$WORK/hid.swift" -o "$WORK/khid" 2>"$WORK/swiftc.log" || {
  echo "FAIL: could not compile the HID helper — see $WORK/swiftc.log"
  cat "$WORK/swiftc.log"; exit 1; }

KVK_RETURN=36

# ------------------------------------------------------------------ the build
echo "building…"
xcodebuild -scheme Kadence -destination 'platform=macOS' build >/tmp/kadence-conflict-return-build.log 2>&1 || {
  echo "FAIL: build failed — see /tmp/kadence-conflict-return-build.log"; exit 1; }

APP=$(ls -d ~/Library/Developer/Xcode/DerivedData/Kadence-*/Build/Products/Debug/Kadence.app 2>/dev/null | head -1)
[[ -z "$APP" ]] && { echo "FAIL: no built app found"; exit 1; }

# Same pid-targeting discipline as check-accessibility.sh: System Events
# resolves `process "Kadence"` by NAME, so a wedged instance with no window
# would happily answer accessibility queries on behalf of the healthy one.
for PID in $(pgrep -f "Kadence.app/Contents/MacOS/Kadence"); do kill -9 "$PID" 2>/dev/null; done
sleep 2

# Fresh mock fixtures every run: `MockData.seedIfNeeded` only seeds an EMPTY
# store, so a store left over from an earlier session (a different real-world
# day) would not contain today's "Client call"/"Focus review" pair at all —
# the exact stale-fixture trap STATUS.md's P2-T20 entry already documents.
# Deleting it makes this launch reseed relative to *today*.
STORE_DIR="$HOME/Library/Containers/XIX.Kadence/Data/Library/Application Support"
STORE="$STORE_DIR/default.store"
rm -f "$STORE" "$STORE-wal" "$STORE-shm"

"$WORK/khid" click 5 5 >/dev/null 2>&1   # park the pointer; nothing hovered at baseline
# -ApplePersistenceIgnoreState YES: see check-accessibility.sh for why —
# suppresses this Mac's window-restoration flake so the main window is the
# only one that can ever appear.
# -KadenceConflictUnderTest (P2-T41): the needs-attention row opens THE
# "Client call"/"Focus review" conflict explicitly, instead of trusting it to
# sort first. It used not to whenever another fixture conflict started
# earlier — e.g. "Journal" seeded 16:41–17:45 overlapped "Training"
# (DEVIATIONS.md B18) — which made this check pass or fail by time of day.
# See CalendarState.conflictUnderTest.
open -n "$APP" --args -ApplePersistenceIgnoreState YES -KadenceConflictUnderTest "Focus review"
sleep 9

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

osascript -e "tell application \"System Events\" to tell (first process whose unix id is $TARGET) to set size of window 1 to {1500, 900}" >/dev/null 2>&1
sleep 2
echo "driving pid $TARGET"

# Give the freshly-reseeded store a moment before reading it — the app writes
# its seed transaction on first launch.
sleep 1
BEFORE_START=$(sqlite3 "$STORE" "SELECT ZSTART FROM ZEVENT WHERE ZTITLE='Focus review';" 2>/dev/null)
if [[ -z "$BEFORE_START" ]]; then
  echo "FAIL: could not read a 'Focus review' row from $STORE before the test."
  echo "      Either the store did not reseed, or MockData.swift's P2-T29 fixture"
  echo "      (the 'Client call'/'Focus review' conflict pair) is missing/renamed."
  [[ $KEEP -eq 0 ]] && pkill -f "Kadence.app/Contents/MacOS/Kadence" 2>/dev/null
  exit 1
fi
echo "baseline 'Focus review' ZSTART: $BEFORE_START"

# ------------------------------------------------------------------ the query
# P2-T41: read the tree through the Accessibility API directly, not System
# Events. On macOS 26.6 a SwiftUI button's attribute list carries
# `AXAttributedDescription` but not `AXDescription`, so System Events'
# `value of attribute "AXDescription"` throws and the old AppleScript reader
# saw an empty name for the needs-attention row and every option row
# (STATUS.md §41). `AXUIElementCopyAttributeValue` — what VoiceOver itself
# reads — still returns the description. The output format is unchanged
# (role~title~desc~value~x~y~w~h, one element per line), so the lookups
# below are the same text matches as before. `AXIdentifier` is appended to
# the description field so the needs-attention row can also be found by its
# `accessibilityIdentifier` ("needs-attention-row", SidebarView.swift).
# Only the reading changed: the clicks are still real HID events, the key is
# still a real HID Return, and the verdict is still the sqlite +1200 s check.
cat > "$WORK/axq.swift" <<'SWIFT'
import ApplicationServices
import Foundation
let pid = pid_t(CommandLine.arguments[1])!
let app = AXUIElementCreateApplication(pid)
func attr(_ e: AXUIElement, _ a: String) -> AnyObject? {
    var v: AnyObject?
    AXUIElementCopyAttributeValue(e, a as CFString, &v)
    return v
}
func str(_ o: AnyObject?) -> String {
    guard let o else { return "" }
    return "\(o)".replacingOccurrences(of: "~", with: " ").replacingOccurrences(of: "\n", with: " ")
}
func walk(_ e: AXUIElement, _ depth: Int) {
    if depth > 16 { return }
    for c in (attr(e, "AXChildren") as? [AXUIElement]) ?? [] {
        var p = CGPoint.zero, s = CGSize.zero
        if let pv = attr(c, "AXPosition") { AXValueGetValue(pv as! AXValue, .cgPoint, &p) }
        if let sv = attr(c, "AXSize") { AXValueGetValue(sv as! AXValue, .cgSize, &s) }
        let role = str(attr(c, "AXRole")), title = str(attr(c, "AXTitle"))
        var desc = str(attr(c, "AXDescription"))
        let ident = str(attr(c, "AXIdentifier"))
        if !ident.isEmpty { desc += " id:" + ident }
        let raw = attr(c, "AXValue")
        let val = (raw is String || raw is NSNumber) ? str(raw) : ""
        if !(title + desc + val).isEmpty {
            print("\(role)~\(title)~\(desc)~\(val)~\(Int(p.x))~\(Int(p.y))~\(Int(s.width))~\(Int(s.height))")
        }
        walk(c, depth + 1)
    }
}
if let w = (attr(app, "AXWindows") as? [AXUIElement])?.first { walk(w, 0) }
SWIFT
swiftc -O "$WORK/axq.swift" -o "$WORK/axq" 2>"$WORK/swiftc-axq.log" || {
  echo "FAIL: could not compile the AX reader — see $WORK/swiftc-axq.log"
  cat "$WORK/swiftc-axq.log"; exit 1; }

query() { "$WORK/axq" "$TARGET"; }

# --------------------------------------------------- find + click needs-attention
query > "$WORK/baseline.txt"

python3 - "$WORK/baseline.txt" "$WORK/plan1.txt" <<'PY'
import sys

src, out = sys.argv[1], sys.argv[2]

def rows(path):
    for line in open(path).read().splitlines():
        parts = line.split("~")
        if len(parts) != 8:
            continue
        role, title, desc, val, x, y, w, h = parts
        try:
            x, y, w, h = float(x), float(y), float(w), float(h)
        except ValueError:
            continue
        yield dict(role=role, title=title, desc=desc, val=val, x=x, y=y, w=w, h=h,
                    blob=(title + " " + desc + " " + val).lower())

hits = [r for r in rows(src)
        if "id:needs-attention-row" in r["blob"] or "needs attention" in r["blob"]]
# Prefer the button itself (identifier) over any text child.
hits.sort(key=lambda r: "id:needs-attention-row" not in r["blob"])
if not hits:
    print("FAIL: no 'Needs attention' element found in the sidebar.")
    print("      Either state.conflicts is empty (MockData's P2-T29/P2-T32")
    print("      conflict fixtures are missing), or the row's default")
    print("      accessibility label changed shape.")
    sys.exit(1)

r = hits[0]
cx, cy = r["x"] + r["w"] / 2, r["y"] + r["h"] / 2
print("needs-attention row:     %r  at (%.0f, %.0f)" % (r["blob"].strip(), cx, cy))
with open(out, "w") as f:
    f.write("%d %d\n" % (int(cx), int(cy)))
PY
[[ $? -ne 0 ]] && { [[ $KEEP -eq 0 ]] && pkill -f "Kadence.app/Contents/MacOS/Kadence" 2>/dev/null; exit 1; }

read -r NA_X NA_Y < "$WORK/plan1.txt"
echo "clicking needs-attention row at $NA_X,$NA_Y …"
"$WORK/khid" click "$NA_X" "$NA_Y"
sleep 2

# ----------------------------------------- find + click the recommended option
query > "$WORK/after-activate.txt"

python3 - "$WORK/after-activate.txt" "$WORK/plan2.txt" <<'PY'
import sys

src, out = sys.argv[1], sys.argv[2]

def rows(path):
    for line in open(path).read().splitlines():
        parts = line.split("~")
        if len(parts) != 8:
            continue
        role, title, desc, val, x, y, w, h = parts
        try:
            x, y, w, h = float(x), float(y), float(w), float(h)
        except ValueError:
            continue
        yield dict(role=role, title=title, desc=desc, val=val, x=x, y=y, w=w, h=h,
                    blob=(title + " " + desc + " " + val).lower())

hits = [r for r in rows(src) if "shorten focus review" in r["blob"]]
if not hits:
    print("FAIL: no 'Shorten Focus review' option row found after activating")
    print("      the needs-attention row. Either the conflict panel did not")
    print("      open (ConflictOrdering.firstUnresolved regression?), or")
    print("      ConflictOptionFormatting's row title text changed.")
    all_text = "\n".join(sorted({r["blob"].strip() for r in rows(src) if r["blob"].strip()}))
    print("      --- all non-empty AX text seen, for debugging ---")
    print(all_text)
    sys.exit(1)

r = hits[0]
cx, cy = r["x"] + r["w"] / 2, r["y"] + r["h"] / 2
print("recommended option row:  %r  at (%.0f, %.0f)" % (r["blob"].strip(), cx, cy))
with open(out, "w") as f:
    f.write("%d %d\n" % (int(cx), int(cy)))
PY
[[ $? -ne 0 ]] && { [[ $KEEP -eq 0 ]] && pkill -f "Kadence.app/Contents/MacOS/Kadence" 2>/dev/null; exit 1; }

read -r OPT_X OPT_Y < "$WORK/plan2.txt"
# This click does double duty, deliberately: it sets `selectedConflictOptionID`
# (the real thing that must be non-nil for ↩ to apply anything — §10.1's own
# "an option the user cannot see the consequence of is an option they cannot
# rank") AND it is a real click INTO the inspector panel, which is this app's
# own established way (DEVIATIONS.md's P2-T16 note) to give the inspector
# real SwiftUI focus — the exact thing this defect needed and never got.
echo "clicking recommended option (\"Shorten Focus review to 40 min\") at $OPT_X,$OPT_Y …"
"$WORK/khid" click "$OPT_X" "$OPT_Y"
sleep 2

# ---------------------------------------------------------- the real ↩ keypress
echo "sending a real HID Return keypress…"
"$WORK/khid" key "$KVK_RETURN"
sleep 2

[[ $KEEP -eq 0 ]] && pkill -f "Kadence.app/Contents/MacOS/Kadence" 2>/dev/null

# ------------------------------------------------------------------- the verdict
AFTER_START=$(sqlite3 "$STORE" "SELECT ZSTART FROM ZEVENT WHERE ZTITLE='Focus review';" 2>/dev/null)
echo ""
echo "after   'Focus review' ZSTART: $AFTER_START"

if [[ -z "$AFTER_START" ]]; then
  echo "FAIL: 'Focus review' vanished from the store after the keypress."
  exit 1
fi

# ConflictEngine.shortenOption keeps the back half: new start = otherInterval.end
# (20:20), i.e. the original start (20:00) + exactly 1200 seconds (20 minutes).
# CalendarState.applyFocusedConflictOption's `.shorten` case writes this via
# EventStore.resize — a real, undoable, persisted store mutation, not a
# preview. A no-op ↩ (the P2-T32 defect) would leave ZSTART unchanged.
DELTA=$(python3 -c "print(int(\"$AFTER_START\".split('.')[0]) - int(\"$BEFORE_START\".split('.')[0]))" 2>/dev/null)

if [[ "$DELTA" == "1200" ]]; then
  echo "PASS: ↩ applied the recommended option — 'Focus review' shortened,"
  echo "      ZSTART moved by exactly +1200s (20 min), matching"
  echo "      ConflictEngine.shortenOption's own computed result."
  exit 0
else
  echo "FAIL: ZSTART moved by ${DELTA:-<unparseable>}s, expected exactly +1200s."
  echo "      This is the P2-T32 signature if the delta is 0: the inspector's"
  echo "      .onKeyPress hook is not forwarding .return to handleKey, so the"
  echo "      conflict-apply case in MainWindow.handleKey (guarded on"
  echo "      state.focusedRegion == .inspector && selectedConflictID != nil"
  echo "      && selectedConflictOptionID != nil) never runs. See"
  echo "      MainWindow.swift's inspector computed view and STATUS.md's"
  echo "      P2-T37 entry."
  exit 1
fi
