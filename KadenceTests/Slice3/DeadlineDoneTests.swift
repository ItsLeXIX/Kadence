//
//  DeadlineDoneTests.swift
//  KadenceTests
//
//  PHASE3-SLICE3-PLAN.md task 7 — components.md §38; interactions.md §16.5:
//  Mark Done / Mark Not Done on a deadline with `markedDoneDueAt`; Skip
//  refused on every Moodle item and Done on openings and notices (§13.4's
//  pair); a done deadline moved by a sync keeps its mark, and says so.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

private typealias F = MoodleFixture

@MainActor
private func moodleEvent(_ kind: ImportKind, _ wording: MomentWording?, at text: String, in context: ModelContext) -> Event {
    let t = F.date(text)
    let e = Event(title: "Item", start: t, end: t, origin: .imported, sourceKey: .teal, sourceID: "moodle",
                  externalID: "\(UUID().uuidString)@moodle.technikum-wien.at")
    e.importKind = kind
    e.momentWording = wording
    context.insert(e)
    try? context.save()
    return e
}

@MainActor
struct DeadlineDoneTests {

    @Test("Mark Done sets .done and markedDoneDueAt = start; Mark Not Done clears both; one named undo step each")
    func markDone() throws {
        let container = try slice2MemoryContainer()
        let context = container.mainContext
        let undo = UndoStack()
        let store = EventStore(context: context, undo: undo)
        let deadline = moodleEvent(.deadline, .due, at: "2026-10-20 12:00", in: context)

        store.toggleDone(deadline)
        #expect(deadline.status == .done && deadline.markedDoneDueAt == deadline.start)
        #expect(undo.undoSteps.count == 1 && undo.undoActionName == "Mark Done")
        store.toggleDone(deadline)
        #expect(deadline.status == .scheduled && deadline.markedDoneDueAt == nil)
        #expect(undo.undoSteps.count == 2 && undo.undoActionName == "Mark Not Done")
        undo.undo()
        #expect(deadline.status == .done && deadline.markedDoneDueAt == deadline.start)
        undo.undo()
        #expect(deadline.status == .scheduled && deadline.markedDoneDueAt == nil)
        undo.redo()
        #expect(deadline.status == .done && deadline.markedDoneDueAt == deadline.start)
    }

    @Test("feedChanged E1 on a done 900008 → still done, the moved condition true; Mark Not Done then Done → false")
    func movedAfterDone() async throws {
        let rig = try FeedRig(now: F.date("2026-10-16 13:07"))
        try await rig.importFeed()
        let undo = UndoStack()
        let store = EventStore(context: rig.context, undo: undo)
        let e8 = try #require(rig.event("900008"))
        store.toggleDone(e8)
        #expect(!e8.dueTimeChangedAfterDone)
        await rig.sync(.feedChanged, at: F.date("2026-10-16 14:07"))
        let moved = try #require(rig.event("900008"))
        #expect(moved.status == .done && moved.dueTimeChangedAfterDone)
        #expect(moved.markedDoneDueAt == F.date("2026-10-20 12:00"))
        store.toggleDone(moved)
        store.toggleDone(moved)
        #expect(moved.status == .done && !moved.dueTimeChangedAfterDone && moved.markedDoneDueAt == moved.start)
        // A content change without a time change shows nothing.
        moved.importedDescription = "Edited upstream."
        #expect(!moved.dueTimeChangedAfterDone)
    }

    @Test("⌥⌘↩ on a deadline / opening / notice → refused, no write, no undo step; ⌘↩ on an opening or a notice → refused")
    func refusals() throws {
        let container = try slice2MemoryContainer()
        let context = container.mainContext
        let undo = UndoStack()
        let store = EventStore(context: context, undo: undo)
        let state = CalendarState()
        var sounds = 0
        state.playRefusalSound = { sounds += 1 }
        let deadline = moodleEvent(.deadline, .closes, at: "2026-10-14 12:30", in: context)
        let opening = moodleEvent(.opening, .opens, at: "2026-10-12 09:30", in: context)
        let notice = moodleEvent(.notice, nil, at: "2026-10-21 10:00", in: context)
        for event in [deadline, opening, notice] {
            let before = sounds
            // The MainWindow path: `if state.permits(.skip, …) { store.toggleSkipped(…) }`.
            if state.permits(.skip, on: event, now: TestClock.now) { store.toggleSkipped(event) }
            #expect(sounds == before + 1 && state.readOnlyEmphasis)
            #expect(event.status == .scheduled)
        }
        for event in [opening, notice] {
            let before = sounds
            if state.permits(.done, on: event, now: TestClock.now) { store.toggleDone(event) }
            #expect(sounds == before + 1 && event.status == .scheduled && event.markedDoneDueAt == nil)
        }
        #expect(undo.undoSteps.isEmpty)
        // The store refuses too, whatever path calls it.
        store.toggleDone(opening); store.toggleSkipped(deadline); store.toggleSkipped(notice)
        #expect(undo.undoSteps.isEmpty && opening.status == .scheduled && deadline.status == .scheduled)
        // Done on a deadline is allowed (no sound).
        let before = sounds
        #expect(state.permits(.done, on: deadline, now: TestClock.now) && sounds == before)
        // A CIS lecture keeps slice 1's rule: done and skip allowed.
        let lecture = Event(title: "SWQM-ILV", start: deadline.start, end: deadline.start + 5400, origin: .imported,
                            sourceID: "timetable")
        #expect(state.permits(.done, on: lecture) && state.permits(.skip, on: lecture))
        #expect(ReadOnlyGate.decide(.skip, origin: .imported, isCancelled: false, importKind: .deadline) == .refuse(sound: true))
        #expect(ReadOnlyGate.decide(.done, origin: .imported, isCancelled: false, importKind: .deadline) == .allow)
        #expect(ReadOnlyGate.decide(.delete, origin: .imported, isCancelled: false, importKind: .deadline) == .refuse(sound: true))
    }

    @Test("Done on a past deadline is allowed (history keeps Done)")
    func pastDeadline() throws {
        let container = try slice2MemoryContainer()
        let context = container.mainContext
        let undo = UndoStack()
        let store = EventStore(context: context, undo: undo)
        let state = CalendarState()
        let past = moodleEvent(.deadline, .closes, at: "2026-10-11 23:59", in: context)
        #expect(state.permits(.done, on: past, now: F.date("2026-10-16 10:00")))
        store.toggleDone(past)
        #expect(past.status == .done && past.markedDoneDueAt == past.start)
    }
}
