//
//  ConflictEntryPointTests.swift
//  KadenceTests
//
//  P2-T15 — the needs-attention row and the static conflict panel (entry
//  point only; no preview, no apply, no abandonment — see STATUS.md/
//  DEVIATIONS.md for what remains). Three things this suite pins, matching
//  the task's own acceptance criteria:
//
//  (a) the row's underlying count is absent at zero conflicts and correct
//      otherwise — `SidebarView`/`KadenceCommands` both key off
//      `CalendarState.conflicts`/`MainWindow.sortedConflicts`, so testing
//      that count is testing exactly what governs "hidden at zero, badge
//      count otherwise" (components.md §10.2). Per
//      AccessibilityTests.swift's own header note, an NSHostingView in a
//      unit test cannot see whether a List row was actually included, so
//      this is the correct, and only reliable, seam.
//  (b) activating the entry point (`CalendarState.activateNeedsAttention()`)
//      selects the first unresolved conflict by `ConflictOrdering`'s stable
//      rule.
//  (c) the panel would render the right number of option rows with the
//      recommended one marked — via `ConflictOptionFormatting.rows(for:)`,
//      the exact array `ConflictPanelView` renders with no further
//      filtering (see that file's own doc comment on why this is the
//      correct testing seam).
//
//  Same in-memory ModelContainer/ModelContext pattern as
//  ConflictEngineTests.swift / ConflictPresentationWiringTests.swift.
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

private func makeBlock(flexibility: Flexibility = .fixed, shiftableMinutes: Int? = nil) -> RoutineBlock {
    RoutineBlock(title: "Block", startMinutes: 0, duration: 0, flexibility: flexibility, shiftableMinutes: shiftableMinutes)
}

private func makeRoutineEvent(
    block: RoutineBlock, title: String = "Routine", start: Date, end: Date
) -> Event {
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

// MARK: - (a) count: hidden at zero, correct otherwise

@Suite("Needs-attention row — the count that governs it")
@MainActor
struct NeedsAttentionCountTests {

    @Test("Zero conflicts: the count is zero, so the row is hidden")
    func zeroConflictsHidesTheRow() throws {
        let context = try makeContext()
        let a = makeManualEvent(title: "A", start: time(9), end: time(10))
        let b = makeManualEvent(title: "B", start: time(11), end: time(12))
        try insert(context, [a, b])

        let conflicts = MainWindow.sortedConflicts(events: [a, b], routineBlocks: [])
        #expect(conflicts.isEmpty)
    }

    @Test("Two independent conflicts: the count is 2, matching the badge")
    func twoConflictsGivesCountTwo() throws {
        let context = try makeContext()
        let blockA = makeBlock()
        let blockB = makeBlock()
        let routineA = makeRoutineEvent(block: blockA, title: "Gym", start: time(9), end: time(10))
        let manualA = makeManualEvent(title: "Call", start: time(9, 30), end: time(10, 30))
        let routineB = makeRoutineEvent(block: blockB, title: "Reading", start: time(20), end: time(21))
        let manualB = makeManualEvent(title: "Dinner", start: time(20, 30), end: time(21, 30))
        try insert(context, [blockA, blockB, routineA, manualA, routineB, manualB])

        let events = [routineA, manualA, routineB, manualB]
        let conflicts = MainWindow.sortedConflicts(events: events, routineBlocks: [blockA, blockB])

        #expect(conflicts.count == 2)
    }

    @Test("CalendarState.conflicts is what SidebarView/KadenceCommands both read — assigning it drives the same count")
    func calendarStateHoldsTheSameCount() throws {
        let context = try makeContext()
        let block = makeBlock()
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(10))
        let manual = makeManualEvent(start: time(9, 30), end: time(10, 30))
        try insert(context, [block, routine, manual])

        let state = CalendarState()
        #expect(state.conflicts.isEmpty)

        state.conflicts = MainWindow.sortedConflicts(events: [routine, manual], routineBlocks: [block])
        #expect(state.conflicts.count == 1)
    }
}

