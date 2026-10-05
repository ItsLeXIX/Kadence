//
//  RoutineMaterializationTests.swift
//  KadenceTests
//
//  Task P2-T40 — components.md §13.6.1 (protected windows refuse), §13.6.2
//  (the refusal is never silent: the inspector copy), and §13.6.5 (horizon,
//  triggers, the past). Unit-test fixtures only. The §17.1 capture
//  fixtures (Lunch / Errands in MockData) are P2-T48's.
//
//  Same in-memory ModelContainer pattern as RoutineEngineTests.swift. The
//  calendar is fixed to UTC with a POSIX English locale, so day arithmetic
//  has no DST transition and `shortWeekdaySymbols` are `Mon`, `Tue`, ….
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

@MainActor
private func allEvents(_ context: ModelContext) -> [Event] {
    (try? context.fetch(FetchDescriptor<Event>(sortBy: [SortDescriptor(\.start)]))) ?? []
}

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    calendar.locale = Locale(identifier: "en_US_POSIX")
    calendar.firstWeekday = 2
    return calendar
}()

// Calendar's weekday numbering: 1 = Sunday … 7 = Saturday.
private let sun = 1, mon = 2, tue = 3, wed = 4, thu = 5, fri = 6, sat = 7
private let everyDay: Set<Int> = Set(1...7)

/// Monday 5 October 2026, 00:00 UTC.
private let monday = calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!
private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: monday)! }
/// Monday through Sunday of that week.
private let oneWeek = DateInterval(start: monday, end: day(7))

private func block(_ title: String, at hour: Int, _ minute: Int = 0, minutes: Int,
                   flexibility: Flexibility = .fixed, shiftableMinutes: Int? = nil) -> RoutineBlock {
    RoutineBlock(title: title, startMinutes: hour * 60 + minute, duration: TimeInterval(minutes * 60),
                 flexibility: flexibility, shiftableMinutes: shiftableMinutes)
}

private func window(_ label: String, _ kind: TimeWindowKind = .protected, weekdays: Set<Int>,
                    from start: (Int, Int), to end: (Int, Int)) -> TimeWindow {
    TimeWindow(weekdays: weekdays, startMinutes: start.0 * 60 + start.1,
               endMinutes: end.0 * 60 + end.1, kind: kind, label: label)
}

@MainActor
@discardableResult
private func materialize(_ template: RoutineTemplate, windows: [TimeWindow] = [],
                         range: DateInterval = oneWeek, today: Date = monday,
                         store: EventStore) -> Int {
    RoutineEngine.materialize(template: template, into: range, timeWindows: windows,
                              today: today, store: store, calendar: calendar)
}

/// Weekday of each created event titled `title`, in date order.
@MainActor
private func weekdays(of title: String, in context: ModelContext) -> [Int] {
    allEvents(context).filter { $0.title == title }.map { calendar.component(.weekday, from: $0.start) }
}

// MARK: - §13.6.1 refusal

@Suite("Materialisation — protected windows refuse (components.md §13.6.1)")
@MainActor
struct ProtectedWindowRefusalTests {

    @Test("A pair that strictly overlaps a protected span produces no event, on exactly the colliding days")
    func refusesStrictOverlap() throws {
        let (store, context, _) = try makeStore()
        let errands = block("Errands", at: 12, 30, minutes: 45)
        let template = RoutineTemplate(name: "R", activeWeekdays: [mon, tue, wed, thu, fri], blocks: [errands])
        let lunch = window("Lunch", weekdays: [mon, wed, fri], from: (12, 0), to: (13, 0))
        context.insert(template)

        let created = materialize(template, windows: [lunch], store: store)

        #expect(created == 2)
        #expect(weekdays(of: "Errands", in: context) == [tue, thu])
    }

