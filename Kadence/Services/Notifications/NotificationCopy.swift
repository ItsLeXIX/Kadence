//
//  NotificationCopy.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 8) — components.md §27.4
//  "Copy — exact, tested" (N1–N8, N1e) and §24.10's short reasons, which the
//  band's hover help, the popover and the notifications share.
//
//  Absolute times only (§27.3): a notification outlives its moment, and
//  `08:15` stays true. Never `late`, `missed`, `overdue`, a count or an
//  exclamation mark.
//

import Foundation

nonisolated enum TravelCopy {
    /// `HH:mm`, 24-hour, in `calendar`'s zone.
    static func time(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// Whole minutes of a travel time (legs carry whole minutes, B48).
    static func minutes(_ seconds: TimeInterval) -> Int { Int((seconds / 60).rounded(.up)) }

    /// §24.10's short form: the band's hover help, the popover, N1e and N7.
    /// `place`: the name of the place a `needsAddress` names.
    ///
    /// §24.10 "No invented fact in the copy either": nothing is filled in.
    /// A `needsAddress` without a place it can name has no short form (nil:
    /// the clause is omitted); a `paused` without its retry time says only
    /// that it is paused.
    static func shortReason(_ reason: TravelReason, place: String?, mode: TravelMode, retryAt: Date?,
                            calendar: Calendar) -> String? {
        switch reason {
        case .needsAddress: place.map { "\($0) has no address" }
        case .offline: "offline"
        case .noRoute: "no route \(mode.copyPhrase)"
        case .paused: "Apple Maps paused" + (retryAt.map { " until \(time($0, calendar: calendar))" } ?? "")
        case .failed: "Apple Maps didn't answer"
        case .pending: "not worked out yet"
        }
    }

    /// The trip clause, with only what the leg says: `35 min from Home`,
    /// `35 min` (no origin), `from Home` (no time), nil (neither). `about`
    /// goes before the minutes of an estimate.
    static func trip(minutes: Int?, origin: String?, about: Bool = false) -> String? {
        let parts = [minutes.map { "\(about ? "about " : "")\($0) min" }, origin.map { "from \($0)" }].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    /// `{origin}`: the origin place's name, or `where you are` (§24.2.1).
    static let whereYouAre = "where you are"
}

/// The identifier prefixes Kadence owns (§27.6). Anything else in the
/// centre is never touched.
nonisolated enum NotificationKindPrefix: String, Sendable, CaseIterable {
    /// `due.` — the deadline reminders (components.md §40.6, slice 3).
    case leave, start, result, sync, due

    static func of(_ identifier: String) -> NotificationKindPrefix? {
        allCases.first { identifier.hasPrefix($0.rawValue + ".") }
    }
}

/// §27.7's categories.
nonisolated enum NotificationCategory: String, Sendable, CaseIterable {
    case event = "kadence.event"
    case readOnly = "kadence.readOnly"
    case result = "kadence.result"
    case source = "kadence.source"
    /// components.md §40.5 (slice 3): N9, one deadline — `Done` · `Open`.
    case deadline = "kadence.deadline"
    /// N10, a group — `Open` only.
    case deadlines = "kadence.deadlines"
}

/// §27.4's levels. The recording centre records the level asked for.
nonisolated enum InterruptionLevel: String, Sendable {
    case active
    case timeSensitive
}

/// One title and body, exact.
nonisolated struct NotificationText: Sendable, Equatable {
    var title: String
    var body: String
}

nonisolated enum NotificationCopy {
    /// `{where}`, with its leading separator handled by the caller: the
    /// location text (`Online` for an online event), else the place's name,
    /// else nil.
    static func whereText(locationText: String?, isOnline: Bool, placeName: String?) -> String? {
        let text = (locationText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !text.isEmpty { return isOnline ? "Online" : text }
        if let placeName, !placeName.isEmpty { return placeName }
        return nil
    }

    static func joined(_ parts: [String?]) -> String { parts.compactMap { $0 }.joined(separator: " · ") }

    /// N1 — `Leave by {depart} for {title}` / `Starts {start} · {where} ·
    /// {min} min from {origin}`. A missing minutes or origin is left out
    /// (§24.10): `Starts 09:00 · HS_A3.15 · 35 min`.
    static func n1(title: String, depart: String, start: String, where place: String?, minutes: Int?,
                   origin: String?) -> NotificationText {
        NotificationText(title: "Leave by \(depart) for \(title)",
                         body: joined(["Starts \(start)", place, TravelCopy.trip(minutes: minutes, origin: origin)]))
    }

    /// N1e — the same from an estimate. No reason: `estimate` alone.
    static func n1e(title: String, depart: String, start: String, where place: String?, minutes: Int?,
                    origin: String?, reason: String?) -> NotificationText {
        NotificationText(title: "Leave by about \(depart) for \(title)",
                         body: joined(["Starts \(start)", place,
                                       TravelCopy.trip(minutes: minutes, origin: origin, about: true),
                                       "estimate" + (reason.map { ", \($0)" } ?? "")]))
    }

    /// N2 — a leave-by held past `departAt` by a protected window.
    static func n2(title: String, depart: String, start: String, where place: String?, window: String,
                   isEstimate: Bool) -> NotificationText {
        let inside = window.isEmpty ? "inside a protected window" : "inside \(window) (protected)"
        return NotificationText(title: "Leave now for \(title)",
                                body: joined(["Starts \(start)", place,
                                              "Leave-by was \(isEstimate ? "about " : "")\(depart), \(inside)"]))
    }

    /// N3 — a catch-up after `departAt`.
    static func n3(title: String, depart: String, start: String, where place: String?,
                   isEstimate: Bool) -> NotificationText {
        NotificationText(title: "Leave now for \(title)",
                         body: joined(["Starts \(start)", place, "Leave-by was \(isEstimate ? "about " : "")\(depart)"]))
    }

    /// N4 — `{title} starts at {start}` / `{where} · {source}`.
    static func n4(title: String, start: String, where place: String?, source: String?) -> NotificationText {
        NotificationText(title: "\(title) starts at \(start)", body: joined([place, source]))
    }

    /// N7 — travel unavailable, or (`isPending`) not worked out yet. A
    /// missing origin or reason is left out with its separator (§24.10):
    /// `Travel time from Home unavailable. Check your route before you leave.`
    static func n7(title: String, start: String, where place: String?, origin: String?,
                   reason: String?, isPending: Bool = false) -> NotificationText {
        let travel = "Travel time" + (origin.map { " from \($0)" } ?? "")
        let sentence = isPending
            ? "\(travel) isn't worked out yet. Check your route before you leave."
            : "\(travel) unavailable\(reason.map { ": \($0)" } ?? ""). Check your route before you leave."
        return NotificationText(title: "\(title) starts at \(start)", body: joined([place, sentence]))
    }

    /// N5 — `{title} moved to {new}` (`moved to tomorrow {new}` across a
    /// day, §16) / `Snoozed from {old} · ⌘Z in Kadence undoes it`.
    static func n5(title: String, oldStart: Date, newStart: Date, calendar: Calendar) -> NotificationText {
        let new = TravelCopy.time(newStart, calendar: calendar)
        let moved = calendar.isDate(newStart, inSameDayAs: oldStart) ? new : "tomorrow \(new)"
        return NotificationText(title: "\(title) moved to \(moved)",
                                body: "Snoozed from \(TravelCopy.time(oldStart, calendar: calendar)) · ⌘Z in Kadence undoes it")
    }

    /// N6 — `{title} not moved` / `{new} is inside {window} (protected)`.
    static func n6(title: String, newStart: Date, window: String, calendar: Calendar) -> NotificationText {
        let new = TravelCopy.time(newStart, calendar: calendar)
        let inside = window.isEmpty ? "a protected window" : "\(window) (protected)"
        return NotificationText(title: "\(title) not moved", body: "\(new) is inside \(inside)")
    }

    /// N8 — a source's background sync paused after a 401 or 403 (§27.4).
    static func n8(name: String, host: String, user: String, forbidden: Bool) -> NotificationText {
        NotificationText(
            title: "\(name) isn't syncing",
            body: forbidden
                ? "\(host) refused access for \(user). Sync is paused until you check the account in Kadence."
                : "\(host) didn't accept the password for \(user). Sync is paused until you update it in Kadence.")
    }

    /// N8 for a Moodle source (components.md §40.7): the four states that
    /// mean "the URL stopped working". Never the URL, its path or token.
    static func n8Feed(name: String, host: String, state: SourceState) -> NotificationText? {
        let body: String
        switch state {
        case .unauthorized:
            body = "\(host) didn't accept the calendar URL. Sync is paused until you paste a new one in Kadence."
        case .forbidden:
            body = "\(host) refused access to the calendar. Sync is paused until you paste a new URL in Kadence."
        case .feedNotFound:
            body = "\(host) has no calendar at the saved URL. Paste a new one in Kadence."
        case .notACalendar:
            body = "\(host) sent a web page instead of the calendar. If you changed your FH password, Moodle made a new calendar URL."
        default:
            return nil
        }
        return NotificationText(title: "\(name) isn't syncing", body: body)
    }

    /// §27.6: `userInfo["hash"]`, SHA-256 of title, body and category.
    static func contentHash(_ text: NotificationText, category: NotificationCategory) -> String {
        ICSFormat.sha256Hex([text.title, text.body, category.rawValue].joined(separator: "\u{1F}"))
    }
}
