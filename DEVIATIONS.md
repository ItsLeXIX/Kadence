# Phase 1 — deviation punch list

Scope: **Phase 1 only.** `design/` gained a full Phase 2 spec in `1c58185`
(components.md §13–§17, layouts.md §8–§10, interactions.md §10–§12). Almost
none of it is built and almost none of it is listed here — unbuilt Phase 2 is
not a deviation, it is an unstarted phase. See `STATUS.md` §3.

*(Noted 2026-09-11, task P2-T08 — the one exception: `RoutineTemplate`,
`RoutineBlock` and `RoutineEngine.materialize` (data layer only, no UI) now
exist per components.md §13.1/§13.2 and BRIEF-PRODUCT.md's data-model draft.
Nothing about that work is a deviation — every value it needed was already
specified, so nothing is listed here for it either. See `STATUS.md` §6.)*

*(Corrected 2026-09-17, task P2-T09. P2-T08's own text above did not flag it,
but at `ba4f3d8` `RoutineTemplate`/`RoutineBlock` were never added to
`KadenceApp.swift`'s `ModelContainer(for:)` — the real app's schema still had
only `Event`/`Place`, so nothing running through the actual app (as opposed to
a test's own hand-built container) could persist or fetch a `RoutineTemplate`.
Not written up as a deviation at the time because nothing in `design/`
specifies container wiring; it was an implementation gap, not a spec question.
P2-T09 registers both types in `KadenceApp.swift`'s primary `init` and in
`emptyFallback()`, closing it. See `STATUS.md` §7.)*

*(Noted 2026-09-17, task P2-T10 — a second exception: a Routines window shell
now exists (`layouts.md` §8, `components.md` §13.1) — a real second `Scene`,
seven weekday-only columns on the main Week view's own hour-grid geometry, and
read-only rendering of one seeded template's blocks through `GridBlockView`.
Deliberately narrow — no create/move/resize/delete, no `[Blocks | Windows]`
mode control, no interactive flexibility control, no detached-instance
tracking or re-sync, no `TimeWindow` model. Nothing about what was built is a
deviation: every value it needed was already specified in `layouts.md` §8/§8.1
or `components.md` §13.1, or was a judgement call the task brief explicitly
left open (read-only flexibility text instead of §13.2's interactive control;
the total-hours formula) and is documented as such rather than invented. See
`STATUS.md` §8.)*

*(Amended 2026-09-17, task P2-T11 — move/resize/delete are no longer part of
the paragraph above's list. That paragraph described the whole window as
read-only; that is now stale for three of the five items it named.
`interactions.md` §11.1's move, resize and delete are built (`RoutineBlockStore` in
`Kadence/State/RoutineEngine.swift`; the drag gesture and `⌫` handler in
`Kadence/Views/Routines/RoutinesWindow.swift`), undoable and named exactly as
§11.1 prescribes. Still absent, unchanged from P2-T10: creating new routine
blocks, the `[Blocks | Windows]` mode control, the flexibility control's
interactive stepper, detached-instance tracking/Re-sync, the background
windows layer. One new judgement call, not left open by the brief: §11.1 says
§3/§4 "apply unchanged", but those sections assume a freely-floating `Date`
where a `RoutineBlock`'s `startMinutes` is bounded to a single day — a drag
that would cross midnight has no specified behaviour, so it clamps at the
boundary rather than wrapping or going out of range. Filed as `design/GAPS.md`
G-013 rather than guessed past silently. See `STATUS.md` §9.

**Corrected 2026-09-17, task P2-T12 — "creating new routine blocks" above is
now STALE.** `interactions.md` §11.1's other half — double-click and
drag-to-create — is built (`RoutineBlockStore.create` in
`Kadence/State/RoutineEngine.swift`; `RoutineDayColumnView.createSurface` in
`Kadence/Views/Routines/RoutinesWindow.swift`), reusing §3's model verbatim
(60-minute double-click default, 15-minute drag floor, empty-title-persists-
nothing, select-on-commit) and G-013's existing day-boundary clamp rather than
opening a new one. Still absent, unchanged: the `[Blocks | Windows]` mode
control, the flexibility control's interactive stepper, detached-instance
tracking/Re-sync, the background windows layer. See `STATUS.md` §10.)*

**Corrected 2026-09-19, task P2-T20 — "the `[Blocks | Windows]` mode control"
and "the background windows layer" are no longer on this list.** Both render
now: a segmented control in the toolbar (`size.editorModeBarHeight`,
`editorModeLabel` type) plus `⌘[`/`⌘]` switch `RoutinesWindow`'s `editorMode`
between `.blocks` and `.windows`, clearing the block selection on either path
(interactions.md §11.1). Every weekday column now draws all three `TimeWindow`
kinds through `BackgroundWindowsLayer`/`WindowLabelsLayer`
(`Kadence/Views/Canvas/GridLayers.swift`), generalized over a new
`TimeWindowRenderable` protocol so they can render either the display-only
`TimeWindowFixture` (main grid, unchanged) or the persisted `TimeWindow`
(Routines window). Blocks mode draws protected/low-energy only, non-hit-
testable — the main grid's own treatment; windows mode adds peak-focus (§7's
"Editor exception": 1pt dashed outline, dash `[4, 4]`,
`color.window.peakFocusEdge`, no fill) and drops the block/draft layer to
`opacity.editorInactiveLayer`, also non-hit-testable (§13.3's table). Still
absent, unchanged: dragging/resizing/creating/deleting a `TimeWindow` and the
inspector's kind picker for one — §13.3 calls windows "editable" in windows
mode, but this task only renders them; the flexibility control's interactive
stepper; detached-instance tracking/Re-sync. See `STATUS.md` §21.

**Corrected 2026-09-24, task P2-T21 — "dragging ... deleting a `TimeWindow`"
above is now STALE for select/move/delete of an EXISTING row specifically.**
`Kadence/State/TimeWindowStore.swift` (new file, `RoutineBlockStore`'s
sibling) now provides `move(_:byDeltaMinutes:)` — a pure modular translation,
`startMinutes`/`endMinutes` each wrap independently mod 1440 with no
clamping, since (unlike `RoutineBlock`/G-013) a `TimeWindow` already supports
spanning midnight — and `delete(_:)`, both named/undoable ("Move Time
Window"/"Delete Time Window"). `RoutinesWindow.swift` wires both in: a new
`windowSelection: UUID?` (window-scoped, simpler than
`RoutineBlockSelection` — a `TimeWindow` needs no weekday disambiguation),
hit-testable only in Windows mode (the exact inverse of the existing blocks-
mode `.allowsHitTesting` pattern, so Blocks mode leaves windows exactly as
non-interactive as before), a whole-span `DragGesture(minimumDistance: 3)`
written to the store only on `.onEnded` (15-minute snap, 5-minute with `⌃`,
via `TimeGeometry.snap` — same rule every other drag in this window already
uses), and `⌫` extended to delete the selected window when one is selected.
Selection is dropped on template switch and mode change, generalizing the
existing block-selection rule to the new kind. The selection ring reuses §6's
existing generic vocabulary (`Tokens.Color.Interactive.focusRing`/
`Tokens.Size.borderSelected`) applied to this new selectable object — judged
as reuse, not an invented value, so no `design/GAPS.md` entry; drawn as a
plain `Rectangle` (no corner radius), matching every other window treatment
already on this canvas rather than inventing a rounded variant. A second,
narrower judgement call: each window's hit region is its raw
`TimeWindow.spans(on:)` span, not the protected-wins-over-low-energy-
*subtracted* span the render layer actually paints where two windows
overlap — selecting/dragging the real underlying object reads as more
correct for an editor than hit-testing whatever fraction of it is still
visible, and where two windows' regions do overlap, frontmost-in-`ForEach`-
order wins the tap, same "today's build keeps frontmost-wins, nothing
invented" precedent this file's own G-010/A24 already establish for
overlapping blocks. **Still absent, unchanged, still explicitly out of
scope (at the time):** creating a new `TimeWindow` (drag-to-create), resizing
one (a top/bottom edge drag), the inspector's kind picker, weekday-set
editing, `RoutineEngine.materialize` honouring windows, `MenuBarExtra`,
snooze — next task's job. See `STATUS.md` §22.)*

**Corrected 2026-09-24, task P2-T22 — the immediately preceding paragraph's
"resizing one (a top/bottom edge drag)" clause is now STALE.**
`Kadence/State/TimeWindowStore.swift` gained `resize(_:newStartMinutes:newEndMinutes:)`,
mirroring `RoutineBlockStore.resize`'s shape (P2-T11) but, like `move` above,
**not** its day-bounded clamp (G-013): a candidate edge wraps mod 1440
(`wrapMinutes`) rather than clamping into `[0, 1440]`, and the only floor is
the same 15-minute minimum `RoutineBlockStore.resize`/`EventStore.resize`
both use — computed with a new `modularDuration(from:to:)` helper that
measures forward and wraps past midnight exactly the way
`spans(on:calendar:)` itself measures a window's span (equal start/end reads
as a full 24-hour window, never zero — matching `spans(on:)`'s own `else`
branch), not a plain subtraction. If a candidate edge would leave less than
15 minutes against the other, fixed edge, it is pulled back to exactly 15
minutes rather than collapsing or inverting the window. Named undo step
`"Resize Time Window"`, matching this file's existing `"Move Time
Window"`/`"Delete Time Window"` naming. `RoutinesWindow.swift`'s
`TimeWindowDragSession` gained a `Mode` (`.move`/`.resizeTop`/`.resizeBottom`,
analogous to `RoutineDragSession.Mode`), classified from the drag's
`startLocation` against the dragged span's own top/bottom
`Tokens.Size.blockResizeHandleHeight` band — the exact classification shape
`blockGesture` already uses for routine blocks, per components.md §13.3's own
"the same size.blockResizeHandleHeight handles blocks use." One narrow
judgement call, not a spec gap: a wrapping window can render two spans on a
given day (`spans(on:calendar:)`'s own doc comment); per this task's own
brief, that is not special-cased in the gesture — whichever single span the
pointer went down on supplies the reference date, and a top-edge drag always
resizes `window.startMinutes` while a bottom-edge drag always resizes
`window.endMinutes`, regardless of which span. Correct for the common
(non-wrapping) case; the render layer already recomputes both spans from the
resulting fields either way. **Still absent, unchanged, still explicitly out
of scope (at the time):** creating a new `TimeWindow` (drag-to-create), the
inspector's kind picker, weekday-set editing, `RoutineEngine.materialize`
honouring windows, `MenuBarExtra`, snooze — next task's job. See `STATUS.md`
§23.)*

**Corrected 2026-09-24, task P2-T23 — the immediately preceding paragraph's
"creating a new `TimeWindow` (drag-to-create)" clause is now STALE.**
`Kadence/State/TimeWindowStore.swift` gained
`create(weekdays:startMinutes:endMinutes:kind:label:) -> TimeWindow?`,
mirroring `RoutineBlockStore.create`'s reversed-`delete` shape (one named
undo step, `"Create Time Window"`, via the existing
`TimeWindowRestoreSnapshot`/`insertWindow`/`removeWindow` plumbing) and, like
`resize` above, its own defensive 15-minute floor computed with the file's
existing wrap-aware `wrapMinutes`/`modularDuration` helpers rather than a
plain clamp. `RoutinesWindow.swift`'s windows-mode empty-canvas `Rectangle`
(the one whose tap already deselects) gained a sibling `DragGesture`,
mirroring `createSurface`'s own create-drag shape (same `TimeGeometry.snap`
rule, same `max(upper.timeIntervalSince(lower), 15*60)` floor pattern
`commitDraft` uses) but writing through `TimeWindowStore.create` with the
dragged column's own single `weekday` — never propagated to any other day —
instead of a title-bearing draft. A new small `TimeWindowCreateDragSession`
(`origin`/`current`), deliberately not folded into `TimeWindowDragSession`
(move/resize-only, keyed by an EXISTING window's `id`), drives a live dashed
preview reusing the existing `dropPreview(_:)` view. The created window is
selected (`windowSelection`) on success. This closes only the drag half of
components.md §13.3's "Creating one: drag on empty canvas, then pick the kind
from the inspector" — every created window still defaults to kind
`.protected`, an empty label, and exactly the single dragged weekday.
**Still absent, unchanged, still explicitly out of scope:** the inspector's
kind picker, weekday-set editing beyond this task's single-weekday default,
label editing, `RoutineEngine.materialize` honouring windows, `MenuBarExtra`,
snooze — next task's job. See `STATUS.md` §24.)*

**Corrected 2026-09-24, task P2-T24 — the immediately preceding paragraph's
"the inspector's kind picker, weekday-set editing beyond this task's
single-weekday default, label editing" clause is now STALE.** Selecting a
`TimeWindow` in Windows mode now shows a dedicated inspector
(`TimeWindowInspectorView`, new, `RoutinesWindow.swift`) instead of always
falling through to the block/template summary — `RoutinesWindow.inspector`
now branches on `windowSelection` first (mirroring `handleDelete()`'s own
"check the more specific selection kind first" ordering). Three new
`TimeWindowStore` methods, same `edit(id) { }` + one named `UndoStack` step
shape as `move`/`resize`/`create`, each guarded against no-op edits:
`setKind(_:to:)` ("Set Time Window Kind"), `setWeekdays(_:to:)` ("Set Time
Window Weekdays", refuses an empty set the same way `create` refuses an empty
`weekdays` parameter), `setLabel(_:to:)` ("Set Time Window Label"). All three
fire immediately on change — no "Save" button, matching every other inspector
control in this app. This finally closes components.md §13.3's full sentence
("Creating one: drag on empty canvas, then pick the kind from the
inspector") — P2-T23 built the drag half, this builds the "pick the kind"
half plus the weekday-set/label editing §7 also names.

Three narrow judgement calls, none a spec gap (§13.3/§7 do not specify exact
segment label text, a toggle glyph/style, or a text-field commit granularity
— documented here per this task's own brief, the same way P2-T15 documented
its option-row prose as a judgement call rather than filing a `GAPS.md`
entry):
  - **Kind segment labels** are the plain English names §13.3/§7's own prose
    already uses for these three kinds — "Protected" / "Low Energy" /
    "Peak Focus" — in a plain native `Picker(.segmented)`, analogous in
    weight to §13.2's "Fixed / Shiftable / Droppable" labelled segmented
    control (the closest existing precedent, though that control's own
    interactive version does not exist yet — `blockDetails` above still
    reads flexibility as text — so there was nothing to copy verbatim, only
    to match in kind).
  - **Weekday toggles** are seven native `Toggle`s in `.toggleStyle(.button)`
    with `.tint(Tokens.Color.Interactive.accent)` — the one existing generic
    "selected" tint this app already uses (the focus ring, the drop preview)
    — rather than inventing a bespoke selected-day swatch/color pair. Labels
    reuse `dayHeaderWeekday` type and the same Mon-first
    `RoutineWeekLayout.orderedWeekdays(firstWeekday:)` ordering
    `RoutineWeekdayHeaderRow` already uses, so the toggle row lines up
    conceptually with the seven weekday columns.
  - **The label field commits on `Return` or on losing focus, not per
    keystroke.** There is no existing precedent in this codebase for editing
    an ALREADY-persisted text field with per-keystroke-vs-per-commit undo
    granularity to match — the one existing inline `TextField`
    (`DraftBlockView`'s title) only ever edits an in-flight, not-yet-persisted
    draft, and discards (rather than commits) on blur. `TimeWindowInspectorView`
    holds the in-flight text in local `@State`, seeded from `window.label`
    (fresh on each selection change via the parent's `.id(selectedWindow.id)`,
    which tears down and rebuilds the view rather than reusing it in place),
    and calls `TimeWindowStore.setLabel` once, on `onSubmit` or on
    `@FocusState` losing focus — one undo step per edit, never one per
    character, matching this task's own explicit instruction on granularity.

**Still absent, unchanged, still explicitly out of scope:**
`RoutineEngine.materialize` honouring protected windows, `MenuBarExtra`,
snooze, the block inspector's own still-read-only flexibility field (§13.2's
interactive stepper — pre-existing, separate gap, untouched by this task),
detached-instance tracking and Re-sync (§13.4). See `STATUS.md` §25.

**Corrected 2026-09-24, task P2-T25 — every entry above's bare "`MenuBarExtra`"
clause (P2-T21/T22/T23/T24) is now STALE for the status item and popover
shell specifically.** `components.md` §15 / `interactions.md` §12's
non-keyboard parts are built: a `MenuBarExtra` scene in `KadenceApp.swift`
(`.modelContainer(container)`, `.menuBarExtraStyle(.window)`) with a status
item (`Kadence/Views/MenuBar/MenuBarStatusItemView.swift`, §15.1's three
states — Normal/Late/Empty, time-never-truncates built structurally via
`.fixedSize()` on the primary text rather than left to usually hold) and a
popover (`Kadence/Views/MenuBar/MenuBarPopoverView.swift`, §15.2's
NEXT/REST OF TODAY, all three states, the `popoverMaxRestRows`/`+N more`
cap). `Done` and the Late state's `Re-offer` are wired to
`EventStore.toggleDone`/`EventStore.markSkipped`; both confirmed live against
the running app (`STATUS.md` §26), including that `⌘Z` undoes a menu-bar
`Done` through the same shared `UndoStack` the rest of the app uses.
**Nothing about what was built is a deviation** — every value it needed
(`Tokens.Size.popoverWidth`/`popoverNextBlockMinHeight`/`popoverRestRowHeight`/
`popoverMaxRestRows`/`statusItemMaxWidth`/`statusItemGlyphSize`,
`Tokens.Color.Semantic.now`/`Text.primary`/`Text.secondary`, the five new
`TypeStyle` statics backed by already-generated `Tokens.Typography.*`
entries) was already specified; the leading rail on the NEXT block reuses
`RailView`/`SourceKey.rail`, the exact existing colour machinery the task
named rather than a new path. Two composition/layout choices `design/`
leaves open are documented as this task's own judgement call, not invented
values — see `STATUS.md` §26: the popover meta line's trailing qualifier
reuses `GridBlockModel.metaLine` rather than a second Source/Location rule,
and the REST OF TODAY time column is a SwiftUI `Grid` (sized to its own
widest cell) rather than a literal pixel width `design/` never names.

**One deliberate interval reuse, per this task's own brief, not a deviation
from a spec value (the spec names none):** both the status item and the
popover refresh `now` on `Timer.publish(every: Tokens.Motion.NowLineTick.interval, ...)`
— the same 60-second cadence `MainWindow.swift` already uses for the
calendar canvas's now-line — rather than a dedicated menu-bar-specific
timer. `interactions.md` §15/§12 name no menu-bar refresh interval of their
own, and `NowLineTick` is the one existing "how often does the clock-driven
UI recompute" token in this codebase; introducing a second, unspecified
number for the same kind of tick would have been the invented value this
task is not allowed to add.

**Still absent, explicitly out of scope for this task (see its own brief):**
the `Snooze` button's action and its confirmation result row (components.md
§16 — next task); the `Open` button's action (bring the main window forward /
navigate to the item — next task; both buttons render, `.disabled(true)`,
matching §15.2's action-row shape without being wired); all of
`interactions.md` §12's keyboard table (`↑`/`↓`/`↩`/`⌘↩`/`⌥⌘↩`/`⎋`, and the
click-vs-keyboard focus rule); any change to `RoutineEngine`,
`ConflictEngine` or `TimeWindow` code. `RoutineEngine.materialize` honouring
protected windows and detached-instance tracking/Re-sync (§13.4) remain
untouched, unchanged from every paragraph above. See `STATUS.md` §26.

