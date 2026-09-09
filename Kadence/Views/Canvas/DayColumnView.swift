//
//  DayColumnView.swift
//  Kadence
//
//  One day of the hour grid: background windows, hour lines, laid-out blocks
//  with their travel bands, the now line, and the drag/create gestures.
//

import SwiftUI
import SwiftData

struct DayColumnView: View {
    let day: Date
    let events: [Event]
    let fixtures: MockFixtures
    let geometry: TimeGeometry
    let now: Date
    let store: EventStore

    @Environment(CalendarState.self) private var state
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// In-flight drag, kept local so the model is only written on drop.
    @State private var drag: DragSession?
    @State private var hoveredID: UUID?

    struct DragSession: Equatable {
        enum Mode: Equatable { case move, resizeTop, resizeBottom, create }
        var mode: Mode
        var eventID: UUID?
        var origin: Date
        var current: Date
        var snapMinutes: Int = 15
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let layout = DayLayoutEngine.layout(
                items: layoutItems,
                columnWidth: width,
                geometry: geometry)

            ZStack(alignment: .topLeading) {
                // 1. Canvas: background windows sit below the grid lines.
                BackgroundWindowsLayer(windows: fixtures.windows, day: day, geometry: geometry)

                // 2. Grid lines.
                HourLinesLayer(geometry: geometry)

                // 3. Empty-grid interaction surface.
                createSurface(width: width)

                // 4. Content.
                ForEach(layout.blocks.sorted(by: { $0.zIndex < $1.zIndex })) { laidOut in
                    if let event = events.first(where: { $0.id == laidOut.id }) {
                        blockStack(event: event, laidOut: laidOut)
                            .zIndex(Double(laidOut.zIndex))
                    }
                }

                // 5. Cascade overflow chips.
                ForEach(layout.overflow) { chip in
                    overflowChip(chip)
                }

                // 6. Drop preview, above content, below the now line.
                if let preview = dropPreviewFrame(in: width) {
                    dropPreview(preview.rect, isProtected: preview.isProtected)
                }

                // 7. The keyboard time cursor.
                if let cursor = state.timeCursor,
                   Calendar.current.isDate(cursor, inSameDayAs: day),
                   state.focusedRegion == .grid {
                    timeCursor(at: cursor)
                }

                // 8. Now line, above everything on the canvas.
                if Calendar.current.isDate(now, inSameDayAs: day) {
                    NowLineView(geometry: geometry, now: now, showsDot: true)
                }
            }
            .frame(height: geometry.totalHeight, alignment: .top)
        }
        .frame(height: geometry.totalHeight)
    }

    // MARK: Layout input

    private var timedEvents: [Event] {
        events.filter { !$0.isAllDay }
    }

    private var layoutItems: [LayoutItem] {
        timedEvents.map { LayoutItem(id: $0.id, start: $0.start, end: $0.end, title: $0.title) }
    }

    // MARK: A block plus its attached travel band

    @ViewBuilder
    private func blockStack(event: Event, laidOut: LaidOutBlock) -> some View {
        let model = GridBlockModel(event: event, now: now)
        let band = fixtures.travel(forEvent: event.id)
        let bandHeight = band.map { travelBandHeight(for: $0, eventStart: event.start) } ?? 0
        let isDragged = drag?.eventID == event.id

        VStack(spacing: 0) {
            if let band {
                TravelBandView(fixture: band, renderedHeight: bandHeight)
            }
            GridBlockView(
                model: model,
                presentation: presentation(for: event, laidOut: laidOut),
                renderedHeight: laidOut.frame.height,
                squareTopCorners: band != nil)
                .frame(height: laidOut.frame.height)
        }
        .frame(width: laidOut.frame.width, alignment: .topLeading)
        .offset(x: laidOut.frame.minX, y: laidOut.frame.minY - bandHeight)
        // Clamped blocks get a larger hit area centred on the true frame.
        .contentShape(
            Rectangle()
                .inset(by: -laidOut.hitExtension / 2))
        .opacity(isDragged ? Tokens.Opacity.blockDragOrigin : 1)
        .onHover { hovering in
            hoveredID = hovering ? event.id : (hoveredID == event.id ? nil : hoveredID)
        }
        .onTapGesture {
            state.selectedEventID = event.id
            state.timeCursor = nil
        }
        .gesture(blockGesture(event: event, laidOut: laidOut))
        .animation(
            reduceMotion ? nil : .spring(
                response: Tokens.Motion.BlockMove.Spring.response,
                dampingFraction: Tokens.Motion.BlockMove.Spring.dampingFraction),
            value: laidOut.frame)
    }

    /// components.md §4 — the band floors at `size.travelBandHeight` and, when
    /// the floor applies, grows upward from the event's top edge.
    private func travelBandHeight(for fixture: TravelFixture, eventStart: Date) -> CGFloat {
        let trueHeight = geometry.height(from: fixture.departAt, to: eventStart)
        return max(trueHeight, Tokens.Size.travelBandHeight)
    }

    private func presentation(for event: Event, laidOut: LaidOutBlock) -> Presentation {
        var presentation: Presentation = []
        if state.selectedEventID == event.id { presentation.insert(.selected) }
        if hoveredID == event.id { presentation.insert(.hovered) }
        if drag?.eventID == event.id { presentation.insert(.dragging) }
        if event.isPast(now: now) { presentation.insert(.past) }
        if conflictsWithProtectedWindow(event) { presentation.insert(.conflicted) }
        return presentation
    }

    /// Phase 1 has no conflict engine (that is Phase 2), but a block sitting in
    /// a protected window is a conflict the spec asks to be *rendered*, so it is
    /// derived here rather than stored.
    private func conflictsWithProtectedWindow(_ event: Event) -> Bool {
        fixtures.windows
            .filter { $0.kind == .protected }
            .flatMap { $0.spans(on: day) }
            .contains { span in event.start < span.end && span.start < event.end }
    }

    // MARK: Gestures

    private func blockGesture(event: Event, laidOut: LaidOutBlock) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard event.isMovable else { return }
                let handle = Tokens.Size.blockResizeHandleHeight
                let localY = value.startLocation.y - laidOut.frame.minY
                let mode: DragSession.Mode =
                    localY <= handle ? .resizeTop
                    : localY >= laidOut.frame.height - handle ? .resizeBottom
                    : .move

                let snap = NSEvent.modifierFlags.contains(.control) ? 5 : 15
                let delta = value.translation.height
                let deltaTime = TimeInterval(delta / geometry.hourHeight) * 3600

                if drag == nil {
                    drag = DragSession(
                        mode: mode, eventID: event.id,
                        origin: event.start, current: event.start, snapMinutes: snap)
                }
                drag?.snapMinutes = snap
                drag?.current = TimeGeometry.snap(
                    event.start.addingTimeInterval(deltaTime), toMinutes: snap)
            }
            .onEnded { _ in
                defer { drag = nil }
                guard let session = drag, session.eventID == event.id else { return }
                switch session.mode {
                case .move:
                    store.move(event, toStart: session.current)
                case .resizeTop:
                    store.resize(event, newStart: session.current)
                case .resizeBottom:
                    let delta = session.current.timeIntervalSince(session.origin)
                    store.resize(event, newEnd: event.end.addingTimeInterval(delta))
                case .create:
                    break
                }
                state.selectedEventID = event.id
            }
    }

    /// Empty grid: click to place the cursor, double-click or drag to create.
    private func createSurface(width: CGFloat) -> some View {
        Rectangle()
            .fill(.clear)
            .contentShape(Rectangle())
            .frame(height: geometry.totalHeight)
            .onTapGesture(count: 2) { location in
                let start = TimeGeometry.snap(geometry.date(forY: location.y), toMinutes: 15)
                let event = store.create(at: start)
                state.selectedEventID = event.id
                state.inlineEditingEventID = event.id
            }
            .onTapGesture { location in
                state.selectedEventID = nil
                state.timeCursor = TimeGeometry.snap(geometry.date(forY: location.y), toMinutes: 15)
            }
            .gesture(
                DragGesture(minimumDistance: 6)
                    .onChanged { value in
                        let snap = NSEvent.modifierFlags.contains(.control) ? 5 : 15
                        let from = TimeGeometry.snap(geometry.date(forY: value.startLocation.y), toMinutes: snap)
                        let to = TimeGeometry.snap(geometry.date(forY: value.location.y), toMinutes: snap)
                        drag = DragSession(
                            mode: .create, eventID: nil,
                            origin: from, current: to, snapMinutes: snap)
                    }
                    .onEnded { _ in
                        defer { drag = nil }
                        guard let session = drag, session.mode == .create else { return }
                        let lower = min(session.origin, session.current)
                        let upper = max(session.origin, session.current)
                        let duration = max(upper.timeIntervalSince(lower), 15 * 60)
                        let event = store.create(at: lower, duration: duration)
                        state.selectedEventID = event.id
                        state.inlineEditingEventID = event.id
                    }
            )
    }

    // MARK: Drop preview and cursor

    private func dropPreviewFrame(in width: CGFloat) -> (rect: CGRect, isProtected: Bool)? {
        guard let session = drag else { return nil }
        let inset = Tokens.Spacing.xxs

        switch session.mode {
        case .create:
            let lower = min(session.origin, session.current)
            let upper = max(session.origin, session.current)
            let rect = CGRect(
                x: inset, y: geometry.y(for: lower),
                width: width - 2 * inset,
                height: max(geometry.height(from: lower, to: upper), Tokens.Size.blockMinRenderedHeight))
            return (rect, isInProtectedWindow(lower, upper))

        case .move, .resizeTop, .resizeBottom:
            guard let id = session.eventID,
                  let event = events.first(where: { $0.id == id }) else { return nil }
            let start: Date
            let end: Date
            switch session.mode {
            case .resizeTop:
                start = min(session.current, event.end.addingTimeInterval(-15 * 60))
                end = event.end
            case .resizeBottom:
                start = event.start
                let delta = session.current.timeIntervalSince(session.origin)
                end = max(event.end.addingTimeInterval(delta), start.addingTimeInterval(15 * 60))
            default:
                start = session.current
                end = session.current.addingTimeInterval(event.duration)
            }
            let rect = CGRect(
                x: inset, y: geometry.y(for: start),
                width: width - 2 * inset,
                height: max(geometry.height(from: start, to: end), Tokens.Size.blockMinRenderedHeight))
            return (rect, isInProtectedWindow(start, end))
        }
    }

    private func isInProtectedWindow(_ start: Date, _ end: Date) -> Bool {
        fixtures.windows
            .filter { $0.kind == .protected }
            .flatMap { $0.spans(on: day) }
            .contains { start < $0.end && $0.start < end }
    }

    /// A drop into a protected window is allowed — the user is being explicit,
    /// and the rule binds automatic placement. The outline turns alert so they
    /// see the cost; they are not blocked from paying it.
    private func dropPreview(_ rect: CGRect, isProtected: Bool) -> some View {
        RoundedRectangle(cornerRadius: Tokens.Radius.block, style: .continuous)
            .strokeBorder(
                isProtected ? Tokens.Color.Semantic.alert : Tokens.Color.Interactive.accent,
                style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .allowsHitTesting(false)
    }

    private func timeCursor(at date: Date) -> some View {
        Rectangle()
            .fill(Tokens.Color.Interactive.accent)
            .frame(height: 1)
            .offset(y: geometry.y(for: date))
            .allowsHitTesting(false)
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
            .offset(x: chip.anchor.x - 28, y: chip.anchor.y)
            .onTapGesture {
                state.anchor = day
                state.mode = .day
            }
    }
}
