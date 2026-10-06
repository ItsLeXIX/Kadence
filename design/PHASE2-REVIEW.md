PHASE 2 NOT YET — FIXES REQUIRED

# Phase 2 screenshot review

Design agent, 2026-10-05. Inputs: CONTEXT.md, BRIEF-PRODUCT.md (Phase 2), BRIEF-DESIGN.md,
DECISIONS.md, all of design/, STATUS.md §42–§51, DEVIATIONS.md, screenshots/2/INDEX.md, and
all 40 PNGs in screenshots/2/, opened and inspected. Where a claim needed more than a look,
the frame was cropped and zoomed or measured; every contrast figure below was computed from
`tokens.json` values (WCAG 2.1 relative luminance).

**Why not accepted.** The engine work of P2-T41…T49 is sound, and the brief's definition of
done is met functionally: a weekday routine materialises, a fixed lecture over it produces
ranked options with a recommendation, one click applies, ⌘Z undoes, and the status item and
popover show what's next. What blocks acceptance is what the user actually sees:

- the main inspector clips its own content (B20) in every main-window frame;
- a selected conflict option's explanation line measures 1.41:1 (light) / 1.25:1 (dark);
- block titles lose to their times at ordinary column widths (`Gym` → `G`);
- the low-energy hatch paints a Saturday the window does not cover;
- the popover's `Open` has never been wired, and its keyboard table is mostly unbuilt;
- the `1 of N` footer is missing, so the conflict panel is not yet a list;
- and several frames cannot serve as evidence (stale builds, or the subject below the fold).

None of this needs a redesign. All of it is small. 20 fix items follow, in dependency order.

---

## 2. Per-item table — components.md §17 items 1–18

Verdicts: **ACCEPT** = the item meets the spec and the frame is valid evidence.
**ACCEPT WITH NOTE** = the item's subject meets the spec; the note names a non-blocking issue
or a recapture that a fix elsewhere forces. **REJECT** = the item's subject violates the spec,
or the frame is not valid evidence (§17.2).