**Corrected 2026-09-24, task P2-T26 — the previous entry's "`Snooze`'s
action" and "all of `interactions.md` §12's keyboard table" clauses are now
STALE for the `⌥⌘↩` row specifically.** `Kadence/Views/MenuBar/MenuBarPopoverView.swift`
wires `Snooze` (button click or `⌥⌘↩` while the popover holds key focus) to
the new `EventStore.snooze(_:)`, with the components.md §16 in-place result
row (`Moved to HH:mm` + `Undo`) cross-fading in and holding for
`motion.snoozeConfirmHold`, pausing on hover, exactly as specced (see
`STATUS.md` §27). **One deviation this wiring required, not a value
invention:** making `⌥⌘↩` reachable at all needs the popover to actually
hold key focus, and nothing before this task ever granted it any.
`interactions.md` §12 specifies that focus should move to the popover
"only when opened by keyboard, not by click" — a click-vs-open-method
distinction this task does not attempt to detect. Instead,
`MenuBarPopoverView.swift` claims key focus **unconditionally on every
open**, regardless of how the popover was opened:

```swift
.focusable()
.focused($isKeyFocused)
.onAppear { isKeyFocused = true }
```

Confirmed live: without this pair, `AXFocused` on every element in the
popover reads `false` even with the popover's window key, and
`.onKeyPress` never ran — `.focusable()` alone makes the view *eligible*
for focus, it does not *grant* it. Claiming focus on every open (not just
keyboard-triggered opens) is a narrower, blunter rule than §12's, chosen
because the finer click-vs-keyboard distinction was already out of scope
for the whole §12 keyboard table per P2-T25's own scope note and remains
so here — this task's brief covers only the `Snooze` row of that table.
Practical effect: a mouse click on the status item also leaves the popover
holding key focus, which §12 does not call for and which a future task
implementing the rest of §12's keyboard table (`↑`/`↓`/`↩`/`⌘↩`/`⎋`) will
need to narrow. See the file's own header comment and the
`.focused($isKeyFocused)`/`.onAppear` block's doc comment, both already
pointing here. Still absent, unchanged from the entry above: `Open`'s
action; the remaining keyboard rows (`↑`/`↓`/`↩`/`⌘↩`/`⎋`); components.md
§16's third bullet (coordinating the block-move transition with
`MainWindow` when it is open on the destination day — a separate concern
needing animation state shared across two SwiftUI scenes). See `STATUS.md`
§27.

