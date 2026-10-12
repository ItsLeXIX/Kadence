# Phase 3 slice 1 — review: the CIS timetable as a CalDAV account

Design agent, 2026-10-10. Reviewed: all 35 frames in `screenshots/3/` (opened
one by one), `screenshots/3/INDEX.md`, STATUS §100–§120, DEVIATIONS "Phase 3
slice 1", GAPS G-053 onward, the Swift source and tests of the transport, the
session, the derivation, the planner, the source views and review mode, and
Parsa's first real connection of 9 Oct 2026.

**NOT YET — FIXES REQUIRED**

The 21 review items are mostly sound: 12 are accepted, 7 accepted with a note
(five of them to be recaptured), 2 rejected. The slice is not accepted because of what the
review set could not show. Five blockers: review mode writes into the real
store; a source is looked up by its colour; the redirect rule that makes the
hand-built `Authorization` header safe is not proven by any test; a co-taught
lecture can lose a lecturer before the merge sees it; and two overlapping
lectures of one source draw as one block. Nothing in the security reading
found a leak — the gap is in the proof, not in the code.

A previous review session was interrupted. It left **nothing** in `design/`:
no `PHASE3-REVIEW.md` existed, and every design file but `GAPS.md` was last
written on 8 Oct at 12:44, before the build ended (`GAPS.md`'s later change is
CA's G-069…G-074). This review starts from the files as CA left them.

---

## 1. Per-item verdicts (§22 items 1–21)

Evidence rules: `components.md` §17.2 rules 1–6. Edge check (rule 6): 34
frames clean, item 16 under the preview exemption — confirmed by eye on item
16 (a complete border on all four sides of the canvas, nothing accent
elsewhere in the band).

| # | Item | Verdict | Spec § | File(s) | What is drawn |
|---|---|---|---|---|---|
| 1 | Sidebar, first run | **ACCEPT WITH NOTE** | layouts §2.1 | `sidebar-first-run-p3.png` | `Connect Timetable…` is the last Sources row, accent, no swatch. But the frame is the Phase 2 dataset: eight sources, one of them a mock `University timetable`, above a link offering to connect a timetable. It is not what a first run looks like. New item 22 replaces it as evidence (fix 2) |
| 2 | Step 1 empty / filled | **ACCEPT** | layouts §12.1 | `connect-step1-empty-p3.png`, `-filled-p3.png` | `Server` prefilled, focus in `Username`, `Connect` disabled; `user01`, bullets, `Connect` enabled; footnote names the host |
| 3 | Connecting | **ACCEPT** | layouts §12.1 | `connect-step1-connecting-p3.png` | Fields disabled, spinner, `Connecting to cis.technikum-wien.at…`, `Cancel` enabled |
| 4 | Failures | **ACCEPT** | layouts §12.1; components §19.1 | `connect-step1-unauthorized-p3.png`, `-certificate-p3.png`, `-nocaldav-p3.png`, `-webdav-hint-p3.png` | Exact titles and step-1 bodies; `Password` focused with contents selected; focus on `Connect`; `Server` focused and selected; the share message under `Server`, `Connect` disabled, footnote in its "server you enter" form |
| 5 | Step 2, one calendar | **ACCEPT** | layouts §12.2 | `connect-step2-single-p3.png` | `✓ LVPlan` as a row, not a control; `13 events, 2 Oct 2026 – 23 Oct 2026`; history `2`; co-taught `1` |
| 6 | Step 2, several | **ACCEPT** | layouts §12.2 | `connect-step2-checklist-p3.png` | `Calendars`, `LVPlan` and `Prüfungen` checked; nothing else listed |
| 7 | Edit mode | **ACCEPT WITH NOTE** | layouts §12.3 | `connect-edit-p3.png` | Title `Edit University timetable`, prefilled, `Saved in Keychain`, focus in `Password`. The system's `Passwords…` AutoFill suggestion covers part of the footnote — ruled in §4.2: system chrome, kept |
| 8 | Settings ▸ Sources | **ACCEPT WITH NOTE** | layouts §11 | `settings-sources-uptodate-p3.png`, `settings-sources-empty-p3.png` | Copy and layout right. `Sync Now` is drawn accent-filled: it is the window's default button, which §11 does not ask for (small fix 10b; recapture). Empty state right |
| 9 | Sidebar row, four states | **ACCEPT** | components §19.2 | `sidebar-row-states-p3.png` (render), `sidebar-live-p3.png` | Spinner, empty slot, secondary glyph, alert glyph; checkboxes in one column. Live: the alert glyph on the timetable row |
| 10 | Source popover | **ACCEPT WITH NOTE** | components §19.3 | `source-popover-forbidden-p3.png`, `source-popover-partial-details-p3.png` (render) | Title, body, `Edit Account…` default. Status line reads `Never synced` (§4.3; fix 9). The render's sentences are CA's G-069 placeholders, replaced by this review — retired by rule 2, recapture (fix 8) |
| 11 | Week `M` | **REJECT** | components §18.2, §3.3, §3.4 | `week-M-p3.png`, `day-inno3-online-p3.png` | Drawn right: the lectures, `REQEN-EXAM` with the cap, Friday's lecture as one conflicted block. Wrong: that block is an **unnamed blue rectangle** for the uncovered hour above `Training` (A35, now required — fix 6); `INNO3-EL` does not read `Online` in the frame the item names — every lecture's meta is `University timetabl…` (fix 7). The Day frame carries a toolbar focus ring the item did not ask for (rule 4; fix 10c) |
| 12 | After the second sync | **REJECT** (evidence) | components §22.1 | `week-M-after-change-p3.png`, `source-popover-last-change-p3.png` | `EPC-ILV` is gone and the popover reads `Last change just now: 2 added · 2 updated · 2 removed`. But the frame filed for "`SWEN3-LAB` in `EDV_F4.26`" shows no room anywhere (rule 1). The tests prove the room; the frame does not. Shown by fix 7's meta line; recapture |
| 13 | Inspector, `SWQM-ILV` | **ACCEPT** | layouts §6.1 | `inspector-imported-p3.png` | Read-only line; `Lecturer L01`, `Group BIF-5C`, `Room HS_A3.15`; Source with swatch and `Synced 20:01`; no Description; `Done` / `Skip` |
| 14 | Inspector, `INNO3-EL` | **ACCEPT** | layouts §6.1 | `inspector-lecturers-collapsed-p3.png`, `-expanded-p3.png` | `L10`, `L11`, `L12`, `and 19 more`; all 22 and `Show fewer`; `Online · WEBINAR01` |
| 15 | A refused edit | **ACCEPT** | interactions §13.4 | `inspector-refusal-emphasis-p3.png` | The read-only line visibly brighter than in item 13's frame |
| 16 | Conflict panel | **ACCEPT WITH NOTE** | components §14, §22.1 | `conflict-lecture-training-p3.png` | Three options, row 1 recommended and previewed, the border, `9 of 15`, overlap line. The header names `SWRM-ILV`; on the grid it is still the unnamed block (fix 6; recapture) |
| 17 | Popover, imported NEXT | **ACCEPT WITH NOTE** | components §18.3, §19.4 | `popover-imported-next-p3.png`, `popover-stale-line-p3.png` (renders), `popover-live-p3.png` | `Done` · `Open`, no `Snooze`; the stale line. The live frame is the late `Breakfast` with `Re-offer` — it evidences the live chrome only, which is all rule 3 asks of it (§4.6) |
| 18 | Removal alert | **ACCEPT** | interactions §13.2 | `remove-source-alert-p3.png` | Exact copy with `13`, `Cancel` default, `Remove` destructive |
| 19 | All-day pill + done | **ACCEPT** | components §5.1, §6 | `allday-and-done-light-p3.png`, `-dark-p3.png` | Graphite pill with `calendar`; the done lecture's label, check and meta all readable in both appearances. Measured: §2, G-074 |
| 20 | Cancelled | **ACCEPT** | components §6, §20.6 | `cancelled-block-p3.png`, `inspector-cancelled-p3.png` (renders) | Dashed, `xmark.circle`, `Cancelled · University timetable`; `Cancelled by University timetable`, `Done` / `Skip` disabled |
| 21 | Calendar missing | **ACCEPT WITH NOTE** | components §19.1, §19.3 | `source-popover-calendar-missing-p3.png` | Title, body, `Choose Calendar…` default. `Never synced` under "Events from the last sync are kept" contradicts itself (§4.3; fix 9; recapture) |

**Provenance note.** INDEX.md says the set was captured on 8 Oct, 19:50–20:06.
Six files are dated 9 Oct 21:59–22:00 (the five renders and the re-cropped
live popover), and two renders show 9 Oct clock times (`Last synced today
21:49`, `Synced 9 Oct 21:59`). The build is the same commit, so rule 2 holds,
but INDEX.md must say when each group was made (fix 11).

---

## 2. Gaps and deviations the build opened

| Entry | Ruling | Where it is written |
|---|---|---|
| **G-069** unreadable-event wording | **Closed.** One exact sentence and technical line per problem: no identifier, ends before it starts, no readable start time, couldn't be read, too large, the `THISANDFUTURE` override | components §19.3 "The sentences" |
| **G-070 / D6** UID length | **Closed. 185.** CA counted right; the spec was wrong in three places | components §20.2, §22.1; PHASE3-PLAN task 3 |
| **G-071 / D7** Import window | **Closed. One calendar year back**, as built. The formula ("− 366 days") was wrong; the pinned value was right | components §20.8.2; PHASE3-PLAN judgement 1 |
| **G-072** object numbers | **Closed.** My file contradicted itself; numbers now follow row order (`r04`, `r05`→`r05b`, `r07`, `r10`) | caldav-mocks "`reportChanged`" |
| **G-073 / B42** `Statistik übung` | **Closed; B42 accepted.** Detached in `phase3` seeding, review only. Adding it to the template would change item 5's `13` everywhere for nothing | components §22.1 |
| **G-074** done meta line | **Closed.** Measured: `text.onSolid` at 0.8 on the done-blended solid fill is **1.65:1 light / 2.44:1 dark** worst. Every text element of a done block on a solid-fill kind is `text.primary`: **9.00 / 6.17** worst (9.19 / 6.24 on blue; the frames' fills sample `#A1BEE8` / `#3F5A83`, equal to the computed blend). CA's placeholder is the rule. **No token value changes**; 1.7.0 records the measurement | components §6; tokens `$measured_1_7_0` |
| **A37** `⌘⌥N` | **Deferred**, still normative. It is event creation, not the timetable; all-day events render since §5.1; no slice 1 item depends on it | interactions §2 |
| **A38** Edit ▸ Delete | **Required now** (small fix 10a). §2 has always said every shortcut is a menu item; `⌫` had none. The item is added and disabled for an imported selection | interactions §2, §13.4 |
| **B40** header built by Kadence | **Accepted, with required tests** — §3 below | components §21.4; interactions §13.1 |
| **B41** `-KadenceReview phase2` | **Accepted**, and superseded in part: review mode gets its own store and two more datasets (`empty`, `fresh`) | components §22.1 |
| **B43** mock accepts any password | **Accepted.** Review only; tests keep the check on; the captures type a filler and show bullets | components §22.1 (unchanged) |
| Note: `ConflictEngine` gains a clock | **Accepted**; it is §20.9 as written | — |
| Note: mock `forbidden` answers every authenticated request | **Accepted** | — |
| Note: `-KadenceAppearance` | **Accepted** as review tooling | — |
| **B44** `⌫` never deleted | Found and fixed by CA; nothing to rule | — |
| **G-061** scheduling details | Recorded by CA (STATUS §111); closed as recorded | GAPS |

---

## 3. Security check — B40

**Result: the code is safe as read; one of the three properties is proven by
a test, two are not. The missing proof is BLOCKER fix 3.**

What the code does (`HTTPTransport.swift`, `CalDAVSession.swift`,
`CalDAVDiscovery.swift`, `CalDAVClient.swift`):

- The transport's delegate answers **every** `willPerformHTTPRedirection`
  with `nil`. No redirect is followed by Foundation, so Foundation never gets
  the chance to copy the header onto a new request.
- `CalDAVSession.send` refuses any URL that is not the source's host, port
  and `https` **before** sending. It is the only caller of the transport.
- `ChallengeResponder` returns no header for another host, another port,
  `http:`, or an unknown scheme.
- The header is added only after a `401` from the request's own URL, or on
  later requests of the same session once that has happened.
- Server trust keeps default evaluation; password challenges are declined.

| | Property | Proven by a test? |
|---|---|---|
| (a) | A cross-host redirect is refused and no request carrying the header reaches the other host | **No.** `redirectOffHost` is tested only at D1, which is sent before any `401`, so no header exists to leak. And the stub never redirects: `StubURLProtocol` returns the `301` through `didReceive response`, so `URLSession`'s redirect machinery never runs and the delegate is never consulted — `redirectNotFollowed` would pass with the delegate method deleted. Its second half calls the delegate method by hand, which shows what it returns, not that it is called. No test redirects a request that carries `Authorization` |
| (b) | An `https` → `http` redirect is refused | **No**, for the same two reasons. Proven only in pieces: `ChallengeResponder` declines `http:` (`challengeScope`), and D1's `redirectToHTTP` maps to `redirected` with one recorded request |
| (c) | The header is never sent before the host's `401` | **Yes.** `discoveryOK` asserts request 0 and 1 carry none and request 2 is the retry of the `401`; `wireRulesHold()` asserts on every recorded request, in every discovery and client test, that the first request carries none and the first that does repeats the path just answered `401`; `reportOK` shows a sync starts unauthenticated (two `REPORT`s: the `401` and its retry) |

Field evidence, not a test: Parsa's real connection got through D1, where CIS
answers `301`. Had Foundation followed it, D1 would not have seen a redirect
and discovery would have ended `noCalDAV`. So the delegate is consulted in
the real app.

**Required** (written into `interactions.md` §13.1 "What the tests must
prove" and `caldav-mocks.md` "Redirects that carry the header"): a stub that
redirects through `wasRedirectedTo`; authorised requests (`REPORT`, D2's
retry, D3, D4) redirected cross-host and to `http:`, with no record for the
target; `CalDAVSession.send` refusing an off-host URL with nothing recorded;
and a **control** — the same redirect through a session that allows it must
record the other host *with* the header, or the tests above prove nothing.

Also ruled: a `3xx` to another host or `http:` at D2–D4 ends `redirected`,
not `noCalDAV` (interactions §13.1). And one defect outside CIS's path, in
Digest (A39, deferred): later requests reuse the first nonce with a fixed
`nc`.

---

## 4. Observations CA reported

1. **`INNO3-EL` `Online` cut off at Week width — a defect in the spec, fixed
   (G-079).** It is not one block: in `week-M-p3.png` every lecture's meta
   line is `University timetabl…` and none shows its room. §3.4 let the source
   win and the location truncate, written when source names were short. The
   line is now `Location · Source`, the source truncates
   (`components.md` §3.4). Small fix 7. **This reverses a Phase 1 rule — for
   Parsa to confirm.**
2. **The system `Passwords…` AutoFill suggestion — accepted, kept.** It is
   what macOS shows under a focused, empty `SecureField` whose content type
   is `.password`, and it can fill the field from the user's own Passwords.
   Removing it would mean dropping the content type the spec asks for. Not a
   rule 4 violation: the item asks for focus in `Password`, and this follows.
3. **`Never synced` in the calendar-missing (and forbidden) popover —
   a review-seeding artefact, and a small spec fix.** A real source is created
   by an Import that read the server. The status line now falls back to
   `importedAt`, and the review source is seeded as imported
   (`components.md` §19.3, §22.1). Fix 9.
4. **The sidebar row speaks its state as label, not value — accepted.** The
   row is exposed as its checkbox, whose value must stay on/off. Spoken the
   same (`components.md` §19.2, amended).
5. **A leftover toolbar focus ring in the Day frame — a small fix, not only a
   capture artefact.** With keyboard navigation on, `⌘3` left key focus on a
   toolbar button. The toolbar is not a focus stop (DECISIONS 2026-09-10) and
   a view change must leave focus in the grid (`interactions.md` §1). Fix 10c
   verifies and fixes; the frame is recaptured.
6. **The live popover shows the Phase 2 dataset's late `Breakfast` —
   accepted.** Rule 3 asks the live frame for chrome only. It will not recur:
   live frames move to the in-memory review store.
7. **A35, Friday's covered `SWRM-ILV` title — pulled in. Required now.**
   Reasons in `components.md` §3.3 (amended 2026-10-10): in Phase 3 the
   covered block is the lecture, and the same rule is what the real overlap
   bug needs. BLOCKER fix 6.

Also seen in the frames and not reported: `Sync Now` as Settings' default
button (fix 10b); item 12's room not visible (fix 7); item 1 not a first run
(fix 2); the source popover opens with a focus ring on `Settings…` beside the
default button — accepted, the popover takes focus on open (§19.3) and `↩`
still triggers the default.

---

## 5. G-068 — the real server (Parsa, 9 Oct 2026)

Recorded in `GAPS.md` G-068, closed.

| | |
|---|---|
| Connect sheet | `91 events, 22 Sep 2026 – 29 Jan 2027`; 21 before today |
| 23:20:37 | `mode report · requests 1 · 1798 ms · objects 70 · time-range honoured · ctag — · etags 70 (set 29fa316d) · nothing to write` |
| 23:23:19 | `mode report · requests 1 · 1921 ms · objects 70 · time-range honoured · ctag — · etags 70 (set 29fa316d) · feed unchanged` |

**Findings.** `REPORT calendar-query` works; no fallback. The sync time-range
is honoured (70 = 91 − 21). ETags are stable across two requests although the
getctag is the request time. One `REPORT` takes 1.8–1.9 s. The `401` is
`Basic`; realm not recorded. The first sync after an Import says `nothing to
write` because the feed hash moves from the Import's window to the sync's; the
second says `feed unchanged`. Both are §20.8.4 working.

**Rulings.**

- **Limited history — a contradiction with §20.1, resolved.** The server
  returned nothing before 22 Sep although the semester began 14 Sep and a
  year was requested. The Import writes "the earlier weeks the server still
  serves". No behaviour changes; because a sync never deletes the past,
  Kadence keeps what CIS stops serving. One rule had to change: a calendar
  deselection must not delete history older than the server's horizon (G-080;
  fix 9). Not reachable on CIS, which has one calendar.
- **The export is not the CalDAV feed.** They differ in range, and in at least
  one lecture's lecturers (§6.3). The fixture stays the parser's reference.
- **The log command** is subsystem-scoped everywhere it is documented:
  `log show --last 1h --info --predicate 'subsystem == "XIX.Kadence" AND category == "sync"'`
  (`components.md` §20.8.4, `GAPS.md` G-068, `PHASE3-PLAN.md`). STATUS §120
  carries the old form; that file is not mine to edit.
- **`ctag —` in report mode is acceptable and correct.** A `REPORT` returns no
  collection property; recording one would cost a second request per poll for
  a value known to be the time of the request.
- **Defaults stand.** One request under 2 s every 30 minutes. `get` mode is
  unreachable on CIS. Stable ETags would allow a cheaper poll; not proposed.

---

## 6. Real-use findings (Parsa's store, week 28 Sep – 4 Oct 2026)

Causes were found in the code and confirmed against a **read-only copy** of
the app's store, taken into this session's scratch directory and deleted at
the end of the review. It holds lecture data, never the password.

What the store held on 9 Oct: **9 sources** — the eight Phase 2 mock sources
(`local`) and one `caldav` source on slot `graphite` — the Phase 2 mock
events, the mock routine template with its 65 materialised occurrences, 4
windows, and 91 imported lectures. **It was not a store containing only the
CIS import.** That one fact explains three of the six findings.

### 6.1 Imported events attributed to `Personal` — BLOCKER

**Cause.** Two faults that needed each other. (1) Every view resolves an
event's source **by palette slot**: `SourceCatalog.name(for: event.sourceKey)`
in `BlockModels.swift`, the swatch and Source row in `InspectorView.swift`,
the hidden set in `CalendarState.hiddenSources`. (2) The new source was given
`graphite`: `Source.firstUnusedPaletteKey` falls back to it when every slot is
used, and the eight mock sources used all eight. `Personal` is `graphite`
too, and sorts before `University timetable`, so every lookup returned
`Personal`. On a clean store the source would have been `blue` and the fault
invisible — which is why no review frame shows it — but the lookup is wrong
on any store where two sources share a slot, and the spec's own fallback
makes that legitimate.

**Ruling.** A source is its record, found by `Event.sourceID`; never its
colour. A connected source never takes `graphite`. Visibility is
`Source.isVisible` (`components.md` §21.1, §21.1.1). Fix 2.

### 6.2 `University timetable` twice; the static source rows — BLOCKER

**Cause.** The first row is the Phase 2 dataset's mock `local` source, the
second the real one. The mock rows were in the real store because **review
mode seeds the real store file**: the capture and check scripts delete
`~/Library/Containers/XIX.Kadence/…/default.store` and relaunch with
`-KadenceReview`, and review seeding writes into that same file. The store file was
created at 22:09 on 9 Oct, during CA's last script run (INDEX.md is dated
22:00, STATUS 22:12), and Parsa connected on top of it at about 23:15. A normal launch does seed nothing —
G-057 is built — but it inherits whatever a review launch left.

**Ruling on the static rows.** A real store lists exactly two built-in local
sources, `Personal` and `Daily routine`, because this build can create events
for both; then the connected sources, once each. `Exams`, `Mail
appointments`, `Coursework`, `Social`, `Planned study` are fixtures of phases
not built and appear only in review datasets (`components.md` §21.1.1;
`layouts.md` §2.1). **And review mode gets its own in-memory store; no script
touches the real one** (`components.md` §22.1). Fixes 1 and 2. The same
scripts would have deleted Parsa's real data — done and skipped marks — the
next time anyone ran them, which is why this is the first fix.

### 6.3 The co-teaching merge lost a lecturer — BLOCKER

**What the store shows.** `BPREF-Info` Fri 2 Oct 18:35–20:15 is one event
with `lecturers = [GuenthMi]`. The 19:30–20:15 session is a separate event
with a different lecturer.

**Cause — one certain defect, one open question.** The merge is correct when
two VEVENTs with different UIDs arrive: that is the fixture's shape, and it
is tested from the file and from the `REPORT` form. The one path in the build
that drops a lecturer is `FeedDerivation.derive` step 1, the exact-duplicate
rule: two VEVENTs with the **same UID and the same start** are reduced to "the
later one" *before* the merge runs, uncounted. §20.2 said so; the defect is in
the spec. If the real feed gives the two halves one UID — the redacted
export's UIDs carry the lecturer, but the export and the CalDAV feed already
differ (§5) — this is exactly what happened. If instead CalDAV serves only one
VEVENT for that lecture, the second lecturer never reached Kadence. Neither
the store nor the log can tell these apart: the line has no VEVENT or merge
count.

**Ruling.** A tie is not a duplicate: when neither VEVENT wins on `SEQUENCE`
or a stamp, both go to the merge and their lecturers are unioned
(`components.md` §20.2). The log line gains `vevents`, `duplicates`, `merged`,
and the connect sheet's fetch is logged (§20.8.4). Fix 4. Parsa's next sync
then answers the open question in one line.

### 6.4 Overlapping imported events render as one block — BLOCKER

**Cause.** The layout engine did what §3.3 says. At that window width a
two-block cluster's slot is under 72pt, so it cascades: the 18:35 block full
width, the 19:30 block on top, indented 22pt. The lower block's *visible
width* is then 22pt, so it draws `.glyphOnly` (the build measures the
narrowest strip — A35, deferred in Phase 2), and the upper block draws its
own glyph and title: two glyphs, one title in the lower part. Both are
`.fixedTimed` blocks of one source — same fill, no rail, no border — and
`DayLayoutEngine.cascadeFrames` draws no gap between cascaded blocks, so
nothing marks where one ends and the other begins.

**Ruling.** Two things, both in `components.md` §3.3: the title-band rule is
required now (the 18:35 block keeps `BPREF-Info` in its uncovered 55 minutes),
and a covering block is separated from what it covers by 2pt of canvas on its
leading and top edges. Where the slot is ≥ 72pt they pack, as before. Fix 6.

### 6.5 `Needs attention` 16 — not what it looked like

**What they are.** Fifteen day conflicts and one template conflict: 13 mock
`Fixture call` / `Client call` / `Supervisor meeting` pairs and the mock
template conflict — the Phase 2 dataset's own 14 — plus two real lectures
against the *mock* routine: `Training` × `RW-ILV` (Wed 14 Oct, 40 min) and
`Morning review` × `INNO3-EL` (Wed 21 Oct, 30 min). **None is imported
against imported.** The two `BPREF-Info` sessions are not among them: the
engine only pairs a routine occurrence with a manual or imported event, and
2 Oct is history, which never conflicts.

**Cause.** The contaminated store (§6.2). On a clean store the count after
the Import is 0, and the row is hidden.

**Ruling.** Two imported events never conflict, from one source or two: a
conflict's options edit only the routine side, and Kadence can offer nothing
for two lectures the university double-booked. They are drawn by §3.3 and not
counted (`components.md` §20.9, stated). No code change; a test pins it
(fix 5).

### 6.6 A history event offers Done / Skip — correct

**Ruling.** History keeps `Done` and `Skip`. "The past is never written"
binds the sync and every automatic writer; it does not bind the user. A
lecture is normally marked after it happened, by which time it is history.
Written into `components.md` §18.1 and `layouts.md` §6.1. No change.

---

## 7. Triage

### BLOCKER (5)

| | Issue | Why it blocks | Fix |
|---|---|---|---|
| B-1 | Review mode seeds, and scripts delete, the real store (G-076) | Wrong behaviour and a data-loss path for real use | 1 |
| B-2 | Source resolved by palette slot; `graphite` given to a connected source; fixture sources in the real sidebar (G-075) | Wrong behaviour: imported events shown as `Personal` | 2 |
| B-3 | B40's redirect safety is not proven by a test: (a) and (b) | Security: the brief's own bar | 3 |
| B-4 | A tie on UID + start drops a VEVENT before the merge (G-077) | Wrong behaviour: a co-taught lecture loses a lecturer | 4 |
| B-5 | Overlapping same-source lectures read as one block; a covered lecture has no title (G-048 / A35, G-078) | Wrong behaviour in the slice's main view; item 11 rejected | 6 |

### SMALL FIX (10)

| | Issue | Fix |
|---|---|---|
| S-1 | Meta line order: `Location · Source` (G-079) | 7 |
| S-2 | G-069 sentences replace the placeholders; G-074's `// SPEC-GAP` mark removed; tokens regenerated at 1.7.0 | 8 |
| S-3 | Status line falls back to `importedAt`; review source seeded as imported | 9 |
| S-4 | Deselection never deletes beyond the server's horizon (G-080) | 9 |
| S-5 | A `3xx` off-host or to `http:` at D2–D4 ends `redirected` | 3 |
| S-6 | Log: subsystem documented, three new fields, `connect` and `import` lines | 4 |
| S-7 | Edit ▸ Delete (A38) | 10 |
| S-8 | Settings' `Sync Now` is not the default button | 10 |
| S-9 | Focus stays in the grid after `⌘1` `⌘2` `⌘3` with keyboard navigation on | 10 |
| S-10 | A test that two imported events never conflict and a fresh import counts 0; INDEX.md states when each frame group was captured | 5, 11 |

### DEFERRED (3 new or re-ruled; 2 unchanged)

| | Issue | Reason |
|---|---|---|
| A37 | `⌘⌥N`, new all-day event | Event creation, not the timetable; nothing in slice 1 depends on it. Still normative |
| A39 (new) | Digest auth across several requests reuses the first nonce with a fixed `nc` | CIS uses Basic; not on Parsa's path. Rule recorded in GAPS |
| A40 (new) | `↩` on a focused connected sidebar row not observed live | Three other paths open the popover; verify with the next sidebar task |
| A33, A34 | Phase 2's deferrals | Unchanged |

**A35 is no longer deferred** (B-5).

---

## 8. FIX LIST for CA — dependency order

Common rules as in `PHASE3-PLAN.md`: tests with `-only-testing:KadenceTests`;
no test, script or capture contacts the university server or holds a real
password; the only passwords in the repo are the sentinel and the review
password; `generate-tokens --check` clean at **1.7.0**. The real-use
regression tests are built from `fixtures/cis-2026WS-redacted.ics` (its
byte-for-byte test-bundle copy), through `reportCIS`, `reportCISOverlap` and
`reportCISSameUID` (`caldav-mocks.md` §2) — objects added or changed **in
code**; the fixture file is never edited.

**1. Review mode gets its own store; no script touches the real one.**
Spec: `components.md` §22.1 "Review mode never touches the real store".
- A launch with `-KadenceReview <dataset>` uses an in-memory `ModelContainer`
  and the in-memory secret store. Datasets `phase2`, `phase3`, `empty`,
  `fresh`.
- Remove every `rm` of `default.store` from `Scripts/`.
- Acceptance: a test builds the app's container for a review launch and for a
  normal launch and asserts the review one is in-memory and that the real
  store's URL is never opened; a test that a normal launch on an empty store
  inserts exactly the two built-in sources and no `Event`, `RoutineTemplate`
  or `TimeWindow`; `grep -rn "default.store" Scripts` returns nothing; the
  six UI scripts PASS on the in-memory store.
- Frames: none of its own (every live frame below depends on it).

**2. A source is its record: identity by id, built-in sources, palette,
visibility.** Spec: `components.md` §21.1, §21.1.1; `layouts.md` §2.1, §6.1;
`tokens.json` `sourcePalette.assignmentRule`.
- Resolve name, symbol, hue and visibility through `Event.sourceID` →
  `Source`; `.manual` / `.routine` events without one resolve to `personal` /
  `routine`. Remove every `MockData.sources` read from production code and
  `CalendarState.hiddenSources`; the checkbox writes `Source.isVisible`.
- A connected source never takes `graphite`.
- Acceptance (regression, from the fixture): import `reportCIS` into a store
  that holds the two built-ins **and a second source deliberately placed on
  the timetable's slot**; every imported `GridBlockModel` has the timetable's
  name and slot; the inspector model's title swatch and Source row are the
  timetable's symbol (`tablecells.fill`), never `person.fill`; the `.full`
  meta line contains `University timetable` and never `Personal`. Import into
  a store whose seven non-graphite slots are all used: the new source's slot
  is not `graphite`. Unchecking `Personal` hides no imported event, and
  survives a relaunch. Sidebar rows on `fresh`: `Personal`, `Daily routine`,
  `University timetable` — three, in that order.
- Frames: §22 items **22**, **23**, **25** (new); recapture **1** as item 22.

**3. Prove the redirect rule (B40), and `redirected` at every step.** Spec:
`interactions.md` §13.1 "What the tests must prove" (tests 1–7);
`caldav-mocks.md` "Redirects that carry the header"; `components.md` §21.4.
- Acceptance: the seven tests, including the control that **must** record a
  request to `login.example.invalid` carrying `Authorization` when the
  delegate allows the redirect. `redirectNotFollowed` is rewritten on the
  redirecting stub. A `3xx` off-host or to `http:` at D2, D3, D4 → `redirected`.
- No code change is expected in the transport or the session. If any of
  tests 2–4 fails, stop and report: that is a live leak.
- Frames: none.

**4. A tie is not a duplicate; the log says what it merged.** Spec:
`components.md` §20.2 (exact duplicates, amended), §20.8.4 (amended);
`caldav-mocks.md` `reportCISSameUID`.
- Acceptance (regression, from the fixture): `reportCIS` → 12 events,
  `BPREF-Info` 2 Oct 18:35 with `[L05, L06]` (exists; keep). **New:**
  `reportCISSameUID` → 12 events, `BPREF-Info` `[L05, L06]`, `merged 1`,
  `duplicates 0`, in both object orders; the same pair with a higher
  `SEQUENCE` on one → that one's lecturers only, `duplicates 1`; a tie with
  different summaries → two events. Import then sync of `reportCISSameUID`
  writes nothing the second time. The log line carries `vevents`,
  `duplicates`, `merged`; a `connect` line and an `import` line are written;
  none contains the sentinel. The inspector model for the merged event lists
  both lecturers under `Lecturers`.
- Frames: item **25**.

**5. Two imported events never conflict.** Spec: `components.md` §20.9.
- Acceptance (regression, from the fixture): import `reportCISOverlap` on
  `fresh` with the clock at 2026-10-01 10:00 (so 2 Oct is not history): 13
  events, the two `BPREF-Info` sessions overlap 45 min, `ConflictEngine.detect`
  returns none, the needs-attention count is 0 and the row is hidden. With a
  routine block added over 19:00–20:00 that day, exactly two conflicts, each
  routine × one session.
- Frames: item **23** (no Needs attention row).

**6. A covered block keeps its title, and a covering block has a gap.** Spec:
`components.md` §3.3 (both 2026-10-10 amendments; the 2026-10-06 title-band
rule); `layouts.md` §3.3. Depends on 2 (the blocks must be the right hue).
- Acceptance (regression, from the fixture): lay out Fri 2 Oct of
  `reportCISOverlap` at a 124pt column and `size.hourHeightWeek`: two blocks,
  cascade; block 0's content set is `.titleOnly` with title `BPREF-Info`
  (its title band is unobstructed at full width); block 1 has a 2pt canvas
  gap on its leading and top edges and block 0's drawn area does not reach
  into it. At a 400pt Day column: packed, two slots, both `.full` or their
  height tier. A render test samples the gap's pixels as `surface.canvas`.
  Phase 2's `conflict-panel-two-options` case: Wednesday's `Training` draws
  its title.
- Frames: item **24** (Week and Day); recapture **11** (`week-M`, Friday's
  `SWRM-ILV` named) and **16**.

**7. The meta line is `Location · Source`.** Spec: `components.md` §3.4
(amended 2026-10-10). **Build after Parsa confirms** (§9).
- Acceptance: at a 124pt Week column a `.full` lecture's meta starts with its
  room, whole, and ends with a truncated source name; `Online` for an online
  event; with no location, the source name alone; the source is dropped whole
  when fewer than 4 of its characters fit. Hover help and VoiceOver unchanged.
- Frames: item **26**; recapture **11** and **12** (`week-M-after-change`
  shows `EDV_F4.26`); `day-inno3-online-p3.png` is then no longer needed
  beside Week `M`, keep or drop it and say so in INDEX.md.

**8. Copy and tokens.** Spec: `components.md` §19.3 "The sentences", §6
(G-074); `tokens.json` 1.7.0.
- Acceptance: exact-string tests for every row of the sentence table from
  `malformed-partial.ics`, `truncated.ics` and `edge-cases.ics`; no
  `// SPEC-GAP G-069` or `G-074` left; tokens regenerated, `--check` clean at
  1.7.0 (the version pin test updated); a done `.fixedTimed` block's time and
  meta resolve to `text.primary`.
- Frames: recapture **10**'s partial-details render.

**9. Status line and the deselection horizon.** Spec: `components.md` §19.3
(amended), §20.1 (step 2, amended), §22.1 (review source seeded as imported).
- Acceptance: a source with `importedAt` set and no later success reads
  `Last synced {importedAt}` in every state, never `Never synced`. Review
  `phase3` seeding performs an Import. Deselection: with a store holding a
  kept calendar's event older than the earliest event of the Import-window
  fetch, `Save` keeps it and the step-2 count excludes it; an event inside
  the horizon and absent is deleted as before.
- Frames: recapture **10** (forbidden) and **21**.

**10. Three small things.**
- a. **Edit ▸ Delete** (`interactions.md` §2, §13.4): present, `⌫`, enabled
  for a deletable selection, disabled for none and for an imported event. A
  menu-model test.
- b. **Settings' `Sync Now`** is `.bordered` and not the default action
  (`layouts.md` §11). `↩` in `Name` commits the name and does not sync.
- c. **Focus after `⌘1` `⌘2` `⌘3`** stays in the grid with keyboard
  navigation on (`interactions.md` §1; DECISIONS 2026-09-10). AX check: the
  focused element after `⌘3` is not a toolbar button.
- Frames: recapture **8**; the Day frame, if kept, without the ring.

**11. Recapture the listed frames and update `screenshots/3/INDEX.md`.**
New items 22–27; recaptured 1 (as 22), 8, 10 (both), 11, 12, 16, 21. Every
live frame from the in-memory review store, one build, fresh launch per
item. INDEX.md states the build, the dataset per item, and the date and time
of each group of frames, renders included. Run the edge check on the whole
set and the secret grep of STATUS §120 again.

---

## 9. For Parsa

1. **Your store is the Phase 2 mock dataset with your timetable on top.**
   Do not judge the slice by it, and do not run any `Scripts/*` until fix 1
   lands (they delete it). When fix 1 and 2 are in: Settings ▸ Sources ▸
   `Remove Source…` (this deletes the Keychain item), quit, delete
   `~/Library/Containers/XIX.Kadence/Data/Library/Application Support/default.store*`,
   launch, connect again. That is your act; no agent deletes your store.
2. **Confirm G-079** — the room before the source on a block's meta line. It
   reverses a Phase 1 priority. Fix 7 waits for your word; everything else
   does not.
3. **At your next real sync after fix 4**, read the log line and note
   `vevents`, `duplicates`, `merged`, and whether `BPREF-Info` Fri 2 Oct now
   lists both lecturers. If `vevents` equals `objects` and `merged` is 0 for
   that week, CIS's CalDAV does not serve the second lecturer and there is
   nothing more to fix. Apple Calendar on the same account shows the same
   thing: two entries at 18:35 there means two VEVENTs.
4. **Log A39 and A40** in DEVIATIONS if you agree with the deferrals (text in
   GAPS, "Deferred by this review"), and mark D6, D7, B40–B43, A38 as ruled.
5. **STATUS §120** still documents the unscoped `log show` command. The right
   one is in §5 above.

## 10. Judgement calls in this review

1. **A35 pulled in as a blocker**, not kept deferred: the covered block is
   now the lecture, and the same rule fixes the real overlap.
2. **A cascade gap of `size.blockColumnGap` in `surface.canvas`** rather than
   a border or a new token: it is the separation packed blocks already have.
3. **Two built-in local sources in a real store.** They are the app's
   taxonomy, not fixtures; without them manual and routine events have no
   sidebar row and cannot be hidden.
4. **`graphite` reserved for `Personal`**; when seven slots are used a new
   source reuses the least-used hue, which identity by id makes safe.
5. **A UID + start tie goes to the merge** instead of "later wins": it
   cannot lose data, and identical VEVENTs still collapse to one event.
6. **B42 kept as built** (the detached `Statistik übung`), with a review-only
   resolution by slot, rather than changing item 5's numbers.
7. **The deselection horizon** — the earliest event start of a fully read
   Import-window fetch — as the bound on what a deselection may delete.
8. **Item 12 rejected on evidence only**: the behaviour is tested and right;
   the frame cannot show what it is filed under.
9. **I read a copy of the real store** to find the causes, because the brief's
   premise (a store holding only the CIS import) could not be told from the
   code alone and turned out to be false. Read-only, lecture data only,
   deleted afterwards.
10. **Spec edits are dated 2026-10-10** (today); the proposed DECISIONS
    entries use the same date.
