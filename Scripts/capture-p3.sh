#!/bin/bash
#
# capture-p3.sh — Phase 3's review captures (components.md §22; PHASE3-PLAN.md
# tasks 12–17). Every run launches Kadence in review mode on a fresh store
# (`-KadenceReview phase3`, the mocked CalDAV server — no network, the review
# password in memory) or `phase2` for the no-source frames, with the mocked
# case each item needs. A fresh pre-flight (screen unlocked, no app in full
# screen) runs before EVERY item; input goes only to Kadence (kadence-guard).
#
# Usage: SUFFIX=p3t12 Scripts/capture-p3.sh ITEM [ITEM ...]
#        Frames go to screenshots/3/<item>-<SUFFIX>.png.
set -uo pipefail
cd "$(dirname "$0")/.."
SUFFIX="${SUFFIX:-p3}"
OUT=screenshots/3
mkdir -p "$OUT"

Scripts/preflight.sh || exit 2
source Scripts/lib/p3-lib.sh

KVK_COMMA=43; KVK_ESC=53; KVK_RETURN=36; KVK_TAB=48

echo "building…"
xcodebuild -scheme Kadence -destination 'platform=macOS' build >"$WORK/build.log" 2>&1 || { echo "FAIL: build"; exit 1; }
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/Kadence-*/Build/Products/Debug/Kadence.app | head -1)

open_settings() {
  key $KVK_COMMA cmd; sleep 2
  local id; id=$(window_id other)
  [[ -n "$id" ]] || { echo "FAIL: no Settings window"; quit_app; exit 1; }
  echo "$id"
}

# Item 8 — Settings ▸ Sources, upToDate, nothing selected in the form.
item_settings_sources_uptodate() {
  launch_fresh -KadenceReview phase3 -KadenceMockCalDAV reportOK
  sleep 3   # the launch sync (the review source's Import) through the mock
  local id; id=$(open_settings)
  has "Up to date" || { echo "FAIL: the source is not Up to date"; quit_app; exit 1; }
  has "user01 @ cis.technikum-wien.at" || { echo "FAIL: no Account row"; quit_app; exit 1; }
  echo "  focus: $("$WORK/focus" "$PID")"
  shoot_window "$id" "settings-sources-uptodate-$SUFFIX.png"
  quit_app
}

# Item 8's empty state — no connected source (the Phase 2 dataset alone).
item_settings_sources_empty() {
  launch_fresh -KadenceReview phase2
  local id; id=$(open_settings)
  has "No timetable connected." || { echo "FAIL: no empty state"; quit_app; exit 1; }
  shoot_window "$id" "settings-sources-empty-$SUFFIX.png"
  quit_app
}

# Item 18 — the removal confirmation alert. ⎋ cancels; nothing is removed.
item_remove_source_alert() {
  launch_fresh -KadenceReview phase3 -KadenceMockCalDAV reportOK
  sleep 3
  open_settings >/dev/null
  local xy; xy=$(find_el "Remove Source…") || { echo "FAIL: no Remove Source… button"; quit_app; exit 1; }
  click $xy; sleep 1.5
  has "will be removed from your calendar" || { echo "FAIL: no removal alert"; quit_app; exit 1; }
  local alert; alert=$("$WORK/wins" | awk '$6 != 0 || ($4 != 1500 && $4 > 0) { print }' | sort -k4 -n | head -1 | cut -d' ' -f1)
  shoot_window "$alert" "remove-source-alert-$SUFFIX.png"
  key $KVK_ESC; sleep 1
  has "will be removed from your calendar" && { echo "FAIL: ⎋ left the alert open"; quit_app; exit 1; }
  has "user01 @ cis.technikum-wien.at" || { echo "FAIL: ⎋ removed the source"; quit_app; exit 1; }
  echo "  ⎋ cancelled; the source is still there"
  quit_app
}

# ---- The connect sheet (items 2–7). Review mode serves the mock even in
# phase2, so nothing here can reach the network. The review mock accepts any
# password for user01, so the script types a non-secret filler (B43).
FILLER="filler-not-a-secret"
KVK_A=0

open_connect_sheet() {  # open_connect_sheet DATASET CASE
  launch_fresh -KadenceReview "$1" -KadenceMockCalDAV "$2"
  open_settings >/dev/null
  local xy; xy=$(find_el "Connect Timetable…") || { echo "FAIL: no Connect Timetable… button"; quit_app; exit 1; }
  click $xy; sleep 1.5
  has "Connect a timetable" || { echo "FAIL: the connect sheet did not open"; quit_app; exit 1; }
}
sheet_id() { window_of_width 440; }
fill_sheet() {  # username, then password (focus starts in Username, §12.1)
  type_text "user01"
  key $KVK_TAB
  type_text "$FILLER"
}
# No AX value or title anywhere in the app holds what was typed into the SecureField.
assert_no_password_in_ax() {
  "$WORK/axq" "$PID" > "$WORK/ax-secret.txt"
  grep -q -- "$FILLER" "$WORK/ax-secret.txt" && { echo "FAIL: the typed password is in the accessibility tree"; quit_app; exit 1; }
  echo "  AX tree: no password"
}
press_connect() { local xy; xy=$(find_el "AXButton~Connect~") || xy=$(find_el "Connect" 1); key $KVK_RETURN; }

