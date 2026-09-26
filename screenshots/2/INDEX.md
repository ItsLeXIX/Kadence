# screenshots/2 — review set (components.md §17)

Four batches, plus one attempted-and-blocked fifth. **Batch 1** (this file's
original content, task P2-T27, items 1–5) covers the Routines window.
**Batch 2** (task P2-T29 retry, items 6–7) covers the conflict panel's
two-option case. **Batch 3** (task P2-T31 retry, item 8) covers the conflict
panel's preview-active state. **Batch 4** (task P2-T32, item 9) covers the
sidebar needs-attention row at counts 0, 1 and 12. **Batch 5** (task P2-T35,
item 10 — the menu bar status item) produced **no images**: two prior tasks
(P2-T33, P2-T34) ran out of turns attempting it, and this task's own attempt
got as far as a fully reproducible capture method before hitting a locked
screen it cannot clear itself. See that section near the end of this file for
the full account and the method, left ready to run to completion. See each
batch's own section near the end of this file for its method, image(s), and
what could not be captured — none of this is folded into batch 1's narrative
below, since all five were attempted by different tasks against different
parts of the app.

## Batch 1 — Routines window (components.md §17 items 1–5)

Task P2-T27. Capture-only: no `Kadence/`, `KadenceTests/` or `Scripts/` file was
changed by this task. **Items 4 and 5 of components.md §17 (detached instances,
the re-sync popover, and the main-grid inspector's "Edited — differs" line) are
NOT captured here — see "What could not be captured" below.** Only items 1–3
are covered, as four images (item 3 needs two, one per mode direction).

Dataset: the fixed mock dataset (`Kadence/Mock/MockData.swift`), reseeded by a
fresh app launch immediately before capture (SwiftData seeding is
idempotent/empty-store-only, so a clean launch guarantees the pristine mock
state — no prior run's edits could have survived, since none were ever made:
this task never interacted with the main calendar window). Appearance: dark
(`defaults read -g AppleInterfaceStyle` → `Dark`, system default in this
environment, unchanged). View: the Routines window (`⌘⌥R`), template **"Daily
routine"** (the one seeded template — `MockData.makeRoutineTemplates()`,
weekdays Mon/Wed/Fri, three blocks: **Gym** 07:00–08:00 `.shiftable` (±30 min),
**Morning review** 08:15–08:45 `.fixed`, **Reading** 21:00–21:30 `.droppable`),
and the three seeded `TimeWindow`s (`MockData.makeTimeWindows()`: **Sleep**
22:00–07:00 `.protected` every day, **Low energy** 13:00–14:30 `.lowEnergy`
Mon–Fri, **Deep work** 15:00–17:00 `.peakFocus` Mon–Fri).

## Capture method (mechanical, not eyeballed)

Same family of technique as `Scripts/check-routines-window.sh` and
`screenshots/p2-t02`'s own INDEX (build → launch a fresh instance → drive with
real input → screencapture the window's own bounds), extended with two new
small compiled Swift helpers for this task (kept under `/tmp/kcap/`, not
committed — this is a capture task, not a tooling task):

1. `xcodebuild -scheme Kadence -destination 'platform=macOS' build` — clean
   build, used for every capture in this set.
2. Kill any existing `Kadence.app/Contents/MacOS/Kadence` process, park the
   pointer off-window, `open -n "$APP" --args -ApplePersistenceIgnoreState YES`
   (same flag `check-accessibility.sh`/`check-routines-window.sh` already use,
   for the same reason: suppresses window-restoration flake on this machine —
   see `STATUS.md` §8/§11).
3. `osascript`/System Events: activate the process, `keystroke "r" using
   {command down, option down}` to open the Routines window (the same
   shortcut `KadenceCommands.swift` binds to Window ▸ Routines).
4. Position and size the Routines window to a fixed `1600×1020` frame at
   `{-1632, 30}` via `set position of window 1` / `set size of window 1`, then
   minimize the main window (`set value of attribute "AXMinimized" of window 2
   to true`) so it cannot peek through the Routines window's rounded corners
   in the capture (it did, faintly, in an early test capture — a capture
   artifact from overlapping window frames, not an app defect; fixed by
   minimizing rather than by cropping around it).
5. A window's **true** on-screen bounds are read back with a small compiled
   Swift helper (`wininfo`, `CGWindowListCopyWindowInfo`) rather than trusted
   from what was requested — macOS clamped one over-tall request during
   setup (see "What did not make it in" below) and the actual applied bounds
   were used for every `screencapture -R` region from then on.
6. Mode switch (Blocks ⇄ Windows): `keystroke "]" using {command down}` /
   `keystroke "["` — `RoutinesWindow`'s own `⌘[`/`⌘]` shortcuts
   (interactions.md §11.1), delivered to the already-focused canvas
   (`.task { canvasFocused = true }` on window open).
7. Scrolling the canvas: a small compiled Swift helper (`kscroll`) posts real
   `CGEventType.scrollWheel` events at a point inside the canvas — the same
   "post a real HID event, don't fake it through the accessibility API"
   discipline `check-block-click-selects.sh`'s own header explains for clicks
   (`click at` bypasses hit-testing; a synthesized scroll event does not).
8. `screencapture -x -R<x>,<y>,<w>,<h>` against the exact bounds from step 5.
   The resulting PNGs are 2× the requested point size (this display renders
   screenshots at a 2× backing scale in this environment) — noted here so a
   reviewer isn't surprised by e.g. a 3200×2040 PNG for a 1600×1020-point
   capture.
9. All Kadence processes killed (`pkill -9 -f
   "Kadence.app/Contents/MacOS/Kadence"`) after every capture pass, confirmed
   with a follow-up `pgrep` returning nothing.

