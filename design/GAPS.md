# Design gaps

Questions from the coding agent for the design agent / Parsa.
Append-only. Each entry: date, where the gap bit, what is needed to close it.

---

## 2026-09-09 — G-001 — the entire design spec is missing (BLOCKER)

**Where:** all of `design/`.

Every file in `design/` is 0 bytes:

| file | size |
|---|---|
| `design/tokens.json` | 0 |
| `design/components.md` | 0 |
| `design/layouts.md` | 0 |
| `design/interactions.md` | 0 |
| `design/GAPS.md` | 0 (before this entry) |

`BRIEF-DESIGN.md` lists six deliverables; none of them exist yet. There are no
commits in the repo, so nothing was lost — the design pass has not run.

**Consequence:** the `// SPEC-GAP` placeholder mechanism in `CONTEXT.md` is for
*individual* unspecified values. Here nothing at all is specified, so proceeding
under it would mean inventing the whole design system inside the Swift target —
exactly what `CONTEXT.md` forbids ("Coding agent … Cannot invent UI values").
No token names, colours, spacing, type, radii or elevation values have been
written into the codebase.

**To close:** run the design pass and land `design/tokens.json` (deliverable 1 of
`BRIEF-DESIGN.md`), then `components.md`, `layouts.md` and `interactions.md`.

---

## 2026-09-09 — G-002 — tokens.json shape not specified

**Where:** `Scripts/generate-tokens.swift` → `Kadence/DesignSystem/Tokens.swift`.

`CONTEXT.md` fixes the *pipeline* (tokens.json is the source, Tokens.swift is
generated, never hand-edited) but nothing fixes the *shape* of tokens.json, and
`BRIEF-DESIGN.md` only says tokens must be "named so they map directly to Swift
constants".

Rather than invent a token vocabulary, the generator was written to mirror
whatever structure the JSON has. It hardcodes no token names and no values. The
only contract it imposes is how JSON shapes map to Swift types:

| JSON at a leaf | becomes |
|---|---|
| `"#RGB"` / `"#RGBA"` / `"#RRGGBB"` / `"#RRGGBBAA"` | `SwiftUI.Color` (fixed) |
| `{"light": "#…", "dark": "#…"}` | `SwiftUI.Color` (appearance-adaptive, AppKit dynamic colour) |
| a number | `CoreGraphics.CGFloat` |
| a string | `Swift.String` |
| a boolean | `Swift.Bool` |
| an array of numbers / strings | `[CGFloat]` / `[String]` |
| any other object | a nested `enum` namespace |
| any key starting with `$` | metadata, skipped (`$schema`, `$note`, …) |

Naming: `kebab-case`, `snake_case` and `dotted.keys` all fold to camelCase.
Nested objects become `UpperCamel` enums, leaves become `lowerCamel` constants.
Keys starting with a digit get a `_` prefix. Swift keywords get backticked.
Keys that would collide after mapping are a hard error, not a silent overwrite.

So `{"color": {"surface": {"canvas": {"light": "#FFF", "dark": "#1E1E1E"}}}}`
generates `Tokens.Color.Surface.canvas`.

**Open questions for the design side:**

1. Is this mapping acceptable, or should tokens.json follow a published format
   (e.g. W3C Design Tokens, with `$value` / `$type` on every leaf)? If the
   latter, say so before writing tokens.json — the generator changes, not the JSON.
2. Type tokens: should a font be one leaf the generator turns into a `Font`
   (family + size + weight + tracking as one object), or separate primitives the
   Swift side composes? Right now a font object becomes a namespace of primitives.
3. Elevation / shadow: same question — one composite token or primitives?
4. Semantic colour tokens presumably need a light and a dark value each. Are
   there any that are deliberately appearance-independent?
5. `BRIEF-DESIGN.md` requires WCAG AA for text on block fills and "colour is
   never the only carrier of meaning". Should contrast ratios be asserted in the
   generator (fail the build when a documented text/background pair drops below
   4.5:1), or is that checked on the design side only? Closing this needs the
   token set to declare which pairs are text-on-fill pairs.

---

## 2026-09-09 — G-002 — ANSWERED (design side)

**Ruling: the mapping documented in G-002 is accepted as written.** No changes to
`Scripts/generate-tokens.swift` are needed on account of it. `design/tokens.json`
was shaped to fit that contract rather than the other way round.

Two things were changed on the design side to conform, both because the original
draft would have produced leaves the documented mapping does not cover:

1. **No `{"system": …}` or `{"material": …}` colour leaves.** Platform colours and
   materials are now expressed as *two* sibling keys: a literal
   `{"light","dark"}` pair, plus a `String` naming the platform value to prefer
   at runtime. So `color.interactive.accent` (pair) sits beside
   `color.interactive.accentSystemName` = `"controlAccentColor"`, and
   `color.surface.sidebar` (pair) beside `color.surface.sidebarMaterial` =
   `"sidebar"`. Runtime rule: prefer the named platform value; the literal pair
   is the fallback, and is what Reduce Transparency and the contrast checks use.
2. **`elevation` is flattened.** It was an array of shadow objects, which the
   documented mapping does not handle. Each level is now
   `{ hasShadow, y, blur, color }`. No leaf anywhere in the file is an array of
   objects.

### Answers

**Q1 — is the mapping acceptable, or should we adopt W3C Design Tokens?**
Acceptable. Do **not** adopt W3C Design Tokens. `$value`/`$type` on every leaf
would triple the file's size and add a schema whose only consumer is one
generator we control. The current shape is already unambiguous because the
generator infers from JSON shape, and `$`-prefixed metadata gives us an escape
hatch we are already using. Revisit only if a second consumer appears.

**Q2 — type tokens: one composite `Font` leaf, or primitives?**
Primitives, as the generator already does. `typography.blockTitle` is a namespace
of `size` / `weight` / `textStyle` / `lineLimit` and, where present,
`monospacedDigit` / `textCase` / `tracking`. The Swift side composes them.
Reason: `size` is the point size **at the default Dynamic Type setting**, and the
font must be resolved through `textStyle` so it scales. A pre-baked `Font` would
hardcode the default size and silently break Dynamic Type, which
`BRIEF-DESIGN.md` requires.

**Q3 — elevation: composite or primitives?**
Primitives, per change (2) above. `hasShadow == false` means draw nothing; do not
draw a zero-radius shadow.

**Q4 — are any semantic colours deliberately appearance-independent?**
No. Every colour in the file has both a `light` and a `dark` value, with no
exceptions. Where a value happens to be identical in both appearances it is still
written out twice, so the generator never has to special-case a single-value
colour and no colour can accidentally inherit the wrong appearance.

**Q5 — should the generator assert contrast ratios?**
Yes. `tokens.json` now declares `$meta.contrastPairs.pairs`: 48 entries of
`{ fg, bg, min }`, where `fg` and `bg` are dotted token paths into the same file
and `min` is the required WCAG 2.1 ratio. It is `$`-prefixed, so codegen skips it;
it exists for the checker. This closes the "needs the token set to declare which
pairs are text-on-fill pairs" part of the question — the declaration now exists.

Implementation is deferred and tracked as G-003 below.

---

## 2026-09-09 — G-003 — contrast checker in the generator (DEFERRED, not blocking)

**Status: deferred. Do not build this before Phase 1 ships.**

All 48 declared pairs were verified numerically on the design side before
`tokens.json` landed, in both appearances. Worst measured ratio is 4.87:1 against
a 4.5 minimum. The values in the file are correct **today**; the checker's job is
to stop a future edit from quietly breaking them. That is a regression guard, not
a Phase 1 blocker, and Phase 1 has enough in it already.

When it is built, the contract is:

- Read `$meta.contrastPairs.pairs` from `tokens.json`. Do not hardcode any pair.
- For each entry, resolve `fg` and `bg` as dotted paths into the same file. Both
  must resolve to an appearance pair; a path that does not is a hard error naming
  the path, not a skip.
- Evaluate **both** appearances. A pair passing in light and failing in dark is a
  failure.
- Ratio is WCAG 2.1 relative luminance over 8-bit sRGB. If a resolved colour
  carries an alpha component (`#RRGGBBAA`), composite it over
  `color.surface.canvas` for that appearance before measuring. No pair currently
  declared uses alpha, but `color.interactive.hoverOverlay` and
  `.pressedOverlay` do, so the case has to be handled rather than assumed away.
- Run in both `generate` and `--check` modes. Failure exits non-zero and names
  the pair, the appearance, the measured ratio and the required minimum.
- Rounding: compare the unrounded ratio. Do not round to two decimals first —
  4.499 must fail.

**To close:** implement the above, and confirm it passes against the current
`tokens.json` unchanged (it should, with zero failures).

---

## 2026-09-09 — G-002 CLOSED

`tokens.json` v1.0.0 adopts the mapping in `$meta.swiftMapping` / `$meta.valueForms`,
and `$meta.contrastPairs` answers Q5 with machine-readable pairs. `Tokens.swift`
generates cleanly: 259 constants, every one cross-checked against the JSON, and
it compiles into the app target.

Q5 follow-up still open: the generator does **not** yet assert
`$meta.contrastPairs`. Should `swift Scripts/generate-tokens.swift --check` fail
the build when a declared pair drops below its `min` ratio? The data is now there
to do it; say the word and it is a small addition.

---

## 2026-09-09 — G-003 — `resolveBlockStyle` cannot be contrast-agnostic

**Where:** `Kadence/DesignSystem/BlockStyleResolver.swift`.

components.md §2 says appearance, Increase Contrast and Reduce Transparency are
"resolved by the token layer below it, not by this function". That holds for
colour, but §11 also changes things no colour token can carry:

- border **width** steps from `size.borderRegular` to `size.borderEmphasis`
- the routine border **drops its opacity** rather than changing hue
- the `.plannedTimed` **dash pattern** tightens from `[4, 3]` to `[3, 2]`

**Resolved as:** an `increaseContrast: Bool = false` parameter, defaulted so §2's
documented signature still calls. Confirm or replace.

---

## 2026-09-09 — G-004 — the sidebar source symbols are not specified

**Where:** components.md §10.1, `Kadence/DesignSystem/SourceColor.swift`.

§10.1 requires "the source's own SF Symbol … the symbol is what makes the sidebar
legend work without colour" — load-bearing for the no-colour-only-meaning rule —
but no symbol is given for any of the eight palette slots, and
`color.sourcePalette` carries names and rules only.

**This is the one place I picked a design value.** Placeholders are in
`SourceKey.swatchSymbol`, marked `// SPEC-GAP`, currently: blue
`building.columns`, teal `graduationcap`, green `repeat`, amber `envelope`,
orange `flag`, pink `person.2`, purple `pencil.and.outline`, graphite `calendar`.
They are keyed to what each mock source *is*, which is wrong in principle: a
palette slot is assigned in order as sources are added, so the symbol belongs to
the **source**, not to the hue. Please specify how a source gets its symbol.

---

## 2026-09-09 — G-005 — a manual all-day event is not one of the six variants

**Where:** components.md §5, interactions.md §3.

The all-day geometry covers deadlines and exams only, both of which are Phase 3
work items. `Event.isAllDay` exists in the Phase 1 model (BRIEF-PRODUCT.md), but
every creation path in interactions.md §3 makes a 60-minute *timed* event, so
there is no way to make an all-day event in Phase 1 and no spec for how one would
look. Nothing was invented: Phase 1 simply cannot produce one. Confirm that is
intended, or specify a seventh variant.

---

## 2026-09-09 — G-006 — `size.blockCascadeIndentMin` never binds

**Where:** layouts.md §3.3, `tokens.json → size`.

`indent = clamp(round(columnWidth × 0.19), 12, 22)`. At the narrowest possible
column, `size.dayColumnMin` (78), that is `round(14.82) = 15` — above the floor of
12. The floor is therefore unreachable at every real column width, and §3.3's own
figure ("15pt at the 78pt minimum") agrees. Either the floor is dead and can go,
or it is guarding a narrower column than `size.dayColumnMin` allows. A test
asserts the current behaviour so this cannot drift silently.

---

## 2026-09-09 — G-007 — cross-reference typo

components.md §3.3 ends "they enter cascade layout (see `layouts.md` §4.3)".
Cascade is layouts.md **§3.3**; §4 is Day view and has no §4.3.

---

## 2026-09-09 — G-008 — numeric tokens that are counts arrive as CGFloat

**Where:** `$meta.swiftMapping.numericLeafType`, all call sites.

The contract maps every JSON number to `CGFloat`, which is right for dimensions
but not for the tokens that are counts: `size.allDayMaxRows`,
`size.blockCascadeMaxSteps`, `size.blockCascadeMaxVisible`,
`size.monthCellMaxVisibleRows`, and every `typography.*.lineLimit`. Each needs an
`Int(...)` at the call site, and `lineLimit: 0` has to be read as "no limit".
It works, but the casts are noise and a fractional value would silently truncate.

Options: (a) leave it; (b) add an integer form to the contract — a `$type` hint,
or a naming convention the generator recognises — so counts emit as `Int`.
Generator change, not a token change.

---

## 2026-09-09 — screenshot review, deviations and rulings (design side)

Reviewed `screenshots/Screenshot 2026-09-09 at 17.06.20.png` — Week, dark
appearance, 1880pt window, 184pt columns. Measured in pixels rather than judged
by eye, which mattered: two things that looked wrong were correct.

**Verified correct, measured:** hour height 44pt exactly; cascade indent 22pt at
a 184pt column, with blocks 4 and 5 correctly sharing the 66pt inset per
`size.blockCascadeMaxSteps`; the topmost cascaded block 114pt wide, which is
`184 − 3×22 − 2×spacing.xxs` to the pixel; `radius.block` ≈ 4–5pt (it upscales
to look rounder than it is — it is right); no shadow on any resting block, in or
out of a cascade; the `+1` chip correct for a six-block fixture; protected window
fill present; low-energy hatch present and spanning the gutter; done, skipped and
conflicted states all rendering; the density ladder picking the right tier at
every size including the two clamped fixtures. `DayLayoutEngine` is a faithful
implementation of layouts.md §3.3.

### Deviations from the spec (implementation side)

