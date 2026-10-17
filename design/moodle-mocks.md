# Moodle feed mocks — normative responses

Design agent, 2026-10-16 (Phase 3 slice 3). The responses
`MockFeedTransport` and the tests' `URLProtocol` stub serve for the Moodle
calendar export. Referenced from `components.md` §34, §35 and §43. The shape
is **Parsa's real feed** as MA verified it on 16 Oct 2026 (Moodle 4.5,
`PRODID:-//Moodle Pty Ltd//NONSGML Moodle Version 2024100712.01//EN`), redacted
to `fixtures/moodle-2026WS-redacted.ics`.

**No real URL, token or user id appears here or in any fixture.** The only
URL is the mock's (`components.md` §43.1):

```
https://moodle.technikum-wien.at/calendar/export_execute.php?userid=4711&authtoken=SENTINELb0c7a1e2d3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8&preset_what=all&preset_time=recentupcoming
```

Conventions:

- Every case answers the **one** `GET` of that URL (plus the redirect target
  where a case redirects). The stub records every request's host, scheme,
  path and whether it carried `Authorization` or `Cookie` — **neither may
  ever be present**.
- Bodies are copied into `KadenceTests/Fixtures/Feed/<case>.ics` (or `.html`)
  **byte for byte** as described: CRLF line ends, TAB folding and the
  lone-TAB lines exactly as the redacted fixture has them, unless a case says
  otherwise.
- `{{M+d HH:mm}}` (review only) is the local Vienna time on `M + d` days,
  rendered as `yyyyMMdd'T'HHmmss'Z'` in UTC through `WallClock`; `{{NOW}}` is
  the fetch time in the same form. Tests use the fixture's absolute dates.
