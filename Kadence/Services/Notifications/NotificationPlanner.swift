//
//  NotificationPlanner.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 8) — components.md §27.1–
//  §27.5, §27.6 (the planning half), §27.9.
//
//  Pure: value snapshots of events, legs, rules, protected windows and
//  records, `now`, and whether this is a catch-up pass, in; the requests
//  that should be pending out. At most one of `leave.` / `start.` per
//  event; absolute times only; never `late`, `missed` or `overdue`. The
//  applier (task 9) diffs this against the centre.
//

import Foundation

/// A protected `TimeWindow` as the planner reads it, with §13.6.1's spans
/// (an overnight window counts on both days) — the same algorithm as
/// `TimeWindow.spans(on:)`, as a value.
nonisolated struct QuietWindow: Sendable, Equatable {
    var weekdays: Set<Int>
    var startMinutes: Int
    var endMinutes: Int
    var label: String

    init(weekdays: Set<Int>, startMinutes: Int, endMinutes: Int, label: String) {
        self.weekdays = weekdays
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.label = label
    }

    @MainActor
    init(_ window: TimeWindow) {
        self.init(weekdays: window.weekdays, startMinutes: window.startMinutes, endMinutes: window.endMinutes,
                  label: window.label)
    }

    func spans(on day: Date, calendar: Calendar) -> [(start: Date, end: Date)] {
        let startOfDay = calendar.startOfDay(for: day)
        let weekday = calendar.component(.weekday, from: startOfDay)
        var result: [(Date, Date)] = []
        func add(_ from: Int, _ to: Int) {
            guard to > from else { return }
            result.append((startOfDay.addingTimeInterval(TimeInterval(from * 60)),
                           startOfDay.addingTimeInterval(TimeInterval(to * 60))))
        }
        if endMinutes > startMinutes {
            if weekdays.contains(weekday) { add(startMinutes, endMinutes) }
        } else {
            if weekdays.contains(weekday) { add(startMinutes, 24 * 60) }
            let previous = (weekday - 2 + 7) % 7 + 1
            if weekdays.contains(previous) { add(0, endMinutes) }
        }
        return result
    }
}

/// One request the centre should hold (§27.6).
nonisolated struct PlannedNotification: Sendable, Equatable {
    var identifier: String
    /// The event's id as a string, or the source's id for `sync.`.
    var subjectID: String
    var kind: NotificationKindPrefix
    /// When it fires. For a delivery "at once" (catch-up, results, N8) this
    /// is `now` and `atOnce` is set: a 1-second trigger.
    var fireAt: Date
    var atOnce: Bool
    var text: NotificationText
    var category: NotificationCategory
    var playsSound: Bool
    var interruption: InterruptionLevel

    var contentHash: String { NotificationCopy.contentHash(text, category: category) }
}

