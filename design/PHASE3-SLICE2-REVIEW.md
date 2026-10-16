# Phase 3 slice 2 — design review (leave-by from Apple Maps, notifications)

Design agent, 2026-10-15. Reviewed: CA's run `b5d7ab2 … e50d062` (18 tasks,
1067 tests green), STATUS §133–§136, DEVIATIONS A41, A42, B48–B54, GAPS
G-097–G-100, `screenshots/3b/INDEX.md` and all 59 frames, both plan files,
and the Swift sources wherever a frame or plan could not prove a rule
(planner, origin rule, cache key, queue, failure copy, location path, log
lines, launch-kind factories, notification copy and identifiers, routine
materialisation, time-window spans, grid geometry). Nothing was launched;
no store was opened; no prompt, notification, MapKit, location or network
request was made. One throwaway Swift check of Foundation's date arithmetic
on 25 Oct / 29 Mar ran in the scratchpad (no app code).

## Verdict

**ACCEPTED AFTER FIXES** — five fix tasks, `P3S2-F01` … `F05`.

The slice is good work. Routing, the cache, the queue, failure states, the
location rule, the notification planner, scheduler, actions and N8 all match
the spec, and the two plan files match §30.1's tables row for row. The copy
on every captured surface is exact. The privacy rule holds in the source:
every log line is a fixed §24.11 form. Every factory reads one launch-kind
table, and only a normal launch builds MapKit, CoreLocation, `NWPathMonitor`
or `UNUserNotificationCenter`.

One fix is urgent and bigger than reported. **G-100 is not only drawing.**
Routine instances and protected-window spans are built as `startOfDay +
minutes`. So on Sun 25 Oct a 20:00 routine block *is* 19:00 CET in the
inspector, the popover and its notification, and Sleep ends at 06:00. On
the grid the two errors cancel, which is why the routine looked right in
`phase3-week-M-p3b.png`. Verified with Foundation:
`date(byAdding: .minute, value: 1200, to: startOfDay(25 Oct))` = 19:00 CET.
F01 fixes all of it and must ship before Sun 25 Oct.

The other four are small: no invented facts in copy (F02), the popover leave
line wraps (F03), the campus lookup at first launch (F04), and recaptures
(F05).

---

## 1. §30 items

