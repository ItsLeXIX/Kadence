//
//  ConflictOptionFormatting.swift
//  Kadence
//
//  components.md §14.3's option-row prose ("Shift Training 90 min later",
//  "Training 17:00 → 18:30 · nothing else moves") is explicitly left to a
//  later UI task by `ConflictEngine.swift`'s own header comment: that engine
//  hands back structured `ConflictOption` values and does not build prose.
//  This file is that later task's formatting layer — kept as plain,
//  testable functions over value types (no SwiftUI, no system clock) rather
//  than inline string-building inside `ConflictPanelView`, the same shape as
//  `ConflictOrdering`.
//
//  Task P2-T45: the copy is now components.md §14.3.4's exact tables.
//  Every minute figure goes through `minutes(_:)`. components.md §14.3.4
//  (amended 2026-10-05, closes G-035): conflict copy counts in minutes at
//  every size (`75 min later`, `135 min lost`) — the ranking is read by
//  comparing numbers. The old `N h MM` sentence is struck.
//

import Foundation

enum ConflictOptionFormatting {
    /// The one place a minute figure becomes text: `N min` at every size
    /// (§14.3.4, see the header).
    static func minutes(_ value: Int) -> String { "\(value) min" }

    /// components.md §14.3.4, line 1 — imperative, no trailing period:
    /// `Shift Training 75 min later` / `Shorten Training to 30 min` /
    /// `Skip Training today`.
    static func title(for option: ConflictOption, conflict: Conflict) -> String {
        let name = conflict.routineEvent.title
        switch option.kind {
        case .shiftLater:
            return "Shift \(name) \(minutes(option.disturbanceMinutes)) later"
        case .shorten:
            return "Shorten \(name) to \(minutes(occurrenceMinutes(conflict) - option.disturbanceMinutes))"
        case .skipToday:
            return "Skip \(name) today"
        }
    }

    /// components.md §14.3.4, line 2 — the ranking's number and what it
    /// costs: `17:00 → 18:15 · all 90 min kept` /
    /// `90 min → 30 min · 60 min lost` /
    /// `Does not run today · 90 min lost · re-offered`.
    static func delta(for option: ConflictOption, conflict: Conflict) -> String {
        let time = BlockFormatters.time
        let total = occurrenceMinutes(conflict)
        switch option.kind {
        case .shiftLater:
            guard let newStart = option.newStart else { return "" }
            return "\(time.string(from: conflict.routineEvent.start)) → \(time.string(from: newStart))"
                + " · all \(minutes(total)) kept"
        case .shorten:
            return "\(minutes(total)) → \(minutes(total - option.disturbanceMinutes))"
                + " · \(minutes(option.disturbanceMinutes)) lost"
        case .skipToday:
            return "Does not run today · \(minutes(option.disturbanceMinutes)) lost · re-offered"
        }
    }

    /// The occurrence's own duration in whole minutes.
    private static func occurrenceMinutes(_ conflict: Conflict) -> Int {
        Int((conflict.routineEvent.duration / 60).rounded())
    }

    /// One row's worth of already-formatted content, in the same order
    /// `conflict.options` already carries (least disturbance first, per
    /// `ConflictEngine.finalize`) — `ConflictPanelView` renders this array
    /// directly with no further filtering or re-sorting, which is what makes
    /// this function the correct seam for testing "the panel renders the
    /// right number of rows, with the recommended one marked" without
    /// hosting a SwiftUI view (see AccessibilityTests.swift's header comment
    /// on why that path is unreliable on this platform).
    static func rows(for conflict: Conflict) -> [ConflictOptionRowContent] {
        conflict.options.map { option in
            ConflictOptionRowContent(
                id: option.id,
                title: title(for: option, conflict: conflict),
                delta: delta(for: option, conflict: conflict),
                isRecommended: option.isRecommended)
        }
    }
}

/// One option row's rendered content — title, disturbance line, and whether
/// it carries the `Recommended` chip (components.md §14.3).
struct ConflictOptionRowContent: Identifiable, Equatable {
    let id: UUID
    let title: String
    let delta: String
    let isRecommended: Bool
}
