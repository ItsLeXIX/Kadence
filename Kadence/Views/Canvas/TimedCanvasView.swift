//
//  TimedCanvasView.swift
//  Kadence
//
//  Week and Day share all their grid machinery (layouts.md §3, §4); they differ
//  only in column count and hour-row height.
//

import SwiftUI
import SwiftData
import AppKit

struct TimedCanvasView: View {
    let days: [Date]
    let events: [Event]
    let fixtures: MockFixtures
    let hourHeight: CGFloat
    let now: Date
    let store: EventStore
    /// Every event id that is one half of a `ConflictEngine.detect` result
    /// (P2-T14) — threaded straight through to `DayColumnView`, same as
    /// `events`/`fixtures`/`now`, so a routine-vs-manual/imported overlap
    /// also renders `.conflicted`, alongside (not replacing) the Phase 1
    /// protected-window placeholder.
    var conflictedEventIDs: Set<UUID> = []
    /// See `DayColumnView.conflictPartnerTitles` (task P2-T41).
    var conflictPartnerTitles: [UUID: [String]] = [:]
    /// interactions.md §1 — the all-day row is its own ⇥ stop, and it lives here
    /// rather than in MainWindow, so the focus binding is passed down.
    var focusedRegion: FocusState<CalendarState.FocusRegion?>.Binding
    var onTab: (KeyPress) -> KeyPress.Result

    @Environment(CalendarState.self) private var state
    /// layouts.md §3.1: while true, the canvas keeps `InitialScroll.hour`
    /// at the top (task P2-F22). Cleared by the user's first scroll or a
    /// conflict scroll request.
    @State private var holdsInitialScroll = true
    /// Bound on the hold's re-aims, so a target that can never be met (it
    /// shouldn't happen — the target is clamped) can't loop forever.
    @State private var initialScrollAims = 0
    /// The viewport in content coordinates (task P2-F15).
    @State private var visibleRect: CGRect = .zero
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Every column's block frames, reported up through
    /// `ColumnLabelInputsKey` — what §7 rule 2's label placement needs.
    @State private var labelInputs: [Int: ColumnLabelInputs] = [:]
    /// `CanvasColumnLayout.systemScrollerReserve`, re-read when the user
    /// switches "Show scroll bars" (AppKit posts a notification; SwiftUI's
    /// `.onReceive` subscribes to it like a listener in Java).
    @State private var scrollerReserve = CanvasColumnLayout.systemScrollerReserve

    private var isWeek: Bool { days.count > 1 }

    var body: some View {
        VStack(spacing: 0) {
            DayHeaderRow(days: days, events: events, now: now, trailingReserve: scrollerReserve)

            AllDayRowView(days: days, fixtures: fixtures, now: now, trailingReserve: scrollerReserve)
                .focusable(AllDayRowView.isVisible(days: days, fixtures: fixtures))
                .focused(focusedRegion, equals: .allDayRow)
                .onKeyPress(keys: [.tab]) { onTab($0) }


            GeometryReader { proxy in
                // Task P2-F02 (B20): the legacy scroller's width is reserved
                // before the columns are divided, or the scroll view grows by
                // it and paints over the inspector (`CanvasColumnLayout`).
                let layout = CanvasColumnLayout.columnWidth(
                    totalWidth: proxy.size.width,
                    gutterWidth: Tokens.Size.timeGutterWidth,
                    dayCount: days.count,
                    columnMin: isWeek ? Tokens.Size.dayColumnMin : nil,
                    scrollerReserve: scrollerReserve)
                let columnWidth = layout.width
                let needsHorizontalScroll = layout.needsHorizontalScroll

                ScrollViewReader { vertical in
                    ScrollView(.vertical) {
                        gridBody(columnWidth: columnWidth)
                            .frame(
                                width: needsHorizontalScroll
                                    ? Tokens.Size.timeGutterWidth + columnWidth * CGFloat(days.count)
                                    : nil,
                                alignment: .leading)
                    }
                    .scrollIndicators(.automatic)
                    // macOS 15: the visible part of the content, in content
                    // points — what "wholly inside the viewport" is tested
                    // against (interactions.md §10.1, task P2-F15).
                    .onScrollGeometryChange(for: CGRect.self) { $0.visibleRect } action: { _, rect in
                        visibleRect = rect
                    }
                    // layouts.md §3.1 (task P2-F22, DEVIATIONS B24): open with
                    // `InitialScroll.hour` at the top, and HOLD it there until
                    // the user first scrolls. A single `scrollTo` at appear
                    // isn't enough (found live): the canvas lays out several
                    // times while the window settles (viewport 56 → 596 → 780pt,
                    // a 44pt top inset coming and going), any of which can
                    // drop or reset the scroll, and on a fresh store the
                    // events — so the hour — arrive after the first render
                    // (`MainWindow` seeds in its `.task`). So every geometry
                    // change re-checks the position and re-aims if it's off.
                    .onScrollGeometryChange(for: InitialScroll.Position.self) { geometry in
                        InitialScroll.Position(geometry)
                    } action: { _, position in
                        holdInitialScroll(position, using: vertical)
                    }
                    .onChange(of: InitialScroll.hour(events: events, days: days)) { _, _ in
                        guard holdsInitialScroll else { return }
                        aimInitialScroll(using: vertical)
                    }
                    // The user's first scroll (trackpad, wheel, scroller) ends
                    // the hold; a programmatic `scrollTo` stays `.idle`.
                    .onScrollPhaseChange { _, phase in
                        if phase == .tracking || phase == .interacting || phase == .decelerating {
                            holdsInitialScroll = false
                        }
                    }
                    // A conflict was activated: bring it into view.
                    .onChange(of: state.conflictScrollRequest) { _, request in
                        guard let request else { return }
                        holdsInitialScroll = false   // the conflict's scroll wins
                        bringIntoView(request, using: vertical)
                    }
                }
                // Below the column floor the grid scrolls horizontally; it never
                // drops columns and never auto-switches view.
                .modifier(HorizontalScrollIfNeeded(isEnabled: needsHorizontalScroll))
            }
        }
        .background(Tokens.Color.Surface.canvas)
        .onReceive(NotificationCenter.default.publisher(for: NSScroller.preferredScrollerStyleDidChangeNotification)) { _ in
            scrollerReserve = CanvasColumnLayout.systemScrollerReserve
        }
    }

