# Status

Updated: 2026-09-09
Phase: **1 — the calendar.** Built, then reworked for the 17:14 spec revision.
Builds clean, 149/149 unit tests pass.

## How to verify

```
swift Scripts/generate-tokens.swift --check    # tokens in sync, no hand edits
./Scripts/check-accessibility.sh               # blocks reach the AX tree (A20)
xcodebuild -scheme Kadence -destination 'platform=macOS' build
xcodebuild -scheme Kadence -destination 'platform=macOS' -only-testing:KadenceTests test
```

All three were run on this Mac (Xcode 26.6, Swift 6.3.3) before this was written:
`** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`, 149 passed / 0 failed.

Use `-only-testing:KadenceTests`. A plain `test` also runs the empty UI-test
template, whose runner fails on this machine with "Timed out while enabling
automation mode" and turns the whole run red for no reason.
The app was launched and Month / Week / Day were each exercised — no crash, and
each toolbar title matches layouts.md §1.2 (`September 2026`, `7 – 13 Sep 2026`,
`Wed 9 Sep 2026`).

## Done

### Design system
- `Scripts/generate-tokens.swift` → `Kadence/DesignSystem/Tokens.swift`.
  259 constants, every one cross-checked against `tokens.json`. Never hand-edited;
  `--check` fails the build if it is stale or edited.
- `TypeStyle` — the `typography.*` groups as applyable styles. Fonts are built
  with `@ScaledMetric(relativeTo:)` against each token's `textStyle`, so explicit
  point sizes still scale with Dynamic Type.
- `SourceKey` — the eight palette slots. Hue carries source and nothing else.
- `Elevation`, `BlockStyle`, `RailStyle`, `BadgeSpec`.
- `resolveBlockStyle` — one pure function, no view or environment dependencies,
  consumed by all three block views. 30 tests.

### Models (SwiftData)
- `Event`, `Place`. The Core Data template (`Persistence.swift`,
  `ContentView.swift`, `Kadence.xcdatamodeld`) is gone — the brief says SwiftData.
  Recoverable from commit `6a615c1` if you want to look at it.
- **One correction to the brief's model:** `colorTag` is replaced by `sourceKey`.
  components.md §1 makes hue mean *source and nothing else*, so a free colour tag
  would be a second, conflicting hue channel. The palette slot is derived from
  the source, never chosen per event.
- `origin`, `status`, `flexibility`, `sourceKey` persist as raw strings — keeps
  the store readable and migration-friendly for when Phase 3 writes imports into it.
- Display-only fixtures for what Phase 1 has no services for: `TravelFixture`,
  `AllDayFixture`, `TimeWindowFixture`, `CalendarSource`. Not persisted.

### Layout
- `DayLayoutEngine` — layouts.md §3.3 in full: cluster → column-pack → cascade,
  pure functions over value types, no SwiftUI and no clock. 22 tests, including
  the spec's own numbers: 22pt indent at a 114pt Week column, Week cascades where
  Day packs, every cascaded block keeps a rail and a glyph visible, `+N` past five.
- `DensityTier` — the four tiers by rendered height, never duration.
- `TimeGeometry` — time↔point, snapping (15 min, 5 with `⌃`), and the clamp
  duration the engine uses.

### Views
- Three block geometries: `GridBlockView`, `TravelBandView`, `AllDayItemView`,
  plus `MonthChipView` for the compressed month row. All driven by the resolver —
  not one view with six branches (DECISIONS.md 2026-09-09).
- Canvas layers: background windows (protected/low-energy, below the grid lines,
  spanning the gutter), hour and half-hour lines, time gutter, now line.
- `TimedCanvasView` (Week and Day share the machinery), `MonthGridView` (always
  six rows), `DayHeaderRow`, `AllDayRowView` (hidden entirely when empty).
- `SidebarView` (sources with symbol swatches, filters), `InspectorView` (day
  summary when nothing is selected, never a placeholder graphic), toolbar, menus.
- Create by double-click, drag, `⌘N` or the `+` button; drag to move; drag the
  edges to resize; delete with `⌫`. Drop preview with the protected-window alert
  outline. Every mutation is undoable and **named** — see the undo section below.

### Mock data
- `MockData` — components.md §12's sixteen fixtures on one day grid, seeded once
  and idempotent.

## Three defects found by actually running it

Worth recording, because none would have been caught by reading the code:

1. **Adaptive colours were not equatable.** `NSColor(name:dynamicProvider:)`
   returns a fresh catalog colour on every call, so two reads of the *same* token
   compared unequal. That silently broke `Equatable` on `BlockStyle` and made
   SwiftUI treat every render as a change. Fixed in the **generator** (the cache
   is in `TokenSupport`, so it regenerates) — not by patching `Tokens.swift`.
2. **`.opacity(1)` is not the same value as the bare colour.** The Increase
   Contrast branch of the routine border wrapped the colour in a modifier instead
   of dropping it. Fixed by branching rather than always calling `.opacity`.
3. **Two sidebar toggles and two View menus.** `NavigationSplitView` installs its
   own sidebar toggle and SwiftUI owns a View menu; mine were duplicates. Fixed
   with `.toolbar(removing: .sidebarToggle)` and by moving the items into
   `CommandGroup(after: .sidebar)`. Also caught: the inspector button announced
   itself to VoiceOver as "sidebar.trailing".

A fourth, from the accessibility tree: the now-time in the Week gutter was placed
by absolute offset from the grid's first day rather than by clock time, so it
landed two days down the ruler. Fixed with `TimeGeometry.yForTimeOfDay`, with a
test.

## Swift 6 — done, with one exception

I previously reported the app target was on Swift 5. **That was wrong** — a
`sort -u` collapsed the grep output and I read it off the wrong build config.
The app target was already `SWIFT_VERSION = 6.0` with
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so all Phase 1 code has been
compiling in Swift 6 language mode from the start.

What actually needed changing was the *test* targets, which were on 5.0:

- `KadenceTests` → Swift 6.0 + `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`
  (needed: `Tokens` is MainActor-isolated in the app, so the test target has to
  match or its file-level constants fail to compile). Builds and passes.
- `KadenceUITests` → **left on Swift 5.0.** The XCTestCase template overrides
  are nonisolated and produce 11 isolation errors under MainActor-by-default.
  It contains no tests of ours and its runner cannot start on this machine
  anyway ("Timed out while enabling automation mode"). Not worth converting now.

`project.pbxproj` before the change is at `/tmp/pbxproj.before` for this session;
the committed version is in `6a615c1`.

## The 17:14 cascade revision — applied

`design/tokens.json`, `layouts.md` and `components.md` were revised mid-build
(worked from a screenshot of the running app). All of it is now implemented:

- `dayColumnCascadeThreshold` 96 → 72, so Week **packs** the common two-block
  overlap and cascades only the pile-up. At this window (1680pt, ~153pt columns)
  a 2-up packs and a 3-up cascades, which is the intent.
- `blockCascadeIndentMin` removed; indent is `min(round(w × ratio), max)`.
- **New:** a block whose *visible* width is under
  `blockCascadeMinReadableWidth` (44) drops to glyph-only whatever its height —
  a clipped title reads as damage, not as occlusion. `LaidOutBlock.visibleWidth`
  → `resolveBlockStyle` → `BlockStyle.contentTier`.
- The `+N` chip now draws above every block in its cluster.
- **New §3.4:** the source name is required as text at tier ≥ 44
  (`Source · Location`), and every block, band, pill and chip carries
  `Title · HH:mm–HH:mm · Source · Kind` as hover help.

Ten tests cover it, including the spec's own worked table (184pt column: 2-up
packs, 3-up cascades; 114pt and 78pt cascade).

## Undo — rebuilt (2026-09-09)

**Correction to what this file previously claimed.** It said ⌘Z was "wired to
SwiftData's undo manager with named actions". It was not: `EventStore` read
`context.undoManager`, and nothing ever assigned one. The container was created
without undo support, so `undoManager` was always `nil` and every
`beginUndoGrouping` / `setActionName` call was a no-op. Undo was not one step
deep — it did nothing at all.

Replaced with an explicit inverse-command stack, `Kadence/State/UndoStack.swift`:

- **Depth.** `UndoStack.defaultDepth = 50`, overridable per instance
  (`UndoStack(depth:)`, which the tests use). Oldest steps fall off the bottom.
