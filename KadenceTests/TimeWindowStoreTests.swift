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
//  Task P2-T22 added `TimeWindowStoreResizeTests` below, covering resize (a
//  top/bottom edge drag).
//
//  Task P2-T23 adds `TimeWindowStoreCreateTests` below, covering the other
//  half this file's own header used to say did not exist yet: create
//  (drag-to-create on empty windows-mode canvas).
//
//  Task P2-T24 adds `TimeWindowStoreInspectorFieldTests` below, covering the
//  three new inspector-driven mutations: `setKind`, `setWeekdays`, `setLabel`
//  — components.md §13.3's "then pick the kind from the inspector," plus the
//  weekday-set and label editing §7 also promises. Same rigor as every suite
//  above: exact field values, exact undo-step name, no-op guards push nothing,
//  undo/redo round-trips.
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

/// Task P2-T22 — components.md §13.3's "the same size.blockResizeHandleHeight
/// handles blocks use", the piece both P2-T20 and P2-T21 explicitly deferred.
/// Same modular-not-clamping reasoning as `TimeWindowStoreMoveTests` above:
/// a candidate edge wraps mod 1440 rather than clamping into `[0, 1440]`, and
/// the only floor is the same 15-minute minimum `RoutineBlockStore.resize`
/// uses, computed forward-and-wrapping the way `spans(on:)`/`move` already do.
@Suite("TimeWindowStore.resize")
@MainActor
struct TimeWindowStoreResizeTests {

    /// A plain daytime window, 09:00–10:00, with no midnight involved — the
    /// baseline every "normal" case below starts from.
    @MainActor
    private func makeDaytimeWindow(in context: ModelContext) -> TimeWindow {
        let window = TimeWindow(
            weekdays: [2, 4, 6], startMinutes: 9 * 60, endMinutes: 10 * 60,
            kind: .lowEnergy, label: "Focus block")
        context.insert(window)
        try? context.save()
        return window
    }

    @Test("Dragging the top edge changes only startMinutes, and names the undo step")
    func resizesTopEdge() throws {
        let (store, context, undo) = try makeTimeWindowStore()
        let window = makeDaytimeWindow(in: context)

        store.resize(window, newStartMinutes: 9 * 60 + 15)

        #expect(window.startMinutes == 9 * 60 + 15)
        #expect(window.endMinutes == 10 * 60)
        #expect(undo.undoActionName == "Resize Time Window")
        #expect(undo.undoMenuTitle == "Undo Resize Time Window")
    }

    @Test("Dragging the bottom edge changes only endMinutes, and names the undo step")
    func resizesBottomEdge() throws {
        let (store, context, undo) = try makeTimeWindowStore()
        let window = makeDaytimeWindow(in: context)

        store.resize(window, newEndMinutes: 10 * 60 + 30)

        #expect(window.startMinutes == 9 * 60)
        #expect(window.endMinutes == 10 * 60 + 30)
        #expect(undo.undoActionName == "Resize Time Window")
    }

    @Test("Dragging the bottom edge past 24:00 wraps it into the small hours instead of clamping at 1440")
    func resizeBottomEdgeWrapsForward() throws {
        let (store, context, _) = try makeTimeWindowStore()
        // 23:20-23:50, so a modest drag of the bottom edge crosses midnight.
        let window = TimeWindow(
            weekdays: [2], startMinutes: 23 * 60 + 20, endMinutes: 23 * 60 + 50,
            kind: .protected, label: "Late block")
        context.insert(window)
        try? context.save()

        // 23:50 + 20 minutes = 00:10 the next day, i.e. minute 1450 unwrapped.
        store.resize(window, newEndMinutes: 23 * 60 + 50 + 20)

        #expect(window.startMinutes == 23 * 60 + 20)
        #expect(window.endMinutes == 10)
    }

    @Test("Dragging the top edge before 00:00 wraps it into the previous day's tail instead of clamping at 0")
    func resizeTopEdgeWrapsBackward() throws {
        let (store, context, _) = try makeTimeWindowStore()
        // 00:10-10:00, so dragging the top edge 30 minutes earlier crosses midnight.
        let window = TimeWindow(
            weekdays: [2], startMinutes: 10, endMinutes: 10 * 60,
            kind: .protected, label: "Early block")
        context.insert(window)
        try? context.save()

        store.resize(window, newStartMinutes: 10 - 30)

        #expect(window.startMinutes == 24 * 60 - 20)
        #expect(window.endMinutes == 10 * 60)
    }

