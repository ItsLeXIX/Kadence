//
//  RoutineEngineTests.swift
//  KadenceTests
//
//  BRIEF-PRODUCT.md's routine data model + RoutineEngine.materialize
//  (components.md §13). Same in-memory ModelContainer/ModelContext pattern as
//  EventCreationTests.swift.
//
//  A note on "priority ... survives onto the materialized Event" (the task's
//  acceptance wording): the field-by-field list of what `materialize` writes
//  onto an `Event` (title, start/end, origin, sourceKey, flexibility,
//  sourceID, externalID) has no `priority`, and `Event` has no such field —
//  adding one would be inventing a field neither Event.swift nor the brief's
//  Event draft has. What is tested here instead is that `priority` survives
//  SwiftData round-tripping on the `RoutineBlock` itself (it is meaningless to
//  "survive" anywhere else, since nothing yet reads it), alongside the
//  `flexibility` check, which does transfer onto the `Event` per spec.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

@MainActor
private func makeStore() throws -> (EventStore, ModelContext, UndoStack) {
    let container = try ModelContainer(
        for: Event.self, Place.self, RoutineTemplate.self, RoutineBlock.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let undo = UndoStack()
    return (EventStore(context: context, undo: undo), context, undo)
}

@MainActor
private func allEvents(_ context: ModelContext) -> [Event] {
    (try? context.fetch(FetchDescriptor<Event>())) ?? []
}

/// September 2026 has no DST transition in US time zones, so a 14-day span
/// measured in raw seconds lines up exactly with 14 calendar days.
private let calendar = Calendar(identifier: .gregorian)
private let rangeStart = calendar.date(from: DateComponents(year: 2026, month: 9, day: 13))!
private let fourteenDayRange = DateInterval(start: rangeStart, duration: 14 * 24 * 3600)

/// Monday / Wednesday / Friday. Which three weekdays does not matter for the
/// count assertions below — any 3-of-7 set appears exactly 2 times each in an
/// exact 14-day (2-week) span, so the total is independent of `rangeStart`'s
/// own weekday.
private let activeWeekdays: Set<Int> = [2, 4, 6]

private func makeGymBlock() -> RoutineBlock {
    RoutineBlock(
        title: "Gym",
        startMinutes: 6 * 60,          // 06:00
        duration: 3600,                // 1h
        flexibility: .fixed,
        priority: 1)
}

private func makeStudyBlock() -> RoutineBlock {
    RoutineBlock(
        title: "Study",
        startMinutes: 20 * 60,         // 20:00
        duration: 90 * 60,             // 1.5h
        flexibility: .shiftable,
        shiftableMinutes: 30,
        priority: 2)
}

private func makeTemplate() -> RoutineTemplate {
    RoutineTemplate(
        name: "Weekday Routine",
        activeWeekdays: activeWeekdays,
        blocks: [makeGymBlock(), makeStudyBlock()],
        sourceKey: .teal)
}

// MARK: - Count and field correctness

@Suite("RoutineEngine.materialize — count and fields")
@MainActor
struct MaterializeFieldTests {

    @Test("2 blocks × 3 active weekdays over a 14-day range produces exactly 12 events")
    func exactCount() throws {
        let (store, context, _) = try makeStore()
        let template = makeTemplate()
        context.insert(template)
        try context.save()

        let created = RoutineEngine.materialize(
            template: template, into: fourteenDayRange, store: store, calendar: calendar)

        // 3 active weekdays × 2 occurrences each in an exact 2-week span × 2 blocks.
        #expect(created == 12)
        #expect(allEvents(context).count == 12)
    }

    @Test("Every materialized event carries the template's sourceKey, origin, and identity")
    func commonFields() throws {
        let (store, context, _) = try makeStore()
        let template = makeTemplate()
        context.insert(template)
        try context.save()

        RoutineEngine.materialize(template: template, into: fourteenDayRange, store: store, calendar: calendar)

        let events = allEvents(context)
        #expect(events.count == 12)
        for event in events {
            #expect(event.origin == .routine)
            #expect(event.sourceKey == .teal)
            #expect(event.sourceID == template.id.uuidString)
            #expect(event.externalID != nil)
        }
    }

    @Test("Each Gym event lands at 06:00 on a Monday, Wednesday or Friday, 1 hour long, fixed")
    func gymFields() throws {
        let (store, context, _) = try makeStore()
        let template = makeTemplate()
        context.insert(template)
        try context.save()

        RoutineEngine.materialize(template: template, into: fourteenDayRange, store: store, calendar: calendar)

        let gymEvents = allEvents(context).filter { $0.title == "Gym" }
        #expect(gymEvents.count == 6)
        for event in gymEvents {
            let components = calendar.dateComponents([.hour, .minute], from: event.start)
            #expect(components.hour == 6)
            #expect(components.minute == 0)
            #expect(activeWeekdays.contains(calendar.component(.weekday, from: event.start)))
            #expect(event.duration == 3600)
            #expect(event.flexibility == .fixed)
        }
    }

    @Test("Each Study event lands at 20:00, 1.5 hours long, shiftable")
    func studyFields() throws {
        let (store, context, _) = try makeStore()
        let template = makeTemplate()
        context.insert(template)
        try context.save()

        RoutineEngine.materialize(template: template, into: fourteenDayRange, store: store, calendar: calendar)

        let studyEvents = allEvents(context).filter { $0.title == "Study" }
        #expect(studyEvents.count == 6)
        for event in studyEvents {
            let components = calendar.dateComponents([.hour, .minute], from: event.start)
            #expect(components.hour == 20)
            #expect(components.minute == 0)
            #expect(event.duration == 90 * 60)
            #expect(event.flexibility == .shiftable)
        }
    }

    @Test("externalID is '<block id>#<yyyy-MM-dd>' of the event's own start date")
    func externalIDShape() throws {
        let (store, context, _) = try makeStore()
        let template = makeTemplate()
        context.insert(template)
        try context.save()
        let gymBlockID = template.blocks.first { $0.title == "Gym" }!.id.uuidString

        RoutineEngine.materialize(template: template, into: fourteenDayRange, store: store, calendar: calendar)

        let gymEvents = allEvents(context).filter { $0.title == "Gym" }
        for event in gymEvents {
            let parts = event.externalID!.split(separator: "#")
            #expect(parts.count == 2)
            #expect(String(parts[0]) == gymBlockID)

            let components = calendar.dateComponents([.year, .month, .day], from: event.start)
            let expectedKey = String(format: "%04d-%02d-%02d", components.year!, components.month!, components.day!)
            #expect(String(parts[1]) == expectedKey)
        }
    }

    @Test("An empty active-weekday set materializes nothing")
    func noActiveWeekdays() throws {
        let (store, context, _) = try makeStore()
        let template = RoutineTemplate(
            name: "Nothing Active", activeWeekdays: [], blocks: [makeGymBlock()], sourceKey: .teal)
        context.insert(template)
        try context.save()

        let created = RoutineEngine.materialize(
            template: template, into: fourteenDayRange, store: store, calendar: calendar)
        #expect(created == 0)
        #expect(allEvents(context).isEmpty)
    }
}

// MARK: - Idempotence

@Suite("RoutineEngine.materialize — idempotence")
@MainActor
struct MaterializeIdempotenceTests {

    @Test("Materializing the same template and range twice does not duplicate events")
    func noDuplicatesOnReRun() throws {
        let (store, context, _) = try makeStore()
        let template = makeTemplate()
        context.insert(template)
        try context.save()

        let firstRun = RoutineEngine.materialize(
            template: template, into: fourteenDayRange, store: store, calendar: calendar)
        #expect(firstRun == 12)

        let pairsAfterFirstRun = Set(allEvents(context).map { "\($0.sourceID ?? "")#\($0.externalID ?? "")" })
        #expect(pairsAfterFirstRun.count == 12)

        let secondRun = RoutineEngine.materialize(
            template: template, into: fourteenDayRange, store: store, calendar: calendar)
        #expect(secondRun == 0, "re-running must create nothing new")
        #expect(allEvents(context).count == 12, "count must be unchanged")

        let pairsAfterSecondRun = Set(allEvents(context).map { "\($0.sourceID ?? "")#\($0.externalID ?? "")" })
        #expect(pairsAfterSecondRun == pairsAfterFirstRun, "the same (sourceID, externalID) pairs, not a new set")
    }

    @Test("Materializing a template registers exactly one undo step for the whole run")
    func oneUndoStep() throws {
        let (store, context, undo) = try makeStore()
        let template = makeTemplate()
        context.insert(template)
        try context.save()

        RoutineEngine.materialize(template: template, into: fourteenDayRange, store: store, calendar: calendar)
        #expect(undo.undoSteps.count == 1)
        #expect(undo.undoMenuTitle == "Undo Materialize Weekday Routine")

        undo.undo()
        #expect(allEvents(context).isEmpty, "one ⌘Z removes every event the run created")

        undo.redo()
        #expect(allEvents(context).count == 12)
    }

    @Test("A materialized range can be extended without disturbing the events already there")
    func extendingRangeOnlyAddsNewOnes() throws {
        let (store, context, _) = try makeStore()
        let template = makeTemplate()
        context.insert(template)
        try context.save()

        RoutineEngine.materialize(template: template, into: fourteenDayRange, store: store, calendar: calendar)
        let originalIDs = Set(allEvents(context).map(\.id))

        // Same start, double the length: the first 14 days must be untouched.
        let extendedRange = DateInterval(start: rangeStart, duration: 28 * 24 * 3600)
        let created = RoutineEngine.materialize(
            template: template, into: extendedRange, store: store, calendar: calendar)

        #expect(created == 12, "the second 14 days' worth of new occurrences")
        let allIDs = Set(allEvents(context).map(\.id))
        #expect(originalIDs.isSubset(of: allIDs), "none of the first run's events were replaced")
        #expect(allEvents(context).count == 24)
    }
}

// MARK: - Priority and flexibility

@Suite("RoutineEngine.materialize — priority and flexibility propagation")
@MainActor
struct MaterializePriorityFlexibilityTests {

    @Test("A block's priority survives on the RoutineBlock itself, unaffected by materialization")
    func priorityPersists() throws {
        let (store, context, _) = try makeStore()
        let template = makeTemplate()
        context.insert(template)
        try context.save()

        RoutineEngine.materialize(template: template, into: fourteenDayRange, store: store, calendar: calendar)

        let refetched = try context.fetch(FetchDescriptor<RoutineTemplate>()).first!
        #expect(refetched.blocks.first { $0.title == "Gym" }?.priority == 1)
        #expect(refetched.blocks.first { $0.title == "Study" }?.priority == 2)
    }

    @Test("A block's flexibility transfers onto every event it materializes")
    func flexibilityTransfers() throws {
        let (store, context, _) = try makeStore()
        let template = makeTemplate()
        context.insert(template)
        try context.save()

        RoutineEngine.materialize(template: template, into: fourteenDayRange, store: store, calendar: calendar)

        let events = allEvents(context)
        #expect(events.filter { $0.title == "Gym" }.allSatisfy { $0.flexibility == .fixed })
        #expect(events.filter { $0.title == "Study" }.allSatisfy { $0.flexibility == .shiftable })
    }

    @Test("shiftableMinutes is preserved on the block and does not leak onto Event")
    func shiftableMinutesStaysOnTheBlock() throws {
        let (store, context, _) = try makeStore()
        let template = makeTemplate()
        context.insert(template)
        try context.save()

        RoutineEngine.materialize(template: template, into: fourteenDayRange, store: store, calendar: calendar)

        let refetched = try context.fetch(FetchDescriptor<RoutineTemplate>()).first!
        #expect(refetched.blocks.first { $0.title == "Study" }?.shiftableMinutes == 30)
        #expect(refetched.blocks.first { $0.title == "Gym" }?.shiftableMinutes == nil)
    }
}
