# Status

Updated: **2026-09-11**
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

**Amended 2026-09-11 by task P2-T02 (click-to-select fix).** §1.6 is new and
records that defect, its root cause and its fix. §1.4 has a new count (140
unique). §5 is re-ordered again. Note for anyone reading the old §2/§5 text:
they described selection as working. Selection by *keyboard* worked; selection
by *mouse* did nothing at all, and had not since the hit region regressed. See
§1.6 and the corrected DEVIATIONS.md B9.

**Amended 2026-09-11 by task P2-T03 (block-overlap diagnosis — report only).**
§1.7 is new. That task changed **no** code: it reproduced and root-caused the
three symptoms Parsa reported and filed the two spec questions they raised
(G-011, G-012). §1.1, §1.3 and §1.4 were re-run and are **unchanged** — build
succeeded, 160 `passed` lines / 140 unique / 0 failed, `--check` green — so
nothing in those sections needed correcting. §5.2 lists the new gaps. The fix is
a separate, future task.

**Amended 2026-09-11 by task P2-T05 (fix symptom (a), and the Week half of (c),
per G-011's CLOSED ruling in `design/GAPS.md`).** §1.7 is rewritten in place:
(a) and (c)-Week are now **fixed**, verified against the two named fixtures
("Stand-up" / "Check mail") and against the "Datenmodellierung" Week strip case.
`DensityTier`'s boundaries are now 18/28/53 (`components.md` §3.3); §3.5's new
confinement invariant is implemented in `GridBlockView` and `DraftBlockView`
(top-anchored `.frame(height:, alignment: .top)` before `.clipShape`, in that
order). (c)-Day remains open as **G-012**, unchanged, out of scope for this
task. §1.4's count is updated (156 unique / 184 lines, +16 unique from
`BlockConfinementTests.swift`). §5 and §5.2 are corrected: G-011 is closed,
G-012 is the only symptom-(c) gap left open. DEVIATIONS.md D4 and B13 are
resolved and moved out of the open tables. `DayLayoutEngine.swift` was **not**
touched — confirmed by diff against the commit immediately before this task.

**Amended 2026-09-11 by task P2-T06 (build G-012's already-CLOSED ruling — fix
(c)-Day).** §1.7 is rewritten in place again: **(c)-Day is now fixed**, per
`design/GAPS.md` G-012's CLOSED ruling in `layouts.md` §3.3 (layout footprint,
steps 1 and 2 restated to share it) and `components.md` §4 (z-order line
amended). This was a ruling built at the spec level only by DA's task P2-T04
and left unimplemented; P2-T06 is the code side. `LayoutItem` gained an
optional `departAt`, `footprintTop`/`footprintBottom`, and `cluster`,
`sortForLayout` and `packIntoSubColumns` now all key off the footprint instead
of raw `start`/`end`; `DayColumnView.layoutItems` now supplies each event's
travel-band `departAt` (`fixtures.travel(forEvent:)?.departAt`, `nil` when
there is no band). Verified: build succeeds, no new warnings;
`KadenceTests` — 189 `passed` lines / 160 unique / 0 failed, including five new
`DayLayoutEngineTests.swift` cases that pin the spec's own worked example
("Morning review" 08:00–09:00, "Datenmodellierung" 09:00–10:30, 22-minute band
departing 08:38): the pair clusters and packs into 2 side-by-side sub-columns
at `hourHeightDay` (case 1) and does *not* cluster at `hourHeightWeek` (case 2,
unchanged behaviour), plus a no-band control case. `design/` was not touched —
the ruling already existed there; this task only built it. No live on-screen
capture was taken — out of scope per this task's brief, a separate follow-up.

