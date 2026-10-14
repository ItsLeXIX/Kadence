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
| `origin == .imported`, timed, `importKind == exam` *(added 2026-10-08, Phase 3, §20.7.1)* | `.fixedTimed` | `graduationcap.fill` |
| `origin == .manual`, timed | `.fixedTimed` | `calendar` |
| `origin == .routine` | `.routineTimed` | `repeat` |
| `origin == .planned` | `.plannedTimed` | `pencil.and.outline` |
| `TravelLeg` | `.travelBand` | `figure.walk` / `car.fill` / `tram.fill` by mode |
| `WorkItem.kind == .assignment/.project`, all-day | `.deadlineAllDay` | `flag.fill` |
| `WorkItem.kind == .exam`, all-day | `.examAllDay` | `graduationcap.fill` |
| `Event`, `isAllDay`, `origin == .imported` *(added 2026-10-08, §5.1)* | `.eventAllDay` | `building.columns`; `graduationcap.fill` when `importKind == exam` |
| `Event`, `isAllDay`, `origin == .manual` *(added 2026-10-08, §5.1)* | `.eventAllDay` | `calendar` |

A manual event is a fixed timed block because a user-created event is fixed
until the user says otherwise. It differs from an imported lecture only by
glyph and by defaulting to `color.source.graphite`.

An imported exam (CIS `-EXAM`, §20.7.1) is the same `.fixedTimed` block with the
exam glyph `.examAllDay` already uses: kind rides on the glyph (§1), so a timed
exam needs no new variant. `graduationcap.fill` is already a kind glyph, so
§10.1's two-vocabulary rule is untouched.

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

**Amended 2026-10-10 (Phase 3 slice 1 review) — no longer deferred; required
now (G-048, A35).** Phase 3 makes the covered block the *lecture*: a lecture
starts earlier and runs longer than the routine block or the second session
that covers it, so it is the block that loses its title. `week-M-p3.png` draws
Friday's `SWRM-ILV` as an unnamed blue rectangle for the whole hour before
`Training` starts, and Parsa's real week (Fri 2 Oct 2026) drew `BPREF-Info`
18:35–20:15 under `BPREF-Info` 19:30–20:15 as what looked like one block with
two glyphs. The title-band rule above is built in this fix round, exactly as
written.

**Added 2026-10-10 — a covering block is separated from what it covers
(G-078).** "The canvas gap between blocks" was never drawn: a cascaded block
sits flush on the one beneath it. Between two different hues that reads; between
two `.fixedTimed` blocks of the **same source** — no rail, no border, one fill —
the upper block's edges disappear and the pair reads as one block. So: every
block in a cascade with index ≥ 1 draws a gap of `size.blockColumnGap` (2) in
`color.surface.canvas` along its **leading and top** edges, outside its own
frame (the covered block is cut back by 2pt there; the covering block's frame
does not move). It is the same 2pt of canvas that separates packed neighbours,
so a pair is as distinct stacked as it is side by side, in every state (a solid
fill against the canvas measures 4.87:1 light / 6.91:1 dark worst; a done or
past wash is as faint against the gap as it already is against the canvas around
it — `tokens.json` `$measured_1_7_0`). No new token. A `conflicted` or `selected` border is drawn inside the gap as before.

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

~~Layout priority on the meta line: **source wins, location truncates first.**
Location is recoverable from the inspector and from the travel band's own label;
source, below `.full`, is recoverable only from hover help and the inspector.~~
When there is no location the line is just the source name.

**Amended 2026-10-10 (Phase 3 slice 1 review; G-079) — the location comes
first and the source truncates.** The line is drawn **`Location · Source`**
(`HS_A3.15 · University timetable`, `Online · University timetable`). The
location is never truncated while any of the source name is still drawn; the
source name tail-truncates (`HS_A3.15 · Universit…`) and is dropped whole, with
its separator, only when fewer than 4 of its characters would fit. Why the
1.0 rule is reversed: it was written when source names were short fixtures. A
real source is called `University timetable`, which fills a Week column by
itself (`week-M-p3.png`: every lecture reads `University timetabl…` and none
shows its room), so the rule spent the line repeating what hue, glyph and the
sidebar already say and hid the one fact that differs from block to block —
where to go. The source stays on the line wherever it fits, in hover help, in
the inspector and in VoiceOver, so §1's greyscale trade is unchanged. The table
row above reads `Location · Source` from this date. The menu bar popover's meta
line (§15) is not changed.

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

**Amended 2026-10-14 (Phase 3 slice 2) — the band is live.** Everything above
stands as the visual spec. From slice 2 the band is drawn from the event's
`TravelLeg` (status `ready`), not a display fixture; "no location" reads "no
`ready` leg"; `departAt` includes the buffer; `NNmin` is the travel time
without it; the hover help and the VoiceOver phrase name the origin and the
mode. The exact list of changes is §25.1.

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

### 5.1 Event all-day — `.eventAllDay` (added 2026-10-08, Phase 3; closes G-055)

An all-day `Event` — an imported all-day entry (`DTSTART;VALUE=DATE`, §20.4) or a
manual one made with `⌘⌥N` — has had no variant: §5 covers deadlines and exams,
which are `WorkItem` projections, and the build filters every `isAllDay` event
out of every view, so a manual all-day event has been created and then never
drawn (found by this pass; G-055). Phase 3 imports them, so the variant is
specified now.

| | **`.eventAllDay`** |
|---|---|
| Geometry | §5's pill: `size.allDayRowHeight`, `radius.allDayPill`, spanning its date range |
| Fill | `color.source.<s>.solid` — fixed, the same weight as its timed sibling `.fixedTimed` |
| Border | none |
| Rail | none |
| Label | `allDayLabel`, `color.text.onSolid` |
| Glyph | `building.columns` (imported) / `calendar` (manual), `color.text.onSolid` — the same glyph as the timed block of the same origin (§2.1); an imported exam takes `graduationcap.fill` (§2.1, amended 2026-10-08) |
| Trailing element | none |

It differs from `.examAllDay` by glyph and by having no countdown chip, and from
`.deadlineAllDay` by fill weight, rail and glyph — never by hue alone. States
(§6) apply as they do to `.fixedTimed`, including `cancelled` (§6, 2026-10-08).
Hover help, inspector and VoiceOver carry the source as for every all-day item
(§3.4). Sort within the all-day row: by start day, then `.examAllDay`,
`.deadlineAllDay`, `.eventAllDay`, then title.

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

| **cancelled** *(added 2026-10-08, Phase 3; §20.6)* | Only on imported events whose source marks them `STATUS:CANCELLED`. Fill blended with canvas at `opacity.blockSkippedFillBlend`. Border dashed `[3, 3]`, `size.borderRegular`, `color.separator.strong` (skipped's border — both mean "not happening here"). Glyph replaced by `xmark.circle` in `color.text.primary`. Label and meta **`color.text.primary`** (`color.text.secondary` measures 3.80:1 on the blended solid fills; `text.primary` ≥ 7.67:1 — `tokens.json` `$measured_1_4_0`). At `.full` the meta line reads `Cancelled · University timetable`; below `.full`, hover help and the inspector carry it. **No strikethrough** (§6 `done`'s reason). Never `conflicted` (§20.9), never `inProgress`, never `past`'s content opacity on top of the blend — a cancelled block that is past takes `past` only. |
| **previewed** | The block is shown at a **proposed** frame during conflict resolution (`interactions.md` §10), not a committed one. It renders at `opacity.blockPreviewed` inside a `size.borderSelected` dashed outline in `color.interactive.accent`, dash `[3, 3]`, **and its current frame stays visible at `opacity.blockDragOrigin`**. Applied last, after every row above it. |

**Amended 2026-10-08 (Phase 3; closes G-054) — `done` on a solid fill.** The
`done` row's `color.text.secondary` label measures **3.32:1 (light, orange) /
3.06:1 (dark, graphite)** on a `.solid` fill blended at `opacity.blockDoneFillBlend`
— below AA. Phase 2 never showed a done `.fixedTimed` block in review; Phase 3 makes
it ordinary (a lecture marked done, §18.1). On the solid-fill kinds — `.fixedTimed`,
`.examAllDay`, `.eventAllDay` — the `done` label and its `checkmark.circle.fill` take
**`color.text.primary`** (worst source, at the 0.55 blend: 9.01:1 light, 6.17:1 dark —
`tokens.json` `$measured_1_4_0`). The tinted and
transparent kinds keep `color.text.secondary`, which passes on them.

**Amended 2026-10-10 (closes G-074) — the meta line too.** The G-054 amendment
named the label and the glyph and forgot the meta lines (time range; location ·
source). Left at `.fixedTimed`'s `color.text.onSolid` at 0.8 they measure
**1.65:1 (light, graphite) / 2.44:1 (dark, teal)** on the done-blended fill —
white on a pale wash. On the solid-fill kinds, in `done`, **every text element
of the block is `color.text.primary` at full opacity**: label, glyph, time and
meta (9.00:1 light / 6.17:1 dark worst — `tokens.json` `$measured_1_7_0`;
checked on `allday-and-done-light-p3.png` / `-dark-p3.png`, whose fills sample
`#A1BEE8` / `#3F5A83`, the computed blend of `blue`). Hierarchy inside the
block is carried by weight and size, as in `cancelled`. CA's placeholder was
this; it stands and loses its `// SPEC-GAP` mark.

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
  *(Amended 2026-10-14; G-082.)* "Collide" is measured on the two labels as
  drawn, not on their times: an hour label is dropped when its text frame and
  the now time's text frame would overlap or come within 2pt of each other.
  The build hangs an hour label below its line and centres the now time on
  the now line, so a 12pt distance between the two *times* still let
  `10:18` print over `10:00` in Week (`source-popover-calendar-missing-p3.png`,
  `source-popover-last-change-p3.png`). The cursor time (`interactions.md` §1)
  follows the same rule.
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
*(Amended 2026-10-14, Phase 3 slice 2.)* A block with a travel leg speaks its
leave-by after the time range, before the kind: §29 has the exact phrases,
including the one for a travel time that is not set.

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

*(Amended 2026-10-14, Phase 3 slice 2.)* Items 7 and 8 are no longer
fixtures: `TravelFixture` is retired, and both bands come from legs computed
from seeded places, walking overrides and the mock travel provider (§30.1
"Other datasets"), drawing the same
`Leave 08:38 · 22min` and `Leave 10:54 · 6min` as before.

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

**Amended 2026-10-14 (Phase 3 slice 2) — the leave-by.** Two states join the
table between Normal and Late when NEXT has a travel leg: **Leave** (`Leave
08:15 · SWQM-ILV`, the `Leave 08:15` unit taking the time's never-truncated
role) and **Leave now** (glyph + `Leave now · SWQM-ILV`), plus the rule that a
due departure outranks a late item. §26.1.

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

