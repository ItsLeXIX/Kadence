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