| # | What | Spec | Evidence |
|---|---|---|---|
| D-1 | The range title renders **twice** — once in the leading toolbar group after **Today**, once centred | layouts.md §1.2: once, `.principal` | both read `7 – 13 Sep 2026` |
| D-2 | The now line is **not drawn in the day column**. Only the red gutter time and the leading dot appear | components.md §8: a `size.nowLineThickness` line across the current day's column, **above every block** | zero red pixels across x 715–905 at y 888–905; the line is behind the 17:00 `Training` block |
| D-3 | The protected window fill **does not span the time gutter**; low-energy's hatch does | components.md §7: full column width **including the gutter**, "so their edges stay visible when the column is full of blocks" | gutter at x=330 is `(26,26,28)` (canvas) at y=400/455/462 while the column at x=600 is `(32,33,35)` (protected fill) |
| D-4 | The `+N` chip is drawn **inside the cluster's z-order** and is partly occluded by the first block | now explicit in layouts.md §3.3: above every block in the cluster | chip clipped by the blue block at the cluster's top-trailing corner |
| D-5 | No conflict badge on `Training` | components.md §6, conflicted | border correct, `exclamationmark.triangle.fill` absent. See R-4 — the spec did not resolve badge-vs-time, so fix this **after** reading the new rule |
| D-6 | The source name is missing from the meta line: `Datenmodellierung` shows `09:00-10:30` + `FH B.2.09` | components.md §3.4: at tier ≥ 44 the meta line is `Source · Location` | §3.4 landed after this build — a to-do, not a miss |
| D-7 | The exam all-day fixture is absent; only the deadline pill is in the all-day row | components.md §12 fixture 10 (`.examAllDay`, `T−6d`, teal) | one pill on Wed |

D-1 through D-4 are straightforward. None of them is a design question.

### Spec defects the screenshot exposed (design side — already fixed)

- **R-1 — travel band destroyed the block above it.** `Leave 08:38 · 22min`
  covered the meta line of the routine block above it. The spec said the band
  grows upward and draws above other blocks, so the implementation was right and
  the spec was wrong. components.md §4 now splits the two cases: a band shorter
  than `size.travelBandHeight` becomes a strip **inside the top of its own
  event**, and never draws outside its own bounds.
- **R-2 — window labels collided with hour labels.** Two instances, one cause:
  the label was specified into the time gutter. components.md §7 now puts window
  labels in the leading day column, bans anything but hour labels and the now
  time from the gutter, and specifies the pinned + `chevron.up` form for a window
  whose top edge is scrolled off — a 22:00–07:00 protected window was otherwise
  unlabelled all morning.
- **R-3 — cascade threshold.** See the ruling below.
- **R-4 — the conflict badge and the trailing-aligned time collide** at tiers
  16–43; both want the trailing-top corner. components.md §6 now rules: the badge
  wins, the time is dropped. Time is recoverable from hover help and the
  inspector; a conflict is not recoverable from anywhere else on the grid.
- **R-5 — "every covered block keeps a rail and a glyph" was false.**
  `.fixedTimed` has no rail by design. layouts.md §3.3 corrected.

### THE CASCADE RULING

**`size.dayColumnCascadeThreshold`: 96 → 72.**

The screenshot is the argument. At a 1880pt window with 184pt Week columns — a
wide window, not a cramped one — a *two*-block overlap still cascaded, because a
2-up slot is 88pt and the threshold was 96. The 11:00 pair rendered as one full
block plus a 22pt sliver reading `10:`, and the 18:00 trio hid the first block's
title completely. Column packing never fired in Week at any window size a person
would actually use: 2-up needed a 200pt column, i.e. a ~2000pt window.

96 was the answer to "how wide is a comfortable block". The question the
threshold actually decides is "how wide is a block that still beats being
hidden". 72 answers that one, and is derived rather than picked: 28pt of fixed
chrome (`blockRailWidth` + `blockPadding` + `blockGlyphSize` + `blockGlyphGap` +
`blockPadding`) plus 44pt of title, about seven characters at
`blockTitleCompact` — enough to tell *Coffee* from *Code review*.

Consequences, now written into layouts.md §3.3 as a table so nobody has to
re-derive them: at a 184pt column, 2 concurrent blocks **pack** at 88pt and 3
concurrent **cascade** at 58pt; at a 114pt column everything cascades; at the
78pt minimum everything cascades. Week packs the common case and cascades the
pile-up. Day packs almost everything.

Two riders, both in layouts.md §3.3:

1. **A covered block shows no text.** Visible width below
   `size.blockCascadeMinReadableWidth` (new, 44) forces the 11–15 content set —
   glyph only — whatever the height tier says. This is what kills the `10:`
   slivers. `resolveBlockStyle` gains visible width alongside rendered height.
2. **Cascaded blocks stay at `elevation.level0`.** The build already does this
   and is right to; it is now written down, so nobody "fixes" cascade later by
   adding a shadow and makes it the only resting block in the app that casts one.

### Rulings on the open gaps

**G-004 — sidebar source symbols. Closed.** Your instinct is right: the symbol
belongs to the **source**, not to the hue, so it cannot live on `SourceKey`.
Move it to `CalendarSource` as a `symbol` field, defaulted from what kind of
source it is and overridable by the user in Settings later:

| Source kind | Symbol |
|---|---|
| university timetable / lectures | `building.columns` |
| coursework, LMS, assignments | `list.bullet.rectangle` |
| exams | `graduationcap` |
| mail-derived appointments | `envelope` |
| daily routine | `repeat` |
| planned study | `pencil.and.outline` |
| social | `person.2` |
| personal / manual (default) | `calendar` |
| anything else | `circle.fill` |

The palette slot stays assignment-ordered and entirely independent of this. Two
sources may share a symbol; they will not share a hue. Drop the `// SPEC-GAP`.

**G-005 — manual all-day events. Closed: build it, no seventh variant.**
`Event.isAllDay` exists in Phase 1, so Phase 1 should be able to produce one. It
is the existing all-day geometry carrying the existing fixed style — solid fill,
`calendar` glyph, `graphite` — which is consistent with the fill-weight ladder
(solid = fixed = a thing the user placed deliberately). Call the kind
`.fixedAllDay`. Creation path: double-click the all-day row, or `⌥⌘N`. I will add
both to interactions.md §3 on the next pass.

**G-006 — dead indent floor. Closed: the floor is dead, remove it.**
`size.blockCascadeIndentMin` is gone from tokens.json and the formula in
layouts.md §3.3 is now `min(round(columnWidth × ratio), max)`. `dayColumnMin`
already guarantees ≥ 15. Good catch, and keep the test.

**G-008 — counts arriving as CGFloat. Closed: option (b), explicit list.**
`$meta.swiftMapping.integerLeaves` now names the five paths that must emit as
`Int`: `size.allDayMaxRows`, `size.blockCascadeMaxSteps`,
`size.blockCascadeMaxVisible`, `size.monthCellMaxVisibleRows`, and
`typography.*.lineLimit` (`*` matches one segment). An explicit list rather than
name-matching, so the generator never has to guess from a suffix. `lineLimit: 0`
means no limit. Generator change, no token change beyond the metadata.

**G-007 — closed**, the typo was fixed before this review.

---

## 2026-09-09 — G-009 — layouts.md §3.3 gives two cascade figures that conflict

**Where:** layouts.md §3.3 step 3, and `Kadence/Layout/DayLayoutEngine.swift`.

The indent bullet: `indent = clamp(round(columnWidth × 0.19), 12, 22)`, and
"15pt at the 78pt minimum" — `round(78 × 0.19) = 15`. Correct.

The narrowest-block bullet: "The narrowest possible block is
`columnWidth − 3 × indent`, which is 48pt at a typical Week column and **42pt at
the absolute minimum**." At 114pt, `114 − 3 × 22 = 48`. ✓ At 78pt,
`78 − 3 × 15 = 33`, not 42. To get 42 the indent must be **12** — the floor.

So the two bullets disagree about the indent at the minimum column width, and
this is the same underlying question as G-006 (the floor is otherwise dead).

**Code follows the indent formula**, so 78pt gives 33pt. Two tests pin the 114pt
figures (`narrowestMatchesSpec`, `spansToTrailingEdge`) so this cannot drift
silently once you rule.

Which is intended — is the floor 15 (drop `blockCascadeIndentMin`), or is the
ratio meant to yield 12 at the minimum column (change the ratio or the clamp)?

---

## 2026-09-09 — G-004 — CLOSED

Specified in components.md §10.1, which now carries a normative symbol table for
all nine source kinds plus the unknown-kind fallback, the rule that the symbol
lives on `CalendarSource` and defaults by kind, and the constraint that keeps the
source vocabulary separate from the block-kind vocabulary.

**This supersedes the G-004 ruling in the 2026-09-09 screenshot-review entry
above. That table was wrong and should not be implemented.** It reused
`building.columns`, `repeat`, `pencil.and.outline`, `graduationcap` and
`calendar` — the block *kind* glyphs from §2.1 and §3.2 — as *source* symbols.
Parsa caught it. The failure is that the two vocabularies co-occur, most directly
in the inspector title row where the kind glyph and the source swatch sit side by
side (`layouts.md` §6), and several source kinds share a name with a block kind
(routine, exams, planned study, travel). Had it shipped, `repeat` would have
appeared as both "this is a routine block" and "this came from the Daily routine
source" in the same window, which teaches the user that a block's glyph means its
source. It does not, and the whole §1 channel separation depends on it not
appearing to.

The replacement vocabulary is drawn from a different domain: kind glyphs depict
the activity, source symbols depict the origin — the container, feed or party the
data arrived from. No symbol appears in both tables, and §10.1 states that as a
rule for anything added later.

**Action:** replace `SourceKey.swatchSymbol` entirely. The symbol does not belong
on `SourceKey` at all — move it to `CalendarSource` as a `symbol` field defaulted
from the source's kind per the §10.1 table, and drop the `// SPEC-GAP` marker.

---

## 2026-09-10 — Phase 2 design pass landed

Additions only. Verified: no Phase 1 design value changed, no token removed. The
only `$meta` edits are the two the contracts require — `integerLeaves` gains
`size.popoverMaxRestRows` (G-008), and `contrastPairs` gains the one new colour
pair (G-003). 49 declared pairs pass in both appearances.

**New spec:** components.md §13 Routines window, §14 Conflict resolution, §15
Menu bar extra, §16 Snooze confirmation, §17 Phase 2 fixtures · layouts.md §8–§10
· interactions.md §10–§12 · 67 new tokens.

**Three amendments, all marked in place:**

- **components.md §7 — the time gutter.** Now carries hour labels, the now time
  **and the keyboard time cursor's time**. The original rule named only the first
  two and contradicted interactions.md §1; §1 wins, per the 2026-09-10 ruling.
  Window labels stay banned from the gutter — that is what the rule was for.
- **interactions.md §1 — the toolbar is not a focus stop.** Dropped from the `⇥`
  cycle, which also fixes the original list saying "four regions" over five
  items. Full Keyboard Access is the route to window chrome, and every toolbar
  action has a key equivalent and a menu item.
- **components.md §10.2 — the needs-attention row takes no icon.** Closes the
  `tray.full` / `tray.2.fill` collision: the build's needs-attention icon sat a
  few rows above the Coursework source swatch in the same list at the same size.
  §10.2 now also states the rule for any future chrome symbol — check §10.1 and
  the kind glyphs in §2.1/§3.2/§5 first.

**Two open conditions from the 2026-09-10 rulings, now specified:**

1. *Previewed blocks must never look committed.* components.md §6 adds a
   `previewed` presentation that reuses the drop-preview vocabulary from
   interactions.md §4 — proposed frame at `opacity.blockPreviewed` inside a
   dashed accent outline, **with the current frame retained as a ghost**. A
   committed block is never in two places at once, so the combination is
   unmistakable, and it costs no new channel. The canvas also takes a
   `size.previewCanvasBorder` accent border while any preview is live
   (components.md §14.4), which is what stops a hypothetical day being read as
   the real one at a glance.
2. *Re-sync must be one undo step.* interactions.md §11.2: one named
   `Undo Re-sync Routine`, restoring every affected instance in a single `⌘Z`,
   plus a confirmation that lists the affected dates rather than only counting
   them. A re-sync that undid one day per press would be worse than no undo,
   because the user stops pressing before they are whole.

**One conflict this pass had to resolve.** §7 said peak-focus windows get no
treatment — correct for the calendar canvas, impossible for an editor, since a
window you cannot see is a window you cannot edit. Resolved by scope rather than
by weakening the rule: peak-focus is drawn **only** inside the Routines window's
windows mode, as a dashed outline in the new `color.window.peakFocusEdge`
(3.2:1 against canvas in both appearances — it is a hit target, so it meets the
3:1 non-text minimum). The calendar canvas rule is unchanged.

**Notes for the build.** Two things in this pass are deliberately reuse, not new
components, and building them fresh would recreate the second-vocabulary problem
§1 exists to prevent: the Routines window **is** the Week canvas with dates, the
now line, the all-day row and travel bands removed (components.md §13.1 lists
every difference), and conflict preview **is** the drag-drop drop-preview
vocabulary. Neither needs a new renderer.

---

## 2026-09-11 — G-010 — §6 does not say which block a click selects when two overlap

**Where it bit:** task P2-T02, fixing click-to-select in
`Kadence/Views/Canvas/DayColumnView.swift`. Found while verifying the fix by
driving real clicks at the running app.

**What happened.** With click-to-select working again, a click at the visual
centre of "Statistik übung" (10:45–11:45) selected **"Coffee with Nora"**
(11:00–11:45) instead. Both are real blocks, both are drawn, and the click point
is genuinely inside both rectangles — Coffee with Nora is simply on top there.
Nothing is malfunctioning; the spec just does not say what should happen.

**What interactions.md §6 says.** "Clicking a block selects it; clicking empty
grid deselects and places the time cursor at the clicked slot. Clicking a travel
band selects its parent event." That is complete for a click that lands on
exactly one block. It says nothing about a click that lands on two.

**What is needed to close it.** A rule for which block wins when the click point
is inside more than one block's hit region. The obvious candidate is "the
frontmost block wins" — i.e. selection follows the same z-order that
`layouts.md` §3.3 already assigns to a cascade, so what you click is what you
can see. That is what the build does today, because it falls out of SwiftUI's
hit-testing order rather than out of a decision. It should be stated, because
two neighbouring questions have no default answer at all:

1. In a cascade, later blocks are drawn on top and cover most of the ones behind
   them. If frontmost always wins, a block whose only visible sliver is its
   leading edge can only ever be selected by clicking that sliver. Is the
   sliver the hit target, or does a cascaded block get a hit region matching
   what is *visible* of it rather than its full frame?
2. Clamped blocks get `size.blockHitExtension` of extra hit area
   (`layouts.md` §3.3), which can push a short block's hit region *underneath* a
   neighbour it does not visually overlap. Does the extension lose to a real
   block's frame, or can it win?

**Not blocking.** The click-to-select fix does not depend on this, and the build
keeps the current frontmost-wins behaviour. `Scripts/check-block-click-selects.sh`
deliberately refuses to pick a click target that sits under another block, so
this ambiguity cannot make that check flap. No value was invented.

