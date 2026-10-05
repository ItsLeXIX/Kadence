//
//  MockData.swift
//  Kadence
//
//  components.md §12 — every variant and every state on one day grid, so the
//  spec can actually be checked. Display fixtures only: no TravelLeg
//  computation, no routine engine, no work item model behind them.
//

import Foundation
import SwiftData

enum MockData {

    static let sources: [CalendarSource] = [
        CalendarSource(id: "timetable", name: "University timetable", key: .blue,
                       kind: .universityTimetable, symbolOverride: nil),
        CalendarSource(id: "exams", name: "Exams", key: .teal,
                       kind: .exams, symbolOverride: nil),
        CalendarSource(id: "routine", name: "Daily routine", key: .green,
                       kind: .routine, symbolOverride: nil),
        CalendarSource(id: "mail", name: "Mail appointments", key: .amber,
                       kind: .mail, symbolOverride: nil),
        CalendarSource(id: "deadlines", name: "Coursework", key: .orange,
                       kind: .coursework, symbolOverride: nil),
        CalendarSource(id: "social", name: "Social", key: .pink,
                       kind: .other, symbolOverride: nil),
        CalendarSource(id: "study", name: "Planned study", key: .purple,
                       kind: .plannedStudy, symbolOverride: nil),
        CalendarSource(id: "personal", name: "Personal", key: .graphite,
                       kind: .manual, symbolOverride: nil),
    ]

    static let timeWindows: [TimeWindowFixture] = [
        TimeWindowFixture(
            weekdays: Set(1...7),
            startMinutes: 22 * 60,
            endMinutes: 7 * 60,
            kind: .protected,
            label: "Sleep"),
        TimeWindowFixture(
            weekdays: [2, 3, 4, 5, 6],
            startMinutes: 13 * 60,
            endMinutes: 14 * 60 + 30,
            kind: .lowEnergy,
            label: "Low energy"),
    ]

    // MARK: Seeding

    /// Inserts the fixture events if the store is empty. Idempotent: a second
    /// launch does not duplicate them.
    @MainActor
    static func seedIfNeeded(_ context: ModelContext, now: Date = Date()) -> MockFixtures {
        removeUntitledEvents(context)
        let existing = (try? context.fetch(FetchDescriptor<Event>())) ?? []
        if existing.isEmpty {
            for event in makeEvents(now: now) {
                context.insert(event)
            }
            try? context.save()
        }
        let events = (try? context.fetch(FetchDescriptor<Event>())) ?? []
        return MockFixtures(
            travel: makeTravel(for: events, now: now),
            allDay: makeAllDay(now: now),
            windows: timeWindows)
    }

    /// Repair for stores written before creation became commit-or-discard.
    ///
    /// interactions.md §3 makes "an event with no title" impossible to create,
    /// so any that exist came from the older insert-immediately path
    /// (DEVIATIONS.md A13) and are garbage rather than data. Cheap to run, and it
    /// keeps a store that predates the fix from carrying the problem forward.
    @MainActor
    static func removeUntitledEvents(_ context: ModelContext) {
        let all = (try? context.fetch(FetchDescriptor<Event>())) ?? []
        let untitled = all.filter {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        guard !untitled.isEmpty else { return }
        for event in untitled { context.delete(event) }
        try? context.save()
    }

    // MARK: Events — items 1–6, 11–14 of §12

    @MainActor
    static func makeEvents(now: Date) -> [Event] {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: now)
        func at(_ hour: Int, _ minute: Int = 0, plusDays: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: plusDays, to: day) ?? day
            return base.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
        }

        var events: [Event] = []

        // 1. Imported lecture, 90 min, blue, with a location so it gets a travel band.
        events.append(Event(
            title: "Datenmodellierung",
            start: at(9), end: at(10, 30),
            origin: .imported, sourceKey: .blue,
            location: Place(name: "FH B.2.09"),
            sourceID: "timetable", externalID: "dm-lecture-01"))

        // 2. Manual event, 45 min, graphite, with a location.
        events.append(Event(
            title: "Coffee with Nora",
            start: at(11), end: at(11, 45),
            origin: .manual, sourceKey: .graphite,
            location: Place(name: "Café Sperl")))

