//
//  RouteRequestQueue.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 5) — components.md §24.9
//  "The routing queue", §24.10 (`paused`), §24.11 (log lines).
//
//  Every MapKit request — an ETA or an address lookup — goes through here:
//
//  - priorities 0 (the user asked) … 4 (the rest, by event start); a key
//    already queued is not queued twice; a queued request whose leg
//    disappeared is dropped;
//  - one request in flight, at least 2 s between two, at most 20 per
//    rolling 10 minutes and 150 a day (priorities 0–2 may use 30 more);
//  - `throttled`: the whole queue pauses 10 minutes, doubling on each
//    consecutive throttle up to 60, reset by a success;
//  - `offline`: the queue pauses until the path monitor reports satisfied,
//    or 5 minutes pass;
//  - each request has a 20 s timeout (→ `failed`).
//
//  It remembers the last failure per key (memory only), which the leg
//  planner reads (`plannerState`): a key that failed `noRoute` or `failed`
//  is not re-queued by a recompute; one it is pausing on waits here.
//
//  G-092 (recorded in STATUS): a main-actor class, not an actor — its
//  callers (the recompute and the Settings lookups) are on the main actor
//  and its answers re-enter the main-actor recompute directly. Every wait is
//  a wake on the injected `TravelClock`; the only off-main work is the
//  provider call itself.
//

import Foundation

@MainActor
final class RouteRequestQueue {

    // MARK: Jobs

    /// What an ETA request is for.
    enum Purpose: Sendable, Equatable {
        /// A leg whose key has no fresh answer (the planner's, priority 3–4),
        /// or the user's `Try Again` (priority 0).
        case change
        /// A departure refresh (§24.6) for one event; bypasses the cache.
        /// `fromHere`: the origin is the current location (§24.2.1).
        case refresh(eventID: UUID, slot: Date, fromHere: Bool)
    }

    struct ETAJob: Sendable, Equatable {
        var key: String
        var origin: TravelEndpoint
        var destination: TravelEndpoint
        var mode: TravelMode
        var arrivingBy: Date
        var purpose: Purpose
        /// The planner's request, for writing the answer to the cache. Nil
        /// for a current-location refresh (never cached, §24.2.1).
        var request: TravelLegPlanner.Request?
    }

    enum Job {
        case eta(ETAJob)
        case lookup(address: String, completion: @MainActor (Result<[GeocodedAddress], GeocodeError>) -> Void)
    }

    private struct Item {
        var id: String
        var priority: Int
        var order: Date
        var seq: Int
        var job: Job
        /// Queued by the planner's pass (dropped when no leg needs it).
        var isPlanned: Bool
    }

    // MARK: Limits (§24.9)

    struct Limits: Sendable {
        var spacing: TimeInterval = 2
        var windowLength: TimeInterval = 600
        var windowMax = 20
        var dayMax = 150
        var dayExtraForUrgent = 30
        var timeout: TimeInterval = 20
        var offlineWait: TimeInterval = 300
        /// 10, 20, 40, 60, 60 … minutes.
        func throttlePause(consecutive: Int) -> TimeInterval {
            min(600 * pow(2, Double(max(consecutive, 1) - 1)), 3600)
        }
    }

    // MARK: State

    let provider: any TravelTimeProvider
    let geocoder: any PlaceGeocoder
    let clock: any TravelClock
    let path: any PathMonitoring
    let calendar: Calendar
    let log: RoutingLog
    let limits: Limits

    /// An answer or a failure for an ETA job, with the time it arrived.
    var onETA: ((ETAJob, Result<TimeInterval, TravelTimeError>, Date) -> Void)?
    /// A pause began or ended, or a remembered failure was cleared: legs
    /// that read `plannerState` need a recompute.
    var onStateChange: (() -> Void)?

    private var items: [Item] = []
    private var inFlight: Item?
    private var inFlightTask: Task<Void, Never>?
    private var timeoutWake: ScheduledWake?
    private var wake: ScheduledWake?
    private var wakeAt: Date?
    private var seq = 0
    private var sentAt: [Date] = []
    private var lastSentAt: Date?
    private var dayStart: Date?
    private var dayCount = 0
    private var consecutiveThrottles = 0
    private(set) var pausedUntil: Date?
    private var offlinePausedUntil: Date?
    private(set) var budgetResumesAt: Date?
    private(set) var failures: [String: TravelLegPlanner.KeyFailure] = [:]
    /// What left, and when (tests read it; ids only, no place or title).
    private(set) var history: [(id: String, at: Date)] = []

