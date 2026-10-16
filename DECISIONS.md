## 2026-09-09 — Event.colorTag replaced with Event.sourceKey.
components.md §1 makes hue mean source and nothing else. A free-form
colour tag would have been a second, conflicting hue channel on the same
block. Colour identity is derived from the source, never set per event.

## 2026-09-09 — Kind glyphs and source symbols are separate vocabularies.
Kind glyphs depict the activity; source symbols depict the origin — the
container, feed or party the data came from. So planned study's source
symbol is `sparkles` (the planner that produced it), not a study glyph.

An earlier symbol table reused block kind glyphs (`repeat`,
`building.columns`, `graduationcap`, `calendar`, `pencil.and.outline`).
That is SUPERSEDED and must not be implemented: `repeat` would have meant
both "this is a routine block" and "this came from the routine source" in
the same window, teaching that a block's glyph means its source — which
§1's channel separation depends on being false.

Normative for future kinds: check §2.1, §3.2 and §5 before adding one; no
symbol appears in both vocabularies. No second human-figure symbol in
either table (`person.fill` and `figure.walk` are already near-adjacent).

## 2026-09-09 — Cascade threshold 96 → 72; blockCascadeIndentMin deleted.
The threshold answers "how wide must a block be to beat being hidden",
not "how wide is comfortable". 72 = 28pt fixed chrome + 44pt title
(~7 characters — enough to tell *Coffee* from *Code review*).

At 96, Week cascaded even two-block overlaps at any realistic window
width; column packing effectively never fired. At 72, 2-up packs and 3-up
cascades on a typical column.

Riders: a covered block whose *visible* width drops below 44pt renders
glyph-only regardless of height tier (so `resolveBlockStyle` takes visible
width as a second input); cascaded blocks stay at elevation.level0 — do
not "fix" cascade with a shadow.

blockCascadeIndentMin was deleted because the spec's two figures could not
both hold. Closes G-006 and G-009.

## 2026-09-09 — KadenceUITests stays at Swift 5 and is excluded from test runs.
It contains only Apple's template, whose XCTestCase overrides are
nonisolated and throw 11 isolation errors under Swift 6. Its runner cannot
start in this environment ("Timed out while enabling automation mode").

Run tests with `-only-testing:KadenceTests`. A red plain `test` is that
target, not a real failure. Do not "fix" it by converting it.

## 2026-09-09 — A20b (VoiceOver label order) closed as won't-fix for Phase 1.
Blocks reach the AX tree (A20, fixed) but carry only the §3.4 hover-help
string; the explicit accessibilityLabel is discarded. Six configurations
measured against the running app:

| Configuration | In tree | §11 label |
|---|---|---|
| `.ignore` + label | 0 | — |
| `.ignore` + label + `.isButton` | 0 | — |
| `.combine` + `.isButton` | 20 | discarded |
| real Button + `.plain` + label | 20 | discarded |
| real Button, content `.accessibilityHidden` | 0 | — |
| `.accessibilityRepresentation` | 0 | — |

Decisive: `.accessibilityIdentifier` lands on the same element one line
above the label; the label does not. Modifiers reach the element; the
label specifically is dropped. Anything that *synthesizes* a replacement
AX element gets dropped in this hierarchy (ZStack-with-offsets inside
ScrollView inside NavigationSplitView); only elements derived from real
rendered content survive.

Rejected: reshaping block content (changes the busiest component) and
NSViewRepresentable (leaves SwiftUI for the densest view). Information is
reachable via AXHelp. check-accessibility.sh keeps warning — do not
silence it. Revisit in Phase 2 when the menu bar extra gives a second
hierarchy to compare.

Untested: whether the Button wrapper was drag-neutral. It was reverted, so
this was never established.

## 2026-09-09 — Undo is an explicit inverse-command stack, not ModelContext.undoManager.
Correction to the record: undo was never one step deep — it was zero.
EventStore read `context.undoManager`, nothing ever assigned one, the
container was built without undo support, so every beginUndoGrouping and
setActionName was a no-op against nil.

ModelContext.undoManager rejected: it groups per property registration,
which is the wrong grain for "these three edits are one user action", and
it cannot survive the identity change that undoing a delete forces.

Kadence/State/UndoStack.swift: depth 50, full redo branch, named actions
in the Edit menu. `EventStore.transaction("name") { … }` records
everything inside as one step; `perform` is re-entrant, so composite
operations call the ordinary verbs (store.move, store.toggleSkipped) and
they join the open group rather than pushing their own steps. Outermost
name wins.

Two load-bearing constraints: events are addressed by `id` and resolved at
execution time — no closure may hold an `Event` reference, because undoing
a delete returns a new object with the same id. And a replay guard is
required, since undo closures call back into the recording paths and would
otherwise push fresh steps so the stack never empties.

## 2026-09-09 — Process rules learned in Phase 1.
Screenshot review is the only real check on spec-vs-implementation.
Four of eleven findings in the first review were the design agent's own
spec being wrong (travel band destroying the meta line below it; window
labels specified into the time gutter where they collided with 13:00; the
conflict badge and trailing time both claiming the trailing-top corner
with no rule; "every covered block keeps a rail and glyph" — false,
`.fixedTimed` has no rail). None were findable on paper.

