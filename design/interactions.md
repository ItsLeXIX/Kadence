# Kadence — interactions (Phase 1)

Scope: the main window and the three calendar canvases. The app must be fully
usable without the mouse. Anything reachable by pointer is reachable by keyboard;
where the two differ, the keyboard path is specified first.

---

## 1. Focus model

Four focus regions, cycled with `⇥` / `⇧⇥`, in this order:

1. Sidebar
2. All-day row (skipped when hidden)
3. Hour grid / month grid
4. Inspector (skipped when collapsed) → wraps to 1

**Amended 2026-09-10: the toolbar is not a focus stop.** The original list opened
with it and then miscounted its own regions as four. SwiftUI toolbar items are
not addressable as a focus region without inserting a phantom item, and macOS
already reaches the toolbar through Full Keyboard Access — which is the route a
keyboard user expects for window chrome. Every toolbar action also has a key
equivalent and a menu item (§2), so nothing is unreachable. The omission is
deliberate and a test asserts it, so it cannot decay into an oversight.

~~The focused region draws the standard system focus ring on its container.~~
**Superseded 2026-10-06 (Phase 2 re-review; closes G-039, rules DEVIATIONS B21
and B35) — see "Where focus is drawn" below.** Within a region, `↑` `↓` `←` `→`
move focus between its items; `⇥` always leaves the region rather than moving
inside it.

**Where focus is drawn (amended 2026-10-06).** **No region draws a region-level
focus ring** — not the hour grid, not the all-day row, not the inspector, not the
Routines window's canvas or editor inspector, not either popover's root. On
macOS 26 the system ring is drawn around a region's hosting rect, and every one
of those rects reaches a window edge: the 2026-10-05 main-window frames showed
it as one accent edge at the canvas/inspector boundary, and every 2026-10-06
Routines frame and the live menu-bar popover show it as a ~1px accent line on
the window's outer edges. A drawn replacement was considered and rejected: an
accent rectangle around the canvas is already `components.md` §14.4's preview
border ("you are looking at a hypothetical"), and the two would follow each
other in the same place with opposite meanings — `⇥` out of the conflict panel
abandons the preview (§10.2) and would swap one accent frame for an identical
one that means something else.

Focus is shown **on the element that has it**, which every region already has.
This is normative — a region that takes focus and shows none of these is a
defect, not an allowed state:

| Region | What shows focus |
|---|---|
| Sidebar | The system's focused-selection treatment of the source list (as built) |
| Hour grid (main window and Routines canvas) | Cursor mode's time cursor and its gutter time, or selection mode's §6 selected ring. Focus entering the grid with nothing selected enters cursor mode, so the cursor is always drawn |
| All-day row | The focused pill takes §6's selected ring |
| Inspector, normal mode | `⇥` in focuses its first control that accepts key focus, which draws its own system control ring |
| Conflict panel (both windows) | The focused option row's `selectedCardFill` + 2pt `focusRing` border (`components.md` §14.3) |
| Routines editor inspector | The weekday toggle row's inset stroke (`layouts.md` §8.1); the flexibility control's own system control ring |
| Menu bar popover | `color.interactive.hoverOverlay` behind the focused row — NEXT included (§12) |
| Re-sync popover | Its one button is the default button; `↩`/`⎋` are its whole keyboard surface (`components.md` §13.4) |

Control-level rings (a text field's, a segmented control's) are untouched; this
rule removes only rings drawn around a region or a window's root view.

The grid is a single focus target. Inside it there are two focus modes:

- **Selection mode** — a block is selected. Arrows move between blocks.
- **Cursor mode** — nothing is selected. A **time cursor** is shown: a 1pt line
  in `color.interactive.accent` across the focused day column, with its time
  printed in the gutter in `hourLabel` / `color.interactive.accent`. Arrows move
  the cursor. This is what makes keyboard-only event creation possible.

`⎋` moves selection mode → cursor mode → unfocused grid.

**Amended 2026-10-07 (Phase 2 closeout; G-050) — the Routines canvas's cursor
mode, minimum form.** The table above says the Routines canvas shows focus by
its time cursor, and that a focused region showing nothing is a defect; no task
built that cursor (DEVIATIONS A36), so `⇥` onto the canvas with nothing selected
showed nothing. Deferring it would leave a defect by this section's own rule, so
the minimum is specified here and is in Phase 2. It is an **indicator**, not a
creation path:

- **Drawn:** the main grid's time cursor — 1pt `color.interactive.accent` — as
  **one line across all seven day columns** (not the gutter), at the cursor's
  time, with that time printed in the gutter in `hourLabel` /
  `color.interactive.accent`, suppressing a colliding hour label by
  `components.md` §7's 12pt rule. All seven, in both Blocks and Windows mode: a
  template time is a time of day, not a day column, and the window has no focused
  day (§11.1). The line paints above blocks and window treatments, like the now
  line, and is transparent to hit-testing (§6.1).
- **On entry** (focus arrives on the canvas with nothing selected, by `⇥` or by
  `⎋` from selection mode): the cursor takes the last cursor time of this window
  session if that time is in the viewport; otherwise the **first whole hour
  strictly below the viewport's top edge** — 07:00 at the default 06:00 scroll
  (`layouts.md` §8). An empty-canvas click deselects and places the cursor at the
  clicked slot's time, as in the main grid (§6.1 step 4) — including on an
  inactive column, where the click still creates nothing (§11.1).
- **Keys:** `↑` `↓` move it 15 minutes, clamped to 00:00…23:45, scrolling the
  canvas only as far as needed to keep the line in view. `←` `→` do nothing
  (§11.1). `⎋` leaves the canvas unfocused. `⇞` `⇟` scroll as in the main grid
  and do not move the cursor. Selecting a block (click) leaves cursor mode;
  dropping the selection on a Blocks/Windows switch (§11.1) enters it if the
  canvas has focus.
- **Not in Phase 2:** `↩`, typing, and `⌘N` create nothing at the cursor here —
  keyboard creation of a template block (which weekdays, which mode) is
  unspecified and no Phase 2 item needs it; whatever those keys do in the
  Routines window as built is unchanged.
- **Accessibility:** the canvas's value in cursor mode is the cursor's time,
  `07:00`.

This resolves DEVIATIONS A36 once built.

---

## 2. Shortcuts

