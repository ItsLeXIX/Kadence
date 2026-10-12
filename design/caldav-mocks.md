# CalDAV mocks — normative request and response shapes

Design agent, 2026-10-08 (Phase 3, CalDAV amendment). This file holds the exact
requests Kadence sends and the responses `MockCalDAVTransport` and the tests'
`URLProtocol` stub serve. It is referenced from `components.md` §20.8 and §22.1.
The shapes are the **real CIS server's** (SabreDAV), as Parsa verified them on
2026-10-08, with the username replaced by **`user01`**.

CA copies each XML body below into `KadenceTests/Fixtures/CalDAV/<case>-<step>.xml`
**byte for byte**. Nothing here may contain a real username or a password. The
only password in the repo is the test sentinel `S3ntinel-pw-⚠` and the review
password `review-only-not-a-password` (`components.md` §22.1). Neither appears
in any file below.

Conventions:

- Host `cis.technikum-wien.at`, HTTPS, port 443.
- `{U}` = `user01`.
- XML bodies are UTF-8, with LF line endings in the fixture files. Whitespace
  between elements is insignificant.
- Request bodies are asserted on **meaning**: the method, the `Depth` header,
  and the set of requested properties in their namespaces. Prefixes and
  whitespace are free.
- **Authentication (every case except `certificate`):**
  - D1's `GET` is answered without a challenge, as on CIS.
  - Every other request without `Authorization` is answered `401` with
    `WWW-Authenticate: Basic realm="…"`. The realm is a placeholder: CIS's real
    realm and scheme are recorded at the first real connection (G-068).
  - Once the host has challenged within a sync, later requests of the same sync
    may carry the credential (`interactions.md` §13.1).
  - The stub records every request's host and whether it carried
    `Authorization`.

---

## 1. Discovery — `discoveryOK` (D1–D4, `components.md` §20.8.1)

### D1 — well-known

```
GET /.well-known/caldav HTTP/1.1
Host: cis.technikum-wien.at
```

```
HTTP/1.1 301 Moved Permanently
Location: https://cis.technikum-wien.at/webdav/lvplan.php/
Content-Length: 0
```

### D2 — the context URL

```
PROPFIND /webdav/lvplan.php/ HTTP/1.1
Host: cis.technikum-wien.at
Depth: 0
Content-Type: application/xml; charset=utf-8
```
```xml
<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
  <d:prop>
    <d:current-user-principal/>
    <cal:calendar-home-set/>
    <d:resourcetype/>
  </d:prop>
</d:propfind>
```

`d2-root-207.xml` — `207 Multi-Status`, `Content-Type: application/xml; charset=utf-8`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:" xmlns:s="http://sabredav.org/ns" xmlns:cal="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/">
  <d:response>
    <d:href>/webdav/lvplan.php/</d:href>
    <d:propstat>
      <d:prop>
        <d:current-user-principal>
          <d:href>/webdav/lvplan.php/principals/user01/</d:href>
        </d:current-user-principal>
        <d:resourcetype>
          <d:collection/>
        </d:resourcetype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
    <d:propstat>
      <d:prop>
        <cal:calendar-home-set/>
      </d:prop>
      <d:status>HTTP/1.1 404 Not Found</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>
```

### D3 — the principal

```
PROPFIND /webdav/lvplan.php/principals/user01/ HTTP/1.1
Depth: 0
```
```xml
<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
  <d:prop>
    <cal:calendar-home-set/>
  </d:prop>
</d:propfind>
```

`d3-principal-207.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:" xmlns:s="http://sabredav.org/ns" xmlns:cal="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/">
  <d:response>
    <d:href>/webdav/lvplan.php/principals/user01/</d:href>
    <d:propstat>
      <d:prop>
        <cal:calendar-home-set>
          <d:href>/webdav/lvplan.php/calendars/user01/</d:href>
        </cal:calendar-home-set>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>
```

### D4 — the calendar home, Depth 1

```
PROPFIND /webdav/lvplan.php/calendars/user01/ HTTP/1.1
Depth: 1
```
```xml
<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/">
  <d:prop>
    <d:resourcetype/>
    <d:displayname/>
    <cal:supported-calendar-component-set/>
    <cs:getctag/>
    <d:sync-token/>
  </d:prop>