Agents ran in parallel three times. It worked each time by luck —
`--check` caught a mid-build tokens.json revision. design/ is frozen for
the duration of a build session (CONTEXT.md).

An agent reporting a gap "closed" is a claim to verify. G-004 was reported
closed and existed only in chat; §10.1 still specified no symbols.


## 2026-09-10 — Routine instances edit instance-only, no dialog.
The template is the baseline, today is the exception. Apple's "this event /
all future" prompt taxes the most frequent interaction in the app. Templates
change only in the template editor. An edited instance is pinned and
re-materialisation leaves it alone.

Detachment is NOT a block signal — every channel is spent. It appears in the
inspector for the selected block, and as a count in the template editor
("3 instances edited this week") with a re-sync action. Detachment matters
when reasoning about the routine, never when reading Tuesday. Re-sync must
be one undo step.

## 2026-09-10 — Conflict resolution previews in place, not in a sheet.
BRIEF-PRODUCT says "sheet with a preview of the resulting day". Rejected: a
miniature grid inside a modal is a second visual vocabulary competing with
the one §1 exists to protect, and a worse preview than the real thing.

Non-modal panel (inspector), sidebar list as entry point. Focusing an option
animates the real grid via interactions.md §7.1 with affected blocks
outlined. ⎋ reverts, ↩ applies, ⌘Z undoes. Zero new components.

Conditions: the panel must survive the user wandering off — spec whether
pending state persists or is cleanly abandoned. Previewed blocks must never
look committed.

## 2026-09-10 — Menu bar requirement split between status item and popover.
"Legible from across the room" is not achievable in a 22pt bar at ~13pt caps.
Status item is for arm's length: ~180pt budget (~18 chars), `17:30 · Training`,
time first and NEVER truncated (the time is what you scan for), title
truncates, degrades to time only. No icon in the normal state.

Popover carries "across the room": next item 20pt+, rest of today secondary.

Late state uses semantic.now red — that colour already means "now" and
lateness is a fact about the clock, not a failure. Phrased as elapsed
("started 12 min ago"), NEVER as deficit ("overdue", "missed"), and always
carries the re-offer action.

## 2026-09-10 — Snooze confirmation is designed in Phase 2, not Phase 4.
Same argument as the six block variants: surfaces get designed as a set, and
an inert button in a shipped popover quietly never gets finished. The design
exemption covers surfaces, not the services behind them — no snooze
scheduling logic in Phase 2.

## 2026-09-10 — Cursor time stays in the time gutter; §1 wins over §7.
components.md §7 says the gutter carries hour labels and the now time and
nothing else; interactions.md §1 puts the cursor time there. §1 wins —
suppression of a colliding hour label uses the same 12pt rule as the now
time. §7 to be amended in the Phase 2 pass.

## 2026-09-10 — The toolbar is not a ⇥ focus stop.
SwiftUI toolbar items aren't addressable as a focus region without a phantom
item; macOS reaches the toolbar through Full Keyboard Access. §1 to be
amended. A test asserts the omission is deliberate so it can't become a
silent oversight.

## 2026-09-10 — Dragging the split view divider counts as an explicit choice.
CalendarState.isSidebarVisible is the single owner; the split view's
columnVisibility is derived through a write-back binding. All four paths
(menu, toolbar, width auto-collapse, divider) move the same value, and the
§1.1 rule "auto-collapse never overwrites an explicit choice" lives only in
setSidebarVisible(_:isUserAction:). A divider drag counts as explicit —
otherwise the next window resize re-opens a sidebar the user just closed.

## 2026-09-10 — New events are drafts in state, never rows in the store.
The old flow inserted on ⌘N and deleted on cancel, so every abandoned
creation left a permanent untitled event (A13). An EventDraft now lives in
CalendarState — laid out, packed, cascaded and editable like a block, but
never in SwiftData. EventStore.commit is the only path that persists one and
refuses an unusable title. §3's rule is true by construction, not by cleanup.
A launch sweep repairs stores written by the older build.

Blur commits a non-empty title; ⎋ and empty-title abandon.

Found by this work: commit and duplicate inserted twice — UndoStack.perform
runs its redo closure immediately AND both wrote directly, producing two rows
with the same id. Pre-existing and invisible. It surfaced only because these
tests run against a real in-memory ModelContainer; a stubbed store would have
passed. Tests that touch persistence use a real container.
 ## 2026-10-01 — The Routines window's seven columns are read-outs, not placement surfaces.
A RoutineBlock is a time of day on the template's weekday set; it is not on a column. 
The window never said so, so a block created on an inactive column was silently relocated 
onto the active days (fixed by hand in 5b73949, never specced).
Ruled: a create gesture on an inactive column is refused, with the reason standing before
the gesture (recessed hour lines, no header underline, a pinned Not in this routine note) 
and the remedy one click away in the same column (Add Sat). Auto-adding was rejected because 
activating a weekday adds every block in the template — the cheapest, most mis-aimed gesture 
must not carry the widest change. A prompt was rejected as the same modal tax DECISIONS.md 2026-09-10 already refused.
Riders: a block drag here is vertical only, so a block cannot move between columns at all; 
the drop preview draws in every active column at once, which is the clearest statement the 
window can make about what it is editing. The inactive column's ground stays color.surface.canvas 
— canvasSunken measures 1.01:1 against color.window.protectedFill in light appearance and would 
delete a protected window from the column it was meant to explain. All of this is Blocks mode 
only; TimeWindow.weekdays is its own set. Closes G-018, G-013.

