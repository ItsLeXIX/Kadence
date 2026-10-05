//
//  ConflictApplyTests.swift
//  KadenceTests
//
//  P2-T17 — `↩` apply (interactions.md §10.1's last paragraph, components.md
//  §14.5). The piece P2-T16 explicitly left out: preview-on-focus and
//  abandonment (`ConflictPreviewTests.swift`) are already covered; this suite
//  covers `CalendarState.applyFocusedConflictOption(store:recomputeConflicts:)`
//  and the `EventStore`/`ConflictEngine` pieces it leans on. Matching the
//  task's own acceptance criteria:
//
//  (a) applying an option commits the correct frame(s) to the store —
//      `.shiftLater` and `.shorten` each land the exact `newStart`/`newEnd`
//      the option proposed.
//  (b) the whole apply is a single named undo step ("Resolve Conflict",
//      read as "Undo Resolve Conflict" in the Edit menu — interactions.md
//      §10.1's own words) that fully reverts every moved block on one
//      `UndoStack.undo()`.
//  (c) after apply, the panel advances to the next unresolved conflict (by
//      `ConflictOrdering`'s stable rule) and previews its first (the
//      top) option, when one exists.
//  (d) after applying the last conflict, the inspector returns to normal
//      (`selectedConflictID == nil`) and `state.conflicts` — the same list
//      that governs the needs-attention row's count (see
//      `ConflictEntryPointTests.swift`) — is empty, so the row hides at
//      zero. No "all clear" state is asserted because none is built.
//  (e) the `.skipToday` apply path writes `.skipped` status, not a block
//      move, as a single undo step, and (per `design/GAPS.md` G-015,
//      `ConflictEngine.detect`'s new `.skipped`-routine filter) actually
//      resolves the conflict it was applied to.
//
//  Same in-memory ModelContainer/ModelContext pattern as
//  ConflictPreviewTests.swift / ConflictEntryPointTests.swift.
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

private func makeBlock(flexibility: Flexibility, shiftableMinutes: Int? = nil) -> RoutineBlock {
    RoutineBlock(title: "Block", startMinutes: 0, duration: 0, flexibility: flexibility, shiftableMinutes: shiftableMinutes)
}

private func makeRoutineEvent(
    block: RoutineBlock, title: String = "Routine", start: Date, end: Date, day: String = "2026-09-18"
) -> Event {
    Event(
        title: title, start: start, end: end, origin: .routine, flexibility: block.flexibility,
        sourceID: "template", externalID: "\(block.id.uuidString)#\(day)")
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

/// Every event and every routine block currently in `context`, refetched
/// fresh — the same shape `MainWindow.applyFocusedConflictOption`'s own
/// `recomputeConflicts` closure builds from the live `@Query` arrays, just
/// driven from a `ModelContext` fetch here since tests have no view/query.
@MainActor
private func recompute(_ context: ModelContext) throws -> [Conflict] {
    let events = try context.fetch(FetchDescriptor<Event>())
    let blocks = try context.fetch(FetchDescriptor<RoutineBlock>())
    return MainWindow.sortedConflicts(events: events, routineBlocks: blocks)
}

@MainActor
private func firstEvent(_ context: ModelContext, id: UUID) throws -> Event {
    var descriptor = FetchDescriptor<Event>(predicate: #Predicate { $0.id == id })
    descriptor.fetchLimit = 1
    return try #require(try context.fetch(descriptor).first)
}

// MARK: - (a)/(b) shiftLater and shorten commit the right frame, as one undo step

@Suite("applyFocusedConflictOption — shiftLater/shorten commit and undo as one step")
@MainActor
struct ApplyShiftAndShortenTests {

    @Test("shiftLater commits the option's exact newStart/newEnd, as a single named undo step that fully reverts")
    func shiftLaterCommitsAndUndoesAsOneStep() throws {
        let context = try makeContext()
        let undo = UndoStack()
        let store = EventStore(context: context, undo: undo)

        let block = makeBlock(flexibility: .shiftable, shiftableMinutes: 180)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(10))
        let manual = makeManualEvent(start: time(9, 20), end: time(10, 10))
        try insert(context, [block, routine, manual])

        let conflicts = try recompute(context)
        let conflict = try #require(conflicts.first)
        let shift = try #require(conflict.options.first { $0.kind == .shiftLater })

        let state = CalendarState()
        state.conflicts = conflicts
        state.selectedConflictID = conflict.id
        state.selectedConflictOptionID = shift.id

        let applied = state.applyFocusedConflictOption(store: store) { try! recompute(context) }
        #expect(applied)

        let moved = try firstEvent(context, id: routine.id)
        #expect(moved.start == time(10, 15))
        #expect(moved.end == time(11, 15))

        // (b) — one named step, not one per moved block.
        #expect(undo.undoSteps.count == 1)
        #expect(undo.undoActionName == "Resolve Conflict")
        #expect(undo.undoMenuTitle == "Undo Resolve Conflict")

        undo.undo()
        let reverted = try firstEvent(context, id: routine.id)
        #expect(reverted.start == time(9))
        #expect(reverted.end == time(10))
        #expect(!undo.canUndo, "the single step must be gone after one ⌘Z, not partially reverted")
    }

    @Test("shorten commits the trimmed span exactly, as a single named undo step that fully reverts")
    func shortenCommitsAndUndoesAsOneStep() throws {
        let context = try makeContext()
        let undo = UndoStack()
        let store = EventStore(context: context, undo: undo)

        let block = makeBlock(flexibility: .fixed)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(11))
        let manual = makeManualEvent(start: time(10, 45), end: time(11, 30))
        try insert(context, [block, routine, manual])

        let conflicts = try recompute(context)
        let conflict = try #require(conflicts.first)
        let shorten = try #require(conflict.options.first { $0.kind == .shorten })

        let state = CalendarState()
        state.conflicts = conflicts
        state.selectedConflictID = conflict.id
        state.selectedConflictOptionID = shorten.id

        state.applyFocusedConflictOption(store: store) { try! recompute(context) }

        let trimmed = try firstEvent(context, id: routine.id)
        #expect(trimmed.start == time(9))
        #expect(trimmed.end == time(10, 45))

        #expect(undo.undoSteps.count == 1)
        #expect(undo.undoActionName == "Resolve Conflict")

        undo.undo()
        let reverted = try firstEvent(context, id: routine.id)
        #expect(reverted.start == time(9))
        #expect(reverted.end == time(11))
    }
}

