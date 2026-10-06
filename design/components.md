# Kadence — components (Phase 1)

Scope: event block anatomy. All six variants plus the two background window
treatments, per DECISIONS.md 2026-09-09. Every value here is a token path from
`tokens.json`; bare numbers appear only where the value is a count or a ratio.

Anything not specified here is a spec gap — append the question to `GAPS.md`
rather than inventing a value.

---

## 1. The signal system

Three orthogonal channels carry three different things. They must never be
merged, and no channel may be asked to carry a second meaning.

| Channel | Carries | Values |
|---|---|---|
| Hue | Which **source** | `color.source.*` — 8 entries, assigned in `color.sourcePalette.order` |
| Fill weight | How **movable** the block is | solid → tint → transparent+dashed |
| Leading rail + glyph | What **kind** it is, and its flexibility | rail style × SF Symbol |

The fill-weight ladder is the load-bearing one, because it is the same in both
geometries:

```
solid fill        = fixed. You do not move this. (lecture, manual event, exam)
tinted fill       = semi-fixed. Movable within rules. (routine block, deadline)
transparent+dash  = proposed / freely movable. (planned study session)
```

**Why hue is not allowed to carry type.** With 6+ sources, hue is fully spent on
source identity. If type also rode on hue, neither would survive. The
consequence is deliberate: in greyscale, or for a user with a colour vision
deficiency, *sources are not reliably distinguishable from one another* — but
type, flexibility and status all still are, because they ride on fill, rail,
glyph and border. Because hue is the *only* thing on a block that carries source,
source identity must also be available as text — that is a hard requirement, not
a nicety, and it is specified in §3.4. Nothing time-critical ever depends on
telling blue from teal.

**Red is not a source colour.** It is reserved for `color.semantic.now` and
`color.semantic.alert`, so red always means "now" or "needs attention" and never
means "this came from Moodle".

---

## 2. The style resolver

One pure function, consumed by three views. Not one view with six branches.

```swift
func resolveBlockStyle(
    kind: BlockKind,               // visual class, see 2.1
    flexibility: Flexibility,      // .fixed | .shiftable | .droppable
    status: BlockStatus,           // .scheduled | .inProgress | .done | .skipped
    presentation: Presentation,    // OptionSet: .hovered .selected .dragging .conflicted .past
    source: SourceColor,           // one of color.sourcePalette.order
    renderedHeight: CGFloat        // points, drives the density tier
) -> BlockStyle
```

It has no view dependencies, no environment access, and no side effects, so it
is unit-testable on its own. Appearance (light/dark), Increase Contrast and
Reduce Transparency are resolved by the token layer below it, not by this
function.

### 2.1 BlockKind is a visual class, not a data origin

`BlockKind` deliberately does not mirror `Event.origin`. Map at the call site:

| Data | BlockKind | Glyph |
|---|---|---|
| `origin == .imported`, timed | `.fixedTimed` | `building.columns` |
| `origin == .manual`, timed | `.fixedTimed` | `calendar` |
| `origin == .routine` | `.routineTimed` | `repeat` |
| `origin == .planned` | `.plannedTimed` | `pencil.and.outline` |
| `TravelLeg` | `.travelBand` | `figure.walk` / `car.fill` / `tram.fill` by mode |
| `WorkItem.kind == .assignment/.project`, all-day | `.deadlineAllDay` | `flag.fill` |
| `WorkItem.kind == .exam`, all-day | `.examAllDay` | `graduationcap.fill` |

A manual event is a fixed timed block because a user-created event is fixed
until the user says otherwise. It differs from an imported lecture only by
glyph and by defaulting to `color.source.graphite`.

### 2.2 BlockStyle output

```swift
struct BlockStyle {
    var fill: Color
    var fillBlendWithCanvas: CGFloat   // opacity.blockPast/Done/SkippedFillBlend, else 0
    var border: Color?
    var borderWidth: CGFloat
    var borderDash: [CGFloat]?         // nil = solid
    var rail: Color?
    var railStyle: RailStyle           // .none .solid .inset .dotted
    var label: Color
    var meta: Color
    var glyph: String                  // SF Symbol name
    var glyphColor: Color
    var cornerRadius: CGFloat
    var elevation: Elevation
    var trailingBar: Color?            // in-progress marker only
    var badge: BadgeSpec?              // conflict / done / skipped marker
    var contentOpacity: CGFloat
}
```

### 2.3 Flexibility modulates the rail, never the fill

Fill weight is already spoken for by kind. Flexibility is a third signal drawn
on the rail itself, `size.blockRailWidth` wide, full block height, leading edge:

| Flexibility | RailStyle | Drawing |
|---|---|---|
| `.fixed` | `.solid` | Full-height bar, square caps, no inset. |
| `.shiftable` | `.inset` | Bar inset `spacing.xs` from top and bottom, both caps rounded at radius `1.5`. Reads as "can slide". |
| `.droppable` | `.dotted` | 2pt on / 2pt off, square caps, full height. Reads as "can be dropped". |

`.fixedTimed` blocks are always `.fixed`. The rail is not drawn for
`.fixedTimed` (see 3.2) — its solid fill already says fixed.

---

## 3. Geometry A — GridBlock

The timed block in the hour grid. Covers variants 1–3. One view.

### 3.1 Anatomy

```
 <-- column width -->
+---+------------------------+   ^
|   | [G] Datenmodellierung  |   |   rail: size.blockRailWidth
| R |     09:00-10:30        |   |   G:    size.blockGlyphSize
|   |     FH B.2.09          |   |   padding: size.blockPadding all sides,
+---+------------------------+   v            leading padding measured from
                                              the rail's trailing edge
```

- Corner radius `radius.block`; `radius.blockCompact` at tier `.glyphOnly`
  (rendered height < 18). **Amended 2026-09-11 (G-011):** this boundary was 16,
  an independent number that no longer matched any tier edge. It now follows the
  ladder, so there is one boundary to keep, not two.
- Vertical gap to the next block in the same column: `size.blockVerticalGap`.
  The gap is subtracted from the block's geometric height **before** the floor in
  §3.3 is applied, so a short block loses no height to it.
- Gap between overlap columns: `size.blockColumnGap`.
- Glyph is vertically aligned to the first text baseline's cap height, not
  centred — except at `.glyphOnly`, where there is no text baseline to align
  to and the glyph is centred in the frame (§3.3).
- Time is always `blockMeta` with monospaced digits, format `HH:mm-HH:mm`, 24-hour.

### 3.2 The three timed variants

| | **1. Fixed timed** (lecture, manual) | **2. Routine** | **3. Planned study** |
|---|---|---|---|
| Fill | `color.source.<s>.solid` | `color.source.<s>.tint` | `color.surface.canvas` at 0 alpha, i.e. none |
| Border | none | `color.source.<s>.rail` at `opacity.routineBorder`, `size.borderRegular` | `color.source.<s>.rail`, `size.borderEmphasis`, dash `[4, 3]` |
| Rail | none | per flexibility (2.3) | per flexibility (2.3) |
| Label | `color.text.onSolid` | `color.text.primary` | `color.text.primary` |
| Meta | `color.text.onSolid` at 0.8 | `color.text.secondary` | `color.text.secondary` |
| Glyph | `color.text.onSolid` | `color.source.<s>.text` | `color.source.<s>.text` |
| Glyph symbol | `building.columns` / `calendar` | `repeat` | `pencil.and.outline` |
| Elevation | `elevation.level0` | `elevation.level0` | `elevation.level0` |

Rationale for no rail on variant 1: the entire block is the source colour, so a
rail in the same hue is invisible and a rail in another hue would lie. The
absence of a rail is itself the signal — only fixed blocks have no rail.

### 3.3 Density ladder

Driven by **rendered height in points**, never by duration. At
`size.hourHeightWeek` a 30-minute block is 22pt; at `size.hourHeightDay` it is
30pt. The same event therefore shows more in Day than in Week, which is correct.

**Revised 2026-09-11 (GAPS.md G-011).** The bands below are derived from each
tier's own content set rather than chosen; the previous table's bands were
smaller than the content they assigned, and every block of 21pt or less was
specified to be drawn taller than its own frame. See the ruling for what moved.

**Rendered height** is the block's laid-out frame height: its geometric height
for its interval, minus `size.blockVerticalGap`, floored at
`size.blockMinRenderedHeight` (11). The floor is applied **last**.
`layouts.md` §3.3 clamps to the same floor before testing overlap, and that
pairing is the whole reason the floor exists: a block is never drawn taller than
the interval the overlap test used for it, so two blocks that do not overlap in
time can never be drawn on top of each other.

**Padding is per tier.** Horizontal padding is `size.blockPadding` (5) at every
tier, measured from the rail's trailing edge (§3.1). Vertical padding is not:

| Tier | Vertical padding, top and bottom |
|---|---|
| `.full` | `size.blockPadding` (5) |
| `.compact` | `size.blockPadding` (5) |
| `.titleOnly` | `spacing.xxs` (2) |
| `.glyphOnly` | 0 — at this tier the glyph *is* the block |

