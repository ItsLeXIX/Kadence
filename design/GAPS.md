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