### What did not make it into the final frame, and why

The Routines window's canvas is a full 24-hour hour-grid `ScrollView`
(`hourHeightWeek` = 44pt/hour), and this machine's display would not grant a
window taller than **1020pt** at this position — a second, taller resize
request (`{1050, 1120}` at one point during setup) came back clamped to
`{1050, 1020}` at `y=30` (confirmed via `wininfo`, not assumed). A `1020pt`
window cannot show the full day (24×44 + header ≈ 1113pt needed) — with no
scroll, the top-anchored view runs from `00:00` to about `20:00`. Since item 1
needs **Gym (07:00), Morning review (08:15) and Reading (21:00)** all on
screen together, the canvas was scrolled down (via `kscroll`, see above) by a
fixed amount that brings the visible range to roughly `03:00`–`23:00` —
comfortably holding all three. This scroll position is used for
`routine-template-flexibility.png`; the two "inactive layer" images
(`routine-blocks-mode-inactive-windows.png` /
`routine-windows-mode-inactive-blocks.png`) and
`routine-windows-all-three-kinds.png` use the **unscrolled top** position
instead (`00:00` at the top edge), which is what puts all three `TimeWindow`
kinds in frame at once (Sleep's `00:00`–`07:00` head, or `22:00` tail; Low
energy `13:00`–`14:30`; Deep work `15:00`–`17:00`).

## The four images

| # | file | §17 item | mode / scroll | what it shows |
|---|---|---|---|---|
| 1 | `routine-template-flexibility.png` | 1 | Blocks, scrolled ~03:00–23:00 | All three flexibility rail styles together |
| 2 | `routine-windows-all-three-kinds.png` | 2 | Windows, top (00:00) | Protected + low-energy + peak-focus together |
| 3a | `routine-blocks-mode-inactive-windows.png` | 3 (Blocks-mode half) | Blocks, top (00:00) | Windows layer while Blocks mode is active |
| 3b | `routine-windows-mode-inactive-blocks.png` | 3 (Windows-mode half) | Windows, top (00:00) | Blocks layer dimmed while Windows mode is active |

### 1. `routine-template-flexibility.png` — §17 item 1

Blocks mode (toolbar segmented control shows **Blocks** selected, filled
capsule). Inspector reads **"Daily routine" / Weekdays: Mon, Wed, Fri / Blocks:
3 / Total: 6.0 h** (the template summary, §8.1 — nothing selected). Three
`RoutineBlock`s visible on each of the Mon/Wed/Fri columns, each rendered with
a visibly different leading rail per components.md §2.3/§13.2:

- **Gym** (07:00–08:00, `.shiftable`) — rail has a small dark gap before the
  block's own top/bottom corner radius and rounded end caps: `.inset`.
- **Morning review** (08:15–08:45, `.fixed`) — rail runs flush from the
  block's top-left corner to its bottom-left corner, no gap, no visible
  end-cap rounding beyond the block's own radius: `.solid`.
- **Reading** (21:00–21:30, `.droppable`) — rail shows visible 2px-on/2px-off
  dashing along its length: `.dotted`.

Verified, not eyeballed: the raw capture was cropped and zoomed 4–6× at each
block's leading edge (verification-only crops, not shipped) and the three
styles are visually distinct at that zoom in exactly the pattern §2.3
prescribes — inset (Gym) vs. solid (Morning review) vs. dotted (Reading). The
**Low energy** time window is also incidentally visible (13:00–14:30 hatch),
drawn normally and non-hit-testable per §13.3's Blocks-mode row — expected,
not a defect.

Judgement call worth recording: `Gym`'s title barely fit at the routine
column's natural width in an earlier, narrower test capture (`1050pt` window)
— at that width the title compressed to an unreadable sliver while the time
range still rendered truncated (`07:00-0…`). That is ordinary SwiftUI
space-starvation under `.compact` tier's un-truncated title `Text`, given
`routineEditorColumnMin` (84pt) is deliberately narrower than the main
calendar's column floor (§13.1's own table) — not a bug, and not shipped; the
window was simply widened to `1600pt` (7 columns × ~150pt effective) for a
legible capture instead.

### 2. `routine-windows-all-three-kinds.png` — §17 item 2