*(Noted 2026-09-18, task P2-T13 — a fourth exception: `ConflictEngine`
(`Kadence/State/ConflictEngine.swift`) now detects every routine-vs-manual/
imported overlap and builds each one's ranked resolution options
(BRIEF-PRODUCT.md's Phase 2 section; `components.md` §14.3), data layer only —
no wiring into `Presentation.conflicted`/`BlockStyleResolver`/`GridBlockView`,
no "Needs your attention" row, no conflict panel, no applying an option to the
store, no protected-window conflicts (no `TimeWindow` model exists yet).
Nothing about what was built is a deviation: every value it needed was either
already specified (the 15-minute snap and floor, `RoutineBlock.shiftableMinutes`,
the externalID scheme `RoutineEngine.swift` already documents) or a judgement
call the task's own brief explicitly left open and is documented as such
rather than invented — which minute-scale metric puts `.skipToday` on the same
disturbance axis as a shift or a shorten, and why a `.droppable` conflict's
option list has exactly 1 entry (its flexibility-derived option already *is*
"skip today", so the brief's own "always offer skip as a fallback" does not
duplicate it). See `STATUS.md` §12.)*

**Corrected 2026-09-18, task P2-T14 — the previous entry's "no wiring into
`Presentation.conflicted`/`BlockStyleResolver`/`GridBlockView`" clause is now
STALE for the wiring half specifically.** `MainWindow` now runs
`ConflictEngine.detect` against the live `Event`/`RoutineBlock` queries and
threads the resulting conflicted-event-id set through `TimedCanvasView` into
`DayColumnView`, which inserts `.conflicted` for either id — additive to, not
a replacement of, the pre-existing Phase 1 `conflictsWithProtectedWindow`
placeholder, which is untouched. Still absent, unchanged: the "Needs your
attention" row, the conflict panel, preview-on-focus, applying an option to
the store, and protected-window conflicts (still no `TimeWindow` model).
Nothing about what was built is a deviation — the wiring needed no new value
`design/` doesn't already give; `Presentation.conflicted` and
`BlockStyleResolver`'s handling of it already existed from Phase 1. See
`STATUS.md` §13.

**Corrected 2026-09-18, task P2-T15 — the previous entry's "Needs your
attention row, the conflict panel" clause is now STALE.** Both now exist:
the needs-attention row is a real button (§10.2, icon removed — **A21 above
is now closed**), `⌘⇧A` does the same thing, and activating either selects
the first unresolved conflict (a new stable ordering rule, `ConflictOrdering`
— see below) and shows components.md §14.2's collision header and §14.3's
ranked option rows in the inspector, as static content. Nothing about what
was built is a deviation: every token §14.2/§14.3 name already existed in
`Tokens.swift` from the Phase 2 pass, and the two things `design/` leaves
unspecified — the option-row prose's literal wording, and the collision
blocks' exact rendered height within the "16–27" density band — are
documented as this task's own engineering call in `STATUS.md` §14, not
invented values (neither is a colour/size/token; both are judgement calls
`design/` explicitly leaves open: §14.3's examples are illustrative, not a
template, and any height inside the 18–27 tier band resolves identically).
Still absent, unchanged: preview-on-focus, `↩` apply, `⎋` abandonment
(interactions.md §10.1's second half and all of §10.2), applying an option to
the store, and protected-window conflicts (still no `TimeWindow` model). See
`STATUS.md` §14.

**Corrected 2026-09-18, task P2-T16 — the previous entry's "preview-on-focus,
`⎋` abandonment" clause is now STALE.** Both now exist (components.md §14.4,
interactions.md §10.1–§10.2): changing `selectedConflictOptionID` (↑/↓ in
`MainWindow.handleKey`, scoped to the inspector having focus) drives a live
canvas preview — `.previewed` (new `Presentation` flag) on the option's
proposed frame, the real block retained as a dimmed ghost at its committed
frame, and the calendar canvas's `size.previewCanvasBorder` accent inset
border — and any of `⎋`, focus leaving the inspector, a view/anchor change, or
collapsing the inspector reverts it unconditionally, no confirmation. `↩`
apply and any `EventStore`/`UndoStack` mutation from the panel remain
out of scope, unchanged, for the next task. Two judgement calls this task's
own brief explicitly asked to be recorded rather than guessed past, neither an
invented value:

1. ~~**The `.skipToday` preview treatment.**~~ **Retired 2026-10-01 (task
   P2-T38): `design/GAPS.md` G-014 — CLOSED confirms what this task built;
   it is now `components.md` §14.4.** The original entry is under
   "Resolved — retired by a spec ruling" near the end of this file.
2. **`abandonConflictPreview()`'s scope.** interactions.md §10.2 says a
   pending preview is abandoned "the moment focus leaves the conflict panel",
   and lists ⎋/click-away/view-change/paging/inspector-collapse as triggers.
   It does not say whether "the panel" itself (i.e. `selectedConflictID`, the
   inspector's whole conflict-mode display) also exits on those same
   triggers, only that the preview does. Read narrowly — §10.2's own subject
   is "a pending preview", not "conflict mode" — so all of the wired triggers
   clear `selectedConflictOptionID` only; `selectedConflictID` survives, and
   the panel stays open (with nothing focused) until the user picks another
   option, applies one (a later task), or the conflict is otherwise resolved
   (§14.5). The alternative reading (clearing both) would mean `⇥` cycling
   through the inspector and back out silently ejects the user from the
   conflict they were looking at, which nothing in §14.5 describes as a way to
   leave conflict mode. See the doc comment on
   `CalendarState.abandonConflictPreview()` for the same argument in place.

Also noted, not filed as a gap: interactions.md §10.1 says the conflict panel
is "a focus region reached from the needs-attention row, from `⌘⇧A`, or by `⇥`
into the inspector" — read as literally as possible this could mean activating
either of the first two also moves real keyboard focus into the inspector, but
`CalendarState.activateNeedsAttention()` (P2-T15, unchanged here) does not,
and doing so needs `MainWindow`'s own `@FocusState`, which `CalendarState` has
no access to. Left as-is: today, ↑/↓ preview navigation requires either
clicking the panel or `⇥`-ing into it first, even right after `⌘⇧A`. See
`STATUS.md` §15.

**Corrected 2026-09-18, task P2-T17 — the previous entry's "`↩` apply and any
`EventStore`/`UndoStack` mutation from the panel remain out of scope" clause
is now STALE.** `↩`, pressed while the inspector has focus, a conflict is
selected, and an option is focused/previewed, now applies it
(`CalendarState.applyFocusedConflictOption`, wired from
`MainWindow.handleKey`): `.shiftLater` calls `EventStore.move`, `.shorten`
calls `EventStore.resize`, `.skipToday` calls the new `EventStore.markSkipped`
— all three wrapped in one `store.transaction("Resolve Conflict")`, so the
Edit menu reads "Undo Resolve Conflict" (interactions.md §10.1's own words)
and one ⌘Z reverts every block the option touched, not one step per block.
Clearing `selectedConflictOptionID` immediately after (no code change needed
beyond the assignment — `isConflictPreviewActive`/`activeConflictPreview`
were already gated on it by P2-T16) drops the canvas's
`size.previewCanvasBorder` border in the same call; `DayColumnView.blockStack`
already keys `motion.blockMove`'s spring on `laidOut.frame` unconditionally
(P2-T11), so the committed move/resize animates the same way a drag already
does, with no new animation code. The method then re-runs `ConflictEngine
.detect` (via a caller-supplied closure — `CalendarState` holds no query of
its own) and either previews the next unresolved conflict's first (==
recommended) option, or, if none remain, sets `selectedConflictID = nil`,
which is what returns the inspector to its ordinary state and what the
needs-attention row's own count (`state.conflicts`) reads to hide at zero —
components.md §14.5's "no 'all clear' state" is satisfied by there being
nothing built beyond that, not by a dedicated empty-state view.

~~One thing built beyond a literal reading of the brief (G-015).~~ **Retired
2026-10-01 (task P2-T38): `design/GAPS.md` G-015 — CLOSED confirms the
`ConflictEngine.detect` `.skipped` guard; it is now `components.md` §14.5.**
The original entry is under "Resolved — retired by a spec ruling" near the
end of this file.

`EventStore.markSkipped` (new) is deliberately not `toggleSkipped` reused: the
existing method flips between `.skipped`/`.scheduled`, and re-applying a
`.skipToday` resolution (or applying it to an occurrence something else had
already skipped) must still land on `.skipped`, never silently un-skip it. It
is a one-directional, idempotent write — see its own doc comment.

Nothing about any of this is an invented UI value: `"Resolve Conflict"` is the
exact string `UndoStack.swift`'s and `EventStore.transaction`'s own worked
examples already use, and every token/animation reused (`motion.blockMove`,
`size.previewCanvasBorder`) was already in place from P2-T16. Still out of
scope, unchanged: the `TimeWindow` editor, `MenuBarExtra`, snooze. See
`STATUS.md` §16.

**Corrected 2026-09-18, task P2-T18 — every earlier entry's "(no `TimeWindow`
model exists yet)" / "still no `TimeWindow` model" clause (P2-T13/T14/T15, and
the "Not a deviation" note below on peak-focus windows) is now STALE for the
model's existence specifically.** `Kadence/Models/TimeWindow.swift` now
defines a persisted `@Model final class TimeWindow` (`id`, `weekdays`,
`startMinutes`/`endMinutes`, `kind: TimeWindowKind`, `label` — the same field
shapes `TimeWindowFixture` already had), registered in `KadenceApp.swift`'s
`ModelContainer`, seeded via `MockData.seedTimeWindowsIfNeeded`/
`makeTimeWindows()` with the same two windows the display-only
`TimeWindowFixture` array already described. This closes no gap and resolves
no deviation on its own — data layer only, per this task's explicit scope.
Everything the earlier entries were actually gating on is still true and
still absent: no `TimeWindow` editor UI, no `[Blocks | Windows]` mode control,
`GridLayers.swift`/`DayColumnView.swift` still render `TimeWindowFixture`
exactly as before (untouched by this task — confirmed via `git diff`),
`RoutineEngine.materialize` still does not honour protected/low-energy
windows, and `ConflictEngine` still does not detect protected-window
conflicts. See `STATUS.md` §19.

