# Status

Updated: **2026-09-10**
Phase 1: **complete and verified.** Phase 2: **designed, not built.** Phase 3:
**neither designed nor built.**

This file was reconciled against the actual tree on 2026-09-10 (task P3-T01).
Everything below was re-derived from the working copy and from commands re-run
in that session — not carried over from the previous text. Several claims in the
old version were wrong and are corrected in place; where a correction matters,
it says so.

---

## 1. Verification — run on this Mac, 2026-09-10

Xcode 26.6 (17F113), Apple Swift 6.3.3, target arm64-apple-macosx26.0.
Working tree clean at `9bd7724` when these were run.

### 1.1 `swift Scripts/generate-tokens.swift --check` — **FAILS**

```
Kadence/DesignSystem/Tokens.swift is out of date or was hand-edited.
Tokens.swift is generated; edit design/tokens.json instead, then run:
    swift Scripts/generate-tokens.swift
```

Exit status **1**. This is the one red result in the four, and it is real, not a
machine artefact. **It is also not a Phase 1 regression.**

Cause, established by regenerating and diffing: commit `1c58185` added 67 Phase 2
tokens to `design/tokens.json` and never regenerated `Tokens.swift`. Running the
generator produces a **+96 / −1** diff against the committed file — the source
fingerprint line, plus new leaves that are all Phase 2 surface:

- `color.window.peakFocusEdge`, `color.window.peakFocusFill` (§7 editor exception)
- `motion.PreviewRevert`, `motion.SnoozeConfirmHold`
- `opacity.blockPreviewed`, `opacity.editorInactiveLayer`
- `size.conflictOption*`, `size.editorInspectorWidth`, `size.editorModeBarHeight`,
  `size.popover*`, `size.previewCanvasBorder`, `size.resyncPopoverWidth`,
  `size.routineEditor*`, `size.statusItem*`
- typography groups `ConflictOptionTitle`, `ConflictOptionDelta`,
  `EditorModeLabel`, `PopoverNextTitle`, `PopoverNextMeta`, `PopoverRow`,
  `PopoverSectionLabel`, `StatusItem`

No Phase 1 token changed. Nothing was hand-edited. The generated file is simply
one design pass behind its source.

**I did not fix this.** P3-T01 is a documentation-reconciliation task and is
scoped to touch no code; I regenerated only to identify the drift, then reverted
with `git checkout` so the tree is byte-identical to `HEAD`. Regenerating is a
one-command fix and belongs to whoever picks up the next build task — see §5.

### 1.2 `./Scripts/check-accessibility.sh` — **PASS**

```
building…
querying pid 19877
block-shaped elements in the tree: 20
carrying the §11 label:            0
  AXHelp=Check mail · 12:50–13:00 · Mail appointments · event ~~
  AXHelp=Stand-up · 12:30–12:45 · Personal · event ~~
  AXHelp=Reading · 21:00–21:30 · Daily routine · routine block, Reading · 21:00–21:30 · Daily routine · routine block ~~

WARN: blocks are in the tree, but 0 carry the §11 label.
      Known open defect A20b — VoiceOver reads the hover-help string
      instead of 'title, time, kind, source, status'.
PASS (elements present)
```

Exit status 0. 20 block elements, matching the 20 renderable fixtures. The A20b
warning is a known open defect, not a new one — DEVIATIONS.md A20b.

### 1.3 `xcodebuild -scheme Kadence -destination 'platform=macOS' build` — **PASS**

```
** BUILD SUCCEEDED **
```

Exit status 0.

### 1.4 `xcodebuild -scheme Kadence -destination 'platform=macOS' -only-testing:KadenceTests test` — **PASS**

```
** TEST SUCCEEDED **
```

Exit status 0. Counted from the log: **149 passed / 0 failed** (129 unique test
cases; the surplus is parameterised cases reported per argument).

