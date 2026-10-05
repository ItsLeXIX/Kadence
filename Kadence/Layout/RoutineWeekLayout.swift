//
//  RoutineWeekLayout.swift
//  Kadence
//
//  layouts.md §8 / components.md §13.1 — the Routines window reuses the main
//  grid's own layout engine (`DayLayoutEngine`) unchanged; what it needs of
//  its own is only the glue between a `RoutineTemplate`'s weekly shape (a set
//  of active weekdays, applied uniformly to every block — see
//  `RoutineEngine.materialize`'s own "(active weekday × block)" pairing) and
//  the `LayoutItem`s that engine consumes.
//
//  Pure functions over value types, free of SwiftUI, SwiftData and the system
//  clock (the one place a "now" is needed, `referenceDayStart`, takes it as a
//  parameter rather than reading it), so this is unit-testable the same way
//  `DayLayoutEngine` itself is.
//

import Foundation

/// A plain-value read of the fields `RoutineWeekLayout` and `GridBlockModel`
/// need from a `RoutineBlock`, so neither has to touch the `@Model` class (or
/// a `ModelContext`) directly. Mirrors why `GridBlockModel` exists for `Event`
/// (`BlockModels.swift`'s header).
struct RoutineBlockSnapshot: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var startMinutes: Int
    var duration: TimeInterval
    var flexibility: Flexibility
    /// Task P2-T42: the ± minutes the inspector's stepper shows
    /// (components.md §13.2). Defaulted so existing call sites are unchanged.
    var shiftableMinutes: Int? = nil
}

extension RoutineBlock {
    var snapshot: RoutineBlockSnapshot {
        RoutineBlockSnapshot(
            id: id, title: title, startMinutes: startMinutes,
            duration: duration, flexibility: flexibility,
            shiftableMinutes: shiftableMinutes)
    }
}

enum RoutineWeekLayout {

    /// `Calendar`'s own weekday numbering (1 = Sunday ... 7 = Saturday, the
    /// same convention `RoutineTemplate.activeWeekdays` uses), ordered
    /// starting from `firstWeekday` — layouts.md §8: "ordered from
    /// Calendar.current.firstWeekday."
    static func orderedWeekdays(firstWeekday: Int) -> [Int] {
        (0..<7).map { offset in ((firstWeekday - 1 + offset) % 7) + 1 }
    }

    /// Midnight of *some* date whose weekday component is `weekday`, anchored
    /// near `now`. The Routines window shows no dates at all (`dayHeaderWeekday`
    /// only, per components.md §13.1's table) — only the time-of-day this date
    /// carries once a block's `startMinutes` is added to it is ever read, so
    /// which actual date is picked is arbitrary as long as its weekday matches.
    static func referenceDayStart(weekday: Int, now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let todayWeekday = calendar.component(.weekday, from: today)
        let diff = weekday - todayWeekday
        return calendar.date(byAdding: .day, value: diff, to: today) ?? today
    }

    /// One `LayoutItem` per block in `blocks`, anchored to `referenceDayStart`.
    /// Empty when `weekday` is not one of the template's active weekdays —
    /// every block in a `RoutineTemplate` repeats on every active weekday
    /// uniformly (there is no per-block weekday field; see
    /// `RoutineTemplate.swift`'s own doc comment), exactly the pairing
    /// `RoutineEngine.materialize` iterates.
    static func layoutItems(
        blocks: [RoutineBlockSnapshot],
        activeWeekdays: Set<Int>,
        weekday: Int,
        referenceDayStart: Date
    ) -> [LayoutItem] {
        guard activeWeekdays.contains(weekday) else { return [] }
        return blocks.map { block in
            let start = referenceDayStart.addingTimeInterval(TimeInterval(block.startMinutes * 60))
            return LayoutItem(
                id: block.id, start: start,
                end: start.addingTimeInterval(block.duration),
                title: block.title)
        }
    }
}
