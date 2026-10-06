# Kadence — layouts (Phase 1)

Scope: the main window and the three calendar canvases. Values are token paths
from `tokens.json`.

---

## 1. Main window

Standard macOS window chrome. No custom titlebar, no custom traffic lights.
`NavigationSplitView` with three columns; the calendar canvas is the content
column, not a detail column.

```
+----------------------------------------------------------------------+
| toolbar                                            size.toolbarHeight |
+-------------+--------------------------------------+-----------------+
|             |  day header row   size.dayHeaderHeight|                 |
|  sidebar    +--------------------------------------+   inspector     |
|             |  all-day row      (variable, §6)      |                 |
|             +--------------------------------------+                 |
|             |                                       |                 |
|             |  hour grid  (vertically scrollable)   |                 |
|             |                                       |                 |
+-------------+--------------------------------------+-----------------+
```

| Region | Default | Min | Max | Resizable |
|---|---|---|---|---|
| Sidebar | `size.sidebarWidthDefault` | `size.sidebarWidthMin` | `size.sidebarWidthMax` | yes |
| Canvas | flexible | `size.canvasWidthMin` | — | takes all remaining width |
| Inspector | `size.inspectorWidthDefault` | `size.inspectorWidthMin` | `size.inspectorWidthMax` | yes |

`size.canvasWidthMin` is 598, derived: `size.timeGutterWidth` (52) + 7 ×
`size.dayColumnMin` (78). Week view governs the floor; Day and Month fit in less.

**Minimum window: `size.windowMinWidth` × `size.windowMinHeight` (800 × 640).**
Derived: 180 sidebar + 1 divider + 598 canvas = 779, rounded up. Height: 52
toolbar + 24 month weekday header + 6 × 94 month rows = 640, which is the tighter
of the three views.

### 1.1 Collapse order

The canvas never collapses and never shrinks below its minimum. Collapse happens
in this order, by window width:

| Window width | Behaviour |
|---|---|
| ≥ 1200 | Sidebar, canvas and inspector all as split regions. |
| 900–1199 | Inspector auto-collapses. Re-opening it (⌥⌘I) presents it as an **overlay** anchored to the trailing edge at `elevation.level2`, over the canvas, not as a split region. |
| < 900 | Sidebar also auto-collapses; toggling it presents it as an overlay the same way. |

Auto-collapse does not overwrite the user's explicit choice: if the user closed
the inspector at 1400pt, widening the window does not re-open it.

### 1.2 Toolbar

Left to right, standard `.toolbar` placement:

- Sidebar toggle (`sidebar.leading`), `.navigation` placement
- `‹` / `›` paging buttons, `.navigation`
- **Today** button, `.navigation`
- Title: the visible range, `toolbarTitle` type, `.principal`
  — Month: `September 2026`; Week: `7 – 13 Sep 2026`; Day: `Wed 9 Sep 2026`
- Spacer
- View switcher: segmented control, Month / Week / Day, `.primaryAction`
- `+` new event, `.primaryAction`
- Inspector toggle, `.primaryAction`

Nothing else. No search field, no filter menu in Phase 1.

---

## 2. Sidebar

`List` with `.sidebar` style, `color.surface.sidebar`.

1. **Needs attention** — a single row with the count badge (`components.md` §10.2).
   Hidden entirely when the count is zero. Phase 1 renders the row and always
   shows zero, so it is hidden; Phase 2 supplies the data.
2. **Sources** — section header `sidebarSection`, then one row per source:
   source swatch (`components.md` §10.1) + name (`sidebarItem`) + a trailing
   visibility checkbox. Toggling hides that source's events from all three views.
3. **Filters** — section header, then: All-day only, Timed only, Hide done,
   Hide skipped. Simple toggles. Filters compose with source visibility by AND.

Row height 24, section spacing `spacing.lg`.

---

## 3. Week view

Seven day columns. First weekday from `Calendar.current.firstWeekday` (Monday in
`de_AT`).

- Column width: `(canvasWidth − size.timeGutterWidth) / 7`, floored at
  `size.dayColumnMin`. Below that floor the grid scrolls **horizontally**; it
  never drops columns and never auto-switches to another view.