Always use `-only-testing:KadenceTests`. A plain `test` also runs the empty
`KadenceUITests` template, whose runner cannot start on this machine ("Timed out
while enabling automation mode"). That red is the template, not a failure.

---

## 2. Phase 1 — complete and verified

Phase 1 as defined in `BRIEF-PRODUCT.md` "Phase 1" is **done**. It builds, its
149 tests pass, its blocks reach the accessibility tree, and it has been run and
exercised in Month / Week / Day.

Built and standing:

- **Design system.** `Scripts/generate-tokens.swift` → `Tokens.swift`;
  `TypeStyle` (Dynamic Type via `@ScaledMetric(relativeTo:)`); `SourceKey`
  (eight palette slots, hue carries source only); `Elevation`, `BlockStyle`,
  `RailStyle`, `BadgeSpec`; `resolveBlockStyle` as one pure function consumed by
  all three block views.
- **Models (SwiftData).** `Event`, `Place`, `EventDraft`. `colorTag` is replaced
  by `sourceKey` (components.md §1 makes hue mean source and nothing else).
  Display-only fixtures where Phase 1 has no service: `TravelFixture`,
  `AllDayFixture`, `TimeWindowFixture`, `CalendarSource`.
- **Layout.** `DayLayoutEngine` (layouts.md §3.3 in full: cluster → column-pack
  → cascade → vertical gaps), `DensityTier`, `TimeGeometry`. Pure functions over
  value types, no SwiftUI and no clock.
- **Views.** `GridBlockView`, `TravelBandView`, `AllDayItemView`, `MonthChipView`;
  canvas layers (background windows spanning the gutter, hour lines, gutter, now
  line); `TimedCanvasView`, `MonthGridView`, `DayHeaderRow`, `AllDayRowView`;
  `SidebarView`, `InspectorView`, toolbar, menus.
- **Interaction.** Create by double-click, drag, `⌘N` or `+`; drag to move;
  edge-drag to resize; `⌫` to delete. Creation is commit-or-discard through
  `EventDraft`, so an untitled event cannot be persisted.
- **Undo.** Explicit inverse-command stack (`UndoStack`), depth 50, named actions
  in the Edit menu, re-entrant grouping, full redo branch. Events are addressed
  by `id` and resolved at execution time, so undoing a delete survives the object
  identity change. Not `ModelContext.undoManager` — that groups at the wrong
  grain and cannot survive that identity change.
- **Focus.** `⇥` / `⇧⇥` cycle sidebar → all-day row → grid → inspector, wrapping
  and skipping hidden regions, as a pure function with 13 tests.
- **Sidebar visibility.** One source of truth (`CalendarState.isSidebarVisible`),
  with the split view's `columnVisibility` derived from it.
- **Mock data.** `MockData` — components.md §12's sixteen fixtures, seeded once
  and idempotent.

### 2.1 Corrections to what this file previously claimed

The old text carried three statements that were false when it was written or had
since gone stale. Recording them so they do not reappear:

- It said `⇥` region cycling "is not implemented" under *Not done*, while a
  section above it correctly described A11 as fixed with 13 tests. **It is
  implemented.**
- It said inline title editing on create was "stubbed rather than built". **It is
  built** — A13, via `EventDraft` / `DraftBlockView`.
- It said "Five gaps remain (G-003, G-005)" — a count of five against a list of
  two. Two remain, and neither blocks.

### 2.2 The one thing Phase 1 is missing

**The Phase 1 screenshot set does not exist.** `CONTEXT.md` requires every phase
to end with `screenshots/<phase>/` populated plus an `INDEX.md`, reviewed by the
design agent.

- `screenshots/` on disk contains one file: `.DS_Store`. No PNGs.
- `git ls-files screenshots` returns **nothing**. No screenshot is tracked.
- History shows only two ad-hoc macOS screengrabs, added and then deleted:
  `7fad990` added `Screenshot 2026-09-09 at 23.31.04.png`, `1590a0d` replaced it
  with `Screenshot 2026-09-10 at 01.14.33.png`, and `15718a9` deleted that.
- Root `INDEX.md` nevertheless describes a 16-file set by name
  (`day-full-dark.png`, `week-overlap4-dark.png`, …). **Those files were never
  committed and are not on disk.** `INDEX.md` is not mine to edit under this
  task; it is flagged here so nobody plans against it.

So Phase 1 is complete and verified *by build, test and accessibility check*, but
its screenshot review artefact is absent.

---

## 3. Phase 2 — full design spec, **zero implementation**

> **Read this before trusting the commit log.** Git history contains commits
> titled **"Phase 2"** (`1590a0d`) and **"Phase 2 finish"** (`15718a9`). Neither
> contains any Phase 2 feature work. Phase 2 has not been started.

`BRIEF-PRODUCT.md` "Phase 2 — routines, conflicts, protected time, and the menu
bar" requires a routine engine, a TimeWindow editor, conflict detection and a
menu bar extra. **None of it exists in `Kadence/`.**

### 3.1 Evidence — searched this session

`Kadence/` contains 36 Swift files. Searching all of `Kadence/` and
`KadenceTests/` for the Phase 2 vocabulary:

| Looked for | Found |
|---|---|
| `RoutineEngine` | **nothing** |
| conflict detection (`conflictDetect`, `ConflictResolv`) | **nothing** |
| `MenuBarExtra` scene | **nothing** |
| `Snooze` | **nothing** |
| a `TimeWindow` *editor* | **nothing** |

The only hits are Phase 1 display fixtures, and the code says so itself.
`Kadence/Models/DisplayFixtures.swift:65` reads:

```swift
/// Stands in for `TimeWindow` (Phase 2). Weekday numbers follow
struct TimeWindowFixture: Identifiable, Equatable, Sendable {
```

`TimeWindowFixture` is generated data drawn by `GridLayers.swift` as a background
band. There is no model behind it, no persistence, no editor, and nothing that
computes a routine. components.md §12 states the same thing for the whole Phase 1
fixture set: *"no TravelLeg computation, no routine engine, no work item model
behind them."*

### 3.2 What the two misleadingly-titled commits actually contain

- **`1590a0d` "Phase 2"** — Phase 1 polish. `EventDraft.swift` and
  `DraftBlockView.swift` (commit-or-discard creation, DEVIATIONS A13),
  `FocusRegionTests` (focus-region cycling, A11), `SidebarVisibilityTests`
  (sidebar-visibility unification), `EventCreationTests`. Every changed file is
  Phase 1 scope.
- **`15718a9` "Phase 2 finish"** — three files: `DECISIONS.md` (+83),
  `INDEX.md` (+6/−5), and the deletion of one screenshot. **No source file at
  all.**

### 3.3 The commit titled "Phase 3" added the **Phase 2 design spec**

`1c58185`, titled **"Phase 3"** in `git log`, contains no Phase 3 work and no
Swift. It touched `design/` and `orchestrator/` only:

```
design/GAPS.md          |  61 +++++
design/components.md    | 320 +++++++++++++++++++++++++-
design/interactions.md  | 144 +++++++++++-
design/layouts.md       | 103 +++++++++
design/tokens.json      | 103 ++++++++-
orchestrator/…          (new files)
```

What it added is the **Phase 2 UI design**:

- `design/components.md` §13 The Routines window, §14 Conflict resolution,
  §15 Menu bar extra, §16 Snooze confirmation, §17 fixtures
- `design/layouts.md` §8 The Routines window, §8.1 Editor inspector,
  §9 Menu bar popover, §10 The conflict panel
- `design/interactions.md` §10 Conflict resolution, §11 The Routines window,
  §12 The menu bar popover
- 67 new tokens in `design/tokens.json`

Its own section banner and final header say so. components.md line 572 opens the
new material with:

```
# Phase 2 — routines, conflicts, protected time, the menu bar
```

and the section closing it, at line 825, is headed — verbatim:

```
## 17. What Phase 2 must render for review
```

followed by *"Additions to the §12 fixture set. Same rule: display fixtures, no
services."* and twelve numbered Phase 2 fixtures (routine template, windows mode,
detached instances, conflict options, preview state, status item, popover, snooze
result row).