## 2026-10-01 — Conflict options: the catalogue is three, and the recommendation is a preservation rule.
G-017 reported the engine structurally cannot produce three options or recommend a non-first one,
and proposed either an engine change or relaxing the spec. Neither was needed in full: makeOptions
gates shorten behind flexibility == .fixed, and no spec ever asked it to. Ungating it is the third source,
and it is the brief's own example triple.
Catalogue: shiftLater (.shiftable, within ±), shorten (any flexibility, remainder ≥ 15 min), skipToday (always).
This also fixes an unfiled defect: .droppable conflicts were offering exactly one option.
Display order stays ascending by disturbance. The recommendation is not the disturbance minimum:
a proportionate shift (≤ the occurrence's own duration), else a shorten keeping ≥ half, else skip.
Disturbance-minutes is blind to what kind of thing is spent — trimming 20 minutes off a 45-minute
session is not the same currency as moving it 20 minutes. §14.3's "usually but not necessarily first"
is now reachable by a named fixture.
shiftEarlier is excluded at day level (almost always the cheapest option and almost never the achievable
one) and included at template level, where the user is editing the week deliberately. The ± in the model
stays two-sided for Phase 6. Closes G-017.

## 2026-10-01 — Protected windows: materialisation refuses. Surfacing a conflict afterwards is not compliance.
CONTEXT.md's rule is "never scheduled into automatically". If after-the-fact surfacing satisfied it,
the rule would have no content — every violation could be excused by a badge, and Phase 6's "validate
and reject the plan rather than trusting the model to have obeyed" would be arguing with Phase 2.
materialize creates nothing for a pair that strictly overlaps a .protected span. It does not trim and
does not shift: both are an automatic process choosing a time. Only .protected is a hard constraint.
Manual placement is untouched — interactions.md §4 binds automatic placement, not a user being explicit.
The refusal is never silent: conflicted on the template block in the colliding columns, a Will not run —
inside Sleep (protected) on … inspector line, and the needs-attention count. Activating it opens the
Routines window, because none of its options can be applied to a day. Closes G-023, G-024.

## 2026-10-01 — Detachment is four fields; deletion is a tombstone; the past is never written.
DECISIONS.md 2026-09-10 said an edited instance is pinned and never defined "edited". Ruled: exactly the
four template-owned fields detach (start, end, title, flexibility). status does not — done and skipped are
facts about a day, and if skipped detached, every .skipToday conflict resolution would detach and Re-sync
would offer to undo the user's own resolutions.
Found by this work: deleting a materialised instance was unhandled. materialize's existence check finds nothing
and recreates it, so a deleted routine block comes back on its own — the same class of silent behaviour as the
weekday defect, in a path nobody had looked at. Deletion now leaves a tombstone keyed by the existing (sourceID,
externalID); ⌘Z restores both.
Re-materialisation updates untouched instances rather than only creating, or the template is not the baseline it
claims to be. Withdrawal deletes future non-detached instances and keeps detached ones. Materialisation never
writes to any day before startOfDay(today) — the one rule in §13.6 with no exception. Closes G-019, G-020, G-021.

## 2026-10-05 — Detachment is one field with three values; a released instance rejoins as detached.
`Event.routineLink`: linked / detached / released. A boolean cannot hold
§13.6.4: once withdrawal clears it, the kept instance is indistinguishable
from an untouched future instance of a withdrawn pair, and the next pass
deletes it.

When the template produces a released instance's pair again (weekday
re-added, block delete undone, window no longer refusing), it becomes
detached — edits kept, counted, re-syncable — and the template never creates
a second instance beside it. The rejoin is folded into the causing undo step
and is never written to the past.

Rejected: staying released, because "No longer part of Gym routine" would
then be false. Closes G-033.

## 2026-10-05 — Conflict copy counts in minutes, always.
`75 min later`, `all 90 min kept`, `135 min lost`. Line 2 is the ranking made
legible, and a ranking is read by comparing numbers; `1 h 15` beside `45 min`
makes the reader convert. The `N h MM` sentence in §14.3.4 was a generic rule
in the one place it doesn't fit. Closes G-035.

## 2026-10-05 — No text on solid accent in multi-line rows.
A selected conflict option is a tinted card (`selectedCardFill`) with a 2pt
focus-ring border carrying selection; the text keeps its normal colours.
Solid `selectedRowFill` measured 1.41:1 for line 2 and 3.81:1 for the title.
The Recommended chip is line 3, as §14.3 always said, so titles are never
truncated. Closes G-038.

## 2026-10-05 — The live status item is template-rendered; colour is not a carrier in the menu bar.
macOS draws a MenuBarExtra label in the bar's own tint and flattens it to one
image and one string. The late state is carried by the glyph and `… ago`, the
empty state by its words. `semantic.now` applies in the popover. Do not force
non-template rendering.

