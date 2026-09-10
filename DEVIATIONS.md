# Phase 1 — deviation punch list

Every place the implementation does not match the frozen spec, audited
2026-09-09 against `design/components.md`, `design/layouts.md` and
`design/interactions.md`, **re-audited after the 17:14–17:15 spec revision**
(cascade rework + new §3.4). Verified by reading the code, not from memory —
where an item says "token unused", that was checked with a search.

Legend: **A** absent · **B** built differently · **C** value I invented (none remain) ·
**D** spec contradiction · ~~struck~~ = fixed in this pass.

Counts: A ×14 · B ×6 · C ×0 · D ×0 — plus 13 items fixed across five passes.

---

## D — spec contradictions

**Both closed by the 17:14 revision.** The designer removed
`size.blockCascadeIndentMin` entirely (the floor was dead — GAPS G-006/G-009) and
restated the narrowest block as "42pt at the absolute minimum", consistent with
`indent = min(round(w × ratio), max)` and no lower clamp. D2 stays resolved by
the `increaseContrast` parameter (GAPS G-003).

---

## C — invented design values

**None.** There are no invented design values left in the codebase.

- ~~**C1 — components.md §10.1, source swatch symbols.**~~ **Closed.** §10.1 now
  carries a normative table for all nine source kinds plus an unknown-kind
  fallback, and the code implements it: the symbol moved off `SourceKey` onto
  `CalendarSource` as a `symbol` defaulted from `CalendarSourceKind`, the
  `// SPEC-GAP` marker is gone, and `SourceSymbolTests` pins the table — including
  §10.1's rule that no source symbol may also be a block-kind glyph.
  GAPS.md records G-004 closed with the section reference.

---

## A — specified but not built

### Canvas
- ~~**A1 — background windows do not span the time gutter.**~~ **Fixed**
  (also review D-3). `BackgroundWindowsLayer` no longer lives inside
  `DayColumnView`, which starts after the gutter. `TimedCanvasView.windowsBackdrop`
  draws one continuous layer behind gutter + every column, below the hour lines
  and below every block, so a protected or low-energy band reads as one band
  across the whole grid and its edges stay visible when a column is full — which
  §7 says is the only time they matter. The gutter takes the leading day's
  windows, since the gutter is shared by all seven columns.

- **A2 — components.md §3.1. `size.blockVerticalGap` is never applied.** The
  token is unused; vertically adjacent blocks in one sub-column touch. Frames
  come straight from the time geometry with no 2pt separation.
- **A3 — components.md §4. A floored travel band does not rise above other
  blocks.** §4 says when the floor applies it "is drawn above other blocks in
  z-order but below the now line". It is inside its parent's `VStack`, so it
  inherits the parent's z-index and can be covered.
- **A4 — components.md §5 / §9 / layouts.md §3.2. Multi-day all-day items do
  not span columns.** They should be "one pill with square inner corners where
  they cross a day divider". `AllDayRowView` renders per day, so a multi-day
  item repeats once per column. `AllDayItemView.squareLeading` /
  `squareTrailing` exist and are never passed by any caller.
- **A5 — layouts.md §3.2. The all-day row does not scroll internally** past
  `size.allDayMaxRows`. The `+N` chip is shown; the internal scroll is not.
- **A6 — components.md §8. The now line does not span the full canvas in Day.**
  It is drawn per column in both modes. In Day the column is nearly the full
  width, so this is close but not what §8 says.

### Blocks
- **A7 — components.md §3.3. `DensityTier.usesEllipsis` is never consumed.**
  Tier 16–27 must truncate "with no ellipsis character"; SwiftUI's default
  `.tail` draws one. The property exists and nothing reads it.
- **A8 — components.md §11. `DensityTier.droppingOneTier()` is never called.**
  The ladder must be "evaluated against *resolved* text height, not against the
  default point sizes" — so a large Dynamic Type setting should drop a tier. It
  is evaluated against block height only.
- **A9 — components.md §6. Hover does not reveal resize handles.**
  `size.blockResizeHandleHeight` is used for hit-testing in the drag gesture but
  nothing is drawn.

### Accessibility
- ~~**A20 — blocks are not exposed to the accessibility tree.**~~ **Fixed.**
  Blocks, all-day pills and month chips now reach the tree as `AXButton`
  elements: 20 present on the fixture week, up from **0**. Verify with
  `Scripts/check-accessibility.sh`.

  Diagnosis, because the cause was not what the symptom suggested. The labels
  were always written correctly — they simply never arrived. Bisected against
  the running app:

  | Configuration | Result |
  |---|---|
  | `.accessibilityElement(children: .ignore)` + `.accessibilityLabel` | element vended as an ignored `AXUnknown`; **absent** from the tree |
  | the same, plus `.accessibilityAddTraits(.isButton)` | still absent |
  | `.accessibilityElement(children: .combine)` + `.isButton` | **appears** as `AXButton` |

  Ruling out the wrong suspects mattered as much as finding the right one:
  removing the modifiers entirely made the block's inner `Text` appear, which
  proved the blocks render and the canvas is walkable; a canary element inside
  the same `ZStack` was suppressed identically, which proved it was not
  block-specific; and removing `.focusable()` / `.onKeyPress` from the canvas
  changed nothing, which cleared the container.

