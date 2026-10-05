//
//  TemplateConflictTests.swift
//  KadenceTests
//
//  Task P2-T46: components.md §14.6 (template conflicts), §14.2's window
//  row copy, §13.6.2's third surface (the needs-attention count), and
//  interactions.md §10.1's routing (day conflicts first, template conflicts
//  open the Routines window). Fixture: §17.1's `Lunch` (protected,
//  Mon/Wed/Fri 12:00–13:00) × `Errands` (12:30, 45 min).
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

@MainActor
private func makeStore() throws -> (ModelContext, UndoStack) {
    let container = try ModelContainer(
        for: Schema(KadenceSchema.models),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return (ModelContext(container), UndoStack())
}

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.firstWeekday = 2
    return calendar
}()
/// Monday 5 October 2026.
private let today = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!
private let monFirst = [2, 3, 4, 5, 6, 7, 1]
private let mwf: Set<Int> = [2, 4, 6]

@MainActor
private func fixture(
    _ context: ModelContext, errandsAt start: Int = 12 * 60 + 30, minutes: Int = 45,
    lunch: (Int, Int) = (12 * 60, 13 * 60)
) -> (RoutineTemplate, RoutineBlock, TimeWindow) {
    let errands = RoutineBlock(title: "Errands", startMinutes: start, duration: TimeInterval(minutes * 60),
                               flexibility: .shiftable, shiftableMinutes: 90)
    let template = RoutineTemplate(name: "Daily routine", activeWeekdays: mwf, blocks: [errands])
    let window = TimeWindow(weekdays: mwf, startMinutes: lunch.0, endMinutes: lunch.1, kind: .protected, label: "Lunch")
    context.insert(template)
    context.insert(window)
    try? context.save()
    return (template, errands, window)
}

@MainActor
private func detect(_ context: ModelContext) -> [TemplateConflict] {
    TemplateConflictEngine.detect(
        templates: (try? context.fetch(FetchDescriptor<RoutineTemplate>())) ?? [],
        windows: (try? context.fetch(FetchDescriptor<TimeWindow>())) ?? [],
        orderedWeekdays: monFirst)
}

// MARK: - Detection and copy

@Suite("Template conflicts — detection and header copy (§14.6, §14.2)")
@MainActor
struct TemplateConflictDetectionTests {

    @Test("Errands × Lunch: one conflict, on Mon/Wed/Fri, overlap 12:30–13:00")
    func errandsLunch() throws {
        let (context, _) = try makeStore()
        fixture(context)
        let conflicts = detect(context)
        #expect(conflicts.count == 1)
        let c = try #require(conflicts.first)
        #expect(c.weekdays == [2, 4, 6])
        #expect(TemplateConflictEngine.overlapLine(c, calendar: calendar) == "12:30–13:00 · 30 min · Mon, Wed, Fri")
        #expect(TemplateConflictEngine.windowLine(c) == "protected · 12:00–13:00")
        #expect(TemplateConflictEngine.landsIn == "lands in")
    }

    @Test("Touching is not a conflict, and low-energy windows never are")
    func notConflicts() throws {
        let (context, _) = try makeStore()
        fixture(context, errandsAt: 13 * 60)
        context.insert(TimeWindow(weekdays: mwf, startMinutes: 13 * 60, endMinutes: 14 * 60, kind: .lowEnergy, label: "Slump"))
        try context.save()
        #expect(detect(context).isEmpty)
    }

    @Test("Only the template's ACTIVE weekdays are named")
    func activeOnly() throws {
        let (context, _) = try makeStore()
        let (template, _, _) = fixture(context)
        template.activeWeekdays = [2, 3]   // Mon, Tue; Lunch is Mon/Wed/Fri
        try context.save()
        #expect(detect(context).first?.weekdays == [2])
    }
}

// MARK: - Catalogue, cap, order, recommendation

@Suite("Template conflicts — the §14.6 catalogue, cap and tie-break")
@MainActor
struct TemplateConflictCatalogueTests {

    @Test("Errands × Lunch: shiftLater 30 and shorten 30 tie (kind order), shiftEarlier 75 is capped out, remove kept")
    func capAndTieBreak() throws {
        let (context, _) = try makeStore()
        fixture(context)
        let c = try #require(detect(context).first)
        #expect(c.options.map(\.kind) == [.shiftLater, .shorten, .remove])
        #expect(c.options.map(\.disturbanceMinutes) == [30, 30, 135])
        #expect(c.options.map(\.isRecommended) == [true, false, false], "30 ≤ 45 is proportionate")
    }

