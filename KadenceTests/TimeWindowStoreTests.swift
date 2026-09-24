//
//  TimeWindowStoreTests.swift
//  KadenceTests
//
//  Task P2-T21 — components.md §13.3's "protected / low-energy / peak-focus
//  regions editable" in the Routines window's Windows mode: select, whole-span
//  move, `⌫` delete for an EXISTING `TimeWindow` row. Same in-memory
//  ModelContainer/ModelContext pattern, and the same undo/redo rigor, as
//  `RoutineWeekLayoutTests.swift`'s own `RoutineBlockStore` suites (task
//  P2-T11) — `TimeWindowStore` is this task's sibling of that store.
//
//  What is deliberately NOT tested here, because it does not exist yet:
//  resize (a top/bottom edge drag) and create (drag-to-create on empty
//  windows-mode canvas) — next task's job, per this task's own brief.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

@MainActor
private func makeTimeWindowStore() throws -> (TimeWindowStore, ModelContext, UndoStack) {
    let container = try ModelContainer(
        for: Event.self, Place.self, RoutineTemplate.self, RoutineBlock.self, TimeWindow.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let undo = UndoStack()
    return (TimeWindowStore(context: context, undo: undo), context, undo)
}

/// A protected "Sleep" window, Mon/Wed/Fri, 22:00–07:00 — deliberately
/// wrapping midnight, since that is the whole reason `TimeWindow.move` does
/// not clamp the way `RoutineBlockStore.move` does (G-013 does not apply
/// here — see `TimeWindowStore.swift`'s own header).
@MainActor
private func makeSleepWindow(in context: ModelContext) -> TimeWindow {
    let window = TimeWindow(
        weekdays: [2, 4, 6], startMinutes: 22 * 60, endMinutes: 7 * 60,
        kind: .protected, label: "Sleep")
    context.insert(window)
    try? context.save()
    return window
}

@MainActor
private func fetchTimeWindow(_ id: UUID, in context: ModelContext) -> TimeWindow? {
    var descriptor = FetchDescriptor<TimeWindow>(predicate: #Predicate { $0.id == id })
    descriptor.fetchLimit = 1
    return try? context.fetch(descriptor).first
}

@Suite("TimeWindowStore.move")
@MainActor
struct TimeWindowStoreMoveTests {

    @Test("A plain within-day move shifts both ends by the same delta and names the undo step")
    func movesWithinDayAndNames() throws {
        let (store, context, undo) = try makeTimeWindowStore()
        let window = makeSleepWindow(in: context)

        // A daytime-shaped window for this case, so the delta cannot itself
        // cross midnight and muddy what is being asserted.
        window.startMinutes = 9 * 60
        window.endMinutes = 10 * 60
        try? context.save()

        store.move(window, byDeltaMinutes: 30)

        #expect(window.startMinutes == 9 * 60 + 30)
        #expect(window.endMinutes == 10 * 60 + 30)
        #expect(undo.undoActionName == "Move Time Window")
        #expect(undo.undoMenuTitle == "Undo Move Time Window")
    }

    @Test("A positive delta that pushes endMinutes past 24:00 wraps it to the small hours, independently of startMinutes")
    func wrapsPastMidnightForward() throws {
        let (store, context, _) = try makeTimeWindowStore()
        let window = makeSleepWindow(in: context)
        window.startMinutes = 23 * 60
        window.endMinutes = 23 * 60 + 30
        try? context.save()

        // +45 minutes: start 23:00 -> 23:45 (no wrap), end 23:30 -> 00:15 (wraps).
        store.move(window, byDeltaMinutes: 45)

        #expect(window.startMinutes == 23 * 60 + 45)
        #expect(window.endMinutes == 15)
    }

    @Test("A negative delta that pushes startMinutes before 00:00 wraps it to the previous day's tail, independently of endMinutes")
    func wrapsPastMidnightBackward() throws {
        let (store, context, _) = try makeTimeWindowStore()
        let window = makeSleepWindow(in: context)
        window.startMinutes = 0
        window.endMinutes = 30

        // -45 minutes: start 00:00 -> 23:15 (wraps), end 00:30 -> 23:45 (wraps too, same amount).
        store.move(window, byDeltaMinutes: -45)

        #expect(window.startMinutes == 24 * 60 - 45)
        #expect(window.endMinutes == 24 * 60 - 15)
    }

    @Test("Moving an already-wrapping window (22:00–07:00) preserves the wrap and the 9-hour duration")
    func movesAnAlreadyWrappingWindow() throws {
        let (store, context, _) = try makeTimeWindowStore()
        let window = makeSleepWindow(in: context) // 22:00 - 07:00

        store.move(window, byDeltaMinutes: 60)

        #expect(window.startMinutes == 23 * 60)
        #expect(window.endMinutes == 8 * 60)
    }

    @Test("A zero delta is a no-op and pushes no undo step")
    func zeroDeltaDoesNotPush() throws {
        let (store, context, undo) = try makeTimeWindowStore()
        let window = makeSleepWindow(in: context)

        store.move(window, byDeltaMinutes: 0)

        #expect(undo.canUndo == false)
    }

    @Test("Undo restores the original startMinutes/endMinutes; redo reapplies the move")
    func undoRedo() throws {
        let (store, context, undo) = try makeTimeWindowStore()
        let window = makeSleepWindow(in: context)
        let id = window.id
        let originalStart = window.startMinutes
        let originalEnd = window.endMinutes

        store.move(window, byDeltaMinutes: 90)
        #expect(undo.canRedo == false)

        undo.undo()
        let afterUndo = try #require(fetchTimeWindow(id, in: context))
        #expect(afterUndo.startMinutes == originalStart)
        #expect(afterUndo.endMinutes == originalEnd)
        #expect(undo.canRedo)

        undo.redo()
        let afterRedo = try #require(fetchTimeWindow(id, in: context))
        #expect(afterRedo.startMinutes == ((originalStart + 90) % 1440 + 1440) % 1440)
        #expect(afterRedo.endMinutes == ((originalEnd + 90) % 1440 + 1440) % 1440)
    }
}

@Suite("TimeWindowStore.delete")
@MainActor
struct TimeWindowStoreDeleteTests {

    @Test("Delete removes the row immediately, no confirmation, and names the undo step")
    func deletes() throws {
        let (store, context, undo) = try makeTimeWindowStore()
        let window = makeSleepWindow(in: context)
        let id = window.id

        store.delete(window)

        #expect(fetchTimeWindow(id, in: context) == nil)
        #expect(undo.undoActionName == "Delete Time Window")
        #expect(undo.undoMenuTitle == "Undo Delete Time Window")
    }

    @Test("Undo reinserts a row carrying the same id and every field, including kind and weekdays")
    func undoRestoresEveryField() throws {
        let (store, context, undo) = try makeTimeWindowStore()
        let window = makeSleepWindow(in: context)
        let id = window.id

        store.delete(window)
        undo.undo()

        let restored = try #require(fetchTimeWindow(id, in: context))
        #expect(restored.id == id)
        #expect(restored.weekdays == [2, 4, 6])
        #expect(restored.startMinutes == 22 * 60)
        #expect(restored.endMinutes == 7 * 60)
        #expect(restored.kind == .protected)
        #expect(restored.label == "Sleep")
    }

    @Test("Redo after an undone delete removes the row again")
    func redoAfterUndo() throws {
        let (store, context, undo) = try makeTimeWindowStore()
        let window = makeSleepWindow(in: context)
        let id = window.id

        store.delete(window)
        undo.undo()
        undo.redo()

        #expect(fetchTimeWindow(id, in: context) == nil)
    }

    @Test("Deleting a non-protected kind restores that kind too, not just protected's default")
    func undoRestoresNonDefaultKind() throws {
        let (store, context, undo) = try makeTimeWindowStore()
        let window = TimeWindow(
            weekdays: [1, 7], startMinutes: 13 * 60, endMinutes: 15 * 60,
            kind: .lowEnergy, label: "Post-lunch dip")
        context.insert(window)
        try? context.save()
        let id = window.id

        store.delete(window)
        undo.undo()

        let restored = try #require(fetchTimeWindow(id, in: context))
        #expect(restored.kind == .lowEnergy)
        #expect(restored.weekdays == [1, 7])
    }
}
