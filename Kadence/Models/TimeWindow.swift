//
//  TimeWindow.swift
//  Kadence
//
//  The Phase 2 persisted time-window data model that layouts.md §8.1 and
//  components.md §13.3 both presuppose ("a selected time window: kind
//  (protected / low-energy / peak-focus), weekdays, start, end, label"). Until
//  now the only thing describing a window was `TimeWindowFixture`
//  (`DisplayFixtures.swift`), whose own doc comment says it is display-only —
//  not persisted, not written to by the UI. This is the data-layer-only model
//  that fixture stands in for; `RoutineEngine` and `ConflictEngine` both
//  record in their headers that they defer protected-window logic pending this
//  model existing.
//
//  Follows RoutineTemplate.swift's conventions (itself P2-T08's precedent for
//  this same kind of task): a stable `id: UUID`, enums stored as a raw
//  `String` with a computed accessor, a memberwise `init`. Field shapes match
//  `TimeWindowFixture` exactly, so both representations describe the same
//  data. This file adds no UI, no editor. As of task P2-T19,
//  `ConflictEngine.swift` does reason about `.protected`-kind windows via
//  `spans(on:calendar:)` below; `GridLayers.swift`/`RoutineEngine.swift`
//  still do not — that remains future work.
//

import Foundation
import SwiftData

/// A persisted time window — "Sleep", "Low energy", etc. — describing a
/// recurring span of the week with a `TimeWindowKind` treatment.
///
/// `TimeWindowFixture.spans(on:)` is ported onto this model as `spans(on:calendar:)`
/// below (task P2-T19) — the future task this file's own original comment
/// deferred to: `ConflictEngine` now schedules against protected windows using it.
@Model
final class TimeWindow {
    /// Stable local identity.
    var id: UUID = UUID()

    /// `Calendar`'s own `weekday` component convention: 1 = Sunday ...
    /// 7 = Saturday, matching `RoutineTemplate.activeWeekdays` and
    /// `TimeWindowFixture.weekdays`.
    var weekdays: Set<Int> = []

    /// Minutes from midnight. `endMinutes` may be less than `startMinutes`,
    /// meaning the window wraps past midnight — exactly as
    /// `TimeWindowFixture`'s fields already mean, and exactly as
    /// `TimeWindowFixture.spans(on:)` already handles for the display-only
    /// stand-in.
    var startMinutes: Int = 0
    var endMinutes: Int = 0

    private var kindRaw: String = TimeWindowKind.protected.rawValue
    var kind: TimeWindowKind {
        get { TimeWindowKind(rawValue: kindRaw) ?? .protected }
        set { kindRaw = newValue.rawValue }
    }

    var label: String = ""

    init(
        weekdays: Set<Int> = [],
        startMinutes: Int = 0,
        endMinutes: Int = 0,
        kind: TimeWindowKind = .protected,
        label: String = ""
    ) {
        self.id = UUID()
        self.weekdays = weekdays
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.kindRaw = kind.rawValue
        self.label = label
    }

    /// Returns the window's span on a given day, split if it wraps midnight.
    /// A 22:00–07:00 protected window is two spans on consecutive days.
    ///
    /// Mirrors `TimeWindowFixture.spans(on:)` (`DisplayFixtures.swift`
    /// ~line 78) exactly — same weekday/wrap semantics — now that a real
    /// `TimeWindow` has a consumer (`ConflictEngine`, task P2-T19) instead of
    /// only the display-only fixture. Kept as a plain method here rather than
    /// factored into shared code, matching this codebase's existing tolerance
    /// for the persisted model and its display-only fixture duplicating small
    /// pure functions (see this file's own header comment on the two types
    /// describing the same data).
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