**Amended 2026-09-11 by a follow-up task (P2-T06 fix — `check-accessibility.sh`
regressed to `FAIL: no Kadence process has a window` after the commit above).**
§1.2 is rewritten in place: the failure was investigated and is **not a defect
in `DayLayoutEngine.swift` or `DayColumnView.swift`**. Reproduced by hand
(`open`/direct launch, no `check-accessibility.sh` involved): a launch showed
AppKit's own log reporting window restoration succeeding (non-nil window,
`error=(null)`), yet `System Events` reported 0 windows and a screen capture
showed nothing on screen — stale/corrupted saved window-restoration state
(`~/Library/Saved Application State/XIX.Kadence.savedState`, most likely left
over from the earlier interrupted P2-T06 session) was silently failing to
present the restored window. Launching once with `-ApplePersistenceIgnoreState
YES` wrote a fresh, good state file; every launch after that — with no flag —
came up normally. Code review of both files found no force-unwrap, no
precondition, and no unbounded loop (`packIntoSubColumns`'s expansion loop is
bounded by `subColumnCount`); `fixtures.travel(forEvent:)` is a plain `.first`
optional lookup, safe for events with no travel fixture. `sample` on a hung
reproduction showed the main thread parked in `mach_msg2_trap` (idle, waiting
for events) at 0% CPU — not spinning, not deadlocked in layout code. Two
consecutive clean runs of `Scripts/check-accessibility.sh` (all Kadence
processes killed first) both **PASS**ed — see §1.2. A second agent session was
independently assigned this same fix task concurrently on this machine
(duplicate assignment, flagged to the orchestrator); some of the intermittent
failures seen mid-investigation were the two sessions' `pkill`/`open -n`
sequences racing each other, which is a separate, purely environmental
artefact of running two verification passes at once and not evidence of a
code defect either. No change was made to `Kadence/Layout/DayLayoutEngine.swift`
or `Kadence/Views/Canvas/DayColumnView.swift` by this follow-up task.

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

**Re-run 2026-09-11 by the P2-T06 fix follow-up task: two consecutive clean
PASSes, after diagnosing and closing out the `FAIL: no Kadence process has a
window` regression reported against commit a3cece1 — see the amendment above
§1. Transcript of the second of the two runs (all Kadence processes killed
first, no interference):**

```
building…
querying pid 72031
block-shaped elements in the tree: 20
carrying the §11 label:            0
  AXHelp=Breakfast · 07:15–07:45 · Daily routine · routine block, Breakfast · 07:15–07:45 · Daily routine · routine block ~~
  AXHelp=Morning review · 08:00–09:00 · Daily routine · routine block, Morning review · 08:00–09:00 · Daily routine · routine block, Morning review · 08:00–09:00 · Daily routine · routine block ~~
  AXHelp=Datenmodellierung · 09:00–10:30 · University timetable · lecture, Datenmodellierung · 09:00–10:30 · University timetable · lecture, Datenmodellierung · 09:00–10:30 · University timetable · lecture ~~

WARN: blocks are in the tree, but 0 carry the §11 label.
      Known open defect A20b — VoiceOver reads the hover-help string
      instead of 'title, time, kind, source, status'.
PASS (elements present)
```

Root cause of the regression: stale saved window-restoration state, not
DayLayoutEngine/DayColumnView — see the amendment above §1 for the full
diagnosis. No code fix was needed or made; the two runs above stand as the
regression's resolution.

### 1.3 `xcodebuild -scheme Kadence -destination 'platform=macOS' build` — **PASS**

```
** BUILD SUCCEEDED **
```

Exit status 0.

### 1.4 `xcodebuild -scheme Kadence -destination 'platform=macOS' -only-testing:KadenceTests test` — **PASS**

```
** TEST SUCCEEDED **
```

Exit status 0. **160 unique test cases, 0 failed.** The log prints 189
`passed` lines; the surplus is parameterised cases reported per argument, and
the count can wobble by one because that per-argument logging is racy
(`SourceSymbolTests/normativeTable` printed 9 lines in one run and 10 in the
next, same 0 failures). Count unique names, not lines.

*(updated 2026-09-10 by P2-T01: was "149 passed / 129 unique". The six new cases
are `KadenceTests/DraftBindingTests.swift` — see §1.5.)*

*(updated 2026-09-11 by P2-T02: was "135 unique / 154–155 lines". The five new
cases are `KadenceTests/BlockHitRegionTests.swift` — see §1.6.)*

*(updated 2026-09-11 by P2-T05: was "140 unique / 160 lines". The sixteen new
cases are `KadenceTests/BlockConfinementTests.swift` — see §1.7, and G-011 in
`design/GAPS.md`.)*

*(updated 2026-09-11 by P2-T06: was "156 unique / 184 lines". The five new cases
are in `KadenceTests/DayLayoutEngineTests.swift` — see §1.7, and G-012 in
`design/GAPS.md`.)*

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