</d:propfind>
```

`d4-home-207.xml`: three responses, as on CIS. Only the second is a calendar:

```xml
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:" xmlns:s="http://sabredav.org/ns" xmlns:cal="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/">
  <d:response>
    <d:href>/webdav/lvplan.php/calendars/user01/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype>
          <d:collection/>
        </d:resourcetype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
    <d:propstat>
      <d:prop>
        <d:displayname/>
        <cal:supported-calendar-component-set/>
        <cs:getctag/>
        <d:sync-token/>
      </d:prop>
      <d:status>HTTP/1.1 404 Not Found</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/webdav/lvplan.php/calendars/user01/LVPlan-user01/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype>
          <d:collection/>
          <cal:calendar/>
        </d:resourcetype>
        <d:displayname>LVPlan</d:displayname>
        <cal:supported-calendar-component-set>
          <cal:comp name="VEVENT"/>
          <cal:comp name="VTODO"/>
        </cal:supported-calendar-component-set>
        <cs:getctag>LVPlan-user01-1791454967</cs:getctag>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
    <d:propstat>
      <d:prop>
        <d:sync-token/>
      </d:prop>
      <d:status>HTTP/1.1 404 Not Found</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/webdav/lvplan.php/calendars/user01/outbox/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype>
          <d:collection/>
          <cal:schedule-outbox/>
        </d:resourcetype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
    <d:propstat>
      <d:prop>
        <d:displayname/>
        <cal:supported-calendar-component-set/>
        <cs:getctag/>
        <d:sync-token/>
      </d:prop>
      <d:status>HTTP/1.1 404 Not Found</d:status>
    </d:propstat>
  </d:response>
</d:multistatus>
```

Expected: one calendar, `LVPlan`, at
`/webdav/lvplan.php/calendars/user01/LVPlan-user01/`. The home and `outbox/` are
excluded. The getctag is logged, never stored.

---

## 2. Events

### F0 — `REPORT calendar-query`

```
REPORT /webdav/lvplan.php/calendars/user01/LVPlan-user01/ HTTP/1.1
Depth: 1
Content-Type: application/xml; charset=utf-8
```
```xml
<?xml version="1.0" encoding="utf-8"?>
<cal:calendar-query xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
  <d:prop>
    <d:getetag/>
    <cal:calendar-data/>
  </d:prop>
  <cal:filter>
    <cal:comp-filter name="VCALENDAR">
      <cal:comp-filter name="VEVENT">
        <cal:time-range start="20261007T220000Z"/>
      </cal:comp-filter>
    </cal:comp-filter>
  </cal:filter>
</cal:calendar-query>
```

The `start` shown is the **sync window** for today = 2026-10-08 in Vienna. The
**Import window** at the same clock is `20251007T220000Z`. There is never an
`end`. A test asserts both values at that clock, and a third at a clock after
25 Oct 2026, when Vienna is UTC+1: today = 2026-11-02 gives
`20261101T230000Z`.

### `reportCIS` — `report-cis-2026WS.xml` (tests)

Built from `fixtures/cis-2026WS-redacted.ics` with **one VEVENT per object**,
13 objects. Object *n* (1-based, in file order):

- href `/webdav/lvplan.php/calendars/user01/LVPlan-user01/obj-NN.ics` (`NN` =
  two digits)
- `getetag` `"cis-NN-a"`
- `calendar-data`: the file's lines 1–20 (`BEGIN:VCALENDAR` … `END:VTIMEZONE`),
  then VEVENT *n*'s lines exactly as in the file, then `END:VCALENDAR`

Lines are joined with CRLF, written raw (the XML parser will deliver LF,
`components.md` §20.7). None of the fixture's text needs XML escaping. If a
later fixture does, `&`, `<` and `>` are escaped. The first object in full:

```xml
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:" xmlns:s="http://sabredav.org/ns" xmlns:cal="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/">
  <d:response>
    <d:href>/webdav/lvplan.php/calendars/user01/LVPlan-user01/obj-01.ics</d:href>
    <d:propstat>
      <d:prop>
        <d:getetag>"cis-01-a"</d:getetag>
        <cal:calendar-data>BEGIN:VCALENDAR
