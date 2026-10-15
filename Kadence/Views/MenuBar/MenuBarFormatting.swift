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
    /// The trailing qualifier is `Source · Location`, or just the source
    /// when there is no location — §3.4's rule as it stood when this was
    /// built. §3.4's 2026-10-10 amendment turned the block's line round
    /// (`Location · Source`) and says "The menu bar popover's meta line
    /// (§15) is not changed", so the popover keeps its own
    /// `GridBlockModel.popoverQualifier`.
    ///
    /// **Slice 2 (components.md §26.2, 2026-10-14): from now on the order is
    /// §3.4's** — time, then location, then source: `09:00 – 10:30 · HS_A3.15
    /// · University timetable`; `14:00 – 15:30 · Online · University
    /// timetable`; `17:30 – 18:15 · Daily routine` with no location. With
    /// the leave line above it, a truncated room would hide the one fact the
    /// leave line points at. REST OF TODAY rows keep their own form.
    static func nextMeta(for event: Event, now: Date, isLate: Bool) -> String {
        let line = GridBlockModel(event: event, now: now).metaLine
        let lead = isLate ? "Started \(elapsed(since: event.start, now: now))" : timeRange(event.start, event.end)
        return "\(lead) · \(line)"
    }

    // MARK: Leave-by (components.md §26)

    /// The status item's unit in Leave: `Leave 08:15`, `Leave ≈08:15`.
    static func leaveUnit(departAt: Date, isEstimate: Bool) -> String {
        "Leave \(isEstimate ? "≈" : "")\(time(departAt))"
    }

    /// §26.2's leave line: its text and how it is drawn.
    struct LeaveLine: Equatable {
        enum Tone: Equatable { case primary, now, secondary }
        var text: String
        var tone: Tone

        /// What the popover draws (§26.2, amended 2026-10-15): the same text,
        /// with `Leave by 08:15` / `Leave now` held together by no-break
        /// spaces, so wrapping at `lineLimit` 2 never splits them from the
        /// time and the time is never the part truncated.
        var display: String {
            guard text.hasPrefix("Leave") else { return text }
            let lead = text.components(separatedBy: " · ").first ?? text
            return lead.replacingOccurrences(of: " ", with: "\u{00A0}") + text.dropFirst(lead.count)
        }
    }

    /// The popover's leave line for NEXT, in its seven forms (nil: omitted —
    /// no leg, or late).
    static func leaveLine(_ result: NextUpProvider.Result, now: Date, placeNames: [String: String],
                          calendar: Calendar = .current) -> LeaveLine? {
        guard result.next != nil, let leg = result.leg else { return nil }
        let origin = TravelPresentation.originName(leg, placeNames: placeNames)
        switch result.state(now: now) {
        case .leave(let departAt, let isEstimate):
            // §24.10: a missing reason, minutes or origin is left out.
            if isEstimate {
                let reason = TravelPresentation.shortReason(leg, placeNames: placeNames, calendar: calendar)
                return LeaveLine(text: "Leave by ≈\(time(departAt)) · estimate" + (reason.map { ", \($0)" } ?? ""),
                                 tone: .primary)
            }
            let trip = TravelCopy.trip(minutes: leg.duration.map(TravelCopy.minutes), origin: origin)
            return LeaveLine(text: "Leave by \(time(departAt))" + (trip.map { " · \($0)" } ?? ""), tone: .primary)
        case .leaveNow(let departAt, let isEstimate):
            return LeaveLine(text: "Leave now · leave-by was \(isEstimate ? "≈" : "")\(time(departAt))", tone: .now)
        case .late, .empty:
            return nil
        case .normal:
            if leg.status == .pending || leg.reason == .pending {
                return LeaveLine(text: "\(TravelPresentation.travelTime(from: origin)) not worked out yet", tone: .secondary)
            }
            let reason = TravelPresentation.shortReason(leg, placeNames: placeNames, calendar: calendar)
            return LeaveLine(text: "Travel time unavailable" + (reason.map { " · \($0)" } ?? ""), tone: .secondary)
        }
    }

    /// §29: the status item's label.
    static func statusAccessibilityLabel(_ result: NextUpProvider.Result, now: Date) -> String? {
        guard let next = result.next else { return nil }
        switch result.state(now: now) {
        case .leave(let departAt, let isEstimate):
            return isEstimate ? "Leave by about \(time(departAt)) for \(next.title), estimate"
                : "Leave by \(time(departAt)) for \(next.title)"
        case .leaveNow(let departAt, let isEstimate):
            return "Leave now for \(next.title), leave-by was \(isEstimate ? "about " : "")\(time(departAt))"
        default:
            return nil
        }
    }

    /// §29: the popover NEXT element's value — the leave line spoken, then
    /// the meta line spoken.
    static func nextAccessibilityValue(_ result: NextUpProvider.Result, now: Date, placeNames: [String: String]) -> String? {
        guard let next = result.next else { return nil }
        let model = GridBlockModel(event: next, now: now)
        let range = result.isLate ? "Started \(elapsed(since: next.start, now: now))"
            : "\(time(next.start)) to \(time(next.end))"
        let meta = ([range] + [model.metaLead, model.sourceName].compactMap { $0 }).joined(separator: ", ")
        var leave: String?
        if let leg = result.leg {
            switch result.state(now: now) {
            case .leave(let departAt, let isEstimate):
                let origin = TravelPresentation.originName(leg, placeNames: placeNames)
                let about = isEstimate ? "about " : ""
                let trip = [leg.duration.map { "\(about)\(TravelCopy.minutes($0)) minutes" }, origin.map { "from \($0)" }]
                    .compactMap { $0 }.joined(separator: " ")
                leave = "Leave by \(about)\(time(departAt))" + (trip.isEmpty ? "" : ", \(trip)")
            case .leaveNow(let departAt, let isEstimate):
                leave = "Leave now, leave-by was \(isEstimate ? "about " : "")\(time(departAt))"
            default:
                leave = leaveLine(result, now: now, placeNames: placeNames)?.text
            }
        }
        return [leave, meta].compactMap { $0 }.joined(separator: ". ")
    }

    /// §26.3: the notifications line, after any stale lines. Only with at
    /// least one rule on.
    static func notificationsLine(_ permission: NotificationPermission, anyRuleOn: Bool) -> String? {
        guard anyRuleOn else { return nil }
        switch permission {
        case .off: return "Notifications are off, so Kadence can't tell you when to leave."
        case .notAllowedYet: return "Notifications aren't allowed yet. Settings ▸ Notifications"
        case .allowed, .notAsked: return nil
        }
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
