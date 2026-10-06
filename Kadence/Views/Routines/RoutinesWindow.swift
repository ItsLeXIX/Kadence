//
//  RoutinesWindow.swift
//  Kadence
//
//  layouts.md §8 / components.md §13.1 — the Routines window shell: template
//  picker, seven weekday-only columns on the same hour-grid geometry as the
//  main Week view, and an inspector.
//
//  Task P2-T10 built this window read-only. Task P2-T11 added interactions.md
//  §11.1's move / resize / delete — "Creating, moving and resizing routine
//  blocks uses §3 and §4 unchanged ... same handles, same drop preview. `⌫`
//  deletes. `⌘Z` undoes, with names." Task P2-T12 added the other half §11.1
//  groups with move/resize but P2-T10/P2-T11 both carved out separately:
//  creating new routine blocks. Double-click empty grid creates a 60-minute
//  block at the snapped slot under the pointer; drag creates a block of the
//  dragged duration, minimum 15 minutes (interactions.md §3, applied unchanged
//  per §11.1) — same inline `TextField`-in-place-of-title,
//  `↩`-commits/`⎋`-cancels-and-removes, empty-title-never-persists shape as an
//  ordinary event's draft.
//
//  Task P2-T20 (this pass) closes the render/mode-switch half of what was
//  still missing: the `[Blocks | Windows]` mode control (components.md
//  §13.3) and the background windows layer, now that a persisted `TimeWindow`
//  model exists (task P2-T18). A segmented control in the toolbar —
//  `size.editorModeBarHeight`, `editorModeLabel` type — plus `⌘[`/`⌘]`
//  (interactions.md §11.1) switch `editorMode` between `.blocks` and
//  `.windows`; either path clears `selection` ("the current selection is
//  dropped on mode change"). Every weekday column now renders all three
//  `TimeWindow` kinds through the generalized `BackgroundWindowsLayer`/
//  `WindowLabelsLayer` (`GridLayers.swift`, now generic over
//  `TimeWindowRenderable` so they can draw either `TimeWindowFixture` or
//  `TimeWindow`): in Blocks mode only protected/low-energy are drawn — the
//  same treatment and z-order the main grid uses, non-hit-testable — matching
//  §13.3's table ("windows drawn normally, not hit-testable"); in Windows
//  mode all three are drawn, including peak-focus as the 1pt dashed outline
//  components.md §7's "Editor exception" paragraph specifies, and the
//  existing block/draft layer drops to `opacity.editorInactiveLayer` and
//  `.allowsHitTesting(false)` (§13.3: "blocks drop to
//  `opacity.editorInactiveLayer`, not hit-testable"). Task P2-T21 then made an
//  EXISTING `TimeWindow` selectable, whole-span draggable and deletable in
//  Windows mode — its own comments named resizing an edge and creating a new
//  window as "next task's job". Task P2-T22 was that next task for
//  resizing: dragging within `Tokens.Size.blockResizeHandleHeight` of a
//  selected span's top or bottom edge — "the same ... handles blocks use"
//  (components.md §13.3, verbatim) — now resizes that edge through the new
//  `TimeWindowStore.resize` instead of moving the whole span; a body drag
//  still moves it, unchanged. Task P2-T23 (this pass) is components.md
//  §13.3's other named half — "Creating one: drag on empty canvas, then pick
//  the kind from the inspector" — but only the drag half of that sentence:
//  dragging on the windows-mode empty-canvas Rectangle (the same one whose
//  tap already deselects) now creates a new TimeWindow scoped to the single
//  weekday column the drag ran in, defaulting to kind .protected and an
//  empty label (TimeWindow.swift's own model defaults), 15-minute minimum
//  duration, selected on success — its own small TimeWindowCreateDragSession
//  state and dashed drop preview, mirroring createSurface's own create-drag
//  shape rather than overloading TimeWindowDragSession (move/resize-only,
//  for an EXISTING window). Task P2-T24 (this pass) closes the remaining
//  half of that same §13.3 sentence — "then pick the kind from the
//  inspector" — plus the weekday-set editing and label editing components.md
//  §7's "protected / low-energy / peak-focus regions ... editable" also
//  promises: the `inspector` computed property below now branches on
//  `windowSelection` first, rendering the new `TimeWindowInspectorView`
//  (kind segmented-Picker, a Mon-first weekday toggle row, a label
//  TextField, all wired straight to the new `TimeWindowStore.setKind` /
//  `.setWeekdays` / `.setLabel`) instead of always falling through to
//  `RoutineInspectorView`. Still explicitly out of scope, left for
//  follow-up tasks:
//    - detached-instance tracking and Re-sync (components.md §13.4,
//      interactions.md §11.2) — always zero right now, so per the existing
//      zero-state rule (§10.2) it is omitted entirely rather than stubbed;
//    - RoutineEngine.materialize honouring protected windows, MenuBarExtra,
//      snooze — separate, later tasks, unrelated to this window.
//
//  Task P2-T38 — weekday activity (components.md §13.5.1–§13.5.3, §13.5.5;
//  interactions.md §11.1 as amended 2026-10-01). In Blocks mode an inactive
//  weekday column recedes (hour lines at half-hour weight, ground unchanged),
//  carries the pinned "Not in this routine" note with an `Add <Day>` button,
//  and refuses create gestures with an `.operationNotAllowed` cursor; active
//  columns gain a header underline in the template's rail colour. A block
//  move/resize is vertical only, and its drop preview draws in every active
//  column at once (`RoutineBlockDrag`, shared by the canvas). The rules
//  themselves live in `Kadence/Layout/RoutineColumnRules.swift`. The
//  `Add <Day>` button is deliberately a no-op until P2-T39 (§13.5.4).
//
//  Task P2-T39 — weekday activation (components.md §13.5.4, interactions.md
//  §11.1.1, layouts.md §8.1). The `Add <Day>` button and the template
//  inspector's weekday toggle row both write through
//  `RoutineTemplateStore.setWeekday` (`RoutineEngine.swift`): one named undo
//  step each, `Add Saturday to Routine` / `Remove Saturday from Routine`. The
//  inspector's old read-only "Weekdays" text is now that toggle row
//  (`WeekdayToggleRow`, shared with the time-window inspector), reachable by
//  `⇥`, `←`/`→` to move, `space` to flip. A column that changes state cross-
//  fades over `motion.viewChange` (`RoutineColumnTransition`).
//
//  Move/resize/delete/create all go through `RoutineBlockStore`
//  (`Kadence/State/RoutineEngine.swift`) — the Routines-window sibling of
//  `EventStore`, same id-addressed/undo-named shape, written over
//  `startMinutes`/`duration` instead of `Date` since a `RoutineBlock` has
//  none of its own. One store instance, one `UndoStack` (the same one
//  `MainWindow` shares — `KadenceApp.swift` now injects it into this window's
//  `WindowGroup` too, which it did not before P2-T11), so `⌘Z` in either
//  window means the same thing and the Edit menu names the step correctly no
//  matter which window is key.
//
//  Create (task P2-T12) reuses `EventDraft`/`DraftBlockView` unchanged — both
//  are already plain `Date`-based types with no `Event`/`CalendarState`
//  dependency of their own (`EventDraft.swift`'s own header: "Deliberately
//  not an `Event`"), so the in-flight draft here is `RoutineDayColumnView`'s
//  own local `@State`, not `CalendarState.draft` (that state belongs to the
//  main-grid window, same reasoning as `RoutineBlockSelection` below being
//  its own window-scoped type rather than `CalendarState.selectedEventID`).
//  The Date-to-minutes conversion on commit is the same
//  `RoutineWeekLayout.referenceDayStart` inverse move/resize already use.
//
//  A single edit to any one weekday's copy of a block changes the
//  `RoutineBlock`'s own `startMinutes`/`duration` once — there is no
//  per-weekday instance to keep in sync, so the change reflects on every
//  other active-weekday column immediately, for free, the same way
//  `RoutineWeekLayout`'s header already describes for read-only rendering.
//
//  What IS reused, unchanged: `DayLayoutEngine` (the same overlap-resolution
//  engine the main grid uses), `TimeGeometry` (including its `snap` — same
//  15-minute/5-minute-with-⌃ rule as `DayColumnView.blockGesture`),
//  `HourLinesLayer` / `TimeGutterView` (`GridLayers.swift`), `GridBlockView`
//  (components.md §13.1: "Anything that looks like a block in this window is
//  a block, and behaves like one" — including its built-in hover resize
//  handles, now that `isMovable` is `true`) and, as of this task, `EventDraft`
//  / `DraftBlockView` (`Kadence/Models/EventDraft.swift`,
//  `Kadence/Views/Blocks/DraftBlockView.swift`) unchanged for the in-flight
//  creation UI. `DayColumnView`/`TimedCanvasView` themselves are still not
//  reused as SwiftUI containers — they are hard-wired to
//  `Event`/`EventStore`/`CalendarState`/drag-and-drop, none of which apply to
//  a `RoutineBlock` canvas — but the drag/create gestures below mirror
//  `DayColumnView.blockGesture`/`.createSurface`'s shape (mode classification
//  by handle-height, snap, drop preview, double-click/drag-to-create) rather
//  than re-deriving them.
//

import SwiftUI
import AppKit
import SwiftData

// `RoutinesEditorMode` now lives in `Kadence/Layout/RoutineColumnRules.swift`
// (task P2-T38), beside the weekday-column rules that take it.

struct RoutinesWindow: View {
    @Query(sort: \RoutineTemplate.name) private var templates: [RoutineTemplate]
    /// Task P2-T18 seeded this via `.task {}` below; nothing read it back
    /// anywhere in this window until this task's windows-mode rendering.
    @Query private var timeWindows: [TimeWindow]
    /// Task P2-T44: every event, so the detached count (§13.7.3) re-renders
    /// when an instance is edited in the main window.
    @Query private var events: [Event]
    @Environment(\.modelContext) private var context
    /// KadenceApp.swift now injects the same instance MainWindow uses, so
    /// `⌘Z`/`⌘⇧Z` (wired once, app-wide, in `KadenceCommands`) undo/redo
    /// routine edits exactly like event edits — one stack for the whole app.
    @Environment(UndoStack.self) private var undoStack
    /// Task P2-T40: read only for the main window's visible range, which sets
    /// the materialisation horizon (components.md §13.6.5). `KadenceApp`
    /// injects the same instance `MainWindow` uses.
    @Environment(CalendarState.self) private var calendarState

    @State private var selectedTemplateID: UUID?
    @State private var selection: RoutineBlockSelection?
    /// Task P2-T21: which existing `TimeWindow` (by `id`) is selected in
    /// Windows mode. Simpler than `RoutineBlockSelection` — a `TimeWindow` is
    /// one object regardless of how many weekday columns it renders into (its
    /// `weekdays` set draws it into every one of them at once), so there is no
    /// weekday-disambiguation to carry the way a `RoutineBlock` needs.
    @State private var windowSelection: UUID?
    @State private var editorMode: RoutinesEditorMode = .blocks
    /// Task P2-T46 — components.md §14.6 / layouts.md §8.1's conflict mode:
    /// which template conflict the editor inspector shows, and which of its
    /// options is focused (and so previewed on the canvas).
    @State private var routineConflictID: String?
    @State private var routineConflictOptionID: String?
    /// Task P2-F15 — the last "bring this conflict into view" request.
    @State private var routineScrollRequest: RoutineScrollRequest?
    @State private var didSeed = false
    /// Task P2-T40 — see `MainWindow.isMaterializationReady`.
    @State private var isMaterializationReady = false
    /// So `⌫` (below) has somewhere to land. Requested whenever a block is
    /// selected — including the very first tap — since nothing else in this
    /// window claims keyboard focus by default.
    @FocusState private var canvasFocused: Bool
    /// layouts.md §8 → §1.1 (task P2-SF6): the editor inspector auto-collapses
    /// below 1040pt and comes back, as an overlay, only when the user opens
    /// it (⌥⌘I — routed here by `RoutinesInspectorToggle` while this window
    /// is key) or a template conflict is activated (its panel lives in the
    /// inspector). An explicit choice isn't overwritten by a later resize.
    /// Mirrors `CalendarState.isInspectorVisible` / `userSetInspectorVisibility`.
    @State private var isInspectorVisible = true
    @State private var userSetInspectorVisibility = false

    private var store: RoutineBlockStore {
        RoutineBlockStore(context: context, undo: undoStack)
    }

    /// Task P2-T21's sibling to `store` above — same one-`UndoStack`-per-app
    /// wiring, so `⌘Z` for a window move/delete names correctly no matter
    /// which window is key.
    private var timeWindowStore: TimeWindowStore {
        TimeWindowStore(context: context, undo: undoStack)
    }

    /// Task P2-T39 — weekday activation (components.md §13.5.4). Same shared
    /// `UndoStack` as the two stores above.
    private var templateStore: RoutineTemplateStore {
        RoutineTemplateStore(context: context, undo: undoStack)
    }

    /// components.md §13.5.4: the one write behind all three activation
    /// paths. Passed down as a closure so the canvas and the inspector need
    /// neither the store nor the template to call it.
    private func setWeekday(_ weekday: Int, active: Bool) {
        guard let selectedTemplate else { return }
        templateStore.setWeekday(weekday, active: active, in: selectedTemplate)
    }

    /// components.md §13.7.3 (task P2-T44): the selected template's detached
    /// instances from today through the materialisation horizon.
    private var detachedInstances: [Event] {
        guard let selectedTemplate else { return [] }
        return RoutineResync.scope(
            of: selectedTemplate, among: events,
            today: calendarState.now, visibleEnd: calendarState.visibleInterval.end)
    }

    /// A block of the selected template, by id.
    private func block(_ id: UUID) -> RoutineBlock? {
        selectedTemplate?.blocks.first { $0.id == id }
    }

    private var selectedTemplate: RoutineTemplate? {
        if let selectedTemplateID, let match = templates.first(where: { $0.id == selectedTemplateID }) {
            return match
        }
        return templates.first
    }