    @Test("Refusal is per pair: another block on the same day still materialises")
    func otherBlocksUnaffected() throws {
        let (store, context, _) = try makeStore()
        let errands = block("Errands", at: 12, 30, minutes: 45)
        let gym = block("Gym", at: 7, minutes: 60)
        let template = RoutineTemplate(name: "R", activeWeekdays: [mon], blocks: [errands, gym])
        let lunch = window("Lunch", weekdays: [mon], from: (12, 0), to: (13, 0))
        context.insert(template)

        materialize(template, windows: [lunch], store: store)

        #expect(allEvents(context).map(\.title) == ["Gym"])
    }

    @Test("A refused pair is not trimmed and not shifted: nothing of it exists anywhere that day")
    func notTrimmedOrShifted() throws {
        let (store, context, _) = try makeStore()
        // Only the first 15 minutes collide; a trim would keep 12:15–13:00.
        let errands = block("Errands", at: 11, 45, minutes: 75)
        let template = RoutineTemplate(name: "R", activeWeekdays: [mon], blocks: [errands])
        let lunch = window("Lunch", weekdays: [mon], from: (11, 0), to: (12, 0))
        context.insert(template)

        materialize(template, windows: [lunch], store: store)

        #expect(allEvents(context).isEmpty)
    }

    @Test("Touching endpoints are not an overlap", arguments: [
        (11, 30, 30),   // 11:30–12:00, ends as Lunch starts
        (13, 0, 30),    // 13:00–13:30, starts as Lunch ends
    ])
    func touchingIsAllowed(hour: Int, minute: Int, minutes: Int) throws {
        let (store, context, _) = try makeStore()
        let template = RoutineTemplate(
            name: "R", activeWeekdays: [mon], blocks: [block("B", at: hour, minute, minutes: minutes)])
        let lunch = window("Lunch", weekdays: [mon], from: (12, 0), to: (13, 0))
        context.insert(template)

        #expect(materialize(template, windows: [lunch], store: store) == 1)
    }

    @Test("Low-energy and peak-focus windows never block", arguments: [TimeWindowKind.lowEnergy, .peakFocus])
    func nonProtectedKindsNeverBlock(kind: TimeWindowKind) throws {
        let (store, context, _) = try makeStore()
        let template = RoutineTemplate(
            name: "R", activeWeekdays: [mon], blocks: [block("Study", at: 13, minutes: 60)])
        let preference = window("Pref", kind, weekdays: [mon], from: (12, 0), to: (15, 0))
        context.insert(template)

        #expect(materialize(template, windows: [preference], store: store) == 1)
    }

    @Test("A protected window not active on that weekday does not block")
    func windowWeekdaysRespected() throws {
        let (store, context, _) = try makeStore()
        let template = RoutineTemplate(
            name: "R", activeWeekdays: [tue], blocks: [block("Errands", at: 12, 30, minutes: 45)])
        let lunch = window("Lunch", weekdays: [mon], from: (12, 0), to: (13, 0))
        context.insert(template)

        #expect(materialize(template, windows: [lunch], store: store) == 1)
    }
}

// MARK: - Cross-midnight protected spans

@Suite("Materialisation — cross-midnight protected windows (Sleep 22:00–07:00)")
@MainActor
struct CrossMidnightRefusalTests {

    /// Interactions.md §11.1 / G-013: a block never crosses midnight, so it
    /// is compared against the window's spans on its own day only: the
    /// evening part of today's window and the morning part of yesterday's.
    @Test("Every-day Sleep: which blocks run", arguments: [
        (6, 0, 30, false),    // 06:00–06:30, inside the morning half
        (6, 45, 30, false),   // 06:45–07:15, straddles 07:00
        (7, 0, 60, true),     // 07:00–08:00, touches the end
        (21, 30, 30, true),   // 21:30–22:00, touches the start
        (21, 45, 30, false),  // 21:45–22:15, straddles 22:00
        (23, 0, 30, false),   // 23:00–23:30, inside the evening half
        (0, 0, 15, false),    // 00:00–00:15, first minutes of the day
    ])
    func everyDaySleep(hour: Int, minute: Int, minutes: Int, runs: Bool) throws {
        let (store, context, _) = try makeStore()
        let template = RoutineTemplate(
            name: "R", activeWeekdays: everyDay, blocks: [block("B", at: hour, minute, minutes: minutes)])
        let sleep = window("Sleep", weekdays: everyDay, from: (22, 0), to: (7, 0))
        context.insert(template)

        #expect(materialize(template, windows: [sleep], store: store) == (runs ? 7 : 0))
    }

