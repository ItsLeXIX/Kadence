//
//  TimedCanvasView.swift
//  Kadence
//
//  Week and Day share all their grid machinery (layouts.md §3, §4); they differ
//  only in column count and hour-row height.
//

import SwiftUI
import SwiftData

struct TimedCanvasView: View {
    let days: [Date]
    let events: [Event]
    let fixtures: MockFixtures
    let hourHeight: CGFloat
    let now: Date
    let store: EventStore

    @Environment(CalendarState.self) private var state
    @State private var didInitialScroll = false

    private var isWeek: Bool { days.count > 1 }

    var body: some View {
        VStack(spacing: 0) {
            DayHeaderRow(days: days, events: events, now: now)

            AllDayRowView(days: days, fixtures: fixtures, now: now)

            GeometryReader { proxy in
                let available = proxy.size.width - Tokens.Size.timeGutterWidth
                let naturalWidth = available / CGFloat(days.count)
                let columnWidth = max(naturalWidth, isWeek ? Tokens.Size.dayColumnMin : naturalWidth)
                let needsHorizontalScroll = columnWidth > naturalWidth

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
                    .onAppear {
                        guard !didInitialScroll else { return }
                        didInitialScroll = true
                        vertical.scrollTo(initialAnchorHour, anchor: .top)
                    }
                }
                // Below the column floor the grid scrolls horizontally; it never
                // drops columns and never auto-switches view.
                .modifier(HorizontalScrollIfNeeded(isEnabled: needsHorizontalScroll))
            }
        }
        .background(Tokens.Color.Surface.canvas)
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
                    showsNow: days.contains { Calendar.current.isDate($0, inSameDayAs: now) })
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
                        // §7 — the window label lives in the LEADING day column,
                        // never the gutter. Only the first column draws it.
                        showsWindowLabels: index == 0,
                        store: store)
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
        // Anchors for the initial scroll position.
        .overlay(alignment: .top) {
            ForEach(0..<24, id: \.self) { hour in
                Color.clear
                    .frame(height: 1)
                    .offset(y: CGFloat(hour) * hourHeight)
                    .id(hour)
            }
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

    private func events(on day: Date) -> [Event] {
        let calendar = Calendar.current
        return events.filter { calendar.isDate($0.start, inSameDayAs: day) }
    }

    private func isWeekend(_ day: Date) -> Bool {
        Calendar.current.isDateInWeekend(day)
    }

    /// Default scroll position: `min(07:00, firstEventStart − 1h)`.
    private var initialAnchorHour: Int {
        let calendar = Calendar.current
        let firstStart = events
            .filter { event in
                !event.isAllDay && days.contains { day in calendar.isDate(event.start, inSameDayAs: day) }
            }
            .map(\.start)
            .min()
        guard let firstStart else { return 7 }
        let hour = calendar.component(.hour, from: firstStart)
        return max(0, min(7, hour - 1))
    }
}

/// Wraps the grid in a horizontal scroll view only when the columns have hit
/// their minimum width, so the common case keeps a single scroll axis.
private struct HorizontalScrollIfNeeded: ViewModifier {
    let isEnabled: Bool

    func body(content: Content) -> some View {
        if isEnabled {
            ScrollView(.horizontal) { content }
        } else {
            content
        }
    }
}