    private var selectedBlockSnapshot: RoutineBlockSnapshot? {
        guard let selection, let template = selectedTemplate,
              let block = template.blocks.first(where: { $0.id == selection.blockID })
        else { return nil }
        return block.snapshot
    }

    /// Task P2-T24: the actual live `TimeWindow` `@Model` instance
    /// `windowSelection` names, if it still exists (deleted-out-from-under
    /// selection resolves to `nil`, same guard `handleDelete()` above already
    /// applies before acting on it). Passed to the inspector directly, unlike
    /// `selectedBlockSnapshot`'s plain-value snapshot — `TimeWindowStore`'s
    /// own mutation methods take a `TimeWindow` model, not an id, matching
    /// `move`/`resize`/`delete`'s existing call shape, and the inspector's
    /// Picker/Toggle/TextField bindings read `window.kind`/`.weekdays`/`.label`
    /// live off that same instance.
    private var selectedWindow: TimeWindow? {
        guard let windowSelection else { return nil }
        return timeWindows.first(where: { $0.id == windowSelection })
    }

    private var orderedWeekdays: [Int] {
        RoutineWeekLayout.orderedWeekdays(firstWeekday: Calendar.current.firstWeekday)
    }

    var body: some View {
        GeometryReader { proxy in
            // layouts.md §8: "the editor inspector collapses below 1040pt and
            // returns as an overlay, exactly as §1.1 does for the main
            // window. The canvas never collapses." 1040 is a literal from
            // that prose, the same way MainWindow hardcodes its own 1200/900
            // collapse widths rather than a token — there is no
            // `size.*` token for this particular width.
            let isSplit = proxy.size.width >= 1040

            ZStack(alignment: .topTrailing) {
                HStack(spacing: 0) {
                    canvas
                        .frame(minWidth: 0, maxWidth: .infinity)
                    if isSplit && isInspectorVisible {
                        Rectangle()
                            .fill(Tokens.Color.Separator.region)
                            .frame(width: Tokens.Size.hairline)
                        inspector
                            .frame(width: Tokens.Size.editorInspectorWidth)
                    }
                }

                if !isSplit && isInspectorVisible {
                    inspector
                        .frame(width: Tokens.Size.editorInspectorWidth)
                        .elevation(.level2)
                }
            }
            // §1.1's collapse order, applied on open (`initial: true`) and
            // whenever the width crosses 1040 — unless the user chose.
            .onChange(of: isSplit, initial: true) { _, wide in
                if !userSetInspectorVisibility { isInspectorVisible = wide }
            }
            // interactions.md §11.1/§5 — `⌫` deletes the selected block
            // immediately, no confirmation. Attached at this level (rather
            // than per-block) so it fires regardless of which weekday column
            // the block was last clicked in.
            .focusable()
            .focused($canvasFocused)
            .onKeyPress(keys: [.delete]) { _ in handleDelete() }
            // Task P2-T46: the conflict panel's keys (interactions.md §10.1).
            // P2-F16: `⌥←`/`⌥→` step the footer (layouts.md §10).
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .escape, .return]) { press in
                handleConflictKey(press)
            }
            // interactions.md §11.1: "Switching between Blocks and Windows
            // mode: ⌘[ / ⌘], or the mode control." Window-scoped, the same
            // way `⌫` above is — not routed through `KadenceCommands`
            // (app-wide menu commands would fire this even with the main
            // calendar window key, where "editor mode" means nothing).
            .onKeyPress(keys: ["[", "]"]) { keyPress in
                guard keyPress.modifiers.contains(.command) else { return .ignored }
                switch keyPress.key {
                case "[": editorMode = .blocks; return .handled
                case "]": editorMode = .windows; return .handled
                default: return .ignored
                }
            }
        }
        .toolbar { toolbarContent }
        // ⌥⌘I (View ▸ Show/Hide Inspector) toggles THIS window's editor
        // inspector while it is the key window. Swift note: a focused scene
        // value is how a menu command (`KadenceCommands`) finds out which
        // window is key and talks to it — roughly a "current window" service
        // the frontmost window registers itself with.
        .focusedSceneValue(\.routinesInspector, RoutinesInspectorToggle(isVisible: isInspectorVisible) {
            userSetInspectorVisibility = true
            isInspectorVisible.toggle()
        })
        .frame(
            minWidth: Tokens.Size.routineEditorMinWidth,
            minHeight: Tokens.Size.routineEditorMinHeight)
        .task {
            guard !didSeed else { return }
            didSeed = true
            // Task P2-T40: the same seeding + launch materialisation call
            // `MainWindow` makes. This window can be the first one a session
            // opens (⌘⌥R), and the hand-seeded events must still arrive
            // before the first pass (see `MockData.seedAllIfNeeded`).
            let visibleEnd = calendarState.visibleInterval.end
            MockData.seedAllIfNeeded(context) {
                RoutineMaterialization.run(context: context, undo: undoStack, visibleEnd: visibleEnd)
            }
            // components.md §13.2 (task P2-T42): no `.shiftable` block
            // survives launch without a ± value.
            store.repairShiftRanges()
            isMaterializationReady = true
            canvasFocused = true
        }
        // components.md §13.6.5: an edit made here materialises even when
        // the main window isn't open. Horizon end is the main window's
        // visible range, read from the shared `CalendarState`.
        .materializesRoutines(isReady: isMaterializationReady, visibleEnd: calendarState.visibleInterval.end)
        .onChange(of: selectedTemplateID) { _, _ in
            // Task P2-T46: `enterConflictMode` selects a template and a block
            // together; keep the block if it belongs to the new template.
            if let selection, selectedTemplate?.blocks.contains(where: { $0.id == selection.blockID }) == true {
                return
            }
            selection = nil
            windowSelection = nil
        }
        .onChange(of: selection) { _, newValue in
            if newValue != nil { canvasFocused = true }
            // Selecting another block (or nothing) leaves conflict mode: the
            // inspector shows what is selected (§10.2 — the panel never traps).
            if let conflict = activeRoutineConflict, newValue?.blockID != conflict.blockID {
                routineConflictID = nil
                routineConflictOptionID = nil
            }
        }
        // §14.6: the needs-attention row / `⌘⇧A` asked for a template
        // conflict. `initial: true` covers the window being opened by that
        // very request.
        .onChange(of: calendarState.pendingTemplateConflictID, initial: true) { _, _ in
            openPendingTemplateConflict()
        }
        // interactions.md §11.1: "The current selection is dropped on mode
        // change." One `onChange` covers both the mode control and the
        // `⌘[`/`⌘]` shortcuts above, since both just assign `editorMode`.
        // Task P2-T21 generalizes this to the new `windowSelection` kind too
        // — interactions.md §11.1's rule is "the current selection", not
        // specifically the block one.
        .onChange(of: editorMode) { _, _ in
            selection = nil
            windowSelection = nil
            routineConflictID = nil
            routineConflictOptionID = nil
        }
    }

    /// `⌫` — no confirmation, matching interactions.md §5's rule for events
    /// ("`⌫` deletes immediately. No confirmation sheet."). `⌘Z` restores it.
    ///
    /// Task P2-T21: branches on `windowSelection` first. A `TimeWindow` and a
    /// `RoutineBlockSelection` can never both be non-nil at once — selecting
    /// one kind always clears the other (see the window/block tap handlers
    /// below) — but the window branch is checked first regardless, since it
    /// is the more specific of the two selection kinds this window now has.
    private func handleDelete() -> KeyPress.Result {
        if let windowSelection, let window = timeWindows.first(where: { $0.id == windowSelection }) {
            self.windowSelection = nil
            timeWindowStore.delete(window)
            return .handled
        }
        guard let selection, let template = selectedTemplate,
              let block = template.blocks.first(where: { $0.id == selection.blockID })
        else { return .ignored }
        self.selection = nil
        store.delete(block, from: template)
        return .handled
    }

    // MARK: Canvas

    private var canvas: some View {
        VStack(spacing: 0) {
            RoutineWeekdayHeaderRow(
                weekdays: orderedWeekdays,
                activeWeekdays: selectedTemplate?.activeWeekdays ?? [],
                railColor: (selectedTemplate?.sourceKey ?? .graphite).rail,
                editorMode: editorMode)
            RoutinesCanvasView(
                weekdays: orderedWeekdays,
                template: selectedTemplate,
                store: store,
                selection: $selection,
                editorMode: editorMode,
                timeWindows: timeWindows,
                timeWindowStore: timeWindowStore,
                windowSelection: $windowSelection,
                onAddWeekday: { setWeekday($0, active: true) },
                conflictPreview: conflictPreview,
                scrollRequest: routineScrollRequest)
        }
    }

    // MARK: Template conflicts (components.md §14.6, task P2-T46)

    /// Every template conflict, from the same queries the canvas draws.
    private var templateConflicts: [TemplateConflict] {
        TemplateConflictEngine.detect(templates: templates, windows: timeWindows, orderedWeekdays: orderedWeekdays)
    }

    private var activeRoutineConflict: TemplateConflict? {
        guard let routineConflictID else { return nil }
        return templateConflicts.first { $0.id == routineConflictID }
    }

    private var focusedRoutineConflictOption: TemplateConflictOption? {
        guard let routineConflictOptionID else { return nil }
        return activeRoutineConflict?.options.first { $0.id == routineConflictOptionID }
    }

    private var conflictPreview: RoutineConflictPreview? {
        guard let conflict = activeRoutineConflict, let option = focusedRoutineConflictOption else { return nil }
        return RoutineConflictPreview(
            blockID: conflict.blockID, startMinutes: option.newStartMinutes, durationMinutes: option.newDurationMinutes)
    }

    /// §14.6: "opens the Routines window …, selects the template, selects
    /// the block, and puts the editor inspector into conflict mode."
    /// Consumes `CalendarState.pendingTemplateConflictID`.
    private func openPendingTemplateConflict() {
        guard let id = calendarState.pendingTemplateConflictID else { return }
        calendarState.pendingTemplateConflictID = nil
        guard let conflict = templateConflicts.first(where: { $0.id == id }) else { return }
        enterConflictMode(conflict)
    }

    private func enterConflictMode(_ conflict: TemplateConflict) {
        // The conflict panel is the editor inspector's conflict mode, so it
        // must be showing — as the main window opens its inspector for a day
        // conflict (`CalendarState.activateNeedsAttention`).
        userSetInspectorVisibility = true
        isInspectorVisible = true
        selectedTemplateID = conflict.templateID
        editorMode = .blocks
        windowSelection = nil
        selection = RoutineBlockSelection(blockID: conflict.blockID, weekday: conflict.weekdays.first ?? 2)
        routineConflictID = conflict.id
        // interactions.md §10.1 (amended 2026-10-05, task P2-F15):
        // activation focuses — and so previews — the recommended option, or
        // the only one.
        routineConflictOptionID = RoutineScrollRequest.activationOptionID(conflict)
        routineScrollRequest = RoutineScrollRequest(conflict)
        canvasFocused = true
    }

    /// interactions.md §10.1 in the Routines window: `↑`/`↓` move and
    /// preview, `⎋` abandons, `↩` applies. Returns `.ignored` outside
    /// conflict mode so the window's other keys behave as before.
    private func handleConflictKey(_ press: KeyPress) -> KeyPress.Result {
        guard let conflict = activeRoutineConflict else { return .ignored }
        let ids = conflict.options.map(\.id)
        switch press.key {
        case .upArrow, .downArrow:
            let step = press.key == .upArrow ? -1 : 1
            let current = routineConflictOptionID.flatMap { ids.firstIndex(of: $0) }
            let next = current.map { min(max($0 + step, 0), ids.count - 1) } ?? 0
            routineConflictOptionID = ids.isEmpty ? nil : ids[next]
            return .handled
        case .leftArrow, .rightArrow:
            guard press.modifiers.contains(.option) else { return .ignored }
            stepRoutineConflict(press.key == .leftArrow ? -1 : 1)
            return .handled
        case .escape:
            // §10.2: ⎋ reverts the pending preview. With nothing previewed,
            // it leaves conflict mode for the ordinary inspector.
            if routineConflictOptionID != nil { routineConflictOptionID = nil } else { routineConflictID = nil }
            return .handled
        case .return:
            guard focusedRoutineConflictOption != nil else { return .ignored }
            applyFocusedRoutineConflictOption()
            return .handled
        default:
            return .ignored
        }
    }

    /// layouts.md §10's footer for the active template conflict (task
    /// P2-F16): its place in the one needs-attention list, of N.
    private var routineConflictFooter: ConflictFooterModel? {
        guard let id = routineConflictID,
              let position = calendarState.conflictPosition(of: .template(id)) else { return nil }
        return ConflictFooterModel(position: position, count: calendarState.needsAttentionCount)
    }

    /// `‹`/`›` in the Routines window. Onto another template conflict:
    /// `stepConflict` records it as pending, which `openPendingTemplateConflict`
    /// (watching that value) consumes here. Back from the first template
    /// conflict onto a day conflict: `stepConflict` opens it in the main
    /// window's state, and the main window is brought forward.
    private func stepRoutineConflict(_ direction: Int) {
        guard let id = routineConflictID else { return }
        if case .day? = calendarState.stepConflict(from: .template(id), by: direction) {
            // The main window is the one window that isn't a Routines
            // window. AppKit is used because `openWindow(id:)` would open a
            // second one of a `WindowGroup`.
            NSApplication.shared.windows
                .first { $0.isVisible && $0.canBecomeMain
                    && !RoutinesWindowOpener.isRoutinesWindow(identifier: $0.identifier?.rawValue) }?
                .makeKeyAndOrderFront(nil)
        }
    }

    /// `↩`: one `Resolve Routine Conflict` step, then advance to the next
    /// template conflict, or back to the ordinary inspector (§14.5).
    private func applyFocusedRoutineConflictOption() {
        guard let conflict = activeRoutineConflict, let option = focusedRoutineConflictOption else { return }
        TemplateConflictResolver.apply(
            option, of: conflict, context: context, undo: undoStack,
            today: calendarState.now, visibleEnd: calendarState.visibleInterval.end)
        routineConflictOptionID = nil
        // Recompute from a fresh fetch: the queries refresh on the next
        // render, and the panel must not advance onto a stale list.
        let fresh = TemplateConflictEngine.detect(
            templates: (try? context.fetch(FetchDescriptor<RoutineTemplate>())) ?? [],
            windows: (try? context.fetch(FetchDescriptor<TimeWindow>())) ?? [],
            orderedWeekdays: orderedWeekdays)
        if let next = fresh.first {
            // The advance after `↩` is an activation (§10.1, P2-F15):
            // `enterConflictMode` focuses the recommendation and scrolls.
            enterConflictMode(next)
        } else {
            routineConflictID = nil
        }
    }

    // MARK: Inspector (layouts.md §8.1)

    /// Task P2-T24: a selected `TimeWindow` (Windows mode) now takes priority
    /// over the block/template summary, mirroring `handleDelete()`'s own
    /// "check the more specific selection kind first" ordering — the two
    /// selections can never both be non-nil (every place that sets one clears
    /// the other), so this is a straightforward either/or rather than a
    /// priority tie-break. `.id(selectedWindow.id)` forces SwiftUI to tear
    /// down and rebuild `TimeWindowInspectorView` (and its local `@State`
    /// label-editing buffer) whenever the selected window's identity changes,
    /// rather than reusing the old view in place and leaving stale text
    /// behind — the same reason a fresh `EventDraft` always gets a fresh
    /// `DraftBlockView` rather than one being mutated across drafts.
    @ViewBuilder
    private var inspector: some View {
        if let conflict = activeRoutineConflict {
            // layouts.md §8.1: "A template conflict replaces the inspector's
            // contents with §10's panel."
            ScrollView {
                TemplateConflictPanelView(
                    conflict: conflict,
                    template: selectedTemplate,
                    selectedOptionID: routineConflictOptionID,
                    onSelectOption: { routineConflictOptionID = $0; canvasFocused = true },
                    footer: routineConflictFooter,
                    onStep: stepRoutineConflict)
                    .padding(Tokens.Spacing.xl)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Tokens.Color.Surface.inspector)
        } else if let selectedWindow {
            TimeWindowInspectorView(window: selectedWindow, store: timeWindowStore)
                .id(selectedWindow.id)
        } else {
            RoutineInspectorView(
                template: selectedTemplate,
                selectedBlock: selectedBlockSnapshot,
                timeWindows: timeWindows,
                onSetWeekday: setWeekday,
                onSetFlexibility: { id, flexibility in
                    if let block = block(id) { store.setFlexibility(block, to: flexibility) }
                },
                onSetShiftRange: { id, minutes in
                    if let block = block(id) { store.setShiftRange(block, to: minutes) }
                },
                onRepairShiftRange: { id in store.repairShiftRanges(blockID: id) },
                detachedInstances: detachedInstances,
                onResync: { instances in
                    RoutineResync.apply(instances, store: EventStore(context: context, undo: undoStack))
                })
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            // layouts.md §8's own diagram: "toolbar: template picker ·
            // [Blocks | Windows] · +". The "+" new-template action is not
            // part of this task's scope — still just the picker plus, now,
            // the mode control.
            Picker("Template", selection: Binding(
                get: { selectedTemplateID ?? templates.first?.id },
                set: { selectedTemplateID = $0 })) {
                    ForEach(templates, id: \.id) { template in
                        Text(template.name).tag(template.id as UUID?)
                    }
                }
                .labelsHidden()
                .disabled(templates.isEmpty)
        }

        // components.md §13.3: "A segmented control in the editor's mode
        // bar, height `size.editorModeBarHeight`, `editorModeLabel` type."
        // Same native `.pickerStyle(.segmented)` shape `MainWindow`'s own
        // Month/Week/Day mode control already uses (`MainWindow.swift`) —
        // no bespoke chrome invented, just this control's own height/type
        // tokens applied on top.
        ToolbarItem(placement: .primaryAction) {
            Picker("Editor Mode", selection: $editorMode) {
                ForEach(RoutinesEditorMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .typeStyle(.editorModeLabel)
            .frame(height: Tokens.Size.editorModeBarHeight)
        }
    }
}

/// One selected `RoutineBlock` instance, identified by the block itself plus
/// which weekday column it was clicked in — the same block recurs in every
/// one of the template's active weekday columns, so the id alone is
/// ambiguous. Window-scoped state, not `CalendarState` (interactions.md's
/// selection model belongs to the main-grid window; this is a separate
/// window with its own selection).
/// Task P2-T46 — what the Routines canvas previews for a focused template
/// conflict option: the block, and its proposed start/duration in minutes
/// (`nil` for `remove`, which only dims the block).
struct RoutineConflictPreview: Equatable {
    var blockID: UUID
    var startMinutes: Int?
    var durationMinutes: Int?
}

struct RoutineBlockSelection: Equatable {
    var blockID: UUID
    var weekday: Int
}

// MARK: - Weekday header (components.md §13.1: "no dates, dayHeaderWeekday only")

private struct RoutineWeekdayHeaderRow: View {
    let weekdays: [Int]
    /// Task P2-T38 — components.md §13.5.2: "The header marks activity
    /// positively. Active days gain the underline; the inactive ones are not
    /// degraded." The weekday symbol itself is identical in every case.
    let activeWeekdays: Set<Int>
    /// The template's own `color.source.<slot>.rail` (§13.1 makes it the one
    /// hue in this window).
    let railColor: Color
    let editorMode: RoutinesEditorMode

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: Tokens.Size.timeGutterWidth)
            ForEach(weekdays, id: \.self) { weekday in
                Text(weekdaySymbol(weekday))
                    .typeStyle(.dayHeaderWeekday)
                    .foregroundStyle(Tokens.Color.Text.secondary)
                    // `.frame(maxWidth: .infinity, maxHeight: .infinity)`
                    // lets the cell fill the row's full height so the
                    // underline below can sit on the row's bottom edge.
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottom) {
                        // §13.5.2: "`size.borderEmphasis` (1.5) tall, drawn at
                        // the header's bottom edge directly above its
                        // `color.separator.region` hairline, full column
                        // width". The `.padding(.bottom, hairline)` is what
                        // puts it *above* that hairline rather than over it.
                        // Blocks mode only (§13.5.5) — `.unmarked` never shows it.
                        if RoutineColumnTreatment.resolve(
                            weekday: weekday, activeWeekdays: activeWeekdays, mode: editorMode
                        ).showsHeaderUnderline {
                            Rectangle()
                                .fill(railColor)
                                .frame(height: Tokens.Size.borderEmphasis)
                                .padding(.bottom, Tokens.Size.hairline)
                                .accessibilityHidden(true)
                        }
                    }
            }
        }
        .frame(height: Tokens.Size.dayHeaderHeight)
        .background(Tokens.Color.Surface.canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Tokens.Color.Separator.region)
                .frame(height: Tokens.Size.hairline)
        }
        // Task P2-T39 — §13.5.4: on activation "the header gains its
        // underline" in the same transition as the column below. The
        // underline is inserted/removed by an `if`, and an inserted view's
        // default transition is a fade, so it fades in or out.
        .animation(RoutineColumnTransition.animation(reduceMotion: reduceMotion), value: activeWeekdays)
    }

    private func weekdaySymbol(_ weekday: Int) -> String {
        Calendar.current.shortWeekdaySymbols[weekday - 1]
    }
}

