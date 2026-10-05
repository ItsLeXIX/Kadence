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

/// Monday 5 and Wednesday 7 Oct 2026 (template days: Gym, Morning review,
/// Training, Reading run) and Thursday 8 Oct (not), at the clock times that used to collide plus
/// ordinary ones. 16:50 put Journal inside Training; 19:45 and 20:00 inside
/// Focus review; 20:50 inside Reading on Mondays.
@MainActor
private func seededTemplates(at now: Date) throws -> [RoutineTemplate] { MockData.makeRoutineTemplates() }
@MainActor
private func seededWindows(at now: Date) throws -> [TimeWindow] { MockData.makeTimeWindows() }

@Suite("MockData — conflicts don't depend on the seeding clock (P2-T41, B18)")
@MainActor
struct MockDataClockTests {

    @Test("Conflict count and the Client call / Focus review pair are the same at every clock time of a day",
          arguments: [
              "5 7:00", "5 12:00", "5 16:50", "5 19:45", "5 20:00", "5 20:50", "5 23:30",
              "7 7:00", "7 13:10", "7 17:00", "7 23:30",
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

        // components.md §17.1 (amended 2026-10-05, task P2-F01): 13 day
        // conflicts on EVERY weekday — Client call × Focus review, the eleven
        // Fixture pairs, Training × Supervisor meeting. Before P2-F01 the
        // Group call / Code review / Notes write-up triple sat at 18:00 and
        // also met the template's Training on a Mon/Wed/Fri today (15).
        #expect(conflicts.count == 13)
        let titles = conflicts.map { Set([$0.routineEvent.title, $0.otherEvent.title]) }
        #expect(titles.contains(["Client call", "Focus review"]))
        #expect(titles.contains(["Training", "Supervisor meeting"]))
        // Which conflict sorts FIRST is no longer pinned: Training's three
        // conflicts tie at 17:00 and are broken by id. That is why the script
        // selects its pair explicitly (`-KadenceConflictUnderTest`).
        #expect(!titles.contains { $0.contains("Journal") }, "Journal is never in a conflict")

        // Journal still serves P2-T34's purpose: it starts after `now`, at
        // least the four-minute lead later.
        let journal = try #require(events.first { $0.title == "Journal" })
        #expect(journal.start >= now.addingTimeInterval(MockData.journalLead))
        #expect(journal.duration == MockData.journalDuration)

        // The template conflict (Errands × Lunch) is there at every clock time too.
        let templateConflicts = TemplateConflictEngine.detect(
            templates: try seededTemplates(at: now), windows: try seededWindows(at: now),
            orderedWeekdays: RoutineWeekLayout.orderedWeekdays(firstWeekday: Calendar.current.firstWeekday))
        #expect(templateConflicts.count == 1)

        // §17.1's expected needs-attention count: 13 + 1 = 14, read through
        // the same property the sidebar row draws.
        let state = CalendarState()
        state.conflicts = conflicts
        state.templateConflicts = templateConflicts
        #expect(state.needsAttentionCount == 14)

        // The §12 item 12 triple still packs: three mutually overlapping blocks
        // today (common interval 13:30–14:00), and none of them is in a conflict.
        let triple = ["Group call", "Code review", "Notes write-up"].compactMap { title in
            events.first { $0.title == title }
        }
        #expect(triple.count == 3)
        for a in triple { for b in triple where a !== b {
            #expect(a.start < b.end && b.start < a.end, "\(a.title) overlaps \(b.title)")
        } }
        #expect(triple.allSatisfy { Calendar.current.isDate($0.start, inSameDayAs: now) })
        #expect(!titles.contains { !$0.isDisjoint(with: ["Group call", "Code review", "Notes write-up"]) })

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
