//
//  WallClock.swift
//  Kadence
//
//  components.md §31.1 (P3S2-F01, G-100): every conversion between a moment
//  and a time of day goes through this one pure pair. A time of day is the
//  local clock time on that day, never the time elapsed since midnight — on
//  Sun 25 Oct 2026 (25 hours in Europe/Vienna) and Sun 29 Mar 2026 (23 hours)
//  the two differ by an hour after the change.
//
//  Pure: the calendar (and so its time zone) is always passed in, so tests
//  run in Europe/Vienna whatever the Mac is set to.
//

import Foundation

nonisolated enum WallClock {

    /// The moment's local time of day on `day`, in minutes:
    /// `hour × 60 + minute + second / 60`. **0** if the moment is before
    /// `day`'s start, **1440** if it is at or after the next day's start.
    static func minuteOfDay(_ moment: Date, on day: Date, calendar: Calendar) -> Double {
        let dayStart = calendar.startOfDay(for: day)
        guard moment >= dayStart else { return 0 }
        guard moment < nextDayStart(after: dayStart, calendar: calendar) else { return 1440 }
        return localMinutes(moment, since: dayStart, timeZone: calendar.timeZone)
    }

    /// The local time `minuteOfDay` on `day` (RFC 5545's reading):
    /// - in the **repeated hour** the **first** occurrence — 02:30 on 25 Oct
    ///   is 02:30 CEST;
    /// - in the **missing hour** the offset before the gap, i.e. moved
    ///   forward by the gap — 02:30 on 29 Mar is 03:30 CEST;
    /// - `≤ 0` is the day's start, `≥ 1440` the next day's start.
    static func moment(minuteOfDay: Double, on day: Date, calendar: Calendar) -> Date {
        let dayStart = calendar.startOfDay(for: day)
        guard minuteOfDay > 0 else { return dayStart }
        guard minuteOfDay < 1440 else { return nextDayStart(after: dayStart, calendar: calendar) }

        let zone = calendar.timeZone
        // The wanted local time, as "seconds since the epoch in local time".
        let target = dayStart.timeIntervalSinceReferenceDate
            + Double(zone.secondsFromGMT(for: dayStart))
            + minuteOfDay * 60
        // Every offset in force within a few hours of it. A moment `x` shows
        // local time `target` when `x + offset(x) == target`.
        let probe = target - Double(zone.secondsFromGMT(for: dayStart))
        let before = Double(zone.secondsFromGMT(for: Date(timeIntervalSinceReferenceDate: probe - 3 * 3600)))
        let after = Double(zone.secondsFromGMT(for: Date(timeIntervalSinceReferenceDate: probe + 3 * 3600)))
        let matches = [before, after]
            .map { Date(timeIntervalSinceReferenceDate: target - $0) }
            .filter { Double(zone.secondsFromGMT(for: $0)) + $0.timeIntervalSinceReferenceDate == target }
        // Repeated hour: both match, the earlier is the first occurrence.
        if let first = matches.min() { return first }
        // Missing hour: read with the offset before the gap.
        return Date(timeIntervalSinceReferenceDate: target - before)
    }

    static func moment(minuteOfDay: Int, on day: Date, calendar: Calendar) -> Date {
        moment(minuteOfDay: Double(minuteOfDay), on: day, calendar: calendar)
    }

    /// The next day's start — 24 hours later except on a change day.
    static func nextDayStart(after dayStart: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: 1, to: dayStart)
            ?? dayStart.addingTimeInterval(86_400)
    }

    /// A point on a drawing ruler `minutes` of **elapsed** time from
    /// `dayStart` — not a time of day. Used where a drawn position is
    /// re-expressed as a date (`DayLayoutEngine`'s drawn intervals) or a
    /// drag runs past either end of the day.
    static func rulerDate(minutes: Double, from dayStart: Date) -> Date {
        dayStart.addingTimeInterval(minutes * 60)
    }

    /// Local clock time of `moment` minus local clock time of `dayStart`, in
    /// minutes. Inside the day that is the time of day; outside it, it runs
    /// on past 0 and 1440 without clipping (used for drawing what spills
    /// over midnight). On a day without a change it equals elapsed time.
    static func localMinutes(_ moment: Date, since dayStart: Date, timeZone: TimeZone) -> Double {
        let local = moment.timeIntervalSince(dayStart)
            + Double(timeZone.secondsFromGMT(for: moment) - timeZone.secondsFromGMT(for: dayStart))
        return local / 60
    }
}