// MARK: - ⌥⌘I routing (task P2-SF6)

/// What the Routines window publishes for the View menu's inspector command
/// while it is key: whether its editor inspector shows, and how to toggle it.
struct RoutinesInspectorToggle {
    let isVisible: Bool
    let toggle: @MainActor () -> Void
}

extension FocusedValues {
    /// Swift note: `@Entry` generates the key type and accessor (macOS 15).
    @Entry var routinesInspector: RoutinesInspectorToggle?
}

// MARK: - The time gutter (layouts.md §8, amended 2026-10-06; G-041)

/// The Routines canvas's time gutter: hour labels and lines over the window
/// treatments. layouts.md §8 (2026-10-06, DEVIATIONS B22): "Hour grid exactly
/// as §3.1" includes components.md §7 rule 2 — protected fill and edges and
/// the low-energy hatch span the gutter at the window's height, as in the main
/// window. Peak focus's dashed outline does not enter it (an outline of the
/// editable span, not a background), and labels never do (§7).
///
/// The gutter is one strip shared by all seven columns, so — as the main
/// grid's `windowsBackdrop` does — it shows the leading column's windows.
/// Internal (not `private`) so `RoutineGutterStripTests` can render it.
struct RoutineGutterStrip: View {
    let windows: [TimeWindow]
    /// Calendar weekday (1 = Sunday … 7 = Saturday) of the leading column.
    let leadingWeekday: Int
    let hourHeight: CGFloat
    var now: Date = Date()

    var body: some View {
        let day = RoutineWeekLayout.referenceDayStart(weekday: leadingWeekday, now: now)
        TimeGutterView(
            geometry: TimeGeometry(dayStart: day, hourHeight: hourHeight),
            now: now,
            showsNow: false)
            // The full 24h height, so the background below has the gutter's
            // real extent (the labels are placed with offsets and don't
            // give the gutter a layout height of their own).
            .frame(width: Tokens.Size.timeGutterWidth, height: hourHeight * 24, alignment: .top)
            .background(alignment: .top) {
                // Below the labels and hour lines (z-order, §7 table).
                // `showsPeakFocus: false` in both modes: no outline here.
                BackgroundWindowsLayer(
                    windows: windows,
                    day: day,
                    geometry: TimeGeometry(dayStart: day, hourHeight: hourHeight),
                    showsPeakFocus: false)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
    }
}

// MARK: - The seven-column canvas

private struct RoutinesCanvasView: View {
    let weekdays: [Int]
    let template: RoutineTemplate?
    let store: RoutineBlockStore
    @Binding var selection: RoutineBlockSelection?
    let editorMode: RoutinesEditorMode
    let timeWindows: [TimeWindow]
    /// Task P2-T21.
    let timeWindowStore: TimeWindowStore
    @Binding var windowSelection: UUID?
    /// Task P2-T39 — the `Add <Day>` button's action (components.md §13.5.4).
    let onAddWeekday: (Int) -> Void
    /// Task P2-T46 — the focused template-conflict option's preview
    /// (components.md §14.6 → §14.4), or `nil`.
    var conflictPreview: RoutineConflictPreview? = nil
    /// Task P2-F15 — bring a template conflict's block into view.
    var scrollRequest: RoutineScrollRequest? = nil
    /// The viewport in content coordinates, for "wholly in view".
    @State private var visibleRect: CGRect = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// layouts.md §8 (amended 2026-10-06, G-047): open at
    /// `min(07:00, earliestBlockStart − 1h)` and hold it (§3.1's hold) until
    /// the user scrolls; re-targeted only when the template changes.
    @State private var initialHold = InitialScroll.Hold(target: 7 * 60)

    /// Task P2-T38 — the one in-flight block move/resize, owned HERE rather
    /// than by each column. interactions.md §11.1: "The drop preview appears
    /// in every active column at once." Before this task the drag lived in the
    /// originating column's own `@State`, so only that column could see it.
    /// `RoutineBlockDrag` carries no weekday at all (see its doc comment), so
    /// one value is equally valid in all seven columns.
    @State private var blockDrag: RoutineBlockDrag?
    /// Task P2-T38 — how far the vertical scroll view has scrolled, in
    /// points. components.md §13.5.3 pins the inactive-column note "to the top
    /// of the visible region", which a view inside the scroll content can only
    /// do if it knows this number.
    @State private var scrollOffsetY: CGFloat = 0
    /// Task P2-F06 — what each column reported for window-label placement.
    @State private var labelInputs: [Int: ColumnLabelInputs] = [:]

    private let hourHeight = Tokens.Size.hourHeightWeek

