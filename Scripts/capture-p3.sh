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

for item in "$@"; do
  Scripts/preflight.sh || { echo "STOPPED before $item: pre-flight failed"; exit 2; }
  fn="item_${item//-/_}"
  declare -F "$fn" >/dev/null || { echo "unknown item $item"; exit 1; }
  echo "== $item"
  "$fn"
done
echo "done"
