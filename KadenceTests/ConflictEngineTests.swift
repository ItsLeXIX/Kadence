//
//  ConflictEngineTests.swift
//  KadenceTests
//
//  BRIEF-PRODUCT.md's conflict detection ("any overlap between a routine
//  block and an imported/manual event ... generate 2-3 concrete resolution
//  options ranked by how little they disturb the day ... with one marked
//  recommended") and components.md §14.3 (title / disturbance / exactly-one-
//  recommended). Same in-memory ModelContainer/ModelContext pattern as
//  RoutineEngineTests.swift.
//
//  `ConflictWindowDetectionTests` (bottom of this file, task P2-T19) covers
//  the brief's other named clause — "any automatic placement that would
//  land in a protected window" — via `ConflictEngine.detectWindowConflicts`.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: Schema(KadenceSchema.models),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return ModelContext(container)
}

private let calendar = Calendar(identifier: .gregorian)
private let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!

/// `hour:minute` of `day`, this suite's whole vocabulary for building fixture
/// times — every scenario below reads as a clock time, not an offset.
private func time(_ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(byAdding: .minute, value: hour * 60 + minute, to: day)!
}

/// A `RoutineBlock` whose only role in these tests is to be looked up by
/// `sourceID`/`externalID` scheme; `startMinutes`/`duration` are unused by
/// `ConflictEngine` and left at 0.
private func makeBlock(flexibility: Flexibility, shiftableMinutes: Int? = nil) -> RoutineBlock {
    RoutineBlock(title: "Block", startMinutes: 0, duration: 0, flexibility: flexibility, shiftableMinutes: shiftableMinutes)
}

/// A materialized routine `Event`, wired to `block` the same way
/// `RoutineEngine.materialize` wires one: `externalID ==
/// "<block.id>#<yyyy-MM-dd>"`.
private func makeRoutineEvent(block: RoutineBlock, title: String = "Routine", start: Date, end: Date) -> Event {
    Event(
        title: title, start: start, end: end, origin: .routine, flexibility: block.flexibility,
        sourceID: "template", externalID: "\(block.id.uuidString)#2026-09-18")
}

private func makeManualEvent(title: String = "Manual", start: Date, end: Date) -> Event {
    Event(title: title, start: start, end: end, origin: .manual)
}

private func makeImportedEvent(title: String = "Imported", start: Date, end: Date) -> Event {
    Event(title: title, start: start, end: end, origin: .imported)
}

@MainActor
private func insert(_ context: ModelContext, _ items: [AnyObject]) throws {
    for item in items {
        if let event = item as? Event { context.insert(event) }
        if let block = item as? RoutineBlock { context.insert(block) }
    }
    try context.save()
}

// MARK: - Detection

@Suite("ConflictEngine.detect — which pairs count")
@MainActor
struct ConflictDetectionTests {

    @Test("A routine event overlapping a manual event is detected")
    func routineOverlapsManual() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .fixed)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(10))
        let manual = makeManualEvent(start: time(9, 30), end: time(10, 30))
        try insert(context, [block, routine, manual])

        let conflicts = ConflictEngine.detect(events: [routine, manual], routineBlocks: [block])
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.routineEvent.id == routine.id)
        #expect(conflicts.first?.otherEvent.id == manual.id)
    }

    @Test("A routine event overlapping an imported event is detected")
    func routineOverlapsImported() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .fixed)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(10))
        let imported = makeImportedEvent(start: time(9, 30), end: time(10, 30))
        try insert(context, [block, routine, imported])

        let conflicts = ConflictEngine.detect(events: [routine, imported], routineBlocks: [block])
        #expect(conflicts.count == 1)
        #expect(conflicts.first?.routineEvent.id == routine.id)
        #expect(conflicts.first?.otherEvent.id == imported.id)
    }

    @Test("Two manual events overlapping each other is NOT detected")
    func manualOverlapsManualIsIgnored() throws {
        let context = try makeContext()
        let a = makeManualEvent(title: "A", start: time(9), end: time(10))
        let b = makeManualEvent(title: "B", start: time(9, 30), end: time(10, 30))
        try insert(context, [a, b])

        let conflicts = ConflictEngine.detect(events: [a, b], routineBlocks: [])
        #expect(conflicts.isEmpty)
    }

    @Test("Two routine events overlapping each other is NOT detected")
    func routineOverlapsRoutineIsIgnored() throws {
        let context = try makeContext()
        let blockA = makeBlock(flexibility: .fixed)
        let blockB = makeBlock(flexibility: .fixed)
        let a = makeRoutineEvent(block: blockA, title: "A", start: time(9), end: time(10))
        let b = makeRoutineEvent(block: blockB, title: "B", start: time(9, 30), end: time(10, 30))
        try insert(context, [blockA, blockB, a, b])

        let conflicts = ConflictEngine.detect(events: [a, b], routineBlocks: [blockA, blockB])
        #expect(conflicts.isEmpty)
    }

    @Test("A routine event overlapping a planned event is NOT detected (out of scope)")
    func routineOverlapsPlannedIsIgnored() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .fixed)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(10))
        let planned = Event(title: "Planned", start: time(9, 30), end: time(10, 30), origin: .planned)
        try insert(context, [block, routine, planned])

        let conflicts = ConflictEngine.detect(events: [routine, planned], routineBlocks: [block])
        #expect(conflicts.isEmpty)
    }

    @Test("A non-overlapping pair produces no conflict")
    func nonOverlappingPairProducesNoConflict() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .fixed)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(10))
        let manual = makeManualEvent(start: time(11), end: time(12))
        try insert(context, [block, routine, manual])

        let conflicts = ConflictEngine.detect(events: [routine, manual], routineBlocks: [block])
        #expect(conflicts.isEmpty)
    }

    @Test("Touching endpoints (one ends exactly when the other starts) do not count as an overlap")
    func touchingEndpointsDoNotOverlap() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .fixed)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(10))
        let manual = makeManualEvent(start: time(10), end: time(11))
        try insert(context, [block, routine, manual])

        let conflicts = ConflictEngine.detect(events: [routine, manual], routineBlocks: [block])
        #expect(conflicts.isEmpty)
    }
}

