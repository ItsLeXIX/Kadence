//
//  NextUpProviderTests.swift
//  KadenceTests
//
//  components.md §15 (the menu bar extra) / DECISIONS.md 2026-09-10 "Menu bar
//  requirement split between status item and popover." `NextUpProvider` is
//  the pure derivation behind both the status item and the popover — these
//  tests drive it directly against fixed fixture events and an injected
//  "now", with no menu bar UI launched, the same in-memory ModelContainer/
//  ModelContext pattern `ConflictEngineTests.swift` already uses.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: Event.self, Place.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return ModelContext(container)
}

private let calendar = Calendar(identifier: .gregorian)
private let day = calendar.date(from: DateComponents(year: 2026, month: 9, day: 18))!
private let tomorrow = calendar.date(byAdding: .day, value: 1, to: day)!

/// `hour:minute` of `day`, this suite's whole vocabulary for building fixture
/// times — every scenario below reads as a clock time, not an offset.
private func time(_ hour: Int, _ minute: Int = 0, on base: Date = day) -> Date {
    calendar.date(byAdding: .minute, value: hour * 60 + minute, to: base)!
}

private func makeEvent(
    _ title: String, start: Date, end: Date,
    status: EventStatus = .scheduled, isAllDay: Bool = false
) -> Event {
    Event(title: title, start: start, end: end, isAllDay: isAllDay, origin: .manual, status: status)
}

@MainActor
private func insert(_ context: ModelContext, _ events: [Event]) throws {
    for event in events { context.insert(event) }
    try context.save()
}

// MARK: - Normal / Late / Empty

@Suite("NextUpProvider.evaluate — normal, late, empty")
@MainActor
struct NextUpProviderStateTests {

    @Test("Normal: the next item's start is still in the future")
    func normalNextInFuture() throws {
        let context = try makeContext()
        let training = makeEvent("Training", start: time(17, 30), end: time(18, 15))
        try insert(context, [training])

        let result = NextUpProvider.evaluate(events: [training], now: time(9), calendar: calendar)

        #expect(result.next?.id == training.id)
        #expect(result.isLate == false)
        #expect(result.restOfToday.isEmpty)
    }

    @Test("Late: the next item's start has already passed and it is not done")
    func lateNextStartPassed() throws {
        let context = try makeContext()
        let gym = makeEvent("Gym", start: time(17, 30), end: time(18, 15))
        try insert(context, [gym])

        // 12 minutes after start — still not done, not skipped.
        let result = NextUpProvider.evaluate(events: [gym], now: time(17, 42), calendar: calendar)

        #expect(result.next?.id == gym.id)
        #expect(result.isLate == true)
    }

    @Test("An item exactly at `now` counts as late, not normal")
    func lateBoundaryIsInclusive() throws {
        let context = try makeContext()
        let event = makeEvent("Standup", start: time(9), end: time(9, 15))
        try insert(context, [event])

        let result = NextUpProvider.evaluate(events: [event], now: time(9), calendar: calendar)

        #expect(result.isLate == true)
    }

    @Test("Empty: nothing scheduled for today at all")
    func emptyNothingScheduled() throws {
        let context = try makeContext()
        // A future event exists, but tomorrow — not today.
        let tomorrowEvent = makeEvent("Tomorrow", start: time(9, 0, on: tomorrow), end: time(10, 0, on: tomorrow))
        try insert(context, [tomorrowEvent])

        let result = NextUpProvider.evaluate(events: [tomorrowEvent], now: time(8), calendar: calendar)

        #expect(result.next == nil)
        #expect(result.isLate == false)
        #expect(result.restOfToday.isEmpty)
    }

    @Test("Empty: everything today is already done or skipped")
    func emptyEverythingResolved() throws {
        let context = try makeContext()
        let done = makeEvent("Done thing", start: time(9), end: time(10), status: .done)
        let skipped = makeEvent("Skipped thing", start: time(11), end: time(12), status: .skipped)
        try insert(context, [done, skipped])

        let result = NextUpProvider.evaluate(events: [done, skipped], now: time(8), calendar: calendar)

        #expect(result.next == nil)
        #expect(result.restOfToday.isEmpty)
    }