**Corrected 2026-09-19, task P2-T19 — the immediately preceding paragraph's
closing clause, "`ConflictEngine` still does not detect protected-window
conflicts," is now STALE.** `Kadence/State/ConflictEngine.swift` gained
`detectWindowConflicts(events:routineBlocks:timeWindows:calendar:)`: a
non-`.skipped` `.routine`-origin event whose interval overlaps a
`.protected`-kind `TimeWindow`'s span (via the new `TimeWindow.spans(on:
calendar:)`, ported from `TimeWindowFixture.spans(on:)`) now produces a
`WindowConflict` with the same ranked shiftLater/shorten/skipToday options,
same disturbance scale, same exactly-one-`isRecommended` ranking `detect`
already used for event-vs-event conflicts. `.lowEnergy`/`.peakFocus` windows
are excluded — the brief names only protected windows for this clause. This
closes that half of the gap and no other: still data layer only, still no
`WindowConflict` wired into `ConflictPanelView`/the needs-attention row/count,
still no `TimeWindow` editor UI, still no `[Blocks | Windows]` mode control,
`RoutineEngine.materialize` still creates occurrences at their configured time
unconditionally regardless of any window. See `STATUS.md` §20.

Re-audited **2026-09-10** against the *current* text of `design/components.md`,
`design/layouts.md` and `design/interactions.md`, re-read this session rather
than trusted from the previous audit — those three files were all edited in
`1c58185`, which amended three Phase 1 rules in place. Every code claim below
("token unused", "never called", "no caller passes it") was re-checked with a
search against the working tree, not carried forward.

Legend: **A** absent · **B** built differently · **C** value I invented (none
remain) · **D** spec contradiction · ~~struck~~ = closed.

**Counts: A ×17 · B ×6 · C ×0 · D ×0** — open items only, counted from this
file rather than carried forward. (A ×8 and B ×7 more are closed and struck
below; the previous audit's "A ×14" did not match its own list.)

*(Updated 2026-09-18 by task P2-T15: was "A ×18". A21 is now closed — see the
amendment note below and the entry itself.)*

*(Updated 2026-09-11 by task P2-T05: was "B ×7 · D ×1". D4 and B13 are now
closed — see the amendment note below and the entries themselves.)*

**Amended 2026-09-10 (task P2-T01, crash fix).** A22 and A23 are new, both found
while reproducing the ⎋/↩ crash rather than by re-reading the spec. The crash
itself is *not* listed as a deviation — it was a defect in a feature the spec
and the build agreed on, and it is fixed; see STATUS.md §1.5 and the note under
A13.

**Amended 2026-09-11 (task P2-T02, click-to-select fix).** A24 is new, found
while building a regression check for the click fix. **B9 is corrected** — its
old wording implied mouse selection worked, and it did not. The click-to-select
defect itself is *not* listed here, for the same reason the ⎋/↩ crash is not:
the spec and the build agreed on the feature, the build simply broke it, and it
is fixed. See STATUS.md §1.6.

**Amended 2026-09-11 (task P2-T03, block-overlap diagnosis — report only).**
That task wrote no code. **B13 is new** and **D4 is new**, both found by
measuring the committed screenshots against a direct run of `DayLayoutEngine`
over the Wed 9 Sep fixtures; see STATUS.md §1.7 for the method and the full
per-symptom root cause. Nothing was closed and nothing else was rewritten.
D4 re-opens the D section, which had been empty since 2026-09-10 — it is
`design/GAPS.md` G-011 restated in this file's terms, because it is a genuine
contradiction between two Phase 1 rules and not only an unanswered question.
`DayLayoutEngine` itself came out of that diagnosis **clean**: every cluster,
sub-column, slot width, cascade indent and z-index it produced for that day
matches §3.3, in both Day and Week. The defect is in the view layer.

**Amended 2026-09-11 (task P2-T05, block-overlap fix).** **D4 and B13 are now
closed**, both struck below rather than deleted. `design/GAPS.md` G-011 was
ruled and closed by task P2-T04 (design agent) — `DensityTier`'s boundaries are
now 18/28/53, derived from each tier's own content set, and a new §3.5
confinement invariant states the rule B13 said the spec was missing. This task
implemented both in `Kadence/Layout/DensityTier.swift`,
`Kadence/DesignSystem/BlockStyleResolver.swift`,
`Kadence/Views/Blocks/GridBlockView.swift` and
`Kadence/Views/Blocks/DraftBlockView.swift`, and added
`KadenceTests/BlockConfinementTests.swift` (sixteen new cases) as regression
cover, including a pixel-level render of the two named fixtures. See
STATUS.md §1.7. `DayLayoutEngine.swift` was not touched. B4–B9 (excluding B13)
are unaffected and unchanged; G-012 (the travel-band footprint question behind
the Day half of symptom (c)) was separate and, at the time of this task, still
open.

**Amended 2026-09-11 (task P2-T06, G-012 fix).** The sentence above is now
stale: G-012 was ruled CLOSED at the spec level by task P2-T04 and this task
built the code side — `DayLayoutEngine.cluster`, `sortForLayout` and
`packIntoSubColumns` now key off a layout footprint (`layouts.md` §3.3) that a
case-1 travel band extends, and `DayColumnView.layoutItems` supplies each
event's `departAt`. G-012 was never listed as its own D/B entry in this file
(only in `design/GAPS.md` and STATUS.md §1.7/§5.2), so there is no entry here
to strike; this note exists only to keep the sentence above from misleading a
future reader. D4 and B13 are untouched by this task and remain closed, as
above.

**Amended 2026-09-11 (P2-T06 fix follow-up — `check-accessibility.sh`
regression investigation).** No deviation entry here changes. The task
investigated a `FAIL: no Kadence process has a window` result reported against
the P2-T06 commit above and found the cause was stale saved window-restoration
state left over from the earlier interrupted P2-T06 session, not a code defect
in `DayLayoutEngine.swift` or `DayColumnView.swift` — see STATUS.md's amendment
near the top and §1.2 for the full diagnosis and two clean re-runs. Recorded
here only so this file's account of P2-T06 stays complete; the G-012 note
immediately above is otherwise unchanged.

**Correction, 2026-09-11 (task P2-T07, report-only re-diagnosis).** The
paragraph above's framing ("resolved") did not hold — independent
verification of the same HEAD failed twice more after it was written. No
deviation entry changes here either (this remains a build/verification-
process question, not a spec deviation), but see STATUS.md §1.2.1 for the
corrected, evidence-backed account: `check-accessibility.sh` still stands at
**FAIL** per independent verification; this task's own 5/5 clean local runs
and matched timing measurements against baseline `03fb5cd` rule out
"footprint-clustering rendering got too slow for the fixed 9s sleep" as the
mechanism, and point instead to an environmental AX-enumeration flake on this
shared, concurrently-loaded machine — not a code defect. Left for a future fix
task to harden the script and get an independent re-verification; not fixed by
this task.

**Fix, 2026-09-18 (P2-T12 follow-up — `check-accessibility.sh` hardened).**
The `FAIL: no Kadence process has a window` result reported again immediately
after task P2-T12 (routine block creation), and P2-T12's own STATUS.md entry
re-quoted the old "TextEdit also shows 0 windows" excuse without re-checking
it. This task re-checked it and found a real, root-cause fix instead of
another excuse: `design/`-external, but recorded at STATUS.md §8 back on
2026-09-17 — a plain `open -n` with no restoration flag can reopen a
*previously used* window (the Routines window included, since P2-T10/P2-T11/
P2-T12's own manual verification opened it repeatedly on this machine) as
"window 1" ahead of the fresh main window, or — the new symptom this session
— produce no window at all for 40+ seconds while the process sits idle. §8
named the fix (`-ApplePersistenceIgnoreState YES`) but never applied it to
any script. It is now applied, consistently, to all four scripts sharing the
identical `open -n "$APP"` pattern: `check-accessibility.sh`,
`check-block-click-selects.sh`, `check-block-hit-regions.sh`,
`check-routines-window.sh`. Evidence it is restoration flake and not a
P2-T12 code crash: `~/Library/Logs/DiagnosticReports` had no Kadence entries;
the container's `CrashReporter` plist held only a stale `Date` key from
2026-09-10; `log show` for the process during a reproduction returned
nothing; `sample` on a live 0-window reproduction showed the main thread
idle in `mach_msg2_trap`, process alive per `ps`. `check-accessibility.sh`
passed three consecutive times after the fix, each reporting the main
window's 20 block elements. See STATUS.md §11 for the full account,
including a second, unrelated, NOT-fixed fragility found in the same
session (a live third-party application intermittently holding OS-wide
frontmost status on this machine, which can still make the two
click/keystroke-driven scripts flake independently of this fix).

**Re-diagnosis, 2026-09-18 (P2-T15 follow-up — `check-accessibility.sh`,
different mechanism this time).** `FAIL: no Kadence process has a window`
was reported again immediately after task P2-T15 (needs-attention row +
static conflict panel), and this task was explicitly asked not to assume it
was either a P2-T15 regression or a recurrence of the P2-T12 restoration
flake above without evidence. Neither is the cause: the screen on this Mac
is **locked** (`CGSSessionCopyCurrentDictionary()` → `CGSSessionScreenIsLocked
= 1`), which blocks accessibility window enumeration session-wide for every
process, not just Kadence. `CGWindowListCopyWindowInfo` at the same moment
showed a live, correctly-sized (1470×882) Kadence window — the app is fine;
System Events simply cannot see any window while the screen is locked. The
screen-lock timestamp decodes to 02:29, more than two hours before P2-T15's
own commit (04:55) — the symptom this task was asked to investigate predates
the diff it was asked to investigate, which rules out a P2-T15 regression on
timing grounds alone, independent of the code-level evidence (clean build, 0
warnings; no crash log; process alive throughout). No file under `Kadence/`
was touched. `check-accessibility.sh`'s failure branch now runs a direct
`swift -e` query of `CGSessionScreenIsLocked` (falling back to the existing
Finder-based control check if that is inconclusive) so a future occurrence
gets diagnosed immediately instead of re-investigated from scratch a third
time. ~~**This task could not obtain an actual `PASS (elements present)`
run** — the screen has been locked continuously since before the task
started and unlocking it needs this machine's password, which is outside
this task's authority to obtain or bypass.~~ **Superseded, 2026-09-18 (P2-T15
gate closure).** The screen was confirmed unlocked first-hand
(`CGSSessionScreenIsLocked` absent from the session dict, i.e. unlocked;
`kCGSSessionOnConsoleKey = 1`) and `check-accessibility.sh` was run twice
against a fresh build, both `PASS (elements present)`, 20 block-shaped
elements each time. No app-code defect was found in the P2-T15 conflict
entry point (`ConflictPanelView.swift`, the needs-attention row wiring, the
`⌘⇧A` shortcut, `ConflictOrdering.swift`, `ConflictOptionFormatting.swift`)
— the `PASS` closes out verification without further changes. See
STATUS.md §15 for the original diagnosis (kept, since it was correct for
its moment) and §16 for the real result.

### What this re-audit changed

The Phase 1 section numbering in all three spec files is **unchanged** —
components.md still runs §1–§12, layouts.md §1–§7, interactions.md §1–§9, with
Phase 2 appended after. So every section reference below still resolves. What
changed is the *content* of three Phase 1 sections, plus three stale entries:

| Item | Was | Now |
|---|---|---|
| **A2** vertical gap | listed absent | **closed** — implemented, entry was stale |
| **A9** resize handles | listed absent | **closed** — implemented, entry was stale |
| **A18** cursors | "no cursors anywhere" | **rewritten** — 3 of 6 are wired |
| **A12** gutter conflict | flagged as an open contradiction | **closed** — §7 text amended |
| **A11** toolbar focus stop | flagged as a gap against §1 | **closed** — §1 text amended |
| **A21** needs-attention icon | — | **new** — created by the §10.2 amendment |

---

## D — spec contradictions

- ~~**D4 — components.md §3.1 vs §3.3. The 11–15pt density tier cannot be drawn.**~~
  **Closed 2026-09-11** — ruled by `design/GAPS.md` G-011 — CLOSED (task P2-T04)
  and implemented in code by task P2-T05 (see STATUS.md §1.7). *(was: new
  2026-09-11, task P2-T03; §3.3's ladder gave a block of rendered height 11–15
  the content set "rail + glyph only" and clamped anything shorter to
  `size.blockMinRenderedHeight` (11); §3.1's padding (5, all sides) plus the
  glyph (11) made that 21pt of chrome — above the tier's own band and nearly
  twice the clamp floor, which is why the two blocks at 12:30 and 12:50 drew
  ~22pt tall (B13).)* The ruling rederived every tier's band from its own
  content set instead of picking one: boundaries moved 16/28/44 → 18/28/53, with
  a normative per-tier padding table and minimum, so the 11–15 (now 11–17)
  tier's minimum (11) sits at or below its own band bottom for the first time.
  No padding or glyph value was weakened — the boundaries moved instead, which
  is not an invented value.

D1 and D2 were closed by the 17:14 revision (`size.blockCascadeIndentMin`
removed; `increaseContrast` parameter, GAPS G-003).

- ~~**D3 — the time gutter: components.md §7 vs interactions.md §1.**~~
  **Closed 2026-09-10 — the spec text itself was amended.** Tracked as A12 below.

## C — invented design values

*(Updated 2026-10-05, task P2-T41.)* One invented design value and four
placeholders (two behavioural, two accessibility strings), all marked
`// SPEC-GAP` in `Kadence/`. Before P2-T39 this section read "None".

- **C5 — the spoken phrase for a block inside a protected window (GAPS
  G-030).** *(new 2026-10-05, task P2-T41.)* `BlockConflict.protectedWindow`
  speaks `conflicts with a protected window`, the string every conflicted
  block used to speak. Block-vs-block conflicts now use §11's own
  `conflicts with <title>`. §11 gives no form for the window kind.
- **C6 — tombstones are never discarded (GAPS G-031).** *(new 2026-10-05,
  task P2-T41.)* §13.7.4 says withdrawal "may" discard a tombstone. The
  placeholder keeps it, so reactivating a weekday doesn't bring back a day
  the user deleted. Only `⌘Z` on the delete removes it.

- **C4 — the needs-attention row's accessibility label and value (GAPS
  G-029).** *(new 2026-10-01, task P2-T40.)* `SidebarView` gives the row
  label `Needs attention` and value the bare count (`12`), both taken from
  what the row draws. No spec says what the row speaks. Before this, the row
  was an unnamed button, so VoiceOver said only "button".

- **C2 — the focused toggle inside the weekday toggle row (GAPS G-028).**
  `WeekdayToggleRow` (`RoutinesWindow.swift`) marks the toggle `←`/`→` have
  moved to with a `color.interactive.focusRing` stroke at `size.borderSelected`,
  `radius.chip`, inside the toggle's bounds. It shows only while the row has
  keyboard focus. The tokens exist, but this use of them is invented. No spec
  marks a focused item inside a toggle row.
- **C3 — removing the last active weekday is allowed (GAPS G-027).**
  `RoutineTemplateStore.setWeekday` doesn't refuse it. The template is left
  with an empty `activeWeekdays`, every column goes inactive with its
  `Add <Day>` button, and `⌘Z` restores it. This is a behaviour, not a visual
  value, but it is the same kind of placeholder, so it is listed here.

Two P2-T39 judgement calls that need no marker, because no value was invented:

- `←`/`→` in the toggle row **stop** at the first and last toggle instead of
  wrapping. §11.1.1 says only "move between the seven toggles".