### 1.6 Clicking a block did nothing — found, root-caused, fixed (task P2-T02)

Parsa reported that clicking an event block had no effect: no selection ring, no
inspector change. It did not.

**Was it a regression or always broken?** Always broken, for mouse input. The
old B9 entry ("selection survives view changes…") made it look like selection
worked; that entry was written from the **keyboard** path (`↖`/`↘`, `↑`/`↓`),
which does work and always did. `state.selectedEventID` had no working mouse
writer. DEVIATIONS.md B9 is corrected accordingly.

**Reproduction.** Instrumented, not assumed. A temporary `TapProbe.log` was put
inside the block's `.onTapGesture` closure, inside `blockGesture`'s `onChanged`
and `onEnded`, and inside the create surface's `.onTapGesture`, writing to
stderr on a debug build. Clicking directly on a block with no drag printed
**`SURFACE onTapGesture`** — the create surface's handler, the one that *clears*
selection — and never printed the block's. The click was not being swallowed by
a gesture conflict; it was never landing on the block at all.

**The hypothesis this refutes.** The obvious suspect was the `.onTapGesture`
immediately followed by `.gesture(DragGesture(minimumDistance: 3))` on the same
view — the documented SwiftUI exclusivity trap. That was **not** the cause. The
tap recogniser was fine; nothing was reaching it.

**Root cause.** `Kadence/Views/Canvas/DayColumnView.swift`, `blockStack`
(pre-fix):

```swift
.offset(x: laidOut.frame.minX, y: laidOut.frame.minY - aboveHeight)
.contentShape(Rectangle().inset(by: -laidOut.hitExtension / 2))
```

`.offset` is a **render-time translation**: it moves what is drawn and leaves the
layout frame where it was. A `.contentShape` applied *after* it therefore
describes the hit region in the **un-offset** layout space. Blocks are positioned
in the column purely by that `.offset`, so their layout frames all sit at the
column's origin — and every block's hit region collapsed onto its day column's
top-left corner.

The invalid state, stated plainly: **every block in a column shared one hit
region, in the wrong place.** A click on a block's visible rectangle could not
hit that block. What it did instead depended on where the pile landed relative
to the pointer: a click inside the collapsed pile at the column corner selected
whichever block happened to be frontmost *there*, and a click anywhere else fell
through to the create surface behind the blocks, which deselected and dropped a
time cursor.

Both outcomes look like "nothing happens" from the user's seat, because neither
puts a ring on the block that was clicked. `screenshots/p2-t02/` shows the first
one caught in the act: in `before-click-block-does-nothing.png`, a click at the
centre of "Datenmodellierung" (09:00–10:30) leaves it unringed and loads
**"Late lab session" (22:30–23:30)** into the inspector — a block thirteen hours
away that was never clicked.

Why no existing check caught it: the *rendering* was never wrong, so screenshot
review had nothing to look at, and modifier ordering is not reachable from a
unit test.

**Measured, both ways.** Accessibility frames are where SwiftUI's resolved
geometry becomes observable from outside the process. With the mock dataset,
20 timed blocks:

| ordering | distinct AX y positions |
|---|---|
| `.contentShape` after `.offset` (bug) | **2** of 20 — every block in a column at `y=150`, the column top |
| `.contentShape` before `.offset` (fix) | **20** of 20 |

**Fix.** Move `.contentShape` **before** `.offset`. The inset value moved into
`LaidOutBlock.hitInset` (`Kadence/Layout/DayLayoutEngine.swift`) alongside a new
`hitRect`, so the "hit area is centred on the true frame" rule is expressed over
value types and is testable without a window. The comment at the call site says
why the order is load-bearing, so it does not get tidied back.

A superficial reorder was deliberately avoided until the mechanism was
understood, because swapping those two lines blind can break dragging instead —
hence the drag re-verification below.

**Regression cover — three layers.**

1. `KadenceTests/BlockHitRegionTests.swift`, five cases over `hitInset` /
   `hitRect`: the inset is zero unless clamped, a clamped block's hit area grows
   by exactly `size.blockHitExtension` and stays centred, every block's hit
   region contains its own centre, blocks at different times get hit regions at
   different places, and a hit region never sits at the column origin.
