//
//  DetachmentTests.swift
//  KadenceTests
//
//  Task P2-T43: components.md §13.7.1 (what detaches — exactly the four
//  template-owned fields), §13.7.2 (one persisted flag), §13.4 / §13.7.3
//  (`Revert to routine`, `Revert Instance to Routine`), and §13.6.3 /
//  §13.6.4 honouring the flag.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

@MainActor
private func makeStore() throws -> (EventStore, ModelContext, UndoStack) {
    let container = try ModelContainer(
        for: Schema(KadenceSchema.models),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let undo = UndoStack()
    return (EventStore(context: context, undo: undo), context, undo)
}

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.firstWeekday = 2
    return calendar
}()
/// Monday 5 October 2026, 00:00 UTC.
private let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!
private let mon = 2, wed = 4

@MainActor
private func events(_ context: ModelContext) -> [Event] {
    (try? context.fetch(FetchDescriptor<Event>(sortBy: [SortDescriptor(\.start)]))) ?? []
}

/// "Training" 17:00–18:30, `.fixed`, Mon/Wed, materialised for one week.
@MainActor
private func materialised(_ store: EventStore) -> (RoutineTemplate, RoutineBlock, Event) {
    let block = RoutineBlock(title: "Training", startMinutes: 17 * 60, duration: 90 * 60, flexibility: .fixed)
    let template = RoutineTemplate(name: "Gym routine", activeWeekdays: [mon, wed], blocks: [block])
    store.context.insert(template)
    try? store.context.save()
    RoutineEngine.materialize(template: template, into: DateInterval(start: today, duration: 7 * 86400),
                              today: today, recordsUndo: false, store: store, calendar: calendar)
    return (template, block, events(store.context)[0])
}

@MainActor
private func pass(_ template: RoutineTemplate, _ store: EventStore) {
    RoutineEngine.withdraw(template: template, today: today, recordsUndo: false, store: store, calendar: calendar)
    RoutineEngine.materialize(template: template, into: DateInterval(start: today, duration: 7 * 86400),
                              today: today, recordsUndo: false, store: store, calendar: calendar)
}

// MARK: - §13.7.1, the four-field table

@Suite("What detaches an instance (§13.7.1)")
@MainActor
struct DetachmentTableTests {

    @Test("Move, resize, retitle, flexibility and snooze detach")
    func templateFieldsDetach() throws {
        let edits: [(String, @MainActor (EventStore, Event) -> Void)] = [
            ("move", { $0.move($1, by: 15 * 60) }),
            ("resize", { $0.resize($1, newEnd: $1.end.addingTimeInterval(30 * 60)) }),
            ("retitle", { $0.retitle($1, to: "Training (long)") }),
            ("flexibility", { $0.setFlexibility($1, to: .shiftable) }),
            ("snooze", { $0.snooze($1) }),
        ]
        for (name, edit) in edits {
            let (store, _, _) = try makeStore()
            let (_, _, event) = materialised(store)
            #expect(event.routineLink == .linked)
            edit(store, event)
            #expect(event.isDetached, "\(name) changes a template-owned field")
        }
    }

    @Test("Done, skipped, notes and lock never detach")
    func statusAndNotesDoNot() throws {
        let edits: [(String, @MainActor (EventStore, Event) -> Void)] = [
            ("done", { $0.toggleDone($1) }),
            ("undone", { $0.toggleDone($1); $0.toggleDone($1) }),
            ("skipped", { $0.toggleSkipped($1) }),
            ("unskipped", { $0.toggleSkipped($1); $0.toggleSkipped($1) }),
            ("markSkipped (.skipToday)", { $0.markSkipped($1) }),
            ("notes", { $0.setNotes($1, to: "bring shoes") }),
        ]
        for (name, edit) in edits {
            let (store, _, _) = try makeStore()
            let (_, _, event) = materialised(store)
            edit(store, event)
            #expect(event.routineLink == .linked, "\(name) is not a template-owned field")
        }
    }