- The time-window inspector's weekday row is now the same `WeekdayToggleRow`
  (layouts.md §8.1: "the same Mon-first toggle row the time-window inspector
  already uses"). Its look and its write are unchanged, and it gains the same
  `⇥`/`←`/`→`/`space` keyboard path.

P2-T40 judgement calls that need no marker, because no value was invented:

- **Horizon "through" is inclusive** (components.md §13.6.5). Day
  `today + 28` is materialised, so the exclusive end is the start of day
  `today + 29`. `(visible end) + 7` takes `CalendarState.visibleInterval.end`,
  which is already exclusive, so the last visible day + 7 is covered too.
  Read the other way, the horizon would be one day shorter.
- **The `Will not run` line is split at the dash** (§13.6.2: "one line,
  `inspectorLabel` / `inspectorValue`"): `Will not run —` in
  `inspectorLabel`, `inside Sleep (protected) on Mon, Wed, Fri` in
  `inspectorValue`. The label doesn't use the inspector's 84pt label column
  (it doesn't fit), and there is no gap between the two runs, only the
  sentence's own space. The value wraps rather than truncates.
- **One `Will not run` line per refusing window.** §13.6.2 shows one window.
  A block refused by two protected windows gets two lines, in the order the
  windows come from the store. Days are named with `shortWeekdaySymbols` in
  the window's column order (Mon-first here), the same source as `Add Sat`.
- **Refusal is compared in minutes-of-day per weekday**, not via
  `TimeWindow.spans(on:)`'s `startOfDay + seconds`. A block never crosses
  midnight (G-013), so the block and the window's spans on that weekday are
  enough, and it can't drift on a DST day. The canvas and `materialize` use
  the same function (`ProtectedWindowRule`), so they can't disagree.

P2-T41 judgement calls that need no marker, because no value was invented:

- **Withdrawal is folded into more steps than §13.6.4 lists.** §13.6.4 names
  three causes (weekday off, block deleted, newly refused). The third can be
  caused by a routine-block move or resize as well as any time-window edit,
  so `Move/Resize Routine Block` and every `TimeWindowStore` step except
  `Set Time Window Label` run the same withdrawal inside their own step.
- **The background pass withdraws too, unrecorded.** That is what makes
  undoing an edit that *added* pairs (`Add Saturday to Routine`) take the
  instances off again. It records nothing (§13.6.5 triggers are not user
  actions; see B16).
- **Withdrawal isn't bounded by the horizon**, only by `startOfDay(today)`:
  an instance created while the visible range reached further out is still
  withdrawn.
- **A withdrawal is a delete without a tombstone.** §13.7.4's tombstone
  records a day the user deleted. Withdrawal is the routine no longer
  containing it.
- **"Materialised instance" means `origin == .routine` with both ids set.**
  Only those get tombstones and updates. Hand-seeded `.routine` fixtures
  (no ids) and Phase 3 imports (`.imported`) are never touched.

- ~~**C1 — components.md §10.1, source swatch symbols.**~~ **Closed.** §10.1
  carries a normative table for all nine source kinds plus an unknown-kind
  fallback, and the code implements it: the symbol moved off `SourceKey` onto
  `CalendarSource` as a `symbol` defaulted from `CalendarSourceKind`, and
  `SourceSymbolTests` pins the table — including §10.1's rule that no source
  symbol may also be a block-kind glyph. GAPS.md records G-004 closed.

---

## A — specified but not built

### Canvas

- ~~**A1 — background windows do not span the time gutter.**~~ **Closed.**
  `TimedCanvasView.windowsBackdrop` draws one continuous layer behind gutter +
  every column, below the hour lines and below every block. The gutter takes the
  leading day's windows, since one gutter serves all seven columns.

- ~~**A2 — components.md §3.1, `size.blockVerticalGap` is never applied.**~~
  **Closed — this entry was stale, not newly fixed.** The previous audit said the
  token was unused; it is not. `DayLayoutEngine.applyVerticalGaps` (line 124) reads
  `Tokens.Size.blockVerticalGap` and is called from the engine's main path at line
  112, as a post-pass over the whole column. It shortens only blocks that have a
  follower sharing column space, so an isolated block still ends exactly on its
  end time. Re-verified by search this session.

- **A3 — components.md §4. A floored travel band does not rise above other
  blocks.** §4 says that when the floor applies the band "is drawn above other
  blocks in z-order but below the now line". It is inside its parent's `VStack`,
  so it inherits the parent's z-index and can be covered. *Still open.*

- **A4 — components.md §5 / §9 / layouts.md §3.2. Multi-day all-day items do not
  span columns.** They should be "one pill with square inner corners where they
  cross a day divider". `AllDayRowView` renders per day, so a multi-day item
  repeats once per column. Re-verified: `AllDayItemView.squareLeading` /
  `squareTrailing` exist (lines 15–16) and are read only by the view's own shape
  (lines 35–38) — **no caller anywhere passes either one.** *Still open.*

- **A5 — layouts.md §3.2. The all-day row does not scroll internally** past
  `size.allDayMaxRows`. Re-verified: `AllDayRowView:36` reads the token as a cap
  and shows the `+N` chip; the internal scroll is not implemented. *Still open.*

- **A6 — components.md §8. The now line does not span the full canvas in Day.**
  Re-verified: `NowLineView` is instantiated inside `DayColumnView` (line 101), so
  it is drawn per column in both modes. In Day the column is nearly the full
  width, so this is visually close but not what §8 says. *Still open.*

### Blocks

- **A7 — components.md §3.3. `DensityTier.usesEllipsis` is never consumed.**
  Tier 16–27 must truncate "with no ellipsis character"; SwiftUI's default `.tail`
  draws one. Re-verified: the only occurrence outside `Tokens.swift` is the
  property's own definition at `DensityTier.swift:35`. Nothing reads it.
  *Still open.*

- **A8 — components.md §11. `DensityTier.droppingOneTier()` is never called.**
  The ladder must be "evaluated against *resolved* text height, not against the
  default point sizes", so a large Dynamic Type setting should drop a tier.
  Re-verified: the only occurrence is the function's own definition at
  `DensityTier.swift:42`. The ladder is still evaluated against block height only.
  *Still open.*

- ~~**A9 — components.md §6, hover does not reveal resize handles.**~~
  **Closed — this entry was stale, not newly fixed.** The previous audit said
  `size.blockResizeHandleHeight` was used only for drag hit-testing and nothing was
  drawn. It is drawn. `GridBlockView` gates a hover branch on
  `presentation.contains(.hovered)` (line 103) which renders the 1pt inset ring and,
  when `model.isMovable`, a `resizeHandle` at top and bottom (lines 111–116);
  `resizeHandle` (line 236) is a `Rectangle` in `Tokens.Color.Interactive.hoverOverlay`
  at `Tokens.Size.blockResizeHandleHeight`. Hover state is plumbed from
  `DayColumnView.hoveredID` (lines 27, 205, 222). Handles are suppressed on
  non-movable blocks, matching interactions.md §4.

### Accessibility

- ~~**A20 — blocks are not exposed to the accessibility tree.**~~ **Closed.**
  Blocks, all-day pills and month chips reach the tree as `AXButton` elements —
  20 on the fixture week, up from **0**. Re-confirmed this session:
  `Scripts/check-accessibility.sh` → `PASS (elements present)`, 20 elements.

  Diagnosis, kept because the cause was not what the symptom suggested. The labels
  were always written correctly — they never arrived. Bisected against the running
  app:

  | Configuration | Result |
  |---|---|
  | `.accessibilityElement(children: .ignore)` + `.accessibilityLabel` | vended as an ignored `AXUnknown`; **absent** from the tree |
  | the same, plus `.accessibilityAddTraits(.isButton)` | still absent |
  | `.accessibilityElement(children: .combine)` + `.isButton` | **appears** as `AXButton` |

  Ruling out the wrong suspects mattered as much as finding the right one:
  removing the modifiers made the block's inner `Text` appear, proving the blocks
  render and the canvas is walkable; a canary element in the same `ZStack` was
  suppressed identically, proving it was not block-specific; removing
  `.focusable()` / `.onKeyPress` from the canvas changed nothing, clearing the
  container.

- **A20b — the §11 label still does not stick.** *(attempted, not fixed —
  unchanged this session, still needs a ruling)*
  Blocks are in the tree as `AXButton` but carry only the §3.4 hover-help string
  in `AXHelp`; `AXDescription` and `AXTitle` are empty, so VoiceOver does not read
  `title, time, kind, source, status`. Today's check-accessibility run reports it
  directly: `carrying the §11 label: 0`.

  The preferred route — make the block a real `Button` — was built, measured, and
  **does not fix it**. Six configurations, all against the running app:

  | Attempt | Elements in tree | §11 label |
  |---|---|---|
  | `.accessibilityElement(children: .ignore)` + label | 0 | — |
  | `.ignore` + label + `.isButton` | 0 | — |
  | `.accessibilityElement(children: .combine)` + `.isButton` | 20 | **discarded** |
  | real `Button` + `.buttonStyle(.plain)` + label | 20 | **discarded** |
  | real `Button`, content `.accessibilityHidden(true)` | 0 | — |
  | `.accessibilityRepresentation { Button(label) {} }` | 0 | — |

  The decisive measurement: with the real `Button`, an
  `.accessibilityIdentifier("kadence.block")` applied to the very same element
  (confirmed present on all 20) while `.accessibilityLabel` on the adjacent line
  did not. The modifiers reach the element; the label alone is dropped, because
  AppKit derives the element from the button's rendered content. Hiding that
  content to stop it removed the element entirely.

  The pattern across all six: in this hierarchy anything that *synthesizes* a
  replacement accessibility element is dropped, and only elements derived from
  real rendered content survive. That points at SwiftUI/AppKit behaviour in a
  deeply nested `ZStack`-with-offsets inside a `ScrollView` inside a
  `NavigationSplitView`, not at the modifier choice.

  **Stopped here rather than compromising the interaction model**, per the
  standing instruction. The label content is correct and unit-tested; only the
  delivery is wrong, and the hover-help string does carry title, time, source and
  kind — so the information is reachable, just not as the element's name and not
  in §11 order.

  Next candidates, in order, each needing a decision because each trades
  something: (a) reshape the block so the §11 string is its *only* rendered text
  at the AX layer — a real change to how content is composed; (b) drop to
  `NSViewRepresentable` for the block and vend `NSAccessibilityElement` directly
  — full control, at the cost of leaving SwiftUI for the busiest view in the app;
  (c) file it against SwiftUI and ship the hover-help carrier as the interim.

### Chrome and appearance

- **A10 — components.md §11. Reduce Transparency is unhandled.** Re-verified by
  search: `color.surface.sidebarMaterial`, `.toolbarMaterial`, `.popoverMaterial`
  and `color.interactive.accentSystemName` have **zero** references outside
  `Tokens.swift`. The app never draws the platform material, so there is nothing
  to fall back *from*. The literal colours are always used — which is the Reduce
  Transparency branch, so the app is correct in that mode and wrong in the default
  one. *Still open.*

- ~~**A21 — components.md §10.2. The needs-attention row draws an icon, and §10.2
  now forbids one.**~~ **Closed 2026-09-18, task P2-T15.** *(was: new 2026-09-10 —
  created by the spec amendment, not by a code change)*
  `SidebarView.swift:29` rendered `Image(systemName: "tray.full")` on the
  needs-attention row. The amended §10.2 says, in as many words: **"The row takes
  no icon."** It is the only non-source row in that list; its text and count
  already separate it from the swatch-prefixed source rows, and §10.2 records that
  this closes a collision found on 2026-09-09 — `tray.full` sits a few rows above
  the Coursework source's `tray.2.fill` (§10.1) in the same list at the same size,
  two trays in one sidebar.

  Fixed while building the needs-attention row's real behaviour (P2-T15, which
  also had to touch this view to make the row a button): the `Image` is deleted,
  and the row is `if !state.conflicts.isEmpty` per §10.2's "hidden entirely at
  zero" rule. §10.2's follow-on rule still applies to anything added later: no
  chrome symbol without first checking §10.1 and the kind glyphs in §2.1, §3.2
  and §5.

### Interaction

- ~~**A11 — region focus cycling is absent.**~~ **Closed, and its one remaining
  gap is now closed too.** `⇥` / `⇧⇥` cycle sidebar → all-day row → grid →
  inspector and wrap, skipping the all-day row when hidden and the inspector when
  collapsed. The rule is a pure function (`CalendarState.FocusRegion.next`) with
  13 tests. Each region draws the standard focus ring per §1, which is why the
  grid no longer sets `.focusEffectDisabled()`.

  **The toolbar-is-not-a-stop gap is resolved by the spec, not by code.** The
  previous audit flagged this as a deviation because §1 listed the toolbar first.
  **interactions.md §1 was amended 2026-09-10** and now reads: *"Amended
  2026-09-10: the toolbar is not a focus stop. The original list opened with it
  and then miscounted its own regions as four."* §1 now specifies exactly the
  four regions the build implements, in the order it implements them, and notes
  that Full Keyboard Access is the expected route to window chrome and that every
  toolbar action has a key equivalent and a menu item. `FocusAvailabilityTests.toolbarExcluded`
  already asserts the omission is deliberate. **The build was right; the spec has
  caught up. No code change needed.**

- ~~**A12 — the time cursor prints no time in the gutter.**~~ **Closed, and the
  spec conflict it raised is closed with it.** The cursor time is printed in the
  gutter in `hourLabel` / `color.interactive.accent`, suppressing a colliding hour
  label by the same 12pt rule the now time uses (§8). Shown only while the grid is
  focused and the cursor is on a visible day.

  **The gutter conflict is genuinely resolved — the spec text itself changed.**
  This was checked directly rather than taken from GAPS.md's narration, because a
  gap is only closed when the resolution is written into the spec file. It was.
  `design/components.md` §7 now reads:

  > **The label never enters the time gutter.** The gutter carries hour labels,
  > the now time, and the keyboard time cursor's time (`interactions.md` §1) — and
  > nothing else. **Amended 2026-09-10:** the original rule named only hour labels
  > and the now time, which contradicted `interactions.md` §1. §1 wins; the cursor
  > time suppresses a colliding hour label by the same 12pt rule the now time uses
  > (§8). Window labels remain banned from the gutter, which is what this rule was
  > written to prevent.

  components.md §7's own preamble to the Phase 2 material confirms the amendment
  was intentional and in place: *"the amendments to §6, §7 and §10.2 above are
  marked in place and were ruled on 2026-09-10."*

  So the previous entry's "the two specs still disagree" is **no longer true**.
  §7 and §1 now agree, they agree with what was built, and window labels remain
  banned from the gutter — which the build also honours. `design/GAPS.md`'s tail
  narrates the same resolution; the difference is that the normative text now
  carries it. Nothing to change in the code.

- ~~**A13 — inline title editing on create is stubbed.**~~ **Closed.** A new event
  is an `EventDraft` held in `CalendarState`, laid out and drawn like a block (so
  it packs and cascades with everything else) but **never in the store**.
  `EventStore.commit(_:)` is the only path that persists one, and it refuses a
  draft with no usable title. §3's rule — "an event created with no title is never
  persisted; cancelling and committing an empty field both remove it" — is
  therefore true by construction rather than by cleanup: there is nothing to
  delete because nothing was written.

  **Behaviour note:** losing focus abandons the draft, per the instruction that
  ⎋, focus loss and an empty title all count as abandonment. The trade-off is that
  a title typed and then clicked away from is lost; committing a non-empty title
  on blur is a one-line change in `DraftBlockView` if that reads better in use.

  **Correction 2026-09-10 (P2-T01): as shipped, this feature crashed the app.**
  The entry above described the design correctly and the behaviour not at all —
  `↩` in the draft field took the whole process down before any of it could
  happen. `DayColumnView.draftBlock` handed `DraftBlockView` a binding built with
  `Binding($state.draft)`, i.e. SwiftUI's `BindingOperations.ForceUnwrapping`,
  which unwraps in its *getter*, on every read. Committing clears
  `CalendarState.draft` from inside the field's own event handling, SwiftUI then
  reads the field's bindings again while tearing it down, and the getter trapped
  on nil. Fixed by `CalendarState.draftBinding()`; `KadenceTests/DraftBindingTests.swift`
  covers the transition. The "losing focus abandons the draft" behaviour note
  below was written from the code, not from use — see A22, `⎋` never reached it.

  Found while testing it: `commit` and `duplicate` **inserted twice** —
  `UndoStack.perform` runs its `redo` closure immediately, and both also inserted
  directly, producing two rows with the same `id`. Pre-existing in `create` and
  `duplicate`; caught only because these tests run against a real in-memory store
  rather than a stub.

- **A14 — interactions.md §4. `⇧` (same-day constraint) and `⌥`-drag duplicate are
  not wired.** `EventStore.duplicate` exists; re-verified this session that no
  gesture path calls it. *Still open.*

- **A15 — interactions.md §4. No time badge follows the pointer** during a drag.
  Re-verified: no drag-badge view exists. *Still open.*

- **A16 — interactions.md §5. Delete leaves no dashed outline** in the vacated slot
  for `motion.outlineHold`. Re-verified: `outlineHold` has **zero** references
  outside `Tokens.swift`. *Still open.*

- **A17 — interactions.md §7.1. Only step 1 of the block-move transition exists.**
  The spring is there; the level-2 lift during travel, the arrival outline hold,
  scroll-into-view-first, and page-then-place are not. This is the transition the
  spec calls the one place motion earns its keep. *Still open.*

- **A18 — interactions.md §8. Cursors are half-wired.** *(rewritten 2026-09-10 —
  the previous entry, "No cursors are set. No `NSCursor` anywhere", was wrong)*
  `Shapes.swift:118–142` defines a `cursor(_:)` modifier that push/pops an
  `NSCursor` on hover, with matched push/pop. Two of the five §8 rows are wired,
  in `DayColumnView`:

  | §8 context | Spec | Built |
  |---|---|---|
  | Over empty grid | `.crosshair` | **yes** — `DayColumnView:289` |
  | Over a draggable block | `.openHand` | **yes** — `DayColumnView:203` |
  | …`.closedHand` while dragging | `.closedHand` | **no** |
  | Over a resize handle | `.resizeUpDown` | **no** |
  | Over a non-draggable block | `.arrow` | **yes** — same line, ternary |
  | …`.operationNotAllowed` on drag attempt | `.operationNotAllowed` | **no** |
  | Over a region divider | `.resizeLeftRight` | **no** |

  What is missing is every *transient* cursor — the ones that change during a
  gesture rather than on hover — plus the divider. The hover cases are done.

- **A19 — interactions.md §9. Undo does not restore selection.** §9 says undo
  restores "the selection state that was in effect". Mutations are named and
  undoable; `⌘Z` puts the data back, not the user. Re-verified: no selection
  snapshot is captured or restored. *Still open.*

- **A22 — interactions.md §3. `⎋` does not cancel an in-flight draft.** *(new
  2026-09-10, found while fixing the P2-T01 crash)* §3: "`↩` commits; `⎋` cancels
  and removes the block entirely." `↩` works. `⎋` does nothing at all — the
  draft stays on the grid with its field still focused. Established under
  instrumentation on a debug build (temporary `print` in
  `DraftBlockView.onExitCommand` and in the `isFieldFocused` `onChange`): with
  the field focused, `⎋` fires **neither**. The field editor swallows it before
  `.onExitCommand` sees it and does not resign first responder either, so the
  blur path does not fire as a backstop. The only ways out of a draft today are
  `↩` and clicking away.

  Not fixed in P2-T01, which was scoped to the crash. Note the ordering: this
  defect was *masking* half of that crash. Once `⎋` is wired up it will run the
  same `discardDraft()` path `↩` runs, which is exactly what trapped — so it
  must not be wired up on a tree without the `draftBinding()` fix. That fix is
  in, so the way is clear. *Still open.*

- **A23 — interactions.md §2. `⌘N` opens a second window instead of creating an
  event.** *(new 2026-09-10, found while reproducing P2-T01)* §2 lists `⌘N` as
  "New event at the time cursor, else at the next half hour", global.
  `KadenceCommands` adds its "New Event" item with `CommandGroup(after: .newItem)`
  and `.keyboardShortcut("n", modifiers: .command)`, but the stock `WindowGroup`
  "New Window" item keeps `⌘N` too. Two menu items, one key equivalent; AppKit
  picks New Window. Observed directly: pressing `⌘N` on the running build opened
  a second Kadence window and started no draft. The menu item itself works when
  clicked. The toolbar `+` also works. *Still open.*

- **A24 — components.md §11. One block reports itself as selected to
  accessibility when nothing is selected.** *(new 2026-09-11, found while
  building the P2-T02 click regression check)* §11 gives each block one
  accessibility element; `GridBlockView` adds the `.isSelected` trait only when
  `presentation` contains `.selected`, which AppKit vends as `AXSelected`. On a
  pristine launch, with nothing selected and the pointer parked off-window,
  exactly one block — "Statistik übung" in the mock data — reports
  `AXSelected = true`. It also keeps reporting `true` while a *different* block
  is selected, which single selection makes impossible. VoiceOver would announce
  a block as selected when it is not.

  **Not our trait.** Established by deleting the
  `.accessibilityAddTraits(presentation.contains(.selected) ? [.isSelected] : [])`
  line from `GridBlockView` entirely, rebuilding, and re-querying: the element
  *still* reported `AXSelected = true`. So the attribute is coming from the
  SwiftUI/AppKit accessibility bridge, not from anything this build asks for.

  Two plausible causes were tested and **refuted**: the block's `.done` status
  (the checkmark glyph merging into `children: .combine` — flipping the fixture
  to `.scheduled` changed nothing) and hover (reproduced with the pointer at
  5,5). Not root-caused further; it was out of P2-T02's scope, and P2-T02 needed
  only to stop being fooled by it. Real selection changes are reported correctly
  on every other block, and correctly on this one too — its baseline is just
  stuck at `true`.

  `Scripts/check-block-click-selects.sh` handles it by only ever choosing a
  click target that reads *not selected* at baseline, and asserting on the
  transition. *Still open.*

### Routines

- **A25 — components.md §13.4. Detached instances (tracking, Re-sync, the
  inspector's "Edited — differs" line) are entirely unbuilt.** *(new
  2026-09-24, task P2-T28, giving this a proper A-list home; first surfaced by
  task P2-T27 while attempting to capture `screenshots/2/` batch 1's items 4–5
  and logged only in that task's `screenshots/2/INDEX.md` and in the scattered
  task-preamble notes above — see "detached-instance" in this file's earlier
  blocks, most recently P2-T21's note at `STATUS.md` §21 and P2-T25's at
  `STATUS.md` §25.)* §13.4 specifies three things together, none of which
  exist: per-occurrence detachment tracking when a routine-materialized event
  is hand-edited on the main grid, a Re-sync button (with a confirmation
  popover) to restore a detached occurrence to its template, and a main-grid
  inspector line reading "Edited — differs" for a detached occurrence.

  P2-T27 confirmed this by search rather than assumption —
  `grep -rn "isDetached\|Detached\|Re-sync\|resync\|differs from\|instances
  edited\|Revert to routine"` across `Kadence/` returns nothing but the
  `resyncPopoverWidth` token itself (unused by any view) and
  `RoutinesWindow.swift`'s own comments recording the gap. Concretely:
  `RoutineEngine.materialize` only guards against re-creating an event that
  already exists for a given `(sourceID, externalID)` pair — it has no concept
  of "this occurrence was hand-edited," so it cannot distinguish an edited
  instance from an untouched one; `EventStore.move`/`resize` have no special
  case for a `.routine`-origin event at all, so editing one on the main grid
  is indistinguishable from editing any other event; and
  `RoutinesWindow.swift`'s `RoutineInspectorView.templateSummary` carries a
  comment explaining exactly this — the edited-instance count is always zero,
  so the row is omitted, not stubbed. Full grep evidence, the exact commands,
  and the three images that could not be produced because of this
  (`routine-detached-instances.png`, `routine-resync-popover.png`,
  `routine-detached-instance-selected.png`) are in
  `screenshots/2/INDEX.md`'s "What could not be captured" section — not
  reproduced here to avoid duplication. *Still open* — building it is a
  separate, much larger `RoutineEngine`-level task, out of scope for both
  P2-T27 and P2-T28. See `STATUS.md` §28.

- **A26 — components.md §14.3. Only the "two options, recommended always
  first" subset of "two or three options, recommended usually but not
  necessarily first" is built.** *(new 2026-09-25, task P2-T29 retry, while
  capturing `screenshots/2/` batch 2's conflict-panel images.)* §14.3: "Two or
  three per conflict... Options are ordered by disturbance, least first. The
  recommended one is usually but not necessarily first." `ConflictEngine.
  makeOptions` (`Kadence/State/ConflictEngine.swift`, lines 344–367) only ever
  appends one flexibility-derived option (or none) plus one skip option — at
  most two `RawOption`s reach `finalize`, never three — and `finalize` (lines
  444–464) always sorts strictly ascending by `disturbanceMinutes` and marks
  index 0 `isRecommended`, so the recommended option is always the
  least-disturbance one and always first. No fixture can exercise the
  three-option case or a non-first recommendation because no code path
  produces either; this is a structural cap in `makeOptions`/`finalize`
  themselves, confirmed by reading the functions, not by exhausting fixture
  attempts. Full citation and reasoning: `design/GAPS.md` **G-017**. The
  built two-option, always-first-recommended case is captured in
  `screenshots/2/conflict-panel-two-options.png` (components.md §17 item 6's
  two-option half); item 6's three-option half and item 7 (a non-first
  recommendation) are the parts this entry covers as *not built*. *Still
  open* — closing it needs an `ConflictEngine` change (a third option source
  and/or a ranking rule that can diverge from strict disturbance-ascending),
  out of scope for a capture task. See `STATUS.md` §31.

- ~~**A27 — interactions.md §10.1. `↩` apply of a previewed conflict option
  (built by P2-T17, `CalendarState.applyFocusedConflictOption`) could not be
  made to visibly commit through real HID key events in this session.**~~
  **Closed 2026-09-26, task P2-T37 — this was a real code defect, now fixed.**
  *(new 2026-09-25, task P2-T32, while capturing `screenshots/2/` batch 4's
  count-0 image; root-caused and fixed by P2-T37, not re-investigated from
  scratch.)* Not confirmed as a code defect at the time — recorded as an open
  question, not a ruling. Everything upstream worked and was visually
  confirmed: clicking a conflict option row previewed it (blue highlight,
  the accent canvas border appeared), and `↑`/`↓` moved the preview between
  options once `state.focusedRegion == .inspector` (`↓` correctly moved from
  the shorten option to the skip option, confirmed by the highlighted row
  changing). Pressing `↩` (virtual keycode 36, via the same `kkey` HID-event
  helper batches 2–3 already used successfully for scrolling/keys) in that
  same state never visibly changed the canvas or the sidebar count, across
  several different sequences for reaching `.inspector` focus (a direct
  click into the panel; one or more `⇥` cycles via `MainWindow.cycleFocus`
  before `↓`/`↩`). At the time, `handleKey`'s `.return where
  state.focusedRegion == .inspector && state.selectedConflictID != nil &&
  state.selectedConflictOptionID != nil` case (`MainWindow.swift` ~line 488)
  was suspected of being gated on a stale `state.focusedRegion` — a
  hand-tracked flag kept in sync with SwiftUI's own `@FocusState` by a
  one-directional `.onChange` — diverging from real first-responder state.

  **P2-T37's actual root cause, found by reading the code: `state.focusedRegion`
  was never the problem.** The `.return` case above was correct and, by the
  time it runs, `state.focusedRegion` genuinely does read `.inspector` — the
  key event simply never reached `handleKey` at all. `MainWindow.swift`'s
  `inspector` computed view attached
  `.onKeyPress(keys: [.upArrow, .downArrow, .escape], action: handleKey)` — a
  keys-*filtered* hook. SwiftUI dispatches a key only to the `.onKeyPress`
  hooks along the currently-*focused* view's own chain; the grid's separate,
  unfiltered `.onKeyPress(action: handleKey)` includes `.return`, but only
  fires when the grid (not the inspector, a sibling view) holds focus. So
  with real focus on the inspector, `.return` was dropped before `handleKey`
  ever ran, regardless of what `state.focusedRegion` held — exactly
  consistent with §33's observation that everything routed through the
  inspector's own filtered hook (`↑`/`↓`, preview) worked, and only `.return`
  (the one key missing from that hook's list) did not. Not an environmental/
  synthetic-HID artifact, as this entry had left open as a possibility — a
  real, deterministic dispatch-layer gap. Fixed by adding `.return` to that
  hook's key list; see `STATUS.md` §36 for the full account and
  `Scripts/check-conflict-apply-return.sh` for the regression check (an
  interaction-level check in this repo's own house style, since
  `KadenceTests/ConflictApplyTests.swift` drives
  `CalendarState.applyFocusedConflictOption` directly and cannot see the
  SwiftUI key-routing layer the bug lived in). That script's own live HID/AX
  run was itself deferred by a locked screen at the time P2-T37 ran (see
  `STATUS.md` §36) — the code fix and the full `KadenceTests` suite are
  green independent of that.

- ~~**A28 — components.md §13.6.3 / §13.6.4 / §13.7. Materialisation only
  creates.**~~ **Resolved 2026-10-05, task P2-T41**, except the detachment
  flag, which is P2-T43's (see A31). `materialize` implements §13.6.3's
  whole table (create / update / leave detached / leave tombstoned) and
  `RoutineEngine.withdraw` implements §13.6.4, folded into the causing step
  for weekday-off, block delete/move/resize and every time-window edit. *(was:)* *(new 2026-10-01, task P2-T40.)* `materialize` now has call
  sites (launch, template/block/window edits, visible-range changes), but it
  never updates an existing instance to the template's current values,
  never withdraws instances the template stopped producing, and has no
  detachment flag or tombstone. So moving a template block doesn't move
  existing instances, deactivating a weekday or deleting a block leaves its
  future instances on the calendar, and an edit that stops a refusal adds
  instances while one that starts a refusal removes none. P2-T41 is the
  update/withdrawal table. Tombstones (§13.7.4) are not scheduled in any
  task this file knows of.
- ~~**A29 — components.md §13.7.4. A deleted materialised instance comes back,
  and undoing its delete can then duplicate it.**~~ **Resolved 2026-10-05,
  task P2-T41.** `EventStore.delete` leaves a `RoutineTombstone` keyed by
  `(sourceID, externalID)` in the delete's own step; `materialize` never
  recreates a tombstoned pair; `⌘Z` restores the one original row and
  removes the tombstone (pinned by `TombstoneTests`). *(was:)* *(new 2026-10-01, task
  P2-T40. This is a consequence of A28 that only exists now that
  `materialize` has call sites.)* `⌫` on a routine instance removes the row.
  The next trigger (paging the calendar, any routine edit, relaunch) finds no
  event for that `(sourceID, externalID)` and creates it again. If the user
  then presses `⌘Z` on the original delete, `EventStore` re-inserts the old
  snapshot alongside the recreated one: two events with the same identity.
  Tombstones close both. Not covered by a test yet, because the fix is
  §13.7.4's, not this task's.
- **A30 — components.md §13.6.2 third surface and §14.6.** *(new 2026-10-01,
  task P2-T40.)* A refused pair doesn't reach the needs-attention count, and
  that row doesn't route to the Routines window. The canvas `conflicted`
  presentation and the inspector `Will not run …` line are built. Marked
  `// P2-T46` in `RoutineInspectorView.blockDetails`.
- **A31 — components.md §13.7.1 / §13.6.3 row 3. Until P2-T43, every
  materialised instance counts as undetached, so a main-grid edit to one is
  overwritten by the next materialisation pass.** *(new 2026-10-05, task
  P2-T41. Temporary, by the brief's design.)* §13.6.3 now updates untouched
  instances, and `RoutineDetachment.isDetached` (the single `// P2-T43` seam)
  returns `false` for everything, because there is no detached flag yet. So
  moving `Gym` on Wednesday's column holds only until the next trigger
  (paging, any routine edit, relaunch), which moves it back to the template's
  time. Status edits (done/skipped) are unaffected: an update carries status
  forward. Hand-seeded `.routine` fixtures (`Training`, `Focus review`, …)
  have no `(sourceID, externalID)` and are never touched. P2-T43 replaces the
  seam.

---

## B — built, but not the way the spec describes

- ~~**B1 — cascade applied the step-2 insets.**~~ **Closed.** Block *i* has a
  leading inset of exactly `min(i, maxSteps) × indent` and spans to the trailing
  edge, so the narrowest block is `columnWidth − 3 × indent`. It was 4pt narrower.
- ~~**B2 — z-order was per cluster.**~~ **Closed**, now global across the column.
- ~~**B3 — the `+N` chip was nudged by a hardcoded 28pt.**~~ **Closed**, anchored
  to the cluster's top trailing corner, and drawn above every block in the
  cluster per the revised §3.3.
- ~~**B10 — the indent had a lower clamp.**~~ **Closed:** `min(round(w × ratio), max)`,
  no floor. `blockCascadeIndentMin` is gone from the spec and the code.
- ~~**B11 — a covered block rendered its full content and got clipped.**~~
  **Closed.** `LaidOutBlock` carries `visibleWidth`, `resolveBlockStyle` takes it,
  and below `size.blockCascadeMinReadableWidth` (44) the block drops to the
  glyph-only content set whatever its height. `BlockStyle.contentTier` is the
  single source of truth for which content set renders.
- ~~**B12 — the source name never appeared as text (§3.4).**~~ **Closed.** Tier ≥ 44
  renders `Source · Location` on the meta line, and every block, band, pill and
  month chip carries `Title · HH:mm–HH:mm · Source · Kind` as hover help.

Still open, all re-checked against the current spec text this session:

- **B4 — components.md §3.1. Glyph baseline alignment is approximate.** §3.1 wants
  the glyph aligned to "the first text baseline's cap height". `GridBlockView:248`
  uses `.alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }` — a magic 1pt, not
  derived from cap height. The comment above it claims cap-height alignment, which
  makes it read as done when it is approximated.
- **B5 — components.md §3.3. The clamped hit region is centred on the clamped
  frame, not the true one.** §3.3 says "centred on the true frame".
- **B6 — components.md §7. Protected only beats low-energy on full containment.**
  A low-energy window that *partially* overlaps a protected one still draws its
  hatch over the overlap. §7's current text is unchanged on this point and still
  says, flatly: "Overlapping windows: protected wins. Never render both treatments
  in the same region."
- **B7 — layouts.md §1.1. The inspector overlay is a `ZStack` layer,** not a
  presented overlay. It reads correctly and sits at `elevation.level2`, but it does
  not dim or dismiss like a real overlay.
- **B8 — layouts.md §3.1. `T` / Today does not scroll the current time to 1/3 from
  the top.** Initial scroll uses `min(07:00, firstEventStart − 1h)` as specified
  (`TimedCanvasView:58`); the Today-key behaviour is not implemented.
- ~~**B13 — layouts.md §3.3 / components.md §3.1. A block paints outside its
  laid-out frame.**~~ **Closed 2026-09-11, task P2-T05.** *(was: new
  2026-09-11, task P2-T03, diagnosed not fixed.)* §3.3 gives every block an
  exact frame and the whole overlap system depends on those frames being what
  is drawn. They were not: `GridBlockView` never constrained itself to its own
  `renderedHeight` parameter, and its caller sized it with
  `.frame(height: laidOut.frame.height)` at `DayColumnView.swift:194`, which
  took SwiftUI's **default `.center` alignment** and did not clip — so whenever
  a tier's content set was taller than the frame it was derived from, the block
  overflowed **symmetrically, in both directions**, damaging its neighbours as
  well as itself ("Stand-up" / "Check mail" at 12:30/12:50, and
  "Datenmodellierung" in Week — see the measurements this entry used to carry,
  now in STATUS.md §1.7's historical diagnosis).

  Fixed by implementing `design/GAPS.md` G-011's new components.md §3.5
  confinement invariant — the rule this entry said the spec was missing:
  `GridBlockView` and `DraftBlockView` now apply
  `.frame(height: renderedHeight, alignment: .top)` **before** `.clipShape`,
  content is laid out `alignment: .topLeading` (not the SwiftUI default), and
  `DayColumnView`'s own `.frame(height:)` also gained `alignment: .top` as a
  second, independent lock on the same rule. Verified with a pixel-level render
  of the two named fixtures (`KadenceTests/BlockConfinementTests.swift`) showing
  no ink in the gap between them. See STATUS.md §1.7.

- **B9 — interactions.md §6. Selection survives view changes but does not scroll
  into view.** *(corrected 2026-09-11, task P2-T02)* §6: "switching Week → Day
  keeps the same block selected and scrolls it into view." The keeping works;
  the scrolling is not implemented. *Still open — the scroll half is unchanged
  by P2-T02.*

  **What the old wording got wrong.** As written it implied selection worked,
  full stop. It did not: until P2-T02, **clicking a block selected nothing at
  all**, so the only way to select anything was the keyboard (`↖`/`↘`, `↑`/`↓`).
  That path was what this entry was actually written from. Mouse selection was
  broken outright — a defect, not a deviation — and is now fixed; see
  STATUS.md §1.6. The scroll-into-view gap is genuinely separate: it is a
  missing behaviour, it was not caused by the hit-region bug, and fixing the
  hit region did not close it.

- **B14 — components.md §15.1. The status item's time is no longer
  structurally protected from truncation, and the 2026-10-01 "below the
  budget" rule is not built.** *(new 2026-10-01, task P2-T38, recording hand
  commit `0d81c96`. See `STATUS.md` §38.)* §15.1: "The time comes first and is
  never truncated ... The title truncates tail-first inside whatever the time
  leaves." Before `0d81c96` this held by construction: the time was its own
  `.fixedSize()` `Text` and only the title could shrink. `0d81c96` merged them
  into one `Text("\(primary) · \(title)")` with `.truncationMode(.tail)`.
  The fix was needed: the separate truncatable `Text` collapsed to zero
  width inside a `MenuBarExtra` label, so the title never showed at all. The
  cost is that truncation now applies to the whole string. The time is
  first, so the title goes first in practice, but nothing stops the time
  itself being cut once the item is given less than the time's own width.
  The rule DA added on 2026-10-01 is not built either: show the time
  **alone**, with no separator or ellipsis, once less than
  `size.statusItemTitleMinWidth` (32) is left for the title. Today a narrow
  item shows a stub such as `17:30 · T…`. The token now exists in
  `Tokens.swift` (regenerated by P2-T38) but nothing reads it. *Still open.*
  Building it is a separate status-item task, outside P2-T38's scope.
- **B15 — components.md §15.1. The status item is always exactly
  `size.statusItemMaxWidth` wide.** *(new 2026-10-01, task P2-T38, recording
  `0d81c96`.)* §15.1 calls 180 "a budget, not a guarantee". `0d81c96` changed
  `.frame(maxWidth: statusItemMaxWidth)` to `.frame(width:
  statusItemMaxWidth)` + `.fixedSize()`, so the label always asks for the full
  180pt, even for `13:29 · Journal` or `Nothing left today`, and reserves
  that menu-bar space whatever the content. This is read from the code. The
  committed crops are tight to the text, so they neither confirm nor rule out
  the empty padding. *Still open*, same task as B14.
- **B16 — components.md §13.6.4 / §14.6 / interactions.md §11.2. Background
  materialisation is not part of the edit that caused it.** *(Narrowed
  2026-10-05, task P2-T41.)* Withdrawal now IS part of its causing step
  (`Remove Saturday from Routine`, `Delete Routine Block`, block move/resize,
  every time-window edit), so `⌘Z` restores template and instances together.
  Creates and updates still come from the background pass. Its cost is
  gone: the background pass now also withdraws, so undoing `Add Saturday to
  Routine` or `Create Routine Block` takes the instances back off the
  calendar on the next pass, and redo brings them back (new ids).
  `Resolve Routine Conflict` (§14.6) re-materialising inside its own step is
  still P2-T46's. *(Original text:)* *(new
  2026-10-01, task P2-T40.)* The spec folds materialisation into the
  causing step (`Remove Saturday from Routine` undoes the deletions;
  `Resolve Routine Conflict` re-materialises inside its step). The P2-T40
  triggers run from `.onChange` *after* the edit's step has closed, and they
  write with `EventStore.insertUnrecorded`, which records no step at all.
  Launch and paging are not user actions, so the alternative (an
  `Undo Materialize …` step on top of the user's own) would make `⌘Z` remove
  routine instances instead of undoing the user's edit. The cost: undoing
  `Add Saturday to Routine` or `Create Routine Block` leaves the instances
  that edit created, until P2-T41's withdrawal removes them. `materialize`
  still joins an open step when called inside one (pinned by
  `MaterializationHorizonTests.joinsOpenStep`), so P2-T41 and P2-T46 can call
  it inside their steps.
- ~~**B17 — components.md §14.1, "The needs-attention row is a button". Only
  its drawn text and badge are clickable.**~~ **Resolved 2026-10-05, task
  P2-T41:** `.contentShape(Rectangle())` on the label. A real HID click at the
  row's centre (the Spacer gap) opened the conflict panel in
  `check-conflict-apply-return.sh`'s run. *(was:)* *(new 2026-10-01, found by task
  P2-T40, not fixed: out of scope.)* The row is a `.plain` `Button` whose
  label is `HStack { Text; Spacer(); badge }`. A `.plain` button only
  hit-tests what it draws, so the `Spacer` gap between `Needs attention` and
  the count does nothing when clicked. Measured live at 1500×900: a real
  click at the row's centre (x 203, just past the text) left the inspector
  unchanged; a click on the text (x 133) and an `AXPress` both opened the
  panel. This is where `Scripts/check-conflict-apply-return.sh` fails next,
  because it clicks the row's centre. The likely fix is a `contentShape` on
  the label, so the whole row is the target.

- ~~**B18 — test fixture, not a spec value. `MockData`'s `Journal` fixture
  collides with routine fixtures depending on what time the store is
  seeded.**~~ **Resolved 2026-10-05, task P2-T41**, in both places.
  `MockData.journalStart` still starts Journal at least 4 minutes after
  `now` (P2-T34's purpose) but pushes it past every interval a conflict
  could involve (hand-seeded `.routine` events, anything overlapping one,
  and today's and tomorrow's template blocks), so it never creates or joins
  a conflict. And the script launches with
  `-KadenceConflictUnderTest "Focus review"`
  (`CalendarState.conflictUnderTest`, a launch-argument test hook that is
  inert otherwise), so it opens that pair explicitly instead of relying on
  it sorting first. `MockDataClockTests` seeds at 12 clock times on a
  template and a non-template day and pins the count (12), the pair, and its
  first place. *(was:)* `Journal` is seeded at `now + 4 … now + 19` minutes (P2-T34, for
  the status item). Seeded between about 16:41 and 17:45 it overlaps
  `Training` (17:00–17:45, `.routine`), and between about 19:41 and 21:26 it
  overlaps `Focus review` or `Reading`. That conflict then sorts first, so
  the needs-attention row opens it instead of `Focus review` /
  `Client call`, and `Scripts/check-conflict-apply-return.sh` fails at
  `no 'Shorten Focus review' option row found` (observed at 16:43). It also
  adds a 13th conflict to the sidebar count.

---

## Resolved — retired by a spec ruling

Entries that recorded a judgement call made against a spec silence, retired
once DA wrote the ruling into `design/` **and** `design/GAPS.md` recorded it
CLOSED (CONTEXT.md's definition of closed). Kept verbatim so the reasoning
stays on record. Moved here by task P2-T38, 2026-10-01.

- ~~**P2-T16 — the `.skipToday` preview treatment.**~~ **Resolved by
  `design/GAPS.md` G-014 — CLOSED (2026-10-01), written into `components.md`
  §14.4:** "the ghost dim is the whole preview for a destination-less option."
  No code change was needed. *Original entry:* §14.4's wording ("every block
  the option would move") is written for shift/shorten and does not say what
  previewing a skip looks like — `.skipToday`'s `newStart`/`newEnd` are `nil`,
  so there is no destination frame to draw a dashed twin at. This engine's
  answer: the real block just dims to `opacity.blockDragOrigin` (the ghost),
  and no dashed twin is drawn at all — `ConflictPreviewFrames.resolve`
  returns `proposed == nil` for this kind, and `DayColumnView` only draws the
  `.previewed` twin when `proposed` is non-nil. Filed as `design/GAPS.md`
  G-014 rather than invented.

- ~~**P2-T17 — `ConflictEngine.detect` excludes a `.skipped` routine
  occurrence.**~~ **Resolved by `design/GAPS.md` G-015 — CLOSED (2026-10-01),
  written into `components.md` §14.5:** "a `.skipped` routine occurrence is
  not an overlap." It applies to the `.routine` side only and only for
  `.skipped`, never `.done`. That is exactly the single `guard` P2-T17 added,
  so no code change was needed. *Original entry:* Without it, applying
  `.skipToday` — which by design (G-014) never touches the occurrence's
  `start`/`end` — could not make `detect`'s plain interval-overlap check stop
  reporting the very pair it was just applied to, so "advances to the next
  conflict, or resolves to normal" could never actually progress for that
  option kind. The fix is one `guard` in the pairing loop, reasoned from
  `EventStore.toggleSkipped`'s own pre-existing doc comment ("puts the item
  back in the pool to be re-offered... never a failure state"): an occurrence
  put back in the pool is not still occupying the slot it was skipped out of.

- ~~**P2-T11 — routine block drags clamp at the day boundary.**~~ **Resolved
  by `design/GAPS.md` G-013 — CLOSED (2026-10-01), written into
  `interactions.md` §11.1** ("Cross-midnight drags clamp"). This confirms the
  placeholder `RoutineBlockStore` clamp, which `create` reuses. P2-T38 replaced
  `RoutineEngine.swift`'s `SPEC-GAP` comment with a reference to §11.1, so
  C's "no `// SPEC-GAP` markers left in `Kadence/`" is true again. (It had
  been stale since P2-T11.) The entry this retires is the judgement call in
  the P2-T11 preamble paragraph near the top of this file.

- ~~**`5b73949` — inactive weekday columns refuse block creation (hand fix,
  unspecced).**~~ **Resolved by `design/GAPS.md` G-018 — CLOSED, written into
  `components.md` §13.5 and `interactions.md` §11.1, and completed by task
  P2-T38.** `5b73949` disabled the create surface and draft layout on
  inactive columns with no spec behind it. It was never logged here, and it
  stands now as the spec's refusal rule. P2-T38 added what the hand fix
  lacked: the `.operationNotAllowed` cursor, draft abandonment on
  deactivation, the §13.5.2 column treatment, the §13.5.3 note, and the
  vertical-only drag with its multi-column preview. See `STATUS.md` §37 and
  §39.

## Not a deviation — worth stating

- **`MockData.makeEvents`'s item 19, the `Journal` fixture** (`.manual`/
  `.graphite`, currently `now.addingTimeInterval(4 * 60)`–`now.addingTimeInterval(19 * 60)`).
  Added by task P2-T33 (commit `ae8a369`) as a controllable target so
  `NextUpProvider` — which always resolves the *earliest* not-done/
  not-skipped event of today as NEXT, not the soonest-still-upcoming one —
  has a genuine "not yet started" event available for components.md §17 item
  10's Normal/Late menu-bar-status-item captures late in the day, when every
  other seeded today fixture has already started. P2-T34 (commit `c7699c5`)
  fixed its original hardcoded `at(23, 35)`/`at(23, 50)` times (which only
  reproduced Normal before 23:35 wall-clock and Late only a few minutes
  after) to the current `now`-relative offsets, which hold regardless of
  when seeding runs. Not a spec deviation — this is mock data supporting a
  capture task, kept permanently per the same precedent `STATUS.md` §33
  already set for its own count-12 conflict-fixture addition (item 18); it
  changes no test's or existing capture's rendered layout, since it is
  the last today-dated event chronologically and no other fixture shares its
  time range. See `STATUS.md` §34 for the P2-T35 bookkeeping closeout and
  the capture attempt this fixture was added for, and §35 for P2-T36's
  follow-up retry, which found the screen still locked and made no further
  changes to this fixture.
- `⌘1/⌘2/⌘3`, `⌘T`, `T`, `←`/`→`, `⌘N`, `↩`, `⌫`, `⌘↩`, `⌥⌘↩`, `⌥`-arrows,
  `⌥⇧`-arrows, `↑`/`↓`, `⎋`, `↖`/`↘`, `⌃⌘S`, `⌥⌘I`, `⌘Z` are all wired, and each
  is a menu item with the same key equivalent.
- Dropping into a protected window is allowed, with the alert-coloured preview
  outline (interactions.md §4) — deliberately not blocked.
- The empty day reads "Nothing scheduled": no illustration, no encouragement.
- Skipped and done are visual siblings; no red, no counter, no strikethrough.
- Peak-focus windows render nothing on the calendar canvas. §7 was extended on
  2026-09-10 with an **editor exception** — peak focus *is* drawn, as a dashed
  outline in `color.window.peakFocusEdge`, but "only inside the Routines window's
  windows mode (§13.3), never on the calendar canvas." *(Updated 2026-09-17,
  task P2-T10: a Routines window now exists, but its Windows mode does not —
  there is still no `TimeWindow` model and no `[Blocks | Windows]` mode
  control, which §13.3 needs, so there is still nothing to draw this outline
  in. Still not a deviation, for the same reason, just a narrower one than
  before.)* *(Updated 2026-09-18, task P2-T18: a persisted `TimeWindow` model
  now exists (data layer only — `Kadence/Models/TimeWindow.swift`), but the
  `[Blocks | Windows]` mode control §13.3 needs still does not, so there is
  still nothing to draw this outline in. Still not a deviation, still the
  same narrower reason as above.)* **(Updated 2026-09-19, task P2-T20: the
  mode control now exists, and the Routines window's windows mode now draws
  this exact outline — `BackgroundWindowsLayer`'s new `showsPeakFocus`
  parameter, true only there. This line is no longer describing an unbuilt
  exception; it is describing what the build does.)** The calendar canvas
  rule is unchanged and the build still honours it — peak-focus still renders
  nothing on the main Day/Week grid, in either mode.

---

## Not listed here on purpose

- **The 18:00 cascade in `screenshots/week-full-dark.png`** — the magenta / blue
  / dashed pile-up Parsa flagged. Measured against `DayLayoutEngine` at the
  reproduced 152.14pt Week column: 3-block cluster, slot width
  `(152.14 − 4) / 3 − 2` = 47.38, below `size.dayColumnCascadeThreshold` (72),
  so §3.3 step 3 is *supposed* to fire; indent 22, x = 0 / 22 / 44, visible
  widths 22 / 22 / 108, glyph-only below `size.blockCascadeMinReadableWidth`
  (44), z-order by start. Every one of those matches the pixels. It looks like a
  defect and is not one. Recorded here so the next task does not "fix" it.

- **`Tokens.swift` is one design pass behind `design/tokens.json`** and
  `generate-tokens.swift --check` is red at `HEAD`. That is not a spec deviation —
  it is a generated artefact that was not regenerated when `1c58185` added 67
  Phase 2 tokens. `STATUS.md` §1.1 and §5 carry it.
- **The Phase 1 screenshot set does not exist**, though root `INDEX.md` describes
  16 files by name. `STATUS.md` §2.2 carries it.
