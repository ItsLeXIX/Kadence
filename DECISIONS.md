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