| Keys | Action | Scope |
|---|---|---|
| `⌘1` `⌘2` `⌘3` | Month / Week / Day | global |
| `⌘T` | Today | global |
| `T` | Today | grid focused, no text editing |
| `←` `→` | Page back / forward one unit (month, week, day) | grid focused, cursor mode |
| `⌘N` | New event at the time cursor, else at the next half hour | global |
| `↩` | Open the selection in the inspector and focus its title field | selection mode |
| `⌫` | Delete the selection — **Edit ▸ Delete** *(menu item required 2026-10-10, A38)* | selection mode |
| `⌘↩` | Toggle done | selection mode |
| `⌥⌘↩` | Toggle skipped | selection mode |
| `⌥↑` `⌥↓` | Move the selection by 15 minutes | selection mode |
| `⌥←` `⌥→` | Move the selection by one day | selection mode |
| `⌥⇧↑` `⌥⇧↓` | Change the selection's end time by 15 minutes | selection mode |
| `↑` `↓` | Previous / next block in the column | selection mode |
| `↑` `↓` | Move the time cursor by 15 minutes | cursor mode |
| `←` `→` | Previous / next day column | selection mode (Week, Month) |
| `⇞` `⇟` | Scroll the grid by one viewport | grid focused |
| `↖` `↘` | First / last block of the day | selection mode |
| `⎋` | Deselect, or cancel an in-flight drag or inline edit | grid focused |
| `⌃⌘S` | Toggle sidebar | global |
| `⌥⌘I` | Toggle inspector | global |
| `⌘Z` `⇧⌘Z` | Undo / redo | global |
| `⌘,` | Settings | global |
| `⌘⌥R` | Routines window | global |
| `⌘⇧A` | Go to the first unresolved conflict | global, when the count is non-zero |
| `↑` `↓` | Move between conflict options | conflict panel focused |
| `↩` | Apply the focused option | conflict panel focused |
| `⎋` | Abandon the pending preview | conflict panel focused |
| `‹` `›` / `⌥←` `⌥→` | Previous / next unresolved conflict | conflict panel focused |
| `⌘⌥N` | New all-day event on the focused day. *Never built (DEVIATIONS A37); deferred out of Phase 3 slice 1 on 2026-10-10, still normative — it belongs with the next task that touches event creation. All-day events are drawn since `components.md` §5.1.* | grid focused |
| `⌘R` | **Sync Now** — every connected source (View ▸ Sync Now). *Added 2026-10-08, §13.3* | global |

Every one of these is also a menu bar item, with the same key equivalent, so the
shortcut set is discoverable without documentation.

*(Added 2026-10-10.)* **Edit ▸ Delete** (`⌫`) did not exist: `⌫` was handled
by the grid alone, and until Phase 3 did not work at all (DEVIATIONS B44). The
item is added to the Edit menu, below the system's pasteboard group. It is
enabled when a deletable event is selected in the main window's grid, deletes
it exactly as `⌫` does (one undo step), and is **disabled** when nothing is
selected or the selection is an imported event (§13.4).

---

## 3. Creating

| Path | Behaviour |
|---|---|
| `⌘N` | Creates a 60-minute event at the time cursor. With no cursor, at the next half hour on the visible day. |
| Double-click empty grid | Creates a 60-minute event starting at the snapped slot under the pointer. |
| Drag on empty grid | Creates an event of the dragged duration, minimum 15 minutes. |
| Double-click a month cell | Creates a 60-minute event at 09:00 on that day. |

A new event appears immediately as a block in `.fixedTimed` / `.manual` style
with an inline `TextField` in place of its title, using `blockTitle`. `↩` commits;
`⎋` cancels and removes the block entirely. The block is selected on commit.

An event created with no title is never persisted — cancelling and committing an
empty field both remove it.

---

## 4. Moving and resizing

Snapping: 15 minutes by default. Hold `⌃` during a drag for 5-minute snapping.
Hold `⇧` to constrain to the same day (vertical movement only). `⌥`-drag
duplicates rather than moves, per macOS convention.

Resize handles are `size.blockResizeHandleHeight` tall at the top and bottom
edges, revealed on hover. The top handle moves the start; the bottom handle moves
the end. Minimum resulting duration 15 minutes; the drag clamps rather than
inverting.

**Drop preview.** A 1pt dashed outline, dash `[3, 3]`, in
`color.interactive.accent`, drawn at the snapped destination frame, plus a time
badge that follows the pointer showing the resulting range in `blockMeta` on
`color.surface.popover` at `elevation.level2`. The block's origin slot stays
visible at `opacity.blockDragOrigin` so the user can see what they are leaving.

**Blocks that cannot be moved.** `origin == .imported` and any block with
`isLocked` do not drag. The cursor becomes `.operationNotAllowed` and the
inspector shows a one-line explanation. No alert, no shake, no dialog.

**Dropping into a protected window is allowed.** The user is being explicit, and
the rule in `CONTEXT.md` binds automatic placement, not manual action. The drop
preview's outline turns `color.semantic.alert` while over a protected window, and
the resulting block takes `.conflicted` presentation. The user sees the cost;
they are not blocked from paying it.

---

## 5. Deleting

`⌫` deletes immediately. No confirmation sheet. The vacated slot holds a 1pt
dashed outline in `color.separator.strong` for `motion.outlineHold` so the user
sees what was removed and where. `⌘Z` restores it with its original selection.

---

## 6. Selection

Single selection only in Phase 1. Clicking a block selects it; clicking empty
grid deselects and places the time cursor at the clicked slot. Clicking a travel
band selects its parent event (`components.md` §4).

Selection survives view changes: switching Week → Day keeps the same block
selected and scrolls it into view. Selection survives paging only if the block is
still in range; otherwise the grid falls back to cursor mode at the same time of
day.

### 6.1 Hit resolution — paint order is hit order

*Added 2026-09-11 (GAPS.md G-010).* The rule above is complete for a click that
lands on exactly one block. Blocks overlap — in cascade by design, and at the
edges of the density floor by arithmetic — so a click point can be inside more
than one hit region. One rule settles it, and it is the rule the user can check
with their own eyes: **what is painted on top is what gets selected.**

**The hit order, front to back.** It is exactly the paint order, with one
subtraction:

1. The `+N` cascade chip (`layouts.md` §3.3), which paints above every block in
   its cluster. It is not a block and does not select: it opens that day in Day
   view.
2. Blocks, in the paint order from `layouts.md` §3.3 — the step 2 sort, later on
   top. That sort is a total order (its final key is `id`), so "the frontmost
   block" always names exactly one block.