- Weekend columns take `color.surface.canvasAlt`.
- Today's column takes `color.surface.canvasAlt` in the header only, plus the
  today pill (`components.md` §10.3).
- Vertical dividers between columns: `color.separator.dayDivider`, 1pt, drawn on
  the leading edge of each column.

### 3.1 Hour grid

- Row height `size.hourHeightWeek` (44). Full day = 1056pt, vertically scrollable.
- Hour lines: `color.separator.hour`, 1pt, at every hour, spanning gutter + all
  columns.
- Half-hour lines: `color.separator.halfHour`, 1pt, columns only, **not** across
  the gutter.
- Time gutter `size.timeGutterWidth` wide. Labels `hourLabel`,
  `color.text.secondary`, trailing-aligned with `spacing.md` trailing padding,
  top edge at the hour line + 2pt (so the 00:00 label is never clipped).
- Default scroll position on open: `min(07:00, firstEventStart − 1h)` at the top
  of the viewport. `T` and the Today button scroll the current time to 1/3 from
  the top of the viewport.
- **Amended 2026-10-06 (Phase 2 re-review; G-042) — what `firstEventStart` is.**
  It is a **time of day**: the earliest start time-of-day of any timed event that
  **starts** on one of the visible days, compared as minutes after that event's own
  midnight. In Day view that is the day's first event; in Week view it is the
  earliest across all seven columns, not the first event of the first day that
  has one. The scroll offset is one value shared by every column, so the question
  it answers is "how early does anything in view begin"; reading only the first
  occupied day would open a week whose Tuesday starts at 08:00 at 07:00 and hide a
  Thursday 05:30 above the fold. All-day items are ignored (they are not on the
  grid), and so is the after-midnight part of an event that started on the
  previous day — it starts at 00:00 only by clipping, and counting it would pin
  every week containing one late night to 00:00. With no timed event the rule's
  07:00 holds. (P2-F22 built "earliest instant"; with the 2026-10-06 fixtures
  both readings give 06:00, so no capture changes.)
