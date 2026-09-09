//
//  DayHeaderRow.swift
//  Kadence
//

import SwiftUI
import SwiftData

struct DayHeaderRow: View {
    let days: [Date]
    let events: [Event]
    let now: Date

    private var isWeek: Bool { days.count > 1 }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            Color.clear.frame(width: Tokens.Size.timeGutterWidth)
            ForEach(days, id: \.self) { day in
                column(for: day)
                    .frame(maxWidth: .infinity)
                    .background(
                        isToday(day) || Calendar.current.isDateInWeekend(day)
                            ? Tokens.Color.Surface.canvasAlt
                            : Tokens.Color.Surface.canvas)
            }
        }
        .frame(height: Tokens.Size.dayHeaderHeight)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Tokens.Color.Separator.region)
                .frame(height: Tokens.Size.hairline)
        }
    }

    @ViewBuilder
    private func column(for day: Date) -> some View {
        VStack(spacing: 0) {
            Text(weekdayFormatter.string(from: day))
                .typeStyle(.dayHeaderWeekday)
                .foregroundStyle(Tokens.Color.Text.secondary)
            if isToday(day) {
                // components.md §10.3 — the today pill.
                Text(dayNumberFormatter.string(from: day))
                    .typeStyle(.dayHeaderDate)
                    .foregroundStyle(Tokens.Color.Text.onSolid)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Tokens.Color.Interactive.accent))
            } else {
                Text(dayNumberFormatter.string(from: day))
                    .typeStyle(.dayHeaderDate)
                    .foregroundStyle(Tokens.Color.Text.primary)
                    .frame(height: 26)
            }
            if !isWeek {
                // Day view carries a secondary summary line.
                Text(summary(for: day))
                    .typeStyle(.blockMeta)
                    .foregroundStyle(Tokens.Color.Text.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func isToday(_ day: Date) -> Bool {
        Calendar.current.isDate(day, inSameDayAs: now)
    }

    /// On an empty day this reads "Nothing scheduled" — no illustration, no
    /// encouragement, no call to action (layouts.md §4).
    private func summary(for day: Date) -> String {
        let calendar = Calendar.current
        let dayEvents = events.filter {
            !$0.isAllDay && calendar.isDate($0.start, inSameDayAs: day)
        }
        guard !dayEvents.isEmpty else { return "Nothing scheduled" }
        let hours = dayEvents.reduce(0) { $0 + $1.duration } / 3600
        let blockWord = dayEvents.count == 1 ? "block" : "blocks"
        let hoursText = hours < 1
            ? String(format: "%.0f min", hours * 60)
            : String(format: "%.1f h", hours)
        return "\(dayEvents.count) \(blockWord) · \(hoursText) scheduled"
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
