//
//  ResyncTests.swift
//  KadenceTests
//
//  Task P2-T44: components.md §13.7.3 and interactions.md §11.2 — the
//  detached count's scope and copy, the popover's dates (six then `+N`), and
//  Re-sync as ONE undo step.
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
private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }

@MainActor
private func events(_ context: ModelContext) -> [Event] {
    (try? context.fetch(FetchDescriptor<Event>(sortBy: [SortDescriptor(\.start)]))) ?? []
}

/// Gym 07:00–08:00 every day, materialised from `from` for `days` days
/// (`today` is set to `from`, so the past can be written for setup).
@MainActor
private func gym(_ store: EventStore, from: Date = today, days: Int = 60) -> (RoutineTemplate, RoutineBlock) {
    let block = RoutineBlock(title: "Gym", startMinutes: 7 * 60, duration: 3600)
    let template = RoutineTemplate(name: "Gym routine", activeWeekdays: Set(1...7), blocks: [block])
    store.context.insert(template)
    try? store.context.save()
    RoutineEngine.materialize(template: template, into: DateInterval(start: from, duration: Double(days) * 86400),
                              today: from, recordsUndo: false, store: store, calendar: calendar)
    return (template, block)
}

@MainActor
private func instance(on offset: Int, _ context: ModelContext) -> Event {
    events(context).first { calendar.isDate($0.start, inSameDayAs: day(offset)) }!
}

@MainActor
private func scope(_ template: RoutineTemplate, _ context: ModelContext) -> [Event] {
    RoutineResync.scope(of: template, in: context, today: today, visibleEnd: nil, calendar: calendar)
}

// MARK: - Scope and copy

@Suite("Re-sync — scope and copy (§13.7.3)")
@MainActor
struct ResyncScopeTests {

    @Test("Scope: detached instances of THIS template, today through the horizon; not past, not beyond, not linked, not released")
    func countScope() throws {
        let (store, context, _) = try makeStore()
        let (template, _) = gym(store, from: day(-3), days: 40)
        let (other, _) = gym(store, from: today, days: 3)

        for offset in [-2, 0, 5, 28, 30] { store.move(instance(on: offset, context), by: 900) }
        // Another template's detached instance never counts here.
        let otherInstance = events(context).first { $0.sourceID == other.id.uuidString }!
        store.move(otherInstance, by: 900)
        // A released instance is an ordinary event, not detached.
        instance(on: 6, context).routineLink = .released

        let days = scope(template, context).map { calendar.dateComponents([.day], from: today, to: $0.start).day! }
        // -2 is past; 30 is beyond today + 28 (horizon end is the start of day + 29).
        #expect(days == [0, 5, 28])
    }

    @Test("The visible range extends the scope with the horizon")
    func visibleRangeExtends() throws {
        let (store, context, _) = try makeStore()
        let (template, _) = gym(store, days: 50)
        store.move(instance(on: 40, context), by: 900)
        #expect(scope(template, context).isEmpty)
        let extended = RoutineResync.scope(of: template, in: context, today: today,
                                           visibleEnd: day(35), calendar: calendar)
        #expect(extended.count == 1)
    }

    @Test("Count copy: no 'this week', singular and plural, hidden at zero")
    func countCopy() {
        #expect(RoutineResync.countText(0) == nil)
        #expect(RoutineResync.countText(1) == "1 instance edited")
        #expect(RoutineResync.countText(3) == "3 instances edited")
        #expect(RoutineResync.actionTitle(1) == "Re-sync 1 instance")
        #expect(RoutineResync.actionTitle(3) == "Re-sync 3 instances")
    }

    @Test("Popover rows: real dates, up to six, then `+2 more` (G-034, P2-F17)")
    func popoverOverflow() throws {
        let (store, context, _) = try makeStore()
        let (template, _) = gym(store)
        for offset in [1, 2, 3, 4, 5, 6, 8, 10] { store.move(instance(on: offset, context), by: 900) }

        let rows = RoutineResync.dateRows(for: scope(template, context), calendar: calendar)
        #expect(rows.dates == ["Tue 6", "Wed 7", "Thu 8", "Fri 9", "Sat 10", "Sun 11"])
        #expect(rows.overflow == "+2 more")

        let six = RoutineResync.dateRows(for: Array(scope(template, context).prefix(6)), calendar: calendar)
        #expect(six.dates.count == 6)
        #expect(six.overflow == nil, "exactly six shows no +N")
    }

    @Test("A row names the pair's own day even if the instance was moved off it")
    func rowUsesPairDay() throws {
        let (store, context, _) = try makeStore()
        let (template, _) = gym(store)
        store.move(instance(on: 1, context), by: 20 * 3600)   // 07:00 Tue → 03:00 Wed
        #expect(RoutineResync.dateRows(for: scope(template, context), calendar: calendar).dates == ["Tue 6"])
    }
}

// MARK: - Apply

@Suite("Re-sync — one undo step (interactions.md §11.2)")
@MainActor
struct ResyncApplyTests {

    @Test("Re-sync writes the template's current values into every listed instance as ONE step; one ⌘Z restores them all")
    func singleStep() throws {
        let (store, context, undo) = try makeStore()
        let (template, block) = gym(store)
        let edited = [1, 3, 9].map { instance(on: $0, context) }
        for (index, event) in edited.enumerated() {
            store.move(event, by: Double(index + 1) * 900)
            store.retitle(event, to: "Gym \(index)")
        }
        edited[1].status = .skipped
        try context.save()
        let before = edited.map { (EventStore.RoutineValues($0), $0.routineLink, $0.status) }
        block.startMinutes = 6 * 60
        try context.save()
        let stepsBefore = undo.undoSteps.count

        let written = RoutineResync.apply(scope(template, context), store: store, calendar: calendar)

        #expect(written == 3)
        #expect(undo.undoSteps.count == stepsBefore + 1)
        #expect(undo.undoMenuTitle == "Undo Re-sync Routine")
        for event in edited {
            #expect(event.title == "Gym")
            #expect(calendar.component(.hour, from: event.start) == 6, "the template's CURRENT start")
            #expect(event.routineLink == .linked)
        }
        #expect(edited[1].status == .skipped, "status left alone")
        #expect(scope(template, context).isEmpty, "count hides at zero afterwards")

        undo.undo()
        for (event, old) in zip(edited, before) {
            #expect(EventStore.RoutineValues(event) == old.0)
            #expect(event.routineLink == old.1)
            #expect(event.status == old.2)
        }
        #expect(scope(template, context).count == 3)

        undo.redo()
        #expect(scope(template, context).isEmpty)
    }

    @Test("Re-sync never resurrects a deleted (tombstoned) instance")
    func noResurrection() throws {
        let (store, context, _) = try makeStore()
        let (template, _) = gym(store)
        let victim = instance(on: 2, context)
        let key = victim.externalID
        store.move(instance(on: 4, context), by: 900)
        store.delete(victim)

        RoutineResync.apply(scope(template, context), store: store, calendar: calendar)
        #expect(!events(context).contains { $0.externalID == key })
    }

    @Test("Nothing to re-sync records nothing")
    func emptyNoStep() throws {
        let (store, context, undo) = try makeStore()
        let (template, _) = gym(store)
        #expect(RoutineResync.apply(scope(template, context), store: store) == 0)
        #expect(undo.undoSteps.isEmpty)
    }
}
