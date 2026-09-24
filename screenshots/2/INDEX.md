# screenshots/2 — Routines window review set, batch 1 (components.md §17 items 1–5)

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