**Related:** the block-overlap *rendering* defect is a separate, already-known
item and is not this gap.

---

## 2026-09-11 — G-011 — the 11–15pt density tier cannot be drawn at `size.blockPadding`

**Where it bit:** task P2-T03, diagnosing the block-overlap defect Parsa reported
in `screenshots/day-full-light.png` and `screenshots/week-full-dark.png` —
symptom (a), the two bars between 12:00 and 13:00 that render on top of each
other. `Kadence/Views/Blocks/GridBlockView.swift`,
`Kadence/Views/Canvas/DayColumnView.swift`.

**What happened.** "Stand-up" (12:30–12:45) and "Check mail" (12:50–13:00) do not
overlap, cluster separately and are laid out full-width and 20 minutes apart —
`DayLayoutEngine` is correct here and was verified directly (Day: y=750 h=13 and
y=770 h=11; Week: y=550 h=11 and y=564.67 h=11). Both are nevertheless *drawn*
~22pt tall in both views, centred on their frames, so each spills ~5pt above and
below and the two collide. 22pt is not arbitrary: it is what the spec's own
chrome adds up to.

**The arithmetic that does not close.** components.md §3.1 sets padding to
`size.blockPadding` (5) on all sides, measured from the rail's trailing edge.
§3.3's 11–15 tier is "rail + glyph only", and the glyph is `size.blockGlyphSize`
(11). So the *minimum* height of a glyph-only block is 5 + 11 + 5 = **21pt** —
above the top of the tier band it belongs to (15) and nearly twice
`size.blockMinRenderedHeight` (11), which is the height the clamp rule in the
same table hands it. Every block in the 11–15 tier is therefore specified to be
smaller than the content the same section specifies for it. At
`size.hourHeightWeek` that is every event of 20 minutes or less; at
`size.hourHeightDay` every event of 21 minutes or less.

**What is needed to close it.** A rule for what gives at the bottom of the
ladder. Candidates, none of which I may pick:

1. A reduced padding token for the glyph-only tier (e.g. vertical padding drops
   to `spacing.xxs`, giving 2 + 11 + 2 = 15 — which lands exactly on the top of
   the tier band and still does not fit an 11pt block).
2. A smaller glyph at this tier, or the glyph clipped/scaled to the available
   height.
3. Raising `size.blockMinRenderedHeight` so the floor and the content agree, and
   restating the tier boundary — this changes the cascade and clustering maths
   in layouts.md §3.3, which clamps overlap tests to that token.

**Second question, same interaction.** Independently of which of those is
chosen, the spec never says that a block's rendering is **confined to its
laid-out frame**. components.md §4 says it explicitly for a travel band in the
short case ("A band never draws outside its own event's bounds"); layouts.md
§3.3 defines block frames but says nothing about what happens when the content
set for a tier does not fit the frame that tier was derived from. Today the
overflow escapes symmetrically in both directions, which is the worst of the
three options (clip, top-anchor, overflow) because it damages the *neighbouring*
block as well as its own. A one-line rule — blocks never paint outside their
laid-out frame; content that does not fit is clipped, top-anchored — would make
the fix unambiguous and would also bound the damage from the case below.

**Also reachable from above.** The same unconfined-render path produces the Week
rendering of "Datenmodellierung": frame 64pt, but with the short-case travel-band
strip occupying `size.travelBandHeight` (18) of its top, the tier evaluated
against the remaining 46pt is `.full`, whose four lines need ~73pt. The block
draws 73pt centred on a 64pt frame and its strip lands ~4.5pt above its own top
edge, on the bottom of "Morning review". So §4's "the event's density tier is
then evaluated against its remaining height" can itself select a content set
that does not fit — a tier chosen against remaining height is still rendered
into the full height *minus* the strip, and 46 ≥ 44 only by 2pt.

**Not blocking.** No value was invented; the diagnosis changed no code. The fix
is a separate task and cannot start until this is answered.

---

## 2026-09-11 — G-012 — §3.3 step 1 is silent on a travel band's visual footprint

**Where it bit:** task P2-T03, symptom (c) — the "Leave 08:38 · 22min" band
overlapping the bottom of "Morning review" in `screenshots/day-full-light.png`.
`Kadence/Layout/DayLayoutEngine.swift` (clustering),
`Kadence/Views/Canvas/DayColumnView.swift` (band placement).

**What happened.** The band belongs to "Datenmodellierung" (09:00–10:30), not to
"Morning review". Its true interval is 22 minutes, which at
`size.hourHeightDay` is 22pt ≥ `size.travelBandHeight` (18), so components.md §4
case 1 applies and it correctly occupies 08:38–09:00 *above* its event, at true
height, "drawn above other blocks in z-order". "Morning review" occupies
08:00–09:00. The two **events** do not overlap, so layouts.md §3.3 step 1 puts
them in different clusters, each gets the full column, and the band paints over
the bottom 20pt of a block that has no idea it is there — hiding its meta line,
which at 58pt is tier `.full` and is required by §3.4. This is precisely the
failure mode §4's own rationale calls out ("A travel band that destroys another
block's content to announce itself is not worth the 18pt") — the short case was
fixed for it; the long case still does it, to a *neighbour* instead of to the
block above.

**What the spec says, exactly.** §3.3 step 1: "Two blocks overlap if
`a.start < b.end && b.start < a.end` after both have been clamped to
`size.blockMinRenderedHeight`." Raw event times, clamped. The only sentence
about bands in §3.3 is "Travel bands are laid out with their parent event and
occupy the parent's slot width" — which fixes the band's *width* and says
nothing about its *extent in time*. The implementation matches the spec
literally; the spec does not cover the interaction.

**What is needed to close it.** Whether an event's footprint for clustering
purposes starts at `departAt` rather than `event.start` when its band is in the
≥ `size.travelBandHeight` case, and if so:

1. Does the extended footprint feed **step 1 only** (so the neighbour is pulled
   into the cluster and packed beside it), or also **step 2's** sub-column
   occupancy test, and is the extended interval clamped like a raw one?
2. The extension is scale-dependent, because the case split in §4 is on the
   band's height in *points*: the same 22-minute band is case 1 in Day (22pt)
   and case 2 in Week (16.1pt). So the same two events would cluster differently
   in Day and in Week. That is defensible — the density ladder is already
   scale-dependent by design — but it should be said out loud, because it means
   a cluster is no longer a property of the day's events alone.
3. Worth knowing before choosing: for this exact pair the answer changes the
   picture only in Day. Extending the footprint makes it a 2-block cluster;
   the Day slot width is `(1060 − 4) / 2 − 2` = 526, far above
   `size.dayColumnCascadeThreshold` (72), so it packs side by side and the
   overlap disappears. In Week the band is case 2 and no extension applies.
   (For reference, the Week column at the reproduced window size is 152.14pt, so
   a hypothetical 2-block cluster there would be `(152.14 − 4) / 2 − 2` = 72.07 —
   it packs, but by 0.07pt. The threshold is genuinely load-bearing at this
   window size.)

**Alternative that needs no clustering change**, if the above is judged too
invasive: state that a case-1 band is clipped to the part of its interval not
covered by another block's frame, or that it draws *under* rather than over
blocks it does not belong to. Both contradict §4's "Drawn above other blocks in
z-order", so either would need §4 amended too.

**Not blocking.** No value was invented; the diagnosis changed no code.

---

## 2026-09-11 — G-010 — CLOSED

