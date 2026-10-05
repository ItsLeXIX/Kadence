//
//  RoutineRematerializationTests.swift
//  KadenceTests
//
//  Task P2-T41: components.md §13.6.3 (the per-pair table), §13.6.4
//  (withdrawal, folded into the causing undo step), §13.6.5 (never the past)
//  and §13.7.4 (tombstones). Real in-memory containers throughout, per
//  DECISIONS.md 2026-09-10: persistence bugs only show up against a real
//  store.
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

private let mon = 2, tue = 3, wed = 4, sat = 7

/// Monday 5 October 2026, 00:00 UTC. "Today" in every test here.
private let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!
private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
/// Two weeks from today: Mon 5 – Sun 18 Oct.
private let twoWeeks = DateInterval(start: today, end: day(14))

@MainActor
private func events(_ context: ModelContext) -> [Event] {
    (try? context.fetch(FetchDescriptor<Event>(sortBy: [SortDescriptor(\.start)]))) ?? []
}

@MainActor
private func tombstones(_ context: ModelContext) -> [RoutineTombstone] {
    (try? context.fetch(FetchDescriptor<RoutineTombstone>())) ?? []
}

@MainActor
private func windows(_ context: ModelContext) -> [TimeWindow] {
    (try? context.fetch(FetchDescriptor<TimeWindow>())) ?? []
}

@MainActor
@discardableResult
private func materialize(_ template: RoutineTemplate, _ store: EventStore,
                         recordsUndo: Bool = true,
                         isDetached: @escaping @MainActor (Event) -> Bool = { _ in false }) -> Int {
    RoutineEngine.materialize(
        template: template, into: twoWeeks, timeWindows: windows(store.context),
        today: today, recordsUndo: recordsUndo, store: store, calendar: calendar,
        isDetached: isDetached)
}

/// A one-block template on Mon/Wed/Sat: Gym 07:00–08:00, `.shiftable`.
@MainActor
private func gymTemplate(_ context: ModelContext, weekdays: Set<Int> = [mon, wed, sat]) -> (RoutineTemplate, RoutineBlock) {
    let gym = RoutineBlock(title: "Gym", startMinutes: 7 * 60, duration: 3600,
                           flexibility: .shiftable, shiftableMinutes: 30)
    let template = RoutineTemplate(name: "Gym routine", activeWeekdays: weekdays, blocks: [gym])
    context.insert(template)
    try? context.save()
    return (template, gym)
}

/// Snapshot of what's on the calendar, for exact before/after comparisons:
/// id, title, start, end, flexibility, status.
private struct Row: Hashable {
    let id: UUID, title: String, start: Date, end: Date, flexibility: Flexibility, status: EventStatus
}
@MainActor
private func rows(_ context: ModelContext) -> Set<Row> {
    Set(events(context).map {
        Row(id: $0.id, title: $0.title, start: $0.start, end: $0.end,
            flexibility: $0.flexibility, status: $0.status)
    })
}

private func at(_ date: Date, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(byAdding: .minute, value: hour * 60 + minute, to: calendar.startOfDay(for: date))!
}

// MARK: - §13.6.3, the per-pair table

@Suite("Re-materialisation — the §13.6.3 per-pair table")
@MainActor
struct PerPairTableTests {