// MARK: - (c)/(d) advance to next conflict, or resolved-and-empty

@Suite("applyFocusedConflictOption — advances to the next conflict, or resolves to empty")
@MainActor
struct ApplyAdvanceTests {

    @Test("Two conflicts: applying the first previews the second's first (top) option")
    func advancesToNextConflictsFirstOption() throws {
        let context = try makeContext()
        let undo = UndoStack()
        let store = EventStore(context: context, undo: undo)

        let earlyBlock = makeBlock(flexibility: .shiftable, shiftableMinutes: 180)
        let earlyRoutine = makeRoutineEvent(block: earlyBlock, title: "Early", start: time(8), end: time(9))
        let earlyOther = makeManualEvent(title: "EarlyOther", start: time(8, 20), end: time(9, 10))

        let lateBlock = makeBlock(flexibility: .shiftable, shiftableMinutes: 180)
        let lateRoutine = makeRoutineEvent(block: lateBlock, title: "Late", start: time(20), end: time(21))
        let lateOther = makeManualEvent(title: "LateOther", start: time(20, 20), end: time(21, 10))

        try insert(context, [earlyBlock, earlyRoutine, earlyOther, lateBlock, lateRoutine, lateOther])

        let conflicts = try recompute(context)
        #expect(conflicts.count == 2)
        let firstConflict = try #require(conflicts.first { $0.routineEvent.title == "Early" })
        let secondConflict = try #require(conflicts.first { $0.routineEvent.title == "Late" })
        let firstOption = try #require(firstConflict.options.first)

        let state = CalendarState()
        state.conflicts = conflicts
        state.selectedConflictID = firstConflict.id
        state.selectedConflictOptionID = firstOption.id

        state.applyFocusedConflictOption(store: store) { try! recompute(context) }

        #expect(state.selectedConflictID == secondConflict.id, "advances to the next unresolved conflict")
        // `ConflictOption.id` is a fresh `UUID()` per `ConflictEngine.detect`
        // pass (`ConflictEngine.finalize`'s own doc comment) — the option's
        // identity from the PRE-apply `conflicts` snapshot is meaningless
        // after `recomputeConflicts` re-runs `detect`, so the expected id
        // has to come from `state.conflicts` (the refreshed list this
        // method itself just wrote), not from `secondConflict` above.
        let refreshedSecond = try #require(state.conflicts.first { $0.id == secondConflict.id })
        #expect(
            state.selectedConflictOptionID == refreshedSecond.options.first?.id,
            "previews the next conflict's top option immediately; since P2-T45 that is not necessarily the recommended one (§14.3.3)")
        #expect(state.conflicts.count == 1, "the resolved conflict has dropped out of the refreshed list")
    }

    @Test("Applying the only conflict's option returns the inspector to normal and empties the conflict list")
    func lastConflictReturnsToNormal() throws {
        let context = try makeContext()
        let undo = UndoStack()
        let store = EventStore(context: context, undo: undo)

        let block = makeBlock(flexibility: .shiftable, shiftableMinutes: 180)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(10))
        let manual = makeManualEvent(start: time(9, 20), end: time(10, 10))
        try insert(context, [block, routine, manual])

        let conflicts = try recompute(context)
        let conflict = try #require(conflicts.first)
        let option = try #require(conflict.options.first)

        let state = CalendarState()
        state.conflicts = conflicts
        state.selectedConflictID = conflict.id
        state.selectedConflictOptionID = option.id

        state.applyFocusedConflictOption(store: store) { try! recompute(context) }

        // components.md §14.5 — "returns to the ordinary inspector... the
        // needs-attention row disappears (hidden at zero). No 'all clear'
        // state." `selectedConflictID == nil` is what takes the inspector
        // out of conflict mode (`MainWindow.activeConflict`'s own guard);
        // `state.conflicts.isEmpty` is what the needs-attention row's count
        // reads (`ConflictEntryPointTests.swift`'s own (a) suite).
        #expect(state.selectedConflictID == nil)
        #expect(state.selectedConflictOptionID == nil)
        #expect(state.conflicts.isEmpty)
    }

    @Test("A no-op when nothing is focused — no store mutation, no undo step, no state change")
    func noOpWhenNoOptionFocused() throws {
        let context = try makeContext()
        let undo = UndoStack()
        let store = EventStore(context: context, undo: undo)

        let block = makeBlock(flexibility: .shiftable, shiftableMinutes: 180)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(10))
        let manual = makeManualEvent(start: time(9, 20), end: time(10, 10))
        try insert(context, [block, routine, manual])

        let conflicts = try recompute(context)
        let conflict = try #require(conflicts.first)

        let state = CalendarState()
        state.conflicts = conflicts
        state.selectedConflictID = conflict.id
        // selectedConflictOptionID left nil — nothing previewed yet.

        let applied = state.applyFocusedConflictOption(store: store) { try! recompute(context) }

        #expect(!applied)
        #expect(!undo.canUndo)
        #expect(state.selectedConflictID == conflict.id, "still on the same conflict, untouched")
        let untouched = try firstEvent(context, id: routine.id)
        #expect(untouched.start == time(9))
    }
}