No token was added for the 2: `spacing.xxs` already exists and already carries
2pt insets elsewhere in this file (§6's conflict badge inset).

**Line heights.** `lineHeight(style) = ceil(typography.<style>.size × 1.2)`, with
no extra line spacing and no gap between rows of the content stack. At the
default Dynamic Type size: `blockTitle` 15, `blockTitleCompact` 14, `blockMeta`
14. Those are the figures the table below is derived from. The implementation
must read the **resolved** font's line height, which is what keeps the ladder
correct under Dynamic Type (§11).

**The ladder.** Tier names are `.glyphOnly` < `.titleOnly` < `.compact` <
`.full` — the names the build already uses.

| Tier | Rendered height | Content | Minimum it needs |
|---|---|---|---|
| `.full` | ≥ 53 | glyph + title (`blockTitle`, up to 2 lines) + time range + meta line, each on its own line. The meta line is `Source · Location` — see §3.4, the source name is required here | 5 + 15 + 14 + 14 + 5 = **53** |
| `.compact` | 28–52 | glyph + title (`blockTitleCompact`, 1 line) + time range trailing-aligned on the same row | 5 + 14 + 5 = **24** |
| `.titleOnly` | 18–27 | glyph + title (`blockTitleCompact`, 1 line, truncated tail) | 2 + 14 + 2 = **18** |
| `.glyphOnly` | 11–17 | rail (full height) + glyph only, no text. The glyph is centred vertically in the frame — there is no text baseline to align to, and it can never overflow because the glyph's 11pt is the band's bottom | 0 + `size.blockGlyphSize` (11) + 0 = **11** |
| < 11 | — | cannot occur: the floor above has already raised it to 11 | |

**The second title line is paid for, not assumed.** `.full` renders the title on
two lines only at rendered height ≥ **68** (53 + `lineHeight(blockTitle)`); below
that the title is one line with an ellipsis. "Up to 2 lines" is a permission.

**The invariant the bands exist to satisfy: a tier's band bottom is never below
that tier's own minimum.** Where the bottom sits above the minimum — `.compact`
starts at 28 though it needs 24 — that is a deliberate density preference, not
slack to be reclaimed. Re-check this arithmetic whenever a content set, a padding
rule or a `typography.*` size changes. It is the invariant G-011 broke, and it
broke silently.

**Tier selection.** Take the tier whose band contains the available height, then
step down while that tier's minimum exceeds the available height. At the default
Dynamic Type size the second step never fires; under a larger Dynamic Type size
the minima grow while the bands do not, and stepping down is how the ladder stays
honest (§11). **Available height** is the rendered height minus the travel-band
strip in §4's short case — and the content is then drawn into that same reduced
area, not into the full frame (§3.5).

**The hit region at the floor.** A block whose geometric height is under
`size.blockMinRenderedHeight` is laid out at exactly 11pt with its frame's **top**
edge at its true start; the floor only ever extends the frame downward. Its hit
region is that frame outset by `size.blockHitExtension / 2` (3pt) at the top and
bottom edges only — 17pt tall, never wider than the frame. The outset is a hit
region, never paint (§3.5), and it loses to any real block's frame
(`interactions.md` §6.1).

Truncation is always `.tail` with no ellipsis character at `.titleOnly` (the clip
edge reads as truncation and the ellipsis costs 6pt of a very short line).
`.compact` and `.full` use a standard ellipsis.
**Confirmed 2026-10-06 (Phase 2 re-review; G-043):** this binds the Routines
window too. `Morning review` (08:15–08:45) is 22pt tall there — `.titleOnly` —
so `Morning revie` clipped at its frame with no `…`, in every Routines frame, is
the rule working, not a defect. The same title at `.compact` (the main Week grid
at narrower widths: `Fixture revi…`) takes the ellipsis. No change.

If two clamped blocks would overlap after clamping, they enter cascade layout
(see `layouts.md` §3.3) rather than being drawn on top of each other.

**Visible width overrides the tier.** In a cascade a block can be partly covered
by the block in front of it. When a block's visible width is below
`size.blockCascadeMinReadableWidth` (44), it renders the `.glyphOnly` content set
— glyph only, no text — regardless of its height. A covered block that renders its
full content gets clipped mid-string and reads as damage (`10:`), not as
something behind something else. `resolveBlockStyle` therefore takes visible
width as well as rendered height.

**Amended 2026-10-06 — DEFERRED out of Phase 2 (G-048; DEVIATIONS A35, to be
logged), still normative.** *Visible width* was never defined, and the build
reads it as the narrowest visible strip anywhere on the block. A conflict is an
overlap, so every Phase 2 conflict draws a cascade, and the 2026-10-06 frames show
the cost: in `conflict-panel-two-options-p2f20.png` Wednesday's `Training`
(17:00–18:30) is covered from 17:30 by `Supervisor meeting`, yet its whole
17:00–17:30 top strip — full column width, uncovered — draws nothing but the
badge; in `conflict-single-option-p2f20.png` the conflict's own `Supervisor
meeting` has no title on the grid. The rule, when built:

- Visible width is measured across the block's **title band**: from the frame's
  top to top + the tier's top padding + `lineHeight(blockTitleCompact)`.
- If the title band's unobstructed width is ≥ `size.blockCascadeMinReadableWidth`
  (44), the block draws the **`.titleOnly` content set** (glyph — or §6's badge
  rule — and a one-line title) in that band, top-anchored, and nothing below it;
  the rest of the frame is fill and rail. Only when the title band is itself
  covered below 44pt does `.glyphOnly` apply as above.
- It never draws more than its height tier allows, and the covering block still
  paints over it (§3.5 is about a block's own frame; occlusion by a block in
  front is not overflow).

Deferred because it changes cascade rendering in every view, not only conflict
frames, and needs its own capture set; Phase 2's definition of done does not
depend on it — the inspector's collision header names both blocks, and hover
help carries every title (§3.4).

**Amended 2026-10-05 (Phase 2 screenshot review) — the title beats the time on a
shared row.** At `.compact` the title and the trailing time share one row, and
nothing said which one gives way when the column is narrow. The 2026-10-05
captures show the wrong one giving way: `Gym` reduced to `G` (main Week grid) and
to a single stray character (Routines window at 780pt) while `07:00-08:00`
rendered in full. The time is recoverable from hover help and the inspector; the
title is the one thing on the block that says what it is. The rule:

1. The title is laid out first and keeps at least
   `size.blockCascadeMinReadableWidth` (44) — the same "enough to tell *Coffee*
   from *Code review*" floor the cascade rule uses (`DECISIONS.md` 2026-09-09).
2. The trailing time is drawn only if it fits **whole** in what is left after that
   44pt and `size.blockGlyphGap`. Otherwise it is **dropped entirely** — never
   truncated (`07:00-0…` is not a time), and never allowed to squeeze the title.
3. The title then takes all remaining width and truncates tail-first with an
   ellipsis, per the rule above.

This is the same trade §6 already makes for the conflict badge at `.titleOnly` and
`.compact`: the corner goes to the thing that cannot be recovered elsewhere. It
binds every GridBlock, including the Routines window's and the conflict panel's
collision blocks. And §3.5 rule 1 still holds underneath it: a title that does not
fit is clipped at the frame — the 780pt capture's `Morning review` printing across
the next column's divider is a §3.5 violation, not a layout choice.

**Reading the old numbers.** Prose elsewhere in this file was written against the
previous bands. The mapping is normative: "11–15" or "below 16" means
`.glyphOnly`; "16–27" means `.titleOnly`; "28–43" means `.compact`; "≥ 44" means
`.full`. All Phase 1 prose in this file has been restated in tier names; the
Phase 2 sections (§13–§17) still use the old numbers and are not re-edited here —
read them through this mapping until the next Phase 2 revision window.
**Amended 2026-10-05:** that window was the Phase 2 screenshot review; §14.2's two
uses are restated in tier names and no other Phase 2 section used the old bands.

### 3.4 Source name in text — required

The block's glyph slot is spent on kind, and the sidebar's per-source symbol is
not repeated on the block. That leaves hue as the only source signal on a block,
which is not sufficient on its own. Every block must therefore make its source
name available as text, by these rules:

| Where | Rule |
|---|---|
| Tier `.full` (≥ 53) | The source name is rendered on the block, on the meta line, as `Source · Location`. `blockMeta` type. |
| Tiers below `.full` | The source name is **not** on the block — there is no room for it without evicting the time. Hover help and the inspector carry it. |
| All-day items (§5) | Never on the pill; `size.allDayRowHeight` fits a title and nothing else. Hover help and the inspector carry it. |
| Month chips (§9) | Never. Hover help carries it. |
| Inspector | Always, as swatch + name, per `layouts.md` §6. |
| VoiceOver | Always, in the label, per §11. |

**Hover help is the universal carrier.** Every block, band, pill and month chip
gets standard help text (`.help()` / `NSToolTip`, system delay, no custom
tooltip): `Title · HH:mm–HH:mm · Source · Kind`. This is the one path that exists
at every density tier, in every view, in both geometries. It is not optional and
it is not a nice-to-have — it is what makes the greyscale trade in §1 acceptable.

Layout priority on the meta line: **source wins, location truncates first.**
Location is recoverable from the inspector and from the travel band's own label;
source, below `.full`, is recoverable only from hover help and the inspector.
When there is no location the line is just the source name.

The two closest hues in the palette are `amber` and `orange`
(`color.sourcePalette.adjacencyWarning`). They are separated in the default
assignment order, but the text rule above is what actually makes them safe.

**The `.full` boundary moved from 44 to 53 on 2026-09-11 (G-011),** which narrows
where this rule applies: blocks of 44–52pt — 46–54 minutes in Day, 63–74 minutes
in Week — no longer carry the meta line. This is not a weakening of the rule. At
44pt the meta line was specified but could not be drawn: the content set needs
53pt, so what those blocks actually rendered was a meta line clipped or spilling
outside the frame. A tier that cannot draw the source name must not claim to. For
those blocks the source is carried by hover help and the inspector, exactly as
for every other tier below `.full`.

### 3.5 Confinement — a block never paints outside its laid-out frame

**New 2026-09-11 (GAPS.md G-011).** Nothing in this spec previously said where a
block's rendering may put its ink. §4 said it for one case (a short travel band
stays inside its event); the general rule was missing, and the result was blocks
that drew their content centred on a frame too small for it, spilling equally
above and below and damaging the *neighbouring* block as well as their own.

1. **A block paints only inside its own laid-out frame.** Clip to the frame's
   rounded rect at the radius from §3.1. Fill, border, rail, glyph, text, badge,
   travel strip — all of it, without exception.
2. **The content stack is top-anchored.** It is laid out from the frame's top
   inset downward. Never vertically centred on the frame, never bottom-anchored.
   A height-setting modifier that centres its child by default is specifically
   wrong here; the anchoring must be stated, not inherited. The single exception
   is `.glyphOnly`, whose one item is 11pt against a band that starts at 11pt and
   so can never overflow: there the glyph is centred (§3.3).
3. **Content that does not fit is clipped at the bottom edge.** No scaling, no
   shrink-to-fit, no overflow. The worst case is therefore a block that shows
   less than its tier claims — never a block that damages the one below it. With
   §3.3's derived bands this should not arise at the default Dynamic Type size;
   rule 3 is what bounds the damage when it does.
4. **Exceptions, exhaustively.** The selection focus ring (§6) is drawn outside
   the bounds with a 1pt gap, by design. Elevation shadows fall outside by
   definition. The `size.blockHitExtension` outset (§3.3) is a hit region, not
   paint. A case-1 travel band has a laid-out frame **of its own** — the
   `departAt → event.start` rect (§4) — and is confined to that, not to its
   parent's. Nothing else.
5. **Scope.** GridBlock (§3), TravelBand (§4), AllDayItem (§5) and the month
   chip (§9). §5 and §9 are fixed-height rows whose content is guaranteed to fit
   and is vertically centred within the row; rules 1 and 3 still bind them.
6. **A travel band's strip is inside its parent's frame in the short case.** The
   parent's content area is its frame minus the strip; §3.3's tier is evaluated
   against that area's height *and the content is drawn into that area*. A tier
   chosen against remaining height but rendered into full height is the same bug
   one level up, and it is what pushed a Week block's strip above its own top
   edge in the 2026-09-09 screenshots.

---

## 4. Geometry B — TravelBand

Not a block. A leading edge attached to the event it belongs to.

- Occupies the interval `departAt → event.start` in the same column as its event.
- Height and placement, two cases:
  - **True interval ≥ `size.travelBandHeight`.** The band occupies the interval
    above its event, in that event's slot, at its true height. That interval is
    part of its parent's layout footprint for overlap resolution — `layouts.md`
    §3.3, steps 1 and 2 — so the band occupies grid time that no other cluster
    can be placed into.

    **Z-order, amended 2026-09-11 (GAPS.md G-012).** The band paints at its
    parent event's index in the paint order, immediately *below* its parent so
    the parent's top edge wins where the two meet, and above or below exactly
    the blocks its parent is above or below. Below the now line. A band is never
    given a z-index of its own.

    This line previously read "Drawn above other blocks in z-order", which
    licensed a case-1 band to paint over a block belonging to a **different**
    cluster — and it did, over the meta line of "Morning review" in the
    2026-09-09 Day screenshot, which is the exact failure this section's own
    rationale says is not worth 18pt. With the footprint rule in `layouts.md`
    §3.3 there is no foreign block left to draw above: anything sharing the
    band's interval is now in the band's own cluster and packed beside it.
    Inside that cluster, under cascade, the band overlaps by design and its
    parent's index is the correct one.
  - **True interval < `size.travelBandHeight`.** The band does **not** grow
    upward out of its event. It becomes a `size.travelBandHeight` strip inside
    the top of the event's own frame, and the event's content starts below it —
    the event's density tier is then evaluated against its remaining height, not
    its full height, **and the event's content is drawn into that remaining area
    rather than into the full frame** (§3.5 rule 6). A case-2 band extends
    nothing: it is inside its parent's frame, so its parent's layout footprint is
    unchanged (`layouts.md` §3.3).

  A band never draws outside its own event's bounds in the short case. The first
  draft of this spec had it grow upward and overlap whatever was above; the
  2026-09-09 screenshot showed the result — a 22-minute band covering the meta
  line of the routine block above it. A travel band that destroys another block's
  content to announce itself is not worth the 18pt.
- Fill `color.surface.travelBand`, plus a 45° hatch: 1pt lines, 5pt pitch, in
  `color.window.lowEnergyHatch`. Corner radius `radius.travelBand` on the top two
  corners only; bottom corners 0.
- The attached event's **top** two corners become 0 while a band is attached, so
  the two read as one object.
- Content, single row, `travelLabel`: mode glyph + `"Leave HH:mm"` +
  ` · NNmin`. Below 18pt height, drop the duration; below 14pt, glyph only.
- Text `color.text.secondary`.
- **Not focusable and not independently selectable.** Clicking or keyboard-focusing
  it selects the parent event. VoiceOver folds it into the parent's label:
  `"Datenmodellierung, 09:00 to 10:30, leave by 08:12, 22 minutes walking"`.
- Never drawn for an event with no location, and never drawn for all-day items.

---

## 5. Geometry C — AllDayItem

Lives in the pinned all-day row above the hour grid (Week/Day) or as a row in the
month cell. Never in the hour grid. Covers variants 5–6.

Pill of height `size.allDayRowHeight`, radius `radius.allDayPill`, spanning its
full date range across day columns.

| | **5. Deadline** | **6. Exam** |
|---|---|---|
| Fill | `color.source.<s>.tint` | `color.source.<s>.solid` |
| Border | `color.source.<s>.rail`, `size.borderRegular` | none |
| Rail | `.solid`, leading | none |
| Label | `color.text.primary` | `color.text.onSolid` |
| Glyph | `flag.fill`, `color.source.<s>.text` | `graduationcap.fill`, `color.text.onSolid` |
| Trailing element | none | countdown chip |

Same fill-weight ladder as the timed blocks: solid = fixed. An exam is a fixed
date you ramp toward; a deadline is a date whose work is movable. The two are
therefore distinguishable by fill, by glyph and by the presence of the chip —
three signals, none of them hue.

**Countdown chip.** Trailing-aligned, `radius.chip`, `countdownChip` type,
horizontal padding `spacing.xs`, height 14. Fill `color.text.onSolid` at 0.18,
text `color.text.onSolid`. Content: `T−6d` / `T−1d` / `today`. Never negative,
never red, no "overdue" state — an exam that has passed leaves the countdown off
entirely and takes `.past` presentation.

---

## 6. States

Nine states. They compose: a block can be past *and* done, or selected *and*
conflicted. Order of application is the order of this table.

| State | Delta |
|---|---|
| **default** | Style as resolved in §3–§5. `elevation.level0`. |
| **hover** | 1pt inset ring in `color.interactive.hoverOverlay`, drawn inside the border. Resize handles become visible (`size.blockResizeHandleHeight` top and bottom). Cursor `.resizeUpDown` over a handle, `.openHand` elsewhere. Transition `motion.hover`. |
| **selected** | Focus ring `color.interactive.focusRing`, `size.borderSelected`, drawn **outside** the block bounds with a 1pt gap, corner radius `radius.block + 2`. Block rises to `elevation.level1`. Fill unchanged. |
| **dragging** | `opacity.blockDragging`, `elevation.level2`. Original slot stays visible at `opacity.blockDragOrigin`. Drop target drawn as a 1pt dashed outline in `color.interactive.accent`, dash `[3, 3]`, at the snapped frame. |
| **conflicted** | Border becomes `color.semantic.alert` at `size.borderEmphasis`, replacing whatever border the variant had (dash pattern is preserved if the variant had one). Badge `exclamationmark.triangle.fill`, `size.conflictBadgeSize`, in `color.semantic.alert`, trailing-top corner, inset `spacing.xxs`. **Fill is never changed** — fill still has to carry source and movability. At `.glyphOnly` the badge replaces the type glyph. **At `.titleOnly` and `.compact` the badge and the trailing-aligned time both want the trailing-top corner: the badge wins and the time is dropped.** The time is recoverable from hover help and the inspector; the conflict is not recoverable from anywhere else on the grid. At `.full` both fit — badge in the corner, time on its own line. |
| **past** | Content opacity `opacity.blockPastContent`. Fill blended with `color.surface.canvas` at `opacity.blockPastFillBlend`. Border and rail take the same blend. No strikethrough. |
| **inProgress** | 3pt bar in `color.semantic.now` on the **trailing** edge, full height, square caps. Block rises to `elevation.level1`. The leading rail and glyph are untouched — type must stay readable while an item is running. |
| **done** | Fill blended with canvas at `opacity.blockDoneFillBlend`. Type glyph replaced by `checkmark.circle.fill` in `color.text.secondary`. Label `color.text.secondary`. No strikethrough (it costs legibility and reads as a cancellation, not a completion). |
| **skipped** | Fill blended with canvas at `opacity.blockSkippedFillBlend`. Border becomes dashed `[3, 3]`, `size.borderRegular`, `color.separator.strong`. Glyph replaced by `arrow.uturn.forward.circle` in `color.text.secondary`. At `.full` a meta line reads `Re-offered`. No red, no counter, no badge. |

| **previewed** | The block is shown at a **proposed** frame during conflict resolution (`interactions.md` §10), not a committed one. It renders at `opacity.blockPreviewed` inside a `size.borderSelected` dashed outline in `color.interactive.accent`, dash `[3, 3]`, **and its current frame stays visible at `opacity.blockDragOrigin`**. Applied last, after every row above it. |

`done` and `skipped` are visually siblings of equal weight. A skipped item must
never look worse than a done one — it has been re-offered, not failed.

**`previewed` deliberately reuses the drop-preview vocabulary** from
`interactions.md` §4 — dashed accent outline at the destination, ghost at the
origin. The user already learned that language by dragging a block, and it is
the one combination a committed block can never have: a committed block is never
in two places at once. That is what makes a previewed block unmistakably
uncommitted without spending a channel the signal system does not have
(`interactions.md` §10.2 carries the canvas-level marker that goes with it).

---

## 7. Background window treatments

Protected and low-energy windows. These are **canvas, not content**. Two rules
make the difference legible:

1. They never use hue. Content owns hue; canvas owns value and texture.
2. They span the full column width **including the time gutter**, and are drawn
   below the hour lines and below every block. Their edges therefore stay visible
   when the column is full of blocks — which is the only time they matter.

| | **Protected** | **Low-energy** |
|---|---|---|
| Fill | `color.window.protectedFill` (1.12:1 against canvas — a value step, not a colour) | none; canvas shows through |
| Texture | none | 45° hatch, 1pt lines, 6pt pitch, `color.window.lowEnergyHatch` |
| Edges | 1pt line `color.window.protectedEdge` at the top and bottom boundary only | none |
| Label | once, at the window's top edge, in the **leading day column** — never the gutter — inset `spacing.xs`, `windowLabel` type, `color.window.label` | same |
| Z-order | below grid lines | below grid lines, above protected fill |

Peak-focus windows get **no treatment on the calendar canvas**, in any phase.
Peak focus is the absence of the other two; adding a third background would turn
the canvas into a second information layer competing with the blocks.

**Editor exception (Phase 2).** A window the user cannot see is a window the user
cannot edit, so peak-focus *is* drawn — but only inside the Routines window's
windows mode (§13.3), never on the calendar canvas. There it is a 1pt dashed
outline in `color.window.peakFocusEdge`, dash `[4, 4]`, with no fill
(`color.window.peakFocusFill` is transparent by definition), plus the standard
window label. Outline-only, so it stays distinct from protected (value step) and
low-energy (hatch) in the one place all three appear together.

**The label never enters the time gutter.** The gutter carries hour labels, the
now time, and the keyboard time cursor's time (`interactions.md` §1) — and
nothing else. **Amended 2026-09-10:** the original rule named only hour labels
and the now time, which contradicted `interactions.md` §1. §1 wins; the cursor
time suppresses a colliding hour label by the same 12pt rule the now time uses
(§8). Window labels remain banned from the gutter, which is what this rule was
written to prevent. The first draft put window
labels there and the 2026-09-09 screenshot showed both collisions it causes: a
low-energy label overprinting the `13:00` hour label, and a protected label
overprinting `00:00`.

**When the window's top edge is scrolled above the viewport,** the label pins to
the top of the visible region — still in the leading day column, still never the
gutter — prefixed with `chevron.up` at `size.blockGlyphSize` to say the window
continues above. A protected window running 22:00–07:00 is otherwise unlabelled
for the whole morning, which is exactly when the user is looking at it.

Overlapping windows: protected wins. Never render both treatments in the same
region.

**Amended 2026-10-05 (Phase 2 screenshot review) — three rules the captures showed
were missing.**

1. **A window paints only inside its own spans.** A span is one weekday's
   `start…end` rect, column-wide, plus the gutter strip at the same height (rule 2
   above). Fill, edge lines and the low-energy hatch are clipped to that union and
   nowhere else. Every 2026-10-05 Routines capture shows the `Low energy` hatch
   (Mon–Fri) continuing past Friday's trailing divider as a diagonal wedge into
   Saturday: the hatch's 45° lines are drawn across a bounding box and not clipped
   to the column. A Saturday with hatch on it is a Saturday the user is told is
   low-energy. This is §3.5's confinement rule applied to canvas.
2. **A window label is never drawn half-covered.** Labels sit below blocks
   (z-order above), so a block whose frame intersects the label's rect leaves a
   sliced string — `Low energy` under `Errands` at 13:00 in items 13, 15 and 16.
   The label is placed in the **leading day column the window spans in which its
   rect intersects no block frame**, scanning in column order; if no such column
   exists it is omitted for that span. The window is still drawn; the label is
   recoverable from Windows mode and the window inspector. ~~In Windows mode
   (§13.3) the edited layer is the windows, so there labels are drawn **above**
   the dimmed block layer and are never displaced.~~
   **Corrected 2026-10-06 (Phase 2 re-review; G-044).** The struck sentence was
   built exactly as written (P2-F06), and `inactive-weekdays-windows-mode-p2f20.png`
   shows what it produces: `Low energy` at 13:00 in Monday with `Errands`'
   2pt alert border running through the middle of the word. Drawn above is not
   the same as legible; a label crossed by a line reads as struck out. In
   Windows mode labels are drawn **above** the dimmed block layer **and placed by
   the same column scan as Blocks mode** (leading spanned column whose label rect
   intersects no block frame). The one difference: Windows mode never omits a
   label, because there the windows are the subject being edited — if every
   spanned column is covered, the label is drawn in the leading spanned column,
   above the blocks. With the `Daily routine` fixtures `Low energy` is therefore
   in Tuesday in both modes.
3. **The leading column's top-left corner is shared by stacking, never by
   overprinting (closes G-025).** When the label's column is an inactive
   Routines column (§13.5.3), the in-column note takes the corner and the label is
   placed directly below the note's frame, `spacing.xs` under it. The note wins
   the corner because it answers the question the pointer is about to ask in that
   column (*why will this gesture do nothing?*); the label is a name, and names
   can move down a line. The same stacking applies when both are pinned to the
   top of the visible region. The label never moves into the gutter to escape
   the note (rule above).

Under **Increase Contrast**: the protected fill's 1.12:1 step disappears, so
protected switches to a 1pt border in `color.window.protectedEdgeHC` on all four
sides plus the fill; low-energy's hatch pitch tightens from 6pt to 4pt.

---

## 8. Current time indicator

- A `size.nowLineThickness` line in `color.semantic.now` spanning the full canvas
  width in Day, and only the current day's column in Week.
- A filled circle of `size.nowDotDiameter` in the same colour, centred on the
  line, at the leading edge of the column (Week) or at the gutter edge (Day).
- The current time is additionally printed in the time gutter in
  `color.semantic.now`, `hourLabel` type, replacing the hour label it would
  collide with (within 12pt).
- Drawn above every block and every background window; below sheets and popovers.
- Updates on `motion.nowLineTick.interval`.
- No block is ever a full-width 2pt line, so the now line cannot be mistaken for
  content.
- Not rendered in Month.

---

## 9. Month cell chip

Month uses the same signal system with the `.titleOnly` content set — glyph +
one truncated title line, no time — at `size.monthCellRowHeight`.

**Clarified 2026-09-11 (G-011).** This is an **explicit content-set assignment,
not a height-derived tier**: the month chip is a fixed-height row and §3.3's band
table governs GridBlock only. `size.monthCellRowHeight` (17) is
`lineHeight(blockTitleCompact)` (14) + 3, so the chip carries **no vertical
padding** and its text is vertically centred in the row. Reading 17 through
§3.3's bands would land on `.glyphOnly` and silently delete every title in Month;
it does not apply here.

- Height `size.monthCellRowHeight`, radius `radius.blockCompact`, full cell width
  minus `spacing.xs` on each side.
- Rail `size.blockRailWidth`, glyph 9pt, title `blockTitleCompact` truncated tail.
- Fill, border, rail and glyph exactly as §3.2 / §5 — the fill-weight ladder is
  what makes Month readable at a glance, so it is not simplified away.
- Timed events show no time. All-day items span horizontally across the cells
  they cover and are always sorted above timed events in the cell.
- Sort order within a cell: all-day items by start, then timed events by start.
- Overflow: `size.monthCellMaxVisibleRows` rows, then a final row
  `+N more` in `blockMeta` / `color.text.secondary`, which is focusable and opens
  that day in Day view.
- Travel bands are **not** rendered in Month. Background windows are **not**
  rendered in Month.

---

## 10. Supporting components

### 10.1 Source swatch (sidebar)

An 11×11 rounded rect, radius 3, filled `color.source.<s>.solid`, plus the
source's own SF Symbol at 9pt in `color.text.onSolid` centred inside it, rendered
monochrome. The symbol is what makes the sidebar legend work without colour.
Unchecked state: fill `color.surface.canvas`, 1pt border `color.source.<s>.rail`,
symbol in `color.source.<s>.text`.

#### The symbol belongs to the source, not to the palette slot

`CalendarSource` carries a `symbol`. A palette slot is assigned in order as
sources are added (`color.sourcePalette.assignmentRule`), so a symbol keyed to
the hue would be meaningless. The symbol defaults from the source's kind by the
table below and is user-overridable; two sources may share a symbol, they will
never share a hue.

#### Normative symbol table

| Source kind | Symbol |
|---|---|
| University timetable | `tablecells.fill` |
| Moodle / coursework deadlines | `tray.2.fill` |
| Exams | `seal.fill` |
| Mail-derived appointments | `envelope.fill` |
| Routine | `rectangle.stack.fill` |
| Manual | `person.fill` |
| Planned study | `sparkles` |
| Travel | `map.fill` |
| Other (a bucket the user named themselves) | `tag.fill` |
| **Unknown kind — fallback** | `circle.fill` |

The fallback is deliberately a plain disc. An unclassified source should say "a
source, unlabelled" and fall back to carrying hue alone; a `questionmark` would
read as an error state for something that is merely unlabelled.

#### Why these, and the rule for adding more

Source symbols and block type glyphs (§3.2, §5) are two different vocabularies
that appear on screen simultaneously — most directly in the inspector, whose
title row puts the block's kind glyph and the source swatch side by side
(`layouts.md` §6). They must not read as one vocabulary. Two rules keep them
apart:

1. **Different domain.** A kind glyph depicts the *activity* — a lecture hall, a
   repeat arrow, a pencil, a walking figure, a flag, a graduation cap. A source
   symbol depicts the *origin*: the container, feed or party the data arrived
   from. `sparkles` for planned study is the planner that produced it, not the
   studying; `map.fill` for travel is the routing provider, not the journey.
2. **No symbol appears in both tables**, and none may be added to either that
   appears in the other. Check §2.1, §3.2 and §5 before adding a source kind.

This matters because several source kinds share a *name* with a block kind —
routine, exams, planned study, travel. If both used the obvious symbol, the glyph
would carry no independent information and, worse, would teach the user that the
glyph on a block means its source. It does not: on a block the glyph always means
kind, and hue always means source.

One near-adjacency to be aware of, in the same spirit as the amber/orange hue
pair: `person.fill` (manual source) and `figure.walk` (walking travel band) are
both human figures. They are a bust and a full stride, at different sizes, in
different places — the sidebar swatch and a travel band — and never adjacent.
Do not add a second figure symbol to either vocabulary.

### 10.2 Needs-attention count (sidebar)

A count badge, `blockMeta` type, `color.text.secondary` on
`color.surface.canvasSunken`, radius `radius.chip`, horizontal padding
`spacing.sm`. **Never red, never a filled alert colour, and hidden entirely at
zero** — no empty-state counter, no zero badge. Zero shows nothing at all.

**The row takes no icon.** It is the only non-source row in that list; its text
and its count already separate it from the swatch-prefixed source rows below,
and a bare label separates it better than any glyph would. This closes a
collision found on 2026-09-09: the build used `tray.full` here, which sits a few
rows above the Coursework source's `tray.2.fill` (§10.1) in the same list at the
same size — two trays in one sidebar. Neither the sidebar nor any other chrome
may introduce a symbol without checking it against §10.1 and against the kind
glyphs in §2.1, §3.2 and §5.

**Amended 2026-10-05 — what the row speaks (closes G-029).** One accessibility
element, role button.

| | Value |
|---|---|
| Label | `Needs attention` — the row's visible text |
| Value | `1 conflict` / `16 conflicts` — the count with its noun |
| Hint | none |

VoiceOver reads it as "Needs attention, 16 conflicts, button". The noun is
**`conflict`** for both kinds the count includes: a §14.6 template refusal is
specified as "a conflict with no event on either side", so it is the same noun,
and one count must mean one thing (`interactions.md` §10.1). Not `items` — that
word could mean anything, and the row exists to say what kind of thing is
waiting. The badge itself stays a bare number; the noun is spoken only, because
the label beside it already names the row.

### 10.3 Today pill (day header)

When a day column's date is today, the `dayHeaderDate` numeral sits on a filled
circle of diameter 26 in `color.interactive.accent` with text
`color.text.onSolid`. Weekday label above is unchanged.

---

## 11. Accessibility and appearance overrides

**Dark mode.** Every token has both appearances; nothing is derived at runtime
except the canvas blends in `opacity.*FillBlend`, which are computed against
`color.surface.canvas` for the current appearance.

**Increase Contrast.**
- All variant borders step from `size.borderRegular` to `size.borderEmphasis`,
  and the routine border drops its `opacity.routineBorder` and draws at full
  strength.
- `color.separator.hour` and `.dayDivider` are replaced by
  `color.separator.strong`.
- Protected windows switch to a bordered treatment (§7).
- The `.plannedTimed` dash pattern tightens from `[4, 3]` to `[3, 2]` so the
  outline reads as continuous.

**Reduce Transparency.** The sidebar, toolbar and popover normally draw the
platform material named by `color.surface.sidebarMaterial`, `.toolbarMaterial`
and `.popoverMaterial`. Under Reduce Transparency they draw the literal colours
`color.surface.sidebar`, `.toolbar` and `.popover` instead. The same pairing
applies to `color.interactive.accent` / `.accentSystemName` and its siblings:
prefer the named platform value, fall back to the literal pair.

**Dynamic Type.** All text resolves through the `textStyle` in
`typography.*`. When the resolved title height would exceed the block, the
density ladder drops a tier — the ladder is evaluated against *resolved* text
height, not against the default point sizes. §3.3 states this as a rule with
numbers: each tier's minimum is recomputed from the resolved line heights, and
tier selection steps down while the selected tier's minimum exceeds the available
height. The bands in §3.3's table are the default-size figures; the minima are
not constants.

**VoiceOver.** Each block is one accessibility element. Label order:
title, time range, kind, source, status, then conflict if present. Example:
`"Datenmodellierung, 09:00 to 10:30, lecture, university timetable, conflicts with Training"`.
Kind and status are spoken because they are carried visually by shape — they must
not be dropped from the label on the assumption colour conveys them.

**Amended 2026-10-05 — the conflict phrase for a protected window (closes
G-030).** §11's example covers block against block. A block inside a `.protected`
window speaks the verb §14.2 chose for exactly this asymmetry:

| Conflict kind | Phrase |
|---|---|
| Another block | `conflicts with Training` — one phrase per partner, in partner start order |
| A protected window with a label | `lands in Sleep, a protected window` |
| A protected window with an empty label | `lands in a protected window` |

Block phrases come first, then window phrases, joined with `, `. Never
`conflicts with a protected window`: two blocks conflict with each other, a block
lands in a window (§14.2), and the spoken label should not teach a symmetry the
screen deliberately does not show. The parenthesised `(protected)` of §13.6.2's
visible line is not spoken as punctuation; `, a protected window` is its spoken
form.

---

## 12. What Phase 1 must render for review

The mock data generator has to put every variant and every state on one day grid
so this spec can actually be checked. Minimum fixture for a single day:

1. `.fixedTimed` imported, 90 min, source `blue`
2. `.fixedTimed` manual, 45 min, source `graphite`
3. `.routineTimed` `.fixed`, 60 min, source `green`
4. `.routineTimed` `.shiftable`, 45 min, source `green`
5. `.routineTimed` `.droppable`, 30 min, source `green`
6. `.plannedTimed`, 90 min, source `purple`
7. A `.travelBand` attached to (1), 22 min
8. A `.travelBand` attached to (2) whose true height is under the floor
9. `.deadlineAllDay`, source `orange`
10. `.examAllDay` with `T−6d`, source `teal`
11. A 15-minute block (tier `.glyphOnly` in both views) and a 10-minute block
    (clamped to `size.blockMinRenderedHeight`), placed 5 minutes apart so the
    §3.5 confinement rule is actually exercised
12. Three mutually overlapping timed blocks, to exercise column packing
13. Six mutually overlapping timed blocks in a narrow week column, to exercise cascade
14. One block in each of: conflicted, past, inProgress, done, skipped
15. A protected window 22:00–07:00 and a low-energy window 13:00–14:30
16. A day with nothing on it at all, to check the empty grid
17. Two blocks side by side on sources `amber` and `orange` — the closest hue
    pair — one above and one below the `.full` boundary (53pt), to check that
    §3.4 does the work that hue cannot
18. One event of 55–60 minutes in Day carrying a case-1 travel band, with an
    unrelated event ending inside the band's interval, to exercise the footprint
    rule in `layouts.md` §3.3 — the pair must pack side by side, not overlap

Items 1–16 are display fixtures only. They are generated data, not services:
no TravelLeg computation, no routine engine, no work item model behind them.

---

# Phase 2 — routines, conflicts, protected time, the menu bar

Everything below is an addition. No Phase 1 value changes; the amendments to §6,
§7 and §10.2 above are marked in place and were ruled on 2026-09-10.

---

## 13. The Routines window

Rulings this implements: `DECISIONS.md` 2026-09-10 "Routine instances edit
instance-only, no dialog."

### 13.1 It is the calendar canvas, not a form

A routine template is a week. The editor therefore **reuses the Week canvas
wholesale** — the same hour grid, the same `GridBlock` geometry, the same
background window layer, the same overlap resolution from `layouts.md` §3.3.
Blocks are created, moved and resized exactly as on the main grid.

Differences from the Week view, and these are the only ones:

| | Week view | Routines window |
|---|---|---|
| Columns | seven dates | seven **weekdays**, no dates, `dayHeaderWeekday` only |
| Now line | yes | **no** |
| All-day row | yes | **no** |
| Travel bands | yes | **no** |
| Blocks | `Event` | `RoutineBlock` — always `.routineTimed` |
| Source hue | per source | the routine's own palette slot, one hue for the whole template |

Building a bespoke weekly-grid widget here would create a second visual
vocabulary for the same information, which is the thing §1 exists to prevent.
Anything that looks like a block in this window is a block, and behaves like one.

### 13.2 The flexibility control

Flexibility is already visible on the rail (§2.3). In the editor it is also
editable: a three-segment control in the editor inspector, labelled
**Fixed / Shiftable / Droppable**, each segment showing a 3pt rail sample in the
segment's leading edge drawn in that rail style — solid, inset, dotted. The
control teaches the grid's own vocabulary rather than describing it in words.

`.shiftable` reveals a stepper for its ± minutes, `blockMeta` type, 15-minute
steps, range 15–180.

**Amended 2026-10-01 — the stepper's value semantics (closes G-022).** The model
field is optional and `ConflictEngine` silently produces no `.shiftLater` option
when it is absent, so "range 15–180" is not enough on its own:

- **Default on entry.** Choosing `Shiftable` for a block that has no ± value
  writes **30** immediately — not `nil`, not 15. 30 is two snap steps, the
  smallest value that lets a block clear an ordinary 15–30 minute collision, so
  the default is useful rather than merely legal.
- **Switching away keeps the number.** Choosing `Fixed` or `Droppable` leaves the
  stored ± value untouched and hides the stepper. Coming back to `Shiftable`
  restores what was there. Discarding it would punish the user for looking at the
  other two segments.
- **A `.shiftable` block with no ± value is a defect, not a state.** It renders
  the stepper at 30 and writes 30 on first display. There is no "unset"
  presentation, because the only thing an unset value does in this build is
  remove a resolution option the user never asked to lose.
- **Clamping.** Values outside 15–180 clamp to the nearest bound; the stepper
  never presents a value it would not accept.
- One named undo step per change: `Set Flexibility` for the segment, `Set Shift
  Range` for the stepper.

**Amended 2026-10-05 — the rail sample and the stepper's text (closes G-032).**

- **Sample height:** the segment title's resolved line height, vertically centred
  on the title — as built. It scales with Dynamic Type through the control font.
- **Sample colour: none of its own.** The sample is a **template image**, tinted by
  the segmented control exactly as it tints the segment's title, in both the
  selected and unselected state. The sample teaches the rail's *style* (solid,
  inset, dotted); hue on the grid means source (§1), and a green bar inside a
  blue selected segment measured as a dark mark on a saturated fill in the
  2026-10-05 capture — legible only by luck. Template tinting is legible by
  construction in every state the platform draws, including Increase Contrast.
- **Stepper copy:** `± 30 min` — `±`, a space, the number, a space, `min`.
  `blockMeta`, `color.text.primary`, monospaced digits, beside a native stepper.
  No label word before it; the `Shiftable` segment directly above is the label.

### 13.3 Modes: blocks or windows

Dragging on empty canvas has to mean one thing, and this window has two kinds of
object on it. A segmented control in the editor's mode bar, height
`size.editorModeBarHeight`, `editorModeLabel` type:

| Mode | Editable | Other layer |
|---|---|---|
| **Blocks** | routine blocks | windows drawn normally, not hit-testable |
| **Windows** | protected / low-energy / peak-focus regions | blocks drop to `opacity.editorInactiveLayer`, not hit-testable |

In windows mode all three window kinds are drawn and draggable, including
peak-focus (§7, editor exception). Creating one: drag on empty canvas, then pick
the kind from the inspector. Resizing uses the same
`size.blockResizeHandleHeight` handles blocks use.

The inactive layer never disappears. You are always editing one layer *against*
the other, because a protected window only makes sense relative to the blocks it
forbids.

### 13.4 Detached instances

An instance edited on the main grid is pinned and re-materialisation leaves it
alone. Per the ruling, **detachment is not a block signal** — it never appears on
the calendar canvas. It appears in exactly two places:

- **The inspector**, for a selected routine block on the main grid: one line,
  `inspectorLabel` / `inspectorValue`, reading `Edited — differs from Gym routine`,
  with a `Revert to routine` action.
- **The Routines window**, as a count beside the template name:
  `3 instances edited this week`, `blockMeta` / `color.text.secondary`, with a
  **Re-sync** button. Hidden entirely at zero — same rule as §10.2, no zero state.

Re-sync is destructive of the user's own edits, so it confirms: a popover
anchored to the button, `size.resyncPopoverWidth`, listing the affected dates
(`popoverRow` type, up to six then `+N`), primary action `Re-sync 3 instances`.
It is **one undo step** — see `interactions.md` §11.2.

**Amended 2026-10-05 — the Re-sync popover's geometry (closes G-034).**

- It is a **system popover** (SwiftUI `.popover`, `NSPopover` underneath), arrow
  edge `.bottom` preferred, so the arrow points up at the button. A system popover
  is its own window: it is never clipped by the Routines window's edge and
  repositions itself at the screen edge. The 2026-10-05 capture shows it cut off at
  the window's trailing edge, which means it is being drawn as an in-window
  overlay; that is a defect, not a geometry choice.
- Insets `spacing.lg` horizontal, `spacing.md` vertical — the menu bar popover's
  own family, as built.
- Date rows `popoverRow`, `color.text.primary`, `spacing.xxs` apart. Date form
  `Tue 6` (`shortStandaloneWeekdaySymbols` + day number).
- The overflow row `+2 more` — **with** `more`, matching §15.2's `+N more` — in
  `popoverRow` / `color.text.secondary`. Shown only beyond six rows.
- The primary action sits `spacing.md` below the last row, is the native default
  button (`↩` triggers it, `⎋` dismisses the popover), and is the only button.
  Cancelling is dismissing.
- **Amended 2026-10-06 (G-040, DEVIATIONS B34).** `⎋` dismisses the popover
  **whenever it is open** — with key focus on the button, on the popover, or
  anywhere inside it — writing nothing, and focus returns to the `Re-sync`
  button. The build answers `↩` and ignores `⎋`, which leaves a keyboard user
  only two exits from a destructive confirmation: confirm it, or close the
  window. Cancelling must be as reachable as confirming. (The menu bar popover
  already closes on a real `⎋`, P2-F19, so this is a defect in this popover's
  wiring, not a platform limit.)
- **Correction 2026-10-06:** the count's copy is `3 instances edited`, with no
  "this week", as `layouts.md` §8.1 (2026-10-01) already rules and the build
  draws; the second bullet at the top of this section predates that ruling.

**Amended 2026-10-01.** This subsection specifies the *surfaces*. What actually
makes an instance detached, what marks it, how re-materialisation treats it, and
what Re-sync writes are specified in §13.7, which closes G-019, G-020 and G-021.

### 13.5 Weekday activity

Ruling this implements: G-018. A `RoutineTemplate` has `activeWeekdays`; the
canvas has seven columns. Those two facts disagree unless the window says which
columns are part of the routine, so until 2026-10-01 a block created on a
Tuesday column was silently relocated onto Monday, Wednesday and Friday.

**The underlying shape, stated once because every rule below follows from it.**
A `RoutineBlock` is not on a weekday. It is a time of day, and it runs on every
one of the template's active weekdays. The seven columns are therefore **seven
read-outs of one week-shaped pattern, not seven placement surfaces** — which is
why the same block is drawn three times for a Mon/Wed/Fri template, and why
editing any one of those three changes all three at once. That is not a bug to
hide; it is the model, and the window should teach it.

#### 13.5.1 The ruling: refuse, with the reason standing and the remedy adjacent

A create gesture on an inactive weekday column is **refused**. It does not add
the weekday, and it does not ask.

Rejected alternatives, and why:

- **Add the weekday automatically.** Activating a weekday adds *every* block in
  the template to that column. A create-drag is the cheapest, most frequently
  mis-aimed gesture in the window; letting it perform the widest change in the
  window is the wrong coupling. This is `DECISIONS.md` 2026-09-10's reasoning
  ("Apple's 'this event / all future' prompt taxes the most frequent
  interaction") read from the other side: do not let the frequent gesture carry
  the rare, expensive decision either.
- **Ask.** A prompt on a drag is the same modal tax, with an extra click.

A refusal is only unacceptable when it is a dead end. This one is not: the
reason is on screen **before** the gesture is attempted and stays there, and the
remedy sits inside the column the pointer is already in. Nothing is transient,
so nothing is silent.

#### 13.5.2 How an inactive column looks

Blocks mode only (§13.5.5). Three channels, all token-only, and **the column's
ground stays `color.surface.canvas`**:

| | Active column | Inactive column |
|---|---|---|
| Ground | `color.surface.canvas` | `color.surface.canvas` — **unchanged** |
| Hour lines | `color.separator.hour` | `color.separator.halfHour` — hour and half-hour lines both |
| Day divider | `color.separator.dayDivider` | unchanged |
| Window layer | §7 as drawn | §7 as drawn, **full strength** |
| Header underline | `size.borderEmphasis` in the template's `color.source.<slot>.rail` | none |
| In-column note | none | §13.5.3 |

**Do not sink the ground.** `color.surface.canvasSunken` was the obvious choice
and is wrong: measured against `color.window.protectedFill` it leaves 1.01:1 in
light appearance, so a protected window drawn on a sunken column disappears
exactly where the user most needs to see it (a Saturday morning inside Sleep).
Dropping the hour lines to half-hour weight recedes the column without touching
the ground the window treatments are calibrated against.

**The header marks activity positively.** Active days gain the underline; the
inactive ones are not degraded. The weekday symbol stays `dayHeaderWeekday` /
`color.text.secondary` in both cases — `color.text.tertiary` is barred for
anything the user must read (`tokens.json` `$meta.contrastPairs.note`), and a
weekday header is read. The underline is `size.borderEmphasis` (1.5) tall, drawn
at the header's bottom edge directly above its `color.separator.region` hairline,
full column width, in the template's own rail colour. Hue here is the template's
hue, which §13.1 already makes the one hue in this window.

Window labels keep §7's rule unchanged: once, at the window's top edge, in the
**leading** day column — whether or not that column is active. A `TimeWindow`
carries its own `weekdays` and has nothing to do with the template's set.
**Amended 2026-10-05:** when that leading column is inactive, §7's stacking rule 3
puts the label directly below this column's note (closes G-025).

**Amended 2026-10-05 — Increase Contrast (closes G-026).** Under Increase Contrast
active columns' hour lines become `color.separator.strong` (§11). Inactive
columns step up by the same one notch and use **`color.separator.hour`** for hour
and half-hour lines both — the weight active columns have in the standard mode.
Keeping `halfHour` literally would leave an Increase Contrast user, the person
who asked for more structure, with an inactive column whose lines measure
1.14:1 against canvas in light appearance (1.13:1 dark) beside active lines at
3.25:1 — functionally no grid at all. `separator.hour` measures 1.28:1 / 1.31:1. The
recess is a relative statement (inactive is one step lighter than active), and
it survives the mode change only if both sides move together. The note (§13.5.3)
and the missing header underline still carry the state on their own; the lines
are the third, redundant channel, never the only one.

| | Standard | Increase Contrast |
|---|---|---|
| Active column, hour lines | `color.separator.hour` | `color.separator.strong` |
| Inactive column, hour and half-hour lines | `color.separator.halfHour` | `color.separator.hour` |

#### 13.5.3 The in-column note

One note per inactive column, pinned to the **top of the visible region** of its
own column — the same pinning rule a scrolled-past window label uses (§7) and for
the same reason: a note that scrolls away is a note that is not there when the
gesture is attempted. Inset `spacing.xs` from the column's leading edge and
`spacing.xs` from the top of the visible region. Maximum width
`size.inactiveDayNoteMaxWidth` (76), so it fits inside
`size.routineEditorColumnMin` (84) with its inset.

Two elements, stacked `spacing.xxs` apart:

1. `Not in this routine` — `inactiveDayLabel` type, `color.text.secondary`,
   wrapping to two lines. Measured 6.42:1 / 7.54:1 on `color.surface.canvas`.
2. `Add Sat` — a text button, `editorModeLabel` type,
   `color.interactive.accent` (4.56:1 / 6.03:1 on canvas, now a checked pair in
   `tokens.json`), underlined, cursor `.pointingHand`. On hover a
   `color.interactive.hoverOverlay` rounded rect at `radius.chip` with
   `spacing.xxs` padding. The weekday is the same `shortWeekdaySymbols` form the
   header uses, so the button names the column it is in.

No glyph, in either element. The symbol vocabularies are closed (§10.1) and this
is chrome in a window that already has two of them.

**Copy is exact.** `Not in this routine`, not "inactive", not "disabled", not
"no blocks". The user did not disable anything; this weekday is simply not part
of this routine, and the next sentence tells them how it could be.

#### 13.5.4 Activation

Three paths, one write:

- the `Add Sat` button (§13.5.3);
- the weekday toggle row in the editor inspector with nothing selected
  (`layouts.md` §8.1) — the keyboard path, so the pointer path is not the only
  one;
- removal only: toggling an active weekday off in that same row.

One named undo step each: `Add Saturday to Routine` / `Remove Saturday from
Routine`, spelled with the weekday's full name (`standaloneWeekdaySymbols`) so
the Edit menu reads as a sentence.

On activation the column's hour lines return to `color.separator.hour`, the
header gains its underline, the note disappears, and **every block in the
template appears in the column at once**, over `motion.viewChange` (0.16,
easeInOut, opacity only). That simultaneous arrival is the point: it is the
clearest available statement of what a weekday set means, and it happens in the
same frame as the click, so the width of the change cannot be missed. Under
Reduce Motion it is an instant swap, per that token's own entry.

Deactivation runs the same transition in reverse. It is not confirmed — nothing
is destroyed (the blocks belong to the template, not the column) and `⌘Z` is one
press away. What happens to instances **already materialised** on that weekday is
§13.6.4's job, not this one's.

**Amended 2026-10-05 — the last active weekday (closes G-027).** Removing it is
**allowed**, exactly as built: `Remove Friday from Routine` leaves an empty
`activeWeekdays`, every column shows its note with its own `Add <Day>` button,
the template produces nothing, and one `⌘Z` restores the day. No confirmation
and no special copy. Reasons:

- A template with no days is a **paused routine** — a real thing a person does in
  exam weeks or on holiday. Refusing it forces them to delete blocks they intend
  to bring back.
- Nothing is destroyed. The blocks belong to the template and the summary still
  reads `Blocks 5`; future instances are withdrawn by §13.6.4 inside the same
  undo step, exactly as for any other weekday.
- The state is self-explaining: seven notes, seven adjacent remedies. A refusal
  would need a reason surface this one does not.

**A `TimeWindow` is the opposite case, and is refused.** A window with an empty
`weekdays` set is drawn in no column, so it can never be selected or edited again
— it would be an invisible object in the store. In the window inspector's toggle
row the last remaining active toggle is therefore **disabled** (system disabled
appearance), with help text `A window needs at least one day. Delete it instead.`
The reason stands before the gesture, per §13.5.1's standard for a refusal, and
the remedy (`⌫`) is the ordinary one. This replaces the build's silent refusal.

#### 13.5.5 Scope: Blocks mode only

Every rule in §13.5 applies in **Blocks mode** and in no other mode. In Windows
mode all seven columns are first-class editing surfaces: no note, no line
reweighting, and no header underline at all — a `TimeWindow`'s `weekdays` is its
own set, unrelated to `activeWeekdays`, so a protected window on a Saturday is
perfectly ordinary and must be editable whether or not the routine runs then.
Showing the template's weekday state while the template is not the edited layer
would mark the wrong thing.

### 13.6 Materialisation

What `RoutineEngine.materialize` may and may not do. Nothing here is a visual
value; it is the behaviour the surfaces in §13.4, §13.5 and §13.7 describe, and it
is specified here because the rules are what make those surfaces truthful.

#### 13.6.1 Protected windows: refuse, never place, never shift

`CONTEXT.md`: *"Protected time windows are never scheduled into automatically."*

**"Place it, then surface a conflict" does not satisfy that rule** (closes
G-023). If after-the-fact surfacing counted as compliance, the rule would have
no content — every violation could be excused by a badge, and the brief's Phase 6
posture ("validate and reject the plan rather than trusting the model to have
obeyed") would be arguing with its own Phase 2. Materialisation is an automatic
process. It refuses.

1. For each `(block, date)` pair, materialisation computes the pair's interval
   and compares it against every `.protected` `TimeWindow` span on that date.
2. Any overlap — strict, touching endpoints do not count, the same test
   `ConflictEngine` uses — means **no event is created for that pair**.
3. It does **not** trim the pair to the non-overlapping remainder, and it does
   **not** shift it clear. Both are an automatic process choosing a time, which
   is the thing the rule forbids and the thing "the assistant proposes, the user
   disposes" forbids twice.
4. `.lowEnergy` and `.peakFocus` windows never block materialisation. They are
   preferences the planner reads in Phase 6; only `.protected` is a hard
   constraint, and only `.protected` is named by the rule.

Manual action is untouched: `interactions.md` §4's "Dropping into a protected
window is allowed" stands, for exactly the reason stated there — that rule binds
automatic placement, not a user being explicit.

#### 13.6.2 A refusal is never silent

A refused pair means a block the user wrote into their routine will never run.
That is the definition of something needing attention, so it surfaces in three
places and the first two are in the window where the cause lives:

- **The Routines window canvas.** A block whose interval overlaps a `.protected`
  span takes the §6 **`conflicted`** presentation, in exactly the columns where
  it collides and no others. This needs no materialisation to compute — template
  interval versus window span is a static comparison — and it introduces no new
  component: the alert border at `size.borderEmphasis` and the
  `exclamationmark.triangle.fill` badge already mean precisely this.
- **The editor inspector**, for that selected block: one line,
  `inspectorLabel` / `inspectorValue`, reading
  `Will not run — inside Sleep (protected) on Mon, Wed, Fri`. The window's label
  and the colliding weekdays, both named. Never "blocked", never "error".
- **The needs-attention count** (§10.2) in the main window, which is what keeps
  this off the list of things the user has to remember to go and check. See
  §14.6 for what activating it does.

#### 13.6.3 Re-materialisation keeps untouched instances current

The brief requires re-materialisation "when a template changes without
destroying manual edits". Creating-only is not enough: a block moved from 07:00
to 07:30 in the template must move on the calendar too, or the template is not
the baseline it claims to be (closes G-020).

Per `(block, date)` pair inside the horizon (§13.6.5):

| Pair state | Re-materialisation does |
|---|---|
| No event exists, no tombstone | create it — unless §13.6.1 refuses |
| Event exists, **not** detached | **update** start, end, title and flexibility to the template's current values |
| Event exists, **detached** (§13.7) | leave it completely alone |
| Event exists, tombstoned (§13.7.4) | leave it deleted — do not recreate |
| Template no longer produces the pair | §13.6.4 |

An update carries the event's own `status` (`.done` / `.skipped`) forward
unchanged. Status is a fact about a day, never a divergence from a routine.

**Amended 2026-10-05 (closes G-033) — the full table over the three link states
of §13.7.2.** "Detached" above means `routineLink == .detached`.

| Pair state | Re-materialisation does |
|---|---|
| No event, no tombstone | create it `linked` — unless §13.6.1 refuses |
| Event `linked` | update the four template-owned fields |
| Event `detached` | leave it completely alone |
| Event `released`, and the template **produces the pair again** | **rejoin:** set `routineLink` to `detached`; touch nothing else |
| Event `released`, pair still not produced | leave it completely alone |
| Tombstoned | leave it deleted |
| Template no longer produces the pair | §13.6.4 |

**Rejoin** is what happens when a weekday comes back (`Add Saturday to Routine`),
a deleted block's delete is undone, or a protected window stops refusing the pair.
The kept instance becomes **detached, not linked**: the user edited that day, and
§13.7.1's own rule is that a deliberate edit is not silently re-adopted. It keeps
its start, end, title, flexibility and status; it reappears in the `N instances
edited` count; its inspector line returns to `Edited — differs from …` with
`Revert to routine`; and Re-sync may now restore it. **The template never creates a
second instance beside it** — the pair already has an event, keyed by the same
`(sourceID, externalID)`, which is exactly what the "Event exists" rows test.

Rejoin is recorded in the step that caused it when that step is a user action
(the same fold as §13.6.4's withdrawal, so `⌘Z` on `Add Saturday to Routine`
releases it again), and unrecorded when a background pass performs it (§13.6.5
triggers are not user actions). It never writes to an instance before
`startOfDay(today)`: a released instance in the past stays released, because
§13.6.5 has no exceptions and a flag is a write.

#### 13.6.4 Withdrawal: when the template stops producing a pair

A weekday is deactivated, a block is deleted from the template, or §13.6.1
starts refusing a pair that it previously created. In every case:

- **Future, non-detached instances are deleted.** A routine that no longer
  contains Saturday should not leave Saturdays on the calendar; leaving them
  would make the template a lie in the other direction.
- **Detached instances are kept**, and they stop being detached — there is no
  longer a template pair for them to differ from. They become ordinary
  `.routine`-origin events, keep their `(sourceID, externalID)`, and §13.4's
  inspector line is replaced by `No longer part of Gym routine`, with no
  `Revert to routine` action, because there is nothing to revert to.
  **Amended 2026-10-05 (G-033):** "stop being detached" means `routineLink`
  becomes `.released` (§13.7.2), not `.linked`. A `.released` instance is never
  withdrawn, never updated, never counted as edited and never reverted. If the
  template later produces its pair again it rejoins as `.detached` (§13.6.3).
- **Past instances are never touched**, detached or not. See §13.6.5.

All of a single withdrawal is **one named undo step**, folded into the step that
caused it — `Remove Saturday from Routine` undoes the deletions as well as the
weekday, in one `⌘Z`. Same reasoning as `interactions.md` §11.2: an undo that
only partly undoes is worse than none, because the user stops pressing before
they are whole.

#### 13.6.5 Horizon, triggers, and the past

- **Materialisation never writes to any day before `startOfDay(today)`** — not a
  create, not an update, not a delete. The past is a record. This is the one rule
  in §13.6 with no exception anywhere.
- **Horizon:** today through the later of `today + 28 days` and
  `(the main window's visible range's end) + 7 days`. The 7-day lead means paging
  forward never shows an empty week that fills in after a beat.
- **Triggers:** app launch; any edit to a template, a block or a `TimeWindow`;
  and a change to the main window's visible range. It is idempotent, so a
  trigger firing twice costs nothing.

### 13.7 Detachment, re-sync and deletion

Rulings this implements: `DECISIONS.md` 2026-09-10 "Routine instances edit
instance-only, no dialog", plus G-019 and G-021. §13.4 specifies the surfaces;
this is what they describe.

#### 13.7.1 What detaches an instance

Detachment means "this instance differs from the routine, deliberately, and
re-materialisation must not overwrite it." The test is therefore not "was this
event touched" but **"does this edit change something the template owns"**.

| Main-grid edit | Detaches |
|---|---|
| Move (drag, `⌥↑`/`⌥↓`, `⌥←`/`⌥→`) | **yes** |
| Resize (drag, `⌥⇧↑`/`⌥⇧↓`) | **yes** |
| Retitle | **yes** |
| Change flexibility | **yes** |
| Mark done / undone | no |
| Mark skipped / unskipped | no |
| Applying a conflict option (`§14`) | per the option's own edit — `.shiftLater` and `.shorten` detach, `.skipToday` does not |
| Notes, location, lock | no |
| Delete | not detachment — §13.7.4 |

Start, end, title and flexibility are the four fields the template owns, so
exactly those four detach. `status` does not: `done` and `skipped` are facts
about one day, and if `skipped` detached, then every `.skipToday` conflict
resolution would detach an instance and `Re-sync` would offer to undo the user's
own conflict resolutions — which is backwards. Notes, location and lock are not
template-owned, so the template has nothing to say about them.

An instance that is edited back to the template's values **stays detached**. The
user made this day explicit; matching by coincidence is not the same as being
generated, and silently re-adopting it would mean a later template edit moves a
day the user had pinned.

#### 13.7.2 What marks it

One persisted flag on the instance, set at the moment of a §13.7.1 edit and
cleared only by Re-sync (§13.7.3), `Revert to routine` (§13.4), or withdrawal
(§13.6.4). Nothing else is stored:

- The **affected date** that §13.4's popover and `interactions.md` §11.2 list is
  the instance's own day. It is not a second field.
- The **template's values** are read live from the `RoutineBlock`, which still
  exists. `Revert to routine` and `Re-sync` therefore restore the template's
  *current* values, not the values in force when the instance was detached. That
  is the predictable reading — "re-sync" means "make this match the routine as it
  is now" — and it is the only one that does not require a second copy of every
  template field per instance.

**Amended 2026-10-05 — one field, three values (closes G-033).** "One persisted
flag" is **one persisted field**, `routineLink`, with exactly three values. The
build's shape is adopted:

| Value | Meaning | Set by | Inspector line |
|---|---|---|---|
| `linked` | generated, untouched; re-materialisation updates it | creation; Re-sync; `Revert to routine` | none |
| `detached` | the user changed a template-owned field; leave it alone | a §13.7.1 edit; rejoin (§13.6.3) | `Edited — differs from Gym routine` + `Revert to routine` |
| `released` | its pair was withdrawn while it was detached; kept as the user's own | withdrawal (§13.6.4) | `No longer part of Gym routine` |

A boolean cannot hold this. After withdrawal clears a two-valued flag, the kept
instance is indistinguishable from an untouched future instance of a withdrawn
pair — and §13.6.4 deletes exactly those, so the next pass of any trigger would
delete the instance withdrawal was specified to keep. The third value is the
memory that it was kept on purpose. Every transition is recorded in the step
that causes it, so `⌘Z` restores the previous value exactly. Manual and
hand-seeded events have no link value at all.

The flag is **not** a block signal. `DECISIONS.md` 2026-09-10 settled that: every
channel on the grid is spent, and detachment matters when reasoning about the
routine, never when reading Tuesday.

#### 13.7.3 Re-sync

Scope, which §13.4's `3 instances edited this week` left open (closes G-021):
**the detached, non-tombstoned instances of this template whose day falls in the
horizon (§13.6.5), from `startOfDay(today)` forward.** Past detached instances
are neither counted nor re-synced — §13.6.5 has no exceptions.

The count's copy therefore changes: `3 instances edited` and
`1 instance edited`, with no "this week". The old string named a scope the
feature does not have, and the popover lists the actual dates anyway. Still
`blockMeta` / `color.text.secondary`, still hidden entirely at zero.

The popover (§13.4) lists those dates, up to six then `+N`; the primary action
reads `Re-sync 3 instances` / `Re-sync 1 instance`. Applying it sets start, end,
title and flexibility back to the template's current values for every listed
instance, clears every flag, and leaves `status` alone. One undo step,
`Undo Re-sync Routine` (`interactions.md` §11.2).

`Revert to routine` (§13.4, one selected instance in the main-grid inspector)
does exactly the same thing to exactly one instance. Its undo step is named
**`Revert Instance to Routine`** — a distinct name, because the two are different
sizes of damage and the Edit menu is the only warning the user gets.

#### 13.7.4 Deleting an instance leaves a tombstone

`⌫` on a materialised routine instance currently removes the row, and the next
re-materialisation pass finds no event for that `(block, date)` pair and creates
it again. The block comes back on its own. That is the same class of silent
behaviour as the weekday defect, and it is closed the same way (part of G-019).

**Deleting a materialised instance records that the pair was deleted**, and
re-materialisation never recreates a tombstoned pair (§13.6.3). The record is
keyed by the same `(sourceID, externalID)` pair the instance had, so it needs no
new identity scheme.

- It is **not** detachment and does not appear in the detached count. A deleted
  day is not an edited day; there is nothing to re-sync it to.
- `⌘Z` restores the instance **and** removes the tombstone, in the one step
  `interactions.md` §5 already names.
- Re-sync does not resurrect tombstoned pairs. Deleting the block from the
  template, or deactivating the weekday, makes the tombstone irrelevant and it
  may be discarded.
- Tombstones before `startOfDay(today)` are never consulted, because nothing
  materialises into the past (§13.6.5).

**Amended 2026-10-05 — a tombstone's lifetime (closes G-031).** The "may be
discarded" above is withdrawn. **A tombstone is removed only by undoing the delete
that created it.** Deactivating the weekday, deleting the block, or any other
template edit leaves it in place. So: delete Saturday 10's Gym, remove Saturday,
add Saturday back — Saturday 10 has **no** Gym. The user deleted that day; an
unrelated toggle must not bring it back, and the alternative would make the
outcome of `Add Saturday` depend on what the user did to one Saturday weeks ago,
which nothing on screen records. A user who does want that day back creates it,
or undoes the delete. A tombstone whose day is before `startOfDay(today)` is
inert and may be pruned silently — that is unobservable, so it is an
implementation choice, not a behaviour.

---

## 14. Conflict resolution

Rulings this implements: `DECISIONS.md` 2026-09-10 "Conflict resolution previews
in place, not in a sheet", plus the abandonment ruling of the same date.

### 14.1 Entry point

The needs-attention row (§10.2) is a button. Activating it selects the first
unresolved conflict and puts the inspector into conflict mode. There is no
separate list view and no sheet.

**Amended 2026-10-05.** Two things activation also does, both specified in
`interactions.md` §10.1's 2026-10-05 amendment: it **brings the conflict into
view** on the canvas (page to its day, scroll so it is visible), and it **focuses
the recommended option** — or the only option — which previews it at once. A
preview of a block scrolled out of sight is not a preview, and the 2026-10-05
captures show exactly that: every main-window conflict frame has its affected
block at or below the bottom edge of the viewport.

### 14.2 The collision header

Top of the conflict panel: the two colliding blocks rendered as **real blocks**
at the `.titleOnly` tier (18–27, §3.3), stacked with `spacing.xs` between them and the word
`overlaps` between them in `inspectorLabel` / `color.text.secondary`. Same style
resolver, same hue, same rail — so the thing in the panel is recognisably the
thing on the grid.

Below them, the overlap itself: `13:00–14:30 · 45 min overlap`, `blockMeta`.

**Amended 2026-10-01 — when the other side is a window, not a block (closes
G-024).** A protected-window collision has no second block to render, and a
`TimeWindow` must not be drawn as one: a block means content, and §7 spends its
whole argument on windows being canvas. The lower half of the header is instead a
**window row**: full panel width, the same height the `.titleOnly` tier gives the block
above it, filled with the window's own §7 treatment — `color.window.protectedFill`
with its `color.window.protectedEdge` lines at top and bottom — carrying two
labels, `windowLabel` / `color.window.label` for the window's own label and
`blockMeta` / `color.text.secondary` for `protected · 22:00–07:00`. No hue, no
rail, no glyph, no corner radius: it is a slab, because that is what it is on the
grid.

The word between the two becomes **`lands in`**, not `overlaps`. Two blocks
overlap each other symmetrically; a block lands in a window, and the asymmetry is
the whole point of the rule being broken.

Under Increase Contrast the row takes §7's override (`color.window
.protectedEdgeHC` on all four sides) for the same reason the grid does.

**Amended 2026-10-05 — the window row's label placement (closes G-036).** As
built: both labels on one baseline, leading inset `size.blockPadding`, trailing
inset `size.blockPadding`, `spacing.sm` between the two labels, vertically centred
in the row. When the pair does not fit on one line the second label truncates
tail-first; the window's own label never truncates before it, because the label
is the noun and `protected · 12:00–13:00` is recoverable from the window
inspector.

**Amended 2026-10-05 — the header's horizontal inset (spec side of DEVIATIONS
B20).** The collision header, the overlap line, the option rows and the footer
all sit inside the inspector's content inset — `spacing.xl` from **both** edges of
the inspector (`layouts.md` §6). No element of the panel touches the inspector's
edge. The 2026-10-05 captures show the collision blocks and the overlap line flush
against the leading edge, and the ordinary inspector's labels losing their first
letter (`tarts`); that is the build clipping its content, not a value to keep.

### 14.3 The option row

Two or three per conflict. Minimum height `size.conflictOptionRowMinHeight`,
`size.conflictOptionGap` between rows, radius `radius.card`, fill
`color.surface.canvasSunken`, selected fill `color.interactive.selectedRowFill`.

Three lines:

1. **Title** — `conflictOptionTitle`, imperative and concrete:
   `Shift Training 90 min later`.
2. **Disturbance** — `conflictOptionDelta`, `color.text.secondary`. This is the
   ranking made legible, so it is required, not optional:
   `Training 17:00 → 18:30 · nothing else moves` /
   `moves 2 blocks, shortens 1`.
3. **Recommendation chip**, on the recommended option only.

**The recommendation is marked with the word `Recommended`, not a colour and not
a glyph.** `blockMeta` type, `color.text.secondary` on
`color.surface.canvasAlt`, radius `radius.chip`, padding `spacing.xs`. Colour is
spent on source and the glyph vocabularies are closed (§10.1); a word costs
nothing and survives greyscale, which is exactly the §1 rule applied to chrome.

Options are ordered by disturbance, least first. The recommended one is usually
but not necessarily first — when it is not, the ordering still reads as a ranking
because line 2 says why.

**Amended 2026-10-05 — the selected row, and where the chip goes (closes G-038).**

*Selected row.* `color.interactive.selectedRowFill` is a **solid** accent, and
nothing in this file paired text with it. Measured: line 2's
`color.text.secondary` on it is **1.41:1** light / **1.25:1** dark, and even
line 1's `color.text.primary` is 3.81:1 / 2.52:1 — the selected row was the least
readable thing in the panel at the moment it mattered most. Solid accent with
white text is right for a one-line list row; it is wrong for a three-line card
whose second line is the ranking's explanation. So the option row does **not**
use `selectedRowFill`. A selected (focused) option row is:

- fill **`color.interactive.selectedCardFill`** (new, `#E3EDFF` / `#1F3352`), a
  low-chroma accent tint;
- a `size.borderSelected` (2) inner border in `color.interactive.focusRing`,
  following `radius.card` — **this border is what carries selection**; the tint
  only reinforces it (fill against `canvasSunken` is 1.04:1 light, by design not
  a carrier);
- text colours **unchanged**: line 1 `color.text.primary` (14.75:1 / 11.36:1),
  line 2 `color.text.secondary` (5.44:1 / 5.63:1). Selection never changes what
  colour the words are, so no on-selected text token is needed.

The rule binds both conflict panels (main inspector and Routines editor
inspector) through the shared row. `selectedRowFill` keeps its job for list rows
elsewhere.

*The chip is line 3.* The three-line list above is normative and the build put
the chip on line 1's trailing edge instead. Beside the chip at
`size.editorInspectorWidth` a §14.6 title truncates
(`Shift Errands 30 min later in the…`), and the title column stays narrow even
on rows without a chip (`Remove Errands from` / `this routine`). The chip goes on
**its own line below line 2**, leading-aligned with lines 1 and 2, `spacing.xs`
above it. Line 1 then has the full row width and `conflictOptionTitle`'s two-line
limit is enough for every title in §14.3.4 and §14.6 at both inspector widths.
A title is never truncated: if a future title needs a third line at the
narrowest width, that is a copy defect to fix in this file, not a truncation to
accept.

**Amended 2026-10-01 — the option catalogue, the cap, the ranking, the
recommendation and the exact copy. Closes G-017.**

G-017 reported that the engine can only ever produce one or two options and can
only ever recommend the first. Both halves are resolved by specifying the thing
§14.3 had left to the engine, rather than by relaxing §14.3 to match it: the brief
asks for "2–3 concrete resolution options ranked by how little they disturb the
day, with one marked recommended", and the brief's own worked example names the
three — *"shift training 90 min later", "shorten it to 45 min", "skip today"*.
The engine's shortfall is not that three is too many; it is that it gates
`shorten` behind `flexibility == .fixed` for no reason the spec ever gave. A
block being shiftable does not make it unshortenable.

#### 14.3.1 The catalogue

Exactly three kinds, in this **kind order** (used as the tie-break everywhere
below):

| Kind | Available when | Disturbance |
|---|---|---|
| `shiftLater` | `flexibility == .shiftable`, and the smallest 15-minute-stepped later shift that clears the collision is ≤ the block's ± minutes | minutes moved |
| `shorten` | **any** flexibility, and the larger of the two non-overlapping remainders is ≥ 15 min | minutes trimmed |
| `skipToday` | always | the occurrence's full duration in minutes |

Three consequences, all intended:

- `.shiftable` now reaches **three** options in the ordinary case.
- `.droppable` now reaches **two** (`shorten` + `skipToday`) instead of one. A
  single take-it-or-leave-it row is not "decisions come with defaults"; it is an
  ultimatum with a chip on it.
- `.fixed` reaches two, which §14.3's "two or three" always permitted.

**`shiftEarlier` is deliberately not in the catalogue.** `Flexibility
.shiftable(±minutes)` in the brief's data model is two-sided, and an earlier
shift is almost always the cheapest option on the disturbance scale — which is
exactly why it is wrong here. A routine block is a habit anchored to a time of
day; moving breakfast earlier is not a cheaper version of moving it later, and a
ranking that offered it first would recommend the least achievable thing most of
the time. The field stays two-sided for the Phase 6 planner, which has the
energy-window information needed to judge an earlier slot. Phase 2 does not.

#### 14.3.2 Cap and order

- **Cap: three.** The catalogue cannot exceed it, so no option is ever dropped.
- **Display order: ascending `disturbanceMinutes`; ties broken by kind order.**
  This is the brief's ranking, unchanged.
- **`skipToday` is never removed**, whatever else is present. It is the no-guilt
  escape, and `.droppable`'s only honest resolution.

#### 14.3.3 The recommendation rule

Disturbance-minutes answers "how little does this disturb the day". It does not
answer "which of these should I pick", because it is blind to *what kind* of
thing is being spent. Twenty minutes trimmed off a 45-minute gym session is not
20 minutes of disturbance in the same sense as a 20-minute shift: one keeps the
session, the other dismantles it. So the recommendation reads the kinds, in this
order, and takes the first that qualifies:

1. **`shiftLater`**, if available and `disturbanceMinutes ≤ the occurrence's own
   duration`. Moving a block by no more than its own length is proportionate;
   moving a 30-minute coffee by two hours is not, and at that point it is not the
   same coffee.
2. **`shorten`**, if available and the kept duration is `≥ half` the original.
   Half a session is still the session. A quarter of one is a different activity
   with the same name.
3. **`skipToday`**, otherwise. When nothing can be preserved proportionately, the
   honest recommendation is the one that puts the block back in the pool.

Exactly one option carries the chip. **A single-option conflict carries no chip
at all** — a recommendation among one is noise, and the footer's `1 of N`
(`layouts.md` §10) already says where the user is. That case is reachable: a
`.fixed` occurrence wholly contained in the other event has no remainder to keep
and cannot shift, so `skipToday` stands alone.

This rule **does** diverge from the display order in reachable cases, which is
what §14.3's "usually but not necessarily first" was always describing. Worked
example, and the fixture §17 item 7 uses: a 90-minute `.shiftable` occurrence at
17:00–18:30 with ±90, colliding with a 17:30–18:15 event — `shorten` trims 60,
`shiftLater` moves 75, `skipToday` costs 90, so the rows read 60 · 75 · 90 and the
**second** is recommended, because 75 ≤ 90 keeps the whole session.

#### 14.3.4 Exact copy

Line 1, `conflictOptionTitle`, imperative, no trailing period:

| Kind | Title |
|---|---|
| `shiftLater` | `Shift Training 75 min later` |
| `shorten` | `Shorten Training to 30 min` |
| `skipToday` | `Skip Training today` |

Line 2, `conflictOptionDelta`. It must carry the number the ranking is made of
*and* what that number costs, because the recommendation can disagree with the
order and line 2 is the only place that disagreement is explained:

| Kind | Line 2 |
|---|---|
| `shiftLater` | `17:00 → 18:15 · all 90 min kept` |
| `shorten` | `90 min → 30 min · 60 min lost` |
| `skipToday` | `Does not run today · 90 min lost · re-offered` |

`re-offered` is not decoration. It is the no-guilt rule stated at the moment the
user is deciding to skip something: the block goes back in the pool, it is not
gone and it is not a mark against them.

~~Durations are always `N min` below 60 and `N h MM` at or above it
(`1 h 30`), monospaced digits throughout, times in 24-hour `HH:mm`.~~

**Amended 2026-10-05 — the tables hold; the sentence was wrong (closes G-035).**
Every duration in conflict copy — §14.2's overlap line, §14.3.4's tables and
§14.6's table — is **`N min`, at every size**: `75 min later`, `all 90 min kept`,
`135 min lost across Mon, Wed, Fri`. Monospaced digits throughout, times in
24-hour `HH:mm`. The reason is §14.3's own: line 2 is "the ranking made legible",
and a ranking is read by comparing numbers. `60 · 75 · 90` compares at a glance;
`1 h 00 · 1 h 15 · 1 h 30` makes the reader convert, and a mixed column
(`45 min` beside `1 h 15`) makes them convert twice. The tables were written with
the right instinct and the sentence under them was a generic formatting rule
pasted into the one place it does not fit. The build already matches; only its
`// SPEC-GAP` marker goes.

### 14.4 Preview in place

Focusing an option previews it on the real grid. Every block the option would
move takes the **`previewed`** presentation (§6): proposed frame at
`opacity.blockPreviewed` inside a dashed accent outline, current frame retained
as a ghost at `opacity.blockDragOrigin`.

While any preview is active the **calendar canvas** — not the sidebar, not the
inspector — carries a `size.previewCanvasBorder` inset border in
`color.interactive.accent`. That is the "you are looking at a hypothetical"
frame, and it is what stops a previewed day being mistaken for the real one at a
glance across the room.

**An option with no destination frame shows the ghost and nothing else (closes
G-014).** `skipToday` proposes no new frame, so there is no proposed frame to
draw a dashed twin at. The occurrence dims to `opacity.blockDragOrigin` exactly
as any focused option dims what it is about to change, and no `previewed` twin is
drawn. Manufacturing one at the block's own unchanged position would put a dashed
accent outline directly on top of the ghost, which reads as a rendering fault,
not as a proposal. The canvas border (above) is what says a hypothetical is
active; it is present for `skipToday` like any other option.

Nothing is written until the option is applied. Abandonment is specified in
`interactions.md` §10.2 and is unconditional.

### 14.5 Resolved and empty

When the last conflict is resolved the panel does not congratulate. It returns to
the ordinary inspector, and the needs-attention row disappears (§10.2, hidden at
zero). No "all clear" state, no checkmark screen.

**A skipped occurrence is resolved (closes G-015).** Applying `skipToday` does
not move the occurrence, so an interval test alone would report the identical
collision on the next pass and the panel could never advance. The ruling:
**a `.skipped` routine occurrence is not an overlap.** `EventStore
.toggleSkipped`'s own reading is the right one — an occurrence that has been put
back in the pool is not occupying the slot it was skipped out of, so it is not
competing for it. Status gates detection, for the `.routine` side only, and only
for `.skipped`. `.done` never gates it: a completed block really did occupy its
slot.

### 14.6 Template conflicts: a routine block that cannot run

A §13.6.1 refusal — a template block whose interval lands in a protected window —
is a conflict with no event on either side. It uses the same panel, with three
differences and no new components.

**It is not shown in the main window.** The needs-attention row counts it and is
its entry point (§13.6.2), but activating it **opens the Routines window**
(`⌘⌥R`'s window), selects the template, selects the block, and puts the *editor*
inspector into conflict mode. None of this conflict's options can be applied to a
day — they all edit the routine — so offering them over a day grid would invite
the user to fix Tuesday for a problem that is in the template.

**The collision header** is §14.2's amended form: the routine block as a real
block above, the window row below, `lands in` between them, and the overlap line
naming the weekdays it happens on — `22:30–23:15 · 45 min · Mon, Wed, Fri`.

**The options** are template-level, same row geometry, same chip, same §14.3.2
ordering (ascending disturbance, kind-order tie-break):

| Kind | Available when | Disturbance | Title | Line 2 |
|---|---|---|---|---|
| `shiftLater` | a 15-minute-stepped later start clears every colliding span on every active weekday, within `0…1440` | minutes moved | `Shift Errands 30 min later in the routine` | `12:30 → 13:00 · all 45 min kept · every active day` |
| `shiftEarlier` | same, earlier | minutes moved | `Shift Errands 75 min earlier in the routine` | `12:30 → 11:15 · all 45 min kept · every active day` |
| `shorten` | the larger remainder outside every colliding span is ≥ 15 min | minutes trimmed | `Shorten Errands to 15 min` | `45 min → 15 min · 30 min lost · every active day` |
| `remove` | always | duration × colliding active weekdays | `Remove Errands from this routine` | `Deletes the block · 135 min lost across Mon, Wed, Fri` |

`shiftEarlier` **is** in this catalogue, unlike §14.3.1's: here the user is
editing the shape of their week on purpose, not triaging one day under time
pressure, and an earlier slot is a perfectly ordinary thing to choose
deliberately. Cap is three: `remove` is always retained, and the other two slots
go to the lowest-disturbance remainder, kind order breaking ties.

Recommendation: §14.3.3's rule with `remove` in `skipToday`'s place — a
proportionate shift (either direction), else a shorten that keeps half, else
`remove`.

**Preview** is §14.4 on the Routines window's own canvas: the previewed block in
every active column at once, ghosts at their current frames, and the
`size.previewCanvasBorder` accent border on the Routines canvas. Applying is one
named undo step, `Resolve Routine Conflict`, and §13.6.3 re-materialises behind
it inside the same step.

---

## 15. Menu bar extra

Ruling this implements: `DECISIONS.md` 2026-09-10 "Menu bar requirement split
between status item and popover."

### 15.1 The status item

Budget `size.statusItemMaxWidth` (180). `statusItem` type, monospaced digits.

```
17:30 · Training
```

**The time comes first and is never truncated** — the time is what you scan for,
and a truncated time is worse than no title. The title truncates tail-first
inside whatever the time leaves. Below the budget the item degrades to the time
alone. No icon in the normal state; every point in a crowded menu bar is
contested and the text is the information.

**Amended 2026-10-01 — where "below the budget" is.** `size.statusItemMaxWidth`
is a budget, not a guarantee; a crowded menu bar gives the item less. The item
measures what it is actually given and:

- renders `HH:mm · Title` with the title truncated tail-first, while the space
  left after the time and the ` · ` separator is at least
  `size.statusItemTitleMinWidth` (32 — about four characters plus an ellipsis at
  `statusItem` size);
- renders the time **alone**, with no separator and no ellipsis, below that. A
  one-character stub of a title is not information; it is noise beside the one
  thing on the item that matters.

In the late state the glyph and the elapsed figure together replace the time in
this calculation — the glyph is never dropped, because without it the elapsed
figure reads as a clock time.

| State | Content | Colour |
|---|---|---|
| Normal | `17:30 · Training` | `color.text.primary` (menu bar tint) |
| Late | `clock.badge.exclamationmark` at `size.statusItemGlyphSize` + `12m ago · Training` | `color.semantic.now` |
| Empty | `Nothing left today` | `color.text.secondary` |

The late state is phrased as **elapsed**, never as a deficit — `12m ago`, never
`overdue`, `late by` or `missed`. It uses `color.semantic.now` because that
colour already means "now"; lateness is a fact about the clock, not a failure,
and this keeps red meaning one thing across the whole app. `clock.badge.exclamationmark`
appears in neither the kind-glyph tables (§2.1, §3.2, §5) nor the source symbol
table (§10.1); it must not be added to either.

The empty state says what is true and stops. No praise, no "all done", no
illustration.

**Amended 2026-10-05 — colour in the live menu bar.** The status item is
**template-rendered**: macOS draws a `MenuBarExtra` label in the menu bar's own
tint (dark or light per wallpaper and appearance), and it flattens the label to
one image plus one string (STATUS §48). The 2026-09-27 live crops show the late
state in that tint, not red. The build must **not** force non-template rendering
to get colour back — a fixed colour fights the menu bar's own appearance logic
and can fail contrast against a light wallpaper. So the Colour column above
applies to the popover and to offscreen renders only. In the live bar the three
states are carried by **content**, which is why the rules above already make
them self-sufficient: the late state by `clock.badge.exclamationmark` plus the
`… ago` phrasing (the glyph is never dropped, for exactly this reason), the empty
state by its words. Colour was always the redundant channel here; §1 forbids it
being the only one.

### 15.2 The popover

Width `size.popoverWidth` (300). This is where "legible from across the room"
lives, because a 22pt menu bar cannot carry it.

```
+------------------------------------------+
|  NEXT                                    |   popoverSectionLabel
|                                          |
|  Training                                |   popoverNextTitle, 20pt
|  17:30 – 18:15 · Gym                     |   popoverNextMeta, 15pt
|                                          |
|  [ Done ]  [ Snooze ]  [ Open ]          |   popoverActionRowHeight
|------------------------------------------|
|  REST OF TODAY                           |   popoverSectionLabel
|  18:30  Code review                      |   popoverRow, 13pt
|  20:00  Dinner                           |
+------------------------------------------+
```

- The next item's block is at least `size.popoverNextBlockMinHeight` tall and
  carries its source hue as a 3pt leading rail — the only colour in the popover.
- Rest of today: `size.popoverRestRowHeight` rows, at most
  `size.popoverMaxRestRows`, then `+N more`. Times are monospaced and
  left-aligned in a fixed column so the list scans vertically.
- **It is not a second calendar.** No hour grid, no durations, no overlap
  rendering, no all-day items.

| State | Next section | Rest section |
|---|---|---|
| Normal | as above | list, or omitted entirely when empty |
| Late | title unchanged; meta becomes `Started 12m ago · Gym` in `color.semantic.now`; actions gain a leading `Re-offer` | unchanged |
| Empty | `Nothing left today`, `popoverNextTitle`, `color.text.secondary`, no actions | omitted |

The late popover always offers `Re-offer`, because the no-guilt rule means a
missed item is put back in the queue rather than counted against you. `Re-offer`
is the primary action in that state.

**Amended 2026-10-05 (Phase 2 screenshot review).**

- **The meta line names the source**, as built: `17:30 – 18:15 · Daily routine`,
  `Started 12m ago · Daily routine`. The `· Gym` in the sketch and table above was
  ambiguous (a place or a source) and is replaced. The source name is what §3.4
  requires wherever hue is shown, and the rail is the popover's only hue. Location
  joins the line in Phase 3 with the leave-by time and is not specified here.
- **`Open` is always enabled.** It activates the main window, opening it if it is
  closed, and selects the next item there. Every 2026-10-05 popover frame — and the
  2026-09-27 live one — draws it disabled; a disabled `Open` in a popover whose
  last-resort job is "take me to the app" is a dead end.
- **`Re-offer` is drawn as the primary action** in the late state: the native
  default / prominent button style (`.borderedProminent`, accent), leading. It takes **no** key
  equivalent: `↩` in the popover already opens the focused item
  (`interactions.md` §12), and that binding stands. The others stay `.bordered`.
  The captures draw all four identically, so nothing on screen says which one
  is primary.
- `Done` / `Snooze` / `Open` keep `.bordered` in the normal state; there is no
  primary there, because none of the three is the default answer to "what now".

---

## 16. Snooze confirmation

Ruling this implements: `DECISIONS.md` 2026-09-10 "Snooze confirmation is
designed in Phase 2, not Phase 4." The surface is specified now; no scheduling
logic exists until Phase 4.

It must show **where the block landed**, not that something happened. It is not a
dialog and it does not steal focus.

- In the popover, the action row is replaced in place by a result row of the same
  height: `Moved to 19:15` + `Undo`, `popoverRow` type. Across a day boundary it
  names the day: `Moved to tomorrow 09:00`.
- It holds for `motion.snoozeConfirmHold` (4s), **pausing while hovered**, then
  the popover returns to its normal state. `Undo` remains available afterwards
  through `⌘Z` in the main window.
- If the main window is open and showing the destination day, the block-move
  transition (`interactions.md` §7.1) runs there at the same time. The
  confirmation and the movement are the same event seen from two places.
- Never a sheet, never an alert, never a toast that outlives the popover.

**Amended 2026-10-06 (Phase 2 re-review; G-046) — a snooze never lands in
protected time.** G-016's placeholder moves the block a fixed 15 minutes, and
nothing stops that destination being inside a `.protected` window:
`snooze-next-day-p2t48.png` shows `Prep: relational algebra` moved to
`00:05 – 01:35`, inside `Sleep` (22:00–07:00). The user asked for *later*; they did
not choose *where*, so the destination is chosen automatically, and CONTEXT.md's
hard rule — protected windows are never scheduled into automatically — applies to
it exactly as `DECISIONS.md` 2026-10-01 applies it to materialisation ("refuses …
does not trim and does not shift: both are an automatic process choosing a time").
The placeholder stays a placeholder; it gains the same refusal, not a search:

- If the snoozed interval would **strictly overlap** any `.protected` span on the
  destination day(s) (§13.6.1's test, using `TimeWindow.spans(on:)`, so overnight
  windows count on both days), **nothing is written**. No undo step is recorded.
- The result row still replaces the action row, same height, same hold
  (`motion.snoozeConfirmHold`, pausing on hover): `Not moved — 00:05 is inside
  Sleep (protected)` — `popoverRow`, `color.text.primary`, **no `Undo`** (there
  is nothing to undo). The time is the destination start that was refused, in the
  same `HH:mm` form; an empty window label reads `inside a protected window`. The
  phrasing is §13.6.2's `Will not run — inside Lunch (protected)` family, so a
  refusal reads the same wherever the app makes one.
- Phase 4's real snooze rule replaces the +15 and must keep this guarantee; it
  does not replace the guarantee.

---

## 17. What Phase 2 must render for review

Additions to the §12 fixture set. Same rule: display fixtures, no services.

1. A routine template with one block of each flexibility, in the Routines window
2. The same template with a protected, a low-energy **and** a peak-focus window,
   in windows mode — the only place all three appear together
3. Blocks mode and windows mode, to check the inactive layer at
   `opacity.editorInactiveLayer`
4. A template with 3 detached instances, showing the count and the re-sync popover
5. A selected detached instance on the main grid, showing the inspector line
6. A conflict with two options and a conflict with three
7. A conflict whose recommended option is **not** first
8. A preview active: previewed blocks, ghost origins, and the canvas border
9. The needs-attention row at 1, at 12, and at 0 (hidden)
10. Status item: normal, late, empty — each at full width and clipped to
    `size.statusItemMaxWidth`
11. Popover: normal, late, empty, and with more than `size.popoverMaxRestRows`
    remaining
12. The snooze result row, same-day and next-day — and (amended 2026-10-06, §16)
    the refused row, `Not moved — … inside Sleep (protected)`
13. The Routines window in Blocks mode with four inactive weekday columns —
    reweighted hour lines, the in-column note, and the active columns' header
    underlines (§13.5.2, §13.5.3)
14. The same window in **Windows** mode, where none of §13.5's treatment applies
    (§13.5.5)
15. A template block taking the `conflicted` presentation in the Routines window
    because it lands in a protected window (§13.6.2), with the editor inspector's
    `Will not run — …` line
16. The §14.6 template conflict panel: the window-row collision header and three
    template-level options
17. A single-option conflict, showing **no** `Recommended` chip (§14.3.3)
18. A `skipToday` option focused: the ghost dim with no dashed twin, plus the
    canvas border (§14.4)

---

### 17.1 Exact fixtures

Every capture above is a display fixture. These are the ones whose state is not
reachable by guessing, so the values are named here rather than left to the
capture task. **Items 6, 7, 15, 16 and 17 need routine `Event`s that
`RoutineEngine.materialize` actually produced** — `ConflictEngine` resolves a
routine occurrence's ± minutes by reversing its `externalID`, so a hand-seeded
`.routine` event cannot reach `shiftLater` at all. Materialisation must be wired
and running before these can be captured.

**Additions to the `Daily routine` template** (Mon/Wed/Fri, `.green`):

| Title | Start | Duration | Flexibility | ± | Serves |
|---|---|---|---|---|---|
| `Training` | 17:00 | 90 min | `.shiftable` | 90 | items 6, 7, 17 |
| `Errands` | 12:30 | 45 min | `.shiftable` | 90 | items 15, 16 |

**Addition to the `TimeWindow` seed:** `Lunch`, `.protected`, Mon/Wed/Fri,
12:00–13:00. The existing `Sleep` (22:00–07:00, every day) deliberately overlaps
nothing, so it cannot drive item 15; a bounded daytime protected window can, and
it is also the only fixture in which a protected collision has a way out in both
directions.

**Addition to the seeded events:** `Supervisor meeting`, `.manual`, 17:30–18:15,
on the first Mon/Wed/Fri at or after today.

**Amended 2026-10-05 — review fixtures must not depend on the weekday.** As
first written, the count was 15 day conflicts when today is Mon/Wed/Fri and 13
otherwise: on a template day the materialised `Training` (17:00–18:30) also
overlaps §12 item 12's packing triple, which is seeded on today at 18:00. A
review count that changes with the calendar is a count nobody can check. The
§12 item 12 triple **moves** — it is a packing fixture with no time of its own,
and the §17.1 conflict is the one whose times are load-bearing:

| §12 item 12 fixture | Was | Now |
|---|---|---|
| `Group call`, `.manual`, pink | 18:00–19:30 | **13:00–14:30** |
| `Code review`, `.manual`, blue | 18:15–19:00 | **13:15–14:00** |
| `Notes write-up`, `.planned` `.droppable`, purple | 18:45–19:45 | **13:30–14:30** |

Still three mutually overlapping blocks (common interval 13:30–14:00), still
today. 13:00–14:30 is free of every routine instance on every weekday (Gym,
Morning review, Training and Reading all lie outside it; Errands never
materialises), touches `Check mail` (ends 13:00) and `Prep: relational algebra`
(starts 14:30) without overlapping either — strict overlap only, so they are not
packed with them — and sits on the `Low energy` window, which is a useful second
check of §7's "present but recessive" under a full column.

**Expected count, on every weekday and at every clock time:**

| | Count |
|---|---|
| `Client call` × `Focus review` (today) | 1 |
| The eleven `Fixture call N` × `Fixture review N` pairs (days 2–12) | 11 |
| `Training` × `Supervisor meeting` (first Mon/Wed/Fri ≥ today) | 1 |
| **Day conflicts** | **13** |
| `Errands` × `Lunch` (template conflict, §14.6) | 1 |
| **Needs-attention count** | **14** |

`MockDataClockTests` pins 13 and 14 for a template weekday **and** a non-template
weekday at every clock time it already sweeps. Any future fixture that changes
either number amends this table in the same edit.

#### Item 6 — two options and three

- **Three options.** `Training` (17:00–18:30) × `Supervisor meeting`
  (17:30–18:15). Rows: `Shorten Training to 30 min` (60) ·
  `Shift Training 75 min later` (75) · `Skip Training today` (90).
- **Two options.** The existing seeded pair, unchanged: the `.fixed`
  `Focus review` × `Client call` overlap already captured as
  `screenshots/2/conflict-panel-two-options.png`.

#### Item 7 — recommended not first

The three-option fixture above, with no change. `shiftLater` moves 75 minutes,
which is ≤ the occurrence's 90-minute duration, so §14.3.3 recommends it; it sorts
**second**, behind the 60-minute shorten. The chip is on row 2.

#### Item 17 — single option, no chip

`Training` with its ± minutes set to **15** for this capture, against a
`Supervisor meeting` widened to 16:45–18:45 — which wholly contains the
occurrence. `shiftLater` needs 105 min (> 15), both remainders are 0, so
`skipToday` stands alone and carries no chip.

#### Items 15 and 16 — the protected-window refusal

`Errands` (12:30–13:15) × `Lunch` (12:00–13:00) on Mon, Wed, Fri. Item 15 is the
Routines canvas: the block carries `conflicted` in those three columns and only
those. Item 16 is the panel, reached from the needs-attention row, with three
rows: `Shift Errands 30 min later in the routine` (30) ·
`Shorten Errands to 15 min` (30) · `Remove Errands from this routine` (135).
`Shift Errands 75 min earlier in the routine` (75) is a fourth candidate that the
three-option cap drops, which is what makes this fixture also a check on §14.6's
cap and kind-order tie-break. The first row is recommended.

#### Item 10 — status item widths

The clipping half needs a title that cannot fit under any reasonable
measurement, so it is named rather than described:

| Capture | `now` | Title | Available width | Expected |
|---|---|---|---|---|
| normal, full | 17:10 | `Gym` | 180 | `17:30 · Gym` |
| normal, clipped | 17:10 | `Statistik Übung Gruppe 4` | 180 | `17:30 · Statistik Üb…` |
| late, full | 17:42 | `Gym` | 180 | glyph + `12m ago · Gym` |
| late, clipped | 17:42 | `Statistik Übung Gruppe 4` | 180 | glyph + `12m ago · Stati…` |
| empty | 23:40 | — | 180 | `Nothing left today` |
| ~~degraded~~ | ~~17:10~~ | ~~`Statistik Übung Gruppe 4`~~ | ~~**110**~~ | ~~`17:30` alone~~ |
| narrowed | 17:10 | `Statistik Übung Gruppe 4` | **110** | `17:30 · Statisti…` |
| degraded | 17:10 | `Statistik Übung Gruppe 4` | **80** | `17:30` alone |

The exact truncation point is whatever the measured font produces; what the
capture is checking is that the **time is intact in every row** and that the
80pt row shows no separator and no ellipsis (§15.1).

**Amended 2026-10-05 — the fixture was wrong, not the token (closes G-037).** At
`statusItem` size `17:30` measures 37.3pt and ` · ` 11.0pt, so at 110pt the title
has 61.8pt — about twice `size.statusItemTitleMinWidth` (32). §15.1 shows the
title there, and it should: 61.8pt is seven or eight characters, which is
information. The token is the reasoned number ("about four characters plus an
ellipsis"); 110 was an arithmetic slip in this table. Raising the token to make
110 degrade (≥ 62) would throw away a readable seven-character title on every
moderately crowded menu bar to satisfy a fixture. The degrade point is
37.3 + 11.0 + 32 = **80.3pt**; the degraded row is captured at **80**, and 110
stays as a second clipped row (`narrowed`) because it checks the truncation path
at a width the 180pt rows do not reach. Both rows are already captured
(`status-item-degraded-110-p2t47.png`, `status-item-degraded-80-p2t47.png`).

#### Item 11 — popover rest-row overflow

`now` = 17:10. Next: `Training`, 17:30–18:15, `Daily routine`. Rest of today,
nine rows, so six render and the overflow line is plural:

`18:30 Code review` · `19:00 Dinner` · `19:30 Reading` · `20:00 Mail triage` ·
`20:30 Stretching` · `21:00 Journal` · `21:30 Plan tomorrow` · `22:00 Tidy desk` ·
`22:30 Water plants`

Expected: rows `18:30` through `21:00`, then `+3 more`.

The other three popover states: **normal** = the same fixture with only the first
three rest rows; **late** = `now` 17:42 against the same next item, giving
`Started 12m ago · Daily routine` (amended 2026-10-05: the meta line names the
source, §15.2); **empty** = `now` 23:40, no next item, rest section omitted
entirely.

#### Item 12 — snooze results (added 2026-10-06)

Renders, like items 10–11 (§17.2 rule 3). Three rows:

| Capture | Fixture | Expected |
|---|---|---|
| same-day | `now` 17:10, `Training` 17:30–18:15, `Sleep` present | `17:45 – 18:30` above `Moved to 17:45` + `Undo` (unchanged, `snooze-same-day-p2t48.png`) |
| next-day | `now` 23:40, `Prep: relational algebra` 23:50–01:20, **no time windows** | `00:05 – 01:35` above `Moved to tomorrow 00:05` + `Undo` |
| refused | the next-day fixture **with** `Sleep` (22:00–07:00 daily) | NEXT unchanged (`23:50 – 01:20`) above `Not moved — 00:05 is inside Sleep (protected)`, no `Undo` |

The next-day row needs a world with no protected window over its destination:
with the seeded `Sleep`, every +15 that crosses midnight is refused, which is
exactly what the third row checks. The existing `snooze-next-day-p2t48.png`
shows the surface correctly but depicts a write that §16 now refuses; it is
replaced by the two new renders.

#### Item 13 — inactive weekday columns

The `Daily routine` template unchanged (Mon/Wed/Fri), Blocks mode, window wide
enough that all seven columns are above
`size.routineEditorColumnMin`. Tue/Thu/Sat/Sun each show the note; Mon/Wed/Fri
each show the green header underline. A second capture at
`size.routineEditorMinWidth` (780) checks the note still fits inside
`size.inactiveDayNoteMaxWidth`.
Nothing selected (amended 2026-10-05: the wide capture had `Morning review`
selected by a stray click; a selection is not part of this item).

#### Item 1 — one block of each flexibility (amended 2026-10-05)

The `Daily routine` template in Blocks mode, scrolled so `Gym` (07:00,
`.shiftable`), `Morning review` (08:15, `.fixed`) and `Reading` (21:00,
`.droppable`) are all in frame at once — a window tall enough, or two captures at
two scroll positions of the same session, the second named `-evening`. Nothing
selected. The 2026-09-24 frame predates §13.5's weekday treatment, the
flexibility stepper and the §17.1 blocks, so it no longer shows the window as
built.

### 17.2 What counts as evidence

Added 2026-10-05 (Phase 2 screenshot review). The captures are the only real
check on spec against implementation (`DECISIONS.md`, Phase 1 process rules), so
what a capture must show is part of the spec.

1. **A frame shows the thing it is filed under, in the viewport.** A conflict
   frame shows the affected block(s) whole, not at the bottom edge. A preview
   frame shows the ghost and, where one exists, the dashed twin. Interactions
   §10.1's scroll-into-view makes this automatic once built.
2. **A frame shows the build as it is at review time.** A frame captured before
   a change that alters what it shows is retired and recaptured, not annotated.
   Copy changes count: a conflict row with pre-§14.3.4 copy is not evidence for
   §14.3.4.
3. **Offscreen renders of the real view are acceptable for items 10–12**, because
   §17.1 pins clock times and widths that a live menu bar cannot be set to. They
   are evidence of **layout, copy, truncation and degrade** only. They are not
   evidence of what the live menu bar does with the label (template tinting,
   §15.1; one image plus one string; the width the bar actually allocates, B15)
   or of the popover's live chrome (material, arrow, enabled state of `Open`).
   So items 10–12 additionally need **one live capture each** of the status
   item (normal state, any time, any title) and of the popover (normal state),
   from the current build, cropped from the real menu bar. Making room in a
   crowded menu bar (quitting or hiding other status items for the capture) is
   an acceptable capture step; it is not a product change.
4. **No selection, hover or focus that the item did not ask for.**
5. **Light or dark is free per frame, but a frame that measures a colour names
   its appearance in INDEX.md.**
