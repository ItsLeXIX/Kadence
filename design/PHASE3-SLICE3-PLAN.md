# Phase 3 — slice 3 plan: Moodle deadlines

Design agent, 2026-10-16. Written after slice 2 was accepted (`DECISIONS.md`
2026-10-16 "Phase 3 slice 2 accepted"). The source facts are MA's, verified
on Parsa's real feed on 16 Oct 2026 and redacted to
`fixtures/moodle-2026WS-redacted.ics`.

## Scope

This slice answers "what is due, and will I be told in time?" for Moodle.

- **Connect** a Moodle calendar export URL (Moodle 4.5, *Calendar ▸ Import
  or export calendars ▸ Export calendar ▸ All events · Recent and upcoming ▸
  Get calendar URL*). One HTTPS `GET`; no login, no header, no VPN.
  - **The URL is the secret.** Validated as pasted (https, the export path,
    `userid` and `authtoken` present, `recentupcoming`, `all`/`courses`)
    without ever being shown; kept only in a Keychain generic-password item;
    shown and logged as `moodle.technikum-wien.at/…`; never in the store,
    `UserDefaults`, a log, an error, a notification, a screenshot or the
    pasteboard (`components.md` §33).
  - Import preview like slice 1's; **`Replace URL…`** when Moodle makes a
    new one after a password change (§33.5).
  - `401`/`403` pause automatic sync (slice 1's rule); `404`, an HTML page
    and an empty calendar each have their own state and copy; the four
    "the URL stopped working" states send N8 once (§34.3, §40.7).
- **Items are imported events** (`importKind` `deadline` / `opening` /
  `notice`), not work items (§32): read-only, local Done, identity by
  `UID`, no co-teaching merge.
- **Reading the feed** (§35): TAB folding and the lone-TAB lines; iCal
  unescaping then HTML entities (`FK CS&amp\;AM` → `FK CS&AM`); kinds only
  from eight verified wordings (`is due`, `ist fällig.`, `closes`, `endet`,
  `Anmeldeende:`, `opens`, `beginnt`), the kind word removed from the
  displayed title and the raw title always in the inspector; course code
  from the shortname (`BIF-VZ-5-WS2026-SWQM-EN` → `SWQM`), matched to the
  timetable by text only.
- **Openings pair with their deadline** into one window (`16:10–17:47 REQEN ·
  F2`); unpaired openings and unrecognised items are shown on their own
  (§36, §37.2).
- **A moment is drawn in the all-day row** as the deadline pill, time first:
  `23:59 INNO3 · Sprint Review…`; Month chips; done and past states; no
  overdue look (§37).
- **Done** is Kadence's own mark, kept across syncs and when a deadline
  moves, with a line saying the time changed (§38).
- **Sync** (§34): hourly by default; change by content (`DTSTAMP` and
  `LAST-MODIFIED` excluded); deletion only on proof of absence inside the
  window the feed covers (`observedLookahead`); the past never rewritten;
  items that age out kept as history; an empty feed proven only after 12 h.
- **Menu bar** (§39): the `Due 23:59 · …` state when nothing timed is left
  today; DUE TODAY in the popover.
- **Deadline notifications** (§40, the deadline half of G-088): early (the
  day before at 18:00) and final (2 hours before), absolute copy, grouped by
  fire time, held by protected windows but never past the deadline, none
  for done items.
- **Clock changes** (§41): moments are instants; the early reminder is a
  wall-clock time on a calendar day; the final one a duration.
- **G-103** is fixed first (task 1).

**Not in this slice:** work items, time logging, the work item view (G-104,
G-111); the Moodle REST client and submission status (G-105); a grid marker
(G-106); bilingual halves (G-107); the morning summary (G-108); reminders for
openings and spans (G-112); the planner.

**No task needs a network, Moodle or a real URL to pass.** The feed is served
by `MockFeedTransport` / the `URLProtocol` stub from `moodle-mocks.md`; the
secret store, notification centre and store are the in-memory doubles in
every test and review launch (B45). The only URL in the repo is the mock's,
with the `SENTINEL…` token the leak tests search for.

## Spec sections — new and changed

| Where | What | § |
|---|---|---|
| `components.md` | Slice-3 intro and four governing rules | "Phase 3 — slice 3" |
| | Moodle items are imported `Event`s, not `WorkItem`s; **what a moment is excluded from** (grid, conflicts, NEXT, scroll, travel, §27's notifications, filters) | §32, §32.1 |
| | The source: the URL, validation V1–V11 and the parsed line, the Keychain generic-password item, where the URL may appear and three build obligations (redacted type, Foundation errors, no HTTP state), Replace, the `Source` values | §33 |
| | Fetch, answers, **states and exact copy**, Import vs sync, **proof window and `observedLookahead`**, `emptyFeed` after 12 h, hourly default, item hash with profile tag, the sync steps, the log line | §34 |
| | The `moodle` profile: unfolding, identity (no merge, duplicate UID), text (unescape, entities, `upstreamTitle`), **kinds**, spans, course code and category, mapping to the timetable | §35 |
| | Pairing openings with deadlines | §36 |
| | Drawing a moment: the pill (label, glyphs, truncation, sort, states, hover help, VoiceOver), which items are drawn, Month, the inspector's content | §37 |
| | Done: no Skip, kept across moves, `markedDoneDueAt` | §38 |
| | Menu bar `Due` state; the popover's Due NEXT and DUE TODAY | §39 |
| | Deadline notifications: the rule, eligibility, fire times and the quiet pull, grouping, **copy N9/N10**, identifiers, actions, catch-up; N8 for feeds; the morning summary deferred | §40 |
| | Clock changes for moments | §41 |
| | Data model: `Event`, `Source`, `NotificationRule` additions | §42 |
| | Review items 1–21, fixtures, datasets `moodle` / `moodleOnly`, the notification tables, required tests | §43 |
| | Amended in place (2026-10-16): §2.1 (three rows), §5, §10.1, §15.1, §18.1, §19.1, §27.1, §27.6, §27.7 | |
| `layouts.md` | Sidebar `Connect Moodle…` row and the Moodle row's context menu | §2.1 (amended) |
| | Settings ▸ Sources empty state and the `+` menu | §11 (amended) |
| | Settings ▸ Sources, a Moodle source | §15 |
| | The Moodle sheet: step 1, step 2 (exact sentences), Replace mode | §16 |
| | Inspector, a Moodle item | §17 |
| | Popover DUE TODAY | §18 |
| | Settings ▸ Notifications, the Deadlines rows | §19 |
| `interactions.md` | Connecting, Replace, syncing, removing (alert text), gestures on a moment, popover and notification actions | §16 |
| `moodle-mocks.md` | **New.** Every mock case, `feedChanged`'s edits, the expected results table | M1–M4 |
| `GAPS.md` | G-088 split; G-103 scheduled; G-104–G-113 opened | "2026-10-16 — Phase 3 slice 3" |

## Tokens — `tokens.json` 1.9.0 → **1.10.0** (updated 2026-10-16)

| Token | Value | Used by |
|---|---|---|
| `typography.allDayTime` | 11, regular, `subheadline`, `lineLimit` 1, **monospaced digits** | the pill's due time, `components.md` §37.1 |
| `size.popoverMaxDueRows` | **3** (integer leaf) | DUE TODAY, §39.2, `layouts.md` §18 |
| `size.inspectorDescriptionMaxLines` | **6** (integer leaf) | the inspector's collapsed description, `layouts.md` §17 |

**No colour added** (`$measured_1_10_0`): the time is `text.secondary` on the
source tint (declared, 5.27 / 5.61; done-blended 5.88 / 6.67; past-blended
5.65 / 6.28). 64 pairs. Both new sizes are in `integerLeaves`.

## DECISIONS.md — proposed entries

For Parsa to confirm and write; text in the design agent's final message.

1. **Moodle deadlines come from the calendar export URL; the URL is the
   secret.** §33.
2. **A Moodle item is an imported event, not a work item.** §32 (G-104).
3. **A moment is drawn in the all-day row, at its instant's local date and
   time, and nothing is added to it.** §37, §41.
4. **Kinds come from Moodle's own words only; the raw title is always
   reachable.** §35.3, §35.4 (G-109).
5. **Done is Kadence's mark, and a moved deadline keeps it.** §38 (amends
   2026-10-08 "Imported events are read-only except their status").
6. **A feed deletes only inside the window it covers, and an empty feed
   only after 12 hours.** §34.5.
7. **Deadline reminders: the day before at 18:00 and 2 hours before,
   absolute, held but never past the deadline.** §40.
8. **The menu bar shows a deadline only when nothing timed is left today.**
   §39.
9. **Slice 3 defaults, confirmed by Parsa.** G-113.

## BUILD TASK LIST for CA — dependency order

**Common rules for every task:**

- One task per session. Tests run with `-only-testing:KadenceTests`.
  Persistence tests use a real in-memory `ModelContainer`.
- **Injected clock and calendar**: no parser, planner, sync or notification
  pass reads `Date()`. Test zone Europe/Vienna; the fixture's absolute
  dates; `M` = Mon 2026-10-12.
- **No real services in tests or review**: `MoodleFeedSource` runs on
  `MockFeedTransport` or the stub; the real `URLSession` transport is
  constructed only by a normal launch (the factory's launch-kind table
  asserted, as B45). The real Keychain is touched only by a normal launch.
  **No task contacts Moodle.**
- **The URL never leaves its three places** (§33.4): every task that logs,
  stores, renders or reports asserts the sentinel `SENTINEL` and `4711`
  absent from its output.
- **No title, category, description, path or query in any log line**
  (§34.9).
- Never open, read or write the real store; record its `stat` before and
  after (STATUS §143).
- A UI task's captures go to `screenshots/3c/<name>-p3ct<N>.png`; task 15
  recaptures the set (§17.2 rule 2).
- `generate-tokens --check` clean at **1.10.0** from task 1 on.
- Baseline: **1113 tests pass** (STATUS §143). Every task ends green.

### Task 1 — G-103; data model; tokens 1.10.0; built-ins

*Spec:* GAPS G-103; components §42, §27.1 (amended), §33.6; tokens 1.10.0.

**Build:**

- **G-103 first**: `TravelDataset.seedStaleCache` uses
  `WallClock.moment(minuteOfDay: 18 * 60, on: …)`; §31.5 T12's scan widened
  to catch a day start chained across lines.
- `Event`: `momentWording`, `upstreamTitle`, `courseCategory`,
  `markedDoneDueAt`; `importKind` accepts `deadline` / `opening` /
  `notice`. `EventStore`'s delete snapshot carries `markedDoneDueAt`.
- `Source`: `connection` `icsFeed`, `feedProfile`, `observedLookahead`,
  `emptySince`; `state` raw values `feedNotFound`, `urlMissing`.
- `NotificationRule`: `aheadDays`, `aheadMinuteOfDay`, `leadEnabled`; the
  sixth rule `deadline` (on, 120, 1, 1080, true) added idempotently.
- Regenerate `Tokens.swift` at 1.10.0.
- DEVIATIONS.md: heading `## Phase 3 slice 3 — Moodle deadlines
  (2026-10-16)`.

**Acceptance — tests:**

- A slice-2 store opens; every event, source and rule reads back unchanged
  with the new fields at their defaults; one launch adds the sixth rule, a
  second adds nothing.
- T12 finds a deliberately chained `startOfDay(…)` / `.addingTimeInterval(18
  * 3600)` in a test-only source string; `seedStaleCache` on `M` = Mon 9 Nov
  2026 gives `25 Oct 18:00 CET`.
- Delete a Moodle event with `markedDoneDueAt`, undo → it is back.
- `Tokens.Typography.allDayTime` exists with monospaced digits;
  `Tokens.Size.popoverMaxDueRows == 3` and `inspectorDescriptionMaxLines ==
  6` as `Int`.
- All 1113 tests still pass.

*Captures:* none.

### Task 2 — The URL: validation, the redacted type, the Keychain item

*Spec:* components §33.1–§33.5.

**Build:** `MoodleFeedURL` (parse, normalise `webcal`, V1–V10 as a pure
function returning the message or the parsed line; redacted `description`,
`debugDescription`, mirror); the secret store's generic-password kind (the
real Keychain item of §33.3 behind the existing protocol; the in-memory
double); read / write / update-in-place / delete by `Source.id`.

