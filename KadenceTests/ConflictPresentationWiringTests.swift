//
//  ConflictPresentationWiringTests.swift
//  KadenceTests
//
//  P2-T14 — wiring `ConflictEngine.detect` into `Presentation.conflicted` on
//  the live calendar canvas. `ConflictEngineTests.swift` already covers the
//  engine's own detection/option logic in isolation (P2-T13); this suite
//  covers the one thing that task explicitly deferred: that
//  `MainWindow.conflictedEventIDs(events:routineBlocks:)` — the small,
//  `@MainActor`, testable helper `MainWindow` calls to build the id set it
//  threads through `TimedCanvasView` into `DayColumnView.presentation(for:
//  laidOut:)` — actually flags both halves of a real routine-vs-manual
//  overlap, and does not flag pairs `ConflictEngine` itself says are out of
//  scope (two manual, or two routine, events overlapping each other). Same
//  in-memory `ModelContainer`/`ModelContext` pattern as
//  RoutineEngineTests.swift / ConflictEngineTests.swift.
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

private func time(_ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(byAdding: .minute, value: hour * 60 + minute, to: day)!
}

private func makeBlock(flexibility: Flexibility = .fixed) -> RoutineBlock {
    RoutineBlock(title: "Block", startMinutes: 0, duration: 0, flexibility: flexibility)
}

private func makeRoutineEvent(block: RoutineBlock, title: String = "Routine", start: Date, end: Date) -> Event {
    Event(
        title: title, start: start, end: end, origin: .routine, flexibility: block.flexibility,
        sourceID: "template", externalID: "\(block.id.uuidString)#2026-09-18")
}

private func makeManualEvent(title: String = "Manual", start: Date, end: Date) -> Event {
    Event(title: title, start: start, end: end, origin: .manual)
}

@MainActor
private func insert(_ context: ModelContext, _ items: [AnyObject]) throws {
    for item in items {
        if let event = item as? Event { context.insert(event) }
        if let block = item as? RoutineBlock { context.insert(block) }
    }
    try context.save()
}

@Suite("MainWindow.conflictedEventIDs — Presentation.conflicted wiring")
@MainActor
struct ConflictPresentationWiringTests {

    @Test("A routine event overlapping a manual event: both ids are flagged")
    func routineOverlapsManualFlagsBothIDs() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .fixed)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(10))
        let manual = makeManualEvent(start: time(9, 30), end: time(10, 30))
        try insert(context, [block, routine, manual])

        let ids = MainWindow.conflictedEventIDs(events: [routine, manual], routineBlocks: [block])

        #expect(ids.contains(routine.id))
        #expect(ids.contains(manual.id))
        #expect(ids.count == 2)
    }

    @Test("Two overlapping manual events: neither id is flagged (out of ConflictEngine's scope)")
    func manualOverlapsManualIsNotFlagged() throws {
        let context = try makeContext()
        let a = makeManualEvent(title: "A", start: time(9), end: time(10))
        let b = makeManualEvent(title: "B", start: time(9, 30), end: time(10, 30))
        try insert(context, [a, b])

        let ids = MainWindow.conflictedEventIDs(events: [a, b], routineBlocks: [])

        #expect(ids.isEmpty)
    }

    @Test("Two overlapping routine events: neither id is flagged (out of ConflictEngine's scope)")
    func routineOverlapsRoutineIsNotFlagged() throws {
        let context = try makeContext()
        let blockA = makeBlock(flexibility: .fixed)
        let blockB = makeBlock(flexibility: .fixed)
        let a = makeRoutineEvent(block: blockA, title: "A", start: time(9), end: time(10))
        let b = makeRoutineEvent(block: blockB, title: "B", start: time(9, 30), end: time(10, 30))
        try insert(context, [blockA, blockB, a, b])

        let ids = MainWindow.conflictedEventIDs(events: [a, b], routineBlocks: [blockA, blockB])

        #expect(ids.isEmpty)
    }

    @Test("A non-overlapping routine/manual pair is not flagged")
    func nonOverlappingPairIsNotFlagged() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .fixed)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(10))
        let manual = makeManualEvent(start: time(11), end: time(12))
        try insert(context, [block, routine, manual])

        let ids = MainWindow.conflictedEventIDs(events: [routine, manual], routineBlocks: [block])

        #expect(ids.isEmpty)
    }

    @Test("Recomputes when the event list changes: adding an overlapping manual event flags a previously-clear routine event")
    func recomputesWhenEventsChange() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .fixed)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(10))
        try insert(context, [block, routine])

        let before = MainWindow.conflictedEventIDs(events: [routine], routineBlocks: [block])
        #expect(before.isEmpty)

        let manual = makeManualEvent(start: time(9, 30), end: time(10, 30))
        try insert(context, [manual])

        let after = MainWindow.conflictedEventIDs(events: [routine, manual], routineBlocks: [block])
        #expect(after.contains(routine.id))
        #expect(after.contains(manual.id))
    }
}
