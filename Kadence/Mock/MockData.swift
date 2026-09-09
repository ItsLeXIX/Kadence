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
        CalendarSource(id: "timetable", name: "University timetable", key: .blue),
        CalendarSource(id: "exams", name: "Exams", key: .teal),
        CalendarSource(id: "routine", name: "Daily routine", key: .green),
        CalendarSource(id: "mail", name: "Mail appointments", key: .amber),
        CalendarSource(id: "deadlines", name: "Coursework", key: .orange),
        CalendarSource(id: "social", name: "Social", key: .pink),
        CalendarSource(id: "study", name: "Planned study", key: .purple),
        CalendarSource(id: "personal", name: "Personal", key: .graphite),
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
        events.append(Event(
            title: "Morning review",
            start: at(8), end: at(9),
            origin: .routine, flexibility: .fixed, sourceKey: .green))
        events.append(Event(
            title: "Training",
            start: at(17), end: at(17, 45),
            origin: .routine, flexibility: .shiftable, sourceKey: .green))
        events.append(Event(
            title: "Reading",
            start: at(21), end: at(21, 30),
            origin: .routine, flexibility: .droppable, sourceKey: .green))

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
        events.append(Event(
            title: "Gym",                    // skipped, re-offered
            start: at(16, 15), end: at(17),
            origin: .routine, status: .skipped, flexibility: .shiftable, sourceKey: .green))

        // 16. A day with nothing on it at all — two days out is deliberately empty.

        return events
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

    // MARK: All-day items — items 9–10

    static func makeAllDay(now: Date) -> [AllDayFixture] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let inSixDays = calendar.date(byAdding: .day, value: 6, to: today) ?? today

        return [
            // 9. Deadline, orange.
            AllDayFixture(
                title: "Abgabe: ER-Diagramm",
                startDay: today, endDay: today,
                kind: .deadline, source: .orange),
            // 10. Exam with T−6d, teal.
            AllDayFixture(
                title: "Prüfung: Datenmodellierung",
                startDay: inSixDays, endDay: inSixDays,
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