    @Test("A top-edge drag that would leave less than 15 minutes before the fixed bottom edge is pulled back to exactly 15, not collapsed or inverted")
    func minimumDurationEnforcedFromTop() throws {
        let (store, context, _) = try makeTimeWindowStore()
        // 09:00-09:30 — only 30 minutes wide.
        let window = TimeWindow(
            weekdays: [2], startMinutes: 9 * 60, endMinutes: 9 * 60 + 30,
            kind: .lowEnergy, label: "Short block")
        context.insert(window)
        try? context.save()

        // Dragging the top edge to 09:20 would leave only 10 minutes.
        store.resize(window, newStartMinutes: 9 * 60 + 20)

        #expect(window.endMinutes == 9 * 60 + 30)
        #expect(window.startMinutes == 9 * 60 + 15) // end - 15, not 09:20.
    }

    @Test("A bottom-edge drag that would leave less than 15 minutes after the fixed top edge is pulled back to exactly 15, not collapsed or inverted")
    func minimumDurationEnforcedFromBottom() throws {
        let (store, context, _) = try makeTimeWindowStore()
        // 09:00-09:30 — only 30 minutes wide.
        let window = TimeWindow(
            weekdays: [2], startMinutes: 9 * 60, endMinutes: 9 * 60 + 30,
            kind: .lowEnergy, label: "Short block")
        context.insert(window)
        try? context.save()

        // Dragging the bottom edge back to 09:05 would leave only 5 minutes.
        store.resize(window, newEndMinutes: 9 * 60 + 5)

        #expect(window.startMinutes == 9 * 60)
        #expect(window.endMinutes == 9 * 60 + 15) // start + 15, not 09:05.
    }

    @Test("A resize that changes neither end (a no-op candidate) pushes no undo step")
    func noOpDoesNotPush() throws {
        let (store, context, undo) = try makeTimeWindowStore()
        let window = makeDaytimeWindow(in: context)

        store.resize(window, newStartMinutes: 9 * 60)

        #expect(undo.canUndo == false)
    }

    @Test("Undo restores the exact original startMinutes/endMinutes; redo reapplies the resize")
    func undoRedo() throws {
        let (store, context, undo) = try makeTimeWindowStore()
        let window = makeDaytimeWindow(in: context)
        let id = window.id
        let originalStart = window.startMinutes
        let originalEnd = window.endMinutes

        store.resize(window, newStartMinutes: 9 * 60 + 15, newEndMinutes: 10 * 60 + 30)
        #expect(undo.canRedo == false)

        undo.undo()
        let afterUndo = try #require(fetchTimeWindow(id, in: context))
        #expect(afterUndo.startMinutes == originalStart)
        #expect(afterUndo.endMinutes == originalEnd)
        #expect(undo.canRedo)

        undo.redo()
        let afterRedo = try #require(fetchTimeWindow(id, in: context))
        #expect(afterRedo.startMinutes == 9 * 60 + 15)
        #expect(afterRedo.endMinutes == 10 * 60 + 30)
    }
}

/// Task P2-T23 — components.md §13.3's "Creating one: drag on empty canvas,
/// then pick the kind from the inspector," the piece P2-T20/T21/T22 all
/// deferred by name. Only the drag half is tested here: `create` always
/// takes its `weekdays`/`startMinutes`/`endMinutes` from the caller (in the
/// real UI, a single-element weekday set and a 15-minute-floored drag) and
/// leaves `kind`/`label` at `TimeWindow.swift`'s own model defaults unless
/// the caller overrides them.
@Suite("TimeWindowStore.create")
@MainActor
struct TimeWindowStoreCreateTests {

    @Test("Create inserts a row with the exact given weekday set, .protected kind by default, and the given start/end minutes, and names the undo step")
    func createsWithDefaults() throws {
        let (store, context, undo) = try makeTimeWindowStore()

        let created = store.create(weekdays: [3], startMinutes: 9 * 60, endMinutes: 9 * 60 + 30)

        let window = try #require(created)
        #expect(window.weekdays == [3])
        #expect(window.startMinutes == 9 * 60)
        #expect(window.endMinutes == 9 * 60 + 30)
        #expect(window.kind == .protected)
        #expect(window.label == "")
        #expect(fetchTimeWindow(window.id, in: context) != nil)
        #expect(undo.undoActionName == "Create Time Window")
        #expect(undo.undoMenuTitle == "Undo Create Time Window")
    }

    @Test("A non-default kind and label are honoured when the caller supplies them")
    func createsWithExplicitKindAndLabel() throws {
        let (store, _, _) = try makeTimeWindowStore()

        let created = store.create(
            weekdays: [5], startMinutes: 13 * 60, endMinutes: 14 * 60,
            kind: .lowEnergy, label: "Post-lunch dip")

        let window = try #require(created)
        #expect(window.kind == .lowEnergy)
        #expect(window.label == "Post-lunch dip")
    }