2. `Scripts/check-block-hit-regions.sh` — asserts via accessibility that within
   a column, later start times sit strictly lower. **Confirmed to fail against
   the pre-fix ordering** (3 distinct positions for 20 blocks) and pass with it.
3. `Scripts/check-block-click-selects.sh` — new. Drives a **real click** at a
   block and asserts it becomes selected, then clicks empty grid and asserts it
   deselects. **Confirmed to fail (exit 1) against the pre-fix ordering and pass
   with the fix.**

**Why that third script does not use `System Events … click at {x, y}`.** That
command does not synthesise a mouse event: it resolves the accessibility element
at the point and sends it `AXPress`, bypassing hit-testing entirely. It passed
happily against the broken build, which makes it worthless here. The script
posts a genuine `CGEvent` mouseDown/mouseUp through the HID event tap instead —
the same path a human click takes. This was checked, not assumed.

**Re-verified in the running app** after the fix, with synthetic `CGEvent`s
against the mock dataset:

- Click a block → selected (`AXSelected` true), ring renders, and the inspector
  loads **that** block. Captured as
  `screenshots/p2-t02/after-click-selects-block.png`, the same click on the same
  block as the before shot; see `screenshots/p2-t02/INDEX.md`.
- Click empty grid → deselects. *(The time cursor a grid click also places is
  not vended to accessibility, so only the deselect half is asserted
  mechanically; the cursor was confirmed by eye.)*
- **Drag to move** — "Prep: relational algebra" dragged down 44pt (one hour at
  the Day hour height): `14:30–16:00` → `15:30–17:00`. Exact.
- **Bottom-edge resize** — dragged down 22pt: `15:30–17:00` → `15:30–17:30`.
  End moved 30 min, start untouched.
- **Top-edge resize** — dragged up 22pt: `15:30–17:30` → `15:00–17:30`. Start
  moved 30 min, end untouched.
- A non-movable block (`origin: .imported`, "Datenmodellierung") correctly
  refuses both move and resize.

So `blockGesture` is intact; the fix did not trade selection for dragging.

**One harness caveat, not an app defect.** Two synthetic drags fired ~2s apart at
nearly the same point: the second was ignored. With ~3s of spacing and a settled
pointer, every gesture above is reliably reproducible. This looks like synthetic
event pacing rather than app behaviour — a human cannot drag twice that fast in
the same place — but it is written down rather than dropped, because it is the
kind of thing that later looks like a real intermittent bug.

**One adjacent defect found and *not* fixed**, now DEVIATIONS.md **A24**: one
block reports `AXSelected = true` to accessibility when nothing is selected. It
is *not* our trait — it reproduces with the `.isSelected` line deleted from
`GridBlockView` outright. Two candidate causes (`.done` status, hover) were
tested and refuted; it was not root-caused further, being outside this task.

**One spec gap surfaced, filed not invented:** `design/GAPS.md` **G-010** —
interactions.md §6 does not say which block a click selects when the click point
is inside two overlapping blocks. Observed live: clicking the visual centre of
"Statistik übung" selects "Coffee with Nora", which is drawn on top there. The
build keeps today's frontmost-wins behaviour and no value was invented. **Open.**

The mock store was reset after this testing (the drags above are persisted by
SwiftData), so the fixed dataset is back to its seeded values and future
captures stay comparable.

### 1.7 The block-overlap defect — all three symptoms now fixed or confirmed-correct: (a) and (c)-Week (task P2-T05), (c)-Day (task P2-T06)

**Status as of task P2-T06, 2026-09-11.** All three reported symptoms are now
resolved. (a) and the Week half of (c) were fixed by task P2-T05, per
`design/GAPS.md`'s **G-011 — CLOSED** ruling. (b) was always correct, per
diagnosis below. The Day half of (c) — **G-012** — is now **fixed in code** by
this task (P2-T06), per `design/GAPS.md`'s **G-012 — CLOSED** ruling
(`layouts.md` §3.3, `components.md` §4). The diagnosis below (task P2-T03) is
kept as the historical record of what was wrong and is annotated in place
rather than rewritten; do not read any of it as still-open.

