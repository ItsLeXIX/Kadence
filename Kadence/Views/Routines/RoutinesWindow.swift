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
//    - the flexibility control's interactive stepper (components.md §13.2) —
//      the inspector still shows flexibility as read-only text;
//    - detached-instance tracking and Re-sync (components.md §13.4,
//      interactions.md §11.2) — always zero right now, so per the existing
//      zero-state rule (§10.2) it is omitted entirely rather than stubbed;
//    - RoutineEngine.materialize honouring protected windows, MenuBarExtra,
//      snooze — separate, later tasks, unrelated to this window.
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
import SwiftData

/// components.md §13.3's mode control: "Blocks" / "Windows". `.blocks` is the
/// default — the window opens the way P2-T10 through P2-T12 already left it.
enum RoutinesEditorMode: String, CaseIterable, Identifiable {
    case blocks
    case windows

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blocks: "Blocks"
        case .windows: "Windows"
        }
    }
}

struct RoutinesWindow: View {
    @Query(sort: \RoutineTemplate.name) private var templates: [RoutineTemplate]
    /// Task P2-T18 seeded this via `.task {}` below; nothing read it back
    /// anywhere in this window until this task's windows-mode rendering.
    @Query private var timeWindows: [TimeWindow]
    @Environment(\.modelContext) private var context
    /// KadenceApp.swift now injects the same instance MainWindow uses, so
    /// `⌘Z`/`⌘⇧Z` (wired once, app-wide, in `KadenceCommands`) undo/redo
    /// routine edits exactly like event edits — one stack for the whole app.
    @Environment(UndoStack.self) private var undoStack

    @State private var selectedTemplateID: UUID?
    @State private var selection: RoutineBlockSelection?
    /// Task P2-T21: which existing `TimeWindow` (by `id`) is selected in
    /// Windows mode. Simpler than `RoutineBlockSelection` — a `TimeWindow` is
    /// one object regardless of how many weekday columns it renders into (its
    /// `weekdays` set draws it into every one of them at once), so there is no
    /// weekday-disambiguation to carry the way a `RoutineBlock` needs.
    @State private var windowSelection: UUID?
    @State private var editorMode: RoutinesEditorMode = .blocks
    @State private var didSeed = false
    /// So `⌫` (below) has somewhere to land. Requested whenever a block is
    /// selected — including the very first tap — since nothing else in this
    /// window claims keyboard focus by default.
    @FocusState private var canvasFocused: Bool

    private var store: RoutineBlockStore {
        RoutineBlockStore(context: context, undo: undoStack)
    }

    /// Task P2-T21's sibling to `store` above — same one-`UndoStack`-per-app
    /// wiring, so `⌘Z` for a window move/delete names correctly no matter
    /// which window is key.
    private var timeWindowStore: TimeWindowStore {
        TimeWindowStore(context: context, undo: undoStack)
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
                    if isSplit {
                        Rectangle()
                            .fill(Tokens.Color.Separator.region)
                            .frame(width: Tokens.Size.hairline)
                        inspector
                            .frame(width: Tokens.Size.editorInspectorWidth)
                    }
                }

