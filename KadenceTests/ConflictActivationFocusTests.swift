//
//  ConflictActivationFocusTests.swift
//  KadenceTests
//
//  Task P2-F15 (PHASE2-REVIEW.md §6 item 15; interactions.md §10.1 and
//  components.md §14.1, amended 2026-10-05). Activation focuses — and so
//  previews — the recommended option, and brings the conflict into view.
//

import Testing
import Foundation
import SwiftData
import CoreGraphics
@testable import Kadence

@Suite("Activation focuses the recommendation and brings the conflict into view (P2-F15)")
@MainActor
struct ConflictActivationFocusTests {

    /// Monday 5 Oct 2026 12:00, seeded the way the app seeds.
    private func seeded() throws -> (conflicts: [Conflict], now: Date) {
        let now = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12)))
        let container = try ModelContainer(
            for: Schema(KadenceSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let undo = UndoStack()
        MockData.seedAllIfNeeded(context, now: now) {
            RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: now)
        }
        let events = try context.fetch(FetchDescriptor<Event>())
        let blocks = try context.fetch(FetchDescriptor<RoutineBlock>())
        return (MainWindow.sortedConflicts(events: events, routineBlocks: blocks), now)
    }

    private func training(_ conflicts: [Conflict]) throws -> Conflict {
        try #require(conflicts.first {
            Set([$0.routineEvent.title, $0.otherEvent.title]) == ["Training", "Supervisor meeting"]
        })
    }

    @Test("Training × Supervisor meeting opens on row 2, `Shift Training 75 min later`")
    func focusesRecommendedRowTwo() throws {
        let (conflicts, now) = try seeded()
        let conflict = try training(conflicts)
        let state = CalendarState()
        state.anchor = now
        state.conflicts = conflicts
        state.open(conflict)

        let focused = try #require(conflict.options.first { $0.id == state.selectedConflictOptionID })
        #expect(focused.isRecommended)
        #expect(focused.kind == .shiftLater)
        #expect(conflict.options.firstIndex { $0.id == focused.id } == 1, "row 2, not the top row (P2-T45 overturned)")
        #expect(ConflictOptionFormatting.title(for: focused, conflict: conflict) == "Shift Training 75 min later")
    }

    @Test("A single-option conflict focuses its one row")
    func singleOption() {
        let only = ConflictOption(
            id: UUID(), kind: .skipToday, newStart: nil, newEnd: nil, skipsOccurrence: true,
            disturbanceMinutes: 90, isRecommended: false)
        #expect(CalendarState.activationOptionID([only]) == only.id)
    }

    @Test("Activation pages to the conflict's week (same view) when it isn't visible")
    func pages() throws {
        let (conflicts, now) = try seeded()
        let conflict = try training(conflicts)
        let state = CalendarState()
        state.setMode(.week)
        state.anchor = Calendar.current.date(byAdding: .day, value: -21, to: now)!
        state.conflicts = conflicts
        state.open(conflict)
        #expect(state.mode == .week, "never an auto-switch")
        #expect(state.visibleDays.contains { Calendar.current.isDate($0, inSameDayAs: conflict.routineEvent.start) })
    }

    @Test("The scroll request asks for 17:00 (the earlier start) one third from the top")
    func scrollsSeventeenToOneThird() throws {
        let (conflicts, now) = try seeded()
        let conflict = try training(conflicts)
        let state = CalendarState()
        state.anchor = now
        state.conflicts = conflicts
        state.open(conflict)
        let request = try #require(state.conflictScrollRequest)
        let dayStart = Calendar.current.startOfDay(for: request.occurrenceStart)
        func minute(_ d: Date) -> Int { Int(d.timeIntervalSince(dayStart) / 60) }
        #expect(minute(request.earliestStart) == 17 * 60)

        // Viewport at the default 07:00, 300pt tall: Training (17:00–18:30)
        // is below it, so the target is 17:00, which lands at height / 3.
        let hourHeight = Tokens.Size.hourHeightWeek
        let target = ConflictScroll.targetMinute(
            occurrence: minute(request.occurrenceStart)..<minute(request.occurrenceEnd),
            earliestStart: minute(request.earliestStart),
            visibleTop: 7 * hourHeight, visibleHeight: 300, hourHeight: hourHeight)
        #expect(target == 17 * 60)
        let offset = ConflictScroll.offset(forMinute: 17 * 60, visibleHeight: 300, hourHeight: hourHeight)
        #expect(17 * hourHeight - offset == 100, "17:00 sits one third of the way down")
    }

    @Test("Already wholly in view: no scroll")
    func noScrollWhenVisible() {
        let hourHeight = Tokens.Size.hourHeightWeek
        #expect(ConflictScroll.targetMinute(
            occurrence: (17 * 60)..<(18 * 60 + 30), earliestStart: 17 * 60,
            visibleTop: 16 * hourHeight, visibleHeight: 600, hourHeight: hourHeight) == nil)
        // Partly cut off at the bottom: scroll.
        #expect(ConflictScroll.targetMinute(
            occurrence: (17 * 60)..<(18 * 60 + 30), earliestStart: 17 * 60,
            visibleTop: 10 * hourHeight, visibleHeight: 300, hourHeight: hourHeight) == 17 * 60)
    }

    @Test("Routines window: Errands × Lunch focuses the recommendation and scrolls to 12:00")
    func routinesWindow() throws {
        let conflict = try #require(TemplateConflictEngine.detect(
            templates: MockData.makeRoutineTemplates(), windows: MockData.makeTimeWindows(),
            orderedWeekdays: RoutineWeekLayout.orderedWeekdays(firstWeekday: 2)).first)
        let request = RoutineScrollRequest(conflict)
        #expect(request.earliestStart == 12 * 60, "Lunch starts before Errands")
        #expect(request.occurrence == (12 * 60 + 30)..<(13 * 60 + 15))
        let id = try #require(RoutineScrollRequest.activationOptionID(conflict))
        #expect(conflict.options.first { $0.id == id }?.isRecommended == true)
    }

    @Test("Stepping back onto the same conflict asks to scroll again")
    func repeatRequestIsAChange() throws {
        let (conflicts, now) = try seeded()
        let conflict = try training(conflicts)
        let state = CalendarState()
        state.anchor = now
        state.conflicts = conflicts
        state.open(conflict)
        let first = state.conflictScrollRequest
        state.open(conflict)
        #expect(state.conflictScrollRequest != first)
    }
}