    @Test("The morning half belongs to the previous weekday's window")
    func morningHalfFromPreviousDay() throws {
        let (store, context, _) = try makeStore()
        // Sleep only on Sunday night: Sunday 22:00 → Monday 07:00.
        let sleep = window("Sleep", weekdays: [sun], from: (22, 0), to: (7, 0))
        let early = block("Early", at: 6, minutes: 30)
        let late = block("Late", at: 23, minutes: 30)
        let template = RoutineTemplate(name: "R", activeWeekdays: [sun, mon], blocks: [early, late])
        context.insert(template)

        materialize(template, windows: [sleep], store: store)

        // Monday 06:00 is inside Sunday's window; Sunday 06:00 is not (no
        // Saturday window). Sunday 23:00 is inside; Monday 23:00 is not.
        #expect(weekdays(of: "Early", in: context) == [sun])
        #expect(weekdays(of: "Late", in: context) == [mon])
    }

    @Test("Saturday's window reaches into Sunday morning (weekday wrap 7 → 1)")
    func saturdayWrapsIntoSunday() {
        let sleep = window("Sleep", weekdays: [sat], from: (22, 0), to: (7, 0))
        #expect(ProtectedWindowRule.minuteSpans(of: sleep, onWeekday: sun) == [0..<420])
        #expect(ProtectedWindowRule.minuteSpans(of: sleep, onWeekday: sat) == [1320..<1440])
        #expect(ProtectedWindowRule.minuteSpans(of: sleep, onWeekday: mon).isEmpty)
    }
}

// MARK: - §13.6.5 the past, idempotency, horizon

@Suite("Materialisation — the past, idempotency and the horizon (components.md §13.6.5)")
@MainActor
struct MaterializationHorizonTests {

    @Test("Nothing is written before startOfDay(today), even when the range starts in the past")
    func pastIsNeverWritten() throws {
        let (store, context, _) = try makeStore()
        let template = RoutineTemplate(
            name: "R", activeWeekdays: everyDay, blocks: [block("Gym", at: 7, minutes: 60)])
        context.insert(template)
        let today = day(3).addingTimeInterval(15 * 3600)   // Thursday 15:00

        let created = materialize(template, range: oneWeek, today: today, store: store)

        // Thu, Fri, Sat, Sun. Today's 07:00 instance counts: the rule is
        // about days, and today is not before startOfDay(today).
        #expect(created == 4)
        #expect(allEvents(context).allSatisfy { $0.start >= calendar.startOfDay(for: today) })
        #expect(allEvents(context).first?.start == day(3).addingTimeInterval(7 * 3600))
    }

    @Test("A range entirely in the past writes nothing")
    func wholeRangeInPast() throws {
        let (store, context, _) = try makeStore()
        let template = RoutineTemplate(
            name: "R", activeWeekdays: everyDay, blocks: [block("Gym", at: 7, minutes: 60)])
        context.insert(template)

        #expect(materialize(template, range: oneWeek, today: day(10), store: store) == 0)
        #expect(allEvents(context).isEmpty)
    }

    @Test("Re-running never duplicates, and the key is (sourceID, externalID), not the time")
    func idempotentByIdentity() throws {
        let (store, context, _) = try makeStore()
        let template = RoutineTemplate(
            name: "R", activeWeekdays: [mon, wed], blocks: [block("Gym", at: 7, minutes: 60)])
        context.insert(template)

        #expect(materialize(template, store: store) == 2)
        // Moving an instance changes its time but not its identity, so the
        // next pass must not see an "empty" 07:00 slot and fill it again.
        // Since P2-T41 (§13.6.3 row 2) the pass instead UPDATES the
        // non-detached instance back to the template's 07:00.
        let first = try #require(allEvents(context).first)
        let firstID = first.id
        let templateStart = first.start
        first.start = first.start.addingTimeInterval(3600)
        first.end = first.end.addingTimeInterval(3600)
        try context.save()

        #expect(materialize(template, store: store) == 0)
        #expect(allEvents(context).count == 2)
        let keys = allEvents(context).map { "\($0.sourceID ?? "")|\($0.externalID ?? "")" }
        #expect(Set(keys).count == keys.count)
        #expect(allEvents(context).first { $0.id == firstID }?.start == templateStart)
    }

