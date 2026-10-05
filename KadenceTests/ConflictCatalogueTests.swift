//
//  ConflictCatalogueTests.swift
//  KadenceTests
//
//  Task P2-T45: components.md §14.3.1–§14.3.4 (closes GAPS G-017 in code).
//  The catalogue (shiftLater / shorten for any flexibility / skipToday), the
//  display order with its kind-order tie-break, the preservation
//  recommendation, the no-chip single option, and the exact copy.
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
    calendar.timeZone = TimeZone(identifier: "Europe/Vienna")!
    return calendar
}()
private let day = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!
private func time(_ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(byAdding: .minute, value: hour * 60 + minute, to: day)!
}

/// A materialised-shaped routine event (`externalID` = `<block id>#…`) so
/// `ConflictEngine` can find its block's ± minutes.
@MainActor
private func conflict(
    _ context: ModelContext, title: String = "Training",
    flexibility: Flexibility, shift: Int? = nil,
    routine: (Date, Date), other: (Date, Date)
) throws -> Conflict {
    let block = RoutineBlock(title: title, startMinutes: 0, duration: 0,
                             flexibility: flexibility, shiftableMinutes: shift)
    let event = Event(title: title, start: routine.0, end: routine.1, origin: .routine,
                      flexibility: flexibility, sourceID: "template",
                      externalID: "\(block.id.uuidString)#2026-10-05")
    let meeting = Event(title: "Supervisor meeting", start: other.0, end: other.1, origin: .manual)
    context.insert(block)
    context.insert(event)
    context.insert(meeting)
    try context.save()
    return try #require(ConflictEngine.detect(events: [event, meeting], routineBlocks: [block]).first)
}

@Suite("Conflict options — catalogue and order (§14.3.1, §14.3.2)")
@MainActor
struct ConflictCatalogueTests {

    @Test("Exactly three kinds, in kind order; no shiftEarlier at day level")
    func catalogueKinds() {
        #expect(ConflictOptionKind.allCases == [.shiftLater, .shorten, .skipToday])
    }

    @Test("§17 item 7: Training 17:00–18:30 ±90 × Supervisor meeting 17:30–18:15 gives 60 · 75 · 90, second recommended")
    func itemSeven() throws {
        let (_, context, _) = try makeStore()
        let c = try conflict(context, flexibility: .shiftable, shift: 90,
                             routine: (time(17), time(18, 30)), other: (time(17, 30), time(18, 15)))
        #expect(c.options.map(\.kind) == [.shorten, .shiftLater, .skipToday])
        #expect(c.options.map(\.disturbanceMinutes) == [60, 75, 90])
        #expect(c.options.map(\.isRecommended) == [false, true, false], "75 ≤ 90 keeps the whole session")
    }

    @Test(".shiftable reaches three options")
    func threeOptions() throws {
        let (_, context, _) = try makeStore()
        let c = try conflict(context, flexibility: .shiftable, shift: 90,
                             routine: (time(17), time(18, 30)), other: (time(17, 30), time(18, 15)))
        #expect(c.options.count == 3)
    }

    @Test(".droppable now gets more than one option (shorten + skip)")
    func droppableGetsTwo() throws {
        let (_, context, _) = try makeStore()
        let c = try conflict(context, title: "Reading", flexibility: .droppable,
                             routine: (time(21), time(22)), other: (time(21, 30), time(22, 30)))
        #expect(c.options.map(\.kind) == [.shorten, .skipToday])
        #expect(c.options.filter(\.isRecommended).count == 1)
    }

    @Test("shorten is offered for .shiftable even when the shift doesn't fit its ±")
    func shortenUngated() throws {
        let (_, context, _) = try makeStore()
        let c = try conflict(context, flexibility: .shiftable, shift: 15,
                             routine: (time(17), time(18, 30)), other: (time(17, 30), time(18, 15)))
        #expect(c.options.map(\.kind) == [.shorten, .skipToday])
    }

    @Test("shorten needs a remainder of at least 15 minutes")
    func shortenFloor() throws {
        let (_, context, _) = try makeStore()
        // Remainders 10 (front) and 5 (back): neither reaches 15.
        let c = try conflict(context, flexibility: .fixed,
                             routine: (time(9), time(9, 45)), other: (time(9, 10), time(9, 40)))
        #expect(c.options.map(\.kind) == [.skipToday])
    }