**Acceptance — tests:**

- V1–V11 row by row with exact messages and the two parsed-line forms; order
  of rows (a `http://` page URL gets V3, not V5); `webcal://` → `https`;
  query order and extra parameters irrelevant; host lower-cased.
- V9 against two stored sources (one unreadable → skipped); V10 in Replace.
- `"\(url)"`, `String(describing:)`, `debugDescription` and `dump` →
  `moodle.technikum-wien.at/…`; only the transport accessor yields the raw
  string (a source scan lists its call sites: one).
- The real Keychain wrapper's query dictionary has §33.3's attributes (built
  and asserted without calling Security).

*Captures:* none.

### Task 3 — The `moodle` profile (pure)

*Spec:* components §35 (incl. §35.7's table), §34.7.

**Build:** unfolding on bytes; text unescaping and entity decoding;
`upstreamTitle`, `title`, `importKind`, `momentWording`; course code, term
and category; identity and duplicate UIDs; spans and all-day; problems; the
item hash with the profile tag; the feed hash.

**Acceptance — tests** (the fixture and `moodle-mocks.md` M1 bodies):

- The fixture parses to 29 items whose local start, `importKind`,
  `momentWording`, course code or category and `title` equal §35.7's table
  row for row (9 due, 15 closes, 1 registrationEnds, 4 opens); `900005`'s title is `Sprint Review Protocol for
  Sprint 1 (till Tuesday 23:59 in T0 + 2)` (the fold after `2) ` kept as one
  space); `900013`'s category is `FK CS&AM - Study Trips & International
  Initiatives`; `900028`'s title keeps every emoji.
- The lone-TAB lines produce no property and no stray character;
  `feedLF` gives byte-equal items; a BOM is skipped.
- §35.4's table row by row, including `Fooopens` → notice and `is due` alone
  → notice.
- Course code: the 10 codes and 2 categories; `/174462` stripped for the
  shortname, kept in `courseCategory`.
- `feedDuplicateUID`, `feedInvalidUTF8`, `feedBroken`: the problems and
  sentences exact.
- `feedNotice`: `900040` notice moment; `900041` a span (timed, notice).
- Hashes: `feedStampOnly` → equal feed hash; any field of §34.7 changed →
  that item's hash changes; changing the profile tag changes every hash.

*Captures:* none.

### Task 4 — Pairing and the presentation model (pure)

*Spec:* components §36, §37.1–§37.4 (strings), §35.5 (mapping), §39
(selection rules).

**Build:** `MoodlePairing`; the label (time / window, `{code} · {title}`),
the drop-the-time rule's inputs, the sort, hover help, VoiceOver, the
inspector's row values, the timetable mapping; the menu-bar candidate
rules (Due NEXT, DUE TODAY rows).

**Acceptance — tests:**

- §36's four pairs and two standalone deadlines from the fixture;
  `feedChanged`'s `900031` unpaired; a re-sync that moves an opening
  re-pairs; ties by externalID.
- Labels: `23:59 INNO3 · Sprint Review Protocol…`, `16:10–17:47 REQEN · F2`,
  `23:50 RW · Mitarbeit Lektion 5` (opening on another day → no window),
  `23:59 VERBINDLICHE Anmeldung …` (no code).
- Drop-the-time: at a text width under 44pt the time is dropped.
- Sort: Tue 3 Nov → `Lessons Learned Lektion 5`, `Mitarbeit Lektion 5` (23:50),
  then `Sprint Review…` (23:59).
- Hover help and VoiceOver: every §37.1 example exact.
- Inspector values for §43 item 15's five items exact; `In timetable`
  against a store holding `travel`'s timetable codes.
- Menu bar: at Tue 13 Oct 20:00 (`moodleOnly`) Due NEXT `900005`, no DUE
  TODAY; at Tue 3 Nov 20:00 Due NEXT `900016`, DUE TODAY `900015`, `900017`;
  with a timed event at 21:00 the status item is Normal and DUE TODAY holds
  all three; done items and passed ones excluded; never an opening or a
  notice.

*Captures:* none.

### Task 5 — The feed source and its transport

*Spec:* components §34.1–§34.3, §33.4 (obligations 2 and 3); `interactions.md`
§16.1 ("The URL on the wire"); `moodle-mocks.md` M3.

**Build:** `MoodleFeedSource: ScheduleSource` over a feed transport
(ephemeral session, no cache, no cookies, no credential storage, redirect
delegate returns `nil`, host check before every send); the answer table;
error mapping by code only; the 20 MB cap; `MockFeedTransport`; the stub's
real-redirect reply (as slice 1's).

**Acceptance — tests:**

- Every M3 case → its state, exactly as M4's "Other cases" table.
- `feedRedirectCrossHost`: the stub records **no** request to
  `login.example.invalid`; the control session that allows redirects does
  (the test of the test). `feedRedirectHTTP`: no `http` request.
  `feedRedirectSameHost`: 2 requests, both to the host. `feedRedirectTwice`:
  `redirected`.
- No recorded request carries `Authorization` or `Cookie`.
- A `URLError` whose `failingURL` and `NSErrorFailingURLStringKey` hold the
  mock URL, for each mapped code: the state is right and the captured log has
  no `SENTINEL`, `4711` or `authtoken`.
- The factory: test-host and review launches construct only the mock.

*Captures:* none.

### Task 6 — Import and sync: windows, proof, empty feed, pause, log

*Spec:* components §34.4–§34.9; §20.9; `interactions.md` §16.3;
`moodle-mocks.md` M4.

**Build:** the Import (every item, nothing deleted, `observedLookahead`
set); the sync planner/applier (today onward, the proof window, the guards,
`emptySince` and the 12 h proof, last-change counts in items); the 401/403
pause and its clearing; the hourly default and scheduling through the
existing per-source scheduler; the connect / import / sync log lines; state
transitions reported to the notification scheduler (task 8 consumes them).

**Acceptance — tests:**

- M4's sync table row by row (Import at Fri 16 Oct 13:07, sync
  `feedChanged` at 14:07), including `900029` kept, `900026` deleted,
  `900008` updated in place with the same `Event.id`, still done; the
  last-change line exact; a second sync writes nothing.
- `feedOK` twice, `feedStampOnly`, `feedLF` → nothing written.
- `feedAged` at Thu 22 Oct → nothing deleted; history keeps `900004`'s done.
- `feedEmpty`: first → `emptyFeed`, body with `{until}` exact; at +11 h 59 min
  nothing; at +12 h deletions in the window only, history kept; a fetch with
  items in between clears `emptySince`.
- `feed401` / `feed403` → paused; the next interval sends nothing; `Sync
  Now` sends one; Replace's `Save` clears the pause.
- `urlMissing` → no request.
- A sync during a conflict preview is held (§20.9).
- Log lines exact for `feedOK`'s connect and Import and `feedChanged`'s sync;
  none contains a title or a category.
- Leak scan of the store and the log after every M4 case.

*Captures:* none.

### Task 7 — Done on deadlines

*Spec:* components §38; `interactions.md` §16.5.

**Build:** `Mark Done` / `Mark Not Done` for deadlines with
`markedDoneDueAt`; refusals for Skip on any Moodle item and Done on
openings and notices (§13.4's pair); the moved-after-done condition.

**Acceptance — tests:**

- Mark Done sets `.done` and `markedDoneDueAt = start`; Not done clears
  both; each one undo step with its name.
- `feedChanged` E1 on a done `900008` → still done, the condition true; Mark
  Not Done then Done → false.
- `⌥⌘↩` on a deadline / opening / notice → refused, no write, no undo step;
  `⌘↩` on an opening → refused.
- Done on a past deadline allowed.

*Captures:* none.

### Task 8 — Deadline notifications

*Spec:* components §40, §41 (reminders); §27 (amended); `moodle-mocks.md`
(N8 states).

**Build:** the deadline planner (early via `WallClock` and calendar days,
final as a duration, the quiet pull, collapse, grouping, N9/N10 copy,
identifiers, `.active`); the applier's `due.` prefix; categories
`kadence.deadline` / `kadence.deadlines`; actions; catch-up; N8 for the four
feed states from background syncs.

**Acceptance — tests:**

- §43.2's three tables at Mon 12 Oct, Mon 2 Nov and Sat 31 Oct 06:00:
  identifiers, fire dates, titles, bodies, categories, levels, exactly.
- The rule variants, the catch-up cases and the actions of §43.2, exactly.
- C3 and C4 (§43.3); §40.3's three examples.
- A group shrinking to one → the group removed, the single added; growing →
  the reverse; marking a member done replaces the group's body.
- Done, deleted, notice → removed; delivered ones of a passed deadline
  cleared.
- N8: `feed401`, `feed403`, `feed404`, `feedHTML` from a background sync →
  one `sync.` each with the §40.7 body; from `Sync Now` → none; leaving the
  state → removed.
- No Kadence-written title or body contains `late`, `missed`, `overdue`, a
  count of undone items, `!` outside `{title}`, `today`, `tomorrow` or `in `
  + a number.

*Captures:* none.

### Task 9 — Review mode: template, datasets, mock cases, the plan dump

*Spec:* components §43.1, §43.2; §22.1's review rules.

**Build:** `Fixtures/ICS/moodle-review.ics.template` from the fixture;
datasets `moodle` and `moodleOnly`; `-KadenceFeed <case>`; the plan dump
`notification-plan-moodle.txt` at §43.2's clocks from the real planner.

**Acceptance — tests:**

- The template rendered with `M` = 2026-10-12 equals the fixture except
  `DTSTAMP`; with `M` = 2026-10-19 every item is 7 days later at the same
  local time (across 25 Oct).
- `moodle`: `travel`'s legs, conflicts and notification plan unchanged; the
  Moodle source `teal`, 29 items, `900004` done.
- `moodleOnly`: built-ins, Sleep, the Moodle source, nothing else.
- The dump equals §43.2's tables.
- Review launches construct no real transport, Keychain or notification
  centre.

*Captures:* none.

### Task 10 — Connecting: the sheet, Settings ▸ Sources, the sidebar

*Spec:* layouts §2.1 (amended), §11 (amended), §15, §16; components §33,
§34.3; `interactions.md` §16.1, §16.2, §16.4.

**Build:** the Moodle sheet's step 1 (SecureField, live validation, the
parsed line, connecting, failures), step 2 (every sentence), Replace mode;
Settings' `+` menu, empty state, the Moodle detail; the sidebar's `Connect
Moodle…` row and context menu; File ▸ Connect Moodle…; the remove alert.

**Acceptance — tests:**

- Validation messages and the parsed line in the view model, exact; `Connect`
  enabled only on V11.
- Step 2 for `feedOK` (Mon 12 Oct 06:00) and `feedNotice`: every sentence
  exact; the empty form for `feedEmpty`.
- `Import` write order; a scripted Keychain failure writes nothing, with the
  exact copy. Cancel at each step writes nothing.
- Replace: V10; `Save` updates the item in place, keeps every `Event.id`,
  clears the pause; a Keychain failure keeps the old URL.
- The detail shows `moodle.technikum-wien.at/…`, not selectable; `Every
  hour`; no account or password row.
- The remove alert's text exact; removal deletes items, source and Keychain
  item and the source's `due.`/`sync.` notifications.
- Accessibility: the URL field's value is `filled` / `empty`, never the URL.
- Leak scan of every rendered string in the sheet and Settings.

*Captures:* §43 items 1–8 as `-p3ct10` frames.

### Task 11 — The canvas: pills, chips, states

*Spec:* components §32.1, §37.1–§37.3, §2.1 (amended), §5 (amended), §6;
layouts §3.2.

**Build:** the moment pill (three kinds), its label and truncation, the sort,
done and past, hover help, VoiceOver; Month chips; the filters (a moment
counts as all-day for `All-day only` / `Timed only`; `Hide done` applies);
no paired opening drawn; spans as `.fixedTimed`.

**Acceptance — tests:**

- Week 12–18 Oct / 19–25 Oct / 2–8 Nov in dataset `moodle`: which pills on
  which day, in which order, with which label (§43 items 9–11); no pill for
  Mon 12 Oct's openings.
- Style: deadline rail and `flag.fill`; opening and notice without rail;
  done blend and `checkmark.circle.fill`; past blend; never conflicted.
- Month Oct/Nov/Dec: chips without time, sorted.
- §32.1's table row by row: a moment is never laid out on the grid, never
  in conflicts, NEXT, REST OF TODAY or the default scroll, never gets a
  `start.` notification, and is not counted in the Day header; a span is
  and does all of these except the notification.
- Filters as stated.

*Captures:* §43 items 9–14 as `-p3ct11` frames, light and dark for item 9.

### Task 12 — The inspector

*Spec:* layouts §17; components §37.4, §38.

**Build:** every row of layouts §17, the Status row with its two lines,
the collapsed description with `Show more` / `Show less`, links.

**Acceptance — tests:**

- §43 item 15's five items row by row, exact; no `Place` / `Leave by` row.
- Status: `Mark Done` ↔ `Mark Not Done`; the moved line after `feedChanged`;
  no Skip button.
- Description: 6 lines collapsed for `900004`, expanded on activation, reset
  on reselection; URLs are links; VoiceOver value is the whole text.

*Captures:* §43 items 15–17 as `-p3ct12` frames.

### Task 13 — The menu bar: Due, DUE TODAY

*Spec:* components §39; layouts §18; `interactions.md` §16.6.

**Build:** the Due state (unit, degrade, template rendering), the popover's
Due NEXT and DUE TODAY, accessibility labels.

**Acceptance — tests:**

- Status item at Tue 13 Oct 20:00 (`moodleOnly`) at 180pt and 110pt; at Tue
  13 Oct 23:59 → `Nothing left today`; marking `900005` done at 20:00 →
  `Nothing left today`.
- Popover at Tue 3 Nov 20:00: NEXT and DUE TODAY rows exact; `Done` replaces
  NEXT with `900015`; `+N more` beyond 3.
- With a timed item left, NEXT is the timed item and DUE TODAY lists the
  deadlines.
- Accessibility labels exact.

*Captures:* §43 item 18 (offscreen, `status-item-due-<width>-p3ct13.png`,
`popover-due-<clock>-p3ct13.png`).

### Task 14 — Settings ▸ Notifications: the Deadlines rows

*Spec:* layouts §19; components §40.1.

**Build:** the row group, the three pop-ups, disabling rules, the footer
sentence, VoiceOver.

**Acceptance — tests:**

- Pop-up items in order; each choice writes `aheadDays` /
  `aheadMinuteOfDay` / `leadMinutes` / `leadEnabled` and triggers a pass.
- `Off` disables the time pop-up and keeps its value; the rule off disables
  all three.
- VoiceOver labels and values exact.

*Captures:* §43 item 19.

### Task 15 — Capture the §43 set and write `screenshots/3c/INDEX.md`

*Spec:* components §43; §17.2 rules 1–6.

**Build:** recapture every §43 item from one final build; item 20 as
`notification-plan-moodle.txt`.

**Acceptance:**

- Every frame obeys §17.2; the edge check runs on all of them.
- INDEX.md maps each item to its file(s) with dataset, `-KadenceFeed` case,
  clock and appearance.
- Full test run green; `generate-tokens --check` clean at 1.10.0.
- **Checks in the report:** a repository grep for `SENTINEL` lists only the
  mock URL's definitions in fixtures and tests; no file under `Kadence/`
  logs a `MoodleFeedURL`'s raw accessor or a `URLError`'s description; no
  `late`, `missed`, `overdue` in any new string; the real store's `stat`
  unchanged; no review launch constructed a real transport, Keychain or
  notification centre.

*Captures:* the full set.

**15 build tasks.** The model and G-103 (1); the URL (2), the profile (3)
and the presentation model (4), all pure or doubled; the transport (5) and
the sync (6); done (7) and notifications (8); review data (9); five UI tasks
(10–14); the capture (15).

## Judgement calls made in this session

1. **Events, not work items** (§32). Upstream facts and user-owned effort
   live in different records; a sync must never be able to delete time logs.
2. **The all-day row, not the grid** (§37.1). It is pinned; a 23:59 deadline
   on the grid would be off-screen whenever it matters.
3. **Time first in the pill, dropped before the title in a narrow column**
   (§37.1), using the existing 44pt readable-title width.
4. **The course code leads the label** (`REQEN · F2`). `F2` alone is
   meaningless; CIS blocks are titled by code, so the two read alike.
5. **No course hue** (§35.5). §1 gives hue to source only.
6. **Paired openings fold into their deadline; unpaired ones show** (§36,
   §37.2). An opening alone can be the useful fact (a registration that
   opens).
7. **Unrecognised items are shown, never reminded, and said so** (§35.4).
   Inventing "deadline" would be a guess; hiding them would be silent.
8. **Bilingual titles stay whole** (§35.3, G-107).
9. **No Skip on deadlines; done survives a move** (§38). Done means handed
   in; an extension doesn't undo a submission. The line makes it visible.
10. **Hourly polling** (§34.6). Deadlines move on days; the earliest default
    reminder is two hours before.
11. **The proof window from a never-shrinking `observedLookahead` minus a
    day** (§34.5). Wrongly deleting a far item heals itself when the window
    reaches it; wrongly keeping a removed deadline would remind of something
    that doesn't exist.
12. **An empty feed is proof only 12 hours after the first** (§34.5): a
    break really empties Moodle; one bad response must not.
13. **401/403 pause** as slice 1, though nothing can be locked (Parsa's
    request): a refused URL won't recover by itself.
14. **N8 also for `feedNotFound` and `notACalendar`** (§40.7): for a URL
    source each means "nothing will arrive until you replace it".
15. **A generic-password Keychain item keyed by `Source.id`** (§33.3): there
    is no account, and dedupe is by host + `userid` read from the items.
16. **`webcal://` accepted, `http://` refused, `recentupcoming` required**
    (§33.2): the deletion rule depends on a rolling window.