    @ViewBuilder
    private func gridBody(columnWidth: CGFloat) -> some View {
        let geometry = TimeGeometry(
            dayStart: Calendar.current.startOfDay(for: days.first ?? now),
            hourHeight: hourHeight)

        ZStack(alignment: .topLeading) {
            // components.md §7 — background windows are CANVAS, not content, and
            // "span the full column width **including the time gutter**, drawn
            // below the hour lines and below every block". They therefore cannot
            // live inside DayColumnView, which starts after the gutter; they are
            // one backdrop behind the whole grid (DEVIATIONS.md A1 / review D-3).
            windowsBackdrop(columnWidth: columnWidth)

            HStack(alignment: .top, spacing: 0) {
                TimeGutterView(
                    geometry: geometry,
                    now: now,
                    showsNow: days.contains { Calendar.current.isDate($0, inSameDayAs: now) },
                    // Only while the grid is focused in cursor mode, matching the
                    // line drawn in the column (interactions.md §1).
                    cursor: gutterCursor)
                .frame(width: Tokens.Size.timeGutterWidth)
                .id(0)

                ForEach(Array(days.enumerated()), id: \.element) { index, day in
                    let dayGeometry = TimeGeometry(
                        dayStart: Calendar.current.startOfDay(for: day),
                        hourHeight: hourHeight)
                    DayColumnView(
                        day: day,
                        events: events(on: day),
                        fixtures: fixtures,
                        geometry: dayGeometry,
                        now: now,
                        // §7 rules 2–3 (task P2-F06): labels placed by
                        // `windowLabelPlacement`, never in the gutter.
                        windowLabels: placedLabels.filter { $0.columnIndex == index },
                        columnIndex: index,
                        store: store,
                        conflictedEventIDs: conflictedEventIDs,
                        conflictPartnerTitles: conflictPartnerTitles)
                        .frame(width: columnWidth)
                        // Weekend tint has to be behind the blocks but IN FRONT of
                        // nothing — the window backdrop is below it, so the tint is
                        // drawn as a translucent wash rather than an opaque fill,
                        // otherwise it would hide the protected shading underneath.
                        .background(
                            isWeekend(day)
                                ? Tokens.Color.Surface.canvasAlt.opacity(0.6)
                                : Color.clear)
                        .overlay(alignment: .leading) {
                            if index > 0 || isWeek {
                                Rectangle()
                                    .fill(Tokens.Color.Separator.dayDivider)
                                    .frame(width: Tokens.Size.hairline)
                            }
                        }
                }
            }
        }
        // Five-minute anchors for bringing a conflict into view (P2-F15)
        // and for the initial scroll position (P2-F22). There used to be a
        // second set of 24 hour anchors placed with `.offset(y:)`; `scrollTo`
        // reads layout frames, so they all sat at y = 0 and the canvas always
        // opened at 00:00 (DEVIATIONS B24).
        .overlay(alignment: .top) {
            ConflictScrollAnchors(hourHeight: hourHeight)
        }
        // Collect what the columns reported (see `ColumnLabelInputsKey`).
        // Frames depend only on layout, never on where labels go, so this
        // settles in one pass.
        .onPreferenceChange(ColumnLabelInputsKey.self) { inputs in
            labelInputs = inputs
        }
    }