| # | Item | Evidence | Result |
|---|---|---|---|
| 1 | Settings ▸ Travel, first run | `settings-travel-first-run-p3b.png` | **Fix (capture).** Copy is right (Home empty with placeholder `Address`, campus `Höchstädtplatz 6, 1200 Wien, Austria`, footer), but the frame is the Places section only. Missing: the three tabs, `Usually`, the one pair row `Usual`, `Buffer 10 minutes`, `Use where you are` on with no block. → F05 |
| 2 | Settings ▸ Travel, filled | `settings-travel-ways-p3b.png`, `settings-travel-live-p3b.png` | **Pass.** Three places, `⊖` on Gym only, footer names the campus, `Home ↔ Gym Walking`, other pairs `Usual`. §30 said `Usual (Public transport)`; layouts §13 (closed pop-up shows `Usual`) wins, and §30 is amended |
| 3 | Notifications, allowed | `settings-notifications-allowed-p3b.png`, `-live-` | **Pass.** Five rules at defaults, `Sync problems` switch only, quiet footer exact |
| 4 | Notifications `off` / `notAllowedYet` | `settings-notifications-off-p3b.png`, `-not-allowed-yet-` | **Pass.** Both blocks exact (§27.8), buttons right, `Routine` off with its pop-up disabled, not hidden |
| 5 | Week `M` | `week-M-travel-p3b.png` | **Pass.** Bands where §24.4 has legs, none on `SWEN3-ILV`, `INNO3-EL`, `Laundry`, `REQEN-EXAM`; nothing selected. Opens at 06:00, which is right by layouts §3.1 (Early study 07:30), and §30's "scrolled to 07:00" is amended. Week labels `Leave HH:mm` per B53 |
| 6 | Week `M`, early and late | same frame | **Pass.** `Leave 06:45` across Sleep's end; `Late call` 23:15, no band |
| 7 | Day Thu `M + 3` | `day-thu-travel-p3b.png` | **Pass.** `Leave 12:15 · 35min` case 1, no band on `REQEN-EXAM`, `Leave 17:45 · 35min` |
| 8 | Case-2 band, `Climbing` | `day-sun-climbing-p3b.png`, `week-M-travel-p3b.png`, `band-states-p3b.png` | **Fix.** The render is right (`figure.walk`, `Leave 17:45 · 5min`). In both live frames `Climbing` 18:00 and its band sit on the 19:00 row: Sun 25 Oct is the clock change (G-100). → F01, recapture F05 |
| 9 | Inspector `SWQM-ILV` | `inspector-swqm-live-p3b.png`, `inspector-swqm-leave-p3b.png` | **Pass.** `Room HS_A3.15`, `Place FH Technikum Wien`, `Leave by 08:15`, `35 min by public transport from Home · 10 min buffer`, `Worked out today 06:00 by Apple Maps.` |
| 10 | Inspector `REQEN-EXAM` | `inspector-reqen-no-travel-p3b.png` | **Pass.** `No travel needed after EPC-ILV`, no `Leave by` |
| 11 | Inspector `Dinner` + pop-up | `inspector-dinner-place-p3b.png`, `inspector-dinner-popup-p3b.png` | **Pass.** Pop-up `Home`; `17:45`, `… from FH Technikum Wien · 10 min buffer`; open: `None` · sep · Home · FH Technikum Wien · Gym · sep · `Edit Places…`. Side note: `Origin manual` (lowercase) beside `Imported`. This predates the slice; layouts §6 is amended → F02 |
| 12 | No address | `inspector-no-address-p3b.png`, `week-M-no-address-p3b.png` | **Pass.** `Unavailable`, the sentence exact, `Add Address…`; Week has no bands |
| 13 | Status item renders | `status-item-*-p3b.png` (7) | **Pass, one frame missing.** Leave full / degraded / now / late / takeover / no takeover / estimate all exact. The `unavailable` row is asserted by a test only (G-099). Ruled: truncation stands, §30 amended. → frame in F05 |
| 14 | Notification plan | `notification-plan-travel.txt`, `notification-plan-live-p3b.txt` | **Pass.** Thu 06:00 and Fri 23:00 tables exact: identifiers, fire times, titles, bodies, categories, sounds, levels. Live plan: P6's leave-by fires at its own time inside Sleep (the event is inside it, §27.5 rule 2). Dump defect: the catch-up sections were planned at 12:14 / 12:22 / 13:07, not the stated 12:12 / 12:20 / 13:05, because `launchAndSettle` drains seven routing requests first. The results happen to be the same, but the evidence is not at the spec's clock. → F05 |
| 15 | Popover renders | `popover-*-p3b.png` (11) | **Fix.** Leave, Leave now (light/dark, `semantic.now`), Late, takeover (`EPC-ILV` first rest row), manual NEXT (`Done · Snooze · Open`), both notification lines, meta line order, estimate, `unavailable · offline`: all exact. **But** `popover-no-address` reads `Travel time unavailable · Home has n…` and the manual / takeover frames read `35 min from FH Tec…`, so the line cuts off the one fact it exists to give. The build follows the spec (`lineLimit` 1); the spec is wrong and is amended to `lineLimit` 2 → F03. **Missing frames:** `pending` and `from where you are` (tests only) → F05 |
| 16 | Live status item + popover | `status-item-live-p3b.png`, `popover-live-p3b.png` | **Fix (recapture).** Content is right (`Leave 02:30 · Pick up parcel`, `Leave by 02:30 · 35 min from Home`, `03:15 – 03:45 · Personal`). But it was captured at 02:13, against §30.1's "between 07:00 and 20:00", so P6 lies inside Sleep. → F05 |
| 17 | Regression `phase3` | `phase3-today-p3b.png`, `phase3-week-M-p3b.png` | **Pass.** `Datenmodellierung` `Leave 08:38`, `Coffee with Nora` `Leave 10:54`, Week `M`'s lectures with 22-min walking bands. (The Sunday 25 Oct routine blocks are an hour early as data: G-100, F01) |
| 18 | Looking up an address | `settings-travel-lookup-*-p3b.png` (7) | **Pass.** All seven lines and controls exact, `Use This Address` is the default action (`.keyboardShortcut(.defaultAction)`, so grey in an inactive offscreen window), `⎋` cancels. `-many-` crops `Add Place` at the bottom edge → taller frame in F05 |
| 19 | Location states | `settings-travel-location-*-p3b.png` (4) | **Pass.** Three blocks exact (§24.12), switch off → no block |
| 20 | Week `M`, estimates | `week-M-estimates-p3b.png`, `inspector-epc-estimate-p3b.png`, `inspector-dinner-unavailable-p3b.png` | **Pass.** Week `Leave ≈08:15` (B53's short form keeps the mark; §30 amended), no band on Dinner or Climbing. EPC inspector `12:15 estimate`, `About 35 min …`, `Last worked out 27 Sep 18:00 by Apple Maps. Couldn't update: this Mac is offline. …`; Dinner `Unavailable` + the offline sentence |
| 21 | `noRoute` | `inspector-climbing-no-route-p3b.png` | **Pass.** Sentence with `walking`, `Change Way to Travel…` |
| 22 | Now time vs hour label | `now-label-*-p3b.png` (3) | **Pass, one frame missing.** 10:18 drops `10:00` in Week and Day; 10:40 keeps both. The cursor case is tested only → frame in F05 |
| 23 | Plan, routing and sync | `notification-plan-travel.txt` | **Pass.** `travelOffline` N1e / N7 and recovery under the same ids; `travelNoAddress` N7 ×3 at start − 60; refresh 50 / 78 (at once) / 30; from where you are 12:22; N8 `unauthorized` / `forbidden` exact; held 03:00 → 07:00 |

## 2. Exact copy

All checked against frames, plan files and `TravelPresentation.swift`,
`MenuBarFormatting.swift` and `NotificationCopy.swift`:

- **Leave line, popover** (§26.2): all seven forms exact. Wrapping → F03.
- **Band label and hover help** (§25.1): `Leave 08:15 · 35min`, `· ≈35min`,
  `Leave ≈08:15`, glyph by mode; hover `Leave 08:15 · 35 min by public
  transport from Home · 10 min buffer` (buffer omitted at 0), the estimate
  form with `about` twice and `· estimate, {reason}`, the `· Travel time
  from Home …` suffixes. Exact.
- **Inspector `Leave by`, four states** (layouts §6): ready, estimate (word
  `estimate`, `About …`, `Last worked out … Couldn't update: {sentence}`,
  `Try Again` only for `failed`), pending (`Working out…` / `Kadence is
  asking Apple Maps for the trip from Home.`), unavailable (sentence +
  button). Exact; never `semantic.now`.
- **N1, N1e, N7, N8**: exact in the plan file (§27.4, §30.1).
- **Settings ▸ Travel lookup lines** (§23.5): exact in all seven frames.
- **Settings ▸ Notifications permission states** (§27.8): exact.
- **One defect across all of them: invented fallbacks.** When a value is
  missing, the copy code supplies one:
  - `originName … ?? "Home"` (`TravelPresentation.swift:46`,
    `NotificationPlanner.swift:261`);
  - `?? "offline"` and `leg.reason ?? .offline` for an estimate's reason
    (`TravelPresentation.swift:100, 187, 190`, `MenuBarFormatting.swift:78`,
    `NotificationPlanner.swift:195`);
  - `?? "Apple Maps didn't answer"` (`MenuBarFormatting.swift:91`);
  - `leg.duration ?? 0` (`MenuBarFormatting.swift:81, 123`,
    `TravelPresentation.swift:176`, `NotificationPlanner.swift:182`);
  - `?? "This place"`, `?? "later"` (`NotificationCopy.swift:31, 34`).

  None fires with the fixtures, because the recompute always sets these
  values. But each is a fact stated without evidence, and DECISIONS
  2026-10-14 ("A failed route is said, never guessed") forbids exactly
  that. §24.10 is amended (omit, never fill in) → F02.

## 3. Never a guessed number, the location rule, the log forms

- **Never a guessed number.** Holds in the planner: §24.10's order with
  `noRoute` / `needsAddress` never falling back, B49's same-trip rule, no
  manual provider, B48 rounding up only. The only exceptions are the
  copy-level `?? 0` / `?? "offline"` above (F02).
