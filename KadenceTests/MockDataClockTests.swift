//
//  MockDataClockTests.swift
//  KadenceTests
//
//  Task P2-T41 (DEVIATIONS.md B18): the mock store must not depend on what
//  time of day it is seeded. `Journal` used to be seeded at `now + 4 min`
//  and, depending on the clock, overlapped `Training` or `Focus review`,
//  which added a conflict and changed which one sorted first. That made
//  `Scripts/check-conflict-apply-return.sh` pass or fail by time of day.
//
//  Uses `Calendar.current`, because `MockData.makeEvents` and the app's own
//  launch pass do.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

@MainActor
private func seeded(at now: Date) throws -> (events: [Event], blocks: [RoutineBlock]) {
    let container = try ModelContainer(
        for: Schema(KadenceSchema.models),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let undo = UndoStack()
    MockData.seedAllIfNeeded(context, now: now) {
        RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: now)
    }
    let events = try context.fetch(FetchDescriptor<Event>(sortBy: [SortDescriptor(\.start)]))
    let blocks = try context.fetch(FetchDescriptor<RoutineBlock>())
    return (events, blocks)
}

/// Monday 5 Oct 2026 (a template day: Gym, Morning review, Reading run)
/// and Thursday 8 Oct (not), at the clock times that used to collide plus
/// ordinary ones. 16:50 put Journal inside Training; 19:45 and 20:00 inside
/// Focus review; 20:50 inside Reading on Mondays.
@Suite("MockData — conflicts don't depend on the seeding clock (P2-T41, B18)")
@MainActor
struct MockDataClockTests {

    @Test("Conflict count, the Client call / Focus review pair, and its first place are the same at every clock time",
          arguments: [
              "5 7:00", "5 12:00", "5 16:50", "5 19:45", "5 20:00", "5 20:50", "5 23:30",
              "8 7:00", "8 12:00", "8 16:50", "8 20:00", "8 23:30",
          ])
    func stableAcrossClock(_ label: String) throws {
        // "<day of Oct 2026> <hour>:<minute>". Monday 5 Oct is a template day
        // (Gym, Morning review, Reading run); Thursday 8 Oct is not. 16:50 used
        // to put Journal inside Training, 19:45/20:00 inside Focus review, and
        // 20:50 inside Monday's Reading.
        let parts = label.split(whereSeparator: { $0 == " " || $0 == ":" }).compactMap { Int($0) }
        let now = try #require(Calendar.current.date(from: DateComponents(
            year: 2026, month: 10, day: parts[0], hour: parts[1], minute: parts[2])))
        let (events, blocks) = try seeded(at: now)
        let conflicts = MainWindow.sortedConflicts(events: events, routineBlocks: blocks)

        #expect(conflicts.count == 12)
        let titles = conflicts.map { Set([$0.routineEvent.title, $0.otherEvent.title]) }
        #expect(titles.contains(["Client call", "Focus review"]))
        #expect(titles.first == ["Client call", "Focus review"], "the pair sorts first at \(label)")
        #expect(!titles.contains { $0.contains("Journal") }, "Journal is never in a conflict")

        // Journal still serves P2-T34's purpose: it starts after `now`, at
        // least the four-minute lead later.
        let journal = try #require(events.first { $0.title == "Journal" })
        #expect(journal.start >= now.addingTimeInterval(MockData.journalLead))
        #expect(journal.duration == MockData.journalDuration)

        // The script's explicit hook finds the same pair.
        let underTest = CalendarState.conflictUnderTest(in: conflicts, title: "Focus review")
        #expect(underTest.map { Set([$0.routineEvent.title, $0.otherEvent.title]) } == ["Client call", "Focus review"])
    }

    @Test("journalStart: now + 4 when free; pushed past each busy interval it would touch, never before it")
    func journalStartRule() {
        let base = Date(timeIntervalSinceReferenceDate: 0)
        func min(_ m: Double) -> Date { base.addingTimeInterval(m * 60) }

        #expect(MockData.journalStart(now: base, busy: []) == min(4))
        // 10…30 blocks 4…19; chained 30…50 blocks 30…45; free at 50.
        let busy = [DateInterval(start: min(10), end: min(30)), DateInterval(start: min(30), end: min(50))]
        #expect(MockData.journalStart(now: base, busy: busy) == min(50))
        // Touching is not overlapping: busy ending exactly at now + 4 is fine.
        #expect(MockData.journalStart(now: base, busy: [DateInterval(start: min(0), end: min(4))]) == min(4))
    }
}