3. Travel bands, each at its **parent's** index rather than one of its own
   (`components.md` §4). A band's hit region belongs to its parent event: a
   case-2 band lies inside the parent's frame and adds nothing; a case-1 band
   adds its own rect to the parent's hit region. Clicking either selects the
   parent, as §6 already says.
4. Empty grid — deselect, and place the time cursor at the clicked slot.

**Subtracted:** non-interactive layers are transparent to hit-testing and can
never take a click, however high they paint. That is the now line
(`components.md` §8, which paints above every block), the background window
treatments (§7), the hour and half-hour lines, and the time gutter.

**Frontmost wins.** Test the point against hit regions front to back; the first
hit takes the click. This is the behaviour the build already has, so nothing
changes — it is now a decision rather than a side effect of the view hierarchy's
traversal order, and it may not be reordered by a refactor.

**A cascaded block's hit region is its full laid-out frame, not its visible
sliver.** There is no second geometry computed for hit-testing. Combined with
frontmost-wins the two answers coincide anyway: the covered part of the frame
always loses to the block covering it, so the *effective* target is exactly what
is visible — the leading sliver of `indent` points (15pt at the narrowest column,
22pt at any column of 116pt or wider, `layouts.md` §3.3) by the block's full
height. That is a usable pointer target, it is the part of the block that carries
rail and glyph (which is why the indent is sized the way it is), and it is never
the *only* route to a covered block: keyboard focus reaches every block in the
grid regardless of coverage (§1, §2). Computing a visible-region hit shape would
produce the same clicks at more cost and one more thing to keep in sync.

**A real block's frame always beats a hit extension.** Resolve in two passes:

- **Pass 1** tests laid-out **frames** only, front to back.
- **Pass 2** runs only if pass 1 found nothing, and tests the
  `size.blockHitExtension` outsets of floored blocks (`components.md` §3.3),
  front to back.

So the extension can only claim canvas that no block is painted on. It can never
take a click that lands on another block's pixels, in either z-direction. The
extension exists to make a block shorter than `size.blockMinRenderedHeight`
reachable with a pointer, not to win arguments with its neighbours — a click that
selects a block whose ink is nowhere near the pointer is worse than a click that
misses.

**One hit order, not several.** The same order governs hover (the ring and resize
handles in `components.md` §6), the drag grab (§4) and the double-click that
creates (§3). Anything the pointer can address is resolved by the list above.

---

## 7. Motion

Motion is for orientation during view changes. It is not decorative, and there is
no animation in this app that exists to be enjoyed.

| Event | Animation | Token |
|---|---|---|
| Hover in/out | Ring and handle opacity | `motion.hover` |
| Selection change | Focus ring opacity and elevation | `motion.selection` |
| Month ↔ Week ↔ Day | Cross-fade only. No scale, no slide, no zoom-into-the-day metaphor. | `motion.viewChange` |
| Paging `←` `→` | Horizontal slide of canvas content in the direction of travel, over a static gutter and header | `motion.paging` |
| Block moved to a new slot | See §7.1 | `motion.blockMove` |
| Now line tick | Position interpolation each minute | `motion.nowLineTick` |

### 7.1 The block-move transition

This is the one place motion earns its keep, because the whole point of moving a
block is to answer "where did it go?". It runs after a drag-drop, after
`⌥`-arrow nudges of more than one step, and — from Phase 4 — after a snooze.
Same transition in all three cases.

1. The block animates its frame (origin **and** size, since the destination may
   be in a differently-sized column) from the old frame to the new one with
   `motion.blockMove.spring` — `response 0.26`, `dampingFraction 0.86`. No
   overshoot beyond 2% at that damping, which is deliberate: this is a report of
   what happened, not a flourish.
2. During the move the block sits at `elevation.level2`, then settles to
   `elevation.level0` over `motion.blockMove.settle` (0.12s).
3. On arrival, a 1pt outline in `color.interactive.accent` is drawn at the new
   frame and fades out over `motion.outlineHold` (0.60s).
4. If the destination is outside the current viewport, the grid scrolls first so
   that the destination is visible, then runs steps 1–3. The block is never
   animated to somewhere the user cannot see.
5. If the destination is outside the current *date range*, no movement is
   animated. Instead the grid pages to the destination date with `motion.paging`,
   and the block arrives already in place with steps 3 only.

### 7.2 Reduce Motion

| Event | Reduce Motion behaviour |
|---|---|
| View change | Instant swap with a 0.10s opacity fade |
| Paging | Instant swap, no slide |
| Block move | **No movement.** The block cross-fades out of its old slot and into its new one over 0.12s, and the destination outline hold is extended to 0.60s at full strength. The "where did it go" question is answered by the outline, not by the travel. |
| Now line tick | Instant reposition |
| Hover, selection | Unchanged — these are 0.09s state changes, not motion |

No animation in this app is longer than 0.6s, and none blocks input. Every
transition is interruptible: a second drag started mid-animation takes over from
the current presented frame.

---

## 8. Cursors

| Context | Cursor |
|---|---|
| Over empty grid | `.crosshair` |
| Over a draggable block | `.openHand`; `.closedHand` while dragging |
| Over a resize handle | `.resizeUpDown` |
| Over a non-draggable block | `.arrow`; `.operationNotAllowed` on drag attempt |
| Over a region divider | `.resizeLeftRight` |

---

## 9. Undo

Every mutation is undoable through the SwiftData undo manager: create, delete,
move, resize, retitle, done, skipped. Each registers a named action so the Edit
menu reads `Undo Move Event`, not `Undo`. Undo restores the selection state that
was in effect before the action, so `⌘Z` puts the user back where they were, not
just the data back where it was.

---

# Phase 2 — additions

Additions only. §1's focus list and §2's table are amended in place above and
marked; nothing else in §1–§9 changes.

---

## 10. Conflict resolution

### 10.1 Focus and preview

The conflict panel is a focus region reached from the needs-attention row, from
`⌘⇧A`, or by `⇥` into the inspector while it is in conflict mode.

`↑` / `↓` move between options. **Moving focus onto an option previews it
immediately** — there is no separate "preview" verb, because an option the user
cannot see the consequence of is an option they cannot rank. Each affected block
takes the `previewed` presentation (`components.md` §6) and moves to its proposed
frame with `motion.blockMove`; the canvas takes its `size.previewCanvasBorder`
accent border.

