# Phase 3 — slice 1 plan: the university timetable from the CIS CalDAV account

Design agent, 2026-10-08. Written after Phase 2 was accepted
(`PHASE2-REVIEW.md`, "Acceptance — 2026-10-08").

This plan has been rewritten twice the same day:

- The **subscription amendment** replaced the WebDAV share. The share is
  IP-restricted to the FH network.
- This **CalDAV amendment** replaces the subscription link. CIS has no such
  link: Apple Calendar holds the timetable as a **CalDAV account** (server,
  username, password), on SabreDAV at
  `https://cis.technikum-wien.at/webdav/lvplan.php/`.

`DECISIONS.md`'s 2026-10-08 entries were rewritten for CalDAV by Parsa and are
authoritative. Nothing had been built from either earlier version, so **this
plan replaces both whole**.

## Scope

This slice connects **one** data source kind: a **CalDAV account**.

- **Connect.** The user enters server (prefilled `cis.technikum-wien.at`),
  username and password.
  - Discovery runs as one visible step: `/.well-known/caldav` → principal →
    calendar home → calendars.
  - Then a calendar step. **One** calendar with events (the real case,
    `LVPlan`) is shown as a single confirmed row. Several are shown as a
    checklist, all checked. The calendar home, the outbox and non-event
    collections are never offered.
  - Then **Import**. Nothing (Keychain item, `Source`, events) is saved before
    it.
- **Fetch.** Each poll sends one `REPORT calendar-query` per selected calendar
  (CIS: **one request**), with a time-range that starts today. The Import's
  time-range starts a year back.
  - If REPORT is refused, the fallback runs: `PROPFIND` → `calendar-multiget`,
    and if that is refused too, `GET` per object.
  - Each fallback is silent unless it fails, and is logged.
  - The cap is 300 requests per sync.
- **Change by content.** CIS has no sync-token, and its getctag is the request
  time. So a normalised **hash per merged event and for the whole feed** decides
  what changed. Unchanged content writes nothing. ctag and ETags are diagnostics
  only.
- **Discovery is cached.** It re-runs only when the calendar answers `404` or
  moves.