    @Test("Equal disturbance: kind order breaks the tie (shiftLater before shorten)")
    func kindOrderTieBreak() throws {
        let (_, context, _) = try makeStore()
        // 60-min block; the other event covers its first 30 minutes. Shift 30,
        // shorten trims 30 (keeps the back half), skip 60.
        let c = try conflict(context, flexibility: .shiftable, shift: 180,
                             routine: (time(9), time(10)), other: (time(9), time(9, 30)))
        #expect(c.options.map(\.disturbanceMinutes) == [30, 30, 60])
        #expect(c.options.map(\.kind) == [.shiftLater, .shorten, .skipToday])
    }

    @Test("A single-option conflict carries no chip")
    func singleOptionNoChip() throws {
        let (_, context, _) = try makeStore()
        let c = try conflict(context, flexibility: .fixed,
                             routine: (time(13, 15), time(13, 45)), other: (time(13), time(14)))
        #expect(c.options.count == 1)
        #expect(c.options.allSatisfy { !$0.isRecommended })
    }
}

@Suite("Conflict options — the recommendation rule (§14.3.3)")
@MainActor
struct ConflictRecommendationTests {

    @Test("shiftLater if its minutes ≤ the occurrence's duration; else shorten if it keeps ≥ half; else skip",
          arguments: [
              // (shift, trimmed, duration, expected)
              (Optional(75), Optional(60), 90, ConflictOptionKind.shiftLater),
              (Optional(90), Optional(60), 90, .shiftLater),      // equal is proportionate
              (Optional(105), Optional(45), 90, .shorten),        // keeps exactly half
              (Optional(105), Optional(46), 90, .skipToday),      // keeps 44 < 45
              (nil, Optional(30), 60, .shorten),
              (nil, nil, 60, .skipToday),
          ])
    func rule(_ input: (Int?, Int?, Int, ConflictOptionKind)) {
        #expect(ConflictEngine.recommendedKind(
            shiftMinutes: input.0, shortenTrimmedMinutes: input.1, occurrenceMinutes: input.2) == input.3)
    }

    @Test("A recommended option that is not first exists in a real conflict (§14.3's 'not necessarily first')")
    func recommendedNotFirst() throws {
        let (_, context, _) = try makeStore()
        let c = try conflict(context, flexibility: .shiftable, shift: 90,
                             routine: (time(17), time(18, 30)), other: (time(17, 30), time(18, 15)))
        #expect(c.options.first?.isRecommended == false)
        #expect(c.options.contains { $0.isRecommended })
    }
}

@Suite("Conflict options — exact copy (§14.3.4)")
@MainActor
struct ConflictCopyTests {

    @Test("Lines 1 and 2 for all three kinds, word for word, on §14.3.4's own fixture")
    func exactCopy() throws {
        let (_, context, _) = try makeStore()
        let c = try conflict(context, flexibility: .shiftable, shift: 90,
                             routine: (time(17), time(18, 30)), other: (time(17, 30), time(18, 15)))
        let rows = Dictionary(uniqueKeysWithValues: c.options.map { option in
            (option.kind, (ConflictOptionFormatting.title(for: option, conflict: c),
                           ConflictOptionFormatting.delta(for: option, conflict: c)))
        })
        #expect(rows[.shiftLater]?.0 == "Shift Training 75 min later")
        #expect(rows[.shiftLater]?.1 == "17:00 → 18:15 · all 90 min kept")
        #expect(rows[.shorten]?.0 == "Shorten Training to 30 min")
        #expect(rows[.shorten]?.1 == "90 min → 30 min · 60 min lost")
        #expect(rows[.skipToday]?.0 == "Skip Training today")
        #expect(rows[.skipToday]?.1 == "Does not run today · 90 min lost · re-offered")
    }
}

@Suite("Conflict options — applying the recommended non-first option")
@MainActor
struct ConflictApplyRecommendedTests {

    @Test("Applying the recommended shiftLater (second row) moves the occurrence 75 min; one ⌘Z restores it")
    func applyRecommended() throws {
        let (store, context, undo) = try makeStore()
        let c = try conflict(context, flexibility: .shiftable, shift: 90,
                             routine: (time(17), time(18, 30)), other: (time(17, 30), time(18, 15)))
        let recommended = try #require(c.options.first { $0.isRecommended })

        let state = CalendarState()
        state.conflicts = [c]
        state.selectedConflictID = c.id
        state.selectedConflictOptionID = recommended.id
        #expect(state.applyFocusedConflictOption(store: store, recomputeConflicts: { [] }))

        #expect(c.routineEvent.start == time(18, 15))
        #expect(c.routineEvent.end == time(19, 45))
        #expect(undo.undoMenuTitle == "Undo Resolve Conflict")
        undo.undo()
        #expect(c.routineEvent.start == time(17))
        #expect(c.routineEvent.end == time(18, 30))
    }
}
