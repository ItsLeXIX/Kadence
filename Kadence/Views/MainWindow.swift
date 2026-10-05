//
//  MainWindow.swift
//  Kadence
//
//  layouts.md §1 — sidebar + calendar canvas + optional inspector, standard
//  macOS window chrome, and the collapse order in §1.1.
//

import SwiftUI
import SwiftData
import Combine

struct MainWindow: View {
    @Environment(CalendarState.self) private var state
    @Environment(UndoStack.self) private var undoStack
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(sort: \Event.start) private var events: [Event]
    /// Live routine blocks, needed only to feed `ConflictEngine.detect`'s
    /// `routineBlocks:` parameter (it looks up each routine event's
    /// `shiftableMinutes` range by reversing `RoutineEngine`'s own
    /// `externalID` scheme — see `ConflictEngine.routineBlock(for:in:)`).
    @Query private var routineBlocks: [RoutineBlock]
    @State private var fixtures = MockFixtures()
    @State private var didSeed = false
    /// Set once the launch `.task` has seeded and run the first
    /// materialisation pass (task P2-T40). `RoutineMaterializationTriggers`
    /// stays idle until then.
    @State private var isMaterializationReady = false
    /// interactions.md §1 — which region ⇥ has landed on.
    @FocusState private var focusedRegion: CalendarState.FocusRegion?

