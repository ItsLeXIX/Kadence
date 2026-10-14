#!/bin/bash
#
# check-view-switch-focus.sh — PHASE3-REVIEW.md fix 10c.
#
# interactions.md §1 (amended 2026-09-10): "the toolbar is not a focus stop",
# and a view change must leave focus in the grid. The Phase 3 review found a
# toolbar button carrying the focus ring in a Day frame: with keyboard
# navigation on, ⌘3 rebuilt the canvas, the focused view went away with it,
# and AppKit moved key focus to the next key view — a toolbar button.
#
# This drives real HID ⌘1 / ⌘2 / ⌘3 at a review launch and reads the
# accessibility focus after each: it must not be a button in the toolbar.
# Then one ↓ must move the grid's time cursor — proof that the keys still go
# to the grid.
#
# A review launch runs on its own in-memory store (components.md §22.1); the
# app's real store is never touched. Input goes only to Kadence
# (Scripts/lib/kadence-guard.swift).
#
# Usage: Scripts/check-view-switch-focus.sh
set -uo pipefail
cd "$(dirname "$0")/.."

Scripts/preflight.sh || exit 2
source Scripts/lib/p3-lib.sh

KVK_1=18; KVK_2=19; KVK_3=20; KVK_DOWN=125; KVK_ESC=53

echo "building…"
xcodebuild -scheme Kadence -destination 'platform=macOS' build >"$WORK/build.log" 2>&1 || { echo "FAIL: build"; exit 1; }
APP=$(ls -td ~/Library/Developer/Xcode/DerivedData/Kadence-*/Build/Products/Debug/Kadence.app | head -1)

KBNAV=$(( $(defaults read -g AppleKeyboardUIMode 2>/dev/null || echo 0) & 2 ))
if [[ "$KBNAV" -ne 0 ]]; then echo "keyboard navigation: on"; else echo "keyboard navigation: off (the toolbar is then never a key view; the check still runs)"; fi

fail() { echo "FAIL: $1"; quit_app; exit 1; }

# The focused element must not be a toolbar button.
assert_focus_in_grid() {  # assert_focus_in_grid LABEL
  local line; line=$("$WORK/focus" "$PID")
  echo "  after $1: $line"
  if grep -q "AXToolbar" <<<"$line"; then fail "after $1 the focused element is in the toolbar"; fi
  if grep -q "^AXButton" <<<"$line" && grep -q "parents AXToolbar\|>AXToolbar" <<<"$line"; then
    fail "after $1 the focused element is a toolbar button"
  fi
}

launch_fresh -KadenceReview phase3 -KadenceMockCalDAV reportOK
sleep 3
# Straight after launch, nothing clicked — the path the review's Day frame
# took (launch, ⌘3): the toolbar must not end up with key focus.
echo "  at launch: $("$WORK/focus" "$PID")"
key $KVK_3 cmd; sleep 1.2
assert_focus_in_grid "⌘3 straight after launch"
key $KVK_2 cmd; sleep 1.2
assert_focus_in_grid "⌘2 straight after launch"
# Put focus in the grid the way a user does: a click on an empty part of it
# (well inside the canvas, below the all-day row), then ⎋ to leave selection.
click 760 620
key $KVK_ESC
assert_focus_in_grid "a click in the grid"

for round in 1 2; do
  key $KVK_3 cmd; sleep 1.2
  has "Day" || true
  assert_focus_in_grid "⌘3 (round $round)"
  key $KVK_1 cmd; sleep 1.2
  assert_focus_in_grid "⌘1 (round $round)"
  key $KVK_2 cmd; sleep 1.2
  assert_focus_in_grid "⌘2 (round $round)"
done

# The grid still takes the keys: in Day, ↓ moves the time cursor. Two reads
# with no input between them must agree first — otherwise a change after the
# keys could be the clock's, and this part says nothing.
key $KVK_3 cmd; sleep 1.2
assert_focus_in_grid "⌘3"
"$WORK/axq" "$PID" > "$WORK/still1.txt"
"$WORK/axq" "$PID" > "$WORK/still2.txt"
if cmp -s "$WORK/still1.txt" "$WORK/still2.txt"; then
  key $KVK_DOWN; key $KVK_DOWN
  "$WORK/axq" "$PID" > "$WORK/after.txt"
  if cmp -s "$WORK/still2.txt" "$WORK/after.txt"; then
    fail "↓ ↓ after ⌘3 changed nothing in the window: the grid does not have the keys"
  fi
  echo "  ↓ ↓ after ⌘3 reached the grid (the window was still before them and changed after)"
  assert_focus_in_grid "↓ ↓"
else
  echo "  (the window changed by itself between two reads — the ↓ ↓ part is skipped, not passed)"
fi

quit_app
echo "PASS: check-view-switch-focus — focus stays out of the toolbar after ⌘1, ⌘2 and ⌘3."
