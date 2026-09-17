//
//  RoutineWeekLayoutTests.swift
//  KadenceTests
//
//  layouts.md §8 / components.md §13.1 — the Routines window shell (task
//  P2-T10). `RoutineWeekLayout` is the pure glue between a `RoutineTemplate`'s
//  weekly shape and `DayLayoutEngine`; this file is the regression test the
//  task asks for, covering exactly the acceptance criterion a pure function
//  can verify without a running window: "the seeded template's blocks appear
//  in the correct weekday columns" — i.e. positioned by weekday + startMinutes
//  + duration, and absent from every weekday the template is not active on.
//
//  Clicking a block and seeing the inspector update is a SwiftUI-state-level
//  behaviour (`RoutinesWindow`'s own `selection`/`selectedBlockSnapshot`
//  wiring), which has no pure-function seam to test in isolation — verified
//  instead by manual build/run per STATUS.md's note on this task.
//

import Testing
import Foundation
import CoreGraphics
@testable import Kadence

private let referenceNow = Calendar(identifier: .gregorian).date(
    from: DateComponents(year: 2026, month: 9, day: 17))! // a Thursday

// MARK: - Weekday ordering

@Suite("RoutineWeekLayout.orderedWeekdays")
struct OrderedWeekdaysTests {

    @Test("Starting from Sunday (1) is the identity 1...7")
    func startsAtSunday() {
        #expect(RoutineWeekLayout.orderedWeekdays(firstWeekday: 1) == [1, 2, 3, 4, 5, 6, 7])
    }

    @Test("Starting from Monday (2) rotates Sunday to the end")
    func startsAtMonday() {
        #expect(RoutineWeekLayout.orderedWeekdays(firstWeekday: 2) == [2, 3, 4, 5, 6, 7, 1])
    }

    @Test("Starting from Saturday (7) rotates everything but Saturday")
    func startsAtSaturday() {
        #expect(RoutineWeekLayout.orderedWeekdays(firstWeekday: 7) == [7, 1, 2, 3, 4, 5, 6])
    }

    @Test("Always exactly the seven weekdays, whatever the start")
    func alwaysAllSeven() {
        for first in 1...7 {
            #expect(Set(RoutineWeekLayout.orderedWeekdays(firstWeekday: first)) == Set(1...7))
        }
    }
}

// MARK: - Reference day start

@Suite("RoutineWeekLayout.referenceDayStart")
struct ReferenceDayStartTests {

    @Test("The returned date's own weekday component matches the requested weekday")
    func matchesRequestedWeekday() {
        let calendar = Calendar(identifier: .gregorian)
        for weekday in 1...7 {
            let date = RoutineWeekLayout.referenceDayStart(weekday: weekday, now: referenceNow, calendar: calendar)
            #expect(calendar.component(.weekday, from: date) == weekday)
        }
    }

    @Test("Is midnight, so adding startMinutes never crosses into the previous day")
    func isMidnight() {
        let calendar = Calendar(identifier: .gregorian)
        let date = RoutineWeekLayout.referenceDayStart(weekday: 3, now: referenceNow, calendar: calendar)
        #expect(calendar.isDate(date, equalTo: calendar.startOfDay(for: date), toGranularity: .second))
    }
}

// MARK: - Layout items: positioned by weekday + startMinutes + duration

@Suite("RoutineWeekLayout.layoutItems")
struct LayoutItemsTests {