    init(provider: any TravelTimeProvider, geocoder: any PlaceGeocoder, clock: any TravelClock,
         path: any PathMonitoring, calendar: Calendar = .current, log: RoutingLog, limits: Limits = Limits()) {
        self.provider = provider
        self.geocoder = geocoder
        self.clock = clock
        self.path = path
        self.calendar = calendar
        self.log = log
        self.limits = limits
        path.onChange = { [weak self] satisfied in
            guard let self, satisfied, self.offlinePausedUntil != nil else { return }
            // §24.9: offline pauses the queue until the path is satisfied.
            self.offlinePausedUntil = nil
            self.onStateChange?()
            self.pump()
        }
    }

    // MARK: What the planner reads

    var plannerState: TravelLegPlanner.QueueState {
        let now = clock.now
        return TravelLegPlanner.QueueState(
            failures: failures,
            pausedUntil: pausedUntil.flatMap { $0 > now ? $0 : nil },
            budgetResumesAt: budgetResumesAt.flatMap { $0 > now ? $0 : nil })
    }

    var queuedIDs: [String] { items.sorted(by: Self.order).map(\.id) }
    var isIdle: Bool { inFlight == nil && items.isEmpty }

    // MARK: Enqueueing

    /// The planner's pass: its requests replace every request it queued
    /// before. A key the queue remembers as `noRoute` or `failed` is not
    /// queued again; one it is pausing on (`offline`, `paused`) stays.
    func syncPlanned(_ requests: [TravelLegPlanner.Request]) {
        let wanted = Dictionary(requests.map { ("eta:" + $0.key, $0) }, uniquingKeysWith: { a, _ in a })
        // A queued request whose leg disappeared is dropped.
        items.removeAll { $0.isPlanned && wanted[$0.id] == nil }
        for (id, request) in wanted {
            if let failure = failures[request.key], failure.reason == .noRoute || failure.reason == .failed { continue }
            if inFlight?.id == id { continue }
            let job = ETAJob(key: request.key, origin: request.origin, destination: request.destination,
                             mode: request.mode, arrivingBy: request.arrivingBy, purpose: .change, request: request)
            insert(id: id, priority: request.priority, order: request.eventStart, job: .eta(job), isPlanned: true)
        }
        pump()
    }

    /// `Try Again` (§24.6 occasion 3): one request now, at the top priority,
    /// still subject to a pause. Forgets the key's remembered failure.
    func tryAgain(_ request: TravelLegPlanner.Request) {
        failures[request.key] = nil
        let job = ETAJob(key: request.key, origin: request.origin, destination: request.destination,
                         mode: request.mode, arrivingBy: request.arrivingBy, purpose: .change, request: request)
        insert(id: "eta:" + request.key, priority: 0, order: clock.now, job: .eta(job), isPlanned: false)
        pump()
    }

    /// A departure refresh (§24.6): priority 1 for the next departure, 2
    /// for the others. Bypasses the cache: it is sent even when the key has
    /// a fresh answer. One per event.
    func enqueueRefresh(_ job: ETAJob, eventID: UUID, priority: Int, eventStart: Date) {
        insert(id: "refresh:" + eventID.uuidString, priority: priority, order: eventStart, job: .eta(job), isPlanned: false)
        pump()
    }

    /// An address lookup (§23.5): one request at the top priority.
    func enqueueLookup(id: String, address: String,
                       completion: @escaping @MainActor (Result<[GeocodedAddress], GeocodeError>) -> Void) {
        insert(id: "lookup:" + id, priority: 0, order: clock.now, job: .lookup(address: address, completion: completion),
               isPlanned: false)
        pump()
    }

    /// Drops a queued refresh (the event moved, started or was deleted).
    func cancelRefresh(eventID: UUID) {
        items.removeAll { $0.id == "refresh:" + eventID.uuidString }
    }

    /// The day changed: a `failed` key may be asked again (memory only;
    /// `noRoute` stays until the trip's inputs change its key).
    func forgetTransientFailures() {
        let before = failures.count
        failures = failures.filter { $0.value.reason == .noRoute }
        if failures.count != before { onStateChange?() }
    }

