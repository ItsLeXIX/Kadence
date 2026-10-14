# Phase 3 — slice 2 plan: leave-by and notifications

Design agent, 2026-10-14. Written after slice 1 was accepted
(`PHASE3-REVIEW.md` "Final — 2026-10-14"; DECISIONS 2026-10-14 "Phase 3
slice 1 accepted").

## Scope

This slice answers "when do I leave?" and makes sure Kadence tells the user
without being checked.

- **Leave by.** Each event that needs travel gets a departure time:
  `start − travel time − buffer`.
  - Travel time comes from a `TravelTimeProvider`. The only provider in this
    slice is **manual**: the user types one travel time per pair of **known
    places** (built-in `Home` and `FH Technikum Wien`, plus any they add),
    with a mode, and one buffer for every trip.
  - Timetable rooms are on campus. Online lectures, routine blocks and
    all-day events need no travel. A manual event travels only if the user
    gives it a place.
  - You come from the last event that had a place if it ended at most two
    hours earlier, otherwise from Home. Same place, no travel.
  - The result is stored as a `TravelLeg` per event, recomputed whenever an
    input changes, and never written onto the event.
  - The travel band draws it; the inspector explains it; the menu bar shows
    `Leave 08:15 · SWQM-ILV`, then `Leave now`, then Phase 2's late state.
- **Notifications** through `UNUserNotificationCenter`:
  - At most one per event: a leave-by notification if it has a leave-by,
    otherwise a "starts at" under its category (timetable, personal,
    routine). Each category can be turned off and has its own lead time.
  - Actions `Done` · `Snooze` · `Open` (no `Snooze` on imported events).
  - Quiet inside protected windows unless the event is inside one.
  - A rolling 48-hour schedule, deduplicated by identifier.
  - Permission asked when there is first something to tell, and never
    silently missing.

**Not in this slice:** routing, MapKit, geocoding, location permission (slice
3; the seam is `components.md` §24.9), Moodle and work items, deadline and
morning-summary notifications (G-088), sync-failure notifications (G-060),
mail, the planner. A41 and A42 are logged, not built. G-083 is untouched.

**No task needs a network, a location, or a real notification permission
prompt to pass.** Travel times come from the store; the notification centre is
a recording double in every test and every review launch (`components.md`
§27.10), as the store and the transport already are (§22.1, B45).

## Spec sections — new and changed

| Where | What | § |
|---|---|---|
| `components.md` | **New part "Phase 3 — slice 2"** | §23–§30 |
| | Known places, which place an event is at, travel times, buffer | §23 |
| | Travel legs: candidates, origin rule, the leg, worked example, storage and ownership, recompute triggers, never writes the event, the provider seam | §24 |
| | The travel band, live: exactly what changes from §4 | §25 |
| | Menu bar: Leave and Leave now states, the takeover rule, the popover's leave line and meta order, the notifications line | §26 |
| | Notifications: rules, which one an event gets, fire time, exact copy N1–N6, quiet, scheduling, actions, permission, the no-guilt rule, the centre protocol | §27 |
| | Data model additions, **proposed** | §28 |
| | VoiceOver strings | §29 |
| | What slice 2 must render for review (17 items), fixtures | §30, §30.1 |
| | Amended in place, 2026-10-14 | §4 (band is live), §11 (VoiceOver), §12 (items 7–8), §15.1, §15.2 |
| `layouts.md` | Inspector `Place` and `Leave by` rows | §6, §6.1 (amended) |
| | Popover regions | §9 (amended) |
| | Settings: three tabs | §11 (amended) |
| | **Settings ▸ Travel** | §13 (new) |
| | **Settings ▸ Notifications** | §14 (new) |
| `interactions.md` | Acting on a notification; permission | §14 (new) |
| | Setting a place; moving an event with a band; Settings edits | §15 (new) |
| `GAPS.md` | G-063 closed in the spec; G-084 … G-092 opened; G-016, G-060 restated | "2026-10-14 — Phase 3 slice 2" |

## Tokens — `tokens.json` 1.7.0 → **1.8.0** (updated 2026-10-14)

| Token | Value | Used by |
|---|---|---|
| `size.settingsPlaceNameFieldWidth` | 160 | a known place's name field, `layouts.md` §13 |
| `size.settingsMinutesFieldWidth` | 48 | a route's minutes field, `layouts.md` §13 |
| contrast pair `color.semantic.now` on `color.surface.popover` (min 4.5) | 4.55 / 5.12 | the popover's `Leave now` line (§26.2); also the Phase 2 late meta line, which used it undeclared |

`$measured_1_8_0` records one failure that is **deliberately not declared**:
`semantic.now` on `surface.inspector` is 4.25 in light, so the inspector never
uses it. 64 pairs. No other value changed. The travel band keeps
`text.secondary` on `surface.travelBand` (5.69 / 6.51, declared since 1.0.0).

## DECISIONS.md — proposed entries

Six entries, ready to paste after Parsa's confirmation. They record the
choices in §23–§28 that change behaviour or the model; everything else follows
from them or from existing entries.

1. **Leave-by comes from known places and typed travel times.** §23, §24.2,
   §28.1.
2. **A travel leg is derived data.** §24.5–§24.7.
3. **One notification per event, with absolute times.** §27.2–§27.4, §27.7,
   §27.9.
4. **Protected windows hold notifications; they never drop a departure.**
   §27.5.
5. **"Leave now" is the should-have-left state, and a due departure outranks
   a late item.** §26.1.
6. **Kadence asks for notification permission when it first has something to
   tell, and says so when it can't.** §27.8, §27.10.

The text of each is in the design agent's final message for this session, so
Parsa can paste it as written.

## BUILD TASK LIST for CA — dependency order

**Common rules for every task:**

- One task per session. Tests run with `-only-testing:KadenceTests`.
- Persistence tests use a real in-memory `ModelContainer` (DECISIONS
  2026-09-10).
- **Injected clock everywhere**: no planner, recompute or scheduler reads
  `Date()` itself. The test zone is Europe/Vienna; `M` = Mon 2026-10-12.
- **No real notification centre**: `SystemNotificationCenter` is constructed
  only by a normal launch; tests and review use `RecordingNotificationCenter`
  (`components.md` §27.10). No task triggers a permission prompt.
- **No network, no location**: nothing in this slice imports MapKit or
  CoreLocation, or sends a request. The CalDAV mock serves the review
  timetable as in slice 1.
- Never open, read or write the real store (§22.1). Record its `stat` before
  and after as in slice 1 (STATUS §132).
- A UI task's captures go to `screenshots/3b/<name>-p3bt<N>.png`; task 12
  recaptures the set from the final build (§17.2 rule 2).
- `generate-tokens --check` is clean at **1.8.0** from task 1 on.
- Baseline: **902 tests pass** (STATUS §132). Every task ends with the whole
  suite green.

### Task 1 — Data model and built-ins; tokens 1.8.0; log A41 and A42

*Spec:* components §28, §23.1, §23.3 (the built-in route), §27.1 (rule
defaults), §21.1.1 (the built-ins pattern).

**Build:**

- `@Model`s `KnownPlace`, `TravelRoute`, `AppSettings`, `TravelLeg`,
  `NotificationRule`, `NotificationRecord`, exactly §28.1's fields; enums as
  raw strings; every field defaulted.
- `Event.placeID: String?`. `EventStore`'s delete snapshot and duplicate
  carry it.
- First-launch built-ins, idempotent, in every launch kind (normal, review,
  test host): places `home` / `campus`, the route `home ↔ campus` (`.transit`,
  minutes nil), `AppSettings` (10 / 120 / nil), the four rules (§27.1
  defaults).
- Regenerate `Tokens.swift` at 1.8.0.
- **DEVIATIONS.md**: under a new heading `## Phase 3 slice 2 — leave-by and
  notifications (2026-10-14)`, log **A41** (the `copies` log field and the
  step-2 count of `merged − copies`; G-081's end-time sentence —
  `components.md` §20.8.4, `layouts.md` §12.2, `caldav-mocks.md`
  `reportCISCopies`) and **A42** (G-082: the now time and hour labels
  measured as drawn, 2pt clearance; the cursor time likewise —
  `components.md` §8), with the wording of `GAPS.md` "Deferred by this check"
  (2026-10-14). Both **deferred, still normative**; neither is built here.

**Acceptance — tests:**

- A store written by the slice 1 build opens; every event reads back unchanged
  with `placeID` nil; no leg, record or extra place exists until the built-ins
  run.
- Built-ins: two launches against one container leave exactly one of each
  (2 places, 1 route, 1 `AppSettings`, 4 rules), with §28.1's and §27.1's
  defaults.
- `TravelRoute` stores its pair sorted; a second route for the same pair in
  either order is refused.
- Delete a manual event with a `placeID`, undo: `placeID` is back. Duplicate
  copies it.
- `Tokens.Size.settingsPlaceNameFieldWidth == 160`,
  `settingsMinutesFieldWidth == 48`.
- DEVIATIONS.md contains `A41` and `A42` under the new heading.
- All 902 tests still pass.

*Captures:* none.

### Task 2 — Places, the provider and the leg planner (pure)

*Spec:* components §23.2, §23.3, §24.1–§24.4, §24.9.

**Build:**

- `TravelEndpoint`, `TravelTimeError`, `TravelTimeProvider` (§24.9's
  signature), `ManualTravelTimeProvider`, and a `MockTravelTimeProvider` that
  counts calls.
- `PlaceResolver` (§23.2's six rules; the timetable rule reads the resolved
  `Source`'s kind, §21.1.1).
- `TravelLegPlanner`: value snapshots in (events, places, routes, settings,
  sources, `today`), legs out — `ready`, `needsTravelTime`, or none.

**Acceptance — tests** (events built in code from §30.1's dataset `travel`,
clock Mon 12 Oct 06:00):

- §24.4's table, row for row: status, origin, destination, `departAt`,
  `duration`, `buffer`, `mode`.
- Variant `travelUnset`: the six legs §24.4 names are `needsTravelTime`;
  `Climbing` stays `ready`.
- §30.1 "The test day": overlap (depart before `P.end`), chain through a
  placeless event, exactly 120 min chains and 121 does not, skipped previous,
  plus: cancelled and all-day events are never candidates; a routine block
  between two lectures changes nothing; an online lecture is never an origin;
  a `.done` previous event is still an origin; origin ties resolve by later
  start, then smaller id.
- The provider is called once per distinct (origin, destination, mode); a mode
  that differs from the route's → `.notSet` → `needsTravelTime`.
- §23.2: an imported event from a source of another kind has no place; a
  timetable event with an empty location has none; a manual event whose
  `placeID` names no place has none.
- The planner's sources import neither MapKit nor CoreLocation (a test reads
  the target's import list, or the module is built without them).

*Captures:* none.

### Task 3 — Leg store and recompute

*Spec:* components §24.5–§24.8; §20.8.4 ("Local identity"); §20.9.

**Build:**

- Applying a plan in **one transaction**: upsert changed legs, delete owned
  legs that are no longer planned, never touch legs of events before
  `startOfDay(today)`, delete a leg with its event.
- The recompute coordinator: §24.6's triggers (event writes including undo and
  redo, sync and Import applied, place / route / buffer edits, launch, wake,
  day change, clock and time-zone change), a 0.5 s debounce on an injected
  scheduler, and a hook that asks for a notification pass (a no-op until
  task 5).

**Acceptance — tests:**

- Two recomputes of the same inputs write nothing the second time;
  `computedAt` is unchanged.
- A route edit changes today's and future legs and leaves a leg of yesterday's
  event byte-equal.
- Delete an event → its leg is gone in the same transaction; undo → the leg is
  back after the next recompute.
- After a recompute, every event's §20.8.4 hash and the source's `feedHash`
  are equal to before; `lastChange*` is unchanged; the undo stack is unchanged.
- §30.1 "Sync" table (`reportChanged` at Mon 12 Oct 06:00), row for row,
  including `REQEN-EXAM` losing its chain when `EPC-ILV` vanishes.
- 50 event writes in 0.2 s → exactly one pass.
- `NSCalendarDayChanged` at midnight moves the ownership window: the
  previous day's legs are no longer rewritten by a route edit.
- A recompute while a conflict preview is active changes no previewed block.

*Captures:* none.

### Task 4 — Notification planner (pure)

*Spec:* components §27.1–§27.5, §27.6 (the planning half: window, cap,
records, catch-up), §27.9.

**Build:** `NotificationPlanner` and the copy formatter for N1–N6; the quiet
rule over `TimeWindow.spans(on:)`; the chain clamp; the 48-hour window, the
48 cap; ordinary and catch-up modes; records as "sent".

**Acceptance — tests:**

- §30.1's notification table at **Thu 15 Oct 06:00** (4 requests) and at **Fri
  16 Oct 23:00** (3 requests): identifiers, fire dates, titles, bodies,
  categories and sounds, exactly.
- Catch-up at Thu 12:12 (N1 at once), 12:20 (N3 at once), 13:05 (nothing); the
  same clocks in an ordinary pass plan nothing late.
- The test-day extras: two protected spans back to back (held to 07:30); leave
  by off → `start.` at 12:30 under `timetableStart`; all rules off → empty.
- Exclusions: done, skipped, cancelled, all-day, events before today, a subject
  time in the past.
- At most one of `leave.` / `start.` per event, in every case.
- Window edges: a fire time at exactly `now + 48 h` is planned, one second
  later is not. 60 candidates → the 48 earliest.
- A record whose fire date has passed is never planned again; a later subject
  (the event moved later) is planned with a new fire date.
- No title or body in any test contains `late`, `missed`, `overdue` or `!`.

*Captures:* none.

### Task 5 — The centre, the applier, scheduling and permission

*Spec:* components §27.6, §27.8, §27.10; §22.1's three-launch rule (B45).

**Build:**

- `NotificationCenterClient`, `SystemNotificationCenter` (normal launch only)
  and `RecordingNotificationCenter`.
- The applier: diff by identifier and content hash; replace, remove, record;
  remove delivered notifications of ended, deleted, done, skipped or
  cancelled events; never touch foreign identifiers.
- Passes: after each recompute, on rule and `TimeWindow` edits, on
  authorization change, hourly; one at a time, coalesced, 1 s debounce.
  Catch-up only for the pass after launch and after wake.
- Authorization: §27.8's state mapping; request once when the first pass has
  something to schedule; re-read on `didBecomeActive`.
- Categories registered at launch; `willPresent` options.
- Review argument `-KadenceNotifications allowed|off|notDetermined|notAsked`.

**Acceptance — tests** (recording centre, injected clock):

- Two passes over the same inputs → the second performs no add and no remove
  (the centre's operation log).
- Move an event → the same identifier is replaced, never duplicated. Mark
  it done → removed. Delete it → removed, and its delivered notification
  cleared.
- A leg appears (a route time set) → `start.` removed, `leave.` added.
- `off` → nothing added, nothing removed; switching to `allowed` → the plan is
  added in the next pass as an ordinary pass.
- First pass with a plan, `notDetermined`, never asked → exactly one
  `requestAuthorization`, `notificationsRequestedAt` set; a second pass → none.
  All rules off → none.
- The hourly pass at Thu 06:00 + 1 h adds what entered the window.
- A pending request with a foreign identifier survives every pass.
- A test-host launch and a `-KadenceReview` launch never construct
  `SystemNotificationCenter` (the factory's launch-kind table is asserted, as
  B45's store is).

*Captures:* none.

### Task 6 — Actions

*Spec:* components §27.7; interactions §14.1.

**Build:** the delegate's response handler and an action router: `Done`,
`Snooze` (via `EventStore.snooze`, with N5 / N6 delivered at once), `Open`,
the default action, dismiss; routing `Open` through the popover's existing
`Open` path.

**Acceptance — tests** (simulated responses, §30.1 "Actions"):

- `Done` on `start.{REQEN-EXAM}` → `.done`, one `Mark Done` step; again →
  nothing.
- `Snooze` on `leave.{Dinner}` at Thu 17:41 → 18:45–20:15, one `Snooze` step,
  N5 exact; after the recompute and pass, `leave.{Dinner}` fires 17:55 with
  `Leave by 18:00 for Dinner with flatmates`.
- `Snooze` on `start.{Late call}` at Sat 23:01 → nothing written, no undo step,
  N6 exact.
- `kadence.readOnly` has no `Snooze` action; `kadence.result` has none.
- `Open` and the default action select the event and page to its day; an
  unknown id opens today with nothing selected; `Done` / `Snooze` on an
  unknown id do nothing.
- Results carry no sound; N1–N4 the default sound.

*Captures:* none.

### Task 7 — Review mode: dataset `travel` and the other datasets' legs

*Spec:* components §30.1; §22.1 (review rules).

**Build:**

- `Fixtures/ICS/cis-travel.ics.template` (the review template without row 1,
  plus T1).
- Dataset `travel` with every §30.1 item; variant `travelUnset`; the live event
  P6.
- `phase2` / `phase3` seeding of places, routes and buffer 0 (`Café Sperl`).
- The notification-plan dump used by §30 item 14 — produced like the
  offscreen renders (§17.2 rule 3), from the real planner, at pinned clocks.

**Acceptance — tests:**

- Dataset `travel` (rendered with `M` = 2026-10-12, clock Mon 06:00): 14
  timetable events (15 VEVENTs, one merge), 2 history; no conflicts; legs equal
  §24.4.
- `phase3`: day conflicts 14 and Needs attention 15, unchanged;
  `Datenmodellierung` leg depart 08:38, 22 min walking; `Coffee with Nora`
  depart 10:54, 6 min walking. `phase2`: the same two legs.
- `empty` / `fresh`: built-ins only, route unset, buffer 10.
- The plan dump at §30.1's clocks equals the notification table.

*Captures:* none.

### Task 8 — Settings ▸ Travel (and the tab bar)

*Spec:* layouts §11 (amended: three tabs), §13; components §23; interactions
§15.3; §29 (Settings rows).

**Build:** the three tabs with their symbols; Places (name, address, remove,
`Add Place`, the footer); Travel times (one row per pair, minutes field, mode
pop-up, footer); Buffer; the removal alert; every edit triggering a
recompute.

**Acceptance — tests** (view model and store):

- An empty or duplicate name reverts. `Add Place` names `New Place`, then `New
  Place 2`.
- Removing a place used by 2 manual events asks with `2 events are at Gym. They
  will have no place, and no leave-by.`; `Remove` sets their `placeID` nil and
  deletes the place's routes; a place nobody uses is removed without asking.
- Built-ins have no remove button.
- Minutes: `0`, `241`, `2.5` and `abc` revert with a beep; empty → not set;
  `35` → the route's minutes and a recompute.
- Route rows: one per pair, ordered as layouts §13; the footer names the
  campus place's current name.
- The focus order of layouts §13.
- VoiceOver labels and values of §29's Settings ▸ Travel rows.

*Captures:* `settings-travel-first-run-p3bt8.png` (`empty`),
`settings-travel-filled-p3bt8.png` (`travel`).

### Task 9 — Settings ▸ Notifications and the permission states

*Spec:* layouts §14; components §27.1, §27.8; interactions §14.2.

**Build:** the status block (both states, exact copy), the four rule rows
(switch, pop-up, second line), the footer; `Allow Notifications…` (asks; if no
prompt is possible, opens the System Settings URL through an injected
opener); `Open System Settings…`; re-reading on `didBecomeActive`.

**Acceptance — tests:**

- `off` and `notAllowedYet` show §27.8's titles, bodies and buttons exactly;
  `allowed` and `notAsked` show no block; all rules off shows no block.
- Switch off → pop-up disabled, value kept; switch on while `notAsked` → one
  request.
- `Allow Notifications…` with a centre that answers without prompting (already
  denied) → the opener receives
  `x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=XIX.Kadence`.
- State changes to `allowed` on `didBecomeActive` → the block disappears and a
  pass runs.
- VoiceOver for the switches and pop-ups (§29).

*Captures:* `settings-notifications-allowed-p3bt9.png`,
`settings-notifications-off-p3bt9.png`,
`settings-notifications-not-allowed-yet-p3bt9.png`.

### Task 10 — The band live, and the inspector

*Spec:* components §25, §29 (block, inspector); layouts §6, §6.1 (amended);
interactions §15.1–§15.2.

**Build:**

- `TravelBandView` fed by `TravelLeg`; `TravelFixture` and
  `MockData.makeTravel` deleted.
- The label, hover help and VoiceOver of §25.1; the past blend of §25.2; no
  band at a drop preview.
- Inspector `Place` (pop-up for manual, text for imported) with the `No travel
  needed after …` line; `Leave by` in `ready` and `needsTravelTime`;
  `Set Place` undo step; `Edit Places…` and `Set Travel Time…` opening
  Settings ▸ Travel (with the route's field focused).

**Acceptance — tests:**

- The band model for every §24.4 leg: `Leave 08:15 · 35min` (the minutes
  exclude the buffer), the frame from `departAt` to start, the mode glyph; no
  band for `needsTravelTime`, same place, online.
- Hover help `Leave 08:15 · 35 min by public transport from Home · 10 min
  buffer`; at buffer 0 without the last term.
- VoiceOver labels exactly as §29 for `SWQM-ILV` with a leg and with
  `needsTravelTime`.
- The inspector rows' copy for §30 items 9–12, exact.
- `Set Place` is one undo step with that name; choosing the current place
  writes nothing.
- The pop-up's items in order: `None`, separator, places by `sortIndex`,
  separator, `Edit Places…`.
- The `Leave by` row never uses `semantic.now`.

*Captures:* `week-M-travel-p3bt10.png`, `week-M-travel-early-late-p3bt10.png`,
`day-thu-travel-p3bt10.png`, `band-case2-week-p3bt10.png`,
`band-case2-day-p3bt10.png`, `inspector-swqm-leave-p3bt10.png`,
`inspector-reqen-no-travel-p3bt10.png`, `inspector-dinner-place-p3bt10.png`,
`inspector-dinner-place-menu-p3bt10.png`,
`inspector-needs-travel-time-p3bt10.png`, `week-M-travel-unset-p3bt10.png`.

### Task 11 — The menu bar: leave states, takeover, the popover

*Spec:* components §26, §29 (status item, popover).

**Build:**

- `NextUpProvider` extended with the leg, the Leave / Leave now states and
  §26.1's takeover.
- The status item's two states and their degrade rule.
- The popover's leave line (four forms); the meta line reordered to time ·
  location · source; the notifications line after the stale lines.
- Accessibility labels.

**Acceptance — tests:**

- §30 item 13's six rows: state and string at each clock and width (`Leave
  12:15` never truncated; degraded to the unit alone at 110).
- Takeover at Thu 17:20 (NEXT `Dinner with flatmates`, `EPC-ILV` first rest
  row) and not at 17:10.
- Leave now offers no `Re-offer`; imported NEXT offers `Done` · `Open`.
- The leave line's four forms and colours; `semantic.now` only in Leave now.
- The meta line `13:00 – 14:30 · LAB_F5.12 · University timetable`; `17:30 –
  18:15 · Daily routine` without a location. Phase 2's meta-line tests are
  updated to the new order — the old order is the spec change, not a
  regression.
- The notifications line in `off` / `notAllowedYet`; none in `allowed`,
  `notAsked`, or with every rule off.
- §29's status item and popover labels.

*Captures:* the §30 item 13 and 15 renders (offscreen, named
`status-item-<row>-p3bt11.png`, `popover-<state>-p3bt11.png`), and the two
live captures of item 16.

### Task 12 — Capture the §30 review set and write `screenshots/3b/INDEX.md`

*Spec:* components §30, §30.1; §17.2 rules 1–6.

**Build:** recapture every §30 item (1–17) from one final build, review mode,
with the dataset and variant each item needs. Names `<item-name>-p3b.png`;
item 14 is `notification-plan-travel.txt`.

**Acceptance:**

- Every frame obeys §17.2 rules 1–6. The edge check runs on all of them; no
  frame is a preview frame.
- INDEX.md maps each §30 item to its file(s), and names the dataset, the
  variant, the `-KadenceNotifications` value, the clock of each offscreen
  render, the launch time of the live captures, and the appearance of the
  Leave now render (it measures `semantic.now`).
- Superseded `-p3bt<N>` frames are deleted once INDEX no longer maps to them.
- The full test run is green; `generate-tokens --check` is clean at 1.8.0.
- **Checks, in the task's report:**
  - no `UNUserNotificationCenter` call from a review or test launch (the
    recording centre's launch log and a grep: `UNUserNotificationCenter`
    appears only in `SystemNotificationCenter`);
  - no `MapKit` / `CoreLocation` import anywhere in `Kadence/`;
  - no `late`, `missed`, `overdue` in any notification or status string in
    `Kadence/` (outside comments quoting the ban);
  - the real store's `stat` unchanged after every capture.

*Captures:* the full set.

**12 build tasks.** The model and providers (1–3), the notification planner,
centre and actions (4–6) and the review data (7) are tested without any UI.
The four UI tasks (8–11) follow, then the capture (12).

## Judgement calls made in this session

1. **`KnownPlace` is a new model, not BRIEF's `Place`.** `Place` already holds
   every imported event's room as a row (`Place(name:)`, §21.3). Reusing it
   as the travel endpoint would mean a migration and would mix "room" with
   "where you travel to" (§28.1).
2. **Timetable rooms map to the campus by source kind, not by room pattern.**
   Every CIS room is on campus; a pattern would be a second place to be wrong
   (§23.2 rule 5).
3. **Routes are symmetric and carry one mode.** A manual time typed twice is a
   chance for the two to disagree; slice 3 can make routing directional
   without changing the row (§23.3).
4. **No default travel time.** The built-in route starts empty, and an event
   that needs it says `Not set` rather than drawing a guessed band (§24.3,
   §25.3).
5. **The origin rule is a fixed two-hour gap, and placeless events are
   transparent** (§24.2). Simple to explain and to test; smarter rules
   ("would going home be worth it?") need real travel times first.
6. **Legs are stored for every future event, with no horizon.** Manual times
   cost nothing, and a band that disappears in week 3 would read as a defect.
   Slice 3 sets a horizon for routed times (§24.5).
7. **A `needsTravelTime` leg is a stored state**, so "why is there no
   leave-by?" has one answer on every surface (§24.3).
8. **One notification per event.** An event with a leave-by gets no "starts"
   (§27.2). Turning `Leave by` off falls back to the start rule, so nothing
   goes silent by accident.
9. **Four rules, by category** (leave-by, timetable, personal, routine) —
   BRIEF's "per category", and the minimum that lets routine blocks be
   switched off on their own (§27.1).
10. **Absolute times only in notification copy** (§27.3). Notification Center
    keeps them; relative times go stale.
11. **The chain clamp** for "starts" notifications (§27.3): the second of two
    back-to-back lectures is announced when the first ends. It answers most
    of "notifications during lectures" without a new setting (G-090).
12. **Protected windows hold, they don't drop** (§27.5), and a held leave-by
    that arrives late says why. The rule's "unless the event is inside it" is
    read as "the event strictly overlaps the window" — §13.6.1's test.
13. **No late notifications in an ordinary pass** (§27.6). Only the passes
    after launch and wake catch up, because those are the cases where Kadence
    could not deliver on time.
14. **Delivered notifications are cleared once their event is over** (§27.6,
    §27.9): a pile of stale reminders is a backlog the no-guilt rule forbids.
15. **Permission is asked at the first thing to schedule, not at launch**
    (§27.8): on a real first run that is right after the Import.
16. **"Leave now"** for the should-have-left state (§26.1), with the
    leave-by time in the popover — an instruction rather than an elapsed
    figure. Proposed as a DECISIONS entry because 2026-09-10 says late states
    are "phrased as elapsed".
17. **A due departure outranks a late item** 30 minutes before it (§26.1), so
    a lecture nobody marked done cannot hide when to leave.
18. **The popover's meta line takes §3.4's order** (time · location · source),
    because the leave line points at the room (§26.2).
19. **The band gets no "should have left" look** (§25.2): the now line already
    crosses it, and red on a block would break §1.
20. **Settings and permission state live in the store** (`AppSettings`), not
    `UserDefaults`, so review and test launches can never read or write the
    real ones (§28.1).
21. **The review dataset `travel` has no routine template**, so travel and
    notifications are reviewed without conflicts in the frame, and drops the
    `{{TODAY}}` lecture so the one clock-relative event (P6) has a
    predictable origin (§30.1).
22. **G-083 is not fixed here**, though it is a design item: the brief scopes
    this session to the slice.

## For Parsa — decisions that are yours

1. **Your travel time from home to the FH**, and its mode (`Public transport`,
   `Walking`, `Driving`). The built-in route starts empty; the review uses 35
   minutes by public transport.
2. **The default buffer** — proposed 10 minutes (0 / 5 / 10 / 15 / 20 / 30).
3. **The default lead times** — leave-by 5 min and timetable 30 min (your
   brief's numbers); personal events 15 min and routine 5 min (proposals).
4. **Whether routine blocks notify by default** — proposed on (5 min). Off
   is one switch.
5. **Notifications during lectures** (G-090) — proposed: allowed, with the
   next lecture's "starts" held until the one before ends. The alternatives
   are holding everything until a lecture ends, or delivering silently.
6. **The chain gap** (G-087) — proposed 2 hours, not shown in Settings.
7. **Time-sensitive leave-by notifications** (G-089) — they would break
   through a Focus, but need the time-sensitive entitlement.
8. **"Leave now"** as the should-have-left wording (proposed DECISIONS entry
   5), versus an elapsed form such as `Leave-by 4m ago`.
9. **The 30-minute takeover** of a late item by a due departure (§26.1).
10. **The campus place's name** — `FH Technikum Wien` by default; you can
    rename it in Settings.
11. **Sync-failure notifications** (G-060) — kept out of this slice. A
    notification when sync pauses after a 401/403 would be a small addition
    (one rule, one copy row) if you want it now.
12. **A42** (now-time label overlap) is logged, not built. It could ride along
    with task 10, which touches the canvas, if you want it in this slice.