- **Location** (`TravelCoordinator.refreshFromHere`):
  - only the next departure's leg (`departAt − 45 ≤ now`, or `start − 105`
    with no time);
  - only its T−45 slot or a launch or wake catching that slot up;
  - only with `useCurrentLocation` on;
  - ask once, `locationRequestedAt` recorded;
  - a fix used only if ≤ 2 min old, accuracy ≤ 200 m and > 300 m from the
    rule origin (`LocationRules`);
  - the fix lives in the function and the queued job; the leg gets
    `originKind currentLocation`, `originPlaceID nil` and no coordinate;
  - the ETA is never cached (key `here:{eventID}`);
  - never logged.

  **Pass.**
- **Log forms** (§24.11): every write in the app is one of: `eta ok · N min
  · mode[ · refresh][ · here]`, `eta failed · {offline|noRoute|throttled|
  failed} · mode`, `queue paused · until HH:mm`, `lookup ok · N results` /
  `lookup none` / `lookup failed · word`, `location used` / `not used ·
  within 300 m` / `unavailable · denied|timeout`, and `notification degraded
  · time-sensitive unavailable`. Interpolated values are counts, minutes,
  mode raw words, error words and a clock time. **No address, coordinate,
  place name, title or search text.** Only `RoutingLog` forwards to
  `os.Logger` (`.public`, normal launch only). **Pass.**
- **Launch kinds**: `ServiceImplementation.of(_:)` is the one table. Mocks
  and scripted / recording doubles are used for review and the test host;
  `SystemNotificationCenter` sets its delegate only when constructed (normal
  launch). Every review launch's `launch-services.txt` lists mocks only.
  **Pass.**
- **Not a code defect, but blocks real use: G-096 item 2.**
  `INFOPLIST_KEY_NSLocationUsageDescription` / `…WhenInUse…` are still
  absent from the project. Without them `Use where you are` never gets a
  prompt in a real launch. Parsa's (Xcode); see "For Parsa".

## 4. Deviations

| Entry | Ruling | Spec |
|---|---|---|
| **A41** — the `copies` field, `merged − copies`, G-081's sentence | **Deferral accepted**, still normative (DECISIONS 2026-10-14 "Slice 2 defaults"). With the next CalDAV task | — |
| **A42** — now time and hour labels measured as drawn | **Accepted, done.** Frames item 22; boundaries pinned. F01's §31.3 keeps the suppression on the new y | — |
| **B48** — travel time rounded up to the minute | **Accepted; better than the spec.** The band adds up and the departure only moves earlier | §24.3 amended |
| **B49** — own last time only for the same trip | **Accepted; better than the spec.** Another trip's time would be a guess | §24.10 step 2 amended |
| **B50** — no `NWPathMonitor` outside a normal launch | **Accepted** (a fix the spec already required, §24.11) | — |
| **B51** — a pending leg's refresh is its queued request | **Accepted; better than the spec.** Keeps one call per key | §24.6 amended |
| **B52** — test harness file-store lifetime | **Accepted** (tests only) | — |
| **B53** — narrow band drops minutes, never the time | **Accepted; better than the spec.** `Leave 0… · 35min` hid the time | §25.1 amended; §30 items 5, 20 amended |
| **B54** — review fixtures anchored (stale entry; wall-clock manual events) | **Accepted.** Its second half is the same fault as G-100; F01 makes every fixture wall-clock | §31.4 |

## 5. Gaps

| Gap | Ruling |
|---|---|
| **G-097** counts of dataset `travel` | **Closed.** The composition is the definition: 14 VEVENTs, 13 events, 2 history; "Cache sharing" names the 7 keys. §30.1 corrected. No code change |
| **G-098** when the campus is looked up | **Closed, build open (F04).** §23.6 amended: **at the first launch**, one request per install, so a real first launch shows what §30 item 1 shows and the review-only switch goes |
| **G-099** item 13's last row at 180pt | **Closed.** §15.1's truncation stands; item 13's `unavailable` and `takeover` rows amended to "truncated as measured". Needs a frame (F05) |
| **G-100** clock-change day | **Closed on the spec side (new §31), build open (F01).** Wider than reported (routine data, window spans, now line, drag, initial scroll, Routines window) |
| **G-101** (new) a note on the change day | **Deferred.** §31 draws nothing extra |
| **G-096** (Parsa) | Still open: the location usage keys are missing |

## 6. The two items Parsa knows about

1. **Live leave-by needs his Home address — expected, not a fix.** With
   Home `none` every trip from home is `unavailable · needsAddress (Home)`:
   no band, the inspector says `Add the address of Home in Settings ▸ Travel
   …` with `Add Address…`, the popover says `Travel time unavailable · Home
   has no address`, and the event gets N7 an hour before it starts (§24.3,
   §24.10, §27.2; item 12 shows it). Chained events (campus → campus) need
   no leg either way. Typing the address in Settings ▸ Travel and
   confirming what Apple Maps found fills every leg.
2. **Week opens around 04:00 instead of 07:00 — the spec says this is
   correct when something in the visible week starts between 05:00 and
   05:59.** layouts §3.1: `min(07:00, floorToHour(firstEventStart − 1h))`
   over **all seven columns and every timed event, routine blocks
   included**; 05:30 → 04:00. The code does exactly that
   (`InitialScroll.minute`). So it is **not a fix** if Parsa's week has a
   05:xx block (a morning routine block is the likely one). If nothing in
   that week starts before 06:00, it is a bug in the hold; he reports the
   week and CA adds it as a test. The reading is now written into layouts
   §3.1. Separately, F01 fixes the one real scroll bug found: on a
   spring-forward week a 06:00 event opened the view at 04:00.

---

## 7. Fix list

Run in this order. One commit per task (`CA P3S2-F<NN>`), the whole suite
green after each (`-only-testing:KadenceTests`), real store `stat` unchanged,
tokens `--check` clean. Frames go into `screenshots/3b/` as
`<name>-p3bf<NN>.png`.

### P3S2-F01 — Wall-clock times on clock-change days (G-100) — **ship before Sun 25 Oct 2026**

**Wrong.**

- *Drawn:* `TimeGeometry.y(for:)` places a moment by seconds since
  midnight, so `Climbing` 18:00 CET is drawn on the 19:00 row with its band
  (`day-sun-climbing-p3b.png`, `week-M-travel-p3b.png`).
