//
//  DisplayFixtures.swift
//  Kadence
//
//  Phase 1 has no TravelLeg service, no routine engine and no work items
//  (DECISIONS.md 2026-09-09), but components.md §12 requires every block
//  variant and every background window to be renderable for review. These are
//  display-only value types that stand in for those models. They are NOT
//  persisted and NOT written to by the UI.
//

import Foundation

/// Stands in for `TravelLeg` (Phase 3).
struct TravelFixture: Identifiable, Equatable, Sendable {
    var id = UUID()
    var eventID: UUID
    var departAt: Date
    var duration: TimeInterval
    var mode: TravelMode
}

enum AllDayKind: Sendable, Equatable {
    /// `WorkItem.kind == .assignment / .project` — a date whose work is movable.
    case deadline
    /// `WorkItem.kind == .exam` — a fixed date you ramp toward.
    case exam
}

/// Stands in for the all-day projection of `WorkItem` (Phase 3).
struct AllDayFixture: Identifiable, Equatable, Sendable {
    var id = UUID()
    var title: String
    /// Inclusive first day.
    var startDay: Date
    /// Inclusive last day. Equal to `startDay` for a single-day item.
    var endDay: Date
    var kind: AllDayKind
    var source: SourceKey
    var status: BlockStatus = .scheduled

    var blockKind: BlockKind {
        switch kind {
        case .deadline: .deadlineAllDay
        case .exam: .examAllDay
        }
    }

    /// components.md §5 — `T−6d` / `T−1d` / `today`. Never negative, never red.
    /// An exam that has passed shows no chip at all and takes `.past`.
    func countdownLabel(now: Date, calendar: Calendar = .current) -> String? {
        guard kind == .exam else { return nil }
        let today = calendar.startOfDay(for: now)
        let target = calendar.startOfDay(for: startDay)
        guard let days = calendar.dateComponents([.day], from: today, to: target).day else { return nil }
        if days < 0 { return nil }
        return days == 0 ? "today" : "T−\(days)d"
    }

    func isPast(now: Date, calendar: Calendar = .current) -> Bool {
        calendar.startOfDay(for: endDay) < calendar.startOfDay(for: now)
    }
}

/// Stands in for `TimeWindow` (Phase 2). Weekday numbers follow
/// `Calendar.component(.weekday:)`, i.e. 1 = Sunday.
struct TimeWindowFixture: Identifiable, Equatable, Sendable {
    var id = UUID()
    var weekdays: Set<Int>
    /// Minutes from midnight.
    var startMinutes: Int
    var endMinutes: Int
    var kind: TimeWindowKind
    var label: String

    /// Returns the window's span on a given day, split if it wraps midnight.
    /// A 22:00–07:00 protected window is two spans on consecutive days.
    func spans(on day: Date, calendar: Calendar = .current) -> [(start: Date, end: Date)] {
        let startOfDay = calendar.startOfDay(for: day)
        let weekday = calendar.component(.weekday, from: startOfDay)
        var result: [(Date, Date)] = []

        func add(_ fromMinutes: Int, _ toMinutes: Int) {
            guard toMinutes > fromMinutes else { return }
            result.append((
                startOfDay.addingTimeInterval(TimeInterval(fromMinutes * 60)),
                startOfDay.addingTimeInterval(TimeInterval(toMinutes * 60))
            ))
        }

        if endMinutes > startMinutes {
            if weekdays.contains(weekday) { add(startMinutes, endMinutes) }
        } else {
            // Wraps midnight: the evening part belongs to today's weekday, the
            // morning part to yesterday's.
            if weekdays.contains(weekday) { add(startMinutes, 24 * 60) }
            let previous = (weekday - 2 + 7) % 7 + 1
            if weekdays.contains(previous) { add(0, endMinutes) }
        }
        return result
    }
}

/// What kind of thing a source is. Drives the swatch symbol by the normative
/// table in components.md §10.1.
///
/// This vocabulary is deliberately disjoint from `BlockKind`: a kind glyph
/// depicts the *activity*, a source symbol depicts the *origin* — the container,
/// feed or party the data arrived from. The two appear together in the inspector
/// title row (layouts.md §6), so no symbol may appear in both tables. Check
/// components.md §2.1, §3.2 and §5 before adding a case here.
enum CalendarSourceKind: String, CaseIterable, Codable, Sendable {
    case universityTimetable
    case coursework
    case exams
    case mail
    case routine
    case manual
    case plannedStudy
    case travel
    case other
    /// Not classified. A plain disc: "a source, unlabelled" — deliberately not a
    /// `questionmark`, which would read as an error state for something that is
    /// merely unlabelled.
    case unknown

    /// components.md §10.1, normative symbol table.
    var symbol: String {
        switch self {
        case .universityTimetable: "tablecells.fill"
        case .coursework: "tray.2.fill"
        case .exams: "seal.fill"
        case .mail: "envelope.fill"
        case .routine: "rectangle.stack.fill"
        case .manual: "person.fill"
        case .plannedStudy: "sparkles"
        case .travel: "map.fill"
        case .other: "tag.fill"
        case .unknown: "circle.fill"
        }
    }
}

/// A source as the sidebar sees it. Phase 1 has no connectors, so this is a
/// static list; Phase 3 replaces it with real source records.
///
/// The palette slot (`key`) and the symbol are independent: slots are assigned in
/// order as sources are added, so a symbol keyed to the hue would be meaningless.
/// Two sources may share a symbol; they will never share a hue.
struct CalendarSource: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var key: SourceKey
    var kind: CalendarSourceKind
    /// Defaults from `kind`; user-overridable from Settings in a later phase.
    var symbolOverride: String?

    var symbol: String { symbolOverride ?? kind.symbol }
}
