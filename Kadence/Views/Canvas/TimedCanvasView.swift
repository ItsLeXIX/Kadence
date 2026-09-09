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

        HStack(alignment: .top, spacing: 0) {
            ZStack(alignment: .topTrailing) {
                TimeGutterView(
                    geometry: geometry,
                    now: now,
                    showsNow: days.contains { Calendar.current.isDate($0, inSameDayAs: now) })
                // The window label lives in the gutter, once, at the top edge.
                if let first = days.first {
                    WindowLabelsLayer(
                        windows: fixtures.windows,
                        day: first,
                        geometry: TimeGeometry(dayStart: first, hourHeight: hourHeight))
                }
            }
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
                    store: store)
                    .frame(width: columnWidth)
                    .background(isWeekend(day) ? Tokens.Color.Surface.canvasAlt : Tokens.Color.Surface.canvas)
                    .overlay(alignment: .leading) {
                        if index > 0 || isWeek {
                            Rectangle()
                                .fill(Tokens.Color.Separator.dayDivider)
                                .frame(width: Tokens.Size.hairline)
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