**So: Phase 2 has a complete design and no code.** The commit title is the only
thing in the repository that suggests otherwise.

---

## 4. Phase 3 — no design coverage at all

`BRIEF-PRODUCT.md` scopes Phase 3 as work items, time logging, ICS import,
`TravelTimeProvider`, Moodle and CalDAV. **There is no Phase 3 design anywhere in
`design/`, and no Phase 3 code.**

Searched `design/` this session for `assignment`, `workItem`, `work item`,
`TimeLog`, `time log`, `effort`, `confidence`, `ICS`, `Moodle`, `CalDAV`,
`TravelTimeProvider`:

- `TimeLog`, `time log`, `effort`, `confidence`, `CalDAV`, `TravelTimeProvider`
  — **zero occurrences in `design/`.**
- `ICS` — one false positive, `GAPS.md:54`, matching inside the word
  "CoreGraphics".
- The rest are **incidental Phase 1 styling references, not feature design**:
  components.md §3.2 keys two all-day glyphs off `WorkItem.kind`
  (`.assignment/.project` → `flag.fill`, `.exam` → `graduationcap.fill`);
  §1 and §10.1 mention Moodle as a *source* for hue and swatch symbols
  (`tray.2.fill`); §10.1's assignment *rule* is about palette-slot assignment,
  not about assignments. components.md §12 explicitly notes there is "no work
  item model behind them."

