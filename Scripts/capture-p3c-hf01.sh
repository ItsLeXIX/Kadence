#!/bin/bash
#
# capture-p3c-hf01.sh — P3S3-HF01's live captures: the Connect Moodle sheet
# (empty, URL typed, step 2 preview), its Replace mode and the Connect
# Timetable sheet, each opened the way Parsa opens it (Settings ▸ Sources ▸
# `+` ▸ …, or `Replace URL…`) in a real window. Every launch is
# `-KadenceReview` on its own in-memory store with the mock feed and the
# mock CalDAV server — no network, no Keychain, no real store. The only URL
# ever typed is `MoodleMock.urlString` (the SENTINEL test URL), into the
# SecureField, which draws dots. A fresh pre-flight runs before EVERY item;
# input goes only to Kadence (kadence-guard). Only the Kadence process this
# script launched is ever quit, by its PID — any other Kadence is left alone.
#
# Usage: SUFFIX=p3chf01 Scripts/capture-p3c-hf01.sh ITEM [ITEM ...]
#        Frames go to screenshots/3c/<item>-<SUFFIX>.png.
set -uo pipefail
cd "$(dirname "$0")/.."
SUFFIX="${SUFFIX:-p3chf01}"
OUT=screenshots/3c
mkdir -p "$OUT"

Scripts/preflight.sh || exit 2
source Scripts/lib/p3-lib.sh

KVK_COMMA=43; KVK_RETURN=36; KVK_DOWN=125
EVIDENCE="$HOME/Library/Containers/XIX.Kadence/Data/tmp/kadence-review"
URL=$(sed -n 's/^ *static let urlString = "\(.*\)"$/\1/p' Kadence/Review/MoodleMock.swift)
[[ "$URL" == *SENTINEL* ]] || { echo "STOP: no SENTINEL mock URL"; exit 1; }

echo "building…"
xcodebuild -scheme Kadence -destination 'platform=macOS' build >"$WORK/build.log" 2>&1 || { echo "FAIL: build"; exit 1; }
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/Kadence-*/Build/Products/Debug/Kadence.app | head -1)

# p3-lib's quit_app ends every Kadence process: here only ours, by PID.
quit_app() { [[ -n "$PID" ]] && kill "$PID" 2>/dev/null; sleep 2; PID=""; }
launch() {
  Scripts/preflight.sh || exit 2
  rm -rf "$EVIDENCE" 2>/dev/null
  local before; before=" $(pgrep -f "Kadence.app/Contents/MacOS/Kadence" | tr '\n' ' ') "
  open -n "$APP" --args -ApplePersistenceIgnoreState YES "$@"
  sleep 9
  PID=""
  for p in $(pgrep -f "Kadence.app/Contents/MacOS/Kadence"); do [[ "$before" == *" $p "* ]] || PID=$p; done
  [[ -z "$PID" ]] && { echo "FAIL: Kadence did not start"; exit 1; }
  for _ in $(seq 1 15); do
    N=$(osascript -e "tell application \"System Events\" to tell (first process whose unix id is $PID) to count windows" 2>/dev/null)
    [[ "${N:-0}" -ge 1 ]] && break; sleep 2
  done
  front; "$WORK/kguard" park "$PID" || { echo "STOP: could not park the pointer inside Kadence."; quit_app; exit 1; }
  local file="$EVIDENCE/launch-services.txt"
  # (The container's tmp may be closed to this shell's sandbox: then the
  # launch's mock-only proof is `ReviewMode`'s own, as in every review run.)
  if [[ -r "$file" ]] && grep -Ev '^(Mock|Scripted|Recording)' "$file" | grep -q .; then
    echo "STOP: a review launch built a real service:"; cat "$file"; quit_app; exit 1
  fi
}
open_settings() { key $KVK_COMMA cmd; sleep 2; }
# Settings ▸ Sources ▸ `+` ▸ the Nth item — the pull-down, as Parsa opens
# it. An open menu is not a window the AX reader walks, so the item is
# chosen with ↓ and Return (1 Connect Timetable…, 2 Connect Moodle…).
plus_menu() {
  local xy; xy=$(find_el "Connect add") || { echo "FAIL: no + menu"; quit_app; exit 1; }
  click $xy; sleep 1
  for _ in $(seq 1 "$1"); do key $KVK_DOWN; done
  key $KVK_RETURN; sleep 2
}
sheet_id() { window_of_width 440; }
expect_sheet() {  # expect_sheet TITLE — the sheet is the sheet, not a blank box
  local id; id=$(sheet_id)
  [[ -n "$id" ]] || { echo "FAIL: no 440-wide sheet window:"; "$WORK/wins"; quit_app; exit 1; }
  has "$1" || { echo "FAIL: sheet has no '$1'"; quit_app; exit 1; }
  "$WORK/wins" | awk -v id="$id" '$1 == id { print "  sheet " $4 "x" $5 }'
}
# No AX value or title anywhere in the app holds the URL.
assert_no_url_in_ax() {
  "$WORK/axq" "$PID" > "$WORK/ax-secret.txt"
  grep -qi -- "SENTINEL\|authtoken" "$WORK/ax-secret.txt" && { echo "FAIL: the URL is in the accessibility tree"; quit_app; exit 1; }
  echo "  AX tree: no URL"
}

moodle_sheet() { launch -KadenceReview empty; open_settings; plus_menu 2; expect_sheet "Connect Moodle"; }

item_connect_moodle_live() {
  moodle_sheet
  shoot_window "$(sheet_id)" "connect-moodle-live-$SUFFIX.png"
  quit_app
}
item_connect_moodle_live_typed() {
  moodle_sheet
  type_text "$URL"
  assert_no_url_in_ax
  shoot_window "$(sheet_id)" "connect-moodle-live-typed-$SUFFIX.png"
  quit_app
}
item_connect_moodle_live_preview() {
  moodle_sheet
  type_text "$URL"
  key $KVK_RETURN; sleep 3
  has "Import" || { echo "FAIL: no step 2"; quit_app; exit 1; }
  assert_no_url_in_ax
  shoot_window "$(sheet_id)" "connect-moodle-live-preview-$SUFFIX.png"
  quit_app
}
item_replace_moodle_live() {
  launch -KadenceReview moodleOnly; open_settings
  local xy; xy=$(find_el "Replace URL…") || { echo "FAIL: no Replace URL…"; quit_app; exit 1; }
  click $xy; sleep 2
  expect_sheet "Replace the calendar URL"
  shoot_window "$(sheet_id)" "replace-moodle-live-$SUFFIX.png"
  quit_app
}
item_connect_timetable_live() {
  launch -KadenceReview empty; open_settings; plus_menu 1
  expect_sheet "Connect a timetable"
  shoot_window "$(sheet_id)" "connect-timetable-live-$SUFFIX.png"
  quit_app
}


# The bug as Parsa saw it — run only on a build of the pre-fix sheets
# (ea3f962): whatever sheet window appears, measured and captured (a
# sheet's capture is drawn over its Settings window).
item_connect_moodle_live_before() {
  launch -KadenceReview empty; open_settings; plus_menu 2
  "$WORK/wins"
  local id; id=$("$WORK/wins" | awk '$4 != 1500 && $4 != 640 { print $1; exit }')
  shoot_window "$id" "connect-moodle-live-before-$SUFFIX.png"
  quit_app
}

for item in "$@"; do
  fn="item_${item//-/_}"
  declare -F "$fn" >/dev/null || { echo "unknown item $item"; exit 1; }
  echo "== $item"; "$fn"
done
