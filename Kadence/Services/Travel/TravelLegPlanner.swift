//
//  TravelLegPlanner.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 3) — components.md §23.2,
//  §23.3, §24.1–§24.4, §24.9 (the cache key), §24.10 (statuses and the
//  fallback order).
//
//  Pure: value snapshots in (events, places, overrides, settings, sources,
//  the ETA cache, the queue's failure and pause state, the existing legs,
//  `today`, `now`), out: the legs every surface reads and the requests the
//  routing queue must send. It calls no provider and reads no clock — every
//  time comes in through `Input`.
//

import Foundation

// MARK: - Which place an event is at (§23.2)

nonisolated enum PlaceResolver {
    /// §23.2's six rules, first match wins. Returns a known place id or nil.
    /// `sourceKinds` maps `Source.id` → kind (the timetable rule reads the
    /// resolved source's kind, §21.1.1); `knownPlaceIDs` are the places that
    /// exist (a manual event naming no existing place has none).
    static func place(of event: TravelEventSnapshot, sourceKinds: [String: CalendarSourceKind],
                      knownPlaceIDs: Set<String>) -> String? {
        // 1. all-day or cancelled: never travels.
        if event.isAllDay || event.isCancelled { return nil }
        switch event.origin {
        // 2. routine (and planned): transparent to travel in this slice (G-084).
        case .routine, .planned:
            return nil
        // 3. manual: the place `placeID` names, if it exists.
        case .manual:
            guard let id = event.placeID, knownPlaceIDs.contains(id) else { return nil }
            return id
        case .imported:
            // 4. online: no travel (G-063).
            if event.isOnline { return nil }
            // 5. a timetable room is on the campus; no room is geocoded.
            let location = (event.locationText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let sourceID = event.sourceID, sourceKinds[sourceID] == .universityTimetable, !location.isEmpty {
                return BuiltInPlace.campus.id
            }
            // 6. any other imported event: none in this slice (G-085).
            return nil
        }
    }

    /// §23.3: the pair's override if one exists, else the preferred mode.
    static func mode(from origin: String, to destination: String, overrides: [OverrideSnapshot],
                     preferred: TravelMode) -> TravelMode {
        let (a, b) = TravelModeOverride.sorted(origin, destination)
        return overrides.first { $0.placeA == a && $0.placeB == b }?.mode ?? preferred
    }
}

/// A `TravelModeOverride` as the planner reads it.
nonisolated struct OverrideSnapshot: Sendable, Equatable {
    var placeA: String
    var placeB: String
    var mode: TravelMode

    init(_ first: String, _ second: String, mode: TravelMode) {
        (placeA, placeB) = TravelModeOverride.sorted(first, second)
        self.mode = mode
    }

    @MainActor
    init(_ row: TravelModeOverride) {
        placeA = row.placeA
        placeB = row.placeB
        mode = row.mode
    }
}

// MARK: - The cache key (§24.9)

nonisolated struct TravelCacheKey: Sendable, Hashable {
    var originPlaceID: String
    var originLatitude: Double
    var originLongitude: Double
    var destinationPlaceID: String
    var destinationLatitude: Double
    var destinationLongitude: Double
    var mode: TravelMode
    var dayType: TravelDayType
    /// The arrival time (`start − buffer`) rounded down to 30 minutes, as
    /// minutes after midnight.
    var slotMinutes: Int

    /// Coordinates rounded to 5 decimals, so a new address is a new key.
    static func rounded(_ value: Double) -> String { String(format: "%.5f", value) }

    /// The key's fields joined. The order of origin and destination is the
    /// direction: a trip and its return are two keys. Stored in
    /// `TravelETACache.key`; never logged (§24.11).
    var string: String {
        "\(originPlaceID)@\(Self.rounded(originLatitude)),\(Self.rounded(originLongitude))"
            + ">\(destinationPlaceID)@\(Self.rounded(destinationLatitude)),\(Self.rounded(destinationLongitude))"
            + "|\(mode.rawValue)|\(dayType.rawValue)|\(slotMinutes)"
    }

    init(origin: TravelEndpoint, destination: TravelEndpoint, mode: TravelMode, arrival: Date, calendar: Calendar) {
        originPlaceID = origin.id ?? ""
        originLatitude = origin.latitude
        originLongitude = origin.longitude
        destinationPlaceID = destination.id ?? ""
        destinationLatitude = destination.latitude
        destinationLongitude = destination.longitude
        self.mode = mode
        dayType = TravelDayType.of(arrival, calendar: calendar)
        slotMinutes = Self.slot(of: arrival, calendar: calendar)
    }

    /// Minutes after midnight, rounded down to a multiple of 30.
    static func slot(of arrival: Date, calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: arrival)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return minutes - minutes % 30
    }
}