    @Test("Applying a .skipToday conflict option does not detach; applying .shorten does")
    func conflictOptions() throws {
        for (kind, expected) in [(ConflictOptionKind.skipToday, RoutineLink.linked), (.shorten, .detached)] {
            let (store, context, _) = try makeStore()
            let (_, _, training) = materialised(store)
            let meeting = Event(title: "Supervisor meeting",
                                start: training.start.addingTimeInterval(30 * 60),
                                end: training.start.addingTimeInterval(75 * 60), origin: .manual)
            context.insert(meeting)
            try context.save()

            let blocks = try context.fetch(FetchDescriptor<RoutineBlock>())
            let conflicts = ConflictEngine.detect(events: events(context), routineBlocks: blocks)
            let conflict = try #require(conflicts.first { $0.routineEvent.id == training.id })
            let option = try #require(conflict.options.first { $0.kind == kind })

            let state = CalendarState()
            state.conflicts = conflicts
            state.selectedConflictID = conflict.id
            state.selectedConflictOptionID = option.id
            #expect(state.applyFocusedConflictOption(store: store, recomputeConflicts: { [] }))

            #expect(training.routineLink == expected, "\(kind)")
        }
    }

    @Test("Delete is a tombstone, not detachment")
    func deleteIsNotDetachment() throws {
        let (store, context, _) = try makeStore()
        let (_, _, event) = materialised(store)
        let key = event.externalID
        store.delete(event)
        #expect(!events(context).contains { $0.externalID == key })
        #expect(try context.fetch(FetchDescriptor<RoutineTombstone>()).count == 1)
        #expect(!events(context).contains { $0.isDetached })
    }

    @Test("An instance edited back to the template's values stays detached")
    func editedBackStaysDetached() throws {
        let (store, _, _) = try makeStore()
        let (_, _, event) = materialised(store)
        store.move(event, by: 30 * 60)
        store.move(event, by: -30 * 60)
        #expect(event.start == calendar.date(byAdding: .hour, value: 17, to: today))
        #expect(event.isDetached)
    }

    @Test("⌘Z on the detaching edit links the instance again")
    func undoRelinks() throws {
        let (store, _, undo) = try makeStore()
        let (_, _, event) = materialised(store)
        store.move(event, by: 30 * 60)
        #expect(event.isDetached)
        undo.undo()
        #expect(event.routineLink == .linked)
        undo.redo()
        #expect(event.isDetached)
    }

    @Test("A manual or hand-seeded event never gets a link")
    func nonInstancesStayLinked() throws {
        let (store, context, _) = try makeStore()
        let manual = Event(title: "Coffee", start: today.addingTimeInterval(36000), end: today.addingTimeInterval(39600))
        let handSeeded = Event(title: "Focus review", start: today.addingTimeInterval(72000),
                               end: today.addingTimeInterval(75600), origin: .routine)
        context.insert(manual)
        context.insert(handSeeded)
        try context.save()
        store.move(manual, by: 900)
        store.move(handSeeded, by: 900)
        #expect(manual.routineLink == .linked)
        #expect(handSeeded.routineLink == .linked)
    }
}

// MARK: - Re-materialisation and withdrawal honour the flag

@Suite("Re-materialisation honours detachment (§13.6.3 / §13.6.4)")
@MainActor
struct DetachmentRematerializationTests {

    @Test("A template edit updates linked instances and leaves the detached one exactly where the user put it")
    func leavesDetachedAlone() throws {
        let (store, context, _) = try makeStore()
        let (template, block, first) = materialised(store)
        store.move(first, by: 60 * 60)          // 18:00–19:30, detached
        let pinnedStart = first.start
        block.startMinutes = 16 * 60
        try context.save()

        pass(template, store)

        #expect(first.start == pinnedStart)
        #expect(first.isDetached)
        let others = events(context).filter { $0.id != first.id }
        #expect(others.allSatisfy { calendar.component(.hour, from: $0.start) == 16 })
    }