    @Test("Horizon: today through today + 28 when the visible range ends sooner")
    func horizonMinimum() {
        let today = day(2).addingTimeInterval(9 * 3600)   // Wednesday 09:00
        let visibleEnd = day(7)                             // the week's exclusive end

        let horizon = RoutineMaterialization.horizon(today: today, visibleEnd: visibleEnd, calendar: calendar)

        #expect(horizon.start == day(2))
        #expect(horizon.end == day(2 + 29))
        #expect(RoutineMaterialization.horizon(today: today, visibleEnd: nil, calendar: calendar) == horizon)
    }

    @Test("Horizon: visible range end + 7 when that is later")
    func horizonFollowsVisibleRange() {
        let visibleEnd = day(42)   // paged six weeks ahead

        let horizon = RoutineMaterialization.horizon(today: monday, visibleEnd: visibleEnd, calendar: calendar)

        #expect(horizon.start == monday)
        #expect(horizon.end == day(49))
    }

    @Test("Horizon: a visible range in the past never moves the start back")
    func horizonPastVisibleRange() {
        let horizon = RoutineMaterialization.horizon(today: monday, visibleEnd: day(-30), calendar: calendar)
        #expect(horizon == DateInterval(start: monday, end: day(29)))
    }

    @Test("run() fills exactly the horizon: first instance today, last on today + 28")
    func runBounds() throws {
        let (_, context, undo) = try makeStore()
        context.insert(RoutineTemplate(
            name: "R", activeWeekdays: everyDay, blocks: [block("Gym", at: 7, minutes: 60)]))
        try context.save()

        let created = RoutineMaterialization.run(
            context: context, undo: undo, visibleEnd: nil, today: monday, calendar: calendar)

        let events = allEvents(context)
        #expect(created == 29)
        #expect(events.first.map { calendar.startOfDay(for: $0.start) } == monday)
        #expect(events.last.map { calendar.startOfDay(for: $0.start) } == day(28))
    }

    @Test("run() refuses with the store's own protected windows, records no undo step, and is idempotent")
    func runIsBackgroundAndIdempotent() throws {
        let (_, context, undo) = try makeStore()
        context.insert(RoutineTemplate(
            name: "R", activeWeekdays: [mon, tue],
            blocks: [block("Errands", at: 12, 30, minutes: 45)]))
        context.insert(window("Lunch", weekdays: [mon], from: (12, 0), to: (13, 0)))
        try context.save()

        let first = RoutineMaterialization.run(
            context: context, undo: undo, visibleEnd: day(7), today: monday, calendar: calendar)
        let second = RoutineMaterialization.run(
            context: context, undo: undo, visibleEnd: day(7), today: monday, calendar: calendar)

        // Tuesdays only, Mon 5 Oct through day +28 (Mon 2 Nov): 6, 13, 20
        // and 27 Oct. Day +29 (Tue 3 Nov) is the exclusive end.
        #expect(first == 4)
        #expect(second == 0)
        #expect(allEvents(context).count == 4)
        #expect(Set(weekdays(of: "Errands", in: context)) == [tue])
        #expect(undo.undoSteps.isEmpty, "background materialisation must not land on the Edit menu")
    }

    @Test("Inside an open undo step, materialize joins it instead of pushing its own")
    func joinsOpenStep() throws {
        let (store, context, undo) = try makeStore()
        let template = RoutineTemplate(
            name: "R", activeWeekdays: [mon], blocks: [block("Gym", at: 7, minutes: 60)])
        context.insert(template)

        undo.perform("Add Monday to Routine") { _ in
            materialize(template, store: store)
        }

        #expect(undo.undoSteps.map(\.name) == ["Add Monday to Routine"])
        undo.undo()
        #expect(allEvents(context).isEmpty)
    }
}