| # | File(s) | Verdict | Spec § | Note |
|---|---|---|---|---|
| 1 | `routine-template-flexibility.png` | **REJECT** | §17.2 rule 2; §17 item 1 (amended) | The rail styles were right in 2026-09 (inset / solid / dotted, verified by zoom). The frame predates §13.5's weekday treatment, the flexibility stepper and §17.1's blocks, and shows the low-energy hatch spilling into Saturday (§7 rule 1). Recapture per the amended item-1 fixture. |
| 2 | `routine-windows-all-three-kinds.png` | **REJECT** | §7 rule 1 (2026-10-05); §17.2 rule 2 | All three kinds are present and distinct (protected value step, low-energy hatch, peak-focus dashed outline). But the hatch crosses Friday's trailing divider into Saturday — a window treatment drawn on a day it does not cover. Stale build. New evidence: item 14's frame after fix 5 (it contains Sleep, Lunch, Low energy and Deep work); this file is retired. |
| 3 | `routine-blocks-mode-inactive-windows.png`, `routine-windows-mode-inactive-blocks.png` | **REJECT** (stale only) | §13.3; §17.2 rule 2 | The subject was correct and pixel-verified (windows at full strength in Blocks mode; blocks at ≈0.4 in Windows mode — matches `opacity.editorInactiveLayer`). Stale build. New evidence: item 13 (wide) for the Blocks-mode half and item 14 for the Windows-mode half, both recaptured anyway; no separate capture needed. Retire both files. |
| 4 | `resync-popover-p2t48.png` | **REJECT** | §13.4 (2026-10-05, G-034); layouts §8.1 (2026-10-05, G-028) | Content is right: `3 instances edited`, Re-sync, dates `Mon 5 · Wed 7 · Fri 9`, `Re-sync 3 instances` as default button. But the popover is cut off at the window's trailing edge — it is an in-window overlay, not a system popover. The weekday toggles above it clip `M`/`W` to `N`/`V`. |
| 5 | `detached-instance-inspector-p2t48.png` | **REJECT** | layouts §6 (2026-10-05, B20); §3.4 | The §13.4 line `Edited — differs from Daily routine` and `Revert to routine` are right. Every label loses its first letter (`tarts`, `nds`, `uration`, `ource`, `rigin`, `dited`, `tatus`, `otes`), a full-height accent line sits on the inspector's leading edge, and `Source` reads **`Green`** — the palette slot, not the source name. `Gym` on Wed/Fri renders as `G` beside its full time (§3.3, 2026-10-05). |
| 6 | `conflict-panel-two-options.png` (2026-09-25), `conflict-panel-three-options-p2t48.png` | **REJECT** | §14.3.4; §14.3 (2026-10-05, chip line 3); §14.2 (2026-10-05 inset); layouts §10 | Three-option half: copy is exact (`Shorten Training to 30 min` / `90 min → 30 min · 60 min lost` · `Shift Training 75 min later` / `17:00 → 18:15 · all 90 min kept` · `Skip Training today` / `Does not run today · 90 min lost · re-offered`), order 60 · 75 · 90, overlap line right. But the collision blocks and overlap line are flush against the inspector edge (B20), the chip sits on line 1 instead of line 3, no option is focused, no footer, and the affected block is at the bottom edge of the viewport. Two-option half: pre-P2-T45 copy (`Shorten Focus review by 20 min`, `Frees 60 min · today's occurrence only`) from a build two catalogue revisions old — not evidence for §14.3.4. Recapture both. |
| 7 | `conflict-panel-three-options-p2t48.png` | **ACCEPT WITH NOTE** | §14.3.3 | The subject holds: `Recommended` is on row 2 (`Shift Training 75 min later`, 75 ≤ 90). The chip's position changes to line 3 (fix 14) and the row is focused on entry (fix 15), so this frame is recaptured with item 6. |
| 8 | `conflict-panel-preview-active.png` (2026-09-25), `template-conflict-preview-p2t48.png` | **REJECT** | §14.3 (2026-10-05, G-038); §14.3.4; §3.3 (2026-10-05) | Main-window frame: stale copy, and the focused row's line 2 (`Focus review now 20:20–21:00`) is unreadable on solid accent. Routines frame: ghosts at 12:30 and dashed twins at 13:00–13:45 in Mon/Wed/Fri, canvas border — §14.4/§14.6 met; but line 2 of the focused row measures 1.41:1, the title truncates beside the chip, and each twin reads `Erran…` beside a full `13:00-13:45`. Recapture the main-window half with §17.1's Training fixture (row 2 focused, block in view) and the Routines half. |
| 9 | `needs-attention-count-{0,1,12}.png` | **ACCEPT WITH NOTE** | §10.2 | Still demonstrates the item: hidden entirely at 0; bare label, no icon; badge fill and text pixel-matched to `canvasSunken` / `text.secondary` (INDEX batch 4). The row has not changed visually since — P2-T41/T46 changed its hit area, AX and what it counts, none of which a frame shows. The counts 1 and 12 come from hand-built datasets, which §17 item 9 always allowed. No recapture required. (These frames also show B20 and the inspector's edge line, which are judged under items 5–6.) |
| 10 | `status-item-*-p2t47.png` (7 renders); batch-7 crops | **ACCEPT WITH NOTE** | §15.1 (2026-10-05); §17.1 item 10 (amended, G-037); §17.2 rule 3 | Layout is right in every row: time intact; `17:30 · Gym`; `17:30 · Statistik Übung Gr…`; glyph + `12m ago · Gym`; glyph + `12m ago · Statistik Übu…`; `Nothing left today`; 110pt = `17:30 · Statisti…` (now the `narrowed` row); 80pt = `17:30` alone with no separator and no ellipsis (now the `degraded` row). Each item only as wide as it draws (B15). Offscreen renders are accepted as evidence for layout and truncation (ruling below). Still owed: one **live** menu-bar crop from the current build (fix 19); the batch-7 crops predate P2-T47's one-string label. |
| 11 | `popover-{normal,late,empty,overflow}-p2t48.png`; batch-7 popovers | **REJECT** | §15.2 (2026-10-05); interactions §12 (2026-10-05) | Content is right in all four: NEXT 20pt, rail, `17:30 – 18:15 · Daily routine`, late meta in now-red with leading `Re-offer`, empty with no actions and no rest section, overflow `18:30…21:00` then `+3 more`. But `Open` is drawn disabled in every frame, the 2026-09-27 live one included — it was never wired — and `Re-offer` is styled like the others although §15.2 makes it the primary action. Batch-7 popovers are superseded. |
| 12 | `snooze-{same-day,next-day}-p2t48.png` | **ACCEPT WITH NOTE** | §16; G-016 | Same day: `17:45 – 18:30` above `Moved to 17:45` + `Undo`. Next day: `00:05 – 01:35` above `Moved to tomorrow 00:05` — the two halves now describe one event (B19 fixed). The +15 destination is G-016's deliberate placeholder. The result row replaces the action row, so fix 18 does not change these frames: no recapture. Batch-7 snooze frames are superseded (the next-day one is the B19 mismatch). |
| 13 | `inactive-weekdays-wide-p2t48.png`, `inactive-weekdays-780-p2t48.png` | **REJECT** | §3.5 rule 1; §3.3 (2026-10-05); §7 rules 1–2 (2026-10-05); §17.2 rule 4 | The subject is right: Tue/Thu/Sat/Sun carry `Not in this routine` + `Add Tue`…; Mon/Wed/Fri carry the green underline; recessed lines; the note fits at 780. But at 780 `Morning review` prints across the next column's divider and its selection ring overhangs it (§3.5), `Gym` collapses to `(` beside `07:00-0…` (§3.3); in both, `Low energy` is sliced under `Errands` and the hatch spills into Saturday; and the wide frame has a block selected. |
| 14 | `inactive-weekdays-windows-mode-p2t48.png` | **REJECT** | §7 rule 1; layouts §8.1 (G-028) | Subject right: no notes, no underlines, no reweighting in Windows mode (§13.5.5); all three window kinds visible. Hatch spill into Saturday; weekday toggles clipped. |
| 15 | `routine-refusal-errands-p2t48.png` | **ACCEPT WITH NOTE** | §13.6.2 | `Errands` is `conflicted` in Mon/Wed/Fri only; inspector reads `Will not run — inside Lunch (protected) on Mon, Wed, Fri`; stepper `± 90 min`. The frame also shows the sliced `Low energy` label and the hatch spill; recapture after fixes 5–6 so the evidence shows the build as it will be. |
| 16 | `template-conflict-panel-p2t48.png` | **REJECT** | §14.3 (2026-10-05, G-038 (2)); layouts §10 / §8.1 | Window row, `lands in`, `Lunch protected · 12:00–13:00`, overlap `12:30–13:00 · 30 min · Mon, Wed, Fri`, rows 30 · 30 · 135 with shiftEarlier capped out and row 1 recommended — §14.2 and §14.6 met exactly. But `Shift Errands 30 min later in the…` truncates beside the chip, and `Remove Errands from / this routine` wraps short on a row with no chip: the chip is on line 1. No footer. Reached only through a launch-argument hook, because there is no other way past 13 day conflicts. |
| 17 | `conflict-single-option-p2t48.png` | **ACCEPT WITH NOTE** | §14.3.3 | Subject right: one row, `Skip Training today`, no chip; overlap `17:00–18:30 · 90 min overlap`. Header flush (B20), no footer (which §14.3.3 relies on to say where the user is), and the lone option is not focused/previewed. Recapture after fixes 2, 15, 16. |
| 18 | `conflict-skip-today-preview-p2t48.png` | **REJECT** | §17.2 rule 1; §14.3 (G-038) | The canvas border is right and no dashed twin is drawn. But the previewed occurrence is Monday's Training at the very bottom edge — about 15pt of it in frame — so "the ghost dim with no dashed twin" cannot be verified from this frame. The focused row's line 2 is unreadable. |

### Rulings asked for

**Items 10–12 as offscreen renders — acceptable, for what they can show.** §17.1 pins clock
times (17:10, 17:42, 23:40) and widths (110, 80) that a live menu bar cannot be set to, so a
render of the real `StatusItemLabel` / `MenuBarPopoverView` with the content asserted in the
same test is better evidence of layout, copy, truncation and the degrade rule than any crop
could be. It is not evidence of what the live menu bar does to the label — and that is not
hypothetical: the 2026-09-27 live crops show the late state in menu-bar tint, not red, while
the render draws it red. Written into `components.md` §17.2 rule 3: renders count for layout;
each of items 10 and 11 additionally needs **one live crop** of the current build (normal
state, any time, any title). Making room on the menu bar for that capture — quitting or
hiding other status items — is an acceptable capture step. `components.md` §15.1 now states
that the live item is template-rendered and the colour column is for the popover and renders.

**Items 1, 2 and 9 predating §17.1.** Item 1 must be recaptured: the Routines window has
changed visibly since (underlines, notes, stepper, five blocks). Item 2 is answered by item
14's frame once the hatch is fixed; its batch-1 file is retired rather than recaptured. Item 9
still demonstrates its item and needs no recapture (above). Item 3 is answered by items 13
and 14.

---

## 3. GAPS closed this session

All written into the spec **and** recorded CLOSED in `GAPS.md` ("2026-10-05 — Phase 2
screenshot review: G-025 to G-038 CLOSED").

| Gap | Ruling, one line | Where |
|---|---|---|
| G-025 | The note takes the inactive leading column's corner; the window label stacks `spacing.xs` below it, pinned or not | components.md §7 rule 3; §13.5.2 |
| G-026 | Under Increase Contrast inactive columns use `separator.hour` (one step below active's `strong`) | components.md §13.5.2 |
| G-027 | Removing a template's last weekday is allowed (paused routine); a TimeWindow's last weekday is refused with a disabled toggle and help text | components.md §13.5.4 |
| G-028 | Focused toggle: inset 2pt focusRing at radius.chip (placeholder adopted); row under its label, 24pt toggles, spacing.xs | layouts.md §8.1 |
| G-029 | Label `Needs attention`, value `N conflicts` / `1 conflict`, no hint | components.md §10.2 |
| G-030 | `lands in Sleep, a protected window` / `lands in a protected window` | components.md §11 |
| G-031 | A tombstone is removed only by undoing its own delete | components.md §13.7.4 |
| G-032 | Sample = title line height, template image tinted like the title; stepper `± 30 min` | components.md §13.2 |
| G-033 | Adopted: one field, `linked / detached / released`. A released instance whose pair returns rejoins as `detached`, keeps its edits; no second instance | components.md §13.7.2, §13.6.3, §13.6.4 |
| G-034 | System popover, never clipped; insets as built; `+N more` | components.md §13.4 |
| G-035 | The tables hold: conflict copy is `N min` at every size; the `N h MM` sentence is struck | components.md §14.3.4 |
| G-036 | As built: blockPadding insets, spacing.sm gap, one baseline | components.md §14.2 |
| G-037 | Fixture fixed, token kept: degraded row at 80pt; 110pt becomes a `narrowed` row | components.md §17.1 item 10 |
| G-038 | Selected option row: new `selectedCardFill` + 2pt focusRing border, text colours unchanged; chip on line 3 | components.md §14.3; tokens.json 1.2.0 |

**Left open:** G-016 (deliberate — Phase 4 scheduling logic). G-003 (contrast checker in the
generator, deferred since Phase 1, outside this range; it would not have caught G-038,
because the failing pair was never declared).

**On G-033, the position you stated, argued.** I adopt it. The case for CA's "stays
released" is that a released instance is now the user's own event and should not be pulled
back into the routine behind their back. It does not survive the inspector: a released
instance says `No longer part of Gym routine`, and once the weekday is back that sentence is
false — the routine produces that day again, and the event sits exactly in its pair. Rejoining
as **detached** (not linked) gives the truth without overriding anything: every edit is kept,
§13.7.1 already says a deliberate edit is never silently re-adopted, and the only new thing the
user can do is Re-sync it, which is confirmed and undoable. Two refinements I added: rejoin is
recorded inside the causing step (so ⌘Z on `Add Saturday to Routine` releases it again), and
it never writes to the past, because a flag change is a write and §13.6.5 has no exceptions.

**Other rulings asked for in the brief**

- **B20** — spec side written (layouts.md §6, components.md §14.2): content inset is
  `spacing.xl` from the inspector's *visible* edges; nothing touches the edge; the inspector's
  focus ring is complete or absent, never one edge. Fix 2.
- **A32, the `1 of N` footer** — **required for Phase 2**, and its spec was not complete; it
  now is (layouts.md §10): N = the needs-attention count, `⌘⇧A` order, no wrap, stepping onto
  a template conflict routes to the Routines window, apply advances within the window's own
  kind, `1 of 1` still shown, AX labels. Fix 16.
- **Selected option row contrast** — measured `text.secondary` on `selectedRowFill`
  1.41:1 / 1.25:1, and `text.primary` on it 3.81:1 / 2.52:1. Fixed by a new token and a
  border, not by an on-accent text colour (white on the dark accent is only 2.82:1). §14.3.
- **Weekday-dependent count** — §17.1 amended: §12 item 12's triple (`Group call`,
  `Code review`, `Notes write-up`) moves from 18:00 to 13:00–14:30. **Expected: 13 day
  conflicts + 1 template conflict = 14**, on every weekday and clock time. Fix 1.
- **§7 window-label pinning on scroll** — **deferred; not required for Phase 2.** It is a
  Phase 1 rule that was never built and never logged. Phase 2's definition of done does not
  touch it, the default scroll (`min(07:00, first − 1h)`) shows Sleep's label region rarely,
  and the build already pins the §13.5.3 note, which is the Phase 2 element that needed
  pinning. The rule stays normative and G-025's stacking already covers the pinned case. CA
  logs it as an A-entry in DEVIATIONS (housekeeping, below).
- **Routines header not scrolling with the canvas** — **no Phase 2 work.** The horizontal
  scroll path is unreachable: at both 780 (inspector overlaid) and 1040 (docked) the canvas is
  780pt wide, 104pt per column, above the 84pt floor. Written into layouts.md §8.
- **Also ruled from the screenshots** (no prior gap): title beats time on a `.compact` row
  (§3.3); window treatments clipped to their spans (§7 rule 1); a window label never drawn
  half-covered (§7 rule 2); conflict activation focuses the recommended option and scrolls
  it into view (interactions §10.1); the inspector's Source row names the source (layouts
  §6); popover meta names the source, `Open` always enabled, `Re-offer` prominent (§15.2);
  the popover keyboard table and `Open` required, key focus on every open adopted,
  §16's cross-scene transition deferred (interactions §12); live status item is
  template-rendered (§15.1); capture evidence rules (§17.2).

---

## 4. New and changed tokens — tokens.json 1.1.0 → 1.2.0 (updated 2026-10-05)

| Token | Light | Dark | Use |
|---|---|---|---|
| `color.interactive.selectedCardFill` (new) | `#E3EDFF` | `#1F3352` | Fill of a selected multi-line card row (conflict options). Always with a `size.borderSelected` inner border in `focusRing`. |
| `size.weekdayToggleSize` (new) | 24 | — | Weekday toggle square, layouts.md §8.1 |

New declared contrast pairs (55 total, all re-verified in both appearances, zero failures;
worst 4.5-class pair is the pre-existing `semantic.now` on canvas at 4.55):

| fg on bg | Light | Dark | Min |
|---|---|---|---|
| `text.primary` on `selectedCardFill` | 14.75 | 11.36 | 4.5 |
| `text.secondary` on `selectedCardFill` | 5.44 | 5.63 | 4.5 |
| `interactive.focusRing` on `selectedCardFill` (the selection border) | 3.87 | 4.50 | 3.0 |
| `text.secondary` on `surface.canvasSunken` (option line 2, badge, off toggle — used since Phase 2 began, never declared) | 5.69 | 8.01 | 4.5 |
| `text.onSolid` on `interactive.accent` (on toggle) | 4.56 | 6.93 | 4.5 |

Recorded as barred, deliberately not declared: `text.secondary` on `selectedRowFill`
(1.41 / 1.25) and `text.primary` on it (3.81 / 2.52). For the record, the `$note`'s old
"worst measured 4.87" counted only source pairs; corrected.

Tokens.swift must be regenerated (fix 13 does it; `generate-tokens --check` will report it
stale until then).

---

## 5. Proposed DECISIONS.md entries (text only — yours to write)

**2026-10-05 — Detachment is one field with three values; a released instance rejoins as
detached.** `Event.routineLink`: linked / detached / released. A boolean cannot hold §13.6.4:
once withdrawal clears it, the kept instance is indistinguishable from an untouched future
instance of a withdrawn pair, and the next pass deletes it. When the template produces a
released instance's pair again (weekday re-added, block delete undone, window no longer
refusing), it becomes detached — edits kept, counted, re-syncable — and the template never
creates a second instance beside it. Folded into the causing step; never written to the past.
Rejected: staying released, because `No longer part of Gym routine` would then be false.
Closes G-033.