// MARK: - (e) .skipToday applies as a status change, not a block move

@Suite("applyFocusedConflictOption — .skipToday writes .skipped, not a frame move")
@MainActor
struct ApplySkipTodayTests {

    @Test("skipToday sets status to .skipped, leaves start/end untouched, as a single reversible undo step")
    func skipTodaySetsStatusOnly() throws {
        let context = try makeContext()
        let undo = UndoStack()
        let store = EventStore(context: context, undo: undo)

        let block = makeBlock(flexibility: .droppable)
        let routine = makeRoutineEvent(block: block, start: time(13), end: time(13, 30))
        let manual = makeManualEvent(start: time(13, 15), end: time(14))
        try insert(context, [block, routine, manual])

        let conflicts = try recompute(context)
        let conflict = try #require(conflicts.first)
        let skip = try #require(conflict.options.first { $0.kind == .skipToday })
        #expect(skip.newStart == nil && skip.newEnd == nil, "confirms this is the destination-less path")

        let state = CalendarState()
        state.conflicts = conflicts
        state.selectedConflictID = conflict.id
        state.selectedConflictOptionID = skip.id

        state.applyFocusedConflictOption(store: store) { try! recompute(context) }

        let skipped = try firstEvent(context, id: routine.id)
        #expect(skipped.status == .skipped)
        #expect(skipped.start == time(13), "a status change, not a block move")
        #expect(skipped.end == time(13, 30))

        #expect(undo.undoSteps.count == 1)
        #expect(undo.undoActionName == "Resolve Conflict")

        undo.undo()
        let reverted = try firstEvent(context, id: routine.id)
        #expect(reverted.status == .scheduled)
    }

    @Test("skipToday actually resolves the conflict: the panel returns to normal with an empty list (G-015)")
    func skipTodayResolvesTheConflict() throws {
        let context = try makeContext()
        let undo = UndoStack()
        let store = EventStore(context: context, undo: undo)

        let block = makeBlock(flexibility: .droppable)
        let routine = makeRoutineEvent(block: block, start: time(13), end: time(13, 30))
        let manual = makeManualEvent(start: time(13, 15), end: time(14))
        try insert(context, [block, routine, manual])

        let conflicts = try recompute(context)
        let conflict = try #require(conflicts.first)
        let skip = try #require(conflict.options.first { $0.kind == .skipToday })

        let state = CalendarState()
        state.conflicts = conflicts
        state.selectedConflictID = conflict.id
        state.selectedConflictOptionID = skip.id

        state.applyFocusedConflictOption(store: store) { try! recompute(context) }

        #expect(state.selectedConflictID == nil)
        #expect(state.conflicts.isEmpty, "ConflictEngine.detect no longer reports a pair whose routine side is .skipped")
    }
}

// MARK: - G-015: ConflictEngine.detect's own .skipped filter, pinned directly

@Suite("ConflictEngine.detect — a .skipped routine event is not an unresolved conflict (G-015)")
@MainActor
struct ConflictEngineSkippedFilterTests {

    @Test("A routine event with status .skipped does not pair, even though its times still overlap")
    func skippedRoutineEventIsExcluded() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .droppable)
        let routine = Event(
            title: "Nap", start: time(13), end: time(13, 30), origin: .routine, status: .skipped,
            flexibility: block.flexibility, sourceID: "template",
            externalID: "\(block.id.uuidString)#2026-09-18")
        let manual = makeManualEvent(start: time(13, 15), end: time(14))
        try insert(context, [block, routine, manual])

        let conflicts = ConflictEngine.detect(events: [routine, manual], routineBlocks: [block])
        #expect(conflicts.isEmpty)
    }
}