- **Grouping.** `EventStore.transaction("Resolve Conflict") { … }` records
  everything inside it as ONE step. `perform` is **re-entrant**: a composite
  operation is written by calling the ordinary verbs (`store.move`,
  `store.toggleSkipped`), and because a group is already open they join it
  instead of pushing steps of their own. The outermost name is the one the user
  sees. That is the shape Phase 2 needs — conflict resolution applying 2–3
  changes, and the routine engine materialising many blocks — without either
  duplicating the verbs or leaving three separate steps behind them.
- **Named.** `CommandGroup(replacing: .undoRedo)` supplies the Edit menu items,
  so it reads "Undo Move Event" / "Redo Resolve Conflict", disabled when empty.
- **Redo.** Full branch, cleared when a new action diverges from history.

Two details that are load-bearing rather than incidental:

- **Events are addressed by `id`, resolved at execution time.** Undoing a delete
  cannot resurrect a deleted `@Model` instance, so the event returns as a new
  object carrying the same `id`. No undo closure holds an `Event` reference, so
  an event can be deleted, restored and moved again in any order.
- **A replay guard.** Undo closures call back into the same code paths that
  record. Without it, one ⌘Z would push a fresh step and the stack would never
  empty. There is a test for exactly that.

Why not `ModelContext.undoManager`: it groups by begin/end pairs around whatever
SwiftData registers per property, which is the wrong grain for "these three
edits are one user action", and it cannot survive the object identity change
that undoing a delete forces.

**Verified end to end in the running app**, not only by unit test: with an empty
stack the Edit menu reads `Undo` / `Redo`, both disabled; after File ▸ New Event
it reads `Undo New Event`, enabled; clicking that leaves `Undo` disabled and
`Redo New Event` enabled.

18 new tests (`KadenceTests/UndoStackTests.swift`) cover depth and its bound,
grouping and reverse-order unwind, re-entrancy, the interleaved
single → group → single case unwinding one press at a time, redo round-trip,
redo invalidation, the replay guard, and the menu titles.

## A1, A11, A12 — done (2026-09-09)

- **A1 / review D-3 — background windows span the gutter.** The layer moved out
  of `DayColumnView` (which starts after the gutter) into
  `TimedCanvasView.windowsBackdrop`: one continuous canvas layer behind gutter +
  every column, below the hour lines and below every block. §7's point is that
  the edges stay visible when a column is full of blocks, which needs the band to
  cross the gutter. The gutter takes the leading day's windows, since one gutter
  serves all seven columns.
- **A11 — `⇥` region cycling.** sidebar → all-day row → grid → inspector, wrapping,
  skipping the all-day row when hidden and the inspector when collapsed. The rule
  is a pure function (`CalendarState.FocusRegion.next`) with 13 tests. Each region
  draws the standard focus ring per §1, so the grid no longer disables it.
  **Gap: the toolbar is not a `⇥` stop.** §1 lists it first, but SwiftUI toolbar
  items are not addressable as a focus region without adding a phantom item;
  macOS reaches the toolbar via Full Keyboard Access. A test asserts the omission
  is deliberate rather than an oversight.
- **A12 — cursor time in the gutter**, `hourLabel` / `color.interactive.accent`,
  suppressing a colliding hour label by the same rule the now time uses.

**Spec conflict to reconcile.** components.md §7 (revised 17:15) says the gutter
carries hour labels and the now time "and nothing else may be drawn in it".
interactions.md §1 puts the cursor time in the gutter. Built per §1 on your
instruction; the two specs still disagree.

**Also noticed, not fixed (out of scope):** `CalendarState.isSidebarVisible` and
the split view's `columnVisibility` are two sources of truth for the same thing
and are not kept in sync — the Edit-menu toggle writes one, auto-collapse writes
the other. A11 sidesteps it by reading `columnVisibility` directly.

## Sidebar visibility — one source of truth (2026-09-10)

`CalendarState.isSidebarVisible` is now the only stored sidebar state. The split
view's `columnVisibility` is derived from it (`sidebarColumnVisibility`) through a
binding that writes back, so all four paths move the same value: the Edit-menu
toggle, the toolbar button, width-driven auto-collapse, and the split view's own
divider. Previously the menu wrote `isSidebarVisible` while auto-collapse wrote a
separate `@State columnVisibility`, so the menu could offer "Hide Sidebar" for a
sidebar that was already hidden.

The §1.1 rule — auto-collapse must never overwrite an explicit choice — now lives
in exactly one place, `setSidebarVisible(_:isUserAction:)`. A change arriving from
the split view's own divider counts as explicit, or the next resize would undo it.
8 tests in `SidebarVisibilityTests`, plus `availableFocusRegions` reads the same
flag so `⇥` can never land on a sidebar that is not on screen.

