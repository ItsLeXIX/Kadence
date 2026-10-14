# Phase 3 — slice 2 plan: leave-by (routed by Apple Maps) and notifications

Design agent, 2026-10-14. Written after slice 1 was accepted
(`PHASE3-REVIEW.md` "Final — 2026-10-14"; DECISIONS 2026-10-14 "Phase 3
slice 1 accepted"). **Rewritten the same day for Parsa's routing amendment,
before anything of slice 2 was built**: travel times are worked out by Apple
Maps, not typed. This file replaces the first version entirely; nothing of
the first version's task list was started.

## Scope

This slice answers "when do I leave?" and makes sure Kadence tells the user
without being checked.

- **Leave by.** Each event that needs travel gets a departure time:
  `start − travel time − buffer`.
  - Travel time comes from a `TravelTimeProvider`. The slice's only real
    provider is **`MapKitTravelTimeProvider`** (`MKDirections.calculateETA`,
    arrive-by `start − buffer`, transit included). **There is no manual
    provider and no typed travel time** — not even as a fallback.
  - **Places**: `Home` (the user types its address; MapKit looks it up once;
    the user confirms what was found), **FH Technikum Wien** (built in with
    its real address `Höchstädtplatz 6, 1200 Wien`, looked up automatically —
    no hard-coded coordinate), and any place the user adds (confirmed like
    Home). Timetable rooms are at the campus; online lectures, routine blocks
    and all-day events need no travel; a manual event travels only if the
    user gives it a place.
  - **The user chooses only how they travel**: one preferred mode (`Public
    transport` by default, `Walking`, `Driving` — no cycling on macOS 15,
    G-095), optionally overridden per pair of places. Not per event (G-094).
  - **Origin**: the last event that had a place if it ended at most two hours
    earlier, otherwise Home; same place, no travel. For the **next departure
    only**, inside its last 45 minutes, the current location may replace
    that origin — with permission asked on first need, never stored, never
    logged, and the app complete without it.
  - **When Apple Maps is asked**: on change (through a cache keyed by origin,
    destination, mode, direction, day type and 30-minute slot, so a semester
    costs a few dozen requests), and in **departure refreshes at T−3 h and
    T−45 min**; through one queue with a budget and a pause after throttling.
  - **Failures never drop a leave-by silently and never invent a number**:
    the last known time marked `≈ estimate`, or "travel time unavailable"
    with the reason, on every surface.
  - The result is stored as a `TravelLeg` per event (status, mode, source,
    `computedAt`, `isEstimate`), recomputed whenever an input changes, never
    written onto the event. The travel band draws it, the inspector explains
    it, the menu bar shows `Leave 08:15 · SWQM-ILV`, then `Leave now`.
- **Notifications** through `UNUserNotificationCenter`:
  - At most one per event: leave-by (N1; N1e for an estimate; N7 "travel
    unavailable" when no time could be worked out), otherwise a "starts at"
    under its category. Leave-by notifications are **time-sensitive**,
    degrading to normal without the entitlement.
  - **Sync paused** (G-060, Parsa): one notification when a source's
    background sync pauses after a 401 or 403.
  - Actions `Done` · `Snooze` · `Open` (no `Snooze` on imported events).
  - Quiet inside protected windows unless the event is inside one; allowed
    during lectures, with the next lecture's "starts" held to the end of the
    one before.
  - A rolling 48-hour schedule, deduplicated by identifier; permission asked
    when there is first something to tell, and never silently missing.
- **A42** (G-082, the now time printed over an hour label) is **built** in
  this slice.

**Not in this slice:** cycling (G-095), a per-event travel mode (G-094),
routes on a map, Moodle and work items, deadline and morning-summary
notifications (G-088), timetable-change notifications (G-060's remainder),
mail, the planner, G-083 (Day header). **A41 is logged, not built.**

**No task needs a network, location services or a permission prompt to
pass.** The travel provider, the geocoder, the location source and the
network path monitor are mocks in every test and every review launch; the
notification centre is the recording double (`components.md` §24.11,
§27.10), as the store and the CalDAV transport already are (§22.1, B45). The
MapKit and CoreLocation implementations are compiled and constructed only
by a normal launch; their only tested parts are pure mapping functions.

## Spec sections — new and changed

| Where | What | § |
|---|---|---|
| `components.md` | Slice-2 intro: scope and the two new governing rules (never a guessed number; where you are stays yours) | "Phase 3 — slice 2" |
| | **Rewritten**: places, addresses and ways to travel — known places, which place an event is at (unchanged), modes and the cycling check, preferred mode and pair overrides, buffer, looking up an address (states and exact copy), the campus's address | §23.1–§23.6 |
| | **Rewritten**: travel legs — candidates, origin rule, **where you are now** (§24.2.1), the leg's four statuses, worked example with the mock and its variants, storage, **when legs are recomputed and when Apple Maps is asked** (refreshes T−3 h / T−45 min), never writes the event, not a promise, **the provider, geocoder, cache and queue** (§24.9), **failures and their exact copy** (§24.10), **privacy and logging** (§24.11), **location permission** (§24.12) | §24.1–§24.12 |
| | The band: drawn for `ready` and `estimate`; the `≈` mark; hover help; no band for `pending` / `unavailable` | §25.1, §25.3 |
| | Menu bar: estimate in the Leave unit; no-time legs show Normal; the popover's leave line in seven forms | §26.1, §26.2 |
| | Notifications: five rules (`syncPaused` added, Parsa's defaults), which notification a leg state gets, N7's fire time, copy **N1e, N7, N8**, time-sensitive levels and the degrade rule, N8's rules, identifiers (`sync.`), the refresh catch-up, category `kadence.source`, the recorded interruption level | §27.1–§27.4, §27.6, §27.7, §27.10 |
| | **Rewritten**: data model — `KnownPlace` (address, confirmed address, coordinate, geocode state), `TravelModeOverride`, `AppSettings` (preferred mode, location), `TravelLeg` (status, reason, mode, origin kind, source, `computedAt`, `isEstimate`, `refreshedAt`), `TravelETACache`, five `NotificationRule`s, `NotificationRecord.subjectID`; `TravelRoute` withdrawn | §28 |
| | VoiceOver: estimate, pending/unavailable, the new Settings controls | §29 |
| | Review: items 1–3, 12, 13, 15 amended; **18–23** new (address lookup, location states, estimates, `noRoute`, A42, routing and sync plans); fixtures — mock coordinates, the mock provider's table, geocoder and location cases, variants `travelNoAddress` / `travelOffline` / `travelPending` / `travelNoRoute`; routing, refresh, location and N8 tables; routing test cases | §30, §30.1 |
| | Already amended (unchanged by this amendment): §4, §8 (G-082 → A42), §11, §12, §15.1, §15.2 | |
| `layouts.md` | Inspector `Leave by` row: `ready`, `estimate`, `pending`, `unavailable`, with `Add Address…` / `Change Way to Travel…` / `Try Again` | §6 (rewritten bullet) |
| | **Settings ▸ Travel, rewritten**: Places with the lookup line and match list, Ways to travel, Leave by, Where you are with the location block | §13 |
| | Settings ▸ Notifications: the fifth rule `Sync problems` | §14 |
| | Settings tab entry points | §11 (one line) |
| `interactions.md` | N8's `Open` | §14.1 |
| | Confirming an address; location | §15.3 (amended), §15.4, §15.5 (new) |
| `GAPS.md` | G-087, G-089, G-090 closed; G-060 split (sync paused in, timetable changes deferred); G-082 built here; G-093–G-096 opened; G-092 extended | "2026-10-14 — Phase 3 slice 2 routing amendment" |

## Tokens — `tokens.json` 1.8.0 → **1.9.0** (updated 2026-10-14)

1.8.0 was never built, so CA generates 1.9.0 directly.

| Token | Value | Used by |
|---|---|---|
| `size.settingsPlaceNameFieldWidth` | 160 (from 1.8.0) | a known place's name field, `layouts.md` §13 |
| `size.settingsAddressMatchRowHeight` | **36** (new) | a two-line match row in the address lookup, `layouts.md` §13 |
| `size.settingsAddressMatchListMaxHeight` | **180** (new) | the match list, five rows, never scrolls |
| `size.settingsMinutesFieldWidth` | **retired** | typed minutes were withdrawn |
| contrast pair `color.semantic.now` on `color.surface.popover` (min 4.5) | 4.55 / 5.12 (from 1.8.0) | the popover's `Leave now` line |

**No colour is added** (`$measured_1_9_0`): `≈`, `estimate`, `Working out…`,
`Unavailable` and the reason lines reuse pairs declared since 1.0.0–1.5.0.
64 pairs. `semantic.now` on `surface.inspector` still fails in light (4.25)
and is still never used there.

## DECISIONS.md — proposed entries

Seven entries plus the defaults entry, ready to paste after Parsa's
confirmation; they **replace all six proposed earlier today** (the first
draft's "typed travel times" entry is withdrawn; the others are revised for
routing, time-sensitive delivery and the sync notification). The text is in
the design agent's final message for this session.

1. **Travel times come from Apple Maps; the user chooses only how they
   travel.** §23, §24.9, §28.1.
2. **Kadence asks Apple Maps sparingly, and again before each departure.**
   §24.6, §24.9.
3. **A failed route is said, never guessed.** §24.10.
4. **Where you are is used for the next departure only, and never kept.**
   §24.2.1, §24.11, §24.12.
5. **A travel leg is derived data.** §24.5–§24.7.
6. **One notification per event, with absolute times; leave-by is
   time-sensitive; a paused sync is told once.** §27.1–§27.4, §27.7, §27.9.
7. **Protected windows hold notifications; they never drop a departure.**
   §27.5.
8. **"Leave now" is the should-have-left state, and a due departure outranks
   a late item.** §26.1.
9. **Kadence asks for permission when it first needs it, and says so when it
   can't.** §27.8, §24.12.
10. **Slice 2 defaults, confirmed by Parsa.**

## BUILD TASK LIST for CA — dependency order

**Common rules for every task:**

- One task per session. Tests run with `-only-testing:KadenceTests`.
- Persistence tests use a real in-memory `ModelContainer` (DECISIONS
  2026-09-10).
- **Injected clock and scheduler everywhere**: no planner, recompute, queue,
  refresh or notification pass reads `Date()` or sleeps. The test zone is
  Europe/Vienna; `M` = Mon 2026-10-12.
- **No real services in tests or review**: `MapKitTravelTimeProvider`,
  `MapKitPlaceGeocoder`, `SystemLocationSource`, the `NWPathMonitor`-backed
  monitor and `SystemNotificationCenter` are constructed **only** by a normal
  launch (a factory per service, its launch-kind table asserted as B45's
  store is). Tests and review use `MockTravelTimeProvider`,
  `MockPlaceGeocoder`, `MockLocationSource`, a scripted path monitor and
  `RecordingNotificationCenter`. **No task triggers a permission prompt or a
  network request.**
- **MapKit and CoreLocation are imported only** in the files of the two
  MapKit types and `SystemLocationSource` (a test reads the target's sources
  and asserts it). Every other file reaches them through the protocols.
- **Nothing logged with an address, a coordinate, a place name, an event
  title or search text** (§24.11): every task that logs asserts its lines
  against §24.11's forms.
- **No Xcode capability or Info key is needed by any task** (G-096 is
  Parsa's, at run time only). If one is missing, the build and every test
  still pass.
- Never open, read or write the real store (§22.1). Record its `stat` before
  and after as in slice 1 (STATUS §132).
- A UI task's captures go to `screenshots/3b/<name>-p3bt<N>.png`; task 18
  recaptures the set from the final build (§17.2 rule 2).
- `generate-tokens --check` is clean at **1.9.0** from task 1 on.
- Baseline: **902 tests pass** (STATUS §132). Every task ends with the whole
  suite green.

### Task 1 — Data model and built-ins; tokens 1.9.0; log A41 and A42

*Spec:* components §28, §23.1, §23.3, §23.6 (the campus address), §27.1
(five rule defaults), §21.1.1 (the built-ins pattern).

**Build:**

- `@Model`s `KnownPlace`, `TravelModeOverride`, `AppSettings`, `TravelLeg`,
  `TravelETACache`, `NotificationRule`, `NotificationRecord`, exactly §28.1's
  fields; enums as raw strings (`TravelMode` `transit` / `walking` /
  `driving`); every field defaulted.
- `Event.placeID: String?`. `EventStore`'s delete snapshot and duplicate
  carry it.
- First-launch built-ins, idempotent, in every launch kind: places `home`
  (no address, `none`) and `campus` (`addressText` `Höchstädtplatz 6, 1200
  Wien`, `unconfirmed`, **no coordinate**), `AppSettings` (`transit`, 10, 120,
  `useCurrentLocation` on, the three dates nil), the five rules. A store with
  four rules gains `syncPaused`.
- Regenerate `Tokens.swift` at 1.9.0.
- **DEVIATIONS.md**: under a new heading `## Phase 3 slice 2 — leave-by and
  notifications (2026-10-14)`, log **A41** (the `copies` log field and the
  step-2 count of `merged − copies`; G-081's end-time sentence —
  `components.md` §20.8.4, `layouts.md` §12.2, `caldav-mocks.md`
  `reportCISCopies`) — **deferred, still normative, not built in this
  slice** — and **A42** (G-082: the now time and hour labels measured as
  drawn, 2pt clearance; the cursor time likewise — `components.md` §8) —
  **scheduled in this slice, task 2**; with the wording of `GAPS.md`
  "Deferred by this check" (2026-10-14).

**Acceptance — tests:**

- A store written by the slice 1 build opens; every event reads back
  unchanged with `placeID` nil; no leg, cache row, record or extra place
  exists until the built-ins run.
- Built-ins: two launches against one container leave exactly one of each
  (2 places, 1 `AppSettings`, 5 rules), with §28.1's and §27.1's defaults;
  the campus has its address and **nil** latitude/longitude.
- `KnownPlace`: latitude and longitude are both set or both nil (a write of
  one alone is refused).
- `TravelModeOverride` stores its pair sorted; a second override for the
  same pair in either order is refused.
- Delete a manual event with a `placeID`, undo: `placeID` is back. Duplicate
  copies it.
- `Tokens.Size.settingsAddressMatchRowHeight == 36`,
  `settingsAddressMatchListMaxHeight == 180`; `settingsMinutesFieldWidth`
  does not exist.
- DEVIATIONS.md contains `A41` and `A42` under the new heading.
- All 902 tests still pass.

*Captures:* none.

### Task 2 — A42: the now time and hour labels, measured as drawn

*Spec:* components §8 (amended 2026-10-14, G-082); `interactions.md` §1 (the
cursor time); §30 item 22.

**Build:** the time gutter's suppression compares the **drawn text frames**
of the now time (and the cursor time) and each hour label: an hour label is
dropped when the frames overlap or come within 2pt. Week and Day.

**Acceptance — tests** (the gutter's layout model, injected clock, Week and
Day hour heights):

- At 10:18 the `10:00` label is dropped and no label's frame is within 2pt
  of the now time's; at 10:40 `10:00` and `10:40` are both drawn.
- The boundary: the latest and earliest minutes at which `10:00` is dropped
  are computed from the frames (hour height, label hang, font line height)
  and pinned in the test, for Week and for Day.
- The cursor time at 10:18 drops `10:00` by the same rule.
- No Phase 1 gutter test regresses (a test that encoded the 12pt-time rule
  is updated — the rule is the spec change, not a regression).

*Captures:* `now-label-week-1018-p3bt2.png`, `now-label-day-1018-p3bt2.png`,
`now-label-week-1040-p3bt2.png` (offscreen, clock pinned).

### Task 3 — Places and the leg planner (pure)

*Spec:* components §23.2, §23.3, §24.1–§24.4, §24.9 (the cache key),
§24.10 (statuses and fallback).

**Build:**

- `PlaceResolver` (§23.2's six rules; the timetable rule reads the resolved
  `Source`'s kind, §21.1.1).
- Mode resolution (pair override, else preferred).
- `TravelLegPlanner`: value snapshots in (events, places, overrides,
  settings, sources, the cache, the queue's failure and pause state,
  `today`, `now`), out: **legs** (`ready` / `estimate` / `pending` /
  `unavailable`, reasons, `departAt = start − buffer − duration`) and the
  **requests it needs** (key, endpoints, `arrivingBy`, mode, priority). It
  calls no provider. Cache-key construction (direction, day type, 30-minute
  slot of `start − buffer`, place id + coordinate to 5 decimals).

**Acceptance — tests** (events built in code from §30.1's dataset `travel`,
clock Mon 12 Oct 06:00, caches built in code):

- With a cache holding the mock's answers: §24.4's table, row for row
  (status, origin, destination, `departAt`, `duration`, `buffer`, `mode`,
  `source` `mock`), and **no requests**.
- With an empty cache: every leg `pending`, and exactly one request per
  distinct key (§30.1 "Cache sharing"), priorities by §24.9.
- Variants `travelNoAddress` (every leg `unavailable · needsAddress`, place
  `home`, **no requests**) and `travelOffline` (estimates and unavailable
  exactly as §24.4), and the fallback order of §30.1's routing cases.
- §30.1 "The test day": overlap, chain through a placeless event, 120 vs
  121 min, skipped previous; cancelled and all-day events are never
  candidates; a routine block between two lectures changes nothing; an online
  lecture is never an origin; a `.done` previous event is still an origin;
  origin ties resolve by later start, then smaller id.
- Freshness: an entry 14 days old → `ready`, no request; 14 days + 1 s →
  `ready` from that entry **and** a request; that request failing →
  `estimate` from the same entry.
- Inside a refresh window: with `refreshedAt` at the slot → `ready`; with the
  slot's refresh failed → `estimate`, reason carried.
- `noRoute` and `needsAddress` never fall back; a mode-mismatch answer is
  `noRoute`.
- §23.2: an imported event from a source of another kind has no place; a
  timetable event with an empty location has none; a manual event whose
  `placeID` names no place has none.

*Captures:* none.

### Task 4 — Provider, geocoder and cache: protocols, mocks, MapKit behind them

*Spec:* components §24.9, §23.5 (lookup results), §23.6, §24.11.

**Build:**

- `TravelEndpoint`, `TravelTimeError`, `TravelTimeProvider`;
  `GeocodedAddress`, `GeocodeError`, `PlaceGeocoder` — §24.9 exactly.
- `MockTravelTimeProvider` (§30.1's table, scriptable answers per key,
  failures, delay, a call log) and `MockPlaceGeocoder` (§30.1's cases).
- `MapKitTravelTimeProvider` and `MapKitPlaceGeocoder`, each with its
  **mapping as a pure function** (`MKError` / `URLError` / an answer's
  `transportType` → result; a map item → `GeocodedAddress`; the result cap of
  6) — the only parts tests touch.
- The cache store: upsert an answer, read by key, delete by place or by old
  coordinate, prune > 28 days at launch.
- The provider factory with its launch-kind table.

**Acceptance — tests:**

- Error mapping: `loadingThrottled` → `throttled`; `directionsNotFound` →
  `noRoute`; `notConnectedToInternet` / `networkConnectionLost` (as the
  error or its underlying error) → `offline`; `serverFailure`, unknown,
  timeout → `failed`; an answer whose transport type differs → `noRoute`.
- Mode mapping: `transit` → `.transit`, `walking` → `.walking`, `driving` →
  `.automobile`; no other value is ever produced.
- The geocode result mapping keeps at most 6; 0 → `[]`.
- The factory: a test-host and a `-KadenceReview` launch construct the mocks
  and never a MapKit type.
- Only the two MapKit files import MapKit (source scan).
- Cache: two answers for one key keep the later; a new Home coordinate
  deletes the old key's rows; pruning at launch deletes > 28 days only.

*Captures:* none.

### Task 5 — The routing queue

*Spec:* components §24.9 ("The routing queue"), §24.10 (`paused`), §24.11
(log lines).

**Build:** `RouteRequestQueue` — priorities 0–4, dedupe by key, one in
flight, 2 s spacing, 20 per rolling 10 min, 150 a day (+30 for priorities
0–2), throttle pause 10 → 20 → 40 → 60 min reset by a success, offline pause
until the path monitor reports satisfied or 5 min, a 20 s timeout, dropping
requests whose leg is gone; the failure / pause state the planner reads; the
routing log lines.

**Acceptance — tests** (mock provider, injected scheduler and monitor):

- §30.1 "Queue" bullet, case by case.
- A burst of 30 distinct keys at once: requests leave in priority order, 2 s
  apart, the 21st waits for the rolling window; nothing is sent twice.
- `throttled` → every waiting request carries `retryAt`; the log has `queue
  paused · until HH:mm`; the next success resets the back-off.
- `offline` → paused; the monitor reports satisfied → resumes at once.
- Day budget: the 151st priority-4 request waits until 00:00; a priority-1
  request still goes.
- Every log line matches §24.11's forms; none contains a coordinate pattern,
  a fixture address, a place name or an event title.

*Captures:* none.

### Task 6 — Leg store, recompute and departure refreshes

*Spec:* components §24.5–§24.8, §24.6 (refreshes), §23.6 (the automatic
campus lookup); §20.8.4 ("Local identity"); §20.9.

**Build:**

- Applying a plan in **one transaction**: upsert changed legs, delete owned
  legs no longer planned, never touch legs of events before
  `startOfDay(today)`, delete a leg with its event.
- The recompute coordinator: §24.6's triggers (including routing answers and
  refresh completions), a 0.5 s debounce on the injected scheduler; it hands
  the planner's requests to the queue; a hook that asks for a notification
  pass (a no-op until task 9).
- Departure refreshes: T−3 h and T−45 min per leg of a not-started event
  today or tomorrow, re-planned on each recompute, cache-bypassing, a missed
  slot run once at launch / wake before the start; `refreshedAt`.
- The campus's automatic lookup (§23.6): once when first needed; accept on
  the match rule; otherwise `unconfirmed` / `notFound` / `lookupFailed`; at
  most one automatic retry a day.

**Acceptance — tests:**

- Two recomputes of the same inputs write nothing the second time.
- A mode change (override or preferred) changes today's and future legs,
  asks for the new keys, and leaves a leg of yesterday's event byte-equal.
- Delete an event → its leg is gone in the same transaction; undo → the leg
  is back after the next recompute, **with no provider call** (cache).
- After a recompute, every event's §20.8.4 hash and the source's `feedHash`
  are equal to before; `lastChange*` is unchanged; the undo stack is
  unchanged.
- §30.1 "Sync" table (`reportChanged` at Mon 12 Oct 06:00), row for row,
  including "no provider call" for the moved `SWEN3-LAB` and the new
  `KOKU-UE`, and `REQEN-EXAM` losing its chain.
- 50 event writes in 0.2 s → one pass; 10 answers arriving together → one
  pass.
- Refresh schedule (§30.1 routing case): slots 09:15 and 11:30 for a 12:15
  departure; moved event → re-planned; missed slot at wake → one refresh;
  after the start → none.
- §30.1 "Departure refresh" (without the notification half, which task 9
  adds): 50 / 78 / 30 min answers change `departAt` to 12:00 / 11:32 /
  12:20.
- Campus lookup: matching first result → `confirmed`, coordinate stored;
  non-matching → `unconfirmed`, legs `unavailable · needsAddress (campus)`;
  `offline` → `lookupFailed`, no second attempt the same day; never an
  automatic lookup for Home or a user place.
- `NSCalendarDayChanged` at midnight moves the ownership window.
- A recompute while a conflict preview is active changes no previewed
  block.

*Captures:* none.

### Task 7 — Where you are: the next departure's origin

*Spec:* components §24.2.1, §24.11, §24.12.

**Build:** `LocationSource`, `MockLocationSource`, `SystemLocationSource`
(normal launch only; `CLLocationManager`, one-shot fix, hundred-metre
accuracy, 10 s timeout); the authorization mapping (`allowed` / `denied`
(incl. restricted) / `servicesOff` / `notDetermined`); the selection of the
next departure; using the fix at its T−45 refresh (age ≤ 2 min, accuracy ≤
200 m, > 300 m from the rule origin); the leg's `originKind`; the ask-once
rule with `locationRequestedAt`; the off switch.

**Acceptance — tests** (mock location, mock provider):

- §30.1 "From where you are", exactly: departure 12:22, `originKind
  currentLocation`, `originPlaceID` nil, **no cache row**, the log line `eta
  ok · 28 min · transit · refresh · here`; within 300 m → rule origin and
  `location not used · within 300 m`.
- §30.1 routing case "Location", bullet by bullet.
- First wanted fix with `notDetermined` and never asked → exactly one
  `requestAuthorization`, `locationRequestedAt` set, the rule origin used;
  a later refresh → no second ask.
- `useCurrentLocation` off → the mock records **no call at all**.
- A `currentLocation` leg survives an unrelated recompute and is replaced by
  the next refresh or by a change of event, destination, mode or buffer.
- After every case: no stored row (any model) and no log line holds the fix's
  coordinate (a scan of the in-memory store and the captured log).
- The factory: test-host and review launches never construct
  `SystemLocationSource`; only its file imports CoreLocation.

*Captures:* none.

### Task 8 — Notification planner (pure)

*Spec:* components §27.1–§27.5, §27.6 (the planning half), §27.9.

**Build:** `NotificationPlanner` and the copy formatter for N1–N8 and N1e;
the leg-state → notification rule (§27.2); N7's `start − 60 min`; the quiet
rule over `TimeWindow.spans(on:)`; the chain clamp; the 48-hour window, the
48 cap; ordinary and catch-up modes; the refresh catch-up for one leg;
interruption levels; records as "sent".

**Acceptance — tests:**

- §30.1's notification table at **Thu 15 Oct 06:00** (4 requests) and at
  **Fri 16 Oct 23:00** (3 requests): identifiers, fire dates, titles,
  bodies, categories, sounds and **interruption levels**, exactly.
- §30.1 "Routing states at Thu 06:00": `travelOffline` (N1e, N7) and
  `travelNoAddress` (N7), exactly; after recovery, the same identifiers with
  N1 content.
- §30.1 "Departure refresh", the notification half: replaced at 11:55 / 12:15;
  the 78-min answer delivered at once **in an ordinary pass** (refresh
  catch-up), and no other request in that pass late.
- Catch-up at Thu 12:12 (N1 at once), 12:20 (N3 at once), 13:05 (nothing);
  the same clocks in an ordinary pass plan nothing late.
- The test-day extras: back-to-back protected spans (held to 07:30); leave by
  off → `start.` at 12:30 under `timetableStart`; all rules off → empty.
- Exclusions: done, skipped, cancelled, all-day, events before today, a
  subject time in the past.
- At most one of `leave.` / `start.` per event, in every case, including
  N7.
- Window edges: `now + 48 h` planned, one second later not; 60 candidates →
  the 48 earliest.
- A sent record is never planned again; a later subject is.
- No title or body contains `late`, `missed`, `overdue` or `!`; none
  contains an address or a coordinate.

*Captures:* none.

### Task 9 — The centre, the applier, scheduling and permission

*Spec:* components §27.6, §27.8, §27.10, §27.4 (levels and the degrade
rule); §22.1's three-launch rule (B45).

**Build:**

- `NotificationCenterClient`, `SystemNotificationCenter` (normal launch
  only, the only file that names `UNUserNotificationCenter`),
  `RecordingNotificationCenter` (records the interruption level; can be
  scripted to reject time-sensitive adds).
- The applier: diff by identifier and content hash; replace, remove, record;
  remove delivered notifications of ended, deleted, done, skipped or
  cancelled events; owned prefixes `leave.`, `start.`, `result.`, `sync.`;
  never touch foreign identifiers; the one retry with `.active` on a
  time-sensitive `add` failure.
- Passes: after each recompute, on rule and `TimeWindow` edits, on
  authorization change, hourly; one at a time, coalesced, 1 s debounce.
  Catch-up for the pass after launch and after wake; the refresh catch-up.
- Authorization: §27.8's mapping; request once when the first pass has
  something to schedule; re-read on `didBecomeActive`.
- Categories registered at launch (`kadence.event`, `kadence.readOnly`,
  `kadence.result`, `kadence.source`); `willPresent` options.
- Review argument `-KadenceNotifications allowed|off|notDetermined|notAsked`.

**Acceptance — tests** (recording centre, injected clock):

- Two passes over the same inputs → the second performs no add and no
  remove.
- Move an event → the same identifier replaced, never duplicated. Done →
  removed. Delete → removed, delivered cleared.
- A leg goes `pending` → `ready` → N7 replaced by N1 under `leave.`.
- `off` → nothing added or removed; switching to `allowed` → the plan added
  as an ordinary pass.
- First pass with a plan, `notDetermined`, never asked → exactly one
  `requestAuthorization`; a second pass → none; all rules off → none.
- The hourly pass at Thu 06:00 + 1 h adds what entered the window.
- A foreign identifier survives every pass.
- A time-sensitive `add` rejected by the scripted centre → added again once
  as `.active`, the log has `notification degraded · time-sensitive
  unavailable`; nothing fails.
- Test-host and `-KadenceReview` launches never construct
  `SystemNotificationCenter`.

*Captures:* none.

### Task 10 — Notification actions

*Spec:* components §27.7; interactions §14.1.

**Build:** the delegate's response handler and an action router: `Done`,
`Snooze` (via `EventStore.snooze`, N5 / N6 at once), `Open`, the default
action, dismiss; `Open` through the popover's existing path; `kadence.source`
`Open` → Settings ▸ Sources with the source selected.

**Acceptance — tests** (simulated responses, §30.1 "Actions"):

- `Done` on `start.{REQEN-EXAM}` → `.done`, one `Mark Done` step; again →
  nothing.
- `Snooze` on `leave.{Dinner}` at Thu 17:41 → 18:45–20:15, one `Snooze`
  step, N5 exact; after the recompute and pass, `leave.{Dinner}` fires 17:55
  with `Leave by 18:00 for Dinner with flatmates` (the new slot is
  answered by the mock through the queue).
- `Snooze` on `start.{Late call}` at Sat 23:01 → nothing written, no undo
  step, N6 exact.
- `kadence.readOnly` has no `Snooze`; `kadence.result` none;
  `kadence.source` only `Open`.
- `Open` / default select the event and page to its day; unknown id → today,
  nothing selected; `Done` / `Snooze` on an unknown id do nothing.
- `Open` on `sync.{source}` → the Settings-open request names `Sources` and
  the source id.
- Results carry no sound; N1–N4, N1e, N7, N8 the default sound.

*Captures:* none.

### Task 11 — The sync-paused notification (G-060)

*Spec:* components §27.1 (`syncPaused`), §27.4 N8 and its rules, §27.6;
§19.1 (`unauthorized`, `forbidden`); §30.1 "Sync paused".

**Build:** the sync engine reports state **transitions** to the
notification scheduler with whether the sync was user-started and whether
Kadence was frontmost; the planner emits `sync.{sourceID}` (N8) on entering
`unauthorized` / `forbidden` from a background, wake or launch sync; removal
on leaving the paused state or removing the source; the quiet hold.

**Acceptance — tests** (`MockCalDAVTransport` cases `unauthorized` and
`forbidden`, recording centre):

- §30.1 "Sync paused": both bodies exact, category `kadence.source`,
  level `.active`, 1-second trigger; at 03:00 inside Sleep → fires 07:00.
- A second paused sync → no new add.
- Recovery (`reportOK` after `Update Password…`) → pending and delivered
  `sync.` removed.
- `Sync Now` / Import / connect sheet reaching `unauthorized` while
  frontmost → nothing.
- `Sync problems` off → nothing; on again while still paused → nothing new
  (the transition has passed).
- Removing the source removes its `sync.` notification.
- The body never contains the password or an `Authorization` value (the
  mock's password string is searched for).

*Captures:* none.

### Task 12 — Review mode: datasets, variants and mocks

*Spec:* components §30.1; §22.1 (review rules); §24.11.

**Build:**

- `Fixtures/ICS/cis-travel.ics.template` (the review template without row 1,
  plus T1).
- Dataset `travel` with every §30.1 item: places with mock coordinates,
  the override, the mock provider's table, the live event P6; variants
  `travelNoAddress`, `travelOffline` (with the stale cache entry),
  `travelPending`, `travelNoRoute`.
- Arguments `-KadenceGeocode one|several|many|none|offline|searching` and
  `-KadenceLocation allowed|denied|servicesOff|notDetermined|notAsked`.
- `phase2` / `phase3` seeding: places, walking overrides, mock answers,
  buffer 0 (`Café Sperl`). `empty` / `fresh`: built-ins, the campus confirmed
  by the mock geocoder.
- The notification-plan dump (§30 items 14 and 23), produced like the
  offscreen renders (§17.2 rule 3), from the real planner, at pinned
  clocks.

**Acceptance — tests:**

- Dataset `travel` (`M` = 2026-10-12, clock Mon 06:00): 14 timetable events
  (15 VEVENTs, one merge), 2 history; no conflicts; legs equal §24.4; every
  variant's legs equal §24.4's variant lines.
- `phase3`: day conflicts 14 and Needs attention 15, unchanged;
  `Datenmodellierung` depart 08:38, 22 min walking; `Coffee with Nora`
  depart 10:54, 6 min walking. `phase2`: the same two legs.
- `empty` / `fresh`: Home `none`; campus `confirmed` with the mock's
  coordinate; preferred `transit`; buffer 10; five rules.
- A review launch of every dataset and variant constructs no MapKit,
  CoreLocation, `NWPathMonitor` or `UNUserNotificationCenter` object (the
  factories' launch log).
- The plan dump at §30.1's clocks equals the notification tables, including
  the routing, refresh and sync-paused ones.

*Captures:* none.

### Task 13 — Settings ▸ Travel: places and confirming an address

*Spec:* layouts §11 (three tabs), §13 (Places); components §23.1, §23.5,
§23.6; interactions §15.3, §15.4; §29 (Settings rows); tokens 1.9.0.

**Build:** the three tabs with their symbols; the Places section — name,
address, the lookup line and its controls in every §23.5 state, the match
list (`settingsAddressMatchRowHeight`, `…ListMaxHeight`), `Still using …`,
remove with the alert, `Add Place`, the footer; the lookup through the
queue at priority 0; every confirmation triggering a recompute.

**Acceptance — tests** (view model and store, mock geocoder):

- Committing an unchanged address → no lookup; a changed one → exactly one
  lookup; typing without committing → none.
- Each mock case's line and controls, exact (§23.5's table); `many` → the
  "more than 5" line and 5 rows.
- `Use This Address` / a row → `confirmedAddress`, coordinate, `confirmed`,
  `geocodedAt`, a recompute; `Cancel` → the previous confirmed address
  restored, nothing written.
- A new address on a confirmed place: the old coordinate kept until
  confirmation, `Still using …` shown; clearing → `none`, legs
  `needsAddress`.
- Leaving with a result unconfirmed → `unconfirmed`, `Look Up` → one lookup.
- An empty or duplicate name reverts; `Add Place` → `New Place`, `New Place
  2`; removal with 2 manual events asks with the exact text and clears
  their `placeID`, its overrides and cache rows; unused → removed at once;
  built-ins have no remove button.
- The focus order and keyboard of interactions §15.4 (`↓` into the list,
  `↩`, `⎋`).
- VoiceOver labels and values of §29's Settings ▸ Travel rows.

*Captures:* `settings-travel-first-run-p3bt13.png` (`empty`),
`settings-travel-filled-p3bt13.png` (`travel`), and item 18's frames
`settings-travel-lookup-<case>-p3bt13.png` (`one`, `several`, `many`,
`none`, `offline`, `searching`, `still-using`).

### Task 14 — Settings ▸ Travel: ways to travel, buffer, where you are

*Spec:* layouts §13 (Ways to travel, Leave by, Where you are); components
§23.3, §23.4, §24.12; interactions §15.5; §29.

**Build:** `Usually`; one pop-up per pair (`Usual` · separator · the three
modes; `Usual` deletes the override); the buffer pop-up; the location
switch and §24.12's status block (`Open System Settings…` through the
injected opener, `Allow Location…` asking once); re-reading on
`didBecomeActive` and when the tab opens.

**Acceptance — tests:**

- Pair rows in layouts §13's order; choosing `Walking` stores one override,
  choosing `Usual` deletes it; both trigger a recompute and requests only for
  uncached keys.
- The pop-up never offers `Cycling` or `Any`.
- Buffer `None` … `30 minutes`; a change moves every future leg's
  `departAt` and the arrival slot (new keys requested where needed).
- Location blocks for `denied`, `servicesOff`, `notDetermined` after an ask
  — titles, bodies, buttons exact; none for `allowed` or never asked; none
  when the switch is off.
- `Open System Settings…` → the opener receives
  `x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices`.
- `Allow Location…` with `notDetermined` → one request; with a source that
  answers without prompting → the opener.
- Opening the tab never asks for location.
- VoiceOver for `Usually`, the pair pop-ups and the switch (§29).

*Captures:* `settings-travel-ways-p3bt14.png` (`travel`), item 19's
`settings-travel-location-<state>-p3bt14.png` (`denied`, `services-off`,
`not-allowed-yet`, `switch-off`).

### Task 15 — Settings ▸ Notifications and the permission states

*Spec:* layouts §14; components §27.1, §27.8; interactions §14.2.

**Build:** the status block (both states, exact copy), the **five** rule rows
(four with switch and pop-up, `Sync problems` with a switch only), the
footer; `Allow Notifications…`; `Open System Settings…`; re-reading on
`didBecomeActive`.

**Acceptance — tests:**

- `off` and `notAllowedYet` show §27.8's titles, bodies and buttons exactly;
  `allowed` and `notAsked` show no block; all rules off shows no block.
- Switch off → pop-up disabled, value kept; switch on while `notAsked` → one
  request. `Sync problems` has no pop-up and its second line is exact.
- `Allow Notifications…` with a centre that answers without prompting → the
  opener receives
  `x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=XIX.Kadence`.
- State → `allowed` on `didBecomeActive` → the block disappears and a pass
  runs.
- VoiceOver for the switches and pop-ups (§29).

*Captures:* `settings-notifications-allowed-p3bt15.png`,
`settings-notifications-off-p3bt15.png`,
`settings-notifications-not-allowed-yet-p3bt15.png`.

### Task 16 — The band live, and the inspector

*Spec:* components §25, §29 (block, inspector); layouts §6, §6.1 (amended);
interactions §15.1–§15.2.

**Build:**

- `TravelBandView` fed by `TravelLeg` (`ready` and `estimate`);
  `TravelFixture` and `MockData.makeTravel` deleted.
- The label with `≈` for an estimate (and its below-18pt form), hover help
  and VoiceOver of §25.1; the past blend of §25.2; no band at a drop
  preview; no band for `pending` / `unavailable`, with §25.3's hover help.
- Inspector `Place` (pop-up for manual, text for imported) with the `No
  travel needed after …` line; `Leave by` in all four states with
  `Worked out … by Apple Maps.`, the `estimate` word, the reason sentences
  and the buttons `Add Address…`, `Change Way to Travel…`, `Try Again`;
  `Set Place` undo step; `Edit Places…`.

**Acceptance — tests:**

- The band model for every §24.4 leg: `Leave 08:15 · 35min`, the frame from
  `departAt` to start, the mode glyph; estimate `Leave 08:15 · ≈35min` and
  `Leave ≈08:15` below 18pt; no band for `pending`, `unavailable`, same
  place, online.
- Hover help exact for ready, estimate, current location and each reason;
  at buffer 0 without the buffer term.
- VoiceOver exactly as §29 for `SWQM-ILV` ready, estimate, pending and
  unavailable.
- The inspector rows' copy for §30 items 9–12, 20 and 21, exact; `Add
  Address…` focuses Home's address field in Settings; `Change Way to
  Travel…` focuses the pair's pop-up; `Try Again` queues one priority-0
  request and is disabled while paused, with the hover help.
- `Set Place` is one undo step; choosing the current place writes nothing.
- The pop-up's items in order: `None`, separator, places by `sortIndex`,
  separator, `Edit Places…`.
- The `Leave by` row never uses `semantic.now`, and no inspector string
  contains an address or a coordinate.

*Captures:* `week-M-travel-p3bt16.png`, `week-M-travel-early-late-p3bt16.png`,
`day-thu-travel-p3bt16.png`, `band-case2-week-p3bt16.png`,
`band-case2-day-p3bt16.png`, `inspector-swqm-leave-p3bt16.png`,
`inspector-reqen-no-travel-p3bt16.png`, `inspector-dinner-place-p3bt16.png`,
`inspector-dinner-place-menu-p3bt16.png`,
`inspector-no-address-p3bt16.png`, `week-M-no-address-p3bt16.png`,
`week-M-estimates-p3bt16.png`, `inspector-epc-estimate-p3bt16.png`,
`inspector-dinner-unavailable-p3bt16.png`,
`inspector-climbing-no-route-p3bt16.png`.

### Task 17 — The menu bar: leave states, takeover, the popover

*Spec:* components §26, §29 (status item, popover).

**Build:**

- `NextUpProvider` extended with the leg, the Leave / Leave now states,
  the estimate unit and §26.1's takeover (for `ready` and `estimate` legs).
- The status item's states and their degrade rule.
- The popover's leave line (seven forms); the meta line reordered to time ·
  location · source; the notifications line after the stale lines.
- Accessibility labels.

**Acceptance — tests:**

- §30 item 13's eight rows: state and string at each clock and width
  (`Leave 12:15` never truncated; degraded at 110; `Leave ≈12:15 · EPC-ILV`;
  an unavailable NEXT in Normal).
- Takeover at Thu 17:20 and not at 17:10.
- Leave now offers no `Re-offer`; imported NEXT offers `Done` · `Open`.
- The leave line's seven forms and colours; `semantic.now` only in Leave
  now; the reason short forms exact; `from where you are`.
- The meta line `13:00 – 14:30 · LAB_F5.12 · University timetable`; `17:30 –
  18:15 · Daily routine` without a location. Phase 2's meta-line tests are
  updated to the new order (the spec change, not a regression).
- The notifications line in `off` / `notAllowedYet`; none in `allowed`,
  `notAsked`, or with every rule off.
- §29's status item and popover labels, including the estimate label.

*Captures:* the §30 item 13 and 15 renders (offscreen,
`status-item-<row>-p3bt17.png`, `popover-<state>-p3bt17.png`), and the two
live captures of item 16.

### Task 18 — Capture the §30 review set and write `screenshots/3b/INDEX.md`

*Spec:* components §30, §30.1; §17.2 rules 1–6.

**Build:** recapture every §30 item (1–23) from one final build, review
mode, with the dataset, variant and mock arguments each item needs. Names
`<item-name>-p3b.png`; items 14 and 23 are
`notification-plan-travel.txt`.

**Acceptance:**

- Every frame obeys §17.2 rules 1–6. The edge check runs on all of them; no
  frame is a preview frame.
- INDEX.md maps each §30 item to its file(s), and names the dataset, the
  variant, `-KadenceNotifications`, `-KadenceGeocode` and `-KadenceLocation`
  values, the clock of each offscreen render, the launch time of the live
  captures, and the appearance of the Leave now render.
- Superseded `-p3bt<N>` frames are deleted once INDEX no longer maps to
  them.
- The full test run is green; `generate-tokens --check` is clean at 1.9.0.
- **Checks, in the task's report:**
  - no `UNUserNotificationCenter` outside `SystemNotificationCenter`; no
    `import MapKit` outside the two MapKit types; no `import CoreLocation`
    outside `SystemLocationSource` (grep);
  - the launch logs of every review launch show only mocks constructed;
  - no `late`, `missed`, `overdue` in any notification or status string in
    `Kadence/` (outside comments quoting the ban);
  - no log format string in `Kadence/` interpolates an address, a
    coordinate, a place name or a title (grep of the `travel` logger's call
    sites, listed in the report);
  - the build passes with `ENABLE_RESOURCE_ACCESS_LOCATION = NO` and without
    the time-sensitive entitlement (the project as it is today);
  - the real store's `stat` unchanged after every capture.

*Captures:* the full set.

**18 build tasks.** The model (1) and A42 (2) first; then routing without
any UI — the pure planner (3), the provider seam and cache (4), the queue
(5), recompute and refreshes (6), the current location (7); then
notifications — planner (8), centre (9), actions (10), sync paused (11);
the review data (12); the five UI tasks (13–17); the capture (18). The
MapKit provider sits behind `TravelTimeProvider` and is exercised only
through its mock and its pure mapping functions.

## Judgement calls made in this session

*Carried from the first version, still standing:* `KnownPlace` is a new
model, not BRIEF's `Place` (§28.1); timetable rooms map to the campus by
source kind (§23.2); the origin rule is a fixed two-hour gap with placeless
events transparent (§24.2); a missing time is a stored state (§24.3); one
notification per event (§27.2); four category rules (now five); absolute
times only (§27.3); the chain clamp (§27.3); protected windows hold, never
drop (§27.5); no late notifications in an ordinary pass (§27.6) — with one
new exception below; delivered notifications cleared once over (§27.6);
permission at the first thing to schedule (§27.8); "Leave now" and the
30-minute takeover (§26.1); the popover meta-line order (§26.2); no "should
have left" look on the band (§25.2); settings in the store (§28.1); the
`travel` dataset without a routine template (§30.1).

*New in the routing amendment:*

1. **The manual provider is removed, not kept as a hidden fallback.** A
   typed number would be exactly the guess Parsa does not want to maintain;
   the fallback is Apple Maps' own last answer, marked (§24.9, §24.10).
2. **Transit uses `calculateETA` with `arrivalDate`**, and one formula for
   every mode: `departAt = start − buffer − travel time`. MapKit gives
   transit ETAs but not transit routes; an ETA is all a leave-by needs
   (§23.3, §24.3).
3. **Cycling is out** — not in `MKDirectionsTransportType` on macOS 15; on
   macOS 26 it exists but was reported to come back as driving. The project's
   26.5 deployment target contradicts the brief; Parsa rules (G-095).
4. **A per-pair mode override is in, a per-event mode is out** (§23.3,
   G-094). The pair covers the weekly case (walking to the gym); the
   symmetric override keeps the old route row's shape in Settings.
5. **Addresses are confirmed by the user; the campus is not** (§23.5,
   §23.6). Home and user places are the user's text, so they confirm what
   MapKit found; the campus address is Kadence's own, accepted
   automatically only when the first result matches `Höchstädtplatz 6` and
   `1200`, otherwise confirmed like any place. No coordinate is
   hard-coded; review and tests use invented mock coordinates, never
   shipped.
6. **Lookups use `MKLocalSearch` (`.address`)**, biased to Vienna, behind
   `PlaceGeocoder` — it exists on macOS 15 and needs no location permission;
   `CLGeocoder` is deprecated on 26 and `MKGeocodingRequest` is 26-only.
7. **The cache key carries direction, day type and a 30-minute arrival
   slot** (§24.9). Transit is not symmetric; weekly lectures share keys, so
   a semester costs a few dozen requests and every future lecture still has
   a band (the first version's "no horizon" stands).
8. **Fresh for 14 days, kept for 28.** Old enough to survive a holiday week,
   young enough that a timetable change in Wiener Linien shows within two
   weeks; departure refreshes make the day's own times current anyway.
9. **Departure refreshes at T−3 h and T−45 min only** (§24.6) — the brief's
   example times; T−3 h catches a disruption before you plan the morning,
   T−45 min catches traffic and delays while the leave-by notification (5
   min before) is still ahead.
10. **A refresh that moves the leave-by into the past delivers it at once**
    (§27.6). The one exception to "no late notifications in an ordinary
    pass": traffic got worse, and late is better than never.
11. **The queue budget** — one in flight, 2 s apart, 20 per 10 minutes,
    150 a day, pause 10 → 60 minutes on throttling (§24.9). MapKit publishes
    no number; G-093 revisits it with real logs.
12. **Estimate vs unavailable** (§24.10): `noRoute` and `needsAddress` never
    fall back — transit at 03:00 is not the 08:00 time, and there is nothing
    to route from without an address. Offline, paused and failed use the
    last known time, marked `≈` / `about` / `estimate` — a character and a
    word, never a colour.
13. **N7 "travel unavailable" fires at `start − 60 min`** (§27.3). It names no
    travel time, so it guesses none; an hour is when you would check your
    route. It takes the leave-by slot, so it is replaced by N1 the moment a
    time arrives.
14. **Current location: the next departure only, at its T−45 refresh, only
    if more than 300 m from where the rule says you are** (§24.2.1). Default
    on, permission asked at that first need, never at launch. Within 300 m
    the rule origin keeps its name, so the copy stays `from Home`. Never
    cached, never stored, never logged; denied changes nothing visible
    outside Settings.
15. **N8 is sent only for background syncs** (§27.4): when the user ran the
    sync, the sheet or the source popover already shows the state.
16. **Time-sensitive for leave-by and N7, active for the rest** (§27.4);
    the degrade is the system's, plus one `.active` retry if `add` throws.
17. **Logs carry no place names**, not just no addresses (§24.11): a place
    name is the user's text and can be as identifying as an address.
18. **A42 is task 2**, early, because it is independent of everything else
    and touches the canvas the UI tasks later capture.

## For Parsa — decisions and Xcode steps that are yours

1. **The deployment target** (G-095): the brief says macOS 15+, the project
   says 26.5. The spec is written to macOS 15 (no cycling). Tell CA which is
   right; nothing in this slice depends on it.
2. **Xcode, at your convenience — no build task needs these, and every test
   passes without them** (G-096):
   - Target `Kadence` ▸ Signing & Capabilities ▸ **App Sandbox ▸ Hardware /
     App Data: Location** ✓ (sets `ENABLE_RESOURCE_ACCESS_LOCATION = YES`,
     the `com.apple.security.personal-information.location` entitlement).
   - Target `Kadence` ▸ Info (or Build Settings, since the Info.plist is
     generated): add **`NSLocationUsageDescription`** and
     **`NSLocationWhenInUseUsageDescription`** ("Privacy - Location Usage
     Description", "Privacy - Location When In Use Usage Description"), both:
     `Kadence uses your location only to work out how long the trip to your
     next event takes. It is sent to Apple Maps for that and is not stored.`
   - **+ Capability ▸ Time Sensitive Notifications**. Your commit db97278 is
     named for it but changed no project file, and the project has no
     `.entitlements` file — check that Xcode actually wrote one and that
     `CODE_SIGN_ENTITLEMENTS` points at it, then commit it.
   - Nothing else: Outgoing Connections (Client) is already on, and MapKit
     needs no Maps capability.
3. **Your Home address** — typed in Settings ▸ Travel once the slice is
   built; confirm what Apple Maps finds. Until then every leave-by says `Home
   has no address`.
