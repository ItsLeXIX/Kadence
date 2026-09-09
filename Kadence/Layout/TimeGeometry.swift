//
//  TimeGeometry.swift
//  Kadence
//
//  Time <-> y conversion and drag snapping. Pure, so it is unit-testable.
//

import Foundation
import CoreGraphics

struct TimeGeometry: Sendable, Equatable {
    /// Midnight of the day being drawn.
    var dayStart: Date
    /// Points per hour: `size.hourHeightDay` or `size.hourHeightWeek`.
    var hourHeight: CGFloat

    static let secondsPerHour: TimeInterval = 3600

    func y(for date: Date) -> CGFloat {
        CGFloat(date.timeIntervalSince(dayStart) / Self.secondsPerHour) * hourHeight
    }

    func date(forY y: CGFloat) -> Date {
        dayStart.addingTimeInterval(TimeInterval(y / hourHeight) * Self.secondsPerHour)
    }

    func height(from start: Date, to end: Date) -> CGFloat {
        CGFloat(end.timeIntervalSince(start) / Self.secondsPerHour) * hourHeight
    }

    /// The full 24-hour extent of the grid.
    var totalHeight: CGFloat { hourHeight * 24 }

    /// The y of a date's *time of day*, ignoring which day it falls on.
    ///
    /// The time gutter is a single 24-hour ruler shared by all seven Week
    /// columns, so anything positioned in it — the now label above all — has to
    /// be placed by clock time. Using `y(for:)` there would offset the label by
    /// whole days whenever `now` is not the grid's first day.
    func yForTimeOfDay(_ date: Date, calendar: Calendar = .current) -> CGFloat {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let hours = Double(components.hour ?? 0)
            + Double(components.minute ?? 0) / 60
            + Double(components.second ?? 0) / 3600
        return CGFloat(hours) * hourHeight
    }

    /// interactions.md §4 — 15-minute snapping, 5 minutes while `⌃` is held.
    static func snap(_ date: Date, toMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        guard minutes > 0 else { return date }
        let interval = TimeInterval(minutes * 60)
        let reference = calendar.startOfDay(for: date)
        let offset = date.timeIntervalSince(reference)
        return reference.addingTimeInterval((offset / interval).rounded() * interval)
    }

    /// The minimum on-screen duration, expressed in seconds at this scale.
    /// Used by the layout engine so that clamped blocks still register as
    /// overlapping (layouts.md §3.3 step 1).
    var minimumRenderedDuration: TimeInterval {
        TimeInterval(Tokens.Size.blockMinRenderedHeight / hourHeight) * Self.secondsPerHour
    }
}