Moving to another option reverts the previous one and previews the new one in a
single pass — blocks travel from the old proposal to the new one, never via their
committed position, so the grid never flickers back to reality between two
hypotheticals.

`↩` applies. Applying is a single named undo step (`Undo Resolve Conflict`),
runs the block-move transition on the committed frames, drops the canvas border,
and advances to the next unresolved conflict — or returns the inspector to normal
if that was the last one (`components.md` §14.5).

**Amended 2026-10-01.** Three additions:

- **A single-option conflict is still a focus region.** `↑`/`↓` have nowhere to
  go; focus lands on the one option, which previews immediately like any other,
  and `↩` applies it. It carries no `Recommended` chip (`components.md` §14.3.3).
- **A template conflict (`components.md` §14.6) is reached in the Routines
  window.** Activating it from the needs-attention row — or `⌘⇧A` landing on one —
  opens that window, selects the template and the block, and focuses the editor
  inspector's conflict panel. The preview, `↑`/`↓`, `↩` and `⎋` all behave
  exactly as they do in the main window; the canvas they animate is the Routines
  canvas, and `↩`'s undo step is named `Resolve Routine Conflict`.
- **`⌘⇧A` orders both kinds together**, day conflicts before template conflicts,
  each by the start of what they affect. Two queues would make the count in the
  sidebar mean two different things.

**Amended 2026-10-05 (Phase 2 screenshot review) — what activation does to focus
and to the canvas.**

- **Activation focuses the recommended option** — or the only option of a
  single-option conflict — and so previews it immediately. This applies to the
  needs-attention row, `⌘⇧A`, the footer's `‹`/`›` (`layouts.md` §10), and the
  advance after `↩`. It replaces the build's P2-T45 judgement call (after apply
  the next conflict previews its *top* row): "decisions come with defaults"
  (`BRIEF-DESIGN`) means the default is what is shown first, so a keyboard user
  can read the preview and press `↩` to accept the recommendation without
  hunting for it. When the recommendation is row 1 nothing changes; when it is
  row 2 (§17 item 7), focus lands on row 2. Nothing is written until `↩`, so
  focusing it commits nothing.