// MARK: - §13.6.2 the inspector line

@Suite("Refusal surfaces — the template-vs-window comparison and its copy (components.md §13.6.2)")
@MainActor
struct RefusalSurfaceTests {

    private let monFirst = [mon, tue, wed, thu, fri, sat, sun]

    @Test("Errands × Lunch on Mon/Wed/Fri: one refusal naming the window and the days, in column order")
    func refusalNamesWindowAndDays() throws {
        let lunch = window("Lunch", weekdays: [fri, wed, mon], from: (12, 0), to: (13, 0))

        let refusals = ProtectedWindowRule.refusals(
            startMinutes: 12 * 60 + 30, duration: 45 * 60,
            activeWeekdays: [mon, tue, wed, thu, fri], orderedWeekdays: monFirst, windows: [lunch])

        let refusal = try #require(refusals.first)
        #expect(refusals.count == 1)
        #expect(refusal.weekdays == [mon, wed, fri])
        #expect(ProtectedWindowRule.inspectorLabel + " " + ProtectedWindowRule.inspectorValue(for: refusal, calendar: calendar)
                == "Will not run — inside Lunch (protected) on Mon, Wed, Fri")
    }

    @Test("Only active weekdays are named: an inactive day is not a day the block won't run")
    func onlyActiveWeekdays() {
        let lunch = window("Lunch", weekdays: [mon, wed, fri], from: (12, 0), to: (13, 0))

        let refusals = ProtectedWindowRule.refusals(
            startMinutes: 12 * 60 + 30, duration: 45 * 60,
            activeWeekdays: [mon, tue], orderedWeekdays: monFirst, windows: [lunch])

        #expect(refusals.map(\.weekdays) == [[mon]])
    }

    @Test("Cross-midnight Sleep names the right days, and non-protected windows never appear")
    func sleepAndNonProtected() {
        let sleep = window("Sleep", weekdays: [sun], from: (22, 0), to: (7, 0))
        let lowEnergy = window("Low energy", .lowEnergy, weekdays: everyDay, from: (5, 0), to: (8, 0))

        let refusals = ProtectedWindowRule.refusals(
            startMinutes: 6 * 60, duration: 30 * 60,
            activeWeekdays: everyDay, orderedWeekdays: monFirst, windows: [sleep, lowEnergy])

        #expect(refusals.map(\.label) == ["Sleep"])
        #expect(refusals.first?.weekdays == [mon])
    }

    @Test("The canvas's per-column test and materialize agree on every weekday")
    func canvasAgreesWithMaterialize() throws {
        let (store, context, _) = try makeStore()
        let errands = block("Errands", at: 12, 30, minutes: 45)
        let template = RoutineTemplate(name: "R", activeWeekdays: everyDay, blocks: [errands])
        let lunch = window("Lunch", weekdays: [mon, wed, fri], from: (12, 0), to: (13, 0))
        context.insert(template)

        materialize(template, windows: [lunch], store: store)
        let materialized = Set(weekdays(of: "Errands", in: context))

        for weekday in 1...7 {
            let conflicted = ProtectedWindowRule.refuses(
                startMinutes: errands.startMinutes, duration: errands.duration, weekday: weekday, windows: [lunch])
            #expect(conflicted != materialized.contains(weekday))
        }
    }
}

// MARK: - ConflictEngine on real materialised events

@Suite("ConflictEngine against materialised routine events")
@MainActor
struct ConflictEngineOnMaterializedTests {

    @MainActor
    private func materializedInstance(_ routineBlock: RoutineBlock) throws -> (ModelContext, Event, [RoutineBlock]) {
        let (store, context, _) = try makeStore()
        let template = RoutineTemplate(name: "R", activeWeekdays: [mon], blocks: [routineBlock])
        context.insert(template)
        materialize(template, store: store)
        let event = try #require(allEvents(context).first)
        return (context, event, template.blocks)
    }