// MARK: - Option generation

@Suite("ConflictEngine.detect — resolution options")
@MainActor
struct ConflictOptionTests {

    @Test(".shiftable produces a shift-later option within the block's shiftableMinutes range")
    func shiftableWithinRangeProducesShiftOption() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .shiftable, shiftableMinutes: 180)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(10))       // 60 min
        let manual = makeManualEvent(start: time(9, 20), end: time(10, 10))               // overlap
        try insert(context, [block, routine, manual])

        let conflicts = ConflictEngine.detect(events: [routine, manual], routineBlocks: [block])
        let conflict = try #require(conflicts.first)

        // Needed to clear: other.end (10:10) - routine.start (9:00) = 70 min,
        // rounded up to the next 15-minute increment = 75 min.
        let shift = try #require(conflict.options.first { $0.kind == .shiftLater })
        #expect(shift.disturbanceMinutes == 75)
        #expect(shift.newStart == time(10, 15))
        #expect(shift.newEnd == time(11, 15))
        #expect(shift.skipsOccurrence == false)
    }

    @Test(".shiftable omits the shift option when the needed shift exceeds shiftableMinutes")
    func shiftableExceedingRangeOmitsShiftOption() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .shiftable, shiftableMinutes: 30)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(10))
        let manual = makeManualEvent(start: time(9, 20), end: time(10, 10)) // needs 75 min, > 30
        try insert(context, [block, routine, manual])

        let conflicts = ConflictEngine.detect(events: [routine, manual], routineBlocks: [block])
        let conflict = try #require(conflicts.first)

        #expect(conflict.options.contains { $0.kind == .shiftLater } == false)
        #expect(conflict.options.contains { $0.kind == .skipToday })
        // The option list never goes to zero even though the derived option
        // is unavailable (item 3's own firm guarantee).
        #expect(conflict.options.isEmpty == false)
    }

    @Test(".droppable produces a skip-today option that marks the occurrence, not the template")
    func droppableProducesSkipOption() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .droppable)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(10))
        let manual = makeManualEvent(start: time(9, 30), end: time(10, 30))
        try insert(context, [block, routine, manual])

        let conflicts = ConflictEngine.detect(events: [routine, manual], routineBlocks: [block])
        let conflict = try #require(conflicts.first)

        let skip = try #require(conflict.options.first { $0.kind == .skipToday })
        #expect(skip.skipsOccurrence == true)
        #expect(skip.newStart == nil)
        #expect(skip.newEnd == nil)
        #expect(skip.isRecommended == true)
    }

    @Test(".fixed produces a shorten-to-fit option when it clears the 15-minute floor")
    func fixedShortenFitsAboveFloor() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .fixed)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(11)) // 120 min
        // Overlaps the tail end only: keeping the front (9:00–10:45 = 105 min)
        // beats keeping the back (11:00–11:30 clamped to 0), so the option
        // truncates the end.
        let manual = makeManualEvent(start: time(10, 45), end: time(11, 30))
        try insert(context, [block, routine, manual])

        let conflicts = ConflictEngine.detect(events: [routine, manual], routineBlocks: [block])
        let conflict = try #require(conflicts.first)

        let shorten = try #require(conflict.options.first { $0.kind == .shorten })
        #expect(shorten.newStart == time(9))
        #expect(shorten.newEnd == time(10, 45))
        #expect(shorten.disturbanceMinutes == 15) // 120 - 105
    }

    @Test(".fixed omits the shorten option when shortening would go below the 15-minute floor")
    func fixedShortenBelowFloorIsOmitted() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .fixed)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(10)) // 60 min
        // Fully inside, with only 5 min free at the front and 10 min free at
        // the back — both below the 15-minute floor either way.
        let manual = makeManualEvent(start: time(9, 5), end: time(9, 50))
        try insert(context, [block, routine, manual])

        let conflicts = ConflictEngine.detect(events: [routine, manual], routineBlocks: [block])
        let conflict = try #require(conflicts.first)

        #expect(conflict.options.contains { $0.kind == .shorten } == false)
        #expect(conflict.options.contains { $0.kind == .skipToday })
        #expect(conflict.options.isEmpty == false)
    }
}