- **Activation brings the conflict into view.** If the occurrence's day is not
  in the visible range, the canvas pages to the range containing it (same view,
  never an auto-switch). Then, if the occurrence's frame is not wholly inside the
  viewport, the grid scrolls so the earlier of the two colliding starts sits
  one third from the top of the viewport (`layouts.md` §3.1's Today rule), using
  `motion.paging` (instant under Reduce Motion). A preview the user cannot see
  is not a preview. In the Routines window the same scroll rule applies to the
  template block. Stepping with `‹`/`›` does the same. Abandoning the preview
  (§10.2) does **not** scroll back.
- **Amended 2026-10-06 — near the end of the day the scroll clamps, and that is
  correct.** The grid's content ends at 24:00, so for a conflict late in the day
  (§17's Training at 17:00 in a 900pt window) "one third from the top" asks for an
  offset past the content's end. The grid scrolls as far as it goes and stops; it
  never pads the content, overscrolls, or moves the 24:00 edge. One third is the
  *aim*; the requirement is the sentence above it — the occurrence wholly in view.
  A clamped scroll satisfies that whenever the occurrence is no taller than the
  viewport, because the clamp puts the day's end at the viewport's bottom edge.
  An occurrence taller than the viewport keeps its earlier start at one third,
  and its end may be below the fold. The same holds for 00:00 at the top. The
  decision "is it wholly in view?" is made against the scroll view's real laid-out
  viewport (P2-F24), never a transient geometry report.

### 10.2 Abandonment is unconditional

**A pending preview is abandoned, never persisted, the moment focus leaves the
conflict panel.** Ruled 2026-09-10, and it is the same rule as draft abandonment
(`DECISIONS.md`, "New events are drafts in state, never rows in the store"): if
you wandered off, you did not decide.

Leaving means any of: `⎋`; clicking anywhere on the grid, sidebar or toolbar;
selecting another block; changing view or paging; collapsing the inspector;
closing the window; quitting. All of them revert with `motion.previewRevert`
(0.12s), with no confirmation and no "keep this?" prompt.

Nothing about a pending preview is written to the store, so there is nothing to
restore on relaunch and nothing that can be applied later by accident. That is
the point of the ruling: a surviving preview is a decision waiting to be made by
the next stray keypress.

### 10.3 Previewed blocks are not editable

While a preview is active the previewed blocks cannot be dragged, resized,
deleted, or marked done. They are a picture of a proposal, not objects. Cursor is
`.arrow` over them; a drag attempt abandons the preview (§10.2) and selects the
block at its real position, which is the least surprising thing that can happen.

---

## 11. The Routines window

### 11.1 Editing

Creating, moving and resizing routine blocks uses §3 and §4 unchanged — same
15-minute snap, same `⌃` for 5-minute, same handles, same drop preview. `⌫`
deletes. `⌘Z` undoes, with names (`Undo Move Routine Block`).

`⌘1` / `⌘2` / `⌘3`, `T`, and `←` `→` do nothing here: a template has no dates and
no today. They are disabled rather than repurposed.

*(2026-10-07, G-050.)* With nothing selected and the canvas focused, the canvas
is in §1's cursor mode in its Routines form (§1, amended 2026-10-07): one line
across all seven columns, `↑` `↓` only.

Switching between Blocks and Windows mode: `⌘[` / `⌘]`, or the mode control.
The current selection is dropped on mode change, because a selection you can no
longer edit is a trap.

**Amended 2026-10-01 — what §3 and §4 "unchanged" cannot mean here.** Three
clarifications and one closure. A `RoutineBlock` is a time of day on a set of
weekdays, not an object on a column (`components.md` §13.5), and §3/§4 were written
against an `Event` that sits on exactly one day.

- **A block drag is vertical only.** Horizontal translation is ignored outright.
  A block cannot be moved between columns, active or inactive, because there is
  no per-column instance to move — which is also the complete answer to "what
  happens when you drag a block toward an inactive column": nothing happens
  there, and §13.5.2's treatment is what says why before the user tries.
- **The drop preview appears in every active column at once.** One drag, one
  snapped destination, and a dashed `[3, 3]` `color.interactive.accent` outline
  at that frame in **each** of the template's active columns, with the origin
  ghost at `opacity.blockDragOrigin` in each of them too. No preview is drawn in
  an inactive column. This is the clearest statement the window can make about
  what it is editing, and it costs no new component — it is §4's drop preview,
  drawn more than once. The pointer-following time badge stays single, at the
  pointer.
- **Cross-midnight drags clamp (closes G-013).** A move clamps `startMinutes` to
  `0…(1440 − duration)`; a resize clamps the moved edge to `0…1440` and keeps
  §4's 15-minute minimum. It never wraps to the previous or next column, because
  a block is not on a column, and a template has no "next day". This confirms the
  placeholder `RoutineBlockStore` already shipped; it is now the spec.
- **Gestures on an inactive column are refused** (`components.md` §13.5.1).
  Double-click and create-drag on the empty canvas of an inactive column do
  nothing: no block, no draft, no outline. The cursor over that canvas is
  `.operationNotAllowed`, the same signal §4 already uses for a block that will
  not move. A draft whose column is deactivated mid-edit is abandoned, per
  `DECISIONS.md`'s draft rule — if the surface went away, you did not decide.
  Windows mode is unaffected: there, every column is live (§13.5.5).

### 11.1.1 Weekday activation

No new global shortcut. Two paths, both named undo steps
(`Add Saturday to Routine` / `Remove Saturday from Routine`):

- **Pointer:** the `Add Sat` button in the inactive column's note
  (`components.md` §13.5.3).
- **Keyboard:** the weekday toggle row in the editor inspector with nothing
  selected (`layouts.md` §8.1). It is reached by `⇥` into the inspector;
  `←`/`→` move between the seven toggles and `space` flips the focused one.

Deactivating a weekday deletes that weekday's future, non-detached instances
inside the same undo step (`components.md` §13.6.4). It is not confirmed: nothing
in the template is destroyed, and the step is one `⌘Z`.

### 11.2 Re-sync is one undo step

Re-syncing detached instances (`components.md` §13.4) discards the user's own
edits across several days, so two things are required and neither is optional:

1. **The confirmation names the damage** — the affected dates, listed, not a
   count alone. "Re-sync 3 instances" over a list of `Tue 8`, `Wed 9`, `Fri 11`.
2. **It is a single undo step**, named `Undo Re-sync Routine`, restoring every
   affected instance to its edited state in one `⌘Z`. Ruled 2026-09-10. A
   re-sync that undid one day per press would be worse than no undo at all,
   because the user would stop pressing before they were whole.

If any affected day is visible in the main window when re-sync is applied, the
block-move transition (§7.1) runs there for each restored instance.

**Amended 2026-10-01 — scope, and the single-instance sibling.**

- **Scope** is the detached instances of this template from `startOfDay(today)`
  forward, inside the materialisation horizon (`components.md` §13.6.5). Past
  detached instances are neither counted nor re-synced; nothing in this app
  rewrites the past. The confirmation lists exactly the dates it will write.
- **`Revert to routine`** (`components.md` §13.4, one selected instance in the
  main-grid inspector) does the same write to one instance. Its undo step is
  named `Revert Instance to Routine` — deliberately not `Re-sync Routine`,
  because the Edit menu is the only thing standing between "I undid one day" and
  "I undid a week".
- Re-sync restores the template's **current** values, not the values in force
  when each instance was detached (`components.md` §13.7.2). "Re-sync" means
  "make this match the routine as it is now"; any other reading needs a second
  copy of every template field per instance and still surprises the user.
- Re-sync never resurrects a deleted instance (`components.md` §13.7.4).

---

## 12. The menu bar popover

The popover takes key focus when opened by keyboard and does not when opened by
click, matching standard `NSPopover` behaviour.

| Keys | Action |
|---|---|
| `↑` `↓` | Move between the next item and the rest-of-today rows |
| `↩` | Open the focused item in the main window |
| `⌘↩` | Done |
| `⌥⌘↩` | Snooze |
| `⎋` | Close the popover |

`⌘↩` and `⌥⌘↩` are the same bindings as the main window's `⌘↩` / `⌥⌘↩` for done
and skipped (§2) — the same action gets the same key wherever it appears.

`Done` and `Snooze` do **not** close the popover. Both replace the action row in
place with their result (`components.md` §16), because a surface that vanishes at
the moment it has something to tell you cannot tell you where the block went.

**Amended 2026-10-05 (Phase 2 screenshot review).** P2-T25/T26 built `Done`,
`Snooze`, `Re-offer` and `⌥⌘↩` and logged the rest as out of scope; the review
rules on what Phase 2 needs.

- **Key focus: the popover takes key focus on every open**, click or keyboard.
  The build's blunt rule is adopted and the click-vs-keyboard distinction above
  is withdrawn. A `MenuBarExtra` window cannot reliably tell how it was opened,
  and a popover that holds focus costs a mouse user nothing — `⎋` and clicking
  outside both close it — while one that does not hold it makes every key in
  this table dead.
- **Required for Phase 2:** `Open` (button and `↩` on the NEXT item: activate the
  main window, opening it if closed, page to the item's day and select it),
  `⌘↩` (Done), `⎋` (close), and `↑`/`↓` between NEXT and the rest rows with `↩`
  opening the focused row the same way. The brief's Phase 2 lists "Done / Snooze
  / Open main window", and `BRIEF-DESIGN` asks for an app "fully usable without
  the mouse"; a popover whose only keyboard path is `⌥⌘↩` is neither.
- The focused rest row draws `color.interactive.hoverOverlay` behind its full
  row width at `radius.chip` — the same treatment as a hovered row — so focus is
  visible without a second focus ring inside a popover that already has one.
  **Amended 2026-10-06:** the popover does **not** have one — §1 now bars a ring
  around the popover's root (the live capture `popover-live-p2f20.png` shows it as
  a ~1px accent line on the popover's edge). So the hover-overlay treatment is the
  popover's only focus indicator and it covers **NEXT as well**: while NEXT is
  focused (the state every open starts in), `hoverOverlay` is drawn behind the
  next-item block's full width at `radius.card`, inside the popover's
  `spacing.xl` padding. Same colour, same reason — one focus vocabulary inside
  one surface.
- **Deferred, not required for Phase 2:** `components.md` §16's third bullet
  (running the block-move transition in an open main window at the moment of a
  popover snooze). It needs animation state shared across two scenes, and
  nothing is lost without it: the popover's result row already says where the
  block went, and the main window shows it there on its next render.

### 12.1 Motion in the popover

The status item's text changes without animation — it updates on a timer and any
animation in a menu bar reads as a glitch. The popover's snooze result row
cross-fades over `motion.selection` (0.09s) and holds for
`motion.snoozeConfirmHold` (4s), pausing while the pointer is inside the popover.
Under Reduce Motion the cross-fade becomes an instant swap; the hold is unchanged
because it is a duration, not a motion.


---

# Phase 3 — additions

Written 2026-10-08. §2's table gains `⌘R` (amended in place). Everything below
is new.

---

## 13. Sources

*(Amended 2026-10-08, CalDAV amendment. The source is a CalDAV account: server,
username, password. It is discovered once and read with one `REPORT` per poll.
The default interval is 30 minutes.)*

### 13.1 Connecting

| Step | What happens |
|---|---|
| Entry | Settings ▸ Sources `+`; the sidebar's `Connect Timetable…`; **File ▸ Connect Timetable…** (no key equivalent; the menu item exists so the path is reachable from the keyboard and from Help search) |
| Step 1 `Connect` | Discovery D1–D4, then one `REPORT` with the Import window per listed calendar (`components.md` §20.8.1–§20.8.2). The user sees this as one step. 30 s per request. The outcome maps to `components.md` §19.1 and shows as `layouts.md` §12.1 says. The discovery result and the events are held in the sheet's memory for step 2 |
| Step 2 `Import` | Keychain item → `Source` → the events already fetched from the checked calendars (the Import, `components.md` §20.1). No further request |
| Cancel / `⎋` / closing Settings | Abandons the sheet. Nothing is written, an in-flight request is cancelled, and everything fetched and typed is discarded |

Keys in the sheet: `⇥` / `⇧⇥` move through the fields, the checkboxes (several
calendars only) and the buttons, in reading order. `↩` = the default button
(`Connect`, `Import`, `Save`) when enabled. `⎋` = `Cancel` in both steps, and it
never half-saves. `Back` is a button only.

**The account on the wire.**

- **HTTPS only.** `Server` is normalised to `https://` + host (+ port, + path
  when typed). `http://` is refused before anything is sent (`layouts.md`
  §12.1). Every request goes to that one host, port and scheme.
- **A TLS failure stops before anything is sent** (`certificate`): with an
  untrusted certificate, no request line, credential or body is written. There
  is **no "connect anyway"** in any build.
- **The password is sent only in answer to that host's `401`.**
  - The first request of a connect or sync carries no `Authorization`.
  - When the source's host answers `401` over HTTPS with a `Basic` or `Digest`
    challenge, the credential is supplied for that challenge's protection space
    (host, port, `https`, realm).
  - Within the same connect or sync, later requests may carry it for that same
    protection space. That is still the answer to the host's challenge, and it
    avoids doubling every request.
  - Never pre-emptively at the start of a sync. Never in a URL. Never to another
    host, port or scheme.
  - A second `401` after the credential was sent is `unauthorized`, and that
    request is not retried.
  - Each connect and each sync uses a fresh ephemeral session, so nothing
    carries over between them (`components.md` §21.4).
- **Redirects** — the transport never follows one itself; the client decides:
  - **D1** (`/.well-known/caldav`): a `301`/`302`/`307`/`308` to `https:` on the
    **same host and port** is the context URL. CIS sends `301` →
    `/webdav/lvplan.php/`.
  - **A selected calendar** answering `301`/`308` to the same host has moved:
    re-discovery (`components.md` §20.8.1).
  - **Any other redirect** to the same host is followed once, for `GET` only.
  - **To another host, or to `http:`** — never followed, at any step
    (`redirected`). Following it would hand the request, and the password, to a
    server the user never chose. The refused `Location` is reduced to its host
    before it is shown or logged.
  *(Clarified 2026-10-10.)* "At any step" includes D2–D4 and every fetch
  request: a `3xx` there whose `Location` is another host or `http:` ends in
  `redirected`, not in `noCalDAV` / `fetchFailed`, so the user is told the
  server tried to send them elsewhere. (The build answered `noCalDAV` at
  D2–D4; nothing was sent either way.)
- **Hrefs from the server** are resolved against the request URL. One that
  resolves to another host is ignored and never requested.
- **One request at a time** per source, never parallel (`components.md`
  §20.8.2's cap).
- **No on-disk HTTP state** (ephemeral session, no URL cache, no credential
  storage, cookies in memory for the sync only: `components.md` §21.4).
  **Nothing secret in any log, error or description**: the password is never
  logged, and no header or body is logged at all.

**What the tests must prove (added 2026-10-10; DEVIATIONS B40, accepted in
`components.md` §21.4).** Kadence sets `Authorization` itself, and Foundation
copies manually set headers onto a request it redirects. Two layers stop that —
the transport's delegate refuses every redirect, and `CalDAVSession.send`
refuses any URL that is not the source's host, port and `https` before it is
sent — and each must be proven **through Foundation's real redirect path**,
which the first test set never entered: its `URLProtocol` stub hands a `301`
back as an ordinary response, so `URLSession` never asks the delegate anything
and the "not followed" assertions pass with or without it.

1. **The stub can redirect for real.** `StubURLProtocol` gains a reply that
   calls `client.urlProtocol(_:wasRedirectedTo:redirectResponse:)`, which is
   what makes `URLSession` consult `willPerformHTTPRedirection`. The stub
   records every request it is asked to load, for **any** host and scheme.
2. **Cross-host, with the header on the request.** A session that has already
   been challenged sends a `REPORT` carrying `Authorization`; the stub
   redirects it (`301`, and again with `302`, `307`, `308`) to
   `https://login.example.invalid/…`. Expected: the fetch ends `redirected`
   with `otherHost` `login.example.invalid`; the stub's records contain **no
   request to that host at all**, with or without the header; the sentinel
   appears in no record but the original request's `Authorization`.
3. **`https` → `http`, same host**, the same way: `redirected`, the `http:`
   body; no record whose scheme is `http`.
4. **The same at D2, D3 and D4** (each carries the header after D2's `401`),
   and for the `401` retry itself: the retried request answered with a
   redirect is refused, not followed.
5. **A control that fails without the delegate.** The same stub and the same
   redirected request through a session whose delegate *allows* the redirect
   records a request to `login.example.invalid` **carrying `Authorization`**.
   This is the test of the test: it shows the harness can see the leak, so (2)
   and (3) mean something.
6. **`CalDAVSession.send` given an off-host or `http:` URL** throws
   `redirected` and the stub records nothing.
7. **Never before the `401`** stays as built and stays asserted on every
   recorded request (`caldav-mocks.md` §4): the first request of every connect
   and every sync carries no `Authorization`; the first one that does is the
   retry of a request the host answered `401`.

**The user's own act.** The app contacts the server only when the user presses
`Connect`, `Import`/`Save` or `Sync Now`, or, once they have connected, on the
schedule they set. **No build task, test, script or capture contacts it** or
holds a real password (BRIEF-PRODUCT non-negotiables: "ask me before doing
anything that logs into a university system with my password"). The first real
connection is Parsa's (G-068).

### 13.2 Editing and removing

- **Edit** — `layouts.md` §12.3. `Save` clears `isAutoSyncPaused` and applies
  the fetched data as a sync at once. Unchecking a calendar there deletes the
  events only it contributed, history included (`components.md` §20.1). The
  step-2 sentence counts them before `Save`, so no alert is added.
- **Remove** — `Remove Source…` (Settings button, `−`, sidebar context menu)
  shows a standard alert (`NSAlert`, warning style), the one confirmation in this
  slice, because removal deletes a Keychain item and cannot be undone:
  - Message: `Remove “University timetable”?`
  - Informative text: `Its 142 events — including past weeks and anything you
    marked done or skipped — will be removed from your calendar, and its
    password deleted from the Keychain. Routine blocks you moved for these
    events stay where they are. You can connect it again at any time; the
    timetable comes back, your done and skipped marks don't.`
  - Buttons: `Remove` (destructive, `hasDestructiveAction`), `Cancel` (default
    — `↩` does not remove; `⎋` cancels).
  - On `Remove`: an in-flight sync is cancelled; the source's events (history
    included) and the `Source` are deleted in one transaction; the Keychain item
    is deleted; the palette slot is freed; conflicts recompute. If the Keychain
    deletion fails the source is still removed, and the alert's follow-up sheet
    says `The password for {name} couldn't be deleted from the Keychain. You
    can remove the item “Kadence — {name}” in Keychain Access.` (`OK`).

### 13.3 When a source syncs

| Trigger | Behaviour |
|---|---|
| `Import` / `Save` | No new request: they write the data step 1 fetched (`components.md` §20.1). The interval starts from then |
| Interval | `NSBackgroundActivityScheduler`, `repeats = true`, `interval` = the source's `pollInterval`, `tolerance` = 10% of it, `qualityOfService = .utility`. One scheduler per source, re-created when the interval changes |
| Launch | If the last attempt is older than the interval, or never happened: at once (after the store loads) |
| Wake (`NSWorkspace.didWakeNotification`) | Same check, once the network path is satisfied; waits up to 60s for it, then gives up quietly until the next trigger (that is `offline`, not an error) |
| Network regained (`NWPathMonitor`: unsatisfied → satisfied) | If the last attempt failed `unreachable`/`offline`, or is older than the interval |
| **Sync Now** (`⌘R`, View ▸ Sync Now; the popover's and Settings' buttons; the sidebar context menu) | Every connected source (one source from a per-source control), regardless of interval and of `isAutoSyncPaused` — it is explicit. Disabled while every source is already syncing. Offline: shows `offline` at once, no request |

**Interval:** default **30 minutes** (Parsa, 2026-10-08); range **15 minutes …
1 day** in the seven steps of `layouts.md` §11. A half-hour means a same-day
room change is missed by at most one break. Each poll costs CIS **one
`REPORT`** for today onward. When nothing changed, the poll usually ends at
`components.md` §20.8.3 step 4 (same feed hash, nothing written). **In `get`
fetch mode** (`components.md` §20.8.2), automatic polls run at most every 6
hours. Sync Now is not limited.

**Rules:**

- **One sync per source at a time.** A trigger during a running sync is
  dropped, not queued (the running one already reads the latest state).
- **Offline is not an error.** While the path is unsatisfied no attempt is made
  and the state is `offline` (`ok` kind, no glyph).
- **No faster retry after a transient failure.** The next automatic attempt is
  the regular interval (or network regained). Polling a struggling server
  harder does not help it come back.
- **A 401 or 403 pauses automatic sync for that source**
  (`isAutoSyncPaused`): `unauthorized` and `forbidden` (`DECISIONS.md`
  2026-10-08). Repeated failed sign-ins can lock a university account, so
  Kadence never makes a second failing attempt on its own. The pause is cleared
  by edit mode's `Save` or by a Sync Now that succeeds.
- **These do not pause:** `noCalDAV`, `noCalendars`, `calendarMissing`,
  `fetchFailed`, `notACalendar`, `redirected`, `certificate` and
  `passwordMissing`. No password was refused, so nothing can be locked, and a
  maintenance page or a moved calendar can clear itself. They are `actionable`
  and shown, and they retry at the normal interval only. (`passwordMissing`
  sends no request at all.)
- **Timeouts:** 30 s per request. A sync of one source is abandoned after 120 s
  in total (600 s in `get` mode) and reported `unreachable`.
- **Requests are sequential**, at most 300 per source per sync
  (`components.md` §20.8.2).
- **Sleep, quit and removal** cancel an in-flight sync; nothing partial is
  written (the diff is applied in one transaction at the end, `components.md`
  §20.8).
- **Hidden** sources (sidebar checkbox off) **still sync**: visibility is a
  view filter, not a connection setting.

### 13.4 Refusing edits to an imported event

Every refusal is visible; none is silent and none is an alert. Two signals, used
together: **(a)** the system alert sound (`NSSound.beep()`) for keyboard and menu
gestures, the standard macOS answer to "that can't be done here"; **(b)** the
inspector's read-only line (`layouts.md` §6.1) switches to its **emphasised
state** for 0.6s — when the inspector is visible. Pointer gestures use the
cursor instead of the sound.

| Gesture | Result |
|---|---|
| Drag the block | No movement; cursor `.operationNotAllowed` from the drag threshold; no drop preview; (b) on release |
| Hover an edge | No resize handles, no resize cursor (`components.md` §18.2) |
| `⌥`-drag (duplicate) | As drag — refused in this slice |
| `⌫`, Edit ▸ Delete | Nothing deleted; (a) + (b). Edit ▸ Delete is **disabled** in the menu while an imported event is selected, so the menu shows the rule before the key does. *(2026-10-10: the item did not exist — DEVIATIONS A38; §2 now requires it.)* |
| `⌥↑` `⌥↓` `⌥←` `⌥→` `⌥⇧↑` `⌥⇧↓` | Nothing moves; (a) + (b) |
| `↩` (open in inspector) | Opens the inspector as usual and focuses its first focusable control; there is no title field to focus |
| Double-click the block | Selects it; no inline title edit; (b) |
| Typing into the title / notes area | Not possible — they are text, not fields |
| `⌘↩` / `⌥⌘↩` (done / skipped) | **Allowed** (`components.md` §18.1); refused with (a) + (b) only on a cancelled event |
| Popover `⌥⌘↩` (snooze) on an imported NEXT | `components.md` §18.3's refusal row |
| A conflict option on a lecture × routine conflict | Unchanged: the options only ever edit the routine side (`components.md` §14.3.1) |

When the inspector is collapsed, (a) alone signals a keyboard refusal; the
inspector is **not** opened by a refusal (a refusal that rearranges the window
would read as the opposite of "nothing happened").

### 13.5 Undo and sync

`components.md` §20.9: sync writes are not on the undo stack; steps that address
an event a sync deleted are dropped; Edit ▸ Undo never names an action that
would do nothing. Done/skipped on an imported event are ordinary named undo steps
(`Undo Mark Done`). The Import is not an undo step either: an Import is undone
by removing the source (§13.2).

---

# Phase 3 slice 2 — additions

Written 2026-10-14. No new key equivalent. Rules: `components.md` §23–§30.

## 14. Notifications

### 14.1 Acting on a notification

The actions are the popover's (§12), reached from outside the app.
`components.md` §27.7 is the table; the interaction rules:

- **Same verbs, same undo stack.** `Done` and `Snooze` call the `EventStore`
  verbs the popover calls and record the same named steps (`Mark Done`,
  `Snooze`), so `⌘Z` in the main window undoes an action taken from a
  notification. Nothing is undone from a notification itself: there is no
  `Undo` action (a background action has no place to show what it undid).
- **Snooze answers.** A snooze from a notification answers with a result
  notification (N5 moved / N6 refused, `components.md` §27.4) — the
  notification-centre form of §16's result row, because "it must show where
  the block landed". If the main window is open on that day, the block moves
  there with §7.1's transition when it is next drawn (as A33 already accepts
  for the popover: no cross-scene animation).
- **`Open` and clicking** activate Kadence, bring the main window forward
  (opening it if closed), page to the event's day in the current view (Month
  pages to its month) and select it, with the inspector showing it. Focus goes
  to the grid in selection mode (§1). The popover is not opened.
- **Dismissing** does nothing (`components.md` §27.9).
- **N8 (sync paused)** has only `Open`: it activates Kadence and opens
  Settings ▸ Sources with that source selected, where its status block's
  button is the remedy (`components.md` §27.7). *(Added 2026-10-14.)*
- Actions address the event by id at the moment they run (DECISIONS
  2026-09-09). An imported event never offers `Snooze` (§13.4).

### 14.2 Permission

- No prompt at launch. The first prompt follows the first moment there is
  something to schedule (`components.md` §27.8) — on a real first run, right
  after the Import. Kadence never asks twice on its own.
- `Allow Notifications…` and `Open System Settings…` (Settings ▸
  Notifications) are the only ways the app re-raises the question; the
  popover's notifications line only names the place.
- Kadence re-reads the authorization when it becomes active, so returning from
  System Settings with notifications on clears the status block and the line
  without a relaunch.

## 15. Travel

### 15.1 Setting a place on a manual event

- Inspector `Place` pop-up (`layouts.md` §6, amended): mouse or keyboard
  (`Space` / `↓` opens it when focused, standard pop-up behaviour). Choosing
  writes `placeID` as one undo step **`Set Place`**; choosing the current
  value writes nothing.
- The band appears, moves or disappears after the leg recompute (debounced
  0.5 s, `components.md` §24.6) without animation of its own — it is derived
  data arriving, not a block moving.
- `⌥`-drag duplicate copies the place. Drafts (§3) have no `Place` row until
  committed.
- Imported events: `Place` is text; there is nothing to set (§13.4's
  refusal table is unchanged — no gesture edits it).

### 15.2 Moving an event that has a band

A drag or nudge moves the block; the band is not drawn at the drop preview
(`components.md` §25.2) and is redrawn at the new position after the
recompute. `⌘Z` restores both. A snooze from the popover or a notification
behaves the same.

### 15.3 Settings ▸ Travel and ▸ Notifications

`layouts.md` §13–§14 give the controls and the `⇥` order. Edits commit on `↩`,
blur or a pop-up choice, are not undo steps (like every Settings edit), and
take effect through the recompute and the notification pass with no further
confirmation — except removing a place that manual events use, which asks
first (`layouts.md` §13), and **an address, which is used only once the user
confirms what Apple Maps found** (§15.4).

### 15.4 Confirming an address *(added 2026-10-14, routing amendment)*

- Committing a changed address field (`↩`, blur) starts one lookup
  (`components.md` §23.5). Typing alone never looks anything up: no search as
  you type, no request per keystroke.
- While a result waits for confirmation, the field stays editable; editing
  and committing again replaces the lookup (the old one's answer is
  discarded).
- One result: `↩` (the row's default button) or `Use This Address` confirms;
  `⎋` or `Cancel` drops it and restores the field to the confirmed address
  (or empties it). Several: `↓` from the field moves into the match list,
  `↑` / `↓` move within it, `↩` or a click confirms, `⎋` cancels.
- Leaving the tab or closing Settings with a result unconfirmed keeps the
  typed text and sets `unconfirmed`; nothing is confirmed by leaving.
- Confirming triggers the leg recompute; legs that were `unavailable ·
  needsAddress` become `pending` and fill in as the queue answers.
- No confirmation is ever an undo step, and no alert is ever shown for a
  lookup: the line under the field is the whole conversation.

### 15.5 Location *(added 2026-10-14, routing amendment)*

- Kadence never asks for location at launch or when Settings opens. The one
  automatic request comes at the first departure refresh that wants a fix
  (`components.md` §24.12); `Allow Location…` is the only other way.
- Nothing in the main window, the popover or a notification mentions
  location: a denied permission changes where trips are worked out from, not
  whether there is a leave-by. Settings ▸ Travel's block is the only place
  the state shows.
- `Open System Settings…` opens the URL through the injected opener and does
  nothing else; Kadence re-reads the state on `didBecomeActive`.
