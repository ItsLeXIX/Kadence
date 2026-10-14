# Phase 3 slice 1 — review captures (components.md §22)

Every live frame is a **review launch** (`-KadenceReview <dataset>`), which
since the fix run (PHASE3-REVIEW.md fix 1) runs on its **own in-memory
store** — the app's real store is never opened — and is served by the mocked
CalDAV server (`MockCalDAVTransport`: no network, the review password in
memory, the account `user01 @ cis.technikum-wien.at`). Fresh pre-flight
before every item; every click through `Scripts/lib/kadence-guard.swift`.
Live frames: `Scripts/capture-p3.sh`; offscreen renders of the real views
(§17.2 rule 3): `Scripts/capture-p3-renders.sh`.

## When and from which build each group was made

| Group | Made | Build | Frames |
|---|---|---|---|
| **A** — first set, live | Thu 2026-10-08 19:50–20:06 | `ae8fb46` (+ task 17 script changes) | the items not recaptured below (2–7, 9 live, 13–15, 17 renders' companions, 18, 19) |
| **B** — first set, renders and one re-crop | Fri 2026-10-09 21:59–22:00 | `ae8fb46` (same build) | `sidebar-row-states`, `popover-imported-next`, `popover-stale-line`, `cancelled-block`, `inspector-cancelled` (renders; they show 9 Oct clock times), `popover-live` (re-cropped) |
| **C** — fix run, live | **Wed 2026-10-14 10:08–10:18** | `1ca98aa` (fix 10) — app code identical at `e1f9876` (HK, docs only); capture-script items added in fix 11 | items 22–27, and the recaptures of 8, 10 (forbidden), 11, 12, 16, 21 |
| **D** — fix run, renders | **Wed 2026-10-14 10:19–10:20** | the same app code; the render tests of fix 11 | `source-popover-partial-details` (item 10), `cascade-gap` (item 24's gap). `sidebar-row-states` was re-rendered and came out byte-identical, so it stays group B |

Group C's clock: today = **Wed 14 Oct 2026**, so `M` = **Mon 19 Oct** (the
first Monday ≥ today + 2) and item 16's `k` = d + 1 = (M + 4 − today) + 1 =
**10** — the footer reads `10 of 15`. Group A's clock was Thu 8 Oct (`M` =
12 Oct, `9 of 15`). The `fresh` dataset's dates are absolute (week 28 Sep –
4 Oct 2026), so its frames are navigated to by date; at group C's clock that
week is history (washed blocks, `Done` / `Skip` still enabled — §18.1).

- **Appearance:** group A's live frames are dark (the system's at that
  capture), except item 19's light frame, which sets Kadence's own appearance
  with the review-only `-KadenceAppearance light` (the system setting is
  never touched). Group C's live frames are light (the system's at this
  capture). Renders are light.
- **Edge check (§17.2 rule 6):** `Scripts/check-frame-edges.py` on all
  **40** frames: **39 ok** with no accent pixel in the 2px band; item 16
  (`conflict-lecture-training-p3.png`) **ok under the rule-6 exemption**
  (`--preview`: a complete 2pt border x 480–2357, y 104–1799). It is the only
  preview frame. (`cascade-gap-p3.png` first flagged: the render had no
  margin and a lecture's blue fill touched the edge; re-rendered with 12pt of
  canvas round it — ok.)
- **Passwords:** shown only as `SecureField` bullets (items 2, 4). The
  connect captures type a non-secret filler (the review mock accepts any
  password for `user01`, DEVIATIONS B43); the script asserts the filler is in
  no AX value.

## Items

