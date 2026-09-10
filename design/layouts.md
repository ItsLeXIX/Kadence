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

**Step 1 — cluster.** Group timed blocks into maximal sets connected transitively
by overlap. Two blocks overlap if `a.start < b.end && b.start < a.end` after both
have been clamped to `size.blockMinRenderedHeight`.

**Step 2 — column packing.** Within a cluster, sort by start ascending, then
duration descending, then title ascending (stable and reproducible). Place each
block in the lowest-index sub-column whose last block ends at or before this
block's start. The cluster's sub-column count is the maximum index used + 1.
Then expand: each block grows trailing-ward through adjacent sub-columns until it
reaches one occupied by a block it overlaps.

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
- Z-order follows start order — later blocks draw on top. Every covered block
  still shows its **glyph, and its leading rail where its variant has one** —
  which is exactly why type, flexibility and source live on the leading edge
  (`components.md` §1). Note that `.fixedTimed` has no rail by design, so a
  covered fixed block is identified by glyph and hue alone. The narrowest
  possible block is `columnWidth − 3 × indent`: 118pt at a 184pt column, 42pt at
  the absolute minimum.
- **A covered block shows no text.** A block whose *visible* width — its own
  width minus whatever the next block covers — is below
  `size.blockCascadeMinReadableWidth` (44) renders the 11–15 content set from
  `components.md` §3.3 (glyph only), whatever its height tier would otherwise
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

Travel bands are laid out with their parent event and occupy the parent's slot
width. All-day items are excluded from all three steps.

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

### 8.1 Editor inspector

For a selected routine block: title, start, duration, and the flexibility control
(`components.md` §13.2). For a selected time window: kind (protected /
low-energy / peak-focus), weekdays, start, end, label.

With nothing selected it shows the template: name, active weekdays, block count,
total hours, and the detached-instance count with its Re-sync button
(`components.md` §13.4). Same rule as §6 — the empty state is a summary, never a
placeholder graphic.

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
the main window). It does **not** close on `Done` or `Snooze` — those replace
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

**The panel is not modal.** The grid stays live underneath: you can scroll it,
change view, and select other blocks. Doing any of those abandons the pending
preview per `interactions.md` §10.2 — the panel never traps you, and it never
holds a decision you did not make.
