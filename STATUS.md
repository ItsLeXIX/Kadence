# Status

Updated: 2026-09-09
Phase: **1 — the calendar.** Built. Builds clean, 70/70 tests pass, runs.

## How to verify

```
swift Scripts/generate-tokens.swift --check    # tokens in sync, no hand edits
xcodebuild -scheme Kadence -destination 'platform=macOS' build
xcodebuild -scheme Kadence -destination 'platform=macOS' test
```

All three were run on this Mac (Xcode 26.6, Swift 6.3.3) before this was written:
`** BUILD SUCCEEDED **`, `** TEST SUCCEEDED **`, 70 passed / 0 failed.
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
  outline. Every mutation is undoable and **named** — the Edit menu reads
  "Undo Move Event".

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

## Blocked / needs your ruling

- **`SWIFT_VERSION = 5.0`.** `BRIEF-PRODUCT.md` specifies Swift 6 strict
  concurrency. Everything written is Swift 6-clean, but flipping the setting is a
  `project.pbxproj` edit, outside the `Kadence/` write scope. One line, and the
  Core Data template that would have fought it is already gone. Say the word.
- **`design/GAPS.md` G-004 — the sidebar source symbols.** components.md §10.1
  makes the symbol load-bearing for the no-colour-only-meaning rule but specifies
  none. This is the one place I picked a design value; it is marked `// SPEC-GAP`
  and needs the design side.
- Six other gaps logged (G-003, G-005 … G-008), none blocking.

## Not done, on purpose

- `⌘Z` is wired to SwiftData's undo manager with named actions, but the undo
  *stack depth* and redo behaviour have not been exercised beyond a single step.
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
