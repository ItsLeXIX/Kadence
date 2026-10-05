//
//  ConflictPreviewTests.swift
//  KadenceTests
//
//  P2-T16 — preview-on-focus and unconditional abandonment
//  (components.md §14.4, interactions.md §10.1–§10.2). Three things this
//  suite pins, matching the task's own acceptance criteria:
//
//  (a) `ConflictPreviewFrames.resolve` — the pure geometry decision behind
//      "which two date intervals does a focused option imply" — covering
//      `.shiftLater`, `.shorten` and `.skipToday`, and the "switching between
//      two options never exposes the committed frame" guarantee at the level
//      this pure function can prove it: the ghost interval it returns is the
//      one invariant across every option of a conflict, so there is no
//      intermediate "reverted to committed" value anywhere in the mapping —
//      only `proposed` ever changes. The SwiftUI-level half (an `.animation`
//      keyed on this value, not a remount) lives in `DayColumnView` and is
//      exercised by hand per STATUS.md, for the reasons
//      `AccessibilityTests.swift`'s header already gives for this whole
//      seam.
//  (b) `CalendarState.moveSelectedConflictOption(by:)` — ↑/↓ moves through
//      `conflict.options` in array order, clamped at both ends, landing on
//      the first option when none was focused yet.
//  (c) `CalendarState.abandonConflictPreview()` — clears only
//      `selectedConflictOptionID`, leaves `selectedConflictID` alone (the
//      scope decision that method's own doc comment argues for and
//      DEVIATIONS.md records).
//
//  Same in-memory ModelContainer/ModelContext pattern as
//  ConflictEngineTests.swift / ConflictEntryPointTests.swift.
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

// MARK: - (a) ConflictPreviewFrames.resolve

@Suite("ConflictPreviewFrames.resolve — ghost/proposed geometry")
@MainActor
struct ConflictPreviewFramesTests {

    @Test("shiftLater: proposed is the option's newStart/newEnd, ghost is the routine event's real span")
    func shiftLaterProducesProposedFrame() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .shiftable, shiftableMinutes: 180)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(10))
        let manual = makeManualEvent(start: time(9, 20), end: time(10, 10))
        try insert(context, [block, routine, manual])

        let conflict = try #require(ConflictEngine.detect(events: [routine, manual], routineBlocks: [block]).first)
        let shift = try #require(conflict.options.first { $0.kind == .shiftLater })

        let frames = ConflictPreviewFrames.resolve(conflict: conflict, option: shift)

        #expect(frames.ghost == DateInterval(start: time(9), end: time(10)))
        #expect(frames.proposed == DateInterval(start: time(10, 15), end: time(11, 15)))
    }

    @Test("shorten: proposed is the trimmed span, ghost is unchanged")
    func shortenProducesProposedFrame() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .fixed)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(11))
        let manual = makeManualEvent(start: time(10, 45), end: time(11, 30))
        try insert(context, [block, routine, manual])

        let conflict = try #require(ConflictEngine.detect(events: [routine, manual], routineBlocks: [block]).first)
        let shorten = try #require(conflict.options.first { $0.kind == .shorten })

        let frames = ConflictPreviewFrames.resolve(conflict: conflict, option: shorten)

        #expect(frames.ghost == DateInterval(start: time(9), end: time(11)))
        #expect(frames.proposed == DateInterval(start: time(9), end: time(10, 45)))
    }

    @Test("skipToday: proposed is nil (documented treatment — ghost dims, no dashed twin) while ghost still resolves")
    func skipTodayProducesNoProposedFrame() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .droppable)
        let routine = makeRoutineEvent(block: block, start: time(13), end: time(13, 30))
        let manual = makeManualEvent(start: time(13, 15), end: time(14))
        try insert(context, [block, routine, manual])

        let conflict = try #require(ConflictEngine.detect(events: [routine, manual], routineBlocks: [block]).first)
        let skip = try #require(conflict.options.first { $0.kind == .skipToday })

        let frames = ConflictPreviewFrames.resolve(conflict: conflict, option: skip)

        #expect(frames.proposed == nil)
        #expect(frames.ghost == DateInterval(start: time(13), end: time(13, 30)))
    }

    @Test("Switching between two options never exposes the committed frame as an intermediate value: the ghost is invariant across the same conflict's options, only proposed changes")
    func switchingOptionsNeverPassesThroughAnUndefinedGhost() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .shiftable, shiftableMinutes: 180)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(10))
        let manual = makeManualEvent(start: time(9, 20), end: time(10, 10))
        try insert(context, [block, routine, manual])

        let conflict = try #require(ConflictEngine.detect(events: [routine, manual], routineBlocks: [block]).first)
        #expect(conflict.options.count >= 2, "need at least two options to prove switching behaves")

        let allFrames = conflict.options.map { ConflictPreviewFrames.resolve(conflict: conflict, option: $0) }

        // The ghost is the same value (the routine event's own real span) no
        // matter which option is focused — it is never recomputed as, or
        // momentarily equal to, some other "committed" value in between.
        let ghosts = Set(allFrames.map(\.ghost))
        #expect(ghosts.count == 1, "the ghost frame must be the one invariant across every option of the same conflict")
        #expect(ghosts.first == DateInterval(start: time(9), end: time(10)))

        // At least the shift/shorten-shaped options actually propose
        // somewhere else — proving `proposed` is the one thing that varies.
        let proposedValues = Set(allFrames.compactMap(\.proposed))
        #expect(!proposedValues.isEmpty)
    }
}