- The initial position is **held** until the user scrolls or a conflict scroll
  request arrives (P2-F22's build, now spec): a window that lays its canvas out
  several times while settling must still open at the computed hour.

### 3.2 All-day row

Between the day header and the hour grid; pinned, does not scroll with the grid.

- Hidden entirely when the visible range has no all-day items. No empty row, no
  residual separator.
- Height = `rows × size.allDayRowHeight + (rows − 1) × size.allDayRowGap`, where
  `rows` is capped at `size.allDayMaxRows` (3). Beyond that the row scrolls
  internally and shows a `+N` chip at the trailing edge.
- Leading label column `size.allDayLabelWidth` wide, aligned with the time gutter,
  reading `all-day` in `allDayLabel` / `color.text.tertiary`.
- Background `color.surface.allDayRow`; bottom edge `color.separator.region`, 1pt.
- Multi-day items span across columns as one pill with square inner corners where
  they cross a day divider.

### 3.3 Overlap resolution

Deterministic, three steps. Run per day column.

**Steps 1 and 2 operate on layout footprints, not on raw event times.**
*Added 2026-09-11, GAPS.md G-012.* An event's **layout footprint** is the
interval of grid time its drawing actually occupies:

- `footprintTop` = `departAt` when the event has a travel band in
  `components.md` §4's **case 1** — true band height ≥ `size.travelBandHeight` at
  the current view's hour height — and `event.start` otherwise. A case-2 band is
  drawn inside its parent's own frame and extends nothing.
- `footprintBottom` = `max(event.end, footprintTop + minInterval)`, where
  `minInterval` is `size.blockMinRenderedHeight` converted to minutes at the
  current hour height. **The clamp only ever extends the bottom; it never moves
  the top.** This is the same clamp as before, applied to the footprint rather
  than to the raw interval — on an event with a case-1 band it is already
  satisfied and does nothing.
- All-day items have no footprint here; they are excluded from all three steps.

**Step 1 — cluster.** Group timed blocks into maximal sets connected transitively
by overlap. Two blocks overlap if
`a.footprintTop < b.footprintBottom && b.footprintTop < a.footprintBottom`.

**Step 2 — column packing.** Within a cluster, sort by `footprintTop` ascending,
then duration descending, then title ascending, then `id` ascending (stable and
reproducible). Place
each block in the lowest-index sub-column whose last block's `footprintBottom` is
at or before this block's `footprintTop`. The cluster's sub-column count is the
maximum index used + 1. Then expand: each block grows trailing-ward through
adjacent sub-columns until it reaches one occupied by a block it overlaps.

Step 2 uses the **same** footprints as step 1, deliberately. If step 1 pulled a
neighbour into the cluster and step 2 then packed on raw times, the neighbour
would land in the same sub-column and the band would still be drawn on top of it
— the extension would have changed the cluster and fixed nothing.

The `id` tie-break is why this sort is a **total order**: two distinct events may
legitimately share a start, a duration and a title, and without it the paint
order of that pair would be undefined. It is what lets `interactions.md` §6.1 say
"the frontmost block" and always mean exactly one block.

Slot width = `(columnWidth − 2 × spacing.xxs) / subColumnCount −
size.blockColumnGap`.

**Step 3 — cascade fallback.** If the slot width would fall below
`size.dayColumnCascadeThreshold` (72), abandon column packing for that cluster.

72 is derived, not chosen: `size.blockRailWidth` (3) + `size.blockPadding` (5) +
`size.blockGlyphSize` (11) + `size.blockGlyphGap` (4) + `size.blockPadding` (5)
= 28pt of fixed chrome, plus 44pt of title — about seven characters at
`blockTitleCompact`, enough to tell *Coffee* from *Code review*. Below 72 a
packed slot carries no more information than a cascade sliver does, so cascade
wins; at or above it packing wins, because in a packed layout **every** block
keeps a title and in a cascade only the topmost one does.

- Indent step, computed per column:
  `indent = min(round(columnWidth × size.blockCascadeIndentRatio), size.blockCascadeIndentMax)`
  — 22pt at any column of 116pt or wider, 15pt at the 78pt minimum. There is no
  lower clamp: `size.dayColumnMin` already guarantees at least 15 (GAPS.md G-006).
  22pt is the width of `size.blockRailWidth` + `size.blockPadding` +
  `size.blockGlyphSize` + 3, i.e. exactly enough to keep a rail and a glyph
  visible on a block that is partly covered.
- Sort as in step 2. Block *i* has a leading inset of
  `min(i, size.blockCascadeMaxSteps) × indent` and spans to the column's trailing
  edge.
- Z-order follows the step 2 sort order — later blocks draw on top. It is the
  paint order, and `interactions.md` §6.1 makes it the hit order too, so what is
  on top is what a click selects. Every covered block
  still shows its **glyph, and its leading rail where its variant has one** —
  which is exactly why type, flexibility and source live on the leading edge
  (`components.md` §1). Note that `.fixedTimed` has no rail by design, so a
  covered fixed block is identified by glyph and hue alone. The narrowest
  possible block is `columnWidth − 3 × indent`: 118pt at a 184pt column, 42pt at
  the absolute minimum.
- **A covered block shows no text.** A block whose *visible* width — its own
  width minus whatever the next block covers — is below
  `size.blockCascadeMinReadableWidth` (44) renders the `.glyphOnly` content set
  from `components.md` §3.3, whatever its height tier would otherwise
  allow. Without this rule a covered block renders its full content and gets
  clipped mid-string, producing slivers that read as `10:` — visible damage
  rather than a partially covered block. The layout engine passes visible width
  to `resolveBlockStyle` alongside rendered height.
- Beyond `size.blockCascadeMaxVisible` (5) blocks in one cascade, blocks 6+ are
  replaced by a `+N` chip pinned at the cluster's top trailing corner, 14pt tall,
  `countdownChip` type, which opens that day in Day view. The chip draws **above
  every block in the cluster**, not in the cluster's z-order — a `+N` a block is
  sitting on top of tells the user nothing.
- Cascaded blocks stay at `elevation.level0`. Overlap is communicated by the
  indent and by the canvas gap between blocks, not by shadow; adding elevation
  here would make cascade the only place in the app where a resting block casts
  a shadow.

**Which step actually fires, and why.** Worked from the 2026-09-09 screenshot,
where the window is 1880pt wide and Week columns are 184pt:

| Cluster | Slot width | Result |
|---|---|---|
| 2 concurrent, 184pt column | `(184 − 4) / 2 − 2` = 88 | **packs** — both blocks keep a title |
| 3 concurrent, 184pt column | `(184 − 4) / 3 − 2` = 58 | cascades |
| 2 concurrent, 114pt column | 53 | cascades |
| anything, 78pt column | ≤ 37 | cascades |

So Week packs the common case — two things overlapping — and cascades the
pile-up. Day, with a column several hundred points wide, packs almost everything.

This threshold was 96 in the first draft of this spec, which was wrong: at 96 a
two-block overlap cascaded even at a 184pt column, so column packing never fired
in Week at any window size a person would actually use (2-up would have needed a
200pt column, i.e. a ~2000pt window). The screenshot showed the cost directly —
an 11:00 pair where one block was a 22pt sliver, and an 18:00 trio where the
first block's title was entirely hidden. 96 answered "how wide is a comfortable
block"; the question the threshold actually decides is "how wide is a block that
still beats being hidden".

**Travel bands.** A band is laid out with its parent event, occupies the parent's
slot width, takes the parent's cascade indent, and paints at the parent's index
in the paint order (`components.md` §4). A case-1 band's interval is part of its
parent's footprint, per the definition above, so a block that would otherwise sit
under the band is clustered with it and packed beside it instead. All-day items
are excluded from all three steps.

**This makes clustering scale-dependent, and that is said out loud.** §4's case
split is decided on the band's height in *points*, so the same 22-minute band is
case 1 in Day (22pt at `size.hourHeightDay`) and case 2 in Week (16.1pt at
`size.hourHeightWeek`). The same two events therefore cluster in Day and do not
cluster in Week. A cluster is a property of **(the day's events, the view's hour
height)** — not of the events alone. This is not a new kind of dependency: the
density ladder (`components.md` §3.3) and the pack-versus-cascade decision in
step 3 are already scale-dependent for exactly the same reason. It does mean
layout is recomputed on a view change and **never cached across views**.

Worked on the case that produced G-012 — "Morning review" 08:00–09:00 and
"Datenmodellierung" 09:00–10:30 with a 22-minute band. In **Day** the band is
case 1, so Datenmodellierung's footprint is 08:38–10:30, the two footprints
overlap, they form one 2-block cluster, the slot width is
`(1060 − 4) / 2 − 2` = 526 — far above `size.dayColumnCascadeThreshold` (72) — so
they pack side by side and the band has nothing foreign to cover. In **Week** the
band is case 2, no extension applies, and the two stay in separate clusters,
which is correct: a case-2 band never leaves its parent's frame.

**Why extend the footprint rather than clip or demote the band.** The two
alternatives were to clip a case-1 band to the part of its interval no other
block covers, or to draw it under blocks it does not belong to. Both hide the one
thing the product exists to tell the user — when to leave — behind an unrelated
block, and the clipped version can lose the label entirely. A band is opaque, it
occupies grid time, and anything opaque that occupies grid time has to take part
in overlap resolution or the engine is not describing what is on the canvas.

---

## 4. Day view

One column. Same grid machinery as Week, with:

- Row height `size.hourHeightDay` (60). Full day = 1440pt.
- The single column takes the full canvas width minus the gutter, so cascade
  fallback effectively never triggers; column packing handles the density.
- Both hour and half-hour lines span the full width; quarter-hour lines are
  **not** drawn (they would compete with block borders at 15pt spacing).
- Background window treatments and travel bands render here at full fidelity —
  this is the view they are designed for.
- Day header shows weekday + date + a secondary line with the day's block count
  and total scheduled hours, `blockMeta` / `color.text.secondary`. On an empty
  day the secondary line reads `Nothing scheduled` — no illustration, no
  encouragement, no call to action.

---

## 5. Month view

- Weekday header row `size.monthWeekdayHeaderHeight` (24), `dayHeaderWeekday`
  type, `color.text.secondary`, `color.surface.canvasAlt`.
- **Always six rows**, so the grid never reflows when paging between months.
- Row height = `(available − header) / 6`, floored at
  `size.monthCellMinHeightFloor` (88); below the floor the grid scrolls
  vertically. `size.monthCellMinHeight` (92) is the preferred height that the
  minimum window size is chosen to satisfy — at a 640pt window, rows are 94pt.
- Cell date numeral: `monthDate`, top-leading, inset `spacing.xs`. Today takes the
  today pill. Days outside the displayed month take
  `color.surface.canvasAlt` and `color.text.tertiary` for the numeral.
- Cell content: chips per `components.md` §9, starting `spacing.xs` below the
  numeral, `spacing.xxs` between rows.
- Cell dividers `color.separator.hour`, 1pt. Outer edge of the grid
  `color.separator.region`.
- No now line, no background windows, no travel bands.

---

## 6. Inspector

Shown for the current selection. Sections, top to bottom:

1. Title (`inspectorTitle`) with the block's glyph and source swatch inline.
2. Time: start, end, duration. `inspectorLabel` / `inspectorValue` pairs.
3. Location, when present, with the travel line beneath it
   (`Leave 08:12 · 22 min walking`) — read-only in Phase 1.
4. Source and origin.
5. Status, with Done / Skip actions.
6. Notes, editable.

Empty selection state: the inspector shows the day's summary — date, block count,
scheduled hours, and the first item — rather than an empty panel. Never a
"nothing selected" placeholder graphic.

Section spacing `spacing.xl`, horizontal padding `spacing.xl`, label column
width 84.

**Amended 2026-10-05 (Phase 2 screenshot review, spec side of DEVIATIONS B20).**

- **The horizontal padding is measured from the inspector's own visible edges**,
  leading and trailing, after any divider. Every inspector element — labels,
  values, the title row, the conflict panel (§10), buttons — starts at least
  `spacing.xl` (16) inside the leading edge. Nothing is drawn at, under or past
  that edge. The 2026-10-05 captures show the labels' first letters cut off
  (`tarts`, `nds`, `ource`) and the conflict panel's blocks flush against the
  edge, plus a full-height accent line on the inspector's leading edge in every
  main-window frame since 2026-09-25. Both are the same fault: the content is
  laid out wider than the region and clipped on the leading side. ~~The focus
  ring the inspector draws when it is the focused region (`interactions.md` §1)
  is the **complete** standard system ring around the region, never one edge of
  it.~~ **Amended 2026-10-06 (closes G-039):** "complete or absent" is decided —
  **absent**. The inspector, like every region, draws no region focus ring;
  focus is shown on the focused control (`interactions.md` §1, "Where focus is
  drawn"). The build's `.focusEffectDisabled()` on the grid and the inspector
  (DEVIATIONS B21) is the spec.
- **Row 4's "Source" is the source's name**, as the sidebar lists it — `Daily
  routine`, `University timetable` — with its swatch (`components.md` §3.4:
  "Inspector: Always, as swatch + name"). Never the palette slot: the 2026-10-05
  capture reads `Source  Green`, which is a colour name standing in for a source
  name, the exact confusion §1 exists to prevent.

---

## 7. What collapses first, restated

In order, as the window narrows: inspector → sidebar → week columns start
scrolling horizontally. Content is never dropped, summarised away, or
auto-switched to a different view. The user always ends up looking at the same
information, just with more scrolling.

---

# Phase 2 — additions

Additions only. Nothing in §1–§7 changes.

---

## 8. The Routines window

A separate window, not a sheet and not a Settings pane. Settings owns sources and
notification rules (`BRIEF-DESIGN` item 10); this window owns the shape of the
week, which is a working surface, not a preference.

Opened with `⌘⌥R` or **Window ▸ Routines**. Standard window chrome. It is a
single window for both routine blocks and time windows, because the two only make
sense against each other (`components.md` §13.3).

```
+---------------------------------------------------------------+
| toolbar: template picker · [Blocks | Windows] · +   size.editorModeBarHeight
+------------------------------------------+--------------------+
|  MON  TUE  WED  THU  FRI  SAT  SUN       |                    |
|  (weekday header, no dates)              |   editor inspector |
+------------------------------------------+                    |
|                                          |   size.editor      |
|  hour grid — size.hourHeightWeek         |   InspectorWidth   |
|  same geometry as layouts.md §3.1        |                    |
|                                          |                    |
+------------------------------------------+--------------------+
```

- **Minimum window** `size.routineEditorMinWidth` × `size.routineEditorMinHeight`
  (780 × 620). Derived: `size.timeGutterWidth` (52) + 7 ×
  `size.routineEditorColumnMin` (84) + `size.editorInspectorWidth` (260) = 900 at
  comfort, floored at 780 where the inspector collapses first.
- **Columns** are weekdays, ordered from `Calendar.current.firstWeekday`. No
  weekend tint here — a routine's Saturday is not a lesser day.
- **Hour grid** exactly as §3.1: same row height, same hour and half-hour lines,
  same gutter width and label placement.
- **No** day header dates, all-day row, now line, travel bands or `+N` chip
  behaviour beyond what §3.3 already specifies.
- **Collapse order**: the editor inspector collapses below 1040pt and returns as
  an overlay, exactly as §1.1 does for the main window. The canvas never
  collapses.
- **Amended 2026-10-05 — the canvas never scrolls horizontally.** At every
  permitted width the columns are `(canvas width − size.timeGutterWidth) / 7` and
  that is ≥ 104pt: at the 780pt minimum the inspector is an overlay, so the
  canvas is 780 wide (104 per column); at 1040 with the inspector docked it is
  780 again. Both are above `size.routineEditorColumnMin` (84), so the
  horizontal-scroll path is unreachable, and with it the question of the weekday
  header (and its §13.5.2 underlines) scrolling out of step with the grid. The
  header and the grid share one column-width computation and one horizontal
  origin. If a future change makes the canvas narrower than 640pt, the header
  must scroll with the grid in the same `ScrollView`, never in a sibling — but
  no Phase 2 change does. No Phase 2 work is required by this paragraph.
  *(Note 2026-10-06: INDEX.md Batch 10 describes the 780pt frame as "the canvas
  scrolls horizontally at this width". It does not — the frame measures 104pt
  columns, 780pt of canvas, with the editor inspector's overlay covering Fri–Sun.
  The overlay is the §1.1 behaviour; the description is wrong, not the build.)*

**Amended 2026-10-06 (Phase 2 re-review) — three rules the 2026-10-06 frames
showed the window needed.**

- **Default scroll position (G-047).** §3.1's rule, over the template instead of
  events: `min(07:00, earliestBlockStart − 1h)` at the top of the viewport, where
  `earliestBlockStart` is the earliest `startMinutes` of any block in the selected
  template (a template block's time of day is the same on every active weekday;
  inactive weekdays do not change it). In Windows mode the same value is used, so
  switching modes never jumps the canvas. With no blocks, 07:00. Re-applied when
  the template picker changes template; **not** re-applied on mode change or
  after an edit. Every 2026-10-06 Routines frame except item 1 opens at 00:00 —
  seven hours of `Sleep` before the first block, which is the view the main
  window's B24 fix removed. With the `Daily routine` fixture (Gym 07:00) it opens
  at 06:00, which still shows `Sleep`'s 22:00 edge, `Lunch`, `Low energy` and
  `Deep work` in a 900pt window. The hold rule of §3.1 applies.
- **Window treatments reach the gutter here too (G-041, DEVIATIONS B22).**
  "Hour grid exactly as §3.1" includes `components.md` §7 rule 2: protected fill
  and edges and the low-energy hatch span the time gutter at the window's height
  in the Routines canvas, as they do in the main window. Peak focus's dashed
  outline (Windows mode only) does **not** enter the gutter: it is an outline of
  the editable span, and §7's gutter strip exists to keep a *background*
  treatment visible under a full column, which an outline with no fill is not.
  Labels still never enter the gutter.
- **No window-level or region-level focus ring (G-039, DEVIATIONS B35).**
  `interactions.md` §1. The ~1px accent line on all four outer edges of every
  2026-10-06 Routines frame is a system focus ring around the window's root (or
  canvas) hosting view and must not be drawn.

### 8.1 Editor inspector

For a selected routine block: title, start, duration, and the flexibility control
(`components.md` §13.2). For a selected time window: kind (protected /
low-energy / peak-focus), weekdays, start, end, label.

With nothing selected it shows the template: name, active weekdays, block count,
total hours, and the detached-instance count with its Re-sync button
(`components.md` §13.4). Same rule as §6 — the empty state is a summary, never a
placeholder graphic.

**Amended 2026-10-01.**

- **Active weekdays is a control, not a field.** It is the same Mon-first toggle
  row the time-window inspector already uses for `TimeWindow.weekdays`: seven
  `dayHeaderWeekday` toggles, `←`/`→` to move, `space` to flip. This is the
  keyboard path for `components.md` §13.5.4, so the column note's `Add Sat`
  button is not the only way in. Same undo step names.
- **Amended 2026-10-05 — the toggle row's geometry and its focused toggle
  (closes G-028).** The 2026-10-05 captures clip `M` and `W` to `N` and `V`: the
  row was squeezed into the space beside the 84pt label column. Ruled:
  - The row sits **under** its `Weekdays` label, full content width (228pt at
    `size.editorInspectorWidth` less two `spacing.xl` insets) — the same
    placement the flexibility control already takes, for the same reason.
  - Seven square toggles, `size.weekdayToggleSize` (24) each, `spacing.xs`
    apart: 7 × 24 + 6 × 4 = 192pt. Radius `radius.chip`.
  - Letter: `veryShortStandaloneWeekdaySymbols` (`M T W T F S S`) in
    `dayHeaderWeekday`, centred. Repeated letters are disambiguated by position,
    as on every calendar header; the accessibility label is the full weekday
    name (`Monday`) and the value `in routine` / `not in routine` (time windows:
    `on` / `off`).
  - **On:** fill `color.interactive.accent`, letter `color.text.onSolid`
    (4.56:1 / 6.93:1). **Off:** fill `color.surface.canvasSunken`, letter
    `color.text.secondary` (5.69:1 / 8.01:1). The fill's value step separates on
    from off without hue; the accessibility value carries it for VoiceOver.
  - **The focused toggle** (`←`/`→` have moved to it, the row has keyboard
    focus): a `size.borderSelected` stroke in `color.interactive.focusRing`,
    **inset** 1pt inside the toggle's bounds, at `radius.chip` — the build's
    placeholder, adopted. Inset rather than outset because the toggles are
    `spacing.xs` apart and an outside ring would touch the neighbour. ~~The
    system focus ring stays on the row as a whole, per `interactions.md` §1:
    the ring says *this region*, the inset stroke says *this item*.~~
    **Amended 2026-10-06:** no ring on the row — `interactions.md` §1 bars
    region rings; the inset stroke is the row's whole focus indicator. Shown
    only while the row has keyboard focus; never on pointer hover.
  - Each toggle is **not** its own `⇥` stop. `interactions.md` §1's model holds:
    the row is one focus target with an internal focused item.
  - The time-window inspector's row is the same component with the same
    geometry; its last active toggle is disabled per `components.md` §13.5.4.
- **The detached count reads `3 instances edited` / `1 instance edited`** — no
  "this week". `components.md` §13.7.3 scopes it from today forward through the
  materialisation horizon, which is not a week, and the popover lists the real
  dates.
- **The editor inspector has a conflict mode.** A template conflict
  (`components.md` §14.6) replaces the inspector's contents with §10's panel —
  collision header, option rows, `1 of N` footer — at
  `size.editorInspectorWidth`. Same collapse behaviour as §8's: below 1040pt it
  returns as an overlay, and it never forces the window wider.

---

## 9. Menu bar popover

Anchored to the status item. Width `size.popoverWidth` (300), height intrinsic —
it never scrolls, because a scrolling "what's next" is a second calendar.

| Region | Height |
|---|---|
| `NEXT` section label | `spacing.xl` leading inset, label row |
| Next item block | ≥ `size.popoverNextBlockMinHeight` |
| Action row | `size.popoverActionRowHeight` |
| Divider | `size.hairline`, `color.separator.region` |
| `REST OF TODAY` label | label row, omitted when the list is empty |
| Rest rows | `size.popoverRestRowHeight` × ≤ `size.popoverMaxRestRows`, then `+N more` |

Padding `spacing.xl` on all sides. Background `color.surface.popover` with its
material, falling back under Reduce Transparency per `components.md` §11.

The popover closes on `⎋`, on clicking outside, and on `Open` (which activates
the main window). **Amended 2026-10-06:** no focus ring around the popover's root
(`interactions.md` §1); NEXT and the rest rows show focus with
`hoverOverlay` (`interactions.md` §12). It does **not** close on `Done` or `Snooze` — those replace
their row in place (`components.md` §16) so you can see what happened.

---

## 10. The conflict panel

Conflict resolution lives in the **inspector**, not a sheet
(`DECISIONS.md` 2026-09-10). Region geometry is unchanged from §1 — same width,
same collapse behaviour, same overlay treatment below 1200pt.

Top to bottom:

1. Collision header (`components.md` §14.2)
2. Option rows (`components.md` §14.3), `size.conflictOptionGap` apart
3. Footer: `1 of 3` in `blockMeta` / `color.text.secondary`, with `‹` `›` to move
   between unresolved conflicts

When the inspector is collapsed and a conflict is activated from the sidebar, the
inspector opens as an overlay. It does not force the window wider.

**Amended 2026-10-05 — the footer, completed (spec side of DEVIATIONS A32).
Required for Phase 2.** Without it there is no way to look at a later conflict
without resolving the current one, and none to reach a template conflict while
day conflicts remain — the 2026-10-05 captures needed a launch-argument test hook
to get past that. The brief's "Needs your attention" is a list; the footer is
what makes this panel one.

- **Position:** the last element of the panel, `spacing.lg` below the last option
  row, inside the inspector's content inset (§6).
- **Content:** `‹` · `3 of 14` · `›`. The text is `blockMeta` /
  `color.text.secondary`, monospaced digits, centred between the two buttons.
  `‹` and `›` are native borderless buttons drawing `chevron.left` /
  `chevron.right` at `size.blockGlyphSize` in `color.text.secondary`, hit
  target at least 24 × 24. (These are chrome symbols for paging, not members of
  either glyph vocabulary in `components.md` §10.1; `chevron.up` in §7 is the
  precedent.)
- **N is the needs-attention count** — day conflicts and template conflicts
  together — and the order is `interactions.md` §10.1's `⌘⇧A` order (day
  conflicts first, then template conflicts, each by the start of what they
  affect). One list, one count, one order; the sidebar badge and the footer's N
  are always the same number.