    @Test("§14.6's copy for shiftLater, shorten and remove, word for word")
    func copyLaterShortenRemove() throws {
        let (context, _) = try makeStore()
        fixture(context)
        let c = try #require(detect(context).first)
        let byKind = Dictionary(uniqueKeysWithValues: c.options.map { ($0.kind, $0) })
        let later = try #require(byKind[.shiftLater])
        let shorten = try #require(byKind[.shorten])
        let remove = try #require(byKind[.remove])
        #expect(TemplateConflictEngine.title(for: later, conflict: c) == "Shift Errands 30 min later in the routine")
        #expect(TemplateConflictEngine.delta(for: later, conflict: c) == "12:30 → 13:00 · all 45 min kept · every active day")
        #expect(TemplateConflictEngine.title(for: shorten, conflict: c) == "Shorten Errands to 15 min")
        #expect(TemplateConflictEngine.delta(for: shorten, conflict: c) == "45 min → 15 min · 30 min lost · every active day")
        #expect(TemplateConflictEngine.title(for: remove, conflict: c) == "Remove Errands from this routine")
        #expect(TemplateConflictEngine.delta(for: remove, conflict: c, calendar: calendar)
                == "Deletes the block · 135 min lost across Mon, Wed, Fri")
    }

    @Test("shiftEarlier is in the template catalogue; with later blocked it is kept, and its copy matches §14.6")
    func shiftEarlier() throws {
        let (context, _) = try makeStore()
        // Lunch widened to 12:00–15:00: later needs +150, earlier −75, no remainder to shorten.
        fixture(context, lunch: (12 * 60, 15 * 60))
        let c = try #require(detect(context).first)
        #expect(c.options.map(\.kind) == [.shiftEarlier, .remove, .shiftLater])
        #expect(c.options.map(\.disturbanceMinutes) == [75, 135, 150])
        let earlier = try #require(c.options.first)
        #expect(TemplateConflictEngine.title(for: earlier, conflict: c) == "Shift Errands 75 min earlier in the routine")
        #expect(TemplateConflictEngine.delta(for: earlier, conflict: c) == "12:30 → 11:15 · all 45 min kept · every active day")
        // Neither shift is ≤ 45 and nothing can be shortened: remove, the second row.
        #expect(c.options.map(\.isRecommended) == [false, true, false])
    }

    @Test("Shifts stay inside the day, and an option never trades one protected window for another")
    func clearsEverySpan() throws {
        let (context, _) = try makeStore()
        fixture(context)
        // A second protected window right after Lunch makes +30 land in it.
        context.insert(TimeWindow(weekdays: [4], startMinutes: 13 * 60, endMinutes: 13 * 60 + 30,
                                  kind: .protected, label: "Call"))
        try context.save()
        let lunchConflict = try #require(detect(context).first { $0.windowLabel == "Lunch" })
        let later = try #require(lunchConflict.options.first { $0.kind == .shiftLater })
        #expect(later.newStartMinutes == 13 * 60 + 30, "clears Lunch on Mon/Fri AND Call on Wed")
    }

    @Test("A conflict whose only option is remove carries no chip")
    func singleOptionNoChip() {
        // 00:05–00:25 inside a 00:15–23:45 window: no earlier (before 00:00),
        // no later (past 24:00), no remainder ≥ 15.
        let options = TemplateConflictEngine.options(
            conflictID: "x", start: 5, duration: 20, spans: [15..<1425], refusedWeekdayCount: 1)
        #expect(options.map(\.kind) == [.remove])
        #expect(options.allSatisfy { !$0.isRecommended })
    }

    @Test("Recommendation: proportionate shift either way, else a shorten keeping half, else remove")
    func recommendation() {
        typealias K = TemplateConflictOptionKind
        let r = TemplateConflictEngine.recommendedKind
        #expect(r([(K.shiftEarlier, 40, 45), (.remove, 135, nil)], 45) == .shiftEarlier)
        #expect(r([(K.shorten, 20, 25), (.shiftLater, 60, 45), (.remove, 90, nil)], 45) == .shorten)
        #expect(r([(K.shorten, 30, 15), (.shiftLater, 60, 45), (.remove, 90, nil)], 45) == .remove)
    }
}

// MARK: - Count and routing

@Suite("Template conflicts — count and routing (§13.6.2, interactions.md §10.1)")
@MainActor
struct TemplateConflictRoutingTests {

    @Test("The needs-attention count adds template conflicts to day conflicts")
    func counting() throws {
        let (context, _) = try makeStore()
        fixture(context)
        let state = CalendarState()
        state.templateConflicts = detect(context)
        #expect(state.needsAttentionCount == 1)
    }

