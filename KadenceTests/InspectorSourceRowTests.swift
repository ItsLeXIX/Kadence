//
//  InspectorSourceRowTests.swift
//  KadenceTests
//
//  Task P2-F03 (PHASE2-REVIEW.md §6 item 3; layouts.md §6 row 4, amended
//  2026-10-05; components.md §3.4). The inspector's Source row names the
//  source as the sidebar lists it, never the palette slot (`Green`).
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

@Suite("Inspector Source row names the source (P2-F03)")
@MainActor
struct InspectorSourceRowTests {

    /// Monday 5 Oct 2026, 12:00 — a template day, so `Daily routine`
    /// materialises instances today.
    private func seededEvents() throws -> [Event] {
        let now = try #require(Calendar.current.date(from: DateComponents(
            year: 2026, month: 10, day: 5, hour: 12)))
        let container = try ModelContainer(
            for: Schema(KadenceSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let undo = UndoStack()
        MockData.seedAllIfNeeded(context, now: now) {
            RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: now)
        }
        return try context.fetch(FetchDescriptor<Event>())
    }

    @Test("A materialised Daily routine instance reads `Daily routine`")
    func routineInstance() throws {
        let instance = try #require(try seededEvents().first { $0.origin == .routine })
        #expect(InspectorView.sourceRowName(for: instance.sourceKey) == "Daily routine")
    }

    @Test("An imported lecture reads `University timetable`")
    func importedLecture() throws {
        let lecture = try #require(try seededEvents().first {
            $0.origin == .imported && $0.sourceKey == .blue
        })
        #expect(InspectorView.sourceRowName(for: lecture.sourceKey) == "University timetable")
    }

    @Test("No source's row ever reads a palette colour word", arguments: SourceKey.allCases)
    func neverAColourWord(_ key: SourceKey) {
        let name = InspectorView.sourceRowName(for: key)
        #expect(!SourceKey.allCases.map(\.displayName).contains(name))
    }
}
