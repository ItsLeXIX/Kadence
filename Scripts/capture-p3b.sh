#!/bin/bash
#
# capture-p3b.sh — Phase 3 slice 2's live review captures (components.md §30;
# PHASE3-SLICE2-PLAN.md task 18). Every item launches Kadence in review mode
# (`-KadenceReview travel` with its variant and mock arguments, or `phase3`)
# on its own in-memory store: the mock travel provider, geocoder, location
# source and path monitor and the recording notification centre — no
# network, no MapKit, no location, no prompt, no real notification. A fresh
# pre-flight (screen unlocked, no app in full screen) runs before EVERY item;
# input goes only to Kadence (kadence-guard). After each launch the launch's
# own service list (`kadence-review/launch-services.txt`) is checked: mocks
# only.
#
# Usage: SUFFIX=p3b Scripts/capture-p3b.sh ITEM [ITEM ...]
#        Frames go to screenshots/3b/<item>-<SUFFIX>.png.
set -uo pipefail
cd "$(dirname "$0")/.."
SUFFIX="${SUFFIX:-p3b}"
OUT=screenshots/3b
mkdir -p "$OUT"

Scripts/preflight.sh || exit 2
source Scripts/lib/p3-lib.sh

KVK_COMMA=43; KVK_ESC=53; KVK_RETURN=36; KVK_2=19; KVK_3=20; KVK_RIGHT=124
EVIDENCE="$HOME/Library/Containers/XIX.Kadence/Data/tmp/kadence-review"

echo "building…"
xcodebuild -scheme Kadence -destination 'platform=macOS' build >"$WORK/build.log" 2>&1 || { echo "FAIL: build"; exit 1; }
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/Kadence-*/Build/Products/Debug/Kadence.app | head -1)

main_id() { window_id 1500; }
# The launch built mocks only (components.md §24.11, §27.10).
check_services() {
  local file="$EVIDENCE/launch-services.txt"
  [[ -f "$file" ]] || { echo "FAIL: no launch-services.txt"; quit_app; exit 1; }
  if grep -Ev '^(Mock|Scripted|Recording)' "$file" | grep -q .; then
    echo "STOP: a review launch built a real service:"; cat "$file"; quit_app; exit 1
  fi
  echo "  services: $(tr '\n' ' ' < "$file")"
}
launch() { rm -rf "$EVIDENCE"; launch_fresh "$@"; check_services; }
to_week_m() { key $KVK_2 cmd; sleep 1; key $KVK_RIGHT cmd; sleep 2; }   # M = next Monday (today + 2 … + 8)

cat > "$WORK/extras.swift" <<'SWIFT'
import ApplicationServices
let app = AXUIElementCreateApplication(pid_t(CommandLine.arguments[1])!)
func attr(_ e: AXUIElement, _ a: String) -> AnyObject? { var v: AnyObject?; AXUIElementCopyAttributeValue(e, a as CFString, &v); return v }
guard let bar = attr(app, "AXExtrasMenuBar") else { exit(1) }
for item in (attr(bar as! AXUIElement, "AXChildren") as? [AXUIElement]) ?? [] {
    var p = CGPoint.zero, z = CGSize.zero
    if let v = attr(item, "AXPosition") { AXValueGetValue(v as! AXValue, .cgPoint, &p) }
    if let v = attr(item, "AXSize") { AXValueGetValue(v as! AXValue, .cgSize, &z) }
    print(Int(p.x), Int(p.y), Int(z.width), Int(z.height))
}
SWIFT
swiftc -O "$WORK/extras.swift" -o "$WORK/extras" 2>/dev/null