## 2026-10-05 — Review evidence rules.
A capture shows its subject in the viewport, from the build under review,
with nothing selected that the item didn't ask for. Offscreen renders of the
real view are accepted for layout and copy when the spec pins inputs a live
surface can't be set to, plus one live capture per surface. Review fixtures
must not depend on the weekday or the clock; §17.1 states the expected
needs-attention count (14).

## 2026-10-05 — A conflict is opened on its recommendation, in view, in one list.
Activation — the row, ⌘⇧A, ‹ ›, or the advance after ↩ — scrolls the
conflict into view and focuses the recommended option, which previews. The
`1 of N` footer is required: N is the needs-attention count, one order for
both kinds, no wrap. ↩ never opens the other window by itself.

## 2026-10-05 — Deferred out of Phase 2, still normative.
§7's scrolled-past window-label pinning, and §16's block-move transition in
an open main window at the moment of a popover snooze. Neither affects Phase
2's definition of done; both are logged as DEVIATIONS A-entries.

## 2026-10-06 — No region focus rings; focus is drawn on the element.
macOS 26 draws a region's system ring around a hosting rect that reaches the window's edge, so it showed as one accent edge in the main window and as a hairline round the Routines window and the menu-bar popover. A drawn ring was rejected: around the canvas it would be the same accent frame as the preview border, which means "you are looking at a hypothetical". Every region already shows focus on the element: the time cursor or selection ring, the focused option card, the toggle's inset stroke, a control's own ring, the popover's hover overlay (NEXT included). That table is normative; a focused region that shows none of these is a defect. Closes G-039.

## 2026-10-06 — A snooze never lands in protected time.
The user asks for later, not for where, so the destination is chosen automatically and the hard rule applies. The +15 placeholder gains the same refusal materialisation has, not a search: if the destination strictly overlaps a protected span, nothing is written and the popover says `Not moved — 00:05 is inside Sleep (protected)`. Phase 4's real rule replaces the +15 and must keep this guarantee. Closes G-046; G-016 stays open.

## 2026-10-06 — A window label is never crossed by a block, in either mode.
Windows mode drew labels above the dimmed blocks wherever the window started, which put Errands' border through `Low energy`. Above is not the same as legible. Both modes now use the same column scan; Windows mode differs only in never omitting a label, because there the windows are what is being edited. Closes G-044.

## 2026-10-06 — The default scroll is a time of day, and the Routines window has one.
`firstEventStart` is the earliest start time-of-day of any event that starts on a visible day: the scroll offset is shared by every column, so the question is how early anything in view begins. The Routines window applies the same rule to its template's blocks and stops opening on seven hours of Sleep. Closes G-042, G-047.

## 2026-10-06 — Deferred out of Phase 2, still normative: a covered block's title band.
A block covered from below its title row keeps its title (title band ≥ 44pt visible → `.titleOnly` content set in that band). It changes cascade rendering in every view and needs its own captures; no Phase 2 definition-of-done item depends on it. Logged as A35 (G-048). A33 and A34 stay deferred.

## 2026-10-07 — A hard-rule refusal is never truncated.
The refused snooze row cut off at `Sleep (protect…`: the sentence needs ~290pt and the popover gives 276. A window label is the user's own text, so no one-line copy can be guaranteed to fit. The row breaks after `is inside` and puts the window on its own line (`Sleep (protected)` / `a protected window`), wrapping further if needed and growing the row; nothing in it is ever elided. The moved row stays one line. Closes G-051.