**2026-10-05 — Conflict copy counts in minutes, always.** `75 min later`, `all 90 min kept`,
`135 min lost`. Line 2 is the ranking made legible, and a ranking is read by comparing numbers;
`1 h 15` beside `45 min` makes the reader convert. The `N h MM` sentence in §14.3.4 was a
generic rule in the one place it doesn't fit. Closes G-035.

**2026-10-05 — No text on solid accent in multi-line rows.** A selected conflict option is a
tinted card (`selectedCardFill`) with a 2pt focus-ring border carrying selection; the text
keeps its normal colours. Solid `selectedRowFill` measured 1.41:1 for line 2 and 3.81:1 for
the title. The `Recommended` chip is line 3, as §14.3 always said, so titles are never
truncated. Closes G-038.

**2026-10-05 — The live status item is template-rendered; colour is not a carrier in the menu
bar.** macOS draws a `MenuBarExtra` label in the bar's own tint and flattens it to one image and
one string. The late state is carried by the glyph and `… ago`, the empty state by its words.
`semantic.now` applies in the popover. Do not force non-template rendering.

**2026-10-05 — Review evidence rules.** A capture shows its subject in the viewport, from the
build under review, with nothing selected that the item didn't ask for. Offscreen renders of
the real view are accepted for layout and copy when the spec pins inputs a live surface can't
be set to, plus one live capture per surface. Review fixtures must not depend on the weekday or
the clock; §17.1 states the expected needs-attention count (14).

**2026-10-05 — A conflict is opened on its recommendation, in view, in one list.** Activation —
row, ⌘⇧A, ‹ ›, or advance after ↩ — scrolls the conflict into view and focuses the recommended
option, which previews. The `1 of N` footer is required: N is the needs-attention count, one
order for both kinds, no wrap. ↩ never opens the other window by itself.

**2026-10-05 — Deferred out of Phase 2, still normative:** §7's scrolled-past window-label
pinning, and §16's block-move transition in an open main window at the moment of a popover
snooze. Neither affects Phase 2's definition of done; both are logged as DEVIATIONS A-entries.

---

## 6. FIX LIST for CA — dependency order

Each item is one task. "Recapture" names the §17 items whose frames must be redone after it;
the actual recapture happens once, in item 20. Every task: build, `-only-testing:KadenceTests`,
`generate-tokens --check`, both check scripts, per the usual rules.

1. **Weekday-independent review fixtures.** Spec: components.md §17.1 (2026-10-05 amendment).
   Move `Group call` 13:00–14:30, `Code review` 13:15–14:00, `Notes write-up` 13:30–14:30
   (today). Test: `MockDataClockTests` asserts **13** day conflicts and needs-attention count
   **14** on a template weekday *and* a non-template weekday at every clock time it sweeps;
   the three still mutually overlap; `check-conflict-apply-return.sh` still PASSes (count
   now 14). Recapture: none on its own (counts reappear in 5, 6, 7, 8, 17, 18).