VERSION:1.0
PRODID:FH Technikum Wien
BEGIN:VTIMEZONE
TZID:Europe/Vienna
BEGIN:DAYLIGHT
TZOFFSETFROM:+0100
RRULE:FREQ=YEARLY;BYMONTH=3;BYDAY=-1SU
DTSTART:19810329T020000
TZNAME:GMT+02:00
TZOFFSETTO:+0200
END:DAYLIGHT
BEGIN:STANDARD
TZOFFSETFROM:+0200
RRULE:FREQ=YEARLY;BYMONTH=10;BYDAY=-1SU
DTSTART:19961027T030000
TZNAME:GMT+01:00
TZOFFSETTO:+0100
END:STANDARD
END:VTIMEZONE
BEGIN:VEVENT
UID:FHBIF-5C HS_A3.15L01SWQM-ILV20260914T14300020260914T160000
SUMMARY:SWQM-ILV  HS_A3.15 - BIF-5C 
DESCRIPTION:SWQM-ILV\nL01\nBIF-5C \nHS_A3.15
LOCATION:HS_A3.15
CATEGORIES:StundenplanTW
DTSTART;TZID=Europe/Vienna:20260914T143000
DTEND;TZID=Europe/Vienna:20260914T160000
END:VEVENT
END:VCALENDAR
</cal:calendar-data>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <!-- obj-02.ics … obj-13.ics: the same shape, one VEVENT each, in file order -->
</d:multistatus>
```

Note the SUMMARY's trailing space, which is kept, as in the file. In the fixture
`obj-03.ics` and `obj-04.ics` are the two `BPREF-Info` halves (L05, L06).

**Time-range in the mock.** The mock returns an object when its VEVENT ends
after `start`, as SabreDAV does. Served for the Import window, `reportCIS`
returns all 13. Served for the sync window at 2026-10-08, it returns the 9
objects from `SWEN3-LAB` (8 Oct 14:30) on.

### `reportReview` — the review template as a `REPORT`

The rendered `cis-review.ics.template` (`components.md` §22.1) is split the same
way into `r01.ics` … `r14.ics` in row order (H1, H2, 1, 2, 3, 4, 5, 6, 7a, 7b,
8, 9, 10, 11), with `getetag` `"rev-NN-a"`. Rendered at test time, never
committed rendered.

### `reportChanged`

`reportReview` with `components.md` §22.1's `reportChanged` table applied:

*(Corrected 2026-10-10, G-072: the numbers below did not follow the row order
stated above — H1 `r01`, H2 `r02`, #1 `r03`, #2 `r04`, #3 `r05`, #4 `r06`,
#5 `r07`, #6 `r08`, #7a `r09`, #7b `r10`, #8–#11 `r11`–`r14`. They do now, and
they match what `ReviewFeed.reportChanged` built by row.)*

- `r04.ics` (#2, lecturer `L09`) keeps its href, gets a new UID and `getetag`
  `"rev-04-b"`.
- `r05.ics` (#3) is replaced by `r05b.ics` (room `EDV_F4.26`, `"rev-05b-a"`).
- `r07.ics` (#5) is absent.
- `r10.ics` (#7b) is absent.
- `r15.ics` (`KOKU-UE` `{{D+9}}`, `"rev-15-a"`) is added.
- `r01.ics` (H1) is moved to room `HS_A3.13` with a new UID. The mock does not
  return it for the sync window, and the planner ignores it if a test forces it
  in.

### `reportCISOverlap` — review dataset `fresh`, and the real-use regression tests

*(Added 2026-10-10.)* `reportCIS` plus **one object**, `obj-14.ics`
(`"cis-14-a"`), built in code from the fixture's own `BPREF-Info` VEVENT — the
fixture file is never edited:

```
UID:FHif-5WEBINAR02L07BPREF-Info20261002T19300020261002T201500
SUMMARY:BPREF-Info  WEBINAR02 - if-5
DESCRIPTION:BPREF-Info\nL07\nif-5\nWEBINAR02
LOCATION:WEBINAR02
CATEGORIES:StundenplanTW
DTSTART;TZID=Europe/Vienna:20261002T193000
DTEND;TZID=Europe/Vienna:20261002T201500
```

It is the shape Parsa's real feed has on Fri 2 Oct 2026: a second session of
the same course, in the same room, inside the first (18:35–20:15, co-taught by
`L05` and `L06`). Expected: 14 VEVENTs → **13 events**; one merge (`L05`,
`L06`); the 19:30 session is its own event, lecturer `L07`, and overlaps the
merged one by 45 min.

### `reportCISSameUID` — tests

`reportCIS` with `obj-04.ics`'s `UID` line replaced by `obj-03.ics`'s, so the
two `BPREF-Info` halves share one UID and one start and differ only in the
lecturer line. Expected (`components.md` §20.2, amended 2026-10-10): still
**12 events**, `BPREF-Info` with lecturers `[L05, L06]`, `merged 1`,
`duplicates 0`, whichever object comes first.

### Redirects that carry the header — tests

For `interactions.md` §13.1's "What the tests must prove". Each replaces one
answer of `reportOK` **after** D2's `401` has been answered, so the redirected
request carries `Authorization`, and each is delivered through
`wasRedirectedTo` (a real redirect), not as a plain `3xx` body:

| Case | Request redirected | `Location` | Expected |
|---|---|---|---|
| `redirectAuthedOffHost` | the `REPORT` (and, parameterised, D2's retry, D3, D4), with `301` / `302` / `307` / `308` | `https://login.example.invalid/caldav/` | `redirected`, `otherHost` `login.example.invalid`; **no record for that host** |
| `redirectAuthedToHTTP` | the same requests | `http://cis.technikum-wien.at/webdav/lvplan.php/` | `redirected`, the `http:` body; **no record with scheme `http`** |
| `redirectFollowedControl` | the `REPORT`, through a test-only session whose delegate allows redirects | `https://login.example.invalid/caldav/` | a record for `login.example.invalid` **with `Authorization`** — the proof that the harness would see a leak |