        // 3–5. Routine blocks, one per flexibility.
        //     Task P2-T40: "Morning review" (.fixed) and "Reading" (.droppable)
        //     are no longer hand-seeded here. The "Daily routine" template
        //     (`makeRoutineTemplates`) produces both, plus "Gym" (.shiftable),
        //     through `RoutineEngine.materialize` on Mon/Wed/Fri. Seeding them
        //     here as well would put two of each on those days. "Training"
        //     stays: no template produces it, so it is still a hand-seeded
        //     `.routine` event with no `(sourceID, externalID)`.
        events.append(Event(
            title: "Training",
            start: at(17), end: at(17, 45),
            origin: .routine, flexibility: .shiftable, sourceKey: .green))

        // 6. Planned study session, 90 min, purple.
        events.append(Event(
            title: "Prep: relational algebra",
            start: at(14, 30), end: at(16),
            origin: .planned, flexibility: .droppable, sourceKey: .purple))

        // 11. A 15-minute block and a 10-minute block (density tiers 11–15 and clamped).
        events.append(Event(
            title: "Stand-up",
            start: at(12, 30), end: at(12, 45),
            origin: .manual, sourceKey: .graphite))
        events.append(Event(
            title: "Check mail",
            start: at(12, 50), end: at(13),
            origin: .manual, sourceKey: .amber))

        // 12. Three mutually overlapping blocks, to exercise column packing in Day.
        events.append(Event(
            title: "Group call",
            start: at(18), end: at(19, 30),
            origin: .manual, sourceKey: .pink))
        events.append(Event(
            title: "Code review",
            start: at(18, 15), end: at(19),
            origin: .manual, sourceKey: .blue))
        events.append(Event(
            title: "Notes write-up",
            start: at(18, 45), end: at(19, 45),
            origin: .planned, flexibility: .droppable, sourceKey: .purple))

        // 13. Six mutually overlapping blocks tomorrow, to exercise cascade in Week.
        for index in 0..<6 {
            events.append(Event(
                title: "Overlap \(index + 1)",
                start: at(10, index * 10, plusDays: 1),
                end: at(11, index * 10 + 30, plusDays: 1),
                origin: .manual, sourceKey: SourceKey.slot(index)))
        }

        // 14. One block in each of conflicted, past, inProgress, done, skipped.
        //     `conflicted` has no stored flag in Phase 1 — conflict detection is
        //     Phase 2 — so it is derived at render time from a genuine overlap
        //     with a protected window (22:00–07:00), which is what item 15 sets up.
        events.append(Event(
            title: "Late lab session",       // lands inside the protected window
            start: at(22, 30), end: at(23, 30),
            origin: .manual, sourceKey: .blue))
        events.append(Event(
            title: "Breakfast",              // past
            start: at(7, 15), end: at(7, 45),
            origin: .routine, flexibility: .fixed, sourceKey: .green))
        events.append(Event(
            title: "Statistik übung",        // done
            start: at(10, 45), end: at(11, 45),
            origin: .imported, status: .done, sourceKey: .blue,
            sourceID: "timetable", externalID: "stat-ue-04"))
        // "skipped" — task P2-T40: no longer a hand-seeded "Gym" at 16:15.
        // The template's own Gym instance carries it instead; see
        // `skipFirstGymInstance`.

        // 16. A day with nothing on it at all — two days out is deliberately empty.