17. **Reminders: the day before at 18:00 and 2 hours before** (§40.1),
    Parsa's suggestion; BRIEF's 3 days / 1 day / 3 hours are all reachable.
    **Pulled before a protected window rather than held past the deadline**
    (§40.3) — the one place the quiet rule moves a notification earlier.
18. **Grouped by fire time and due date** (§40.4), so the two RW items
    closing together are one message; `Done` only on singles.
19. **Absolute dates in deadline copy** (`Tue 13 Oct 23:59`, never
    `tomorrow`): a notification read the next morning must still be true.
20. **The menu bar's Due state only when nothing timed is left** (§39). The
    status item stays "where to go next"; the evening before a 23:59
    deadline is when it is the next thing.
21. **The URL as a redacted type, and Foundation errors never logged** (§33.4)
    — `URLError` carries the URL in its `userInfo`, which a generic error
    log would leak.

## For Parsa — decisions that are yours

1. **The order** (G-104): BRIEF says work items before imports; this slice
   imports deadlines and leaves work items + time logging to the next slice.
2. **The defaults** (G-113): poll every hour; early reminder the day before at
   18:00; final reminder 2 hours before; openings folded into their deadline,
   unpaired ones shown; unrecognised items shown but not reminded; done kept
   when a deadline moves; the `Due` state in the menu bar; the course code
   first in labels; bilingual titles whole; `emptyFeed` proof after 12 h;
   `feedNotFound` and `notACalendar` notified once.
3. **The first real connection** — yours, after the build: in Moodle,
   *Calendar ▸ Import or export calendars ▸ Export calendar ▸ All events ·
   Recent and upcoming ▸ Get calendar URL*, paste it into *Settings ▸
   Sources ▸ + ▸ Connect Moodle…*. Then read one `sync` line (`log show
   --last 1h --info --predicate 'subsystem == "XIX.Kadence" AND category ==
   "sync"'`) and note the `lookahead` value (G-110). No agent may do this.
4. **When your FH password next changes** (G-110): note what Kadence shows
   for the old URL before you replace it.
5. **Moodle wordings** (G-109): tell DA about any item shown as a notice that
   is really a deadline.