    @Test("All-day events are never the next item")
    func allDayEventsExcluded() throws {
        let context = try makeContext()
        let allDay = makeEvent("Deadline", start: time(0), end: time(23, 59), isAllDay: true)
        let timed = makeEvent("Training", start: time(17, 30), end: time(18, 15))
        try insert(context, [allDay, timed])

        let result = NextUpProvider.evaluate(events: [allDay, timed], now: time(8), calendar: calendar)

        #expect(result.next?.id == timed.id)
    }
}

// MARK: - Rest of today ordering

@Suite("NextUpProvider.evaluate — rest-of-today ordering")
@MainActor
struct NextUpProviderRestOrderingTests {

    @Test("Rest-of-today is every remaining event, in start order, after NEXT")
    func restOfTodayIsOrdered() throws {
        let context = try makeContext()
        let dinner = makeEvent("Dinner", start: time(20), end: time(21))
        let training = makeEvent("Training", start: time(17, 30), end: time(18, 15))
        let codeReview = makeEvent("Code review", start: time(18, 30), end: time(19))
        // Inserted out of order on purpose — the provider must sort by start,
        // not trust caller order.
        try insert(context, [dinner, training, codeReview])

        let result = NextUpProvider.evaluate(
            events: [dinner, training, codeReview], now: time(9), calendar: calendar)

        #expect(result.next?.id == training.id)
        #expect(result.restOfToday.map(\.id) == [codeReview.id, dinner.id])
    }

    @Test("A done/skipped event never appears in rest-of-today either")
    func restOfTodayExcludesResolved() throws {
        let context = try makeContext()
        let training = makeEvent("Training", start: time(17, 30), end: time(18, 15))
        let skippedDinner = makeEvent("Dinner", start: time(20), end: time(21), status: .skipped)
        try insert(context, [training, skippedDinner])

        let result = NextUpProvider.evaluate(
            events: [training, skippedDinner], now: time(9), calendar: calendar)

        #expect(result.restOfToday.isEmpty)
    }
}

// MARK: - `restDisplay` — the `popoverMaxRestRows` boundary

@Suite("NextUpProvider.restDisplay — the +N more cap")
@MainActor
struct NextUpProviderRestDisplayTests {

    private func makeRest(_ count: Int) -> [Event] {
        (0..<count).map { i in
            makeEvent("Item \(i)", start: time(12 + i), end: time(12 + i, 30))
        }
    }

    @Test("Exactly at the cap: every row shows, no +N more line")
    func exactlyAtCap() throws {
        let cap = Tokens.Size.popoverMaxRestRows
        let rest = makeRest(cap)

        let display = NextUpProvider.restDisplay(rest, cap: cap)

        #expect(display.rows.count == cap)
        #expect(display.moreCount == 0)
    }

    @Test("One over the cap: the cap's worth of rows, plus +1 more")
    func oneOverCap() throws {
        let cap = Tokens.Size.popoverMaxRestRows
        let rest = makeRest(cap + 1)

        let display = NextUpProvider.restDisplay(rest, cap: cap)

        #expect(display.rows.count == cap)
        #expect(display.rows.map(\.title) == rest.prefix(cap).map(\.title))
        #expect(display.moreCount == 1)
    }

    @Test("Well under the cap: no +N more line")
    func underCap() throws {
        let cap = Tokens.Size.popoverMaxRestRows
        let rest = makeRest(max(0, cap - 2))

        let display = NextUpProvider.restDisplay(rest, cap: cap)

        #expect(display.rows.count == rest.count)
        #expect(display.moreCount == 0)
    }

    @Test("The real Tokens.Size.popoverMaxRestRows default is used when no cap is passed")
    func defaultCapMatchesToken() throws {
        let rest = makeRest(Tokens.Size.popoverMaxRestRows + 3)

        let display = NextUpProvider.restDisplay(rest)

        #expect(display.rows.count == Tokens.Size.popoverMaxRestRows)
        #expect(display.moreCount == 3)
    }
}
