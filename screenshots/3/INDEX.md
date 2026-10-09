# Phase 3 slice 1 — review captures (components.md §22)

One build (`ae8fb46` + the task 17 script changes), captured 2026-10-08
19:50–20:06 in **review mode** (`-KadenceReview phase3`, or `phase2` where no
connected source is wanted) on a fresh store, served by the mocked CalDAV
server (`MockCalDAVTransport` — no network, the review password in memory,
the account `user01 @ cis.technikum-wien.at`). Every live item had a fresh
pre-flight; every click went through `Scripts/lib/kadence-guard.swift`.
Live frames: `Scripts/capture-p3.sh`; offscreen renders of the real views
(§17.2 rule 3): `Scripts/capture-p3-renders.sh` (the render tests in
`KadenceTests/Phase3/*RenderTests.swift`).

- **Clock / `M`:** today = Thu 8 Oct 2026; `M` = Mon **12 Oct 2026** (the
  first Monday ≥ today + 2); `M + 2` = Wed 14 Oct (`Studieninformationstag`).
- **Item 16's `k`:** d = (M + 4) − today = 8, so **k = 9** — the footer reads
  `9 of 15`.
- **Appearance:** live frames are dark (the system's), except item 19's light
  frame, which sets Kadence's own appearance with the review-only argument
  `-KadenceAppearance light` (the system setting is never touched). Renders
  are light.
- **Edge check (§17.2 rule 6):** `Scripts/check-frame-edges.py` on all 35
  frames: **34 ok** with no accent pixel in the 2px band; item 16
  (`conflict-lecture-training-p3.png`) **ok under the rule-6 exemption**
  (`--preview`: a complete 2pt border x 480–2357, y 104–1799, nothing accent
  outside it). It is the only preview frame.
- **Passwords:** shown only as `SecureField` bullets (items 2, 4). The
  connect captures type a non-secret filler (the review mock accepts any
  password for `user01`, DEVIATIONS B43); the script asserts the filler is in
  no AX value.

| § 22 item | File(s) | Mocked case | Notes |
|---|---|---|---|
| 1 Sidebar, first run | `sidebar-first-run-p3.png` | `phase2` (no source) | `Connect Timetable…` as the last Sources row |
| 2 Step 1 empty / filled | `connect-step1-empty-p3.png`, `connect-step1-filled-p3.png` | `phase2`, `reportOK` | Server prefilled, `Connect` disabled when empty; `user01` + bullets |
| 3 Connecting | `connect-step1-connecting-p3.png` | `slow` | spinner + `Connecting to cis.technikum-wien.at…`, fields disabled |
| 4 Failures | `connect-step1-unauthorized-p3.png`, `connect-step1-certificate-p3.png`, `connect-step1-nocaldav-p3.png`, `connect-step1-webdav-hint-p3.png` | `unauthorized`, `certificate`, `wellKnown404`, — | Password focused with its contents selected; focus on Connect; Server focused; the WebDAV-share message |
| 5 Step 2, one calendar | `connect-step2-single-p3.png` | `reportOK` | confirmed row `✓ LVPlan` (AX `Calendar: LVPlan`, no checkbox — asserted live), `13 events, 2 Oct 2026 – 23 Oct 2026`, history `2`, co-teaching `1` |
| 6 Step 2, several | `connect-step2-checklist-p3.png` | `multiCalendar` | `LVPlan`, `Prüfungen` checked; `Aufgaben`, `outbox`, `inbox` absent |
| 7 Edit mode | `connect-edit-p3.png` | `unauthorized` (its `Update Password…`) | Server/Username prefilled, Password empty with `Saved in Keychain`, focused; the system's "Passwords…" AutoFill suggestion appears under a focused password field (system chrome) |
| 8 Settings ▸ Sources | `settings-sources-uptodate-p3.png` (+ `settings-sources-empty-p3.png`) | `reportOK` (empty: `phase2`) | `Up to date`, `Account user01 @ cis.technikum-wien.at`, `Calendar LVPlan`, `Every 30 minutes`; nothing in the form focused (the list holds focus and its selection) |
| 9 Sidebar row, four states | `sidebar-row-states-p3.png` (render) + `sidebar-live-p3.png` | render; live `forbidden` | syncing spinner, upToDate empty slot, transient secondary glyph, actionable alert glyph; checkboxes in one column |
| 10 Source popover | `source-popover-forbidden-p3.png`, `source-popover-partial-details-p3.png` (render) | `forbidden`; render | `Access refused`, `Edit Account…` default; `partialImport` with details expanded (no review case produces it) |
| 11 Week `M` | `week-M-p3.png` (+ `day-inno3-online-p3.png`) | `reportOK` | lectures; `REQEN-EXAM` with `graduationcap.fill`; Friday's `SWRM-ILV` **one** block, conflicted against `Training`. `INNO3-EL`'s `.full` meta is tail-truncated at Week column width, so the Day frame of `M + 2` shows `University timetable · Online` whole. Friday's block title band is covered by `Training` (deferred A35/G-048). The Day frame's sidebar toolbar button shows a focus ring from the ⌘3/⌘→ keystrokes (keyboard navigation on) |
| 12 After the second sync | `week-M-after-change-p3.png`, `source-popover-last-change-p3.png` | `reportChanged` (⌘R) | `SWEN3-LAB` in `EDV_F4.26`, `EPC-ILV` (Thu 15) gone; `Last change just now: 2 added · 2 updated · 2 removed` |
| 13 Inspector, `SWQM-ILV` | `inspector-imported-p3.png` | `reportOK` | read-only line, `Lecturer L01`, `Group BIF-5C`, `Room HS_A3.15`, Source + `Synced HH:mm`, no Description |
| 14 Inspector, `INNO3-EL` | `inspector-lecturers-collapsed-p3.png`, `inspector-lecturers-expanded-p3.png` | `reportOK` | `L10`, `L11`, `L12`, `and 19 more` / all 22 + `Show fewer`; `Room Online · WEBINAR01` |
| 15 A refused edit | `inspector-refusal-emphasis-p3.png` | `reportOK` | taken right after ⌫: the read-only line in `text.primary` (#F2F2F4; #A8ADB5 at rest) |
| 16 Conflict panel | `conflict-lecture-training-p3.png` | `reportOK`, `-KadenceConflictUnderTest SWRM-ILV` | three options, `Shift Training 45 min later` recommended and previewed, the canvas border, `9 of 15` |
| 17 Popover, imported NEXT | `popover-imported-next-p3.png`, `popover-stale-line-p3.png` (renders) + `popover-live-p3.png` | render; live `reportOK` | `Done` · `Open`, no `Snooze`; the stale line. The live frame shows the popover's real chrome; its NEXT is the Phase 2 dataset's late `Breakfast` (it was 20:04) |
| 18 Removal alert | `remove-source-alert-p3.png` | `reportOK` | `Cancel` the default; ⎋ cancelled it (the source stayed) |
| 19 All-day pill + done, light/dark | `allday-and-done-light-p3.png`, `allday-and-done-dark-p3.png` | `reportOK` | **measures colour — appearance named in the file name**: `Studieninformationstag` (`.eventAllDay`, graphite) and `SWQM-ILV` done via ⌘↩ (label, checkmark and — G-074 placeholder — meta in `text.primary`) |
| 20 Cancelled | `cancelled-block-p3.png`, `inspector-cancelled-p3.png` (renders) | `edge-cases.ics` | dashed border, `xmark.circle`, `Cancelled · University timetable`; inspector `Cancelled by University timetable`, Done/Skip disabled |
| 21 Calendar missing | `source-popover-calendar-missing-p3.png` | `calendarGone` | `Choose Calendar…` the default. This launch's first fetch (the Import) hit the 404, so its status line reads `Never synced` |

Superseded `-p3t12` … `-p3t16` frames were deleted when this set replaced
them (task 17).