Windows mode (toolbar shows **Windows** selected), scrolled to the top
(`00:00`). All three `TimeWindow` kinds are visible together — the only place
in the app they ever are (§17 item 2's own wording):

- **Sleep** (`.protected`, 22:00–07:00, every day) — its `00:00`–`07:00` head
  is visible at the very top of frame as the familiar hatched protected
  treatment.
- **Low energy** (`.lowEnergy`, 13:00–14:30, Mon–Fri) — hatched fill, same
  treatment Blocks mode already showed.
- **Deep work** (`.peakFocus`, 15:00–17:00, Mon–Fri) — **only rendered in
  Windows mode** (components.md §7's "Editor exception"): a 1pt dashed
  outline, `color.window.peakFocusEdge`, no fill, spanning the Mon–Fri
  columns exactly at 15:00–17:00.

The three routine blocks are also in frame (Gym, Morning review), visibly
dimmed — see 3b below for the machine-checked opacity value; this image's own
job is only the three window kinds.

### 3a. `routine-blocks-mode-inactive-windows.png` — §17 item 3, Blocks-mode half

Blocks mode active, top scroll position. Shows the **windows layer** — the
"other" layer while Blocks mode is active. **Correction against the task
brief's own wording:** the brief describing this file called for "windows
layer dimmed to `opacity.editorInactiveLayer`" in Blocks mode, but
components.md §13.3's own table says the opposite for this direction —
Blocks mode's other layer ("windows") is "drawn normally, not hit-testable,"
full opacity; only Windows mode's other layer ("blocks") dims. Code confirms
the spec, not the brief:
`RoutinesWindow.swift`'s `.opacity(editorMode == .windows ? ... : 1)` is
conditioned on `editorMode == .windows`, and there is no corresponding
opacity modifier anywhere on the windows-drawing layer. **Pixel-checked, not
eyeballed:** the Low-energy hatch region (a 320×130pt sample block, one pixel
every 2pt) has a **byte-for-byte identical color histogram** between this
image's source capture and `routine-windows-mode-inactive-blocks.png`'s (both
captured at the same window bounds and scroll position, one in each mode) —
the windows layer's pixels do not change at all between the two modes, which
is the strongest form of "not dimmed" a screenshot diff can show. This image
is filed under this task's own required name; the file name's "inactive"
wording is kept as given, but this note is the accurate account of what it
actually shows.

### 3b. `routine-windows-mode-inactive-blocks.png` — §17 item 3, Windows-mode half

Windows mode active, same top scroll position, same window bounds — identical
source capture to `routine-windows-all-three-kinds.png` (both needs are the
same underlying state; saved twice under the two required names). Shows the
**blocks layer** dimmed while Windows mode is active. **Pixel-checked:**
sampling the Gym block's title text at identical coordinates between the
Blocks-mode and Windows-mode captures:

| | Blocks mode (opacity 1) | Windows mode (dimmed) |
|---|---|---|
| Title text (white) | `(242, 242, 244)` | `(117, 120, 119)` |
| Rail (bright green) | `(100, 199, 107)` | `(60, 103, 64)` / `(54, 75, 58)` |
| Block fill | `(39, 54, 42)` | `(33, 39, 35)` |
| Canvas background (unaffected control) | `(28, 28, 30)` | `(28, 28, 30)` |

Solving the composite equation `dimmed = bg + opacity × (full − bg)` for the
title-text row against the canvas background gives `opacity ≈ 0.41–0.43` per
channel; against the block's own fill (the more correct backdrop, since the
title text sits on the fill, not directly on canvas) gives `opacity ≈
0.35–0.38`. `Tokens.Opacity.editorInactiveLayer = 0.4` (`Tokens.swift:244`)
sits inside or immediately adjacent to both estimates — the residual few
hundredths is consistent with 8-bit quantization and macOS's gamma-correct
(not naive-linear) compositing, not with a different opacity value. Background
pixels (`(28,28,30)`) are identical between the two captures, confirming
nothing except the block layer's opacity changed. This is the confirmation
components.md §13.3 and this task's brief both ask for — "not just
eyeballing it."

## What could not be captured — §17 items 4 and 5, blocked

**Not attempted, not faked.** components.md §13.4 (detached instances,
Re-sync, the main-grid "Edited — differs" inspector line) has **no
implementation anywhere in `Kadence/`** — confirmed by search, not assumed:

- `grep -rn "isDetached\|Detached\|Re-sync\|resync\|differs from\|instances
  edited\|Revert to routine"` across `Kadence/` returns nothing but the
  `resyncPopoverWidth` **token itself** (unused by any view) and
  `RoutinesWindow.swift`'s own comments recording the gap.
- `RoutineEngine.materialize` only guards against re-creating an event that
  already exists for a given `(sourceID, externalID)` pair — it has no
  concept of "this occurrence was hand-edited," so it cannot distinguish an
  edited instance from an untouched one.
- `EventStore.move`/`resize` have no special case for a `.routine`-origin
  event at all — editing one on the main grid is, today, indistinguishable
  from editing any other event.
- `RoutinesWindow.swift`'s own `RoutineInspectorView.templateSummary` has a
  comment explaining exactly this: *"the count is always zero... the row is
  omitted, not stubbed."*

This is not a new finding — it is the same gap every task from P2-T10 through
P2-T26 has logged in `STATUS.md`/`DEVIATIONS.md` as absent, most recently
P2-T26's own closing list. This task's brief assumed §13.4 was built ("Phase
2's UI is fully built and verified") and asked for three images that all
depend on it:

- `routine-detached-instances.png` (§17 item 4's count + Re-sync button)
- `routine-resync-popover.png` (§17 item 4's confirmation popover)
- `routine-detached-instance-selected.png` (§17 item 5's inspector line)

None of these can be produced by driving the real app, because the feature
they show does not exist to drive — "edit 3 occurrences on the main grid"
does nothing that the Routines window or the inspector can detect. Per this
task's own instruction ("if you find ... an actual bug ... stop, do not fix
it, and report it — do not silently patch it into a 'nicer' screenshot"),
this was reported rather than worked around: no detachment state was
hand-written into the data layer to fake a screenshot, and no UI was added
(out of scope for a capture-only task regardless). See `STATUS.md` and
`DEVIATIONS.md`'s new entries for this task for the same account.

## Known open at capture time

- **components.md §13.4 in full** (as above) — the largest gap, blocking two
  of the six §17-item-4/5 images this batch was asked for.
- **The flexibility control's interactive stepper** (§13.2) is still
  read-only text in the inspector, unchanged from every prior task's account
  — not exercised by these captures (nothing here selects a block).
- `RoutineEngine.materialize` still does not honour protected windows — not
  visible in any of these four images (none show a materialized `Event`).
- §17 items 6–12 (conflict panel states, needs-attention counts,
  preview-active state, menu bar extra states, snooze result row) are
  deliberately out of scope for this task and not represented here at all —
  a follow-up task's job, per this task's own brief.

---

## Batch 2 — conflict panel, two-option case (components.md §17 item 6, two-option half)

Task P2-T29 (retry, after two prior failed attempts for reasons unrelated to
app code — see `STATUS.md`'s entries for both). Capture-only: the only code
change anywhere in this batch's lineage is the small `Kadence/Mock/MockData.swift`
fixture addition already committed at HEAD before this retry started (a
`.manual` "Client call" 19:50–20:20 overlapping a `.routine .fixed` "Focus
review" 20:00–21:00, both on today's date — see that file's own inline
comment for why these times and this flexibility were chosen). This retry
touched no `Kadence/`, `KadenceTests/` or `Scripts/` file.

Dataset: same fixed mock dataset as batch 1, but note the store had to be
**wiped and reseeded** for this capture — `MockData.seedIfNeeded` only seeds
an empty store (see that function's own doc comment), and a stale
`~/Library/Containers/XIX.Kadence/Data/Library/Application Support/default.store`
left over from an earlier attempt (21 events, predating the "Client call"/
"Focus review" fixture) was still on disk. Deleted
`default.store`/`-shm`/`-wal` before the launch used for this capture, then
verified via `sqlite3` against the reseeded store that both new events were
present (23 events total) before driving the app further. Appearance: dark
(system default, unchanged, same as batch 1). Window: the main window
(`MainWindow`), not the Routines window — the conflict panel lives in the
main window's inspector.

### Capture method

Same family of technique as batch 1 (real input, no synthetic AX state,
bounds read back rather than assumed), reusing the same compiled helpers left
under `/tmp/kcap/` (`kclick` — a real `CGEventType` mouseDown/mouseUp pair
through the HID event tap, not `System Events ... click at`, which only sends
`AXPress` and would bypass hit-testing exactly the way
`check-block-click-selects.sh`'s own header explains; `wininfo` — true
on-screen window bounds via `CGWindowListCopyWindowInfo`, not assumed):

1. `xcodebuild -scheme Kadence -destination 'platform=macOS' build` — clean
   build (also this task's required build-and-test step; see `STATUS.md`).
2. Kill any existing `Kadence.app/Contents/MacOS/Kadence` process by pid (same
   pid-targeting discipline as `check-accessibility.sh` — `System Events`
   resolves a process by name, so a wedged instance with no window can
   answer for a healthy one).
3. Delete the stale store (see "Dataset" above), then `open -n "$APP" --args
   -ApplePersistenceIgnoreState YES`, poll for the first window the same way
   `check-accessibility.sh` does, and confirm via `sqlite3` against the fresh
   `default.store` that "Client call"/"Focus review" are present before
   proceeding — this batch hit the stale-store trap once and is recording the
   check so a future capture task does not lose time rediscovering it.
4. Position/size the main window to a fixed `{80, 80}`/`1500×900` frame
   (`System Events ... set position/size of window 1`) — the same
   `1500×900` size `check-block-click-selects.sh`/`check-block-hit-regions.sh`
   already use for main-window driving, applied here for the same reason
   (predictable layout for both AX queries and the capture region).
5. Locate the needs-attention row: a small AppleScript walks the AX tree from
   `window 1` down (depth-bounded recursion over `UI elements of`), collecting
   role + value/title/description + position/size for every element that
   carries a non-generic label. Before the store held the new fixture, no such
   row existed in the sidebar (confirming `state.conflicts.isEmpty` at that
   point — see "Dataset" above for the fix); after reseeding, exactly one new
   `AXButton` appeared as the sidebar's first outline row, at the position
   components.md §10.2 describes (top of the list, ahead of "Sources").
6. `kclick` a real HID click at that button's on-screen center
   (`components.md §14.1`: "Activating it selects the first unresolved
   conflict and puts the inspector into conflict mode"). Re-ran the same AX
   walk afterward and confirmed the inspector's content changed from the
   ordinary day-summary panel to the conflict panel — the walk now surfaced
   `overlaps` and `20:00–20:20 · 20 min overlap` (components.md §14.2's own
   wording, `ConflictPanelView.overlapLine`) in place of the "Blocks / N",
   "Scheduled / H h", "First / HH:mm · title" rows batch 1's day-summary
   panel would show instead — that swap is what confirms conflict mode is
   active, since the option-row and collision-block buttons' own AX
   title/description did not surface through this particular walk (SwiftUI
   appears to fold their inner `Text` children into the button's own AX node
   without exposing a readable title/description/value through this method —
   not investigated further, since the screenshot itself is the actual
   evidence for this task, and the walk already gave two independent,
   spec-matching text confirmations).
7. `wininfo Kadence` to read back the window's true on-screen bounds
   immediately before capture (confirmed unchanged from step 4: `{80, 80,
   1500, 900}`).
8. `screencapture -x -R80,80,1500,900` against those exact bounds.
9. All Kadence processes killed (`pkill -9 -f
   "Kadence.app/Contents/MacOS/Kadence"`) after the capture, confirmed with a
   follow-up `pgrep` returning nothing.

Unlike batch 1's captures, this PNG came back **1500×900** (1×), not 2×
`(3000×1800)` — noted so a reviewer isn't surprised by a different pixel size
between the two batches; nothing here depends on which scale factor a given
capture session's display happened to render at.

### The one image

| file | §17 item | what it shows |
|---|---|---|
| `conflict-panel-two-options.png` | 6 (two-option half) | Full main window, conflict mode active in the inspector |

**`conflict-panel-two-options.png`.** The inspector (right-hand panel) shows,
top to bottom: the **collision header** (§14.2) — a real "Client call" block,
the word "overlaps", a real "Focus review" block, both rendered at the
16–27pt density tier with their normal rail/hue/style (the same
`.conflicted` presentation the grid itself uses, per `ConflictPanelView`'s own
doc comment), then the overlap line "20:00–20:20 · 20 min overlap"; then the
**two option rows** (§14.3) — "Shorten Focus review by 20 min" with a
**Recommended** chip and the delta line "Focus review now 20:20–21:00", and
below it "Skip today's Focus review" with the delta line "Frees 60 min ·
today's occurrence only", with no chip. This is components.md §17 item 6's
two-option half, driven by the `.fixed`-flexibility branch of
`ConflictEngine.makeOptions`'s `.shorten` case (recommended because 20 min
disturbance < the skip option's 60 min — `ConflictEngine.finalize`'s
ascending sort).

### What could not be captured — §17 item 6's three-option half, and item 7, blocked

**Not attempted, not faked.** `ConflictEngine.makeOptions`/`finalize`
(`Kadence/State/ConflictEngine.swift`, lines 344–367 / 444–464) can
structurally only ever produce 1–2 options per conflict, with the recommended
one always at index 0 after a strict ascending-disturbance sort — there is no
input (fixture or otherwise) that reaches a third option or a non-first
recommendation, because there is no code path in either function that
produces one. This is a build gap, not a missing fixture — see `design/GAPS.md`'s
new **G-017** entry for the full citation and reasoning; it is not
re-explained here. Per this task's own instruction, `ConflictEngine.swift`
was not touched to manufacture a state it cannot currently reach.

### Known open at capture time (batch 2, in addition to batch 1's list above)

- **components.md §17 item 6's three-option half, and item 7 in full** — see
  "What could not be captured" above and `design/GAPS.md` G-017.
- §17 items 8–12 (preview-active state, needs-attention row at other counts,
  status item states, popover states, snooze result row) — explicitly out of
  scope for this task per its own brief; separate follow-up tasks' job.
  **(Item 8 closed by batch 3, below.)**

---

## Batch 3 — conflict panel, preview-active state (components.md §17 item 8)

Task P2-T31 (retry — the first attempt ran out of turns with no commit).
Capture-only: no `Kadence/`, `KadenceTests/` or `Scripts/` file was touched.

Dataset and appearance: identical to batch 2's own — see that section above,
not restated here. Steps 1–6 of batch 2's "Capture method" (build, kill any
stale process, wipe/reseed the store, verify via `sqlite3`, position the main
window to `{80, 80}`/`1500×900`, AX-walk to find and click the needs-attention
row to enter conflict mode) were followed exactly, with one substitution
recorded in `STATUS.md`'s new §32 rather than here: a real `kclick` HID event
did not register against this session's window (evidence points at
concurrent, unrelated human use of the machine during this task, not an app
defect — full account in `STATUS.md`), so both the needs-attention row and
the option-row click below were driven via `AXPress` posted at the same
AX-confirmed element instead. This exercises the same `Button` `action` a
real click would; it is a capture-tooling substitution, not a different
interaction path through the app.

**The one new step.** `ConflictPanelView`'s `optionRow` (lines 107–135) is a
plain `Button` wired in `MainWindow.swift` (`inspectorBody`, ~line 257) to
`onSelectConflictOption: { state.selectedConflictOptionID = $0 }`. Setting
that one field is everything that gates preview — `MainWindow.isConflictPreviewActive`
and `DayColumnView`'s `activeConflictPreview`/`isPreviewGhost` (lines
~164–219) both key off it being non-nil. An AX walk of the inspector (taken
while already in conflict mode, window confirmed at `{80,80}/1500×900`)
located the first option row's `AXButton` at absolute `(1276, 250)`, size
`288×60` — activating it (via `AXPress`, per the substitution above) was
the entire step.

Before saving, preview-active state was confirmed against all four things
this task's brief asked for, not assumed: (a) a blue inset border around the
calendar grid only (`Tokens.Color.Interactive.accent` /
`previewCanvasBorder`); (b) "Focus review" drawn at its proposed shortened
frame (20:20–21:00); (c) a dimmed sliver of the same block at its original
frame (20:00–20:20 — the part the full-opacity proposed block, drawn above
it at a higher `zIndex`, doesn't cover; `DayColumnView`'s `isPreviewGhost`
dims the *real* block in place rather than drawing a second dashed copy, so
only the uncovered part reads as dimmed — see `STATUS.md` §32 for the exact
line references); (d) the clicked option row highlighted with
`Tokens.Color.Interactive.selectedRowFill`. All four were visible in a
zoomed verification crop (not shipped) before the full-window capture below
was saved.

The canvas was scrolled down first (`kscroll`, the same real-HID-scroll
helper batch 1 used — this one worked normally, unlike `kclick`) so the
07:00–23:00 range, and specifically the previewed block, is in frame; the
20:00 hour is well below the fold at the window's default top scroll
position.

### The one image

| file | §17 item | what it shows |
|---|---|---|
| `conflict-panel-preview-active.png` | 8 | Conflict preview active: canvas border, previewed block, dimmed ghost sliver, selected option row |

**`conflict-panel-preview-active.png`.** Full main window, `1500×900` (1×,
same scale note as batch 2 — not 2×). Inspector shows the same collision
header as batch 2's own image plus the first option row now highlighted
blue; the calendar canvas carries the accent inset border around its own
bounds only; "Focus review" appears at `20:20–21:00` in its normal
full-opacity style; immediately above it, a thin amber sliver (`20:00–20:20`,
still carrying the conflicted-block warning glyph) is the dimmed remainder of
the original block peeking out from behind the proposed block's higher
`zIndex`.

### Known open at capture time (batch 3, in addition to batches 1–2's lists above)

- §17 items 9–12 (needs-attention row at other counts, status item states,
  popover states, snooze result row) — explicitly out of scope for this task
  per its own brief; separate follow-up tasks' job. **(Item 9 closed by batch
  4, below — this line is kept, struck nowhere, only annotated, since it was
  accurate at batch 3's own capture time.)**
- The `kclick`-vs-`AXPress` finding above — not an app gap, a capture-tooling
  note for whichever task next needs to drive this window by real HID click
  on a machine that may be in concurrent use.

---

## Batch 4 — sidebar needs-attention row at 0, 1 and 12 (components.md §17 item 9)

Task P2-T32. Capture-only in intent, but unlike batches 1–3 this one required
a real, permanent `Kadence/Mock/MockData.swift` fixture addition (not a
revert-after-capture change) to reach a count of 12 — see "The count-12
fixture" below. No other `Kadence/`, `KadenceTests/` or `Scripts/` file was
touched.

Dataset and appearance: the same fixed mock dataset and dark appearance as
batches 2–3 (system default, unchanged). Window: the main window
(`MainWindow`), `{80, 80}` / `1500×900`, same fixed frame batches 2–3 used —
chosen again here for the same reason (predictable layout for the capture
region). Unlike batch 1's Routines-window captures, these three PNGs are all
**1×** (`1500×900`, not `3000×1800`), matching batches 2–3's own note about
this machine's scale factor varying by capture session.

### What `state.conflicts.count` actually counts

`SidebarView.swift`'s needs-attention row is `if !state.conflicts.isEmpty`,
reading `CalendarState.conflicts: [Conflict]`, which `MainWindow.swift`'s
`refreshConflicts()` sets from `ConflictEngine.detect(events:routineBlocks:)`
— a `.routine`-origin event overlapping a `.manual`/`.imported`-origin event,
skipping any `.skipped` occurrence (G-015). Two things confirmed by reading
the code before touching any fixture, not assumed:

- `events` (`MainWindow`'s own `@Query(sort: \Event.start)`) has **no date
  predicate** — it is every `Event` in the store, not just the visible
  day/week. A conflict pair can sit on a day nobody is looking at and still
  count.
- `WindowConflict` (routine-vs-protected-window overlaps, e.g. the existing
  "Late lab session" fixture against the Sleep window) is a **separate**
  type, never folded into `state.conflicts` — DEVIATIONS.md already records
  this as "still no `WindowConflict` wired into ... the needs-attention row/
  count" (P2-T19's entry). Confirmed unchanged by this task: only
  `Conflict` (event-vs-event) feeds the sidebar badge.

Both facts are what make the count-0 and count-12 states buildable as pure
fixture data, entirely off-day, with no interaction needed.

### Count 1 — the existing default, unmodified

Before this task added anything, the mock dataset already produced exactly
**one** `Conflict`: item 17's own "Client call" (`.manual`, 19:50–20:20) /
"Focus review" (`.routine`, `.fixed`, 20:00–21:00) pair, added by task P2-T29
for the conflict-panel batch 2 captures above. Checked by hand against every
other event in `makeEvents(now:)` (every routine event's start/end against
every manual/imported event's) before relying on it — no other pair overlaps
under `ConflictEngine.overlaps`'s strict (non-touching) rule. This state
needed no fixture change at all: build, wipe the stale store (same trap
batch 2 already hit and documented — a leftover `default.store` from a prior
run predates the mock dataset a given build actually seeds, so it is deleted
before every fresh launch in this batch too), launch, confirm via `sqlite3`
that the store holds the expected 23 events, screenshot.

### Count 0 — deliberately constructed, not reached by driving the UI

The task brief's own suggested route was resolving the count-1 conflict
through the real conflict panel (select the needs-attention row, preview the
recommended option, apply it with `↩`) and screenshotting what's left. That
UI path was tried first, driven for real (`kclick`/`kkey`, the same HID-event
helpers batches 2–3 left under `/tmp/kcap/`, not `System Events ... click
at`/synthetic AX actions): the option-row click and the `↑`/`↓` preview
navigation (`CalendarState.moveSelectedConflictOption`) both worked and were
visibly confirmed (the recommended option highlighted blue, the accent
preview border appeared on the canvas, `↓` correctly moved the preview from
the shorten option to the skip option). Applying with `↩`
(`CalendarState.applyFocusedConflictOption`, gated on
`state.focusedRegion == .inspector`) did not visibly commit across several
different focus-reaching sequences (a direct click into the panel; `⇥`-cycled
into the inspector one or more times before `↓`/`↩`) — the panel stayed open
with the same option highlighted and the block on the canvas never animated
to its shortened frame. This was not chased further into a root-cause,
because `state.focusedRegion` is a hand-tracked flag separate from SwiftUI's
own `@FocusState`, kept in sync by a `.onChange` with a documented one-way
gap (see `MainWindow.swift`'s own comments near line 63/239), and correctly
diagnosing which of several plausible focus-timing causes is responsible
needs instrumentation this task's brief did not ask for and is not owed to a
capture-only task — `applyFocusedConflictOption`, `handleKey`'s `.return`
case, and everything else in `CalendarState`/`ConflictEngine` were left
untouched, per this task's explicit scope. **Not filed as a `design/GAPS.md`
gap** — nothing here contradicts or leaves unspecified a `design/` value;
this is a candidate code-behavior question for whoever owns
`applyFocusedConflictOption` next, recorded in `STATUS.md`/`DEVIATIONS.md`
instead.

Given that, count 0 was constructed deliberately instead, per this task's own
brief allowing exactly that: item 17's "Client call"/"Focus review" pair was
temporarily commented out in `MockData.swift`, built, the store wiped and
reseeded, and the result confirmed two ways before capture — `sqlite3`
against the fresh store showed no row titled "Client call" or "Focus review"
(21 events total, down from 23), and the running app's sidebar shows no
needs-attention row at all, Sources starting at the very top of the list
where the row would otherwise sit. The comment-out was then reverted
immediately (confirmed via `git diff` matching this batch's own intended
final `MockData.swift` state — see below) before the count-12 build.

### The count-12 fixture — the one permanent `MockData.swift` addition

`MockData.makeEvents(now:)` gained a new item 18, appended right after item
17's own pair, following the same "why this exists" comment style item 17's
own P2-T29 addition already set: a loop over `plusDays: 2` through
`plusDays: 12` (11 iterations), each adding one more `.manual`/`.routine
.fixed` pair with item 17's own exact overlap shape (19:50–20:20 /
20:00–21:00, 20-minute overlap, the `.shorten` branch of
`ConflictEngine.makeOptions` — no `RoutineTemplate`/`RoutineBlock` wiring
needed, same reasoning item 17's own comment already gives). Days 2–12 are
otherwise-empty in every existing fixture (items 1–17 only ever place a
timed event on `plusDays: 0` or `plusDays: 1`), so this addition cannot
change the rendered layout of anything any prior batch or any existing test
looks at — confirmed by `check-accessibility.sh` still reporting the same
**24** block-shaped elements on today's grid after the addition (the 22 new
events all land on future, unvisited days). Combined with item 17's own pair,
this gives `state.conflicts.count == 12` for review. Kept permanently per
this task's own brief, mirroring batch 2's own precedent for committing a
`MockData.swift` fixture addition rather than reverting it — this is mock
dataset content, not engine or state behavior, and no `Kadence/State/*` or
`Kadence/Views/*` file was touched to produce it.

### The three images

| file | §17 item | what it shows |
|---|---|---|
| `needs-attention-count-0.png` | 9 (0 half) | Sidebar with no needs-attention row — item 17's pair temporarily removed |
| `needs-attention-count-1.png` | 9 (1 half) | Sidebar needs-attention row reading "1" — the unmodified default dataset |
| `needs-attention-count-12.png` | 9 (12 half) | Sidebar needs-attention row reading "12" — item 17's pair plus the 11 new item-18 pairs |

**`needs-attention-count-0.png`.** Full main window. The sidebar's Sources
section begins immediately below the sidebar's top edge — no "Needs
attention" row, no badge, no empty-state placeholder of any kind, matching
§10.2's "hidden entirely at zero — no empty-state counter, no zero badge.
Zero shows nothing at all" exactly.

**`needs-attention-count-1.png`.** Full main window. A "Needs attention" row
sits above the Sources section, reading a plain "1" in a small chip at the
row's trailing edge, no icon (§10.2's "the row takes no icon").

**`needs-attention-count-12.png`.** Full main window. Same row, now reading
"12". **Verified, not just eyeballed** (components.md §10.2: `blockMeta`
type, `color.text.secondary` on `color.surface.canvasSunken`, radius
`radius.chip`): a 4×-zoomed crop of the badge (verification-only, not
shipped) plus direct pixel sampling of the saved PNG —

| sample | measured (dark mode) | token (dark mode) |
|---|---|---|
| badge background | `(22, 22, 23)` | `color.surface.canvasSunken` `#161618` = `(22, 22, 24)` |
| ordinary sidebar background (control) | `(26, 26, 27)` | — (confirms the badge fill is a distinct, slightly darker chip against the sidebar, not the same surface) |
| brightest pixel of the "12" glyph | `(159, 163, 171)` | `color.text.secondary` `#A8ADB5` = `(168, 173, 181)` |

The background match is within one 8-bit count per channel — as close as a
screenshot round-trip gets. The glyph sample reads slightly under the token
because at this row height and 1× capture scale, the "1"/"2" strokes are only
a few pixels wide, so even the brightest sampled pixel still carries some
anti-aliasing blend toward the darker chip fill behind it — the same
quantization/gamma-blend caveat batch 1's own opacity measurement notes for
exactly this reason. The direction and magnitude are both consistent with
`color.text.secondary` and inconsistent with any other text color in this
app's palette (`Text.primary` renders far brighter, at or near white; no red
or amber tone is present anywhere in the sample). No icon precedes the label,
matching count 1's own image and §10.2's rule.

### Known open at capture time (batch 4, in addition to batches 1–3's lists above)

- **`CalendarState.applyFocusedConflictOption` via `↩`, driven through real
  HID key events while the conflict panel is open, did not visibly commit**
  in this task's own testing — see "Count 0" above for the full account and
  what was and was not investigated. Not fixed, not filed as a `design/GAPS.md`
  gap (nothing here is a spec question), recorded here and in
  `STATUS.md`/`DEVIATIONS.md` for whichever task next drives that path.
- §17 items 10–12 (menu bar extra status item/popover states, the snooze
  result row) — explicitly out of scope for this task per its own brief;
  separate follow-up tasks' job, per the task brief that produced this batch.

## Batch 5 — attempted, blocked: menu bar status item states (components.md §17
item 10, task P2-T35, 2026-09-26)

**No images produced.** `status-item-normal.png`, `status-item-late.png` and
`status-item-empty.png` do **not** exist in this directory. Two prior tasks
(P2-T33, P2-T34) each ran out of turns attempting this same capture and each
left only a `Kadence/Mock/MockData.swift` diff behind (a `Journal` fixture,
added then fixed — see `STATUS.md` §34 and `DEVIATIONS.md`'s "Not a
deviation" section for the full history). This task closed out that
bookkeeping, then made its own attempt, following exactly the method its own
brief specified — no real-time waiting, direct SQLite edits to the ephemeral
store rather than editing `MockData.swift` again — and got substantially
further than either prior attempt before hitting a different, harder wall:
**the screen on this machine is locked**, and has been since before P2-T34's
own commit timestamp (`CGSSessionScreenLockedTime` → 2026-09-26 02:22:16;
P2-T34 committed at 02:56:55). That timing makes it likely the *real* reason
both prior tasks produced zero screenshots was this same lock, not the
wall-clock fixture problem P2-T34's own commit message names — the fixture
problem was real and worth fixing, but was not, on this evidence, the actual
blocker.

### What was proven out, ready for the next attempt

- **Schema** (`sqlite3 default.store '.schema ZEVENT'`): table `ZEVENT`,
  relevant columns `ZTITLE` (text), `ZSTART`/`ZEND` (Core Data reference-date
  seconds — epoch **2001-01-01 00:00:00 UTC**, i.e. `unix_time − 978307200`),
  `ZSTATUSRAW` (text: `scheduled`/`done`/`skipped`), `ZISALLDAY`,
  `ZISLOCKED`. Confirmed against two known values: `Morning review`'s stored
  `ZSTART` (`812095200`) converts to `2026-09-26 08:00:00` local — the exact
  `at(8)` `MockData` seeds it at — and a freshly reseeded `Journal`'s own
  `ZSTART` converted to a few minutes after the real seed wall-clock time,
  matching `now.addingTimeInterval(4 * 60)`.
- **Isolating `Journal` as NEXT:** with a fresh reseed (46 rows: 44
  `scheduled`, 1 `done` — `Statistik übung` — 1 `skipped` — `Gym`), a single
  `UPDATE ZEVENT SET ZSTATUSRAW='done' WHERE ZTITLE IN (...)` naming the
  other 17 today-dated titles (`Breakfast`, `Morning review`,
  `Datenmodellierung`, `Statistik übung`, `Coffee with Nora`, `Stand-up`,
  `Check mail`, `Prep: relational algebra`, `Gym`, `Training`,
  `Group call`, `Code review`, `Notes write-up`, `Client call`,
  `Focus review`, `Reading`, `Late lab session`) leaves `Journal` as the only
  not-done/not-skipped event today — verified by `SELECT` before each
  relaunch. `MockData.swift` was never touched.
- **Per-state `Journal` values**, computed from a fresh `date +%s` minus
  `978307200` each time (not hardcoded): Normal → `ZSTART = now + 600`,
  `ZEND = now + 1500`; Late → `ZSTART = now − 120`, `ZEND = now + 780`;
  Empty → also `ZSTATUSRAW='done'`.

None of the above needed a workaround — it all worked exactly as the task
brief predicted. What did not work, under the confirmed lock:

- `screencapture -x` returned a well-formed 3360×2100 PNG with **exactly one
  distinct pixel value across the whole image** — the lock curtain, not the
  desktop or menu bar. No crop of that image would show anything real.
- The status item's own `AXTitle`, read via the same `System Events` /
  `menu bar item of menu bar 2` approach P2-T25 proved out (`STATUS.md`
  §26), read `"Nothing left today"` even immediately after the `UPDATE`
  above confirmed `Journal` `scheduled` with a `ZSTART` ~9 minutes in the
  future on disk — i.e. it did not reflect the real state. Whether this is
  the screen lock suspending the `MenuBarExtra` label's own SwiftUI update
  cycle (the app was launched *while already locked*, so its first render
  may have run before `@Query` finished loading and never refreshed) or a
  separate bug was not chased further: under a confirmed lock, per this
  machine's own established precedent (`STATUS.md` §15–16), no AX read here
  is trustworthy enough to tell the two apart, and doing so would not yield
  a usable screenshot regardless of the answer.
- One non-destructive attempt to see if the lock would clear itself (a
  keystroke via `System Events`, no password entry attempted) left
  `CGSSessionScreenLockedTime` unchanged — it needs this machine's password,
  which this task does not have.

### Cleanup performed before stopping

Store deleted and reseeded fresh once more; `sqlite3` confirmed the pristine
44 `scheduled` / 1 `done` / 1 `skipped` split (46 rows total, `Journal` back
to its normal `now`-relative future start). All Kadence processes confirmed
killed (`pkill -9 -f Kadence`, `pgrep` empty).

### What is next

The moment `CGSessionCopyCurrentDictionary()` shows `CGSSessionScreenIsLocked`
absent or `0`, re-run steps 4–5 of `STATUS.md` §34's Part B (the `UPDATE`
statements above, one relaunch + `screencapture` + AX title check per state)
for Normal, Late and Empty in turn — no further investigation should be
needed. §17 items 11 (popover states) and 12 (snooze result row) are still
this batch's own explicit next-next items, unstarted, per the P2-T35 brief.
The full-width-vs-clipped-to-`size.statusItemMaxWidth` sub-variant of item
10 is also still unattempted, independent of the lock.

**Batch 6 attempt, still locked, timestamp 2026-09-26 03:58:12 CEST**
(task P2-T36): ran the exact lock probe `check-accessibility.sh` uses
(`swift -e` reading `CGSSessionScreenIsLocked` from
`CGSessionCopyCurrentDictionary()`) as step 0, before touching the store or
building anything, per this task's own brief. Result: `1` — still locked.
Per Parsa's standing ruling that a lock failure is environmental and should
not consume a full task's turn budget, stopped immediately: no build, no
reseed, no `screencapture` attempted, no store mutation made. A pre-existing
Kadence process (unrelated to this task, not launched by it) was observed
running via `pgrep` but was left untouched, since it predates this attempt
and killing it is not part of the lock-stop protocol. Still nothing further
to add beyond Batch 5's "What is next" above: re-run steps 4–5 of
`STATUS.md` §34 Part B the moment the probe reports `0`.