week_item() {  # week_item NAME [variant]
  if [[ -n "${2:-}" ]]; then launch -KadenceReview travel -KadenceReviewVariant "$2"; else launch -KadenceReview travel; fi
  sleep 4; to_week_m
  has "SWQM-ILV" || { echo "FAIL: no SWQM-ILV in week M"; quit_app; exit 1; }
  shoot_window "$(main_id)" "$1-$SUFFIX.png"
  quit_app
}
item_week_m_travel() { week_item week-M-travel; }                         # item 5 (and 6's early part, 8 in Week)
item_week_m_no_address() { week_item week-M-no-address travelNoAddress; }  # item 12
item_week_m_estimates() { week_item week-M-estimates travelOffline; }      # item 20
item_week_m_late() {                                                        # item 6's late part
  launch -KadenceReview travel
  sleep 4; to_week_m
  front; "$WORK/hid" scroll 784 520 -4000; sleep 1.5
  has "Late call" || { echo "FAIL: no Late call"; quit_app; exit 1; }
  shoot_window "$(main_id)" "week-M-travel-late-$SUFFIX.png"
  quit_app
}
item_day_thu_travel() {                                                     # item 7
  launch -KadenceReview travel
  sleep 4; to_week_m
  key $KVK_3 cmd; sleep 2
  has "EPC-ILV" || { echo "FAIL: Day is not Thu M + 3"; quit_app; exit 1; }
  shoot_window "$(main_id)" "day-thu-travel-$SUFFIX.png"
  quit_app
}
item_inspector_swqm_live() {                                                # item 9, live
  launch -KadenceReview travel
  sleep 4; to_week_m
  local xy; xy=$(find_el "SWQM-ILV") || { echo "FAIL: no SWQM-ILV block"; quit_app; exit 1; }
  click $xy
  has "Leave by" || { echo "FAIL: no Leave by row"; quit_app; exit 1; }
  shoot_window "$(main_id)" "inspector-swqm-live-$SUFFIX.png"
  quit_app
}
item_day_sun_climbing() {                                                   # item 8, Day
  launch -KadenceReview travel
  sleep 4; to_week_m
  key $KVK_3 cmd; sleep 2
  local i; for i in 1 2 3; do key $KVK_RIGHT cmd; sleep 1; done
  has "Climbing" || { echo "FAIL: Day is not Sun M + 6"; quit_app; exit 1; }
  shoot_window "$(main_id)" "day-sun-climbing-$SUFFIX.png"
  quit_app
}
item_inspector_dinner_popup() {                                             # item 11, the pop-up open
  launch -KadenceReview travel
  sleep 4; to_week_m
  local xy; xy=$(find_el "Dinner with") || { echo "FAIL: no Dinner block"; quit_app; exit 1; }
  click $xy
  has "Leave by" || { echo "FAIL: no Leave by row"; quit_app; exit 1; }
  xy=$(find_el "Place, Place") || { echo "FAIL: no Place pop-up"; quit_app; exit 1; }
  click $xy; sleep 1
  local box; box=$("$WORK/wins" | awk '$4 == 1500 { print $2, $3, $4, $5; exit }')
  read -r wx wy ww wh <<<"$box"
  screencapture -x -R "$wx,$wy,$ww,$wh" "$OUT/inspector-dinner-popup-$SUFFIX.png"
  echo "  captured inspector-dinner-popup-$SUFFIX.png"
  key $KVK_ESC
  quit_app
}
settings_tab() {  # settings_tab TAB NAME [args…]
  local tab="$1" name="$2"; shift 2
  launch -KadenceReview travel "$@"
  sleep 4
  key $KVK_COMMA cmd; sleep 2
  local id; id=$(window_id other)
  [[ -n "$id" ]] || { echo "FAIL: no Settings window"; quit_app; exit 1; }
  local xy; xy=$(find_el "AXButton~$tab~") || xy=$(find_el "$tab") || { echo "FAIL: no $tab tab"; quit_app; exit 1; }
  click $xy; sleep 1.5
  shoot_window "$id" "$name-$SUFFIX.png"
  quit_app
}
item_settings_travel_live() { settings_tab Travel settings-travel-live; }                 # items 2, live
item_settings_notifications_live() { settings_tab Notifications settings-notifications-live; }  # item 3, live
item_status_live() {                                                        # item 16
  launch -KadenceReview travel
  sleep 6
  local box; box=$("$WORK/extras" "$PID" | head -1)
  [[ -z "$box" ]] && { echo "  SKIP: no status item found"; quit_app; return; }
  read -r ix iy iw ih <<<"$box"
  if (( ix < 0 )); then echo "  SKIP: the status item is off the visible menu bar (x $ix)"; quit_app; return; fi
  screencapture -x -R "$((ix - 8)),$iy,$((iw + 16)),$ih" "$OUT/status-item-live-$SUFFIX.png"
  echo "  captured status-item-live-$SUFFIX.png"
  click $((ix + iw / 2)) $((iy + ih / 2)); sleep 1.5
  local pop; pop=$("$WORK/wins" | awk '$6 > 0 && $4 > 200 && $4 < 400 { print $2, $3, $4, $5; exit }')
  [[ -z "$pop" ]] && { echo "  SKIP: the popover did not open"; quit_app; return; }
  read -r px py pw ph <<<"$pop"
  screencapture -x -R "$px,0,$pw,$((py + ph))" "$OUT/popover-live-$SUFFIX.png"
  echo "  captured popover-live-$SUFFIX.png"
  key $KVK_ESC
  quit_app
}
item_phase3_week_m() {                                                      # item 17
  launch -KadenceReview phase3 -KadenceMockCalDAV reportOK
  sleep 4
  has "Datenmodellierung" || { echo "FAIL: no Datenmodellierung today"; quit_app; exit 1; }
  shoot_window "$(main_id)" "phase3-today-$SUFFIX.png"
  to_week_m
  shoot_window "$(main_id)" "phase3-week-M-$SUFFIX.png"
  quit_app
}
item_plan_live() {                                                           # item 14, the live recorded plan
  launch -KadenceReview travel
  sleep 8
  [[ -f "$EVIDENCE/notification-plan-live.txt" ]] && cp "$EVIDENCE/notification-plan-live.txt" "$OUT/notification-plan-live-$SUFFIX.txt" \
    && echo "  captured notification-plan-live-$SUFFIX.txt" || echo "  SKIP: no live plan written"
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
