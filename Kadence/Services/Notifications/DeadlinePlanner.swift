//
//  DeadlinePlanner.swift
//  Kadence
//
//  Phase 3 slice 3 (PHASE3-SLICE3-PLAN.md task 8) — components.md §40
//  (deadline notifications, the deadline half of G-088) and §41 (clock
//  changes). Pure: the deadlines, the rule, the protected windows, the
//  records, `now` and whether this is a catch-up pass in; the `due.`
//  requests out. §27's machinery (the 48-hour window and its cap, records,
//  the applier's diff, permission, categories) is the scheduler's.
//
//  Two reminders per deadline: **early** — a wall-clock time on the calendar
//  day `aheadDays` before the due date (`WallClock`, `.day` arithmetic, never
//  86 400 s) — and **final** — `due − lead`, a duration. Protected windows
//  hold them but never past the deadline; a pair closer than 60 min
//  collapses to the final one; reminders with the same fire time for
//  deadlines due on the same date are one notification. Absolute copy only.
//

import Foundation

/// A Moodle deadline as the planner reads it.
nonisolated struct DeadlineSnapshot: Sendable, Equatable {
    var id: UUID
    var title: String
    var wording: MomentWording?
    var kind: ImportKind
    /// The due moment (`start == end` for a moment).
    var due: Date
    var end: Date
    var isAllDay: Bool
    var courseCode: String?
    var courseCategory: String?
    var sourceName: String
    var isDone: Bool

    /// §40.2: a not-done deadline moment. Never an opening, a notice or a span.
    var isEligible: Bool { kind == .deadline && !isAllDay && due == end && !isDone }

    /// `{course}`: the course code, else the category, else nil.
    var course: String? { courseCode ?? courseCategory }

    @MainActor
    init?(_ event: Event, sourceName: String) {
        guard event.origin == .imported, event.importKind.isMoodle else { return nil }
        self.init(id: event.id, title: event.title, wording: event.momentWording, kind: event.importKind,
                  due: event.start, end: event.end, isAllDay: event.isAllDay, courseCode: event.courseCode,
                  courseCategory: event.courseCategory, sourceName: sourceName, isDone: event.status == .done)
    }

    init(id: UUID, title: String, wording: MomentWording?, kind: ImportKind = .deadline, due: Date, end: Date? = nil,
         isAllDay: Bool = false, courseCode: String?, courseCategory: String?, sourceName: String, isDone: Bool = false) {
        self.id = id; self.title = title; self.wording = wording; self.kind = kind; self.due = due
        self.end = end ?? due; self.isAllDay = isAllDay; self.courseCode = courseCode
        self.courseCategory = courseCategory; self.sourceName = sourceName; self.isDone = isDone
    }
}

/// The `deadline` rule's values (§40.1, §42.3).
nonisolated struct DeadlineRule: Sendable, Equatable {
    var isEnabled = true
    /// The early reminder: days before (0 = off) at a minute of day.
    var aheadDays = 1
    var aheadMinuteOfDay = 1080
    /// The final reminder.
    var leadEnabled = true
    var leadMinutes = 120

    @MainActor
    init(_ rule: NotificationRule) {
        isEnabled = rule.isEnabled; aheadDays = rule.aheadDays; aheadMinuteOfDay = rule.aheadMinuteOfDay
        leadEnabled = rule.leadEnabled; leadMinutes = rule.leadMinutes
    }

    init(isEnabled: Bool = true, aheadDays: Int = 1, aheadMinuteOfDay: Int = 1080, leadEnabled: Bool = true,
         leadMinutes: Int = 120) {
        self.isEnabled = isEnabled; self.aheadDays = aheadDays; self.aheadMinuteOfDay = aheadMinuteOfDay
        self.leadEnabled = leadEnabled; self.leadMinutes = leadMinutes
    }
}