    /// One continuous canvas layer behind gutter + every column, so a protected
    /// or low-energy window reads as a single band across the whole grid and its
    /// edges stay visible when a column is full of blocks.
    ///
    /// The gutter takes the leading day's windows: the gutter is shared by all
    /// seven columns, and in practice these windows repeat daily (sleep, the
    /// post-lunch dip), so the leading day is the honest representative. Each
    /// column still draws its own, so a window that does not apply on Saturday
    /// simply is not shaded there.
    @ViewBuilder
    private func windowsBackdrop(columnWidth: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if let first = days.first {
                BackgroundWindowsLayer(
                    windows: fixtures.windows,
                    day: first,
                    geometry: TimeGeometry(
                        dayStart: Calendar.current.startOfDay(for: first),
                        hourHeight: hourHeight))
                    .frame(width: Tokens.Size.timeGutterWidth)
            }
            ForEach(days, id: \.self) { day in
                BackgroundWindowsLayer(
                    windows: fixtures.windows,
                    day: day,
                    geometry: TimeGeometry(
                        dayStart: Calendar.current.startOfDay(for: day),
                        hourHeight: hourHeight))
                    .frame(width: columnWidth)
            }
        }
        .frame(height: hourHeight * 24, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// One re-check of the initial scroll position (see the modifier's comment).
    private func holdInitialScroll(_ position: InitialScroll.Position, using proxy: ScrollViewProxy) {
        guard holdsInitialScroll else { return }
        let hour = InitialScroll.hour(events: events, days: days)
        guard InitialScroll.needsAim(position, hour: hour, hourHeight: hourHeight) else { return }
        aimInitialScroll(using: proxy)
    }

    private func aimInitialScroll(using proxy: ScrollViewProxy) {
        guard initialScrollAims < InitialScroll.maxAims else {
            holdsInitialScroll = false
            return
        }
        initialScrollAims += 1
        let anchor = ConflictScroll.anchorID(minute: InitialScroll.hour(events: events, days: days) * 60)
        // Deferred one main-actor turn: inside a layout/geometry callback the
        // scroll view hasn't finished laying out, and a `scrollTo` then is
        // silently dropped (found live). `Task { @MainActor in … }` is like
        // posting a Runnable to the UI thread's queue in Java/C#.
        Task { @MainActor in
            proxy.scrollTo(anchor, anchor: .top)
        }
    }

    /// interactions.md §10.1 (amended 2026-10-05, task P2-F15): if the
    /// occurrence isn't wholly in view, scroll so the earlier colliding start
    /// sits one third from the top, over `motion.paging` (instant under
    /// Reduce Motion). Paging to its week already happened in
    /// `CalendarState.open(_:)`; a day not on this canvas is ignored.
    private func bringIntoView(_ request: CalendarState.ConflictScrollRequest, using proxy: ScrollViewProxy) {
        let calendar = Calendar.current
        guard let day = days.first(where: { calendar.isDate($0, inSameDayAs: request.occurrenceStart) }) else { return }
        let dayStart = calendar.startOfDay(for: day)
        func minute(_ date: Date) -> Int { Int(date.timeIntervalSince(dayStart) / 60) }
        guard let target = ConflictScroll.targetMinute(
            occurrence: minute(request.occurrenceStart)..<max(minute(request.occurrenceEnd), minute(request.occurrenceStart) + 1),
            earliestStart: minute(request.earliestStart),
            visibleTop: visibleRect.minY,
            visibleHeight: visibleRect.height,
            hourHeight: hourHeight)
        else { return }
        withAnimation(ConflictScroll.animation(reduceMotion: reduceMotion)) {
            proxy.scrollTo(ConflictScroll.anchorID(minute: target), anchor: ConflictScroll.oneThird)
        }
    }

    /// components.md §7 rules 2–3 (task P2-F06): one label per window span,
    /// in the leading column whose label rect no block covers.
    private var placedLabels: [WindowLabelPlacement.Placed] {
        WindowLabelPlacement.place(
            windows: fixtures.windows,
            columns: days.indices.map { index in
                WindowLabelPlacement.Column(
                    day: days[index],
                    blockFrames: labelInputs[index]?.blockFrames ?? [])
            },
            hourHeight: hourHeight,
            showsPeakFocus: false,
            avoidsBlocks: true)
    }

    /// The cursor time to print in the gutter, or nil when there is no cursor to
    /// show. The gutter is one ruler for all seven columns, so it shows the time
    /// whichever day column the cursor is in.
    private var gutterCursor: Date? {
        guard state.focusedRegion == .grid, let cursor = state.timeCursor else { return nil }
        guard days.contains(where: { Calendar.current.isDate($0, inSameDayAs: cursor) }) else { return nil }
        return cursor
    }

    private func events(on day: Date) -> [Event] {
        let calendar = Calendar.current
        return events.filter { calendar.isDate($0.start, inSameDayAs: day) }
    }

    private func isWeekend(_ day: Date) -> Bool {
        Calendar.current.isDateInWeekend(day)
    }
}

/// Wraps the grid in a horizontal scroll view only when the columns have hit
/// their minimum width, so the common case keeps a single scroll axis.
///
/// Internal rather than `private` so the Routines window (`layouts.md` §8,
/// `Kadence/Views/Routines/RoutinesWindow.swift`) can reuse the same
/// column-floor behaviour instead of re-implementing it — its grid is a
/// different data type (`RoutineBlock`, not `Event`) but the same geometry
/// rule applies verbatim.
struct HorizontalScrollIfNeeded: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            ScrollView(.horizontal) { content }
        } else {
            content
        }
    }
}