**What changed for (c)-Day, and why it closes G-012.** `layouts.md` §3.3 now
defines a **layout footprint** — `footprintTop` is a case-1 travel band's
`departAt` when the true band height (`geometry.height(from: departAt, to:
start)`) is at least `size.travelBandHeight`, else the event's own `start`;
`footprintBottom = max(end, footprintTop + minInterval)`, and the clamp only
ever extends the bottom, never moves the top. Both step 1 (clustering) and step
2 (column packing) now key off the same footprint — the ruling's explicit
warning was against clustering on footprints while packing on raw times, which
would pull a neighbour into the cluster and then still pack it into the band's
own sub-column, fixing nothing. The fix:

- `Kadence/Layout/DayLayoutEngine.swift` — `LayoutItem` gained an optional
  `departAt: Date?` (nil when the event has no band) and
  `footprintTop(geometry:)` / `footprintBottom(geometry:minimumDuration:)`
  methods implementing the definition above. `cluster`, `sortForLayout` (whose
  primary key is now `footprintTop`) and `packIntoSubColumns` all read the
  footprint instead of `start`/`end` directly. `layout(...)` needed no new
  parameter — it already receives `geometry: TimeGeometry`, which is what the
  case-1/case-2 height test needs.
- `Kadence/Views/Canvas/DayColumnView.swift` — `layoutItems` now passes
  `departAt: fixtures.travel(forEvent: $0.id)?.departAt` into each
  `LayoutItem`, so the engine — not the view — decides case 1 vs case 2 and
  whether the footprint extends. Drafts and events with no band pass `nil`,
  unchanged from before.

