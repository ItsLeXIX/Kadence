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