    @Test("Routing: a template conflict alone opens the Routines window's request, not the main inspector")
    func routesToRoutinesWindow() throws {
        let (context, _) = try makeStore()
        fixture(context)
        let state = CalendarState()
        state.templateConflicts = detect(context)
        let target = state.activateNeedsAttention()
        #expect(target == .template(state.templateConflicts[0].id))
        #expect(state.pendingTemplateConflictID == state.templateConflicts[0].id)
        #expect(state.selectedConflictID == nil, "never shown in the main window")
    }

    @Test("Routing: day conflicts come first; nothing at all routes nowhere")
    func dayFirst() throws {
        let (context, _) = try makeStore()
        fixture(context)
        let templateConflicts = detect(context)
        #expect(CalendarState.needsAttentionTarget(day: [], template: [], preferring: nil) == nil)
        #expect(CalendarState.needsAttentionTarget(day: [], template: templateConflicts, preferring: nil)
                == .template(templateConflicts[0].id))

        let routine = Event(title: "Gym", start: today.addingTimeInterval(3600), end: today.addingTimeInterval(7200), origin: .routine)
        let meeting = Event(title: "Call", start: today.addingTimeInterval(5400), end: today.addingTimeInterval(9000))
        context.insert(routine)
        context.insert(meeting)
        let day = ConflictEngine.detect(events: [routine, meeting], routineBlocks: [])
        #expect(CalendarState.needsAttentionTarget(day: day, template: templateConflicts, preferring: nil) == .day(day[0].id))
    }
}

// MARK: - Apply and undo

@Suite("Template conflicts — apply is one 'Resolve Routine Conflict' step")
@MainActor
struct TemplateConflictApplyTests {

    @Test("shiftLater moves the block, re-materialises the freed days in the same step, and ⌘Z restores both")
    func applyShift() throws {
        let (context, undo) = try makeStore()
        let (template, errands, _) = fixture(context)
        let store = EventStore(context: context, undo: undo)
        let range = RoutineMaterialization.horizon(today: today, visibleEnd: nil, calendar: calendar)
        let windows = try context.fetch(FetchDescriptor<TimeWindow>())
        RoutineEngine.materialize(template: template, into: range, timeWindows: windows, today: today,
                                  recordsUndo: false, store: store, calendar: calendar)
        #expect(try context.fetch(FetchDescriptor<Event>()).isEmpty, "refused on every active day")

        let c = try #require(detect(context).first)
        let later = try #require(c.options.first { $0.kind == .shiftLater })
        #expect(TemplateConflictResolver.apply(later, of: c, context: context, undo: undo, today: today, calendar: calendar))

        #expect(errands.startMinutes == 13 * 60)
        #expect(undo.undoSteps.count == 1)
        #expect(undo.undoMenuTitle == "Undo Resolve Routine Conflict")
        let created = try context.fetch(FetchDescriptor<Event>())
        #expect(!created.isEmpty, "the freed Mon/Wed/Fri pairs materialise inside the step")
        #expect(detect(context).isEmpty)

        undo.undo()
        #expect(errands.startMinutes == 12 * 60 + 30)
        #expect(try context.fetch(FetchDescriptor<Event>()).isEmpty)
        #expect(detect(context).count == 1)
        undo.redo()
        #expect(errands.startMinutes == 13 * 60)
        #expect(try context.fetch(FetchDescriptor<Event>()).count == created.count)
    }

    @Test("shorten keeps the back remainder; remove deletes the block; each undoes in one step")
    func applyShortenAndRemove() throws {
        for kind in [TemplateConflictOptionKind.shorten, .remove] {
            let (context, undo) = try makeStore()
            let (template, errands, _) = fixture(context)
            let c = try #require(detect(context).first)
            let option = try #require(c.options.first { $0.kind == kind })
            TemplateConflictResolver.apply(option, of: c, context: context, undo: undo, today: today, calendar: calendar)

            if kind == .shorten {
                #expect(errands.startMinutes == 13 * 60)
                #expect(errands.duration == 15 * 60)
            } else {
                #expect(template.blocks.isEmpty)
            }
            #expect(undo.undoMenuTitle == "Undo Resolve Routine Conflict")
            undo.undo()
            #expect(template.blocks.count == 1)
            #expect(template.blocks.first?.startMinutes == 12 * 60 + 30)
            #expect(template.blocks.first?.duration == 45 * 60)
        }
    }
}