2. **Inspector inset (B20).** Spec: layouts.md §6 (2026-10-05); components.md §14.2 inset
   paragraph. Every inspector element ≥ `spacing.xl` from the inspector's visible leading
   and trailing edges; remove the leading-edge accent line (the focus ring is the complete
   system ring or nothing). Test: a layout test or AX frame check that the first label's
   x ≥ inspector x + 16 in the main window, in both normal and conflict mode; screenshot shows
   `Starts`, not `tarts`. Recapture: 5, 6, 7, 8, 17, 18.

3. **Inspector Source row names the source.** Spec: layouts.md §6 (2026-10-05); components.md
   §3.4. Test: for a materialised `Daily routine` instance the Source row reads
   `Daily routine` with its swatch; for an imported lecture `University timetable`; never a
   `SourceKey.displayName` colour word. Recapture: 5.

4. **Title beats time on a `.compact` row; text confined.** Spec: components.md §3.3
   (2026-10-05) and §3.5 rule 1. Test: pure layout function — `Gym` / `07:00-08:00` at a
   126pt (main Week, 1500pt window) and a 104pt (Routines, 780pt) column keeps `Gym` whole and drops the time; at a width where time fits
   beside ≥ 44pt of title both show; the time is never partially drawn; `Morning review` at
   104pt truncates with `…` inside the frame. Screenshot: no text crosses a column divider at
   780pt. Recapture: 1, 5, 8, 13.

5. **Window treatments clipped to their spans.** Spec: components.md §7 rule 1 (2026-10-05).
   Test: the clip shape for `Low energy` (Mon–Fri) is the union of its five day rects plus
   gutter strip; a pixel test or render test shows no hatch in Saturday's column on the main
   Week grid and the Routines canvas. Recapture: 1, 2 (via 14), 13, 14, 15, 16.

6. **Window label placement.** Spec: components.md §7 rules 2 and 3 (2026-10-05; G-025).
   Test: pure placement function — `Low energy` at 13:00 with `Errands` (12:30–13:15) in the
   Monday column is placed in Tuesday; omitted when every spanned column is covered; drawn
   above dimmed blocks in Windows mode; placed `spacing.xs` below the note when the leading
   column is inactive (Sunday-first calendar fixture with a Mon–Fri template). Recapture: 13,
   14, 15, 16.

7. **Inactive columns under Increase Contrast.** Spec: components.md §13.5.2 (2026-10-05;
   G-026). Test: the line-colour resolver returns `separator.hour` for an inactive column with
   `increaseContrast == true`, `separator.halfHour` without. Remove the G-026 marker. Recapture:
   none.

8. **Weekday toggle row.** Spec: layouts.md §8.1 (2026-10-05; G-027, G-028); components.md
   §13.5.4. Row under its label, seven 24pt squares `spacing.xs` apart,
   `veryShortStandaloneWeekdaySymbols`, on/off colours as specified, inset focus marker kept,
   AX label full weekday name with value `in routine` / `not in routine` (`on` / `off` for
   windows); in the time-window inspector the last active toggle is disabled with the help
   text. Test: AX label/value per toggle; the row fits in 228pt; a time window with one
   weekday cannot reach an empty set and its toggle reports disabled; the template's last
   weekday can still be removed (existing `removeLastWeekday` test kept). Remove the G-027
   and G-028 markers. Recapture: 4, 14.

9. **Flexibility rail sample as a template image.** Spec: components.md §13.2 (2026-10-05;
   G-032). Test: the segment images have `isTemplate == true`; stepper text `± 30 min`.
   Remove the G-032 marker. Recapture: 15.

10. **Spoken strings.** Spec: components.md §10.2 (G-029) and §11 (G-030), both 2026-10-05.
    Test: the row's AX value is `14 conflicts` with the §17.1 fixtures and `1 conflict` at
    one; `GridBlockModel.accessibilityLabel` ends `lands in Sleep, a protected window` for
    `Late lab session`, `lands in a protected window` for an empty label, and orders block
    phrases before window phrases. Remove the G-029 and G-030 markers; update
    `check-conflict-apply-return.sh` if it matches the value text. Recapture: none.

11. **Detachment rejoin.** Spec: components.md §13.6.3, §13.6.4, §13.7.2 (2026-10-05;
    G-033). Test: Monday instance moved (detached) → `Remove Monday` → released, kept →
    `Add Monday` → same id, `detached`, edited start kept, counted in `1 instance edited`,
    exactly one event for the pair; ⌘Z on `Add Monday to Routine` returns it to released;
    a background pass performs the same rejoin unrecorded; a released instance dated before
    today is untouched. Remove the G-033 markers (the field itself is now spec). Recapture:
    none.

12. **Marker cleanup for rulings adopted as built.** Spec: components.md §14.3.4 (G-035),
    §13.7.4 (G-031), §14.2 (G-036). No behaviour change: remove the `// SPEC-GAP` markers
    and point their comments at the spec section; DEVIATIONS C6, C10 and D5 move to
    "Resolved — retired by a spec ruling". Test: existing copy and tombstone tests unchanged
    and passing. Recapture: none.

13. **Selected option row.** Spec: components.md §14.3 (2026-10-05; G-038 (1)); tokens.json
    1.2.0. Regenerate Tokens.swift. The shared `ConflictOptionRowView`'s focused state uses
    `selectedCardFill` plus a `size.borderSelected` `focusRing` inner border at `radius.card`;
    text colours unchanged. Test: `generate-tokens --check` clean; the row's style for
    `isFocused == true` resolves to those tokens; no view in the target references
    `selectedRowFill` with text on it in a conflict panel. Recapture: 6, 7, 8, 16, 17, 18.

14. **Chip on line 3.** Spec: components.md §14.3 (2026-10-05; G-038 (2)). Chip below line
    2, leading-aligned, `spacing.xs` above; line 1 takes the full row width. Test: at
    `size.editorInspectorWidth`, `Shift Errands 30 min later in the routine` and every
    §14.3.4 / §14.6 title render without truncation (line count ≤ 2, no ellipsis);
    `Remove Errands from this routine` is laid out at full width. Recapture: 6, 7, 16, 17.

15. **Activation focuses the recommendation and brings the conflict into view.** Spec:
    interactions.md §10.1 (2026-10-05); components.md §14.1. Applies to the row, `⌘⇧A`, and
    the advance after `↩`. Test: activating Training × Supervisor focuses and previews row 2
    (`Shift Training 75 min later`); a single-option conflict focuses its one row; the
    canvas pages to the conflict's week and scrolls so 17:00 is one third from the top; the
    Routines window scrolls the template block into view; the P2-T45 "top row" behaviour is
    gone (test updated). Recapture: 6, 7, 8, 16, 17, 18.

16. **The `1 of N` footer (A32).** Spec: layouts.md §10 (2026-10-05) and §8.1. Depends on 15.
    Both windows. Test: N equals the needs-attention count (14); order equals `⌘⇧A` order;
    `‹` disabled at 1 and `›` at N; `⌥←`/`⌥→` step; stepping from the last day conflict onto
    the template conflict opens the Routines window on it; `↩` in the main window never
    opens the Routines window; `1 of 1` is shown with both buttons disabled; AX text
    `Conflict 3 of 14`. Captures for 6/7/16/17/18 must reach their conflicts by stepping, not
    by `-KadenceConflictUnderTest` (the hook may stay for the script). DEVIATIONS A32
    resolved. Recapture: 6, 7, 8, 16, 17, 18.

17. **Re-sync popover as a system popover.** Spec: components.md §13.4 (2026-10-05; G-034).
    `.popover` anchored to the button, arrow edge `.bottom`; overflow row `+N more`. Test:
    eight detached → six dates then `+2 more`; screenshot shows the whole popover with the
    window at its default width. Remove the G-034 marker. Recapture: 4.

