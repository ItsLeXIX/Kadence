//
//  MenuBarFormatting.swift
//  Kadence
//
//  String formatting shared by the status item and the popover
//  (components.md §15). Kept as plain functions over `Event`/`Date` so both
//  views compute the exact same strings from the exact same inputs.
//

import Foundation

@MainActor
enum MenuBarFormatting {
    /// `17:30`, reusing `BlockFormatters.time` (`BlockModels.swift`) rather
    /// than a second 24-hour formatter.
    static func time(_ date: Date) -> String {
        BlockFormatters.time.string(from: date)
    }

    /// `17:30 – 18:15`, the popover's own separator (components.md §15.2's
    /// diagram) — wider than `GridBlockModel.timeRange`'s block-canvas
    /// `HH:mm-HH:mm`, which is a different surface with its own spacing rule.
    static func timeRange(_ start: Date, _ end: Date) -> String {
        "\(time(start)) – \(time(end))"
    }

    /// `12m ago` — components.md §15's elapsed phrasing. Never `overdue`,
    /// `late by` or `missed` (DECISIONS.md 2026-09-10).
    static func elapsed(since start: Date, now: Date) -> String {
        let minutes = max(0, Int(now.timeIntervalSince(start) / 60))
        return "\(minutes)m ago"
    }

    /// The NEXT block's meta line (components.md §15.2's diagram row 2):
    /// `17:30 – 18:15 · Gym` normally, `Started 12m ago · Gym` once late.
    /// The trailing qualifier reuses `GridBlockModel.metaLine` (§3.4's own
    /// "Source · Location, or just Source when there is no location" rule)
    /// rather than inventing a second composition rule for the same two
    /// fields — `design/` does not write out a popover-specific version of
    /// that rule, so this is a documented reuse, not an invented one (see
    /// STATUS.md).
    static func nextMeta(for event: Event, now: Date, isLate: Bool) -> String {
        let qualifier = GridBlockModel(event: event, now: now).metaLine
        let lead = isLate ? "Started \(elapsed(since: event.start, now: now))" : timeRange(event.start, event.end)
        return "\(lead) · \(qualifier)"
    }

    /// components.md §16 — the snooze confirmation's result row: `Moved to
    /// 19:15` normally, or `Moved to tomorrow 09:00` once the new start lands
    /// on a different calendar day than the original ("Across a day boundary
    /// it names the day").
    static func snoozeResult(oldStart: Date, newStart: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(newStart, inSameDayAs: oldStart) {
            return "Moved to \(time(newStart))"
        }
        return "Moved to tomorrow \(time(newStart))"
    }

    /// components.md §16 (amended 2026-10-06, G-046) — the refused row as
    /// one sentence: `Not moved — 00:05 is inside Sleep (protected)`; an
    /// unlabelled window reads `inside a protected window`. `start` is the
    /// destination that was refused, in the same `HH:mm` form as the moved
    /// row. Since 2026-10-07 (G-051) this is the row's accessibility label;
    /// the row itself draws `snoozeRefusedLines`.
    static func snoozeRefused(start: Date, windowLabel: String) -> String {
        let lines = snoozeRefusedLines(start: start, windowLabel: windowLabel)
        // "line break replaced by a space" (§16, 2026-10-07). The no-break
        // space is a layout instruction, not part of the spoken sentence.
        return lines.first + " " + lines.second.replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    /// The refused row's two drawn lines (components.md §16, amended
    /// 2026-10-07, G-051). Line 1 is fixed and always fits; line 2 is the
    /// window. The label is drawn verbatim; an empty or whitespace-only label
    /// is "unlabelled". The space before `(protected)` is U+00A0 (no-break
    /// space), so when a long label wraps, the qualifier always stays on the
    /// same line as the label's last word and never sits alone.
    static func snoozeRefusedLines(start: Date, windowLabel: String) -> RefusalLines {
        let unlabelled = windowLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return RefusalLines(
            first: "Not moved — \(time(start)) is inside",
            second: unlabelled ? "a protected window" : "\(windowLabel)\u{00A0}(protected)")
    }

    /// Two strings rather than one with a `\n` in it, so the fixed break is
    /// a fact of the data the tests can check, not of string parsing.
    struct RefusalLines: Equatable, Sendable {
        let first: String
        let second: String
    }
}
