//
//  SnoozeMidnightTests.swift
//  KadenceTests
//
//  Task P2-T49: `screenshots/2/snooze-next-day.png` reads `Moved to tomorrow
//  00:05` while the NEXT block above it reads `23:50 – 01:20`. Against
//  components.md §16 ("must show where the block landed"; "across a day
//  boundary it names the day") and GAPS G-016 (the fixed 15-minute
//  placeholder, deliberately kept), the result row is right and the block
//  half was wrong: a snooze past midnight moved the event out of "today", so
//  it stopped being NEXT.
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

private func at(_ hour: Int, _ minute: Int, day: Int = 5) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

@MainActor
private func all(_ context: ModelContext) -> [Event] {
    (try? context.fetch(FetchDescriptor<Event>(sortBy: [SortDescriptor(\.start)]))) ?? []
}

@Suite("Snooze across midnight (components.md §16, G-016)")
@MainActor
struct SnoozeMidnightTests {

    /// The capture's own shape: `Prep: relational algebra` at 23:50–01:20,
    /// snoozed at 23:45 by G-016's fixed 15 minutes.
    private func snoozed() throws -> (EventStore, ModelContext, UndoStack, Event, Date, String) {
        let (store, context, undo) = try makeStore()
        let prep = Event(title: "Prep: relational algebra", start: at(23, 50), end: at(1, 20, day: 6),
                         origin: .planned, sourceKey: .purple)
        context.insert(prep)
        try context.save()
        let oldStart = prep.start
        let newStart = try #require(store.snooze(prep).movedTo)
        let text = MenuBarFormatting.snoozeResult(oldStart: oldStart, newStart: newStart)
        return (store, context, undo, prep, newStart, text)
    }

    @Test("The result row is right: G-016's +15 lands at 00:05 tomorrow, and it says so")
    func rowIsRight() throws {
        let (_, _, _, prep, newStart, text) = try snoozed()
        #expect(newStart == at(0, 5, day: 6))
        #expect(prep.start == at(0, 5, day: 6))
        #expect(prep.end == at(1, 35, day: 6), "the duration is kept")
        #expect(text == "Moved to tomorrow 00:05")
    }

    @Test("Reproduced: without the pin, the snoozed block is no longer NEXT once it crosses midnight")
    func reproducesTheMismatch() throws {
        let (_, context, _, prep, _, _) = try snoozed()
        let plain = NextUpProvider.evaluate(events: all(context), now: at(23, 45))
        #expect(plain.next?.id != prep.id,
                "NEXT drops the block the row is talking about, so the two halves can't agree")
    }

    @Test("Fixed: while the confirmation holds, NEXT is the snoozed block at the time the row names")
    func pinnedAgrees() throws {
        let (_, context, _, prep, newStart, text) = try snoozed()
        let now = at(23, 45)
        let pinned = NextUpProvider.pinning(
            NextUpProvider.evaluate(events: all(context), now: now),
            events: all(context), to: (prep.id, newStart))
        let next = try #require(pinned.next)
        #expect(next.id == prep.id)
        #expect(!pinned.isLate)
        let meta = MenuBarFormatting.nextMeta(for: next, now: now, isLate: pinned.isLate)
        #expect(meta.hasPrefix("00:05 – 01:35"), "the block reads where it landed: \(meta)")
        #expect(text.hasSuffix(MenuBarFormatting.time(next.start)), "row and block name the same start")
    }

    @Test("After Undo the pin no longer applies and the block is back at 23:50")
    func undoReleasesThePin() throws {
        let (_, context, undo, prep, newStart, _) = try snoozed()
        undo.undo()
        let result = NextUpProvider.pinning(
            NextUpProvider.evaluate(events: all(context), now: at(23, 45)),
            events: all(context), to: (prep.id, newStart))
        #expect(result.next?.id == prep.id)
        #expect(result.next?.start == at(23, 50))
    }

    @Test("A same-day snooze is unchanged: the pin and the plain result agree")
    func sameDayUnchanged() throws {
        let (store, context, _) = try makeStore()
        let gym = Event(title: "Gym", start: at(17, 30), end: at(18, 15), origin: .routine)
        let later = Event(title: "Reading", start: at(21, 0), end: at(21, 30), origin: .routine)
        context.insert(gym)
        context.insert(later)
        try context.save()
        let newStart = try #require(store.snooze(gym).movedTo)
        let now = at(17, 20)
        let plain = NextUpProvider.evaluate(events: all(context), now: now)
        let pinned = NextUpProvider.pinning(plain, events: all(context), to: (gym.id, newStart))
        #expect(plain.next?.id == gym.id)
        #expect(pinned.next?.id == gym.id)
        #expect(pinned.restOfToday.map(\.id) == plain.restOfToday.map(\.id))
        #expect(MenuBarFormatting.snoozeResult(oldStart: at(17, 30), newStart: newStart) == "Moved to 17:45")
    }
}
