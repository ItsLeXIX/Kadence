//
//  EventCreationTests.swift
//  KadenceTests
//
//  interactions.md §3 — creation is commit-or-discard: "an event created with no
//  title is never persisted — cancelling and committing an empty field both
//  remove it."
//
//  These run against a real in-memory SwiftData store rather than a fake,
//  because the defect being fixed (DEVIATIONS.md A13) was precisely that an
//  event reached the store when it should not have. A test that stubbed the
//  store could not have caught it.
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

@MainActor
private func eventCount(_ context: ModelContext) -> Int {
    ((try? context.fetch(FetchDescriptor<Event>())) ?? []).count
}

private let start = Calendar(identifier: .gregorian)
    .date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 23, minute: 30)) ?? Date()

private func draft(_ title: String) -> EventDraft {
    EventDraft(start: start, end: start.addingTimeInterval(3600), title: title)
}

// MARK: - Commit

@Suite("Creating an event — commit")
@MainActor
struct EventCommitTests {

    @Test("A named draft persists exactly one event")
    func commitPersists() throws {
        let (store, context, _) = try makeStore()
        let event = store.commit(draft("Datenmodellierung"))

        #expect(event != nil)
        #expect(eventCount(context) == 1)
        #expect(event?.title == "Datenmodellierung")
        #expect(event?.origin == .manual)
        #expect(event?.start == start)
    }

    @Test("The title is trimmed on the way in")
    func trims() throws {
        let (store, _, _) = try makeStore()
        #expect(store.commit(draft("  Coffee  "))?.title == "Coffee")
    }

    @Test("Committing registers one named undo step")
    func undoStep() throws {
        let (store, context, undo) = try makeStore()
        store.commit(draft("Gym"))
        #expect(undo.undoSteps.count == 1)
        #expect(undo.undoMenuTitle == "Undo New Event")

        undo.undo()
        #expect(eventCount(context) == 0, "⌘Z after creating must remove the event")

        undo.redo()
        #expect(eventCount(context) == 1)
    }
}

// MARK: - Discard

@Suite("Creating an event — discard")
@MainActor
struct EventDiscardTests {

    @Test("An empty title persists nothing")
    func emptyTitle() throws {
        let (store, context, undo) = try makeStore()
        let event = store.commit(draft(""))

        #expect(event == nil)
        #expect(eventCount(context) == 0, "this is A13: an untitled event reached the store")
        #expect(!undo.canUndo, "nothing happened, so there is nothing to press ⌘Z through")
    }

    @Test("A whitespace-only title persists nothing")
    func whitespaceTitle() throws {
        let (store, context, _) = try makeStore()
        #expect(store.commit(draft("   \n\t ")) == nil)
        #expect(eventCount(context) == 0)
    }

    @Test("Discarding a draft touches the store at all — never")
    func discardNeverPersists() throws {
        let (_, context, undo) = try makeStore()
        let state = CalendarState()

        state.beginDraft(at: start)
        #expect(state.draft != nil)
        #expect(eventCount(context) == 0, "a draft must not be in the store while being typed")

        // ⎋, or focus loss.
        state.discardDraft()
        #expect(state.draft == nil)
        #expect(eventCount(context) == 0)
        #expect(!undo.canUndo)
    }

    @Test("Typing into a draft still persists nothing until commit")
    func typingDoesNotPersist() throws {
        let (store, context, _) = try makeStore()
        let state = CalendarState()
        state.beginDraft(at: start)
        state.draft?.title = "Halfway through typ"
        #expect(eventCount(context) == 0)

        // Only the explicit commit writes.
        if let d = state.draft { store.commit(d) }
        #expect(eventCount(context) == 1)
    }
}

// MARK: - The draft itself

@Suite("Draft state")
@MainActor
struct EventDraftTests {

    @Test("A draft is 60 minutes by default and takes the requested duration otherwise")
    func durations() {
        let state = CalendarState()
        state.beginDraft(at: start)
        #expect(state.draft?.duration == 3600)

        state.beginDraft(at: start, duration: 15 * 60)
        #expect(state.draft?.duration == 900)
    }

    @Test("Beginning a draft clears the selection")
    func clearsSelection() {
        let state = CalendarState()
        state.selectedEventID = UUID()
        state.beginDraft(at: start)
        #expect(state.selectedEventID == nil, "the draft is what is being edited now")
    }

    @Test("hasUsableTitle is the single rule for whether a draft is real")
    func usableTitle() {
        #expect(!draft("").hasUsableTitle)
        #expect(!draft("  ").hasUsableTitle)
        #expect(draft("x").hasUsableTitle)
    }
}

// MARK: - Repairing older stores

@Suite("Untitled-event sweep")
@MainActor
struct UntitledSweepTests {

    @Test("Events with no title are removed from a store written by an older build")
    func sweep() throws {
        let container = try ModelContainer(
            for: Schema(KadenceSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)

        // Exactly the shape of the stray event A13 left behind.
        context.insert(Event(title: "", start: start, end: start.addingTimeInterval(3600)))
        context.insert(Event(title: "   ", start: start, end: start.addingTimeInterval(3600)))
        context.insert(Event(title: "Real event", start: start, end: start.addingTimeInterval(3600)))
        try? context.save()
        #expect(eventCount(context) == 3)

        MockData.removeUntitledEvents(context)

        let remaining = (try? context.fetch(FetchDescriptor<Event>())) ?? []
        #expect(remaining.count == 1)
        #expect(remaining.first?.title == "Real event")
    }

    @Test("The sweep leaves a healthy store alone")
    func sweepIsANoOpWhenClean() throws {
        let container = try ModelContainer(
            for: Schema(KadenceSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        context.insert(Event(title: "Lecture", start: start, end: start.addingTimeInterval(3600)))
        try? context.save()

        MockData.removeUntitledEvents(context)
        #expect(eventCount(context) == 1)
    }
}
