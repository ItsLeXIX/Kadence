//
//  ConflictFooterTests.swift
//  KadenceTests
//
//  Task P2-F16 (PHASE2-REVIEW.md §6 item 16; layouts.md §10 and §8.1,
//  amended 2026-10-05; DEVIATIONS A32). The `1 of N` footer: one list (day
//  then template conflicts), N = the needs-attention count, no wrap,
//  stepping crosses windows only explicitly.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

@Suite("The `1 of N` footer (P2-F16)")
@MainActor
struct ConflictFooterTests {

    /// Monday 5 Oct 2026 12:00 with the §17.1 fixtures: 13 day + 1 template.
    private func seededState() throws -> (CalendarState, ModelContext) {
        let now = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 5, hour: 12)))
        let container = try ModelContainer(
            for: Schema(KadenceSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let undo = UndoStack()
        MockData.seedAllIfNeeded(context, now: now) {
            RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: now)
        }
        let state = CalendarState()
        state.anchor = now
        state.conflicts = MainWindow.sortedConflicts(
            events: try context.fetch(FetchDescriptor<Event>()),
            routineBlocks: try context.fetch(FetchDescriptor<RoutineBlock>()))
        state.templateConflicts = TemplateConflictEngine.detect(
            templates: try context.fetch(FetchDescriptor<RoutineTemplate>()),
            windows: try context.fetch(FetchDescriptor<TimeWindow>()),
            orderedWeekdays: RoutineWeekLayout.orderedWeekdays(firstWeekday: Calendar.current.firstWeekday))
        return (state, context)
    }

    @Test("N equals the needs-attention count (14), and the order is `⌘⇧A`'s")
    func countAndOrder() throws {
        let (state, _) = try seededState()
        #expect(state.conflictList.count == 14)
        #expect(state.conflictList.count == state.needsAttentionCount)
        let first = CalendarState.needsAttentionTarget(
            day: state.conflicts, template: state.templateConflicts, preferring: nil)
        if case .day(let id)? = first { #expect(state.conflictList.first == .day(id)) } else { Issue.record("expected a day conflict first") }
        // Day conflicts first, then the template conflict last.
        guard case .template? = state.conflictList.last else { Issue.record("template conflict should be last"); return }
        #expect(state.conflictList.dropLast().allSatisfy { if case .day = $0 { true } else { false } })
    }

    @Test("`‹` is disabled at 1, `›` at N; `1 of 1` shows with both disabled")
    func ends() {
        let first = ConflictFooterModel(position: 1, count: 14)
        #expect(!first.canGoBack && first.canGoForward)
        let last = ConflictFooterModel(position: 14, count: 14)
        #expect(last.canGoBack && !last.canGoForward)
        let only = ConflictFooterModel(position: 1, count: 1)
        #expect(only.text == "1 of 1" && !only.canGoBack && !only.canGoForward)
    }

    @Test("Text and AX: `3 of 14`, `Conflict 3 of 14`")
    func copy() {
        let model = ConflictFooterModel(position: 3, count: 14)
        #expect(model.text == "3 of 14")
        #expect(model.accessibilityText == "Conflict 3 of 14")
    }

    @Test("Stepping moves one place and opens the new conflict on its recommendation; ends don't wrap")
    func stepping() throws {
        let (state, _) = try seededState()
        let list = state.conflictList
        guard case .day(let firstID) = list[0], case .day(let secondID) = list[1] else { Issue.record("day first"); return }
        state.open(try #require(state.conflicts.first { $0.id == firstID }))
        #expect(state.stepConflict(from: .day(firstID), by: -1) == nil, "no wrap at 1")
        #expect(state.selectedConflictID == firstID)

        #expect(state.stepConflict(from: .day(firstID), by: 1) == .day(secondID))
        #expect(state.selectedConflictID == secondID)
        let second = try #require(state.conflicts.first { $0.id == secondID })
        #expect(state.selectedConflictOptionID == CalendarState.activationOptionID(second.options))
        #expect(state.conflictPosition(of: .day(secondID)) == 2)

        guard case .template(let templateID) = try #require(list.last) else { return }
        #expect(state.stepConflict(from: .template(templateID), by: 1) == nil, "no wrap at N")
    }

    @Test("From the last day conflict, `›` routes to the template conflict (Routines window); `‹` from it returns")
    func crossesToTemplate() throws {
        let (state, _) = try seededState()
        guard case .day(let lastDay) = state.conflictList[state.conflictList.count - 2],
              case .template(let templateID) = try #require(state.conflictList.last) else { Issue.record("shape"); return }
        let went = state.stepConflict(from: .day(lastDay), by: 1)
        #expect(went == .template(templateID))
        #expect(state.pendingTemplateConflictID == templateID, "routes exactly as activation does")

        let back = state.stepConflict(from: .template(templateID), by: -1)
        #expect(back == .day(lastDay))
        #expect(state.selectedConflictID == lastDay)
    }

    @Test("`↩` in the main window never opens the Routines window, even with a template conflict left")
    func returnStaysInWindow() throws {
        let (state, context) = try seededState()
        let store = EventStore(context: context, undo: UndoStack())
        // Resolve every day conflict with ↩; the template one remains.
        var guardCount = 0
        state.activateNeedsAttention()
        while state.selectedConflictID != nil, guardCount < 30 {
            if state.selectedConflictOptionID == nil { state.moveSelectedConflictOption(by: 1) }
            state.applyFocusedConflictOption(store: store) {
                MainWindow.sortedConflicts(
                    events: (try? context.fetch(FetchDescriptor<Event>())) ?? [],
                    routineBlocks: (try? context.fetch(FetchDescriptor<RoutineBlock>())) ?? [])
            }
            guardCount += 1
        }
        #expect(state.selectedConflictID == nil, "the panel closes when no day conflict remains")
        #expect(state.pendingTemplateConflictID == nil, "never routed to the Routines window by ↩")
        #expect(state.templateConflicts.count == 1)
        #expect(state.needsAttentionCount >= 1, "the sidebar still shows what remains")
    }

    @Test("A Routines window is recognised by its WindowGroup id")
    func routinesWindowIdentifier() {
        #expect(RoutinesWindowOpener.isRoutinesWindow(identifier: "routines-AppWindow-1"))
        #expect(!RoutinesWindowOpener.isRoutinesWindow(identifier: "main-AppWindow-1"))
        #expect(!RoutinesWindowOpener.isRoutinesWindow(identifier: nil))
    }
}