- Headers: `Content-Type: text/calendar; charset=utf-8` for calendar bodies
  (Moodle's), `text/html; charset=utf-8` for pages. Kadence trusts neither
  (`components.md` §34.2).

---

## M1. Calendar bodies

| Case | Body |
|---|---|
| `feedOK` | `fixtures/moodle-2026WS-redacted.ics` unchanged (29 VEVENTs, `DTSTAMP:20261016T110712Z` on each) |
| `feedStampOnly` | `feedOK` with every `DTSTAMP` → `20261016T120712Z`, and `900020`'s `LAST-MODIFIED` → `20261016T120000Z` |
| `feedLF` | `feedOK` with every `CRLF` → `LF`, every fold's TAB → one space, and the lone-TAB lines removed |
| `feedChanged` | `feedOK` with the six edits of §M2 |
| `feedAged` | `feedOK` without `900001`–`900007` (everything before Sat 17 Oct), `DTSTAMP` `20261022T060000Z` — what the feed looks like a week later |
| `feedEmpty` | `BEGIN:VCALENDAR` · `METHOD:PUBLISH` · `PRODID:` as `feedOK` · `VERSION:2.0` · `END:VCALENDAR`, CRLF, no VEVENT |
| `feedNotice` | `feedOK` plus `900040` (`SUMMARY:Guest lecture: Testing in practice`, `CATEGORIES:BIF-VZ-5-WS2026-SWQM-EN/174454`, `DTSTART` = `DTEND` = `20261021T080000Z`, empty `DESCRIPTION`) and `900041` (`SUMMARY:Consultation hour`, same category, `DTSTART:20261021T120000Z`, `DTEND:20261021T130000Z` — a span) |
| `feedBroken` | `feedOK` plus `900090` with no `UID` line, `900091` with no `DTSTART`, `900092` with `DTEND:20261020T090000Z` before `DTSTART:20261020T100000Z`, and a last `BEGIN:VEVENT` (`900093`) never closed before `END:VCALENDAR` |
| `feedDuplicateUID` | `feedOK` with a second copy of `900008` whose `DESCRIPTION` is `Second copy.` and whose `LAST-MODIFIED` equals the first's |
| `feedInvalidUTF8` | `feedOK` with the byte `0xFF` inserted after `🎮` in `900024`'s `SUMMARY` |
| `feedHuge` | a valid calendar padded with `DESCRIPTION` text to 21 MB |

## M2. `feedChanged` — the edits

Applied to `feedOK`; every edited VEVENT also gets a new `LAST-MODIFIED`
(`20261016T120000Z`) and every `DTSTAMP` is `20261016T120712Z`.

| # | Edit | Item |
|---|---|---|
| E1 | `DTSTART` and `DTEND` `20261020T100000Z` → **`20261022T100000Z`** (Tue 20 Oct 12:00 → Thu 22 Oct 12:00) | `900008` `Submission - Sprint 3: Queuing is due` |
| E2 | **removed** | `900026` `Submission: Proposal draft is due` (Fri 4 Dec 23:59 CET) |
| E3 | **removed** | `900029` `Test Controlling endet` (Mon 14 Dec 14:20 CET — the latest item) |
| E4 | `DESCRIPTION:` (empty) → `DESCRIPTION:Fixture description 24.` | `900024` `🎮Assignment: Level Design is due` |
| E5 | `LAST-MODIFIED` only | `900020` `Test Unternehmenskultur endet` |
| E6 | **added** `900030` `SUMMARY:Quiz 2 closes`, `CATEGORIES:BIF-VZ-4-SS2026-REQEN-EN/166166`, `DTSTART` = `DTEND` = `20261105T224500Z` (Thu 5 Nov 23:45 CET), empty `DESCRIPTION`; and `900031` `SUMMARY:Quiz 3 opens`, same category, `DTSTART` = `DTEND` = `20261210T080000Z` (Thu 10 Dec 09:00 CET) — an opening with no closing |
| E7 | **removed** (aged out) | `900001` `Voting: … closes` (Sun 11 Oct — past) |
| E8 | `DESCRIPTION` → `Changed after the fact.` | `900005` (Tue 13 Oct — past) |

## M3. Answers that are not a calendar

| Case | Answer |
|---|---|
| `feedHTML` | `200`, `text/html`: `<!DOCTYPE html>` … `<title>Moodle: Log in to the site</title>` … (a 2 KB sign-in page; no `BEGIN:VCALENDAR` anywhere) |
| `feedError200` | `200`, `text/html`: Moodle's error page shape, `<title>Error</title>` … `Invalid authentication` … |
| `feed401` | `401`, empty body |
| `feed403` | `403`, `text/html` body |
| `feed404`, `feed410` | `404` / `410`, `text/html` body |
| `feed500`, `feed503`, `feed429` | the status, `text/html` body |
| `feedRedirectSameHost` | `302`, `Location: https://moodle.technikum-wien.at/calendar/export_execute.php?userid=4711&authtoken=SENTINELb0c7a1e2d3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8&preset_what=all&preset_time=recentupcoming&lang=en` → that `GET` answers `feedOK` |
| `feedRedirectTwice` | `302` to the same host, whose `GET` answers another `302` to the same host |
| `feedRedirectCrossHost` | `302`, `Location: https://login.example.invalid/sso?return=%2Fcalendar` |
| `feedRedirectHTTP` | `301`, `Location: http://moodle.technikum-wien.at/calendar/export_execute.php?…` (the same query) |
| `feedTLS`, `feedOffline`, `feedTimeout`, `feedRefused` | transport failures: an untrusted certificate (nothing sent), no path, no answer in 30 s, connection refused |

## M4. Expected results

### Connect and Import (`feedOK`)

At Mon 12 Oct 2026 06:00 (`moodleOnly`): step 2 reads `29 items, 11 Oct 2026
– 14 Dec 2026` · `25 deadlines from 10 courses and 2 other categories.` · `4
openings are shown with the deadline they belong to.` · `1 of them is
before today. It's imported once, as history, and never changed
afterwards.` · the done sentence. The Import writes 29 events; the log
line ends `vevents 29 · duplicates 0 · deadlines 25 · openings 4 · paired 4 ·
notices 0 · lookahead 63d · previewed 29 items` for the connect, then
`import moodle.technikum-wien.at/… · 29 items · 1 before today`.

### The sync table

Import `feedOK` at **Fri 16 Oct 2026 13:07 CEST** (fetch 11:07Z;
`observedLookahead` 59 d 2 h 13 min), mark `900008` done, then sync
`feedChanged` at **Fri 16 Oct 14:07 CEST** (12:07Z; proof window `[16 Oct
00:00 CEST, Sun 13 Dec 14:20Z]`):

| Item | Result |
|---|---|
| `900008` (E1) | **updated in place**: same `Event.id`, start Thu 22 Oct 12:00, **still done**; the inspector shows `Due time changed after you marked it done (was Tue 20 Oct, 12:00).` |
| `900026` (E2) | **deleted** (inside the window) |
| `900029` (E3) | **kept** (Mon 14 Dec 13:20Z is after the window's end) |
| `900024` (E4) | updated (description) |
| `900020` (E5) | nothing |
| `900030`, `900031` (E6) | created; `900030` a deadline with no opening; `900031` an **unpaired opening**, drawn on Thu 10 Dec (`components.md` §37.2) |
| `900001` (E7) | kept as history, unchanged (past) |
| `900005` (E8) | unchanged (past) |

Last-change line `Last change today 14:07: 2 added · 2 updated · 1
removed`. Log line ends `vevents 28 · duplicates 0 · deadlines 23 · openings 5 ·
paired 4 · notices 0 · lookahead 59d` (29 − E2 − E3 − E7 + E6's two). A second sync of `feedChanged` writes nothing.

### Other cases, after an Import of `feedOK`

| Case | State | Writes |
|---|---|---|
| `feedStampOnly`, `feedLF` | `upToDate` | nothing (`feed unchanged`) |
| `feedAged` at Thu 22 Oct 08:00 | `upToDate` | nothing deleted: everything missing is before today; the feed hash is stored |
| `feedEmpty` | `emptyFeed`, `emptySince` = the fetch time | nothing; a second `feedEmpty` **11 h 59 min** later: still nothing; one **12 h** later: `upToDate`, every item from today on inside the proof window deleted, history kept |
| `feedNotice` | `upToDate` | `900040` a notice (pill `info.circle.fill`, `10:00 SWQM · Guest lecture: Testing in practice`); `900041` a timed `.fixedTimed` block Wed 21 Oct 14:00–15:00 with `info.circle.fill`; the connect sheet's notices sentence counts **2** |
| `feedBroken` | `partialImport`, `4 of 33 items couldn't be read and were skipped. Nothing was removed.` | the 29 valid items; no deletion; four problem sentences per `components.md` §19.3 |
| `feedDuplicateUID` | `partialImport` (one problem: `Submission - Sprint 3: Queuing is due is listed twice with different details; one copy was used.`) | the copy whose item hash sorts lower; no deletion |
| `feedInvalidUTF8` | `partialImport` | `900024` kept, its title with U+FFFD; the problem `🎮… contains characters Kadence couldn't read.` |
| `feedHuge` | `notACalendar` | nothing |
| `feedHTML`, `feedError200` | `notACalendar`; N8 if a background sync | nothing |
| `feed401` | `unauthorized`, **paused**; N8 | nothing |
| `feed403` | `forbidden`, **paused**; N8 | nothing |
| `feed404`, `feed410` | `feedNotFound`; N8 | nothing |
| `feed500`, `feed503`, `feed429` | `serverError` (`{code}` 500 / 503 / 429) | nothing |
| `feedRedirectSameHost` | `upToDate` | as `feedOK`; **2 requests**, both to `moodle.technikum-wien.at` |
| `feedRedirectTwice` | `redirected` | nothing |
| `feedRedirectCrossHost` | `redirected`, `{otherHost}` `login.example.invalid` | nothing; **no request to that host** |
| `feedRedirectHTTP` | `redirected` (the `http:` body) | nothing; no `http` request |
| `feedTLS` | `certificate` | nothing; nothing sent |
| `feedOffline` | `offline` | nothing; no request |
| `feedTimeout`, `feedRefused` | `unreachable` | nothing |
| the Keychain item deleted before a sync | `urlMissing` | nothing; **no request** |

Every row: the recorded request carries no `Authorization` and no `Cookie`;
no log line, state or problem contains `SENTINEL`, `4711` or `authtoken`.