    private let day = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 9, day: 14))! // a Monday, weekday 2

    private let gym = RoutineBlockSnapshot(
        id: UUID(), title: "Gym", startMinutes: 7 * 60, duration: 3600, flexibility: .shiftable)
    private let reading = RoutineBlockSnapshot(
        id: UUID(), title: "Reading", startMinutes: 21 * 60, duration: 30 * 60, flexibility: .droppable)

    @Test("A weekday in the active set gets one item per block, at the right time")
    func activeWeekdayProducesItems() {
        let items = RoutineWeekLayout.layoutItems(
            blocks: [gym, reading], activeWeekdays: [2, 4, 6], weekday: 2, referenceDayStart: day)

        #expect(items.count == 2)
        let gymItem = try? #require(items.first { $0.title == "Gym" })
        #expect(gymItem?.start == day.addingTimeInterval(7 * 3600))
        #expect(gymItem?.end == day.addingTimeInterval(8 * 3600))

        let readingItem = try? #require(items.first { $0.title == "Reading" })
        #expect(readingItem?.start == day.addingTimeInterval(21 * 3600))
        #expect(readingItem?.end == day.addingTimeInterval(21 * 3600 + 30 * 60))
    }

    @Test("A weekday NOT in the active set gets no items at all")
    func inactiveWeekdayProducesNothing() {
        let items = RoutineWeekLayout.layoutItems(
            blocks: [gym, reading], activeWeekdays: [2, 4, 6], weekday: 3, referenceDayStart: day)
        #expect(items.isEmpty)
    }

    @Test("Every block carries its own id through unchanged, for GridBlockView lookup")
    func idsSurvive() {
        let items = RoutineWeekLayout.layoutItems(
            blocks: [gym], activeWeekdays: [2], weekday: 2, referenceDayStart: day)
        #expect(items.first?.id == gym.id)
    }
}

// MARK: - End to end: the seeded demo template lands in the right columns

@Suite("Seeded demo template — weekday placement")
@MainActor
struct SeededTemplateLayoutTests {

    @Test("MockData.makeRoutineTemplates seeds a template spanning more than one weekday")
    func seedsMultipleWeekdays() {
        let templates = MockData.makeRoutineTemplates()
        #expect(templates.count == 1)
        #expect((templates.first?.activeWeekdays.count ?? 0) >= 2)
        #expect(!(templates.first?.blocks.isEmpty ?? true))
    }

    @Test("Blocks appear only in the template's active weekday columns, never the others")
    func blocksOnlyInActiveWeekdayColumns() throws {
        let template = try #require(MockData.makeRoutineTemplates().first)
        let snapshots = template.blocks.map(\.snapshot)
        let weekdays = RoutineWeekLayout.orderedWeekdays(firstWeekday: 1) // Sun...Sat, exhaustive

        for weekday in weekdays {
            let day = RoutineWeekLayout.referenceDayStart(weekday: weekday, now: referenceNow)
            let items = RoutineWeekLayout.layoutItems(
                blocks: snapshots, activeWeekdays: template.activeWeekdays,
                weekday: weekday, referenceDayStart: day)

            if template.activeWeekdays.contains(weekday) {
                #expect(items.count == snapshots.count, "weekday \(weekday) should carry every block")
            } else {
                #expect(items.isEmpty, "weekday \(weekday) is not active and should carry no blocks")
            }
        }
    }

    @Test("Laying out an active weekday's items through DayLayoutEngine positions each block by its own start/duration")
    func dayLayoutEnginePlacesEachBlockByItsOwnTime() throws {
        let template = try #require(MockData.makeRoutineTemplates().first)
        let snapshots = template.blocks.map(\.snapshot)
        let activeWeekday = try #require(template.activeWeekdays.sorted().first)
        let day = RoutineWeekLayout.referenceDayStart(weekday: activeWeekday, now: referenceNow)
        let geometry = TimeGeometry(dayStart: day, hourHeight: Tokens.Size.hourHeightWeek)

        let items = RoutineWeekLayout.layoutItems(
            blocks: snapshots, activeWeekdays: template.activeWeekdays,
            weekday: activeWeekday, referenceDayStart: day)
        let layout = DayLayoutEngine.layout(items: items, columnWidth: 200, geometry: geometry)

        for block in snapshots {
            let laidOut = try #require(layout.block(for: block.id), "block \(block.title) missing from layout")
            let expectedY = geometry.y(for: day.addingTimeInterval(TimeInterval(block.startMinutes * 60)))
            #expect(abs(laidOut.frame.minY - expectedY) < 0.01)
        }
    }
}
