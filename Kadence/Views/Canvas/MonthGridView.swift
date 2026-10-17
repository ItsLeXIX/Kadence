//
//  MonthGridView.swift
//  Kadence
//
//  layouts.md §5. Always six rows, so the grid never reflows when paging.
//  No now line, no background windows, no travel bands.
//

import SwiftUI
import SwiftData

struct MonthGridView: View {
    let days: [Date]
    let events: [Event]
    let fixtures: MockFixtures
    let now: Date
    let anchorMonth: Date

    @Environment(CalendarState.self) private var state

    private let columns = 7
    private let rows = 6

    var body: some View {
        VStack(spacing: 0) {
            weekdayHeader
            GeometryReader { proxy in
                let available = proxy.size.height
                let naturalRow = available / CGFloat(rows)
                let rowHeight = max(naturalRow, Tokens.Size.monthCellMinHeightFloor)
                let needsScroll = rowHeight > naturalRow

                Group {
                    if needsScroll {
                        ScrollView(.vertical) { grid(rowHeight: rowHeight) }
                    } else {
                        grid(rowHeight: rowHeight)
                    }
                }
            }
        }
        .background(Tokens.Color.Surface.canvas)
        .overlay {
            Rectangle()
                .strokeBorder(Tokens.Color.Separator.region, lineWidth: Tokens.Size.hairline)
        }
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(Array(days.prefix(columns)), id: \.self) { day in
                Text(weekdayFormatter.string(from: day))
                    .typeStyle(.dayHeaderWeekday)
                    .foregroundStyle(Tokens.Color.Text.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: Tokens.Size.monthWeekdayHeaderHeight)
        .background(Tokens.Color.Surface.canvasAlt)
    }

    private func grid(rowHeight: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { column in
                        let index = row * columns + column
                        if index < days.count {
                            cell(for: days[index])
                                .frame(maxWidth: .infinity)
                                .frame(height: rowHeight)
                                .overlay(alignment: .top) {
                                    Rectangle()
                                        .fill(Tokens.Color.Separator.hour)
                                        .frame(height: Tokens.Size.hairline)
                                }
                                .overlay(alignment: .leading) {
                                    if column > 0 {
                                        Rectangle()
                                            .fill(Tokens.Color.Separator.hour)
                                            .frame(width: Tokens.Size.hairline)
                                    }
                                }
                        }
                    }
                }
            }
        }
    }

    /// The timed events a cell lists: those that **start** on its day, in
    /// start order. Month places by date, so a clock change does not move
    /// anything here (components.md §31.4).
    static func timedEvents(_ events: [Event], on day: Date, calendar: Calendar) -> [Event] {
        events
            // §37.3: a moment is a chip in the all-day section, not here.
            .filter { !$0.isDrawnAsAllDay && calendar.isDate($0.start, inSameDayAs: day) }
            .sorted { $0.start < $1.start }
    }

    @ViewBuilder
    private func cell(for day: Date) -> some View {
        let calendar = Calendar.current
        let inMonth = calendar.isDate(day, equalTo: anchorMonth, toGranularity: .month)
        let isToday = calendar.isDate(day, inSameDayAs: now)
        let allDay = fixtures.allDayItems(on: day)
        let timed = Self.timedEvents(events, on: day, calendar: calendar)
        let maxRows = Tokens.Size.monthCellMaxVisibleRows
        let total = allDay.count + timed.count

        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            HStack {
                if isToday {
                    Text(dayNumberFormatter.string(from: day))
                        .typeStyle(.monthDate)
                        .foregroundStyle(Tokens.Color.Text.onSolid)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(Tokens.Color.Interactive.accent))
                } else {
                    Text(dayNumberFormatter.string(from: day))
                        .typeStyle(.monthDate)
                        .foregroundStyle(inMonth ? Tokens.Color.Text.primary : Tokens.Color.Text.tertiary)
                }
                Spacer(minLength: 0)
            }
            .padding(.top, Tokens.Spacing.xs)
            .padding(.horizontal, Tokens.Spacing.xs)

            // All-day items sort above timed events, always.
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                ForEach(allDay.prefix(maxRows)) { item in
                    AllDayItemView(fixture: item,
                                   presentation: item.eventID != nil && item.eventID == state.selectedEventID ? [.selected] : [],
                                   now: now, showsMomentTime: false)
                        .frame(height: Tokens.Size.monthCellRowHeight)
                        .onTapGesture { if let id = item.eventID { state.selectedEventID = id } }
                }
                ForEach(Array(timed.prefix(max(0, maxRows - allDay.count))), id: \.id) { event in
                    MonthChipView(
                        model: GridBlockModel(event: event, now: now),
                        presentation: state.selectedEventID == event.id ? [.selected] : [])
                        .onTapGesture { state.selectedEventID = event.id }
                }
                if total > maxRows {
                    Button {
                        state.anchor = day
                        state.mode = .day
                    } label: {
                        Text("+\(total - maxRows) more")
                            .typeStyle(.blockMeta)
                            .foregroundStyle(Tokens.Color.Text.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Tokens.Spacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(inMonth ? Tokens.Color.Surface.canvas : Tokens.Color.Surface.canvasAlt)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            // Double-click a month cell creates a 60-minute event at 09:00.
            let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day) ?? day
            state.anchor = day
        }
    }

    private var weekdayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE"
        return formatter
    }

    private var dayNumberFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "d"
        return formatter
    }
}
