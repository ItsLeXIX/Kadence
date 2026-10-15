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
    /// The calendar whose time zone gives the wall clock (components.md
    /// §31.1). Injected in tests; the app draws in `.current`.
    var calendar: Calendar = .current

    static let secondsPerHour: TimeInterval = 3600

    init(dayStart: Date, hourHeight: CGFloat, calendar: Calendar = .current) {
        self.dayStart = dayStart
        self.hourHeight = hourHeight
        self.calendar = calendar
    }

    /// components.md §31.1: a moment is drawn at its **wall-clock** time of
    /// day — never at the time elapsed since midnight, which is an hour off
    /// after a clock change. Outside the day it runs on past 0 and 24 h, so
    /// what spills over midnight is still drawn where it was.
    func y(for date: Date) -> CGFloat {
        CGFloat(minute(of: date) / 60) * hourHeight
    }

    /// The moment at `y` on this day (`WallClock.moment`): a time in the
    /// missing hour moves forward by the gap, one in the repeated hour is its
    /// first occurrence. Above 0 or below 24 h it runs on by elapsed time.
    func date(forY y: CGFloat) -> Date {
        let minutes = Double(y / hourHeight) * 60
        if minutes < 0 { return WallClock.rulerDate(minutes: minutes, from: dayStart) }
        if minutes >= 1440 {
            return WallClock.rulerDate(minutes: minutes - 1440,
                                       from: WallClock.nextDayStart(after: dayStart, calendar: calendar))
        }
        return WallClock.moment(minuteOfDay: minutes, on: dayStart, calendar: calendar)
    }

    /// The drawn height of `[start, end)` (components.md §31.2): wall-clock
    /// bottom minus wall-clock top, except an interval that runs back through
    /// the repeated hour (02:45 CEST → 02:15 CET), which is drawn its elapsed
    /// length down from its top.
    func height(from start: Date, to end: Date) -> CGFloat {
        let bounds = drawnMinutes(from: start, to: end)
        return CGFloat((bounds.bottom - bounds.top) / 60) * hourHeight
    }

    /// §31.2 steps 1–2, in minutes of this day's ruler.
    func drawnMinutes(from start: Date, to end: Date) -> (top: Double, bottom: Double) {
        let top = minute(of: start)
        var bottom = minute(of: end)
        if bottom <= top, end > start {
            bottom = top + end.timeIntervalSince(start) / 60
        }
        return (top, bottom)
    }

    /// The moment's place on this day's ruler, in minutes (unclipped).
    func minute(of date: Date) -> Double {
        WallClock.localMinutes(date, since: dayStart, timeZone: calendar.timeZone)
    }

    /// The same ruler with no clock change in it: `y(for:)` is elapsed time
    /// from `dayStart`. `DayLayoutEngine` lays out **drawn** intervals
    /// (§31.2) re-expressed on this ruler.
    var elapsedRuler: TimeGeometry {
        var ruler = self
        ruler.calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? ruler.calendar.timeZone
        return ruler
    }

    /// The full 24-hour extent of the grid.
    var totalHeight: CGFloat { hourHeight * 24 }

    /// The y of a date's *time of day*, ignoring which day it falls on.
    ///
    /// The time gutter is a single 24-hour ruler shared by all seven Week
    /// columns, so anything positioned in it — the now label above all — has to
    /// be placed by clock time. Using `y(for:)` there would offset the label by
    /// whole days whenever `now` is not the grid's first day.
    ///
    /// components.md §31.3: the column's now line (`y(for:)` on its own day)
    /// and this label read the same wall clock, so they are always level.
    func yForTimeOfDay(_ date: Date) -> CGFloat {
        yForTimeOfDay(date, calendar: calendar)
    }

    func yForTimeOfDay(_ date: Date, calendar: Calendar) -> CGFloat {
        CGFloat(WallClock.minuteOfDay(date, on: date, calendar: calendar) / 60) * hourHeight
    }

    /// interactions.md §4 — 15-minute snapping, 5 minutes while `⌃` is held.
    /// Snaps the **wall-clock** time of day (components.md §31.4); on a day
    /// without a change that is the same as snapping elapsed time.
    static func snap(_ date: Date, toMinutes minutes: Int, calendar: Calendar = .current) -> Date {
        guard minutes > 0 else { return date }
        let day = calendar.startOfDay(for: date)
        let minuteOfDay = WallClock.minuteOfDay(date, on: day, calendar: calendar)
        let interval = Double(minutes)
        return WallClock.moment(minuteOfDay: (minuteOfDay / interval).rounded() * interval,
                                on: day, calendar: calendar)
    }

    /// interactions.md §4 drag, components.md §31.4: the edge at `edge`,
    /// moved `dy` points on this column's ruler and snapped there. The
    /// dropped edge is the wall-clock time at the snapped y.
    func dragged(_ edge: Date, by dy: CGFloat, snapMinutes: Int) -> Date {
        Self.snap(date(forY: y(for: edge) + dy), toMinutes: snapMinutes, calendar: calendar)
    }

    /// The minimum on-screen duration, expressed in seconds at this scale.
    /// Used by the layout engine so that clamped blocks still register as
    /// overlapping (layouts.md §3.3 step 1).
    var minimumRenderedDuration: TimeInterval {
        TimeInterval(Tokens.Size.blockMinRenderedHeight / hourHeight) * Self.secondsPerHour
    }
}