nonisolated enum DeadlineCopy {
    /// N9 — one deadline. `{title} is due {date} {time}` / `closes` /
    /// `Registration for {title} ends {date} {time}`; body `{course} ·
    /// {source}` (no course: `{source}`).
    static func n9(_ d: DeadlineSnapshot, calendar: Calendar) -> NotificationText {
        let when = "\(date(d.due, calendar)) \(TravelCopy.time(d.due, calendar: calendar))"
        let title: String = switch d.wording {
        case .registrationEnds?: "Registration for \(d.title) ends \(when)"
        case .closes?: "\(d.title) closes \(when)"
        default: "\(d.title) is due \(when)"
        }
        return NotificationText(title: title, body: NotificationCopy.joined([d.course, d.sourceName]))
    }

    /// N10 — a group (§40.4): `{n} deadlines on {date} at {time}` when they
    /// share one time, else `{n} deadlines on {date}`; entries `{time}
    /// {title} ({course})` joined by ` · `, in §37.1's order.
    static func n10(_ members: [DeadlineSnapshot], calendar: Calendar) -> NotificationText {
        let sorted = sortedMembers(members)
        let first = sorted[0]
        let times = Set(sorted.map { TravelCopy.time($0.due, calendar: calendar) })
        let title = times.count == 1
            ? "\(sorted.count) deadlines on \(date(first.due, calendar)) at \(TravelCopy.time(first.due, calendar: calendar))"
            : "\(sorted.count) deadlines on \(date(first.due, calendar))"
        let body = sorted.map { d in
            "\(TravelCopy.time(d.due, calendar: calendar)) \(d.title)" + (d.course.map { " (\($0))" } ?? "")
        }.joined(separator: " · ")
        return NotificationText(title: title, body: body)
    }

    /// §37.1's order among deadlines: the instant, then the title.
    static func sortedMembers(_ members: [DeadlineSnapshot]) -> [DeadlineSnapshot] {
        members.sorted { $0.due != $1.due ? $0.due < $1.due : ($0.title != $1.title ? $0.title < $1.title
                                                                    : $0.id.uuidString < $1.id.uuidString) }
    }

    /// `EEE d MMM` — `Tue 13 Oct`.
    static func date(_ d: Date, _ calendar: Calendar) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = "EEE d MMM"
        return f.string(from: d)
    }

    /// `yyyyMMdd` of the due date, local.
    static func dayStamp(_ d: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// `yyyyMMdd'T'HHmm'Z'` in UTC.
    static func fireStamp(_ d: Date) -> String { String(ICSFormat.utcStamp(d).dropLast(3)) + "Z" }
}