// MARK: - (b) activating selects the first unresolved conflict, by the stable order

@Suite("ConflictOrdering / activateNeedsAttention — 'first' is well-defined")
@MainActor
struct ConflictActivationTests {

    @Test("Ordering is ascending by the earlier of the two colliding events' start times")
    func orderingIsAscendingByEarliestStart() throws {
        let context = try makeContext()
        let lateBlock = makeBlock()
        let lateRoutine = makeRoutineEvent(block: lateBlock, title: "Late", start: time(20), end: time(21))
        let lateOther = makeManualEvent(title: "LateOther", start: time(20, 30), end: time(21, 30))

        let earlyBlock = makeBlock()
        let earlyRoutine = makeRoutineEvent(block: earlyBlock, title: "Early", start: time(8), end: time(9))
        let earlyOther = makeManualEvent(title: "EarlyOther", start: time(8, 30), end: time(9, 30))

        try insert(context, [lateBlock, lateRoutine, lateOther, earlyBlock, earlyRoutine, earlyOther])

        // Deliberately handed to `detect` in "late first" order, so a
        // passing test proves the ordering re-sorts rather than merely
        // preserving whatever order the input happened to be in.
        let events = [lateRoutine, lateOther, earlyRoutine, earlyOther]
        let conflicts = MainWindow.sortedConflicts(events: events, routineBlocks: [lateBlock, earlyBlock])

        #expect(conflicts.count == 2)
        #expect(conflicts.first?.routineEvent.title == "Early")
        #expect(conflicts.last?.routineEvent.title == "Late")
    }

    @Test("Tied start times sort deterministically by Conflict.id")
    func tiedStartTimesSortByID() throws {
        let context = try makeContext()
        let blockA = makeBlock()
        let routineA = makeRoutineEvent(block: blockA, title: "A", start: time(9), end: time(10))
        let otherA = makeManualEvent(title: "OtherA", start: time(9, 15), end: time(10, 15))

        let blockB = makeBlock()
        let routineB = makeRoutineEvent(block: blockB, title: "B", start: time(9), end: time(10))
        let otherB = makeManualEvent(title: "OtherB", start: time(9, 15), end: time(10, 15))

        try insert(context, [blockA, routineA, otherA, blockB, routineB, otherB])

        let events = [routineA, otherA, routineB, otherB]
        let firstPass = MainWindow.sortedConflicts(events: events, routineBlocks: [blockA, blockB])
        let secondPass = MainWindow.sortedConflicts(events: events, routineBlocks: [blockA, blockB])

        #expect(firstPass.map(\.id) == secondPass.map(\.id), "the same input must sort the same way every time")
    }

    @Test("activateNeedsAttention() selects the first unresolved conflict and enters conflict mode")
    func activateSelectsFirstConflict() throws {
        let context = try makeContext()
        let lateBlock = makeBlock()
        let lateRoutine = makeRoutineEvent(block: lateBlock, title: "Late", start: time(20), end: time(21))
        let lateOther = makeManualEvent(title: "LateOther", start: time(20, 30), end: time(21, 30))

        let earlyBlock = makeBlock()
        let earlyRoutine = makeRoutineEvent(block: earlyBlock, title: "Early", start: time(8), end: time(9))
        let earlyOther = makeManualEvent(title: "EarlyOther", start: time(8, 30), end: time(9, 30))

        try insert(context, [lateBlock, lateRoutine, lateOther, earlyBlock, earlyRoutine, earlyOther])

        let state = CalendarState()
        state.selectedEventID = earlyOther.id // pre-existing ordinary selection
        state.isInspectorVisible = false
        state.conflicts = MainWindow.sortedConflicts(
            events: [lateRoutine, lateOther, earlyRoutine, earlyOther],
            routineBlocks: [lateBlock, earlyBlock])

        state.activateNeedsAttention()

        #expect(state.selectedConflictID == state.conflicts.first?.id)
        #expect(state.conflicts.first?.routineEvent.title == "Early")
        #expect(state.selectedEventID == nil, "conflict mode replaces an ordinary selection")
        #expect(state.isInspectorVisible == true, "conflict mode requires the inspector to be visible")
        #expect(state.selectedConflictOptionID == nil, "no option is pre-highlighted")
    }