                if !isSplit {
                    inspector
                        .frame(width: Tokens.Size.editorInspectorWidth)
                        .elevation(.level2)
                }
            }
            // interactions.md §11.1/§5 — `⌫` deletes the selected block
            // immediately, no confirmation. Attached at this level (rather
            // than per-block) so it fires regardless of which weekday column
            // the block was last clicked in.
            .focusable()
            .focused($canvasFocused)
            .onKeyPress(keys: [.delete]) { _ in handleDelete() }
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
        .frame(
            minWidth: Tokens.Size.routineEditorMinWidth,
            minHeight: Tokens.Size.routineEditorMinHeight)
        .task {
            guard !didSeed else { return }
            didSeed = true
            MockData.seedRoutineTemplatesIfNeeded(context)
            MockData.seedTimeWindowsIfNeeded(context)
            canvasFocused = true
        }
        .onChange(of: selectedTemplateID) { _, _ in
            selection = nil
            windowSelection = nil
        }
        .onChange(of: selection) { _, newValue in
            if newValue != nil { canvasFocused = true }
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
            RoutineWeekdayHeaderRow(weekdays: orderedWeekdays)
            RoutinesCanvasView(
                weekdays: orderedWeekdays,
                template: selectedTemplate,
                store: store,
                selection: $selection,
                editorMode: editorMode,
                timeWindows: timeWindows,
                timeWindowStore: timeWindowStore,
                windowSelection: $windowSelection)
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
        if let selectedWindow {
            TimeWindowInspectorView(window: selectedWindow, store: timeWindowStore)
                .id(selectedWindow.id)
        } else {
            RoutineInspectorView(template: selectedTemplate, selectedBlock: selectedBlockSnapshot)
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
struct RoutineBlockSelection: Equatable {
    var blockID: UUID
    var weekday: Int
}

// MARK: - Weekday header (components.md §13.1: "no dates, dayHeaderWeekday only")

private struct RoutineWeekdayHeaderRow: View {
    let weekdays: [Int]

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: Tokens.Size.timeGutterWidth)
            ForEach(weekdays, id: \.self) { weekday in
                Text(weekdaySymbol(weekday))
                    .typeStyle(.dayHeaderWeekday)
                    .foregroundStyle(Tokens.Color.Text.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: Tokens.Size.dayHeaderHeight)
        .background(Tokens.Color.Surface.canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Tokens.Color.Separator.region)
                .frame(height: Tokens.Size.hairline)
        }
    }

    private func weekdaySymbol(_ weekday: Int) -> String {
        Calendar.current.shortWeekdaySymbols[weekday - 1]
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

            ScrollView(.vertical) {
                gridBody(columnWidth: columnWidth)
                    .frame(
                        width: needsHorizontalScroll
                            ? Tokens.Size.timeGutterWidth + columnWidth * CGFloat(weekdays.count)
                            : nil,
                        alignment: .leading)
            }
            .scrollIndicators(.automatic)
            .modifier(HorizontalScrollIfNeeded(isEnabled: needsHorizontalScroll))
        }
        .background(Tokens.Color.Surface.canvas)
    }

    private func gridBody(columnWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            TimeGutterView(
                geometry: TimeGeometry(dayStart: Date(), hourHeight: hourHeight),
                now: Date(),
                showsNow: false)
                .frame(width: Tokens.Size.timeGutterWidth)

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
                    // components.md §7: the window label is drawn "once, at
                    // the window's top edge, in the leading day column" —
                    // same rule `TimedCanvasView.windowsBackdrop`/
                    // `DayColumnView.showsWindowLabels` already apply on the
                    // main grid (`index == 0`), just keyed to this window's
                    // own leading (first-ordered) weekday instead of a
                    // column index.
                    showsWindowLabels: weekday == weekdays.first)
                    .frame(width: columnWidth)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Tokens.Color.Separator.dayDivider)
                            .frame(width: Tokens.Size.hairline)
                    }
            }
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
    let showsWindowLabels: Bool

    /// In-flight drag, kept local so the model is only written on drop — same
    /// rule as `DayColumnView.DragSession`.
    @State private var drag: RoutineDragSession?
    @State private var hoveredID: UUID?
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

    struct RoutineDragSession: Equatable {
        enum Mode: Equatable { case move, resizeTop, resizeBottom, create }
        var mode: Mode
        /// `nil` for `.create` — there is no existing block to address until
        /// the drag ends and a new one is actually made.
        var blockID: UUID?
        var origin: Date
        var current: Date
    }

    struct TimeWindowDragSession: Equatable {
        /// Analogous to `RoutineDragSession.Mode` above, minus `.create` — a
        /// `TimeWindow` is never created from this drag (task P2-T22).
        /// Classified once, from the drag's `startLocation` against the
        /// dragged span's own top/bottom `Tokens.Size.blockResizeHandleHeight`
        /// band, the same way `blockGesture` classifies `RoutineDragSession.Mode`.
        enum Mode: Equatable { case move, resizeTop, resizeBottom }
        var windowID: UUID
        var mode: Mode
        var translationHeight: CGFloat
    }

    /// Task P2-T23 — drag-to-create on empty windows-mode canvas. Mirrors
    /// `RoutineDragSession`'s own `.create` case shape (`origin`/`current`
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
    /// weekdays. Blocks only render on active days; creating a block on
    /// an inactive day would silently place it on the nearest active day
    /// instead, which is confusing — so creation and move gestures are
    /// disabled here (the column still renders its time-window backdrop
    /// and hour lines so the user sees the full week shape).
    private var isActiveDay: Bool {
        template?.activeWeekdays.contains(weekday) ?? false
    }

    private var layoutItems: [LayoutItem] {
        var items = RoutineWeekLayout.layoutItems(
            blocks: blocks,
            activeWeekdays: template?.activeWeekdays ?? [],
            weekday: weekday,
            referenceDayStart: referenceDayStart)
        // The draft is laid out only on active weekday columns.
        // Creating on an inactive column would silently place the block
        // on the nearest active day instead — the "silent relocation"
        // defect reported in goal.txt §A. `createSurface` is already
        // non-hit-testable on inactive days, but this guard catches the
        // edge case where a draft outlives a weekday-toggle that
        // deactivates the column it was started in.
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

                HourLinesLayer(geometry: geometry)

                if showsWindowLabels {
                    WindowLabelsLayer(
                        windows: timeWindows,
                        day: referenceDayStart,
                        geometry: geometry,
                        showsPeakFocus: editorMode == .windows)
                }

                // Empty-grid tap deselects, matching the main grid's
                // "clicking empty grid deselects" (interactions.md §6).
                // Double-click / drag create (task P2-T12, interactions.md
                // §3 via §11.1). Windows mode (task P2-T20) turns this off:
                // §13.3 — in windows mode routine blocks are not the editable
                // layer, so creating one from here would be editing the
                // wrong layer.
                createSurface(width: proxy.size.width, geometry: geometry)
                    .allowsHitTesting(editorMode == .blocks && isActiveDay)

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

                // interactions.md §4 — "same drop preview" as the main grid's
                // move/resize (the outline only; the main grid itself has no
                // time badge yet — DEVIATIONS.md A15 — so there is nothing
                // extra to mirror here). Drag/resize only ever runs in
                // Blocks mode (createSurface/blockGesture are non-hit-
                // testable in Windows mode above), so `drag` is always nil
                // there and this never fires in Windows mode either.
                if let previewRect = dropPreviewFrame(in: proxy.size.width, geometry: geometry) {
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
                // `dropPreview`/`dropPreviewFrame`'s own mechanism for
                // blocks-mode create, keyed off `windowCreateDrag` instead of
                // `drag` so the two never interfere (one only ever runs in
                // Blocks mode, the other only in Windows mode).
                if let previewRect = windowCreatePreviewFrame(in: proxy.size.width, geometry: geometry) {
                    dropPreview(previewRect)
                }

                windowInteractionLayer(geometry: geometry)
                    .allowsHitTesting(editorMode == .windows)
            }
            .frame(height: geometry.totalHeight, alignment: .top)
        }
        .frame(height: hourHeight * 24)
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
            isMovable: true)
        let isSelected = selection?.blockID == block.id && selection?.weekday == weekday

        GridBlockView(
            model: model,
            presentation: presentation(for: block, isSelected: isSelected),
            renderedHeight: laidOut.frame.height,
            visibleWidth: laidOut.visibleWidth)
            .frame(width: laidOut.frame.width, height: laidOut.frame.height, alignment: .topLeading)
            .contentShape(Rectangle().inset(by: laidOut.hitInset))
            .offset(x: laidOut.frame.minX, y: laidOut.frame.minY)
            .opacity(drag?.blockID == block.id ? Tokens.Opacity.blockDragOrigin : 1)
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
        if drag?.blockID == block.id { presentation.insert(.dragging) }
        return presentation
    }

    // MARK: Gesture (mirrors DayColumnView.blockGesture's shape)

    private func blockGesture(block: RoutineBlockSnapshot, laidOut: LaidOutBlock, geometry: TimeGeometry) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                let handle = Tokens.Size.blockResizeHandleHeight
                let localY = value.startLocation.y - laidOut.frame.minY
                let mode: RoutineDragSession.Mode =
                    localY <= handle ? .resizeTop
                    : localY >= laidOut.frame.height - handle ? .resizeBottom
                    : .move

                let snap = NSEvent.modifierFlags.contains(.control) ? 5 : 15
                let delta = value.translation.height
                let deltaTime = TimeInterval(delta / hourHeight) * 3600
                let blockStart = referenceDayStart.addingTimeInterval(TimeInterval(block.startMinutes * 60))

                if drag == nil {
                    drag = RoutineDragSession(mode: mode, blockID: block.id, origin: blockStart, current: blockStart)
                }
                drag?.current = TimeGeometry.snap(blockStart.addingTimeInterval(deltaTime), toMinutes: snap)
            }
            .onEnded { _ in
                defer { drag = nil }
                guard let session = drag, session.blockID == block.id,
                      let template, let liveBlock = template.blocks.first(where: { $0.id == block.id })
                else { return }

                let currentMinutes = minutes(for: session.current)
                switch session.mode {
                case .move:
                    store.move(liveBlock, toStartMinutes: currentMinutes)
                case .resizeTop:
                    store.resize(liveBlock, newStartMinutes: currentMinutes)
                case .resizeBottom:
                    let deltaMinutes = currentMinutes - minutes(for: session.origin)
                    let oldEndMinutes = liveBlock.startMinutes + Int(liveBlock.duration / 60)
                    store.resize(liveBlock, newEndMinutes: oldEndMinutes + deltaMinutes)
                case .create:
                    break // Unreachable: `session.blockID == block.id` above already excludes it.
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
    /// `blockGesture` classifies `RoutineDragSession.Mode`. Snap (15-minute,
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
    /// math as `dropPreviewFrame`'s own `.create` case, just keyed off
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
                        drag = RoutineDragSession(mode: .create, blockID: nil, origin: from, current: to)
                    }
                    .onEnded { _ in
                        defer { drag = nil }
                        guard let session = drag, session.mode == .create else { return }
                        let lower = min(session.origin, session.current)
                        let upper = max(session.origin, session.current)
                        let duration = max(upper.timeIntervalSince(lower), 15 * 60)
                        beginDraft(at: lower, duration: duration)
                    }
            )
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
        guard let draft, let template else { return }
        let startMinutes = minutes(for: draft.start)
        if let created = store.create(
            title: draft.title, startMinutes: startMinutes, duration: draft.duration, in: template) {
            selection = RoutineBlockSelection(blockID: created.id, weekday: weekday)
        }
    }

    // MARK: Drop preview

    private func dropPreviewFrame(in width: CGFloat, geometry: TimeGeometry) -> CGRect? {
        guard let session = drag else { return nil }
        let inset = Tokens.Spacing.xxs

        switch session.mode {
        case .create:
            let lower = min(session.origin, session.current)
            let upper = max(session.origin, session.current)
            return CGRect(
                x: inset, y: geometry.y(for: lower),
                width: width - 2 * inset,
                height: max(geometry.height(from: lower, to: upper), Tokens.Size.blockMinRenderedHeight))

        case .move, .resizeTop, .resizeBottom:
            guard let blockID = session.blockID,
                  let block = blocks.first(where: { $0.id == blockID })
            else { return nil }
            let originalStart = referenceDayStart.addingTimeInterval(TimeInterval(block.startMinutes * 60))
            let originalEnd = originalStart.addingTimeInterval(block.duration)

            let start: Date
            let end: Date
            switch session.mode {
            case .resizeTop:
                start = min(session.current, originalEnd.addingTimeInterval(-15 * 60))
                end = originalEnd
            case .resizeBottom:
                start = originalStart
                let delta = session.current.timeIntervalSince(session.origin)
                end = max(originalEnd.addingTimeInterval(delta), start.addingTimeInterval(15 * 60))
            default:
                start = session.current
                end = session.current.addingTimeInterval(block.duration)
            }
            return CGRect(
                x: inset, y: geometry.y(for: start),
                width: width - 2 * inset,
                height: max(geometry.height(from: start, to: end), Tokens.Size.blockMinRenderedHeight))
        }
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

// MARK: - Inspector (layouts.md §8.1)

private struct RoutineInspectorView: View {
    let template: RoutineTemplate?
    let selectedBlock: RoutineBlockSnapshot?

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
        // components.md §13.2's interactive three-segment flexibility control
        // (Fixed / Shiftable / Droppable with a rail-style sample and, for
        // `.shiftable`, a ± minutes stepper) is explicitly out of scope for
        // this task. Read-only text stands in for it, per the task's own
        // "your call" — this is the value it reads, not a design decision.
        field("Flexibility", block.flexibility.rawValue.capitalized)
    }

    // MARK: Nothing selected — the template summary (§8.1)

    @ViewBuilder
    private func templateSummary(_ template: RoutineTemplate) -> some View {
        Text(template.name)
            .typeStyle(.inspectorTitle)
            .foregroundStyle(Tokens.Color.Text.primary)

        field("Weekdays", weekdayList(template.activeWeekdays))
        field("Blocks", "\(template.blocks.count)")
        field("Total", String(format: "%.1f h", totalHours(template)))
        // §13.4 — detached-instance count and its Re-sync button belong here
        // too, but there is no main-grid edit-command path yet that can tell
        // an instance apart from an untouched one (RoutineEngine.swift's own
        // header), so the count is always zero. Same zero-state rule this
        // window otherwise follows (§10.2 — "hidden entirely at zero"): the
        // row is omitted, not stubbed at "0 instances edited this week".
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

    private func weekdayList(_ weekdays: Set<Int>) -> String {
        guard !weekdays.isEmpty else { return "None" }
        let symbols = Calendar.current.shortWeekdaySymbols
        return weekdays.sorted().map { symbols[$0 - 1] }.joined(separator: ", ")
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
///   - the weekday toggle row reuses `dayHeaderWeekday` type and
///     `Tokens.Color.Interactive.accent` (the one existing generic
///     "selected" tint this app already uses for the focus ring/drop
///     preview) via the system `.toggleStyle(.button)` chrome, rather than
///     inventing a bespoke selected-day swatch;
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
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.md) {
            label("Weekdays")
            HStack(spacing: Tokens.Spacing.xs) {
                ForEach(orderedWeekdays, id: \.self) { weekday in
                    weekdayToggle(weekday)
                }
            }
        }
    }

    private func weekdayToggle(_ weekday: Int) -> some View {
        let isOn = window.weekdays.contains(weekday)
        return Toggle(isOn: Binding(
            get: { isOn },
            set: { newValue in
                var newWeekdays = window.weekdays
                if newValue { newWeekdays.insert(weekday) } else { newWeekdays.remove(weekday) }
                store.setWeekdays(window, to: newWeekdays)
            })) {
                Text(weekdaySymbol(weekday))
                    .typeStyle(.dayHeaderWeekday)
            }
            .toggleStyle(.button)
            .tint(Tokens.Color.Interactive.accent)
            .accessibilityLabel(weekdayFullName(weekday))
    }

    private func weekdaySymbol(_ weekday: Int) -> String {
        Calendar.current.shortWeekdaySymbols[weekday - 1]
    }

    private func weekdayFullName(_ weekday: Int) -> String {
        Calendar.current.weekdaySymbols[weekday - 1]
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