18. **Popover: `Open`, keyboard, and the primary `Re-offer`.** Spec: components.md §15.2
    (2026-10-05); interactions.md §12 (2026-10-05). `Open` enabled always (activates or opens
    the main window, pages to and selects the item); `↩` on NEXT or a focused rest row does
    the same; `⌘↩` Done; `⎋` close; `↑`/`↓` move focus with the hover-overlay row
    treatment; key focus on every open (already built — now spec); `Re-offer`
    `.borderedProminent`, others `.bordered`. Test: `Open` is enabled in all three states that
    show actions; a test drives `↑`/`↓`/`↩`/`⌘↩` against the popover's key handler; the late
    state's first button has the prominent style. Log §16's deferred third bullet as an
    A-entry. Recapture: 11.

19. **Live captures for items 10 and 11.** Spec: components.md §17.2 rule 3; §15.1
    (2026-10-05). From the current build, crop the real menu bar: one status item (normal,
    any time and title) and one open popover (normal). Expected: menu-bar tint, one string,
    item only as wide as its text, `Open` enabled. If the item is hidden off a crowded menu
    bar, make room for the capture (quit/hide other status items) — **this may need Parsa's
    hand**; if it can't be done unattended, stop and say so rather than substituting a
    render. Recapture: 10 (live half), 11 (live half).