- *Data:* `RoutineEngine.materialize` / `templateValues`
  (`date(byAdding: .minute, startMinutes, to: day)`), `TimeWindow.spans`,
  `NotificationPlanner`'s quiet spans and `TimeWindowFixture` add elapsed
  minutes to midnight. On 25 Oct that gives a 20:00 routine block **at
  19:00 CET** and Sleep ending at **06:00 CET** / starting at **21:00 CET**.
  On 29 Mar it gives 21:00 CEST and 08:00 CEST. Verified with Foundation in
  the scratchpad.
- *Now line:* the column's now line uses elapsed time while the gutter's now
  time uses wall-clock, so after the change they are an hour apart.
- *Other paths:* drag, resize, create and preview; initial and conflict
  scroll; window labels; and the Routines window all use the same elapsed
  maths.

**Expected.** `components.md` **§31** (new): one pure `WallClock` pair
(`minuteOfDay(_:on:)`, `moment(minuteOfDay:on:)`; repeated hour → first
occurrence, missing hour → forward by the gap). The drawing rule for
intervals is §31.2: back-through-the-repeated-hour, the band anchored to its
parent, overlap on drawn intervals while conflicts stay on instants. The now
line and cursor follow §31.3, and the full list of call sites is §31.4. 24
rows, no marker. Durations unchanged. Instances already materialised wrong
are corrected by the next materialisation (detached ones untouched).
`layouts.md` §3.1 amended for the initial scroll.

**Files likely touched**

- new: `Kadence/Layout/WallClock.swift`
- `Layout/`: `TimeGeometry.swift`, `DayLayoutEngine.swift` (or its caller:
  feed it drawn intervals), `InitialScroll.swift`,
  `WindowLabelPlacement.swift`, `RoutineWeekLayout.swift`
- `Views/Canvas/`: `GridLayers.swift` (now line, window bands),
  `DayColumnView.swift` (blocks, band, drag / resize / preview),
  `TimedCanvasView.swift` (conflict scroll)
- `State/RoutineEngine.swift`; `Models/TimeWindow.swift`,
  `Models/DisplayFixtures.swift`
- `Services/Notifications/NotificationPlanner.swift` (reuse
  `TimeWindow.spans`)
- `Views/Routines/RoutinesWindow.swift`,
  `Views/Routines/TemplateConflictPanelView.swift`
- `Mock/MockData.swift`, `Review/TravelDataset.swift` (P6)

**Tests.** New `KadenceTests/Slice2/ClockChangeTests.swift` with §31.5's
**T1–T12**, exactly:

- T1: `WallClock` on 25 Oct, 29 Mar and 22 Oct.
- T2: Day 25 Oct — before / across / both 02:00 hours side by side with no
  conflict / back-through / `Climbing` and band / routine 20:00 → 20:00 CET.
- T3: Day 29 Mar — before / across / `Climbing` / routine 20:00 → 20:00
  CEST / routine 02:30 → 03:30 CEST.
- T4: Week of both changes, Mon–Sat unchanged.
- T5: Month of both.
- T6: Now line equals the gutter label at eight clocks.
- T7: Initial scroll 05:00 ×3.
- T8: Sleep spans and the quiet rule — 06:40 → 07:00 on both days, 21:30
  CET not held.
- T9: Routine data and notification 19:55; an old-maths instance corrected,
  a detached one kept.
- T10: Drag to y(20), y(2.5) on both days.
- T11: `Climbing`'s leg and `leave.` at 17:40 CET.
- T12: The source scan.

Existing tests pinned to elapsed maths on an ordinary day must not change.
If one does, it is a regression; stop and report.

**Frames** (offscreen, §30 item 24, clock pinned):

- `dst-day-1025-p3bf01.png`, `dst-week-1025-p3bf01.png`,
  `dst-month-1025-p3bf01.png` — clock Sun 25 Oct 18:30 CET;
- `dst-day-0329-p3bf01.png`, `dst-week-0329-p3bf01.png`,
  `dst-month-0329-p3bf01.png` — clock Sun 29 Mar 18:30 CEST;

each with T2 / T3's events, the routine block, `Climbing`'s band and the now
line. The live recaptures of items 5, 6 and 8 are F05's.

### P3S2-F02 — No invented fact in the copy; `Origin` as a word

**Wrong.** §2's list: `?? "Home"`, `?? "offline"` / `?? .offline`, `?? "Apple
Maps didn't answer"`, `?? 0` minutes, `?? "This place"`, `?? "later"` in
`TravelPresentation.swift`, `MenuBarFormatting.swift`,
`NotificationCopy.swift` and `NotificationPlanner.swift`. And `Origin
manual` in the inspector (`InspectorView.swift:111`, raw enum) beside
`Imported` (`inspector-dinner-place-p3b.png`).

**Expected.**

- `components.md` §24.10, "No invented fact in the copy either": the clause
  that would state a missing value is omitted with its separator. Examples:
  `Leave by 08:15 · 35 min`, `Leave by ≈08:15 · estimate`, `Travel time
  unavailable`, N1 `Starts 09:00 · HS_A3.15 · 35 min`, N7 `{where} · Travel
  time from Home unavailable. Check your route before you leave.`, hover
  `Leave 08:15 · 35 min by public transport` (no `from …`), VoiceOver
  likewise.
- The planner side keeps the invariant: a removed place's legs are rewritten
  in the same pass (already true; assert it).
- `layouts.md` §6 row 4: `Origin` reads `Manual` · `Routine` · `Imported` ·
  `Planned`.

**Files.** `Views/Blocks/TravelPresentation.swift`,
`Views/MenuBar/MenuBarFormatting.swift`,
`Services/Notifications/NotificationCopy.swift`,
`Services/Notifications/NotificationPlanner.swift`,
`Views/Chrome/InspectorView.swift`.

**Tests.** For each surface (band hover, VoiceOver, inspector row, popover
line, status item label, N1 / N1e / N7 / N2 / N3), a leg with
(a) an unresolvable origin id, (b) an estimate with `reason nil`, (c) an
unavailable with `reason nil`, and (d) a `paused` with `retryAt nil` → the
strings above, and a scan that none contains `Home`, `offline`, `0 min`,
`This place` or `later` unless the leg says so. An inspector test for
`Origin Manual` / `Routine`. All existing copy tests unchanged.

**Frames.** None (the fixtures never hit the fallbacks).
`inspector-dinner-place-p3bf02.png` (offscreen) shows `Origin Manual`.