### `etagsOnly`

The second response is `reportReview` (or `reportCIS`) with **identical
`calendar-data`**, every href renamed (`r01.ics` → `x-r01.ics` …) and every
`getetag` suffix `-a` → `-b`. Expected: nothing written, `feedHash` equal, and
the log line's ETag set differs.

### F1 — fallback when `REPORT` is refused (`reportRefused`, `ctagOnly`)

`REPORT` → `405 Method Not Allowed` (empty body). Then:

```
PROPFIND /webdav/lvplan.php/calendars/user01/LVPlan-user01/ HTTP/1.1
Depth: 1
```
```xml
<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">
  <d:prop>
    <d:resourcetype/>
    <d:getetag/>
    <d:getcontenttype/>
    <cs:getctag/>
  </d:prop>
</d:propfind>
```

`f1-propfind-207.xml` has the collection first, then one response per object:

```xml
<?xml version="1.0" encoding="utf-8"?>
<d:multistatus xmlns:d="DAV:" xmlns:s="http://sabredav.org/ns" xmlns:cal="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/">
  <d:response>
    <d:href>/webdav/lvplan.php/calendars/user01/LVPlan-user01/</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype>
          <d:collection/>
          <cal:calendar/>
        </d:resourcetype>
        <cs:getctag>LVPlan-user01-1791454967</cs:getctag>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <d:response>
    <d:href>/webdav/lvplan.php/calendars/user01/LVPlan-user01/r01.ics</d:href>
    <d:propstat>
      <d:prop>
        <d:resourcetype/>
        <d:getetag>"rev-01-a"</d:getetag>
        <d:getcontenttype>text/calendar; charset=utf-8; component=vevent</d:getcontenttype>
      </d:prop>
      <d:status>HTTP/1.1 200 OK</d:status>
    </d:propstat>
  </d:response>
  <!-- r02.ics … r14.ics -->
</d:multistatus>
```

Then `calendar-multiget` for the member hrefs, in batches of at most 100:

```
REPORT /webdav/lvplan.php/calendars/user01/LVPlan-user01/ HTTP/1.1
Depth: 1
```
```xml
<?xml version="1.0" encoding="utf-8"?>
<cal:calendar-multiget xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
  <d:prop>
    <d:getetag/>
    <cal:calendar-data/>
  </d:prop>
  <d:href>/webdav/lvplan.php/calendars/user01/LVPlan-user01/r01.ics</d:href>
  <!-- … one d:href per member … -->
</cal:calendar-multiget>
```

The answer is a `207` with the same shape as `reportReview`, **unfiltered**.
That includes H1 and H2: the planner drops them from a sync (`components.md`
§20.1).

**`ctagOnly`** serves this path on two polls. Poll 2's `PROPFIND` differs only
in these ways:

- `getctag` is `LVPlan-user01-1791455022` (+55, as observed on CIS).
- Every `getetag` suffix is `-b`.

`calendar-multiget` content is byte-identical. Expected:

- Poll 1 writes (it is the first sync after the Import fixture).
- Poll 2 writes **nothing**: no `Event` inserted, updated or deleted, and
  `feedHash` and `lastChange*` unchanged.
- The two log lines show the two ctags.
- `fetchMode` is `multiget` on both polls, and poll 2 starts at F1: its first
  request is the `PROPFIND`, not a `REPORT`.

### F2 — `GET` per object (`multigetRefused`, `allRefused`, `overCap`)

`calendar-multiget` → `501 Not Implemented`. Then for each member href, one at
a time:

```
GET /webdav/lvplan.php/calendars/user01/LVPlan-user01/r01.ics HTTP/1.1
```
```
HTTP/1.1 200 OK
Content-Type: text/calendar; charset=utf-8
ETag: "rev-01-a"

BEGIN:VCALENDAR␍␊ … (the object's calendar-data, CRLF kept) … END:VCALENDAR␍␊
```