**Verified.** `xcodebuild build` succeeds, no new warnings.
`swift Scripts/generate-tokens.swift --check` is green (this task touched no
tokens). `KadenceTests` — 189 `passed` lines / 160 unique test names / 0
failed. Five new cases in `KadenceTests/DayLayoutEngineTests.swift` reproduce
the spec's own worked example directly: "Morning review" 08:00–09:00 and
"Datenmodellierung" 09:00–10:30 with a 22-minute band departing 08:38 —
`caseOneBandClustersInDay` and `gapG012PacksInDay` assert the pair forms one
cluster and packs into 2 non-overlapping side-by-side sub-columns at
`size.hourHeightDay` (case 1, footprint 08:38–10:30 vs 08:00–09:00, verified on
the resulting frames' x-ranges); `caseTwoBandDoesNotClusterInWeek` and
`gapG012DoesNotPackInWeek` assert the identical pair does **not** cluster at
`size.hourHeightWeek` (case 2, band under `travelBandHeight`, extends nothing —
unchanged behaviour, each block keeps the full column width); and
`noTravelBandUnaffected` pins that an event with `departAt: nil` clusters
exactly as before the change. No live on-screen capture was taken this
session — out of scope per this task's brief, a separate follow-up once this
lands.

`design/layouts.md` and `design/components.md` were **not** touched — the
ruling already existed there from task P2-T04; this task only built the code
side of it.

**What changed, and why it closes (a) and (c)-Week.** `design/GAPS.md` G-011
ruled that `DensityTier`'s three boundaries move 16/28/44 → **18/28/53**, each
now derived from its own tier's content set so a band's bottom is never below
that tier's own minimum (`components.md` §3.3), and added a new **§3.5
confinement invariant**: a block paints only inside its own laid-out frame,
clipped to its rounded rect, top-anchored, clipped at the bottom — never
centred. Implementing both together is what closes the defect; either alone
does not (a shrunk floor is still centred and still spills, and top-anchoring a
block still 22pt tall into a 13pt frame still clips into a neighbour rather
than fixing the number). The fix:

- `Kadence/Layout/DensityTier.swift` — boundaries 18/28/53, per-tier vertical
  padding (0 / `spacing.xxs` / `size.blockPadding` / `size.blockPadding`),
  minima matching G-011's table exactly (11/18/24/53).
- `Kadence/DesignSystem/BlockStyleResolver.swift` — `radius.blockCompact`'s
  threshold moved `< 16` → `< 18`, and the conflicted-badge swap at
  `.glyphOnly` is now keyed on the resolved content tier rather than a literal
  height, so a narrow cascaded block gets the same rule.
- `Kadence/Views/Blocks/GridBlockView.swift` — content is laid out into
  `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)`
  (was default-centred), the view is constrained to
  `.frame(height: renderedHeight, alignment: .top)` **before** `.clipShape`
  (was clipping to the content's own bounds, which clipped nothing), and a
  §4 short-case travel strip's height comes off the top of the content area via
  `contentTopInset`, not drawn over content sized to the full frame.
- `Kadence/Views/Blocks/DraftBlockView.swift` — the in-progress drag/create
  draft is a GridBlock too and gets the same `.frame(height:, alignment: .top)`
  fix, since it renders a block's content stack into a laid-out frame exactly
  as `GridBlockView` does.
- `Kadence/Views/Canvas/DayColumnView.swift` — the caller's own
  `.frame(height: laidOut.frame.height)` also picked up `alignment: .top`; it
  was the second, independent place the SwiftUI default centred a block, and
  both had to move for the fix to hold under either code path.
- `Kadence/DesignSystem/SourceColor.swift` and `MonthChipView` (§9's explicit,
  non-tier-derived content set) were **not** touched, per G-011's own scope
  note.

**Verified.** `xcodebuild build` succeeds; `KadenceTests` passes 184 `passed`
lines / 156 unique / 0 failed, including sixteen new cases in
`KadenceTests/BlockConfinementTests.swift` that pin the 18/28/53 boundaries, the
per-tier padding and minima, the confinement invariant over an `NSHostingView`
(a block reports exactly its laid-out height regardless of content), and a
pixel-level render of the two named fixtures ("Stand-up" 12:30–12:45, "Check
mail" 12:50–13:00) at their `DayLayoutEngine` frames in both Day and Week
geometry, asserting no ink lands in the gap between them — the direct
regression test for the symptom Parsa reported. A live on-screen capture was
still not possible this session for the same reason as P2-T03 (the Mac vends 0
windows); the `ImageRenderer`-based pixel test is the closest verification
available and does not depend on window vending.

`Kadence/Layout/DayLayoutEngine.swift` was **not modified** by this task —
confirmed by diffing it against the commit immediately preceding this task's
work, which is empty. G-012 (the travel-band footprint/clustering question) is
untouched and still open; nothing in this fix depends on it or forecloses it.

---

The diagnosis that follows is task P2-T03's original report-only finding, kept
verbatim as the record of what the defect was before the fix above:

Parsa reported three symptoms visible in `screenshots/day-full-light.png` and
`screenshots/week-full-dark.png` (mock fixtures, Wed 9 Sep). P2-T03 was a
report-only task: reproduce, root-cause, classify, change nothing. **No file
under `Kadence/` was modified.** The findings, in full, are in the task report;
the short version:

**Method.** The three symptoms were measured out of the committed PNGs at pixel
level (hour lines recovered from the images themselves, then times derived from
them), and `DayLayoutEngine` was run directly against the Wed 9 Sep fixture set
at the reproduced column widths — Day 1060pt, Week 152.14pt — by compiling
`DayLayoutEngine.swift`, `TimeGeometry.swift` and `Tokens.swift` into a
throwaway command-line driver outside the repo. Engine output and measured
pixels agree everywhere, which is what makes the split below trustworthy.

A live capture was **not** possible this session: the app launches but the Mac
is not vending windows — `Kadence` reports 0 windows and so does TextEdit, and
`screencapture` returns an all-black frame. That is the machine, not the code.
Everything below therefore rests on the committed screenshots plus the engine
run, and none of it depends on a screenshot being current.

**(a) The two bars at 12:30 and 12:50 — a *view* bug, plus G-011.**
`DayLayoutEngine` is correct and is not involved. "Stand-up" (12:30–12:45) and
"Check mail" (12:50–13:00) do not overlap even after the §3.3 clamp, cluster
separately, and each takes the whole column (Day y=750 h=13 / y=770 h=11; Week
y=550 h=11 / y=564.67 h=11). No packing and no cascade: slot width is the full
column, 1054pt in Day and 146.14pt in Week, against
`size.dayColumnCascadeThreshold` of 72. They collide because
`GridBlockView` never constrains itself to `renderedHeight` and
`DayColumnView.blockStack` sizes it with a default-**centred**
`.frame(height:)` (DayColumnView.swift:194), so a block whose content cannot fit
overflows its laid-out frame symmetrically instead of being clipped. Both bars
draw ~22pt tall — `size.blockGlyphSize` (11) + 2 × `size.blockPadding` (5) — and
spill ~5pt each way, closing the 7pt / 3.5pt gap between them. Measured, Day:
frames 1376–1402 and 1416–1438 device px; drawn 1367–~1410 and 1405–1448.
The underlying spec problem is **G-011**: the 11–15 tier is not renderable at
the specced padding at all.

**(b) The 18:00 trio in Week — working as specified.** 3-block cluster, Week
column 152.14pt, slot width `(152.14 − 4) / 3 − 2` = **47.38 < 72**, so step 3
fires exactly as §3.3 says it should. Indent
`min(round(152.14 × 0.19), 22)` = 22; blocks land at x = 0 / 22 / 44 with
visible widths 22 / 22 / 108.14, and 22 < `size.blockCascadeMinReadableWidth`
(44), so the first two are glyph-only. All of that is confirmed in the pixels
(blue starts 42–44px into the column, the dashed block 86–88px in) and in the
z-order (start order, later on top). Nothing to fix. For contrast, the same trio
in **Day** packs — slot width 350 — which is also what §3.3 predicts.

**(c) The 08:38 travel band — G-012, plus the same view bug as (a).** The band
belongs to "Datenmodellierung", not to "Morning review". Two separate things:

- *Day.* True interval 22 minutes = 22pt ≥ `size.travelBandHeight` (18), so
  components.md §4 case 1 applies and the band correctly draws above its own
  event, 08:38–09:00. It lands on "Morning review" (08:00–09:00) because
  §3.3 step 1 clusters on raw event times only
  (`DayLayoutEngine.swift:166-189`, fed from `DayColumnView.swift:117-119`) and
  knows nothing about the band's visual footprint. The two events do not
  overlap, so both get the full column and the band paints over the bottom 20pt
  of a block that has no idea it is there — hiding the §3.4 meta line, which is
  visibly missing from "Morning review" in the screenshot while
  "Datenmodellierung" below it has one. **This is a spec gap, G-012**, not an
  implementation error: the code matches §3.3 literally. It is *not* the
  short-case bug the report suspected — the short case (6-minute band on "Coffee
  with Nora") renders correctly as an 18pt strip inside the block's own top,
  which the pixels confirm (strip 11:00–11:18, block frame starts at 11:00).
  The claim that "Datenmodellierung starts on top of it" does not reproduce: the
  band ends at 09:00 and the block starts at 09:00, exactly adjacent.
- *Week.* The same 22-minute band is only 16.1pt, so it is case 2 and correctly
  becomes an inside-strip. It still clips "Morning review" by ~2.5pt, and for a
  different reason: with an 18pt strip at its top the block's `.full` tier needs
  ~73pt in a 64pt frame, and the centred overflow from (a) pushes the strip
  ~4.5pt above its own frame. Same `DayColumnView.swift:194` root cause.

**Classification, stated plainly.** (a) code bug + **G-011**; (b) correct, no
action; (c) **G-012** in Day, code bug in Week. **None of the three is a stale
screenshot** — every one reproduces against today's engine output and today's
view code. The code bug is one fix in the view layer and is common to (a) and
the Week half of (c); G-012 is independent of it and can be fixed separately.
Splitting the follow-up per symptom is therefore warranted, but (a) and (c)-Week
should be one change, not two.

**Superseded by tasks P2-T05 and P2-T06, above.** (a) and (c)-Week are fixed;
the "one fix in the view layer" this paragraph anticipated is the change
documented at the top of this section. (c)-Day / G-012, described here as still
open, is now also fixed — task P2-T06 built the footprint-clustering fix; see
the top of this section. All three symptoms are now closed or confirmed
correct; nothing from this diagnosis remains open.


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
4. **Phase 1 has open deviations.** 18 absent, 6 built-differently, **0 invented
   values**, **0 open spec contradictions** (D4 closed 2026-09-11 by task
   P2-T05, per `design/GAPS.md` G-011 — CLOSED; see §1.7 and DEVIATIONS.md) —
   see `DEVIATIONS.md`, re-audited
   2026-09-10 against the current spec text, plus A22/A23 from P2-T01 and A24
   from P2-T02. **A22 is the one to take next**: `⎋` does not cancel a draft at
   all, which is a §3 rule the build simply does not implement, and it is a
   small change now that the binding underneath it is safe. Do not wire it up on
   a tree without the `draftBinding()` fix — it runs the code path that used to
   trap.
5. **Phase 1 never produced its screenshot set** (§2.2), and root `INDEX.md`
   describes 16 files that do not exist.
6. **The ⎋ / ↩ crash is fixed** (§1.5). It outranked everything on this list
   while it was open; nothing else was started until it was closed.
7. **Click-to-select is fixed** (§1.6). Same precedence: it made the calendar
   unusable with a mouse, and nothing else was started until it was closed. Two
   things it left behind — **A24** (a block reporting itself selected to
   accessibility when it is not) and **G-010** (§6 does not say which block wins
   when a click lands on two) — are both open and neither blocks Phase 2.
   The **block-overlap rendering defect** was the next task; G-010 is its
   spec-side neighbour and worth reading first.
8. **The block-overlap defect is fully resolved.** (a) and (c)-Week are fixed
   (§1.7, task P2-T05, per `design/GAPS.md` G-011 — CLOSED): the view-layer
   bug — blocks painting outside their laid-out frame because `GridBlockView`
   was never constrained to `renderedHeight` and `DayColumnView.swift` centred
   it — is fixed together with `DensityTier`'s new 18/28/53 boundaries; neither
   alone would have closed it. (c)-Day is now also fixed (§1.7, task P2-T06,
   per `design/GAPS.md` G-012 — CLOSED): `DayLayoutEngine` clusters and packs
   on a layout footprint rather than raw event times, so a case-1 travel band
   pulls its parent's overlapping neighbour into the same cluster instead of
   drawing over it. The 18:00 cascade (symptom (b)) was always correct and was
   not touched.

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

*(Corrected 2026-09-11 by task P2-T05 — G-010 and G-011 had been closed by DA's
task P2-T04 in `design/GAPS.md` but this section still listed them as open.
That was a stale-entry bug in this file, not in the spec; it is fixed below.)*

*(Corrected again 2026-09-11 by task P2-T06 — G-012 was ruled CLOSED at the
spec level by task P2-T04 on the same day as G-010/G-011, but this section
kept listing it as open because the code side had not been built yet. It is
fixed in code now too; the stale entry is corrected below.)*

Two remain open, none blocking: **G-003** and **G-005**. Closed: G-004, G-006,
G-007, G-008, G-009, G-010, G-011, G-012. **There are no invented design
values in the codebase** and no `// SPEC-GAP` markers left in `Kadence/`.

**G-010 — CLOSED** (ruled 2026-09-11, task P2-T04, design agent):
interactions.md gains §6.1, stating frontmost-wins as "paint order is hit
order" — the build's existing behaviour is now a decision, not a side effect.
"Effect on the build: none required" per the ruling; nothing in `Kadence/`
changed for it.

**G-011 — CLOSED** (ruled 2026-09-11, task P2-T04; fixed in code 2026-09-11,
task P2-T05, this task). components.md §3.1 padding (5) plus §3.3's glyph (11)
made the 11–15pt density tier 21pt of chrome, so that tier could not be drawn
at the height the same table assigned it, and the spec had never said a
block's render is confined to its laid-out frame. The ruling rederived every
tier's band from its own content set (boundaries 18/28/53) and added §3.5's
confinement invariant; both are now implemented — see §1.7. **Closes
DEVIATIONS.md D4 and B13.**

**G-012 — CLOSED** (ruled 2026-09-11, task P2-T04; fixed in code 2026-09-11,
task P2-T06). From the block-overlap diagnosis in §1.7 (task P2-T03):
layouts.md §3.3 step 1 clustered on raw event times and was silent on whether
a case-1 travel band's visual footprint (`departAt` → `event.start`) extends
its parent's footprint, which is why a band landed on a neighbouring block
that did not overlap it in time. The ruling defined a **layout footprint**
(`layouts.md` §3.3) that both step 1 and step 2 key off, and amended
`components.md` §4's z-order line to match; both are now implemented — see
§1.7.

No new gap was filed by this reconciliation. The three defects it found —
the stale `Tokens.swift`, the `tray.full` collision, and the missing screenshots
— are all cases where `design/` is unambiguous and the build or the repo has
drifted from it. None is a question for the designer, so none belongs in
`GAPS.md`.