    var body: some View {
        GeometryReader { proxy in
            // Same column-floor rule as the main Week view (layouts.md §3.1),
            // just with the Routines window's own floor
            // (`size.routineEditorColumnMin`, 84) rather than
            // `size.dayColumnMin` — components.md §13.1 gives this window a
            // narrower minimum column than the calendar's Week view.
            let available = proxy.size.width - Tokens.Size.timeGutterWidth
            let naturalWidth = available / CGFloat(weekdays.count)
            let columnWidth = max(naturalWidth, Tokens.Size.routineEditorColumnMin)
            let needsHorizontalScroll = columnWidth > naturalWidth

            // `ScrollViewReader` hands out a proxy that can scroll to a
            // view by id (task P2-F15: bringing a template conflict's block
            // into view).
            ScrollViewReader { vertical in
                ScrollView(.vertical) {
                    gridBody(columnWidth: columnWidth)
                        .frame(
                            width: needsHorizontalScroll
                                ? Tokens.Size.timeGutterWidth + columnWidth * CGFloat(weekdays.count)
                                : nil,
                            alignment: .leading)
                        .overlay(alignment: .top) { ConflictScrollAnchors(hourHeight: hourHeight) }
                }
                .scrollIndicators(.automatic)
                // macOS 15 API: calls `action` whenever the value the `of:`
                // closure extracts from the scroll geometry changes. Here that is
                // the content's vertical offset — positive once scrolled down.
                .onScrollGeometryChange(for: CGFloat.self) { scrollGeometry in
                    scrollGeometry.contentOffset.y + scrollGeometry.contentInsets.top
                } action: { _, newOffset in
                    scrollOffsetY = newOffset
                }
                .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, rect in
                    visibleRect = rect
                }
                // The default scroll (G-047). Like the main grid's (P2-F22):
                // the window lays the canvas out several times while it
                // settles and any pass can reset the scroll, so every
                // geometry change re-checks and re-aims while holding. The
                // viewport height is the scroll view's laid-out height
                // (P2-F24: `ScrollGeometry`'s container alternates).
                .onScrollGeometryChange(for: InitialScroll.Position.self) { geometry in
                    InitialScroll.Position(geometry)
                } action: { _, position in
                    if initialHold.shouldAim(position, hourHeight: hourHeight, viewportHeight: proxy.size.height) {
                        aimInitialScroll(using: vertical)
                    }
                }
                // Re-applied when the template changes — including nil → the
                // seeded template on a fresh store — and on open
                // (`initial: true`); NOT on a Blocks/Windows switch or an
                // edit, which change neither the id nor the hold's target.
                .onChange(of: template?.id, initial: true) { _, _ in
                    initialHold.retarget(InitialScroll.minute(
                        blockStartMinutes: template?.blocks.map(\.startMinutes) ?? []))
                    aimInitialScroll(using: vertical)
                }
                // The user's first scroll ends the hold; a programmatic
                // `scrollTo` stays `.idle`.
                .onScrollPhaseChange { _, phase in
                    if phase == .tracking || phase == .interacting || phase == .decelerating {
                        initialHold.release()
                    }
                }
                // `initial: true`: the request is usually set in the same
                // update that opens this window on the conflict.
                .onChange(of: scrollRequest, initial: true) { _, request in
                    if request != nil { initialHold.release() }   // the conflict's scroll wins
                    guard let request,
                          let target = ConflictScroll.targetMinute(
                            occurrence: request.occurrence, earliestStart: request.earliestStart,
                            visibleTop: visibleRect.minY, visibleHeight: visibleRect.height,
                            hourHeight: hourHeight)
                    else { return }
                    withAnimation(ConflictScroll.animation(reduceMotion: reduceMotion)) {
                        vertical.scrollTo(ConflictScroll.anchorID(minute: target), anchor: ConflictScroll.oneThird)
                    }
                }
            }
            .modifier(HorizontalScrollIfNeeded(isEnabled: needsHorizontalScroll))
        }
        .background(Tokens.Color.Surface.canvas)
        // §14.4 via §14.6: while a template option is previewed, the
        // Routines canvas carries the same inset accent border the main
        // canvas does. Same drawing as `MainWindow.canvas`'s overlay.
        .overlay {
            if conflictPreview != nil {
                Rectangle()
                    .strokeBorder(Tokens.Color.Interactive.accent, lineWidth: Tokens.Size.previewCanvasBorder)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    /// One aim at the hold's target, deferred a main-actor turn: inside a
    /// geometry callback the scroll view hasn't finished laying out and a
    /// `scrollTo` then is dropped (P2-F22, found live on the main grid).
    private func aimInitialScroll(using proxy: ScrollViewProxy) {
        let anchor = ConflictScroll.anchorID(minute: initialHold.target)
        Task { @MainActor in
            guard initialHold.isHolding else { return }
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    /// components.md §7 rules 2–3 (task P2-F06; corrected 2026-10-06, G-044,
    /// task P2-SF2). Both modes: a label goes in the leading column whose
    /// label rect no block covers, and under an inactive column's note
    /// (G-025). Blocks mode omits it when every spanned column is covered;
    /// Windows mode (windows are the edited layer) never omits — it falls
    /// back to the leading spanned column, drawn above the dimmed blocks.
    private var placedLabels: [WindowLabelPlacement.Placed] {
        WindowLabelPlacement.place(
            windows: timeWindows,
            columns: weekdays.indices.map { index in
                WindowLabelPlacement.Column(
                    day: RoutineWeekLayout.referenceDayStart(weekday: weekdays[index], now: Date()),
                    blockFrames: labelInputs[index]?.blockFrames ?? [],
                    noteFrame: labelInputs[index]?.noteFrame)
            },
            hourHeight: hourHeight,
            showsPeakFocus: editorMode == .windows,
            omitsWhenCovered: editorMode == .blocks)
    }

    private func gridBody(columnWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            RoutineGutterStrip(
                windows: timeWindows,
                leadingWeekday: weekdays.first ?? Calendar.current.firstWeekday,
                hourHeight: hourHeight)

            ForEach(weekdays, id: \.self) { weekday in
                RoutineDayColumnView(
                    weekday: weekday,
                    template: template,
                    store: store,
                    hourHeight: hourHeight,
                    selection: $selection,
                    editorMode: editorMode,
                    timeWindows: timeWindows,
                    timeWindowStore: timeWindowStore,
                    windowSelection: $windowSelection,
                    blockDrag: $blockDrag,
                    onAddWeekday: onAddWeekday,
                    conflictPreview: conflictPreview,
                    showsDropPreview: RoutineBlockDrag.previewWeekdays(
                        orderedWeekdays: weekdays,
                        activeWeekdays: template?.activeWeekdays ?? []
                    ).contains(weekday),
                    scrollOffsetY: scrollOffsetY,
                    // components.md §7 rules 2–3 (task P2-F06): the labels
                    // this column draws, placed canvas-wide by
                    // `placedLabels` — the same placement the main grid uses.
                    windowLabels: placedLabels.filter { $0.columnIndex == weekdays.firstIndex(of: weekday) },
                    columnIndex: weekdays.firstIndex(of: weekday) ?? 0)
                    .frame(width: columnWidth)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Tokens.Color.Separator.dayDivider)
                            .frame(width: Tokens.Size.hairline)
                    }
            }
        }
        // See `ColumnLabelInputsKey`: each column's block and note frames.
        .onPreferenceChange(ColumnLabelInputsKey.self) { inputs in
            labelInputs = inputs
        }
    }
}

/// One weekday column: the hour grid, whichever of the template's blocks land
/// on this weekday, and (task P2-T20) that weekday's `TimeWindow` spans. No
/// now-line, no all-day row, no travel bands.
///
/// Move/resize (task P2-T11) mirror `DayColumnView.blockGesture`'s shape —
/// same handle-height mode classification, same snap, same drop preview — but
/// write through `RoutineBlockStore` in minutes instead of `EventStore` in
/// `Date`s. Because a block dragged from *any* one of the template's active
/// weekday columns changes the one underlying `RoutineBlock`, the edit is
/// still correct even though this view only ever sees a single column's worth
/// of geometry.
///
/// Create (task P2-T12) mirrors `DayColumnView.createSurface` the same way:
/// double-click or drag on the empty grid begins a local `EventDraft` (this
/// view's own `@State`, not `CalendarState.draft`), rendered through the same
/// `DraftBlockView`. Which weekday column the gesture starts in only decides
/// *whose* geometry supplies the snapped startMinutes/duration read on commit
/// — a `RoutineBlock` has no per-weekday instance (see this type's own header
/// above), so the resulting block, once created, appears on every one of the
/// template's active weekdays immediately, the same as every other block.
private struct RoutineDayColumnView: View {
    let weekday: Int
    let template: RoutineTemplate?
    let store: RoutineBlockStore
    let hourHeight: CGFloat
    @Binding var selection: RoutineBlockSelection?
    let editorMode: RoutinesEditorMode
    let timeWindows: [TimeWindow]
    /// Task P2-T21.
    let timeWindowStore: TimeWindowStore
    @Binding var windowSelection: UUID?
    /// Task P2-T38 — the canvas-wide block move/resize (see
    /// `RoutinesCanvasView.blockDrag`). A `@Binding` because every column
    /// reads it to draw the preview and the origin ghost, and whichever column
    /// the drag started in writes it.
    @Binding var blockDrag: RoutineBlockDrag?
    /// Task P2-T39 — the note's `Add <Day>` action (components.md §13.5.4).
    let onAddWeekday: (Int) -> Void
    /// Task P2-T46 — see `RoutinesCanvasView.conflictPreview`.
    let conflictPreview: RoutineConflictPreview?
    /// Whether this column draws `blockDrag`'s drop preview — true for every
    /// active column, false for an inactive one (interactions.md §11.1).
    let showsDropPreview: Bool
    /// Vertical scroll offset of the canvas, for pinning the §13.5.3 note.
    let scrollOffsetY: CGFloat
    /// Task P2-F06 — this column's placed window labels, and its index.
    let windowLabels: [WindowLabelPlacement.Placed]
    let columnIndex: Int
    /// The §13.5.3 note's measured size, for §7 rule 3's stacking.
    @State private var noteSize: CGSize = .zero

    /// In-flight create-drag, kept local so nothing is written until drop —
    /// same rule as `DayColumnView.DragSession`. Create stays per-column
    /// (unlike `blockDrag`): it begins a draft in the column it was made in,
    /// and an inactive column refuses it outright.
    @State private var drag: RoutineDragSession?
    @State private var hoveredID: UUID?
    /// `@Environment` reads a value SwiftUI supplies from outside the view —
    /// here the system's Reduce Motion setting, which changes
    /// `RoutineColumnTransition` (task P2-T39).
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// The in-flight creation draft, if any (task P2-T12). Local to this one
    /// weekday column, exactly the way `drag` above is — nothing persists
    /// until `commitDraft()` calls into `RoutineBlockStore.create`.
    @State private var draft: EventDraft?
    /// In-flight `TimeWindow` drag (task P2-T21 move; task P2-T22 adds
    /// resize) — same nothing-written-until-drop rule as `drag` above, but
    /// this one only ever carries a live pixel translation for the
    /// ring/hit-region to follow visually; the actual minute delta is
    /// computed once, at `.onEnded`, exactly the way `blockGesture` computes
    /// its snapped result at drop rather than on every frame.
    @State private var windowDrag: TimeWindowDragSession?
    /// In-flight drag-to-create on empty windows-mode canvas (task P2-T23) —
    /// its own small session, deliberately NOT folded into `TimeWindowDragSession`
    /// above, which is move/resize-only for an EXISTING window and is keyed by
    /// `windowID`; there is no id yet for a window that does not exist until
    /// `.onEnded`. Same nothing-written-until-drop rule as `drag`/`windowDrag`.
    @State private var windowCreateDrag: TimeWindowCreateDragSession?

    /// Create-drag only, as of task P2-T38. Move/resize moved to the shared,
    /// minute-based `RoutineBlockDrag` (`RoutineColumnRules.swift`).
    struct RoutineDragSession: Equatable {
        var origin: Date
        var current: Date
    }

    struct TimeWindowDragSession: Equatable {
        /// Analogous to `RoutineBlockDrag.Mode` — a
        /// `TimeWindow` is never created from this drag (task P2-T22).
        /// Classified once, from the drag's `startLocation` against the
        /// dragged span's own top/bottom `Tokens.Size.blockResizeHandleHeight`
        /// band, the same way `blockGesture` classifies `RoutineBlockDrag.Mode`.
        enum Mode: Equatable { case move, resizeTop, resizeBottom }
        var windowID: UUID
        var mode: Mode
        var translationHeight: CGFloat
    }

    /// Task P2-T23 — drag-to-create on empty windows-mode canvas. Mirrors
    /// `RoutineDragSession`'s create-drag shape (`origin`/`current`
    /// snapped `Date`s, nothing written until `.onEnded`), kept as its own
    /// type rather than a third case bolted onto `TimeWindowDragSession`
    /// above, which addresses an EXISTING window by `windowID` — a window
    /// being created has none yet.
    struct TimeWindowCreateDragSession: Equatable {
        var origin: Date
        var current: Date
    }

    private var referenceDayStart: Date {
        RoutineWeekLayout.referenceDayStart(weekday: weekday, now: Date())
    }

    private var blocks: [RoutineBlockSnapshot] {
        template?.blocks.map(\.snapshot) ?? []
    }

    /// Whether this column's weekday is one of the template's active
    /// weekdays, regardless of editor mode. (Commit 5b73949 introduced this
    /// as a hand fix for the silent-relocation defect; task P2-T38 keeps it
    /// and puts the spec behind it — components.md §13.5.1.)
    private var isActiveDay: Bool {
        template?.activeWeekdays.contains(weekday) ?? false
    }

    /// components.md §13.5.2 / §13.5.5 — what this column shows and accepts.
    private var treatment: RoutineColumnTreatment {
        RoutineColumnTreatment.resolve(
            weekday: weekday, activeWeekdays: template?.activeWeekdays ?? [], mode: editorMode)
    }

    private var layoutItems: [LayoutItem] {
        var items = RoutineWeekLayout.layoutItems(
            blocks: blocks,
            activeWeekdays: template?.activeWeekdays ?? [],
            weekday: weekday,
            referenceDayStart: referenceDayStart)
        // The draft is laid out only on active weekday columns. This is a
        // second lock, not the main one: the create surface is refused on
        // inactive columns, and a draft whose column is deactivated is
        // abandoned outright (`.onChange(of: isActiveDay)` in `body`,
        // interactions.md §11.1). This guard only covers the single frame
        // between the weekday set changing and that `onChange` running.
        if let draft, isActiveDay {
            items.append(LayoutItem(id: draft.id, start: draft.start, end: draft.end, title: draft.title))
        }
        return items
    }