- **`allRefused`:** every `GET` → `405`. The result is `fetchFailed`, with the
  technical line `REPORT 405 · PROPFIND 207 · calendar-multiget 501 · GET 405`.
- **`overCap`:** F1's `PROPFIND` lists 400 members. The client sends `REPORT`
  (1), `PROPFIND` (2), `calendar-multiget` (3) and `GET` ×297, then stops before
  request 301. The result is `fetchFailed`, nothing is written, and the
  technical line is `Request cap reached (300) reading LVPlan one object at a
  time`.

---

## 3. Failures

| Case | Request answered | Response |
|---|---|---|
| `unauthorized` | D2 and every later request, with or without `Authorization` | `401`, `WWW-Authenticate: Basic realm="…"`, empty body |
| `forbidden` | D2, after `Authorization` | `403 Forbidden`, empty body |
| `wellKnown404` | D1 | `404 Not Found`, `Content-Type: text/html`, a short HTML body |
| `propfindNot207` | D2 | `200 OK`, `Content-Type: text/html`, `html-login.html` |
| `noCalendars` | D4 | `207` with the home and `outbox/` responses of `d4-home-207.xml` only |
| `calendarGone` | F0 | `404 Not Found`. Then D1–D4 again, D4 = `noCalendars`'s body |
| `calendarMoved` | F0 | `301`, `Location: https://cis.technikum-wien.at/webdav/lvplan.php/calendars/user01/LVPlan-user01-ws26/`. Then D1–D4 again; D4 lists `LVPlan` at that href. Then F0 there → `reportReview` |
| `htmlOK` | F0 | `200 OK`, `Content-Type: text/html; charset=utf-8`, `html-login.html` |
| `emptyCalendar` | F0 | `207` with `<d:multistatus …/>` and no `response` |
| `serverError` | F0 | `503 Service Unavailable` |
| `timeout` | F0 | no answer; the injected timeout fires |
| `offline` | any | `URLError(.notConnectedToInternet)` before sending |
| `certificate` | D1 | `URLError(.serverCertificateUntrusted)`. **The stub must record zero requests delivered**: the TLS failure happens before the request line is written |
| `redirectOffHost` | D1 | `301`, `Location: https://login.example.invalid/caldav/`. The stub asserts **no request to `login.example.invalid`** |
| `redirectToHTTP` | D1 | `301`, `Location: http://cis.technikum-wien.at/webdav/lvplan.php/`. The stub asserts **no `http:` request** |
| `slow` | F0 | `reportReview` after 3 s (review only) |

### `multiCalendar` — `d4-home-multi-207.xml`

`d4-home-207.xml` plus three responses:

| href | resourcetype | displayname | components | Listed? |
|---|---|---|---|---|
| `…/calendars/user01/Pruefungen-user01/` | collection + `cal:calendar` | `Prüfungen` | VEVENT | **yes**, checked |
| `…/calendars/user01/Aufgaben-user01/` | collection + `cal:calendar` | `Aufgaben` | VTODO only | no |
| `…/calendars/user01/inbox/` | collection + `cal:schedule-inbox` | — | — | no |

`Prüfungen`'s `REPORT` returns one object: `RW-EXAM`, identical to the template's
#11. Expected:

- The checklist shows `LVPlan` and `Prüfungen`, both checked, in D4's order.
- The step-2 count is still **13**: the duplicate `RW-EXAM` merges across the
  two calendars (`components.md` §20.2).
- Unchecking `Prüfungen` leaves 13.
- Unchecking `LVPlan` gives `1 event, …`.
- Unchecking both disables `Import`.

---

## 4. What every transport test asserts (all cases)

1. **No request ever goes to a host other than `cis.technikum-wien.at`**, and
   none over `http:`.
2. **`Authorization` is never on the first request of a sync.** It is sent only
   after a `401` from `cis.technikum-wien.at`, and never to any other host.
3. **The sentinel password never appears outside the `Authorization` header**:
   not in any URL, request body, error, `stateDetail`, problem line, captured
   source-logger line, or `description`/`debugDescription`/`dump` output. The
   header itself appears only in the stub's own record.
4. **Request count per poll** is as `components.md` §20.8.2's table gives it:
   - `reportOK`: 1 for a sync with cached discovery, 5 for `Connect` (4 + 1).
   - `reportRefused`: 3.
   - `multigetRefused`: 3 + n.
   - `calendarMoved`: 1 + 4 + 1.

   A `401` retry is not counted.
5. **Requests are sequential**: the stub never sees two in flight.
