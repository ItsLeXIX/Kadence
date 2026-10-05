//
//  SpokenStringsTests.swift
//  KadenceTests
//
//  Task P2-F10 (PHASE2-REVIEW.md §6 item 10; components.md §10.2 (G-029) and
//  §11 (G-030), both amended 2026-10-05).
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

@Suite("Spoken strings (P2-F10)")
@MainActor
struct SpokenStringsTests {

    /// Monday 5 Oct 2026 at noon, seeded the way the app seeds.
    private func seeded() throws -> (events: [Event], blocks: [RoutineBlock], now: Date) {
        let now = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12)))
        let container = try ModelContainer(
            for: Schema(KadenceSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let undo = UndoStack()
        MockData.seedAllIfNeeded(context, now: now) {
            RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: now)
        }
        return (try context.fetch(FetchDescriptor<Event>()), try context.fetch(FetchDescriptor<RoutineBlock>()), now)
    }

    @Test("The needs-attention row's value is `14 conflicts` with the §17.1 fixtures")
    func rowValueFixtures() throws {
        let (events, blocks, _) = try seeded()
        let state = CalendarState()
        state.conflicts = MainWindow.sortedConflicts(events: events, routineBlocks: blocks)
        state.templateConflicts = TemplateConflictEngine.detect(
            templates: MockData.makeRoutineTemplates(), windows: MockData.makeTimeWindows(),
            orderedWeekdays: RoutineWeekLayout.orderedWeekdays(firstWeekday: Calendar.current.firstWeekday))
        #expect(NeedsAttentionSpeech.value(count: state.needsAttentionCount) == "14 conflicts")
    }

    @Test("`1 conflict` at one; the noun is plural otherwise")
    func rowValueCounts() {
        #expect(NeedsAttentionSpeech.value(count: 1) == "1 conflict")
        #expect(NeedsAttentionSpeech.value(count: 2) == "2 conflicts")
        #expect(NeedsAttentionSpeech.value(count: 12) == "12 conflicts")
    }

    @Test("`Late lab session` ends `lands in Sleep, a protected window`")
    func lateLabSession() throws {
        let (events, _, now) = try seeded()
        let lab = try #require(events.first { $0.title == "Late lab session" })
        var model = GridBlockModel(event: lab, now: now)
        model.conflicts = DayColumnView.protectedWindowLabels(
            for: lab, windows: MockData.timeWindows, day: lab.start).map { .protectedWindow(label: $0) }
        #expect(model.accessibilityLabel(presentation: .conflicted).hasSuffix("lands in Sleep, a protected window"))
    }

    @Test("An empty window label speaks `lands in a protected window`")
    func emptyLabel() {
        #expect(BlockConflict.protectedWindow(label: "").spokenPhrase == "lands in a protected window")
    }

    @Test("Block phrases come before window phrases, whatever order they arrive in")
    func ordering() {
        let phrases = GridBlockModel.orderedConflictPhrases([
            .protectedWindow(label: "Sleep"), .event(title: "Training"), .event(title: "Code review"),
        ])
        #expect(phrases == ["conflicts with Training", "conflicts with Code review",
                            "lands in Sleep, a protected window"])
    }

    @Test("Block partners are spoken in partner start order")
    func partnerStartOrder() throws {
        let (events, blocks, _) = try seeded()
        let titles = MainWindow.conflictPartnerTitles(events: events, routineBlocks: blocks)
        let byTitle = Dictionary(events.map { ($0.title, $0.start) }, uniquingKeysWith: { a, _ in a })
        for (_, partners) in titles where partners.count > 1 {
            let starts = partners.compactMap { byTitle[$0] }
            #expect(starts == starts.sorted())
        }
    }
}