- **Ends do not wrap.** `‹` is disabled on 1, `›` on N. Wrapping would let `›`
  silently mean "back to the start", and a list of things needing attention
  should end.
- **Stepping onto a template conflict from the main window** routes exactly as
  activating one does (`components.md` §14.6): the Routines window opens on it,
  in conflict mode, and its own footer reads the same `k of N`. Stepping back
  with `‹` from the first template conflict in the Routines window returns to the
  main window's last day conflict.
- **Stepping abandons the pending preview** (`interactions.md` §10.2) and focuses
  the new conflict's recommended option, which previews (`interactions.md`
  §10.1).
- **After `↩` applies an option**, the conflict leaves the list and the panel
  advances to the next conflict **of the same window's kind** — a day conflict in
  the main window, a template conflict in the Routines window — with the footer
  reading its new `k of N−1`. `↩` never opens the other window by itself:
  crossing windows is always an explicit `‹`/`›` or a needs-attention
  activation, because a window appearing as a side effect of applying an option
  reads as something going wrong. When no conflict of this window's kind
  remains, the panel closes (`components.md` §14.5) even if N is still above
  zero; the sidebar count shows what remains. This adopts the build's P2-T46
  judgement call ("applying a day conflict never advances into the template
  queue").
- **N = 1 still shows the footer** (`1 of 1`, both buttons disabled):
  `components.md` §14.3.3 leans on it to say where the user is when a single-
  option conflict has no chip.
- **Keys:** `‹` `›` / `⌥←` `⌥→` with the panel focused, as `interactions.md` §2
  already lists. Accessibility: the buttons are labelled `Previous conflict` /
  `Next conflict`; the text is read as `Conflict 3 of 14`.
- The Routines window's editor-inspector panel (§8.1) carries the identical
  footer at `size.editorInspectorWidth`.

**The panel is not modal.** The grid stays live underneath: you can scroll it,
change view, and select other blocks. Doing any of those abandons the pending
preview per `interactions.md` §10.2 — the panel never traps you, and it never
holds a decision you did not make.
