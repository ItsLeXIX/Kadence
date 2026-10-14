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

# ---- Sidebar and source popover (items 1, 9, 10, 12, 21).
main_id() { window_id 1500; }
# The popover is its own window: the smallest on-screen Kadence window that is
# neither the main window nor a menu.
popover_id() { "$WORK/wins" | awk '$4 != 1500 && $4 > 100 && $4 < 600 { print $4 * $5, $1 }' | sort -n | head -1 | cut -d' ' -f2; }
# The status slot sits just left of the row's checkbox (layouts.md §2.1:
# slot 16pt, spacing.xs, then the checkbox). The row is one combined AX
# element whose value starts with the source's name.
open_source_popover() {
  "$WORK/axq" "$PID" > "$WORK/ax-row.txt"
  local xy; xy=$(python3 - "$WORK/ax-row.txt" <<'PY2'
import sys
best = None
for line in open(sys.argv[1]).read().splitlines():
    p = line.split("~")
    if len(p) != 9: continue
    x, y, w, h = map(int, p[5:9])
    if p[0] == "AXCheckBox" and any(f.startswith("University timetable") for f in p[1:3]) and w > 100:
        best = (x, y, w, h); break
if not best: sys.exit(1)
x, y, w, h = best
# The combined row element spans swatch … checkbox; checkbox ~16 +
# spacing.xs 4 → the slot's centre is 28pt in from its right edge.
print(x + w - 28, y + h // 2)
PY2
) || { echo "FAIL: no source row"; quit_app; exit 1; }
  click $xy; sleep 1.5
}

item_sidebar_first_run() {
  launch_fresh -KadenceReview phase2
  has "Connect Timetable…" || { echo "FAIL: no first-run row"; quit_app; exit 1; }
  shoot_window "$(main_id)" "sidebar-first-run-$SUFFIX.png"
  quit_app
}
item_sidebar_live() {
  launch_fresh -KadenceReview phase3 -KadenceMockCalDAV forbidden
  sleep 3
  has "Connect Timetable…" && { echo "FAIL: the first-run row is still there"; quit_app; exit 1; }
  shoot_window "$(main_id)" "sidebar-live-$SUFFIX.png"
  quit_app
}
popover_item() {  # popover_item CASE NAME EXPECT [syncnow]
  launch_fresh -KadenceReview phase3 -KadenceMockCalDAV "$1"
  sleep 3
  if [[ "${4:-}" == "syncnow" ]]; then key $KVK_R cmd; sleep 3; fi
  open_source_popover
  has "$3" || { echo "FAIL: the popover doesn't show '$3'"; quit_app; exit 1; }
  echo "  focus: $("$WORK/focus" "$PID")"
  shoot_window "$(popover_id)" "$2-$SUFFIX.png"
  quit_app
}
KVK_R=15
item_source_popover_forbidden() { popover_item forbidden source-popover-forbidden "Access refused"; }
item_source_popover_last_change() { popover_item reportChanged source-popover-last-change "2 added · 2 updated · 2 removed" syncnow; }
item_source_popover_calendar_missing() { popover_item calendarGone source-popover-calendar-missing "Choose Calendar…"; }

# ---- The week of M (items 11, 12, 19).
KVK_2=19; KVK_RIGHT=124
to_week_m() {
  key $KVK_2 cmd; sleep 1
  key $KVK_RIGHT cmd; sleep 2   # M is the Monday of the next week (today + 2 … + 8)
}
item_week_m() {
  launch_fresh -KadenceReview phase3 -KadenceMockCalDAV reportOK
  sleep 3
  to_week_m
  has "SWRM-ILV" || { echo "FAIL: no SWRM-ILV in week M"; quit_app; exit 1; }
  has "REQEN-EXAM" || { echo "FAIL: no REQEN-EXAM"; quit_app; exit 1; }
  shoot_window "$(main_id)" "week-M-$SUFFIX.png"
  quit_app
}
item_week_m_after_change() {
  launch_fresh -KadenceReview phase3 -KadenceMockCalDAV reportChanged
  sleep 3
  key $KVK_R cmd; sleep 3
  to_week_m
  has "EPC-ILV" && "$WORK/axq" "$PID" | grep -c "EPC-ILV" | grep -q "^1$" || true
  shoot_window "$(main_id)" "week-M-after-change-$SUFFIX.png"
  quit_app
}
# Item 19 — the all-day pill (Studieninformationstag, M + 2) and a done
# lecture, light and dark. The appearance is set for Kadence alone through
# its own review argument (`-KadenceAppearance`), never in System Settings.
allday_and_done() {  # allday_and_done Light|Dark NAME
  launch_fresh -KadenceReview phase3 -KadenceMockCalDAV reportOK -KadenceAppearance "$1"
  sleep 3
  to_week_m
  local xy; xy=$(find_el "SWQM-ILV") || { echo "FAIL: no SWQM-ILV block"; quit_app; exit 1; }
  click $xy
  key $KVK_RETURN cmd; sleep 1      # ⌘↩ Done (allowed on an imported event, §18.1)
  key $KVK_ESC; key $KVK_ESC        # selection → cursor → unfocused (§17.2 rule 4)
  has "Studieninformationstag" || { echo "FAIL: no all-day pill"; quit_app; exit 1; }
  shoot_window "$(main_id)" "$2-$SUFFIX.png"
  quit_app
}
item_allday_and_done_light() { allday_and_done light allday-and-done-light; }
item_allday_and_done_dark() { allday_and_done dark allday-and-done-dark; }

# ---- The inspector for imported events (items 13–16).
KVK_DELETE=51
select_block() {  # select_block TITLE — on week M
  local xy; xy=$(find_el "$1") || { echo "FAIL: no $1 block"; quit_app; exit 1; }
  click $xy
}
item_inspector_imported() {
  launch_fresh -KadenceReview phase3 -KadenceMockCalDAV reportOK
  sleep 3; to_week_m
  select_block "SWQM-ILV"
  has "Read-only — from University timetable" || { echo "FAIL: no read-only line"; quit_app; exit 1; }
  shoot_window "$(main_id)" "inspector-imported-$SUFFIX.png"
  quit_app
}
item_inspector_lecturers() {
  launch_fresh -KadenceReview phase3 -KadenceMockCalDAV reportOK
  sleep 3; to_week_m
  select_block "INNO3-EL"
  has "Show all 22 lecturers" || { echo "FAIL: not collapsed (no 'Show all 22 lecturers' button)"; quit_app; exit 1; }
  shoot_window "$(main_id)" "inspector-lecturers-collapsed-$SUFFIX.png"
  local xy; xy=$(find_el "Show all 22 lecturers") || { echo "FAIL: no 'and 19 more' button"; quit_app; exit 1; }
  click $xy
  has "Show fewer lecturers" || { echo "FAIL: not expanded"; quit_app; exit 1; }
  shoot_window "$(main_id)" "inspector-lecturers-expanded-$SUFFIX.png"
  quit_app
}
# Item 15 — ⌫ on SWQM-ILV: nothing deleted; the read-only line emphasised for
# 0.6 s, so the frame is taken straight after the key (no settle wait).
item_inspector_refusal_emphasis() {
  launch_fresh -KadenceReview phase3 -KadenceMockCalDAV reportOK
  sleep 3; to_week_m
  select_block "SWQM-ILV"
  echo "  before ⌫, focus: $("$WORK/focus" "$PID")"
  local id; id=$(main_id)
  front; "$WORK/hid" key $KVK_DELETE
  shoot_window "$id" "inspector-refusal-emphasis-$SUFFIX.png"
  sleep 1
  has "SWQM-ILV" || { echo "FAIL: ⌫ deleted the imported event"; quit_app; exit 1; }
  echo "  ⌫ refused; SWQM-ILV still there"
  quit_app
}
# Item 16 — Friday's conflict previewed (the script hook picks it).
item_conflict_lecture_training() {
  launch_fresh -KadenceReview phase3 -KadenceMockCalDAV reportOK -KadenceConflictUnderTest "SWRM-ILV"
  sleep 3
  local xy; xy=$(find_el "needs-attention-row") || { echo "FAIL: no Needs attention row"; quit_app; exit 1; }
  click $xy; sleep 2
  has "Shift Training 45 min later" || { echo "FAIL: not Friday's conflict"; quit_app; exit 1; }
  # A click on the recommended row previews it (§10.1; check-conflict-apply-return.sh does the same).
  xy=$(find_el "Shift Training 45 min later") || { echo "FAIL: no recommended row"; quit_app; exit 1; }
  click $xy; sleep 1.5
  shoot_window "$(main_id)" "conflict-lecture-training-$SUFFIX.png"
  quit_app
}

# ---- Task 17 extras.
# Item 11's `INNO3-EL` reading `Online` at `.full`: in Week view its column is
# too narrow for the meta line, so a Day frame of M + 2 shows it whole.
KVK_3=20
item_day_inno3_online() {
  launch_fresh -KadenceReview phase3 -KadenceMockCalDAV reportOK
  sleep 3
  key $KVK_3 cmd; sleep 1
  for _ in 1 2 3 4 5 6; do key $KVK_RIGHT cmd; done   # today (8 Oct) → Wed 14 Oct = M + 2
  sleep 1
  has "INNO3-EL" || { echo "FAIL: no INNO3-EL on M + 2"; quit_app; exit 1; }
  shoot_window "$(main_id)" "day-inno3-online-$SUFFIX.png"
  quit_app
}
# Item 17's one live popover frame: a guarded click on Kadence's own status
# item. Skipped (not failed) when the menu bar has no room for it.
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
item_popover_live() {
  launch_fresh -KadenceReview phase3 -KadenceMockCalDAV reportOK
  sleep 3
  local box; box=$("$WORK/extras" "$PID" | head -1)
  [[ -z "$box" ]] && { echo "  SKIP: no status item found"; quit_app; return; }
  read -r ix iy iw ih <<<"$box"
  if (( ix < 0 )); then echo "  SKIP: the status item is off the visible menu bar (x $ix)"; quit_app; return; fi
  click $((ix + iw / 2)) $((iy + ih / 2)); sleep 1.5
  local pop; pop=$("$WORK/wins" | awk '$6 > 0 && $4 > 200 && $4 < 400 { print $2, $3, $4, $5; exit }')
  [[ -z "$pop" ]] && { echo "  SKIP: the popover did not open"; quit_app; return; }
  read -r px py pw ph <<<"$pop"
  # The popover's own bounds and the menu bar above it — nothing of the
  # windows behind it at the edges (the §17.2 rule 6 band).
  screencapture -x -R "$px,0,$pw,$((py + ph))" "$OUT/popover-live-$SUFFIX.png"
  echo "  captured popover-live-$SUFFIX.png"
  key $KVK_ESC
  quit_app
}

# ---- PHASE3-REVIEW fix 11: the real-use set (components.md §22 items 22–27),
# on the datasets `empty` and `fresh` (§22.1). Every launch is a review launch
# on its own in-memory store.
KVK_LEFT=123
# The week of 28 Sep – 4 Oct 2026 from today's week (fresh's dates are absolute).
to_week_of_2_oct() {
  key $KVK_2 cmd; sleep 1
  local i
  for i in $(seq 1 30); do
    has "BPREF-Info" && return 0
    key $KVK_LEFT cmd; sleep 0.8
  done
  echo "FAIL: never reached the week of 2 Oct"; quit_app; exit 1
}
item_real_first_run() {           # item 22 (and item 1's first-run evidence)
  launch_fresh -KadenceReview empty
  sleep 2
  has "Connect Timetable…" || { echo "FAIL: no Connect Timetable… row"; quit_app; exit 1; }
  has "Needs attention" && { echo "FAIL: a Needs attention row on a first run"; quit_app; exit 1; }
  has "University timetable" && { echo "FAIL: a timetable row on a first run"; quit_app; exit 1; }
  shoot_window "$(main_id)" "real-first-run-$SUFFIX.png"
  quit_app
}
item_fresh_week() {               # item 23
  launch_fresh -KadenceReview fresh -KadenceMockCalDAV reportOK
  sleep 3
  to_week_of_2_oct
  has "Needs attention" && { echo "FAIL: a Needs attention row after the Import"; quit_app; exit 1; }
  shoot_window "$(main_id)" "fresh-week-sidebar-$SUFFIX.png"
  quit_app
}
item_fresh_overlap_week() {       # item 24, Week (cascade)
  launch_fresh -KadenceReview fresh -KadenceMockCalDAV reportOK
  sleep 3
  to_week_of_2_oct
  key $KVK_ESC; key $KVK_ESC
  shoot_window "$(main_id)" "fresh-overlap-week-$SUFFIX.png"
  quit_app
}
item_fresh_overlap_day() {        # item 24, Day (packed)
  launch_fresh -KadenceReview fresh -KadenceMockCalDAV reportOK
  sleep 3
  to_week_of_2_oct
  # Into the week's Friday: Day view, then step to 2 Oct.
  key $KVK_3 cmd; sleep 1
  local i
  # The day view opens on the week's anchor day; Friday 2 Oct is within
  # four days of it either way.
  for i in 1 2 3 4 5 6; do
    "$WORK/axq" "$PID" | grep -q "BPREF-Info" && break
    key $KVK_RIGHT cmd; sleep 0.8
  done
  for i in $(seq 1 10); do
    "$WORK/axq" "$PID" | grep -q "BPREF-Info" && break
    key $KVK_LEFT cmd; sleep 0.8
  done
  # Bring 18:00–20:30 into view: scroll the canvas down.
  local xy; xy=$(find_el "BPREF-Info") || { echo "FAIL: no BPREF-Info on this day"; quit_app; exit 1; }
  front; "$WORK/hid" scroll 900 600 -300; sleep 1.5
  key $KVK_ESC; key $KVK_ESC
  shoot_window "$(main_id)" "fresh-overlap-day-$SUFFIX.png"
  quit_app
}
item_inspector_bpref() {          # item 25
  launch_fresh -KadenceReview fresh -KadenceMockCalDAV reportOK
  sleep 3
  to_week_of_2_oct
  "$WORK/axq" "$PID" > "$WORK/ax-bpref.txt"
  # The 18:35 block: of the two BPREF-Info elements, the higher one; click
  # inside its title band, clear of the 19:30 session.
  local xy; xy=$(python3 - "$WORK/ax-bpref.txt" <<'PY2'
import sys
best = None
for line in open(sys.argv[1]).read().splitlines():
    p = line.split("~")
    if len(p) != 9 or "BPREF-Info" not in " ".join(p[1:5]): continue
    x, y, w, h = map(int, p[5:9])
    if w > 0 and h > 0 and (best is None or y < best[1]): best = (x, y, w, h)
if not best: sys.exit(1)
print(best[0] + 40, best[1] + 8)
PY2
) || { echo "FAIL: no BPREF-Info block"; quit_app; exit 1; }
  click $xy
  has "Read-only — from University timetable" || { echo "FAIL: BPREF-Info not selected"; quit_app; exit 1; }
  has "L06" || { echo "FAIL: the inspector does not list L06"; quit_app; exit 1; }
  shoot_window "$(main_id)" "inspector-bpref-two-lecturers-$SUFFIX.png"
  quit_app
}
item_settings_fresh() {           # item 27
  launch_fresh -KadenceReview fresh -KadenceMockCalDAV reportOK
  sleep 3
  local id; id=$(open_settings)
  has "13 events" || { echo "FAIL: no '13 events' in Settings"; quit_app; exit 1; }
  echo "  focus: $("$WORK/focus" "$PID")"
  shoot_window "$id" "settings-sources-fresh-$SUFFIX.png"
  quit_app
}

item_debug_emphasis() {   # diagnostics only
  launch_fresh -KadenceReview phase3 -KadenceMockCalDAV reportOK
  sleep 3; to_week_m
  select_block "SWQM-ILV"
  local id; id=$(main_id)
  front; "$WORK/hid" key $KVK_DELETE
  for i in 1 2 3 4 5 6; do screencapture -x -o -l "$id" "$WORK/burst$i.png"; done
  for i in 1 2 3 4 5 6; do python3 -c "
from PIL import Image
im=Image.open('$WORK/burst$i.png').convert('RGB'); print('burst $i', max(im.crop((2390,180,2800,210)).getdata()))"; done
  quit_app
}
item_debug_delete() {   # diagnostics only: does ⌫ reach the grid?
  launch_fresh -KadenceReview phase2
  local xy; xy=$(find_el "Coffee with Nora") || { echo "no coffee"; quit_app; exit 1; }
  click $xy
  front; "$WORK/hid" key $KVK_DELETE; sleep 1.5
  has "Coffee with Nora" && echo "  ⌫ did NOT delete the manual event" || echo "  ⌫ deleted the manual event"
  quit_app
}
item_dump_sidebar_ax() {   # diagnostics only: no capture
  launch_fresh -KadenceReview phase3 -KadenceMockCalDAV forbidden
  sleep 3
  "$WORK/axq" "$PID" | awk -F'~' '$6 < 400' | grep -iv "^AXStaticText~~~~~" | head -60
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
