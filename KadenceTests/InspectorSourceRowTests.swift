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
    /// The Phase 2 dataset and its source directory. Its mock events carry
    /// no `sourceID`, so — as in a review launch (components.md §22.1) — they
    /// resolve to the source holding their slot.
    private func seeded() throws -> ([Event], SourceDirectory) {
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
        return (try context.fetch(FetchDescriptor<Event>()),
                SourceDirectory(try context.fetch(FetchDescriptor<Source>()), allowsSlotFallback: true))
    }

    @Test("A materialised Daily routine instance reads `Daily routine`")
    func routineInstance() throws {
        let (events, sources) = try seeded()
        let instance = try #require(events.first { $0.origin == .routine })
        #expect(InspectorView.sourceRowName(for: instance, sources: sources) == "Daily routine")
    }

    @Test("An imported lecture reads `University timetable`")
    func importedLecture() throws {
        let (events, sources) = try seeded()
        let lecture = try #require(events.first {
            $0.origin == .imported && $0.sourceKey == .blue
        })
        #expect(InspectorView.sourceRowName(for: lecture, sources: sources) == "University timetable")
    }

    @Test("No event's row ever reads a palette colour word")
    func neverAColourWord() throws {
        let (events, sources) = try seeded()
        let words = SourceKey.allCases.map(\.displayName)
        for event in events {
            #expect(!words.contains(InspectorView.sourceRowName(for: event, sources: sources)))
        }
    }
}