### P3S2-F03 — The popover's leave line wraps to two lines

**Wrong.** `popover-no-address-p3b.png`: `Travel time unavailable · Home has
n…`; `popover-manual-next-p3b.png`, `popover-takeover-p3b.png`: `Leave by
17:45 · 35 min from FH Tec…`. The build follows §26.2's old `lineLimit` 1;
the spec was wrong.

**Expected.** `components.md` §26.2 amended:

- the leave line has `lineLimit` 2, tail truncation only after the second
  line;
- `Leave by HH:mm` / `Leave now` are never split or truncated;
- the meta line stays `lineLimit` 1;
- the NEXT block grows by the extra line (`size.popoverNextBlockMinHeight`
  stays a minimum).

Every popover state otherwise unchanged.

**Files.** `Views/MenuBar/MenuBarPopoverView.swift` (~462).

**Tests.** The render test at the popover's width:

- `Travel time unavailable · Home has no address`,
  `Leave by 17:45 · 35 min from FH Technikum Wien` and
  `Travel time unavailable · Apple Maps paused until 10:40` are drawn
  whole on ≤ 2 lines;
- `Leave by 12:15 · 35 min from Home` stays one line;
- a 60-character place name truncates on line 2 with the time intact.

**Frames** (offscreen): `popover-no-address-p3bf03.png`,
`popover-manual-next-p3bf03.png`, `popover-takeover-p3bf03.png`,
`popover-leave-p3bf03.png` (unchanged one-line case).

### P3S2-F04 — The campus is looked up at the first launch (G-098)

**Wrong.** Real launches look the campus up only when a recompute first
needs it, and review `empty` / `fresh` set `looksUpCampusAtLaunch` (a review-only
behaviour), so §30 item 1 shows a state a real first launch never shows.

**Expected.** `components.md` §23.6 amended: at the first launch (after the
built-ins exist), while the campus address is Kadence's own and not
confirmed, one automatic lookup through the queue (priority 0 is not
needed; 3 is fine). Then the existing rules: match →
`confirmed`; else `unconfirmed` / `notFound` / `lookupFailed`; a failure
retried at most once a day at launch or wake; never after the user edits
it. Remove `looksUpCampusAtLaunch` and its review switch
(`KadenceApp.swift:87`, `TravelCoordinator.swift:72, 241`).

**Tests.**

- A fresh store with no events, at launch: one lookup, campus `confirmed`
  with the mock coordinate, no ETA request.
- The same launch offline: `lookupFailed`, retried the next day at launch,
  not again that day.
- A store where the user edited the campus address: no automatic lookup.
- `ReviewTravelTests` `empty` / `fresh` still `confirmed` without the
  switch.

**Frames.** None of its own (item 1 is recaptured in F05).

### P3S2-F05 — Recapture, missing frames, the plan dump; `INDEX.md`

**Wrong.**

- Items whose frames changed with F01–F04.
- Item 1 is the Places section only.
- Item 13's `unavailable` row, item 15's `pending` and
  `from where you are`, and item 22's cursor case have no frames.
- Item 16 was captured at 02:13, against "between 07:00 and 20:00".
- Item 18 `many` crops `Add Place`.
- The plan dump's catch-up sections were planned at 12:14 / 12:22 / 13:07,
  not 12:12 / 12:20 / 13:05.

**Expected — frames to (re)capture** into `screenshots/3b/`:

| Item | Frame | Kind |
|---|---|---|
| 1 | `settings-travel-first-run-p3bf05.png` — the **whole** pane in a Settings window: three tabs, Places, Ways (`Usually Public transport`, `Home ↔ FH Technikum Wien Usual`), `Buffer 10 minutes`, `Use where you are` on, no block. Dataset `empty`, after F04 with no review switch | live (or offscreen of the full pane, if the window can't show it all: two frames, top and bottom) |
| 5, 6, 8 | `week-M-travel-p3bf05.png` (`Climbing` on the 18:00 row with its band from 17:45), `day-sun-climbing-p3bf05.png` | live, after F01 |
| 12, 20 | `week-M-no-address-p3bf05.png`, `week-M-estimates-p3bf05.png` | live, after F01 (Sunday column) |
| 13 | `status-item-unavailable-p3bf05.png` — `18:30 · Dinner with flatmat…` | offscreen |
| 15 | `popover-pending-p3bf05.png` (`travelPending`, Thu 11:50: `Travel time from Home not worked out yet`), `popover-from-here-p3bf05.png` (Thu 12:00, `-KadenceLocation allowed`: `Leave by 12:22 · 28 min from where you are`) | offscreen |
| 16 | `status-item-live-p3bf05.png`, `popover-live-p3bf05.png` — launched **between 07:00 and 20:00** | live |
| 17 | `phase3-week-M-p3bf05.png` (Sunday's routine blocks after F01) | live |
| 18 | `settings-travel-lookup-many-p3bf05.png` — frame tall enough for `Add Place` | offscreen |
| 22 | `now-label-cursor-week-1018-p3bf05.png` — cursor hovering at 10:18, `10:00` dropped | offscreen |

**Plan dump.** In `NotificationPlanDumpTests`, the catch-up cases seed the
ETA cache (or the legs) so the launch pass runs **at** 12:12 / 12:20 / 13:05.
Assert `rig.clock.now` equals the stated clock before planning, and print
the pass clock in each section header. Rewrite
`screenshots/3b/notification-plan-travel.txt`. Live plan:
`notification-plan-live-p3bf05.txt` from the item-16 launch.

**INDEX.md.** One row per §30 item 1–24 naming its current frame. Superseded
`-p3b` frames are removed only where a `-p3bf<NN>` replaces them; say which.
Edge check on every new frame; every launch's services list (mocks only).
Note G-096's state (the location keys) in the notes.

**Tests.** None new beyond the dump's clock assertions; full suite green.

---

## 8. Spec amendments made in this review

- `components.md`:
  - §23.6 (campus at first launch; G-098 closed)
  - §24.3 (B48: duration rounded up)
  - §24.6 item 2 (B51)
  - §24.10 step 2 (B49) and the new paragraph "No invented fact in the
    copy either" (F02)
  - §25.1 (B53: the width rule; `≈` placement)
  - §26.2 (leave line `lineLimit` 2; F03)
  - §30 items 2, 5, 13, 20 (wording), new item 24 (clock changes)
  - §30.1 dataset counts and "Cache sharing" (G-097 closed)
  - **new §31 "Clock changes"** (G-100; F01)
- `layouts.md`:
  - §3.1 (wall-clock note; the reading of the Week scroll rule)
  - §6 row 4 (`Origin` as a word)
- `GAPS.md`:
  - closed G-097, G-098, G-099, G-100 (spec side)
  - opened G-101 (deferred)
  - G-096 re-checked (location keys still missing)

Not amended: `interactions.md` (§14.1 and §15.3–§15.5 match the build).
§31.4 covers drag on a change day, and interactions §4 needs no edit.

## 9. Proposed DECISIONS.md entries (for Parsa to write)

```
## 2026-10-15 — Times are wall-clock times, also on the days the clocks change.
A time of day in Kadence — an event's place on the grid, a routine block, a
time window, a drop position — is the local clock time on that day, never the
time elapsed since midnight. On the 25-hour day the repeated hour shares its
row; on the 23-hour day the missing hour holds nothing; a routine block in the
missing hour moves forward by the gap (02:30 → 03:30), in the repeated hour
it is the first one. Durations stay durations. The grid keeps 24 rows and
draws no marker. Closes G-100 (components.md §31).

## 2026-10-15 — No invented fact, in copy as in numbers.
Extends "A failed route is said, never guessed": a surface never fills in an
origin, a reason, a place or a number it does not have. What is missing is
left out, never defaulted.
```

After F01–F05 are in and reviewed, for Parsa to write (final, from the re-check at the end of this file):

```
## 2026-10-16 — Phase 3 slice 2 accepted.
Shipped: leave-by from Apple Maps — places confirmed by the user, the campus looked up by Kadence at the first launch, a usual way to travel with per-pair modes, a buffer, an ETA cache and a sparing queue with refreshes at T−3 h and T−45 min; failures said as estimates or "unavailable" with the reason, never guessed, and no surface fills in an origin, reason, place or number it does not have; where you are used for the next departure only and never kept; the live band, the inspector's Place, Leave by and Origin, the menu bar's Leave / Leave now and the takeover, the popover's leave line on up to two lines; notifications (one per event, absolute times, time-sensitive leave-by, held by protected windows, Done / Snooze / Open, sync paused told once); every time of day drawn, materialised, held and scheduled at wall-clock time, so Sun 25 Oct and Sun 29 Mar keep 24 rows and routine blocks, Sleep and leave-bys at their clock times. 1113 tests green. Review frames for slice 2's fixes were rendered offscreen from the real views at a pinned clock (B55). Deferred: A41; G-094, G-095, G-101; G-103 (a review fixture's timestamp, next slice). Open with Parsa: G-096 (time-sensitive capability, optional).
```

## 10. For Parsa

1. **Add the location usage keys (G-096 item 2)** before relying on `Use
   where you are`, as build settings on the Kadence target:
   `INFOPLIST_KEY_NSLocationUsageDescription` and
   `INFOPLIST_KEY_NSLocationWhenInUseUsageDescription` = `Kadence uses your
   location only to work out how long the trip to your next event takes. It
   is sent to Apple Maps for that and is not stored.` Without them macOS
   shows no prompt, and Kadence's one automatic ask is spent silently. If
   that has already happened, `Allow Location…` in Settings ▸ Travel asks
   again once the keys exist. Time-sensitive delivery (item 3) is optional:
   without it leave-by notifications arrive as normal ones.
2. **Week opening at 04:00**: check whether anything in that week starts
   between 05:00 and 05:59 (a morning routine block counts). If yes, it is
   the rule working. If you would rather routine blocks did not pull the
   view earlier, that is a design change to decide (my recommendation:
   keep the rule; it guarantees the first block is in view). If nothing
   starts before 06:00, report the week; that is a bug.
3. **F01 before Sun 25 Oct.** Until it is in, routine blocks that day are
   an hour early (a 20:00 block reads 19:00 and notifies at 18:55 CET), and
   Sleep is shifted an hour (ends 06:00, starts 21:00). Detached routine
   instances on 25 Oct are not corrected by the fix; any you have edited by
   hand will keep their times.
4. Confirm the two proposed DECISIONS entries in §9.

---

## Re-check — 2026-10-15

Design agent; the re-check was done on Fri 16 Oct 2026. Re-checked: CA's
fixes run `2aa857a` (step 0), `f031452` (F01), `0b2ea6f` (F02), `2e83fe0`
(F03), `62969b4` (F04), `bfdaed0` (F05), `0319bfd` (summary); STATUS
§137–§143; DEVIATIONS B55 (new); GAPS G-098, G-100, G-102 (new);
`screenshots/3b/INDEX.md`, every `-p3bf01` … `-p3bf05` frame and both plan
files; the fix diffs (`git show`), above all F01's `WallClock.swift`,
`TimeGeometry`, `DayLayoutEngine`, `RoutineEngine`, `TimeWindow` /
`QuietWindow` spans, `NowLineView` and the drag / resize / create paths;
and `ClockChangeTests.swift`. Read-only git only. Nothing was launched, no
store was opened, and no test run was made. No prompt, notification, MapKit,
location or network request was made. The suite count (**1113 passed / 0
failed**) is CA's, from STATUS §143.

### Verdict

**ACCEPTED.** Phase 3 slice 2 is closed. All five fixes pass. G-098 and
G-100 are closed (build). G-102 is closed (confirmed as built). One small
new gap, G-103 (a review fixture only), does not block. F01 is in before
Sun 25 Oct 2026, as required.

### Per fix

| Fix | Result | Evidence |
|---|---|---|
| **F01** wall-clock times | **Pass** | See "F01 in detail" below |
| **F02** no invented fact; `Origin` as a word | **Pass** | `rg '\?\? *("\|\.offline\|\.failed\|0\b\|now)'` over `TravelPresentation`, `MenuBarFormatting`, `NotificationCopy`, `NotificationPlanner`, `InspectorView` finds only the omit form (`x.map { " from \($0)" } ?? ""`), plus `?? 0` on date components in `TravelCopy.time`. That is not a fact. Every fallback listed in §2 is gone. N7 now decides `pending` from status and reason, not from "reason is nil" (a real fix beyond the list). `NoInventedFactTests` covers surfaces (a)–(e) and the scan words, plus the planner invariant. `EventOrigin.displayName`: `inspector-dinner-place-p3bf02.png` reads `Origin Manual`; the rest of the inspector is unchanged (`Leave by 17:45`, `35 min by public transport from FH Technikum Wien · 10 min buffer`) |
| **F03** popover leave line, 2 lines | **Pass** | `popover-no-address-p3bf03.png`: `Travel time unavailable · Home has` / `no address`. `popover-takeover-p3bf03.png` (and `-manual-next-`): `Leave by 17:45 · 35 min from FH` / `Technikum Wien`, with `EPC-ILV` as the first rest row. `popover-leave-p3bf03.png`: one line. The meta line stays one line (`Universi…`). The lead is joined with no-break spaces, so `Leave by 17:45` is never split. `PopoverLeaveLineTests` covers the three wrapping strings, the one-line case and the 60-character place |
| **F04** campus at first launch | **Pass** | `TravelCoordinator.recompute`: `lookupDue && (kind != .ordinary \|\| a leg needs the campus)`. `campusLookupIsDue` is unchanged (once per day, launch / wake only, never after an edit). `looksUpCampusAtLaunch` is gone from the app (asserted by `CampusLookupTests`). Its four tests are the four §7 asked for. `settings-travel-first-run-p3bf05.png` shows the campus found with no switch |
| **F05** recaptures, frames, dump, INDEX | **Pass** (offscreen, B55 accepted below) | Item 1 is the whole pane. Items 5, 6 and 8 show `Climbing` on the 18:00 row. Item 13: `18:30 · Dinner with flatmat…`. Item 15: `Travel time from Home not worked out` / `yet` and `Leave by 12:22 · 28 min from where` / `you are`. Item 16: `Leave 12:15 · Pick up parcel` and `Leave by 12:15 · 35 min from Home`, `13:00 – 13:30 · Personal` at 12:00, with the live plan firing at 12:10. Item 17: Sunday's `Fixture review` sits at 20:00 like Mon–Sat. Item 18 is tall enough to show `Add Place`. Item 22: cursor `10:18`, `10:00` dropped. Plan dump: the three catch-up headers read `launch pass at 12:12 / 12:20 / 13:05`, and fire times are 12:12 / 12:20; only those lines changed. INDEX has one row per item 1–24; the removed files are listed; G-096 is noted |

### F01 in detail

**`WallClock`.** Checked by hand against Europe/Vienna:

- `moment(150, 25 Oct)` solves `x + offset(x) = local` over the offsets
  ±3 h. Both 00:30 UTC and 01:30 UTC match, and the earlier one is chosen:
  **02:30 CEST**.
- `moment(150, 29 Mar)`: neither candidate matches, so the offset before the
  gap is used: **03:30 CEST**.
- `moment(1200, 25 Oct)`: **20:00 CET**.
- `localMinutes(18:00 CET, since 00:00 CEST)` = 1140 − 60 = **1080**. On a day
  with no change the offset difference is 0, so the old maths is unchanged
  (T1 checks every quarter hour on 22 Oct).

**Grep for remaining elapsed time-of-day maths.** Searched for
`addingTimeInterval` / `timeIntervalSince` / `byAdding: .minute|.hour` /
`bySettingHour` / `* 3600` across `Kadence/`, 99 sites in all. Outside
`WallClock` every hit is one of:

- a duration: event length, snooze, nudge ±15, leads, the travel and refresh
  offsets, `chainGap`, the 48-hour horizon, resize minimums, `nextHalfHour`'s
  +30;
- `byAdding: .day` (wall-clock days);
- `bySettingHour` (Foundation's wall-clock default);
- **one** day-start + hours: `TravelDataset.seedStaleCache`, `computedAt =
  date(byAdding: .day, −15, anchor).addingTimeInterval(18 * 3600)`.

That last line is a review fixture's "last worked out" stamp, not a drawn
time. It is wrong only when `anchor − 15 days` is a change day, for example
`M` = Mon 9 Nov 2026, where it would read `Last worked out 25 Oct 17:00`.
T12's regex misses it because the `.addingTimeInterval` is on its own
continuation line. **Not blocking → G-103** (below). Nothing computes a y
from seconds since midnight: `TimeGeometry.y`, `height`, `date(forY:)`,
`yForTimeOfDay`, `snap` and `dragged` all go through `WallClock`.
`DayLayoutEngine` lays out drawn intervals on `elapsedRuler`, which is an
honest UTC ruler. `NowLineView.lineY` = `y(for: now)`, which is wall-clock.

**Paths.** All are wall-clock, and a move keeps the elapsed duration:

- *Drag:* the dragged edge is the start, or the **end** for resize-bottom.
  `geometry.dragged(edge, by: dy)` returns the moment at the snapped y.
  Commit and preview use `session.current` directly; the old "delta added
  to `end`" is gone.
- *Create / click / double-click:* snap with the column's calendar.
- *Conflict scroll and initial scroll:* `minuteOfDay` on the occurrence's own
  day.
- *Routines window, template conflict panel, window labels:* `WallClock` on
  the reference day.
- *Routine materialisation and `templateValues`:* `WallClock.moment`; the end
  is start + duration.
- *Spans:* `TimeWindow.spans`, `QuietWindow.spans` and `TimeWindowFixture`
  are all wall-clock.

Snapping inside the repeated hour lands on the first 02:xx. That is §31.1's
rule, and it only applies while dragging at 02:xx on the change night.

**Test coverage** (`ClockChangeTests`, 20 tests):

| Asked | Covered |
|---|---|
| 25 Oct and 29 Mar in **Day** | T2 (A, B, B1 / B2 side by side with no conflict, B3 back through, `Climbing` + band, block rows) and T3 (A, B, `Climbing` + band, R, R2 in the gap) |
| … in **Week** | T4, both weeks: Sunday rows at `hourHeightWeek`, Mon–Sat layouts identical to the elapsed ruler's |
| … in **Month** | T5, both: `Climbing` in the change day's cell at `18:00`; the 23:30–00:30 Saturday event only in its start cell |
| Repeated hour | T1 (both occurrences → 150), T2 B1 / B2 / B3 / B, the routine in the repeated hour → its first one, T6 at 02:30 CEST and 02:30 CET |
| Missing hour | T1 `moment(150)` → 03:30 CEST, T3 R2 02:30 → 03:30 CEST, T10 drop at y(2.5) on 29 Mar → 03:30 CEST |
| Routine blocks, both days | T2 / T3 routine 20:00 → 20:00 CET / CEST; T9 `routineStart` 19:55 CET / CEST; an old 19:00 CET instance corrected in one update with no undo step, a detached one kept |
| Sleep spans | T8: all three span builders on 24–26 Oct and 28–30 Mar; 21:30–22:30 routine refused every day |
| The band | T2 / T3 drawn band y(17.75)–y(18); T4 Sunday; T11 slot `sunday 17:30`, `departAt` 17:45 CET |
| Now line vs gutter | T6: eight clocks × Day and Week, gutter on Monday's ruler, A42's marker on the same y |
| Notifications | T8 hold 06:40 → 07:00 on both days, 21:30 CET not held; T9 routine 19:55; T11 `leave.` 17:40 CET, `Leave by 17:45 for Climbing` |
| Source scan | T12 (> 100 files, live against both banned forms). Misses a two-line chain (G-103) |

**Frames.**

- `dst-day-1025-p3bf01.png`: A at 01:00; B1 and B2 side by side on the 02:00
  row with `B across` (01:30–03:30, two rows tall) between them; B3 below B1;
  Sleep ends at the 07:00 line and starts at 22:00; `Climbing` on the 18:00
  row with the case-2 strip `Leave 17:45 · 5min` inside its top (§4 short
  case, §30 item 8); `Evening review` 20:00–21:00; the now line level with
  the red `18:30`.
- `dst-day-0329-p3bf01.png`: B across 01:30–03:30; the 02:00 row starts
  nothing; `R2 in the gap` at 03:30; `Climbing` and `Evening review` as
  above.
- Week and Month frames for both changes agree.
- **`week-M-travel-p3bf05.png` and `day-sun-climbing-p3bf05.png` show
  `Climbing` on Sun 25 Oct's 18:00 row**, its strip from the 18:00 line, and
  the block ending at 19:30.

In the Week `dst-week-1025` frame the Sunday column cascades four
overlapping blocks into ~200 pt, so B1 shows only its ⚠. That is layouts
§3.3's narrow-column cascade, the same on any day, and not a clock-change
effect. The Day frame shows them side by side.

**F01: pass.** No existing test was changed. CA ran the baseline on a clean
`HEAD` export (1067), which is the honest way to recover from the ordering
slip in §137.

### Rulings

1. **Item 1 without the tab bar: accepted.** §7 allowed "offscreen of the
   full pane" when a window could not show it. The `SettingsView` tab bar is
   unchanged chrome that the live T18 frames already show
   (`settings-travel-live-p3b.png`, `settings-notifications-live-p3b.png`).
   What item 1 has to prove is the Travel pane at first run, after F04 and
   with no switch. The frame proves all of it: Home empty with `Address`;
   the campus `Höchstädtplatz 6, 1200 Wien, Austria`; the footer; `Add
   Place`; `Usually Public transport`; `Home ↔ FH Technikum Wien Usual`;
   `Buffer 10 minutes`; `Use where you are` on (knob right, on-label shown;
   grey only because an offscreen window is never key, which STATUS §142
   says is asserted); no block.
2. **DEVIATIONS B55** (items 5, 6, 8, 12, 16, 17 and 20 offscreen, not
   live): **accepted.**
   - The renders use the real views, the review launch's own seeding, the
     real coordinator and scheduler, and mocks plus the recording centre, at
     a pinned clock (Thu 15 Oct 12:00).
   - That is stronger evidence for item 16's "between 07:00 and 20:00" than
     a live launch, which has no injected clock.
   - What the renders lack (window chrome, the real menu bar) is covered by
     the T18 live frames, and no slice 2 fix changed it.
   - Next slice: if the run's sandbox can read the container again, live
     frames return to their usual role.
3. **G-102** (a `ready` / `estimate` leg with no `departAt`): **confirmed as
   built.** The row reads `Unavailable` (secondary), with no sentence and no
   button; VoiceOver says `Leave by, unavailable`. That is the omission rule
   applied to the one value the row exists for. `layouts.md` §6 is amended.
   Closed.
4. **The capture slip** (STATUS §142, a `pkill -f` on the test host's path
   pattern): it matched nothing, and the real store's files are dated the
   day before the run (§143). No action. The run rule stands: kill by PID
   only.

### Gaps

| Gap | Ruling |
|---|---|
| **G-098** | **Closed (build).** F04 as above |
| **G-100** | **Closed (build).** F01 as above |
| **G-102** | **Closed.** Confirmed as built; `layouts.md` §6 amended |
| **G-103** (new) | **Open (CA, small, not blocking).** `TravelDataset.seedStaleCache`'s `computedAt` is day + `18 * 3600`. Make it `WallClock.moment(minuteOfDay: 1080, on:)`. Extend T12 so a day start chained to `.addingTimeInterval(… * 60 / 3600)` on the next line is caught too. Do it with the next slice's first task |
| G-096 | Location keys **present** (`a0deaaa`); only the optional time-sensitive entitlement (item 3) remains. Stays open with Parsa for that alone |
| G-101 | Still deferred |

### Final

**ACCEPTED** — Phase 3 slice 2 is closed with 1113 tests green. §9's
acceptance entry, final:

```
## 2026-10-16 — Phase 3 slice 2 accepted.
Shipped: leave-by from Apple Maps — places confirmed by the user, the campus looked up by Kadence at the first launch, a usual way to travel with per-pair modes, a buffer, an ETA cache and a sparing queue with refreshes at T−3 h and T−45 min; failures said as estimates or "unavailable" with the reason, never guessed, and no surface fills in an origin, reason, place or number it does not have; where you are used for the next departure only and never kept; the live band, the inspector's Place, Leave by and Origin, the menu bar's Leave / Leave now and the takeover, the popover's leave line on up to two lines; notifications (one per event, absolute times, time-sensitive leave-by, held by protected windows, Done / Snooze / Open, sync paused told once); every time of day drawn, materialised, held and scheduled at wall-clock time, so Sun 25 Oct and Sun 29 Mar keep 24 rows and routine blocks, Sleep and leave-bys at their clock times. 1113 tests green. Review frames for slice 2's fixes were rendered offscreen from the real views at a pinned clock (B55). Deferred: A41; G-094, G-095, G-101; G-103 (a review fixture's timestamp, next slice). Open with Parsa: G-096 (time-sensitive capability, optional).
```
