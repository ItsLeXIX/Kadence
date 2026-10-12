//
//  ImportedOverlapTests.swift
//  KadenceTests
//
//  PHASE3-REVIEW.md fix 5 — components.md §20.9 (stated 2026-10-10): "Two
//  imported events never conflict with each other", whether from one source
//  or two. DECISIONS 2026-10-10 "Two imported events never conflict".
//
//  The regression is Parsa's Fri 2 Oct 2026: `BPREF-Info` 18:35–20:15 (co-
//  taught, L05 and L06) with a second `BPREF-Info` session 19:30–20:15 inside
//  it. Built from `fixtures/cis-2026WS-redacted.ics` through
//  `reportCISOverlap` (the `fresh` review dataset), with the clock at
//  2026-10-01 10:00 so that 2 Oct is not history.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

@MainActor
@Suite(.serialized)
struct ImportedOverlapTests {

    /// Thu 1 Oct 2026, 10:00 Europe/Vienna: the day before the overlap.
    private let clock = TestClock.date("2026-10-01 10:00")

    /// `fresh` at `clock`: the two built-ins and the timetable imported from
    /// `reportCISOverlap`.
    private func fresh() throws -> ModelContext {
        let context = ModelContext(try ModelContainer(for: Schema(KadenceSchema.models),
                                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        ReviewMode.seedFresh(context: context, now: clock, secrets: InMemorySecretStore(), zone: TestClock.zone)
        return context
    }

    private func needsAttention(_ context: ModelContext) throws -> (conflicts: [Conflict], count: Int) {
        let events = try context.fetch(FetchDescriptor<Event>())
        let conflicts = MainWindow.sortedConflicts(events: events,
                                                   routineBlocks: try context.fetch(FetchDescriptor<RoutineBlock>()),
                                                   now: clock)
        let state = CalendarState()
        state.conflicts = conflicts
        state.templateConflicts = TemplateConflictEngine.detect(
            templates: try context.fetch(FetchDescriptor<RoutineTemplate>()),
            windows: try context.fetch(FetchDescriptor<TimeWindow>()),
            orderedWeekdays: RoutineWeekLayout.orderedWeekdays(firstWeekday: Calendar.current.firstWeekday))
        return (conflicts, state.needsAttentionCount)
    }

    @Test("reportCISOverlap on `fresh`: 13 events; the two BPREF-Info sessions overlap 45 min and are not a conflict; Needs attention is 0 and hidden")
    func twoLecturesNeverConflict() throws {
        let context = try fresh()
        let events = try context.fetch(FetchDescriptor<Event>())
        #expect(events.count == 13)
        #expect(events.allSatisfy { $0.origin == .imported })

        // The overlap is real, and neither session is history at this clock.
        let sessions = events.filter { $0.title == "BPREF-Info" }.sorted { $0.start < $1.start }
        #expect(sessions.count == 2)
        let long = try #require(sessions.first), short = try #require(sessions.last)
        #expect(long.start == TestClock.date("2026-10-02 18:35") && long.end == TestClock.date("2026-10-02 20:15"))
        #expect(short.start == TestClock.date("2026-10-02 19:30") && short.end == TestClock.date("2026-10-02 20:15"))
        #expect(long.lecturers == ["L05", "L06"] && short.lecturers == ["L07"])
        let overlap = min(long.end, short.end).timeIntervalSince(max(long.start, short.start))
        #expect(overlap == 45 * 60)
        #expect(long.start >= Calendar.current.startOfDay(for: clock))

        // No conflict — with or without the clock (so it is not history
        // that hides it), and for the pair alone.
        let blocks = try context.fetch(FetchDescriptor<RoutineBlock>())
        #expect(ConflictEngine.detect(events: events, routineBlocks: blocks, today: clock).isEmpty)
        #expect(ConflictEngine.detect(events: events, routineBlocks: blocks).isEmpty)
        #expect(ConflictEngine.detect(events: [long, short], routineBlocks: [], today: clock).isEmpty)

        // The count is 0 and the sidebar row is hidden (§10.2).
        let attention = try needsAttention(context)
        #expect(attention.conflicts.isEmpty && attention.count == 0)
        #expect(!SidebarSourcesRule.showsNeedsAttentionRow(count: attention.count))
        #expect(SidebarSourcesRule.showsNeedsAttentionRow(count: 1))
    }

    @Test("Lectures of two different sources that overlap do not conflict either")
    func twoSourcesNeverConflict() throws {
        let context = try fresh()
        let other = Source.connected(id: "other", displayName: "Second timetable", serverURL: "https://example.invalid",
                                     username: "user01", principalHref: nil, calendarHomeHref: nil, calendars: [],
                                     capabilities: SourceCapabilities(), paletteKey: .teal)
        context.insert(other)
        let lecture = Event(title: "OTHER-ILV", start: TestClock.date("2026-10-02 19:00"), end: TestClock.date("2026-10-02 20:00"),
                            origin: .imported, sourceKey: .teal, sourceID: other.id, externalID: "other-1")
        context.insert(lecture)
        try context.save()
        #expect(try needsAttention(context).count == 0)
    }

    @Test("A routine block over 19:00–20:00 that day conflicts with each session: exactly two conflicts, routine × one session each")
    func aRoutineBlockConflictsWithEach() throws {
        let context = try fresh()
        let routine = Event(title: "Training", start: TestClock.date("2026-10-02 19:00"), end: TestClock.date("2026-10-02 20:00"),
                            origin: .routine, flexibility: .shiftable, sourceKey: .green,
                            sourceID: UUID().uuidString, externalID: "\(UUID().uuidString)#20261002")
        context.insert(routine)
        try context.save()

        let attention = try needsAttention(context)
        #expect(attention.conflicts.count == 2 && attention.count == 2)
        #expect(SidebarSourcesRule.showsNeedsAttentionRow(count: attention.count))
        // Each is the routine block against one of the two sessions — never
        // session against session.
        #expect(attention.conflicts.allSatisfy { $0.routineEvent.id == routine.id && $0.routineEvent.origin == .routine })
        #expect(attention.conflicts.allSatisfy { $0.otherEvent.origin == .imported && $0.otherEvent.title == "BPREF-Info" })
        #expect(Set(attention.conflicts.map(\.otherEvent.id)).count == 2)
        let overlaps = attention.conflicts.map { Int($0.overlapEnd.timeIntervalSince($0.overlapStart) / 60) }.sorted()
        #expect(overlaps == [30, 60])   // 19:30–20:00 with the short session, 19:00–20:00 with the long one
        // The options edit the routine side only.
        #expect(attention.conflicts.allSatisfy { !$0.options.isEmpty })
    }

    @Test("On a clock after 2 Oct the pair is history and still nothing is counted")
    func historyNeverConflicts() throws {
        let context = try fresh()
        let events = try context.fetch(FetchDescriptor<Event>())
        #expect(ConflictEngine.detect(events: events, routineBlocks: [], today: TestClock.now).isEmpty)
    }
}