**Ruled in `interactions.md` §6.1** (new subsection), with the supporting
statements in `layouts.md` §3.3 (the step 2 sort is a total order; z-order is the
paint order and the hit order) and `components.md` §3.3 (the hit region at the
floor, stated geometrically) and §4 (a band paints at its parent's index).

**Frontmost wins, and it is now a decision rather than a side effect.** The
build's current behaviour stands — §6.1 states the hit order front to back,
subtracts the layers that may never take a click (the now line, background
windows, grid lines, the gutter), and pins the rule to the one thing the user can
verify with their eyes: what is painted on top is what gets selected. Because the
step 2 sort in `layouts.md` §3.3 is now a total order — it gains an `id` ascending
final key, since two distinct events may legitimately share a start, a duration
and a title — "the frontmost block" always names exactly one block. What this closes is the risk
of it being silently reordered by a refactor of the view hierarchy.

**Sub-question 1 — the cascade sliver.** A cascaded block's hit region is its
**full laid-out frame**, not its visible sliver. No second geometry is computed
for hit-testing. Under frontmost-wins the two answers coincide anyway: the
covered part of the frame always loses to the block covering it, so the effective
target *is* the visible sliver — `indent` points wide (15 at the narrowest
column, 22 at 116pt or wider) by the block's full height. That is a usable
pointer target, it is the part of the block carrying rail and glyph, and keyboard
focus reaches every block regardless of coverage, so it is never the only route
in. A visible-region hit shape would produce identical clicks at more cost and
one more thing to keep in sync.

**Sub-question 2 — `size.blockHitExtension`.** The extension **loses** to a real
block's frame, in either z-direction. §6.1 resolves in two passes: pass 1 tests
laid-out frames only, front to back; pass 2 runs only if pass 1 found nothing and
tests the extensions. The extension can therefore only claim canvas no block is
painted on. It exists to make a block shorter than `size.blockMinRenderedHeight`
reachable with a pointer, not to win arguments with its neighbours — a click that
selects a block whose ink is nowhere near the pointer is worse than a click that
misses. `components.md` §3.3 also now states the extension's geometry exactly,
which "extend the hit region by `size.blockHitExtension` centred on the true
frame" did not: the floored frame keeps its **top** edge at the true start, and
the hit region is that frame outset by `size.blockHitExtension / 2` (3pt) top and
bottom only, never horizontally — 17pt tall. That matches what the build does.

**Tokens:** none added, none changed. `size.blockHitExtension` (6) keeps its
value; only its geometry is now unambiguous.

**Effect on the build:** none required. `Scripts/check-block-click-selects.sh`
may now legitimately pick a click target that sits under another block, provided
it asserts the frontmost one is selected.

---

## 2026-09-11 — G-011 — CLOSED

**Ruled in `components.md` §3.3 (the ladder, rewritten), the new §3.5
(confinement), §3.1 (corner-radius boundary), §3.4 (the `.full` boundary moved),
§6 (state rows restated in tier names), §9 (the month chip), §11 (Dynamic Type)
and §12 (fixtures 11, 17, and a new 18); and in `layouts.md` §3.3 where the
cascade rule referenced the old band by number.** Supersedes the original §3.3
table in full. DEVIATIONS.md D4 is the same defect and is answered by this entry.

**None of the three listed candidates, taken alone.** Candidate 1 (reduced
padding) does not reach the floor — the gap entry says so itself: 2 + 11 + 2 = 15
against a floor of 11. Candidate 2 (a smaller or clipped glyph) spends the last
non-hue kind signal at the tier that has nothing else left. Candidate 3 (raise
`size.blockMinRenderedHeight`) changes a Phase 1 token that `layouts.md` §3.3's
clamp depends on, to fix a symptom of the real defect. The real defect is
structural and was one rung wider than the gap reported: at
`size.blockPadding` on all sides, **the 16–27 tier does not fit either**
(5 + 14 + 5 = 24 > 16), and **neither does ≥ 44** (5 + 15 + 14 + 14 + 5 = 53 >
44 — which is why the STATUS §1.7 diagnosis measured `.full` needing ~73pt for a
2-line title). The table's bands were chosen; they should have been derived.

**The ruling: derive every band from its own content set, and state the invariant
that was missing.** A tier's band bottom is never below that tier's own minimum.
§3.3 now carries a normative line-height rule
(`lineHeight(style) = ceil(typography.<style>.size × 1.2)`, no extra line
spacing, no inter-row gap → `blockTitle` 15, `blockTitleCompact` 14, `blockMeta`
14), a per-tier vertical-padding table, and the arithmetic for each minimum
alongside its band:

| Tier | Band | Vertical padding | Minimum |
|---|---|---|---|
| `.full` | ≥ 53 | 5 | 5 + 15 + 14 + 14 + 5 = 53 |
| `.compact` | 28–52 | 5 | 5 + 14 + 5 = 24 |
| `.titleOnly` | 18–27 | `spacing.xxs` (2) | 2 + 14 + 2 = 18 |
| `.glyphOnly` | 11–17 | 0 | 0 + 11 + 0 = 11 |

`.glyphOnly` takes **no** vertical padding — at 11pt the glyph is the block, and
this is what makes the floor honest: `size.blockMinRenderedHeight` is now, by
construction, the smallest height at which a block can actually be drawn, which
is the property `layouts.md` §3.3's clamp always assumed and never had. Tier
names are `.glyphOnly` / `.titleOnly` / `.compact` / `.full` — the names the build
already uses — and §3.3 carries a normative mapping from the old numeric bands so
the Phase 2 sections (§13–§17), which are not re-edited here, still read
correctly.

Two riders. `.full` earns its second title line only at ≥ 68 (53 +
`lineHeight(blockTitle)`); "up to 2 lines" is a permission that must be paid for
in real height. And tier selection is now fit-based — take the tier whose band
contains the available height, then step down while that tier's minimum exceeds
it — which is what makes §11's Dynamic Type rule computable instead of
aspirational.

**The confinement invariant — `components.md` §3.5, new.** Stated regardless of
the above, and this is the part CA is blocked on:

1. A block paints only inside its own laid-out frame, clipped to the frame's
   rounded rect. Fill, border, rail, glyph, text, badge, strip — all of it.
2. The content stack is **top-anchored**, laid out from the top inset downward.
   Never vertically centred, never bottom-anchored. A height-setting modifier
   that centres its child by default is specifically wrong here.
3. Content that does not fit is clipped at the **bottom** edge. No scaling, no
   shrink-to-fit, no overflow. The worst case becomes a block that shows less
   than its tier claims — never one that damages its neighbour.
4. Exceptions, exhaustively: the §6 selection ring (outside by design), elevation
   shadows, the `size.blockHitExtension` outset (a hit region, not paint), and a
   case-1 travel band, whose laid-out frame is its own rect (§4).
5. Scope: §3, §4, §5 and §9. The fixed-height rows (§5, §9) centre their content
   vertically and are guaranteed to fit; rules 1 and 3 still bind them.
6. In §4's short case the parent's content area is its frame **minus** the strip,
   and the content is drawn into that area — not into the full frame. This is the
   "also reachable from above" half of the gap: a tier chosen against remaining
   height but rendered into full height is the same bug one level up, and it is
   what pushed a Week block's strip above its own top edge.

**Tokens: none added, none changed.** `.titleOnly`'s 2pt vertical padding uses
the existing `spacing.xxs`, which already carries 2pt insets in §6.
`size.blockMinRenderedHeight` keeps its value of 11 — deliberately, because the
ruling makes the content fit the floor rather than moving the floor to fit the
content, so `layouts.md` §3.3's clamp maths is untouched.

**Non-token Phase 1 values that did move, called out by name:**
- The `.full` boundary, **44 → 53**. Blocks of 44–52pt (46–54 min in Day, 63–74
  min in Week) lose the meta line and therefore the on-block source name. §3.4
  now says why this is not a weakening: at 44pt that line was specified but could
  not be drawn, so what those blocks actually rendered was a clipped or spilling
  meta line. A tier that cannot draw the source name must not claim to.
- The `.titleOnly` bottom, **16 → 18**, and the `.glyphOnly` top, **15 → 17**.
- `radius.blockCompact`'s threshold, **< 16 → < 18** (§3.1), so it follows the
  tier edge instead of being a second independent number.
- `size.monthCellRowHeight` (17) is **not** affected: §9 now states that the
  month chip is an explicit content-set assignment, not a height-derived tier,
  with no vertical padding and vertically centred text. Read through §3.3's bands
  a 17pt row would land on `.glyphOnly` and silently delete every title in Month.

**Effect on the build:** `DensityTier.init(renderedHeight:)`'s three boundaries
become 18 / 28 / 53, `showsLocation` still means `.full`, and the view layer must
clip and top-anchor. The fix for STATUS §1.7 symptoms (a) and (c)-Week is now
unblocked; note that with §3.5 alone both symptoms disappear, since the 12:30 and
12:50 pair are 13pt and 11pt frames drawing 22pt of content.

---

## 2026-09-11 — G-012 — CLOSED

**Ruled in `layouts.md` §3.3 (footprint definition before step 1; steps 1 and 2
restated; the travel-band paragraph rewritten) and `components.md` §4, whose
z-order line is amended to match.** Supersedes §4's "Drawn above other blocks in
z-order".

**Yes — a case-1 band's visual footprint extends its parent event's footprint for
clustering.** §3.3 now defines a **layout footprint** as the interval of grid time
a block's drawing actually occupies: `footprintTop` is `departAt` when the event
has a `components.md` §4 case-1 band (true band height ≥ `size.travelBandHeight`
at the current hour height) and `event.start` otherwise.

**It feeds step 1 *and* step 2, not step 1 only.** If step 1 clustered on
footprints and step 2 packed on raw times, the neighbour pulled into the cluster
would land in the same sub-column and the band would still be drawn on top of it
— the extension would have changed the cluster and fixed nothing. Both steps use
the same footprints; step 2's sort key becomes `footprintTop`, and z-order
follows that sort.

**And yes, it is clamped like a raw interval,** but the clamp is restated to be
unambiguous about direction: `footprintBottom = max(event.end, footprintTop +
minInterval)` where `minInterval` is `size.blockMinRenderedHeight` in minutes at
the current hour height. **The clamp only ever extends the bottom; it never moves
the top.** On an event carrying a case-1 band the clamp is already satisfied and
does nothing.

**Scale dependence, said out loud, as the gap asked.** §4's case split is decided
on the band's height in *points*, so the same 22-minute band is case 1 in Day
(22pt) and case 2 in Week (16.1pt), and the same two events cluster in Day and do
not cluster in Week. §3.3 now states plainly that a cluster is a property of **(the
day's events, the view's hour height)**, not of the events alone — which is not a
new kind of dependency, since the density ladder and the pack-versus-cascade
decision are already scale-dependent for the same reason — and that layout is
therefore recomputed on a view change and never cached across views. The worked
Day/Week numbers for the G-012 pair are in §3.3.

**The alternative was rejected, with reasons.** Clipping a case-1 band to the
uncovered part of its interval, or drawing it under blocks it does not belong to,
both hide the one thing the product exists to tell the user — when to leave —
behind an unrelated block, and the clipped version can lose the label entirely. A
band is opaque and occupies grid time; anything opaque that occupies grid time
has to take part in overlap resolution, or the engine is not describing what is
on the canvas.

**`components.md` §4 amended to agree.** A band now paints at its parent event's
index in the paint order, immediately *below* its parent so the parent's top edge
wins where they meet, above or below exactly the blocks its parent is above or
below, and below the now line. It is never given a z-index of its own. With the
footprint rule there is no foreign block left for it to draw above: anything
sharing its interval is in its own cluster and packed beside it. Inside that
cluster, under cascade, the band overlaps by design and the parent's index is the
right one. This also gives `interactions.md` §6.1 a band's place in the hit
order for free.

**Tokens: none added, none changed.**

**Effect on the build:** `DayLayoutEngine` clustering takes travel legs as an
input rather than raw event times only, and must be told the view's hour height
so it can evaluate §4's case split. This is independent of the §3.5 view-layer
fix and can land separately.

---

## 2026-09-17 — G-013 — §3/§4 assume a free `Date`; a `RoutineBlock`'s day boundary is unhandled

**Where it bit:** task P2-T11, wiring move/resize drag gestures for
`RoutineBlock`s in the Routines window (`Kadence/State/RoutineEngine.swift`'s
new `RoutineBlockStore`, `Kadence/Views/Routines/RoutinesWindow.swift`).

**What interactions.md §11.1 says.** "Creating, moving and resizing routine
blocks uses §3 and §4 unchanged — same 15-minute snap, same `⌃` for 5-minute,
same handles, same drop preview." §4 in turn says resizing clamps rather than
inverts, with a 15-minute minimum duration, and says nothing else about limits.

**What is missing.** Both §3 and §4 are written against `Event.start`/`Event.end`
— ordinary `Date`s with no floor or ceiling; dragging an event past midnight
just moves it onto the next day, which is a perfectly good `Date`. A
`RoutineBlock` has no date at all — `startMinutes: Int` is a time-of-day offset
applied uniformly to every one of the template's active weekdays
(`RoutineTemplate.swift`'s own doc comment) — so it only makes sense in
`0...1440`. Neither §3 nor §4 says what a drag that would push a block's start
before 00:00 or its end past 24:00 should do: wrap to the next/previous
weekday's column (which has no defined meaning — a block is not "on" any one
weekday), clamp at the boundary, or something else.

**What was built instead of guessing.** `RoutineBlockStore.move`/`.resize`
clamp `startMinutes` to `0...(1440 - durationMinutes)` and a resize's `end` to
`...1440`, the same shape as the existing (specified) 15-minute-minimum clamp
in §4 — a drag that would cross midnight stops at the boundary rather than
wrapping or silently producing an out-of-range `startMinutes`. This is a
placeholder decision, not a spec answer: marked here rather than invented
silently and moved past.

**Not blocking.** Ordinary use (a Gym block at 07:00, a Study block at 20:00)
never approaches either edge, so this does not affect the acceptance criteria
task P2-T11 was built against. Needed only to close: an explicit ruling in
`interactions.md` §11.1 (or a new subsection) on cross-midnight drag behaviour
for a `RoutineBlock` specifically.

---

## 2026-09-18 — G-014 — §14.4 does not say what previewing a `.skipToday` conflict option looks like

**Where it bit:** task P2-T16, wiring `components.md` §14.4's "preview in
place" mechanic (`ConflictPreviewFrames` in `Kadence/State/CalendarState.swift`,
consumed by `Kadence/Views/Canvas/DayColumnView.swift`).

**What components.md §14.4 says.** "Focusing an option previews it on the real
grid. Every block the option would move takes the `previewed` presentation
(§6): proposed frame at `opacity.blockPreviewed` inside a dashed accent
outline, current frame retained as a ghost at `opacity.blockDragOrigin`."

**What is missing.** That sentence is written for `.shiftLater`/`.shorten` —
options that have somewhere to move a block *to*. `.skipToday`
(`ConflictOption.newStart`/`newEnd == nil`, `ConflictEngine.swift`'s own doc
comment) proposes marking one occurrence `.skipped`, not moving it anywhere.
§14.4 never says what "preview" means for an option with no destination frame:
whether the block should show some other treatment (e.g. the `.skipped`
presentation itself, previewed), or nothing beyond the ghost dim every option
already gets.

**What was built instead of guessing.** The routine block dims to
`opacity.blockDragOrigin` (the ghost) exactly as it would for any other
focused option on the same conflict, and no dashed `.previewed` twin is drawn
— there is no proposed frame to draw one at, and manufacturing one (e.g. at
the block's own unchanged position) would draw a dashed outline directly on
top of the ghost, which reads as a rendering bug, not a preview.
`ConflictPreviewFrames.resolve` returns `proposed == nil` for `.skipToday`,
and `DayColumnView` only draws the `.previewed` twin when `proposed` is
non-nil. See `DEVIATIONS.md`, task P2-T16.

**Not blocking.** The dim-only treatment is legible on its own (dimming a
block already reads as "something about to happen to this" from the drag
ghost vocabulary it borrows), and every acceptance criterion this task was
built against is satisfied by it. Needed only to close: an explicit ruling in
`components.md` §14.4 on what, if anything, a `.skipToday` (or any other
destination-less) option should additionally show beyond the ghost dim.

---

## 2026-09-18 — G-015 — neither `ConflictEngine.swift` nor components.md §14 says whether a `.skipped` occurrence still counts as "an overlap"

**Where it bit:** task P2-T17, wiring `↩` apply
(`CalendarState.applyFocusedConflictOption`, interactions.md §10.1's last
paragraph) and, specifically, its `.skipToday` path
(`EventStore.markSkipped`).

**What the spec says.** `ConflictEngine.swift`'s own header (pre-existing,
P2-T13): "A conflict is exactly 'an overlap between a routine block and an
imported/manual event.'" `interactions.md` §10.1: "`↩` applies... and
advances to the next unresolved conflict." `components.md` §14.5: "When the
last conflict is resolved the panel... returns to the ordinary inspector."
None of the three says whether an occurrence's `EventStatus` is part of what
makes it "an overlap" — `ConflictEngine.detect` (as P2-T13 built it) reads
only `origin` and the two intervals, never `status`.

**What is missing / the conflict this produces.** `.skipToday`
(`ConflictOption.skipsOccurrence == true`) does not move the routine
occurrence — its `start`/`end` are untouched by design (see G-014). Applying
it therefore cannot change what `detect`'s interval-overlap check sees.
Taken literally, "an overlap between a routine block and an
imported/manual event" is still true of the pair the instant after
`.skipToday` is applied — the two intervals still overlap — so an
unmodified `detect` would report the *exact same conflict* again on its very
next pass, and "advances to the next unresolved conflict, or returns to
normal if that was the last one" (§10.1/§14.5) could never actually progress
for a `.skipToday` resolution: applying the only option on the only conflict
would leave the panel pointed at the conflict it was just told to resolve,
which is not "resolved and empty," and is not any other state the spec
describes either.

**What was built instead of guessing.** `ConflictEngine.detect` now excludes
a pair whose `.routine`-origin side has `status == .skipped` (one added
`guard` in the pairing loop, `Kadence/State/ConflictEngine.swift`) — reasoning
from `EventStore.toggleSkipped`'s own pre-existing doc comment ("Skipping
puts the item back in the pool to be re-offered. It is never a failure
state"): an occurrence that has been put back in the pool is not, in any
useful sense, still occupying the slot it was skipped out of, so it should
not still register as colliding with whatever else is in that slot. This is
a narrow, deliberate answer to a real silence, not an invented UI value —
recorded here, in `ConflictEngine.detect`'s own inline comment, and in
`DEVIATIONS.md` (task P2-T17), rather than built quietly.

**Not blocking.** Every acceptance criterion P2-T17 was built against
(single-step apply, canvas border drop, advance/resolve-to-normal, the
`.skipToday` status write) is satisfied by this reading, and it changes
nothing about `.shiftLater`/`.shorten`, which already clear the overlap by
moving the interval. Needed only to close: an explicit ruling on whether
`ConflictEngine.detect` (or, if the design intends conflicts to be
status-agnostic, some other, not-yet-built place — e.g. a "skipped
routine occurrences are excluded from the needs-attention count" rule stated
in `components.md` §14 itself) should treat a `.skipped` routine event as no
longer conflicting. If a future spec pass answers this differently, only the
one `guard` in `ConflictEngine.detect` needs to change.

---

## 2026-09-24 — G-016 — components.md §16 needs a destination time for Snooze, but Phase 2 is barred from real scheduling logic

**Where it bit:** task P2-T26, wiring the menu bar popover's `Snooze` button
and its `⌥⌘↩` binding (interactions.md §12) to the components.md §16
confirmation ("`Moved to 19:15` + `Undo`", or "`Moved to tomorrow 09:00`"
across a day boundary).

**What the spec says.** components.md §16 is explicit that it specifies the
*surface*, not the mechanism: "Ruling this implements: `DECISIONS.md`
2026-09-10 'Snooze confirmation is designed in Phase 2, not Phase 4.' The
surface is specified now; no scheduling logic exists until Phase 4." It
requires the result row to "show where the block landed" — an actual new
start time — but names no rule for what that new time *is*. `DECISIONS.md`
2026-09-10 reinforces the boundary from the other side: "the design exemption
covers surfaces, not the services behind them."

**What is missing.** A confirmation row that says "Moved to HH:mm" has to
have moved the event *somewhere real* first — there is no such thing as
rendering the result of a move without first deciding the move. Nothing in
`design/` gives Phase 2 a rule for what a snoozed event's new start should
be (the obvious real answers — "next free slot," "N minutes from now,"
"round to the next :00/:15" — are all scheduling logic, exactly what
`DECISIONS.md` 2026-09-10 bars this phase from building).

**What was built instead of guessing at real scheduling.** `EventStore.snooze(_:)`
(`Kadence/State/EventStore.swift`) shifts the event's start *and* end by one
fixed, well-commented constant, `EventStore.snoozeOffset` — **15 minutes**.
Chosen because it is the smallest common "snooze" increment (the unit most
calendar and reminder apps default a snooze to) and reads cleanly against any
`HH:mm` clock with no rounding needed. It is arithmetic, not a design value —
no colour, size or motion token was invented, and no attempt is made to find
a "better" slot the way real scheduling would. This is the same category of
narrow, documented judgment call as G-015's `.skipToday` conflict exclusion:
a real silence in the spec, answered narrowly, in one place, with the answer
recorded rather than guessed quietly.