    @Test("Withdrawal keeps a detached instance, releases it, and later passes keep it")
    func withdrawalReleases() throws {
        let (store, context, undo) = try makeStore()
        let (template, _, first) = materialised(store)   // Monday's
        store.move(first, by: 30 * 60)
        let keptID = first.id

        RoutineTemplateStore(context: context, undo: undo)
            .setWeekday(mon, active: false, in: template, today: today, calendar: calendar)
        #expect(events(context).contains { $0.id == keptID })
        #expect(first.routineLink == .released)
        #expect(RoutineInstance.status(of: first, in: context) == .released(routineName: "Gym routine"))

        pass(template, store)
        pass(template, store)
        #expect(events(context).contains { $0.id == keptID }, "a released instance is an ordinary event now")

        // The release is part of the weekday step: one ⌘Z re-detaches it.
        #expect(undo.undoMenuTitle == "Undo Remove Monday from Routine")
        undo.undo()
        #expect(first.routineLink == .detached)
    }

    @Test("A released instance has no Revert")
    func releasedCannotRevert() throws {
        let (store, context, undo) = try makeStore()
        let (template, _, first) = materialised(store)
        store.move(first, by: 30 * 60)
        RoutineTemplateStore(context: context, undo: undo)
            .setWeekday(mon, active: false, in: template, today: today, calendar: calendar)
        #expect(!RoutineInstance.revert(first, store: store, calendar: calendar))
    }
}

// MARK: - Revert to routine

@Suite("Revert to routine (§13.4, §13.7.3)")
@MainActor
struct RevertToRoutineTests {

    @Test("Reverts all four fields to the template's CURRENT values, links it, keeps status; one named step; ⌘Z restores the edit")
    func revertAndUndo() throws {
        let (store, context, undo) = try makeStore()
        let (_, block, event) = materialised(store)
        store.move(event, by: 45 * 60)
        store.retitle(event, to: "Hard training")
        store.setFlexibility(event, to: .droppable)
        store.toggleDone(event)
        let edited = EventStore.RoutineValues(event)

        // The template changed since the instance was detached.
        block.startMinutes = 16 * 60 + 30
        block.duration = 60 * 60
        try context.save()

        #expect(RoutineInstance.status(of: event, in: context) == .edited(routineName: "Gym routine"))
        #expect(RoutineInstance.revert(event, store: store, calendar: calendar))
        #expect(undo.undoMenuTitle == "Undo Revert Instance to Routine")
        #expect(event.title == "Training")
        #expect(event.flexibility == .fixed)
        #expect(calendar.dateComponents([.hour, .minute], from: event.start) == DateComponents(hour: 16, minute: 30))
        #expect(event.duration == 3600)
        #expect(event.routineLink == .linked)
        #expect(event.status == .done, "status is a fact about the day, left alone")
        #expect(RoutineInstance.status(of: event, in: context) == nil)

        undo.undo()
        #expect(EventStore.RoutineValues(event) == edited)
        #expect(event.isDetached)
        #expect(event.status == .done)
    }

    @Test("The inspector copy is §13.4's and §13.6.4's, exactly")
    func copy() {
        #expect(RoutineInstance.editedLabel + " " + RoutineInstance.editedValue(routineName: "Gym routine")
                == "Edited — differs from Gym routine")
        #expect(RoutineInstance.revertActionTitle == "Revert to routine")
        #expect(RoutineInstance.releasedLine(routineName: "Gym routine") == "No longer part of Gym routine")
    }

    @Test("A linked instance has no status line and nothing to revert")
    func linkedHasNothing() throws {
        let (store, context, undo) = try makeStore()
        let (_, _, event) = materialised(store)
        #expect(RoutineInstance.status(of: event, in: context) == nil)
        #expect(!RoutineInstance.revert(event, store: store, calendar: calendar))
        #expect(undo.undoSteps.isEmpty)
    }

    @Test("The flag survives a delete and its undo (snapshot carries it)")
    func snapshotCarriesLink() throws {
        let (store, context, undo) = try makeStore()
        let (_, _, event) = materialised(store)
        store.move(event, by: 900)
        let id = event.id
        store.delete(event)
        undo.undo()
        #expect(events(context).first { $0.id == id }?.isDetached == true)
    }
}