// MARK: - The planner

nonisolated enum TravelLegPlanner {

    /// §24.9: fresh for planning while at most 14 days old.
    static let freshFor: TimeInterval = 14 * 86_400
    /// §24.9: entries older than 28 days are deleted at launch (and are
    /// therefore never a fallback).
    static let keptFor: TimeInterval = 28 * 86_400

    /// What the routing queue last saw for a key (memory only, §24.9).
    struct KeyFailure: Sendable, Equatable {
        var reason: TravelReason
        var retryAt: Date?
    }

    /// The queue's state the planner reads.
    struct QueueState: Sendable, Equatable {
        /// The last failure per key since its last success.
        var failures: [String: KeyFailure] = [:]
        /// A throttle pause (§24.9): every waiting leg carries `paused`.
        var pausedUntil: Date?
        /// The day budget is spent: priorities 3–4 wait until this time.
        var budgetResumesAt: Date?
        /// The queue is paused because a request failed `offline`: every
        /// request it would send now fails the same way, so a waiting key is
        /// `offline` too (§24.4 `travelOffline`: "every leg asks, fails
        /// offline and falls back").
        var isOffline: Bool = false
    }

    /// The outcome of a leg's departure refresh in its current window
    /// (§24.6; filled by the refresh scheduler, task 6).
    struct RefreshOutcome: Sendable, Equatable {
        /// The refresh slot (T−3 h or T−45 min) this outcome is for.
        var slot: Date
        /// nil: the refresh answered. Otherwise why it failed.
        var failure: TravelReason?
        var retryAt: Date?
        /// The cache key the refresh asked for; an outcome for another key
        /// (the event moved, the mode changed) no longer applies.
        var key: String?
        /// When a successful refresh answered (`TravelLeg.refreshedAt`).
        var answeredAt: Date?
    }

    struct Input: Sendable {
        var events: [TravelEventSnapshot]
        var places: [PlaceSnapshot]
        var overrides: [OverrideSnapshot]
        var preferredMode: TravelMode
        var bufferMinutes: Int
        var chainGapMinutes: Int
        var sourceKinds: [String: CalendarSourceKind]
        var cache: [ETACacheEntry]
        var queue: QueueState = QueueState()
        /// The legs the store holds now (the "own last time" fallback,
        /// `refreshedAt`, and current-location legs, §24.2.1).
        var existingLegs: [UUID: LegValues] = [:]
        var refreshes: [UUID: RefreshOutcome] = [:]
        /// §23.6: the campus's automatic lookup has not answered yet.
        var campusLookupPending: Bool = false
        /// `mapKit` in a normal launch, `mock` in tests and review.
        var providerSource: String
        var now: Date
        var calendar: Calendar
    }

    /// One request the queue must send: an ETA for a key nobody has a fresh
    /// answer for. Several events may share it.
    struct Request: Sendable, Equatable {
        var key: String
        var origin: TravelEndpoint
        var destination: TravelEndpoint
        var mode: TravelMode
        var arrivingBy: Date
        /// §24.9: 3 for legs of today and tomorrow, 4 for the rest (0–2 are
        /// the user's and the refreshes', not the planner's). Handed to the
        /// queue even when it remembers a failure for the key — the queue
        /// decides (§24.9).
        var priority: Int
        /// The earliest start among the events sharing it (the queue's
        /// order inside priority 4).
        var eventStart: Date
        var eventIDs: [UUID]
        var dayType: TravelDayType
        var slotMinutes: Int
        var originPlaceID: String
        var destinationPlaceID: String
    }

    struct Output: Sendable {
        /// One entry per leg candidate that needs travel; an event missing
        /// here has no leg (no place, same place, not a candidate).
        var legs: [UUID: LegValues]
        var requests: [Request]
        /// Each leg's rule origin (for §24.2.1 and the inspector), and the
        /// previous event `P` that made it, when it chained.
        var ruleOrigins: [UUID: String]
        var chainedFrom: [UUID: UUID]
    }

    static func plan(_ input: Input) -> Output {
        let calendar = input.calendar
        let today = calendar.startOfDay(for: input.now)
        let placeIDs = Set(input.places.map(\.id))
        let placesByID = Dictionary(input.places.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let cacheByKey = Dictionary(input.cache.map { ($0.key, $0) }, uniquingKeysWith: { a, b in a.computedAt >= b.computedAt ? a : b })
        let buffer = TimeInterval(input.bufferMinutes * 60)
        let chainGap = TimeInterval(input.chainGapMinutes * 60)

        // §24.1: origin candidates (any day) and leg candidates (today on).
        let resolved: [(event: TravelEventSnapshot, place: String)] = input.events.compactMap { event in
            guard !event.isAllDay, !event.isCancelled, event.status != .skipped,
                  let place = PlaceResolver.place(of: event, sourceKinds: input.sourceKinds, knownPlaceIDs: placeIDs)
            else { return nil }
            return (event, place)
        }

        var legs: [UUID: LegValues] = [:]
        var ruleOrigins: [UUID: String] = [:]
        var chainedFrom: [UUID: UUID] = [:]
        var requestsByKey: [String: Request] = [:]
        let tomorrowEnd = calendar.date(byAdding: .day, value: 2, to: today) ?? today

        for (event, destination) in resolved where event.start >= today {
            // §24.2: the origin candidate with a place, start before E's,
            // with the latest end (ties: later start, then smaller id).
            let previous = resolved
                .filter { $0.event.id != event.id && $0.event.start < event.start }
                .max { a, b in
                    if a.event.end != b.event.end { return a.event.end < b.event.end }
                    if a.event.start != b.event.start { return a.event.start < b.event.start }
                    return a.event.id.uuidString > b.event.id.uuidString
                }
            var origin = BuiltInPlace.home.id
            if let previous, event.start.timeIntervalSince(previous.event.end) <= chainGap {
                origin = previous.place
                chainedFrom[event.id] = previous.event.id
            }
            ruleOrigins[event.id] = origin
            // §24.3: same place, no leg.
            guard origin != destination else { continue }

            let mode = PlaceResolver.mode(from: origin, to: destination, overrides: input.overrides,
                                          preferred: input.preferredMode)
            let existing = input.existingLegs[event.id]

            // §24.2.1: a current-location leg keeps its values until its next
            // refresh, or until the event, destination, mode or buffer change.
            if let existing, existing.originKind == .currentLocation, existing.hasTime,
               existing.destinationPlaceID == destination, existing.mode == mode, existing.buffer == buffer,
               let departAt = existing.departAt, let duration = existing.duration,
               departAt.addingTimeInterval(buffer + roundedUp(duration)) == event.start {
                legs[event.id] = existing
                continue
            }

            var leg = LegValues(eventID: event.id, status: .pending, buffer: buffer, mode: mode,
                                originPlaceID: origin, destinationPlaceID: destination)

            // §24.3 needsAddress: an endpoint without a coordinate. The
            // campus before its automatic lookup has answered is pending.
            let originPlace = placesByID[origin]
            let destinationPlace = placesByID[destination]
            guard let from = originPlace?.endpoint, let to = destinationPlace?.endpoint else {
                let missing = originPlace?.endpoint == nil ? origin : destination
                if missing == BuiltInPlace.campus.id, input.campusLookupPending {
                    leg.status = .pending
                    leg.reason = .pending
                } else {
                    leg.status = .unavailable
                    leg.reason = .needsAddress
                    leg.reasonPlaceID = missing
                }
                legs[event.id] = leg
                continue
            }

            let arrival = event.start.addingTimeInterval(-buffer)
            let key = TravelCacheKey(origin: from, destination: to, mode: mode, arrival: arrival, calendar: calendar)
            let keyString = key.string
            let entry = cacheByKey[keyString].flatMap { input.now.timeIntervalSince($0.computedAt) <= keptFor ? $0 : nil }
            let isFresh = entry.map { input.now.timeIntervalSince($0.computedAt) <= freshFor } ?? false
            let failure = input.queue.failures[keyString]
            let priority = event.start < tomorrowEnd ? 3 : 4

            // The queue waits on this key: a recorded failure (remembered,
            // so it is not re-queued, §24.9), a throttle pause, or a spent
            // day budget for priorities 3–4.
            var waiting: KeyFailure? = failure
            if !isFresh, waiting == nil {
                if let until = input.queue.pausedUntil, until > input.now {
                    waiting = KeyFailure(reason: .paused, retryAt: until)
                } else if priority >= 3, let resumes = input.queue.budgetResumesAt, resumes > input.now {
                    waiting = KeyFailure(reason: .paused, retryAt: resumes)
                } else if input.queue.isOffline {
                    waiting = KeyFailure(reason: .offline, retryAt: nil)
                }
            }
            // A refresh due in this window that failed (§24.3 `ready`: "if a
            // refresh was due, the refresh answered").
            let refresh = input.refreshes[event.id].flatMap { $0.key == nil || $0.key == keyString ? $0 : nil }
            let refreshFailure = refresh.flatMap { outcome -> KeyFailure? in
                guard let reason = outcome.failure, outcome.slot <= input.now else { return nil }
                return KeyFailure(reason: reason, retryAt: outcome.retryAt)
            }

            if let entry, isFresh || (failure == nil && waiting?.reason != .offline), refreshFailure == nil {
                // Ready: Apple Maps answered for this key — a stale entry
                // counts while its new request is outstanding.
                fill(&leg, from: entry, start: event.start, buffer: buffer, source: input.providerSource)
                leg.status = .ready
                leg.refreshedAt = refresh?.answeredAt ?? (sameTrip(existing, leg) ? existing?.refreshedAt : nil)
            } else if let failed = refreshFailure ?? (entry != nil && isFresh ? nil : waiting) {
                // §24.10: the latest request this leg needed failed.
                fallback(&leg, reason: failed.reason, retryAt: failed.retryAt, existing: existing, entry: entry,
                         key: key, cache: input.cache, now: input.now, start: event.start, buffer: buffer,
                         source: input.providerSource)
            } else {
                leg.status = .pending
                leg.reason = .pending
            }

            legs[event.id] = leg

            // Every key with no fresh answer goes to the queue, which
            // remembers its failures (§24.9): it does not re-queue a key that
            // failed `noRoute` or `failed`, and holds one it is pausing on.
            // A key no leg needs any more is dropped there.
            if !isFresh {
                if var request = requestsByKey[keyString] {
                    request.priority = min(request.priority, priority)
                    if event.start < request.eventStart {
                        request.eventStart = event.start
                        request.arrivingBy = arrival
                    }
                    request.eventIDs.append(event.id)
                    requestsByKey[keyString] = request
                } else {
                    requestsByKey[keyString] = Request(
                        key: keyString, origin: from, destination: to, mode: mode, arrivingBy: arrival,
                        priority: priority, eventStart: event.start, eventIDs: [event.id], dayType: key.dayType,
                        slotMinutes: key.slotMinutes, originPlaceID: origin, destinationPlaceID: destination)
                }
            }
        }

        let requests = requestsByKey.values.sorted {
            ($0.priority, $0.eventStart, $0.key) < ($1.priority, $1.eventStart, $1.key)
        }
        return Output(legs: legs, requests: requests, ruleOrigins: ruleOrigins, chainedFrom: chainedFrom)
    }

    /// The travel time the leave-by uses, rounded up to the whole minute, so
    /// `departAt` sits on a minute and `Leave 08:15 · 35min` adds up. A
    /// mock or MapKit answer in whole minutes is unchanged.
    static func roundedUp(_ seconds: TimeInterval) -> TimeInterval {
        (seconds / 60).rounded(.up) * 60
    }

    private static func fill(_ leg: inout LegValues, from entry: ETACacheEntry, start: Date, buffer: TimeInterval,
                             source: String) {
        let duration = roundedUp(entry.travelSeconds)
        leg.duration = duration
        leg.departAt = start.addingTimeInterval(-buffer - duration)
        leg.computedAt = entry.computedAt
        leg.source = source
    }

    private static func sameTrip(_ existing: LegValues?, _ leg: LegValues) -> Bool {
        guard let existing else { return false }
        return existing.originKind == .place && existing.originPlaceID == leg.originPlaceID
            && existing.destinationPlaceID == leg.destinationPlaceID && existing.mode == leg.mode
            && existing.buffer == leg.buffer && existing.departAt == leg.departAt
    }

    /// §24.10, first match wins.
    private static func fallback(_ leg: inout LegValues, reason: TravelReason, retryAt: Date?, existing: LegValues?,
                                 entry: ETACacheEntry?, key: TravelCacheKey, cache: [ETACacheEntry], now: Date,
                                 start: Date, buffer: TimeInterval, source: String) {
        leg.reason = reason
        leg.retryAt = reason == .paused ? retryAt : nil
        // 1. noRoute (and needsAddress, handled before) rule out a fallback.
        if reason == .noRoute {
            leg.status = .unavailable
            return
        }
        // 2. This event's own last time, for the same trip.
        if let existing, existing.hasTime, existing.originKind == .place,
           existing.originPlaceID == leg.originPlaceID, existing.destinationPlaceID == leg.destinationPlaceID,
           existing.mode == leg.mode, let duration = existing.duration {
            leg.status = .estimate
            leg.duration = duration
            leg.departAt = start.addingTimeInterval(-buffer - duration)
            leg.computedAt = existing.computedAt
            leg.source = existing.source.isEmpty ? source : existing.source
            return
        }
        // 3. The cache's entry for this key, any age up to 28 days.
        if let entry {
            fill(&leg, from: entry, start: start, buffer: buffer, source: source)
            leg.status = .estimate
            return
        }
        // 4. The nearest cached slot for the same trip (origin, destination,
        //    mode, direction): the same day type first, then any; ties to
        //    the earlier slot.
        let candidates = cache.filter {
            now.timeIntervalSince($0.computedAt) <= keptFor
                && $0.originPlaceID == key.originPlaceID && $0.destinationPlaceID == key.destinationPlaceID
                && $0.mode == key.mode && sameCoordinates($0.key, key)
        }
        func nearest(_ entries: [ETACacheEntry]) -> ETACacheEntry? {
            entries.min { a, b in
                let da = abs(a.slotMinutes - key.slotMinutes), db = abs(b.slotMinutes - key.slotMinutes)
                return da != db ? da < db : a.slotMinutes < b.slotMinutes
            }
        }
        if let near = nearest(candidates.filter { $0.dayType == key.dayType }) ?? nearest(candidates) {
            fill(&leg, from: near, start: start, buffer: buffer, source: source)
            leg.status = .estimate
            return
        }
        // 5. Nothing: unavailable with the reason.
        leg.status = .unavailable
    }

    /// An entry is for the same trip only if its coordinates are the key's
    /// (a new address is a new trip, §24.9).
    private static func sameCoordinates(_ entryKey: String, _ key: TravelCacheKey) -> Bool {
        let prefix = key.string.split(separator: "|").first.map(String.init) ?? ""
        return entryKey.hasPrefix(prefix + "|")
    }
}