The inspector was already single-source (`isInspectorVisible`) and is unchanged.

## A13 — creation is commit-or-discard (2026-09-10)

A new event is an `EventDraft` held in `CalendarState`. It is laid out and drawn
like a block — it packs and cascades with everything else, and carries the
inline `TextField` §3 asks for — but it is **never in the store**.
`EventStore.commit(_:)` is the only path that persists one, and it refuses a
draft with no usable title.

That makes §3's rule true by construction rather than by cleanup: there is
nothing to delete on cancel because nothing was written. The old flow inserted
first and deleted on cancel, which is what left untitled events behind whenever
the delete did not happen.

- `⌘N`, the toolbar `+`, double-click and drag-create all call
  `CalendarState.beginDraft`; none of them touch SwiftData.
- `↩` commits and selects the result. `⎋` and an empty title discard.
- `UndoStack.discardLastStep` is gone — it existed only to paper over the old
  insert-then-cancel flow.

**Behaviour note, worth a second look in use:** losing focus abandons the draft,
following the instruction that ⎋, focus loss and an empty title all count as
abandonment. The cost is that a title typed and then clicked away from is lost.
Committing a non-empty title on blur is a one-line change in `DraftBlockView`.

**A bug this surfaced.** `commit` and `duplicate` inserted the event **twice** —
`UndoStack.perform` runs its `redo` closure immediately, and both also inserted
directly, so two rows appeared with the same `id`. Pre-existing in `create` and
`duplicate` and invisible until now: the new tests run against a real in-memory
`ModelContainer` rather than a stub, which is the only reason it showed up.

**The stray event is gone.** `MockData.removeUntitledEvents` sweeps empty-title
events at launch — a repair for stores written by the older build, since an
untitled event is now impossible to create. Two tests cover the sweep and its
no-op case.

## Accessibility check — 20, as expected

`./Scripts/check-accessibility.sh` → **PASS, 20 block elements** (was 21). The
extra one was the stray untitled 23:30–00:30 event; the sweep removed it, and the
count now matches the 20 renderable fixtures exactly — 21 timed fixtures with
Overlap 6 correctly hidden behind the cascade's `+1` chip.

The A20b warning still stands and is unchanged: blocks reach the tree, but carry
the hover-help string rather than the §11 label.

## Blocked / needs your ruling

- **`DEVIATIONS.md`** — full punch list of where the build does not match the
  frozen spec: 17 absent, 6 built differently, **0 invented values**, 0 open
  spec contradictions. Read that before Phase 2.
- ~~`design/GAPS.md` G-004 — the sidebar source symbols.~~ **Closed.** §10.1 is
  normative and the code implements it. **There are no invented design values
  left in the codebase.**
- **A20b in `DEVIATIONS.md`** — A20 is fixed (blocks reach the accessibility
  tree: 20 elements, up from 0). A20b is **attempted and not fixed**: six
  configurations measured against the running app, including the preferred real
  `Button` route, and the §11 label is discarded in every one that produces an
  element at all. Evidence table and next candidates are in DEVIATIONS.md.
  Needs a decision — every remaining option trades something.
- G-006 and G-009 are **closed** by the 17:14 revision. Five gaps remain
  (G-003, G-005), neither blocking. G-004, G-006, G-007, G-008 and G-009 are
  closed.

## Not done, on purpose

- Undo: see the section above. Selection restoration (interactions.md §9's
  "undo restores the selection state that was in effect") is still **not** done —
  DEVIATIONS.md A19. ⌘Z puts the data back, not the user.
- Inline title editing on a newly created block: the event is created and
  selected, and `inlineEditingEventID` is set, but the in-place `TextField` in
  the block is not yet wired — you name it in the inspector instead. It is the
  one thing in interactions.md §3 that is stubbed rather than built.
- `⇥` region cycling and the full focus-order model (interactions.md §1) are
  partial: the grid is focusable and handles its own keys, but the four-region
  cycle is not implemented.
- Everything in Phases 2–6, per the scope rule.

## Next

1. Reconcile the gutter conflict below.
2. Finish the three partial items above — they are all Phase 1 scope.
3. Then Phase 2 (routines, conflicts, protected time, menu bar extra), not before.