        // 17. Task P2-T29 addition (components.md §17 item 6, the two-option
        //     half only — see DEVIATIONS.md for the three-option and
        //     recommended-not-first halves, which `ConflictEngine` cannot
        //     produce without an engine change, so are not attempted here).
        //     A `.fixed` routine block overlapping a manual event: `.fixed`
        //     reaches `ConflictEngine.makeOptions`'s `.shorten` branch, which
        //     needs no `RoutineBlock`/`externalID` wiring (unlike `.shiftable`'s
        //     `.shiftLater`, which does), so a plain seeded pair is enough —
        //     no new `RoutineTemplate`/`RoutineBlock` fixture required. Times
        //     chosen so neither event touches any existing fixture in this
        //     list: "Notes write-up" ends 19:45, "Reading" (routine,
        //     droppable) starts 21:00, and this pair sits strictly between
        //     them. Overlap: 20:00–20:20 (20 min). `shortenOption` keeps the
        //     back half (20:20–21:00, 40 min, comfortably clear of the
        //     15-minute floor) — trims 20 min — so the panel shows exactly
        //     two rows: `Shorten … by 20 min` (recommended, 20 < 60) and
        //     `Skip today's …` (60 min disturbance) second.
        events.append(Event(
            title: "Client call",
            start: at(19, 50), end: at(20, 20),
            origin: .manual, sourceKey: .amber))
        events.append(Event(
            title: "Focus review",
            start: at(20), end: at(21),
            origin: .routine, flexibility: .fixed, sourceKey: .green))

        // 18. Task P2-T32 addition (components.md §17 item 9 — the sidebar
        //     needs-attention row at a count of 12). Item 17 above already
        //     gives exactly one `Conflict` (today's "Client call"/"Focus
        //     review" pair). Eleven more are added here, one pair per day
        //     from `plusDays: 2` through `plusDays: 12` — days nothing above
        //     ever places a timed event on (items 1–17 only ever use
        //     `plusDays: 0` or `plusDays: 1`), so this cannot change the
        //     layout of any existing capture or test that reads today's or
        //     tomorrow's grid. Each pair reuses item 17's own shape verbatim
        //     (a `.manual` event 19:50–20:20 overlapping a `.fixed`
        //     `.routine` event 20:00–21:00 — a 20-minute overlap,
        //     `ConflictEngine.detect`'s `.shorten` branch, same reasoning as
        //     item 17's own comment for why no `RoutineTemplate`/
        //     `RoutineBlock` wiring is needed) so `ConflictEngine.detect`
        //     yields exactly one additional `Conflict` per day added. Total:
        //     1 (item 17) + 11 (here) = 12, `state.conflicts.count == 12`,
        //     which is what this task needed to review the badge at that
        //     count. See STATUS.md/DEVIATIONS.md for the task this served.
        for dayOffset in 2...12 {
            events.append(Event(
                title: "Fixture call \(dayOffset)",
                start: at(19, 50, plusDays: dayOffset), end: at(20, 20, plusDays: dayOffset),
                origin: .manual, sourceKey: .amber))
            events.append(Event(
                title: "Fixture review \(dayOffset)",
                start: at(20, plusDays: dayOffset), end: at(21, plusDays: dayOffset),
                origin: .routine, flexibility: .fixed, sourceKey: .green))
        }

        // 19. Task P2-T33/P2-T34 addition (components.md §17 item 10 — the
        //     menu bar status item's Normal/Late states, components.md
        //     §15.1). P2-T33's version hardcoded `at(23, 35)`/`at(23, 50)`
        //     (today's wall-clock 23:35–23:50), which only reproduces Normal
        //     if captured before that clock time and Late only a few minutes
        //     after — fragile on any later cycle. Using offsets relative to
        //     `now` itself instead removes that dependency: the event always
        //     starts a few minutes after seeding, whatever time seeding runs.
        //     4–19 minutes keeps it clear of every other `at(...)`-based
        //     today fixture above regardless of wall-clock time, since none
        //     of them fall in the few-minutes window right after `now`.
        //     `.manual`/`.graphite`, matching `Coffee with Nora`/`Stand-up`.
        //     See STATUS.md/screenshots/2/INDEX.md (batch 5) for the capture
        //     method — reaching the actual Normal/Late/Empty states also
        //     needs every *other* today event's `status` toggled to `.done`,
        //     done directly against the ephemeral SQLite store, never here.
        //
        //     Task P2-T41: `now + 4` alone collided with routine fixtures at
        //     some times of day (`Training` if seeded 16:41–17:45, `Focus
        //     review` / `Reading` in the evening). That conflict then sorted
        //     first, and what the needs-attention row opened depended on the
        //     clock (DEVIATIONS.md B18). `journalStart` keeps "a few minutes
        //     after `now`" but skips forward past anything a conflict could
        //     involve, so Journal never creates or joins one.
        let journalStart = journalStart(
            now: now,
            busy: conflictBusyIntervals(events: events, now: now, calendar: calendar))
        events.append(Event(
            title: "Journal",
            start: journalStart, end: journalStart.addingTimeInterval(journalDuration),
            origin: .manual, sourceKey: .graphite))