- **A20b — the §11 label still does not stick.** *(attempted, not fixed)*
  Blocks are in the tree as `AXButton` but carry only the §3.4 hover-help string
  in `AXHelp`; `AXDescription` and `AXTitle` are empty, so VoiceOver does not
  read `title, time, kind, source, status`.

  The preferred route — make the block a real `Button` — was built and measured
  and **does not fix it**. Six configurations, all against the running app:

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
  did not. So the modifiers reach the element and the label alone is dropped —
  AppKit derives the element from the button's rendered content instead. Hiding
  that content to stop it removed the element entirely.

  The pattern across all six: in this hierarchy anything that *synthesizes* a
  replacement accessibility element is dropped, and only elements derived from
  real rendered content survive. That points at SwiftUI/AppKit behaviour in a
  deeply nested `ZStack`-with-offsets inside a `ScrollView` inside a
  `NavigationSplitView`, not at the modifier choice.

  **Stopped here rather than compromising the interaction model**, per the
  standing instruction. The label content is correct and unit-tested; only the
  delivery is wrong, and the hover-help string does currently carry title, time,
  source and kind — so the information is reachable, just not as the element's
  name and not in §11 order.

  Next candidates, in order, each needing a decision because each trades
  something: (a) reshape the block so the §11 string is its *only* rendered text
  at the AX layer — a real change to how content is composed; (b) drop to
  `NSViewRepresentable` for the block and vend `NSAccessibilityElement` directly
  — full control, at the cost of leaving SwiftUI for the busiest view in the app;
  (c) file it against SwiftUI and ship the hover-help carrier as the interim.

### Chrome and appearance
- **A10 — components.md §11. Reduce Transparency is unhandled.**
  `color.surface.sidebarMaterial`, `.toolbarMaterial`, `.popoverMaterial` and
  `color.interactive.accentSystemName` (plus siblings) are all unused. The app
  never draws the platform material, so there is nothing to fall back *from*.
  The literal colours are always used — which is the Reduce Transparency
  branch, so the app is correct in that mode and wrong in the default one.

### Interaction
- ~~**A11 — region focus cycling is absent.**~~ **Fixed, with one gap.**
  `⇥` / `⇧⇥` now cycle sidebar → all-day row → grid → inspector and wrap,
  skipping the all-day row when hidden and the inspector when collapsed. The
  rule is a pure function (`CalendarState.FocusRegion.next`) with 13 tests, so
  the skipping and wrapping are checked rather than tabbed through by hand. Each
  region draws the standard focus ring, per §1, which is why the grid no longer
  sets `.focusEffectDisabled()`.
  **The toolbar is not a stop.** §1 lists it first, but SwiftUI toolbar items are
  not addressable as a focus region without a phantom item; macOS reaches the
  toolbar through Full Keyboard Access instead. Asserted as deliberate in
  `FocusAvailabilityTests.toolbarExcluded`.
- ~~**A12 — the time cursor prints no time in the gutter.**~~ **Fixed.** The
  cursor time is printed in the gutter in `hourLabel` / `color.interactive.accent`,
  and suppresses a colliding hour label by the same 12pt rule the now time uses.
  Shown only while the grid is focused and the cursor is on a visible day.
  **Spec conflict, flagged:** components.md §7 (revised 17:15) says the gutter
  carries hour labels and the now time "and nothing else"; interactions.md §1
  puts the cursor time there. Built per §1 on Parsa's instruction — the two need
  reconciling.
- ~~**A13 — inline title editing on create is stubbed.**~~ **Fixed.** A new event
  is now an `EventDraft` held in `CalendarState`, laid out and drawn like a block
  (so it packs and cascades with everything else) but **never in the store**.
  `EventStore.commit(_:)` is the only path that persists one, and it refuses a
  draft with no usable title. §3's rule — "an event created with no title is
  never persisted; cancelling and committing an empty field both remove it" — is
  therefore true by construction rather than by cleanup: there is nothing to
  delete because nothing was written.

  **Behaviour note:** losing focus abandons the draft, per the instruction that
  ⎋, focus loss and an empty title all count as abandonment. The trade-off is
  that a title typed and then clicked away from is lost; committing a non-empty
  title on blur is a one-line change in `DraftBlockView` if that reads better in
  use.

  Found while testing it: `commit` and `duplicate` **inserted twice** —
  `UndoStack.perform` runs its `redo` closure immediately, and both also inserted
  directly, producing two rows with the same `id`. Pre-existing in `create` and
  `duplicate`; caught only because these tests run against a real in-memory
  store rather than a stub.