// MARK: - Ranking invariants

@Suite("ConflictEngine.detect — ranking invariants")
@MainActor
struct ConflictRankingTests {

    @Test("Every conflict has at least one isRecommended option, and never more than one")
    func exactlyOneRecommendedPerConflict() throws {
        let context = try makeContext()

        let shiftableBlock = makeBlock(flexibility: .shiftable, shiftableMinutes: 180)
        let shiftableRoutine = makeRoutineEvent(block: shiftableBlock, title: "Shiftable", start: time(9), end: time(10))
        let shiftableOther = makeManualEvent(title: "M1", start: time(9, 20), end: time(10, 10))

        let droppableBlock = makeBlock(flexibility: .droppable)
        let droppableRoutine = makeRoutineEvent(block: droppableBlock, title: "Droppable", start: time(13), end: time(14))
        let droppableOther = makeManualEvent(title: "M2", start: time(13, 30), end: time(14, 30))

        let fixedBlock = makeBlock(flexibility: .fixed)
        let fixedRoutine = makeRoutineEvent(block: fixedBlock, title: "Fixed", start: time(17), end: time(19))
        let fixedOther = makeManualEvent(title: "M3", start: time(18, 45), end: time(19, 30))

        let events = [shiftableRoutine, shiftableOther, droppableRoutine, droppableOther, fixedRoutine, fixedOther]
        let blocks = [shiftableBlock, droppableBlock, fixedBlock]
        try insert(context, blocks.map { $0 as AnyObject } + events.map { $0 as AnyObject })

        let conflicts = ConflictEngine.detect(events: events, routineBlocks: blocks)
        #expect(conflicts.count == 3)
        for conflict in conflicts {
            let recommendedCount = conflict.options.filter(\.isRecommended).count
            #expect(recommendedCount == 1, "\(conflict.routineEvent.title) had \(recommendedCount) recommended options")
        }
    }

    @Test("Options are ordered by ascending disturbance, and the first is the recommended one")
    func optionsSortedAscendingByDisturbance() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .shiftable, shiftableMinutes: 180)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(10))
        let manual = makeManualEvent(start: time(9, 20), end: time(10, 10))
        try insert(context, [block, routine, manual])

        let conflicts = ConflictEngine.detect(events: [routine, manual], routineBlocks: [block])
        let conflict = try #require(conflicts.first)

        #expect(conflict.options.count >= 2)
        let disturbances = conflict.options.map(\.disturbanceMinutes)
        #expect(disturbances == disturbances.sorted())
        #expect(conflict.options.first?.isRecommended == true)
        #expect(conflict.options.dropFirst().allSatisfy { $0.isRecommended == false })
    }
}

// MARK: - Window conflicts (task P2-T19)

/// Same two `TimeWindow`s `MockData.makeTimeWindows()` seeds — a protected
/// Sleep window wrapping midnight (22:00–07:00, every day) and a lowEnergy
/// window (13:00–14:30, Mon–Fri) — built directly here rather than via
/// `MockData` so this suite has no dependency on the seed helper's own
/// behavior, only on the `TimeWindow` shape itself.
private func makeSleepWindow() -> TimeWindow {
    TimeWindow(weekdays: Set(1...7), startMinutes: 22 * 60, endMinutes: 7 * 60, kind: .protected, label: "Sleep")
}

private func makeLowEnergyWindow() -> TimeWindow {
    TimeWindow(weekdays: [2, 3, 4, 5, 6], startMinutes: 13 * 60, endMinutes: 14 * 60 + 30, kind: .lowEnergy, label: "Low energy")
}

@Suite("TimeWindow.spans — wrap-around semantics")
struct TimeWindowSpansTests {

