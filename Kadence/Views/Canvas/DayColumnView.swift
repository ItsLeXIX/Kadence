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
    /// §7 — the window label is drawn once, in the leading day column.
    var showsWindowLabels: Bool = false
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
                // Background windows are drawn by the canvas, not here: §7 has
                // them spanning the time gutter too. See TimedCanvasView.

                // 1. Grid lines.
                HourLinesLayer(geometry: geometry)

                // 2. Window labels — leading day column only, never the gutter.
                if showsWindowLabels {
                    WindowLabelsLayer(
                        windows: fixtures.windows,
                        day: day,
                        geometry: geometry)
                }

                // 3. Empty-grid interaction surface.
                createSurface(width: width)

                // 4. Content.
                ForEach(layout.blocks.sorted(by: { $0.zIndex < $1.zIndex })) { laidOut in
                    if let event = events.first(where: { $0.id == laidOut.id }) {
                        blockStack(event: event, laidOut: laidOut)
                            .zIndex(Double(laidOut.zIndex))
                    } else if let draft = draftOnThisDay, draft.id == laidOut.id {
                        draftBlock(laidOut: laidOut)
                            .zIndex(Double(laidOut.zIndex) + 500)
                    }
                }

                // 5. Cascade overflow chips.
                // The chip draws above every block in the cluster, not in the
                // cluster's z-order — a +N that a block is sitting on top of
                // tells the user nothing (layouts.md §3.3).
                ForEach(layout.overflow) { chip in
                    overflowChip(chip)
                        .zIndex(1000)
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
                // components.md §8 — above every block and every background
                // window. Blocks carry their own zIndex, so this needs one that
                // beats them (review D-2: the line was behind the 17:00 block).
                if Calendar.current.isDate(now, inSameDayAs: day) {
                    NowLineView(geometry: geometry, now: now, showsDot: true)
                        .zIndex(2000)
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
        var items = timedEvents.map {
            LayoutItem(id: $0.id, start: $0.start, end: $0.end, title: $0.title)
        }
        // The draft is laid out with everything else so the user sees where it
        // will land, even though it is not in the store (interactions.md §3).
        if let draft = draftOnThisDay {
            items.append(LayoutItem(id: draft.id, start: draft.start, end: draft.end, title: draft.title))
        }
        return items
    }

    private var draftOnThisDay: EventDraft? {
        guard let draft = state.draft,
              Calendar.current.isDate(draft.start, inSameDayAs: day) else { return nil }
        return draft
    }

    // MARK: A block plus its attached travel band

    @ViewBuilder
    private func draftBlock(laidOut: LaidOutBlock) -> some View {
        // CalendarState.draftBinding(), never Binding($state.draft): the latter
        // force-unwraps on every read and traps when ⎋ or ↩ clears the draft
        // out from under the field that is still being torn down.
        if let binding = state.draftBinding() {
            DraftBlockView(
                draft: binding,
                renderedHeight: laidOut.frame.height,
                onCommit: commitDraft,
                onDiscard: { state.discardDraft() })
                .frame(width: laidOut.frame.width, height: laidOut.frame.height, alignment: .topLeading)
                .offset(x: laidOut.frame.minX, y: laidOut.frame.minY)
        }
    }

    /// ↩ — persists only if there is a title, and selects the result.
    private func commitDraft() {
        guard let draft = state.draft else { return }
        if let event = store.commit(draft) {
            state.selectedEventID = event.id
        }
        state.discardDraft()
    }

    @ViewBuilder
    private func blockStack(event: Event, laidOut: LaidOutBlock) -> some View {
        let model = GridBlockModel(event: event, now: now)
        let band = fixtures.travel(forEvent: event.id)
        let trueBandHeight = band.map { geometry.height(from: $0.departAt, to: event.start) } ?? 0
        // components.md §4, two cases. A short band no longer grows upward out of
        // its event: it becomes a strip inside the event's own top, because the
        // upward version covered the meta line of whatever sat above it (R-1).
        let bandFitsAbove = band != nil && trueBandHeight >= Tokens.Size.travelBandHeight
        let insideStrip = band != nil && !bandFitsAbove
        let aboveHeight = bandFitsAbove ? trueBandHeight : 0
        let isDragged = drag?.eventID == event.id

        VStack(spacing: 0) {
            if let band, bandFitsAbove {
                TravelBandView(fixture: band, renderedHeight: aboveHeight)
            }
            ZStack(alignment: .top) {
                GridBlockView(
                    model: model,
                    presentation: presentation(for: event, laidOut: laidOut),
                    renderedHeight: laidOut.frame.height,
                    visibleWidth: laidOut.visibleWidth,
                    squareTopCorners: bandFitsAbove,
                    contentTopInset: insideStrip ? Tokens.Size.travelBandHeight : 0)
                if let band, insideStrip {
                    TravelBandView(fixture: band, renderedHeight: Tokens.Size.travelBandHeight)
                        .clipShape(
                            PartialRoundedRectangle(
                                topRadius: Tokens.Radius.block,
                                bottomRadius: 0))
                }
            }
            // §3.5 rule 2 — `alignment: .top`, never SwiftUI's default `.center`.
            // This line took the default and centred a block's content on the
            // laid-out frame, which is how two non-overlapping blocks ended up
            // drawn on top of each other (STATUS.md §1.7 (a), DEVIATIONS B13).
            // `GridBlockView` now also constrains and clips itself, so this is
            // the second of two locks on the same rule, not the only one.
            .frame(height: laidOut.frame.height, alignment: .top)
        }
        .frame(width: laidOut.frame.width, alignment: .topLeading)
        // Clamped blocks get a larger hit area centred on the true frame
        // (`LaidOutBlock.hitInset`).
        //
        // ORDER IS LOAD-BEARING: `.contentShape` MUST come before `.offset`.
        // `.offset` is a render-time translation that moves what is drawn while
        // leaving the layout frame where it was. A `.contentShape` applied
        // *after* it therefore describes the hit region in the UN-offset layout
        // space, which collapsed every block's hit region onto its day column's
        // top-left corner. Blocks still drew in the right place, so screenshots
        // looked perfect while a click could not land on the block it was aimed
        // at: it either hit whichever block was frontmost in the collapsed pile
        // (selecting an event hours away) or fell through to the create surface
        // behind them, which deselected instead. Both read as "nothing happens".
        // Measured: with the two lines swapped, all 20 mock blocks report just
        // 2 distinct accessibility y values instead of 20. See STATUS.md §1.6
        // and Scripts/check-block-hit-regions.sh.
        .contentShape(Rectangle().inset(by: laidOut.hitInset))
        .offset(x: laidOut.frame.minX, y: laidOut.frame.minY - aboveHeight)
        .opacity(isDragged ? Tokens.Opacity.blockDragOrigin : 1)
        // interactions.md §8 — a draggable block gets the open hand; one that
        // cannot move keeps the arrow rather than promising a drag.
        .cursor(event.isMovable ? .openHand : .arrow)
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
            .cursor(.crosshair)
            .accessibilityHidden(true)
            .onTapGesture(count: 2) { location in
                let start = TimeGeometry.snap(geometry.date(forY: location.y), toMinutes: 15)
                state.beginDraft(at: start)
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
                        state.beginDraft(at: lower, duration: duration)
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
            .accessibilityHidden(true)
    }

    private func timeCursor(at date: Date) -> some View {
        Rectangle()
            .fill(Tokens.Color.Interactive.accent)
            .frame(height: 1)
            .offset(y: geometry.y(for: date))
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
            .onTapGesture {
                state.anchor = day
                state.mode = .day
            }
    }
}
