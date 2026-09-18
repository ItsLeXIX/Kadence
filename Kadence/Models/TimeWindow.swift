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
//  data. This file adds no UI, no editor, and does not change how
//  `GridLayers.swift`, `RoutineEngine.swift` or `ConflictEngine.swift` render
//  or reason about windows — that is future work.
//

import Foundation
import SwiftData

/// A persisted time window — "Sleep", "Low energy", etc. — describing a
/// recurring span of the week with a `TimeWindowKind` treatment.
///
/// `TimeWindowFixture.spans(on:)` is deliberately not ported onto this model
/// yet: nothing reads a persisted `TimeWindow` today, so that logic belongs to
/// whichever future task actually renders or schedules against one.
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
}