    /// Mirrors `DensityAndGeometryTests.swift`'s existing
    /// `TimeWindowFixture`-wrap test exactly, now for the persisted model.
    @Test("A protected window that wraps midnight yields two spans on a day")
    func wrapsMidnight() {
        let window = makeSleepWindow()
        let spans = window.spans(on: day, calendar: calendar)
        #expect(spans.count == 2)
        let minutes = spans.map { Int($0.start.timeIntervalSince(calendar.startOfDay(for: day)) / 60) }
        #expect(minutes.sorted() == [0, 22 * 60])
    }

    @Test("A same-day window yields exactly one span")
    func sameDay() {
        let window = makeLowEnergyWindow()
        // `day` (2026-09-18) is a Friday, weekday 6 — inside [2,3,4,5,6].
        #expect(window.spans(on: day, calendar: calendar).count == 1)
    }

    @Test("A window not active on that weekday yields nothing")
    func inactiveWeekday() {
        let window = TimeWindow(weekdays: [1], startMinutes: 9 * 60, endMinutes: 10 * 60, kind: .protected, label: "Sunday only")
        #expect(window.spans(on: day, calendar: calendar).isEmpty)
    }
}

@Suite("ConflictEngine.detectWindowConflicts — protected-window placements")
@MainActor
struct ConflictWindowDetectionTests {

    @Test("A routine event overlapping the protected Sleep window produces a conflict with ranked options")
    func routineOverlappingProtectedWindowProducesConflict() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .shiftable, shiftableMinutes: 180)
        // 22:00 Sleep window starts today's evening span; a routine block
        // 22:30–23:30 lands fully inside it.
        let routine = makeRoutineEvent(block: block, start: time(22, 30), end: time(23, 30))
        try insert(context, [block, routine])

        let windows = [makeSleepWindow(), makeLowEnergyWindow()]
        let conflicts = ConflictEngine.detectWindowConflicts(
            events: [routine], routineBlocks: [block], timeWindows: windows, calendar: calendar)

        #expect(conflicts.count == 1)
        let conflict = try #require(conflicts.first)
        #expect(conflict.routineEvent.id == routine.id)
        #expect(conflict.window.kind == .protected)
        #expect(conflict.overlapStart == time(22, 30))
        #expect(conflict.overlapEnd == time(23, 30))

        // Same ranking invariants as event-vs-event conflicts.
        #expect(conflict.options.isEmpty == false)
        let recommendedCount = conflict.options.filter(\.isRecommended).count
        #expect(recommendedCount == 1)
        let disturbances = conflict.options.map(\.disturbanceMinutes)
        #expect(disturbances == disturbances.sorted())
        #expect(conflict.options.first?.isRecommended == true)
        #expect(conflict.options.contains { $0.kind == .skipToday })
    }

    @Test("A routine event overlapping only the lowEnergy window produces NO conflict")
    func routineOverlappingLowEnergyWindowProducesNoConflict() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .fixed)
        // 13:00–14:00 Friday: inside the lowEnergy window, nowhere near the
        // 22:00–07:00 protected window.
        let routine = makeRoutineEvent(block: block, start: time(13), end: time(14))
        try insert(context, [block, routine])

        let windows = [makeSleepWindow(), makeLowEnergyWindow()]
        let conflicts = ConflictEngine.detectWindowConflicts(
            events: [routine], routineBlocks: [block], timeWindows: windows, calendar: calendar)

        #expect(conflicts.isEmpty)
    }

    @Test("A .skipped routine event overlapping the protected window produces no conflict")
    func skippedRoutineEventOverlappingProtectedWindowProducesNoConflict() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .shiftable, shiftableMinutes: 180)
        let routine = Event(
            title: "Routine", start: time(22, 30), end: time(23, 30), origin: .routine,
            status: .skipped, flexibility: block.flexibility, sourceID: "template",
            externalID: "\(block.id.uuidString)#2026-09-18")
        try insert(context, [block, routine])

        let windows = [makeSleepWindow()]
        let conflicts = ConflictEngine.detectWindowConflicts(
            events: [routine], routineBlocks: [block], timeWindows: windows, calendar: calendar)

        #expect(conflicts.isEmpty)
    }

    @Test("A manual (non-routine) event overlapping the protected window produces no conflict")
    func manualEventOverlappingProtectedWindowProducesNoConflict() throws {
        let context = try makeContext()
        let manual = makeManualEvent(start: time(22, 30), end: time(23, 30))
        try insert(context, [manual])

        let windows = [makeSleepWindow()]
        let conflicts = ConflictEngine.detectWindowConflicts(
            events: [manual], routineBlocks: [], timeWindows: windows, calendar: calendar)

        #expect(conflicts.isEmpty)
    }
}