**Amended 2026-10-14 (Phase 3 slice 2).** "Location joins the line in Phase 3
with the leave-by time" is specified in §26.2: NEXT gains a **leave line**
(`Leave by 08:15 · 35 min from Home`, or `Leave now · leave-by was 08:15` in
`color.semantic.now`), the meta line becomes **time · location · source**
(§3.4's order), and the popover's last lines gain the notifications line
(§26.3).

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

**Amended 2026-10-07 (Phase 2 closeout; G-051) — the refused row is read in
full.** `snooze-refused-p2f25.png` draws `Not moved — 00:05 is inside Sleep
(protect…`: the sentence is ~290pt in `popoverRow` and the row has 276pt
(`size.popoverWidth` 300 less two `spacing.lg` insets), at a fixed
`size.popoverActionRowHeight`. A refusal of a hard rule that is cut off is not a
refusal the user can read, and a window label is the user's own text, so no
single-line copy can be guaranteed to fit. Ruled — **two lines with a fixed
break, then wrap; never truncated:**

- **Line 1, fixed:** `Not moved — 00:05 is inside` (the refused destination
  start, `HH:mm`, monospaced digits; always fits — about 175pt).
- **Line 2, the window:** `Sleep (protected)`. Unlabelled window (empty or
  whitespace-only label): `a protected window`. The label is drawn verbatim. The
  space before `(protected)` is a no-break space (U+00A0), so the qualifier never
  sits alone on a line.
- Type `popoverRefusalRow` (13pt, regular, `lineLimit` 0 — added in
  `tokens.json` 1.3.0), `color.text.primary`, leading-aligned. If line 2 is
  wider than 276pt it **wraps at word boundaries onto further lines**; it is never
  truncated, at any label length. No `Undo`.
- **Row height** = the text's height + `spacing.xs` above and below, never less
  than `size.popoverActionRowHeight` (28). Two lines at 13pt ≈ 40pt. The popover's
  content height follows the row for the hold and returns to the normal state's
  height when the hold ends; no animation of its own (the system's popover
  resize, or none). The hold (`motion.snoozeConfirmHold`, pausing on hover) is
  unchanged.
- **Accessibility:** the row is one element whose label is the one-line sentence
  — `Not moved — 00:05 is inside Sleep (protected)` / `Not moved — 00:05 is inside
  a protected window` — line break replaced by a space.
- The **moved** row (`Moved to 19:15` + `Undo`, `Moved to tomorrow 00:05` +
  `Undo`) is unchanged: `popoverRow`, one line, `size.popoverActionRowHeight`.
  Its longest form fits.

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
| refused, unlabelled (added 2026-10-07) | the refused fixture with `Sleep`'s label set to empty | NEXT unchanged above two lines: `Not moved — 00:05 is inside` / `a protected window`, no `Undo` |

The next-day row needs a world with no protected window over its destination:
with the seeded `Sleep`, every +15 that crosses midnight is refused, which is
exactly what the third row checks. The existing `snooze-next-day-p2t48.png`
shows the surface correctly but depicts a write that §16 now refuses; it is
replaced by the two new renders.

**Amended 2026-10-07 (G-051).** The refused rows render on **two lines**, line 1
`Not moved — 00:05 is inside`, line 2 `Sleep (protected)` (or `a protected
window`), nothing truncated and no `…` anywhere in the row (§16, 2026-10-07). All
four item 12 renders — same-day, next-day, refused, refused-unlabelled — are
captured from one build with one renderer; `snooze-same-day-p2t48.png` (which
predates B1 and NEXT's focus overlay) is replaced, not kept.

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
6. **The window-edge check (added 2026-10-08, Phase 2 acceptance; closes
   G-053).** No pixel in a frame's outermost 2px band may match
   `color.interactive.accent` / `color.interactive.focusRing` (sampled, as
   P2-SF1 and CF5 do). This is the evidence form of `interactions.md` §1's
   "no region draws a region-level focus ring": the G-039 defect showed as
   exactly such a line. **One exemption: §14.4's preview border, while a
   preview is active.** The canvas carries `size.previewCanvasBorder` (2pt) in
   `accent` round its own bounds, and both canvases reach the window's edge on
   at least two sides, so a preview frame cannot pass the band test and is not
   meant to — the border is what items 8, 16 and 18 are filed to show. The
   exemption is narrow and checkable, so it cannot hide the defect it sits
   beside:
   - it applies only to a frame filed under an item that asks for an active
     preview (§17 items 8, 16, 18; any later item that says so);
   - the flagged pixels must form a **complete rectangle** 2pt wide that
     follows the canvas's bounds on all four sides — including the side that
     does **not** touch the window edge (the canvas/inspector boundary), which
     is what separates the preview border from a region ring drawn as one edge;
   - accent pixels in the band **outside** that rectangle's columns and rows
     (the inspector's or the sidebar's outer edge, the title bar) still fail.

   `template-conflict-panel-p2c.png` meets all three: its accent band runs down
   the canvas's left edge, along its bottom, across its top below the day header,
   and down its right side at x 1576–1579 beside the inspector, and nothing in
   the inspector's or title bar's edge band is accent. The check script
   (`Scripts/check-frame-edges.py`) implements the exemption from these three
   conditions; it does not take a per-file allow-list.

---

# Phase 3 — slice 1: the university timetable from the CIS CalDAV account

Written 2026-10-08 and amended twice the same day. The first version read the
CIS WebDAV share, the second a calendar subscription link; both assumptions were
wrong. **This version (the CalDAV amendment) reads the CIS CalDAV account** —
what Apple Calendar syncs as an account with a server
(`cis.technikum-wien.at`), a username and a password, without VPN
(`DECISIONS.md` 2026-10-08 "The timetable is a CalDAV account…"). The server is
SabreDAV at `https://cis.technikum-wien.at/webdav/lvplan.php/`. The event rules
(§20.2–§20.7.1) come from a redacted real export
(`fixtures/cis-2026WS-redacted.ics`) and do not depend on the transport, so they
carry over unchanged. Nothing had been built from either earlier version.

Scope: **one** data source kind — a **CalDAV account**: discovery
(`/.well-known/caldav` → principal → calendar home → calendars, §20.8.1), one
`REPORT calendar-query` per selected calendar per poll, with a fallback used only
if REPORT is refused (§20.8.2), and change detected **by content**, never by the
server's markers (§20.8.4). Imported events are read-only and polled. The WebDAV
share is out of scope (§19.0; G-065). Nothing in this slice touches Moodle, work
items, time logging, travel time, notifications, mail or the planner. Every
Phase 1–2 value stands. The in-place amendments are §2.1, §5.1 and §6, all marked
2026-10-08. Plan and build order: `PHASE3-PLAN.md`. Layouts: `layouts.md` §2.1,
§6.1, §11, §12. Interactions: `interactions.md` §2 (amended), §13. Mocked
server responses: `caldav-mocks.md`.

Three rules from earlier phases govern the whole slice:

- **The assistant proposes, the user disposes.** A sync writes upstream facts;
  it never moves, shortens or skips anything the user owns. Conflicts a sync
  creates are surfaced through §14 like any other.
- **Never silent.** A sync that fails, partly fails, finds nothing or removes
  something says so where the source is shown (§19), and it never deletes what it
  could not see (§20.8).
- **The password is the only secret.** Server, username, calendar names, hrefs,
  ctags and ETags are not secret: they are shown (`user01 @
  cis.technikum-wien.at`) and logged. The password lives in one Keychain item
  (§21.4). It is sent only over HTTPS, only to the source's host, and only in
  answer to that host's 401. It is never logged and never appears in a fixture,
  a test assertion message or a screenshot.

---

## 18. Imported events

### 18.1 What read-only means

An imported event's **upstream fields** belong to the sync and nothing else
writes them: title, start, end, all-day, location, online, course, group,
lecturers, kind (lecture / exam), description, link, cancelled. **One field is
local: `status`** (`.scheduled` / `.done` / `.skipped`). Done and skipped are
facts about the user's day, not about the lecture — the same reading
`DECISIONS.md` 2026-10-01 gave routine detachment — so `⌘↩`, `⌥⌘↩` and the
inspector's Done / Skip work on imported events, and a sync never writes
`status`, with one exception: when an upstream change moves an event's `start`
or `end` **in place** (a source with stable identities, §20.2), its status resets
to `.scheduled` (a lecture marked done and then moved to next week has not been
attended). On CIS a move is a delete plus an add (§20.10), so the new event
starts `.scheduled` anyway.

Every other mutation is refused, visibly (`interactions.md` §13.4).

**History keeps Done and Skip (ruled 2026-10-10).** An imported event that
started before today offers `Done` / `Skip` exactly like a future one, in the
inspector and by `⌘↩` / `⌥⌘↩`. "The past is never written" binds the **sync**
and every automatic writer (§20.1); it does not bind the user. Done and skipped
are facts about the user's day, and the usual moment to record one is after the
lecture — the same evening or the next morning, by which time it is history.
Refusing them there would make the one local field unusable when it is needed.
The marks are ordinary undo steps (`interactions.md` §13.5).

### 18.2 On the canvas

Unchanged from Phase 1: `.fixedTimed`, solid fill, no rail, source hue. The
glyph is `building.columns` for a lecture and **`graduationcap.fill` for an
exam** (§2.1, amended; §20.7.1 decides which). Two consequences of read-only,
both already true by §6 and `interactions.md` §4 and restated so nobody adds
them back:

- **No resize handles.** The hover state draws its inset ring but not the
  `size.blockResizeHandleHeight` handles.
- **Cursor `.arrow`** over the block; `.operationNotAllowed` once a drag starts
  (`interactions.md` §8).

**Online events** (§20.7.1: `LOCATION` `WEBINAR01`, `WEBINAR02` …) show
**`Online`** wherever the location would show: the `.full` meta line reads
`University timetable · Online`; the inspector's `Room` row reads `Online ·
WEBINAR02` (`layouts.md` §6.1). No glyph is added: the block's glyph slot is
spent on kind (§3.4), and neither vocabulary (§10.1) has an "online" symbol —
adding one would spend a third vocabulary on a fact the location text already
states. The travel slice reads `isOnline` and plans no travel for it (G-063).

All-day entries render as `.eventAllDay` (§5.1). Cancelled entries take the
`cancelled` state (§6). Nothing else on a block says "imported" — the glyph
already does, and source hue plus §3.4's source text say from where.

### 18.3 The menu bar

- **Status item:** unchanged. It never shows sync state (§19.4 says why).
- **Popover, NEXT is an imported event:** the action row is `Done` · `Open`.
  **`Snooze` is not drawn** — snoozing moves the event, and an imported event
  cannot move. `⌥⌘↩` on it does not move it and shows §16's refusal row form, in
  place of the action row, for the same hold: line 1 `Not moved — SWQM-ILV`,
  line 2 `is read-only (University timetable)`, `popoverRefusalRow`,
  `color.text.primary`, no `Undo`, never truncated (§16's 2026-10-07 rule; the
  source name is the user's text, so it wraps). Accessibility label: the one-line
  sentence. A `cancelled` event is never NEXT and never in REST OF TODAY (§20.6).
- **Late state on an imported event:** `Re-offer` is not offered (it re-places,
  which is a move). The late meta line stays (`Started 12m ago · University
  timetable`); the actions are `Done` · `Open`.
- **Location in the popover** follows §18.2: an online NEXT reads `Online`.

---

## 19. Source status

### 19.0 One source kind in this slice: the CalDAV account

*(Rewritten 2026-10-08, CalDAV amendment.)* The source is the **CIS CalDAV
account**, entered as Apple Calendar enters it: server, username, password. The
two other transports are out:

1. **The WebDAV share `/Webdav/Lvplan`** only answers inside the FH network
   (IP-restricted). A source that syncs only on VPN fails BRIEF-PRODUCT's
   "nothing important may depend on me remembering". It is out of scope (G-065).
   If someone types the share's address into `Server`, they are told so before
   anything is sent (`layouts.md` §12.1's validation table).
2. **There is no subscription link.** What Apple Calendar holds for CIS is an
   account, not a `webcal://` URL. So there is no link to paste, no link to
   keep secret, and no link field.

`Source.connection` is a raw string (§21.1), and the parser, the merge and the
sync planner do not depend on the transport (§21.5). A second kind can be added
later without a migration.

### 19.1 States and their copy — normative

*(Rewritten 2026-10-08, CalDAV amendment.)* A connected source is in exactly one
of these states. Every surface that shows a source's state takes its words from
this table and nowhere else: the sidebar row (§19.2), the source popover
(§19.3), the Settings detail (`layouts.md` §11) and the connect sheet
(`layouts.md` §12). Placeholders:

- `{host}`: the server's host (`cis.technikum-wien.at`).
- `{user}`: the username (`user01`).
- `{account}`: `{user} @ {host}`.
- `{calendar}`: the affected calendar's display name (`LVPlan`). With two
  affected calendars it reads `LVPlan and Prüfungen`; with three or more, `LVPlan
  and 2 other calendars`.
- `{name}`: the source's display name.
- `{otherHost}`: a redirect target's host.
- `{next}`: the next automatic attempt (`HH:mm`, or `tomorrow HH:mm`).
- `{last}`: the last successful sync, per §19.5.
- `{code}`: the HTTP status.
- `{n}`, `{k}`: counts.

Copy is in English, like the rest of the app.

| State | Kind | Title | Body | Primary action |
|---|---|---|---|---|
| `upToDate` | ok | `Up to date` | — | `Sync Now` |
| `syncing` | ok | `Syncing…` | — | — (disabled `Sync Now`) |
| `neverSynced` | ok | `Waiting for first sync` | `Kadence will sync as soon as {host} can be reached.` | `Sync Now` |
| `offline` | ok | `Offline` | `Kadence will sync when this Mac is back online. Events from the last sync ({last}) are still shown.` | — |
| `unauthorized` (401 after the password was sent) | **actionable** | `Sign-in failed` | `{host} didn't accept the password for {user}. Automatic sync is paused so the account isn't locked.` | `Update Password…` |
| `forbidden` (403) | **actionable** | `Access refused` | `{host} refused access for {user}. Automatic sync is paused so the account isn't locked.` | `Edit Account…` |
| `noCalDAV` (`/.well-known/caldav` 404 or not a redirect; a discovery `PROPFIND` not answered `207`) | **actionable** | `No calendar server found` | `{host} doesn't offer CalDAV calendars. Check the server name. Events from the last sync are kept.` | `Edit Account…` |
| `noCalendars` (discovery found no calendar with events) | **actionable** | `No calendars found` | `{account} has no calendars with events. Events from the last sync are kept.` | `Sync Now` |
| `calendarMissing` (a selected calendar is gone after re-discovery, §20.8.1) | **actionable** | `Calendar not found` | `{calendar} is no longer on {host}. Events from the last sync are kept until you choose a calendar or remove the source.` | `Choose Calendar…` |
| `fetchFailed` (REPORT and every fallback refused, §20.8.2) | **actionable** | `Couldn't read the calendar` | `{host} refused every way Kadence asks for events from {calendar}. Nothing was changed.` | `Sync Now` |
| `notACalendar` (a web page where calendar data was expected) | **actionable** | `Not a calendar` | `{host} sent a web page instead of calendar data — often a sign-in or maintenance page. Events from the last sync are kept.` | `Sync Now` |
| `emptyFeed` (§20.8 guard) | **actionable** | `The calendar is empty` | `{host} sent no events for {calendar}. It had {n} events at the last sync, so they are kept. If the timetable really is empty, remove the source in Settings.` | `Sync Now` |
| `partialImport` | **actionable** | `Imported with problems` | `{k} of {n} events couldn't be read and were skipped. Nothing was removed.` | `Show Details` |
| `certificate` (TLS) | **actionable** | `Secure connection failed` | `The certificate for {host} couldn't be verified, so Kadence sent nothing to it. Nothing was changed.` | `Sync Now` |
| `passwordMissing` (no Keychain item, or access denied) | **actionable** | `Password not found` | `Kadence couldn't read the password for {account} from the Keychain. Enter it again.` | `Update Password…` |
| `redirected` (to another host, or to `http:`) | **actionable** | `Redirected to another server` | another host: `{host} sent Kadence to {otherHost}. Kadence didn't follow it, so nothing — and no password — was sent there.` · `http:`: `{host} sent Kadence to an address without HTTPS. Kadence didn't follow it.` | `Edit Account…` |
| `unreachable` (DNS, connection refused or lost, timeout) | transient | `Can't reach {host}` | `Kadence will try again at {next}. Events from the last sync ({last}) are still shown.` | `Sync Now` |
| `serverError` (5xx) | transient | `Server error` | `{host} answered with an error ({code}). Kadence will try again at {next}.` | `Sync Now` |

Gone with the subscription: `signInRequired` (an account always has a password),
`notFound` (now `noCalDAV` for discovery and `calendarMissing` for a calendar),
and `secretMissing` (now `passwordMissing`).

Rules:

- **Only the kind sets the colour** (§19.2). `actionable` means the user must
  do something, `transient` means it will fix itself, and `ok` means there is
  nothing to do.
- **One state at a time.** A poll can make several requests (§20.8.2), but it
  ends in one state. Refusals inside the fallback chain are not states. Only
  the chain's end is. When two selected calendars end differently, the earlier
  row of this table wins, and `{calendar}` names the calendars in that state.
  `partialImport` is the only error state that can sit beside written events.
- **`{n}` and `{k}` are written as digits, not words.** `events` is always
  plural, except `1 event`.
- **No error code is shown, except `serverError`'s HTTP status.** That means no
  `NSURLErrorDomain -1202` and no stack text. The detail list (§19.3) may add
  one technical line per problem in `blockMeta` / `color.text.secondary`. It
  never contains a password, an `Authorization` header or a request body. It may
  contain methods, statuses, hrefs and calendar names, which are not secret:
  `REPORT 405 · PROPFIND 207 · calendar-multiget 501 · GET 405`, or `Object
  obj-07.ics, line 9: DTEND before DTSTART`.
- **`Update Password…`** opens the connect sheet in edit mode with focus in
  `Password`. **`Edit Account…`** opens it with focus in `Server`.
  **`Choose Calendar…`** opens it and starts `Connect` at once with the saved
  account, so it lands on the calendar step (`layouts.md` §12.3).
- **Exact strings are tested** (`PHASE3-PLAN.md` task 11). Changing any wording
  is a spec change.

### 19.2 The sidebar row

`layouts.md` §2.1 places it. Every source row gains a **status slot** `size.statusSlotWidth` (16) wide
between the name and the visibility checkbox; rows of local sources (`Daily
routine`, `Personal` …) reserve it empty so the checkboxes stay in one column.

| State kind | Slot shows |
|---|---|
| `ok`, not syncing | nothing |
| `syncing` | a `ProgressView` (`.controlSize(.mini)`), shown only once the sync has run for 0.5s, so a half-hourly poll does not flicker the row |
| `offline` | nothing (hover help says it) |
| `transient` | `exclamationmark.arrow.triangle.2.circlepath` at `size.blockGlyphSize`, `color.text.secondary` |
| `actionable` | the same symbol in **`color.semantic.alert`** |

`exclamationmark.arrow.triangle.2.circlepath` is a chrome symbol, like §10's
chevrons; it is in neither glyph vocabulary (§10.1) and must not be added to
either. Red/alert here obeys §1: it means "needs attention", and an actionable
source failure is exactly that. It is **not** counted in the needs-attention row
(§10.2): that count means conflicts, and one count means one thing.

The glyph is a button (borderless, hit target ≥ 24 × 24) that opens §19.3.
Hover help on the whole row: `University timetable — Synced 14:02`, `University
timetable — Sign-in failed`, `University timetable — Offline, last synced
14:02`. VoiceOver: ~~the row's value appends the state title~~ the row is
spoken `University timetable, Access refused` — name, then the state title —
and the state title rides on the row's **label**, not its value *(amended
2026-10-10, accepting the build)*: the combined row is exposed as its
visibility checkbox, whose value has to stay its on/off state, so the value
slot is taken. The state title is appended for every state except `upToDate`
(a row that is fine says only its name). Neither ever contains a password.
*(Amended 2026-10-08, CalDAV amendment.)*

### 19.3 The source popover

A **system popover** (`NSPopover` / `.popover`), anchored to the row's status
slot (or to the row when the slot is empty) — never an in-window overlay, which
`DECISIONS.md` and G-034 already ruled out after the Re-sync popover clipped at
the window edge. Width `size.sourcePopoverWidth` (280), height intrinsic, padding
`spacing.xl`, background `color.surface.popover` with its material.

```
+--------------------------------------------+
| Access refused                             |  sourceStatusTitle, text.primary
| cis.technikum-wien.at refused access for   |  inspectorValue, text.primary
| user01. Automatic sync is paused so the    |
| account isn't locked.                      |
|                                            |
| Last synced today 14:02 · 142 events       |  blockMeta, text.secondary
| Last change Mon 08:30: 1 added · 1 removed |  blockMeta, text.secondary
|                                            |
|             [ Settings… ] [Edit Account…]  |  default button = primary action
+--------------------------------------------+
```

- **Title** `sourceStatusTitle`; **body** `inspectorValue`, `lineLimit` 0, never
  truncated; **status line** `blockMeta` / `color.text.secondary`:
  `Last synced {last} · {count} events` (`Never synced` before the first success).
  *(Amended 2026-10-10.)* `{last}` is `lastSuccessAt`, or `importedAt` when no
  sync has succeeded since the Import — the Import read the server
  successfully, so a connected source is never "never synced". `Never synced`
  can therefore only appear on a source that was never imported, which a real
  store cannot hold; the review frames that showed it under `Events from the
  last sync are kept` (`source-popover-forbidden-p3.png`,
  `source-popover-calendar-missing-p3.png`) were a review-seeding artefact, and
  §22.1's review source is now seeded as already imported.
  `spacing.sm` between title and body, `spacing.lg` before the status line and
  before the button row.
- **Last-change line** (added 2026-10-08; §20.6 says why it
  exists), directly under the status line, same style: `Last change {when}: {a}
  added · {u} updated · {r} removed`, zero terms omitted (`Last change today
  14:02: 1 removed`), `{when}` per §19.5's in-sentence forms. It reports the most
  recent sync that **wrote** something, counting only events on or after that
  sync's today; the Import is not a change and sets nothing. Omitted when no sync
  has written since the Import. `lineLimit` 0.
- **Buttons**, trailing-aligned: `Settings…` (opens Settings ▸ Sources with this
  source selected) and the state's primary action as the default button (`↩`).
  States without a primary action show `Settings…` alone.
- **`Show Details`** expands the popover in place (no new window) to a list of
  problems, one per line, `blockMeta`, `color.text.primary` for the sentence and
  `color.text.secondary` for the technical line under it; at most 8, then `+N
  more` (full list in Settings). The button becomes `Hide Details`.
- **The sentences** *(added 2026-10-10; closes G-069)*. One per problem,
  exact, tested like §19.1. `{title}` is the VEVENT's `SUMMARY` treated as
  §20.7 treats a title (for a CIS-profile event: its course code); when there
  is no readable `SUMMARY` the sentence starts `An event`.

  | Problem | Sentence | Technical line |
  |---|---|---|
  | No `UID` (§20.2) | `{title} has no identifier, so it was skipped.` | `Object obj-07.ics, line 3: no UID` |
  | `DTEND` before `DTSTART`, or a negative `DURATION` (§20.4) | `{title} ends before it starts, so it was skipped.` | `Object obj-07.ics, line 9: DTEND before DTSTART` |
  | `DTSTART` missing or unreadable | `{title} has no readable start time, so it was skipped.` | `Object obj-07.ics, line 8: DTSTART` |
  | `DTEND` or `DURATION` present but unreadable *(added 2026-10-14; G-081)* | `{title} has no readable end time, so it was skipped.` | `Object obj-07.ics, line 9: DTEND` / `… line 9: DURATION` |
  | `BEGIN:VEVENT` never closed; an object that is not calendar data (§20.8.2); a failed member of a `207` | `1 event couldn't be read.` | `Object obj-11.ics: not calendar data` / `Object obj-11.ics: 404` |
  | An object over 1 MB (§20.8.2) | `1 event was too large to read.` | `Object obj-11.ics: over 1 MB` |
  | `RANGE=THISANDFUTURE` override (§20.5; the event is kept) | `A change to {title} and its later repeats was applied to one occurrence only.` | `Object obj-07.ics, line 12: RECURRENCE-ID;RANGE=THISANDFUTURE` |
  | Unsupported rule (§20.5) | as §20.5 | the `RRULE` line |
  | Unknown time zone (§20.3; kept) | as §20.3 | — |

  Without an object name (a plain file) the technical line starts at `Line 9:`.

  *(Added 2026-10-14; G-081.)* Without a readable `SUMMARY`, `{title}` is
  `An event` at the start of a sentence and `an event` inside one: `A change
  to an event and its later repeats was applied to one occurrence only.` A
  missing `DTEND` with no `DURATION` is not a problem (§20.4 gives the
  event's default length); only one that is present and cannot be read is.
- **`upToDate`** shows the title, then `Synced {last} · {count} events`, the
  last-change line when present, and `Sync Now`.
- Keyboard: it takes focus on open; `↩` = primary action; `⎋` closes. Focus is
  shown by the buttons' own control rings (`interactions.md` §1).

### 19.4 The popover's stale line

The status item stays "the next thing" and nothing else (`DECISIONS.md`
2026-09-10); a sync state there would be a second job for a 180pt label. But the
popover answers "what now", and an answer drawn from a timetable that stopped
updating should say so. **One line**, last element of the popover, below REST OF
TODAY (or below the action row when that section is omitted), `spacing.lg`
above it:

`University timetable not synced since Mon 14:02`

- Shown when **any connected source** is in an `actionable` state, **or** its last
  success is older than `max(24 h, 2 × its interval)`. Hidden otherwise —
  including while merely `offline` or `transient` for less than that.
- `popoverRefusalRow` metrics (13pt, `lineLimit` 0 — it is the user's source name
  and is never truncated), `color.text.secondary`. Never red, no glyph.
- Not focusable and not a button: the remedy is in the main window. `Open`
  still opens it.
- Two stale sources: one line each, at most two, then `+N more sources not
  synced`.
- Never synced: `University timetable has not synced yet`.

### 19.5 Time in status copy

`{last}`, `{when}` and the `Synced …` forms, 24-hour, monospaced digits:

| When | Form |
|---|---|
| Within the last minute | `just now` |
| Today | `today 14:02` (in a sentence) / `14:02` (after `Synced`) |
| Yesterday | `yesterday 14:02` |
| Within the last 6 days | `Mon 14:02` |
| Older | `6 Oct 14:02` (`6 Oct 2025 14:02` in another year) |

The hover-help and popover-status forms are `Synced 14:02`, `Synced yesterday
14:02`. Relative forms update when the popover or Settings is open; nothing
updates on a timer otherwise.

---

## 20. ICS semantics the UI depends on

These are data rules. They are specified here because the UI's promises depend on
them: idempotent, never silent, read-only, past untouched. The CalDAV server
returns iCalendar text. Each calendar object (`calendar-data`) is one
`VCALENDAR`, and on CIS each object holds one `VEVENT`. The parser reads each
object with these rules. It follows RFC 5545 where CIS does, and §20.7.1 records
where CIS does not. How the objects are fetched is §20.8.

### 20.1 Import and sync: what each may write

*(Amended 2026-10-08, CalDAV amendment: data comes from `REPORT`, not a `GET`;
deselecting a calendar is added.)* There is **one Import per source**, then
syncs. They differ only in the window they write and whether they delete:

| | **Import** | **Sync** |
|---|---|---|
| When | The connect sheet's `Import` (`layouts.md` §12.2): the first write for a new source | Every later poll: interval, launch, wake, network, Sync Now, and edit mode's `Save` |
| Data | The events the sheet's `Connect` already fetched with the **Import window** (§20.8.2) and previewed. **No second request** | A new fetch with the **sync window** (§20.8.2) |
| Creates / updates | **Every event fetched**, including those that start before `startOfDay(today)` (the semester's earlier weeks, as history) | Only events whose start is **on or after `startOfDay(today)`** |
| Deletes | **Nothing**: the source has no events yet, so nothing can be absent | Only on proof of absence (§20.8), only on or after `startOfDay(today)` |
| Past | Written **once**, here | **Never** created, updated or deleted, except when the user deselects a calendar (below) |
| Undo | Not an undo step | Not an undo step |

There is **no upper bound**. Both windows are open-ended forward (CIS: the
semester, 14 Sep 2026 – 29 Jan 2027). The Import window reaches back one year
(§20.8.2) — far enough for any semester the feed holds. The only other bound is
on open-ended recurrence (§20.5).

**The server decides how much history there is (added 2026-10-10; G-068).** At
Parsa's first real connection on 9 Oct 2026 the Import returned 91 events from
**22 Sep 2026**, though the semester began on 14 Sep and the request asked for a
year: CIS's CalDAV endpoint serves only a short window of the past (about two
and a half weeks that day), whatever `time-range` is sent. So "the semester's
earlier weeks" means **the earlier weeks the server still serves**. Nothing in
the rules changes — the Import writes every event fetched, the sheet's history
sentence counts what actually came (`21 of them are before today`) — and one
consequence becomes important: because a sync never deletes the past, Kadence
keeps lectures CIS has long stopped serving. **The server's horizon** is the
earliest event start in an Import-window fetch that was read in full; before
it, absence from the feed proves nothing.

**Reconciling "never writes the past".** `DECISIONS.md` 2026-10-01 (the past is
a record) and the 2026-10-08 sync rule both stand **for syncs**. The Import is
the one write that reaches back. At that moment nothing local in the past needs
protecting: the source has no events, so no done/skipped mark, conflict
resolution or selection can be overwritten. From the first sync on, the history
is a record like any other past. A later upstream change to a past lecture (a
room corrected after the fact) is ignored, and a past lecture that vanishes
upstream stays. An event that ends today but started yesterday counts as past
under this rule.

- **Editing the account** (edit mode, `layouts.md` §12.3) is a sync, not an
  Import. This covers a new password, a changed server or username, and adding a
  calendar. The source keeps its events, and its history is not rewritten. A
  calendar added in edit mode contributes from today on: its earlier weeks are
  not imported.
- **Deselecting a calendar** (edit mode's calendar step) deletes the events that
  only that calendar contributed, **history included**. The user is saying so,
  as `DECISIONS.md` 2026-10-08 rules. Events carry no calendar of their own
  (§21.3: hrefs are not identity, and a merge can span calendars), so the rule
  is stated by content:
  1. Edit mode's `Connect` fetches the calendars that stay selected with the
     **Import window**.
  2. `Save` deletes every event of the source whose externalID is not in that
     fetch **and that starts on or after the server's horizon** (above),
     provided the fetch was read in full (§20.8 guards). *(Amended 2026-10-10,
     G-080: was "past or future".)* An event older than the horizon is kept:
     the server no longer serves that week for **any** calendar, so its absence
     is not proof that it belonged to the unchecked one. With an empty fetch
     there is no horizon and nothing in the past is deleted.
  3. If it was not read in full, `Save` deletes nothing for the deselection and
     shows the state. The calendar list is still saved.

  A past lecture inside the horizon that had already vanished from a calendar
  that stays selected is removed by the same `Save`. This is accepted: the user
  asked for the source to hold what its selected calendars hold. Step 2 says how
  many events will go before `Save` (`layouts.md` §12.3). History older than
  the horizon from an unchecked calendar stays until the source is removed;
  that is the cost of not storing a calendar per event (§21.3), and it errs on
  the side of keeping.
- **Removing the source and connecting again** is a new Import. History comes
  back from the server. Local done/skipped marks went with the removal, as the
  alert says (`interactions.md` §13.2).
- **History never conflicts.** Events that start before `startOfDay(today)` take
  no part in conflict detection (§20.9): a resolution would have to write the
  past, which nothing may do.

### 20.2 Identity: externalID and the co-teaching merge

The pair `(sourceID, externalID)` is the identity. `sourceID` is the `Source`'s
id (§21). `externalID` is decided **per VEVENT** by whether its UID can be
trusted to survive a change:

| VEVENT | Identity mode | externalID |
|---|---|---|
| No `RRULE`/`RDATE`/`RECURRENCE-ID`, and its `UID` **contains its own `DTSTART` value as written** (`20260914T143000`) — a UID built from the event's content, as CIS builds it | **content** | the **content key** (below) |
| No `RRULE`/`RDATE`/`RECURRENCE-ID`, any other UID | **uid** | `UID` — or the content key if the event is merged (below) |
| An occurrence of a series (expanded from `RRULE`/`RDATE`), or an override (`RECURRENCE-ID`) | uid | `UID` + `\|` + the occurrence's original start: `yyyyMMdd'T'HHmmss'Z'` in UTC for date-times, `yyyyMMdd` for dates |
| **Flat series**: several VEVENTs share a UID with different `DTSTART`s and no `RRULE`/`RECURRENCE-ID` | uid | `UID` + `\|` + that VEVENT's own `DTSTART`, normalised as above |

**Why content mode.** The CIS UID is `FH` + group + room + lecturer(s) + course +
start + end, run together (`FHBIF-5C HS_A3.15L01SWQM-ILV20260914T143000…`; it
contains spaces and ` / `; with 22 lecturers it is 185 characters in the
redacted export and, per Parsa, over 300 with real names). Any
change to room, time **or lecturer** gives a new UID, and two co-teachers give
two UIDs for one lecture. A UID that encodes the time cannot identify an event
across a move, so nothing is lost by not using it — and keying on content lets a
lecturer change update in place instead of deleting and re-adding the lecture.
The test (UID contains the event's own `DTSTART` digits) is a property of the
data, not a vendor check: no `PRODID` match, no host match.

**The content key** is the string

`{summary}|{location}|{startUTC}|{endUTC}`

where `{summary}` is `SUMMARY` unescaped, every run of whitespace collapsed to one
space, and trimmed (`SWQM-ILV  HS_A3.15 - BIF-5C ` → `SWQM-ILV HS_A3.15 -
BIF-5C`); `{location}` is `LOCATION` treated the same (empty when absent); and
the times are the instants in UTC as `yyyyMMdd'T'HHmmss'Z'` (dates as
`yyyyMMdd` for all-day). Example from the fixture:
`SWQM-ILV HS_A3.15 - BIF-5C|HS_A3.15|20260914T123000Z|20260914T140000Z`. It
contains no lecturer, so a lecturer change keeps it. CIS's `SUMMARY` already
names course, room and group, so for CIS the key is exactly course + room +
group + start + end. The key is not secret and may appear in logs and tests.

**The co-teaching merge.** Two or more non-recurring VEVENTs in one feed with
the **same content key** are **one Kadence event** (the fixture's `BPREF-Info`
on 2 Oct, L05 and L06: same course, room, group and time, two UIDs). Without the
merge, a co-taught lecture is two identical blocks that collide with each other.

- **Merge key** = the content key, in either identity mode.
- **externalID of a merged event** = the content key. It survives a co-teacher
  being **added** (a third VEVENT with the same key joins the group) or
  **removed** (the group shrinks, to one member if need be): the key does not
  change, so the event **updates in place** — `lecturers` changes, `Event.id`,
  `status` and selection are kept. In uid mode an event that becomes or stops
  being a merge changes externalID (UID ↔ content key) and is replaced (delete +
  add) — rare, outside CIS, and accepted.
- **Fields of the merged event:** `lecturers` = the union of the members'
  lecturer lists, members taken in ascending `UID` order and each member's own
  order kept, duplicates dropped — so the order does not depend on the feed's
  VEVENT order and an unchanged feed writes nothing. Every other field is taken
  from the first member in that order (title, location, group and times are
  equal by construction). `isCancelled` only if **every** member is cancelled.
- **Counted, not reported.** A merge is not a problem; the connect sheet's
  summary names how many lectures it merged (`layouts.md` §12.2).

**CalDAV hrefs and ETags are not identity.** *(Added 2026-10-08, CalDAV
amendment.)* Each object comes with an href
(`/webdav/lvplan.php/calendars/user01/LVPlan-user01/obj-07.ics`) and a
`getetag`. Both are transport details and play no part in identity. CIS builds
its objects from the same content as its UIDs, so an href may change whenever
the content does. It may also change when nothing does, as the getctag already
does (§20.8.4). The externalID is decided only by the rules above, from the
VEVENT. A fetch that returns the same VEVENTs under different hrefs and ETags
writes nothing (§22.1, cases `etagsOnly` and `ctagOnly`).

**Across calendars.** The merge and identity apply to the source as a whole.
VEVENTs from two selected calendars with the same content key are one event, so
a lecture listed in two calendars is drawn once. Exact duplicates across objects
follow the tie-break below, as within one object.
**Exact duplicates** — the same UID and the same start twice — are one event:
the higher `SEQUENCE` wins, then the later `LAST-MODIFIED`/`DTSTAMP`. ~~then the
later VEVENT in the file (CIS sends none of these, so the later VEVENT).~~

*(Amended 2026-10-10; G-077.)* **When neither VEVENT wins on `SEQUENCE` or
stamp — always, on CIS, which sends neither — they are not duplicates to choose
between: both go on to the merge**, where they share a content key and become
one event with their lecturers unioned. "The later one wins" silently threw
away the other VEVENT's fields, and it ran before the merge, so two co-teaching
VEVENTs that happened to carry one UID lost a lecturer without being counted as
a merge or as a problem. Two VEVENTs that tie and whose content keys differ
(same UID and start, another summary, room or end) are both kept as separate
events, each under its content key. The order of members inside the merge is
ascending `UID`, then lecturer list joined by `/`, so it never depends on the
feed's order. This is the rule that makes the merge independent of how the
server builds its UIDs — which the first real connection showed is not safe to
assume from the export (§20.8.4, G-068).

`UID` missing: the VEVENT is skipped and counted as a problem (§19.1
`partialImport`) — without an identity it cannot be updated or removed. (In
content mode the UID is not used for identity, but its absence still means the
generator failed; skip it.)

### 20.3 Time zones

**Events display in the Mac's current time zone**, like every other event.

| `DTSTART` form | Interpreted as |
|---|---|
| `…Z` (UTC) | that instant |
| `TZID=Europe/Vienna` — any IANA identifier `TimeZone(identifier:)` accepts (CIS) | wall-clock time in that zone, converted |
| `TZID=` a non-IANA name with a known mapping (the Windows names `W. Europe Standard Time`, `Central Europe Standard Time`, `Romance Standard Time`, `GMT Standard Time`, `UTC`) | the mapped IANA zone |
| `TZID=` anything else | **the Mac's current time zone** at the time of the fetch — kept, and reported as a problem: `{k} events used an unknown time zone ({tzid}) and were read in this Mac's time zone ({zone})` (state `partialImport`; the event is not skipped) |
| Floating (no `Z`, no `TZID`) | wall-clock time in **the Mac's current time zone** at the time of the fetch |

Ruled by Parsa 2026-10-08: no hard-coded Vienna. Consequence, accepted: a
floating event read while the Mac is in another zone gets a different instant;
the next sync after a zone change updates it in place like any time change
(§18.1). CIS always sends `TZID=Europe/Vienna`, so CIS events are unaffected.

`VTIMEZONE` blocks are read past, not interpreted (the identifier is enough for
every zone above; CIS's block describes Europe/Vienna's own rules).
**Recurrences expand in the event's own zone**, by calendar arithmetic, never by
adding 7 × 86 400 s. The CIS feed crosses the DST change on **25 Oct 2026**:
14:30 on 14 Sep is 12:30Z, 14:30 on 2 Nov is 13:30Z, and both draw at 14:30 on a
Mac in Vienna.

### 20.4 All-day

`DTSTART;VALUE=DATE` is all-day: `isAllDay = true`, starting at the date's
`startOfDay` in the user's calendar (dates float — no zone conversion), ending at
`DTEND`'s date (exclusive), or one day later when `DTEND` is absent. Multi-day
entries span their days in the all-day row (§5). Rendered as `.eventAllDay`
(§5.1). All-day events take no part in conflict detection (they are not on the
grid — as for deadlines and exams). CIS sends none; other feeds do.

`DTEND` absent on a date-time: `DURATION` if present, else the event ends at its
start (a zero-length event, drawn at `size.blockMinRenderedHeight`). `DTEND` ≤
`DTSTART` (or a negative `DURATION`): skipped, a problem — except that a
zero-length `DTEND == DTSTART` is kept as above.

### 20.5 Recurrence

CIS sends **no recurrence** — every lecture is its own VEVENT. The subset stays
for other feeds. Supported, and only this — anything else is a problem, never a
guess:

- `RRULE` with `FREQ=DAILY` or `FREQ=WEEKLY`; `INTERVAL`; `COUNT`; `UNTIL` (date
  or UTC date-time, inclusive); `BYDAY` without ordinals (`TU,TH`); `WKST`.
- `RDATE` (date-time or date lists; not `PERIOD`).
- `EXDATE` — removes the occurrence whose original start equals it, compared as
  instants (dates compare as dates).
- `RECURRENCE-ID` overrides — replace the matching occurrence's fields wholesale.
  An override whose `RECURRENCE-ID` matches no generated occurrence is imported
  on its own, same externalID rule. `RANGE=THISANDFUTURE` is treated as a
  single-occurrence override and reported.
- **Open-ended series** (no `COUNT`, no `UNTIL`) expand to `startOfDay(today) +
  366 days` and no further — the one bound in this slice, because "the whole
  feed" of an endless rule is infinite.

An unsupported rule (`FREQ=MONTHLY`, `BYSETPOS`, `BYDAY=2MO`, `BYMONTH` …) skips
**that series and its overrides** and reports it — `1 repeating event uses a rule
Kadence can't read yet: Mathe Tutorium` — because importing only its first
occurrence would look complete and be wrong.

### 20.6 Cancelled, and what a vanished lecture leaves

**CIS never sends `STATUS:CANCELLED`** (none in the real export). A cancelled
CIS lecture **simply disappears from the feed**. What Parsa sees:

1. At the next sync that reads the feed in full (§20.8's guards), the lecture is
   **deleted** from the calendar — proof of absence, as `DECISIONS.md`
   2026-10-08 rules. Its block is gone; if it was selected, the inspector returns
   to the day summary (§20.9).
2. The source's **last-change line** (§19.3; also in Settings, `layouts.md` §11)
   reads `Last change today 14:02: 1 removed` — so a removal is never silent,
   and "the calendar changed" can be checked in one click from the sidebar.
3. A routine block he had shifted for it **stays shifted** (§20.9).
4. Nothing else: no notification (Phase 4, G-060), no ghost of the old block
   (G-067 asks Parsa whether he wants one).

A lecture that **moved** arrives the same way plus an add (§20.10).

**For sources that do send it**, the cancelled presentation stays as specified:
`STATUS:CANCELLED` on a VEVENT, or on an override, imports the occurrence with
`isCancelled = true`. It is **kept and shown** (`cancelled` state, §6) rather
than deleted: "this week's lecture is off" is the most useful thing a timetable
can say when the source is willing to say it. A cancelled event:

- takes **no part in conflict detection** and is never `conflicted`;
- is never the popover's NEXT or in REST OF TODAY, and never counts toward
  `firstEventStart` (`layouts.md` §3.1);
- keeps `status` per §18.1; Done/Skip are refused on it with the inspector line
  `Cancelled by University timetable` (nothing to attend);
- becomes un-cancelled if a later sync drops the `STATUS:CANCELLED`.

### 20.7 Field mapping

Generic mapping, used for every VEVENT that §20.7.1's CIS profile does not
match:

| ICS | Event / inspector | Notes |
|---|---|---|
| `SUMMARY` | `title` | unescaped (`\,` `\;` `\n` `\\`), whitespace runs collapsed, trimmed; empty → `(No title)` |
| `DTSTART` / `DTEND` / `DURATION` | `start` / `end` / `isAllDay` | §20.3, §20.4 |
| `LOCATION` | `location = Place(name:)`, inspector row `Location` | trimmed; address and coordinate nil in this slice; `GEO` ignored |
| `DESCRIPTION` | `importedDescription` (§21), inspector row `Description` | unescaped, line breaks kept; never written to `notes` |
| `ORGANIZER;CN=…` | `lecturers` (one name), inspector row `Lecturer` | the `CN` value; no `CN` → the address after `mailto:`; absent → no row. `ATTENDEE`s are ignored |
| `URL` | `link`, inspector row `Link` | shown as a link (opens in the browser) |
| `STATUS:CANCELLED` | `isCancelled` | §20.6. `TENTATIVE`/`CONFIRMED` are ignored |
| `UID`, `RECURRENCE-ID` | `externalID` | §20.2 |
| `SEQUENCE`, `LAST-MODIFIED`, `DTSTAMP` | tie-breaks | §20.2; not stored; absent is normal (CIS) |
| `VERSION` | — | **not checked**: `1.0` (CIS), `2.0` and absent are all accepted. What makes a body a calendar is §20.8.2 ("A web page where data was expected") |
| everything else (`X-…`, `CATEGORIES`, `CLASS`, `PRODID`, `VALARM` …) | ignored | not a problem |

Line endings: **CRLF and LF** are both accepted (CIS sends CRLF), and a body may
mix them; folded lines (CRLF or LF followed by one space or tab) are unfolded
first. A UTF-8 BOM is skipped. Inside a CalDAV `207`, the XML parser turns
CRLF in `calendar-data` into LF (XML end-of-line handling). Expect LF from
`REPORT` and `calendar-multiget`, and CRLF from a plain `GET`. Both must give
identical events (§20.8.4).

#### 20.7.1 The CIS profile (closes G-056)

Checked against `fixtures/cis-2026WS-redacted.ics` (13 VEVENTs, CRLF,
`VERSION:1.0`, `PRODID:FH Technikum Wien`, one `VTIMEZONE` for Europe/Vienna, no
`DTSTAMP`/`SEQUENCE`/`STATUS`/`RRULE`/`ORGANIZER`/`URL`, `CATEGORIES:StundenplanTW`
on every event):

```
SUMMARY:SWQM-ILV  HS_A3.15 - BIF-5C␠          ← course, two spaces, room, " - ", group, trailing space
DESCRIPTION:SWQM-ILV\nL01\nBIF-5C \nHS_A3.15  ← course \n lecturer(s) \n group \n room
LOCATION:HS_A3.15
```

**Match.** A VEVENT is read with the CIS profile when its `DESCRIPTION`,
unescaped and split on line breaks (trailing empty lines dropped), has **exactly
four lines** and line 1, trimmed, **equals the first whitespace-separated token
of `SUMMARY`**. Otherwise §20.7's generic mapping applies to it, silently (a
non-matching event is not a problem). The match is per event, not per feed.

| Field | From | Rule |
|---|---|---|
| `courseCode` | DESCRIPTION line 1 | trimmed (`SWQM-ILV`) |
| **`title`** (displayed) | `courseCode` | **the course code**, not the SUMMARY — room and group have rows of their own, and SUMMARY's double and trailing spaces are noise. Codes are cryptic (`SWQM-ILV`); friendly names are G-064, not this slice |
| `lecturers` | DESCRIPTION line 2 | split on `/`, each trimmed, empties dropped, order kept (`L10 / L11 / … / L31` → 22 names). Merged events union them (§20.2) |
| `group` | DESCRIPTION line 3 | trimmed (`BIF-5C ` → `BIF-5C`) |
| `location` | `LOCATION`, else DESCRIPTION line 4 | trimmed. The inspector labels it `Room` |
| `isOnline` | `location` | **true when it matches `WEBINAR` + digits, case-insensitive** (`WEBINAR01`, `WEBINAR02`). Shown as `Online` (§18.2); the travel slice plans no travel for it (G-063) |
| `kind` | `courseCode`'s suffix — the text after its **last** `-`, case-insensitive | `EXAM` → **exam**; `ILV`, `UE`, `LAB`, `EL`, `INFO` → **lecture**. **Unknown suffix, or no `-`: lecture** — the presentation every imported timed event already had; no problem is reported, because nothing was lost |
| `importedDescription` | — | **nil**: all four lines have their own fields, so there is no Description row |
| `externalID` | — | content mode (§20.2): CIS UIDs contain their `DTSTART` |

`kind` decides the glyph only (§2.1, amended): **exam** → `graduationcap.fill` on
`.fixedTimed` (and on `.eventAllDay`, should an all-day exam ever arrive);
**lecture** → `building.columns`. Hover help's `Kind` reads `Exam` / `Lecture`;
VoiceOver likewise (§11). No countdown chip: that belongs to `WorkItem` exams
(§5), and an imported exam is an event.

On CalDAV each lecture is its own calendar object (one VEVENT per object, as
in `caldav-mocks.md`); the profile reads the VEVENT and never the object's href
or name.

### 20.8 Discovery, fetch, change detection, and what a sync must never delete

*(Rewritten 2026-10-08, CalDAV amendment.)* The exact requests and the mocked
responses are in `caldav-mocks.md`. The wire rules (HTTPS, redirects, when the
password is sent) are in `interactions.md` §13.1.

#### 20.8.1 Discovery

Discovery finds the calendars of one account. The user sees it as **one step**
(`Connecting to cis.technikum-wien.at…`, `layouts.md` §12.1), never as its
parts.

| # | Request | Expected (CIS, verified 2026-10-08) | Otherwise |
|---|---|---|---|
| D1 | `GET https://{host}/.well-known/caldav` | `301`, `Location: https://cis.technikum-wien.at/webdav/lvplan.php/` → the **context URL** | `301`/`302`/`307`/`308` to another host or to `http:` → `redirected`. `404`, or any other non-redirect answer → `noCalDAV`. Skipped when `Server` holds a path (`layouts.md` §12.1): that path is the context URL |
| D2 | `PROPFIND` Depth 0 on the context URL: `current-user-principal`, `calendar-home-set`, `resourcetype` | `207`; `current-user-principal` = `/webdav/lvplan.php/principals/{user}/`; `calendar-home-set` → `404` in its propstat | Not `207` (`200` HTML, `404`, `405` …) → `noCalDAV`. A `207` without a principal → `noCalDAV`. If `calendar-home-set` comes back `200` here, D3 is skipped |
| D3 | `PROPFIND` Depth 0 on the principal: `calendar-home-set` | `207`; `calendar-home-set` = `/webdav/lvplan.php/calendars/{user}/` | Not `207`, or no home → `noCalDAV` |
| D4 | `PROPFIND` Depth 1 on the home: `resourcetype`, `displayname`, `supported-calendar-component-set`, `cs:getctag`, `sync-token` | `207` with three responses: the home, `LVPlan-{user}/`, `outbox/` | Not `207` → `noCalDAV` |

At any step, a `401` is answered with the password (`interactions.md` §13.1). A
`401` after the password was sent is `unauthorized`, and `403` is `forbidden`.
Hrefs are resolved against the URL of the request that returned them. **An href
that resolves to another host is ignored**: it is never requested, and it is
logged.

**Which D4 responses are calendars.** A response is offered as a calendar only
if **all** of these hold:

1. Its href is not the home's own href.
2. Its `resourcetype` contains `cal:calendar`.
3. Its `resourcetype` contains neither `cal:schedule-outbox` nor
   `cal:schedule-inbox`.
4. Its `supported-calendar-component-set` contains `VEVENT`, or comes back
   `404`/absent, which RFC 4791 says means every component.

On CIS this leaves exactly **`LVPlan`**. It supports `VEVENT` and `VTODO`, and
that is enough. The home and `outbox/` are excluded. Nothing else is ever
selectable, and an excluded collection is never shown. A calendar without a
`displayname` is shown under its href's last path segment, decoded
(`LVPlan-user01`). Zero calendars → `noCalendars`.

**Cached, not repeated.** Discovery runs at `Connect` and in edit mode's
`Connect` (an explicit user act), and at no other time **unless** a request on a
selected calendar answers `404`/`410`, or `301`/`308` to the same host (the
calendar moved; `DECISIONS.md` 2026-10-08). Then, once per sync:

- D1–D4 run again.
- Each selected calendar is matched first by href, then by `displayname`. A name
  match counts only when exactly one listed calendar has that name. A matched
  calendar's new href is adopted silently and logged.
- The calendar is fetched again.
- A calendar that matches nothing is `calendarMissing`.

The source stores the principal, the home and the selected calendars (§21.1).
D1–D4 cost at most **4 requests**.

#### 20.8.2 Fetching events

**Windows.** Each selected calendar is read with one `REPORT calendar-query`
(Depth 1). Its filter is `VCALENDAR` › `VEVENT` › `time-range` with a `start`
and **no `end`** (open-ended, as RFC 4791 §9.9 allows):

| Window | `start` | Used by |
|---|---|---|
| **Import window** | `startOfDay(today)` **minus one calendar year** (`Calendar.date(byAdding: .year, value: -1)` in the Mac's zone), in UTC (`20251007T220000Z` for today = 8 Oct 2026, Vienna). *(Corrected 2026-10-10, G-071: the formula read "− 366 days", which gives `20251006T220000Z` and contradicted its own pinned value. One calendar year is what is meant and what is built. On 29 Feb it is 28 Feb of the year before.)* | `Connect` and edit mode's `Connect` (the step-2 preview, the Import, a deselection) |
| **Sync window** | `startOfDay(today)`, in UTC (`20261007T220000Z`) | every sync |

The request asks for `getetag` and `calendar-data`, with no `expand`, and
expands recurrence itself (§20.5). **The time-range is a saving, not a rule.**
A server may ignore it. The planner applies the window (§20.1) whatever comes
back. Here is how the source records whether the server honoured it
(`SourceCapabilities.timeRangeHonoured`, §21.1):

- An event that ends on or before `start` came back: `false`.
- Otherwise: `true`.
- Overlapping events are correctly returned, so they do not count.

**Fallback chain** — used only when a step is **refused** with `405` or `501`.
Any other failure maps to §19.1 at that step (`401`, `403`, `5xx`, a web page
…) and ends the chain.

| Step | Requests | Then |
|---|---|---|
| F0 | `REPORT calendar-query` with the window | `207` → read |
| F1 | `PROPFIND` Depth 1 on the calendar (`getetag`, `resourcetype`, `getcontenttype`, `cs:getctag`) → member hrefs, collections excluded; then `REPORT calendar-multiget` for those hrefs, in batches of **100** | `207` → read. F1 has no time-range: everything comes back, and the planner filters |
| F2 | `GET` of each member href from F1's `PROPFIND`, one at a time | `200` with a calendar body → read |
| — | F2 refused too (`405`/`501`) | `fetchFailed`, nothing written. Technical line: `REPORT 405 · PROPFIND 207 · calendar-multiget 501 · GET 405` |

- **Silent unless it fails.** A fallback that works raises no state, problem or
  line in the UI. It is recorded in two places: in
  `SourceCapabilities.fetchMode` (`report` / `multiget` / `get`), and in the
  diagnostics log line (§20.8.4).
- **Remembered.** Later polls start at the recorded mode instead of being
  refused again every 30 minutes. The mode resets to `report` on re-discovery
  and on edit mode's `Save`.
- **A `207` with a failed member** (a `propstat` other than `200` for
  `calendar-data`, or a member `status` `404`) is a problem for that object
  (`partialImport`), not a failure of the calendar.

**Request cap, per source per sync:**

| Path | Requests |
|---|---|
| Normal (F0) | **1 per selected calendar — 1 for CIS** |
| + re-discovery (only after a `404`/`410`/`301`/`308`, §20.8.1) | + at most 4, then the calendar's fetch again |
| F1 | + 1 `PROPFIND` + ⌈objects ÷ 100⌉ `calendar-multiget` |
| F2 | + 1 `PROPFIND` + 1 `GET` per object |
| **Hard cap** | **300 requests.** A sync that would send the 301st stops before it: `fetchFailed`, nothing written, technical line `Request cap reached (300) reading {calendar} one object at a time` |

- Requests are **sequential**, never parallel: one university server, one
  request at a time.
- A `401` answered with the password is the same request retried once, and is
  not counted again.
- **In `get` mode, automatic polls run at most every 6 hours**:
  `max(pollInterval, 6 h)`. One sync in that mode can cost a request per object,
  and the half-hour interval was chosen for one request. Sync Now is not limited.
  Settings shows nothing of this (G-068 will show whether `get` mode can happen
  on CIS at all).
- **Size limits:** one response over **20 MB**, or one object's `calendar-data`
  over **1 MB**, is not read. The response → `notACalendar`. The object → a
  problem.

**A web page where data was expected.** Two cases are `notACalendar`:

- a `200` whose body is not XML where a `207` was expected (F0, F1), or a
  non-calendar body to F2's `GET`;
- an object whose `calendar-data` does not start with `BEGIN:VCALENDAR` (after
  an optional BOM and whitespace) and contain `END:VCALENDAR`.

`Content-Type` is not trusted either way. The same check fails a single object
inside a good `207` as one **problem**, not as `notACalendar`.

#### 20.8.3 One sync of one source

1. **Read the password** from the Keychain (§21.4). If it is missing or access
   is denied → `passwordMissing`, and no request is sent.
2. **Fetch** each selected calendar in `Source.calendars` order (§20.8.2) with
   the sync window, re-discovering once if a calendar answers `404` or moved
   (§20.8.1).
3. **Parse each object** (§20.3–§20.7). **Derive identities and merge across
   all selected calendars** (§20.2), and expand (§20.5).
4. **Change by content** (§20.8.4). If the feed hash of the events in the write
   window equals `Source.feedHash`, **stop**: no event is created, updated or
   deleted, and `lastChange*` stays as it is.
5. **Diff** against this source's stored events **on or after
   `startOfDay(today)`**, by externalID:
   - **Create** the new.
   - **Update** an event whose event hash differs from the stored event's, and
     write only the fields that differ.
   - **Delete** the absent, under the guards below.

   Events before `startOfDay(today)` are not in the diff at all (§20.1).
6. **Apply in one store transaction**. Record `feedHash`, the counts, the
   problems, the change summary (§19.3) and the state (§19.1). Write one
   diagnostics log line (§20.8.4).

Only the bookkeeping fields `lastAttemptAt`, `lastSuccessAt`, `state`,
`stateDetail` and `problems` are written on every poll. They describe the poll,
not the timetable.

#### 20.8.4 Change by content — the server's markers are diagnostics

The CIS server sends **no `sync-token`** (`404` in D4). Its `getctag` is the
**time of the request**: `LVPlan-user01-1791454967`, and 55 s later
`LVPlan-user01-1791455022`. So it changes when nothing did, and its ETags may do
the same (G-068). Change is therefore decided **by content only**
(`DECISIONS.md` 2026-10-08 "Change is detected by content…"):

- **Event hash** — SHA-256, lower-case hex, of the UTF-8 string made of these
  fields **in this order**, joined by U+001F:
  1. externalID
  2. title
  3. start, as `yyyyMMdd'T'HHmmss'Z'` in UTC (`yyyyMMdd` when all-day)
  4. end, in the same form
  5. isAllDay (`1`/`0`)
  6. location (empty when nil)
  7. isOnline (`1`/`0`)
  8. courseCode (empty when nil)
  9. group (empty when nil)
  10. lecturers, joined by U+001E, in the merged order (§20.2)
  11. kind (`lecture`/`exam`)
  12. description (empty when nil)
  13. link (empty when nil)
  14. isCancelled (`1`/`0`)

  These are exactly `ExternalEvent`'s upstream fields (§21.5). UID, href, ETag,
  `DTSTAMP`, `SEQUENCE` and `LAST-MODIFIED` are **not** in it. A stored `Event`'s
  hash is computed from its stored upstream fields the same way, when it is
  compared. **Per-event hashes are never stored.**
- **Feed hash** — SHA-256 hex of the event hashes of every event **in the write
  window** (Import: all; sync: start ≥ `startOfDay(today)`), sorted ascending
  and joined by `\n`. It is stored as `Source.feedHash`. It changes when a day
  passes and an event leaves the window. Step 5 then finds nothing to write, and
  the new hash is stored.
- **What the hashes guarantee** (tested, `PHASE3-PLAN.md` tasks 4 and 8):
  - The same VEVENTs in another order, under other hrefs or ETags, with another
    getctag, or with `\r\n` turned into `\n` by the XML parser give the same
    feed hash, so nothing is written.
  - A lecturer added to a co-taught lecture changes one event hash, so exactly
    one update is written.
- **Diagnostics, never decisions.** The getctag (when a response carries one —
  D4 and F1; it is **never requested for its own sake**), the ETags, the fetch
  mode, the request count and the duration go into **one log line per sync**,
  through the source logger (§21.4), in the app's unified-log subsystem,
  category `sync`:

  `sync user01 @ cis.technikum-wien.at · LVPlan · mode report · requests 1 · 412 ms · objects 287 · time-range honoured · ctag — · etags 287 (set 3f9a01c2) · feed unchanged`

  `etags … (set …)` is the first 8 hex digits of SHA-256 over the sorted
  `href=etag` lines. Two polls of unchanged content with the same set prove that
  ETags are stable (G-068). Nothing in the app reads these values back.

  *(Amended 2026-10-10, G-068.)*
  - **Subsystem.** The lines are logged under subsystem **`XIX.Kadence`** (the
    bundle identifier), category `sync`. A predicate on the category alone also
    matches Apple's own `sync` categories, so the command is always written
    with both:

    ```
    log show --last 1h --info --predicate 'subsystem == "XIX.Kadence" AND category == "sync"'
    ```
  - **Three more fields**, after `objects`: `vevents {v}` (VEVENTs read, before
    anything is dropped), `duplicates {d}` (VEVENTs replaced by a strict
    `SEQUENCE`/stamp winner, §20.2) and `merged {m}` (events that are a merge of
    two or more VEVENTs). A co-taught lecture that arrives as one VEVENT, or as
    two, is then visible in the log without reading the store:

    `sync user01 @ cis.technikum-wien.at · LVPlan · mode report · requests 1 · 412 ms · objects 287 · vevents 287 · duplicates 0 · merged 9 · time-range honoured · ctag — · etags 287 (set 3f9a01c2) · feed unchanged`
  - **The connect sheet's fetch is logged too**, as one line of the same shape
    that starts `connect` instead of `sync` and ends `previewed {n} events`
    (no `Source` exists yet, so the logger takes the account string). The
    Import itself makes no request and logs `import {account} · {n} events ·
    {h} before today`.
  - *(Amended 2026-10-14; G-077 record.)* **Copies are not co-teaching.**
    CIS's CalDAV serves some lectures as two calendar objects that are byte
    for byte the same VEVENT (same UID, same lecturer). They tie (§20.2), go
    to the merge and are one event — correct — but they were counted in
    `merged`, and the connect sheet called them co-taught. One more field,
    after `merged`: `copies {c}`, the merges whose members all carry the same
    lecturer list (order ignored), so the union added nothing. `merged`
    keeps counting every merge; `merged − copies` is the co-teaching.
    `layouts.md` §12.2's sentence counts `merged − copies` only; copies are
    not mentioned in the UI, because there is nothing to tell the user and
    nothing lost. Parsa's connect line of 14 Oct would read
    `… vevents 87 · duplicates 0 · merged 2 · copies 2 · previewed 85 events`.
  - **`ctag —` in `report` mode is correct, and stays.** The getctag is a
    property of the collection; a `REPORT` returns objects, not the collection,
    so there is no ctag to record, and asking for one would cost a second
    request per poll for a value known to be the time of the request. It is
    logged only when a response happens to carry it (D4 at `Connect`, F1).

#### Guards — **deletion only on proof of absence**

- A failed fetch (any §19.1 error state) contributes **no deletions** and no
  writes at all.
- A feed with `partialImport` problems contributes creates and updates but **no
  deletions**: an object that could not be read may be the one that looks
  absent. On CIS a moved lecture then shows twice, old and new, until a clean
  sync. The state says `Imported with problems`, so this is visible, not silent.
- **Every selected calendar must be read in full.** With several calendars, one
  in `calendarMissing`, `fetchFailed` or any other error means **no deletions**
  for the source. The merge spans calendars (§20.2), so an event that looks
  absent may belong to the calendar that could not be read. Creates and updates
  from the calendars that were read are applied, and the state is the failing
  calendar's.
- A fetch that returns **zero** VEVENTs when the last full read had events
  (`lastFeedEventCount` > 0) is `emptyFeed` and contributes no deletions. An empty
  calendar at the Import is just empty.
- The Import window's re-read in edit mode follows the same guards before a
  deselection deletes anything (§20.1).
- Removing the source **does** delete its events: that is the user saying so.

**Idempotency** is testable as stated:

- Two syncs of the same content → the second writes nothing (step 4 stops it).
  With step 4 disabled in a test, step 5 still writes nothing.
- Every `Event.id` is unchanged.

Local identity: an updated event keeps its `Event.id`, so selection, the
inspector and any `TravelLeg` keyed by it survive a sync.

### 20.9 Sync, conflicts, selection and undo

- **Conflicts** are recomputed after every write, by the Phase 2 engine,
  unchanged: an imported event conflicts with a routine occurrence exactly as §14
  defines, the options edit only the routine side, and the needs-attention count
  includes the new ones. **Excluded:** cancelled events (§20.6) and events that
  start before `startOfDay(today)` (§20.1 — history never conflicts). Merged
  co-teaching duplicates never reach the engine as two events (§20.2).
  **Two imported events never conflict with each other** *(stated 2026-10-10)*,
  whether from one source or two: a conflict is a routine occurrence against
  an imported or manual event (§14), its options edit only the routine side,
  and nothing Kadence could offer would resolve two lectures the university
  scheduled on top of each other. They are drawn by `layouts.md` §3.3 —
  packed, or cascaded with §3.3's title band and gap — and are not counted in
  Needs attention. A conflict
  whose imported side a sync removes or moves disappears or changes on recompute
  — no special handling. A routine occurrence the user already shifted for a
  lecture that later vanishes or moves **stays shifted**: it is detached (§13.7)
  and the user's resolution stands; if the moved lecture now collides with
  something else, that is a new conflict, offered as any other.
- **A sync never lands during a preview.** While a conflict preview is active
  (§14.4) a finished sync's writes are **held** and applied when the preview ends
  (applied or abandoned); the canvas never changes under a hypothetical. The
  Import cannot coincide with a preview (Settings' sheet is modal to Settings,
  not to the main window — if one is active, the Import is held the same way).
- **Selection:** a selected event a sync deletes is deselected and the inspector
  returns to its day summary. A selected event a sync updates stays selected.
- **Undo:** sync and Import writes are not undo steps and do not clear the
  stack. Undo/redo steps that address an event a sync deleted are **dropped**
  from the stack (the Edit menu never offers an action that would do nothing).
- **Removed sources** remove their events in one store transaction, after
  confirmation (`interactions.md` §13.2); it is not undoable — the Keychain item
  is gone — and the alert says what reconnecting restores.

### 20.10 A moved lecture (CIS: delete + add)

On CIS a change of **room or time** changes the content key (§20.2), so the
lecture arrives as one deletion (old key, absent) and one creation (new key) in
the same sync. A change of **lecturer** does not: it updates in place. Rules for
the delete + add, all following from rules above, stated so nobody adds a
heuristic:

| Local state on the old event | After the sync |
|---|---|
| `status` `.done` / `.skipped` | **Not carried over.** The new event starts `.scheduled`. Kadence does not guess that "SWQM-ILV in A3.13" is "SWQM-ILV in A3.15 moved" — two lectures of one course on one day are ordinary. (Marking a future lecture done is rare; one moved after being marked is rarer.) |
| Deletion guard | The old event is deleted only on proof of absence (§20.8). If the sync has `partialImport` problems, the old one stays beside the new until a clean sync |
| Old event in the past | Untouched: the past is not in the diff (§20.1). Only the new event is created, and only if it is on or after today |
| A conflict resolution applied against the old event | The routine occurrence stays where the user put it (detached, §13.7). The old conflict disappears with the old event; the new event's conflicts, if any, are new |
| Selection, undo steps | §20.9: deselected; steps addressing the old event dropped |
| Last-change line | Counts `1 added · 1 removed` — which is what happened upstream |

---

## 21. Data model additions

*(Rewritten 2026-10-08, CalDAV amendment, to match `DECISIONS.md` 2026-10-08
"Sources become records…".)* BRIEF-PRODUCT's draft has no record for a source at
all: sources are a static list in `MockData.sources`. These are SwiftData
`@Model`s, with enum fields stored as raw strings, like `Event`'s.

### 21.1 `Source`

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | A UUID string for a new source. **A String, not a UUID**, because `Event.sourceID` is already `String` and the mock sources use slugs (`timetable`) |
| `kind` | `CalendarSourceKind` raw | `.universityTimetable` for this slice. It sets the §10.1 symbol |
| `connection` | raw `String`: `local` / `caldav` | `local` for routine, manual and mock sources. A raw string, so another transport can be added without a migration (G-065) |
| `displayName` | `String` | Default `University timetable`. Renamable in Settings |
| `paletteKey` | `SourceKey` raw | At creation: the first slot in `color.sourcePalette.order` **other than `graphite`** that no other `Source` uses; when all seven are used, the least-used of them (ties: the earlier in the order). **Never `graphite` for a connected source** *(amended 2026-10-10, G-075)*: `graphite` is `Personal`'s — manual events — and a timetable drawn in it is indistinguishable from them. The user cannot change it in this slice. In the review dataset the timetable keeps `blue` (§22.1) |
| `symbolOverride` | `String?` | As `CalendarSource` |
| `isVisible` | `Bool` | The sidebar checkbox, now persisted. **It is the only visibility state**: there is no set of hidden palette slots (§21.1.1) |
| `serverURL` | `String?` | **What the user typed, normalised**: `https://` + host (lower-cased) + port when not 443, + the path when one was typed (`https://cis.technikum-wien.at`). `{host}` in §19 is its host |
| `username` | `String?` | `user01`. **Not secret**: it is shown as `{user} @ {host}` (`layouts.md` §11) and is the Keychain item's account (§21.4) |
| `principalHref` | `String?` | From D2 (`/webdav/lvplan.php/principals/user01/`). Absolute path on `serverURL`'s host |
| `calendarHomeHref` | `String?` | From D3 (`/webdav/lvplan.php/calendars/user01/`) |
| `calendars` | `[SourceCalendar]` (Codable JSON) | The **selected** calendars, in display order: `SourceCalendar { href: String; displayName: String }`, e.g. `/webdav/lvplan.php/calendars/user01/LVPlan-user01/`, `LVPlan`. Never empty for a connected source |
| `capabilities` | `SourceCapabilities` (Codable JSON) | `fetchMode` (`report` / `multiget` / `get`, §20.8.2), `timeRangeHonoured: Bool?` (nil until the first `REPORT`), `discoveredAt: Date` |
| `pollInterval` | `Int` (seconds) | Default **1800**. One of `interactions.md` §13.3's values |
| `isAutoSyncPaused` | `Bool` | Set by a 401/403 (`interactions.md` §13.3). Cleared by edit mode's `Save` or by a successful Sync Now |
| `importedAt` | `Date?` | When the Import wrote. Nil before that. A source with `importedAt == nil` that syncs anyway (review seeding) treats its first successful write as the Import (§20.1) |
| `lastAttemptAt` | `Date?` | |
| `lastSuccessAt` | `Date?` | `{last}` in §19 |
| `feedHash` | `String?` | §20.8.4. Set only by a sync that read **every** selected calendar in full. Not secret |
| `lastFeedEventCount` | `Int` | VEVENTs in the last full read, before the merge. Used by the `emptyFeed` guard |
| `state` | raw, §19.1's names | |
| `stateDetail` | `String?` | The substituted body sentence for the last problem set. It **never** contains a password, an `Authorization` header or a request body (task 7's test) |
| `problems` | `[ImportProblem]` (Codable JSON) | Line, sentence and technical line: what `Show Details` lists |
| `lastEventCount` | `Int` | `{count}`: this source's events in the store |
| `lastChangeAt`, `lastChangeAdded`, `lastChangeUpdated`, `lastChangeRemoved` | `Date?`, `Int` ×3 | The last-change line (§19.3, §20.6). Set only by a sync that wrote |

**The password is never a field**, and no field can hold it (§21.4). The
display form `{username} @ {host}` is computed and not stored.

#### 21.1.1 A source is identified by its id, never by its colour (added 2026-10-10; G-075)

Found in real use: Parsa's imported lectures drew grey, read `Personal · {room}`
and showed the person glyph in the inspector. The build resolved an event's
source **by palette slot** (`SourceCatalog.name(for: event.sourceKey)`, the
inspector's swatch, the sidebar checkbox's hidden set). The new source had been
given `graphite` — the old fallback, every other slot being held by leftover
mock sources (§22.1 says how they got there) — so it shared a slot with
`Personal`, and the lookup returned whichever record sorted first. A colour is
a property of a source; it cannot be its key.

- **Resolution.** An event's source is the `Source` whose `id` equals
  `Event.sourceID`. Its name, symbol, palette slot, state and visibility all
  come from that record. Nothing — block, inspector, popover, hover help,
  VoiceOver, filter — looks a source up by `SourceKey`.
- **Events without a `sourceID`** belong to a built-in source by origin:
  `.manual` → `personal`, `.routine` → `routine`. `Event.sourceID` is set at
  creation from then on; existing rows without one are resolved by this rule
  at read time (no migration write is required).
  *(Amended 2026-10-14; DEVIATIONS B46 accepted.)* **Except routine
  instances:** a materialised routine instance's `sourceID` is its
  template's id, because it is half of §13.6's `(sourceID, externalID)` pair
  that materialisation, withdrawal, tombstones and Re-sync key on. A
  `sourceID` that names no `Source` record resolves by origin exactly as a
  missing one does, so a routine instance is `Daily routine`. The rule that
  matters is unchanged: every lookup goes through a record or the origin,
  never through the slot.
- **Colour.** A block's hue is its source's `paletteKey`, read from the record.
  `Event.sourceKey` remains as the stored copy written at creation and is not
  consulted when the record exists.
- **Visibility** is `Source.isVisible` on the resolved record, persisted.
  Unchecking `Personal` hides manual events and nothing else.
- **Built-in local sources.** Every store has exactly two `local` sources,
  created at first launch if missing, idempotently, with fixed ids — they are
  the app's own taxonomy, not fixture data, because this build has a creator
  for each (`⌘N`; the Routines window):

  | id | Name | Kind → symbol (§10.1) | Slot |
  |---|---|---|---|
  | `personal` | `Personal` | manual → `person.fill` | `graphite` |
  | `routine` | `Daily routine` | routine → `rectangle.stack.fill` | `green` |

  **No other local source exists in a real store.** `Exams`, `Mail
  appointments`, `Coursework`, `Social`, `Planned study` and the mock
  `University timetable` are review fixtures for phases not built yet; each
  arrives as a real source with the phase that gives it a creator. Production
  code never reads `MockData.sources`.
- **Never two rows for one thing.** The sidebar lists `Source` records, sorted
  built-ins first (`Personal`, `Daily routine`), then connected sources by
  name. A connected source and a `local` one never share a display name in a
  real store, because no `local` timetable exists there.

*(Removed with the subscription)*: `displayHost` (the host now comes from
`serverURL`), `usesSignIn` (an account always signs in), `etag`,
`lastModifiedHeader`, `lastBodyHash` (replaced by `feedHash`; validators are not
used, §20.8.4). *(Never added)*: a stored ctag, sync-token or per-object ETag.
These are diagnostics, which are logged and never stored (`DECISIONS.md`
2026-10-08).

### 21.2 No `SourceFile`

There is no `SourceFile` and no record of calendar objects. Hrefs are not
identity (§20.2), and the events are the record. A selected calendar is the
`SourceCalendar` value above.

### 21.3 `Event` additions

| Field | Type | Notes |
|---|---|---|
| `isCancelled` | `Bool` = false | §20.6. Sync-owned |
| `importedDescription` | `String?` | §20.7. Kept apart from the user's `notes`, so a later "your notes on a lecture" feature (G-058) never collides with upstream text. Nil for CIS-profile events |
| `lecturers` | `[String]` = [] | §20.7, §20.7.1. Up to 22 on CIS |
| `courseCode` | `String?` | §20.7.1. The title source for CIS events, and the key a future alias would use (G-064) |
| `group` | `String?` | §20.7.1 |
| `isOnline` | `Bool` = false | §20.7.1. Read by §18.2 and by the travel slice |
| `importKind` | raw `String` = `lecture` | `lecture` / `exam`. §20.7.1. Sets the glyph (§2.1) |
| `link` | `String?` | §20.7 (generic feeds) |

These are exactly `DECISIONS.md`'s list. **No href, ETag or calendar field**:
which calendar an event came from is not stored (§20.1 says how deselection
works without it). These stay as they are today:

- `origin == .imported`, `sourceID`, `externalID`, `flexibility == .fixed` and
  `isLocked == false`. Read-only comes from `origin`, not from `isLocked`, which
  stays the user's own lock on manual events.
- `location` keeps carrying the room as `Place(name:)`.

### 21.4 The password — the only secret

**One Keychain internet-password item per source** (`DECISIONS.md` 2026-10-08):

| Attribute | Value |
|---|---|
| `kSecClass` | `kSecClassInternetPassword` |
| `kSecAttrServer` | the host (`cis.technikum-wien.at`) |
| `kSecAttrPort` | 443, or the explicit port |
| `kSecAttrProtocol` | `kSecAttrProtocolHTTPS` |
| `kSecAttrAuthenticationType` | `kSecAttrAuthenticationTypeDefault` |
| `kSecAttrAccount` | the username (`user01`) |
| `kSecAttrSecurityDomain` | `Kadence` |
| `kSecAttrCreator` | `'Kdnc'` (four-char code) |
| `kSecAttrComment` | the `Source.id` |
| `kSecAttrLabel` | `Kadence — {displayName}` |
| `kSecAttrAccessible` | `kSecAttrAccessibleAfterFirstUnlock`: background sync runs while the screen is locked |
| `kSecAttrSynchronizable` | `false` |
| `kSecValueData` | the password, UTF-8. **Nothing else**: no JSON, no URL |

- **Kadence's item only.** Every query carries the server, account, protocol,
  security domain and creator, so Kadence never reads or replaces an item that
  another app saved for the same account. Apple Calendar is the one that matters
  here.
- **One source per account.** A second source with the same host and username is
  refused at `Connect` (`layouts.md` §12.1), so (server, account, security
  domain) is unique.

**Handling the password.** It enters memory only to answer a challenge. ~~It
goes into a `URLCredential` with `.none` persistence, built for that sync.~~
*(Amended 2026-10-10, accepting DEVIATIONS B40.)* **Kadence builds the
`Authorization` header itself** (`ChallengeResponder`: Basic, or Digest
MD5 / `qop=auth`) in answer to the host's `401`, and Foundation is given no
credential at all: the session delegate declines every password challenge, so
no `URLCredential`, credential storage or protection-space cache is involved.
This is accepted because it makes "sent only after that host's `401`" a
property of one function that every test can observe on the wire. It carries
one obligation the `URLCredential` form did not: **Foundation copies a manually
set header onto a redirected request**, so the design is safe only while no
redirect is ever followed by the transport. That is already the rule ("The
transport never follows a redirect itself", below); with this amendment it is
a **security invariant with required tests** (`interactions.md` §13.1, "What
the tests must prove"). It is
never kept in a property that outlives the sync. It never appears in
`UserDefaults`, the store, a log line, an error's description, `stateDetail`, a
problem line, an accessibility value, hover help, a fixture, a test assertion
message, a screenshot or the repo. `SecureField` is the only view that ever
holds it.

**What is not secret, and may be shown and logged:** the server, username,
principal and home hrefs, calendar names and hrefs, object hrefs, ctags, ETags,
methods, statuses and durations. Every log line about a source goes through
**one source logger** that takes a `Source`, never a request. It writes the
§20.8.4 line and errors in §19.1's vocabulary. It never logs a header or a body.

**No on-disk HTTP state.** The transport's `URLSession` uses an **ephemeral**
configuration: `urlCache = nil`, `urlCredentialStorage = nil` (the credential is
given per challenge and never stored by Foundation), and cookies kept in memory
for the sync only. **The transport never follows a redirect itself.** Its
delegate returns `nil`, and the CalDAV client decides (`interactions.md` §13.1).

### 21.5 `ScheduleSource`, amended

BRIEF-PRODUCT's `fetchEvents(in:) async throws -> [ExternalEvent]` cannot carry
partial failure, a window or what discovery learned. *(Amended for CalDAV.)*

```swift
protocol ScheduleSource: Sendable {
    func fetch(windowStart: Date) async throws(ScheduleSourceError) -> ScheduleFetchResult
}
struct ScheduleFetchResult: Sendable {
    var events: [ExternalEvent]            // merged across the selected calendars (§20.2)
    var problems: [ImportProblem]
    var objectCount: Int                   // VEVENTs read, before the merge — the emptyFeed guard
    var mergedCount: Int
    var calendarsReadInFully: [String]     // hrefs; the deletion guard (§20.8)
    var failedCalendars: [(SourceCalendar, ScheduleSourceError)]
    var adoptedCalendars: [SourceCalendar] // after a re-discovery, the new hrefs (§20.8.1)
    var capabilities: SourceCapabilities
    var diagnostics: SyncDiagnostics       // the §20.8.4 log line's values; never stored
}
struct ExternalEvent: Sendable, Equatable {
    var externalID: String; var title: String; var start: Date; var end: Date
    var isAllDay: Bool; var location: String?; var isOnline: Bool
    var courseCode: String?; var group: String?; var lecturers: [String]
    var kind: ImportKind; var description: String?; var link: String?
    var isCancelled: Bool; var sequence: Int; var stamp: Date?
}
```

- **Every event, any window.** `fetch` returns every event the server returned.
  `windowStart` only sets the `REPORT`'s time-range (§20.8.2). The **sync
  planner** applies the Import or sync window (§20.1), computes the hashes and
  decides "unchanged" (§20.8.4). There is no `.unchanged` result: the server
  cannot say so.
- **Errors.** `throws` covers the states that end the whole fetch:
  `unauthorized`, `forbidden`, `noCalDAV`, `noCalendars`, `certificate`,
  `passwordMissing`, `redirected`, `unreachable`, `serverError`, `offline`. The
  per-calendar states (`calendarMissing`, `fetchFailed`, `notACalendar`) arrive
  in `failedCalendars`. `emptyFeed` and `partialImport` are decided by the
  planner.
- **The concrete source.** `CalDAVScheduleSource` = `CalDAVDiscovery` (§20.8.1)
  + `CalDAVClient` (§20.8.2) + the parser + the derivation. The connect sheet
  uses `CalDAVDiscovery` and `CalDAVClient` directly, before any `Source`
  exists.
- **The mock.** A `MockScheduleSource` returns fixture results directly, as the
  brief's architecture requires.

---

## 22. What Phase 3 must render for review

*(Amended 2026-10-08, CalDAV amendment.)* The same rules as §17 apply: display
fixtures, mocked services, and all six of §17.2's evidence rules. **No item
needs a real server, a real password or network access.** In review, every
source is served by the mocked CalDAV transport of §22.1 (`caldav-mocks.md`).
The only account it shows is the **review account** `user01 @
cis.technikum-wien.at`. A password is only ever drawn as `SecureField` bullets.

1. Sidebar, first run: no connected source, and the `Connect Timetable…` row
   (`layouts.md` §2.1)
2. Connect sheet, step 1: empty (`Server` prefilled, `Connect` disabled), and
   filled (`user01`, a password as bullets)
3. Step 1 while connecting: spinner and `Connecting to cis.technikum-wien.at…`
4. Step 1 failures:
   - `unauthorized`: `Password` focused with its contents selected
   - `certificate`
   - `noCalDAV` (case `wellKnown404`)
   - the WebDAV-share validation message
5. Step 2 with **one** calendar (case `reportOK`):
   - the **single confirmed row** `LVPlan` (no checkbox)
   - `user01 @ cis.technikum-wien.at`
   - `13 events, {first} – {last}`
   - the history sentence with `2`
   - the co-teaching sentence with `1`
6. Step 2 with **several** calendars (case `multiCalendar`): the checklist, with
   `LVPlan` and `Prüfungen` checked. The `Aufgaben` (VTODO-only) and `outbox`
   collections are absent
7. Edit mode (`Update Password…`): `Server` and `Username` prefilled, `Password`
   empty with its `Saved in Keychain` placeholder and focused
8. Settings ▸ Sources, `upToDate`, nothing selected in the form:
   - `Account` `user01 @ cis.technikum-wien.at`
   - `Calendar` `LVPlan`
   - `Sync` `Every 30 minutes`
9. The sidebar row in four states, one frame each or one offscreen render of the
   row at all four (§17.2 rule 3 applies):
   - `syncing` (spinner)
   - `upToDate` (empty slot)
   - `transient` (secondary glyph)
   - `actionable` (alert glyph)
10. The source popover in `forbidden`, and in `partialImport` with details
    expanded
11. Week view of fixture week `M` (§22.1):
    - the lectures
    - `REQEN-EXAM` with `graduationcap.fill`
    - `INNO3-EL` reading `Online` at `.full`
    - Friday's co-taught `SWRM-ILV` as **one** block, `conflicted` against
      `Training`
12. After the second sync (case `reportChanged`):
    - week `M` with `SWEN3-LAB` in its new room and `EPC-ILV` gone
    - the source popover's `Last change …: 2 added · 2 updated · 2 removed`
13. Inspector, `SWQM-ILV` selected:
    - the read-only line
    - `Lecturer`, `Group`, `Room`
    - Source row `University timetable` with its swatch and sync line
    - no Description
14. Inspector, `INNO3-EL` selected:
    - `Lecturers` collapsed (`L10`, `L11`, `L12`, `and 19 more`) and expanded
    - `Room` `Online · WEBINAR01`
15. A refused edit: the inspector's read-only line in its emphasised state after
    `⌫` (`interactions.md` §13.4)
16. Conflict panel on Friday's `SWRM-ILV` × `Training`:
    - three options
    - row 1 `Shift Training 45 min later`, recommended and previewed
    - the canvas border
    - footer `k of 15`, with `k` per §22.1
17. Popover with an imported NEXT: `Done` · `Open`, no `Snooze`. Then the same
    popover with the stale line (offscreen renders per §17.2 rule 3)
18. The removal confirmation alert
19. An `.eventAllDay` pill (the review mode's manual all-day event, §22.1) and a
    `.fixedTimed` block in `done`, light and dark: the G-054 contrast fix.
    INDEX.md names the appearance
20. The `cancelled` state, block and inspector, as an offscreen render of the
    real views fed `edge-cases.ics`'s cancelled event. §17.2 rule 3 applies: no
    source in review sends `STATUS:CANCELLED`
21. The source popover in `calendarMissing` (case `calendarGone`), with `Choose
    Calendar…` as the default button

**Added 2026-10-10 (Phase 3 slice 1 review) — the real-use set.** Items 1–21
are all drawn from the Phase 2 dataset with a timetable added, and that is why
they missed every defect Parsa's first real week showed: none of them puts a
connected source in a store that looks like a real one, and none overlaps two
lectures. Items 22–27 use the two datasets added in §22.1 (`empty`, `fresh`).

22. **A real first run** (dataset `empty`): the sidebar lists exactly
    `Personal` and `Daily routine`, then `Connect Timetable…`; no Needs
    attention row; an empty week. This replaces `sidebar-first-run-p3.png` as
    item 1's evidence of "first run".
23. **After the Import on a fresh store** (dataset `fresh`), week 28 Sep – 4 Oct
    2026: the sidebar lists `Personal`, `Daily routine`, `University timetable`
    — **one** timetable row, its swatch `blue` with `tablecells.fill`; every
    lecture is `blue`; **no Needs attention row** (count 0).
24. The same week, Fri 2 Oct: `BPREF-Info` 18:35–20:15 and `BPREF-Info`
    19:30–20:15 as **two** blocks — packed where the slot allows, otherwise
    cascaded with the earlier block's title drawn in its title band and the
    2pt canvas gap round the later one (`layouts.md` §3.3; §3.3 above). One
    frame in Week at the default window width (cascade) and one in Day (packed).
25. Inspector, `BPREF-Info` 18:35 selected: title row glyph `building.columns`
    and the `blue` timetable swatch; `Read-only — from University timetable`;
    **`Lecturers` `L05`, `L06`**; `Room` `Online · WEBINAR02`; Source row with
    the timetable swatch; `Done` / `Skip` enabled (it is history, §18.1).
26. A lecture at `.full` in Week with the meta line `HS_A3.15 · Universit…`
    (§3.4, amended), and item 12's `SWEN3-LAB` reading `EDV_F4.26 · …` after
    the second sync — the frame filed under item 12 could not show the room
    it claimed.
27. Settings ▸ Sources after the Import on `fresh`: `Synced … · 13 events`,
    `Sync Now` as an ordinary bordered button (`layouts.md` §11).

### 22.1 Fixtures

#### The real export (tests only)

`fixtures/cis-2026WS-redacted.ics` is Parsa's export with lecturer names
replaced by `L01`–`L35`. CA copies it **byte for byte** into the test bundle
(`KadenceTests/Fixtures/ICS/cis-2026WS-redacted.ics`). A test asserts that its
SHA-256 equals the repo file's, so CRLF survives. It is never edited and never
served in review: its dates are absolute.

**Its CalDAV form**, `KadenceTests/Fixtures/CalDAV/report-cis-2026WS.xml`, is a
`REPORT` `207` built from it with **one VEVENT per object**
(`caldav-mocks.md` "`reportCIS`"):

- 13 objects, `obj-01.ics` … `obj-13.ics` in file order.
- Each object is the file's `VCALENDAR` header, its `VTIMEZONE` block, one
  VEVENT, and `END:VCALENDAR`, every line as in the file.

A test rebuilds the `.ics` VEVENT lines from the `.xml`'s objects and asserts
that they equal the fixture's, line for line, so the two cannot drift.

Expected, with the test clock at **2026-10-08 10:00 Europe/Vienna** and the
test's Mac zone Europe/Vienna, **from the `.ics` and from the `.xml` alike**:

| Check | Expected |
|---|---|
| VEVENTs read / problems | 13 / 0; `VERSION:1.0` accepted |
| CIS profile | matches all 13 |
| Events after the merge | **12**. One merge: `BPREF-Info` on 2 Oct 18:35–20:15, lecturers `[L05, L06]`, `isOnline`, group `if-5`, location `WEBINAR02`. In the `.xml` the two halves are separate objects (`obj-03.ics`, `obj-04.ics`) |
| Content keys | All 12 in content mode, e.g. `SWQM-ILV HS_A3.15 - BIF-5C\|HS_A3.15\|20260914T123000Z\|20260914T140000Z` |
| Long lecturer list | `INNO3-EL` 21 Oct: 22 lecturers `L10` … `L31` in order; `isOnline` (`WEBINAR01`). Its UID (**185** characters after `UID:` — corrected 2026-10-10, G-070; the content line is 189 — with spaces and ` / ` inside) is read intact and not used |
| Kinds | exam: `REQEN-EXAM`, `RW-EXAM`, `GLD-EXAM`. Lecture: the other 9 (`-ILV`, `-UE`, `-LAB`, `-EL`, `-Info`) |
| DST | `INNO3-EL` 21 Oct 08:00 → 06:00Z; `UF-ILV` 2 Nov 14:30 → 13:30Z; `SWQM-ILV` 14 Sep 14:30 → 12:30Z |
| Range | First 14 Sep 2026, last 29 Jan 2027. `CGRMR-ILV` 11:20–12:50 and `GLD-EXAM` 12:50–14:20 touch but do not overlap |
| Titles / groups | The course code; `BIF-5C ` → `BIF-5C` |
| Import at the test clock | 12 created. **3 history** (`SWQM-ILV`, `KOKU-UE`, merged `BPREF-Info`), 9 on or after today (`SWEN3-LAB` 8 Oct counts as today) |
| A sync of the same content a day later | Writes nothing |
| The same, with every href renamed and every ETag changed | Writes nothing; feed hash equal |
| The same, with every CRLF replaced by LF | Identical result |
| Mac zone `America/New_York` | Identical instants; `SWQM-ILV` draws at 08:30 |

#### Review mode never touches the real store (added 2026-10-10; G-076)

Parsa's first real connection ran on a store a review launch had seeded
about an hour earlier: the capture and check scripts delete
`~/Library/Containers/XIX.Kadence/…/default.store` and relaunch with
`-KadenceReview`, and review mode seeded **that same file**. So the "real"
store held the whole Phase 2 dataset — eight mock sources, the mock events, the
mock routine template and its windows — before the first lecture arrived.
Every one of these followed from it: the second `University timetable` row,
the six fixture sources, the `graphite` slot (all seven others were taken),
and a Needs-attention count of 16 (14 of them the mock dataset's own).

- **A launch with `-KadenceReview` uses its own store**: an in-memory
  `ModelContainer`, created fresh for that launch and gone when it quits. It
  never opens, reads, writes or deletes the real store, and it uses the
  in-memory secret store, never the Keychain.
- **A launch without it never seeds anything** except §21.1.1's two built-in
  sources, and never reads a review argument's data.
- **No script deletes or writes the real store.** `Scripts/*` lose their `rm`
  of `default.store`; a fresh review launch is fresh by construction.
- *(Added 2026-10-14; DEVIATIONS B45 accepted.)* **The unit tests' host is a
  third launch, and it is in-memory too.** `KadenceTests` is hosted by
  Kadence.app, so every test run launches the app. A launch XCTest started
  (its environment variables, its injected library, or a loaded
  `XCTestCase`) uses an in-memory store, the in-memory secret store and a
  transport that refuses every request before it is sent. It takes
  precedence over `-KadenceReview`. Only a normal launch opens the real
  store, the Keychain or the network; a test asserts the test host holds no
  descriptor on the real store.
- **Datasets**, selected by the argument's value:

  | Value | Contents |
  |---|---|
  | `phase2` | the Phase 2 dataset, no connected source (regression scripts) |
  | `phase3` | the review dataset below |
  | `empty` | nothing but the two built-in sources — what a real first launch holds |
  | `fresh` | `empty`, then one connected source imported from `reportCISOverlap` (`caldav-mocks.md`): the real export plus one overlapping session. Its dates are absolute, so its frames are navigated to by date (week 28 Sep – 4 Oct 2026), and the clock only decides which blocks are `past` |

#### The review dataset

**The Phase 2 dataset, unchanged, plus one connected source, and only in review
mode.** G-057 (ruled 2026-10-08) says **a fresh real store starts empty**:
`MockData` seeds only under `-KadenceReview` (`PHASE3-PLAN.md` task 10).

In review, the mock source `timetable` (`University timetable`, `blue`,
`.universityTimetable`) becomes a `Source` with these values:

- `connection = caldav`
- `serverURL` `https://cis.technikum-wien.at`, `username` `user01`
- the principal, home and `calendars` = `[LVPlan]` from `caldav-mocks.md`

It is seeded **as already imported** *(amended 2026-10-10)*: `importedAt` and
`lastSuccessAt` are set to the seeding time and the template's events are
written by an Import, so the failure cases (`forbidden`, `calendarGone` …) show
what a real source shows when a later sync fails — a last-synced time, and
events that are in fact kept — instead of `Never synced`.

`Statistik übung` (the Phase 2 dataset's second imported event, today
10:45–11:45, `done`) is not in the template, so a sync of the review source
would remove it and item 12 would read `3 removed`. **Ruled 2026-10-10 (closes
G-073, accepts DEVIATIONS B42):** `phase3` seeding detaches it (`sourceID`
nil, still `.imported`, `blue`), as built. It is the one event in any dataset
that is imported and has no source; §21.1.1 resolves it for display to the
`Source` holding its stored slot, **in review mode only** — a test asserts
that no production path creates an imported event without a `sourceID`.
Adding it to the template instead would change item 5's `13` everywhere it is
pinned for no gain.

`MockCalDAVTransport` serves it (no network) from the template below. Its
password comes from an in-memory secret store, **never the Keychain**, and is
the **review password** `review-only-not-a-password`. It is drawn only as
bullets.

The **sentinel** (tests only) is account `user01`, password `S3ntinel-pw-⚠`.
No other password appears in the repo.

Review mode also seeds **one manual all-day event**, `Studieninformationstag`,
on `M + 2` (`graphite`), for item 19. All-day events take no part in conflicts,
so the counts below are unaffected.

**`M`** is the first Monday at least two days after today (`today + 2 … today +
8`). Every fixture lecture after today is on `M … M + 11`, so none shares a day
with the §12/§17 today/tomorrow fixtures. The week's appearance therefore does
not depend on the weekday or the clock (`DECISIONS.md` 2026-10-05). The fixture
is a **template**:

- `{{D+n}}` is the date `M + n` as `yyyyMMdd`.
- `{{T-n}}` / `{{TODAY}}` is today's date minus n.

Tests render it with `M` = 2026-10-12 and today = 2026-10-08.

#### `Fixtures/ICS/cis-review.ics.template`

It has the real file's structure exactly:

- CRLF line endings, `VERSION:1.0`, `PRODID:FH Technikum Wien`, and the real
  file's `VTIMEZONE` block verbatim.
- Per VEVENT:
  - `UID`, built the CIS way: `FH` + group + room + lecturers + course + start +
    end, local `yyyyMMdd'T'HHmmss`.
  - `SUMMARY`: `COURSE  ROOM - GROUP`, with a double space, and the group padded
    with a trailing space where the real file pads it.
  - The four-line `DESCRIPTION`, `LOCATION`, `CATEGORIES:StundenplanTW`, and
    `DTSTART`/`DTEND` `;TZID=Europe/Vienna`.
- Lecturers are `Lnn` codes, as in the real file.

`MockCalDAVTransport` serves the rendered template as a `REPORT` `207` with one
VEVENT per object (`r01.ics` … `r14.ics` in row order), built exactly as
`reportCIS` is.

| # | Day / time | Course | Room | Group | Lecturer(s) | Serves |
|---|---|---|---|---|---|---|
| H1 | `{{T-6}}` 14:30–16:00 | `SWQM-ILV` | `HS_A3.15` | `BIF-5C` | `L01` | history (item 5's `2`) |
| H2 | `{{T-5}}` 09:40–12:50 | `KOKU-UE` | `UEB_B2.02` | `BIF-5C3` | `L02` | history |
| 1 | `{{TODAY}}` 09:00–10:30 | `Datenmodellierung` | `FH B.2.09` | `BIF-5C` | `L08` | Reproduces §12 item 1. There is no `-` in the code, so it is a lecture by fallback. The seeded mock event's externalID **is this event's content key**, so the review sync updates it in place (`Event.id` and travel leg survive) |
| 2 | `{{D+0}}` 09:00–10:30 | `SWQM-ILV` | `HS_A3.15` | `BIF-5C` | `L01` | 11, 13 |
| 3 | `{{D+1}}` 10:00–11:30 | `SWEN3-LAB` | `EDV_F4.25` | `BIF-5C3` | `L03` | 11, 12 (room changes) |
| 4 | `{{D+2}}` 14:00–15:30 | `INNO3-EL` | `WEBINAR01` | `BIF-5C` | `L10 / L11 / … / L31` (22) | 11, 14 |
| 5 | `{{D+3}}` 13:00–14:30 | `EPC-ILV` | `LAB_F5.12` | `BIF-5VGE1` | `L04` | 11, 12 (vanishes) |
| 6 | `{{D+3}}` 16:00–17:30 | `REQEN-EXAM` | `EDV_A5.09` | `if-5` | `L32` | 11 (exam glyph) |
| 7a | `{{D+4}}` 16:00–17:45 | `SWRM-ILV` | `UEB_B2.01` | `BIF-5C` | `L05` | 11, 16. Co-taught: the first VEVENT… |
| 7b | `{{D+4}}` 16:00–17:45 | `SWRM-ILV` | `UEB_B2.01` | `BIF-5C` | `L06` | …the second VEVENT, with its own UID and its own object, merged with 7a |
| 8 | `{{D+7}}` 09:00–10:30 | `SWQM-ILV` | `HS_A3.15` | `BIF-5C` | `L01` | week `M + 7` |
| 9 | `{{D+8}}` 10:00–11:30 | `SWEN3-LAB` | `EDV_F4.25` | `BIF-5C3` | `L03` | |
| 10 | `{{D+10}}` 10:00–11:30 | `EPC-ILV` | `LAB_F5.12` | `BIF-5VGE1` | `L04` | |
| 11 | `{{D+11}}` 09:40–11:10 | `RW-EXAM` | `EDV_F2.01` | `BIF-5C` | `L34` | last date (item 5's `{last}`) |

14 VEVENTs become **13 events** after the merge (7a+7b), **2 of them history**.
These are item 5's numbers. The Import window (§20.8.2) reaches back a year, so
the history rows come back from the mock's `REPORT`. The mock honours the
time-range the way SabreDAV does: it returns objects that end after `start`.

Placement is the first version's, slot for slot, so its check against every
Phase 2 fixture still holds. Nothing on `M … M+11` touches these slots:

- 12:00–13:00 on Mon/Wed/Fri (`Lunch`)
- 17:00–18:30 on Mon/Wed (`Training`)
- 19:30–21:30 (the §17.1 `Fixture call N` pairs)
- 21:00–21:30 (`Reading`)
- 07:00–08:45 (`Gym`, `Morning review`)

H1 and H2 are history and never conflict (§20.9). Only #7 overlaps a routine
occurrence: `Training` (Fri 17:00–18:30, `.shiftable` ±90), by **17:00–17:45,
45 min**. Expected panel:

| Row | Title | Line 2 |
|---|---|---|
| 1 (recommended) | `Shift Training 45 min later` | `17:00 → 17:45 · all 90 min kept` |
| 2 | `Shorten Training to 45 min` | `90 min → 45 min · 45 min lost` |
| 3 | `Skip Training today` | `Does not run today · 90 min lost · re-offered` |

Rows 1 and 2 tie at 45. Kind order (§14.3.1) puts `shiftLater` first, and
§14.3.3 recommends it (45 ≤ 90). The overlap line reads `17:00–17:45 · 45 min
overlap`.

**Expected counts:** day conflicts **14** (§17.1's 13 + #7), needs-attention
**15**. **These counts also prove the merge.** Unmerged, 7a and 7b would be two
blocks, each conflicting with `Training` (and with each other, if the engine
compares fixed events): 15 / 16 or more. `MockDataClockTests` (or its Phase 3
sibling) pins 14 and 15 for a template weekday and for a non-template weekday,
as §17.1 requires of any fixture that changes them.

**Item 16's footer `k`** is unchanged. Day conflicts sort by start
(`interactions.md` §10.1). These come before #7:

- today's `Client call` × `Focus review`
- `Training` × `Supervisor meeting` (the first Mon/Wed/Fri ≥ today, always
  before `M + 4`)
- the §17.1 `Fixture call N` pairs on days 2 … d − 1, where **d = (M + 4) −
  today** in days (6 … 12)

The pair on day d starts at 19:50, after #7. So **k = d + 1** (7 … 13), and the
footer reads `k of 15`. The test pins the formula, and the capture names the
`k` it shows.

#### `reportChanged` — the second response (review item 12, sync tests)

The same template, served as a `REPORT`, with exactly these differences. The
objects of unchanged VEVENTs keep their hrefs, and changed VEVENTs get new ones
(`r03b.ics` …). The hrefs are irrelevant either way (§20.2).

| Change upstream | CIS shape | Expected in Kadence |
|---|---|---|
| **Room move**: #3 `SWEN3-LAB` `{{D+1}}` moves to room `EDV_F4.26` | New UID, SUMMARY, DESCRIPTION, LOCATION, object | Old deleted, new created (`.scheduled`, even if the old was `done`). §20.10 |
| **Vanished lecture**: #5 `EPC-ILV` `{{D+3}}` | VEVENT absent | Deleted (§20.6) |
| **Lecturer change**: #2 `SWQM-ILV` `{{D+0}}` `L01` → `L09` | New UID, same content key | Updated in place: `lecturers` `[L09]`, `Event.id` and `status` kept |
| **Co-teacher removal**: #7b gone (`L06`) | One object fewer | Merged #7 updated in place: `lecturers` `[L05]`. Still one block, still conflicts. Counts stay 14 / 15 |
| New: `KOKU-UE` `{{D+9}}` 10:00–11:30, `UEB_B2.02`, `BIF-5C3`, `L02` | New VEVENT | Created |
| H1 (history) room → `HS_A3.13` | New UID | **Not written.** The sync window starts today, so the mock does not return it, and the planner would drop it if it did. H1 is unchanged, and no H1' is created |

Last-change line: **`2 added · 2 updated · 2 removed`**.

#### Parser fixtures (tests only, never in review)

The parser takes one iCalendar text, a file or one object's `calendar-data`, so
these stay files:

| File | Contents | Expected |
|---|---|---|
| `cis-2026WS-redacted.ics` | the real export, above | the table above |
| `edge-cases.ics` | `VERSION:2.0`; folded lines (CRLF + space and + tab); LF-only line endings; escaped `\,` `\;` `\n` `\\`; a UTC `Z` event; a floating event; `TZID=W. Europe Standard Time`; `TZID=Custom Zone` (unknown); `DURATION` instead of `DTEND`; a zero-length event; a two-day `VALUE=DATE` event; a weekly series across 25 Oct 2026 (DST end); an `RDATE`; an orphan `RECURRENCE-ID`; a `STATUS:CANCELLED` event (review item 20); two VEVENTs with stable UIDs and one shared content key (a generic co-teaching merge); an `ORGANIZER;CN=`; a `URL`; `X-` properties; a `VALARM`; a `VTIMEZONE` block | Every row of §20.3–§20.7 asserted. Floating and unknown-zone events are read in the test's Mac zone. One problem (the unknown zone), no skips |
| `malformed-partial.ics` | 10 VEVENTs: 1 without `UID`, 1 with `DTEND` before `DTSTART`, 1 with `DTSTART:garbage`, 1 `FREQ=MONTHLY;BYDAY=2MO` series | 6 imported, 4 problems with line numbers, state `partialImport`, no deletions |
| `html-login.html` | an HTML sign-in page | Served as a `200 text/html` answer to `REPORT`: `notACalendar`, nothing written |
| `truncated.ics` | `BEGIN:VCALENDAR`, two VEVENTs, no `END:VCALENDAR` | As one object's `calendar-data`: that object is a problem (`partialImport`), and the others are read |

#### Mocked responses (`MockCalDAVTransport` and the `URLProtocol` stub)

**Normative shapes: `caldav-mocks.md`.** CA copies its XML bodies into
`KadenceTests/Fixtures/CalDAV/` as files. They use the real server's shapes from
2026-10-08, with the username replaced by `user01`. Every case starts with the
discovery chain D1–D4 (`discoveryOK`) unless it replaces a step.

| Case | What differs | Expected |
|---|---|---|
| `reportOK` | Discovery as CIS, then `REPORT` → `207` with the review template (review) or `reportCIS` (tests) | Step 2 single row `LVPlan`; `upToDate` |
| `reportChanged` | Second `REPORT` = the table above | `upToDate`, last change `2 added · 2 updated · 2 removed` |
| `etagsOnly` | Second `REPORT`: identical `calendar-data`, every `getetag` and href changed | **Nothing written**; feed hash equal; log line shows a different ETag set |
| `ctagOnly` | `REPORT` → `405` on both polls (so F1 runs). F1's `PROPFIND` carries `getctag` `LVPlan-user01-1791454967`, then `LVPlan-user01-1791455022`, with different `getetag`s. `calendar-multiget` content is identical | First poll writes. **Second poll writes nothing.** `fetchMode` `multiget`; the log shows both ctags |
| `reportRefused` | `REPORT` → `405`; F1 `PROPFIND` `207` + `calendar-multiget` `207` | Same events as `reportOK`; no UI difference; `fetchMode` `multiget` |
| `multigetRefused` | `REPORT` `405`, `calendar-multiget` `501`, `GET` per href `200` | Same events; `fetchMode` `get`; requests = 1 + 1 + 1 + n |
| `allRefused` | `REPORT` `405`, `calendar-multiget` `501`, `GET` `405` | `fetchFailed`, nothing written |
| `overCap` | `multigetRefused` with 400 member hrefs | `fetchFailed` after exactly 300 requests, nothing written |
| `unauthorized` | D2 and every later request → `401` `WWW-Authenticate: Basic realm="…"`, also with the password | `unauthorized`, paused. Exactly one request carried `Authorization`, and only after the first `401` |
| `forbidden` | D2 → `403` after the password | `forbidden`, paused |
| `wellKnown404` | D1 → `404` | `noCalDAV` |
| `propfindNot207` | D2 → `200 text/html` | `noCalDAV` |
| `noCalendars` | D4 lists only the home and `outbox/` | `noCalendars` |
| `multiCalendar` | D4 adds `Prüfungen` (VEVENT), `Aufgaben` (VTODO only) and `inbox/` | Checklist: `LVPlan`, `Prüfungen` checked; nothing else listed |
| `calendarGone` | `REPORT` → `404`; re-discovery's D4 has no `LVPlan` | `calendarMissing`, events kept, not paused |
| `calendarMoved` | `REPORT` → `301` same host; re-discovery finds `LVPlan` at `…/LVPlan-user01-ws26/` | Adopted silently, `upToDate`; `calendars[0].href` updated |
| `htmlOK` | `REPORT` → `200 text/html` (`html-login.html`) | `notACalendar`, nothing written |
| `emptyCalendar` | `REPORT` → `207` with no `response` | At the Import: allowed, 0 events. After events: `emptyFeed` |
| `timeout` | No response; the client's timeout fires (injected short in tests, 30 s in the app) | `unreachable` |
| `offline` | `URLError.notConnectedToInternet` | `offline` |
| `certificate` | The transport fails with `URLError.serverCertificateUntrusted` | `certificate`. The stub records **no request at all**: no credentials, no body |
| `redirectOffHost` | D1 → `301 Location: https://login.example.invalid/caldav/` | `redirected` (`{otherHost}` = `login.example.invalid`). **No request reached it** |
| `redirectToHTTP` | D1 → `301 Location: http://cis.technikum-wien.at/webdav/lvplan.php/` | `redirected`, the `http:` body; nothing sent there |
| `serverError` | `REPORT` → `503` | `serverError` |
| `slow` | `reportOK` after 3 s (review only: item 3's spinner) | |

The review build selects a case per launch (`PHASE3-PLAN.md` task 10 names the
arguments). The default is `reportOK`.
---

# Phase 3 — slice 2: leave-by and notifications

Written 2026-10-14, after slice 1 was accepted (`PHASE3-REVIEW.md` "Final —
2026-10-14"). Plan and build order: `PHASE3-SLICE2-PLAN.md`. Layouts:
`layouts.md` §6, §6.1, §9, §11 (amended), §13, §14 (new). Interactions:
`interactions.md` §14, §15 (new).

**Scope.** Two things, and only these. *(Amended 2026-10-14, routing
amendment: travel times are worked out by Apple Maps, not typed.)*

1. **Leave by.** Each event that needs travel gets a departure time:
   `start − travel time − buffer`. The travel time comes from a
   `TravelTimeProvider`; the slice's only real provider is **MapKit**
   (`MKDirections` ETAs, §24.9), between **known places** whose addresses
   MapKit looked up and the user confirmed (Home, FH Technikum Wien — built
   in with its real address — and any the user adds, §23). The user chooses
   only how they usually travel (§23.3). The travel band (§4), the inspector
   and the menu bar show the result, and say so when Apple Maps could not
   answer (§24.10).
2. **Notifications**, local, through `UNUserNotificationCenter`: a leave-by
   notification for an event with travel, a "starts at" notification for an
   event without, with Done / Snooze / Open; and one notification when a
   connected source's sync pauses after a 401 or 403 (§27.4 N8; G-060).

Not in this slice: cycling (G-095), a per-event way to travel (G-094),
routes drawn on a map, Moodle, work items, deadline notifications, the
morning summary (G-088); mail; the planner; notifications about timetable
changes (G-060's remainder). Every Phase 1–3 slice 1 value stands; in-place
amendments are marked 2026-10-14 in §4, §8 (A42, built in this slice), §11,
§15.1 and §15.2.

Three rules govern the slice:

- **Nothing important depends on checking the app** (BRIEF-PRODUCT). A
  departure the user would miss is told to them; when Kadence cannot tell them
  (no permission, no travel time), it says so where they look (§24.10, §26.3,
  §27.8).
- **Never a guessed number.** A travel time is Apple Maps' answer, or Apple
  Maps' last answer marked as an estimate, or "unavailable" with the reason
  (§24.10). Nothing is typed, defaulted or extrapolated.
- **Where you are stays yours.** Addresses and coordinates go to Apple Maps
  only; the current location is used for one departure and never kept or
  logged (§24.11).
- **Derived, never upstream.** A leave-by is computed from the event; it is
  stored beside the event and never written onto it (§24.7). Imported events
  stay read-only exactly as §18.1 says.
- **Skipped and missed are re-offered, never counted** (§27.9). No badge, no
  "missed" notification, no count of ignored ones.

---

## 23. Places, addresses and ways to travel

*(Rewritten 2026-10-14, routing amendment. Parsa does not type travel times:
Kadence works them out with Apple Maps, like a navigation app. The user
chooses where places are and how they usually travel; nothing else. The
first draft's typed minutes per route, `TravelRoute` and the manual provider
are withdrawn, never built.)*

### 23.1 Known places

A **known place** is somewhere Kadence can travel from or to. It is not the
same thing as an event's location text: `HS_A3.15` is where in the building;
`FH Technikum Wien` is where you travel to. The two stay separate models
(§28.1).

Every store has two **built-in** known places, created at first launch if
missing, idempotently, with fixed ids — the same pattern as §21.1.1's
built-in sources:

| id | Default name | Address at first launch | Can be removed |
|---|---|---|---|
| `home` | `Home` | none — the user types it (§23.5) | no |
| `campus` | `FH Technikum Wien` | **`Höchstädtplatz 6, 1200 Wien`**, looked up by Kadence itself (§23.6) | no |

- **Name**: required, trimmed, unique among known places (case-insensitive).
  Renamable in Settings ▸ Travel (`layouts.md` §13); an empty or duplicate
  name reverts to the last name, like a source's name (`layouts.md` §11).
  Renaming changes every place it is shown and nothing else.
- **Address**: what the user typed, looked up once with MapKit and
  **confirmed by the user** before Kadence uses it (§23.5). Only a confirmed
  address has a coordinate, and only a place with a coordinate can be
  travelled from or to.
- **More places**: the user may add places (`Add Place`, `layouts.md` §13),
  e.g. `Gym`, each with an address confirmed the same way. A user place can
  be removed; a built-in cannot (it can be renamed — `campus` stays the place
  timetable rooms are at, whatever it is called).

### 23.2 Which place an event is at

An event's **place** is resolved by these rules, first match wins. Nothing is
inferred from free text beyond rule 4's one test. **Unchanged by the routing
amendment** — routing changes how long a trip takes, never where an event is.

| # | Event | Place |
|---|---|---|
| 1 | `isAllDay`, or `isCancelled` | **none** — never travels |
| 2 | `origin == .routine` (or `.planned`) | **none** in this slice (G-084). A routine block is transparent to travel: it is never a leg's origin or destination |
| 3 | `origin == .manual` | the known place `Event.placeID` names (§28.2); `nil`, or an id no known place has, is **none** — "manual events with no place need no travel unless the user sets one" |
| 4 | `origin == .imported`, `isOnline` | **none** (G-063: online events need no travel) |
| 5 | `origin == .imported`, its `Source` (resolved by §21.1.1) has kind `.universityTimetable`, and its location text is not empty after trimming | **`campus`**. Every CIS room — `HS_A3.15`, `EDV_F4.25`, `LAB_F5.12`, `UEB_B2.01`, `FH B.2.09` — is on the FH campus, so no room pattern is needed or kept, and **no room is ever geocoded** |
| 6 | any other imported event | **none** in this slice (no other connected kind exists; G-085) |

An imported event's place is **never stored on the event** and cannot be set
by the user in this slice (G-085): it is a function of upstream fields, so a
sync that changes the room or makes a lecture online changes the place by
itself.

### 23.3 Ways to travel

**Modes.** Exactly the transport types MapKit's `MKDirections` offers on
macOS 15 (BRIEF-PRODUCT's floor), checked, not assumed:

| `TravelMode` raw | `MKDirectionsTransportType` | Settings label | Copy phrase | Glyph (§2.1) |
|---|---|---|---|---|
| `transit` | `.transit` (ETA only — MapKit gives transit ETAs, not transit routes, which is all a leave-by needs) | `Public transport` | `by public transport` | `tram.fill` |
| `walking` | `.walking` | `Walking` | `walking` | `figure.walk` |
| `driving` | `.automobile` | `Driving` | `driving` | `car.fill` |

**Cycling is not offered.** `MKDirectionsTransportType` on macOS 15 has
automobile, walking, transit and any; a cycling type arrived with the 2025
MapKit (macOS 26), and a developer report on macOS 26 shows a cycling request
answered with a driving route. Kadence's brief sets macOS 15 as the floor, so
cycling waits (G-095, with the deployment-target question). `.any` is never
used: a leave-by must say how you are travelling.

- **Preferred mode** — one setting, `AppSettings.preferredTravelMode`,
  default **`transit`** (Vienna's public transport covers every campus trip;
  Parsa's default). Settings ▸ Travel, `Usually` (`layouts.md` §13).
- **Per pair of places** — optional: a pair of known places may have its own
  mode (`Home ↔ Gym`: `Walking`), stored as a `TravelModeOverride` (§28.1)
  only when it differs from "usual". **Symmetric**: the same mode both ways
  (the trip itself is routed in its own direction, §24.9). Removing a place
  removes its overrides. In scope because a short walk to the gym routed as
  public transport is the one case the preferred mode gets wrong every week.
- **Per event** — **not in this slice** (G-094). A one-off "I'm driving
  today" would be a local field on the event and a pop-up on the inspector;
  the pair override covers the repeated cases.

A leg's mode = the pair's override if one exists, else the preferred mode.

### 23.4 Buffer

One **buffer**, added to every trip so the user arrives early: **0, 5, 10, 15,
20 or 30 minutes**, default **10** (Parsa's decision; §28.1 `AppSettings`).
The buffer is part of the band's interval (§25) and is named in the inspector
(`layouts.md` §6), never folded silently into the travel time. Kadence asks
Apple Maps to **arrive by `start − buffer`** (§24.9).

### 23.5 Looking up an address

Every address is looked up **once**, when the user commits it, with MapKit's
address search (`PlaceGeocoder`, §24.9: `MKLocalSearch` with
`resultTypes = .address`, the region biased to Vienna — a bias, not a filter).
No address is ever looked up again on its own, and no coordinate is typed.

**States** (`KnownPlace.geocodeState`, §28.1), as Settings ▸ Travel shows them
under the address field (`layouts.md` §13; copy exact, `{typed}` is the
user's text, `{found}` MapKit's one-line address):

| State | When | Line under the field | Controls |
|---|---|---|---|
| `none` | no address typed | — (placeholder `Address`) | — |
| `searching` (not stored) | a lookup is running | `Looking up…` with a small spinner | — |
| one result | MapKit found exactly one | `Found: {found}` | **`Use This Address`** (default, `↩`) · `Cancel` |
| several results | 2 or more | `{n} addresses match. Choose one:` then the list (up to 5; name and address, `layouts.md` §13). More than 5: `More than 5 addresses match. Add the postcode or district, for example 1200 Wien.` above the first 5 | click / `↩` on a row confirms it · `Cancel` |
| `notFound` | 0 results | `No address found for “{typed}”. Check the spelling, or add the postcode or district.` | the field stays editable · `Cancel` |
| `lookupFailed` | the lookup failed | offline: `Couldn't look up the address because this Mac is offline.` · throttled or paused (§24.10): `Apple Maps asked Kadence to wait. Try again at {HH:mm}.` · anything else: `Apple Maps didn't answer. Try again in a moment.` | `Try Again` · `Cancel` |
| `confirmed` | the user chose a result | the field shows `{found}`; no line | — |
| `unconfirmed` | the user typed an address and left without choosing | `Not confirmed yet. Kadence can't work out trips to or from {name} until you do.` | `Look Up` |

- **Nothing is used until it is confirmed.** `Use This Address` (or choosing a
  row) stores `confirmedAddress = {found}` and the coordinate, and sets
  `confirmed`; that is the only write of a coordinate.
- **A confirmed address stays in effect while a new one is looked up.** If
  `{name}` already had a confirmed address and the user types a different
  one, the old coordinate is kept until a new result is confirmed; the line
  adds `Still using {old found}.` `Cancel` restores the old text.
- Clearing the field removes the address and the coordinate (`none`); trips
  to and from the place become `unavailable · needsAddress` (§24.3).
- A lookup is one request in the routing queue at the top priority (§24.9),
  so it obeys the same budget and the same pause after throttling.
- The typed text and `{found}` are user data: shown in Settings only, never
  logged (§24.11), never shown in the popover or a notification (they name
  the place by its **name**).

### 23.6 FH Technikum Wien's address

The campus is built in with its real address, **`Höchstädtplatz 6, 1200
Wien`** (`KnownPlace.addressText` of `campus`). **No coordinate is hard-coded**:
the coordinate is what MapKit returns for that address, so the campus and
every trip to it come from one source, Apple Maps.

- The campus is looked up **automatically**, without asking, the first time a
  recompute needs it (in practice the first launch after the timetable is
  imported): the address is Kadence's own, not something the user typed. It
  is accepted without confirmation when the first result's one-line address
  contains both `Höchstädtplatz 6` and `1200`; that is `confirmed`.
- Any other answer — no result, a first result that does not match, or a
  failure — leaves the campus `unconfirmed` / `notFound` / `lookupFailed`,
  shown in Settings ▸ Travel like any place, and the user confirms it there.
  A failed automatic lookup is retried at the next launch or wake, at most
  once a day; it is never retried in a loop.
- Until the automatic lookup has answered, legs to and from the campus are
  `pending`; if it does not confirm, they are `unavailable · needsAddress
  (FH Technikum Wien)` and Settings ▸ Travel asks the user to confirm.
- If the user edits the campus address, it becomes an ordinary typed address
  (§23.5) and is never looked up automatically again.

---

## 24. Travel legs

A `TravelLeg` is the computed departure for one event. It is **derived data**:
stored so every surface reads one answer and so routing can fill it
asynchronously, but never edited, never an undo step and never written onto
the event. *(Amended 2026-10-14, routing amendment: the time comes from Apple
Maps, §24.9; a leg can be an estimate or unavailable, §24.3, §24.10.)*

### 24.1 Which events get a leg

A **leg candidate** is an event that is timed (not all-day), not cancelled,
not `.skipped`, starts on or after `startOfDay(today)`, and has a place
(§23.2). `.done` events stay candidates (a lecture marked done ahead of time
still happened somewhere); they get no notification (§27.2).

An **origin candidate** is the same, except that it may start before today
(an event at 23:00 yesterday can be where you are coming from at 00:30).

### 24.2 Where you are coming from

For a leg candidate `E`:

1. Among origin candidates with a place and with **`start < E.start`** (`E`
   itself excluded), take the one with the **latest `end`** (ties: the later
   `start`, then the smaller `Event.id` string). Call it `P`.
2. If `P` exists and `E.start − P.end ≤ chainGap`, the **origin is `P`'s
   place**. The difference may be negative (`P` is still running when `E`
   starts): that is the same chain.
3. Otherwise the origin is **`home`**.

This is the **rule origin**. **`chainGap` = 120 minutes**, fixed (§28.1
`AppSettings`, not shown in Settings; Parsa's decision). Reading: with less
than two hours between two things, you stay where the first one was; with
more, you are assumed to be at home. Events with no place — routine blocks,
online lectures, manual events without a place — are **transparent**: they
neither break nor make a chain.

| Case (review dataset `travel`, §30.1) | `P` | Origin |
|---|---|---|
| `SWQM-ILV` Mon 09:00, nothing placed before | — | `home` |
| `SWEN3-ILV` Tue 11:45, after `SWEN3-LAB` 10:00–11:30 | `SWEN3-LAB` (15 min) | `campus` — back-to-back, **no leg** |
| `REQEN-EXAM` Thu 16:00, after `EPC-ILV` 13:00–14:30 | `EPC-ILV` (90 min) | `campus` — **no leg** |
| `Dinner with flatmates` Thu 18:30 at Home, after `REQEN-EXAM` –17:30 | `REQEN-EXAM` (60 min) | `campus` → leg to Home |
| `INNO3-EL` Wed 14:00, online | — | — (no place, no leg) |
| `Climbing` Sun 18:00 at Gym, after `Late call` (no place) and `Early study group` –09:00 Sat | `Early study group` (33 h) | `home` |

#### 24.2.1 Where you are now — the next departure only

The rule origin is a guess about where you will be. For **one** leg — the
**next departure** — Kadence may use where the Mac actually is:

- **Which leg**: the leg of the earliest not-started leg candidate whose
  departure is due within the next 45 minutes (`departAt − 45 min ≤ now`, or
  `start − 105 min ≤ now` while the leg has no time yet). One leg at a time.
- **When**: at that leg's **T−45 refresh** (§24.6) and at a launch or wake
  inside that window — never at T−3 h (you will probably still move), never
  for any other leg, never in the background on a timer of its own.
- **Only with** `AppSettings.useCurrentLocation` on (default **on**) and
  location `allowed` (§24.12). One request for one fix
  (`requestLocation()`, accuracy hundred metres), **10 s** timeout.
- **The fix is used** if it is at most 2 minutes old, its horizontal accuracy
  is 200 m or better, **and** it is more than **300 m** from the rule origin's
  coordinate. Within 300 m you are where the rule says: the leg keeps the
  rule origin and its name (`from Home`). Otherwise the ETA is requested from
  the fix, and the leg's origin is **`currentLocation`**, named **`where you
  are`** in every copy (§26–§27, §29).
- **Mode**: the mode the leg would have with its rule origin (§23.3).
- **It never blocks the departure.** No fix, a denied permission, a timeout,
  or a failed request from the fix → the leg keeps its rule-origin value
  (refreshed as usual); nothing is shown on the leg about location.
- **It never outlives its computation** (§24.11): the coordinate is held in
  memory for the one request, never cached (§24.9), never written to the leg
  (which stores `originKind = currentLocation` and no place id, no
  coordinate), never logged.
- A `currentLocation` leg keeps its values until its next refresh or until
  the event, its destination, its mode or the buffer changes; a recompute for
  any other reason leaves it alone. At the event's start it is history like
  any leg.

### 24.3 The leg

- **Origin = destination** (same known place, by rule origin): **no leg**.
  Nothing is stored; the event needs no travel. (A `currentLocation` origin
  is only ever considered for an existing leg, so it never creates one.)
- Otherwise a leg exists, with `mode` (§23.3), `originPlaceID` (or
  `originKind = currentLocation`), `destinationPlaceID`, `buffer` (the buffer
  at compute time), and **one status**:

| Status | Meaning | `departAt`, `duration` | Drawn (§25) | Notified (§27.2) |
|---|---|---|---|---|
| **`ready`** | Apple Maps answered for this trip's cache key (§24.9) — a stale entry counts while its new request is outstanding — and, if a refresh was due (§24.6), the refresh answered | set | band | leave-by N1 |
| **`estimate`** | the latest request this leg needed **failed**, and the last known time is used instead (§24.10's fallback); `isEstimate = true`, with the failure's reason | set, from the last known time | band marked `≈` | leave-by N1e |
| **`pending`** | no time yet; a request is queued and has not failed | nil | none | travel unavailable N7 (reason `pending`) if still pending at planning |
| **`unavailable`** | no time and none to fall back on, or the failure rules out a fallback (`noRoute`, `needsAddress`); with its reason | nil | none | travel unavailable N7 |

- `duration` = the ETA's travel time, **without the buffer**.
- **`departAt = E.start − buffer − duration`**, for every mode. Kadence asks
  to arrive by `E.start − buffer` (transit: `arrivalDate`, so the ETA follows
  the timetable at that hour), and takes the answer's travel time; one
  formula, the same for every mode and every surface.
- `computedAt` = when Apple Maps produced the time the leg uses (for an
  estimate: when the last known time was produced). `source` = the provider
  that produced it: `mapKit`, or `mock` in tests and review.
- **Reasons** (`TravelLeg.unavailableReason`, also carried by an estimate):
  `needsAddress` (the origin or destination place has no confirmed address;
  names that place), `offline`, `noRoute` (Apple Maps has no route for this
  mode at this time), `paused` (Kadence is waiting after a throttle, or its
  own budget, §24.9 — carries the retry time), `failed` (any other error),
  `pending` (asked, no answer yet). Exact copy per surface: §24.10.

`departAt` may fall **before `P.end`** (you must leave before the previous
thing ends) or **inside a protected window** (you must leave during Sleep).
Both are facts and are drawn and told as they are: §25 draws the band, §27.5
holds the notification. Neither is a conflict in this slice (G-086).

### 24.4 Worked example (review dataset `travel`, buffer 10, the mock provider)

The mock provider (§30.1) answers `home → campus` and `campus → home` 35 min
by public transport, `home → Gym` 5 min walking (the pair `Home ↔ Gym` is
overridden to `Walking`). Every leg below is `ready`, source `mock`.

| Event | Place | Origin | Leg |
|---|---|---|---|
| `SWQM-ILV` Mon 09:00–10:30 `HS_A3.15` | campus | home | ready, depart **08:15**, 35 min transit |
| `SWEN3-LAB` Tue 10:00–11:30 `EDV_F4.25` | campus | home | ready, depart **09:15** |
| `SWEN3-ILV` Tue 11:45–13:15 `HS_A2.07` | campus | campus | none |
| `Laundry` Wed 08:00–08:45 | home | home | none |
| `INNO3-EL` Wed 14:00–15:30 `WEBINAR01` | none | — | none |
| `EPC-ILV` Thu 13:00–14:30 `LAB_F5.12` | campus | home | ready, depart **12:15** |
| `REQEN-EXAM` Thu 16:00–17:30 `EDV_A5.09` | campus | campus | none |
| `Dinner with flatmates` Thu 18:30–20:00 | home | campus | ready, depart **17:45** |
| `SWRM-ILV` Fri 16:00–17:45 `UEB_B2.01` | campus | home | ready, depart **15:15** |
| `Early study group` Sat 07:30–09:00 | campus | home | ready, depart **06:45** (inside Sleep) |
| `Late call` Sat 23:15–23:45 | none | — | none |
| `Climbing` Sun 18:00–19:30 | Gym | home | ready, depart **17:45**, 5 min walking (pair override) |

Variants (§30.1):

- **`travelNoAddress`** — Home has no address: the five campus legs from home,
  `Dinner with flatmates` (to Home) and `Climbing` (from Home) are
  `unavailable · needsAddress (Home)`; no bands at all.
- **`travelOffline`** — the provider answers `offline` to every request; the
  cache holds only `home → campus` transit 35 min, computed Sun 27 Sep 18:00
  (stale, so it is asked for and the request fails): the five campus legs from home are **`estimate`** (depart as
  above, `≈`, reason `offline`); `Dinner with flatmates` (`campus → home`, no
  last known time in that direction) and `Climbing` are `unavailable ·
  offline`.

### 24.5 Storage and ownership

- One `TravelLeg` per event at most, keyed by `eventID` (unique).
- **The recompute owns every leg whose event starts on or after
  `startOfDay(today)`**, with no upper bound: it creates, updates and deletes
  them so they equal §24.1–§24.3 exactly. A leg far in the future costs no
  request of its own: legs share ETAs through the cache (§24.9), and a
  semester's lectures repeat a handful of trips at a handful of times, so
  every future lecture shows its band.
- **Legs of events before today are history**: never recomputed, never
  deleted except with their event. Changing the address or the mode does not
  rewrite yesterday's band — the same reading as "the past is never written"
  (§20.1).
- A leg whose values are unchanged is **not rewritten**. Two recomputes of
  the same inputs and the same cache write nothing.
- Deleting an event deletes its leg in the same transaction. Undoing the
  delete brings the event back with the same `id` (DECISIONS 2026-09-09) and
  the next recompute brings the leg back (from the cache, without a request).

### 24.6 When legs are recomputed, and when Apple Maps is asked

**The recompute** is pure and local: it reads the store and the ETA cache
(§24.9) and writes legs. It **never waits for the network**. Where the cache
has no answer, it writes the leg as `pending` (or `estimate` / `unavailable`
by §24.10) and hands a request to the routing queue; when the answer arrives,
it is cached and triggers another recompute.

One recompute pass, on the main actor, in **one store transaction**,
**debounced 0.5 s** so a burst (a drag, a sync writing 80 events, ten answers
arriving) is one pass. Triggers:

| Trigger | Why |
|---|---|
| Any `Event` insert, update or delete (move, resize, status, place, title …), including undo and redo | start, place, status and order are all inputs |
| A sync or Import applied (§20.8.3 step 6) — including one that wrote nothing, which costs one cheap pass | a moved or vanished lecture, an online switch |
| A known place's address confirmed or cleared, a place removed, the preferred mode, a pair's mode, the buffer, or `useCurrentLocation` edited in Settings | inputs |
| **An answer from the routing queue** (success or failure) | the cache or a failure changed |
| **A departure refresh** completing (below) | the leg's time is current |
| Launch (after the store loads and the built-ins exist), wake (`NSWorkspace.didWakeNotification`), the day changing (`NSCalendarDayChanged`) and the clock or time zone changing (`NSSystemClockDidChange`, `NSSystemTimeZoneDidChange`) | the window starts at `startOfDay(today)` |

Every pass ends by asking the notification scheduler for a pass (§27.6).

**When Apple Maps is asked** — three occasions, nothing else:

1. **On change**: a leg whose cache key (§24.9) has no fresh entry. That is
   a new event, a moved event in a new time slot, a new or changed address, a
   new mode, a new buffer that moves the arrival into another slot, or a
   first launch.
2. **Departure refreshes** — for each leg of a not-started event today or
   tomorrow, two scheduled refreshes that **bypass the cache** for that one
   request, so transit delays and traffic are current: at **T−3 h** and at
   **T−45 min**, where T is the leg's `departAt` (while the leg has no time,
   T is `start − 60 min`). The refresh times are re-planned on every
   recompute. A refresh that changes `departAt` re-plans the notification
   (§27.6). A refresh whose slot passed while Kadence was not running or the
   Mac slept runs once at launch or wake, if the event has not started.
3. **The user asks**: `Try Again` (inspector, Settings) — one request now,
   at the top priority, still subject to a pause (§24.9).

Never: on a timer of its own, on every recompute, for events before today,
for an event that has started, or for an online, routine or all-day event.

- **Not an undo step**, and it never clears or edits the undo stack.
- **Not held by a conflict preview.** A preview only ever moves routine
  blocks (§14), which are transparent to travel, so a recompute during a
  preview cannot change what the preview shows.
- A sync's held writes (§20.9) trigger their pass when they are applied.

### 24.7 A leg never writes the event

The recompute reads `Event`, `KnownPlace`, `TravelModeOverride`,
`AppSettings`, `Source` and the ETA cache, and writes **only `TravelLeg`
rows** (and asks the queue for requests). In particular it never writes an
imported event's upstream fields (§18.1), never its `status`, and never a
manual event's `placeID`. Consequences, all tested:

- A recompute leaves every `Event`'s §20.8.4 event hash, and every source's
  `feedHash`, unchanged.
- Because a sync keeps `Event.id` on an in-place update (§20.8.4 "Local
  identity"), a lecturer change keeps its leg untouched; a CIS room or time
  change (delete + add, §20.10) deletes the old event's leg and computes a new
  one for the new event — from the cache when the slot is the same.
- Leg writes are not sync writes: they do not appear in a source's
  last-change line and never touch `lastChange*`.

### 24.8 What the leg is not

- **Not a block.** It never enters conflict detection (G-086), never counts in
  Needs attention, is never selected (§4) and never drawn in Month or in the
  Routines window (§4, §13.1).
- **Not a promise.** An ETA is Apple Maps' estimate at `computedAt`; Kadence
  states it with the mode, the origin and, in the inspector, when and by whom
  it was worked out (`layouts.md` §6), so it can be checked. An estimate says
  so (`≈`, §24.10). **No number is ever invented**: with no answer and nothing
  to fall back on, the leg is `unavailable` and every surface says why.

### 24.9 The provider, the geocoder, the cache and the queue

```swift
struct TravelEndpoint: Sendable, Equatable {   // a value snapshot of a KnownPlace,
    var id: String?                             // or of the current location (id nil)
    var latitude: Double; var longitude: Double // required: no coordinate, no request
}
enum TravelTimeError: Error, Equatable, Sendable {
    case offline            // no network (URLError.notConnectedToInternet and kin)
    case noRoute            // MKError.directionsNotFound, or an answer in another mode
    case throttled          // MKError.loadingThrottled
    case failed             // anything else (serverFailure, unknown, a timeout of 20 s)
}
protocol TravelTimeProvider: Sendable {         // BRIEF-PRODUCT's signature, typed
    func duration(from: TravelEndpoint, to: TravelEndpoint,
                  arrivingBy: Date, mode: TravelMode) async throws(TravelTimeError) -> TimeInterval
}

struct GeocodedAddress: Sendable, Equatable { var line: String; var latitude: Double; var longitude: Double }
enum GeocodeError: Error, Equatable, Sendable { case offline, throttled, failed }
protocol PlaceGeocoder: Sendable {
    func lookUp(_ address: String) async throws(GeocodeError) -> [GeocodedAddress]   // [] = not found
}
```

- **`MapKitTravelTimeProvider`** — the slice's only real provider. One
  `MKDirections.Request` per call: source and destination `MKMapItem`s from
  the coordinates, `transportType` by §23.3's table, **`arrivalDate =
  arrivingBy`**, `requestsAlternateRoutes = false`; `calculateETA()`; returns
  `expectedTravelTime`. An answer whose `transportType` is not the requested
  one is **`noRoute`** (never accepted as a different mode). Errors map as in
  the enum's comments. Nothing else in the app imports MapKit for routing.
- **`MapKitPlaceGeocoder`** — `MKLocalSearch` with
  `resultTypes = .address`, region centred on Vienna (48.21, 16.37) spanning
  0.5°, as a **bias**; at most the first 6 results are kept (5 shown, the 6th
  only tells "more than 5"). `line` is the map item's one-line formatted
  address. (If the deployment floor becomes macOS 26, `MKGeocodingRequest` may
  replace the search behind the same protocol; G-095.)
- **`MockTravelTimeProvider`** and **`MockPlaceGeocoder`** — scripted tables
  (§30.1), counting calls, with injectable failures and an injectable delay.
  **Every test and every review launch uses them** — the three-launch rule of
  §22.1 / §27.10 (B45): only a normal launch constructs the MapKit ones.
  No test needs a network, a location or a prompt.
- **The manual provider is removed.** There is no typed travel time anywhere,
  not even as a hidden fallback: a typed number would be the guess §24.8
  forbids, and the fallback is the last *Apple Maps* answer (§24.10).

**The ETA cache** (`TravelETACache`, §28.1) — what lets a semester of legs
cost a few dozen requests:

- **Key**: origin place id + its coordinate (rounded to 5 decimals, so a new
  address is a new key), destination likewise, mode, **direction** (a trip and
  its return are separate keys — transit is not symmetric), **day type**
  (`weekday` Mon–Fri, `saturday`, `sunday`), and the **slot**: the arrival
  time (`start − buffer`) rounded down to 30 minutes.
- **Value**: `travelSeconds`, `computedAt`, the arrival date it was computed
  for.
- **Fresh** for planning while `computedAt` is at most **14 days** old.
  Entries older than **28 days** are deleted at launch. A departure refresh
  (§24.6) ignores freshness and asks anyway; its answer updates the entry.
- **Current-location trips are never cached** (§24.2.1).
- Failures are not cached; the queue remembers the last failure per key
  (memory only) so a recompute does not re-queue a key it is pausing on.

**The routing queue** (`RouteRequestQueue`) — every MapKit request, ETA or
lookup, goes through it:

- **One request in flight**, at least **2 s** between two requests, at most
  **20 requests per rolling 10 minutes** and **150 per day** (G-093: MapKit
  publishes no number; these are well under what one device has been seen to
  get). Each request has a 20 s timeout (→ `failed`).
- **Priority**, highest first: (0) the user asked (an address lookup, `Try
  Again`); (1) the next departure's refresh; (2) other departure refreshes;
  (3) legs of today and tomorrow; (4) the rest, by event start. A key already
  queued is not queued twice; a queued request whose leg disappeared is
  dropped.
- **Throttled** (`MKError.loadingThrottled`): the whole queue **pauses** 10
  minutes, doubling on each consecutive throttle up to 60, reset by a
  success. **Budget spent**: priorities 3–4 wait for the next day (priorities
  0–2 may use 30 more). Either way the waiting legs carry reason **`paused`**
  with the time the queue resumes.
- **Offline**: a request that fails `offline` pauses the queue until the
  network path is satisfied again (an injected `NetworkPathMonitor`, the
  `Network` framework's `NWPathMonitor` in a normal launch) or 5 minutes pass.
- The queue, the cache's clock and the monitor are injected; tests drive
  them without waiting.

### 24.10 When routing fails — never silent, never a guessed number

A failed request **never removes a leave-by silently** and **never invents
a time**. The leg falls back in this order, first match wins:

1. **The reason rules out a fallback** — `noRoute` (Apple Maps has no route
   in this mode at this hour: transit at 03:00 is not 35 minutes) or
   `needsAddress` (no place to route from) → **`unavailable`** with the
   reason, even if an older time exists.
2. **This event's own last time** (the leg already had `departAt` from an
   earlier answer) → **`estimate`**, keeping that time and its `computedAt`.
3. **The cache's entry for this key**, any age up to 28 days → **`estimate`**.
4. **The nearest cached slot** for the same origin, destination, mode and
   direction — the same day type first, then any day type; ties to the
   earlier slot → **`estimate`**.
5. **Nothing** → **`unavailable`** with the reason (`offline`, `paused`,
   `failed`), or **`pending`** if nothing has failed yet.

An estimate becomes `ready` again with the next successful answer; there is
no "estimate" that outlives a success.

**Copy — exact, tested.** `{place}` is the place a `needsAddress` names;
`{mode}` the copy phrase (§23.3: `by public transport`); `{retry}` the queue's
resume time `HH:mm`; `{origin}` the origin's name (`Home`, `where you are`).

| Reason | Short (band hover, popover, notification) | Inspector sentence | Inspector button |
|---|---|---|---|
| `needsAddress` | `{place} has no address` | `Add the address of {place} in Settings ▸ Travel so Kadence can work out the trip.` | `Add Address…` (opens Settings ▸ Travel, that place's address field focused) |
| `offline` | `offline` | `This Mac is offline. Kadence will ask Apple Maps again when it's back online.` | — |
| `noRoute` | `no route {mode}` | `Apple Maps has no route {mode} for this trip at this time. Choose another way to travel between these places in Settings ▸ Travel.` | `Change Way to Travel…` (opens Settings ▸ Travel, that pair's pop-up focused) |
| `paused` | `Apple Maps paused until {retry}` | `Kadence is waiting before it asks Apple Maps again, and will try at {retry}.` | — |
| `failed` | `Apple Maps didn't answer` | `Apple Maps didn't answer. Kadence will try again at the next refresh.` | `Try Again` |
| `pending` | `not worked out yet` | `Kadence is asking Apple Maps for the trip from {origin}.` | — |

Where each surface puts them: the band §25.3, the status item and popover
§26, notifications §27.4 (N1e, N7), the inspector `layouts.md` §6. An
estimate also says when its time was worked out: the inspector's `Last worked
out {when} by Apple Maps.` (`{when}` per §19.5).

### 24.11 Privacy and trust

- **Addresses and coordinates go to Apple Maps only** — through
  `MapKitTravelTimeProvider`, `MapKitPlaceGeocoder` and nothing else. No other
  service, no URL built from an address, no analytics.
- **Stored**: a place's typed address, its confirmed one-line address and its
  coordinate (`KnownPlace`), and the cache's place ids and rounded
  coordinates of known places. **Never stored**: the current location, in any
  form, anywhere — not in the leg, the cache, `AppSettings`, a log or a
  crash-report string.
- **Logged**: the routing log (category `travel`, the same one-line style as
  the sync log, §20.8.4) carries **no address, no coordinate, no place name,
  no event title and no search text**. Exactly these forms:
  - `eta ok · 34 min · transit` (`· refresh` appended for a departure
    refresh; `· here` when the origin was the current location)
  - `eta failed · offline · transit` / `· noRoute ·` / `· throttled ·` /
    `· failed ·`
  - `queue paused · until 10:40`
  - `lookup ok · 3 results` / `lookup none` / `lookup failed · offline`
  - `location used` / `location not used · within 300 m` / `location
    unavailable · denied` / `· timeout`
- **Review mode and tests** use the mock provider, the mock geocoder, a mock
  location source and a mock path monitor; a launch XCTest started or one
  with `-KadenceReview` **never constructs** a MapKit, CoreLocation or
  `NWPathMonitor` object (asserted as B45's store is). No task needs network,
  location services or a permission prompt.

### 24.12 Location permission

Location is **optional**: every leg works from the rule origin without it.
Behind a protocol like the notification centre (§27.10):

```swift
protocol LocationSource: Sendable {
    func authorization() async -> LocationAuthorization      // allowed / denied / servicesOff / notDetermined
    func requestAuthorization() async -> LocationAuthorization
    func currentFix(timeout: Duration) async -> LocationFix?   // nil on any failure; never throws
}
```

`SystemLocationSource` (CoreLocation, `CLLocationManager`, normal launch
only) and `MockLocationSource` (scripted authorization and fix).

- **When Kadence asks.** Not at launch, not in Settings by itself. The first
  time §24.2.1 wants a fix while authorization is `notDetermined` and Kadence
  has never asked (`AppSettings.locationRequestedAt == nil`), it requests
  authorization once and records the time; that refresh uses the rule origin.
  `Allow Location…` in Settings asks the same way. Kadence never asks twice on
  its own.
- **States** (Settings ▸ Travel, `layouts.md` §13 — the only place they
  show; the popover, the inspector and notifications never mention
  location). Shown only while `Use where you are` is on:

| State | Title | Body | Button |
|---|---|---|---|
| `denied` (or restricted) | `Location is off for Kadence` | `Kadence works out each trip from Home or from your previous event instead. To use where you are, allow Kadence in System Settings ▸ Privacy & Security ▸ Location Services.` | `Open System Settings…` — `x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices` |
| `servicesOff` | `Location Services are off` | `Location Services are off on this Mac, so Kadence works out each trip from Home or from your previous event.` | `Open System Settings…` — the same URL |
| `notDetermined`, Kadence has asked | `Location isn't allowed yet` | `Kadence can use where you are to work out the trip to your next event.` | `Allow Location…` — asks again; if macOS shows no prompt, opens the URL above |
| `allowed`, or `notDetermined` and never asked | — | — | — |

- Turning `Use where you are` off stops every location request at once; it
  does not revoke the system permission (System Settings does that).
- The state is re-read on launch, on `didBecomeActive` and when Settings ▸
  Travel opens.

---

## 25. The travel band, live

§4's visual spec is **unchanged**: geometry, the two height cases, z-order,
fill, hatch, corner rules, `travelLabel`, `color.text.secondary`, the
footprint rule (`layouts.md` §3.3), not focusable, folded into the parent's
VoiceOver label, never in Month, never on all-day items. What changes is the
data and the words.

### 25.1 Exactly what changes from §4

| §4 said | From 2026-10-14 |
|---|---|
| Fed by a display fixture (`TravelFixture`, §12 items 7–8) | Fed by the event's **`TravelLeg` with status `ready`**. `TravelFixture` is retired; the review datasets compute real legs (§30.1) |
| "Never drawn for an event with no location" | Drawn **exactly when the event has a `ready` or `estimate` leg**. No leg (no place, same place, online, skipped, cancelled, all-day, routine) → no band. A `pending` or `unavailable` leg → **no band**: there is no time to draw, and a band without one would be a guess. The inspector and popover say why (§25.3) |
| Occupies `departAt → event.start` | Unchanged — and `departAt` now includes the **buffer**, so the band is travel **plus** buffer tall |
| Label `Leave HH:mm · NNmin` | Unchanged form. **`HH:mm` is `departAt`; `NN` is the travel time without the buffer** (`Leave 08:15 · 35min` on a 09:00 lecture: 35 min trip, 10 min buffer, 45 min band). Below 18pt the duration drops, below 14pt the glyph only — as §4 |
| Glyph by mode | The leg's `mode` (§23.3: `tram.fill`, `figure.walk`, `car.fill`) |
| — | **An estimate** (§24.3) is marked by **`≈` before the minutes**: `Leave 08:15 · ≈35min`. Below 18pt, where the minutes drop, `≈` moves before the time: `Leave ≈08:15`. Same font, colour, fill and hatch — the mark is a character, not a colour, so it survives template rendering and greyscale |
| Hover help `Leave 08:12 · 22 min walking` (as built) | **`Leave 08:15 · 35 min by public transport from Home · 10 min buffer`** (`· N min buffer` omitted at 0). Estimate: **`Leave about 08:15 · about 35 min by public transport from Home · 10 min buffer · estimate, offline`** (the short reason, §24.10). Current location: `from where you are` |
| VoiceOver phrase `leave by 08:12, 22 minutes walking` | §29 |

### 25.2 States

The band takes **its parent's presentation**, nothing of its own:

- **past** (the parent is past): the band's content takes
  `opacity.blockPastContent` and its fill the same `opacity.blockPastFillBlend`
  blend as the parent. A past band is history (§24.5).
- **done**: drawn as past. A **skipped** or **cancelled** parent has no leg.
- **Should have left** (`departAt ≤ now < start`): **no change on the
  canvas.** The now line already crosses the band, which says exactly that;
  the menu bar carries the state (§26). A red band would be a second "now"
  signal on the canvas and would spend red on a block (§1).
- **Selected / dragging / conflicted**: as §4 — the band follows its parent and
  is never independently selected. While a manual event is dragged, its band
  is **not** drawn at the drop preview; it reappears after the drop when the
  recompute has run (§24.6). An imported event never drags (§18.2).

### 25.3 A leg with no time — `pending` or `unavailable`

*(Rewritten 2026-10-14, routing amendment; was "a leg that needs a travel
time".)* No band (§25.1). The inspector's `Leave by` row says `Working out…`
or `Unavailable` with the reason and, where there is one, the way to fix it
(`layouts.md` §6); the popover's leave line says it (§26.2); the event gets
the travel-unavailable notification N7 instead of a leave-by (§27.2). Hover
help on the block gains `· Travel time from Home unavailable: offline` (the
short reason, §24.10; `pending`: `· Travel time from Home not worked out
yet`).

A band does not animate when a refresh moves it (§24.6): it is redrawn at the
next frame, like any derived data arriving.

---

## 26. Leave-by in the menu bar

The Phase 2 brief: the status item shows "the single next thing — its title,
its start time, and **the leave-by time once Phase 3 exists**". §15's budget,
truncation and template-rendering rules all stand.

### 26.1 The status item

Two states are added between Normal and Late. They apply when NEXT has a
leg with a time — `ready` or `estimate` (§24.3; "a `ready` leg" below means
either):

| State | When | Content | Colour (popover and offscreen only, §15.1 2026-10-05) |
|---|---|---|---|
| Normal | no `ready` leg, `now < start` | `17:30 · Training` | `color.text.primary` |
| **Leave** | `ready` leg, `now < departAt` | **`Leave 08:15 · SWQM-ILV`** | `color.text.primary` |
| **Leave now** | `ready` leg, `departAt ≤ now < start` | `clock.badge.exclamationmark` + **`Leave now · SWQM-ILV`** | `color.semantic.now` |
| Late | `start ≤ now` | glyph + `12m ago · SWQM-ILV` | `color.semantic.now` |
| Empty | — | `Nothing left today` | `color.text.secondary` |

- **The time unit.** In Leave, `Leave 08:15` is one unit that takes §15.1's
  "time" role: never truncated, never split, always first. The title
  truncates and drops by §15.1's rules with the unit's measured width in
  place of the time's (degrade point = width(`Leave 08:15`) + width(` · `) +
  `size.statusItemTitleMinWidth`, about 117pt; below it, `Leave 08:15` alone).
  In Leave now, glyph + `Leave now` is the unit, exactly as glyph + `12m ago`
  is in Late.
- **"Leave now" is the should-have-left state.** It is an instruction that is
  true at that moment, it is not a deficit (`late`, `missed`, `overdue` stay
  banned), and it reads from across the room. The elapsed figure is in the
  popover (§26.2). This is a reading of `DECISIONS.md` 2026-09-10's "phrased
  as elapsed" for a state that ruling did not have; it is a proposed
  DECISIONS entry for Parsa (plan, "DECISIONS.md").
- The glyph is the Late state's `clock.badge.exclamationmark`: the same fact
  — the time that mattered has passed. No new symbol.
- **An estimate** puts `≈` before the time inside the unit: `Leave ≈08:15 ·
  SWQM-ILV` (the degrade point is measured on `Leave ≈08:15`). Leave now is
  unchanged by an estimate — the instruction is the same. *(Routing
  amendment, 2026-10-14.)*
- **A leg with no time** (`pending`, `unavailable`) shows the Normal state
  (start time). The popover says why (§26.2). The status item never shows a
  reason: it is one glance, and the reason needs a sentence.
- The item switches state at the minute boundary on its existing timer
  (§15: "updates on a timer and on any data change"); no animation (§12.1).

**A due departure outranks a late item.** Phase 2's NEXT is the earliest
not-done, not-skipped timed event of today, so an event that started and was
never marked stays NEXT (the late state, with `Re-offer`). That must not hide
a departure. So:

> If NEXT by Phase 2's rule is **late**, and some other candidate today has
> not started and has a `ready` leg with `departAt ≤ now + 30 min`, the
> earliest-starting such event **is NEXT** (in Leave or Leave now). The late
> item is the first row of REST OF TODAY. When that event starts, Phase 2's
> rule applies again.

30 minutes is a behaviour constant (`leaveDueLookahead`), not a token. Review
fixture: §30 item 13.

### 26.2 The popover

**NEXT gains a leave line**, between the title and the meta line, when NEXT
has a leg:

```
+------------------------------------------+
|  NEXT                                    |
|                                          |
|  SWQM-ILV                                |   popoverNextTitle
|  Leave by 08:15 · 35 min from Home       |   popoverNextMeta, text.primary   ← new
|  09:00 – 10:30 · HS_A3.15 · University…  |   popoverNextMeta (meta line)
|                                          |
|  [ Done ]  [ Open ]                      |
|------------------------------------------|
```

| NEXT's state | Leave line | Colour |
|---|---|---|
| Leave | `Leave by 08:15 · 35 min from Home` | `color.text.primary` |
| Leave, estimate | `Leave by ≈08:15 · estimate, offline` (the short reason, §24.10) | `color.text.primary` |
| Leave, from the current location (§24.2.1) | `Leave by 08:22 · 28 min from where you are` | `color.text.primary` |
| Leave now | `Leave now · leave-by was 08:15` (estimate: `was ≈08:15`) | **`color.semantic.now`** (4.55 / 5.12 on `surface.popover`, `tokens.json` 1.8.0) |
| Late (started) | — (omitted; the meta line says `Started 12m ago`) | |
| `pending` | `Travel time from Home not worked out yet` | `color.text.secondary` |
| `unavailable` | `Travel time unavailable · offline` — the short reason: `· Home has no address`, `· no route by public transport`, `· Apple Maps paused until 10:40`, `· Apple Maps didn't answer` | `color.text.secondary` |
| No leg | — (omitted) | |

- `popoverNextMeta`, `lineLimit` 1, tail truncation. The time comes first and
  is never truncated; the place name (the user's text) truncates.
- The origin is the place **name** (`from Home`, `from FH Technikum Wien`),
  or `from where you are` (§24.2.1).
  The mode is not on this line (the hover help, inspector and VoiceOver carry
  it); the line is for arm's length.
- **The meta line's order follows §3.4's 2026-10-10 amendment from now on:**
  `09:00 – 10:30 · HS_A3.15 · University timetable` — time, then location,
  then source, the source truncating first. §3.4 left the popover alone when
  it had no location; with the leave line above it, a truncated room
  (`· University timetable · HS_A…`) would hide the one fact the leave line
  points at. With no location: `17:30 – 18:15 · Daily routine`, as before.
  Online: `14:00 – 15:30 · Online · University timetable`.
- **Actions** are unchanged by the leave states: `Done` · `Snooze` · `Open`,
  or `Done` · `Open` for an imported NEXT (§18.3). **No `Re-offer` in Leave
  now** — the event has not started, so there is nothing to re-offer.
  `Snooze` on a manual NEXT with a leg moves the event (§16); the leg follows
  on the next recompute, so the leave line and the status item show the new
  departure.
- REST OF TODAY rows are **unchanged** — no leave times in the list (§15.2:
  not a second calendar).
- The NEXT block's height grows by one `popoverNextMeta` line when the leave
  line is shown; `size.popoverNextBlockMinHeight` stays a minimum.

### 26.3 The popover's last lines

§19.4's stale line is joined by a **notifications line**, same slot (last
element, `spacing.lg` above), same style (`popoverRefusalRow` metrics,
`lineLimit` 0, `color.text.secondary`, no glyph, not focusable, not a button).
Order: stale source lines first, then this one. Shown only when **at least
one notification rule is enabled** (§27.1) and:

| Authorization (§27.8) | Line |
|---|---|
| `off` | `Notifications are off, so Kadence can't tell you when to leave.` |
| `notAllowedYet` | `Notifications aren't allowed yet. Settings ▸ Notifications` |
| `allowed`, or Kadence has not asked yet | — |

The remedy is in Settings ▸ Notifications (`layouts.md` §14); `Open` still
opens the main window, and `⌘,` opens Settings. All rules off is the user
saying so: no line.

---

## 27. Notifications

Local notifications through `UNUserNotificationCenter`, behind a protocol
(§27.10) so nothing in tests or review touches the real centre. No badge on
the app icon, ever (§27.9).

### 27.1 Rules

Five `NotificationRule`s (§28.1), created at first launch with these
defaults, edited in Settings ▸ Notifications (`layouts.md` §14):

| Kind (`kind` raw) | Settings label | Applies to | Default | Lead choices |
|---|---|---|---|---|
| `leaveBy` | `Leave by` | an event with a `ready` leg | **on, 5 min** | `At leave time` · 5 · 10 · 15 · 30 min |
| `timetableStart` | `Timetable` | an imported event that gets no leave-by | **on, 30 min** | `At start time` · 5 · 10 · 15 · 30 min · 1 hour |
| `personalStart` | `Personal events` | a manual event that gets no leave-by | **on, 15 min** | as `timetableStart` |
| `routineStart` | `Routine` | a routine block | **on, 5 min** | as `timetableStart` |
| `syncPaused` | `Sync problems` | a connected source whose sync pauses after a 401 or 403 (§27.4 N8; G-060) | **on** | none — delivered when it happens |

The defaults are Parsa's, confirmed 2026-10-14: leave-by 5, timetable 30,
personal 15, routine 5 and on, sync problems on. A disabled rule keeps its
lead time.

### 27.2 Which notification an event gets — at most one

| Event | Notification |
|---|---|
| all-day, cancelled, `.done`, `.skipped`, or starting before `startOfDay(today)` | **none** |
| has a `ready` or `estimate` leg **and** `leaveBy` is enabled | **leave-by** (N1, or N1e for an estimate) |
| has a `pending` or `unavailable` leg **and** `leaveBy` is enabled | **travel unavailable** (N7): the leave-by that could not be worked out, never dropped silently. When the leg gets a time, the next pass replaces it with N1 under the same identifier |
| otherwise (no leg, or `leaveBy` disabled) | **starts**, under its origin's rule (`timetableStart` / `personalStart` / `routineStart`), if that rule is enabled |
| `.planned` (Phase 6) | none in this slice |

An event with a leave-by gets **no** "starts" notification: one event, one
nudge, at the moment that matters. Turning `Leave by` off falls back to the
start rule rather than silencing the event.

### 27.3 When it fires

The **subject time** is what the notification is about: `departAt` for a
leave-by, `start` for a starts. The **fire time** `F`:

1. Leave-by: `F = departAt − lead`. Travel unavailable (N7): **`F = start −
   60 min`** (`unavailableLead`, a behaviour constant, not a token): the hour
   in which you would check your route. It names no travel time, so it guesses
   none. The quiet rule applies as to a starts.
2. Starts: `F = start − lead`. **Chain clamp:** if §24.2 finds a `P` within
   `chainGap` (whatever its place), `F = min(max(F, P.end), start)` — the
   notification for the second of two back-to-back lectures comes when the
   first one ends, not in the middle of it. The leave-by is **not** clamped:
   if you must leave during the previous event, you are told when you must
   leave.
3. Then the quiet rule (§27.5) may move `F` later.

Copy is fixed at planning time, with **absolute times only**: a notification
outlives its moment in Notification Center, and `in 5 min` read twenty
minutes later is false. `08:15` stays true.

### 27.4 Copy — exact, tested

`{title}`: the event's title as the block shows it (a CIS event's course
code). `{where}`: the event's location text if not empty (`HS_A3.15`,
`Online` for an online event), else its place's name (`Home`); omitted with
its separator when both are empty. `{origin}`: the origin place's name.
`{min}`: travel minutes. `{source}`: the source's display name. Times are
`HH:mm`, 24-hour.

| # | Notification | Title | Body | Category |
|---|---|---|---|---|
| N1 | Leave-by | `Leave by {depart} for {title}` | `Starts {start} · {where} · {min} min from {origin}` | by event (§27.7) |
| N2 | Leave-by, moved past `departAt` by a protected window (§27.5) | `Leave now for {title}` | `Starts {start} · {where} · Leave-by was {depart}, inside {window} (protected)` — unlabelled window: `inside a protected window` | by event |
| N3 | Leave-by, catch-up after `departAt` (§27.6) | `Leave now for {title}` | `Starts {start} · {where} · Leave-by was {depart}` | by event |
| N4 | Starts | `{title} starts at {start}` | `{where} · {source}`; no `{where}`: `{source}` | by event |
| N5 | Snooze result, moved | `{title} moved to {new}` — `moved to tomorrow {new}` across a day, as §16 | `Snoozed from {old} · ⌘Z in Kadence undoes it` | `result` |
| N6 | Snooze result, refused | `{title} not moved` | `{new} is inside {window} (protected)` / `{new} is inside a protected window` — §16's family | `result` |
| **N1e** | Leave-by from an **estimate** (§24.3) | `Leave by about {depart} for {title}` | `Starts {start} · {where} · about {min} min from {origin} · estimate, {reason}` | by event |
| **N7** | **Travel unavailable** (a `pending` or `unavailable` leg, §27.2) | `{title} starts at {start}` | `{where} · Travel time from {origin} unavailable: {reason}. Check your route before you leave.` — `pending`: `{where} · Travel time from {origin} isn't worked out yet. Check your route before you leave.` | by event |
| **N8** | **Sync paused** (§19.1 `unauthorized`, `forbidden`; G-060) | `{name} isn't syncing` | `unauthorized`: `{host} didn't accept the password for {user}. Sync is paused until you update it in Kadence.` · `forbidden`: `{host} refused access for {user}. Sync is paused until you check the account in Kadence.` | `source` |

*(N1e, N7, N8 and `{origin}` = `where you are` added 2026-10-14, routing
amendment.)* `{reason}` is §24.10's **short** form (`offline`, `Home has no
address`, `no route by public transport`, `Apple Maps paused until 10:40`,
`Apple Maps didn't answer`). N2 and N3 from an estimate write `Leave-by was
about {depart}`. `{origin}` is `where you are` for a current-location leg.

Examples (§30.1, buffer 10): N1 `Leave by 12:15 for EPC-ILV` /
`Starts 13:00 · LAB_F5.12 · 35 min from Home`. N1 for a manual event at Home:
`Leave by 17:45 for Dinner with flatmates` / `Starts 18:30 · Home · 35 min
from FH Technikum Wien`. N2 `Leave now for Early study group` / `Starts 07:30
· FH Technikum Wien · Leave-by was 06:45, inside Sleep (protected)`. N4
`REQEN-EXAM starts at 16:00` / `EDV_A5.09 · University timetable`; `INNO3-EL
starts at 14:00` / `Online · University timetable`; `Late call starts at
23:15` / `Personal`.

- **Never** `late`, `missed`, `overdue`, a count, or an exclamation mark.
- Titles are the system's to truncate; the body repeats nothing the title
  says except the time it is about.
- Sound: the default sound for N1–N4, N1e, N7 and N8; **none** for N5–N6
  (the user just acted).
- **Interruption level** *(ruled 2026-10-14, G-089 closed — Parsa:
  time-sensitive)*: **`.timeSensitive`** for N1, N1e, N2, N3 and N7 — a
  departure is what Focus is meant to let through; `.active` for N4 and N8;
  `.active` without sound for N5–N6. **Degrades, never fails**: without the
  `com.apple.developer.usernotifications.time-sensitive` entitlement, or with
  time-sensitive notifications off for Kadence, macOS delivers them as
  `.active`. If `add` itself throws for a time-sensitive request, the applier
  adds it again once with `.active` and logs `notification degraded ·
  time-sensitive unavailable`. No test depends on the entitlement: the
  recording centre records the level asked for.
- **N8, the sync-paused notification** (G-060, pulled into this slice by
  Parsa): sent once when a source **enters** `unauthorized` or `forbidden`
  in a sync Kadence started on its own (background, wake, launch) — not when
  the user is looking at it (`Sync Now`, Import, the connect sheet, while
  Kadence is frontmost). Identifier `sync.{sourceID}`; delivered with a
  1-second trigger, or held to the end of a protected window like any
  notification (§27.5 — it is not urgent). Not repeated while the source stays
  paused; removed, pending and delivered, when the source leaves the paused
  state or is removed. Category `kadence.source` (§27.7). `{name}`, `{host}`,
  `{user}` as §19.1 — the username and host are not secret (§19.1's rules);
  the password never appears.

### 27.5 Quiet: protected windows hold notifications

No notification is delivered inside a `.protected` `TimeWindow` (Sleep)
**unless the event itself is inside it**:

1. Take every `.protected` span from `TimeWindow.spans(on:)` (§13.6.1's spans,
   so an overnight window counts on both days). If `S.start ≤ F < S.end` and
   the event **does not strictly overlap** `S` (§13.6.1's test), set
   `F = S.end`. Repeat while `F` lands in another such span.
2. If the event strictly overlaps `S` — `Late call` 23:15 inside Sleep — the
   notification fires at its own time: the user put the event there, and
   being told about it is what they asked for.
3. A **held leave-by** whose new `F` is after `departAt` takes copy N2: it
   arrives when the window ends and says the leave-by was inside it. It is
   never dropped — the event is outside the window, so the departure still
   matters (`Early study group`: due 06:40, held to 07:00, N2). A held starts
   notification keeps N4 (`F ≤ start` always holds, because the event is
   outside the window).
4. `.lowEnergy` and `.peakFocus` windows do not affect notifications.
5. **Lectures are not quiet time** in this slice: a notification due during
   a lecture fires (G-090, Parsa). The chain clamp (§27.3) already keeps the
   common case — the next lecture's "starts" — out of the lecture before.
6. Snooze results (N5, N6) are answers to the user's own act and are
   delivered at once, inside a window or not.

### 27.6 Scheduling

**The scheduler** = a pure **planner** (`NotificationPlanner`: value snapshots
of events, legs, rules, protected windows, records, `now`, and whether this is
a catch-up pass → planned requests with identifier, fire date, title, body,
category, sound, `userInfo`) and an **applier** that diffs the plan against
the centre (§27.10).

- **Identifiers**: `leave.{eventID}` (N1, N1e, N2, N3 and N7 — one
  leave-by slot per event, whatever its leg's state), `start.{eventID}`;
  `result.{eventID}.{epochSeconds}` for N5/N6; `sync.{sourceID}` for N8. Deterministic, so a pass that
  plans what is already pending changes nothing, a relaunch cannot duplicate,
  and an event has at most one of `leave.`/`start.` pending (a leg appearing
  removes `start.` and adds `leave.`).
- **Window**: requests whose `F` is in `(now, now + 48 h]`, at most the **48**
  earliest (the system keeps 64 per app; headroom for results). The window
  rolls forward on every pass.
- **Trigger**: `UNCalendarNotificationTrigger` with year … second in the
  current calendar and time zone, not repeating. Catch-up and results: a
  1-second `UNTimeIntervalNotificationTrigger`.
- **Diff**: a pending Kadence request whose identifier is not in the plan is
  removed; one whose fire date or content hash (`userInfo["hash"]`, SHA-256 of
  title, body, category) differs is replaced; an identical one is left alone.
  Requests whose identifiers do not start with `leave.`, `start.`,
  `result.` or `sync.` are never touched.
- **Records** (`NotificationRecord`, §28.1): for each scheduled identifier the
  fire date it was given. **A record whose fire date has passed means "sent"**
  — the system delivers a scheduled request even when Kadence is not running.
  A sent identifier is never planned again unless its subject moves (a new
  fire date in the future is a new notification: the event was moved later).
  Records are deleted with their event, and when their event ended more than a
  day ago.
- **Passes** run (debounced 1 s, one at a time — a trigger during a pass is
  coalesced into one more pass after it):
  - after every leg recompute (§24.6 — which already covers every event
    change, sync, place, address, mode or buffer edit, routing answer,
    departure refresh, launch, wake, day and clock change);
  - when a rule is edited, a `TimeWindow` is created, edited or deleted, or
    authorization changes (§27.8);
  - **hourly** while running, so the 48-hour window rolls forward on a quiet
    day.
- **Never scheduled**: anything §27.2 excludes; any request whose subject time
  has passed; any request whose `F` has passed — **except in a catch-up
  pass**.
- **A departure refresh is a catch-up for its own leg** *(routing
  amendment)*: when a refresh (§24.6) moves `departAt` earlier so that the
  pending leave-by's new `F` has passed while `departAt` has not, that one
  request is delivered at once (N1 / N1e). Traffic got worse; being told late
  is better than not at all. No other request in that pass is late.
- **Catch-up pass** (the pass after **launch** and after **wake** only): a
  request with no record, whose `F` has passed but whose event has not
  started, is delivered **at once**, with N1 if `now < departAt`, N3 if
  `departAt ≤ now < start`; a starts (N4) if `now < start`. This is the case
  where Kadence could not deliver on time (it was not running, or the Mac was
  asleep when the plan would have been made). An ordinary pass never sends a
  notification late: a change the user just made in the app is visible in the
  app.
- **Removal**: an event deleted, marked done, skipped, cancelled, or no longer
  matching a rule loses its pending request in the next pass. **Delivered**
  notifications whose event has ended, been deleted, marked done, skipped or
  cancelled are removed from Notification Center in the same pass — a list of
  stale reminders is a backlog the user did not ask for (§27.9).
- **Authorization not `allowed`**: the planner still runs (Settings and the
  popover need its state), the applier adds nothing, removes nothing that is
  pending, and records nothing. When authorization becomes `allowed`, the next
  pass schedules the plan (as a normal pass, not a catch-up).

### 27.7 Actions

The popover's semantics, through the same `EventStore` verbs and the same
undo stack (`⌘Z` in the main window undoes them), addressed by `eventID`
from `userInfo`, resolved at the moment the action runs (DECISIONS
2026-09-09: no closure holds an `Event`).

| Category | When | Actions |
|---|---|---|
| `kadence.event` | a manual or routine event | `Done` · `Snooze` · `Open` |
| `kadence.readOnly` | an imported event | `Done` · `Open` — **no `Snooze`**: snoozing moves the event, and an imported event cannot move (§18.3) |
| `kadence.result` | N5, N6 | none (clicking opens, below) |
| `kadence.source` | N8 | `Open` only. `Open` and clicking open Settings ▸ Sources with that source selected (`layouts.md` §11), where its status block's `Update Password…` / `Edit Account…` is one click |

| Action | Does | Undo step |
|---|---|---|
| `Done` (background) | marks the event `.done`; already done → nothing. Its pending and delivered notifications go in the next pass | `Mark Done` |
| `Snooze` (background) | `EventStore.snooze` — §16's +15 placeholder (G-016) **with §16's protected-window refusal**. Then N5 (moved) or N6 (refused) is delivered at once. A moved event's leg and notification follow on the next recompute | `Snooze` (moved only) |
| `Open` (`.foreground`) | the popover's `Open`: activate Kadence, open the main window if closed, page to the event's day, select it | — |
| Clicking the notification (`UNNotificationDefaultActionIdentifier`) | `Open` | — |
| Dismissing it | **nothing** (§27.9) | — |

- An action whose event no longer exists: `Open` opens the main window on
  today with nothing selected; `Done` and `Snooze` do nothing.
- A cancelled imported event has no notification (§27.2), so Done is never
  offered on one (§20.6 refuses it).
- Delivery while Kadence is frontmost: shown as a banner with sound
  (`willPresent` → `.banner`, `.list`, `.sound`; results without `.sound`).

### 27.8 Permission

**When Kadence asks.** Not at launch. The first time a pass has **at least one
request to schedule** while authorization is `notDetermined` and Kadence has
never asked (`AppSettings.notificationsRequestedAt == nil`), it calls
`requestAuthorization(options: [.alert, .sound])` once and records the time.
On a real first run that is right after the timetable's Import or the first
manual event — the moment there is something to tell. Turning a rule on in
Settings, or `Allow Notifications…`, asks the same way. Never `.badge`, never
`.provisional`.

**What Kadence calls the state** (read on launch, on `didBecomeActive`, when
Settings ▸ Notifications or the popover opens, and after asking):

| `UNAuthorizationStatus` / settings | Kadence's state |
|---|---|
| `authorized`, `provisional`, `ephemeral`, with `alertSetting` enabled | `allowed` |
| `authorized` with `alertStyle == .none` (the user chose "None"), or `denied` | `off` |
| `notDetermined`, Kadence has asked | `notAllowedYet` |
| `notDetermined`, Kadence has not asked | `notAsked` — nothing is shown |

**Never silent when it can't notify.** In `off` and `notAllowedYet` (and at
least one rule on): Settings ▸ Notifications shows a status block
(`layouts.md` §14), and the popover shows §26.3's line. There is no alert and
no nag: Kadence does not ask again on its own.

| State | Title | Body | Button |
|---|---|---|---|
| `off` | `Notifications are off` | `macOS isn't showing notifications from Kadence, so it can't tell you when to leave or when something starts. Turn them on in System Settings ▸ Notifications ▸ Kadence.` | `Open System Settings…` — `x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=XIX.Kadence` |
| `notAllowedYet` | `Notifications aren't allowed yet` | `Kadence needs your permission to tell you when to leave and when something starts.` | `Allow Notifications…` — asks again; if macOS shows no prompt (the question was already answered), opens System Settings as above |

**Recovery** is detected, not assumed: when the state becomes `allowed`, the
block and the line disappear and the next pass schedules the plan.

### 27.9 Skipped and missed — re-offered, never counted

- An **ignored or dismissed** notification changes **nothing**: no status,
  no mark, no count, no follow-up "you missed …". The event reaches its start
  and becomes the popover's late state with `Re-offer` (§15.2), which is where
  a missed item is re-offered.
- **No badge** on the app icon and no count anywhere of notifications sent,
  ignored or acted on.
- Delivered notifications whose moment has passed are cleared (§27.6), so
  Notification Center never becomes a list of what didn't happen.
- `Done` and `Snooze` are the only actions; neither is ever offered as a
  consequence of not acting.

### 27.10 The centre behind a protocol

```swift
protocol NotificationCenterClient: Sendable {
    func authorization() async -> NotificationAuthorization   // allowed / off / notDetermined
    func requestAuthorization() async -> Bool
    func setCategories(_ categories: [NotificationCategorySpec]) async
    func pending() async -> [ScheduledRequest]
    func add(_ request: ScheduledRequest) async throws
    func removePending(_ ids: [String]) async
    func delivered() async -> [DeliveredNotification]
    func removeDelivered(_ ids: [String]) async
}
```

- **`SystemNotificationCenter`** wraps `UNUserNotificationCenter.current()`.
  It is used **only by a normal launch**.
- **`RecordingNotificationCenter`** keeps requests in memory, with an
  injectable authorization (`allowed` / `off` / `notDetermined`) and a
  scriptable `requestAuthorization` answer. It **never shows a prompt**. Used
  by every test and by every review launch — the same three-launch rule as
  §22.1's store and transport (B45): a launch XCTest started, or one with
  `-KadenceReview`, never calls `UNUserNotificationCenter`.
- Review mode takes `-KadenceNotifications allowed|off|notDetermined|notAsked`
  (default `allowed`) and writes the recorded plan to a text file for review
  (§30 item 14).
- Responses are simulated in tests by calling the delegate's handler with an
  action identifier and `userInfo`; no real response object is needed.
- `ScheduledRequest` carries the **interruption level** asked for (§27.4), so
  tests assert `.timeSensitive` without the entitlement.

---

## 28. Data model additions (slice 2) — PROPOSED

*Proposed by the design agent, 2026-10-14, for Parsa's confirmation (plan,
"DECISIONS.md"); **rewritten the same day for the routing amendment**.
BRIEF-PRODUCT's draft has `Place(name, address, coordinate)`,
`TravelLeg(eventID, departAt, duration, mode, computedAt)` and
`NotificationRule(kind, leadTime, isEnabled)`. Below: what changes and why.*
SwiftData `@Model`s, enums as raw strings, every new field with a default so
a slice 1 store opens without a migration step (as §21.3). **Withdrawn before
it was built:** `TravelRoute` (typed minutes per pair) — replaced by
`TravelModeOverride` and `TravelETACache`.

### 28.1 New models

**`KnownPlace`** — BRIEF's `Place`, under a new name. The existing `Place`
model is already something else: the event's stated location, one row per
event, written by the sync as `Place(name: "HS_A3.15")` (§20.7, §21.3). Making
it the travel endpoint would mean a migration of every imported event and
would mix "where in the building" with "where you travel to". So `Place` stays
as it is, and the travel endpoint is new.

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | `home`, `campus` for the built-ins; a UUID string otherwise. A String, as `Source.id` |
| `name` | `String` | §23.1 |
| `addressText` | `String?` | what the user typed (`campus`: `Höchstädtplatz 6, 1200 Wien` at first launch, §23.6) |
| `confirmedAddress` | `String?` | MapKit's one-line address the user confirmed (§23.5) |
| `latitude`, `longitude` | `Double?` | the confirmed result's coordinate; **both set or both nil**, and set only by a confirmation (§23.5) or the campus's automatic match (§23.6) |
| `geocodeState` | raw `none` / `unconfirmed` / `notFound` / `lookupFailed` / `confirmed` | §23.5; `searching` is not stored. A place keeps its last confirmed coordinate in any state but `none` |
| `geocodedAt` | `Date?` | when the coordinate was confirmed |
| `isBuiltIn` | `Bool` | `home`, `campus`: renamable, not removable |
| `sortIndex` | `Int` | display order: `home` 0, `campus` 1, user places in creation order |

**`TravelModeOverride`** — new; a pair of places travelled in another mode
than the preferred one (§23.3).

| Field | Type | Notes |
|---|---|---|
| `placeA`, `placeB` | `String` | known place ids, **stored sorted** (`placeA < placeB`); the pair is unique |
| `mode` | `TravelMode` raw | `transit` / `walking` / `driving`. Choosing `Usual` in Settings **deletes** the row |

**`AppSettings`** — new, one row, id `app`: the settings that are not per
source, per place or per rule. In the store (not `UserDefaults`), so a review
or test launch — in-memory stores — can never read or write the real ones.

| Field | Type | Default |
|---|---|---|
| `preferredTravelMode` | `TravelMode` raw | `transit` (§23.3) |
| `travelBufferMinutes` | `Int` | 10 (§23.4) |
| `travelChainGapMinutes` | `Int` | 120 (§24.2; fixed, not in Settings) |
| `useCurrentLocation` | `Bool` | `true` (§24.2.1) |
| `locationRequestedAt` | `Date?` | nil (§24.12) |
| `campusLookupAttemptedAt` | `Date?` | nil (§23.6: at most one automatic retry a day) |
| `notificationsRequestedAt` | `Date?` | nil (§27.8) |

**`TravelLeg`** — BRIEF's draft, amended:

| Field | Type | Notes |
|---|---|---|
| `eventID` | `UUID` | unique; the event's local `id` (not `externalID`) |
| `status` | raw `ready` / `estimate` / `pending` / `unavailable` | §24.3 — a missing time is a state, not an absence |
| `isEstimate` | `Bool` | `status == .estimate`; stored so every reader tests one field (BRIEF-style flag the brief asked for) |
| `unavailableReason` | raw `needsAddress` / `offline` / `noRoute` / `paused` / `failed` / `pending`, or nil | §24.3; set for `estimate`, `pending` and `unavailable`, nil for `ready` |
| `reasonPlaceID` | `String?` | the place a `needsAddress` names |
| `retryAt` | `Date?` | `paused`: when the queue resumes |
| `departAt` | `Date?` | nil for `pending` / `unavailable` |
| `duration` | `TimeInterval?` | travel only, without the buffer |
| `buffer` | `TimeInterval` | the buffer used, so the band and the inspector can say it |
| `mode` | `TravelMode` raw | |
| `originKind` | raw `place` / `currentLocation` | §24.2.1 |
| `originPlaceID` | `String?` | the origin place; **nil for `currentLocation`** (no coordinate is ever stored) |
| `destinationPlaceID` | `String` | |
| `source` | `String` | the provider that produced the time: `mapKit`, `mock`; empty for `pending` / `unavailable` |
| `computedAt` | `Date?` | when that provider produced the time (§24.3); nil with no time |
| `refreshedAt` | `Date?` | the last departure refresh that succeeded (§24.6: decides `ready` vs `estimate` inside a refresh window) |

**`TravelETACache`** — new, bookkeeping only, never shown (§24.9):
`key: String` (unique — the key's fields joined, coordinates of known places
only), `originPlaceID`, `destinationPlaceID`, `mode` raw, `dayType` raw,
`slotMinutes: Int` (minutes after midnight, multiple of 30),
`travelSeconds: Double`, `computedAt: Date`, `arrivalDate: Date`. Rows of a
removed place, or of an old coordinate, are deleted with the change.

**`NotificationRule`** — BRIEF's draft: `kind` raw (§27.1's five),
`leadMinutes: Int` (BRIEF's `leadTime`, in whole minutes because every choice
is; 0 and unused for `syncPaused`), `isEnabled: Bool`. One row per kind,
created at first launch; a store that has the four slice-2 rules gains
`syncPaused` on the next launch, idempotently.

**`NotificationRecord`** — new, bookkeeping only, never shown:
`identifier: String` (unique), `subjectID: String` (the event's `id` as a
string, or the source's id for `sync.`), `kind` raw, `fireAt: Date`,
`contentHash: String` (§27.6).

### 28.2 `Event` addition

| Field | Type | Notes |
|---|---|---|
| `placeID` | `String?` = nil | the known place a **manual** event is at (§23.2 rule 3). Set only by the user (`layouts.md` §6, `Set Place`, an undo step). **Never written on an imported event** (its place is derived, §23.2 rule 5) and never on a routine instance (G-084). Copied by duplicate; kept in `EventStore`'s delete snapshot so undo restores it |

`Event.location` (`Place?`) is unchanged and keeps the stated location text.

### 28.3 Not added

No `Source` field (the timetable → campus rule reads `Source.kind`); no
per-event lead time; no per-event travel mode (G-094); no stored "origin
event"; no notification history; no stored current location, ever (§24.11).
A `TravelLeg` relationship on `Event` is not added: legs are found by
`eventID`, like sources by `sourceID` (§21.1.1).

---

## 29. Accessibility

VoiceOver strings, exact. Minutes are spoken as minutes (`35 minutes`), like
conflict copy (DECISIONS 2026-10-05). Mode phrases: `.transit` `by public
transport`, `.walking` `walking`, `.driving` `driving` (visible copy uses the
same phrases; Settings' pop-up shows `Public transport`, `Walking`,
`Driving`).

| Element | Spoken |
|---|---|
| A block with a `ready` leg (§11's label, the band folded in after the time) | `SWQM-ILV, 09:00 to 10:30, leave by 08:15, 35 minutes by public transport from Home, lecture, University timetable` — and `, 10 minute buffer` is **not** spoken (the leave-by time already includes it) |
| A block with an `estimate` leg | `SWQM-ILV, 09:00 to 10:30, leave by about 08:15, about 35 minutes by public transport from Home, estimate, lecture, University timetable` |
| A block with a `pending` / `unavailable` leg | `…, 09:00 to 10:30, travel time from Home not worked out yet, lecture, …` / `…, 09:00 to 10:30, travel time from Home unavailable, offline, lecture, …` (the short reason, §24.10) |
| Status item, Leave | label `Leave by 08:15 for SWQM-ILV`; estimate: `Leave by about 08:15 for SWQM-ILV, estimate` |
| Status item, Leave now | label `Leave now for SWQM-ILV, leave-by was 08:15` |
| Popover NEXT (one element, as built) | label `SWQM-ILV`; value `Leave by 08:15, 35 minutes from Home. 09:00 to 10:30, HS_A3.15, University timetable` — Leave now: `Leave now, leave-by was 08:15. …` |
| Popover notifications line | its text, as a static text element |
| Inspector `Place` row (imported) | `Place, FH Technikum Wien`; with the explanation: `Place, FH Technikum Wien, no travel needed after EPC-ILV` |
| Inspector `Place` pop-up (manual) | label `Place`, value `Home` / `None` |
| Inspector `Leave by` row | `Leave by, 08:15, 35 minutes by public transport from Home, plus 10 minutes buffer, worked out at 06:02 by Apple Maps`; estimate: `Leave by, about 08:15, estimate, …, last worked out Sunday 18:00 by Apple Maps, couldn't update, offline`; pending: `Leave by, working out`; unavailable: `Leave by, unavailable, ` + the inspector sentence (§24.10), and the button by its title (`Add Address`, `Change Way to Travel`, `Try Again`) |
| Settings ▸ Travel, `Usually` pop-up | label `Usual way to travel`, value `Public transport` |
| Settings ▸ Travel, a pair's mode pop-up | label `Way to travel, Home to Gym`, value `Walking` / `Usual, public transport` |
| Settings ▸ Travel, a place's name field | label `Place name`; address field `Address of Home` |
| Settings ▸ Travel, an address's state line | its text, read after the field; a match row in the list: `{name}, {address}`, button trait |
| Settings ▸ Travel, `Use where you are` switch | label `Use where you are for the next departure`, value on/off |
| Settings ▸ Travel, remove button | `Remove Gym` |
| Settings ▸ Notifications, a rule's switch | label `Leave by notifications`, value on/off |
| Settings ▸ Notifications, a rule's pop-up | label `Leave by, notify`, value `5 minutes before` |
| Settings ▸ Notifications, status block | one element: title then body; the button separately |
| Notifications themselves | the system reads title and body; nothing custom |

Hover help: the band's (§25.1); the status item has none (a menu bar extra
label shows no tooltip).

---

## 30. What slice 2 must render for review

Same rules as §17 and §22: display fixtures, mocked services, all six of
§17.2's evidence rules. **No item needs a network, a location, or a real
permission prompt**: every launch uses the recording centre (§27.10), the
mock travel provider, geocoder, location source and path monitor (§24.11).
Captures go to `screenshots/3b/`. Datasets and variants: §30.1.
*(Items 1, 2, 3, 12, 13, 15 amended and items 18–23 added 2026-10-14,
routing amendment.)*

1. **Settings ▸ Travel, first run** (dataset `empty`): the three tabs
   `Sources` · `Travel` · `Notifications`; `Home` with an empty address field
   (placeholder `Address`); `FH Technikum Wien` showing `Höchstädtplatz 6,
   1200 Wien, Austria` confirmed (the mock geocoder's automatic match,
   §23.6); `Usually` `Public transport`; no pair rows changed (`Usual`);
   `Buffer` `10 minutes`; `Use where you are` on, no status block
   (`-KadenceLocation notAsked`).
2. **Settings ▸ Travel, filled** (dataset `travel`): the three places with
   confirmed addresses (`Gym` with its remove button, the built-ins without),
   the Places footer naming `FH Technikum Wien`, the pair rows (`Home ↔ Gym`
   `Walking`, the other two `Usual (Public transport)`).
3. **Settings ▸ Notifications, allowed**: five rules at their defaults
   (`Sync problems` with a switch and no pop-up), no status block, the quiet
   footer.
4. **Settings ▸ Notifications, `off`** (`-KadenceNotifications off`) and
   **`notAllowedYet`** (`notDetermined` after a recorded ask): the status
   block with `Open System Settings…` / `Allow Notifications…`; one rule
   switched off with its pop-up disabled (not hidden).
5. **Week `M`** (dataset `travel`), scrolled to 07:00: bands on Mon `SWQM-ILV`
   (`Leave 08:15 · 35min`), Tue `SWEN3-LAB` (`Leave 09:15`) and **no** band on
   Tue `SWEN3-ILV` (back-to-back), **no** band on Wed `INNO3-EL` (Online) or
   `Laundry` (Home → Home), Thu `EPC-ILV` (`Leave 12:15`) and **no** band on
   `REQEN-EXAM`, Thu `Dinner with flatmates` (`Leave 17:45`, origin campus),
   Fri `SWRM-ILV` (`Leave 15:15`). Nothing selected.
6. **Week `M`, early and late**: a second scroll position showing Sat
   `Early study group`'s band from 06:45, across the end of `Sleep`; and Sat
   `Late call` inside `Sleep`, no band.
7. **Day, Thu `M + 3`**: `EPC-ILV`'s case-1 band at Day height, no band on
   `REQEN-EXAM`, `Dinner with flatmates`' band.
8. **A case-2 band** — `Climbing` (Sun, 15 min band, `figure.walk`) in Week
   and in Day: the strip inside the event's top. Replaces §12 item 8's
   fixture as evidence.
9. **Inspector, `SWQM-ILV` (Mon) selected**: `Room` `HS_A3.15`, `Place` `FH
   Technikum Wien`, `Leave by` `08:15` with `35 min by public transport from
   Home · 10 min buffer`.
10. **Inspector, `REQEN-EXAM` selected**: `Place` `FH Technikum Wien` with
    `No travel needed after EPC-ILV`, no `Leave by` row.
11. **Inspector, `Dinner with flatmates` selected**: the `Place` pop-up
    reading `Home`; `Leave by` `17:45`, `35 min by public transport from FH
    Technikum Wien · 10 min buffer`. A second frame with the pop-up open:
    `None`, separator, `Home`, `FH Technikum Wien`, `Gym`, separator, `Edit
    Places…`.
12. **Inspector, unavailable — no address** (variant `travelNoAddress`),
    `SWQM-ILV` selected: `Leave by` `Unavailable`, `Add the address of Home in
    Settings ▸ Travel so Kadence can work out the trip.` and `Add Address…`;
    Week `M` with **no** bands at all.
13. **Status item renders** (offscreen, §17.2 rule 3; `travel` dataset, clock
    pinned per row):

    | Capture | `now` | NEXT | Width | Expected |
    |---|---|---|---|---|
    | leave, full | Thu 11:50 | `EPC-ILV` | 180 | `Leave 12:15 · EPC-ILV` |
    | leave, degraded | Thu 11:50 | `EPC-ILV` | 110 | `Leave 12:15` alone |
    | leave now | Thu 12:20 | `EPC-ILV` | 180 | glyph + `Leave now · EPC-ILV` |
    | late | Thu 13:05 | `EPC-ILV` | 180 | glyph + `5m ago · EPC-ILV` (Phase 2, unchanged) |
    | takeover | Thu 17:20, `EPC-ILV` and `REQEN-EXAM` not done | `Dinner with flatmates` | 180 | `Leave 17:45 · Dinner with fl…` |
    | no takeover | Thu 17:10, the same | `EPC-ILV` (late) | 180 | glyph + `250m ago · EPC-ILV` |
    | estimate | Thu 11:50, variant `travelOffline` | `EPC-ILV` | 180 | `Leave ≈12:15 · EPC-ILV` |
    | unavailable | Thu 17:20, variant `travelOffline`, `EPC-ILV` and `REQEN-EXAM` done | `Dinner with flatmates` | 180 | `18:30 · Dinner with flatmates` (Normal: no time to leave by) |

14. **The notification plan** — not a screenshot: the review launch's
    recorded plan (§27.10) as `screenshots/3b/notification-plan-travel.txt`,
    one block per request (identifier, fire date, title, body, category,
    sound), at the two clocks of §30.1's notification table, plus the
    catch-up and snooze cases. INDEX.md names it. It is the review evidence
    for §27.3–§27.7; the strings are also asserted by tests.
15. **Popover renders** (offscreen): Leave (Thu 11:50, imported NEXT: `Done` ·
    `Open`), Leave now (Thu 12:20, `semantic.now` line — names its
    appearance), Late (Thu 13:05, no leave line), takeover (Thu 17:20,
    `EPC-ILV` as the first rest row), a manual NEXT with a leg (Thu 17:30,
    `EPC-ILV` and `REQEN-EXAM` marked done, `Dinner with flatmates`: `Done` ·
    `Snooze` · `Open`), the notifications line in `off` and in
    `notAllowedYet`, and the meta line `13:00 – 14:30 · LAB_F5.12 ·
    University timetable`. Routing states: **estimate** (variant
    `travelOffline`, Thu 11:50: `Leave by ≈12:15 · estimate, offline`),
    **unavailable** (variant `travelOffline`, Thu 17:30 as the manual-NEXT
    row: `Travel time unavailable · offline`), **no address** (variant
    `travelNoAddress`, Thu 11:50: `Travel time unavailable · Home has no
    address`), **pending** (variant `travelPending`, Thu 11:50: `Travel time
    from Home not worked out yet`), and **from where you are** (Thu 12:00,
    `-KadenceLocation allowed` with the mock fix `cafe`, §30.1: `Leave by
    12:22 · 28 min from where you are`).
16. **Live**: one live capture of the status item in the Leave state and one
    of the popover with its leave line (dataset `travel`, the live event
    `Pick up parcel`, §30.1), cropped from the real menu bar.
17. **Regression**: the `phase3` dataset's Week `M` and today's
    `Datenmodellierung` band `Leave 08:38 · 22min` (§12 item 7) drawn from a
    computed leg (§30.1, "Other datasets").
18. **Settings ▸ Travel, looking up an address** (dataset `empty`, Home's
    field, `-KadenceGeocode <case>`, one frame each): `one` — `Found:
    Example Straße 1, 1020 Wien, Austria` with `Use This Address` (default)
    and `Cancel`; `several` — `3 addresses match. Choose one:` and the list;
    `many` — the `More than 5 addresses match…` line above five rows;
    `none` — `No address found for “Exampel Strasse 1”…`; `offline` —
    `Couldn't look up the address because this Mac is offline.` with `Try
    Again`; `searching` — `Looking up…` (the mock's delay held). Plus a
    frame of `Gym` with a new unconfirmed address and `Still using Example
    Straße 1, 1020 Wien, Austria.`
19. **Settings ▸ Travel, location states** (dataset `travel`,
    `-KadenceLocation denied`, `servicesOff`, `notDetermined` after a
    recorded ask): the three status blocks of §24.12, exact; and `Use where
    you are` switched off with no block.
20. **Week `M`, estimates** (variant `travelOffline`, scrolled to 07:00): the
    campus bands from home marked `≈` (`Leave 08:15 · ≈35min`); **no** band on
    `Dinner with flatmates`. Plus the inspector of `EPC-ILV` (`12:15`,
    `estimate`, `About 35 min by public transport from Home · 10 min buffer`,
    `Last worked out 27 Sep 18:00 by Apple Maps. Couldn't update: this Mac is
    offline.`) and of `Dinner with flatmates` (`Unavailable`, the `offline`
    sentence).
21. **Inspector, `noRoute`** (variant `travelNoRoute`: the mock answers
    `noRoute` for `home → Gym` walking): `Climbing` selected, `Unavailable`,
    the sentence and `Change Way to Travel…`.
22. **The now time and an hour label** (A42, §8 amended): Week and Day with
    the clock pinned at 10:18 (offscreen): the `10:00` label dropped, the
    now time `10:18` clear of every other label by at least 2pt; at 10:40
    both `10:00` and `10:40` drawn. The cursor time likewise (hover at
    10:18).
23. **Notification plan, routing and sync** — appended to item 14's file:
    the `travelOffline` and `travelNoAddress` plans at Thu 06:00 (N1e, N7),
    the departure-refresh catch-up, and N8 for `unauthorized` and
    `forbidden` (§30.1).

### 30.1 Fixtures

#### Dataset `travel` (review)

`-KadenceReview travel`. In-memory store (§22.1), built-in sources, the
recording notification centre, **the mock travel provider, geocoder,
location source and path monitor** (§24.11). Contents:

- **One connected source**, `University timetable` (`blue`), seeded as
  already imported (§22.1), served by `MockCalDAVTransport` from
  **`Fixtures/ICS/cis-travel.ics.template`**: `cis-review.ics.template`
  (§22.1) **without row 1** (`{{TODAY}}` `Datenmodellierung` — it would chain
  today's live event to campus by the clock), **plus row T1**:

  | # | Day / time | Course | Room | Group | Lecturer | Serves |
  |---|---|---|---|---|---|---|
  | T1 | `{{D+1}}` 11:45–13:15 | `SWEN3-ILV` | `HS_A2.07` | `BIF-5C` | `L03` | back-to-back after `SWEN3-LAB` (items 5, §24.2) |

  So 15 VEVENTs, 14 events after the 7a+7b merge, 2 of them history.
- **No routine template** and therefore no conflicts and no Needs attention
  row: travel is reviewed on its own.
- **One time window**: `Sleep`, `.protected`, every day, 22:00–07:00.
- **Known places**, all `confirmed`, seeded with the mock geocoder's
  results (no lookup at launch):

  | Place | `addressText` | `confirmedAddress` | Coordinate (mock) |
  |---|---|---|---|
  | `Home` | `Example Gasse 5, 1030 Wien` | `Example Gasse 5, 1030 Wien, Austria` | 48.2000, 16.3900 |
  | `FH Technikum Wien` | `Höchstädtplatz 6, 1200 Wien` | `Höchstädtplatz 6, 1200 Wien, Austria` | 48.2390, 16.3770 |
  | `Gym` | `Example Straße 1, 1020 Wien` | `Example Straße 1, 1020 Wien, Austria` | 48.2050, 16.3950 |

  The coordinates are **fixture values** for the mocks, invented for review
  and tests only; they are never shipped as data, and the real campus
  coordinate is always MapKit's (§23.6). `Example` street names are
  deliberately not real addresses.
- **Ways to travel**: preferred `transit`; override `Home ↔ Gym` `walking`.
- **Mock travel provider** (`MockTravelTimeProvider`, scripted by directed
  pair and mode, independent of the arrival time unless a case says so):

  | From → to | Mode | Answer |
  |---|---|---|
  | `home → campus`, `campus → home` | transit | 35 min |
  | `home → Gym`, `Gym → home` | walking | 5 min |
  | `campus → Gym`, `Gym → campus` | transit | 20 min |
  | mock fix `cafe` → `campus` | transit | 28 min |
  | anything else | any | `noRoute` |

- **Mock geocoder** cases (`-KadenceGeocode`, default `one`): `one` → 1
  result (`Example Straße 1, 1020 Wien, Austria`); `several` → 3 (`Example
  Straße 1, 1020 Wien, Austria` / `Example Straße 1, 1210 Wien, Austria` /
  `Example Straße 1, 2340 Mödling, Austria`); `many` → 6; `none` → 0;
  `offline` → `offline`; `searching` → `one` after a held delay. The campus
  query `Höchstädtplatz 6, 1200 Wien` always answers 1 result,
  `Höchstädtplatz 6, 1200 Wien, Austria`, 48.2390, 16.3770.
- **Mock location** (`-KadenceLocation allowed|denied|servicesOff|notDetermined|notAsked`,
  default `notAsked`): authorization as named; with `allowed`, the fix
  **`cafe`** at 48.2150, 16.3800, accuracy 50 m, age 0 — 1.7 km from Home,
  so it is used (§24.2.1).
- **Buffer** 10 min; chain gap 120 min; `useCurrentLocation` on.
- **Rules**: the five defaults (§27.1).
- **Manual events** (`Personal`, `graphite`; `M` as §22.1):

  | # | Day / time | Title | `placeID` |
  |---|---|---|---|
  | P1 | `M + 2` 08:00–08:45 | `Laundry` | `home` |
  | P2 | `M + 3` 18:30–20:00 | `Dinner with flatmates` | `home` |
  | P3 | `M + 5` 07:30–09:00 | `Early study group` | `campus` |
  | P4 | `M + 5` 23:15–23:45 | `Late call` | nil |
  | P5 | `M + 6` 18:00–19:30 | `Climbing` | Gym |
  | P6 | today, start = launch time rounded **up** to the quarter hour + 60 min, 30 min long | `Pick up parcel` | `campus` |

  P6 is the one clock-relative fixture, and exists only for item 16's live
  captures: nothing placed precedes it today (row 1 is removed), so its
  origin is `home` and its leave-by is 15 min after the rounded launch time.
  Capture item 16 between 07:00 and 20:00.
- **Variants** (`-KadenceReviewVariant <name>`), each the same dataset with:
  - `travelNoAddress` — Home's address cleared (`none`, no coordinate)
    (items 12, 15, 23);
  - `travelOffline` — the provider answers `offline` to everything; the ETA
    cache seeded with one entry, `home → campus` transit, weekday, every slot
    of the dataset's campus lectures, 35 min, `computedAt` **`M − 15 days`
    18:00** (Sun 27 Sep): older than 14 days, so every leg asks, fails
    `offline` and falls back to it (§24.10 step 3) (items 13, 15, 20, 23);
  - `travelPending` — the provider never answers (held), nothing cached
    (item 15);
  - `travelNoRoute` — `home → Gym` walking answers `noRoute` (item 21).

Expected legs: §24.4 (and its variants). Expected bands: item 5.

#### Notification table (tests, and item 14)

Clock **Thu 15 Oct 2026** (`M` = Mon 12 Oct), zone Europe/Vienna, the
`travel` dataset rendered with `M` = 2026-10-12 and today = the clock's day
(so P6 is absent: tests do not seed it). Legs computed at the clock (so
Mon–Wed events, being before today, have none).

**At 06:00, ordinary pass** — 4 pending, in fire order:

| Identifier | Fire | Title | Body | Category |
|---|---|---|---|---|
| `leave.{EPC-ILV}` | Thu 12:10 | `Leave by 12:15 for EPC-ILV` | `Starts 13:00 · LAB_F5.12 · 35 min from Home` | `kadence.readOnly` |
| `start.{REQEN-EXAM}` | Thu 15:30 | `REQEN-EXAM starts at 16:00` | `EDV_A5.09 · University timetable` | `kadence.readOnly` |
| `leave.{Dinner}` | Thu 17:40 | `Leave by 17:45 for Dinner with flatmates` | `Starts 18:30 · Home · 35 min from FH Technikum Wien` | `kadence.event` |
| `leave.{SWRM-ILV}` | Fri 15:10 | `Leave by 15:15 for SWRM-ILV` | `Starts 16:00 · UEB_B2.01 · 35 min from Home` | `kadence.readOnly` |

(`Early study group`'s held leave-by fires Sat 07:00, outside the 48-hour
window.) `REQEN-EXAM`'s fire time is `max(15:30, 14:30)`: the chain clamp
does not move it.

**At Fri 16 Oct 23:00, ordinary pass** — 3 pending:

| Identifier | Fire | Title | Body |
|---|---|---|---|
| `leave.{Early study group}` | Sat 07:00 (held from 06:40 by Sleep) | `Leave now for Early study group` | `Starts 07:30 · FH Technikum Wien · Leave-by was 06:45, inside Sleep (protected)` |
| `start.{Late call}` | Sat 23:00 (inside Sleep; the event is too) | `Late call starts at 23:15` | `Personal` |
| `leave.{Climbing}` | Sun 17:40 | `Leave by 17:45 for Climbing` | `Starts 18:00 · Gym · 5 min from Home` |

`SWRM-ILV`'s leave-by (Fri 15:10) has passed: not planned, not sent late.

Interruption levels in both tables: every `leave.` request
`.timeSensitive`, every `start.` request `.active` (§27.4).

**Routing states at Thu 06:00, ordinary pass** *(routing amendment)*:

Variant `travelOffline` — 4 pending:

| Identifier | Fire | Title | Body |
|---|---|---|---|
| `leave.{EPC-ILV}` | Thu 12:10 | `Leave by about 12:15 for EPC-ILV` | `Starts 13:00 · LAB_F5.12 · about 35 min from Home · estimate, offline` |
| `start.{REQEN-EXAM}` | Thu 15:30 | `REQEN-EXAM starts at 16:00` | `EDV_A5.09 · University timetable` |
| `leave.{Dinner}` | Thu 17:30 (start − 60) | `Dinner with flatmates starts at 18:30` | `Home · Travel time from FH Technikum Wien unavailable: offline. Check your route before you leave.` |
| `leave.{SWRM-ILV}` | Fri 15:10 | `Leave by about 15:15 for SWRM-ILV` | `Starts 16:00 · UEB_B2.01 · about 35 min from Home · estimate, offline` |

Then the provider recovers (`ok`) and the queue drains: the next pass
**replaces** all three `leave.` requests with the ordinary table's N1 rows
(same identifiers, new content hash) and adds nothing else.

Variant `travelNoAddress` — `leave.{EPC-ILV}` fires Thu 12:00, `EPC-ILV
starts at 13:00` / `LAB_F5.12 · Travel time from Home unavailable: Home has
no address. Check your route before you leave.`; `leave.{Dinner}` 17:30 the
same with `Home · Travel time from FH Technikum Wien unavailable: Home has no
address. …`; `leave.{SWRM-ILV}` Fri 15:00 likewise; `start.{REQEN-EXAM}`
unchanged. No request is sent to the provider for any of them.

**Departure refresh** (variant `travel`, clock Thu 11:30, the T−45 refresh of
`EPC-ILV`; `-KadenceLocation notAsked`): the mock answers 50 min instead of
35 → `departAt` 12:00, `leave.{EPC-ILV}` replaced to fire 11:55 with `Leave by
12:00 for EPC-ILV` / `… · 50 min from Home`. Same refresh answering 78 min →
`departAt` 11:32, new `F` 11:27 has passed, `departAt` has not → delivered
**at once** (§27.6). Answering 30 → fire 12:15, `Leave by 12:20`. The refresh
asks for location authorization exactly once (`notDetermined`, never asked)
and uses the rule origin.

**From where you are** (clock Thu 11:30, `-KadenceLocation allowed`, fix
`cafe`): the T−45 refresh asks the mock from `cafe` → 28 min → `departAt`
12:22, `leave.{EPC-ILV}` `Leave by 12:22 for EPC-ILV` / `Starts 13:00 ·
LAB_F5.12 · 28 min from where you are`; the leg has `originKind
currentLocation`, `originPlaceID` nil; the cache has no new row; the log has
`eta ok · 28 min · transit · refresh · here` and no coordinate. With the fix
at Home's coordinate + 100 m → `location not used · within 300 m`, the rule
origin, `from Home`.

**Sync paused** (N8; `travel` dataset, the source's next background sync
answered `unauthorized`, then in a second case `forbidden`; Kadence not
frontmost):

| Identifier | Title | Body | Category |
|---|---|---|---|
| `sync.{source}` | `University timetable isn't syncing` | `cis.technikum-wien.at didn't accept the password for user01. Sync is paused until you update it in Kadence.` | `kadence.source` |
| `sync.{source}` | `University timetable isn't syncing` | `cis.technikum-wien.at refused access for user01. Sync is paused until you check the account in Kadence.` | `kadence.source` |

Delivered with a 1-second trigger (or at 07:00 when the sync ran at 03:00,
inside Sleep); a second paused sync adds nothing; `Sync Now` that succeeds
removes it, pending and delivered; the same `unauthorized` reached by `Sync
Now` while Kadence is frontmost sends nothing; `Sync problems` off sends
nothing.

**Catch-up** (a launch pass, no records): at Thu 12:12 → `leave.{EPC-ILV}`
delivered at once with N1; at Thu 12:20 → delivered at once with N3, `Leave
now for EPC-ILV` / `Starts 13:00 · LAB_F5.12 · Leave-by was 12:15`; at Thu
13:05 → nothing. The same clocks in an **ordinary** pass → nothing.

**Actions** (simulated responses):

- `Done` on `start.{REQEN-EXAM}` → `REQEN-EXAM` `.done`, one `Mark Done` undo
  step; the next pass removes nothing else and does not re-plan it.
- `Snooze` on `leave.{Dinner}` at Thu 17:41 → `Dinner with flatmates`
  18:45–20:15, one `Snooze` step; N5 `Dinner with flatmates moved to 18:45` /
  `Snoozed from 18:30 · ⌘Z in Kadence undoes it` at once; after the
  recompute, `leave.{Dinner}` is replaced: fire 17:55, `Leave by 18:00 for
  Dinner with flatmates`.
- `Snooze` on `start.{Late call}` at Sat 23:01 → refused (23:30–00:00 is
  inside Sleep): nothing written, no undo step, N6 `Late call not moved` /
  `23:30 is inside Sleep (protected)`.
- `Snooze` is not an action of `kadence.readOnly` (asserted on the
  registered categories).
- `Open` on any → the open-request records the event id; on an unknown id →
  today, nothing selected.

**Sync** — `reportChanged` (§22.1) applied to the `travel` dataset at
**Mon 12 Oct 06:00** (so every changed lecture is ahead of the clock; T1 is
not touched by it):

| Change upstream | Expected for legs |
|---|---|
| `SWQM-ILV` Mon, lecturer `L01` → `L09` (in place) | same `Event.id`; leg row unchanged, `computedAt` unchanged |
| `SWEN3-LAB` Tue, room → `EDV_F4.26` (delete + add) | the old event's leg deleted with it; the new event's leg: depart 09:15, **from the cache — no provider call** (same key); `SWEN3-ILV` still chained (no leg) |
| `EPC-ILV` Thu vanishes | its leg deleted; **`REQEN-EXAM` loses its chain**: origin home, new leg depart **15:15**, and its `start.` notification becomes `leave.` |
| `SWRM-ILV` Fri loses co-teacher `L06` (in place) | leg unchanged |
| new `KOKU-UE` `M + 9` 10:00 `UEB_B2.02` | new leg, depart 09:15 (weekday slot 09:30 already cached by `SWEN3-LAB`: no provider call) |

**Legs and `Event`**: after any recompute, every event's §20.8.4 hash and the
source's `feedHash` are byte-equal to before.

#### Other datasets

`TravelFixture` is retired, so the `phase2` and `phase3` datasets get real
legs that reproduce §12 items 7–8:

- places `Home`, `FH Technikum Wien`, and a user place `Café Sperl`, all
  `confirmed` with mock coordinates (Home and campus as dataset `travel`;
  `Café Sperl` 48.2000, 16.3640);
- preferred mode `transit`; overrides `Home ↔ FH Technikum Wien`,
  `FH Technikum Wien ↔ Café Sperl` and `Home ↔ Café Sperl`, all `walking`;
  the mock answers 22 min for home ↔ campus walking and 6 min for every Café
  trip walking, both directions; buffer **0**;
- `Coffee with Nora` (manual, 11:00) has `placeID` = `Café Sperl`.

`Datenmodellierung` (imported, `FH B.2.09`, 09:00) → campus, origin home →
`Leave 08:38 · 22min`, as before. `Coffee with Nora` → origin campus (it
follows `Datenmodellierung`, 30 min earlier; `Statistik übung` has no room and
is transparent) → 6 min → `Leave 10:54 · 6min`, as before. Both Café routes
trips are 6, so the result would not change if a fixture ever gave it another
predecessor. In `phase3`, week `M`'s lectures gain
22-minute bands from home where nothing placed precedes them; conflicts and
the counts 14 / 15 are unchanged (a leg is never a conflict, §24.8).

`empty` and `fresh`: built-in places — Home with no address, the campus
with its built-in address, looked up by the mock geocoder at launch and
`confirmed` (§23.6) — preferred mode `transit`, no overrides, buffer 10,
`useCurrentLocation` on, the five default rules: what a real store holds.

#### The test day for the planners

Unit tests construct the `travel` dataset's events directly (no review
launch), with `M` = 2026-10-12, zone Europe/Vienna, the mock provider,
geocoder, location source and path monitor, the recording centre, an
injected queue scheduler and an injected clock. They pin §24.4's table, the
notification tables above and these cases on top:

- **Overlap**: a manual event at Home 12:00–12:30 while `EPC-ILV` runs
  11:00–13:00 (moved for the test) → origin campus, depart 11:15, before
  `P.end`; the leave-by is not clamped.
- **Chain through a placeless event**: `Coffee` (no place) 14:40–15:00 between
  `EPC-ILV` and `REQEN-EXAM` → still no leg for `REQEN-EXAM`.
- **Exactly `chainGap`** (120 min) → chained; 121 → home.
- **Skipped previous**: `EPC-ILV` skipped → `REQEN-EXAM`'s origin is home →
  leg depart 15:15; `EPC-ILV` gets no leg and no notification.
- **Two protected spans back to back** (22:00–07:00 and 07:00–07:30) → a
  notification due 06:50 is held to 07:30.
- **Leave by off** → `EPC-ILV` gets `start.` at 12:30 under `timetableStart`.
- **All rules off** → nothing planned, and no authorization request.
- **First pass with something to plan, `notDetermined`, never asked** →
  exactly one `requestAuthorization`; a second pass → none.

*Routing cases (routing amendment):*

- **Cache sharing**: the 14 timetable events of dataset `travel` at Mon
  06:00 with an empty cache → exactly one provider call per distinct key
  (`home → campus` transit at each distinct weekday slot, `campus → home`
  for `Dinner`, `home → Gym` walking) — never one per event; a second
  recompute → zero calls.
- **Directional**: `campus → home` and `home → campus` are two keys; an
  answer for one never fills the other.
- **New address**: confirming a new Home coordinate invalidates every key
  with the old one (new calls), and deletes the old rows.
- **Freshness**: an entry 14 days old is used without a call; 14 days + 1 s
  → a call; a failure then → `estimate` from that entry; 28 days + 1 s →
  deleted at launch.
- **Fallback order** (§24.10): own last time → exact key → nearest slot
  same day type → any day type → `unavailable`; `noRoute` and
  `needsAddress` never fall back.
- **Mode mismatch**: the mock answers `walking` to a `transit` request →
  `noRoute`.
- **Queue**: one in flight; ≥ 2 s apart; the 21st request in 10 minutes
  waits; a `throttled` answer pauses 10 min, then 20, 40, 60, 60, reset by a
  success, with `retryAt` on every waiting leg; priority order 0 → 4; a
  duplicate key is queued once; `offline` pauses until the path monitor
  reports satisfied.
- **Refresh schedule**: a leg with `departAt` 12:15 today has refreshes at
  09:15 and 11:30; moving the event re-plans them; a refresh slot missed
  while asleep runs once at wake if the event has not started, and never
  after its start.
- **Ready vs estimate in a window**: at 11:31 with the 11:30 refresh failed
  `offline` → `estimate` (reason `offline`); with it succeeded → `ready`,
  `refreshedAt` 11:30.
- **Location** (§24.2.1): used only for the next departure inside its 45
  minutes; never at T−3 h; a fix 3 min old, or 250 m accuracy, is not used;
  `denied` → rule origin and no further request; `useCurrentLocation` off →
  no location call at all; the coordinate appears in no stored row and no
  log line.
- **Campus lookup** (§23.6): first recompute needing the campus → one lookup;
  a matching first result → `confirmed` without asking; a non-matching one →
  `unconfirmed`, legs `unavailable · needsAddress (FH Technikum Wien)`; a
  failure → retried at the next launch, not within the same day.
- **Logging**: every routing log line produced by the cases above matches
  §24.11's forms; none contains a digit pattern of a coordinate
  (`\d+\.\d{3,}`), a fixture address, a place name or an event title.
