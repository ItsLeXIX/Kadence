#!/bin/bash
#
# check-edit-delete.sh — PHASE3-REVIEW.md fix 10a (interactions.md §2, §13.4;
# DEVIATIONS A38): Edit ▸ Delete exists with ⌫, is enabled for a deletable
# selection in the grid, disabled with nothing selected and for an imported
# event — and a bare-key menu shortcut does not eat backspace in a text field.
#
# Real HID keys and clicks, to Kadence only (Scripts/lib/kadence-guard.swift),
# on review launches, which run on their own in-memory store (components.md
# §22.1): the app's real store is never touched.
#
# Usage: Scripts/check-edit-delete.sh
set -uo pipefail
cd "$(dirname "$0")/.."

Scripts/preflight.sh || exit 2
source Scripts/lib/p3-lib.sh

KVK_DELETE=51; KVK_ESC=53; KVK_N=45; KVK_Z=6; KVK_2=19; KVK_RIGHT=124

echo "building…"
xcodebuild -scheme Kadence -destination 'platform=macOS' build >"$WORK/build.log" 2>&1 || { echo "FAIL: build"; exit 1; }
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/Kadence-*/Build/Products/Debug/Kadence.app | head -1)

# The Edit menu's `Delete` item that carries ⌫, read through the Accessibility
# API without opening the menu: prints "enabled" / "disabled" / "missing".
cat > "$WORK/menu.swift" <<'SWIFT'
import ApplicationServices
let app = AXUIElementCreateApplication(pid_t(CommandLine.arguments[1])!)
func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v }
func kids(_ e: AXUIElement) -> [AXUIElement] { (attr(e, "AXChildren") as? [AXUIElement]) ?? [] }
guard let bar = attr(app, "AXMenuBar") else { print("missing"); exit(0) }
var found = "missing"
for top in kids(bar as! AXUIElement) where (attr(top, "AXTitle") as? String) == "Edit" {
    for menu in kids(top) {
        for item in kids(menu) where (attr(item, "AXTitle") as? String) == "Delete" {
            // ⌫ as a key equivalent: virtual key 51, or the delete glyph/char.
            let vk = (attr(item, "AXMenuItemCmdVirtualKey") as? Int) ?? -1
            let glyph = (attr(item, "AXMenuItemCmdGlyph") as? Int) ?? -1
            let char = (attr(item, "AXMenuItemCmdChar") as? String) ?? ""
            guard vk == 51 || glyph == 23 || char == "\u{8}" || char == "\u{7F}" else { continue }
            found = ((attr(item, "AXEnabled") as? Bool) ?? false) ? "enabled" : "disabled"
        }
    }
}
print(found)
SWIFT
swiftc -O "$WORK/menu.swift" -o "$WORK/menu" 2>"$WORK/menu.log" || { echo "FAIL: helper menu"; cat "$WORK/menu.log"; exit 1; }
delete_item() { "$WORK/menu" "$PID"; }

fail() { echo "FAIL: $1"; quit_app; exit 1; }
expect_item() {  # expect_item STATE WHEN
  local got; got=$(delete_item)
  [[ "$got" == "$1" ]] || fail "Edit ▸ Delete is '$got' $2 (expected $1)"
  echo "  Edit ▸ Delete (⌫) is $got $2"
}
select_block() { local xy; xy=$(find_el "$1") || fail "no '$1' block"; click $xy; }

# ---------------------------------------------------------------- phase2: a manual event
launch_fresh -KadenceReview phase2
[[ "$(delete_item)" != "missing" ]] || fail "Edit ▸ Delete with ⌫ is not in the Edit menu"
has "Coffee with Nora" || fail "the fixture's manual event is missing"

select_block "Coffee with Nora"
expect_item enabled "with a manual event selected in the grid"

# ⌫ on the selected manual event deletes it; ⌘Z brings it back in one step.
select_block "Coffee with Nora"
expect_item enabled "with the manual event selected again"
front; "$WORK/hid" key $KVK_DELETE; sleep 1.5
has "Coffee with Nora" && fail "⌫ did not delete the selected manual event"
echo "  ⌫ deleted the manual event"
expect_item disabled "with nothing selected"
key $KVK_Z cmd; sleep 1.5
has "Coffee with Nora" || fail "⌘Z did not bring the event back (not one undo step?)"
echo "  ⌘Z restored it (one undo step)"
quit_app

# ---------------------------------------------------------------- phase3: a text field, an imported event
Scripts/preflight.sh || exit 2
launch_fresh -KadenceReview phase3 -KadenceMockCalDAV reportOK
sleep 3
# A manual event selected in the main window, then backspace typed into a
# text field elsewhere (Settings ▸ Sources ▸ Name): the bare ⌫ shortcut must
# not take it — the item is disabled while focus is outside the grid.
select_block "Coffee with Nora"
expect_item enabled "with a manual event selected in the grid"
KVK_COMMA=43
key $KVK_COMMA cmd; sleep 2
name_field() { "$WORK/axq" "$PID" | awk -F'~' '$1 == "AXTextField" && $4 ~ /timetable/ { print int($6 + $8 / 2), int($7 + $9 / 2), $4; exit }'; }
read -r nx ny before <<<"$(name_field)"
[[ -n "${nx:-}" ]] || fail "no Name field in Settings ▸ Sources"
click "$nx" "$ny"
expect_item disabled "while the Name field has focus"
front; "$WORK/hid" key $KVK_DELETE; sleep 1
after=$("$WORK/axq" "$PID" | awk -F'~' '$1 == "AXTextField" && $4 ~ /timet|tabl|Univ/ { print $4; exit }')
[[ ${#after} -eq $(( ${#before} - 1 )) ]] || fail "backspace in Name did not edit it ('$before' → '$after')"
has "Coffee with Nora" || fail "backspace in the Name field deleted the selected event"
echo "  backspace in Settings' Name field edited it ('$before' → '$after'); the selected event is still there"
key $KVK_ESC; sleep 0.5
quit_app

Scripts/preflight.sh || exit 2
launch_fresh -KadenceReview phase3 -KadenceMockCalDAV reportOK
sleep 3
key $KVK_2 cmd; sleep 1
key $KVK_RIGHT cmd; sleep 2     # the week of M
select_block "SWQM-ILV"
has "Read-only — from University timetable" || fail "the imported event is not selected"
expect_item disabled "with an imported event selected"
front; "$WORK/hid" key $KVK_DELETE; sleep 1.5
has "SWQM-ILV" || fail "⌫ deleted an imported event"
echo "  ⌫ on the imported event was refused; it is still there"
quit_app
echo "PASS: check-edit-delete — Edit ▸ Delete follows the selection and never takes a text field's backspace."