    var body: some View {
        GeometryReader { proxy in
            let geometry = TimeGeometry(dayStart: referenceDayStart, hourHeight: hourHeight)
            let layout = DayLayoutEngine.layout(
                items: layoutItems, columnWidth: proxy.size.width, geometry: geometry)

            ZStack(alignment: .topLeading) {
                // components.md §7 / §13.3 (task P2-T20): background windows,
                // drawn below the hour lines and below every block, same as
                // the main grid's z-order. Blocks mode draws protected/
                // low-energy only, "not hit-testable" — the same treatment
                // Phase 1's main grid already uses. Windows mode adds
                // peak-focus too (§7's "Editor exception"); neither mode
                // makes a window selectable or draggable yet (deferred, see
                // this file's header).
                BackgroundWindowsLayer(
                    windows: timeWindows,
                    day: referenceDayStart,
                    geometry: geometry,
                    showsPeakFocus: editorMode == .windows)
                    .allowsHitTesting(false)

                // §13.5.2: an inactive column (Blocks mode only) recedes by
                // drawing its hour lines at half-hour weight. The ground is
                // left alone — `RoutinesCanvasView`'s `color.surface.canvas`
                // background shows through unchanged, on purpose (DECISIONS.md
                // 2026-10-01: `canvasSunken` would hide protected windows).
                HourLinesLayer(geometry: geometry, recessed: treatment.recessesHourLines)

                // §7 rule 2: in Blocks mode labels sit below the blocks
                // (placed where none covers them). Windows mode draws them
                // above the dimmed block layer instead — see below.
                if editorMode == .blocks {
                    WindowLabelsLayer(labels: windowLabels)
                }

                // Empty-grid tap deselects, matching the main grid's
                // "clicking empty grid deselects" (interactions.md §6).
                // Double-click / drag create (task P2-T12, interactions.md
                // §3 via §11.1). Windows mode (task P2-T20) turns this off:
                // §13.3 — in windows mode routine blocks are not the editable
                // layer, so creating one from here would be editing the
                // wrong layer.
                //
                // Task P2-T38 — interactions.md §11.1, "Gestures on an
                // inactive column are refused": an inactive column gets a
                // different surface that accepts no create gesture at all
                // (no block, no draft, no outline) and shows
                // `.operationNotAllowed`. Its only response is the ordinary
                // empty-grid tap-to-deselect, which is not a create gesture.
                if treatment.refusesBlockCreate {
                    refusedCreateSurface(geometry: geometry)
                } else {
                    createSurface(width: proxy.size.width, geometry: geometry)
                        .allowsHitTesting(treatment.acceptsBlockCreate)
                }

                // components.md §13.3: "Windows mode: ... blocks drop to
                // `opacity.editorInactiveLayer`, not hit-testable." Applied
                // to the whole block/draft/overflow layer together so the
                // dimming reads as one layer, not a block-by-block toggle.
                Group {
                    ForEach(layout.blocks.sorted(by: { $0.zIndex < $1.zIndex })) { laidOut in
                        if let block = blocks.first(where: { $0.id == laidOut.id }) {
                            blockView(block: block, laidOut: laidOut, geometry: geometry)
                        } else if let draft, draft.id == laidOut.id {
                            draftBlock(laidOut: laidOut)
                        }
                    }

                    ForEach(layout.overflow) { chip in
                        overflowChip(chip)
                    }
                }
                .opacity(editorMode == .windows ? Tokens.Opacity.editorInactiveLayer : 1)
                .allowsHitTesting(editorMode == .blocks)

                // §7 rule 2, Windows mode (corrected 2026-10-06, G-044):
                // labels are drawn above the dimmed block layer, placed by
                // the same column scan as Blocks mode, never omitted.
                if editorMode == .windows {
                    WindowLabelsLayer(labels: windowLabels)
                }

                // components.md §14.6: "the previewed block in every active
                // column at once" — §14.4's `previewed` twin at the proposed
                // frame, in the same columns a drag preview uses
                // (`showsDropPreview`). `remove` proposes no frame, so it is
                // the ghost alone (§14.4's destination-less rule).
                if showsDropPreview, let twin = conflictTwin(width: proxy.size.width, geometry: geometry) {
                    twin
                }

                // interactions.md §4 — "same drop preview" as the main grid's
                // move/resize (the outline only; the main grid itself has no
                // time badge yet — DEVIATIONS.md A15 — so there is nothing
                // extra to mirror here). Drag/resize only ever runs in
                // Blocks mode (createSurface/blockGesture are non-hit-
                // testable in Windows mode above), so `drag` is always nil
                // there and this never fires in Windows mode either.
                //
                // Task P2-T38 — interactions.md §11.1: a move/resize preview
                // is drawn "in every active column at once"; none in an
                // inactive column. `showsDropPreview` is that rule, computed
                // once by the canvas. The create-drag preview stays local to
                // the one column the drag runs in.
                if let previewRect = createPreviewFrame(in: proxy.size.width, geometry: geometry) {
                    dropPreview(previewRect)
                }
                if showsDropPreview,
                   let previewRect = blockDragPreviewFrame(in: proxy.size.width, geometry: geometry) {
                    dropPreview(previewRect)
                }

                // components.md §13.3 / task P2-T21: in Windows mode, an
                // existing protected/low-energy/peak-focus `TimeWindow` is
                // now selectable and whole-span draggable. Tapping empty
                // windows-mode canvas deselects — same "clicking empty grid
                // deselects" rule `createSurface`'s own tap already applies
                // to blocks mode, mirrored here rather than reusing
                // `createSurface` itself (which stays exclusively the
                // create-a-block surface, disabled in Windows mode above).
                // Drawn BELOW the per-window hit regions so a tap that lands
                // inside an actual window span hits that window first — same
                // z-order reasoning `createSurface`/the block `Group` already
                // use for the analogous blocks-mode case.
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .frame(height: geometry.totalHeight)
                    .accessibilityHidden(true)
                    .onTapGesture { windowSelection = nil }
                    // components.md §13.3 / task P2-T23: "Creating one: drag
                    // on empty canvas..." — a sibling to `createSurface`'s own
                    // create-drag below, on the same Rectangle whose tap
                    // already deselects, active only in Windows mode via the
                    // `.allowsHitTesting` this Rectangle already carried.
                    .gesture(windowCreateGesture(geometry: geometry))
                    .allowsHitTesting(editorMode == .windows)

                // Live dashed preview for the drag-to-create above — mirrors
                // `dropPreview`/`createPreviewFrame`'s own mechanism for
                // blocks-mode create, keyed off `windowCreateDrag` instead of
                // `drag` so the two never interfere (one only ever runs in
                // Blocks mode, the other only in Windows mode).
                if let previewRect = windowCreatePreviewFrame(in: proxy.size.width, geometry: geometry) {
                    dropPreview(previewRect)
                }

                windowInteractionLayer(geometry: geometry)
                    .allowsHitTesting(editorMode == .windows)

                // components.md §13.5.3 — one note per inactive column,
                // pinned to the top of the *visible* region: `scrollOffsetY`
                // is how far the canvas has scrolled, so offsetting by it
                // keeps the note on screen however far down the user is.
                // Inset `spacing.xs` from the column's leading edge and from
                // that visible top. Drawn last so the `Add` button sits above
                // the refusal surface and is clickable.
                if treatment.showsInactiveNote {
                    // Task P2-T39 — components.md §13.5.4: adds this weekday
                    // to the template, as one `Add Saturday to Routine` step.
                    InactiveDayNote(weekday: weekday, onAdd: { onAddWeekday(weekday) })
                    // Task P2-F06: the note's real size, for §7 rule 3.
                    // `onGeometryChange` reports the measured size whenever
                    // it changes (wrapping, Dynamic Type).
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { noteSize = $0 }
                    .padding(.leading, Tokens.Spacing.xs)
                    .offset(y: max(scrollOffsetY, 0) + Tokens.Spacing.xs)
                }
            }
            .frame(height: geometry.totalHeight, alignment: .top)
            // §7 rules 2–3 (task P2-F06): report block frames and, on an
            // inactive column, the note's frame — where it is drawn above.
            .preference(
                key: ColumnLabelInputsKey.self,
                value: [columnIndex: ColumnLabelInputs(
                    blockFrames: layout.blocks.map(\.frame),
                    noteFrame: treatment.showsInactiveNote
                        ? CGRect(origin: CGPoint(x: Tokens.Spacing.xs,
                                                 y: max(scrollOffsetY, 0) + Tokens.Spacing.xs),
                                 size: noteSize)
                        : nil)])
            // Task P2-T39 — components.md §13.5.4: when this column's weekday
            // is activated, "every block in the template appears in the
            // column at once, over `motion.viewChange` (0.16, easeInOut,
            // opacity only)"; deactivation "runs the same transition in
            // reverse". `.animation(_:value:)` animates every change in this
            // subtree that happens in the same update as `isActiveDay`
            // changing — and only those. The blocks and the note come and go
            // through `ForEach`/`if`, whose default insertion/removal
            // transition is `.opacity`; the hour-line colour interpolates.
            // Keyed on the weekday set rather than on the click, so `⌘Z` and
            // `⌘⇧Z` animate the same way.
            .animation(RoutineColumnTransition.animation(reduceMotion: reduceMotion), value: isActiveDay)
        }
        .frame(height: hourHeight * 24)
        // interactions.md §11.1: "A draft whose column is deactivated
        // mid-edit is abandoned ... if the surface went away, you did not
        // decide." `.onChange` runs its closure whenever the observed value
        // changes between renders. Any half-finished create-drag goes too —
        // it would otherwise turn into a draft on mouse-up.
        .onChange(of: isActiveDay) { _, _ in
            guard let activeWeekdays = template?.activeWeekdays,
                  RoutineDraftRules.mustAbandonDraft(draftWeekday: weekday, activeWeekdays: activeWeekdays)
            else { return }
            draft = nil
            drag = nil
        }
    }

    @ViewBuilder
    private func blockView(block: RoutineBlockSnapshot, laidOut: LaidOutBlock, geometry: TimeGeometry) -> some View {
        let start = referenceDayStart.addingTimeInterval(TimeInterval(block.startMinutes * 60))
        let model = GridBlockModel(
            id: block.id,
            title: block.title,
            start: start,
            end: start.addingTimeInterval(block.duration),
            locationName: nil,
            kind: .routineTimed,
            flexibility: block.flexibility,
            // No "now" concept applies to an abstract weekly template, so
            // every block reads as plainly `.scheduled` — none of
            // done/skipped/in-progress make sense without a real date.
            status: .scheduled,
            source: template?.sourceKey ?? .graphite,
            // components.md §13.1: "the routine's own palette slot, one hue
            // for the whole template" — the template's own name stands in for
            // `sourceName` (there is no separate source-catalogue entry for a
            // routine template), so the meta line and hover help read
            // "<Template name>" rather than a per-source name.
            sourceName: template?.name ?? "Routine",
            glyphOverride: nil,
            // task P2-T11: move/resize now reuse §3/§4 unchanged, so a
            // routine block is movable exactly like an ordinary event.
            // `GridBlockView` already draws its hover resize handles once
            // `isMovable` is true — no new chrome needed here.
            isMovable: true,
            // §11 / §13.6.2: here `.conflicted` always means "lands in a
            // protected window on this column's weekday", so the spoken
            // label names that kind (task P2-T41).
            conflicts: ProtectedWindowRule.refusingWindows(
                startMinutes: block.startMinutes, duration: block.duration,
                weekday: weekday, windows: timeWindows)
                .map { .protectedWindow(label: $0.label) })
        let isSelected = selection?.blockID == block.id && selection?.weekday == weekday

        GridBlockView(
            model: model,
            presentation: presentation(for: block, isSelected: isSelected),
            renderedHeight: laidOut.frame.height,
            visibleWidth: laidOut.visibleWidth)
            .frame(width: laidOut.frame.width, height: laidOut.frame.height, alignment: .topLeading)
            .contentShape(Rectangle().inset(by: laidOut.hitInset))
            .offset(x: laidOut.frame.minX, y: laidOut.frame.minY)
            // The origin ghost, `opacity.blockDragOrigin` — shown in EVERY
            // column that draws this block, because `blockDrag` is shared
            // (interactions.md §11.1: "with the origin ghost at
            // `opacity.blockDragOrigin` in each of them too").
            .opacity(blockDrag?.blockID == block.id || conflictPreview?.blockID == block.id
                     ? Tokens.Opacity.blockDragOrigin : 1)
            // interactions.md §8 — open-hand cursor for a draggable block.
            .cursor(.openHand)
            .onHover { hovering in
                hoveredID = hovering ? block.id : (hoveredID == block.id ? nil : hoveredID)
            }
            .onTapGesture {
                selection = RoutineBlockSelection(blockID: block.id, weekday: weekday)
            }
            .gesture(blockGesture(block: block, laidOut: laidOut, geometry: geometry))
    }

    /// Plain (non-`@ViewBuilder`) helper, same reason `DayColumnView.presentation(for:laidOut:)`
    /// is one: `if` statements that only mutate a value, not build a view,
    /// cannot live inside a `@ViewBuilder`-attributed function body.
    private func presentation(for block: RoutineBlockSnapshot, isSelected: Bool) -> Presentation {
        var presentation: Presentation = isSelected ? [.selected] : []
        if hoveredID == block.id { presentation.insert(.hovered) }
        if blockDrag?.blockID == block.id { presentation.insert(.dragging) }
        // components.md §13.6.2 (task P2-T40): a block whose interval overlaps
        // a `.protected` window on THIS column's weekday takes §6's
        // `conflicted` state, in exactly the colliding columns. It's the same
        // rule `RoutineEngine.materialize` uses to refuse the pair, so a
        // conflicted block here is exactly a day the calendar won't get.
        // Blocks are drawn only in active columns, so an inactive column
        // never shows this.
        if ProtectedWindowRule.refuses(
            startMinutes: block.startMinutes, duration: block.duration,
            weekday: weekday, windows: timeWindows) {
            presentation.insert(.conflicted)
        }
        return presentation
    }

    // MARK: Gesture (mirrors DayColumnView.blockGesture's shape)

    /// Move/resize. Task P2-T38 — interactions.md §11.1: "A block drag is
    /// vertical only. Horizontal translation is ignored outright." Only
    /// `value.translation.height` is ever read below, and the session it
    /// writes (`RoutineBlockDrag`) has no weekday to change — so dragging
    /// sideways, into another column active or inactive, does nothing there.
    /// The session is the canvas-wide `blockDrag`, so every active column
    /// draws the same preview while the drag runs.
    private func blockGesture(block: RoutineBlockSnapshot, laidOut: LaidOutBlock, geometry: TimeGeometry) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let snap = NSEvent.modifierFlags.contains(.control) ? 5 : 15

