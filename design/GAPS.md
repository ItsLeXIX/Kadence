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