That is a handful of icon and colour rules that anticipate Phase 3 data. It is
not a design for work items, time logging, feed import, or travel-time lookup.
No layout, no interaction model, no tokens, no fixture list exists for any of it.
Phase 3 vocabulary appears only in `BRIEF-PRODUCT.md`, `BRIEF-DESIGN.md` and
`CONTEXT.md` — the briefs, not the spec.

---

## 5. What is actually next

Stating facts, not choosing an order. The Phase 2-vs-Phase 3 build order is not
mine to decide.

1. **`Tokens.swift` is one design pass stale and `--check` is red at `HEAD`.**
   Fixed by running `swift Scripts/generate-tokens.swift` and committing the
   result. It is a prerequisite for any task that reports a green token check,
   and for any Phase 2 code, since all 67 Phase 2 tokens are missing from the
   generated file. Nothing else in the repo is blocked by it — the app builds and
   tests pass, because no Phase 1 code references the new leaves.
2. **Phase 2 has a design and no code.** `design/components.md` §13–§17,
   `layouts.md` §8–§10, `interactions.md` §10–§12 and the 67 new tokens are
   complete and frozen. Nothing in `Kadence/` implements any of it. The design
   pass also notes two deliberate reuses: the Routines window **is** the Week
   canvas with dates, now line, all-day row and travel bands removed
   (components.md §13.1 lists every difference), and conflict preview **is** the
   drag-drop drop-preview vocabulary. Neither needs a new renderer.
3. **Phase 3 has neither design nor code.** It cannot be built without a design
   pass first; per `CONTEXT.md` the coding agent cannot invent UI values.
4. **Phase 1 has open deviations.** 15 absent, 6 built-differently, **0 invented
   values**, **0 open spec contradictions** — see `DEVIATIONS.md`, re-audited
   2026-09-10 against the current spec text.
5. **Phase 1 never produced its screenshot set** (§2.2), and root `INDEX.md`
   describes 16 files that do not exist.

### 5.1 Needs a ruling

- **A20b** — blocks reach the accessibility tree but carry the §3.4 hover-help
  string instead of the §11 label. Six configurations were measured against the
  running app, including the preferred real-`Button` route; the label is
  discarded in every one that produces an element at all. Three next candidates,
  each trading something, are in DEVIATIONS.md. Unchanged this session.
- **A21** — the sidebar's needs-attention row draws `tray.full`, which the
  amended components.md §10.2 now forbids outright. New, and a one-line fix; see
  DEVIATIONS.md.

### 5.2 Gaps

Two remain open, neither blocking: **G-003** and **G-005**. Closed: G-004, G-006,
G-007, G-008, G-009. **There are no invented design values in the codebase** and
no `// SPEC-GAP` markers left in `Kadence/`.

No new gap was filed by this reconciliation. The three defects it found —
the stale `Tokens.swift`, the `tray.full` collision, and the missing screenshots
— are all cases where `design/` is unambiguous and the build or the repo has
drifted from it. None is a question for the designer, so none belongs in
`GAPS.md`.
