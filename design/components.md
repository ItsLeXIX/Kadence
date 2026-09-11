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

If two clamped blocks would overlap after clamping, they enter cascade layout
(see `layouts.md` §3.3) rather than being drawn on top of each other.

**Visible width overrides the tier.** In a cascade a block can be partly covered
by the block in front of it. When a block's visible width is below
`size.blockCascadeMinReadableWidth` (44), it renders the `.glyphOnly` content set
— glyph only, no text — regardless of its height. A covered block that renders its
full content gets clipped mid-string and reads as damage (`10:`), not as
something behind something else. `resolveBlockStyle` therefore takes visible
width as well as rendered height.

**Reading the old numbers.** Prose elsewhere in this file was written against the
previous bands. The mapping is normative: "11–15" or "below 16" means
`.glyphOnly`; "16–27" means `.titleOnly`; "28–43" means `.compact`; "≥ 44" means
`.full`. All Phase 1 prose in this file has been restated in tier names; the
Phase 2 sections (§13–§17) still use the old numbers and are not re-edited here —
read them through this mapping until the next Phase 2 revision window.

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

---

## 14. Conflict resolution

Rulings this implements: `DECISIONS.md` 2026-09-10 "Conflict resolution previews
in place, not in a sheet", plus the abandonment ruling of the same date.

### 14.1 Entry point

The needs-attention row (§10.2) is a button. Activating it selects the first
unresolved conflict and puts the inspector into conflict mode. There is no
separate list view and no sheet.

### 14.2 The collision header

Top of the conflict panel: the two colliding blocks rendered as **real blocks**
at the 16–27 density tier, stacked with `spacing.xs` between them and the word
`overlaps` between them in `inspectorLabel` / `color.text.secondary`. Same style
resolver, same hue, same rail — so the thing in the panel is recognisably the
thing on the grid.

Below them, the overlap itself: `13:00–14:30 · 45 min overlap`, `blockMeta`.

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

Nothing is written until the option is applied. Abandonment is specified in
`interactions.md` §10.2 and is unconditional.

### 14.5 Resolved and empty

When the last conflict is resolved the panel does not congratulate. It returns to
the ordinary inspector, and the needs-attention row disappears (§10.2, hidden at
zero). No "all clear" state, no checkmark screen.

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
12. The snooze result row, same-day and next-day