    private func insert(id: String, priority: Int, order: Date, job: Job, isPlanned: Bool) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items[index].priority = min(items[index].priority, priority)
            items[index].order = min(items[index].order, order)
            if !isPlanned { items[index].isPlanned = false }
            if case .eta(let newJob) = job, case .eta(var old) = items[index].job {
                if newJob.arrivingBy < old.arrivingBy { old.arrivingBy = newJob.arrivingBy }
                old.request = newJob.request ?? old.request
                items[index].job = .eta(old)
            }
            return
        }
        seq += 1
        items.append(Item(id: id, priority: priority, order: order, seq: seq, job: job, isPlanned: isPlanned))
    }

    private static func order(_ a: Item, _ b: Item) -> Bool {
        (a.priority, a.order, a.seq) < (b.priority, b.order, b.seq)
    }

    // MARK: Sending

    /// Sends the next request if the limits allow, otherwise schedules a
    /// wake for when they will. Called after every change and every wake.
    func pump() {
        guard inFlight == nil else { return }
        let now = clock.now
        rollDay(now)
        if let until = pausedUntil {
            if until > now { return schedule(until) }
            pausedUntil = nil
            // The pause is over: legs waiting on it are pending again.
            failures = failures.filter { $0.value.reason != .paused }
            onStateChange?()
        }
        if let until = offlinePausedUntil {
            if until > now, !path.isSatisfied || offlineWaitsForTime { return schedule(until) }
            offlinePausedUntil = nil
        }
        let sorted = items.sorted(by: Self.order)
        guard !sorted.isEmpty else { return }
        // §24.9 day budget: 150, and 30 more for priorities 0–2.
        guard let next = sorted.first(where: { dayCount < limits.dayMax + ($0.priority <= 2 ? limits.dayExtraForUrgent : 0) })
        else {
            let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now
            if budgetResumesAt != midnight {
                budgetResumesAt = midnight
                onStateChange?()
            }
            return schedule(midnight)
        }
        // Only priorities 0–2 can still go today: the waiting 3–4 carry
        // `paused` until midnight (§24.9 "Budget spent").
        if dayCount >= limits.dayMax, budgetResumesAt == nil, sorted.contains(where: { $0.priority >= 3 }) {
            budgetResumesAt = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))
            onStateChange?()
        }
        // Spacing and the rolling window.
        sentAt.removeAll { now.timeIntervalSince($0) >= limits.windowLength }
        var earliest = now
        if let last = lastSentAt { earliest = max(earliest, last.addingTimeInterval(limits.spacing)) }
        if sentAt.count >= limits.windowMax, let oldest = sentAt.first {
            earliest = max(earliest, oldest.addingTimeInterval(limits.windowLength))
        }
        if earliest > now { return schedule(earliest) }
        send(next, now: now)
    }

    /// Whether the offline pause was taken while the path already looked
    /// satisfied (MapKit said offline anyway): then only the 5 minutes end it.
    private var offlineWaitsForTime = false

    private func schedule(_ date: Date) {
        if let wakeAt, wakeAt <= date, wake != nil { return }
        wake?.cancel()
        wakeAt = date
        wake = clock.wake(at: date) { [weak self] in
            guard let self else { return }
            self.wake = nil
            self.wakeAt = nil
            self.pump()
        }
    }

    private func rollDay(_ now: Date) {
        let today = calendar.startOfDay(for: now)
        if dayStart != today {
            if dayStart != nil { forgetTransientFailures() }
            dayStart = today
            dayCount = 0
            if budgetResumesAt != nil {
                budgetResumesAt = nil
                onStateChange?()
            }
        }
    }

    private func send(_ item: Item, now: Date) {
        items.removeAll { $0.id == item.id }
        inFlight = item
        lastSentAt = now
        sentAt.append(now)
        dayCount += 1
        history.append((item.id, now))
        if history.count > 1000 { history.removeFirst(history.count - 1000) }
        let token = item.seq
        timeoutWake = clock.wake(at: now.addingTimeInterval(limits.timeout)) { [weak self] in
            // §24.9: a request has 20 s; then it is `failed`.
            self?.finish(token: token, eta: .failure(.failed), lookup: .failure(.failed))
        }
        let provider = provider, geocoder = geocoder
        switch item.job {
        case .eta(let job):
            inFlightTask = Task { [weak self] in
                let result: Result<TimeInterval, TravelTimeError>
                do throws(TravelTimeError) {
                    result = .success(try await provider.duration(from: job.origin, to: job.destination,
                                                                   arrivingBy: job.arrivingBy, mode: job.mode))
                } catch {
                    result = .failure(error)
                }
                self?.finish(token: token, eta: result, lookup: nil)
            }
        case .lookup(let address, _):
            inFlightTask = Task { [weak self] in
                let result: Result<[GeocodedAddress], GeocodeError>
                do throws(GeocodeError) { result = .success(try await geocoder.lookUp(address)) } catch { result = .failure(error) }
                self?.finish(token: token, eta: nil, lookup: result)
            }
        }
    }

    private func finish(token: Int, eta: Result<TimeInterval, TravelTimeError>?,
                        lookup: Result<[GeocodedAddress], GeocodeError>?) {
        guard let item = inFlight, item.seq == token else { return }   // late: the timeout already answered
        inFlight = nil
        inFlightTask = nil
        timeoutWake?.cancel()
        timeoutWake = nil
        let now = clock.now
        switch item.job {
        case .eta(let job):
            handle(eta ?? .failure(.failed), job: job, item: item, now: now)
        case .lookup(_, let completion):
            let result = lookup ?? .failure(.failed)
            switch result {
            case .success(let found):
                log.write(found.isEmpty ? "lookup none" : "lookup ok · \(found.count) results")
            case .failure(let error):
                log.write("lookup failed · \(Self.word(error))")
                if error == .throttled { beginThrottlePause(now: now) }
                if error == .offline { beginOfflinePause(now: now) }
            }
            completion(result)
        }
        pump()
    }

    private func handle(_ result: Result<TimeInterval, TravelTimeError>, job: ETAJob, item: Item, now: Date) {
        let fromHere: Bool
        let isRefresh: Bool
        switch job.purpose {
        case .change: (isRefresh, fromHere) = (false, false)
        case .refresh(_, _, let here): (isRefresh, fromHere) = (true, here)
        }
        switch result {
        case .success(let seconds):
            consecutiveThrottles = 0
            if !fromHere { failures[job.key] = nil }
            log.write("eta ok · \(RoutingLog.minutes(seconds)) min · \(job.mode.label)"
                      + (isRefresh ? " · refresh" : "") + (fromHere ? " · here" : ""))
        case .failure(let error):
            log.write("eta failed · \(error.logWord) · \(job.mode.label)")
            switch error {
            case .throttled:
                beginThrottlePause(now: now)
                if !fromHere { failures[job.key] = .init(reason: .paused, retryAt: pausedUntil) }
                // The request waits for the pause to end.
                if !fromHere { reinsert(item) }
            case .offline:
                if !fromHere { failures[job.key] = .init(reason: .offline, retryAt: nil) }
                beginOfflinePause(now: now)
                if !fromHere, !isRefresh { reinsert(item) }
            case .noRoute, .failed:
                if !fromHere, !isRefresh { failures[job.key] = .init(reason: error.reason, retryAt: nil) }
            }
        }
        onETA?(job, result, now)
    }

    private func reinsert(_ item: Item) {
        guard !items.contains(where: { $0.id == item.id }) else { return }
        items.append(item)
    }

    private func beginThrottlePause(now: Date) {
        consecutiveThrottles += 1
        let until = now.addingTimeInterval(limits.throttlePause(consecutive: consecutiveThrottles))
        pausedUntil = until
        // Every waiting request carries the time the queue resumes.
        for (key, failure) in failures where failure.reason == .paused {
            failures[key] = .init(reason: .paused, retryAt: until)
        }
        log.write("queue paused · until \(RoutingLog.clock(until, calendar: calendar))")
        onStateChange?()
    }

    private func beginOfflinePause(now: Date) {
        offlinePausedUntil = now.addingTimeInterval(limits.offlineWait)
        offlineWaitsForTime = path.isSatisfied
        onStateChange?()
    }

    private static func word(_ error: GeocodeError) -> String {
        switch error {
        case .offline: "offline"
        case .throttled: "throttled"
        case .failed: "failed"
        }
    }

    // MARK: Tests

    /// Waits for the request in flight to finish (tests drive the clock;
    /// nothing here sleeps).
    func settle() async {
        while let task = inFlightTask { await task.value }
    }
}