- **Unchanged from the subscription version:**
  - CIS profile parsing (course code as title, lecturers, group, room, exam,
    online)
  - the co-teaching merge
  - read-only imported events with local done/skipped
  - Import vs sync windows (the Import writes the whole semester once; syncs
    write today onward, delete only on proof of absence, never write the past)
  - the 401/403 pause
  - sync state with the source
  - `.eventAllDay`, and the done label on solid fills
  - the defaults (30 minutes; the Mac's current time zone; an empty real store)
- **The password is the only secret.** It is stored in one Keychain
  internet-password item. It is sent only over HTTPS, to that host, in answer
  to its 401. Never across hosts, never logged. `user01 @
  cis.technikum-wien.at` is shown freely.

**Not in this slice:**

- the WebDAV share (G-065), and any subscription link
- Moodle, work items, time logging
- travel time / MapKit / leave-by
- notifications, mail triage, the planner
- friendly course names (G-064)

**No build task, test, script or capture contacts the university server, holds
a real password, or needs network access.** Every HTTP exchange goes through an
injected transport serving `design/caldav-mocks.md`.

## Before task 1 — housekeeping (Phase 2 leftovers, not Phase 3 work)

Unchanged.

- **H1. `Scripts/check-resync-escape.sh`'s matcher.** It reports FAIL after ⎋
  although the focused element is `AXButton "Re-sync"` (observed live
  2026-10-07, `AppleKeyboardUIMode` 2). Fix the comparison so that element
  matches, then re-run with keyboard navigation on. PASS expected. Script-only.
- **H2. `Scripts/check-frame-edges.py` implements `components.md` §17.2 rule 6**
  (the preview-border exemption: three conditions, no per-file allow-list).
  Acceptance:
  - `template-conflict-panel-p2c.png` passes.
  - A synthetic frame with a one-edge accent line in the band still fails.
  - A synthetic preview frame whose rectangle is missing its inner side fails.

## Spec sections — what changed in the CalDAV amendment

| File | § | What | Status |
|---|---|---|---|
| components.md | Phase 3 header | Scope: a CalDAV account. **The password is the only secret**; server, username, hrefs, ctags and ETags are not | rewritten |
| components.md | §2.1, §5.1, §6 | Exam glyph, `.eventAllDay`, `cancelled`, done on solid fills | unchanged |
| components.md | §18 | Imported events: read-only, local status, exam glyph, online, menu bar | unchanged |
| components.md | §19.0 | **One kind: the CalDAV account**. Why not the WebDAV share (IP-restricted, G-065) and why no subscription link | rewritten |
| components.md | §19.1 | **States and exact copy, 18 states.** New: `forbidden` copy, `noCalDAV`, `noCalendars`, `calendarMissing`, `fetchFailed`, `passwordMissing`; `notACalendar` and `redirected` reworded. Gone: `signInRequired`, `notFound`, `secretMissing`. Primary actions `Update Password…`, `Edit Account…`, `Choose Calendar…` | rewritten |
| components.md | §19.2, §19.3 | Examples: `Access refused`, `Edit Account…`. The last-change line is unchanged | amended |
| components.md | §19.4, §19.5 | Stale line, time forms | unchanged |
| components.md | §20 intro, §20.1 | Data from `REPORT` with the **Import window** / **sync window**. **Deselecting a calendar** deletes the events only it contributed, history included, decided by content | amended |
| components.md | §20.2 | **CalDAV hrefs and ETags are not identity.** The merge spans calendars. Content key and co-teaching merge unchanged | amended |
| components.md | §20.3–§20.6, §20.9, §20.10 | Time zones, all-day, recurrence, cancelled, conflicts, moved lectures | unchanged |
| components.md | §20.7, §20.7.1 | XML turns CRLF into LF: both must agree. The file-name note is gone | amended |
| components.md | §20.8 | **§20.8.1 discovery** (D1–D4, which responses are calendars, cache and re-discovery), **§20.8.2 fetch** (windows, `REPORT` body, **fallback chain F0–F2**, **request cap 300**, `get`-mode 6 h floor, size limits, not-a-calendar), **§20.8.3 one sync**, **§20.8.4 change by content** (event hash, feed hash, diagnostics log line), guards (all calendars read in full) | rewritten |
| components.md | §21 | **`Source` per DECISIONS "Sources become records"**: `serverURL`, `username`, `principalHref`, `calendarHomeHref`, `calendars`, `capabilities`, `feedHash` … Never the password. **No `SourceFile`.** `Event` additions unchanged. **Keychain internet-password item** (§21.4). `ScheduleSource.fetch(windowStart:)` | rewritten |
| components.md | §22, §22.1 | **21** review items (5 = single confirmed calendar row, 6 = checklist, 21 = `calendarMissing`). The real export as a `REPORT` (`reportCIS`). The review template served as a `REPORT`. `reportChanged`. The mocked-case table | rewritten |
| **caldav-mocks.md** | all | **New.** Exact requests and responses: D1–D4 in the real shapes with `user01`, F0/F1/F2, every case, the per-test assertions | new |
| layouts.md | §2.1 | Context menu note (`Edit Source…` → edit mode) | amended |
| layouts.md | §6.1 | Example state title `Access refused` | amended |
| layouts.md | §11 | Settings ▸ Sources: `Account` `user01 @ cis.technikum-wien.at` + `Edit Account…`, `Calendar(s)`. No password row | rewritten |
| layouts.md | §12 | Connect sheet: step 1 Server / Username / Password, validation (incl. the WebDAV share and a duplicate account), one connecting step, failure table. **Step 2: single confirmed row or checklist**, range and sentences, Import. Edit mode with re-discovery and the deselection sentence | rewritten |
| interactions.md | §2 | `⌘R` Sync Now | unchanged |
| interactions.md | §13 | §13.1 connecting and **the account on the wire** (HTTPS only, password only after the host's 401, redirects, hrefs, sequential). §13.2 removal copy (password, not link). §13.3 what pauses, timeouts, `get`-mode floor | amended |
| GAPS.md | G-065, G-067, **G-068** | Share IP-restricted; G-067 ruled (no ghost); **G-068 opened**: REPORT/time-range, ETag stability, REPORT duration at the first real connection | new section |

## Tokens — `tokens.json` 1.5.0 → **1.6.0** (phase 3, updated 2026-10-08)

1.5.0 was never built from. 1.6.0 is what task 1 generates.

| Token | Value | Used by | Change |
|---|---|---|---|
| `size.statusSlotWidth` | 16 | components §19.2, layouts §2.1, §11 | 1.4.0 |
| `size.sourcePopoverWidth` | 280 | components §19.3 | 1.4.0 |
| `size.settingsWindowWidth` / `Height` | 640 / 440 | layouts §11 | 1.4.0 |
| `size.settingsSourceListWidth` | 200 | layouts §11 | 1.4.0 |
| `size.connectSheetWidth` | 440 | layouts §12 | 1.4.0 |
| `size.inspectorLecturersMaxRows` | 4 (integer leaf) | layouts §6.1 | 1.5.0 |
| `size.connectCalendarRowHeight` | **24** | layouts §12.2: the confirmed calendar row and checklist rows | **new 1.6.0** |
| `size.connectCalendarListMaxHeight` | **144** (six rows, then scroll) | layouts §12.2 checklist | **new 1.6.0** |
| `color.interactive.link` | light `#0A60E0`, dark `#4C9BFF` | layouts §6.1 | 1.5.0 |
| `typography.sourceStatusTitle` | 13 semibold | components §19.3, layouts §11, §12.1 | 1.4.0 |
| `typography.popoverRefusalRow` | note extended | components §18.3, §19.4 | 1.4.0 |
| contrast pairs | **63, unchanged** (no colour added) | — | — |

Glyphs (not tokens):

- `xmark.circle` (cancelled)
- `exclamationmark.arrow.triangle.2.circlepath` (source status, chrome)
- `link` (Settings tab)
- `graduationcap.fill` (timed imported exams)
- **`checkmark`** (the confirmed calendar row, chrome, `text.secondary`): new
  in this amendment, and in neither §10.1 vocabulary

## DECISIONS.md

**No new entries are proposed.** The subscription version's six proposals are
withdrawn. Every one was superseded by Parsa's CalDAV rewrite of the 2026-10-08
entries, and the spec now follows those entries as written. Three readings are
recorded here so they can be checked, but none of them conflicts with an entry:

- **"Discovery is … re-run only when the calendar URL answers 404 or moves"**
  (Change is detected by content). This is read as applying to **automatic
  syncs**. Edit mode's `Connect` also discovers, because the user may have
  changed server or username, or wants to choose calendars. That is an explicit
  act, like the first `Connect`.
- **"Sent only … in answer to its 401 challenge"** (The timetable is a CalDAV
  account). Once the host has challenged within one connect or sync, later
  requests of that same sync may carry the credential for the same protection
  space. Every sync starts without it, in a fresh session. The alternative
  doubles every request to the university server.
- **"Deselecting a calendar … does delete, history included"** (The Import
  writes the semester once). `Event` has no calendar field ("Sources become
  records" fixes its additions). So a deselection deletes the events **absent
  from a full Import-window read of the calendars that stay**. A past lecture
  that had already vanished from a kept calendar goes too. That is the user's
  act, and step 2 counts it before `Save`.

## BUILD TASK LIST for CA — dependency order

**Common rules for every task:**

- Each task is one session.
- Tests run with `-only-testing:KadenceTests`.
- Persistence tests use a real in-memory `ModelContainer` (DECISIONS
  2026-09-10).
- **No task needs a real server, a real password or network access to pass.**
  - HTTP goes through an injected `HTTPTransport`: a `URLProtocol` stub in
    tests, `MockCalDAVTransport` in review, both serving `caldav-mocks.md`.
  - Passwords go through an injected `SecretStore`.
  - The only passwords in the repo are the **sentinel** `S3ntinel-pw-⚠` (tests
    only) and the **review password** `review-only-not-a-password` (review
    mode, in-memory only).
  - The only username is `user01`.
- The test clock is 2026-10-08 10:00 Europe/Vienna unless a task says otherwise.
- A capture from a UI task goes to `screenshots/3/<name>-p3t<N>.png`. Task 17
  recaptures the whole set from the final build (§17.2 rule 2).
- `generate-tokens --check` is clean at **1.6.0** from task 1 on.

### Task 1 — Data model: `Source`, `Event` additions; tokens 1.6.0

*Spec:* components §21.1–§21.3, §19.1 (state names).

**Build:**

- `Source` `@Model`, enum fields as raw strings: `connection` `local`/`caldav`.
  Codable JSON fields `calendars: [SourceCalendar]`, `capabilities:
  SourceCapabilities`, `problems: [ImportProblem]`.
- **No `SourceFile`**, and no href/ETag/ctag field anywhere.
- `Event` gains `isCancelled`, `importedDescription`, `lecturers: [String]`,
  `courseCode`, `group`, `isOnline`, `importKind` (raw, default `lecture`) and
  `link`. Each has a default, so an existing Phase 2 store opens without a
  migration step.
- The sidebar reads sources from `Source` records. `MockData` seeding is left as
  it is until task 10.
- Regenerate tokens at 1.6.0: `connectCalendarRowHeight`,
  `connectCalendarListMaxHeight`; `inspectorLecturersMaxRows` as `Int`.

**Acceptance — tests:**

- A store written by the Phase 2 build (fixture file or schema-v2 container)
  opens, and every Phase 2 event reads back unchanged with the new fields at
  their defaults.
- `paletteKey` assignment picks the first unused slot, and `graphite` when all
  are used.
- `Source` round-trips every field, including the three JSON fields.
- **No `Source` property can hold a password**:
  - A test enumerates `Source`'s stored properties against an allow-list equal
    to §21.1's table.
  - A `Source` built during a connect that used the sentinel password contains
    no substring of it in any stored value.
- `Source.accountDisplay` for `serverURL` `https://cis.technikum-wien.at` and
  `username` `user01` is exactly `user01 @ cis.technikum-wien.at`.
- `Tokens.Size.inspectorLecturersMaxRows` is an `Int`.
- All 622 Phase 2 tests still pass.

*Captures:* none.

### Task 2 — `SecretStore`: Keychain internet-password item, in-memory double

*Spec:* components §21.4; interactions §13.1.

**Build:**

- `protocol SecretStore`: save / read / delete the password for `(host, port,
  username)`.
- `KeychainSecretStore`: an internet-password item with exactly §21.4's
  attributes; queries always include server, account, protocol, security domain
  `Kadence` and creator `Kdnc`.
- `InMemorySecretStore` for tests and review mode.
- A `Password` wrapper type whose `description`, `debugDescription`, `dump` and
  `String(reflecting:)` print `Password(•)` only.

**Acceptance — tests:**

- In-memory round trip, replace and delete.
- **Query dictionaries** built for save, read and delete carry every §21.4
  attribute: `kSecClassInternetPassword`, server, port 443, HTTPS protocol,
  account, security domain, creator, label `Kadence — University timetable`,
  `AfterFirstUnlock`, not synchronizable, value = UTF-8 password only. This is
  asserted on the dictionary, without touching the Keychain.
- **The read query never matches a foreign item.** Its dictionary includes the
  security domain and creator. And a Keychain test inserts an item with the
  same server and account but no security domain, then asserts that `read`
  returns nil and `delete` leaves that item.
- A real Keychain round trip against a throwaway account (`user01-tests`),
  deleted in `tearDown`. It **skips** (`XCTSkip`), not fails, when the Keychain
  is unavailable to the test host.
- Replace writes the new item before deleting the old: an injected failure
  between the two leaves the old item readable.
- The sentinel password never appears in any `description`,
  `debugDescription`, `String(reflecting:)`, `dump` or error message produced
  by the store or the wrapper.

*Captures:* none.

### Task 3 — ICS parser, including the real export

*Spec:* components §20.3, §20.4, §20.7 (generic, CRLF/LF), §22.1 "Parser
fixtures" and "The real export".

**Build:**

- Pure: one iCalendar text (`Data`) → `ParsedCalendar` (`[ParsedVEvent]` +
  `[ImportProblem]` with line numbers), or `.notACalendar`.
- It handles: BOM; CRLF, LF and mixed; unfolding; unescaping; parameters;
  `DATE` / `DATE-TIME` / `Z` / `TZID` / floating (→ an injected "current zone",
  the Mac's in the app); the Windows-name table; `DURATION`; `STATUS`;
  `ORGANIZER` CN; `URL`.
- `VERSION` is not checked.
- The is-a-calendar check (§20.8.2) and the 1 MB per-object limit.

**Fixtures** under `KadenceTests/Fixtures/ICS/`:

- **`cis-2026WS-redacted.ics`, copied byte for byte from `fixtures/`**
- `edge-cases.ics`
- `malformed-partial.ics`
- `html-login.html`
- `truncated.ics`
- `flat-series.ics`

**Acceptance — tests:**

- **The real export:**
  - The bundled copy's SHA-256 equals `fixtures/cis-2026WS-redacted.ics`'s.
  - It parses to **13 VEVENTs, 0 problems** with `VERSION:1.0`.
  - The 22-name `INNO3-EL` description and its 186-character UID read intact.
  - The DST rows of §22.1's table hold (12:30Z, 06:00Z, 13:30Z).
  - An LF-only copy made in the test parses identically.
  - With the injected zone `America/New_York`, every instant is unchanged.
- **`edge-cases.ics`:** every row of §20.3, §20.4 and §20.7 is asserted.
  Floating and `Custom Zone` are read in the injected zone. One problem (the
  unknown zone).
- **`malformed-partial.ics`:** 3 unparseable VEVENTs are reported with their
  line numbers, and 7 parse. The `FREQ=MONTHLY` series is task 4's fourth
  problem.
- **Not a calendar:** `html-login.html`, `truncated.ics` and a 1.1 MB object →
  `.notACalendar`.

*Captures:* none.

### Task 4 — Feed derivation and content hashes: identity, the CIS profile, the merge, recurrence

*Spec:* components §20.2 (incl. "hrefs and ETags are not identity", "across
calendars"), §20.5, §20.7.1, §20.8.4 (hash definitions), §20.10 (key
behaviour).

**Build:**

- Pure: `[(calendarHref, objectHref, ParsedCalendar)]` → `[ExternalEvent]` +
  problems + `mergedCount` + `objectCount`.
  - Content-vs-uid identity per VEVENT, and the content key.
  - The CIS profile.
  - The merge **across objects and calendars**: lecturers union in ascending-UID
    order.
  - Exact-duplicate tie-breaks.
  - The `RRULE` subset, `RDATE`, `EXDATE`, `RECURRENCE-ID`, flat series, and
    open-ended series bounded at today + 366 days.
- `EventHash.of(ExternalEvent)` and `EventHash.of(Event)` (stored upstream
  fields), plus `FeedHash.of([eventHash])`, exactly per §20.8.4. Field order
  and separators U+001F / U+001E.

**Acceptance — tests:**

- **Merge and profile**, on `cis-2026WS-redacted.ics` split one VEVENT per
  object (as `reportCIS` does):
  - **12 events, `mergedCount` 1, `objectCount` 13.**
  - `BPREF-Info` 2 Oct has `lecturers == ["L05", "L06"]` whichever object comes
    first: the test also runs with the two swapped and asserts equal output.
  - All 12 are in content mode. `SWQM-ILV`'s externalID is exactly `SWQM-ILV
    HS_A3.15 - BIF-5C|HS_A3.15|20260914T123000Z|20260914T140000Z`.
  - Titles are the course codes, and groups are trimmed.
  - `INNO3-EL` has 22 lecturers `L10`…`L31`, and `isOnline`.
  - Exactly `REQEN-EXAM`, `RW-EXAM` and `GLD-EXAM` are `.exam`.
  - `importedDescription` is nil for all 12.
  - Parsing the whole file as one object gives the identical result.
- **Hrefs are not identity:**
  - Renaming every object href, and moving `BPREF-Info`'s two halves into two
    different calendar hrefs, gives identical events and an identical feed hash.
  - A duplicate `RW-EXAM` in a second calendar merges to one event.
- **Hashes:**
  - Feed hash is invariant under object order, and under CRLF → LF.
  - Feed hash changes when one lecturer is added, and exactly one event hash
    differs.
  - `EventHash.of(Event)` of an event written from an `ExternalEvent` equals
    `EventHash.of` that `ExternalEvent`.
  - A golden test pins the hex of `SWQM-ILV`'s event hash. CA computes it once
    from §20.8.4's definition, and records the string in the test and STATUS.
- **Merge survival** (synthetic, built from the fixture's lines):
  - Adding a third co-teacher, or removing one, keeps the externalID and
    changes only `lecturers`.
  - A room change gives a new externalID.
- **Kind fallback:** course code `Datenmodellierung` and `FOO-XYZ` →
  `.lecture`, with no problem.
- **Generic feeds:**
  - `edge-cases.ics`'s stable-UID pair merges, keyed by the content key.
  - `flat-series.ics` → 4 externalIDs `UID|…`.
  - A weekly 09:00 Europe/Vienna series stays at 09:00 local across 25 Oct 2026.
  - An open-ended `FREQ=DAILY` stops at today + 366 days.
  - `FREQ=MONTHLY` skips its series with §20.5's sentence:
    `malformed-partial.ics` → 6 imported, 4 problems.

*Captures:* none.

### Task 5 — HTTP transport and WebDAV XML

*Spec:* components §21.4 (session, no redirects), §20.8.2 (window `start`
values, request bodies, size limits); interactions §13.1; `caldav-mocks.md` §1–§2
(shapes).

**Build:**

- `protocol HTTPTransport`.
- `URLSessionTransport`:
  - an ephemeral configuration, `urlCache = nil`, `urlCredentialStorage = nil`;
  - a redirect delegate that **never follows** and returns the `3xx` to the
    caller;
  - a challenge handler that supplies the password only for the source's host,
    port and `https`, and that the client can arm per connect or sync;
  - a fresh session per connect and per sync.
- `MultistatusParser`: a `207` body → `[DAVResponse { href, propstats[status,
  props] , status }]`. It is namespace-aware (DAV:, caldav, calendarserver,
  sabredav), and prefixes are irrelevant.
- `CalDAVRequests`: builders for D2/D3/D4 `PROPFIND`, `calendar-query` with
  `start`, `PROPFIND` Depth 1 on a calendar, and `calendar-multiget` in batches
  of 100.
- `Windows.importStart(now:zone:)` and `syncStart(now:zone:)`.
- One `SourceLogger` that takes a `Source`, never a request.

**Acceptance — tests:**

- **Parsing:** every XML body in `caldav-mocks.md` parses to the expected values.
  - D2: principal `/webdav/lvplan.php/principals/user01/`, with
    `calendar-home-set` in a `404` propstat.
  - D3: home `/webdav/lvplan.php/calendars/user01/`.
  - D4: three responses with their resourcetypes, `LVPlan`, VEVENT+VTODO,
    getctag `LVPlan-user01-1791454967`, and `sync-token` in a `404` propstat.
  - `report-cis-2026WS.xml`: 13 hrefs, etags, and `calendar-data` with LF line
    endings.
  - The same bodies re-serialised with other prefixes parse identically.
- **Request bodies:** they match `caldav-mocks.md` on meaning: method, `Depth`,
  property set, filter. The multiget for 250 hrefs makes 3 batches.
- **Windows:** `syncStart` = `20261007T220000Z` and `importStart` =
  `20251007T220000Z` at the test clock; `syncStart` = `20261101T230000Z` on
  2026-11-02.
- **Transport:** a `3xx` is returned, not followed. A response over 20 MB is
  refused as too large.
- **Challenges:** the challenge handler declines `login.example.invalid` and
  `http://cis.technikum-wien.at`.
- **Session state:** no cookie, cache or credential survives into a new session.

*Captures:* none.

### Task 6 — CalDAV discovery

*Spec:* components §20.8.1, §19.1 (discovery states); interactions §13.1;
`caldav-mocks.md` §1, §3.

**Build:** `CalDAVDiscovery.discover(server:username:password) async throws →
DiscoveryResult { contextURL, principalHref, calendarHomeHref, calendars:
[DiscoveredCalendar { href, displayName, components, ctag? }] }`:

- D1–D4 with the selection rule.
- The `Server` path shortcut.
- Href resolution, with off-host hrefs ignored.
- 401 handling per interactions §13.1.

**Acceptance — tests through the `URLProtocol` stub:**

- **`discoveryOK`:** exactly one calendar `LVPlan` at
  `/webdav/lvplan.php/calendars/user01/LVPlan-user01/`. The home and `outbox/`
  are excluded. Exactly **4** requests.
  - D1 carried no `Authorization`.
  - The first request that did came after a `401` from
    `cis.technikum-wien.at`.
- **`multiCalendar`:** `LVPlan`, `Prüfungen`, in D4 order. `Aufgaben` (VTODO
  only) and `inbox/` are excluded.
- **D2 shortcut:** a `207` with `calendar-home-set` at `200` skips D3 (3
  requests).
- **A `Server` with a path** (`https://cis.technikum-wien.at/webdav/lvplan.php/`)
  skips D1.
- **A missing `displayname`** shows the decoded last segment.
- **Failures** map to these states:
  - `wellKnown404`, `propfindNot207` → `noCalDAV`
  - `noCalendars` → `noCalendars`
  - `unauthorized` → `unauthorized`, after exactly one request carrying
    `Authorization`
  - `forbidden` → `forbidden`
  - `certificate` → `certificate`, with **zero requests delivered**
  - `redirectOffHost` → `redirected` (`login.example.invalid`), with **no
    request to that host**
  - `redirectToHTTP` → `redirected` (`http:`)
  - `timeout` → `unreachable`
  - `offline` → `offline`
- **An off-host href in D4** is never requested.
- **Secret hygiene:** run every case with the sentinel password. It appears in
  no error, `stateDetail`, captured logger line or `dump` of the result.

*Captures:* none.

### Task 7 — CalDAV client: fetch, the fallback chain, re-discovery, the cap (`CalDAVScheduleSource`)

*Spec:* components §20.8.1 (cache, re-discovery), §20.8.2 (all), §21.5;
`caldav-mocks.md` §2, §3, §4.

**Build:**

- `CalDAVClient.fetch(calendar:windowStart:mode:)`, implementing the chain
  F0 → F1 → F2 on `405`/`501` only.
- `207` member failures become problems.
- The not-a-calendar and size checks.
- `timeRangeHonoured` detection.
- `CalDAVScheduleSource: ScheduleSource`, built from the client, the parser
  (task 3) and the derivation (task 4):
  - Calendars are fetched sequentially, in `Source.calendars` order.
  - Re-discovery happens once per sync on `404`/`410`/`301`/`308`, matching by
    href, then by unique display name.
  - `failedCalendars`, `adoptedCalendars` and `calendarsReadInFully`.
  - The 300-request cap.
  - `SyncDiagnostics` and the §20.8.4 log line.

**Acceptance — tests through the stub:**

- **`reportOK`** (`reportCIS`, sync window at the test clock):
  - **1 request** (discovery cached), `REPORT` `Depth: 1`, `start` =
    `20261007T220000Z`.
  - 9 objects → the expected events.
  - `fetchMode` `report`, `timeRangeHonoured == true`.
  - With the mock ignoring the time-range (all 13 returned),
    `timeRangeHonoured == false` and `events` still contain all 12.
- **`reportRefused`:** 3 requests (`REPORT` 405, `PROPFIND`,
  `calendar-multiget`), the same events as `reportOK`'s unfiltered set, and
  `fetchMode` `multiget`. **No problem and no non-ok state.**
- **`multigetRefused`:** 3 + n requests, sent one at a time, and `fetchMode`
  `get`. CRLF from `GET` gives the same feed hash as LF from `REPORT`.
- **`allRefused`:** `fetchFailed`, with technical line `REPORT 405 · PROPFIND
  207 · calendar-multiget 501 · GET 405`.
- **`overCap`:** `fetchFailed` after **exactly 300** requests, with the cap
  technical line.
- **Mode memory:** a second fetch with `fetchMode` `multiget` starts at
  `PROPFIND`.
- **`calendarMoved`:** 1 + 4 + 1 requests. `adoptedCalendars[0].href` is the
  new href, and the events are read.
- **`calendarGone`:** `calendarMissing` in `failedCalendars`, with
  `calendarsReadInFully` empty.
- **`htmlOK`:** `notACalendar`.
- **One object with `truncated.ics` as its `calendar-data`:** one problem, and
  the others are read.
- **`serverError`** → `serverError`. **`timeout`** → `unreachable`.
- **Two calendars, one failing:** the first calendar's events are returned, and
  `calendarsReadInFully` holds only it.
- **No two requests are ever in flight** (the stub asserts it).
- **Secret hygiene:** as in task 6, for every case. The log line for
  `reportOK` matches §20.8.4's format, and contains `user01 @
  cis.technikum-wien.at` and no password.

*Captures:* none.

### Task 8 — Sync planner and applier: change detection by content, windows, guards, deselection

*Spec:* components §20.1, §20.6, §20.8.3, §20.8.4, guards, §20.9, §20.10,
§18.1, §21.5.

**Build:**

- `SyncPlanner.plan(existing:result:kind:now:) -> SyncPlan`, pure. `kind` is
  `.import`, `.sync` or `.editSave(deselected:)`. It applies the window,
  computes the feed hash, and stops when it equals `Source.feedHash`. Otherwise
  it diffs by externalID and event hash, under the guards.
- `SyncApplier`: one store transaction. It writes the last-change counts,
  `feedHash` (only when every calendar was read in full) and `calendars`
  (adopted hrefs).

**Acceptance — in-memory container tests**, clock 2026-10-08 10:00
Europe/Vienna, events from `reportCIS`:

- **Import** creates 12 events, 3 of them history, and deletes nothing.
- **A sync of the same content a day later** writes nothing (no insert, update
  or delete; `feedHash` re-stored for the new window), and every `Event.id` is
  unchanged.
- **Change by content, not markers:**
  - `etagsOnly` (every href and ETag changed) → **nothing written**.
  - `ctagOnly` (via the task 7 client and stub, two polls, getctag +55) → the
    second poll writes **nothing**, and `lastChange*` is unchanged.
  - With step 4 disabled, step 5 still writes nothing.
- **The changed feed**, with the review template rendered (`M` = 2026-10-12)
  and served as `reportReview`, then `reportChanged` — exactly §22.1's table:
  - **Room move:** `SWEN3-LAB`'s old event is deleted and a new one created
    `.scheduled`, although the old was marked `done`.
  - **Vanished lecture:** `EPC-ILV` is deleted.
  - **Lecturer change:** `SWQM-ILV` is updated in place, keeping `status` and
    `Event.id`.
  - **Co-teacher removal:** merged `SWRM-ILV` is updated in place to `[L05]`.
  - `KOKU-UE` is created.
  - H1 is untouched, and no H1' is created.
  - The last change reads `2 added · 2 updated · 2 removed`.
- **Guards:**
  - `partialImport` → creates and updates, no deletions (the old `SWEN3-LAB`
    stays beside the new).
  - `emptyCalendar` after events → `emptyFeed`, nothing deleted.
  - Two calendars with one `calendarMissing` → creates and updates from the
    other, no deletions, state `calendarMissing`, `feedHash` not written.
  - Any thrown error → nothing written.
  - Removing the source deletes history too.
- **Edit-mode `Save`:**
  - It follows sync rules: a past event in the fetched data is not created.
  - **Deselection** (`multiCalendar` with `Prüfungen` unchecked, after
    `Prüfungen` contributed a unique past and a unique future event) deletes
    both, history included.
  - The deduplicated `RW-EXAM` stays, because `LVPlan` still has it.
  - A deselection whose Import-window read was not full deletes nothing.
- **Selection and undo:**
  - A deleted selected event clears the selection.
  - Undo steps addressing a deleted event are dropped.
  - A sync that finishes during an active conflict preview is held, and applied
    when the preview ends.
- **History never conflicts:** an H-event placed on a past routine occurrence
  adds nothing to the count. If the Phase 2 engine already excludes past days,
  this test documents it; record which in STATUS.
- **Conflict counts:** after the review Import, `ConflictEngine` reports **14
  day conflicts** and needs-attention **15**, which proves the merge. Friday's
  conflict has rows `Shift Training 45 min later` (recommended) · `Shorten
  Training to 45 min` · `Skip Training today`.
- **Cancelled:** a cancelled event (`edge-cases.ics`) produces no conflict.

*Captures:* none.

### Task 9 — Sync coordinator and scheduling

*Spec:* interactions §13.3; components §19.1 (transitions), §20.8.2 (`get`-mode
floor, timeouts); G-061.

**Build:**

- `SyncCoordinator`:
  - triggers: interval, launch, wake, network regained, Sync Now (Import/Save
    write without a request);
  - one sync at a time per source;
  - the 401/403 pause and the offline state;
  - timeouts: 30 s per request, 120 s per sync (600 s in `get` mode);
  - `max(interval, 6 h)` in `get` mode;
  - cancellation on sleep, quit and removal.
- The scheduler, clock, path monitor and wake notifications sit behind
  protocols with fakes.
- View ▸ Sync Now `⌘R`.

**Acceptance — fake-driven tests:**

- The default interval is 1800 s.
- Launch with a stale `lastAttemptAt` syncs; with a fresh one it doesn't.
- An interval change re-creates the scheduler with 10% tolerance.
- A trigger during a running sync is dropped.
- **Pause:** after `unauthorized` or `forbidden`, no automatic trigger syncs
  until edit `Save`, while Sync Now does. A successful Sync Now clears the
  pause.
- **These do not pause:** `noCalDAV`, `noCalendars`, `calendarMissing`,
  `fetchFailed`, `notACalendar`, `redirected`, `certificate`,
  `passwordMissing`.
- **`passwordMissing`** makes no transport call.
- **Offline** → the `offline` state and no transport call.
- **Network regained** after `unreachable` syncs.
- **Wake** waits for the path.
- **`get` mode:** automatic polls are spaced at least 6 h apart, and Sync Now is
  not limited.
- **Import** makes **no** transport call.
- **Sleep** cancels a sync mid-chain, and nothing is written.
- **Menu:** the `⌘R` item exists, and is disabled while every source is
  syncing.
- Record the G-061 choices in STATUS.

*Captures:* none.

### Task 10 — Review mode: mocked CalDAV server, the review dataset, empty real store

*Spec:* components §22.1; `caldav-mocks.md`; G-057 (ruled).

**Build:**

- `MockCalDAVTransport` (no network). It serves D1–D4 and every
  `caldav-mocks.md` case, and the rendered `cis-review.ics.template` as
  `reportReview` (split `r01.ics` … `r14.ics`), honouring the time-range as
  SabreDAV does.
- Launch arguments:
  - `-KadenceReview phase3`:
    - seed the Phase 2 dataset;
    - make `timetable` a `caldav` `Source` (`user01`, `LVPlan`) with the review
      password in an `InMemorySecretStore`;
    - seed the manual all-day `Studieninformationstag` on `M + 2`.
  - `-KadenceMockCalDAV <case>`, default `reportOK`. `reportChanged` serves
    `reportReview` first, then the changed body on the next sync.
- `M` = the first Monday ≥ today + 2.
- The seeded mock `Datenmodellierung`'s externalID is the content key of the
  template's `{{TODAY}}` event.
- **Without `-KadenceReview`, an empty store stays empty** (G-057): no sources,
  no events, no routine.

**Acceptance:**

- A `MockDataClockTests` sibling pins day conflicts **14** and needs-attention
  **15**, for a template weekday and a non-template weekday at the clock times
  it sweeps, and pins the footer index of Friday's conflict at **d + 1**
  (§22.1).
- **The rendered template:**
  - It has CRLF line endings, `VERSION:1.0`, and 14 VEVENTs in the CIS shape.
  - Split as `reportReview`, it gives 14 objects that parse with 0 problems
    to 13 events.
  - For the sync window at the test clock, H1 and H2 are not returned.
- A launch with each case reaches its §19.1 state.
- The review password never touches `KeychainSecretStore` (asserted by
  injecting a failing Keychain store).
- `Datenmodellierung`'s `Event.id` and travel leg survive the review Import.
- A launch without the argument, on an empty store, yields zero `Source`s and
  zero `Event`s.

*Captures:* none (task 17 uses it).

### Task 11 — Status presentation model and copy

*Spec:* components §19.1, §19.2 (kind → colour), §19.3 (last-change line),
§19.4 (stale rule), §19.5; layouts §12.1 (step-1 bodies and focus).

**Build:**

- `SourceStatusPresentation(source, now)` → title, body, status line,
  last-change line or nil, primary action, glyph kind, hover help, and
  stale-line text or nil. Pure.
- `ConnectFailurePresentation(state)` → step-1 title, body and focus target.

**Acceptance — tests:**

- One test per §19.1 row, asserting the **exact** strings with these values:
  - `{host}` `cis.technikum-wien.at`, `{user}` `user01`, `{account}` `user01 @
    cis.technikum-wien.at`
  - `{calendar}` `LVPlan`, plus the two- and three-calendar forms
  - `{name}` `University timetable`, `{otherHost}` `login.example.invalid`
  - both `redirected` bodies
- One test per §12.1 failure-table row (body and focus).
- **Primary actions** per state: `Update Password…` / `Edit Account…` /
  `Choose Calendar…` / `Sync Now` / `Show Details` / none.
- **Plurals:** `1 event` / `2 events`.
- **The last-change line:** every combination of zero terms omitted, and `nil`
  after an Import with no later write.
- **§19.5's five time forms** at fixed clocks.
- **The stale line:**
  - shown/hidden at 23 h 59 / 24 h 01 for a 30-minute interval;
  - shown/hidden at 2 × 1 day for a 1-day interval;
  - never for `offline` alone.
- **No secrets:** no output string, for any state, built while the sentinel
  password is in the secret store, contains it.

*Captures:* none.

### Task 12 — Settings ▸ Sources and removal

*Spec:* layouts §11; interactions §13.2; components §19.3 (inline block), §21.4.

**Build:**

- A `Settings` scene with the one `Sources` tab: list + `+`/`−`.
- The detail: status block (with the last-change line), then the form — Name,
  `Account` `{user} @ {host}` with `Edit Account…`, `Calendar(s)`, and the Sync
  interval — then `Remove Source…`.
- The empty state.
- The removal alert, and its Keychain-failure follow-up.
- File ▸ Connect Timetable….

**Acceptance — tests:**

- **Renaming** commits on `↩`/blur, reverts when empty, and updates the
  Keychain label.
- **The `Account` row** reads exactly `user01 @ cis.technikum-wien.at` and is
  selectable. **No row, label, help text or accessibility value shows a
  password or bullets.**
- **`Calendar` vs `Calendars`** follows the count; names are comma-separated.
- **The interval picker** offers exactly the seven values, default `Every 30
  minutes`.
- **`Remove`:**
  - deletes the events (history included) and the source in one transaction;
  - calls `SecretStore.delete`;
  - frees the palette slot;
  - recomputes conflicts (the count drops by the source's conflicts).
- **The alert:** `Cancel` is the default button, and the text says `password
  deleted from the Keychain`.
- **A Keychain delete failure** still removes the source and shows the
  follow-up copy.
- **Review mode:** Settings opens on the source in `upToDate`.

*Captures:* `settings-sources-uptodate`, `settings-sources-empty`,
`remove-source-alert` (§22 items 8, 18).

### Task 13 — The connect sheet

*Spec:* layouts §12; interactions §13.1, §13.2; components §19.1, §20.1,
§20.8.1.

**Build:**

- **Step 1:** Server (prefilled), Username, Password; validation; one
  connecting state over discovery and the Import-window fetch; inline failures
  with focus placement.
- **Step 2:** `{user} @ {host}`; **the single confirmed row for one calendar**,
  or a checklist for several, recomputing from fetched data; range and
  sentences; `Show Details`.
- **Edit mode:** prefill, the `Saved in Keychain` placeholder, `Choose
  Calendar…` auto-Connect, unchecked new calendars, the missing-calendar line,
  the deselection sentence, `Save`.
- Nothing is persisted before `Import`/`Save`. Import writes the
  already-fetched data.

**Acceptance — tests:**

- **Validation:** every row of §12.1's table, including the WebDAV share
  (`https://cis.technikum-wien.at/Webdav/Lvplan` refused;
  `…/webdav/lvplan.php/` accepted as a path) and the duplicate account.
  `Connect` enablement follows the table.
- **Cancel** mid-discovery cancels the request and writes nothing: no
  `SecretStore.save`, no `Source`, no `Event`.
- **Failures:** each failure case maps to §12.1's step-1 body and focus target.
- **Step 2 on `reportOK`** (template):
  - **one confirmed row `LVPlan`, which is not a control** (no checkbox in the
    view tree, not focusable, AX `Calendar: LVPlan`);
  - `13 events, …`, history `2`, merges `1`.
- **Step 2 on `reportCIS`:** `12 events, 14 Sep 2026 – 29 Jan 2027`, `3 of them
  are before today…`, `1 co-taught lecture…`.
- **Step 2 on `multiCalendar`:**
  - two checkboxes, both checked;
  - unchecking `Prüfungen` keeps 13;
  - unchecking both shows `Choose at least one calendar.` and disables
    `Import`;
  - toggling makes **no** transport call.
- **Copy:** singular forms; the empty-calendar copy with `Import` enabled.
- **`Import`:**
  - makes **no** transport call;
  - writes Keychain → Source → events, in that order;
  - stores `calendars`, `principalHref` and `calendarHomeHref`;
  - a Keychain failure writes nothing else, with the `Password not saved` copy.
- **`Back`** restores every field, the password included.
- **Edit mode:**
  - The password is empty with its placeholder.
  - Empty uses the saved password, unless the username changed (then `Connect`
    is disabled).
  - `Choose Calendar…` starts connecting at once.
  - Unselected calendars are unchecked.
  - The deselection sentence counts correctly.
  - `Save` replaces the Keychain item (new, then old), clears the pause, resets
    `fetchMode`, and applies as a sync plus deselection (task 8's planner).
- **No secrets:** the sentinel password appears in no view other than the
  `SecureField`, and in no accessibility value.

*Captures:*

- `connect-step1-empty`, `connect-step1-filled`
- `connect-step1-connecting` (`slow`)
- `connect-step1-unauthorized`, `connect-step1-certificate`,
  `connect-step1-nocaldav` (`wellKnown404`), `connect-step1-webdav-hint`
- `connect-step2-single` (`reportOK`), `connect-step2-checklist`
  (`multiCalendar`)
- `connect-edit`

These are §22 items 2–7.

### Task 14 — Sidebar rows, the source popover, the stale line

*Spec:* layouts §2.1; components §19.2, §19.3, §19.4.

**Build:**

- The status slot: spinner after 0.5 s, glyph and colour by kind.
- Hover help, AX value, and the context menu.
- `↩` opens the popover.
- The source popover with the last-change line and `Show Details`.
- The first-run `Connect Timetable…` row.
- The menu bar popover's stale line.

**Acceptance — tests:**

- **Slot content** per kind, including nothing for `offline`.
- **The spinner** is not shown for a sync shorter than 0.5 s.
- **Checkboxes** share one x across local and connected rows.
- **The popover's default button** is the state's primary action:
  - `Update Password…` opens edit mode focused on `Password`.
  - `Edit Account…` opens edit mode focused on `Server`.
  - `Choose Calendar…` opens edit mode already connecting.
  - `Settings…` opens Settings on the source.
- **The details list** is capped at 8, then `+N more`.
- **The first-run row** is present with no connected source and gone with one.
- **The stale line** is present or absent per task 11's model, and never
  truncated at a 60-character source name.
- **Needs attention:** source errors do not change the count.
- **No secrets:** no hover help or AX value contains a password.

*Captures:*

- `sidebar-first-run`
- `sidebar-row-states` (an offscreen render of the four states, §17.2 rule 3),
  plus one live sidebar frame
- `source-popover-forbidden`, `source-popover-partial-details`
- `source-popover-last-change` (`reportChanged`)
- `source-popover-calendar-missing` (`calendarGone`)

These are §22 items 1, 9, 10, 12 and 21.

### Task 15 — Imported events on the canvas

*Spec:* components §2.1, §5.1, §6 (`cancelled`, the `done` amendment), §18.2,
§20.4, §20.6.

**Build:**

- `.eventAllDay` in the resolver and the all-day row (manual all-day events now
  draw too).
- The exam glyph, and `Online` in the location slot.
- The `cancelled` state.
- `done` on solid fills in `text.primary`.
- No resize handles on imported blocks.
- Cancelled events excluded from conflicts, next-up and `firstEventStart`.

**Acceptance — resolver tests:**

- **Glyphs:** `.fixedTimed` imported `exam` → `graduationcap.fill`; `lecture` →
  `building.columns`.
- **`.eventAllDay`:** fill, glyph, no rail and no chip, for both origins and for
  an imported exam.
- **The `.full` meta line:** `University timetable · Online` for an online
  event, `University timetable · HS_A3.15` otherwise.
- **Hover help:** Kind `Exam` / `Lecture`.
- **`cancelled`:**
  - blend, dashed border, `xmark.circle`;
  - label and meta in `text.primary`;
  - `Cancelled · University timetable` at `.full`.
- **`done`:** the label is `text.primary` for the three solid kinds and
  `text.secondary` for the others.
- **Hover** shows no handles on an imported block.
- **G-055 regression:** a `⌘⌥N` all-day event appears in the all-day row.
- **The all-day row** sorts per §5.1.
- **The merged `SWRM-ILV`** is one block.

*Captures:*

- `week-M` (review mode, Week view paged to `M`)
- `week-M-after-change` (`reportChanged`)
- `allday-and-done-{light,dark}`
- `cancelled-block` (offscreen, `edge-cases.ics`)

These are §22 items 11, 12, 19 and 20.

### Task 16 — Inspector, refusals and the menu bar for imported events

*Spec:* layouts §6.1; interactions §13.4, §13.5; components §18.1, §18.3.

**Build:**

- **Read-only inspector rows:**
  - the title as text, and the read-only line;
  - `Lecturer(s)` with the collapse rule;
  - `Group`, and `Room` / `Online · …`;
  - Source + sync line;
  - Description;
  - Link in `interactive.link`.
- **Refusals:** the emphasis on refusal, the beep, and Edit ▸ Delete disabled.
- **Menu bar:** popover `Done` · `Open` for an imported NEXT, the `⌥⌘↩` refusal
  row, and no `Re-offer` when late.
- **VoiceOver:** the label adds `cancelled`.

**Acceptance — tests:**

- **Refusals:** every row of §13.4's table (drag, `⌫`, the six `⌥` keys,
  double-click, done/skip allowed, refused on cancelled), asserting that:
  - the store is unchanged;
  - the sound hook fired for keyboard paths;
  - the emphasis state was set for 0.6 s;
  - the inspector was not opened by a refusal.
- **Lecturer rows:**
  - 1 name → `Lecturer`; 2–4 → all shown under `Lecturers`.
  - 5 → 3 + `and 2 more`; 22 → 3 + `and 19 more`.
  - Expansion shows all 22 and `Show fewer`, and a new selection resets it.
  - The AX value lists every name.
- **Location label:** `Room` vs `Location` by profile; `Online · WEBINAR01`.
- **Description:** no row for a CIS event, and it never writes to `notes`.
- **Link** opens via `NSWorkspace` (stubbed).
- **Menu bar:**
  - the popover action set for an imported NEXT, normal and late;
  - the refusal row's text (`Not moved — SWQM-ILV`) and accessibility label are
    exact.
- **Undo:** done/skip on imported events are named undo steps.
- **The sync line** reads `Access refused` for a `forbidden` source.

*Captures:*

- `inspector-imported` (`SWQM-ILV`)
- `inspector-lecturers-{collapsed,expanded}` (`INNO3-EL`)
- `inspector-cancelled` (offscreen, `edge-cases.ics`)
- `inspector-refusal-emphasis`
- `conflict-lecture-training`: Friday's conflict previewed. No new code, but
  its evidence lives here.
- `popover-imported-next`, `popover-stale-line` (offscreen renders per §17.2
  rule 3; one live popover frame)

These are §22 items 13–17 and 20.

### Task 17 — Capture the §22 review set and write `screenshots/3/INDEX.md`

*Spec:* components §22, §22.1, §17.2 (rules 1–6).

**Build:** recapture every §22 item (1–21) from one final build in review
mode, with the mocked case each item needs. Names are `<item-name>-p3.png`.

**Acceptance:**

- Every frame obeys §17.2 rules 1–6. The edge check runs on all of them, and
  item 16 is the only preview frame.
- INDEX.md maps each §22 item to its file(s), and names:
  - the mocked case;
  - the `M` date and the `k` shown;
  - the appearance of any colour-measuring frame.
- Superseded `-p3t<N>` frames are deleted once INDEX no longer maps to them.
- The full test run is green, and `generate-tokens --check` is clean at 1.6.0.
- **Secret grep, in the task's report:**
  - `S3ntinel-pw` appears only in the tests that define it.
  - `review-only-not-a-password` appears only in the review-mode seeding and
    its test.
  - No `Authorization:` header value appears anywhere in the repo.
  - No username other than `user01` appears in `KadenceTests/Fixtures/` or in
    any capture.
  - No `webcal`, `••••••` mask or subscription-link string remains in
    `Kadence/` or `KadenceTests/`.
  - No capture shows a password other than as `SecureField` bullets.

*Captures:* the full set.

**17 build tasks** (plus housekeeping H1, H2). Discovery (task 6), the fallback
chain (task 7), content-hash change detection (tasks 4 and 8) and the duplicate
merge (task 4, proven again by task 8's conflict counts) are each tested only
against `caldav-mocks.md`.

## Judgement calls made in this amendment

1. **The Import window reaches back 366 days**, and both windows are
   open-ended forward (`time-range` with `start` only). A `REPORT` needs a
   window, while "the whole semester the feed contains" has no fixed size. A
   year back holds any semester (§20.8.2).
2. **The time-range is a saving, not a rule.** The planner filters whatever the
   server returns, and `timeRangeHonoured` is recorded (§20.8.2, G-068).
3. **Fallback mode is remembered** until re-discovery or edit `Save`, so a
   server that refuses `REPORT` isn't asked again every 30 minutes (§20.8.2).
4. **Request cap of 300 per sync, sequential requests, and a 6-hour floor in
   `get` mode.** One object per request every half hour is not something to
   point at a university server. On CIS (`REPORT` works, per Apple Calendar)
   none of this should ever trigger (§20.8.2).
5. **Event hash and feed hash definitions.** Upstream fields only, fixed order,
   U+001F/U+001E separators. The feed hash covers only events in the write
   window. Per-event hashes are recomputed from stored fields, never stored.
   This needs no model field beyond DECISIONS' `feedHash` (§20.8.4).
6. **ctag and ETags are logged, never stored or requested on their own.** The
   diagnostics are one unified-log line per sync, and that line is also how
   Parsa answers G-068 (§20.8.4).
7. **Discovery runs again in edit mode's `Connect`**: an explicit act (see
   "DECISIONS.md" above).
8. **Within one sync, the credential may be reused** after the host's first
   `401`. Every sync starts without it (see "DECISIONS.md" above).
9. **The merge spans calendars.** The same lecture in two selected calendars is
   one event (§20.2).
10. **Deselection deletes by content**, using a full Import-window read of the
    remaining calendars, because `Event` has no calendar field (§20.1). Step 2
    counts the deletion before `Save`. No alert.
11. **With several calendars, one failing blocks all deletions** for the source
    (§20.8 guards), because of 9.
12. **Edit mode never adds a calendar the user didn't check.** On `Connect`,
    every listed calendar is checked (§12.2–§12.3).
13. **A calendar added in edit mode contributes from today on.** Its past is
    not imported: edit `Save` is a sync (§20.1).
14. **One source per (host, username)**, enforced at `Connect`. That makes the
    Keychain item (server, account, security domain `Kadence`) unique without
    a `Source.id` in its key (§21.4).
15. **The Keychain item is filtered by security domain `Kadence` and creator
    `Kdnc`**, so Kadence never reads or overwrites an internet-password item
    that Apple Calendar or another app saved for the same account (§21.4).
16. **`forbidden` → `Edit Account…`**: a 403 for a valid password is about the
    account, not the password. **`notACalendar` → `Sync Now`**: there is no
    link left to fix (§19.1).
17. **`Server` accepts a path**, which skips `/.well-known/caldav`. This is the
    escape hatch if the well-known redirect ever disappears. It costs no UI
    (§12.1).
18. **The WebDAV share path is caught by validation** in `Server`, with copy
    naming the FH network (§12.1).
19. **No password row in Settings**, not even bullets. Bullets would imply a
    stored value the user can see, and Keychain Access is where it lives
    (§11).
20. **`Prüfungen`, `Aufgaben`, `inbox`** in `multiCalendar` are invented for the
    checklist review item. CIS itself has one calendar (`caldav-mocks.md`).

## For Parsa — decisions that are yours

1. **The first real connection (G-068).** Connect with your own account, then
   read the `sync` log line (`log show --last 1h --predicate 'category ==
   "sync"' --info`) and record three things:
   - whether `REPORT` with a time-range is honoured (`mode report`,
     `time-range honoured`);
   - whether ETags are stable (the same `etags … (set …)` on two Sync Nows with
     nothing changed);
   - how long one `REPORT` takes, and how many objects it returns.

   Note the 401's scheme and realm too. No agent can do this.
2. **The three readings under "DECISIONS.md" above.** If any of them is not
   what you meant, say so and the spec changes. None needs a new entry.
3. **The `get`-mode 6-hour floor** (judgement 4). It only matters if CIS ever
   refuses both `REPORT` and `calendar-multiget`. Keep it, or say otherwise.
