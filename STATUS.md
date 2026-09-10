# Status

Updated: **2026-09-10**
Phase 1: **complete and verified.** Phase 2: **designed, not built.** Phase 3:
**neither designed nor built.**

This file was reconciled against the actual tree on 2026-09-10 (task P3-T01).
Everything below was re-derived from the working copy and from commands re-run
in that session — not carried over from the previous text. Several claims in the
old version were wrong and are corrected in place; where a correction matters,
it says so.

**Amended 2026-09-10 by task P2-T01 (crash fix).** §1.1 and §1.2 are corrected —
both re-run this session with different results. §1.4 has a new count. §1.5 is
new and records the crash, its root cause and its fix. §5 is re-ordered: the
crash outranked everything that was listed as next, and is now done.

---

## 1. Verification — run on this Mac, 2026-09-10

Xcode 26.6 (17F113), Apple Swift 6.3.3, target arm64-apple-macosx26.0.
Working tree clean at `9bd7724` when these were run.

### 1.1 `swift Scripts/generate-tokens.swift --check` — **PASSES**

*(corrected 2026-09-10 by P2-T01 — this section previously said FAILS)*

```
Kadence/DesignSystem/Tokens.swift is up to date.
```

Exit status **0**, re-run this session. The failure P3-T01 recorded here was
real when it was recorded: commit `1c58185` added 67 Phase 2 tokens to
`design/tokens.json` and did not regenerate `Tokens.swift`, leaving the
generated file one design pass behind its source. P3-T01 was scoped to touch no
code and so left it. It has since been regenerated — not by this task, which ran
the generator only in `--check` mode and never wrote `Tokens.swift`.

No Phase 1 token was ever involved; the drift was entirely Phase 2 surface
(`color.window.peakFocus*`, `motion.PreviewRevert`, `size.popover*`,
`size.routineEditor*`, the `ConflictOption*` / `Popover*` / `StatusItem`
typography groups, and the rest).

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

**Re-run 2026-09-10 by P2-T01: reported `FAIL`, 0 block elements — but that is
the machine, not the code.** The control the script's own guidance asks for was
run in the same minute: TextEdit with a document open also reports **0 windows**
through the accessibility API (`System Events ... get count of windows` → `0`,
and `window 1` → "Invalid index"). The Mac is not vending windows to AX right
now, so the script has nothing to count. It is intermittent — window enumeration
worked earlier in the same session, which is how the ⎋/↩ crash was driven through
the menu bar. Nothing in this task touched block accessibility. Treat the PASS
above as the standing result and re-run when AX is healthy.

### 1.3 `xcodebuild -scheme Kadence -destination 'platform=macOS' build` — **PASS**

```
** BUILD SUCCEEDED **
```

Exit status 0.

### 1.4 `xcodebuild -scheme Kadence -destination 'platform=macOS' -only-testing:KadenceTests test` — **PASS**

```
** TEST SUCCEEDED **
```

Exit status 0. **135 unique test cases, 0 failed.** The log prints 154–155
`passed` lines depending on the run; the surplus is parameterised cases reported
per argument, and the count wobbles by one because that per-argument logging is
racy (`SourceSymbolTests/normativeTable` printed 9 lines in one run and 10 in the
next, same 0 failures). Count unique names, not lines.

*(updated 2026-09-10 by P2-T01: was "149 passed / 129 unique". The six new cases
are `KadenceTests/DraftBindingTests.swift` — see §1.5.)*

