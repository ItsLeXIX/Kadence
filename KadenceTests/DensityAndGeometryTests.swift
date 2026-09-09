//
//  DensityAndGeometryTests.swift
//  KadenceTests
//

import Testing
import Foundation
import CoreGraphics
@testable import Kadence

@Suite("Density ladder")
struct DensityTierTests {

    @Test("Tier boundaries match components.md §3.3 exactly", arguments: [
        (10.0, DensityTier.glyphOnly),
        (11.0, DensityTier.glyphOnly),
        (15.0, DensityTier.glyphOnly),
        (16.0, DensityTier.titleOnly),
        (27.0, DensityTier.titleOnly),
        (28.0, DensityTier.compact),
        (43.0, DensityTier.compact),
        (44.0, DensityTier.full),
        (200.0, DensityTier.full),
    ])
    func boundaries(height: Double, expected: DensityTier) {
        #expect(DensityTier(renderedHeight: CGFloat(height)) == expected)
    }

    @Test("A 30-minute block shows more in Day than in Week")
    func sameEventDiffersByView() {
        let week = DensityTier(renderedHeight: 0.5 * Tokens.Size.hourHeightWeek)  // 22pt
        let day = DensityTier(renderedHeight: 0.5 * Tokens.Size.hourHeightDay)    // 30pt
        #expect(week == .titleOnly)
        #expect(day == .compact)
        #expect(day > week)
    }

    @Test("Only tiers at or above compact use an ellipsis")
    func ellipsis() {
        #expect(DensityTier.titleOnly.usesEllipsis == false)
        #expect(DensityTier.compact.usesEllipsis == true)
        #expect(DensityTier.full.usesEllipsis == true)
    }

    @Test("Dropping a tier never goes below glyphOnly")
    func dropFloor() {
        #expect(DensityTier.full.droppingOneTier() == .compact)
        #expect(DensityTier.glyphOnly.droppingOneTier() == .glyphOnly)
    }
}

@Suite("Time geometry")
struct TimeGeometryTests {

    private let day = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 9, day: 9))!

    @Test("y and date round-trip")
    func roundTrip() {
        let geometry = TimeGeometry(dayStart: day, hourHeight: 60)
        let time = day.addingTimeInterval(9.5 * 3600)
        #expect(geometry.y(for: time) == 570)
        #expect(abs(geometry.date(forY: 570).timeIntervalSince(time)) < 0.001)
    }

    @Test("Time-of-day placement ignores which day the date falls on")
    func timeOfDay() {
        // The gutter is one 24-hour ruler shared by all seven Week columns, so
        // a `now` two days into the range must still land at its clock time.
        let geometry = TimeGeometry(dayStart: day, hourHeight: 44)
        let twoDaysLater = day.addingTimeInterval(2 * 86400 + 12 * 3600)
        let clockTimeY: CGFloat = 12 * 44
        let absoluteY: CGFloat = (2 * 24 + 12) * 44
        #expect(geometry.yForTimeOfDay(twoDaysLater) == clockTimeY)
        #expect(geometry.y(for: twoDaysLater) == absoluteY)
    }

    @Test("A full day is 24 rows tall")
    func totalHeight() {
        #expect(TimeGeometry(dayStart: day, hourHeight: 44).totalHeight == 1056)
        #expect(TimeGeometry(dayStart: day, hourHeight: 60).totalHeight == 1440)
    }

    @Test("Snapping rounds to the nearest step, not down")
    func snapping() {
        let calendar = Calendar.current
        func snap(_ minutes: Int, to step: Int) -> Int {
            let date = day.addingTimeInterval(TimeInterval(minutes * 60))
            let snapped = TimeGeometry.snap(date, toMinutes: step, calendar: calendar)
            return Int(snapped.timeIntervalSince(day) / 60)
        }
        #expect(snap(7, to: 15) == 0)
        #expect(snap(8, to: 15) == 15)
        #expect(snap(22, to: 15) == 15)
        #expect(snap(23, to: 15) == 30)
        // ⌃ held: 5-minute snapping.
        #expect(snap(23, to: 5) == 25)
        #expect(snap(22, to: 5) == 20)
    }

    @Test("A zero or negative step leaves the date untouched rather than dividing by zero")
    func degenerateSnap() {
        let date = day.addingTimeInterval(1234)
        #expect(TimeGeometry.snap(date, toMinutes: 0) == date)
    }

    @Test("The clamp duration reflects the row height")
    func minimumRenderedDuration() {
        let week = TimeGeometry(dayStart: day, hourHeight: Tokens.Size.hourHeightWeek)
        let dayScale = TimeGeometry(dayStart: day, hourHeight: Tokens.Size.hourHeightDay)
        // 11pt is a longer slice of time on the tighter Week grid.
        #expect(week.minimumRenderedDuration > dayScale.minimumRenderedDuration)
        #expect(abs(week.minimumRenderedDuration - (11.0 / 44.0) * 3600) < 0.001)
    }
}

@Suite("Time windows")
struct TimeWindowTests {

    private let calendar = Calendar(identifier: .gregorian)
    private let wednesday = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 9, day: 9))!

    @Test("A window that wraps midnight yields two spans on a day")
    func wrapsMidnight() {
        let window = TimeWindowFixture(
            weekdays: Set(1...7), startMinutes: 22 * 60, endMinutes: 7 * 60,
            kind: .protected, label: "Sleep")
        let spans = window.spans(on: wednesday, calendar: calendar)
        #expect(spans.count == 2)
        // 00:00–07:00 (carried from yesterday) and 22:00–24:00.
        let minutes = spans.map { Int($0.start.timeIntervalSince(calendar.startOfDay(for: wednesday)) / 60) }
        #expect(minutes.sorted() == [0, 22 * 60])
    }

    @Test("A same-day window yields exactly one span")
    func sameDay() {
        let window = TimeWindowFixture(
            weekdays: [4], startMinutes: 13 * 60, endMinutes: 14 * 60 + 30,
            kind: .lowEnergy, label: "Low energy")
        #expect(window.spans(on: wednesday, calendar: calendar).count == 1)
    }

    @Test("A window not active on that weekday yields nothing")
    func inactiveWeekday() {
        let window = TimeWindowFixture(
            weekdays: [1], startMinutes: 9 * 60, endMinutes: 10 * 60,
            kind: .protected, label: "Sunday only")
        #expect(window.spans(on: wednesday, calendar: calendar).isEmpty)
    }
}
