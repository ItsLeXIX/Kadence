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
//  The exact wording is this task's own judgement call, not an invented
//  design token: §14.3 gives two worked examples for illustration, not a
//  template with placeholders, and no file under `design/` specifies a
//  literal format string for either line. What §14.3 *requires*, and what
//  these functions guarantee, is the shape: the title is imperative and
//  names the routine event (plus, for shift/shorten, the minute figure);
//  the disturbance line always makes the ranking legible — the routine
//  event's new time range for shift/shorten, or how many minutes are freed
//  for skip.
//

import Foundation

enum ConflictOptionFormatting {
    /// components.md §14.3, line 1 — "imperative and concrete".
    static func title(for option: ConflictOption, conflict: Conflict) -> String {
        let name = conflict.routineEvent.title
        switch option.kind {
        case .shiftLater:
            return "Shift \(name) \(option.disturbanceMinutes) min later"
        case .shorten:
            return "Shorten \(name) by \(option.disturbanceMinutes) min"
        case .skipToday:
            return "Skip today's \(name)"
        }
    }

    /// components.md §14.3, line 2 — "the ranking made legible", required on
    /// every row.
    static func delta(for option: ConflictOption, conflict: Conflict) -> String {
        let time = BlockFormatters.time
        let name = conflict.routineEvent.title
        switch option.kind {
        case .shiftLater:
            guard let newStart = option.newStart, let newEnd = option.newEnd else { return "" }
            return "\(name) \(time.string(from: newStart))–\(time.string(from: newEnd)) · nothing else moves"
        case .shorten:
            guard let newStart = option.newStart, let newEnd = option.newEnd else { return "" }
            return "\(name) now \(time.string(from: newStart))–\(time.string(from: newEnd))"
        case .skipToday:
            return "Frees \(option.disturbanceMinutes) min · today's occurrence only"
        }
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