Always use `-only-testing:KadenceTests`. A plain `test` also runs the empty
`KadenceUITests` template, whose runner cannot start on this machine ("Timed out
while enabling automation mode"). That red is the template, not a failure.

---

### 1.5 The ⎋ / ↩ crash — found, root-caused, fixed (task P2-T01)

Parsa reported that pressing ⎋ or ↩ crashed the running app. It did.

**Reproduction.** Reproduced under `lldb` on a debug build. The state that
crashes is (d), mid-draft with the inline title field active: File ▸ New Event,
type a title, press `↩`. The app dies immediately.

**Stack.**

```
Process 30139 stopped
* thread #1, queue = 'com.apple.main-thread',
  stop reason = EXC_BREAKPOINT (code=1, subcode=0x23576d648)
    frame #0: SwiftUICore`BindingOperations.ForceUnwrapping.get(base:) + 304
->  0x23576d648 <+304>: brk    #0x1
```

**Root cause.** `Kadence/Views/Canvas/DayColumnView.swift:138-139` (pre-fix):

```swift
@Bindable var state = state
if let binding = Binding($state.draft) {
```

`Binding.init?(_ base: Binding<Value?>)` does **not** unwrap once at
construction. It builds a `BindingOperations.ForceUnwrapping`, which unwraps
inside its *getter*, on every read. So the binding handed to `DraftBlockView`
force-unwraps `CalendarState.draft` each time SwiftUI reads it.

`↩` runs `DraftBlockView.onSubmit` → `DayColumnView.commitDraft()` →
`EventStore.commit(_:)` → `state.discardDraft()`, which sets `draft = nil` —
from inside the draft field's own event handling. SwiftUI then reads the field's
bindings again while tearing the field down. Those trailing reads unwrap nil and
trap. Verified independently of the app with a 15-line SwiftUI program: reading a
`Binding(optionalBinding)` after the source goes nil stops in the same frame.

The invalid state, stated plainly: **a force-unwrapping binding outliving its
source by one update pass.** It was the only `Binding(_:)` optional-unwrap in
`Kadence/` — every other binding in the tree is an explicit `get:`/`set:` pair.

**Fix.** `CalendarState.draftBinding()`, in `Kadence/State/CalendarState.swift`,
replaces it; `DayColumnView.draftBlock` calls that instead. The binding
remembers the last value written through it and serves that to reads arriving
after `draft` is nil, and it drops writes once `draft` is nil — which also stops
a dying field flushing its last text back and resurrecting a draft the user just
cancelled. The doc comment says why, so it does not get "simplified" back.

**Regression cover.** `KadenceTests/DraftBindingTests.swift`, six cases driving
`CalendarState` and `EventStore` through the exact transition. Confirmed to fail
against the pre-fix code path: with `draftBinding()` temporarily reverted to the
`Binding(optionalBinding)` shape, the run is `** TEST FAILED **` and the trap
takes the whole runner down. With the fix, `** TEST SUCCEEDED **`.

**Re-verified in the running app** after the fix — ⎋ and ↩ pressed repeatedly,
no crash, no console exception, in: grid focused with nothing selected; with a
time cursor; with an event selected (Home/End); mid-draft with the field active
(empty title, typed title, ⎋-then-↩, ↩-then-⎋); each of those with the inspector
open and closed.

**Two adjacent defects found and *not* fixed** (P2-T01 was scoped to the crash) —
both now in DEVIATIONS.md: **A22**, `⎋` does not cancel a draft at all, so it was
masking half of this crash; **A23**, `⌘N` opens a second window because the stock
"New Window" item keeps the same key equivalent.

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

1. ~~**`Tokens.swift` is one design pass stale and `--check` is red at `HEAD`.**~~
   **Done** — `--check` is green, see §1.1. Not this task's doing; it was already
   regenerated when P2-T01 picked the tree up.
2. **Phase 2 has a design and no code.** `design/components.md` §13–§17,
   `layouts.md` §8–§10, `interactions.md` §10–§12 and the 67 new tokens are
   complete and frozen. Nothing in `Kadence/` implements any of it. The design
   pass also notes two deliberate reuses: the Routines window **is** the Week
   canvas with dates, now line, all-day row and travel bands removed
   (components.md §13.1 lists every difference), and conflict preview **is** the
   drag-drop drop-preview vocabulary. Neither needs a new renderer.
3. **Phase 3 has neither design nor code.** It cannot be built without a design
   pass first; per `CONTEXT.md` the coding agent cannot invent UI values.
4. **Phase 1 has open deviations.** 17 absent, 6 built-differently, **0 invented
   values**, **0 open spec contradictions** — see `DEVIATIONS.md`, re-audited
   2026-09-10 against the current spec text, plus A22 and A23 added by P2-T01.
   **A22 is the one to take next**: `⎋` does not cancel a draft at all, which is
   a §3 rule the build simply does not implement, and it is a small change now
   that the binding underneath it is safe. Do not wire it up on a tree without
   the `draftBinding()` fix — it runs the code path that used to trap.
5. **Phase 1 never produced its screenshot set** (§2.2), and root `INDEX.md`
   describes 16 files that do not exist.
6. **The ⎋ / ↩ crash is fixed** (§1.5). It outranked everything on this list
   while it was open; nothing else was started until it was closed.

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