    @Test("activateNeedsAttention() is a no-op when there are no conflicts")
    func activateIsNoOpAtZero() {
        let state = CalendarState()
        state.selectedEventID = UUID()
        let idBefore = state.selectedEventID

        state.activateNeedsAttention()

        #expect(state.selectedConflictID == nil)
        #expect(state.selectedEventID == idBefore, "nothing should be disturbed when there is nothing to activate")
    }
}

// MARK: - (c) the panel's option rows: right count, recommended marked

@Suite("ConflictOptionFormatting.rows — what ConflictPanelView renders")
@MainActor
struct ConflictOptionRowContentTests {

    @Test("Row count matches the conflict's option count, and exactly one row is marked Recommended")
    func rowCountAndRecommendedFlagMatchTheConflict() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .shiftable, shiftableMinutes: 180)
        let routine = makeRoutineEvent(block: block, title: "Training", start: time(9), end: time(10))
        let manual = makeManualEvent(start: time(9, 20), end: time(10, 10))
        try insert(context, [block, routine, manual])

        let conflicts = ConflictEngine.detect(events: [routine, manual], routineBlocks: [block])
        let conflict = try #require(conflicts.first)

        let rows = ConflictOptionFormatting.rows(for: conflict)

        #expect(rows.count == conflict.options.count)
        #expect(rows.count >= 2)
        #expect(rows.filter(\.isRecommended).count == 1)
        // Ordering is preserved 1:1 — least disturbance first, same as
        // `conflict.options` (ConflictEngine.finalize already sorts it).
        #expect(rows.map(\.id) == conflict.options.map(\.id))
        #expect(rows.first?.isRecommended == true)
    }

    @Test("A droppable conflict's single option is still marked Recommended — the panel never shows zero rows")
    func singleOptionConflictStillShowsARecommendedRow() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .droppable)
        let routine = makeRoutineEvent(block: block, title: "Nap", start: time(13), end: time(13, 30))
        let manual = makeManualEvent(start: time(13, 15), end: time(14))
        try insert(context, [block, routine, manual])

        let conflicts = ConflictEngine.detect(events: [routine, manual], routineBlocks: [block])
        let conflict = try #require(conflicts.first)

        let rows = ConflictOptionFormatting.rows(for: conflict)

        #expect(rows.count == 1)
        #expect(rows[0].isRecommended == true)
        #expect(!rows[0].title.isEmpty)
        #expect(!rows[0].delta.isEmpty)
    }

    @Test("Titles are imperative and name the routine event; shift/shorten deltas name its new time range")
    func titlesAndDeltasNameTheRoutineEvent() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .shiftable, shiftableMinutes: 180)
        let routine = makeRoutineEvent(block: block, title: "Training", start: time(9), end: time(10))
        let manual = makeManualEvent(start: time(9, 20), end: time(10, 10))
        try insert(context, [block, routine, manual])

        let conflicts = ConflictEngine.detect(events: [routine, manual], routineBlocks: [block])
        let conflict = try #require(conflicts.first)
        let shift = try #require(conflict.options.first { $0.kind == .shiftLater })

        let title = ConflictOptionFormatting.title(for: shift, conflict: conflict)
        let delta = ConflictOptionFormatting.delta(for: shift, conflict: conflict)

        #expect(title.contains("Training"))
        #expect(title.contains("\(shift.disturbanceMinutes)"))
        #expect(delta.contains("Training"))
        #expect(delta.contains("10:15"), "the new start time should be legible in the disturbance line")
    }
}
