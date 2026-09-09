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
    @State private var fixtures = MockFixtures()
    @State private var didSeed = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    private var store: EventStore { EventStore(context: context, undo: undoStack) }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width

            NavigationSplitView(columnVisibility: $columnVisibility) {
                SidebarView(needsAttentionCount: 0)
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
        }
        .frame(
            minWidth: Tokens.Size.windowMinWidth,
            minHeight: Tokens.Size.windowMinHeight)
        .task {
            guard !didSeed else { return }
            didSeed = true
            fixtures = MockData.seedIfNeeded(context)
        }
        .onReceive(
            Timer.publish(every: Tokens.Motion.NowLineTick.interval, on: .main, in: .common).autoconnect()
        ) { date in
            state.now = date
        }
        .onReceive(NotificationCenter.default.publisher(for: .kadenceNewEvent)) { _ in
            createAtCursor()
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
                    store: store)
            case .day:
                TimedCanvasView(
                    days: state.visibleDays,
                    events: visible,
                    fixtures: fixtures,
                    hourHeight: Tokens.Size.hourHeightDay,
                    now: state.now,
                    store: store)
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
        .focusEffectDisabled()
        .onKeyPress(action: handleKey)
    }

    private var inspector: some View {
        InspectorView(
            event: selectedEvent,
            dayEvents: eventsOnAnchorDay,
            day: state.anchor,
            travel: selectedEvent.flatMap { fixtures.travel(forEvent: $0.id) },
            now: state.now,
            store: store)
    }

    private var selectedEvent: Event? {
        guard let id = state.selectedEventID else { return nil }
        return events.first { $0.id == id }
    }

    private var eventsOnAnchorDay: [Event] {
        events.filter { Calendar.current.isDate($0.start, inSameDayAs: state.anchor) }
    }

    // MARK: Collapse order (§1.1)

    private func applyCollapseOrder(width: CGFloat) {
        // Auto-collapse never overwrites an explicit choice.
        if !state.userSetInspectorVisibility {
            state.isInspectorVisible = width >= 1200
        }
        if !state.userSetSidebarVisibility {
            columnVisibility = width >= 900 ? .all : .detailOnly
        }
    }

    // MARK: Toolbar (§1.2)

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                state.userSetSidebarVisibility = true
                columnVisibility = columnVisibility == .all ? .detailOnly : .all
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

    private func createAtCursor() {
        let start = state.timeCursor ?? nextHalfHour()
        let event = store.create(at: start)
        state.selectedEventID = event.id
        state.inlineEditingEventID = event.id
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
}
