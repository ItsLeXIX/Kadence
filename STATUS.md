# Status

Updated: 2026-09-09
Phase: **1 — the calendar.** Built, then reworked for the 17:14 spec revision.
Builds clean, 117/117 unit tests pass, runs.

## How to verify

```
swift Scripts/generate-tokens.swift --check    # tokens in sync, no hand edits
./Scripts/check-accessibility.sh               # blocks reach the AX tree (A20)
xcodebuild -scheme Kadence -destination 'platform=macOS' build
xcodebuild -scheme Kadence -destination 'platform=macOS' -only-testing:KadenceTests test
```

All three were run on this Mac (Xcode 26.6, Swift 6.3.3) before this was written:
`** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`, 117 passed / 0 failed.

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

## Blocked / needs your ruling

- **`DEVIATIONS.md`** — full punch list of where the build does not match the
  frozen spec: 19 absent, 9 built differently (3 now fixed), 1 invented value,
  2 spec contradictions. Read that before Phase 2.
- **`design/GAPS.md` G-004 — the sidebar source symbols.** components.md §10.1
  makes the symbol load-bearing for the no-colour-only-meaning rule but specifies
  none. This is the one place I picked a design value; it is marked `// SPEC-GAP`
  and needs the design side.
- **A20b in `DEVIATIONS.md`** — A20 is fixed (blocks reach the accessibility
  tree: 20 elements, up from 0). A20b is **attempted and not fixed**: six
  configurations measured against the running app, including the preferred real
  `Button` route, and the §11 label is discarded in every one that produces an
  element at all. Evidence table and next candidates are in DEVIATIONS.md.
  Needs a decision — every remaining option trades something.
- G-006 and G-009 are **closed** by the 17:14 revision. Five gaps remain
  (G-003, G-004, G-005, G-007, G-008), none blocking except G-004.

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

1. Rule on Swift 6 and on G-004.
2. Finish the three partial items above — they are all Phase 1 scope.
3. Then Phase 2 (routines, conflicts, protected time, menu bar extra), not before.