    private var store: EventStore { EventStore(context: context, undo: undoStack) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            NavigationSplitView(columnVisibility: sidebarVisibility) {
                SidebarView()
                    .focusable()
                    .focused($focusedRegion, equals: .sidebar)
                    .onKeyPress(keys: [.tab]) { press in cycleFocus(press) }
                    // NavigationSplitView installs its own sidebar toggle. Ours has
                    // to exist so that toggling records an explicit user choice that
                    // auto-collapse must not override (layouts.md §1.1), so the
                    // automatic one is removed rather than left as a second button.
                    .toolbar(removing: .sidebarToggle)
                    .navigationSplitViewColumnWidth(
                        min: Tokens.Size.sidebarWidthMin,
                        ideal: Tokens.Size.sidebarWidthDefault,
                        max: Tokens.Size.sidebarWidthMax)
            } detail: {
                canvasAndInspector(windowWidth: width)
            }
            // No .navigationTitle: layouts.md §1.2 puts the range title in the
            // toolbar once, at .principal. Setting it here rendered it a second
            // time in the leading group (review D-1).
            .toolbar { toolbarContent }
            .onChange(of: width, initial: true) { _, newWidth in
                applyCollapseOrder(width: newWidth)
            }
            .onChange(of: focusedRegion) { _, region in
                // The time cursor and its gutter time are gated on the grid being
                // focused, so the shared state has to follow the real focus.
                if let region { state.focusedRegion = region }
            }
            // interactions.md §10.2 — "leaving the conflict panel" abandons
            // any pending preview unconditionally. `state.focusedRegion`
            // moving away from `.inspector` covers ⇥ cycling away and
            // clicking the grid or sidebar (both write `state.focusedRegion`
            // via `focused($focusedRegion, equals:)` above / `cycleFocus`) —
            // §10.2's own list, minus the toolbar (see STATUS.md: the toolbar
            // is not a tracked focus region, and the toolbar actions that
            // actually change state — paging, view switch, closing the
            // inspector — are each covered by their own `onChange` below).
            .onChange(of: state.focusedRegion) { _, region in
                if region != .inspector { state.selectedConflictOptionID = nil }
            }
            // interactions.md §10.2 — changing view mode or paging also
            // abandons a pending preview; a hypothetical about a block on the
            // day you just left stops meaning anything.
            .onChange(of: state.mode) { _, _ in state.selectedConflictOptionID = nil }
            .onChange(of: state.anchor) { _, _ in state.selectedConflictOptionID = nil }
            // interactions.md §10.2 — collapsing the inspector hides the
            // panel the preview belongs to.
            .onChange(of: state.isInspectorVisible) { _, visible in
                if !visible { state.selectedConflictOptionID = nil }
            }
            // Keeps `state.conflicts` in sync with the live queries — see
            // `sortedConflicts(events:routineBlocks:)`'s own doc comment and
            // `CalendarState.conflicts`'s. Both queries can change
            // independently (an event edited, a routine block added), so
            // both are watched.
            .onChange(of: events, initial: true) { _, _ in refreshConflicts() }
            .onChange(of: routineBlocks, initial: true) { _, _ in refreshConflicts() }
        }
        .frame(
            minWidth: Tokens.Size.windowMinWidth,
            minHeight: Tokens.Size.windowMinHeight)
        .task {
            guard !didSeed else { return }
            didSeed = true
            // Task P2-T40: seeding plus the launch materialisation trigger
            // (components.md §13.6.5). See `MockData.seedAllIfNeeded` for why
            // seeding and the first pass are one call.
            let visibleEnd = state.visibleInterval.end
            fixtures = MockData.seedAllIfNeeded(context) {
                RoutineMaterialization.run(context: context, undo: undoStack, visibleEnd: visibleEnd)
            }
            // components.md §13.2 (task P2-T42): no `.shiftable` routine block
            // survives launch without a ± value. Same call the Routines window
            // makes; whichever window opens first does it.
            RoutineBlockStore(context: context, undo: undoStack).repairShiftRanges()
            isMaterializationReady = true
        }
        // §13.6.5's other two triggers: a template/block/window edit, and a
        // change to the visible range (paging, Today, switching mode).
        .materializesRoutines(isReady: isMaterializationReady, visibleEnd: state.visibleInterval.end)
        .onReceive(
            Timer.publish(every: Tokens.Motion.NowLineTick.interval, on: .main, in: .common).autoconnect()
        ) { date in
            state.now = date
        }
        .onReceive(NotificationCenter.default.publisher(for: .kadenceNewEvent)) { _ in
            createAtCursor()
        }
        // components.md §14.1 / interactions.md §10.1's first sentence —
        // `⌘⇧A`, posted by `KadenceCommands` (which has no query of its own
        // onto live events/routine blocks).
        .onReceive(NotificationCenter.default.publisher(for: .kadenceGoToFirstConflict)) { _ in
            state.activateNeedsAttention()
        }
    }

    // MARK: Canvas + inspector

    @ViewBuilder
    private func canvasAndInspector(windowWidth: CGFloat) -> some View {
        // ≥1200 the inspector is a split region; below that it presents as an
        // overlay anchored to the trailing edge, over the canvas.
        let isSplit = windowWidth >= 1200

        ZStack(alignment: .topTrailing) {
            HStack(spacing: 0) {
                canvas
                    .frame(minWidth: Tokens.Size.canvasWidthMin)
                if isSplit && state.isInspectorVisible {
                    Rectangle()
                        .fill(Tokens.Color.Separator.region)
                        .frame(width: Tokens.Size.hairline)
                    inspector
                        .frame(width: Tokens.Size.inspectorWidthDefault)
                }
            }

            if !isSplit && state.isInspectorVisible {
                inspector
                    .frame(width: Tokens.Size.inspectorWidthDefault)
                    .elevation(.level2)
                    .transition(.move(edge: .trailing))
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: Tokens.Motion.ViewChange.duration),
                   value: state.isInspectorVisible)
    }

    @ViewBuilder
    private var canvas: some View {
        let visible = events.filter { state.isVisible($0) }
        let conflictedIDs = conflictedEventIDs
        let partnerTitles = Self.conflictPartnerTitles(events: events, routineBlocks: routineBlocks)

        Group {
            switch state.mode {
            case .month:
                MonthGridView(
                    days: state.visibleDays,
                    events: visible,
                    fixtures: fixtures,
                    now: state.now,
                    anchorMonth: state.anchor)
            case .week:
                TimedCanvasView(
                    days: state.visibleDays,
                    events: visible,
                    fixtures: fixtures,
                    hourHeight: Tokens.Size.hourHeightWeek,
                    now: state.now,
                    store: store,
                    conflictedEventIDs: conflictedIDs,
                    conflictPartnerTitles: partnerTitles,
                    focusedRegion: $focusedRegion,
                    onTab: cycleFocus)
            case .day:
                TimedCanvasView(
                    days: state.visibleDays,
                    events: visible,
                    fixtures: fixtures,
                    hourHeight: Tokens.Size.hourHeightDay,
                    now: state.now,
                    store: store,
                    conflictedEventIDs: conflictedIDs,
                    conflictPartnerTitles: partnerTitles,
                    focusedRegion: $focusedRegion,
                    onTab: cycleFocus)
            }
        }
        // Month ↔ Week ↔ Day is a cross-fade only. No scale, no slide, no
        // zoom-into-the-day metaphor.
        .transition(.opacity)
        .animation(
            reduceMotion
                ? .easeInOut(duration: 0.10)
                : .easeInOut(duration: Tokens.Motion.ViewChange.duration),
            value: state.mode)
        .focusable()
        .focused($focusedRegion, equals: .grid)
        // §1 — "the focused region draws the standard system focus ring on its
        // container", so the ring is deliberately NOT disabled here.
        .onKeyPress(keys: [.tab]) { press in cycleFocus(press) }
        .onKeyPress(action: handleKey)
        // components.md §14.4 — "while any preview is active the calendar
        // canvas — not the sidebar, not the inspector — carries a
        // `size.previewCanvasBorder` inset border". Gated on
        // `selectedConflictOptionID`, not `selectedConflictID`: the panel can
        // be open with nothing focused yet (right after
        // `activateNeedsAttention()`), and that is not itself a preview.
        .overlay {
            if isConflictPreviewActive {
                // `.strokeBorder` draws fully inside the shape's own bounds
                // (inset by half the line width), which is what "inset
                // border" means here — same drawing idiom `GridBlockView`
                // already uses for its hover ring.
                Rectangle()
                    .strokeBorder(Tokens.Color.Interactive.accent, lineWidth: Tokens.Size.previewCanvasBorder)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }

    /// Backs the canvas border above and gates `DayColumnView`'s own preview
    /// rendering identically (`activeConflict` is the same lookup both use),
    /// so "a preview is active" never disagrees between the two.
    private var isConflictPreviewActive: Bool {
        state.selectedConflictOptionID != nil && activeConflict != nil
    }

    private var inspector: some View {
        inspectorBody
            .focusable()
            .focused($focusedRegion, equals: .inspector)
            .onKeyPress(keys: [.tab]) { press in cycleFocus(press) }
            // interactions.md §10.1/§10.2 — ↑/↓ move+preview between conflict
            // options, ⎋ abandons, and ↩ applies the focused/previewed option
            // (§10.1's last paragraph: "↩ applies"; §10.2's table line 71),
            // all scoped inside `handleKey` itself
            // (`state.focusedRegion == .inspector && state.selectedConflictID
            // != nil`, plus `selectedConflictOptionID != nil` for `.return`
            // specifically). Deliberately a `keys:`-filtered hook, not the
            // grid's unrestricted `.onKeyPress(action: handleKey)` — `t`,
            // delete, and the option-modified moves are still grid-only and
            // stay that way — but `.return` must be forwarded too: SwiftUI
            // only dispatches a key to the `.onKeyPress` hooks along the
            // FOCUSED view's own chain, so when the inspector holds real
            // focus, the grid's own `.return`-inclusive hook (above) never
            // fires, and `handleKey`'s conflict-apply case (below) was
            // unreachable dead code without `.return` in this list. (Fixed
            // P2-T37 — see STATUS.md/DEVIATIONS.md for the prior "applying
            // with ↩ did not visibly commit" finding this closes.) Widening
            // this list to include `.return` is safe for the inspector's
            // other states: with a conflict selected but no option focused,
            // `handleKey`'s conflict-apply case's guard fails and falls
            // through to the plain `.return` case, which only re-asserts
            // `isInspectorVisible = true` (already true, since the inspector
            // has focus) — a harmless no-op, not a new behaviour.
            .onKeyPress(keys: [.upArrow, .downArrow, .escape, .return], action: handleKey)
    }

    private var inspectorBody: some View {
        InspectorView(
            event: selectedEvent,
            dayEvents: eventsOnAnchorDay,
            day: state.anchor,
            travel: selectedEvent.flatMap { fixtures.travel(forEvent: $0.id) },
            now: state.now,
            store: store,
            conflict: activeConflict,
            selectedConflictOptionID: state.selectedConflictOptionID,
            onSelectConflictOption: { state.selectedConflictOptionID = $0 },
            routineStatus: selectedEvent.flatMap { RoutineInstance.status(of: $0, in: context) },
            onRevertToRoutine: {
                if let selectedEvent { RoutineInstance.revert(selectedEvent, store: store) }
            })
    }

    /// The conflict `state.selectedConflictID` names, if it still exists in
    /// the current `state.conflicts` — falls back to the ordinary inspector
    /// (not a crash) if the underlying events changed out from under a
    /// stale id, since neither is wired up to clear it yet (that is the
    /// follow-up task that builds abandonment/resolution).
    private var activeConflict: Conflict? {
        guard let id = state.selectedConflictID else { return nil }
        return state.conflicts.first { $0.id == id }
    }

    private var selectedEvent: Event? {
        guard let id = state.selectedEventID else { return nil }
        return events.first { $0.id == id }
    }

    private var eventsOnAnchorDay: [Event] {
        events.filter { Calendar.current.isDate($0.start, inSameDayAs: state.anchor) }
    }

    // MARK: Conflicts (P2-T14 wired Presentation.conflicted; P2-T15 added the
    // "needs your attention" row and the static conflict panel; P2-T16 wired
    // preview-on-focus and unconditional abandonment; P2-T17 (this task)
    // wired `↩` apply — see `CalendarState.conflicts`/
    // `activateNeedsAttention()`/`moveSelectedConflictOption(by:)`/
    // `abandonConflictPreview()`/`applyFocusedConflictOption(store:
    // recomputeConflicts:)`, `ConflictPanelView`, `ConflictPreviewFrames`,
    // `isConflictPreviewActive` above, and the `.onChange`/`handleKey` wiring
    // above/below.)

    /// Recomputed from the live `events`/`routineBlocks` queries on every body
    /// evaluation — `ConflictEngine.detect` is O(n²) over one day's/week's
    /// worth of events, cheap enough that hand-rolled caching would only add a
    /// second, easier-to-desync source of truth.
    private var conflictedEventIDs: Set<UUID> {
        Self.conflictedEventIDs(events: events, routineBlocks: routineBlocks)
    }

    /// The `Presentation.conflicted` input side of the wiring, pulled out as a
    /// `static` function (rather than left inline in `conflictedEventIDs`
    /// above) so `KadenceTests` can drive it directly without instantiating
    /// the view.
    @MainActor
    static func conflictedEventIDs(events: [Event], routineBlocks: [RoutineBlock]) -> Set<UUID> {
        var ids: Set<UUID> = []
        for conflict in sortedConflicts(events: events, routineBlocks: routineBlocks) {
            ids.insert(conflict.routineEvent.id)
            ids.insert(conflict.otherEvent.id)
        }
        return ids
    }

    /// For each event in a conflict, the titles of the events it collides
    /// with, in `sortedConflicts` order — §11's "conflicts with Training"
    /// (task P2-T41).
    @MainActor
    static func conflictPartnerTitles(events: [Event], routineBlocks: [RoutineBlock]) -> [UUID: [String]] {
        var titles: [UUID: [String]] = [:]
        for conflict in sortedConflicts(events: events, routineBlocks: routineBlocks) {
            titles[conflict.routineEvent.id, default: []].append(conflict.otherEvent.title)
            titles[conflict.otherEvent.id, default: []].append(conflict.routineEvent.title)
        }
        return titles
    }

    /// `ConflictEngine.detect`'s result, in `ConflictOrdering`'s stable order
    /// — the single source both `conflictedEventIDs` above and
    /// `refreshConflicts()` below build from, so the id set fed to the grid
    /// and the list fed to the sidebar/inspector can never disagree about
    /// which pairs are conflicts. `static` and `@MainActor` for the same
    /// reason as `conflictedEventIDs`: `KadenceTests` drives it directly.
    @MainActor
    static func sortedConflicts(events: [Event], routineBlocks: [RoutineBlock]) -> [Conflict] {
        ConflictOrdering.sorted(ConflictEngine.detect(events: events, routineBlocks: routineBlocks))
    }

    /// Writes `Self.sortedConflicts(...)` into `state.conflicts`. Called from
    /// `.onChange(of: events)` / `.onChange(of: routineBlocks)` rather than
    /// computed straight in `body` and assigned there, because mutating an
    /// `@Observable` the view itself reads during its own body evaluation is
    /// exactly the "publishing changes from within view updates" trap —
    /// `.onChange` runs after the view update that triggered it, which is
    /// the supported place to feed a query result into stored state.
    private func refreshConflicts() {
        state.conflicts = Self.sortedConflicts(events: events, routineBlocks: routineBlocks)
    }

    // MARK: Sidebar visibility

    /// Derived from `CalendarState`, and writes back to it.
    ///
    /// Without the write-back the split view could close its own column and the
    /// app would not know — which is how this drifted into two sources of truth
    /// in the first place. A change arriving from the split view is by definition
    /// something the user did, so it counts as an explicit choice.
    private var sidebarVisibility: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { state.sidebarColumnVisibility },
            set: { newValue in
                let visible = newValue != .detailOnly
                // Guard against the echo of our own programmatic change.
                guard visible != state.isSidebarVisible else { return }
                state.setSidebarVisible(visible, isUserAction: true)
            })
    }

    // MARK: Region focus (interactions.md §1)

    /// `⇥` / `⇧⇥` leave the current region and land on the next available one,
    /// skipping the all-day row when it is hidden and the inspector when it is
    /// collapsed, and wrapping at either end.
    ///
    /// `⇥` always leaves a region rather than moving inside it, which is why this
    /// returns `.handled` unconditionally: letting AppKit also advance focus
    /// would move within the sidebar's list instead of out of it.
    private func cycleFocus(_ press: KeyPress) -> KeyPress.Result {
        let available = state.availableFocusRegions(
            allDayRowVisible: AllDayRowView.isVisible(days: state.visibleDays, fixtures: fixtures))

        let current = focusedRegion ?? state.focusedRegion
        let next = CalendarState.FocusRegion.next(
            after: current,
            backwards: press.modifiers.contains(.shift),
            available: available)

        focusedRegion = next
        state.focusedRegion = next
        return .handled
    }

    // MARK: Collapse order (§1.1)

    private func applyCollapseOrder(width: CGFloat) {
        // Auto-collapse never overwrites an explicit choice.
        if !state.userSetInspectorVisibility {
            state.isInspectorVisible = width >= 1200
        }
        state.setSidebarVisible(width >= 900, isUserAction: false)
    }

    // MARK: Toolbar (§1.2)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                state.toggleSidebar()
            } label: {
                Image(systemName: "sidebar.leading")
            }
            .help("Toggle sidebar")
            .accessibilityLabel("Toggle sidebar")

            Button { state.page(by: -1) } label: { Image(systemName: "chevron.left") }
                .help("Previous")
                .accessibilityLabel("Previous")
            Button { state.page(by: 1) } label: { Image(systemName: "chevron.right") }
                .help("Next")
                .accessibilityLabel("Next")
            Button("Today") { state.goToToday() }
        }

        ToolbarItem(placement: .principal) {
            Text(state.toolbarTitle)
                .typeStyle(.toolbarTitle)
                .foregroundStyle(Tokens.Color.Text.primary)
        }

        ToolbarItemGroup(placement: .primaryAction) {
            Picker("View", selection: Binding(
                get: { state.mode },
                set: { state.setMode($0) })) {
                    ForEach(CalendarMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

            Button { createAtCursor() } label: { Image(systemName: "plus") }
                .help("New event")
                .accessibilityLabel("New event")

            Button {
                state.userSetInspectorVisibility = true
                state.isInspectorVisible.toggle()
            } label: {
                Image(systemName: "sidebar.trailing")
            }
            .help("Toggle inspector")
            .accessibilityLabel("Toggle inspector")
        }
    }

    // MARK: Keyboard (interactions.md §2)

    /// ⌘N and the toolbar +. Starts a draft; nothing persists until it is named
    /// (interactions.md §3).
    private func createAtCursor() {
        state.beginDraft(at: state.timeCursor ?? nextHalfHour())
    }

    private func nextHalfHour() -> Date {
        let calendar = Calendar.current
        let base = calendar.isDate(state.anchor, inSameDayAs: state.now)
            ? state.now
            : calendar.startOfDay(for: state.anchor).addingTimeInterval(9 * 3600)
        return TimeGeometry.snap(base.addingTimeInterval(30 * 60), toMinutes: 30)
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let selected = selectedEvent
        let option = press.modifiers.contains(.option)
        let shift = press.modifiers.contains(.shift)
        let command = press.modifiers.contains(.command)

        switch press.key {
        case KeyEquivalent("t") where press.modifiers.isEmpty:
            state.goToToday(); return .handled

        // interactions.md §10.1 — "moving focus onto an option previews it
        // immediately". Guarded on both the inspector having focus AND a
        // conflict actually being selected, and placed ahead of every other
        // `.upArrow`/`.downArrow` case below so a focused conflict panel
        // always wins regardless of an incidental modifier key; this is the
        // only path these two keys can reach here anyway, since the
        // inspector's own `.onKeyPress` only forwards `.upArrow`/`.downArrow`/
        // `.escape` (see `inspector`'s doc comment).
        case .upArrow where state.focusedRegion == .inspector && state.selectedConflictID != nil:
            state.moveSelectedConflictOption(by: -1); return .handled
        case .downArrow where state.focusedRegion == .inspector && state.selectedConflictID != nil:
            state.moveSelectedConflictOption(by: 1); return .handled

        // interactions.md §10.1's last paragraph — "↩ applies" the focused/
        // previewed option. Same guard shape as the ↑/↓ cases above, plus a
        // focused option to actually apply; placed ahead of the ordinary
        // `.return` cases below (toggle done/skip, open inspector) for the
        // same reason those two are ahead of the rest of the ladder — a
        // focused conflict panel always wins. `↩` with the panel open but
        // nothing previewed yet falls through to `.ignored` via the plain
        // `.return` case's own `selected == nil` branch below, which is
        // correct: there is nothing to apply.
        case .return where state.focusedRegion == .inspector
            && state.selectedConflictID != nil && state.selectedConflictOptionID != nil:
            applyFocusedConflictOption(); return .handled

        case .leftArrow where option:
            if let selected { store.move(selected, by: -86400); return .handled }
            return .ignored
        case .rightArrow where option:
            if let selected { store.move(selected, by: 86400); return .handled }
            return .ignored

        case .upArrow where option && shift:
            if let selected { store.resize(selected, newEnd: selected.end.addingTimeInterval(-900)); return .handled }
            return .ignored
        case .downArrow where option && shift:
            if let selected { store.resize(selected, newEnd: selected.end.addingTimeInterval(900)); return .handled }
            return .ignored

        case .upArrow where option:
            if let selected { store.move(selected, by: -900); return .handled }
            return .ignored
        case .downArrow where option:
            if let selected { store.move(selected, by: 900); return .handled }
            return .ignored

        case .leftArrow:
            if selected == nil { state.page(by: -1); return .handled }
            return .ignored
        case .rightArrow:
            if selected == nil { state.page(by: 1); return .handled }
            return .ignored

        case .upArrow:
            return moveCursorOrSelection(by: -1)
        case .downArrow:
            return moveCursorOrSelection(by: 1)

        case .delete:
            if let selected { deleteSelection(selected); return .handled }
            return .ignored

        case .return where command && option:
            if let selected { store.toggleSkipped(selected); return .handled }
            return .ignored
        case .return where command:
            if let selected { store.toggleDone(selected); return .handled }
            return .ignored
        case .return:
            if selected != nil {
                state.userSetInspectorVisibility = true
                state.isInspectorVisible = true
                return .handled
            }
            return .ignored

        case .escape:
            // interactions.md §10.2 — "leaving the conflict panel" via ⎋,
            // unconditional, no confirmation. Checked first and returns
            // early so it cannot fall through into the selection/cursor
            // ladder below, which is unrelated state and must keep working
            // exactly as before when the grid (not the inspector) has focus.
            if state.focusedRegion == .inspector && state.selectedConflictID != nil {
                state.abandonConflictPreview()
                return .handled
            }
            // Selection mode → cursor mode → unfocused grid.
            if state.selectedEventID != nil {
                state.selectedEventID = nil
                state.timeCursor = state.timeCursor ?? nextHalfHour()
            } else if state.timeCursor != nil {
                state.timeCursor = nil
            }
            return .handled

        case .home:
            selectEdgeBlock(first: true); return .handled
        case .end:
            selectEdgeBlock(first: false); return .handled

        default:
            return .ignored
        }
    }

    private func moveCursorOrSelection(by direction: Int) -> KeyPress.Result {
        if let selected = selectedEvent {
            let sameDay = eventsOnAnchorDay
                .filter { !$0.isAllDay }
                .sorted { $0.start < $1.start }
            guard let index = sameDay.firstIndex(where: { $0.id == selected.id }) else { return .ignored }
            let next = index + direction
            guard sameDay.indices.contains(next) else { return .handled }
            state.selectedEventID = sameDay[next].id
            return .handled
        }
        // Cursor mode: 15-minute steps.
        let cursor = state.timeCursor ?? nextHalfHour()
        state.timeCursor = cursor.addingTimeInterval(TimeInterval(direction * 900))
        return .handled
    }

    private func selectEdgeBlock(first: Bool) {
        let sameDay = eventsOnAnchorDay
            .filter { !$0.isAllDay }
            .sorted { $0.start < $1.start }
        state.selectedEventID = (first ? sameDay.first : sameDay.last)?.id
    }

    private func deleteSelection(_ event: Event) {
        state.selectedEventID = nil
        store.delete(event)
    }

    /// interactions.md §10.1 — `↩` apply. `recomputeConflicts` re-runs
    /// `Self.sortedConflicts` against the live `events`/`routineBlocks`
    /// queries — safe to read synchronously right after `store`'s
    /// transaction returns because `EventStore.edit`'s fetch resolves to the
    /// SAME `@Model` instances already sitting in `events` (one identity map
    /// per `ModelContext`), so their `start`/`end`/`status` already carry the
    /// new values by the time this closure runs, with no need to wait for
    /// SwiftUI's own `@Query` refresh cycle.
    private func applyFocusedConflictOption() {
        state.applyFocusedConflictOption(store: store) {
            Self.sortedConflicts(events: events, routineBlocks: routineBlocks)
        }
    }
}