    @Test(".shiftable: the block's ± is found by reversing the materialised externalID")
    func shiftLaterFromExternalID() throws {
        let training = block("Training", at: 17, minutes: 45, flexibility: .shiftable, shiftableMinutes: 30)
        let (context, routine, blocks) = try materializedInstance(training)
        let call = Event(title: "Call", start: monday.addingTimeInterval(16.75 * 3600),
                         end: monday.addingTimeInterval(17.25 * 3600), origin: .manual)
        context.insert(call)

        let conflicts = ConflictEngine.detect(events: [routine, call], routineBlocks: blocks)

        let shift = try #require(conflicts.first?.options.first { $0.kind == .shiftLater })
        #expect(conflicts.count == 1)
        #expect(shift.newStart == monday.addingTimeInterval(17.25 * 3600))
    }

    @Test(".fixed: shorten and skip, recommendation per §14.3.3")
    func fixedShortenAndSkip() throws {
        let review = block("Focus review", at: 20, minutes: 60)
        let (context, routine, blocks) = try materializedInstance(review)
        let call = Event(title: "Client call", start: monday.addingTimeInterval(19 * 3600 + 50 * 60),
                         end: monday.addingTimeInterval(20 * 3600 + 20 * 60), origin: .manual)
        context.insert(call)

        let conflict = try #require(ConflictEngine.detect(events: [routine, call], routineBlocks: blocks).first)

        #expect(conflict.options.map(\.kind) == [.shorten, .skipToday])
        #expect(conflict.options.first?.isRecommended == true)
    }
}

// MARK: - Mock data through the template

@Suite("MockData — routine events come from the template (task P2-T40)")
@MainActor
struct MockDataMaterializationTests {

    /// Uses `Calendar.current`, because `MockData.makeEvents` and the app's
    /// own run do. 12:00 on a Monday (template day) and on a Thursday (not).
    @Test("Seeding + the launch pass: no duplicates, the conflict fixtures survive, Gym carries 'skipped'",
          arguments: [5, 8])
    func seededStore(dayOfMonth: Int) throws {
        let (_, context, undo) = try makeStore()
        let now = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: dayOfMonth, hour: 12))!

        MockData.seedAllIfNeeded(context, now: now) {
            RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: now)
        }
        let events = allEvents(context)

        // No hand-seeded copy of a template block remains.
        let templateTitles: Set<String> = ["Gym", "Morning review", "Reading", "Training", "Errands"]
        #expect(events.filter { templateTitles.contains($0.title) }.allSatisfy { $0.externalID?.contains("#") == true })
        let keys = events.compactMap { event in event.externalID.map { "\(event.sourceID ?? "")|\($0)" } }
        #expect(Set(keys).count == keys.count)
        // The P2-T29 / P2-T32 conflict fixtures are unchanged.
        #expect(events.filter { $0.title == "Focus review" }.count == 1)
        #expect(events.filter { $0.title == "Client call" }.count == 1)
        // P2-T48: §17.1's Training × Supervisor meeting, plus (on a Mon/Wed/Fri
        // today) Training × Group call and × Code review.
        #expect(MainWindow.sortedConflicts(events: events, routineBlocks: try context.fetch(FetchDescriptor<RoutineBlock>())).count
                == (dayOfMonth == 5 ? 15 : 13))
        // Errands never materialises: Lunch refuses it on every active day.
        #expect(!events.contains { $0.title == "Errands" })
        // §12 item 14's skipped state is on exactly one template Gym instance.
        let skippedGyms = events.filter { $0.title == "Gym" && $0.status == .skipped }
        #expect(skippedGyms.count == 1)
        #expect(undo.undoSteps.isEmpty)

        // A second launch adds nothing.
        let before = events.count
        MockData.seedAllIfNeeded(context, now: now) {
            RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: now)
        }
        #expect(allEvents(context).count == before)
    }
}