    @Test("Row 1 — no event, no tombstone: create")
    func createsMissingPair() throws {
        let (store, context, _) = try makeStore()
        let (template, _) = gymTemplate(context)
        // Mon 5, Wed 7, Sat 10, Mon 12, Wed 14, Sat 17.
        #expect(materialize(template, store) == 6)
        #expect(events(context).map(\.start) == [
            at(day(0), 7), at(day(2), 7), at(day(5), 7), at(day(7), 7), at(day(9), 7), at(day(12), 7)])
    }

    @Test("Row 2 — exists, not detached: update start, end, title and flexibility to the template's current values")
    func updatesUntouched() throws {
        let (store, context, _) = try makeStore()
        let (template, gym) = gymTemplate(context)
        materialize(template, store)
        let ids = Set(events(context).map(\.id))

        gym.startMinutes = 7 * 60 + 30
        gym.duration = 45 * 60
        gym.title = "Gym (short)"
        gym.flexibility = .droppable
        try context.save()

        #expect(materialize(template, store) == 0, "an update creates nothing")
        #expect(Set(events(context).map(\.id)) == ids, "updated in place: same rows, same ids")
        for event in events(context) {
            #expect(calendar.component(.hour, from: event.start) == 7)
            #expect(calendar.component(.minute, from: event.start) == 30)
            #expect(event.duration == 45 * 60)
            #expect(event.title == "Gym (short)")
            #expect(event.flexibility == .droppable)
        }
    }

    @Test("Row 2 — an update carries status (done / skipped) forward unchanged")
    func updateKeepsStatus() throws {
        let (store, context, _) = try makeStore()
        let (template, gym) = gymTemplate(context)
        materialize(template, store)
        let all = events(context)
        all[0].status = .done
        all[1].status = .skipped
        try context.save()

        gym.startMinutes = 8 * 60
        materialize(template, store)

        let after = events(context)
        #expect(after[0].status == .done)
        #expect(after[1].status == .skipped)
        #expect(after.allSatisfy { calendar.component(.hour, from: $0.start) == 8 })
    }

    @Test("Row 3 — exists, detached: left completely alone")
    func leavesDetached() throws {
        let (store, context, _) = try makeStore()
        let (template, gym) = gymTemplate(context)
        materialize(template, store)
        let pinned = events(context)[1]
        let pinnedID = pinned.id
        pinned.start = at(day(2), 9)
        pinned.end = at(day(2), 10)
        try context.save()

        gym.startMinutes = 6 * 60
        // The P2-T43 seam, overridden: only `pinned` counts as detached.
        materialize(template, store, isDetached: { $0.id == pinnedID })

        for event in events(context) {
            let expectedHour = event.id == pinnedID ? 9 : 6
            #expect(calendar.component(.hour, from: event.start) == expectedHour)
        }
    }

    @Test("Row 4 — tombstoned: left deleted, not recreated")
    func leavesTombstoned() throws {
        let (store, context, _) = try makeStore()
        let (template, _) = gymTemplate(context)
        materialize(template, store)
        let victim = events(context)[0]
        let victimKey = victim.externalID
        store.delete(victim)

        #expect(materialize(template, store) == 0)
        #expect(events(context).count == 5)
        #expect(!events(context).contains { $0.externalID == victimKey })
    }

    @Test("Row 5 — the template no longer produces the pair: withdrawn (§13.6.4)")
    func withdrawsUnproduced() throws {
        let (store, context, _) = try makeStore()
        let (template, _) = gymTemplate(context)
        materialize(template, store)
        template.activeWeekdays = [mon, wed]
        try context.save()

        let removed = RoutineEngine.withdraw(
            template: template, today: today, store: store, calendar: calendar)
        #expect(removed == 2, "Sat 10 and Sat 17")
        #expect(events(context).allSatisfy { calendar.component(.weekday, from: $0.start) != sat })
    }

    @Test("A pair that exists but is now refused is not updated by materialize; withdraw removes it")
    func refusedExistingIsWithdrawnNotUpdated() throws {
        let (store, context, _) = try makeStore()
        let (template, gym) = gymTemplate(context, weekdays: [mon])
        materialize(template, store)
        context.insert(TimeWindow(weekdays: [mon], startMinutes: 12 * 60, endMinutes: 13 * 60,
                                  kind: .protected, label: "Lunch"))
        gym.startMinutes = 12 * 60
        try context.save()

        materialize(template, store)
        #expect(events(context).allSatisfy { calendar.component(.hour, from: $0.start) == 7 },
                "no instance is ever written into a protected window")
        RoutineEngine.withdraw(template: template, timeWindows: windows(context),
                               today: today, store: store, calendar: calendar)
        #expect(events(context).isEmpty)
    }
}

// MARK: - §13.6.4 withdrawal, folded into the causing step

@Suite("Withdrawal — one undo step with its cause (§13.6.4, interactions.md §11.1.1)")
@MainActor
struct WithdrawalUndoTests {

    @Test("Weekday off: future instances go in the same step; ⌘Z restores template + instances exactly; ⌘⇧Z removes them again")
    func weekdayOff() throws {
        let (store, context, undo) = try makeStore()
        let (template, _) = gymTemplate(context)
        materialize(template, store, recordsUndo: false)
        events(context).first { calendar.component(.weekday, from: $0.start) == sat }?.status = .skipped
        try context.save()
        let before = rows(context)

        RoutineTemplateStore(context: context, undo: undo)
            .setWeekday(sat, active: false, in: template, today: today, calendar: calendar)

        #expect(undo.undoSteps.count == 1)
        #expect(undo.undoMenuTitle == "Undo Remove Saturday from Routine")
        #expect(events(context).count == 4)
        #expect(!template.activeWeekdays.contains(sat))

        undo.undo()
        #expect(template.activeWeekdays.contains(sat))
        #expect(rows(context) == before, "same ids, times and statuses as before")

        undo.redo()
        #expect(events(context).count == 4)
        #expect(!template.activeWeekdays.contains(sat))
    }

