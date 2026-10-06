//
//  SnoozeProtectedTests.swift
//  KadenceTests
//
//  Task P2-B1: components.md §16 (amended 2026-10-06, G-046) — a snooze never
//  lands in protected time. G-016's +15 placeholder is kept; a destination
//  that strictly overlaps a `.protected` span writes nothing, pushes no undo
//  step, and the popover's result row reads `Not moved — 00:05 is inside
//  Sleep (protected)` with no `Undo`.
//

import Testing
import Foundation
import SwiftData
import SwiftUI   // `KeyPress` keys and modifiers (`.return`, `.command`)
@testable import Kadence

extension EventStore.SnoozeResult {
    /// The landed start for `.moved`, nil otherwise — so the older tests
    /// that only care about a successful shift can `#require` it.
    var movedTo: Date? {
        if case .moved(let date) = self { return date }
        return nil
    }
}

/// Mon 5 Oct 2026 (Tue 6 Oct is the fixtures' non-template day).
private func at(_ hour: Int, _ minute: Int, day: Int = 5) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

@MainActor
private func makeStore(windows: [TimeWindow]) throws -> (EventStore, ModelContext, UndoStack) {
    let container = try ModelContainer(
        for: Schema(KadenceSchema.models),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    windows.forEach(context.insert)
    try context.save()
    let undo = UndoStack()
    return (EventStore(context: context, undo: undo), context, undo)
}

/// The seeded windows' shapes (`MockData.makeTimeWindows`): Sleep 22:00–07:00
/// daily, Lunch 12:00–13:00 Mon/Wed/Fri.
private func sleep(label: String = "Sleep") -> TimeWindow {
    TimeWindow(weekdays: Set(1...7), startMinutes: 22 * 60, endMinutes: 7 * 60, kind: .protected, label: label)
}
private func lunch() -> TimeWindow {
    TimeWindow(weekdays: [2, 4, 6], startMinutes: 12 * 60, endMinutes: 13 * 60, kind: .protected, label: "Lunch")
}

@MainActor
private func insert(_ title: String, _ start: Date, _ end: Date, in context: ModelContext) throws -> Event {
    let event = Event(title: title, start: start, end: end, origin: .planned, sourceKey: .purple)
    context.insert(event)
    try context.save()
    return event
}

@Suite("A snooze never lands in protected time (components.md §16, G-046)")
@MainActor
struct SnoozeProtectedTests {

    @Test("23:50 with Sleep: refused at 00:05, store and undo stack unchanged, row text exact")
    func refusedIntoSleep() throws {
        let (store, context, undo) = try makeStore(windows: [sleep()])
        let prep = try insert("Prep: relational algebra", at(23, 50), at(1, 20, day: 6), in: context)

        let result = store.snooze(prep)

        #expect(result == .refused(start: at(0, 5, day: 6), windowLabel: "Sleep"))
        #expect(prep.start == at(23, 50))
        #expect(prep.end == at(1, 20, day: 6))
        #expect(undo.undoSteps.isEmpty, "a refusal records no undo step")
        let row = try #require(MenuBarPopoverView.SnoozeConfirmation.make(
            for: prep, oldStart: at(23, 50), result: result))
        #expect(row.text == "Not moved — 00:05 is inside Sleep (protected)")
        #expect(row.isRefusal, "no Undo on a refusal")
        #expect(row.expectedStart == at(23, 50), "the row stays matched to NEXT at its unchanged start")
    }

    @Test("Mon 11:50 against Lunch: refused")
    func refusedIntoLunch() throws {
        let (store, context, undo) = try makeStore(windows: [sleep(), lunch()])
        let errand = try insert("Errand", at(11, 50), at(12, 20), in: context)
        #expect(store.snooze(errand) == .refused(start: at(12, 5), windowLabel: "Lunch"))
        #expect(errand.start == at(11, 50))
        #expect(undo.undoSteps.isEmpty)
    }

    @Test("17:30 with nothing protected after it: moved to 17:45, as before")
    func movesWhenClear() throws {
        let (store, context, undo) = try makeStore(windows: [sleep(), lunch()])
        let training = try insert("Training", at(17, 30), at(18, 15), in: context)
        let result = store.snooze(training)
        #expect(result == .moved(to: at(17, 45)))
        #expect(training.start == at(17, 45))
        #expect(undo.undoMenuTitle == "Undo Snooze")
        let row = try #require(MenuBarPopoverView.SnoozeConfirmation.make(
            for: training, oldStart: at(17, 30), result: result))
        #expect(row.text == "Moved to 17:45")
        #expect(!row.isRefusal)
    }

    @Test("Touching endpoints are not an overlap: ending exactly at 22:00 moves")
    func touchingIsNotOverlap() throws {
        let (store, context, _) = try makeStore(windows: [sleep()])
        let e = try insert("Reading", at(21, 0), at(21, 45), in: context)
        #expect(store.snooze(e) == .moved(to: at(21, 15)))
    }

    @Test("Only .protected refuses: a low-energy window over the destination doesn't")
    func onlyProtected() throws {
        let low = TimeWindow(weekdays: Set(1...7), startMinutes: 22 * 60, endMinutes: 7 * 60,
                             kind: .lowEnergy, label: "Low energy")
        let (store, context, _) = try makeStore(windows: [low])
        let prep = try insert("Prep", at(23, 50), at(1, 20, day: 6), in: context)
        #expect(store.snooze(prep) == .moved(to: at(0, 5, day: 6)))
    }

    @Test("Empty label → `inside a protected window`")
    func emptyLabel() throws {
        let (store, context, _) = try makeStore(windows: [sleep(label: "")])
        let prep = try insert("Prep", at(23, 50), at(1, 20, day: 6), in: context)
        let result = store.snooze(prep)
        #expect(result == .refused(start: at(0, 5, day: 6), windowLabel: ""))
        let row = try #require(MenuBarPopoverView.SnoozeConfirmation.make(
            for: prep, oldStart: at(23, 50), result: result))
        #expect(row.text == "Not moved — 00:05 is inside a protected window")
    }

    @Test("`⌥⌘↩` takes the same path as the button: the key maps to .snooze, and the shared perform refuses")
    func keyTakesTheSamePath() throws {
        // interactions.md §12: `⌥⌘↩` → Snooze. In `MenuBarPopoverView` both
        // `handleKey`'s `.snooze` and the button's `perform(.snooze)` call
        // `performSnooze`, which is `SnoozeConfirmation.perform` — tested here.
        #expect(MenuBarPopoverKeys.action(key: .return, modifiers: [.command, .option], focus: 0, rowCount: 1) == .snooze)
        #expect(MenuBarPopoverKeys.actionButtons(isLate: false).contains { $0.kind == .snooze })

        let (store, context, undo) = try makeStore(windows: [sleep()])
        let prep = try insert("Prep: relational algebra", at(23, 50), at(1, 20, day: 6), in: context)
        let row = try #require(MenuBarPopoverView.SnoozeConfirmation.perform(prep, store: store))
        #expect(row.text == "Not moved — 00:05 is inside Sleep (protected)")
        #expect(row.isRefusal)
        #expect(prep.start == at(23, 50))
        #expect(undo.undoSteps.isEmpty)
    }

    @Test("The overlap test checks both days of an overnight window")
    func overnightBothDays() {
        let w = sleep()
        // Fully in the morning half (the day after the window's start).
        #expect(EventStore.protectedWindow(overlapping: at(5, 0, day: 6), at(5, 30, day: 6), windows: [w]) === w)
        // Fully in the evening half.
        #expect(EventStore.protectedWindow(overlapping: at(22, 30), at(23, 0), windows: [w]) === w)
        // Clear of both: 07:00–21:00 touches neither.
        #expect(EventStore.protectedWindow(overlapping: at(7, 0), at(22, 0), windows: [w]) == nil)
    }
}