                if blockDrag?.blockID != block.id {
                    // First change of this drag: classify the mode once, from
                    // where the pointer went down relative to the block's own
                    // top/bottom resize-handle bands.
                    let handle = Tokens.Size.blockResizeHandleHeight
                    let localY = value.startLocation.y - laidOut.frame.minY
                    let mode: RoutineBlockDrag.Mode =
                        localY <= handle ? .resizeTop
                        : localY >= laidOut.frame.height - handle ? .resizeBottom
                        : .move
                    blockDrag = RoutineBlockDrag(
                        blockID: block.id, mode: mode,
                        startMinutes: block.startMinutes,
                        durationMinutes: Int(block.duration / 60))
                }
                blockDrag = blockDrag?.updated(
                    translationHeight: value.translation.height,
                    hourHeight: hourHeight,
                    snapMinutes: snap)
            }
            .onEnded { _ in
                defer { blockDrag = nil }
                guard let session = blockDrag, session.blockID == block.id,
                      let template, let liveBlock = template.blocks.first(where: { $0.id == block.id })
                else { return }

                // `proposedRange` already applies the store's own clamps, so
                // what was previewed is exactly what is written.
                let range = session.proposedRange
                switch session.mode {
                case .move:
                    store.move(liveBlock, toStartMinutes: range.start)
                case .resizeTop:
                    store.resize(liveBlock, newStartMinutes: range.start)
                case .resizeBottom:
                    store.resize(liveBlock, newEndMinutes: range.end)
                }
                selection = RoutineBlockSelection(blockID: block.id, weekday: weekday)
            }
    }

    private func minutes(for date: Date) -> Int {
        Int(date.timeIntervalSince(referenceDayStart) / 60)
    }

    // MARK: TimeWindow select / move / resize (tasks P2-T21, P2-T22)
    //
    // components.md §13.3: "protected / low-energy / peak-focus regions
    // editable" in Windows mode — select, whole-span move, top/bottom-edge
    // resize, `⌫` delete for an EXISTING row. Drag-to-create a NEW row is
    // task P2-T23's job, below (see `windowCreateGesture`/`createSurface`'s
    // own note at its call site). No kind picker, no weekday-set editing
    // beyond a single default, no label editing — still explicitly out of
    // scope, next task's job.

    /// One hit-testable, selectable, draggable region per `(window, span)` —
    /// a window can produce more than one span on a given day when it wraps
    /// past midnight (`TimeWindow.spans(on:calendar:)`'s own doc comment),
    /// and each rendered span gets its own independent hit region and ring,
    /// same as `BackgroundWindowsLayer` already draws each span independently.
    @ViewBuilder
    private func windowInteractionLayer(geometry: TimeGeometry) -> some View {
        ForEach(timeWindows, id: \.id) { window in
            let spans = window.spans(on: referenceDayStart)
            ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                windowHitRegion(window: window, span: span, geometry: geometry)
            }
        }
    }

    private func windowHitRegion(window: TimeWindow, span: (start: Date, end: Date), geometry: TimeGeometry) -> some View {
        let y = geometry.y(for: span.start)
        let height = max(geometry.height(from: span.start, to: span.end), 0)
        let isSelected = windowSelection == window.id
        // Live visual feedback only — nothing is written to the store until
        // `.onEnded`. Only the region belonging to the window actually being
        // dragged follows the pointer; every other window (and every other
        // span of the *same* wrapping window) stays put. A `.move` drag
        // translates the whole region; `.resizeTop`/`.resizeBottom` (task
        // P2-T22) instead grow/shrink it from the edge being dragged, so the
        // opposite edge visibly stays put while the pointer moves — the same
        // "handle moves one edge, body moves the whole span" split
        // `blockGesture`'s own drop preview already gives routine blocks.
        let feedback = liveWindowFeedback(for: window)
        let liveHeight = max(height + feedback.heightDelta, 0)
        let liveY = y + feedback.offset

        return Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .frame(height: liveHeight)
            .frame(maxWidth: .infinity)
            // Selection ring — the app's one existing generic selection
            // vocabulary (`Tokens.Color.Interactive.focusRing` /
            // `Tokens.Size.borderSelected`), drawn outside the bounds with a
            // 1pt gap exactly as `GridBlockView.swift`'s own `.selected`
            // overlay does. `Rectangle`, not `RoundedRectangle`, because every
            // window treatment already on this canvas (`BackgroundWindowsLayer`'s
            // `protectedSpan`/`lowEnergySpan`/`peakFocusSpan`) draws a plain
            // rectangle with no corner radius — there is no window-specific
            // radius token to reuse instead, and inventing one only for the
            // ring would contradict the very regions it rings.
            .overlay {
                if isSelected {
                    Rectangle()
                        .strokeBorder(Tokens.Color.Interactive.focusRing, lineWidth: Tokens.Size.borderSelected)
                        .padding(-(Tokens.Size.borderSelected + 1))
                        .allowsHitTesting(false)
                }
            }
            .offset(y: liveY)
            .accessibilityHidden(true)
            .onTapGesture { windowSelection = window.id }
            .gesture(windowGesture(window: window, span: span, geometry: geometry))
    }

    /// The live pixel translation/height-delta `windowHitRegion` applies for
    /// `window`, or all-zero when no drag is in flight for it (task P2-T22).
    private func liveWindowFeedback(for window: TimeWindow) -> (offset: CGFloat, heightDelta: CGFloat) {
        guard let windowDrag, windowDrag.windowID == window.id else { return (0, 0) }
        switch windowDrag.mode {
        case .move:
            return (windowDrag.translationHeight, 0)
        case .resizeTop:
            // The top edge follows the pointer; the bottom edge (`y + height`)
            // must stay fixed, so the region's height shrinks by exactly the
            // same amount its top moves down.
            return (windowDrag.translationHeight, -windowDrag.translationHeight)
        case .resizeBottom:
            // The bottom edge follows the pointer; the top stays fixed, so
            // only the height changes.
            return (0, windowDrag.translationHeight)
        }
    }

    /// Whole-span move, or a top/bottom-edge resize (task P2-T22) — mode is
    /// classified once from the drag's `startLocation` against `span`'s own
    /// top/bottom `Tokens.Size.blockResizeHandleHeight` band, exactly the way
    /// `blockGesture` classifies `RoutineBlockDrag.Mode`. Snap (15-minute,
    /// 5-minute with `⌃`) via `TimeGeometry.snap`, same rule every other drag
    /// in this window already uses, and only written to `TimeWindowStore` on
    /// `.onEnded` — `windowDrag` exists purely so the hit region can follow
    /// the pointer live in between.
    ///
    /// `span` is whichever single rendered span of `window` the pointer went
    /// down on — a wrapping window can render two (`spans(on:)`'s own doc
    /// comment). Per this task's own brief, that is not special-cased further:
    /// a top-edge drag always resizes `window.startMinutes`, a bottom-edge
    /// drag always resizes `window.endMinutes`, measured from `span.start`/
    /// `span.end` respectively — correct for the common (non-wrapping)
    /// case, and `TimeWindowStore.resize`'s own modular arithmetic is what
    /// makes the render layer recompute both spans from the result either way.
    private func windowGesture(window: TimeWindow, span: (start: Date, end: Date), geometry: TimeGeometry) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let handle = Tokens.Size.blockResizeHandleHeight
                let spanY = geometry.y(for: span.start)
                let spanHeight = max(geometry.height(from: span.start, to: span.end), 0)
                let localY = value.startLocation.y - spanY
                let mode: TimeWindowDragSession.Mode =
                    localY <= handle ? .resizeTop
                    : localY >= spanHeight - handle ? .resizeBottom
                    : .move
                windowDrag = TimeWindowDragSession(windowID: window.id, mode: mode, translationHeight: value.translation.height)
            }
            .onEnded { value in
                defer { windowDrag = nil }
                guard let mode = windowDrag?.mode else { return }
                let snap = NSEvent.modifierFlags.contains(.control) ? 5 : 15
                let deltaTime = TimeInterval(value.translation.height / hourHeight) * 3600
                windowSelection = window.id

                switch mode {
                case .move:
                    // `referenceDayStart` is just a stable anchor here —
                    // snapping and then differencing against the same anchor
                    // yields the correct elapsed minute delta regardless of
                    // which calendar day `TimeGeometry.snap` resolves
                    // internally, the same reasoning `blockGesture`/
                    // `minutes(for:)` already rely on.
                    let snapped = TimeGeometry.snap(referenceDayStart.addingTimeInterval(deltaTime), toMinutes: snap)
                    let deltaMinutes = Int(snapped.timeIntervalSince(referenceDayStart) / 60)
                    timeWindowStore.move(window, byDeltaMinutes: deltaMinutes)
                case .resizeTop:
                    let snapped = TimeGeometry.snap(span.start.addingTimeInterval(deltaTime), toMinutes: snap)
                    let deltaMinutes = Int(snapped.timeIntervalSince(span.start) / 60)
                    timeWindowStore.resize(window, newStartMinutes: window.startMinutes + deltaMinutes)
                case .resizeBottom:
                    let snapped = TimeGeometry.snap(span.end.addingTimeInterval(deltaTime), toMinutes: snap)
                    let deltaMinutes = Int(snapped.timeIntervalSince(span.end) / 60)
                    timeWindowStore.resize(window, newEndMinutes: window.endMinutes + deltaMinutes)
                }
            }
    }

    // MARK: TimeWindow create (task P2-T23)
    //
    // components.md §13.3: "Creating one: drag on empty canvas, then pick the
    // kind from the inspector." Only the drag half — this always creates a
    // `.protected`-kind, empty-label `TimeWindow` scoped to exactly this
    // column's own `weekday`, never propagated to any other day. Mirrors
    // `createSurface`'s own drag-to-create `DragGesture` below (same snap,
    // same 15-minute floor via `max(upper.timeIntervalSince(lower), 15*60)`,
    // same "commit at `.onEnded`, nothing written mid-drag" shape) rather than
    // `windowGesture` above, which addresses an EXISTING window.

    /// Snaps `value.startLocation`/`value.location` the same 15-minute (or
    /// 5-minute with `⌃`) way `createSurface`/`windowGesture` both already do,
    /// via `TimeGeometry.snap`; on drop, floors the dragged duration to 15
    /// minutes (`commitDraft`'s own pattern) and creates a new `TimeWindow`
    /// over this column's single `weekday`, selecting it on success.
    private func windowCreateGesture(geometry: TimeGeometry) -> some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                let snap = NSEvent.modifierFlags.contains(.control) ? 5 : 15
                let from = TimeGeometry.snap(geometry.date(forY: value.startLocation.y), toMinutes: snap)
                let to = TimeGeometry.snap(geometry.date(forY: value.location.y), toMinutes: snap)
                windowCreateDrag = TimeWindowCreateDragSession(origin: from, current: to)
            }
            .onEnded { _ in
                defer { windowCreateDrag = nil }
                guard let session = windowCreateDrag else { return }
                let lower = min(session.origin, session.current)
                let upper = max(session.origin, session.current)
                let duration = max(upper.timeIntervalSince(lower), 15 * 60)
                let startMinutes = minutes(for: lower)
                // Wrapped mod 1440 rather than left to run past it, for the
                // same reason `TimeWindowStore`'s own `wrapMinutes` wraps
                // rather than clamps (this file's header, and
                // `TimeWindowStore.swift`'s own): a `TimeWindow` already
                // supports a span past midnight via `endMinutes < startMinutes`,
                // so a drag that starts within the last 15 minutes of the day
                // (the only way the floored `duration` can push the raw sum
                // past 1440) wraps into the small hours instead of producing
                // an out-of-range `endMinutes` the model was never meant to
                // hold.
                let rawEnd = startMinutes + Int(duration / 60)
                let endMinutes = ((rawEnd % 1440) + 1440) % 1440
                if let created = timeWindowStore.create(
                    weekdays: [weekday], startMinutes: startMinutes, endMinutes: endMinutes) {
                    windowSelection = created.id
                }
            }
    }

    /// Live dashed preview for `windowCreateGesture` above — same geometry
    /// math as `createPreviewFrame`, just keyed off
    /// `windowCreateDrag` instead of `drag` (blocks-mode create's own session
    /// type), rendered through the same `dropPreview(_:)` view.
    private func windowCreatePreviewFrame(in width: CGFloat, geometry: TimeGeometry) -> CGRect? {
        guard let session = windowCreateDrag else { return nil }
        let lower = min(session.origin, session.current)
        let upper = max(session.origin, session.current)
        let inset = Tokens.Spacing.xxs
        return CGRect(
            x: inset, y: geometry.y(for: lower),
            width: width - 2 * inset,
            height: max(geometry.height(from: lower, to: upper), Tokens.Size.blockMinRenderedHeight))
    }

    // MARK: Create (task P2-T12, mirrors DayColumnView.createSurface)

    /// Empty grid: double-click or drag creates a new `RoutineBlock`.
    /// interactions.md §11.1: "Creating ... uses §3 ... unchanged" — §3's own
    /// model (double-click = 60 minutes at the snapped slot; drag = the
    /// dragged duration, 15-minute minimum) is reused verbatim, just writing
    /// into a local `EventDraft` instead of `CalendarState.draft`.
    private func createSurface(width: CGFloat, geometry: TimeGeometry) -> some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .frame(height: geometry.totalHeight)
            .cursor(.crosshair)
            .accessibilityHidden(true)
            .onTapGesture(count: 2) { location in
                let start = TimeGeometry.snap(geometry.date(forY: location.y), toMinutes: 15)
                beginDraft(at: start)
            }
            .onTapGesture { selection = nil }
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        let snap = NSEvent.modifierFlags.contains(.control) ? 5 : 15
                        let from = TimeGeometry.snap(geometry.date(forY: value.startLocation.y), toMinutes: snap)
                        let to = TimeGeometry.snap(geometry.date(forY: value.location.y), toMinutes: snap)
                        drag = RoutineDragSession(origin: from, current: to)
                    }
                    .onEnded { _ in
                        defer { drag = nil }
                        guard let session = drag else { return }
                        let lower = min(session.origin, session.current)
                        let upper = max(session.origin, session.current)
                        let duration = max(upper.timeIntervalSince(lower), 15 * 60)
                        beginDraft(at: lower, duration: duration)
                    }
            )
    }

    /// Task P2-T38 — the inactive column's empty canvas (Blocks mode only).
    /// interactions.md §11.1: "Double-click and create-drag on the empty
    /// canvas of an inactive column do nothing: no block, no draft, no
    /// outline. The cursor over that canvas is `.operationNotAllowed`."
    /// So: no double-click handler and no drag gesture are attached at all —
    /// there is nothing to begin a draft or draw an outline from. It still
    /// takes a single tap as "clicking empty grid deselects" (§6), which is
    /// not a create gesture.
    private func refusedCreateSurface(geometry: TimeGeometry) -> some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .frame(height: geometry.totalHeight)
            .cursor(.operationNotAllowed)
            .accessibilityHidden(true)
            .onTapGesture { selection = nil }
    }

    /// Start typing a new block. Nothing is persisted until `commitDraft()`.
    private func beginDraft(at start: Date, duration: TimeInterval = 3600) {
        selection = nil
        draft = EventDraft(start: start, end: start.addingTimeInterval(duration))
    }

    /// A binding to the in-flight draft that stays safe to read after the
    /// draft is gone — same reasoning and same shape as
    /// `CalendarState.draftBinding()`: both `↩` (→ `commitDraft` → `draft =
    /// nil`) and `⎋`/blur (→ `draft = nil` directly) clear the draft from
    /// inside the draft field's own event handling, and SwiftUI reads the
    /// field's bindings again while tearing the field down. Do **not**
    /// replace this with `Binding($draft)` — see that function's own doc
    /// comment for why a force-unwrapping binding traps here.
    private func draftBinding() -> Binding<EventDraft>? {
        guard let current = draft else { return nil }
        var lastKnown = current
        return Binding(
            get: { self.draft ?? lastKnown },
            set: { newValue in
                guard self.draft != nil else { return }
                lastKnown = newValue
                self.draft = newValue
            })
    }

    @ViewBuilder
    private func draftBlock(laidOut: LaidOutBlock) -> some View {
        if let binding = draftBinding() {
            DraftBlockView(
                draft: binding,
                renderedHeight: laidOut.frame.height,
                onCommit: commitDraft,
                onDiscard: { draft = nil })
                .frame(width: laidOut.frame.width, height: laidOut.frame.height, alignment: .topLeading)
                .offset(x: laidOut.frame.minX, y: laidOut.frame.minY)
        }
    }

    /// `↩` — persists only if there is a title (`RoutineBlockStore.create`
    /// enforces this itself, same as `EventStore.commit`), and selects the
    /// result, per interactions.md §3 ("the event is selected on commit").
    private func commitDraft() {
        defer { draft = nil }
        // interactions.md §11.1 — never commit into a column that no longer
        // accepts creation; the draft is abandoned instead (same rule as the
        // `.onChange(of: isActiveDay)` in `body`, checked again here because
        // `↩` can land before that `onChange` has run).
        guard let draft, let template,
              !RoutineDraftRules.mustAbandonDraft(draftWeekday: weekday, activeWeekdays: template.activeWeekdays)
        else { return }
        let startMinutes = minutes(for: draft.start)
        if let created = store.create(
            title: draft.title, startMinutes: startMinutes, duration: draft.duration, in: template) {
            selection = RoutineBlockSelection(blockID: created.id, weekday: weekday)
        }
    }

    // MARK: Drop preview

    /// The create-drag's outline — this column only.
    private func createPreviewFrame(in width: CGFloat, geometry: TimeGeometry) -> CGRect? {
        guard let session = drag else { return nil }
        let inset = Tokens.Spacing.xxs
        let lower = min(session.origin, session.current)
        let upper = max(session.origin, session.current)
        return CGRect(
            x: inset, y: geometry.y(for: lower),
            width: width - 2 * inset,
            height: max(geometry.height(from: lower, to: upper), Tokens.Size.blockMinRenderedHeight))
    }

    /// The move/resize outline, at `blockDrag.proposedRange` converted into
    /// THIS column's geometry. The same minutes give the same frame in every
    /// column, which is what makes the multi-column preview line up.
    private func blockDragPreviewFrame(in width: CGFloat, geometry: TimeGeometry) -> CGRect? {
        guard let session = blockDrag else { return nil }
        let inset = Tokens.Spacing.xxs
        let range = session.proposedRange
        let start = referenceDayStart.addingTimeInterval(TimeInterval(range.start * 60))
        let end = referenceDayStart.addingTimeInterval(TimeInterval(range.end * 60))
        return CGRect(
            x: inset, y: geometry.y(for: start),
            width: width - 2 * inset,
            height: max(geometry.height(from: start, to: end), Tokens.Size.blockMinRenderedHeight))
    }

    /// The §14.4 `previewed` twin for a focused template option, or `nil`
    /// when there is no preview, it is for another template's block, or the
    /// option proposes no frame (`remove`). Same model shape as `blockView`.
    private func conflictTwin(width: CGFloat, geometry: TimeGeometry) -> AnyView? {
        guard let preview = conflictPreview,
              let startMinutes = preview.startMinutes, let duration = preview.durationMinutes,
              let block = blocks.first(where: { $0.id == preview.blockID })
        else { return nil }
        let inset = Tokens.Spacing.xxs
        let start = referenceDayStart.addingTimeInterval(TimeInterval(startMinutes * 60))
        let end = start.addingTimeInterval(TimeInterval(duration * 60))
        let height = max(geometry.height(from: start, to: end), Tokens.Size.blockMinRenderedHeight)
        let model = GridBlockModel(
            id: block.id, title: block.title, start: start, end: end, locationName: nil,
            kind: .routineTimed, flexibility: block.flexibility, status: .scheduled,
            source: template?.sourceKey ?? .graphite, sourceName: template?.name ?? "Routine",
            glyphOverride: nil, isMovable: false)
        // `AnyView` erases the concrete view type so this helper can return
        // "a view or nothing" from ordinary (non-builder) code.
        return AnyView(
            GridBlockView(model: model, presentation: [.previewed], renderedHeight: height)
                .frame(width: width - 2 * inset, height: height, alignment: .topLeading)
                .offset(x: inset, y: geometry.y(for: start))
                // interactions.md §10.3: previewed blocks are not editable.
                .allowsHitTesting(false))
    }

    private func dropPreview(_ rect: CGRect) -> some View {
        RoundedRectangle(cornerRadius: Tokens.Radius.block, style: .continuous)
            .strokeBorder(
                Tokens.Color.Interactive.accent,
                style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private func overflowChip(_ chip: OverflowChip) -> some View {
        Text("+\(chip.hiddenCount)")
            .typeStyle(.countdownChip)
            .foregroundStyle(Tokens.Color.Text.secondary)
            .padding(.horizontal, Tokens.Spacing.xs)
            .frame(height: 14)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip, style: .continuous)
                    .fill(Tokens.Color.Surface.canvasSunken))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .offset(y: chip.anchor.y)
            .padding(.trailing, Tokens.Spacing.xxs)
            .allowsHitTesting(false)
    }
}