## 2026-10-07 — A focus stroke takes its colour from the fill it sits on.
`focusRing` equals `accent`, so the focused stroke on an ON weekday toggle was invisible, and ⇥ enters the row on an ON toggle. On an accent fill the stroke is `focusRingOnAccent` (the letter's colour, 4.56 / 6.93 : 1); elsewhere it stays `focusRing` (4.05 / 6.40 : 1 on the off fill). Never the system focus colour on accent, which follows the accent. Closes G-049.

## 2026-10-07 — The Routines canvas has a cursor, as an indicator only.
Interactions §1 makes a focused region that shows nothing a defect, so the missing cursor isn't deferrable. In Phase 2 it is one accent line across all seven columns with its gutter time, moved by ↑ ↓ only. It creates nothing: keyboard creation of a template block stays unspecified. Closes G-050 and A36 once built.

## 2026-10-07 — The default scroll lands on a whole hour.
`min(07:00, firstEventStart − 1h)` is rounded down to the hour in every view, so a 07:15 first event opens at 06:00, not 06:15. The viewport then starts on a labelled hour line, and rounding down only adds lead. Closes G-052.

## 2026-10-08 — Phase 2 accepted.
Routines and materialisation (with protected-window refusal, re-materialisation, withdrawal, tombstones, detachment and Re-sync), conflict detection with 2–3 ranked options and one-step undo, the TimeWindow editor, and the menu bar status item and popover with snooze are built and reviewed (PHASE2-REVIEW.md "Final — 2026-10-07"). Deferred, still normative: A33 (§16 block-move transition on popover snooze), A34 (§7 scrolled-past label pinning), A35 / G-048 (a covered block's title band). Open gaps carried forward: G-016 (snooze destination, Phase 4), G-003 (contrast checker in the token generator).

## 2026-10-08 — The preview border is the edge check's one exemption.
A frame's outer 2px band may not contain the accent colour: that is how the G-039 region ring showed, so the check is the evidence form of "focus is drawn on the element". §14.4's preview border is accent and follows the canvas, which reaches the window edge, so every preview frame tripped it. Exempt it only where it can be told apart: an item that asks for a preview, a complete 2pt rectangle on all four sides of the canvas including the side away from the window edge, and nothing accent in the band outside it. A one-edge line still fails. Closes G-053.

## 2026-10-08 — The timetable is a CalDAV account; the password is the secret, and nothing is saved until Import.
CIS serves the timetable over CalDAV (SabreDAV) at https://cis.technikum-wien.at/webdav/lvplan.php/, reachable without VPN, exactly as Apple Calendar uses it; the WebDAV file share /Webdav/Lvplan only answers inside the FH network and is out of scope (G-065). Kadence connects with server, username and password, discovers through /.well-known/caldav → current-user-principal → calendar-home-set → the calendar list, and reads events with REPORT calendar-query, falling back to multiget or GET only if REPORT is refused. The username and server are shown (`if23b139 @ cis.technikum-wien.at`); the password lives in one Keychain internet-password item per source, is sent only over HTTPS to that host and only in answer to its 401 challenge, never across a redirect to another host, never logged, never in a fixture or screenshot. A certificate failure stops before anything is sent, with no "connect anyway". Connect discovers and previews; nothing — Keychain item, Source, event — is written until Import. Agents never contact the server; the first real connection is Parsa's.

## 2026-10-08 — Change is detected by content, not by the server's markers.
The CIS server has no sync-token, and its getctag is the time of the request (verified 2026-10-08: two requests 55 s apart differed by 55), so it changes even when nothing did. Every poll fetches the calendar with one REPORT and compares a normalised hash of each merged event and of the whole feed; unchanged content writes nothing. ctag and ETags are recorded as diagnostics only. Discovery is cached and re-run only when the calendar URL answers 404 or moves.

## 2026-10-08 — Imported events are read-only except their status, and every refusal shows.
Upstream fields belong to the sync. Done and skipped are facts about the user's day and stay local; a sync never writes them, except that an upstream time change resets them. Every other edit is refused with the system sound and the inspector's always-visible "Read-only — from University timetable" line emphasised; Edit ▸ Delete is disabled; the popover drops Snooze and Re-offer for an imported item. No alert, no silent no-op.

## 2026-10-08 — The Import writes the semester once; a sync deletes only on proof of absence and never writes the past.
The Import writes every event in the feed, the semester's earlier weeks included as history, and deletes nothing. Every later sync writes only events starting on or after today, with no upper cap, and never creates, updates or deletes one before — the past is a record from the first sync on, and history never conflicts. The Import may reach back because at that moment the source has nothing local to overwrite. An event is removed only when a fully read feed no longer contains it; a failed fetch, a feed with unreadable events, or a feed that is suddenly empty deletes nothing and says so. Deselecting a calendar or removing the source does delete, history included — that is the user saying so. Two syncs of the same content write nothing the second time.

## 2026-10-08 — CIS events are identified by their content, and co-taught duplicates are one event.
The CIS UID is built from group, room, lecturers, course, start and end, so it changes with any of them and co-teachers get one UID each. A UID that contains its own start time is therefore ignored for identity: the event is keyed by summary, location, start and end. A lecturer change updates in place; a room or time change arrives as a removal and an addition, so done or skipped marks do not carry over and no heuristic tries to; a routine block moved for the old slot stays where it is. VEVENTs with the same key merge into one event with their lecturers combined, so a co-taught lecture is one block, not two that collide; it survives a co-teacher being added or removed. A four-line description is read as course, lecturers, group and room: the title is the course code, -EXAM shows the exam glyph and every other suffix the lecture one, WEBINAR rooms read Online.

## 2026-10-08 — A 401 or 403 pauses automatic sync.
Repeated failed sign-ins can lock a university account, so after a 401 or 403 Kadence makes no further attempt on its own until the password is edited or the user presses Sync Now. No CalDAV found, no calendar, not a calendar, a cross-host redirect and a certificate failure are shown as needing action but do not pause. Transient failures retry at the normal interval, never faster. Offline is a state, not an error.

## 2026-10-08 — A lecture CIS removes is deleted and counted; a cancelled one from any source stays, marked.
CIS never sends STATUS:CANCELLED: a cancelled lecture vanishes from the feed. It is deleted at the next fully read sync, and the source's last-change line ("Last change today 14:02: 1 removed") records it, so a removal is never silent. For sources that do send STATUS:CANCELLED the occurrence is kept, drawn dimmed and dashed with xmark.circle and Cancelled, takes no part in conflicts, is never next-up, and refuses done/skipped.

## 2026-10-08 — A removed lecture leaves no ghost, for now.
G-067 is deferred by Parsa: a future lecture CIS removes is deleted and counted in the last-change line, with no "Removed" ghost. Revisit after a few weeks of real use; if a missed cancellation causes a wasted trip, the ghost comes back as a design task.

## 2026-10-08 — Sync state lives with the source, not in the status item.
The sidebar row carries a status slot (spinner, or a sync-error glyph — alert colour when the user must act), the row opens a source popover with exact copy, and Settings ▸ Sources shows the same block. The status item stays "the next thing" only. The popover gains one line, only when a source needs action or has not synced in max(24 h, 2 × interval), because "what now" drawn from a stalled timetable should say so. Source errors are not counted in Needs attention: that count means conflicts.

## 2026-10-08 — Sources become records; all-day events get a variant.
Phase 3 adds a Source model: server URL, username, principal and calendar-home hrefs, the selected calendars (href, display name), discovered capabilities, feed hash, import time, last-change counts, pause flag, state and problems — never the password. Event gains isCancelled, importedDescription, lecturers, courseCode, group, isOnline, importKind and link. There is no SourceFile; the exact shape is components §21. ScheduleSource returns the parsed feed with its problems; the planner applies the Import or sync window. Floating and unknown time zones are read in the Mac's current zone. All-day Events — never drawn until now, manual ones included — render as .eventAllDay: solid fill, the timed sibling's glyph, no chip. Closes G-055 and G-056.

## 2026-10-08 — A done block on a solid fill keeps a readable label.
The done label in `text.secondary` measures 3.06–3.32:1 on a blended solid fill. On `.fixedTimed`, `.examAllDay` and `.eventAllDay` it is `text.primary`. Closes G-054.

## 2026-10-08 — Phase 3 defaults, confirmed by Parsa.
Default poll interval 30 minutes, range 15 minutes to 1 day. Import covers the whole semester the feed contains — no fixed week cap; the first import includes the semester's earlier weeks as read-only history, and after that syncs never write the past. Times are shown in the Mac's current time zone; TZID times are converted, and floating or unknown times are read in the Mac's current time zone. A fresh real store starts empty; fixture data is seeded only in review mode (G-057). G-056 is resolved: a redacted real export is at fixtures/cis-2026WS-redacted.ics.

## 2026-10-08 — Phase 3 amendment readings, confirmed by Parsa.
The three readings in PHASE3-PLAN.md are confirmed: discovery re-runs on an explicit Connect in edit mode, and automatic syncs re-run it only on 404 or a move; after this host's first 401 in a sync, later requests in that same sync may carry the password, and every sync starts without it; deselecting a calendar compares against a full Import-window read of the calendars that stay and may remove past events only that calendar contributed. The 6-hour polling floor when only GET works is kept. The CIS server accepted HTTP Basic auth via curl on 2026-10-08; the rest of G-068 is recorded at Parsa's first real connection.

## 2026-10-10 — Review mode has its own store.
Parsa's first real connection ran on the Phase 2 mock dataset: review launches seeded the real store file, and the check scripts deleted it. A launch with -KadenceReview now uses an in-memory store and the in-memory secret store, and never opens the real one; no script deletes or writes the real store. A normal launch seeds nothing but the two built-in sources. Closes G-076.

## 2026-10-10 — A source is its record, never its colour.
Imported lectures were shown as Personal because the build looked a source up by palette slot and the timetable had been given graphite. An event's source is the Source its sourceID names; name, symbol, hue and visibility come from that record. A connected source never takes graphite. A real store has two built-in local sources, Personal and Daily routine, and no fixture ones; the other five arrive with the phases that can create their events. Closes G-075.

## 2026-10-10 — Kadence builds the Authorization header, so no redirect is ever followed.
DEVIATIONS B40 is accepted: the password answers the host's 401 as a header Kadence builds, and Foundation is given no credential. Foundation copies a manually set header onto a redirected request, so "the transport never follows a redirect" becomes a security invariant with required tests: a real redirect of a request that carries the header, cross-host and to http, must leave no request at the target, and a control must show the harness would see one. A redirect to another host or to http ends in "redirected" at every step.

## 2026-10-10 — A tie is not a duplicate.
Two VEVENTs with the same UID and start were reduced to the later one before the co-teaching merge, which lost a lecturer on real data. When neither wins on SEQUENCE or a stamp, both go to the merge and their lecturers are combined. The sync log line gains vevents, duplicates and merged. Closes G-077.

## 2026-10-10 — Two imported events never conflict.
A conflict is a routine occurrence against an imported or manual event, and its options edit only the routine side. Two lectures the university scheduled on top of each other are drawn side by side or cascaded and are not counted in Needs attention.

## 2026-10-10 — A covered block keeps its title, and a covering block has a gap.
A35 is no longer deferred: in Phase 3 the covered block is the lecture. A block whose title band is uncovered draws its title there, and a block drawn on top of another is separated from it by 2pt of canvas on its leading and top edges, so two same-source lectures never read as one. Closes G-048 and G-078 once built.

## 2026-10-10 — The server decides how much history there is.
CIS's CalDAV returned events from 22 Sep although the semester began 14 Sep and a year was requested (G-068). The Import writes the earlier weeks the server still serves; because a sync never deletes the past, Kadence keeps what CIS stops serving. Deselecting a calendar never deletes anything older than the earliest event the server returned. Also recorded: REPORT works with no fallback, the time-range is honoured, ETags are stable, one REPORT takes about 1.9 s, and the 401 scheme is Basic.

## 2026-10-10 — History keeps Done and Skip.
"The past is never written" binds the sync and every automatic writer, not the user. Done and skipped are facts about the user's day and are usually recorded after the lecture.

## 2026-10-10 — The room comes before the source on a block.
Confirmed by Parsa. A real source is called "University timetable" and fills a Week column, so every lecture read "University timetabl…" and none showed its room. The meta line is Location · Source and the source truncates; hover help, the inspector and VoiceOver still carry it. Reverses the Phase 1 priority. Closes G-079.

## 2026-10-10 — Phase 3 slice 1 gaps closed by review.
G-069 (exact sentences for unreadable events), G-070 (the UID is 185 characters), G-071 (the Import window is one calendar year back), G-072 (mock object numbers), G-073 (Statistik übung detached in review seeding), G-074 (every text element of a done block on a solid fill is text.primary: 9.00 / 6.17 worst, against 1.65 / 2.44 as first built). Edit ▸ Delete is required (A38). Deferred, still normative, and accepted by Parsa: ⌘⌥N (A37), Digest across several requests (A39), ↩ on a sidebar source row (A40).

## 2026-10-14 — CIS's CalDAV serves copies, not co-teachers.
A REPORT for Fri 2 Oct 18:00–21:00 returned four calendar objects: two byte-identical copies of each BPREF-Info session, one lecturer each. The second co-teacher in the manual export (VERSION:1.0) is not served by CalDAV (VERSION:2.0) at all. Kadence merges identical copies into one event, which is correct; it shows what CalDAV serves and does not borrow lecturers from the export. Merges that add no lecturer are counted as `copies` in the log, and the connect sheet's co-taught sentence counts only real co-teaching. Closes G-077.

## 2026-10-14 — The test runner is a third launch, and it never touches the real store.
KadenceTests is hosted by the app, so every test run launches it. A launch started by XCTest uses an in-memory store, the in-memory secret store and a transport that refuses every request. Only a normal launch opens the real store, the Keychain or the network. DEVIATIONS B45 accepted.

## 2026-10-14 — Phase 3 slice 1 accepted.
Shipped: the CIS timetable as a CalDAV account. Connect, Import and sync with change detected by content. Deletion only on proof of absence, and the past is never rewritten. A 401 or 403 pauses sync. Kadence builds the Authorization header and never follows a redirect, proven by tests including a control that would see a leak. A source is its record, never its colour; a real store has Personal, Daily routine and the connected sources. Review mode and the test runner run on in-memory stores. Co-taught lectures are merged, and a tie is not a duplicate. Two imported events never conflict. A covered block keeps its title and a covering block has a 2pt gap. The meta line is Location · Source. Exact problem sentences; status falls back to the Import time; a deselection never deletes beyond the server's horizon; Edit ▸ Delete. Verified on Parsa's clean store on 14 Oct: blue lectures, three sidebar rows, no Needs attention, rooms first, Online webinars, the two Fri 2 Oct sessions drawn apart. Deferred: ⌘⌥N (A37), Digest across requests (A39), ↩ on a sidebar source row (A40), the copies field and the end-time sentence (A41), the now-time label overlap (A42, G-082), the Day header height (G-083, design), the removed-lecture ghost (G-067). Known data limitation: CIS's CalDAV omits some co-teachers that its manual export lists; Kadence shows what CalDAV serves.

## 2026-10-14 — Travel times come from Apple Maps; the user chooses only how they travel.
Leave-by is start − travel time − buffer. The travel time comes from Apple Maps (MKDirections ETA, arriving by start − buffer); there is no typed travel time and no manual fallback. Places are Home (the user types the address, Apple Maps looks it up, the user confirms what was found), FH Technikum Wien (built in, Höchstädtplatz 6, 1200 Wien, looked up automatically, no hard-coded coordinate) and any place the user adds, confirmed like Home. Timetable events with a room are at the campus; online events, routine blocks and all-day events need no travel; a manual event travels only if the user gives it a place. The user picks one preferred mode — Public transport (default), Walking or Driving — optionally overridden per pair of places, the same both ways. No per-event mode (G-094), no cycling (G-095). Origin: the last event that had a place if it ended at most two hours before, otherwise Home; same place, no travel.

## 2026-10-14 — Kadence asks Apple Maps sparingly, and again before each departure.
Results are cached by origin, destination, mode, direction, day type and 30-minute slot, so a semester costs a few dozen requests. Each departure is refreshed at T−3 h and T−45 min. Every request goes through one queue: one at a time, at least 2 s apart, at most 20 per rolling 10 minutes and 150 per day, with priority for what the user asked and the next departure. A throttle pauses the queue 10 minutes, doubling up to 60; offline pauses it until the network is back.

## 2026-10-14 — A failed route is said, never guessed.
When Apple Maps can't answer, a leg keeps its last known time marked "≈ estimate", or says "travel time unavailable" with the reason, on every surface. Kadence never invents, defaults or extrapolates a number and never drops a leave-by silently.

## 2026-10-14 — Where you are is used for the next departure only, and never kept.
Only for the next departure, at its T−45 refresh, and only with "Use where you are" on: if the current location is more than 300 m from the rule's origin, it replaces that origin. It is sent to Apple Maps for that one request, never stored, never logged. Logs never carry an address, coordinate, place name, event title or search text. The app is complete without location permission.

## 2026-10-14 — A travel leg is derived data.
A TravelLeg (status ready / estimate / pending / unavailable, reason, mode, origin kind, source, computedAt, isEstimate) is stored per event so every surface reads one answer. It is recomputed for events from today on whenever an input changes; it is never an undo step and never written onto the event, so an imported event's upstream fields and hashes are untouched. Legs of past events are history and are never recomputed.

## 2026-10-14 — One notification per event, with absolute times; leave-by is time-sensitive; a paused sync is told once.
An event with a leave-by gets a leave-by notification (an estimate says so; "travel unavailable" when no time could be worked out); any other event gets a "starts at" under its category. Copy carries clock times, never "in 5 min", never late, missed or overdue. Actions are Done, Snooze, Open; no Snooze on imported events. Leave-by notifications are time-sensitive and degrade to normal delivery without the entitlement, never fail. When a source's background sync pauses after a 401 or 403, one notification says so (G-060). No badge. A rolling 48-hour schedule, deduplicated by identifier.

## 2026-10-14 — Protected windows hold notifications; they never drop a departure.
A notification due inside a protected window arrives when the window ends, unless the event itself is inside the window. A held leave-by that arrives after the departure says so. Lectures are not quiet time; the next lecture's "starts" waits until the one before ends.

## 2026-10-14 — "Leave now" is the should-have-left state, and a due departure outranks a late item.
Between the leave-by and the start, the status item reads "Leave now · Title" and the popover gives the leave-by time. This extends 2026-09-10's elapsed rule. A departure due within 30 minutes takes NEXT from an earlier event that started and was never marked.

## 2026-10-14 — Kadence asks for permission when it first needs it, and says so when it can't.
No prompt at launch. Notification permission is asked the first time there is something to schedule; location permission the first time a departure could use it. Each is asked once and never again on its own. When either is off, Settings says so with the way back. Tests and review launches use recording and mock doubles and never prompt, never post, never touch MapKit, location or the network.

## 2026-10-14 — Slice 2 defaults, confirmed by Parsa.
Preferred mode Public transport. Buffer 10 min. Lead times: leave-by 5 min, timetable 30, personal 15, routine 5 (routine on); sync problems on. "Use where you are" on. The 2-hour chain gap is fixed, not a setting. Notifications are allowed during lectures. The campus is named FH Technikum Wien. "Leave now" is the wording. A42 (the now-time label overlap) is fixed in this slice; A41 stays deferred.

## 2026-10-14 — Kadence targets macOS 26.5.
The project's deployment target, 26.5, is the floor; the brief's "macOS 15+" is superseded. Cycling still stays out (G-095): macOS 26 has been seen answering a cycling request with a driving route. Revisit when that is fixed.

## 2026-10-15 — Times are wall-clock times, also on the days the clocks change.
A time of day in Kadence — an event's place on the grid, a routine block, a time window, a drop position — is the local clock time on that day, never the time elapsed since midnight. On the 25-hour day the repeated hour shares its row; on the 23-hour day the missing hour holds nothing; a routine block in the missing hour moves forward by the gap (02:30 → 03:30), in the repeated hour it is the first one. Durations stay durations. The grid keeps 24 rows and draws no marker. Closes G-100 (components.md §31).

## 2026-10-15 — No invented fact, in copy as in numbers.
Extends "A failed route is said, never guessed": a surface never fills in an origin, a reason, a place or a number it does not have. What is missing is left out, never defaulted.

## 2026-10-15 — Week view opening hour stays as specified.
Week opens at the earliest start in the visible week when anything starts before 06:00, routine blocks included, so the first block of the day is always in view.

## 2026-10-16 — Phase 3 slice 2 accepted.
Shipped: leave-by from Apple Maps — places confirmed by the user, the campus looked up by Kadence at the first launch, a usual way to travel with per-pair modes, a buffer, an ETA cache and a sparing queue with refreshes at T−3 h and T−45 min; failures said as estimates or "unavailable" with the reason, never guessed, and no surface fills in an origin, reason, place or number it does not have; where you are used for the next departure only and never kept; the live band, the inspector's Place, Leave by and Origin, the menu bar's Leave / Leave now and the takeover, the popover's leave line on up to two lines; notifications (one per event, absolute times, time-sensitive leave-by, held by protected windows, Done / Snooze / Open, sync paused told once); every time of day drawn, materialised, held and scheduled at wall-clock time, so Sun 25 Oct and Sun 29 Mar keep 24 rows and routine blocks, Sleep and leave-bys at their clock times. 1113 tests green. Review frames for slice 2's fixes were rendered offscreen from the real views at a pinned clock (B55). Verified on Parsa's real store on 16 Oct: Home confirmed, FH Technikum Wien found on its own, Home ↔ FH set to Walking (17 min), leave-bys correct across the week (from Home after an online lecture, no travel between lectures at the campus), notification permission asked once, log lines without places. Deferred: A41; G-094, G-095, G-101; G-103 (a review fixture's timestamp, next slice). Open with Parsa: G-096 (time-sensitive capability, optional).