nonisolated enum DeadlinePlanner {
    /// §40.3: a pair closer than this collapses to the final reminder; the
    /// catch-up's "within 60 min".
    static let collapse: TimeInterval = 60 * 60

    enum Which: String, Sendable { case ahead, close }

    struct Input: Sendable {
        var deadlines: [DeadlineSnapshot]
        var rule: DeadlineRule
        var windows: [QuietWindow]
        /// Identifier → the fire date the centre was given.
        var records: [String: Date]
        var now: Date
        var isCatchUp = false
        var calendar: Calendar
    }

    /// One reminder before grouping.
    struct Reminder: Sendable, Equatable {
        var deadline: DeadlineSnapshot
        var which: Which
        /// When it is delivered.
        var fireAt: Date
        var atOnce: Bool
        /// The fire time it was planned for — a missed one keeps it, so a
        /// caught-up group has the identifier it would have had (§43.2).
        var plannedFor: Date
        var identifier: String { "due.\(deadline.id.uuidString).\(which.rawValue)" }
    }

    /// `due.day.{yyyyMMdd}.{F}` (§40.6).
    static func groupIdentifier(day: String, fire: Date) -> String { "due.day.\(day).\(DeadlineCopy.fireStamp(fire))" }

    /// §40.1: the early reminder's fire time.
    static func aheadTime(due: Date, rule: DeadlineRule, calendar: Calendar) -> Date? {
        guard rule.aheadDays > 0 else { return nil }
        let day = calendar.date(byAdding: .day, value: -rule.aheadDays, to: calendar.startOfDay(for: due))
            ?? calendar.startOfDay(for: due)
        return WallClock.moment(minuteOfDay: rule.aheadMinuteOfDay, on: day, calendar: calendar)
    }

    /// §40.1: the final reminder's fire time — a duration.
    static func closeTime(due: Date, rule: DeadlineRule) -> Date? {
        rule.leadEnabled ? due.addingTimeInterval(-TimeInterval(rule.leadMinutes * 60)) : nil
    }

    /// §40.3 step 1: held to the end of a protected span (repeat for
    /// back-to-back spans); at or after the due moment it fires at the first
    /// span's start − 1 min instead. Returns nil when there is no time
    /// before the deadline left outside a window (nothing to plan).
    static func quiet(_ fire: Date, due: Date, windows: [QuietWindow], calendar: Calendar) -> Date? {
        var f = fire
        var firstStart: Date?
        for _ in 0..<16 {
            let day = calendar.startOfDay(for: f)
            let days = [-1, 0, 1].compactMap { calendar.date(byAdding: .day, value: $0, to: day) }
            let span = windows.flatMap { w in days.flatMap { w.spans(on: $0, calendar: calendar) } }
                .first { $0.start <= f && f < $0.end }
            guard let span else { break }
            if firstStart == nil { firstStart = span.start }
            f = span.end
        }
        guard f >= due else { return f }
        return firstStart.map { $0.addingTimeInterval(-60) }
    }

    static func plan(_ input: Input) -> [PlannedNotification] {
        guard input.rule.isEnabled else { return [] }
        let cal = input.calendar
        let now = input.now
        let today = cal.startOfDay(for: now)
        var reminders: [Reminder] = []

        for d in input.deadlines where d.isEligible && d.due > now && d.due >= today {
            let day = DeadlineCopy.dayStamp(d.due, cal)
            let ahead = aheadTime(due: d.due, rule: input.rule, calendar: cal)
                .flatMap { quiet($0, due: d.due, windows: input.windows, calendar: cal) }
            let close = closeTime(due: d.due, rule: input.rule)
                .flatMap { quiet($0, due: d.due, windows: input.windows, calendar: cal) }
            var times: [(Which, Date)] = []
            if let ahead { times.append((.ahead, ahead)) }
            if let close { times.append((.close, close)) }
            // Step 2 — collapse.
            if let ahead, let close, close.timeIntervalSince(ahead) < collapse { times.removeAll { $0.0 == .ahead } }

            var upcoming: [Reminder] = []
            var missed: [Reminder] = []
            for (which, fire) in times {
                // Sent alone or as part of a group: either record counts.
                let records = ["due.\(d.id.uuidString).\(which.rawValue)", groupIdentifier(day: day, fire: fire)]
                    .compactMap { input.records[$0] }
                if fire > now {
                    // §27.6: a sent identifier is never planned again unless
                    // its fire date moved.
                    if records.contains(where: { $0 <= now && $0 == fire }) { continue }
                    upcoming.append(Reminder(deadline: d, which: which, fireAt: fire, atOnce: false, plannedFor: fire))
                } else if records.isEmpty {
                    missed.append(Reminder(deadline: d, which: which, fireAt: fire, atOnce: true, plannedFor: fire))
                }
            }
            reminders += upcoming
            // §40.6 catch-up (launch and wake only): one for the deadline,
            // unless its other reminder comes within 60 min.
            if input.isCatchUp, let last = missed.last,
               !upcoming.contains(where: { $0.fireAt.timeIntervalSince(now) <= collapse }) {
                // "At once" = `F = now` through §40.3 step 1.
                if let held = quiet(now, due: d.due, windows: input.windows, calendar: cal), held >= now {
                    reminders.append(Reminder(deadline: d, which: last.which, fireAt: held, atOnce: held == now,
                                              plannedFor: last.plannedFor))
                }
            }
        }

        // §40.4 — grouping: the same fire time, due on the same local date.
        struct Key: Hashable { var day: String; var plannedFor: Date; var fireAt: Date; var atOnce: Bool }
        var groups: [Key: [Reminder]] = [:]
        for r in reminders {
            groups[Key(day: DeadlineCopy.dayStamp(r.deadline.due, cal), plannedFor: r.plannedFor, fireAt: r.fireAt,
                       atOnce: r.atOnce), default: []].append(r)
        }
        var planned: [PlannedNotification] = []
        for (key, members) in groups {
            if members.count == 1, let r = members.first {
                planned.append(PlannedNotification(
                    identifier: r.identifier, subjectID: r.deadline.id.uuidString, kind: .due, fireAt: r.fireAt,
                    atOnce: r.atOnce, text: DeadlineCopy.n9(r.deadline, calendar: cal), category: .deadline,
                    playsSound: true, interruption: .active))
            } else {
                planned.append(PlannedNotification(
                    identifier: groupIdentifier(day: key.day, fire: key.plannedFor), subjectID: key.day, kind: .due,
                    fireAt: key.fireAt, atOnce: key.atOnce, text: DeadlineCopy.n10(members.map(\.deadline), calendar: cal),
                    category: .deadlines, playsSound: true, interruption: .active))
            }
        }
        return planned.sorted { ($0.fireAt, $0.identifier) < ($1.fireAt, $1.identifier) }
    }
}
