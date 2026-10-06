//
//  MenuBarSnoozeTests.swift
//  KadenceTests
//
//  components.md §16 (Snooze confirmation) / interactions.md §12's `⌥⌘↩` row —
//  task P2-T26. Two things are tested directly, with no menu bar UI launched:
//
//  1. `MenuBarFormatting.snoozeResult` — the pure string composition behind
//     the result row: `Moved to HH:mm` same-day, `Moved to tomorrow HH:mm`
//     once the shift crosses midnight. Driven with fixed `oldStart`/`newStart`
//     pairs rather than `EventStore.snooze`'s own offset, so this suite keeps
//     testing the formatting rule even if the placeholder constant changes.
//  2. `EventStore.snooze` itself, against a real in-memory SwiftData store
//     (the same pattern `EventCreationTests.swift` uses) — that it actually
//     shifts by its documented offset, registers exactly one named "Snooze"
//     undo step, and that undoing it restores the *exact* original
//     start/end, not an approximation.
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

/// `EventStore`'s verbs resolve their target by re-fetching `id` from the
/// context (see `EventStore.edit`'s own doc comment), so — same as
/// `TimeWindowStoreTests.swift`'s `makeSleepWindow(in:)` — a fixture event
/// must actually be inserted before a mutating verb can find and change it.
@discardableResult
@MainActor
private func makeEvent(
    _ title: String, start: Date, end: Date, in context: ModelContext, isLocked: Bool = false
) -> Event {
    let event = Event(title: title, start: start, end: end, origin: .manual, isLocked: isLocked)
    context.insert(event)
    try? context.save()
    return event
}

private let calendar = Calendar(identifier: .gregorian)
private let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!

private func time(_ hour: Int, _ minute: Int = 0, on base: Date = day) -> Date {
    calendar.date(byAdding: .minute, value: hour * 60 + minute, to: base)!
}

// MARK: - MenuBarFormatting.snoozeResult

@Suite("MenuBarFormatting.snoozeResult — components.md §16's result row text")
struct SnoozeResultFormattingTests {

    @Test("Same day: `Moved to HH:mm`, no day name")
    func sameDayFormatting() {
        let oldStart = time(19, 0)
        let newStart = time(19, 15)

        let text = MenuBarFormatting.snoozeResult(oldStart: oldStart, newStart: newStart, calendar: calendar)

        #expect(text == "Moved to 19:15")
    }

    @Test("Crossing midnight: `Moved to tomorrow HH:mm`")
    func nextDayFormatting() {
        // 23:50 shifted by the 15-minute placeholder offset lands at 00:05
        // the next calendar day — the exact boundary this rule exists for.
        let oldStart = time(23, 50)
        let newStart = oldStart.addingTimeInterval(EventStore.snoozeOffset)

        let text = MenuBarFormatting.snoozeResult(oldStart: oldStart, newStart: newStart, calendar: calendar)

        #expect(text == "Moved to tomorrow 00:05")
    }

    @Test("A shift that lands exactly on the next midnight still names the day")
    func exactMidnightBoundary() {
        let oldStart = time(23, 45)
        let newStart = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day))!

        let text = MenuBarFormatting.snoozeResult(oldStart: oldStart, newStart: newStart, calendar: calendar)

        #expect(text == "Moved to tomorrow 00:00")
    }
}

// MARK: - EventStore.snooze

@Suite("EventStore.snooze — the placeholder shift and its undo")
@MainActor
struct EventStoreSnoozeTests {

    @Test("Snoozing shifts start and end by the documented fixed offset")
    func shiftsByFixedOffset() throws {
        let (store, context, _) = try makeStore()
        let event = makeEvent("Gym", start: time(17, 30), end: time(18, 15), in: context)

        let result = store.snooze(event)

        #expect(result == .moved(to: time(17, 30).addingTimeInterval(EventStore.snoozeOffset)))
        #expect(event.start == time(17, 30).addingTimeInterval(EventStore.snoozeOffset))
        #expect(event.end == time(18, 15).addingTimeInterval(EventStore.snoozeOffset))
        // Duration is preserved — this is a shift, not a resize.
        #expect(event.end.timeIntervalSince(event.start) == 45 * 60)
    }

    @Test("Snoozing registers exactly one named 'Snooze' undo step")
    func registersNamedStep() throws {
        let (store, context, undo) = try makeStore()
        let event = makeEvent("Gym", start: time(17, 30), end: time(18, 15), in: context)

        store.snooze(event)

        #expect(undo.undoSteps.count == 1)
        #expect(undo.undoMenuTitle == "Undo Snooze")
    }

    @Test("Undo restores the exact original start and end")
    func undoRestoresExactly() throws {
        let (store, context, undo) = try makeStore()
        let originalStart = time(17, 30)
        let originalEnd = time(18, 15)
        let event = makeEvent("Gym", start: originalStart, end: originalEnd, in: context)

        store.snooze(event)
        #expect(event.start != originalStart, "sanity: the snooze must actually have moved it")

        undo.undo()

        #expect(event.start == originalStart)
        #expect(event.end == originalEnd)
    }

    @Test("Redo re-applies the same snooze after an undo")
    func redoReappliesShift() throws {
        let (store, context, undo) = try makeStore()
        let event = makeEvent("Gym", start: time(17, 30), end: time(18, 15), in: context)

        let newStart = try #require(store.snooze(event).movedTo)
        undo.undo()
        undo.redo()

        #expect(event.start == newStart)
    }

    @Test("A locked event is not moved, matching move(_:by:)'s own isMovable guard")
    func lockedEventUnaffected() throws {
        let (store, context, undo) = try makeStore()
        let originalStart = time(17, 30)
        let event = makeEvent("Fixed", start: originalStart, end: time(18, 15), in: context, isLocked: true)

        let result = store.snooze(event)

        #expect(result == .unchanged)
        #expect(event.start == originalStart)
        #expect(undo.undoSteps.isEmpty, "a no-op snooze must not push an undo step")
    }
}