// MARK: - Column activation transition (components.md §13.5.4, task P2-T39)

/// `motion.viewChange` for a weekday column changing state. An `enum` with no
/// cases is Swift's usual namespace for static helpers (like a static class).
enum RoutineColumnTransition {
    /// §13.5.4: "over `motion.viewChange` (0.16, easeInOut, opacity only)
    /// ... Under Reduce Motion it is an instant swap, per that token's own
    /// entry." That entry (`Tokens.Motion.ViewChange.reduceMotion`) reads
    /// "instant swap, 0.10 opacity fade only", so Reduce Motion keeps a 0.10
    /// fade and drops nothing else; this transition has no movement to drop.
    /// The 0.10 comes from that prose, as `MainWindow`'s view-mode cross-fade
    /// already reads it — the token has no numeric field for it.
    static func animation(reduceMotion: Bool) -> Animation {
        reduceMotion
            ? .easeInOut(duration: 0.10)
            : .easeInOut(duration: Tokens.Motion.ViewChange.duration)
    }
}

// MARK: - Inactive-column note (components.md §13.5.3, task P2-T38)

/// "Not in this routine" + an `Add Sat` text button, stacked `spacing.xxs`
/// apart, at most `size.inactiveDayNoteMaxWidth` wide. No glyph in either
/// element (§13.5.3: the symbol vocabularies are closed). Copy is exact.
private struct InactiveDayNote: View {
    /// `Calendar`'s weekday number (1 = Sunday … 7 = Saturday).
    let weekday: Int
    let onAdd: () -> Void

    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            Text("Not in this routine")
                .typeStyle(.inactiveDayLabel)
                .foregroundStyle(Tokens.Color.Text.secondary)
                // Lets the text take the second line its type token allows
                // (`lineLimit` 2) instead of being squeezed to one line and
                // truncated by the narrow column.
                .fixedSize(horizontal: false, vertical: true)
                .allowsHitTesting(false)

            Button(action: onAdd) {
                // "The weekday is the same `shortWeekdaySymbols` form the
                // header uses, so the button names the column it is in."
                Text("Add \(Calendar.current.shortWeekdaySymbols[weekday - 1])")
                    .underline()
                    .typeStyle(.editorModeLabel)
                    .foregroundStyle(Tokens.Color.Interactive.accent)
                    // Hover: a `color.interactive.hoverOverlay` rounded rect at
                    // `radius.chip` with `spacing.xxs` padding. The negative
                    // padding after the background gives the space back, so
                    // the button text stays flush with the label above while
                    // the hover rect extends `spacing.xxs` around it.
                    .padding(Tokens.Spacing.xxs)
                    .background {
                        if isHovered {
                            RoundedRectangle(cornerRadius: Tokens.Radius.chip, style: .continuous)
                                .fill(Tokens.Color.Interactive.hoverOverlay)
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(-Tokens.Spacing.xxs)
            }
            // `.plain` drops the system bezel; the text above is the whole look.
            .buttonStyle(.plain)
            .cursor(.pointingHand)
            .onHover { isHovered = $0 }
        }
        .frame(maxWidth: Tokens.Size.inactiveDayNoteMaxWidth, alignment: .leading)
    }
}

// MARK: - Inspector (layouts.md §8.1)

private struct RoutineInspectorView: View {
    let template: RoutineTemplate?
    let selectedBlock: RoutineBlockSnapshot?
    /// Task P2-T40 — for §13.6.2's `Will not run` line.
    let timeWindows: [TimeWindow]
    /// Task P2-T39 — `(weekday, active)`: the toggle row's write
    /// (components.md §13.5.4 via `RoutinesWindow.setWeekday`).
    let onSetWeekday: (Int, Bool) -> Void
    /// Task P2-T42 — components.md §13.2's writes, by block id.
    let onSetFlexibility: (UUID, Flexibility) -> Void
    let onSetShiftRange: (UUID, Int) -> Void
    let onRepairShiftRange: (UUID) -> Void
    /// Task P2-T44 — §13.7.3's scope and its one-step write.
    let detachedInstances: [Event]
    let onResync: ([Event]) -> Void
    @State private var isResyncPresented = false
    /// §13.4 (amended 2026-10-06, G-040): `⎋` closes the Re-sync popover
    /// wherever key focus is; see `EscapeKeyMonitor` for why a monitor.
    /// Swift note: `@State` keeps this one object alive for the view's
    /// lifetime (SwiftUI recreates the struct itself on every update).
    @State private var resyncEscape = EscapeKeyMonitor()
    /// …and focus returns to the `Re-sync` button.
    @FocusState private var isResyncButtonFocused: Bool