item_connect_step1_empty() {
  open_connect_sheet phase2 reportOK
  shoot_window "$(sheet_id)" "connect-step1-empty-$SUFFIX.png"
  quit_app
}
item_connect_step1_filled() {
  open_connect_sheet phase2 reportOK
  fill_sheet
  assert_no_password_in_ax
  shoot_window "$(sheet_id)" "connect-step1-filled-$SUFFIX.png"
  quit_app
}
item_connect_step1_connecting() {
  open_connect_sheet phase2 slow
  fill_sheet
  key $KVK_RETURN; sleep 0.8
  has "Connecting to cis.technikum-wien.at" || { echo "FAIL: not connecting"; quit_app; exit 1; }
  shoot_window "$(sheet_id)" "connect-step1-connecting-$SUFFIX.png"
  quit_app
}
connect_failure() {  # connect_failure CASE NAME EXPECT
  open_connect_sheet phase2 "$1"
  fill_sheet
  key $KVK_RETURN; sleep 2.5
  has "$3" || { echo "FAIL: no '$3'"; quit_app; exit 1; }
  echo "  focus: $("$WORK/focus" "$PID")"
  assert_no_password_in_ax
  shoot_window "$(sheet_id)" "$2-$SUFFIX.png"
  quit_app
}
item_connect_step1_unauthorized() { connect_failure unauthorized connect-step1-unauthorized "Sign-in failed"; }
item_connect_step1_certificate() { connect_failure certificate connect-step1-certificate "Secure connection failed"; }
item_connect_step1_nocaldav() { connect_failure wellKnown404 connect-step1-nocaldav "No calendar server found"; }
item_connect_step1_webdav_hint() {
  open_connect_sheet phase2 reportOK
  key $KVK_TAB shift      # Username → Server (focus starts in Username)
  key $KVK_A cmd
  type_text "https://cis.technikum-wien.at/Webdav/Lvplan"
  key $KVK_TAB
  has "That's the WebDAV share" || { echo "FAIL: no WebDAV-share message"; quit_app; exit 1; }
  shoot_window "$(sheet_id)" "connect-step1-webdav-hint-$SUFFIX.png"
  quit_app
}
item_connect_step2_single() {
  open_connect_sheet phase2 reportOK
  fill_sheet
  key $KVK_RETURN; sleep 3
  has "Import University timetable" || { echo "FAIL: not on step 2"; quit_app; exit 1; }
  has "Calendar: LVPlan" || { echo "FAIL: no confirmed row 'Calendar: LVPlan' in the AX tree"; quit_app; exit 1; }
  "$WORK/axq" "$PID" > "$WORK/ax-step2.txt"
  # Only the sheet's own window counts (the main window's sidebar has checkboxes).
  local frame; frame=$("$WORK/wins" | awk '$6 == 0 && $4 == 640 { print $2, $3, $4, $5; exit }')
  python3 - "$WORK/ax-step2.txt" $frame <<'PY2' || { echo "FAIL: a checkbox on the single-calendar step"; quit_app; exit 1; }
import sys
path, x0, y0, w, h = sys.argv[1], *map(int, sys.argv[2:6])
for line in open(path).read().splitlines():
    p = line.split("~")
    if len(p) == 9 and p[0] == "AXCheckBox":
        x, y = int(p[5]), int(p[6])
        if x0 <= x < x0 + w and y0 <= y < y0 + h: print("checkbox in the sheet:", line); sys.exit(1)
PY2
  echo "  AX: 'Calendar: LVPlan', no checkbox"
  shoot_window "$(sheet_id)" "connect-step2-single-$SUFFIX.png"
  quit_app
}
item_connect_step2_checklist() {
  open_connect_sheet phase2 multiCalendar
  fill_sheet
  key $KVK_RETURN; sleep 3
  has "Prüfungen" || { echo "FAIL: no checklist"; quit_app; exit 1; }
  has "Aufgaben" && { echo "FAIL: Aufgaben listed"; quit_app; exit 1; }
  shoot_window "$(sheet_id)" "connect-step2-checklist-$SUFFIX.png"
  quit_app
}
# Item 7 — edit mode from `Update Password…`: Server and Username prefilled,
# Password empty with `Saved in Keychain`, focused. Reached through the
# source's `unauthorized` state, whose primary action is Update Password….
item_connect_edit() {
  launch_fresh -KadenceReview phase3 -KadenceMockCalDAV unauthorized
  sleep 3
  open_settings >/dev/null
  local xy; xy=$(find_el "Update Password…") || { echo "FAIL: no Update Password… button"; quit_app; exit 1; }
  click $xy; sleep 1.5
  has "Edit University timetable" || { echo "FAIL: edit mode did not open"; quit_app; exit 1; }
  echo "  focus: $("$WORK/focus" "$PID")"
  shoot_window "$(sheet_id)" "connect-edit-$SUFFIX.png"
  quit_app
}

for item in "$@"; do
  Scripts/preflight.sh || { echo "STOPPED before $item: pre-flight failed"; exit 2; }
  fn="item_${item//-/_}"
  declare -F "$fn" >/dev/null || { echo "unknown item $item"; exit 1; }
  echo "== $item"
  "$fn"
done
echo "done"
