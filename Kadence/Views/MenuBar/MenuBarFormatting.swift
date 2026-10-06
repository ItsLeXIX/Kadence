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

    /// components.md §16 (amended 2026-10-06, G-046) — the refused row:
    /// `Not moved — 00:05 is inside Sleep (protected)`; an empty label reads
    /// `inside a protected window`. `start` is the destination that was
    /// refused, in the same `HH:mm` form as the moved row.
    static func snoozeRefused(start: Date, windowLabel: String) -> String {
        let place = windowLabel.isEmpty ? "a protected window" : "\(windowLabel) (protected)"
        return "Not moved — \(time(start)) is inside \(place)"
    }
}