    private var orderedWeekdays: [Int] {
        RoutineWeekLayout.orderedWeekdays(firstWeekday: Calendar.current.firstWeekday)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xl) {
                if let selectedBlock {
                    blockDetails(selectedBlock)
                } else if let template {
                    templateSummary(template)
                } else {
                    // No template exists at all (seeding failed or the store
                    // was cleared). A summary sentence, not a placeholder
                    // graphic — the same rule §6/§8.1 give the day/template
                    // empty state.
                    Text("No routine templates yet.")
                        .typeStyle(.inspectorValue)
                        .foregroundStyle(Tokens.Color.Text.secondary)
                }
            }
            .padding(Tokens.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Color.Surface.inspector)
    }

    // MARK: Selected block

    @ViewBuilder
    private func blockDetails(_ block: RoutineBlockSnapshot) -> some View {
        Text(block.title)
            .typeStyle(.inspectorTitle)
            .foregroundStyle(Tokens.Color.Text.primary)

        field("Start", timeOfDay(block.startMinutes))
        field("Duration", durationText(block.duration))
        // components.md §13.2 (task P2-T42): the three-segment control with
        // rail samples, and the ± stepper for `.shiftable`.
        // Label above, control below: the three segments don't fit beside
        // the 84pt label column at the inspector's width.
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            label("Flexibility")
            FlexibilityControl(
                flexibility: block.flexibility,
                shiftableMinutes: block.shiftableMinutes,
                onSetFlexibility: { onSetFlexibility(block.id, $0) },
                onSetShiftRange: { onSetShiftRange(block.id, $0) })
        }
        // "writes 30 on first display" (§13.2): a `.shiftable` block with no
        // ± value is repaired the moment the inspector shows it. `.task(id:)`
        // runs once per selected block, not once per redraw.
        .task(id: block.id) { onRepairShiftRange(block.id) }

        // components.md §13.6.2 (task P2-T40): one line per protected window
        // that refuses this block, naming the window and the colliding
        // weekdays. `ForEach` over value types that aren't `Identifiable`
        // needs `id:`, which says which property tells the rows apart.
        if let template {
            ForEach(refusals(for: block, in: template), id: \.windowID) { refusal in
                refusalLine(refusal)
            }
        }
        // §13.6.2's third surface (the needs-attention count) and §14.6's
        // routing into this window's conflict mode are built (task P2-T46):
        // `CalendarState.templateConflicts`, `RoutinesWindow.openPendingTemplateConflict`.
    }

    private func refusals(for block: RoutineBlockSnapshot, in template: RoutineTemplate) -> [ProtectedWindowRule.Refusal] {
        ProtectedWindowRule.refusals(
            startMinutes: block.startMinutes, duration: block.duration,
            activeWeekdays: template.activeWeekdays,
            orderedWeekdays: orderedWeekdays,
            windows: timeWindows)
    }

    /// `Will not run — inside Sleep (protected) on Mon, Wed, Fri`, in
    /// `inspectorLabel` / `inspectorValue` as §13.6.2 specifies. The split
    /// falls at the dash: `Will not run —` is the label and the rest is the
    /// value. Unlike `field(_:_:)` the label has no fixed 84pt column,
    /// because `Will not run —` doesn't fit in it. `spacing: 0` with the
    /// space carried in the label text keeps the sentence's own spacing
    /// instead of inventing a gap. The value wraps instead of truncating, so
    /// the window and the days are always both named.
    private func refusalLine(_ refusal: ProtectedWindowRule.Refusal) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(ProtectedWindowRule.inspectorLabel + " ")
                .typeStyle(.inspectorLabel)
                .foregroundStyle(Tokens.Color.Text.secondary)
            Text(ProtectedWindowRule.inspectorValue(for: refusal))
                .typeStyle(.inspectorValue)
                .foregroundStyle(Tokens.Color.Text.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        // VoiceOver reads the line as one sentence instead of two fragments.
        .accessibilityElement(children: .combine)
    }

    // MARK: Nothing selected — the template summary (§8.1)

    @ViewBuilder
    private func templateSummary(_ template: RoutineTemplate) -> some View {
        Text(template.name)
            .typeStyle(.inspectorTitle)
            .foregroundStyle(Tokens.Color.Text.primary)

        // layouts.md §8.1 (amended 2026-10-01): "Active weekdays is a
        // control, not a field. It is the same Mon-first toggle row the
        // time-window inspector already uses" — so it is literally that row.
        // It replaces the read-only weekday list that used to sit here.
        // layouts.md §8.1 (amended 2026-10-05, G-028): the row sits UNDER
        // its label at full content width — beside the 84pt label column it
        // was squeezed until `M`/`W` clipped to `N`/`V`. Label above,
        // control below, `spacing.sm`, as the flexibility control does.
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            label("Weekdays")
            WeekdayToggleRow(
                weekdays: orderedWeekdays,
                isOn: { template.activeWeekdays.contains($0) },
                context: .routine,
                onFlip: { weekday in
                    onSetWeekday(weekday, !template.activeWeekdays.contains(weekday))
                })
        }
        field("Blocks", "\(template.blocks.count)")
        field("Total", String(format: "%.1f h", totalHours(template)))
        // §13.4 / §13.7.3 (task P2-T44): the detached count and Re-sync.
        // "Hidden entirely at zero": no row at all, not "0 instances".
        if let count = RoutineResync.countText(detachedInstances.count) {
            resyncRow(count)
        }
    }

    /// `3 instances edited`, `blockMeta` / `color.text.secondary`, with a
    /// **Re-sync** button whose popover names the damage (interactions.md
    /// §11.2: "the affected dates, listed, not a count alone").
    private func resyncRow(_ count: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.md) {
            Text(count)
                .typeStyle(.blockMeta)
                .foregroundStyle(Tokens.Color.Text.secondary)
            Button("Re-sync") { isResyncPresented = true }
                // Swift note: `.popover` attaches the popover to this
                // button, so it is "anchored to the button" (§13.4).
                .popover(isPresented: $isResyncPresented, arrowEdge: .bottom) {
                    resyncPopover
                }
                .focused($isResyncButtonFocused)
                // §13.4 (amended 2026-10-06): while the popover is open, a
                // bare `⎋` anywhere in the app dismisses it (writing
                // nothing) and focus returns to this button.
                .onChange(of: isResyncPresented) { _, presented in
                    if presented {
                        resyncEscape.start {
                            isResyncPresented = false
                            isResyncButtonFocused = true
                        }
                    } else {
                        resyncEscape.stop()
                    }
                }
                .onDisappear { resyncEscape.stop() }
            Spacer(minLength: 0)
        }
    }

    private var resyncPopover: some View {
        let rows = RoutineResync.dateRows(for: detachedInstances)
        return VStack(alignment: .leading, spacing: Tokens.Spacing.md) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                ForEach(rows.dates, id: \.self) { date in
                    Text(date)
                        .typeStyle(.popoverRow)
                        .foregroundStyle(Tokens.Color.Text.primary)
                }
                if let overflow = rows.overflow {
                    // components.md §13.4 (amended 2026-10-05, G-034):
                    // `+2 more` in `popoverRow` / `color.text.secondary`.
                    Text(overflow)
                        .typeStyle(.popoverRow)
                        .foregroundStyle(Tokens.Color.Text.secondary)
                }
            }
            Button(RoutineResync.actionTitle(detachedInstances.count)) {
                onResync(detachedInstances)
                isResyncPresented = false
            }
            // The primary action: ↩ triggers it, and macOS draws it prominent.
            .keyboardShortcut(.defaultAction)
        }
        // components.md §13.4 (amended 2026-10-05, G-034): insets
        // `spacing.lg` horizontal, `spacing.md` vertical, as built. The
        // `.popover` above is a system popover (`NSPopover`, its own window),
        // so it is never clipped by the Routines window's edge.
        .padding(.horizontal, Tokens.Spacing.lg)
        .padding(.vertical, Tokens.Spacing.md)
        .frame(width: Tokens.Size.resyncPopoverWidth, alignment: .leading)
    }

    // MARK: Building blocks (mirrors InspectorView.swift's own)

    private func field(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.md) {
            label(name)
            Text(value)
                .typeStyle(.inspectorValue)
                .foregroundStyle(Tokens.Color.Text.primary)
            Spacer(minLength: 0)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .typeStyle(.inspectorLabel)
            .foregroundStyle(Tokens.Color.Text.secondary)
            .frame(width: 84, alignment: .leading)
    }

    private func timeOfDay(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }

    private func durationText(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder) min" }
        return remainder == 0 ? "\(hours) h" : "\(hours) h \(remainder) min"
    }

    /// Hours per *week*, not just the sum of the block set: every block
    /// repeats on every active weekday (`RoutineWeekLayout`'s own header
    /// comment), so the total time this template actually occupies across a
    /// week is `sum(block durations) × active weekday count`. layouts.md §8.1
    /// asks for "total hours" without a formula; this is the one reading that
    /// is consistent with what the rest of the window already shows — a
    /// per-block-set total would silently disagree with what "3 active
    /// weekdays" beside it implies.
    private func totalHours(_ template: RoutineTemplate) -> Double {
        let perOccurrence = template.blocks.reduce(0) { $0 + $1.duration } / 3600
        return perOccurrence * Double(template.activeWeekdays.count)
    }
}

// The weekday toggle row lives in `WeekdayToggleRow.swift` (task P2-F08).

// MARK: - Inspector: selected TimeWindow (task P2-T24, components.md §13.3)

/// Task P2-T24 closes components.md §13.3's own sentence: "Creating one: drag
/// on empty canvas, then pick the kind from the inspector." Tasks P2-T21/22/23
/// built select/move/resize/create for an EXISTING `TimeWindow`; this is the
/// still-missing "pick the kind" half, plus the weekday-set editing and label
/// editing §7's "protected / low-energy / peak-focus regions ... editable"
/// also promises and no prior task closed.
///
/// Takes the live `TimeWindow` `@Model` instance directly (not a snapshot,
/// unlike `RoutineInspectorView.selectedBlock`) — every control here writes
/// straight back through `TimeWindowStore`, and `TimeWindowStore`'s own
/// mutation methods already take a `TimeWindow` model, matching `move`/
/// `resize`/`delete`'s existing call shape (`RoutinesWindow.swift`'s own
/// `windowGesture`/`handleDelete` above).
///
/// §13.3/§7 do not specify exact segment label text, a toggle glyph, or a
/// text-editing commit granularity, so all three are the narrowest reasonable
/// judgement calls (documented in DEVIATIONS.md, not GAPS.md — same rule
/// P2-T15 used for its own option-row prose):
///   - kind segment labels are the plain English names §13.3/§7's own prose
///     already uses for these three kinds ("Protected" / "Low Energy" /
///     "Peak Focus"), analogous in weight to §13.2's "Fixed / Shiftable /
///     Droppable" labelled segmented control — the closest existing
///     precedent, though that control's own interactive version does not
///     exist yet (still read-only text in `blockDetails` above) so there is
///     nothing to copy verbatim;
///   - the weekday toggle row is `WeekdayToggleRow`, specified since
///     2026-10-05 by layouts.md §8.1 (task P2-F08);
///   - the label field commits on `Return` or on losing focus, not per
///     keystroke — there is no existing precedent in this codebase for
///     editing an ALREADY-persisted text field (`DraftBlockView`'s own
///     `TextField` only ever edits an in-flight, not-yet-persisted draft), so
///     this mirrors that field's `↩`-commits shape as the closest analogue
///     rather than inventing an unrelated one.
private struct TimeWindowInspectorView: View {
    let window: TimeWindow
    let store: TimeWindowStore

    /// In-flight label text, seeded from `window.label` when this view
    /// appears (and, via the parent's `.id(selectedWindow.id)`, freshly
    /// re-seeded whenever the selected window's identity changes — this view
    /// is torn down and rebuilt rather than reused in place). Nothing is
    /// written back to `store` until `commitLabel()` runs, the same
    /// "nothing persists until commit" shape `RoutineDayColumnView`'s own
    /// `EventDraft` title field already uses for an in-flight draft.
    @State private var labelText: String = ""
    @FocusState private var labelFieldFocused: Bool

    private var orderedWeekdays: [Int] {
        RoutineWeekLayout.orderedWeekdays(firstWeekday: Calendar.current.firstWeekday)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xl) {
                Text(window.label.isEmpty ? "Time Window" : window.label)
                    .typeStyle(.inspectorTitle)
                    .foregroundStyle(Tokens.Color.Text.primary)

                kindField
                weekdaysField
                labelField
                field("Start", timeOfDay(window.startMinutes))
                field("End", timeOfDay(window.endMinutes))
            }
            .padding(Tokens.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Color.Surface.inspector)
        .onAppear { labelText = window.label }
        .onChange(of: labelFieldFocused) { _, focused in
            if !focused { commitLabel() }
        }
    }

    // MARK: Kind (components.md §13.3: "pick the kind from the inspector")

    private var kindField: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.md) {
            label("Kind")
            Picker("Kind", selection: Binding(
                get: { window.kind },
                set: { store.setKind(window, to: $0) })) {
                    ForEach(TimeWindowKind.allCases, id: \.self) { kind in
                        Text(kindLabel(kind)).tag(kind)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .accessibilityLabel("Kind")
        }
    }

    private func kindLabel(_ kind: TimeWindowKind) -> String {
        switch kind {
        case .protected: "Protected"
        case .lowEnergy: "Low Energy"
        case .peakFocus: "Peak Focus"
        }
    }

    // MARK: Weekdays

    private var weekdaysField: some View {
        // Same component and placement as the template's row (layouts.md
        // §8.1, amended 2026-10-05). `.window` context: `on`/`off` values,
        // and the last active toggle is disabled (components.md §13.5.4,
        // G-027) — a window with no days could never be selected again.
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            label("Weekdays")
            WeekdayToggleRow(
                weekdays: orderedWeekdays,
                isOn: { window.weekdays.contains($0) },
                context: .window,
                onFlip: { weekday in
                    store.setWeekdays(
                        window,
                        to: RoutineWeekdayActivation.applying(
                            weekday, active: !window.weekdays.contains(weekday), to: window.weekdays))
                })
        }
    }

    // MARK: Label

    private var labelField: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.md) {
            label("Label")
            TextField("Label", text: $labelText)
                .textFieldStyle(.plain)
                .typeStyle(.inspectorValue)
                .foregroundStyle(Tokens.Color.Text.primary)
                .focused($labelFieldFocused)
                .onSubmit { commitLabel() }
                .accessibilityLabel("Label")
        }
    }

    private func commitLabel() {
        guard labelText != window.label else { return }
        store.setLabel(window, to: labelText)
    }

    // MARK: Building blocks (mirrors RoutineInspectorView's own)

    private func field(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.md) {
            label(name)
            Text(value)
                .typeStyle(.inspectorValue)
                .foregroundStyle(Tokens.Color.Text.primary)
            Spacer(minLength: 0)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .typeStyle(.inspectorLabel)
            .foregroundStyle(Tokens.Color.Text.secondary)
            .frame(width: 84, alignment: .leading)
    }

    private func timeOfDay(_ minutes: Int) -> String {
        String(format: "%02d:%02d", minutes / 60, minutes % 60)
    }
}

/// interactions.md §10.1 (amended 2026-10-05) in the Routines window: bring
/// a template conflict's block into view. Minutes of day. `token` makes a
/// repeat request a change. Task P2-F15.
struct RoutineScrollRequest: Equatable {
    let token = UUID()
    var occurrence: Range<Int>
    var earliestStart: Int

    /// "In the Routines window the same scroll rule applies to the template
    /// block": its frame, and the earlier of the two colliding starts (a
    /// window that wraps midnight collides from 00:00).
    init(_ conflict: TemplateConflict) {
        occurrence = conflict.blockStartMinutes..<(conflict.blockStartMinutes + max(conflict.durationMinutes, 1))
        let windowStart = conflict.windowStartMinutes < conflict.windowEndMinutes ? conflict.windowStartMinutes : 0
        earliestStart = min(conflict.blockStartMinutes, windowStart)
    }

    /// The option activation focuses in the Routines window: the
    /// recommended one, or the only one (interactions.md §10.1).
    static func activationOptionID(_ conflict: TemplateConflict) -> String? {
        (conflict.options.first(where: \.isRecommended) ?? conflict.options.first)?.id
    }
}