20. **Recapture and re-index every affected §17 item.** Items **1, 4, 5, 6** (both halves —
    the two-option half is `Focus review` × `Client call` with current copy), **7, 8** (main
    window with §17.1's Training fixture, row 2 focused, block in view; and the Routines
    template preview), **11** (four renders), **13** (wide and 780, nothing selected),
    **14** (also stands for item 2 and item 3's Windows half), **15, 16, 17, 18**, plus fix
    19's live crops. Not recaptured: 9, 10 (renders), 12. Retire `routine-template-flexibility.png`,
    `routine-windows-all-three-kinds.png`, `routine-blocks-mode-inactive-windows.png`,
    `routine-windows-mode-inactive-blocks.png`, `conflict-panel-two-options.png`,
    `conflict-panel-preview-active.png`, and the batch-7 popover/snooze frames (they show
    superseded builds); rewrite INDEX.md's §17 table to the new files, mapping item 2 → item
    14's frame and item 3 → item 13 (wide) + item 14. Each frame per §17.2: subject in the
    viewport, no stray selection, appearance named where a colour is measured.

---

## 7. Housekeeping for CA (list only — not edited)

**screenshots/2/INDEX.md, stale or wrong lines**

1. "`secondary_with_popover.png` — flagged for deletion" (Batch 7) — the file was deleted in
   `2b8f02a`; remove the section, and STATUS §51 item 6's "still awaiting your delete
   decision" is stale too.
2. The opening paragraph: "Four batches, plus one attempted-and-blocked fifth" and the
   Batch-5 "produced no images" lead — there are nine batches and items 10–12 have images.
3. Batch 1 table and item-2 narrative: `routine-windows-all-three-kinds.png` and 3b are
   described as "top (00:00)" with "Sleep's 00:00–07:00 head visible at the very top" — both
   frames start at **03:00**. The same narrative calls Sleep "the familiar hatched protected
   treatment"; protected is a value step, not hatched (only low-energy is hatched).
4. Batch 1 item 1 and 3a: describe the Low-energy window as "drawn normally" — it spills into
   Saturday in every Routines frame (fix 5).
5. Batch 2's option-row description (`Shorten Focus review by 20 min`, `Frees 60 min · …`)
   is the pre-P2-T45 catalogue; mark superseded.
6. Batch 3 says the build "dims the real block in place rather than drawing a second dashed
   copy" and the proposed block appears "in its normal full-opacity style" — the frame shows
   a dashed accent twin at 20:20–21:00. The text contradicts the image.
7. Batch 4: "`WindowConflict` … never folded into `state.conflicts`" — stale since P2-T46
   (template conflicts are counted). "`↩` … did not visibly commit" — fixed in P2-T37
   (STATUS §36). Both "Known open" bullets are stale.
8. Batch 7's "Still missing or questionable" list — the clipped sub-variant exists (batch 8),
   the next-day mismatch was fixed (B19), the same-day "moved earlier" is G-016's placeholder.
   The batch-7 table should be marked superseded by batches 8–9.
9. Batch 8: "§17.1's expectation … contradicts the rule" and "GAPS G-037 asks which one to
   change" — resolved; the 110 row is now `narrowed`, the 80 row `degraded`.
10. Batch 9 table, item 9: "the fixtures now give 16 (15 day + 1 template)" — weekday-
    dependent and superseded; after fix 1 it is 14 on every weekday.
11. Batch 9 table, item 11: "§17.1 writes `· Gym`" — §17.1 now writes `· Daily routine`.
12. Batch 9 table, item 10: "see G-037" — closed.
13. Batch 9 "For the design review" list — every bullet is answered in this file; replace with
    a pointer here.

**Elsewhere (for CA's bookkeeping, not mine to edit)**

- DEVIATIONS: add A-entries for §7's scrolled-past label pinning (never logged) and §16's
  cross-scene block-move (deferred here); add entries for the hatch spill, the label slicing,
  the title/time squeeze, `Source  Green`, `Open` disabled and the clipped Re-sync popover
  (each closed by its fix above). C2, C3, C4, C5, C7, C8, C9 move to "Resolved — retired by a
  spec ruling" as their fixes land; C3's and C8's placeholders are partly overturned (G-027's
  TimeWindow half; G-033's rejoin), not merely retired.
- DEVIATIONS B15 still reads "*Still open*, same task as B14" although STATUS §48 resolves it.
- DEVIATIONS' P2-T45 judgement call "after an apply, the next conflict previews its top row"
  is overturned by interactions §10.1 (2026-10-05).

---

## Re-review — 2026-10-06

PHASE 2 NOT YET — BLOCKERS

Design agent, 2026-10-06. Inputs: CONTEXT.md, DECISIONS.md (through the 2026-10-05
entries), this file's 2026-10-05 review, all of design/, STATUS.md §52–§81,
DEVIATIONS.md, screenshots/2/INDEX.md Batch 10, and every frame Batch 10 maps to
items 1–18, opened and looked at — including `status-item-live-p2f20.png` and
`popover-live-p2f20.png`. Where a claim needed more than a look, the frame was
cropped and zoomed or its pixels sampled (the edge-line colours below are sampled
values). Judged on what is drawn, under DECISIONS 2026-10-05 "Review evidence rules".

**Why not accepted — two blockers, both small.** Everything the 2026-10-05 review
asked for is built and visible, and every §17 item is accepted (none rejected).
What stops acceptance:

1. **A snooze can write into protected time.** `snooze-next-day-p2t48.png` shows
   `Prep: relational algebra` moved to `00:05 – 01:35`, inside `Sleep`. That breaks
   a CONTEXT.md hard rule. I accepted this frame on 2026-10-05 looking only at its
   copy; that was my miss, not the build's. Ruled in §16 (G-046).
2. **`⎋` does not close the Re-sync popover (B34).** On a destructive confirmation
   a keyboard user can confirm or close the window, and nothing else. That is a
   wrong behaviour against §13.4 and a keyboard-accessibility failure (G-040).

Each is a guard of a few lines plus a test. When they and the small fixes land,
Phase 2 can be accepted on the final run's evidence: the tests named below, a
recaptured item 14, the two new snooze renders, and the popover edge check. I do
not need to re-review all 18 items again (see "For Parsa").

### R1. Fix-list verification (2026-10-05 §6, items 1–20)

Judged from the frames and the spec. Where a fix has nothing a frame can show,
that is said, and the verdict rests on the spec plus the named test.

| # | Fix | Verdict | Evidence |
|---|---|---|---|
| 1 | Weekday-independent fixtures | **DONE** | Sidebar badge `14` in every main frame; footers read `1 of 14`, `2 of 14`, `14 of 14` (Tue 6 Oct, a non-template day). |
| 2 | Inspector inset (B20) | **DONE** | `Starts`, `Ends`, `Duration`, `Source`, `Origin`, `Edited`, `Status`, `Notes` whole in `detached-instance-inspector-p2f20.png`; collision blocks inset in all conflict frames; main-window edge pixels clean (sampled). The ring half is now ruled (G-039). |
| 3 | Source row names the source | **DONE** | `Source  ▢ Daily routine` in item 5's frame. |
| 4 | Title beats time; text confined | **DONE** | `Gym` whole in main Week and Routines; at 780pt no text crosses a divider; `Morning revie` is §3.3's `.titleOnly` clip (G-043). |
| 5 | Window treatments clipped | **DONE** | Hatch stops at Friday's trailing divider in every main and Routines frame. |
| 6 | Window label placement | **DONE to its text; text corrected** | Blocks mode: `Low energy` in Tuesday, clear of `Errands`. Windows mode: drawn above `Errands` as the 2026-10-05 sentence said, with the block's border through the word. The sentence was wrong (G-044) → SF2. |
| 7 | Inactive columns under Increase Contrast | **DONE (test only)** | No IC frame was asked for; `HourLineColorsTests` covers the resolver. Spec unchanged. |
| 8 | Weekday toggle row | **DONE** | Row under its label, `M T W T F S S` unclipped, M/W/F filled, in every Routines frame. Focused-toggle stroke not captured (not asked). |
| 9 | Rail sample as template image | **DONE** | `routine-refusal-errands-p2f20.png`: samples in title colour, white in the selected `Shiftable` segment; `± 90 min`. |
| 10 | Spoken strings | **DONE (test + live AX)** | Not frame-visible. `SpokenStringsTests`; STATUS §61's live AX read `14 conflicts` and the `Late lab session` phrase. |
| 11 | Detachment rejoin | **DONE (test only)** | Engine; `RejoinTests`. |
| 12 | Marker cleanup | **DONE** | No behaviour; no `SPEC-GAP` marker left (STATUS §68). |
| 13 | Selected option row | **DONE** | Tinted card + 2pt accent border, text in normal colours, in items 6, 7, 16, 17, 18. |
| 14 | Chip on line 3 | **DONE** | `Recommended` below line 2 in all panels; `Shift Errands 30 min later in / the routine` on two whole lines; `Remove Errands from this routine` on one. |
| 15 | Activation focuses + brings into view | **DONE** | Row 2 focused on entry (item 7); single option focused (item 17); recommendation focused in the Routines panel; every conflict wholly in view. |
| 16 | `1 of N` footer | **DONE** | Footer in both panels; frames reached by stepping (INDEX method). |
| 17 | Re-sync popover as system popover | **PARTLY** | Whole, arrow on the button, `Wed 7 · Fri 9 · Mon 12`, default button. But `⎋` does not dismiss it (B34) → **Blocker B2**. |
| 18 | Popover `Open` / keyboard / `Re-offer` | **DONE** | `Open` enabled in every render and live; `Re-offer` leading and prominent. With the popover's root ring now barred, NEXT needs its own focus indicator → SF1. |
| 19 | Live captures | **DONE** | Status item in menu-bar tint, one string, no glyph, only as wide as its text; popover live with `Open` enabled and `+2 more`. |
| 20 | Recapture and re-index | **DONE** | All live items recaptured from `8531c18`/`827a254`; subjects in view; selection only where asked. Two INDEX wording errors (780pt "scrolls horizontally"; see SF6) and 17 stale `-p2t48` files left (R6). |

Score: 18 DONE (three of them test-only by nature), 1 DONE with its spec text
corrected (6), 1 PARTLY (17).

### R2. Per-item table — components.md §17 items 1–18

| # | File(s) | Verdict | Spec § | Note |
|---|---|---|---|---|
| 1 | `routine-template-flexibility-p2f20.png` | **ACCEPT WITH NOTE** | §2.3, §13.2, §17.1 item 1 | `Gym` (inset rail, shiftable), `Morning review` (solid, fixed), `Reading` (dotted, droppable) in one frame, verified by zoom; nothing selected. Notes: window-edge accent line (B35 → SF1); gutter unpainted under `Lunch`/`Sleep` (B22 → SF3). Neither is the item's subject. |
| 2 | `inactive-weekdays-windows-mode-p2f20.png` | **ACCEPT WITH NOTE** | §7, §13.3 | Protected value step (`Sleep`, `Lunch`), low-energy hatch (Mon–Fri, stops at Friday), peak-focus dashed outline (`Deep work` 15:00–17:00) — all three distinct. Note: `Low energy` crossed by `Errands`' border (G-044 → SF2); gutter (SF3). |
| 3 | `inactive-weekdays-wide-p2f20.png` + item 14's frame | **ACCEPT** | §13.3 | Windows at full strength in Blocks mode; blocks at the inactive layer in Windows mode. |
| 4 | `resync-popover-p2f20.png` | **ACCEPT WITH NOTE** | §13.4 | Subject as specified, whole. The `⎋` defect is behaviour, not in the frame → Blocker B2. |
| 5 | `detached-instance-inspector-p2f20.png` | **ACCEPT** | §13.4, layouts §6 | Mon 12 `Morning review` at 08:30, selected; `Edited — differs from Daily routine`, `Revert to routine`; `Source  Daily routine`; labels whole. |
| 6 | `conflict-panel-two-options-p2f20.png`, `conflict-panel-three-options-p2f20.png` | **ACCEPT WITH NOTE** | §14.2, §14.3, §14.3.4, layouts §10 | Copy exact in both (`60 min → 40 min · 20 min lost`; rows 60 · 75 · 90). Note: in the two-option frame Wednesday's `Training` is drawn with no title — §3.3's covered-block rule as written (G-048, deferred). |
| 7 | `conflict-panel-three-options-p2f20.png` | **ACCEPT** | §14.3.3, interactions §10.1 | Row 2 recommended, focused, previewed on entry. |
| 8 | `conflict-panel-three-options-p2f20.png`, `template-conflict-panel-p2f20.png` | **ACCEPT** | §6 previewed, §14.4, §14.6 | Main: ghost at 17:00, dashed twin 18:15–19:45, canvas border. Routines: ghosts at 12:30 and dashed twins at 13:00 in Mon/Wed/Fri, canvas border. |
| 9 | `needs-attention-count-{0,1,12}.png` | **ACCEPT WITH NOTE** | §10.2 | Unchanged since 2026-10-05's verdict; the live `14` is in every current main frame. |
| 10 | `status-item-*-p2t47.png` (7 renders) + `status-item-live-p2f20.png` | **ACCEPT** | §15.1, §17.2 rule 3 | Live: `12:30 · Stand-up`, template white on the dark bar, no glyph, tight width. |
| 11 | `popover-{normal,late,empty,overflow}-p2f20.png` + `popover-live-p2f20.png` | **ACCEPT WITH NOTE** | §15.2, interactions §12 | All four states right; `Open` enabled; `Re-offer` prominent. Note: the live popover has a ~1px accent line on its edge (sampled `#8DBBFB`), the same root focus ring as B35 → SF1. |
| 12 | `snooze-{same-day,next-day}-p2t48.png` | **ACCEPT WITH NOTE** | §16 | The surface is right in both. But the next-day frame depicts a write into `Sleep` → Blocker B1, which also adds a refused-row render and replaces the next-day render (§17.1 item 12). |
| 13 | `inactive-weekdays-{wide,780}-p2f20.png` | **ACCEPT WITH NOTE** | §13.5.2, §13.5.3, layouts §8 | Notes `Not in this routine` + `Add Tue`… in Tue/Thu/Sat/Sun (wide), Tue/Thu (780) and fit; green underlines on Mon/Wed/Fri; nothing selected. Note: at 780 the editor inspector's overlay is open over Fri–Sun, and INDEX calls this horizontal scrolling — it isn't (104pt columns). Whether the overlay opens by itself → SF6. |
| 14 | `inactive-weekdays-windows-mode-p2f20.png` | **ACCEPT WITH NOTE** | §13.5.5, §7 | No notes, no underlines, no reweighting; toggles whole. Notes as item 2. Recaptured after SF1–SF4. |
| 15 | `routine-refusal-errands-p2f20.png` | **ACCEPT WITH NOTE** | §13.6.2 | `Errands` conflicted in Mon/Wed/Fri only; `Will not run — inside Lunch (protected) on Mon, Wed, Fri`. Notes: gutter, edge line. |
| 16 | `template-conflict-panel-p2f20.png` | **ACCEPT** | §14.2, §14.6, layouts §8.1 | Window row, `lands in`, `Lunch protected · 12:00–13:00`, `12:30–13:00 · 30 min · Mon, Wed, Fri`; 30 · 30 · 135; row 1 recommended, chip on line 3; `14 of 14`. |
| 17 | `conflict-single-option-p2f20.png` | **ACCEPT WITH NOTE** | §14.3.3 | One row, no chip, focused and previewed; `17:00–18:30 · 90 min overlap`; `2 of 14`. Note: the conflict's `Supervisor meeting` has no title on the grid (G-048, deferred). |
| 18 | `conflict-skip-today-preview-p2f20.png` | **ACCEPT WITH NOTE** | §14.4 | Ghost dimmed in place, no dashed twin, canvas border, skip row focused, chip stays on row 2. Note: the ghost sits under `Supervisor meeting` and reads untitled (G-048). |

**18 of 18 accepted** (6 ACCEPT, 12 ACCEPT WITH NOTE, 0 REJECT). No note requires
a recapture before acceptance except item 14 (after SF1–SF4) and item 12 (after B1).

### R3. Rulings, with § references

| Open item | Ruling | Where | GAPS |
|---|---|---|---|
| G-039 / B21 + B35 | **Absent**, both windows and both popovers: no region or window-root focus ring. Focus is drawn on the element (normative table: time cursor / selected ring, focused option card, toggle inset stroke, control rings, popover `hoverOverlay` — NEXT included). A drawn ring rejected: it would duplicate §14.4's preview border with the opposite meaning. B21 is the spec; B35 and the popover edge line are to remove. | interactions §1, §12; layouts §6, §8, §8.1, §9 | G-039 CLOSED |
| B34 | `⎋` dismisses the Re-sync popover wherever focus is inside it, writes nothing, returns focus to `Re-sync`. | components §13.4 | G-040 opened + CLOSED |
| B22 | Routines canvas paints protected/low-energy treatments into the gutter (§7 rule 2); peak-focus outline does not; labels never. | layouts §8; components §7 | G-041 opened + CLOSED |
| layouts §3.1 "first event" | Earliest **time of day** among timed events starting on a visible day; all-day and previous-day carry-overs excluded. Both readings give 06:00 today. | layouts §3.1 | G-042 opened + CLOSED |
| `Morning revie` | Correct: §3.3 `.titleOnly`, no ellipsis. No change. | components §3.3 | G-043 opened + CLOSED |
| Windows-mode label over `Errands` | The coding agent read §7 rule 2 correctly; the sentence was wrong. Corrected: same column scan as Blocks mode, drawn above, never omitted. | components §7 rule 2 | G-044 opened + CLOSED |
| Evening conflict and one third | Clamp accepted and written: one third is the aim, wholly-in-view is the requirement. | interactions §10.1 | G-045 opened + CLOSED |
| A33, A34 | Stay deferred. Nothing in the frames depends on either. | DECISIONS 2026-10-05 | — |
| **Found:** snooze into protected time | A snooze whose destination strictly overlaps a `.protected` span writes nothing; `Not moved — 00:05 is inside Sleep (protected)`, no `Undo`. G-016 stays open for the destination rule. | components §16, §17 item 12, §17.1 item 12 | G-046 opened + CLOSED |
| **Found:** Routines opens at 00:00 | §3.1's rule over the template's blocks, held, re-applied on template change only → 06:00. | layouts §8 | G-047 opened + CLOSED |
| **Found:** covered block loses its title | Visible width measured over the title band; ≥ 44pt there draws `.titleOnly`. **Deferred** (A35). | components §3.3 | G-048 opened, OPEN (deferred) |
| **Found:** §13.4 base still says `this week` | Struck by a dated correction; layouts §8.1 and the build already agree. | components §13.4 | — |

**tokens.json is unchanged** (still 1.2.0, 2026-10-05). No ruling introduced a new
value: every colour, size and radius used above (`hoverOverlay`, `radius.card`,
`popoverRow`, `text.primary`, `blockCascadeMinReadableWidth`, `blockTitleCompact`)
already exists, and no new colour pair is drawn.

### R4. Triage

#### BLOCKERS (2)

**B1 — A snooze never lands in protected time.** CONTEXT.md hard rule; components
§16 (2026-10-06), §17.1 item 12; G-046.
- *Build:* in `EventStore.snooze`, before writing, test the shifted interval
  against `.protected` spans on its day(s) with §13.6.1's strict-overlap test
  (`spans(on:)`, so overnight windows count on both days). Overlap → no write, no
  undo step, a refused result carrying the destination start and the window's
  label. The result row draws `Not moved — HH:mm is inside <Label> (protected)` /
  `inside a protected window`, no `Undo`, same height and hold.
- *Acceptance:* tests — an event at 23:50 snoozed with `Sleep` present: store
  unchanged, undo stack unchanged, result `.refused(00:05, "Sleep")`, row text
  exact; Mon 11:50 against `Lunch`: refused; an event at 17:30 with nothing
  protected after it: moved to 17:45 (existing behaviour); empty label → `inside
  a protected window`; `⌥⌘↩` takes the same path as the button.
- *Recapture:* item 12 — `snooze-next-day-<suffix>.png` (no time windows) and
  `snooze-refused-<suffix>.png` (with `Sleep`), per §17.1 item 12's table; then
  delete `snooze-next-day-p2t48.png`.

**B2 — `⎋` closes the Re-sync popover.** components §13.4 (2026-10-06); G-040;
DEVIATIONS B34.
- *Acceptance:* a test or scripted check: open the popover, send `⎋` (guarded,
  `kadence-guard`) with focus on the default button — popover gone, store
  unchanged (`3 instances edited` still shown), focus on `Re-sync`; repeat after
  clicking inside the popover's date list. `↩` still re-syncs. Add the `⎋` step to
  `check-routines-window.sh` (or a new check) so it cannot regress, and drop
  `capture-p2f20.sh`'s click-to-close workaround.
- *Recapture:* none.

#### SMALL FIXES (7) — one short final run

**SF1 — No region or window-root focus ring; NEXT shows focus.** interactions §1
("Where focus is drawn"), §12; layouts §8, §9; G-039; DEVIATIONS B35.
- *Acceptance:* sampled edge check — in a Routines window capture (both modes) and
  in a menu-bar popover capture, no pixel in the outermost 2px band matches
  `interactive.accent`/`focusRing` (the `#80B3FA` / `#8DBBFB` lines are gone); the
  main window stays clean. Popover key model: on open, focus index 0 → the
  `hoverOverlay` is drawn behind NEXT at `radius.card` (render test with NEXT
  focused). A `⇥` walk through every region of both windows (AX or by eye) finds
  the §1-table indicator in each; any region that shows none is fixed in this
  task (most likely the main inspector in normal mode: `⇥` must land on its first
  focusable control).
- *Recapture:* item 14 (with SF2–SF4) and `popover-live-<suffix>.png`. The live
  popover may again need room made on the menu bar (Parsa's hand); if that isn't
  available, a `screencapture -l` of the popover's own window opened from the
  status item is acceptable for this edge check only.

**SF2 — Windows-mode window labels avoid blocks, never omitted.** components §7
rule 2 (corrected 2026-10-06); G-044.
- *Acceptance:* `WindowLabelPlacementTests` — Windows mode, `Low energy` with
  `Errands` in Monday → Tuesday; Windows mode with every spanned column covered →
  leading column, drawn (not omitted); Blocks mode unchanged (still omitted when
  all covered).
- *Recapture:* item 14 — `Low energy` in Tuesday, uncrossed.

**SF3 — Routines gutter carries window treatments.** layouts §8 (2026-10-06);
components §7 rule 2; G-041; DEVIATIONS B22.
- *Acceptance:* a render test of the Routines canvas's gutter strip: protected fill
  at `Lunch`'s and `Sleep`'s heights, hatch at `Low energy`'s, nothing at `Deep
  work`'s (peak focus); no label in the gutter.
- *Recapture:* item 14 (shows all three).

**SF4 — Routines window default scroll.** layouts §8 (2026-10-06); G-047.
- *Acceptance:* pure test — `Daily routine` → 06:00; a template with no blocks →
  07:00; first block 05:30 → 04:30; held through the window's settling passes
  (the §3.1 hold); re-applied on template change, not on Blocks/Windows switch or
  after an edit.
- *Recapture:* item 14 opens at 06:00 by itself (the capture script must not
  scroll it).

**SF5 — Week view's first event is a time of day.** layouts §3.1 (2026-10-06);
G-042.
- *Acceptance:* `InitialScrollTests` — Tue first event 08:00 and Thu 05:30 →
  04:30 (built today: 07:00); an event 23:50–01:20 the previous day doesn't count
  for the next day; all-day ignored; Day view unchanged.
- *Recapture:* none (06:00 with today's fixtures either way).

**SF6 — The 780pt Routines frame: check the overlay and correct INDEX.** layouts §8,
§1.1 (via §8's collapse order).
- *Acceptance:* open the Routines window at 780pt on a fresh state: the editor
  inspector is collapsed (overlay only after the user opens it). If the build
  opens it by itself, fix it here. Correct INDEX Batch 10's "the canvas scrolls
  horizontally at this width" (it doesn't).
- *Recapture:* item 13's 780 frame **only if** the build changed (then nothing
  covers Sat/Sun and all four notes show).

**SF7 — Housekeeping.** Delete the 15 superseded files in R6 (and the three
2026-09-27 status-item crops); `snooze-next-day-p2t48.png` after B1's render
exists. INDEX: retire them, map item 12 to the new renders, item 14 / 11-live to
their recaptures. DEVIATIONS: B21 → resolved by spec ruling (G-039); B22, B34, B35
→ resolved by their fixes; log **A35** (G-048) as deferred; log B1's defect as a
B-entry resolved by its fix.

#### DEFERRED (3) — still normative

- **A33** — §16's block-move transition in an open main window at the moment of a
  popover snooze (interactions §12, 2026-10-05). Unchanged.
- **A34** — §7's scrolled-past window-label pinning. Unchanged; SF4 makes the
  Routines window open below `Sleep`'s 00:00 edge, which makes the unpinned label
  slightly more visible as missing, not less correct.
- **A35 (new; G-048)** — a covered block's title band (components §3.3, amended
  2026-10-06). Changes cascade rendering in every view; needs its own captures;
  no Phase 2 definition-of-done item depends on it.

### R5. GAPS closed and opened this pass

Recorded in GAPS.md under "2026-10-06 — Phase 2 re-review: gaps opened and closed".

- **Closed:** G-039.
- **Opened and closed in the same pass:** G-040, G-041, G-042, G-043, G-044, G-045,
  G-046, G-047.
- **Opened, left open (deferred):** G-048.
- **Still open, unchanged:** G-016 (snooze destination, Phase 4), G-003 (contrast
  checker).

### R6. Stale frames in screenshots/2/

**Superseded by Batch 10 and safe to delete now (15):**

- `conflict-panel-three-options-p2t48.png`
- `conflict-single-option-p2t48.png`
- `conflict-skip-today-preview-p2t48.png`
- `detached-instance-inspector-p2t48.png`
- `inactive-weekdays-780-p2t48.png`
- `inactive-weekdays-wide-p2t48.png`
- `inactive-weekdays-windows-mode-p2t48.png`
- `popover-empty-p2t48.png`
- `popover-late-p2t48.png`
- `popover-normal-p2t48.png`
- `popover-overflow-p2t48.png`
- `resync-popover-p2t48.png`
- `routine-refusal-errands-p2t48.png`
- `template-conflict-panel-p2t48.png`
- `template-conflict-preview-p2t48.png` (item 8's Routines half is now
  `template-conflict-panel-p2f20.png`, which shows the ghosts, twins and border)

**Must stay:**

- `snooze-same-day-p2t48.png` — the current, accepted evidence for item 12's
  same-day row (§17.1 item 12).
- `snooze-next-day-p2t48.png` — current evidence until B1's two new renders are
  filed; delete it then.

**Not `-p2t48`, also safe to delete:** `status-item-normal.png`,
`status-item-late.png`, `status-item-empty.png` (2026-09-27 live crops, batch 7)
— superseded by the seven `-p2t47` renders and `status-item-live-p2f20.png`, and
they predate P2-T47's one-string label. INDEX maps no item to them.

### R7. Proposed DECISIONS.md entries (text only — yours to write)

**2026-10-06 — No region focus rings; focus is drawn on the element.** macOS 26
draws a region's system ring around a hosting rect that reaches the window's
edge, so it showed as one accent edge in the main window and as a hairline round
the Routines window and the menu-bar popover. A drawn ring was rejected: around
the canvas it would be the same accent frame as the preview border, which means
"you are looking at a hypothetical". Every region already shows focus on the
element: the time cursor or selection ring, the focused option card, the toggle's
inset stroke, a control's own ring, the popover's hover overlay (NEXT included).
That table is normative; a focused region that shows none of these is a defect.
Closes G-039.

**2026-10-06 — A snooze never lands in protected time.** The user asks for later,
not for where, so the destination is chosen automatically and the hard rule
applies. The +15 placeholder gains the same refusal materialisation has, not a
search: if the destination strictly overlaps a protected span, nothing is written
and the popover says `Not moved — 00:05 is inside Sleep (protected)`. Phase 4's
real rule replaces the +15 and must keep this guarantee. Closes G-046; G-016 stays
open.

**2026-10-06 — A window label is never crossed by a block, in either mode.**
Windows mode drew labels above the dimmed blocks wherever the window started,
which put `Errands`' border through `Low energy`. Above is not the same as
legible. Both modes now use the same column scan; Windows mode differs only in
never omitting a label, because there the windows are what is being edited.
Closes G-044.

**2026-10-06 — The default scroll is a time of day, and the Routines window has
one.** `firstEventStart` is the earliest start time-of-day of any event that
starts on a visible day: the scroll offset is shared by every column, so the
question is how early anything in view begins. The Routines window applies the
same rule to its template's blocks and stops opening on seven hours of Sleep.
Closes G-042, G-047.

**2026-10-06 — Deferred out of Phase 2, still normative: a covered block's title
band.** A block covered from below its title row keeps its title (title band ≥
44pt visible → `.titleOnly` content set in that band). It changes cascade
rendering in every view and needs its own captures; no Phase 2
definition-of-done item depends on it. Logged as A35 (G-048). A33 and A34 stay
deferred.

### For Parsa — decisions that are yours

1. **Is a snooze automatic placement?** B1 depends on reading CONTEXT.md's "never
   scheduled into automatically" as covering a destination the user didn't pick.
   I think it does (the 2026-10-01 materialisation ruling makes the same cut). If
   you rule that pressing Snooze is the user being explicit, B1 drops out, §16's
   2026-10-06 amendment and G-046 should be withdrawn, and the next-day frame
   stands.
2. **Is B34 a blocker?** By your definition it is (wrong behaviour plus a keyboard
   exit missing from a destructive confirmation). ⌘Z does undo a mistaken
   Re-sync in one step, so if you weigh that recovery as enough, it becomes a
   small fix.
3. **Acceptance without another full review.** If both blockers stay blockers, I
   propose Phase 2 is accepted when the final run's report shows: B1's and B2's
   tests passing, SF1–SF6's named tests, the item 14 recapture, the two snooze
   renders, the popover edge check, and the R6 deletions. I'd check only those
   frames and tests, not all 18 items again. CONTEXT.md says a phase isn't done
   until I've reviewed its screenshots, so whether that narrower check is enough
   is your call.
4. **The live popover recapture (SF1)** may need you to make room on the menu bar
   again, as in P2-F19.
5. **Deleting the stale frames** (R6) is a `git rm` the final run does and you
   commit.
