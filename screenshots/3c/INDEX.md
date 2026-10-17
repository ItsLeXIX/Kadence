# Phase 3 slice 3 — Moodle deadlines: review frames (`components.md` §43)

Every frame below is `-p3ct15`, recaptured from one build (`CA P3S3-T15`) by
`RENDER_SUFFIX=p3ct15 SUFFIX=p3ct15 Scripts/capture-p3c-renders.sh
MoodleConnectTests MoodleCanvasTests MoodleInspectorTests MenuBarDueTests
DeadlineSettingsTests MoodleReviewTests`, after `Scripts/preflight.sh`
passed. The `-p3ct10` … `-p3ct14` files are the same frames as first captured
by tasks 10–14.

**How they were made (DEVIATIONS B58, as slice 2's B55):** offscreen renders
of the real views in the test host — no app launched, no input sent, no real
service built. Stores are in memory, seeded by the review datasets' own
seeding (`MoodleReview.seed`, M = Mon 12 Oct 2026); the feed is
`MockFeedTransport` (`-KadenceFeed`'s cases); the URL is the mock's, in the
in-memory secret store, and no frame shows more of it than
`moodle.technikum-wien.at/…`. The views draw in the Mac's zone
(Europe/Vienna). Edge check (§17.2 rule 6, `Scripts/check-frame-edges.py`):
**53 of 53 ok**.

| § 43 item | File(s) | Dataset / case | Clock | Appearance |
|---|---|---|---|---|
| 1 Sidebar first run; timetable connected | `sidebar-first-run-p3ct15.png`, `sidebar-timetable-connected-p3ct15.png` | rows only (rule `SidebarSourcesRule`) | — | light |
| 2 Settings ▸ Sources empty; `+` menu | `settings-sources-empty-p3ct15.png` — **the open `+` menu is not drawable offscreen** (B58; its two items are asserted by test) | built-ins only | render time | light |
| 3 Sheet step 1 empty; filled | `moodle-sheet-empty-p3ct15.png`, `moodle-sheet-filled-p3ct15.png` | — / mock URL | — | light |
| 4 Validation V3, V5, V6, V7, V9 | `moodle-sheet-v3-…`, `-v5-…`, `-v6-…`, `-v7-…`, `-v9-p3ct15.png` | mock URL edited | — | light |
| 5 Connecting; failures | `moodle-sheet-connecting-…` (the model in its connecting phase, B58), `-unauthorized-…` (`feed401`), `-notacalendar-…` (`feedHTML`), `-feednotfound-…` (`feed404`), `-offline-p3ct15.png` (`feedOffline`) | `MockFeedTransport` | — | light |
| 6 Step 2 `feedOK`; `feedNotice` | `moodle-sheet-step2-feedok-p3ct15.png`, `moodle-sheet-step2-feednotice-p3ct15.png` | `feedOK`, `feedNotice` | Mon 12 Oct 06:00 | light |
| 7 Settings, the Moodle source: up to date; unauthorized; emptyFeed | `settings-moodle-uptodate-…`, `settings-moodle-unauthorized-…`, `settings-moodle-emptyfeed-p3ct15.png` | imported `feedOK`, state set | render time (`Last synced …`) | light |
| 8 Replace: empty; V10; Update | `moodle-sheet-replace-empty-…`, `-replace-v10-…`, `-replace-step2-p3ct15.png` | `feedOK` | Mon 12 Oct 06:00 | light |
| 9 Week 12–18 Oct, light and dark | `week-1218-oct-p3ct15.png`, `week-1218-oct-dark-p3ct15.png` — Mon–Sun, so Sun 11's past pill is in the week before (G-115; asserted by test) | `moodle` | Mon 12 Oct 06:00 | light, dark |
| 10 Week 19–25 Oct | `week-1925-oct-p3ct15.png` | `moodle` | Mon 12 Oct 06:00 | light |
| 11 Week 2–8 Nov | `week-0208-nov-p3ct15.png` | `moodle` | Mon 12 Oct 06:00 | light |
| 12 Narrow Week column | `week-0208-nov-narrow-p3ct15.png` (7 × 104pt columns, the width of a 1100pt window) | `moodle` | Mon 12 Oct 06:00 | light |
| 13 Day Thu 22 Oct; Day Sun 1 Nov | `day-thu-22-oct-p3ct15.png`, `day-sun-01-nov-p3ct15.png` | `moodle` | Mon 12 Oct 06:00 | light |
| 14 Month Oct, Nov, Dec | `month-oct-2026-…`, `month-nov-2026-…`, `month-dec-2026-p3ct15.png` | `moodle` | Mon 12 Oct 06:00 | light |
| 15 Inspector: 900008, 900011, 900013, 900028, a notice, 900004 collapsed / expanded | `inspector-900008-…`, `-900011-…`, `-900013-…`, `-900028-…`, `-notice-900040-…`, `-900004-collapsed-…`, `-900004-expanded-p3ct15.png` | `moodle` (+ `feedNotice`'s 900040) | Mon 12 Oct 06:00 | light |
| 16 Done: 900005 in the inspector and on the pill; 900008 done then moved | `inspector-900005-done-…`, `pill-900005-done-…`, `inspector-900008-moved-p3ct15.png` | `moodle`; E1 applied | Mon 12 Oct 06:00 | light |
| 17 Unpaired opening | `pill-opening-900031-…`, `inspector-opening-900031-p3ct15.png` | `moodle` + `feedChanged`'s 900031 | Mon 12 Oct 06:00 | light |
| 18 Menu bar | `status-item-due-180-…`, `-110-…`, `-80-p3ct15.png` (degraded); `popover-due-1013-2000-…`, `popover-due-1103-2000-p3ct15.png` | `moodleOnly` | Tue 13 Oct 20:00; Tue 3 Nov 20:00 (its stale line is true: the store was seeded on 12 Oct) | light |
| 19 Settings ▸ Notifications: Deadlines; rule off; early Off | `settings-notifications-deadlines-…`, `-deadlines-off-…`, `-early-off-p3ct15.png` | slice 2's rig, §42.3 defaults | — | light (offscreen switches draw inactive) |
| 20 The plan dump | `notification-plan-moodle.txt` — §43.2's three tables and the three catch-up launches, from the real scheduler and planner | `moodleOnly` | the §43.2 clocks | — |
| 21 §M4's sync table | no frame — `FeedSyncTests.syncTable` | `feedOK` → `feedChanged` | Fri 16 Oct 13:07 / 14:07 | — |

## Hotfix — live (P3S3-HF01)

Real windows, not renders: each frame is a `-KadenceReview` launch of the
built app on its own in-memory store (mock feed, mock CalDAV server — no
network, no Keychain), opened the way Parsa opens it, captured by
`SUFFIX=p3chf01 Scripts/capture-p3c-hf01.sh ITEM` after
`Scripts/preflight.sh` passed (fresh before every launch). Input went only to
Kadence; only the launched PID was quit. Dark appearance (the Mac's). The
only URL typed is the mock's SENTINEL URL, into the SecureField — dots only,
and the app's accessibility tree was checked to hold none of it. Edge check
(`Scripts/check-frame-edges.py`): **6 of 6 ok**.

| Frame | What | Dataset | Sheet |
|---|---|---|---|
| `connect-moodle-live-before-p3chf01.png` | **The bug, before the fix** (a build of `ea3f962`'s sheets): Settings ▸ Sources ▸ `+` ▸ Connect Moodle… — the blank box | `empty` | 100×80 |
| `connect-moodle-live-p3chf01.png` | The same path after the fix: step 1, empty (macOS shows its own Passwords AutoFill bubble under a focused SecureField) | `empty` | 440×303 |
| `connect-moodle-live-typed-p3chf01.png` | The mock URL typed: dots, the display line, Connect enabled | `empty` | 440×303 |
| `connect-moodle-live-preview-p3chf01.png` | Return → step 2, the import preview from the mock (`feedOK`) | `empty` | 440×303 |
| `replace-moodle-live-p3chf01.png` | The Moodle source ▸ Replace URL… (§16.3) | `moodleOnly` | 440×255 |
| `connect-timetable-live-p3chf01.png` | Settings ▸ Sources ▸ `+` ▸ Connect Timetable… (had the same bug) | `empty` | 440×337 |
