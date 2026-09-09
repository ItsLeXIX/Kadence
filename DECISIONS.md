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