    @Test("Block deleted: its future instances go in the same step, and ⌘Z brings both back")
    func blockDeleted() throws {
        let (store, context, undo) = try makeStore()
        let (template, gym) = gymTemplate(context)
        let reading = RoutineBlock(title: "Reading", startMinutes: 21 * 60, duration: 1800)
        template.blocks.append(reading)
        try context.save()
        materialize(template, store, recordsUndo: false)
        let before = rows(context)
        #expect(before.count == 12)

        RoutineBlockStore(context: context, undo: undo, now: { today }, calendar: calendar)
            .delete(gym, from: template)

        #expect(undo.undoSteps.count == 1)
        #expect(undo.undoMenuTitle == "Undo Delete Routine Block")
        #expect(events(context).map(\.title) == Array(repeating: "Reading", count: 6))

        undo.undo()
        #expect(rows(context) == before)
        #expect(template.blocks.count == 2)
    }

    @Test("Newly protected (window created over the block): withdrawn in the window's step, restored by ⌘Z")
    func newlyProtectedByCreate() throws {
        let (store, context, undo) = try makeStore()
        let (template, _) = gymTemplate(context)
        materialize(template, store, recordsUndo: false)
        let before = rows(context)

        TimeWindowStore(context: context, undo: undo, now: { today }, calendar: calendar)
            .create(weekdays: [wed], startMinutes: 6 * 60, endMinutes: 9 * 60, kind: .protected, label: "Swim")

        #expect(undo.undoSteps.count == 1)
        #expect(undo.undoMenuTitle == "Undo Create Time Window")
        #expect(events(context).count == 4, "both Wednesdays withdrawn")
        #expect(events(context).allSatisfy { calendar.component(.weekday, from: $0.start) != wed })

        undo.undo()
        #expect(rows(context) == before)
        #expect(windows(context).isEmpty)
    }

    @Test("Newly protected (kind changed to .protected): withdrawn in 'Set Time Window Kind'")
    func newlyProtectedByKind() throws {
        let (store, context, undo) = try makeStore()
        let (template, _) = gymTemplate(context)
        let window = TimeWindow(weekdays: [mon], startMinutes: 6 * 60, endMinutes: 8 * 60,
                                kind: .lowEnergy, label: "Slow start")
        context.insert(window)
        try context.save()
        materialize(template, store, recordsUndo: false)
        #expect(events(context).count == 6, "low-energy never refuses")

        TimeWindowStore(context: context, undo: undo, now: { today }, calendar: calendar)
            .setKind(window, to: .protected)
        #expect(undo.undoMenuTitle == "Undo Set Time Window Kind")
        #expect(events(context).count == 4)

        undo.undo()
        #expect(events(context).count == 6)
    }

    @Test("Detached instances are kept by a withdrawal")
    func detachedKept() throws {
        let (store, context, _) = try makeStore()
        let (template, _) = gymTemplate(context)
        materialize(template, store, recordsUndo: false)
        let keep = try #require(events(context).first { calendar.component(.weekday, from: $0.start) == sat })
        let keepID = keep.id
        template.activeWeekdays = [mon, wed]
        try context.save()

        RoutineEngine.withdraw(template: template, today: today, store: store, calendar: calendar,
                               isDetached: { $0.id == keepID })

        #expect(events(context).count == 5)
        #expect(events(context).contains { $0.id == keepID })
    }

    @Test("Activating a weekday records only the weekday; the background pass creates the instances, and withdraws them after ⌘Z")
    func activationAndUndo() throws {
        let (_, context, undo) = try makeStore()
        let (template, _) = gymTemplate(context, weekdays: [mon])
        RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: today, calendar: calendar)
        let mondays = events(context).count

        RoutineTemplateStore(context: context, undo: undo)
            .setWeekday(tue, active: true, in: template, today: today, calendar: calendar)
        RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: today, calendar: calendar)
        #expect(events(context).count > mondays)
        #expect(undo.undoSteps.count == 1, "the background pass adds no step")

        undo.undo()
        RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: today, calendar: calendar)
        #expect(events(context).count == mondays, "the Tuesdays are withdrawn again")
        #expect(undo.undoSteps.isEmpty)
        #expect(undo.canRedo)
    }
}

// MARK: - Background runs and the past

@Suite("Re-materialisation — background runs and the past (§13.6.5)")
@MainActor
struct RematerializationBackgroundTests {

    @Test("A background run that creates, updates and withdraws records no undo step")
    func backgroundIsUnrecorded() throws {
        let (_, context, undo) = try makeStore()
        let (template, gym) = gymTemplate(context)
        RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: today, calendar: calendar)
        gym.startMinutes = 9 * 60
        template.activeWeekdays = [mon, wed]
        try context.save()

        RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: today, calendar: calendar)

        #expect(undo.undoSteps.isEmpty && undo.redoSteps.isEmpty)
        #expect(events(context).allSatisfy { calendar.component(.hour, from: $0.start) == 9 })
        #expect(events(context).allSatisfy { calendar.component(.weekday, from: $0.start) != sat })
    }

    @Test("Nothing before startOfDay(today) is created, updated or withdrawn")
    func pastIsARecord() throws {
        let (store, context, undo) = try makeStore()
        let (template, gym) = gymTemplate(context)
        // Materialise from last Monday, as if run a week ago.
        let lastWeek = calendar.date(byAdding: .day, value: -7, to: today)!
        RoutineEngine.materialize(template: template, into: DateInterval(start: lastWeek, end: day(7)),
                                  today: lastWeek, recordsUndo: false, store: store, calendar: calendar)
        let past = events(context).filter { $0.start < today }
        #expect(past.count == 3)
        let pastRows = Set(past.map { Row(id: $0.id, title: $0.title, start: $0.start, end: $0.end,
                                          flexibility: $0.flexibility, status: $0.status) })

        // Template moves and loses Saturday; a run from today must not touch last week.
        gym.startMinutes = 10 * 60
        try context.save()
        RoutineTemplateStore(context: context, undo: undo)
            .setWeekday(sat, active: false, in: template, today: today, calendar: calendar)
        RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: today, calendar: calendar)

        let stillPast = Set(events(context).filter { $0.start < today }.map {
            Row(id: $0.id, title: $0.title, start: $0.start, end: $0.end, flexibility: $0.flexibility, status: $0.status)
        })
        #expect(stillPast == pastRows)
        #expect(events(context).filter { $0.start >= today }.allSatisfy {
            calendar.component(.hour, from: $0.start) == 10
        })
    }
}

// MARK: - §13.7.4 tombstones

@Suite("Tombstones (§13.7.4)")
@MainActor
struct TombstoneTests {

    @Test("Deleting an instance leaves a tombstone keyed by (sourceID, externalID)")
    func deleteLeavesTombstone() throws {
        let (store, context, _) = try makeStore()
        let (template, _) = gymTemplate(context)
        materialize(template, store)
        let victim = events(context)[2]
        let key = (victim.sourceID, victim.externalID)

        store.delete(victim)

        let stones = tombstones(context)
        #expect(stones.count == 1)
        #expect(stones.first?.sourceID == key.0)
        #expect(stones.first?.externalID == key.1)
    }

    @Test("A tombstone survives repeated triggers: the pair is never recreated")
    func survivesTriggers() throws {
        let (_, context, undo) = try makeStore()
        let (template, gym) = gymTemplate(context)
        let store = EventStore(context: context, undo: undo)
        RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: today, calendar: calendar)
        let count = events(context).count
        let victim = events(context)[0]
        let key = victim.externalID
        store.delete(victim)

        for _ in 0..<3 {
            RoutineMaterialization.run(context: context, undo: undo, visibleEnd: day(40), today: today, calendar: calendar)
        }
        // A template edit is a trigger too, and updates the others.
        gym.startMinutes = 8 * 60
        try context.save()
        RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: today, calendar: calendar)

        #expect(!events(context).contains { $0.externalID == key })
        #expect(tombstones(context).count == 1)
        #expect(events(context).count >= count - 1)
    }

    @Test("⌘Z on the delete restores exactly one instance and removes the tombstone; ⌘⇧Z deletes it again")
    func undoRestoresExactlyOne() throws {
        let (_, context, undo) = try makeStore()
        let (template, _) = gymTemplate(context)
        _ = template
        let store = EventStore(context: context, undo: undo)
        RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: today, calendar: calendar)
        let victim = events(context)[0]
        let victimID = victim.id
        let key = victim.externalID
        store.delete(victim)
        RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: today, calendar: calendar)
        #expect(undo.undoMenuTitle == "Undo Delete Event")

        undo.undo()
        RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: today, calendar: calendar)

        let matches = events(context).filter { $0.externalID == key }
        #expect(matches.count == 1, "exactly one instance, never a duplicate (A29)")
        #expect(matches.first?.id == victimID, "the original row, same id")
        #expect(tombstones(context).isEmpty)

        undo.redo()
        RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: today, calendar: calendar)
        #expect(!events(context).contains { $0.externalID == key })
        #expect(tombstones(context).count == 1)
    }

    @Test("Only materialised routine instances leave a tombstone")
    func manualDeleteLeavesNone() throws {
        let (store, context, _) = try makeStore()
        let manual = Event(title: "Coffee", start: at(today, 10), end: at(today, 11), origin: .manual)
        let handSeeded = Event(title: "Training", start: at(today, 17), end: at(today, 18), origin: .routine)
        context.insert(manual)
        context.insert(handSeeded)
        try context.save()

        store.delete(manual)
        store.delete(handSeeded)

        #expect(tombstones(context).isEmpty)
    }
}