// MARK: - (b) CalendarState.moveSelectedConflictOption(by:)

@Suite("CalendarState.moveSelectedConflictOption — ↑/↓ preview navigation")
@MainActor
struct MoveSelectedConflictOptionTests {

    private func makeConflictState() throws -> (CalendarState, Conflict) {
        let context = try makeContext()
        let block = makeBlock(flexibility: .shiftable, shiftableMinutes: 180)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(10))
        let manual = makeManualEvent(start: time(9, 20), end: time(10, 10))
        try insert(context, [block, routine, manual])

        let conflicts = MainWindow.sortedConflicts(events: [routine, manual], routineBlocks: [block])
        let conflict = try #require(conflicts.first)
        #expect(conflict.options.count >= 2, "need at least two options to prove clamping/stepping")

        let state = CalendarState()
        state.conflicts = conflicts
        state.selectedConflictID = conflict.id
        return (state, conflict)
    }

    @Test("With nothing focused yet, both ↑ and ↓ land on the first option")
    func startsOnFirstOptionEitherDirection() throws {
        // Two independent conflicts (`ConflictOption.id` is a fresh `UUID()`
        // per `ConflictEngine.detect` pass) — each direction is checked
        // against its OWN conflict's first option, never the other's.
        let (upState, upConflict) = try makeConflictState()
        upState.moveSelectedConflictOption(by: -1)
        #expect(upState.selectedConflictOptionID == upConflict.options[0].id)

        let (downState, downConflict) = try makeConflictState()
        downState.moveSelectedConflictOption(by: 1)
        #expect(downState.selectedConflictOptionID == downConflict.options[0].id)
    }

    @Test("↓ steps forward through options in array order")
    func stepsForward() throws {
        let (state, conflict) = try makeConflictState()
        state.moveSelectedConflictOption(by: 1) // -> index 0
        state.moveSelectedConflictOption(by: 1) // -> index 1
        #expect(state.selectedConflictOptionID == conflict.options[1].id)
    }

    @Test("↑ steps backward, and clamps at the first option rather than wrapping")
    func stepsBackwardAndClampsAtStart() throws {
        let (state, conflict) = try makeConflictState()
        state.selectedConflictOptionID = conflict.options[1].id
        state.moveSelectedConflictOption(by: -1)
        #expect(state.selectedConflictOptionID == conflict.options[0].id)

        state.moveSelectedConflictOption(by: -1) // already at 0 — stays put
        #expect(state.selectedConflictOptionID == conflict.options[0].id)
    }

    @Test("↓ clamps at the last option rather than wrapping")
    func stepsForwardAndClampsAtEnd() throws {
        let (state, conflict) = try makeConflictState()
        let lastIndex = conflict.options.count - 1
        state.selectedConflictOptionID = conflict.options[lastIndex].id

        state.moveSelectedConflictOption(by: 1)
        #expect(state.selectedConflictOptionID == conflict.options[lastIndex].id)
    }

    @Test("A no-op when there is no selected conflict")
    func noOpWithNoConflict() {
        let state = CalendarState()
        state.moveSelectedConflictOption(by: 1)
        #expect(state.selectedConflictOptionID == nil)
    }
}

// MARK: - (c) CalendarState.abandonConflictPreview()

@Suite("CalendarState.abandonConflictPreview — unconditional, scoped abandonment")
@MainActor
struct AbandonConflictPreviewTests {

    @Test("Clears the pending preview but leaves the selected conflict itself alone")
    func clearsOptionOnlyNotConflict() throws {
        let context = try makeContext()
        let block = makeBlock(flexibility: .shiftable, shiftableMinutes: 180)
        let routine = makeRoutineEvent(block: block, start: time(9), end: time(10))
        let manual = makeManualEvent(start: time(9, 20), end: time(10, 10))
        try insert(context, [block, routine, manual])

        let conflicts = MainWindow.sortedConflicts(events: [routine, manual], routineBlocks: [block])
        let conflict = try #require(conflicts.first)

        let state = CalendarState()
        state.conflicts = conflicts
        state.selectedConflictID = conflict.id
        state.selectedConflictOptionID = conflict.options[0].id

        state.abandonConflictPreview()

        #expect(state.selectedConflictOptionID == nil, "the pending preview must revert")
        #expect(state.selectedConflictID == conflict.id, "leaving the panel does not also exit conflict mode — §10.2's subject is the preview, not the panel")
    }

    @Test("A no-op-shaped call (nothing was focused) leaves state as it found it")
    func noOpWhenNothingWasFocused() {
        let state = CalendarState()
        state.selectedConflictID = "irrelevant"
        state.abandonConflictPreview()
        #expect(state.selectedConflictOptionID == nil)
        #expect(state.selectedConflictID == "irrelevant")
    }
}