    @Test("Exactly one named undo step is pushed per create")
    func pushesExactlyOneUndoStep() throws {
        let (store, _, undo) = try makeTimeWindowStore()

        store.create(weekdays: [2], startMinutes: 8 * 60, endMinutes: 8 * 60 + 45)

        #expect(undo.canUndo)
        undo.undo()
        #expect(undo.canUndo == false)
        #expect(undo.canRedo)
    }

    @Test("A drag shorter than 15 minutes is floored to exactly 15, not collapsed or left short")
    func fifteenMinuteFloorEnforced() throws {
        // `create` enforces the 15-minute minimum itself, defensively, the
        // same belt-and-braces shape `RoutineBlockStore.create` already uses
        // for its own floor — even though `RoutinesWindow.swift`'s
        // create-drag already floors before calling in. A 5-minute span
        // (10:00-10:05) must come back as exactly 15 minutes (10:00-10:15),
        // start held fixed, same as `resize`'s own minimum-duration rule.
        let (store, _, _) = try makeTimeWindowStore()

        let created = store.create(weekdays: [4], startMinutes: 10 * 60, endMinutes: 10 * 60 + 5)

        let window = try #require(created)
        #expect(window.startMinutes == 10 * 60)
        #expect(window.endMinutes == 10 * 60 + 15)
    }

    @Test("An empty weekday set creates nothing and pushes no undo step")
    func emptyWeekdaysCreatesNothing() throws {
        let (store, _, undo) = try makeTimeWindowStore()

        let created = store.create(weekdays: [], startMinutes: 9 * 60, endMinutes: 9 * 60 + 30)

        #expect(created == nil)
        #expect(undo.canUndo == false)
    }

    @Test("Undo removes the created window (fetch by id returns nil); redo restores it with the same id and fields")
    func undoRemovesRedoRestores() throws {
        let (store, context, undo) = try makeTimeWindowStore()

        let created = try #require(store.create(
            weekdays: [6], startMinutes: 7 * 60, endMinutes: 7 * 60 + 15,
            kind: .peakFocus, label: "Deep work"))
        let id = created.id

        #expect(fetchTimeWindow(id, in: context) != nil)

        undo.undo()
        #expect(fetchTimeWindow(id, in: context) == nil)
        #expect(undo.canRedo)

        undo.redo()
        let restored = try #require(fetchTimeWindow(id, in: context))
        #expect(restored.id == id)
        #expect(restored.weekdays == [6])
        #expect(restored.startMinutes == 7 * 60)
        #expect(restored.endMinutes == 7 * 60 + 15)
        #expect(restored.kind == .peakFocus)
        #expect(restored.label == "Deep work")
    }
}

/// Task P2-T24 — components.md §13.3's "then pick the kind from the
/// inspector," the remaining half of the sentence P2-T23 above's own header
/// names as its create-drag's counterpart. `setKind`/`setWeekdays`/`setLabel`
/// are the inspector's three field edits, wired to fire immediately on
/// change (no "Save" button) — each one is exactly one named undo step, same
/// as every method in the suites above.
@Suite("TimeWindowStore.inspector field edits")
@MainActor
struct TimeWindowStoreInspectorFieldTests {

    @MainActor
    private func makeFocusWindow(in context: ModelContext) -> TimeWindow {
        let window = TimeWindow(
            weekdays: [2, 4, 6], startMinutes: 9 * 60, endMinutes: 11 * 60,
            kind: .peakFocus, label: "Deep work")
        context.insert(window)
        try? context.save()
        return window
    }

    // MARK: setKind

    @Test("setKind changes the kind and names its own undo step")
    func setKindChangesKindAndNames() throws {
        let (store, context, undo) = try makeTimeWindowStore()
        let window = makeFocusWindow(in: context)

        store.setKind(window, to: .lowEnergy)

        #expect(window.kind == .lowEnergy)
        #expect(undo.undoActionName == "Set Time Window Kind")
        #expect(undo.undoMenuTitle == "Undo Set Time Window Kind")
    }

    @Test("Setting the same kind again is a no-op and pushes no undo step")
    func setKindSameValueIsNoOp() throws {
        let (store, context, undo) = try makeTimeWindowStore()
        let window = makeFocusWindow(in: context)

        store.setKind(window, to: .peakFocus)

        #expect(undo.canUndo == false)
    }

    @Test("Undo restores the original kind; redo reapplies the new one")
    func setKindUndoRedo() throws {
        let (store, context, undo) = try makeTimeWindowStore()
        let window = makeFocusWindow(in: context)
        let id = window.id

        store.setKind(window, to: .protected)
        #expect(undo.canRedo == false)

        undo.undo()
        let afterUndo = try #require(fetchTimeWindow(id, in: context))
        #expect(afterUndo.kind == .peakFocus)
        #expect(undo.canRedo)

        undo.redo()
        let afterRedo = try #require(fetchTimeWindow(id, in: context))
        #expect(afterRedo.kind == .protected)
    }