**Not blocking.** Every acceptance criterion P2-T26 was built against (the
result row's same-day/next-day text, the same-height in-place swap, the
`motion.snoozeConfirmHold` hold with hover-pause, undo restoring the exact
original start/end) is satisfied by this placeholder, because none of them
depend on *which* 15 minutes — only on the row correctly describing whatever
shift `EventStore.snooze` actually made. Needed only to close: Phase 4's real
snooze-scheduling rule (design/PRD text for what "snooze" should actually
compute), at which point `EventStore.snooze` is replaced outright and
`Kadence/Views/MenuBar/MenuBarPopoverView.swift`/`MenuBarFormatting.snoozeResult`
need no change at all — they only ever read the resulting `start`.

---

## 2026-09-25 — G-017 — ConflictEngine structurally cannot produce a 3-option conflict or a non-first recommendation

**Where it bit:** task P2-T29 (retry), capturing `screenshots/2/` batch 2 —
components.md §17 item 6 (the conflict panel's option-row states) and item 7
(a conflict whose recommended option is not first). Item 6's two-option half
was captured (`screenshots/2/conflict-panel-two-options.png`, the seeded
"Client call" `.manual` / "Focus review" `.routine .fixed` overlap in
`Kadence/Mock/MockData.swift`). Item 6's three-option half and item 7 in full
could not be, and this entry records why that is a build gap, not a missing
fixture.

**What components.md §14.3 says.** "Two or three [options] per conflict." And
on ordering: "Options are ordered by disturbance, least first. The
recommended one is usually but not necessarily first — when it is not, the
ordering still reads as a ranking because line 2 says why."

**What the engine actually does, at HEAD.** `ConflictEngine.makeOptions`
(`Kadence/State/ConflictEngine.swift`, lines 344–367) switches on
`routineEvent.flexibility` and appends at most one flexibility-derived
`RawOption` (`.shiftLater` for `.shiftable`, `.shorten` for `.fixed`, nothing
extra for `.droppable`) plus exactly one `skipOption(for:)` call — there is no
third source of options anywhere in the function, and no code path that can
append more than two `RawOption`s to `raw` before it is handed to `finalize`.
`ConflictEngine.finalize` (lines 444–464) then unconditionally does
`raw.sorted { $0.disturbanceMinutes < $1.disturbanceMinutes }` and marks
`index == 0` as `isRecommended` — strictly disturbance-ascending, no other
tie-break, no override. The combination means:

- Every conflict `detect` can produce has **exactly 1 or 2** options (1 only
  in the documented edge case `makeOptions`'s own comment names — a
  `.droppable` conflict, or a `.shiftable`/`.fixed` conflict where the
  derived option doesn't fit), never 3.
- The recommended option is **always** index 0 after the ascending sort —
  i.e. always the least-disturbance option — never anything else, so "usually
  but not necessarily first" collapses to "always first."

**Why this is an engine gap, not a fixture gap.** No `Event`/`RoutineBlock`
fixture, however constructed, can make `makeOptions` emit a third
`RawOption` — the function has only two `append` call sites, full stop — and
none can make `finalize` mark anything but the disturbance-minimum as
recommended, since that is the entirety of its sort/mark logic. Closing this
needs an engine change: a third option source (e.g. a `.shiftable` block
that could also be shortened, or a "do nothing, absorb the overlap" option)
and/or a ranking rule that can diverge from strict disturbance-ascending
(e.g. a tie-break or a policy override that promotes a different option to
`isRecommended` while leaving the display order by disturbance). Both are
out of scope for a capture task.

**Consequence for components.md §17.** Item 6's three-option half and item 7
in full describe conflict-panel states this build cannot currently reach by
any input — not "no fixture yet drives it," but "no input drives it."

**Not blocking** for anything item 6's two-option half or any other shipped
acceptance criterion depends on: `ConflictRankingTests` already asserts
"exactly one recommended per conflict" and "options sorted ascending by
disturbance," both of which this reading holds unconditionally already — see
`KadenceTests/ConflictRankingTests.swift`. Needed only to close: a spec or
engine decision to add a third option source and/or a non-disturbance
tie-break/override rule for `isRecommended`, at which point `makeOptions`/
`finalize` above are exactly what would need to change.

---

# 2026-10-01 — design session: the rulings needed to finish Phase 2

Design-only session; no coding agent running, so `design/` was not frozen. Scope
was Phase 2 of `BRIEF-PRODUCT.md` and nothing beyond it. Every entry below is
written into a spec file before being marked CLOSED here, per `CONTEXT.md`.

---

## 2026-10-01 — G-018 — the Routines window offers seven columns over a model that has no weekdays (DEFECT)

**Where it bit:** the mock template `Daily routine` has
`activeWeekdays = [2, 4, 6]` (Mon/Wed/Fri). `RoutineWeekLayout.layoutItems`
returns nothing for the other four weekdays, so those columns render as an empty
hour grid plus the time-window backdrop. Before commit `5b73949`, creating a
block on a Tue/Thu/Sat/Sun column silently placed it on Mon, Wed and Fri
instead — the user drew on one column and the block appeared on three others.

**Why it happened.** A `RoutineBlock` is not on a weekday. It is a
`startMinutes` + `duration` that runs on every one of the template's active
weekdays (`RoutineTemplate.swift`'s own doc comment). The canvas presents seven
columns, which reads as seven placement surfaces. Nothing in `design/` ever said
which of the two readings was true, so the window inherited the one the geometry
implies and the store implemented the one the model allows.

**`5b73949` was a hand fix, never specced.** It disables `createSurface`
hit-testing and draft layout on inactive columns
(`RoutinesWindow.swift`'s `isActiveDay`). It stops the silent relocation and
nothing else: the columns still draw hour lines and the window backdrop with no
statement of why they are inert, and dragging an existing block toward one was
not addressed at all.

**RULING — CLOSED. Written into `components.md` §13.5 (with §13.5.1–§13.5.5) and
`interactions.md` §11.1 / §11.1.1.**

(a) **Refuse, with the reason standing and the remedy adjacent.** A create
gesture on an inactive column does nothing — no block, no draft, no outline,
cursor `.operationNotAllowed`. It does not add the weekday and it does not ask.
Auto-adding was rejected because activating a weekday adds *every* block in the
template to that column, and a create-drag is the cheapest and most
mis-aimed gesture in the window; a prompt was rejected as the same modal tax
`DECISIONS.md` 2026-09-10 already refused. The refusal is not a dead end: the
reason is on screen before the gesture and stays there (§13.5.2–§13.5.3), and
the remedy — an `Add Sat` text button — is inside the column the pointer is
already in. Undo step names: `Add Saturday to Routine` /
`Remove Saturday from Routine`. Full copy, geometry and the activation
transition are in §13.5.3–§13.5.4.

(b) **Column treatment, §13.5.2.** Three channels, token-only: hour *and*
half-hour lines both drawn in `color.separator.halfHour`; no header underline
(active days gain a `size.borderEmphasis` underline in the template's
`color.source.<slot>.rail`, so activity is marked positively rather than the
inactive days being degraded); and a pinned two-element note,
`Not in this routine` + `Add Sat`. **The ground stays
`color.surface.canvas`** — `color.surface.canvasSunken` measures 1.01:1 against
`color.window.protectedFill` in light appearance, which would delete a protected
window from exactly the column it was drawn to explain. Window layer and window
labels unchanged, at full strength, because a `TimeWindow` carries its own
`weekdays` and has nothing to do with `activeWeekdays`. All of §13.5 applies in
**Blocks mode only** (§13.5.5).

(c) **`5b73949`'s gesture-disable stays, and is now specified** —
`interactions.md` §11.1's "Gestures on an inactive column are refused" is that
behaviour, plus the `.operationNotAllowed` cursor it was missing and the
draft-abandonment rule its own inline comment was guessing at. Also now
specified, and previously absent: a block drag in this window is **vertical
only** (a block cannot move between columns at all, which is the complete answer
to dragging toward an inactive column), and the drop preview is drawn in **every
active column at once**.

**New tokens:** `typography.inactiveDayLabel`, `size.inactiveDayNoteMaxWidth`
(76). **New checked contrast pair:** `color.interactive.accent` on
`color.surface.canvas` (measured 4.56 / 6.03).

---

## 2026-10-01 — G-017 — CLOSED

**The ruling: implement 2–3 options. `components.md` §14.3 and §17 items 6/7 are
not relaxed.** Written into `components.md` §14.3.1–§14.3.4.

G-017's diagnosis was right and its conclusion was one step short. The engine
cannot produce three options because `makeOptions` gates `shorten` behind
`flexibility == .fixed`, and **no spec ever asked it to**. A block being
shiftable does not make it unshortenable. Ungating `shorten` for every
flexibility is the third option source, and it is the brief's own worked example:
*"shift training 90 min later", "shorten it to 45 min", "skip today"* — three
options, one block, and the brief did not say the block was `.fixed`.

- **Catalogue (§14.3.1):** `shiftLater` (`.shiftable` only, within ± minutes),
  `shorten` (**any** flexibility, remainder ≥ 15 min), `skipToday` (always).
  Consequences: `.shiftable` reaches three; **`.droppable` reaches two instead of
  one**, which was a defect of its own — a single take-it-or-leave-it row is an
  ultimatum with a chip on it, not "decisions come with defaults"; `.fixed`
  reaches two, which §14.3 always permitted.
- **`shiftEarlier` is deliberately excluded** from the day-level catalogue and
  the reasoning is recorded: it is almost always the cheapest option on the
  disturbance scale and almost never the achievable one, so a disturbance
  ranking would recommend it first most of the time. It *is* included in the
  template-level catalogue (§14.6), where the user is editing the shape of the
  week on purpose. The `±` in the model stays two-sided for Phase 6.
- **Cap three** — unreachable by construction, so no option is ever dropped.
  Display order ascending by `disturbanceMinutes`, ties by kind order.
  `skipToday` is never removed.
- **Recommendation (§14.3.3) is a preservation rule, not the disturbance
  minimum,** and it legitimately diverges from the display order: `shiftLater`
  if its minutes ≤ the occurrence's own duration; else `shorten` if it keeps ≥
  half; else `skipToday`. Disturbance-minutes is blind to *what kind* of thing is
  spent — 20 minutes trimmed off a 45-minute session is not 20 minutes of the
  same currency as a 20-minute shift. §14.3's "usually but not necessarily
  first" is now true of a reachable, named fixture rather than aspirational.
- **A single-option conflict carries no chip at all.** Reachable: a `.fixed`
  occurrence wholly contained in the other event. A recommendation among one is
  noise.
- **Exact line-1 and line-2 copy per kind (§14.3.4)**, including
  `re-offered` on the skip row, which is the no-guilt rule stated at the moment
  the user is deciding to skip.
- **Fixtures (§17.1)** for items 6, 7 and the new item 17, with the arithmetic
  worked: `Training` 17:00–18:30 `.shiftable` ±90 × `Supervisor meeting`
  17:30–18:15 gives rows 60 · 75 · 90 with the **second** recommended. This is
  item 7, and it needs no engine special case.

**Blocking dependency G-017 did not name:** `RoutineEngine.materialize` has no
call site anywhere in `Kadence/`. Every `.routine` event on the grid today is
hand-seeded, and `ConflictEngine` resolves ± minutes by reversing a materialised
event's `externalID` — so `shiftLater` is unreachable for a seeded event no
matter what the ranking says. Materialisation must be wired before items 6, 7,
15, 16 or 17 can be captured. Recorded in §17.1 and in the build-task order.

---

## 2026-10-01 — G-019 — §13.4 never says what makes an instance detached, what marks it, or what happens when one is deleted

**Where it bit:** `RoutineEngine.swift`'s header ("Recognising that an existing
event has since been hand-edited … needs the main-grid edit-command path wired
up first") and `RoutinesWindow.swift` line ~1292 ("there is no main-grid edit
path yet that can tell an instance apart from an untouched one, so the count is
always zero"). Both are correct, and both were waiting on a spec answer that did
not exist: `components.md` §13.4 and `DECISIONS.md` 2026-09-10 say an instance
"edited on the main grid" is pinned, and nothing anywhere defines *edited*.

**Three concrete holes.** (1) Does marking an instance done or skipped detach
it? If skipped detaches, then applying a `.skipToday` conflict option detaches,
and `Re-sync` then offers to undo the user's own conflict resolutions. (2) What
field marks it, and does `Revert to routine` need a stored copy of the
template's old values? (3) **Deleting a materialised instance is not handled at
all** — `materialize`'s `eventExists` check finds nothing and recreates it on the
next pass, so a deleted routine block comes back on its own. That is the same
class of silent behaviour as G-018, in a path nobody had looked at.

**RULING — CLOSED. Written into `components.md` §13.7.1, §13.7.2 and §13.7.4.**

- **Exactly four fields detach: start, end, title, flexibility** — the four the
  template owns. Move, resize, retitle and flexibility changes detach; `done`,
  `skipped`, notes, location and lock do not. `status` is a fact about a day,
  never a divergence from a routine, which also keeps `.skipToday` resolutions
  out of the detached count. A full edit-by-edit table is in §13.7.1.
- **An instance edited back to the template's values stays detached.** The user
  made that day explicit; matching by coincidence is not the same as being
  generated.
- **One persisted flag, and nothing else.** The affected date is the instance's
  own day, not a second field; the template's values are read live from the
  still-existing `RoutineBlock`, so `Revert` and `Re-sync` restore the
  template's **current** values. Detachment remains **not** a block signal
  (`DECISIONS.md` 2026-09-10 — every channel on the grid is spent).
- **Deleting a materialised instance leaves a tombstone** keyed by the same
  `(sourceID, externalID)` pair, and re-materialisation never recreates a
  tombstoned pair. It is not detachment and is not counted. `⌘Z` restores the
  instance and removes the tombstone in the one step `interactions.md` §5
  already names. Tombstones before `startOfDay(today)` are never consulted.

---

## 2026-10-01 — G-020 — re-materialisation is specified only as "leaves detached instances alone", which is not enough to be correct

**Where it bit:** `RoutineEngine.materialize` creates and never updates. Its own
doc comment is explicit — "calling `materialize` again over an overlapping range
creates nothing new for a date/block pair that already exists". So moving a
template block from 07:00 to 07:30 changes the Routines window and changes
nothing on the calendar, and the template is not the baseline §13.4 claims it is.
`BRIEF-PRODUCT.md` Phase 2 asks for an engine that "re-materialises when a
template changes without destroying manual edits"; only the second half was
specified.

**Also unspecified:** what happens to instances of a `(block, weekday)` pair the
template has stopped producing (a weekday deactivated, a block deleted); what
date range re-materialisation covers; and whether it may write to the past.

**RULING — CLOSED. Written into `components.md` §13.6.3, §13.6.4 and §13.6.5.**

- **Per-pair table (§13.6.3):** no event and no tombstone → create (unless
  §13.6.1 refuses); exists and not detached → **update** start, end, title and
  flexibility to the template's current values; exists and detached → leave
  alone; tombstoned → leave deleted. An update carries `status` forward
  unchanged.
- **Withdrawal (§13.6.4):** future non-detached instances of a withdrawn pair are
  **deleted**; detached ones are **kept** and stop being detached, with §13.4's
  inspector line replaced by `No longer part of Gym routine` and no `Revert`
  action; past instances are never touched. The whole withdrawal folds into the
  undo step that caused it — `Remove Saturday from Routine` undoes the deletions
  too, in one `⌘Z`, for `interactions.md` §11.2's own reason.
- **The past is a record (§13.6.5):** materialisation never writes to any day
  before `startOfDay(today)` — not a create, not an update, not a delete. This is
  the one rule in §13.6 with no exception anywhere.
- **Horizon:** today through the later of `today + 28 days` and
  `(visible range end) + 7 days`. **Triggers:** launch, any template / block /
  `TimeWindow` edit, and a change to the visible range. Idempotent, so a double
  trigger costs nothing.

---

## 2026-10-01 — G-021 — `3 instances edited this week` names a scope the feature does not have, and `Revert to routine` has no undo step name

**Where it bit:** `components.md` §13.4 and `interactions.md` §11.2 specify
Re-sync's confirmation and its single undo step (`Undo Re-sync Routine`) but
never say which instances are in scope — the visible week, the current calendar
week, or all of them. §13.4 also gives a single-instance `Revert to routine`
action in the main-grid inspector with no undo step name at all, while
`interactions.md` §9 requires every mutation to register a named action.

**RULING — CLOSED. Written into `components.md` §13.7.3 and `interactions.md`
§11.2.**

- **Scope:** the detached, non-tombstoned instances of this template from
  `startOfDay(today)` forward, inside the materialisation horizon (§13.6.5).
  Past detached instances are neither counted nor re-synced.
- **The copy changes to `3 instances edited` / `1 instance edited`** — "this
  week" is deleted, because the scope is not a week and the popover lists the
  real dates anyway.
- **`Revert to routine`'s undo step is `Revert Instance to Routine`** — a
  deliberately distinct name, because the Edit menu is the only thing standing
  between "I undid one day" and "I undid a week".
- Both restore the template's **current** values, and neither resurrects a
  tombstoned pair.

---

## 2026-10-01 — G-022 — §13.2's ± stepper has a range but no value semantics, and the absent value silently removes a resolution option

**Where it bit:** `components.md` §13.2 specifies the stepper as "`blockMeta`
type, 15-minute steps, range 15–180" and stops. `RoutineBlock.shiftableMinutes`
is optional, and `ConflictEngine.shiftLaterOption` returns `nil` when it is
absent — so a `.shiftable` block with no ± value silently loses its
`shiftLater` option, which after G-017 is the option the recommendation prefers.
Nothing said what choosing `Shiftable` writes, what leaving it keeps, or whether
absent is a legal state.

**RULING — CLOSED. Written into `components.md` §13.2.**

Choosing `Shiftable` with no stored value writes **30** immediately — two snap
steps, the smallest value that clears an ordinary 15–30 minute collision, so the
default is useful rather than merely legal. Switching to `Fixed` or `Droppable`
**keeps** the number and hides the stepper. A `.shiftable` block with no value is
a defect, not a state: it renders at 30 and writes 30 on first display, because
the only thing "unset" does in this build is remove an option the user never
asked to lose. Values clamp to 15–180. Undo steps `Set Flexibility` and
`Set Shift Range`.

---

## 2026-10-01 — G-023 — does "place it, then surface a conflict" satisfy `CONTEXT.md`'s protected-window rule?

**Where it bit:** `CONTEXT.md`'s hard rule — "Protected time windows are never
scheduled into automatically." `RoutineEngine.materialize` ignores `TimeWindow`
entirely. `ConflictEngine.detectWindowConflicts` (task P2-T19) detects routine
placements that land in a protected window *after the fact*, and nothing said
whether that counts as compliance.

**RULING — CLOSED. It does not. Written into `components.md` §13.6.1 and
§13.6.2, with the panel in §14.6.**

If after-the-fact surfacing counted, the rule would have no content: every
violation could be excused by a badge. The brief's own Phase 6 posture —
"validate and reject the plan rather than trusting the model to have obeyed" —
would be arguing with its own Phase 2. Materialisation is an automatic process,
so it **refuses**: any strict overlap with a `.protected` span means no event is
created for that pair. It does **not** trim and does **not** shift, because both
are an automatic process choosing a time. `.lowEnergy` and `.peakFocus` never
block materialisation — only `.protected` is a hard constraint and only
`.protected` is named by the rule. `interactions.md` §4's "dropping into a
protected window is allowed" stands untouched: that rule binds automatic
placement, not a user being explicit.

**A refusal is never silent (§13.6.2).** It surfaces in the Routines window
canvas as the §6 `conflicted` presentation on the template block, in exactly the
colliding columns (a static template-vs-window comparison — no materialisation
needed, no new component); in the editor inspector as
`Will not run — inside Sleep (protected) on Mon, Wed, Fri`; and in the
needs-attention count, so it does not depend on the user remembering to look.
Activating it from the sidebar **opens the Routines window**, not the main
inspector, because none of its options can be applied to a day (§14.6).

**Fixture §17 should use (§17.1).** The current mock data cannot show this: the
only protected window is `Sleep` 22:00–07:00 and no block overlaps it (`Reading`
ends 21:30; `Gym` starts exactly at 07:00, and touching endpoints are not an
overlap). Add **`Lunch`, `.protected`, Mon/Wed/Fri, 12:00–13:00** to the
`TimeWindow` seed, and **`Errands`, 12:30, 45 min, `.shiftable` ±90** to the
`Daily routine` template. A bounded daytime window is also the only fixture in
which a protected collision has a way out in both directions, which is what
makes §14.6's cap and tie-break visible. §17 items 15 and 16.

---

## 2026-10-01 — G-024 — §14.2's collision header has no form for a window on the other side

**Where it bit:** `ConflictEngine.detectWindowConflicts`'s own doc comment named
this and deliberately filed no gap ("nothing in this function's own scope needs
it answered"). It is needed now that §14.6 exists. `components.md` §14.2 renders
"the two colliding blocks as **real blocks**"; a `WindowConflict` has one block
and one `TimeWindow`, and a window must not be drawn as a block — a block means
content, and §7 spends its whole argument on windows being canvas.

**RULING — CLOSED. Written into `components.md` §14.2.**

The lower half becomes a **window row**: full panel width, the height the 16–27
tier gives the block above it, filled with the window's own §7 treatment
(`color.window.protectedFill` plus `color.window.protectedEdge` at top and
bottom), carrying its label in `windowLabel` / `color.window.label` and
`protected · 22:00–07:00` in `blockMeta` / `color.text.secondary`. No hue, no
rail, no glyph, no corner radius — a slab, because that is what it is on the
grid. The word between the two becomes **`lands in`**, not `overlaps`: two
blocks overlap symmetrically, a block lands in a window, and the asymmetry is
the point of the rule being broken. Increase Contrast takes §7's override.

---

## 2026-10-01 — G-014 — CLOSED

**Ruling: the ghost dim is the whole preview for a destination-less option.
Written into `components.md` §14.4.** `skipToday` proposes no frame, so there is
no proposed frame to draw a dashed twin at. The occurrence dims to
`opacity.blockDragOrigin` exactly as any focused option dims what it is about to
change, and no `previewed` twin is drawn — manufacturing one at the block's own
unchanged position puts a dashed accent outline directly on top of the ghost,
which reads as a rendering fault rather than a proposal. The
`size.previewCanvasBorder` canvas border is present, as it is for every option;
that is what says a hypothetical is active. This confirms what task P2-T16 built
(`ConflictPreviewFrames.resolve` returning `proposed == nil`); it is now the
spec, and `DEVIATIONS.md`'s P2-T16 entry can be retired.

---

## 2026-10-01 — G-015 — CLOSED

**Ruling: a `.skipped` routine occurrence is not an overlap. Written into
`components.md` §14.5.** `EventStore.toggleSkipped`'s own reading is the right
one — an occurrence put back in the pool is not occupying the slot it was skipped
out of, so it is not competing for it. Without this, applying `skipToday` leaves
the identical collision detectable on the next pass and §14.5's "advance to the
next unresolved conflict" can never progress. Status gates detection for the
`.routine` side only, and only for `.skipped`: `.done` never gates it, because a
completed block really did occupy its slot. This confirms the single `guard` task
P2-T17 added to `ConflictEngine.detect`; it is now the spec, and
`DEVIATIONS.md`'s P2-T17 entry can be retired.

---

## 2026-10-01 — G-013 — CLOSED

**Ruling: clamp at the day boundary, never wrap. Written into `interactions.md`
§11.1.** A move clamps `startMinutes` to `0…(1440 − duration)`; a resize clamps
the moved edge to `0…1440` and keeps §4's 15-minute minimum. It never wraps to
the previous or next column, because a `RoutineBlock` is not on a column
(§13.5's statement of the model) and a template has no "next day". This confirms
the placeholder `RoutineBlockStore.move`/`.resize` already shipped and the same
clamp `create` reuses — the SPEC-GAP comments in `RoutineEngine.swift` can be
replaced with a reference to §11.1.

---

## 2026-10-01 — G-016 — still OPEN, deliberately

Not closed and not closable in Phase 2. Snooze's destination time is Phase 4
scheduling logic, `DECISIONS.md` 2026-09-10 bars it from this phase, and
`EventStore.snoozeOffset`'s fixed 15 minutes remains the right placeholder:
`components.md` §16 and `MenuBarFormatting.snoozeResult` only ever read the
resulting start, so nothing in Phase 2 changes when the real rule lands. Recorded
here so its continued openness is a decision rather than an oversight.

---

## 2026-10-01 — G-025 — §13.5.3's note and §7's window label both claim the leading column's top-left corner

**Where it bit:** task P2-T38, building `components.md` §13.5.3's in-column note
(`InactiveDayNote` in `Kadence/Views/Routines/RoutinesWindow.swift`).

**What the spec says.** §13.5.3 pins the note to the top of the visible region,
inset `spacing.xs` from the column's leading edge. §13.5.2 keeps §7's
window-label rule: the label goes "once, at the window's top edge, in the
**leading** day column — whether or not that column is active". When the window
is scrolled past its top edge, §7 pins that label to the top of the visible
region too, also in the leading column.

**What is missing.** When the leading column is inactive, both elements want the
same corner. Examples: a Sunday-first locale with a Mon–Fri template, or any
template that doesn't run on the first weekday. One case is a protected `Sleep`
window wrapping past midnight with the canvas scrolled to 00:00, or scrolled
anywhere inside the window once §7's pinning is built. Neither section says
which one yields, or whether one stacks below the other.

**What was built instead of guessing.** Nothing special-cased. Both draw where
their own rules put them, and in that case they overlap. §7's scrolled-past
label pinning is not built at all yet (not listed in `DEVIATIONS.md` either), so
today the clash only occurs when the window's top edge is in view. No
`// SPEC-GAP` marker, since no value was invented. The overlap is just left
unresolved.

**Not blocking** for the default fixture (Mon-first locale, the leading column
Monday is active). Needed to close: a stacking or priority rule for the two
pinned elements in the leading column.

---

## 2026-10-01 — G-026 — §13.5.2's recessed hour lines under Increase Contrast

**Where it bit:** task P2-T38, `HourLinesLayer`'s new `recessed` flag
(`Kadence/Views/Canvas/GridLayers.swift`).

**What the spec says.** §13.5.2's table gives inactive columns
`color.separator.halfHour` for "hour and half-hour lines both". On the main
grid, Increase Contrast swaps hour lines to `color.separator.strong`.

**What is missing.** Whether the recessed column keeps `halfHour` under Increase
Contrast, or steps up to some stronger value, as every other line does in
that mode.

**What was built instead of guessing.** The table is read literally:
`halfHour` in both modes. Under Increase Contrast that widens the gap
between active and inactive columns (`strong` against `halfHour`), and it
takes no value the spec doesn't name. Not blocking.

---

## 2026-10-01 — G-027 — what removing a template's last active weekday does

**Where it bit:** task P2-T39, `RoutineTemplateStore.setWeekday`
(`Kadence/State/RoutineEngine.swift`).

**What the spec says.** `components.md` §13.5.4 lists "removal only: toggling
an active weekday off" in the inspector row, not confirmed, one undo step.
`interactions.md` §11.1.1 says the same. Neither makes an exception for the
last active weekday.

**What is missing.** Whether the last day can be turned off, leaving a template
with an empty `activeWeekdays` that produces nothing. The alternative is
refusing it, and §13.5.1 says a refusal has to show its reason. The time-window
sibling (`TimeWindowStore.setWeekdays`, P2-T24) silently refuses an empty set,
but no spec rule covers that either.

**What was built instead of guessing.** It is allowed, read literally from
§13.5.4: `Remove Friday from Routine` leaves an empty set, all seven columns
go inactive and each shows its `Add <Day>` button, and one `⌘Z` restores the
day. Marked `// SPEC-GAP (design/GAPS.md G-027)`. A test pins this placeholder
(`RoutineWeekdayActivationTests.removeLastWeekday`). Not blocking.

**Needed to close:** allow, or refuse with a stated surface for the reason.

---

## 2026-10-01 — G-028 — how the focused toggle inside a weekday toggle row is marked

**Where it bit:** task P2-T39, `WeekdayToggleRow`
(`Kadence/Views/Routines/RoutinesWindow.swift`).

**What the spec says.** `layouts.md` §8.1 and `interactions.md` §11.1.1:
`⇥` reaches the row, `←`/`→` move between the seven toggles, `space` flips
"the focused one". `interactions.md` §1: a focused region draws the standard
system focus ring on its container, and `⇥` leaves a region instead of moving
inside it. So the row is one focus target with an internal focused item.

**What is missing.** Any visual for which toggle inside the row is focused.
The system ring goes around the container, so it can't show this.

**What was built instead of guessing.** Placeholder, marked
`// SPEC-GAP (design/GAPS.md G-028)`: a `color.interactive.focusRing` stroke at
`size.borderSelected`, inset in the toggle's bounds, at `radius.chip`. These are
the selection ring's own colour and width, but the shape and placement are
invented. Shown only while the row has keyboard focus. Not blocking.

**Needed to close:** the focused-item marker for this row, or a ruling that
each toggle is its own focus stop after all.

---

## 2026-10-01 — G-029 — the needs-attention row has no specified accessibility label or value

**Where it bit:** task P2-T40, `SidebarView` (`Kadence/Views/Chrome/SidebarView.swift`).
P2-T39 found the row drawn as `Needs attention 12` but exposed to the
Accessibility tree as an unnamed button with no text. VoiceOver announced only
"button", and `Scripts/check-conflict-apply-return.sh` couldn't find it.

**What the spec says.** `components.md` §10.2 specifies the row's look: a bare
label, no icon, and a `blockMeta` count badge hidden at zero. §11's VoiceOver
paragraph covers grid blocks only. `layouts.md` §2 lists the row. None of them
says what the row speaks.

**What was built instead of guessing.** Placeholder, marked
`// SPEC-GAP (design/GAPS.md G-029)`: accessibility label `Needs attention`
(the row's visible text) and accessibility value the bare count, e.g. `12`
(the badge's visible number). VoiceOver reads it as "Needs attention, 12,
button". No new words were invented. Not blocking.

**Needed to close:** the row's spoken label and value. For example, whether the
count carries a noun (`12 conflicts`, `12 items`), and whether P2-T46's
template conflicts (§13.6.2) change that noun.

---

## 2026-10-05 — G-030 — §11's VoiceOver conflict phrase has no form for a block inside a protected window

**Where it bit:** task P2-T41, `GridBlockModel.accessibilityLabel`
(`Kadence/Views/Blocks/BlockModels.swift`). Since P2-T14 it appended
`conflicts with a protected window` to **every** conflicted block, including
main-grid block-vs-block conflicts such as `Client call` / `Focus review`.

**What the spec says.** `components.md` §11: "Label order: title, time range,
kind, source, status, then conflict if present", with one example —
`… university timetable, conflicts with Training` — the other block's title.
§14.2 (G-024) says a block **lands in** a window, deliberately not "overlaps".

**What is missing.** The spoken phrase for the other kind of conflict: a block
inside a `.protected` window (the Routines window's §13.6.2 refusal
presentation, and the main grid's Phase 1 protected-window `conflicted`).
`conflicts with Sleep`, `lands in Sleep (protected)`, or something else.

**What was built instead of guessing.** Block-vs-block now speaks §11's form,
`conflicts with <other title>` (one phrase per partner). The protected-window
kind keeps the string the build already spoke, `conflicts with a protected
window`, marked `// SPEC-GAP (design/GAPS.md G-030)`. The window's label is
already carried (`BlockConflict.protectedWindow(label:)`), so a ruling that
names the window needs no model change. Not blocking.

**Needed to close:** the spoken phrase for a block in a protected window.

---

## 2026-10-05 — G-031 — when a tombstone stops applying

**Where it bit:** task P2-T41, `RoutineTombstone` / `RoutineEngine.materialize`.

**What the spec says.** `components.md` §13.7.4: "Deleting the block from the
template, or deactivating the weekday, makes the tombstone irrelevant and it
**may** be discarded." and "Tombstones before `startOfDay(today)` are never
consulted."

**What is missing.** "May" leaves the observable case open. Delete Saturday
10's Gym, deactivate Saturday, then reactivate it: if the tombstone was
discarded on deactivation, Saturday 10 gets a fresh Gym; if it was kept, it
stays deleted. The same question applies to deleting a block and undoing that
delete. Nothing says whether a tombstone is ever cleared other than by `⌘Z` on
its own delete.

**What was built instead of guessing.** Tombstones are kept until the delete
that made them is undone, and never discarded otherwise, marked
`// SPEC-GAP (design/GAPS.md G-031)` in `RoutineTombstone.swift`. This is the
conservative reading: a day the user deleted is never brought back by an
unrelated template edit. Past tombstones are inert, since nothing
materialises before today. Not blocking.

**Needed to close:** whether withdrawal (or reactivation) clears the pair's
tombstone.

---

## 2026-10-05 — G-032 — §13.2's rail sample height and the stepper's text

**Where it bit:** task P2-T42, `FlexibilityControl`
(`Kadence/Views/Routines/FlexibilityControl.swift`).

**What the spec says.** `components.md` §13.2: each segment shows "a 3pt rail
sample in the segment's leading edge drawn in that rail style", and
`.shiftable` "reveals a stepper for its ± minutes, `blockMeta` type".

**What is missing.** (1) The sample's height (only its 3pt width is given), and
its colour. (2) The stepper's visible text: the type is given, the words are
not.

**What was built instead of guessing.** Placeholders, marked
`// SPEC-GAP (design/GAPS.md G-032)`: the sample is as tall as the segment's
own title line (the system control font's line height), drawn by the grid's
own `RailView` in the template's `color.source.<slot>.rail`; the stepper reads
`± 30 min` in `blockMeta`. The segmented control is a native
`NSSegmentedControl` (SwiftUI's segmented `Picker` drops segment images on
macOS), so the segments themselves invent nothing. Not blocking.

**Needed to close:** the sample's height and colour, and the stepper's copy.

---

## 2026-10-05 — G-033 — a detached instance kept by withdrawal: one flag can't hold it, and its pair can come back

**Where it bit:** task P2-T43, `Event.routineLink` (`Kadence/Models/Event.swift`)
and `RoutineEngine.withdraw`.

**What the spec says.** `components.md` §13.7.2: "One persisted flag … cleared
only by Re-sync, `Revert to routine`, or withdrawal." §13.6.4: detached
instances of a withdrawn pair "are kept, and they stop being detached … become
ordinary `.routine`-origin events, keep their `(sourceID, externalID)`", with
the inspector line `No longer part of Gym routine`.

**What is missing.** (1) Once its flag is cleared, a kept instance looks exactly
like an untouched one, and §13.6.4 itself says future non-detached instances of
a withdrawn pair are deleted. The next pass (any trigger) would delete the
instance withdrawal just kept. The "No longer part of" line also needs to know
it was kept. A two-valued flag can't express it. (2) If the pair is produced
again (the weekday reactivated, the block's delete undone), nothing says whether
the kept instance rejoins the routine (and gets updated to the template) or
stays an ordinary event.

**What was built instead of guessing.** (1) The flag is one persisted field
with three values: `linked`, `detached`, `released`. Withdrawal turns
`detached` into `released`, in the same undo step. `released` is never
withdrawn, updated, counted as detached, or reverted. (2) A released instance
stays released when its pair comes back, so re-materialisation leaves it alone.
Marked `// SPEC-GAP (design/GAPS.md G-033)` in `Event.swift` and
`RoutineEngine.swift`. Not blocking.

**Needed to close:** confirm the three-valued field, and rule on (2).

---

## 2026-10-05 — G-034 — the Re-sync popover's `+N` row and insets

**Where it bit:** task P2-T44, the Re-sync popover in `RoutineInspectorView`
(`Kadence/Views/Routines/RoutinesWindow.swift`).

**What the spec says.** `components.md` §13.4 / §13.7.3: a popover anchored to
the button, `size.resyncPopoverWidth`, listing the affected dates in
`popoverRow` type, "up to six then `+N`", primary action `Re-sync 3 instances`.

**What is missing.** The `+N` row's type and colour, and the popover's insets
and row spacing.

**What was built instead of guessing.** Placeholders, marked
`// SPEC-GAP (design/GAPS.md G-034)`: `+N` in `popoverRow` /
`color.text.secondary`; insets `spacing.lg` horizontal, `spacing.md`
vertical, the menu bar popover's own (`MenuBarPopoverView`); rows
`spacing.xxs` apart and `spacing.md` above the action. Dates read `Tue 6` (the
calendar's short weekday symbol and the day, as in interactions.md §11.2's
`Tue 8`). The primary action is the native default button (↩ triggers it).
Not blocking.

**Needed to close:** the `+N` row's style and the popover's insets.

---

## 2026-10-05 — G-035 — §14.3.4's copy tables contradict its own duration rule

**Where it bit:** task P2-T45, `ConflictOptionFormatting`
(`Kadence/State/ConflictOptionFormatting.swift`).

**What the spec says.** `components.md` §14.3.4's exact-copy tables read
`Shift Training 75 min later`, `17:00 → 18:15 · all 90 min kept`,
`90 min → 30 min · 60 min lost` and `Does not run today · 90 min lost ·
re-offered`. The sentence directly under them: "Durations are always `N min`
below 60 and `N h MM` at or above it (`1 h 30`)."

**What is missing.** Both can't hold: by the sentence, the tables would read
`1 h 15 later`, `all 1 h 30 kept`, `1 h 30 → 30 min · 1 h 00 lost`.

**What was built instead of guessing.** The tables, word for word, because
they are labelled exact copy and the brief asked for exact copy. Every minute
figure goes through one function (`ConflictOptionFormatting.minutes`), marked
`// SPEC-GAP (design/GAPS.md G-035)`, so a ruling for the sentence is a
one-line change plus the copy tests. Not blocking.

**Needed to close:** which one holds.

---

## 2026-10-05 — G-036 — §14.2's window row: label inset and spacing

**Where it bit:** task P2-T46, `TemplateConflictPanelView.windowRow`
(`Kadence/Views/Routines/TemplateConflictPanelView.swift`).

**What the spec says.** `components.md` §14.2 (amended): full panel width, the
16–27 tier's height, `color.window.protectedFill` with `protectedEdge` lines at
top and bottom, two labels (`windowLabel` / `color.window.label` and
`blockMeta` / `color.text.secondary`), no hue, rail, glyph or radius.

**What is missing.** Where the two labels sit inside the slab: the leading
inset and the gap between them.

**What was built instead of guessing.** Placeholder, marked
`// SPEC-GAP (design/GAPS.md G-036)`: leading/trailing inset `size.blockPadding`
(the block above it uses the same), `spacing.sm` between the labels, both on
one baseline. Not blocking.

**Needed to close:** the row's label inset and gap.

---

## 2026-10-05 — G-037 — §17.1 item 10's "degraded at 110pt" row contradicts §15.1's own threshold

**Where it bit:** task P2-T47, `StatusItemLayout` and the item-10 captures.

**What the spec says.** `components.md` §15.1 (amended): show `HH:mm · Title`
while the space left after the time and ` · ` is at least
`size.statusItemTitleMinWidth` (32), and the time alone below that. §17.1
item 10: `degraded | 17:10 | Statistik Übung Gruppe 4 | 110 | 17:30 alone`.

**What is missing.** Measured at the `statusItem` type (13pt medium,
monospaced digits): `17:30` = 37.3pt and ` · ` = 11.0pt, so at 110pt the
title has 61.8pt, about twice the threshold. By §15.1 the 110pt row shows
`17:30 · Statisti…`. The degrade first happens below about 80.3pt (37.3 + 11.0
+ 32).

**What was built instead of guessing.** §15.1's rule as written. The 110pt
row is captured as the rule renders it, and an extra 80pt row shows the
degrade (`screenshots/2/INDEX.md`, Batch 8). No SPEC-GAP marker, since no value
was invented. Not blocking.

**Needed to close:** change the fixture's width (to about 80) or the token.

---

## 2026-10-05 — G-038 — a selected conflict option row: line 2 contrast and long titles

**Where it bit:** task P2-T48's captures (`screenshots/2/conflict-skip-today-preview-p2t48.png`,
`template-conflict-preview-p2t48.png`, `template-conflict-panel-p2t48.png`).

**What the spec says.** `components.md` §14.3: rows on `color.surface.canvasSunken`,
selected fill `color.interactive.selectedRowFill`; line 2 in
`conflictOptionDelta` / `color.text.secondary`. §14.6 gives template titles
such as `Shift Errands 30 min later in the routine`.

**What is missing.** (1) On the selected fill (rendered as the accent blue
here), `color.text.secondary` line 2 is close to illegible. No on-selected
text colour is specified. (2) In the editor inspector, a §14.6 title beside
the `Recommended` chip runs past `conflictOptionTitle`'s line limit and
truncates (`Shift Errands 30 min later in the…`), so the imperative copy
isn't fully readable.

**What was built instead of guessing.** Nothing changed. The tokens are used
as specified and the frames show the result. Not blocking.

**Needed to close:** a text colour for rows on the selected fill, and a rule
for long titles (wrap, or the chip on its own line).

---

## 2026-10-05 — Phase 2 screenshot review: G-025 to G-038 CLOSED

Design agent, Phase 2 screenshot-review session. Every ruling below is written
into the spec file named, **and** recorded here, per `CONTEXT.md`. Full reasoning
lives in the spec text; this list is the index. `design/PHASE2-REVIEW.md` carries
the verdict, the per-item table and the fix list. `tokens.json` is now 1.2.0.

### G-025 — CLOSED. `components.md` §7 (2026-10-05 amendment, rule 3) and §13.5.2.
The note and the window label share the inactive leading column's top-left
corner by **stacking**: the note takes the corner, the label sits `spacing.xs`
below the note's frame. Same when both are pinned. The label never escapes into
the gutter. §7 also gains rule 2 (a label is never drawn half-covered by a block;
it moves to the first spanned column where it is clear, else is omitted; in
Windows mode labels draw above the dimmed block layer).

### G-026 — CLOSED. `components.md` §13.5.2 (2026-10-05, Increase Contrast).
Inactive columns step up one notch with the active ones: `color.separator.hour`
for hour and half-hour lines under Increase Contrast (active: `separator.strong`).
The build's literal `halfHour` reading is replaced.

### G-027 — CLOSED. `components.md` §13.5.4 (2026-10-05).
Removing a template's last active weekday is **allowed** as built (a paused
routine; nothing destroyed; one `⌘Z`). The `// SPEC-GAP` placeholder becomes the
spec. A `TimeWindow`'s last weekday is the opposite case and is **refused**: the
last active toggle is disabled with help text
`A window needs at least one day. Delete it instead.` This replaces the build's
silent refusal.

### G-028 — CLOSED. `layouts.md` §8.1 (2026-10-05, toggle row).
The placeholder is adopted: `color.interactive.focusRing`, `size.borderSelected`,
inset 1pt inside the toggle, `radius.chip`, only while the row has keyboard
focus; the row stays one focus target. The same amendment fixes the clipped
letters: the row moves under its label, seven `size.weekdayToggleSize` (24, new)
squares `spacing.xs` apart, `veryShortStandaloneWeekdaySymbols`, on = accent /
`text.onSolid`, off = `canvasSunken` / `text.secondary`, AX label = full weekday
name.

### G-029 — CLOSED. `components.md` §10.2 (2026-10-05).
Label `Needs attention`; value `1 conflict` / `16 conflicts` (template refusals
are conflicts too, §14.6); no hint. The badge stays a bare number.

### G-030 — CLOSED. `components.md` §11 (2026-10-05).
`lands in Sleep, a protected window`; `lands in a protected window` for an empty
label; block phrases before window phrases. `conflicts with a protected window`
is retired.

### G-031 — CLOSED. `components.md` §13.7.4 (2026-10-05).
A tombstone is removed only by undoing its own delete; "may be discarded" is
withdrawn. The build's conservative placeholder is the spec. Past tombstones may
be pruned silently (unobservable).

### G-032 — CLOSED. `components.md` §13.2 (2026-10-05).
Sample height = the segment title's resolved line height (as built). Sample
colour: a **template image** tinted by the control like the title, in every
state — not the template's rail hue. Stepper copy `± 30 min` in `blockMeta` /
`text.primary`, no label word.

### G-033 — CLOSED. `components.md` §13.7.2, §13.6.3, §13.6.4 (2026-10-05).
The spec **adopts** one persisted field `routineLink` with three values
(`linked` / `detached` / `released`). A `released` instance whose pair the
template produces again **rejoins as `detached`**, keeping every edit; the
template never creates a second instance beside it. Rejoin is folded into the
causing user step (unrecorded in background passes) and never touches the past.
This overturns the build's "stays released" placeholder.

### G-034 — CLOSED. `components.md` §13.4 (2026-10-05).
The popover's insets and row spacing are adopted as built. It must be a system
popover (never clipped by the window — the capture shows it clipped). The
overflow row reads `+N more` in `popoverRow` / `text.secondary`.

### G-035 — CLOSED. `components.md` §14.3.4 (2026-10-05).
The **tables** hold: every duration in conflict copy is `N min` at every size;
the `N h MM` sentence is struck. The build already matches; only the
`// SPEC-GAP` marker is removed.

### G-036 — CLOSED. `components.md` §14.2 (2026-10-05).
Adopted as built: `size.blockPadding` insets, `spacing.sm` between the labels,
one baseline, vertically centred; the second label truncates first.

### G-037 — CLOSED. `components.md` §17.1 item 10 (2026-10-05).
The **fixture** was wrong; the token stays 32. The degraded row moves to 80pt;
110pt stays as a `narrowed` row expecting `17:30 · Statisti…`. Both are already
captured.

### G-038 — CLOSED. `components.md` §14.3 (2026-10-05) and `tokens.json` 1.2.0.
(1) A selected option row uses the new `color.interactive.selectedCardFill`
(`#E3EDFF` / `#1F3352`) plus a 2pt `focusRing` inner border; text colours are
unchanged (line 2 now 5.44:1 / 5.63:1, was 1.41:1 / 1.25:1 on
`selectedRowFill`). (2) The `Recommended` chip is **line 3**, on its own line, as
§14.3 always listed it; titles get the full row width and are never truncated.

### Still open after this session

- **G-016** — open deliberately (snooze destination is Phase 4 logic; the fixed
  +15 placeholder stands). Unchanged.
- **G-003** (contrast checker in the generator) — still deferred. Not in this
  review's range and not a Phase 2 acceptance condition. Note for Parsa: the
  G-038 failure would **not** have been caught by it, because the failing pair
  was never declared; the checker guards declared pairs only. 1.2.0 declares
  the selected-card pairs and records the barred `selectedRowFill` text pairing
  in `$meta`.

### New rulings with no prior GAPS entry (found in the screenshots)

Written into the spec in the same pass; listed here so they are not mistaken
for closures of filed gaps:

- `components.md` §3.3 — on a shared `.compact` row the title keeps ≥ 44pt and
  the trailing time is dropped whole rather than squeezing it (`Gym` → `G`).
- `components.md` §7 rule 1 — window treatments (the low-energy hatch) are
  clipped to their spans; the hatch currently spills into Saturday.
- `components.md` §14.1 / `interactions.md` §10.1 — activating a conflict
  scrolls it into view and focuses the recommended option.
- `components.md` §15.1 — the live status item is template-rendered; colour
  applies to the popover and to renders only.
- `components.md` §15.2 — meta line names the source; `Open` always enabled;
  `Re-offer` drawn prominent.
- `components.md` §17.1 — §12 item 12's triple moves to 13:00–14:30; expected
  count 13 day + 1 template = **14** on every weekday.
- `components.md` §17.2 — what counts as capture evidence.
- `layouts.md` §6 — inspector inset measured from its visible edges (B20); the
  Source row shows the source's name, not `Green`.
- `layouts.md` §8 — the Routines canvas never scrolls horizontally at any
  permitted width (no work required).
- `layouts.md` §10 — the `1 of N` footer completed and required (A32).
- `interactions.md` §12 — popover keyboard table and `Open` required; key focus
  on every open adopted; §16's cross-scene transition deferred.

---

## 2026-10-05 — G-039 — the main window's region focus rings show as one edge

**Where it bit:** task P2-F02 (DEVIATIONS B20/B21). The "full-height accent line
on the inspector's leading edge" in every 2026-10-05 main-window frame.

**What the spec says.** `interactions.md` §1: the focused region draws the
standard system focus ring on its container. `layouts.md` §6 (2026-10-05): the
inspector's ring is the complete standard ring around the region, never one
edge of it.

**What is missing.** On macOS 26 AppKit draws both the grid's and the
inspector's rings around their hosting rects, which reach the window's own
edges (the detail column runs under the floating sidebar and the toolbar).
Three edges fall on the window border; the one visible edge is the line at the
canvas/inspector boundary. A complete ring would have to be drawn by hand, and
no inset, colour or width is specified for a custom ring.

**What was built instead of guessing.** Absent, which layouts.md §6 allows for
the inspector: `.focusEffectDisabled()` on the grid and on the inspector. The
grid's focus is still shown by its own §1 signals (the time cursor in the
column and the gutter, the selection ring). The sidebar's ring is unaffected.

**Needed to close:** confirm "absent" for the grid region, or specify a drawn
region ring (inset, width, colour) for regions whose system ring cannot be
complete.

---

## 2026-10-06 — Phase 2 re-review: gaps opened and closed

Design agent, 2026-10-06 (`PHASE2-REVIEW.md`, "Re-review — 2026-10-06"). Each item
the re-review was asked to rule on, or found in the Batch 10 frames, that had no
GAPS entry is **opened here and closed in the same pass**, so the record shows
both. Every closure names the spec text that now carries the ruling.

### G-039 — CLOSED. `interactions.md` §1 ("Where focus is drawn", 2026-10-06); `layouts.md` §6, §8, §8.1, §9 (2026-10-06).

Absent, everywhere: no region draws a region focus ring and no window or popover
root draws one. Focus is shown on the element that has it, per §1's table, which
is normative (a focused region showing none of those indicators is a defect).
Covers DEVIATIONS B21 (main grid and inspector — built as now specced) and B35
(the Routines window's ~1px accent line on all four outer edges, measured
`#80B3FA`-ish; still to remove). Also covers the same line on the live menu-bar
popover's edge (`popover-live-p2f20.png`, measured `#8DBBFB`), with NEXT now taking
`hoverOverlay` when focused (`interactions.md` §12). A drawn ring was rejected:
around the canvas it would be the same accent frame as §14.4's preview border with
the opposite meaning. No token added.

### G-040 — opened and CLOSED. `components.md` §13.4 (2026-10-06).

**Gap:** §13.4 said `⎋` dismisses the Re-sync popover; the build ignores it
(DEVIATIONS B34) and nothing said what "dismiss" must cover. **Ruled:** `⎋`
dismisses whenever the popover is open, wherever focus is inside it, writes
nothing, and returns focus to the `Re-sync` button. A keyboard user's only other
exits are confirming or closing the window.

### G-041 — opened and CLOSED. `layouts.md` §8 (2026-10-06); `components.md` §7 rule 2.

**Gap:** DEVIATIONS B22 — the Routines canvas leaves its time gutter unpainted;
§8's "hour grid exactly as §3.1" did not say whether §7's gutter span came with
it. **Ruled:** it does. Protected and low-energy treatments span the gutter in the
Routines canvas; peak focus's outline does not; labels never do.

### G-042 — opened and CLOSED. `layouts.md` §3.1 (2026-10-06).

**Gap:** in Week view, is `firstEventStart` the earliest instant on the visible
days or the earliest time of day across them? (P2-F22 built the first.)
**Ruled:** earliest time of day among timed events that start on a visible day;
all-day items and previous-day carry-overs excluded. Same result (06:00) with
today's fixtures.

### G-043 — opened and CLOSED (no change). `components.md` §3.3 (2026-10-06 confirmation).

**Gap:** Routines-window block titles clip without an ellipsis (`Morning revie`).
**Ruled:** that is §3.3's `.titleOnly` rule (no ellipsis character) on a 22pt
block. Correct as built.

### G-044 — opened and CLOSED. `components.md` §7 rule 2 (corrected 2026-10-06).

**Gap:** in Windows mode `Low energy` is drawn above `Errands` with the block's
border through the word. The coding agent read §7 rule 2 ("drawn above … never
displaced") as allowing it — a correct reading of a wrong sentence. **Ruled:**
Windows mode places labels by the same column scan as Blocks mode, draws them
above the dimmed blocks, and never omits one (fallback: leading spanned column).

### G-045 — opened and CLOSED. `interactions.md` §10.1 (2026-10-06).

**Gap:** an evening conflict cannot sit one third from the top because the
content ends at 24:00. **Ruled:** the clamp is correct. One third is the aim;
"wholly in view" is the requirement, and the clamp meets it for any occurrence no
taller than the viewport. No padding, no overscroll.

### G-046 — opened and CLOSED. `components.md` §16 (2026-10-06), §17 item 12, §17.1 item 12.

**Gap:** found in the frames. G-016's +15 placeholder can move a block into
protected time (`snooze-next-day-p2t48.png`: `00:05 – 01:35`, inside `Sleep`),
against CONTEXT.md's hard rule. **Ruled:** a snooze whose destination strictly
overlaps a `.protected` span writes nothing; the result row reads `Not moved —
00:05 is inside Sleep (protected)`, no `Undo`. G-016 itself stays open (the
destination rule is still Phase 4's); this closes only the guarantee.

### G-047 — opened and CLOSED. `layouts.md` §8 (2026-10-06).

**Gap:** found in the frames. The Routines window opens at 00:00 (every Batch 10
Routines frame but item 1, which the script scrolled). §8 never gave it a default
scroll. **Ruled:** §3.1's rule over the template's blocks —
`min(07:00, earliestBlockStart − 1h)` — held like the main grid's, re-applied on
template change only. 06:00 with `Daily routine`.

## 2026-10-06 — G-048 — a covered block's title band (DEFERRED out of Phase 2)

**Where it bit:** found in the Batch 10 frames. `conflict-panel-two-options-p2f20.png`
(Wednesday's `Training`, covered from 17:30, draws only a badge although its
17:00–17:30 strip is uncovered at full width) and `conflict-single-option-p2f20.png`
(the conflict's own `Supervisor meeting` has no title on the grid).

**What the spec says.** §3.3: a block whose *visible width* is below 44pt renders
`.glyphOnly`. *Visible width* is not defined; the build takes the narrowest strip.

**Ruled, deferred.** The rule is written into `components.md` §3.3 (amended
2026-10-06) — visible width is measured across the title band; ≥ 44pt there draws
the `.titleOnly` content set in that band — and marked **deferred out of Phase 2,
still normative**, to be logged as DEVIATIONS **A35**. Reason: it changes cascade
rendering in every view and needs its own capture set; Phase 2's definition of
done does not depend on it (the collision header names both blocks; hover help
carries every title). **Stays OPEN** until built and captured.

### Still open after this pass

- **G-016** — unchanged (snooze destination: Phase 4). G-046 adds a guarantee the
  Phase 4 rule must keep.
- **G-003** — unchanged (contrast checker; not a Phase 2 condition).
- **G-048** — deferred, above.

## 2026-10-06 — Phase 2 final run (coding agent): gaps found in P2-SF1's ⇥ walk

### G-049 — OPEN. `layouts.md` §8.1 (focused toggle) / `tokens.json` `color.interactive.focusRing`.

**Where it bit:** P2-SF1's live ⇥ walk of the Routines window. ⇥ into the editor
inspector focuses the weekday toggle row on its first toggle in display order —
`M`, which is **on** in `Daily routine`. The focused toggle's inset stroke is
`color.interactive.focusRing`; an on toggle is filled with
`color.interactive.accent`. Both tokens are the same value (light `#0A6CFF`,
dark `#4C9BFF`), so the stroke is drawn but cannot be seen on any on toggle
(`M`, `W`, `F` here). On an off toggle it shows (`→` to `T`: visible). So on
entry, and on every active weekday, the row shows no focus — which
`interactions.md` §1 calls a defect.

**Question:** what marks the focused toggle when it is on? (A different stroke
colour on on-toggles, an outset, a stroke in `text.onSolid`, …) A value is
needed; the coding agent may not pick one. **Placeholder:** unchanged
(`focusRing` on both), marked `// SPEC-GAP G-049` in `WeekdayToggleRow.swift`.

### G-050 — OPEN. `interactions.md` §1 table (Routines canvas) vs §11.1.

**Where it bit:** P2-SF1's ⇥ walk. §1's table says the Routines canvas shows
focus by "cursor mode's time cursor … or selection mode's §6 selected ring",
and "focus entering the grid with nothing selected enters cursor mode, so the
cursor is always drawn". The Routines canvas has never had a cursor mode (no
task built one), so focused with nothing selected it shows nothing.

**Why the coding agent did not build it:** the main grid's cursor is "across the
focused day column" and its column follows the day; the Routines window has no
focused day, and §11.1 says `←` `→` "do nothing here" (they page by date in the
main window). Which weekday column holds the cursor on entry, whether and how it
moves between columns, and what `↩`/typing does at it (the main grid creates an
event there; §11.1 routes block creation through the template) are all
unspecified. **Placeholder:** none drawn; logged as DEVIATIONS A36.

### G-051 — OPEN. `components.md` §16 (amended 2026-10-06) / §17.1 item 12 (refused row).

**Where it bit:** P2-RC's render `screenshots/2/snooze-refused-p2f25.png`. The
refused row's exact copy, `Not moved — 00:05 is inside Sleep (protected)`, in
`popoverRow` on one line is wider than `size.popoverWidth` (300) less the
popover's `spacing.lg` insets, and §16 fixes the row at the action row's height
(`size.popoverActionRowHeight`), so it renders `Not moved — 00:05 is inside
Sleep (protect…`. A longer window label is worse.

**Question:** which gives — the copy (a shorter form), the height (two lines),
or truncation (and where)? Each is a design value the coding agent may not
choose. **Placeholder:** SwiftUI's default tail truncation, marked
`// SPEC-GAP G-051` in `MenuBarPopoverView.swift`.