| § 22 item | File(s) | Group | Dataset · mocked case | Notes |
|---|---|---|---|---|
| 1 Sidebar, first run | **`real-first-run-p3.png`** (item 22) | C | `empty` | Replaced, as §22 item 22 says: the old `sidebar-first-run-p3.png` (the Phase 2 dataset with eight sources) is deleted |
| 2 Step 1 empty / filled | `connect-step1-empty-p3.png`, `connect-step1-filled-p3.png` | A | `phase2` · `reportOK` | Server prefilled, `Connect` disabled when empty; `user01` + bullets |
| 3 Connecting | `connect-step1-connecting-p3.png` | A | `phase2` · `slow` | spinner + `Connecting to cis.technikum-wien.at…`, fields disabled |
| 4 Failures | `connect-step1-unauthorized-p3.png`, `connect-step1-certificate-p3.png`, `connect-step1-nocaldav-p3.png`, `connect-step1-webdav-hint-p3.png` | A | `phase2` · `unauthorized`, `certificate`, `wellKnown404`, — | Password focused with its contents selected; focus on Connect; Server focused; the WebDAV-share message |
| 5 Step 2, one calendar | `connect-step2-single-p3.png` | A | `phase2` · `reportOK` | confirmed row `✓ LVPlan` (no checkbox — asserted live), `13 events, 2 Oct 2026 – 23 Oct 2026`, history `2`, co-teaching `1` |
| 6 Step 2, several | `connect-step2-checklist-p3.png` | A | `phase2` · `multiCalendar` | `LVPlan`, `Prüfungen` checked; `Aufgaben`, `outbox`, `inbox` absent |
| 7 Edit mode | `connect-edit-p3.png` | A | `phase3` · `unauthorized` | Server/Username prefilled, Password empty with `Saved in Keychain`, focused; the system's `Passwords…` AutoFill suggestion (system chrome, review §4.2) |
| 8 Settings ▸ Sources | **`settings-sources-uptodate-p3.png`** (+ `settings-sources-empty-p3.png`, group A) | C | `phase3` · `reportOK` (empty: `phase2`) | `Up to date`, `Synced just now · 13 events`; **`Sync Now` a plain bordered button, not the default** (fix 10b); `Account`, `Calendar LVPlan`, `Every 30 minutes`; the list holds focus |
| 9 Sidebar row, four states | `sidebar-row-states-p3.png` (render) + `sidebar-live-p3.png` | B, A | render; `phase3` · `forbidden` | spinner, empty slot, secondary glyph, alert glyph; checkboxes in one column |
| 10 Source popover | **`source-popover-forbidden-p3.png`**, **`source-popover-partial-details-p3.png`** (render) | C, D | `phase3` · `forbidden`; render | `Access refused`, `Edit Account…` default, **`Last synced today … · 13 events`** (fix 9: the review source is seeded as imported); details expanded with §19.3's exact sentences: `SWQM-ILV ends before it starts, so it was skipped.` / `Object obj-07.ics, line 9: DTEND before DTSTART`, `1 event couldn't be read.` / `Object obj-11.ics: not calendar data` (fix 8) |
| 11 Week `M` | **`week-M-p3.png`** | C | `phase3` · `reportOK` | 19–25 Oct. The lectures; `REQEN-EXAM` with `graduationcap.fill`; **Friday's `SWRM-ILV` named** in its title band above `Training` (fix 6); meta lines `HS_A3.15 · Univer…`, **`Online · University…`** for `INNO3-EL` at Week width (fix 7). `day-inno3-online-p3.png` is **dropped** (deleted): Week now shows `Online` itself |
| 12 After the second sync | **`week-M-after-change-p3.png`**, **`source-popover-last-change-p3.png`** | C | `phase3` · `reportChanged` (⌘R) | **`SWEN3-LAB` reads `EDV_F4.26 · Unive…`** — the room the first frame could not show; `EPC-ILV` (Thu 22) gone; `Last change just now: 2 added · 2 updated · 2 removed` |
| 13 Inspector, `SWQM-ILV` | `inspector-imported-p3.png` | A | `phase3` · `reportOK` | read-only line, `Lecturer L01`, `Group BIF-5C`, `Room HS_A3.15`, Source + `Synced HH:mm`, no Description |
| 14 Inspector, `INNO3-EL` | `inspector-lecturers-collapsed-p3.png`, `inspector-lecturers-expanded-p3.png` | A | `phase3` · `reportOK` | `L10`, `L11`, `L12`, `and 19 more` / all 22 + `Show fewer`; `Room Online · WEBINAR01` |
| 15 A refused edit | `inspector-refusal-emphasis-p3.png` | A | `phase3` · `reportOK` | taken right after ⌫: the read-only line in `text.primary` |
| 16 Conflict panel | **`conflict-lecture-training-p3.png`** | C | `phase3` · `reportOK`, `-KadenceConflictUnderTest SWRM-ILV` | three options, `Shift Training 45 min later` recommended and previewed, the canvas border, **`10 of 15`**; on the grid `SWRM-ILV` now carries its title |
| 17 Popover, imported NEXT | `popover-imported-next-p3.png`, `popover-stale-line-p3.png` (renders) + `popover-live-p3.png` | B | render; `phase3` · `reportOK` | `Done` · `Open`, no `Snooze`; the stale line; the live frame shows the popover's real chrome only (review §4.6) |
| 18 Removal alert | `remove-source-alert-p3.png` | A | `phase3` · `reportOK` | `Cancel` the default; ⎋ cancelled it |
| 19 All-day pill + done, light/dark | `allday-and-done-light-p3.png`, `allday-and-done-dark-p3.png` | A | `phase3` · `reportOK` | **measures colour — appearance in the file name**: `Studieninformationstag` (`.eventAllDay`) and `SWQM-ILV` done: label, checkmark and meta in `text.primary` (§6, G-074 — now the rule, not a placeholder) |
| 20 Cancelled | `cancelled-block-p3.png`, `inspector-cancelled-p3.png` (renders) | B | `edge-cases.ics` | dashed border, `xmark.circle`, `Cancelled · University timetable`; inspector `Cancelled by University timetable`, Done/Skip disabled |
| 21 Calendar missing | **`source-popover-calendar-missing-p3.png`** | C | `phase3` · `calendarGone` | `Choose Calendar…` the default; **`Last synced just now · 13 events`** under "Events from the last sync are kept" — no longer `Never synced` (fix 9) |
| **22** A real first run | `real-first-run-p3.png` | C | `empty` | the sidebar lists exactly `Personal`, `Daily routine`, then `Connect Timetable…`; no Needs attention row; an empty week (12–18 Oct) |
| **23** After the Import on a fresh store | `fresh-week-sidebar-p3.png` | C | `fresh` · `reportOK` | week 28 Sep – 4 Oct: `Personal`, `Daily routine`, `University timetable` — **one** timetable row, `blue` swatch with `tablecells.fill`; the lectures blue; **no Needs attention row** |
| **24** Fri 2 Oct, two sessions | `fresh-overlap-week-p3.png` (Week, cascade), `fresh-overlap-day-p3.png` (Day, packed), `cascade-gap-p3.png` (render) | C, C, D | `fresh` · `reportOK` | Week: `BPREF-Info` 18:35 keeps its title in its band; the 19:30 session is indented with 2pt of canvas on its leading and top edges. Day: packed side by side, `Online · University timetable` on the 18:35 block. The render is the same pair at the engine's 124pt column, larger. (`fresh-week-sidebar` and `fresh-overlap-week` are separate launches of the same view and came out byte-identical) |
| **25** Inspector, `BPREF-Info` 18:35 | `inspector-bpref-two-lecturers-p3.png` | C | `fresh` · `reportOK` | `building.columns` + the blue timetable swatch; `Read-only — from University timetable`; **`Lecturers L05, L06`**; `Room Online · WEBINAR02`; Source row with the timetable swatch; `Done` / `Skip` enabled (history) |
| **26** Room before source | `week-M-p3.png`, `week-M-after-change-p3.png` | C | `phase3` · `reportOK`, `reportChanged` | `.full` lectures read `HS_A3.15 · Univer…`; item 12's `SWEN3-LAB` reads `EDV_F4.26 · Unive…` |
| **27** Settings ▸ Sources on `fresh` | `settings-sources-fresh-p3.png` | C | `fresh` · `reportOK` | `Synced just now · 13 events`; `Sync Now` an ordinary bordered button. (Byte-identical to item 8's frame: same visible content on another dataset) |

Deleted in fix 11: `sidebar-first-run-p3.png` (superseded by item 22) and
`day-inno3-online-p3.png` (no longer needed beside Week `M`; it also carried
the toolbar focus ring fixed in fix 10c).