nonisolated enum NotificationPlanner {
    /// §27.6: requests whose fire time is in `(now, now + 48 h]`, at most 48.
    static let window: TimeInterval = 48 * 3600
    static let cap = 48
    /// §27.3: travel unavailable fires `start − 60 min`.
    static let unavailableLead: TimeInterval = 60 * 60

    struct Rule: Sendable, Equatable {
        var leadMinutes: Int
        var isEnabled: Bool
    }

    struct Input: Sendable {
        var events: [TravelEventSnapshot]
        var legs: [UUID: LegValues]
        /// Each event's resolved place (§23.2), for `{where}` and the chain.
        var eventPlaces: [UUID: String]
        var placeNames: [String: String]
        var sourceNames: [String: String]
        var rules: [NotificationRuleKind: Rule]
        var windows: [QuietWindow]
        /// Identifier → the fire date the centre was given (§27.6 records).
        var records: [String: Date]
        var chainGapMinutes: Int = 120
        /// Events whose departure refresh just moved `departAt` earlier
        /// (§27.6: the refresh catch-up).
        var refreshedEarlier: Set<UUID> = []
        var now: Date
        /// The pass after launch and after wake (§27.6).
        var isCatchUp: Bool = false
        var calendar: Calendar
    }

    static func plan(_ input: Input) -> [PlannedNotification] {
        let calendar = input.calendar
        let now = input.now
        let today = calendar.startOfDay(for: now)
        let horizon = now.addingTimeInterval(window)
        let chainGap = TimeInterval(input.chainGapMinutes * 60)
        let placed = input.events.filter {
            !$0.isAllDay && !$0.isCancelled && $0.status != .skipped && input.eventPlaces[$0.id] != nil
        }
        func time(_ date: Date) -> String { TravelCopy.time(date, calendar: calendar) }

        var planned: [PlannedNotification] = []
        for event in input.events {
            // §27.2: none for all-day, cancelled, done, skipped, before today,
            // and `.planned` in this slice.
            guard !event.isAllDay, !event.isCancelled, event.status == .scheduled, event.start >= today,
                  event.origin != .planned else { continue }
            let leg = input.legs[event.id]
            let leaveRule = input.rules[.leaveBy] ?? Rule(leadMinutes: 5, isEnabled: true)
            let category: NotificationCategory = event.origin == .imported ? .readOnly : .event
            let placeName = input.eventPlaces[event.id].flatMap { input.placeNames[$0] }
            let place = NotificationCopy.whereText(locationText: event.locationText, isOnline: event.isOnline,
                                                   placeName: placeName)
            let start = time(event.start)
            let identifier: String
            let subject: Date
            var fire: Date
            enum Shape { case leave(LegValues, Date), unavailable(LegValues), starts }
            let shape: Shape

            if let leg, leaveRule.isEnabled {
                identifier = "leave.\(event.id.uuidString)"
                if leg.hasTime, let departAt = leg.departAt {
                    shape = .leave(leg, departAt)
                    subject = departAt
                    fire = departAt.addingTimeInterval(-TimeInterval(leaveRule.leadMinutes * 60))
                } else {
                    shape = .unavailable(leg)
                    subject = event.start
                    fire = event.start.addingTimeInterval(-unavailableLead)
                }
            } else {
                let kind: NotificationRuleKind = switch event.origin {
                case .imported: .timetableStart
                case .routine: .routineStart
                default: .personalStart
                }
                guard let rule = input.rules[kind], rule.isEnabled else { continue }
                identifier = "start.\(event.id.uuidString)"
                shape = .starts
                subject = event.start
                fire = event.start.addingTimeInterval(-TimeInterval(rule.leadMinutes * 60))
                // §27.3 chain clamp: §24.2's P within the chain gap (whatever
                // its place) → `min(max(F, P.end), start)`.
                if let previous = previousEvent(of: event, among: placed),
                   event.start.timeIntervalSince(previous.end) <= chainGap {
                    fire = min(max(fire, previous.end), event.start)
                }
            }

            // §27.5: protected windows hold the notification.
            let (held, holdingWindow) = hold(fire, event: event, windows: input.windows, calendar: calendar)
            fire = held

            // Which copy, and is it on time, late, or not at all?
            let record = input.records[identifier]
            var atOnce = false
            var text: NotificationText
            var interruption: InterruptionLevel = .timeSensitive

            func leaveText(_ leg: LegValues, _ departAt: Date, catchUpAfterDeparture: Bool) -> NotificationText {
                let origin = originName(leg, placeNames: input.placeNames)
                let minutes = TravelCopy.minutes(leg.duration ?? 0)
                if catchUpAfterDeparture {
                    return NotificationCopy.n3(title: event.title, depart: time(departAt), start: start, where: place,
                                               isEstimate: leg.isEstimate)
                }
                if fire > departAt, let holdingWindow {
                    return NotificationCopy.n2(title: event.title, depart: time(departAt), start: start, where: place,
                                               window: holdingWindow, isEstimate: leg.isEstimate)
                }
                if leg.isEstimate {
                    let reason = leg.reason.map {
                        TravelCopy.shortReason($0, place: leg.reasonPlaceID.flatMap { input.placeNames[$0] },
                                               mode: leg.mode, retryAt: leg.retryAt, calendar: calendar)
                    } ?? "offline"
                    return NotificationCopy.n1e(title: event.title, depart: time(departAt), start: start, where: place,
                                                minutes: minutes, origin: origin, reason: reason)
                }
                return NotificationCopy.n1(title: event.title, depart: time(departAt), start: start, where: place,
                                           minutes: minutes, origin: origin)
            }

            switch shape {
            case .leave(let leg, let departAt):
                if departAt <= now {
                    // The subject has passed. Only a catch-up pass delivers,
                    // with N3, while the event has not started.
                    guard input.isCatchUp, record == nil, now < event.start else { continue }
                    text = leaveText(leg, departAt, catchUpAfterDeparture: true)
                    atOnce = true
                } else if fire <= now {
                    let refreshCatchUp = input.refreshedEarlier.contains(event.id) && (record.map { $0 > now } ?? false)
                    guard (input.isCatchUp && record == nil) || refreshCatchUp else { continue }
                    text = leaveText(leg, departAt, catchUpAfterDeparture: false)
                    atOnce = true
                } else {
                    text = leaveText(leg, departAt, catchUpAfterDeparture: false)
                }
            case .unavailable(let leg):
                guard subject > now else { continue }
                let origin = originName(leg, placeNames: input.placeNames)
                let reason = leg.reason == .pending || leg.reason == nil ? nil : TravelCopy.shortReason(
                    leg.reason ?? .failed, place: leg.reasonPlaceID.flatMap { input.placeNames[$0] }, mode: leg.mode,
                    retryAt: leg.retryAt, calendar: calendar)
                text = NotificationCopy.n7(title: event.title, start: start, where: place, origin: origin, reason: reason)
                if fire <= now {
                    guard input.isCatchUp, record == nil else { continue }
                    atOnce = true
                }
            case .starts:
                guard subject > now else { continue }
                let source = event.sourceID.flatMap { input.sourceNames[$0] } ?? ""
                text = NotificationCopy.n4(title: event.title, start: start, where: place, source: source)
                interruption = .active
                if fire <= now {
                    guard input.isCatchUp, record == nil else { continue }
                    atOnce = true
                }
            }

            let fireAt = atOnce ? now : fire
            guard fireAt <= horizon else { continue }
            // §27.6: a sent identifier is never planned again unless its
            // subject moved (a new fire date in the future).
            if let record, record <= now, !atOnce, record == fireAt { continue }

            planned.append(PlannedNotification(
                identifier: identifier, subjectID: event.id.uuidString,
                kind: identifier.hasPrefix("leave.") ? .leave : .start,
                fireAt: fireAt, atOnce: atOnce, text: text, category: category, playsSound: true,
                interruption: interruption))
        }

        let sorted = planned.sorted { ($0.fireAt, $0.identifier) < ($1.fireAt, $1.identifier) }
        return Array(sorted.prefix(cap))
    }

    /// `{origin}`: the origin place's name, or `where you are`.
    static func originName(_ leg: LegValues, placeNames: [String: String]) -> String {
        if leg.originKind == .currentLocation { return TravelCopy.whereYouAre }
        return leg.originPlaceID.flatMap { placeNames[$0] } ?? "Home"
    }

    /// §24.2's `P` for an event: the placed event starting before it with
    /// the latest end (ties: later start, then smaller id).
    static func previousEvent(of event: TravelEventSnapshot, among placed: [TravelEventSnapshot]) -> TravelEventSnapshot? {
        placed.filter { $0.id != event.id && $0.start < event.start }.max { a, b in
            if a.end != b.end { return a.end < b.end }
            if a.start != b.start { return a.start < b.start }
            return a.id.uuidString > b.id.uuidString
        }
    }

    /// §27.5: while `F` is inside a protected span the event does not
    /// strictly overlap, move it to the span's end. Returns the new time and
    /// the label of the first window that held it (nil if none did).
    static func hold(_ fire: Date, event: TravelEventSnapshot, windows: [QuietWindow],
                     calendar: Calendar) -> (Date, String?) {
        var f = fire
        var label: String?
        for _ in 0..<16 {
            let day = calendar.startOfDay(for: f)
            let days = [-1, 0, 1].compactMap { calendar.date(byAdding: .day, value: $0, to: day) }
            let holding = windows.flatMap { window in
                days.flatMap { window.spans(on: $0, calendar: calendar).map { (span: $0, label: window.label) } }
            }.first { entry in
                entry.span.start <= f && f < entry.span.end
                    && !(event.start < entry.span.end && entry.span.start < event.end)
            }
            guard let holding else { break }
            if label == nil { label = holding.label }
            f = holding.span.end
        }
        return (f, label)
    }
}