    // MARK: setWeekdays

    @Test("setWeekdays adds a weekday to the set and names its own undo step")
    func setWeekdaysAdds() throws {
        let (store, context, undo) = try makeTimeWindowStore()
        let window = makeFocusWindow(in: context)

        store.setWeekdays(window, to: [2, 4, 6, 3])

        #expect(window.weekdays == [2, 3, 4, 6])
        #expect(undo.undoActionName == "Set Time Window Weekdays")
        #expect(undo.undoMenuTitle == "Undo Set Time Window Weekdays")
    }

    @Test("setWeekdays removes a weekday from the set")
    func setWeekdaysRemoves() throws {
        let (store, context, _) = try makeTimeWindowStore()
        let window = makeFocusWindow(in: context)

        store.setWeekdays(window, to: [2, 4])

        #expect(window.weekdays == [2, 4])
    }

    @Test("An empty weekday set is refused: the field, and the row, stay unchanged, and no undo step is pushed")
    func setWeekdaysRefusesEmpty() throws {
        let (store, context, undo) = try makeTimeWindowStore()
        let window = makeFocusWindow(in: context)

        store.setWeekdays(window, to: [])

        #expect(window.weekdays == [2, 4, 6])
        #expect(undo.canUndo == false)
    }

    @Test("Setting the identical weekday set again is a no-op and pushes no undo step")
    func setWeekdaysSameValueIsNoOp() throws {
        let (store, context, undo) = try makeTimeWindowStore()
        let window = makeFocusWindow(in: context)

        store.setWeekdays(window, to: [2, 4, 6])

        #expect(undo.canUndo == false)
    }

    @Test("Undo restores the original weekday set; redo reapplies the new one")
    func setWeekdaysUndoRedo() throws {
        let (store, context, undo) = try makeTimeWindowStore()
        let window = makeFocusWindow(in: context)
        let id = window.id

        store.setWeekdays(window, to: [1, 2, 4, 6])
        #expect(undo.canRedo == false)

        undo.undo()
        let afterUndo = try #require(fetchTimeWindow(id, in: context))
        #expect(afterUndo.weekdays == [2, 4, 6])
        #expect(undo.canRedo)

        undo.redo()
        let afterRedo = try #require(fetchTimeWindow(id, in: context))
        #expect(afterRedo.weekdays == [1, 2, 4, 6])
    }

    // MARK: setLabel

    @Test("setLabel commits the new text and names its own undo step")
    func setLabelCommits() throws {
        let (store, context, undo) = try makeTimeWindowStore()
        let window = makeFocusWindow(in: context)

        store.setLabel(window, to: "Deep Work Block")

        #expect(window.label == "Deep Work Block")
        #expect(undo.undoActionName == "Set Time Window Label")
        #expect(undo.undoMenuTitle == "Undo Set Time Window Label")
    }

    @Test("Committing the identical label again is a no-op and pushes no undo step")
    func setLabelSameValueIsNoOp() throws {
        let (store, context, undo) = try makeTimeWindowStore()
        let window = makeFocusWindow(in: context)

        store.setLabel(window, to: "Deep work")

        #expect(undo.canUndo == false)
    }

    @Test("Undo restores the original label; redo reapplies the new one")
    func setLabelUndoRedo() throws {
        let (store, context, undo) = try makeTimeWindowStore()
        let window = makeFocusWindow(in: context)
        let id = window.id

        store.setLabel(window, to: "Renamed")
        #expect(undo.canRedo == false)

        undo.undo()
        let afterUndo = try #require(fetchTimeWindow(id, in: context))
        #expect(afterUndo.label == "Deep work")
        #expect(undo.canRedo)

        undo.redo()
        let afterRedo = try #require(fetchTimeWindow(id, in: context))
        #expect(afterRedo.label == "Renamed")
    }

    @Test("Each field edit is exactly one named undo step: three separate calls push three separate steps")
    func eachFieldEditIsExactlyOneStep() throws {
        let (store, context, undo) = try makeTimeWindowStore()
        let window = makeFocusWindow(in: context)

        store.setKind(window, to: .protected)
        store.setWeekdays(window, to: [2, 4, 6, 1])
        store.setLabel(window, to: "Sleep")

        #expect(undo.undoSteps.map(\.name) == [
            "Set Time Window Kind", "Set Time Window Weekdays", "Set Time Window Label",
        ])
    }
}