- **A14 — interactions.md §4. `⇧` (same-day constraint) and `⌥`-drag duplicate
  are not wired.** `EventStore.duplicate` exists with no gesture path to it.
- **A15 — interactions.md §4. No time badge follows the pointer** during a drag.
- **A16 — interactions.md §5. Delete leaves no dashed outline** in the vacated
  slot for `motion.outlineHold`. The token is unused anywhere.
- **A17 — interactions.md §7.1. Only step 1 of the block-move transition
  exists.** The spring is there; the level-2 lift during travel, the arrival
  outline hold, scroll-into-view-first, and page-then-place are not. This is
  the transition the spec calls the one place motion earns its keep.
- **A18 — interactions.md §8. No cursors are set.** No `NSCursor` anywhere:
  `.crosshair`, `.openHand`/`.closedHand`, `.resizeUpDown`,
  `.operationNotAllowed` all missing.
- **A19 — interactions.md §9. Undo does not restore selection.** Mutations are
  named and undoable; `⌘Z` puts the data back, not the user.

---

## B — built, but not the way the spec describes

- ~~**B1 — cascade applied the step-2 insets.**~~ **Fixed.** Block *i* now has a
  leading inset of exactly `min(i, maxSteps) × indent` and spans to the trailing
  edge, so the narrowest block is `columnWidth − 3 × indent`. It was 4pt narrower.
- ~~**B2 — z-order was per cluster.**~~ **Fixed**, now global across the column.
- ~~**B3 — the `+N` chip was nudged by a hardcoded 28pt.**~~ **Fixed**, anchored
  to the cluster's top trailing corner — and now drawn above every block in the
  cluster, per the revised §3.3.
- ~~**B10 — the indent had a lower clamp.**~~ **Fixed** for the 17:14 revision:
  `min(round(w × ratio), max)`, no floor. `blockCascadeIndentMin` is gone.
- ~~**B11 — a covered block rendered its full content and got clipped.**~~
  **Fixed.** `LaidOutBlock` now carries `visibleWidth`, `resolveBlockStyle` takes
  it, and below `size.blockCascadeMinReadableWidth` (44) the block drops to the
  glyph-only content set whatever its height. `BlockStyle.contentTier` is the
  single source of truth for which content set renders.
- ~~**B12 — the source name never appeared as text (new §3.4).**~~ **Fixed.**
  Tier ≥ 44 renders `Source · Location` on the meta line, and every block, band,
  pill and month chip carries `Title · HH:mm–HH:mm · Source · Kind` as hover help.

- **B4 — components.md §3.1. Glyph baseline alignment is approximate.** §3.1
  wants the glyph aligned to "the first text baseline's cap height". The code
  uses `.alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }` — a magic 1pt,
  not derived from cap height.
- **B5 — components.md §3.3. The clamped hit region is centred on the clamped
  frame, not the true one.** §3.3 says "centred on the true frame".
- **B6 — components.md §7. Protected only beats low-energy on full
  containment.** A low-energy window that *partially* overlaps a protected one
  still draws its hatch over the overlap. §7 says protected wins outright.
- **B7 — layouts.md §1.1. The inspector overlay is a `ZStack` layer,** not a
  presented overlay. It reads correctly and sits at `elevation.level2`, but it
  does not dim or dismiss like a real overlay.
- **B8 — layouts.md §3.1. `T` / Today does not scroll the current time to 1/3
  from the top.** Initial scroll uses `min(07:00, firstEventStart − 1h)` as
  specified; the Today-key behaviour is not implemented.
- **B9 — interactions.md §6. Selection survives view changes but does not
  scroll into view.**

---

## Not a deviation — worth stating

- `⌘1/⌘2/⌘3`, `⌘T`, `T`, `←`/`→`, `⌘N`, `↩`, `⌫`, `⌘↩`, `⌥⌘↩`, `⌥`-arrows,
  `⌥⇧`-arrows, `↑`/`↓`, `⎋`, `↖`/`↘`, `⌃⌘S`, `⌥⌘I`, `⌘Z` are all wired, and
  each is a menu item with the same key equivalent.
- Dropping into a protected window is allowed, with the alert-coloured preview
  outline (interactions.md §4) — deliberately not blocked.
- The empty day reads "Nothing scheduled": no illustration, no encouragement.
- Skipped and done are visual siblings; no red, no counter, no strikethrough.
- Peak-focus windows render nothing, per §7.