        return events
    }

    /// Journal's length: 15 minutes, as P2-T34 seeded it (`now + 4 … now + 19`).
    static let journalDuration: TimeInterval = 15 * 60
    /// "A few minutes after seeding" (P2-T34): the earliest Journal may start.
    static let journalLead: TimeInterval = 4 * 60

    /// The earliest start at or after `now + journalLead` where a
    /// `journalDuration` block overlaps none of `busy`. Each overlap pushes
    /// the candidate to the end of the interval it hit, so the loop always
    /// moves forward and ends after at most `busy.count` pushes.
    static func journalStart(now: Date, busy: [DateInterval]) -> Date {
        var start = now.addingTimeInterval(journalLead)
        while let hit = busy.first(where: {
            $0.start < start.addingTimeInterval(journalDuration) && start < $0.end
        }) {
            start = hit.end
        }
        return start
    }

    /// Everything a manual Journal could form a conflict with, or join one
    /// through: every hand-seeded `.routine` event, every event that overlaps
    /// one (a conflict fixture's other half, e.g. `Client call`), and the
    /// routine template's blocks on today and tomorrow (the instances the
    /// launch pass will materialise; tomorrow because a late-evening Journal
    /// can run past midnight). `ConflictEngine` only pairs a `.routine`
    /// event with something else, so this is the whole set.
    @MainActor
    static func conflictBusyIntervals(events: [Event], now: Date, calendar: Calendar) -> [DateInterval] {
        let routine = events.filter { $0.origin == .routine }
        var busy = routine.map { DateInterval(start: $0.start, end: $0.end) }
        for event in events where event.origin != .routine {
            if routine.contains(where: { $0.start < event.end && event.start < $0.end }) {
                busy.append(DateInterval(start: event.start, end: event.end))
            }
        }
        let today = calendar.startOfDay(for: now)
        for template in makeRoutineTemplates() {
            for offset in 0...1 {
                guard let day = calendar.date(byAdding: .day, value: offset, to: today),
                      template.activeWeekdays.contains(calendar.component(.weekday, from: day))
                else { continue }
                for block in template.blocks {
                    let start = day.addingTimeInterval(TimeInterval(block.startMinutes * 60))
                    busy.append(DateInterval(start: start, duration: block.duration))
                }
            }
        }
        return busy
    }

    // MARK: Seeding everything + the launch pass (task P2-T40)

    /// Both windows' launch `.task`: seed whatever is missing, then run the
    /// launch materialisation trigger (components.md §13.6.5), then (on a
    /// freshly seeded store only) apply the one fixture that lives on a
    /// materialised instance.
    ///
    /// Order matters. `seedIfNeeded` only seeds an *empty* `Event` store, so
    /// emptiness has to be checked before anything materialises. Otherwise
    /// opening the Routines window first (⌘⌥R, before `MainWindow`'s `.task`)
    /// would fill the store with routine instances, and the hand-seeded
    /// fixtures would never arrive. That is why both windows call this one
    /// function rather than each seeding their own part.
    ///
    /// `materialize` is passed in as a closure (like a callback parameter in
    /// Java/C#), so this mock-data file doesn't need to know the horizon or
    /// the undo stack. The caller passes `RoutineMaterialization.run`.
    @MainActor
    @discardableResult
    static func seedAllIfNeeded(
        _ context: ModelContext, now: Date = Date(), materialize: () -> Void
    ) -> MockFixtures {
        let storeWasEmpty = ((try? context.fetchCount(FetchDescriptor<Event>())) ?? 0) == 0
        seedRoutineTemplatesIfNeeded(context)
        seedTimeWindowsIfNeeded(context)
        let fixtures = seedIfNeeded(context, now: now)
        materialize()
        if storeWasEmpty { skipFirstGymInstance(context, now: now) }
        return fixtures
    }

    /// components.md §12 item 14's `skipped` state used to be a hand-seeded
    /// `.routine` "Gym" at 16:15 today. The template produces "Gym" now, so
    /// the state moves onto the template's first Gym instance from today on
    /// (Mon/Wed/Fri at 07:00). Status doesn't detach an instance
    /// (components.md §13.7.1), so this is an ordinary skipped occurrence of
    /// the routine.
    @MainActor
    static func skipFirstGymInstance(_ context: ModelContext, now: Date) {
        let templates = (try? context.fetch(FetchDescriptor<RoutineTemplate>())) ?? []
        guard let gym = templates.lazy.flatMap(\.blocks).first(where: { $0.title == "Gym" }) else { return }
        let prefix = gym.id.uuidString + "#"
        let today = Calendar.current.startOfDay(for: now)
        let events = (try? context.fetch(FetchDescriptor<Event>(sortBy: [SortDescriptor(\.start)]))) ?? []
        guard let first = events.first(where: {
            $0.start >= today && ($0.externalID?.hasPrefix(prefix) ?? false)
        }) else { return }
        first.status = .skipped
        try? context.save()
    }

    // MARK: Travel bands — items 7–8

    static func makeTravel(for events: [Event], now: Date) -> [TravelFixture] {
        var result: [TravelFixture] = []
        // 7. A 22-minute band on the lecture.
        if let lecture = events.first(where: { $0.externalID == "dm-lecture-01" }) {
            result.append(TravelFixture(
                eventID: lecture.id,
                departAt: lecture.start.addingTimeInterval(-22 * 60),
                duration: 22 * 60,
                mode: .walking))
        }
        // 8. A band whose true height is under the floor, so it grows upward.
        if let coffee = events.first(where: { $0.title == "Coffee with Nora" }) {
            result.append(TravelFixture(
                eventID: coffee.id,
                departAt: coffee.start.addingTimeInterval(-6 * 60),
                duration: 6 * 60,
                mode: .walking))
        }
        return result
    }

    // MARK: Routine templates (task P2-T10 — Routines window seed data)

    /// Inserts one demo `RoutineTemplate` if the store has none yet.
    /// Independent of `seedIfNeeded` above (`Event`/`Place` seeding): the
    /// Routines window can be the first window a session opens, via ⌘⌥R,
    /// before `MainWindow` has ever run its own `.task`, so this has to be
    /// callable — and idempotent — on its own. `RoutinesWindow` calls it from
    /// its own `.task`.
    @MainActor
    static func seedRoutineTemplatesIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<RoutineTemplate>())) ?? []
        guard existing.isEmpty else { return }
        for template in makeRoutineTemplates() {
            context.insert(template)
        }
        try? context.save()
    }

    /// One template, a few blocks, spanning more than one weekday — enough
    /// for the Routines window (layouts.md §8) to have something to render.
    /// Not part of components.md §12's block-variant sheet (that sheet is
    /// Phase 1's `Event` fixtures); this is Phase 2 data, seeded the same
    /// idempotent way.
    @MainActor
    static func makeRoutineTemplates() -> [RoutineTemplate] {
        let gym = RoutineBlock(
            title: "Gym", startMinutes: 7 * 60, duration: 60 * 60,
            flexibility: .shiftable, shiftableMinutes: 30)
        let review = RoutineBlock(
            title: "Morning review", startMinutes: 8 * 60 + 15, duration: 30 * 60,
            flexibility: .fixed)
        let reading = RoutineBlock(
            title: "Reading", startMinutes: 21 * 60, duration: 30 * 60,
            flexibility: .droppable)

        // Calendar's weekday convention (1 = Sunday ... 7 = Saturday, per
        // `RoutineTemplate.activeWeekdays`'s own doc comment): 2/4/6 = Mon/Wed/Fri.
        let template = RoutineTemplate(
            name: "Daily routine",
            activeWeekdays: [2, 4, 6],
            blocks: [gym, review, reading],
            sourceKey: .green)
        return [template]
    }

    // MARK: Time windows (task P2-T18 — persisted TimeWindow seed data)

    /// Inserts the demo `TimeWindow`s if the store has none yet. Mirrors
    /// `seedRoutineTemplatesIfNeeded` exactly: idempotent, called from
    /// wherever that one is called, independent of `seedIfNeeded`'s own
    /// `Event`/`Place` seeding.
    @MainActor
    static func seedTimeWindowsIfNeeded(_ context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<TimeWindow>())) ?? []
        guard existing.isEmpty else { return }
        for window in makeTimeWindows() {
            context.insert(window)
        }
        try? context.save()
    }

    /// The persisted counterpart of `timeWindows` above (`TimeWindowFixture`,
    /// display-only): the same Sleep/Low-energy pair, described as a real
    /// `TimeWindow` model, so both representations agree on the data even
    /// though `GridLayers.swift`'s main-grid call sites still read only the
    /// display-only fixture list.
    ///
    /// A third entry — a weekday-afternoon peak-focus window, "Deep work" —
    /// was added by task P2-T20. `TimeWindowFixture`'s own `timeWindows`
    /// array above deliberately stays a two-window Sleep/Low-energy pair:
    /// peak-focus never renders on the main grid (components.md §7 — "Peak-
    /// focus windows get no treatment on the calendar canvas, in any
    /// phase"), so adding it there would describe a fixture nothing ever
    /// reads. This persisted list is the one the Routines window's windows
    /// mode (task P2-T20) actually renders through, and components.md §17
    /// item 2 requires "a protected, a low-energy AND a peak-focus window"
    /// to exist for review — this is what supplies it. Weekday afternoon,
    /// 15:00–17:00 Mon–Fri, chosen to sit clear of the 13:00–14:30
    /// low-energy window rather than overlap it, so both are legible
    /// side by side in a windows-mode screenshot.
    @MainActor
    static func makeTimeWindows() -> [TimeWindow] {
        [
            TimeWindow(
                weekdays: Set(1...7),
                startMinutes: 22 * 60,
                endMinutes: 7 * 60,
                kind: .protected,
                label: "Sleep"),
            TimeWindow(
                weekdays: [2, 3, 4, 5, 6],
                startMinutes: 13 * 60,
                endMinutes: 14 * 60 + 30,
                kind: .lowEnergy,
                label: "Low energy"),
            TimeWindow(
                weekdays: [2, 3, 4, 5, 6],
                startMinutes: 15 * 60,
                endMinutes: 17 * 60,
                kind: .peakFocus,
                label: "Deep work"),
        ]
    }

    // MARK: All-day items — items 9–10

    static func makeAllDay(now: Date) -> [AllDayFixture] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        // components.md §12 asks for the exam pill with `T−6d`, but six days from
        // a Wednesday lands outside the displayed week, so the variant was never
        // reviewable — the 2026-09-09 review logged it missing (D-7). Anchored to
        // the last day of the current week instead, which keeps it on screen at
        // any weekday. See GAPS.md G-010.
        let endOfWeek = calendar.dateInterval(of: .weekOfYear, for: today)
            .map { calendar.date(byAdding: .day, value: -1, to: $0.end) ?? today } ?? today
        let examDay = max(endOfWeek, calendar.date(byAdding: .day, value: 1, to: today) ?? today)

        return [
            // 9. Deadline, orange.
            AllDayFixture(
                title: "Abgabe: ER-Diagramm",
                startDay: today, endDay: today,
                kind: .deadline, source: .orange),
            // 10. Exam with T−6d, teal.
            AllDayFixture(
                title: "Prüfung: Datenmodellierung",
                startDay: examDay, endDay: examDay,
                kind: .exam, source: .teal),
        ]
    }
}

/// The non-persisted half of the fixture set.
struct MockFixtures: Equatable, Sendable {
    var travel: [TravelFixture] = []
    var allDay: [AllDayFixture] = []
    var windows: [TimeWindowFixture] = []

    func travel(forEvent id: UUID) -> TravelFixture? {
        travel.first { $0.eventID == id }
    }

    func allDayItems(on day: Date, calendar: Calendar = .current) -> [AllDayFixture] {
        let target = calendar.startOfDay(for: day)
        return allDay.filter { item in
            let start = calendar.startOfDay(for: item.startDay)
            let end = calendar.startOfDay(for: item.endDay)
            return start <= target && target <= end
        }
    }
}
