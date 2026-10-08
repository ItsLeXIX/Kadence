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

### 2.1 Source rows with a connection (added 2026-10-08, Phase 3)

Sources now come from `Source` records (`components.md` §21), not a static
list. Row, left to right: swatch (`components.md` §10.1) · name (`sidebarItem`,
truncates tail) · **status slot**, `size.statusSlotWidth` (16), `spacing.xs` before the checkbox
(`components.md` §19.2; reserved on every row so checkboxes align) · visibility
checkbox. Row height stays 24.

- **Context menu on a connected source's row:** `Sync Now` · `Show Sync
  Status` · separator · `Edit Source…` · separator · `Remove Source…`. Local
  sources keep the menu they had (none). `Edit Source…` opens Settings ▸
  Sources with the connect sheet in edit mode (§12.3).
- **`↩` on a focused connected row** opens its source popover (`components.md` §19.3); `Space`
  still toggles the checkbox.
- **First run — no connected source.** The last row of the Sources section is a
  borderless link-style button `Connect Timetable…` (`sidebarItem`,
  `color.interactive.accent`, leading inset aligned with the source names, no
  swatch, no icon). It opens Settings ▸ Sources with the connect sheet open
  (§12). It disappears once any connected source exists. This is BRIEF-DESIGN
  item 11's "first-run with nothing connected" state for this slice: one quiet
  line, no illustration, no empty-state panel.

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
- **Amended 2026-10-07 (Phase 2 closeout; G-052) — the position is a whole
  hour.** The rule is `min(07:00, floorToHour(firstEventStart − 1h))`, clamped
  at 00:00: the result of `firstEventStart − 1h` is rounded **down** to the hour.
  A Day view whose first event is 07:15 opens at **06:00**, not 06:15. Reasons:
  the top of the viewport is then an hour line with its label (§3.1's labels sit
  at the line + 2pt), so the first thing read is a time, not 45 unlabelled
  minutes; and rounding down only ever adds lead, so "one hour before the first
  event" stays a minimum. Examples: 08:00 → 07:00; 07:59 → 06:00; 05:30 → 04:00;
  00:30 → 00:00; no timed event → 07:00. Same rule in Week view and in the
  Routines window (§8, over `earliestBlockStart`); with today's fixtures every
  view still opens at 06:00.

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

### 6.1 An imported event selected (added 2026-10-08, Phase 3; amended the same day for the CIS profile)

Same sections and geometry as §6; what changes is what can be edited and a few
rows. Top to bottom:

1. **Title row** — the kind glyph (`building.columns`, or `graduationcap.fill` for
   an exam, `components.md` §2.1) and swatch inline, as §6. The title is **text,
   not a `TextField`** (`inspectorTitle`, `lineLimit` 3, selectable). For a CIS
   event the title is the course code (`SWQM-ILV`, `components.md` §20.7.1).
2. **Read-only line**, directly under the title, `spacing.xs` above:
   `Read-only — from University timetable` (the source's display name),
   `inspectorLabel` / `color.text.secondary`. Always shown for an imported
   event, not only after a refused gesture: a rule the user discovers by being
   refused is a rule that refuses them first. For a cancelled event it reads
   `Cancelled by University timetable` instead (`components.md` §20.6).
   **Emphasised state** (`interactions.md` §13.4): `color.text.primary` for
   `motion.outlineHold` (0.6s), then back, cross-fading over `motion.selection`;
   under Reduce Motion it switches without the fade and holds the same 0.6s.
3. **Time** — `Starts`, `Ends`, `Duration` as §6, values as text, no steppers or
   pickers, in the Mac's current time zone. All-day: `All day` and the date
   range.
4. **Lecturer / Lecturers** — when `lecturers` is non-empty (`components.md`
   §20.7, §20.7.1). Label `Lecturer` for one name, `Lecturers` for more. One name
   per line (`inspectorValue`, each line `lineLimit` 2, selectable). **Long
   lists collapse**: with more than `size.inspectorLecturersMaxRows` (4) names,
   the row shows the first **three** and a fourth line `and {n} more` (`n` =
   the rest; 22 names → `and 19 more`), a borderless link-style button in
   `inspectorValue` / **`color.interactive.link`**. Activating it expands the row
   in place to every name, the button moving to the end as `Show fewer`. The
   expansion lasts while the event stays selected; a new selection starts
   collapsed. Up to four names never collapse — a fourth line saying `and 1 more`
   would cost the same space as the name. VoiceOver reads the row as one
   element: label `Lecturers`, value `22 lecturers: L10, L11, …` (every name,
   collapsed or not), and the button as `Show all 22 lecturers` / `Show fewer
   lecturers`.
5. **Group** — when `group` is set (CIS): `BIF-5C`.
6. **Room** — when `location` is set. Label **`Room`** for CIS events, `Location`
   for others (§20.7). An online event (`isOnline`) reads **`Online ·
   WEBINAR02`**: the word first, because it is the fact; the code after it,
   because it is what CIS and the lecturer call it. No travel line in this slice
   (`GAPS.md` G-063).
7. **Source** — swatch + `University timetable`, as §6 (amended 2026-10-05), with
   a second line in `blockMeta` / `color.text.secondary`: `Synced 14:02`
   (`components.md` §19.5), or the state title when not `upToDate` (`Access
   refused`). Clicking that line opens the source popover (`components.md`
   §19.3). **Origin** — `Imported`.
8. **Status** — Done / Skip, enabled (they are local, `components.md` §18.1).
   Disabled, with the read-only line saying why, on a cancelled event.
9. **Description** — replaces **Notes** for imported events: label
   `Description`, value `importedDescription` as selectable text
   (`inspectorValue`, `lineLimit` 0, line breaks kept). Omitted when empty —
   always, for CIS events, whose description is split into rows 4–6. No
   editable Notes field in this slice (G-058).
10. **Link** — when `link` is set (generic feeds; CIS sends none): the URL's host
    as a link (`inspectorValue`, **`color.interactive.link`** — amended: was
    `color.interactive.accent`, which measures 4.26:1 on `surface.inspector` in
    light and fails, G-066), opening in the default browser.

Labels use §6's 84pt label column. `Lecturer`, `Lecturers`, `Group`, `Room`,
`Description`, `Link` are the labels' exact text. No row is drawn empty. There is
no `Course` row: the title is the course.

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
  events: `min(07:00, earliestBlockStart − 1h)` — rounded down to the hour per
  §3.1's 2026-10-07 amendment (G-052) — at the top of the viewport, where
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
    **Amended 2026-10-07 (Phase 2 closeout; G-049) — the stroke's colour
    follows the fill.** `focusRing` and `accent` are the same value, so on an
    **on** toggle the stroke was drawn and invisible (1.00:1) — and `⇥` enters
    the row on `M`, which is on in `Daily routine`, so the row showed no focus on
    entry. Ruled, same geometry for both states (`size.borderSelected` 2pt,
    inset 1pt, `radius.chip`), colour by the toggle's fill:
    - **On** (fill `interactive.accent`): stroke
      `color.interactive.focusRingOnAccent` (light `#FFFFFF`, dark `#0C0C0D` —
      the letter's colour, added in `tokens.json` 1.3.0). Measured against the
      fill it sits on: **4.56:1 light / 6.93:1 dark**.
    - **Off** (fill `surface.canvasSunken`): stroke `color.interactive.focusRing`,
      as before. Measured: **4.05:1 light / 6.40:1 dark**.
    - Both clear WCAG 1.4.11's 3:1 for a non-text indicator, both declared as
      `contrastPairs` (1.3.0). The rule is by fill, not by meaning: any toggle
      drawn on `accent` takes `focusRingOnAccent`, anything else `focusRing`;
      a disabled toggle (§13.5.4's last window weekday) keeps its fill's rule.
    - The stroke must not use `focusRingSystemName`
      (`keyboardFocusIndicatorColor`) on an on toggle: it follows the accent and
      recreates the defect. The same component in the time-window inspector
      takes the same rule.
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


---

# Phase 3 — additions

Written 2026-10-08. Additions only; §2.1 and §6.1 above are the in-place
amendments.

---

## 11. Settings ▸ Sources

*(Amended 2026-10-08, CalDAV amendment: `Link` and `Sign-in` replaced by
`Account` and `Calendar`. The default interval is 30 minutes.)*

The app's `Settings` scene (`⌘,`) is a standard macOS settings window:

- toolbar-style tab bar, title = the selected tab
- not resizable
- closes with `⌘W`

Phase 3 has **one tab, `Sources`** (symbol `link`). A tab bar with one tab is on
purpose: later phases add panes (BRIEF-DESIGN item 10) without moving this one.
Content size is `size.settingsWindowWidth` × `size.settingsWindowHeight`
(640 × 440).

```
+------------------------------------------------------------------+
|                        [ link ] Sources                          |
+--------------------+---------------------------------------------+
| ■ University time… | Up to date                                  |
|                    | Synced 14:02 · 142 events                   |
|                    | Last change today 14:02: 1 removed          |
|                    |                              [ Sync Now ]   |
|                    | ------------------------------------------- |
|                    |      Name  [University timetable       ]    |
|                    |   Account  user01 @ cis.technikum-wien.at   |
|                    |                         [ Edit Account… ]   |
|                    |  Calendar  LVPlan                           |
|                    |      Sync  [ Every 30 minutes      ⌄ ]      |
|                    |                                             |
| [+][−]             | [ Remove Source… ]                          |
+--------------------+---------------------------------------------+
```

- **Source list** (leading, `size.settingsSourceListWidth` 200, full height
  minus the button bar):
  - It lists connected sources only. Local sources have nothing to configure.
  - Row: swatch + name (`sidebarItem`) + status slot (`components.md` §19.2,
    same glyph rules).
  - Below it, the standard `+` / `−` square buttons (`.borderless`, small,
    bottom-leading, as in System Settings' lists). `+` opens the connect sheet
    (§12). `−` is `Remove Source…` for the selection.
  - One source is selected whenever any exist.
- **Detail** (the rest), padding `spacing.xl`:
  1. **Status block** — `components.md` §19.3's content inline: title, body,
     status line, last-change line, and the primary action as a `.bordered`
     button, trailing. `Show Details` expands the full problem list here,
     scrolling inside the detail if long. There is no `Settings…` button (you
     are there).
  2. Divider, `size.hairline`, `color.separator.region`, `spacing.lg` above and
     below.
  3. **Form** — standard `Form` / `LabeledContent`, labels trailing-aligned:
     - `Name` — a `TextField`. It commits on `↩` or blur, and an empty field
       reverts to the last name. Renaming changes the sidebar, hover help,
       inspector and Keychain label, and nothing else.
     - `Account` — `{user} @ {host}` (`user01 @ cis.technikum-wien.at`) as text,
       `inspectorValue`, **selectable** (nothing in it is secret,
       `components.md` §21.4). There is no password row: the password is never
       drawn, not even as bullets, outside the sheet's `SecureField`. Below it,
       trailing, `Edit Account…` opens the connect sheet in edit mode with
       focus in `Password` (§12.3).
     - `Calendar` (one) / `Calendars` (several) — the selected calendars'
       display names, comma-separated, as text (`inspectorValue`, `lineLimit`
       0). Choosing others is in edit mode's step 2 (§12.3).
     - `Sync` — a pop-up button: `Every 15 minutes` · `Every 30 minutes` ·
       `Every hour` · `Every 3 hours` · `Every 6 hours` · `Every 12 hours` ·
       `Every day`. **Default `Every 30 minutes`** (Parsa, 2026-10-08;
       `interactions.md` §13.3). There is no "manually" option: nothing
       important may depend on the user remembering to sync.
  4. **`Remove Source…`**, a `.bordered` button, bottom-leading of the detail.
- **Empty state** (no connected source):
  - The list is empty.
  - The detail shows one line, `No timetable connected.` (`inspectorValue`,
    `color.text.secondary`), and a `Connect Timetable…` button beneath it,
    `spacing.lg` apart, both vertically centred.
  - No illustration.
- **Ways to reach Settings:**
  - `⌘,`
  - the sidebar's `Connect Timetable…` row
  - the popover's `Settings…`
  - the sidebar context menu's `Edit Source…`, which opens the sheet over
    Settings

## 12. The connect sheet

*(Rewritten 2026-10-08, CalDAV amendment. The sheet signs in to an account and
lets the user confirm its calendars. There is no link field, no masked link
and no file step. Tokens `size.connectCalendarRowHeight` and
`size.connectCalendarListMaxHeight` are added in `tokens.json` 1.6.0.)*

The sheet sits on the Settings window. Width `size.connectSheetWidth` (440),
height intrinsic, padding `spacing.xxxl`. It has two steps in one sheet, and
the content swaps with `motion.viewChange` (Reduce Motion: §7.2's fade).

**Nothing is written until step 2's `Import` / `Save`**: no Keychain item, no
`Source`, no event (`DECISIONS.md` 2026-10-08). Cancelling at any point leaves
nothing behind. This is the same rule as event drafts and conflict previews
(`DECISIONS.md` 2026-09-10). The discovery result, the fetched events and the
typed password are held in the sheet's memory only, and are discarded with it.

### 12.1 Step 1 — Connect

```
+------------------------------------------------+
| Connect a timetable                            |  inspectorTitle
| Sign in with your FH account — the server,     |  inspectorValue, text.secondary
| username and password Apple Calendar uses.     |
| Kadence only reads the timetable; it never     |
| changes anything in CIS.                       |
|                                                |
|      Name  [University timetable            ]  |
|    Server  [cis.technikum-wien.at           ]  |
|  Username  [                                ]  |
|  Password  [                                ]  |
|                                                |
| Your password is kept in the macOS Keychain    |  blockMeta, text.secondary
| and sent only to cis.technikum-wien.at, over   |
| HTTPS.                                         |
|                                                |
|                       [ Cancel ]  [ Connect ]  |
+------------------------------------------------+
```

- **Fields** — a standard `Form`, labels trailing-aligned, fields full width:
  - `Name` — default `University timetable`.
  - `Server` — **prefilled `cis.technikum-wien.at`**, editable.
    `textContentType(.URL)`, autocorrection and spell-checking off.
  - `Username` — empty, `textContentType(.username)`, autocorrection off. Focus
    starts here.
  - `Password` — a `SecureField`, `textContentType(.password)`. It is never
    prefilled, never echoed, and never in an accessibility value.
- **Footnote** — the sentence above, with `{host}` taken live from `Server`.
  When `Server` doesn't parse, it reads `Your password is kept in the macOS
  Keychain and sent only to the server you enter, over HTTPS.`
- **Validation, inline, as you type.** The message sits under the field it is
  about, in `blockMeta`, `color.text.secondary`. It is not red: it is guidance
  until `Connect`. Leading and trailing whitespace is trimmed silently.
  `Connect` is enabled only when every row reads "enabled".

  | Field | Value | Message | Connect |
  |---|---|---|---|
  | Server | empty | — | disabled |
  | Server | a host (`cis.technikum-wien.at`, optionally `:port`), or `https://` + host, optionally with a path | — | enabled. A path skips D1 and is the context URL (`components.md` §20.8.1) |
  | Server | `http://…` | `Kadence only connects over HTTPS.` | disabled |
  | Server | another scheme, spaces, or no host | `Enter the server name, like cis.technikum-wien.at.` | disabled |
  | Server | contains `user@` or `user:pass@` | `Enter the username in its own field.` | disabled |
  | Server | path is `/webdav/lvplan` or starts with `/webdav/lvplan/` (any case, the WebDAV share) | `That's the WebDAV share, which only works on the FH network. Enter just the server name: cis.technikum-wien.at.` | disabled |
  | Username | empty | — | disabled |
  | Username | the host and username of an existing source | `{user} @ {host} is already connected as {name}.` | disabled |
  | Password | empty | — | disabled |

- **`Connect`** (default, `↩`) runs **discovery and the first fetch as one
  step** (`components.md` §20.8.1–§20.8.2):
  - D1–D4 run, then one `REPORT` with the **Import window** for every listed
    calendar (CIS: one).
  - While it runs, every field is disabled. The footnote is replaced by a mini
    `ProgressView` and `Connecting to cis.technikum-wien.at…` (`blockMeta`,
    `color.text.secondary`), which is the only progress the user sees. No step
    names, no request count.
  - `Connect` is disabled. `Cancel` stays enabled: it cancels the request in
    flight and returns the sheet to its editable state with nothing changed.
  - The password is sent only in answer to the host's `401`
    (`interactions.md` §13.1).
- **Failure.** The footnote's place shows the state's title from
  `components.md` §19.1 and the step-1 body below (`sourceStatusTitle` /
  `inspectorValue`, `color.text.primary`, `lineLimit` 0). The fields are
  re-enabled, and focus moves to the field to fix. The step-1 bodies drop the
  sync-only clauses and say what to do now:

  | State | Step-1 body | Focus |
  |---|---|---|
  | `unauthorized` | `{host} didn't accept the username or password.` | `Password`, contents selected |
  | `forbidden` | `{host} refused access for {user}.` | `Username`, contents selected |
  | `noCalDAV` | `{host} doesn't offer CalDAV calendars. Check the server name.` | `Server`, contents selected |
  | `noCalendars` | `{account} has no calendars with events.` | `Username` |
  | `redirected` | as §19.1 | `Server` |
  | `notACalendar` | `{host} sent a web page instead of calendar data. Try again later.` | stays on `Connect` |
  | `fetchFailed` | `{host} refused every way Kadence asks for events. Nothing was saved.` | stays on `Connect` |
  | `certificate` | `The certificate for {host} couldn't be verified, so Kadence sent nothing to it.` | stays on `Connect` |
  | `unreachable` | `Check the server name and your connection, then try again.` | stays on `Connect` |
  | `serverError` | `{host} answered with an error ({code}). Try again later.` | stays on `Connect` |
  | `offline` | `This Mac is offline. Connect when it's back online.` | stays on `Connect` |

  There is no "connect anyway" for any of them. Problems inside objects are not
  failures: they appear in step 2.
- **Success** (at least one calendar, even an empty one) → step 2.

### 12.2 Step 2 — Calendar and Import

**One calendar** — the CIS case:

```
+------------------------------------------------+
| Import University timetable                    |  inspectorTitle
| user01 @ cis.technikum-wien.at                 |  inspectorValue, text.secondary
|                                                |
| Calendar                                       |  inspectorLabel, text.secondary
|  ✓ LVPlan                                      |  confirmed row
|                                                |
| 142 events, 14 Sep 2026 – 29 Jan 2027          |  inspectorValue, text.primary
|                                                |
| 38 of them are before today. They're imported  |  inspectorValue, text.secondary
| once, as history, and never changed afterwards.|
| 9 co-taught lectures are listed once per       |
| lecturer and are shown once.                   |
| 2 events couldn't be read and will be skipped. |  inspectorValue, text.primary
| [ Show Details ]                               |
|                                                |
|                          [ Back ]  [ Import ]  |
+------------------------------------------------+
```

**Several calendars** — the same, with a checklist in place of the row:

```
| Calendars                                      |  inspectorLabel, text.secondary
|  [x] LVPlan                                    |  checkbox rows
|  [x] Prüfungen                                 |
```

- **Title** `Import {name}`. Under it is `{user} @ {host}`.
- **The calendar** — label `Calendar` (one) or `Calendars` (several),
  `inspectorLabel`, `color.text.secondary`, `spacing.lg` above, `spacing.sm`
  below.
  - **Exactly one calendar** (CIS: `LVPlan`) — a **single confirmed row**, not
    a control:
    - `checkmark` at `size.blockGlyphSize`, `color.text.secondary`, then
      `spacing.sm`, then the display name in `inspectorValue` /
      `color.text.primary`.
    - Row height `size.connectCalendarRowHeight` (24).
    - Not focusable and not clickable: there is nothing to choose.
    - VoiceOver reads `Calendar: LVPlan`.
  - **Several** — one `Toggle` (`.checkbox` style) per calendar, label = the
    display name, rows of `size.connectCalendarRowHeight`, in D4's order:
    - On `Connect` **every listed calendar is checked**: every one supports
      `VEVENT`, or it would not be listed (`components.md` §20.8.1).
    - The list scrolls inside `size.connectCalendarListMaxHeight` (144, six
      rows).
    - `⇥` reaches each checkbox, and `Space` toggles it.
    - With none checked, a line `Choose at least one calendar.` (`blockMeta`,
      `color.text.secondary`) replaces the range line, and `Import` is
      disabled.
  - **Never listed** (`components.md` §20.8.1): the calendar home, `outbox`,
    `inbox`, VTODO-only calendars and any non-calendar collection. Nothing says
    they were left out.
- **Range line** — `{n} events, {first date} – {last date}`:
  - Dates use the `6 Oct 2026` form (§19.5's `Older` date form, without the
    time). One date when `first == last`: `1 event, 14 Sep 2026`.
  - `{n}` counts events **after the merge across the checked calendars**
    (`components.md` §20.2) — what will be on the calendar.
  - Toggling a checkbox recomputes the line and the sentences **from the data
    already fetched**, with no request.
- **Sentences**, each only when its number is non-zero, `spacing.sm` apart:
  - history: `{h} of them are before today. They're imported once, as history,
    and never changed afterwards.` Singular: `1 of them is before today. It's
    imported once, …`. When every event is before today: `All of them are
    before today. …`.
  - merges: `{m} co-taught lectures are listed once per lecturer and are shown
    once.` / `1 co-taught lecture is listed once per lecturer and is shown
    once.`
  - problems: `{k} events couldn't be read and will be skipped.` / `1 event
    couldn't …`, in `color.text.primary`. A borderless `Show Details` expands
    the problem list in place, exactly as `components.md` §19.3 does (8, then
    `+N more`).
- **Empty calendar** — the range line reads `The calendar has no events yet.`,
  and the sentence under it reads `Kadence will add them as they appear.`
  `Import` stays enabled: an empty timetable before the semester's plan is
  published is real.
- **`Import`** (default, `↩`) writes in this order, with **no further
  request** (the Import, `components.md` §20.1):
  1. the Keychain item (`components.md` §21.4);
  2. the `Source`, with the checked calendars, the principal and home hrefs,
     and the capabilities learned;
  3. the events already fetched from the checked calendars, in one transaction.

  A Keychain failure stops at step 1 and writes nothing else. It shows the title
  `Password not saved` and the body `Kadence couldn't save the password in the
  Keychain, so nothing was saved. Try again.` (sheet-only copy, not a §19.1
  state). On success the sheet closes, Settings selects the source, and its
  status block reads `Up to date`. The next sync is one interval later.
- **`Back`** returns to step 1 with every field as entered, the password too,
  for this sheet's lifetime only. `Connect` then runs again.

### 12.3 Edit mode

**Opened by** `Edit Account…` (Settings, and a state's primary action),
`Update Password…`, `Choose Calendar…` and `Edit Source…`. Title `Edit
University timetable`.

**Step 1:**

- `Name`, `Server` and `Username` are prefilled.
- **`Password` is empty**, with the placeholder `Saved in Keychain`. Left empty,
  the saved password is used, unless `Server` or `Username` changed: a
  different account needs its password, and `Connect` stays disabled until one
  is typed.
- The duplicate-account check (§12.1) ignores this source itself.

**Focus:**

| Opened by | Focus |
|---|---|
| `Update Password…` | `Password` |
| `Edit Account…` (Settings) | `Password` |
| `Edit Account…` (a state's action) | `Server` |
| `Edit Source…` | `Name` |
| `Choose Calendar…` | none: it **starts `Connect` at once** with the saved account, so the sheet opens in the connecting state and lands on step 2 |

**`Connect`** runs discovery again (an explicit act, `components.md` §20.8.1).
It then fetches every listed calendar with the Import window, so a deselection
can be counted.

**Step 2, edit form:**

- Title `Update {name}`.
- The calendar row or checklist as in §12.2:
  - The **current selection is checked**.
  - Calendars that are not selected are listed **unchecked**. In edit mode
    nothing is added without the user checking it.
  - A selected calendar that discovery no longer finds is not listed. The line
    `{calendar} is no longer on {host}.` (`inspectorValue`,
    `color.text.primary`) stands above the list.
- The range and problem sentences as in §12.2.
- The history sentence is replaced by `Events before today are not changed.`
  (it is a sync, `components.md` §20.1).
- When a calendar is unchecked, and the events only it contributed number `d` >
  0, the sentence `{d} events from calendars you unchecked will be removed,
  including past weeks.` (`1 event … will be removed, …`) appears in
  `color.text.primary`, last before the buttons.
- The button is **`Save`**.

**`Save`:**

- If the password, server or username changed, it replaces the Keychain item:
  the new one is written first, then the old one is deleted.
- It updates the `Source` (server, username, hrefs, calendars) and resets
  `capabilities.fetchMode` to `report`.
- It clears `isAutoSyncPaused`.
- It applies the already-fetched data **as a sync**, under `components.md`
  §20.8's guards, today onward only, **plus** the deselection deletion of
  §20.1.
