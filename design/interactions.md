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

The focused region draws the standard system focus ring on its container. Within
a region, `↑` `↓` `←` `→` move focus between its items; `⇥` always leaves the
region rather than moving inside it.

The grid is a single focus target. Inside it there are two focus modes:

- **Selection mode** — a block is selected. Arrows move between blocks.
- **Cursor mode** — nothing is selected. A **time cursor** is shown: a 1pt line
  in `color.interactive.accent` across the focused day column, with its time
  printed in the gutter in `hourLabel` / `color.interactive.accent`. Arrows move
  the cursor. This is what makes keyboard-only event creation possible.

`⎋` moves selection mode → cursor mode → unfocused grid.

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
| `⌫` | Delete the selection | selection mode |
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
| `⌘⌥N` | New all-day event on the focused day | grid focused |

Every one of these is also a menu bar item, with the same key equivalent, so the
shortcut set is discoverable without documentation.

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

### 12.1 Motion in the popover

The status item's text changes without animation — it updates on a timer and any
animation in a menu bar reads as a glitch. The popover's snooze result row
cross-fades over `motion.selection` (0.09s) and holds for
`motion.snoozeConfirmHold` (4s), pausing while the pointer is inside the popover.
Under Reduce Motion the cross-fade becomes an instant swap; the hold is unchanged
because it is a duration, not a motion.
