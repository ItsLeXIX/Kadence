//
//  TravelCoordinator.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 6) — components.md §24.5–
//  §24.8, §24.6 (departure refreshes), §23.6 (the campus's automatic
//  lookup); §20.8.4 "Local identity"; §20.9.
//
//  The recompute: reads the store and the ETA cache, plans with
//  `TravelLegPlanner`, and writes **only `TravelLeg` rows**, in one
//  transaction — never an undo step, never an event field (§24.7). It never
//  waits for the network: the planner's requests go to the routing queue,
//  whose answers are cached and trigger another pass.
//
//  Triggers (§24.6): any save that touched an `Event`, a known place, a
//  pair override, the settings or a source; a routing answer; a refresh
//  completing; launch, wake, the day changing, the clock or time zone
//  changing. Debounced 0.5 s on the injected clock, so a burst is one pass.
//  Every pass ends by asking the notification scheduler for a pass
//  (`onPassCompleted`, task 9).
//
//  G-092 (recorded in STATUS): main actor throughout; the debounce, the
//  refresh slots and the queue's waits are wakes on the injected
//  `TravelClock`.
//

import Foundation
import Observation
import SwiftData
import AppKit

@MainActor
@Observable
final class TravelCoordinator {
    /// Why a pass runs: launch and wake catch up a missed refresh slot and
    /// may retry the campus lookup (§24.6, §23.6).
    enum PassKind: Sendable, Equatable { case ordinary, launch, wake }

    @ObservationIgnored let context: ModelContext
    @ObservationIgnored let queue: RouteRequestQueue
    @ObservationIgnored let clock: any TravelClock
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored let providerSource: String
    @ObservationIgnored let log: RoutingLog
    /// §24.12: where the Mac is (a mock in tests and review).
    @ObservationIgnored let location: any LocationSource
    /// Asks the notification scheduler for a pass (task 9) — a catch-up
    /// after the launch and wake passes (§27.6).
    @ObservationIgnored var onPassCompleted: ((PassKind) -> Void)?
    /// Events whose departure refresh answered since the scheduler last
    /// read them (§27.6's refresh catch-up).
    @ObservationIgnored private var refreshedEvents: Set<UUID> = []
    /// Refresh answers not yet applied by a pass; published to
    /// `refreshedEvents` only once the pass has written the new times.
    @ObservationIgnored private var answeredRefreshes: Set<UUID> = []

    func consumeRefreshed() -> Set<UUID> {
        defer { refreshedEvents = [] }
        return refreshedEvents
    }

    /// Bumped by every pass that wrote a leg, so views can redraw.
    private(set) var revision = 0
    /// Every pass, for tests.
    @ObservationIgnored private(set) var passCount = 0
    /// The last plan (its rule origins and chains — the inspector's
    /// "No travel needed after …").
    @ObservationIgnored private(set) var lastOutput: TravelLegPlanner.Output?

    /// Review datasets `empty` / `fresh` only (§30.1, GAPS G-098): look the
    /// campus up at launch even when no leg needs it yet.
    @ObservationIgnored var looksUpCampusAtLaunch = false

    static let debounce: TimeInterval = 0.5
    /// §24.6: T−3 h and T−45 min.
    static let refreshOffsets: [TimeInterval] = [3 * 3600, 45 * 60]
    /// §24.6: while a leg has no time, T is `start − 60 min`.
    static let unknownDepartureLead: TimeInterval = 60 * 60

    @ObservationIgnored private var debounceWake: ScheduledWake?
    @ObservationIgnored private var refreshWake: ScheduledWake?
    @ObservationIgnored private var refreshWatermark: Date
    @ObservationIgnored private var refreshOutcomes: [UUID: TravelLegPlanner.RefreshOutcome] = [:]
    /// The refresh slots that ran, per event, with the start they were for
    /// (a moved event's slots are new).
    @ObservationIgnored private var ranSlots: [UUID: (start: Date, offsets: Set<TimeInterval>)] = [:]
    @ObservationIgnored private(set) var plannedSlots: [UUID: [Date]] = [:]
    @ObservationIgnored private var campusLookupInFlight = false
    /// §24.2.1: the one location step in flight, and what to fall back to if
    /// the request from where you are fails.
    @ObservationIgnored private var locationTask: Task<Void, Never>?
    @ObservationIgnored private var hereFallbacks: [UUID: () -> Void] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init(context: ModelContext, queue: RouteRequestQueue, clock: any TravelClock, calendar: Calendar = .current,
         providerSource: String, log: RoutingLog, location: any LocationSource) {
        self.location = location
        self.context = context
        self.queue = queue
        self.clock = clock
        self.calendar = calendar
        self.providerSource = providerSource
        self.log = log
        refreshWatermark = clock.now
        queue.onETA = { [weak self] job, result, at in self?.handleAnswer(job, result, at: at) }
        queue.onStateChange = { [weak self] in self?.requestRecompute() }
    }

    // MARK: Triggers

    /// Debounced: a burst of triggers is one pass, 0.5 s after the last.
    func requestRecompute() {
        debounceWake?.cancel()
        debounceWake = clock.wake(at: clock.now.addingTimeInterval(Self.debounce)) { [weak self] in
            self?.debounceWake = nil
            self?.recompute()
        }
    }

    @ObservationIgnored private var isStarted = false

    /// The app's launch: observe the triggers and run the launch pass, once
    /// (both windows may ask).
    func start() {
        guard !isStarted else { return }
        isStarted = true
        startObserving()
        launched()
    }

    /// Launch, after the store loads and the built-ins exist: prune the
    /// cache (§24.9) and pass, catching up a missed refresh slot.
    func launched() {
        TravelETACacheStore(context: context).prune(now: clock.now)
        recompute(.launch)
    }

    func didWake() { recompute(.wake) }

    /// `NSCalendarDayChanged`, a clock or time-zone change: the ownership
    /// window starts at the new `startOfDay(today)`.
    func dayChanged() { recompute() }

    /// The app's own observers (a normal and a review launch).
    func startObserving() {
        let center = NotificationCenter.default
        // `queue: nil` delivers on the posting thread: a save on the main
        // context is handled before `save()` returns, so a burst of saves is
        // debounced as it happens. A notification posted elsewhere hops.
        observers.append(center.addObserver(forName: ModelContext.didSave, object: context, queue: nil) { [weak self] note in
            guard Self.touchesInputs(note.userInfo) else { return }
            Self.onMain { self?.requestRecompute() }
        })
        for name in [Notification.Name.NSCalendarDayChanged, .NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            observers.append(center.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                Self.onMain { self?.dayChanged() }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { [weak self] _ in
            Self.onMain { self?.didWake() }
        })
    }

    /// Runs `work` on the main actor: at once when already on the main
    /// thread, otherwise hopping there.
    nonisolated static func onMain(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated { work() }
        } else {
            Task { @MainActor in work() }
        }
    }

    /// The entities whose saves are recompute inputs (§24.6). Leg, cache and
    /// record saves are the recompute's own and never trigger one.
    nonisolated static let inputEntities: Set<String> = [
        "Event", "Place", "KnownPlace", "TravelModeOverride", "AppSettings", "Source",
    ]

    nonisolated static func touchesInputs(_ userInfo: [AnyHashable: Any]?) -> Bool {
        guard let userInfo else { return true }
        let keys = [ModelContext.NotificationKey.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers]
            .map(\.rawValue)
        var sawAny = false
        for key in keys {
            guard let ids = userInfo[key] as? [PersistentIdentifier] else { continue }
            sawAny = true
            if ids.contains(where: { inputEntities.contains($0.entityName) }) { return true }
        }
        return !sawAny
    }

    // MARK: The pass

    /// One recompute pass, now. Returns how many legs it wrote (inserted,
    /// changed or deleted). Two passes over the same inputs write nothing
    /// the second time (§24.5).
    @discardableResult
    func recompute(_ kind: PassKind = .ordinary) -> Int {
        debounceWake?.cancel()
        debounceWake = nil
        passCount += 1
        let now = clock.now
        let today = calendar.startOfDay(for: now)

        let events = (try? context.fetch(FetchDescriptor<Event>())) ?? []
        let places = (try? context.fetch(FetchDescriptor<KnownPlace>())) ?? []
        let overrides = (try? context.fetch(FetchDescriptor<TravelModeOverride>())) ?? []
        let sources = (try? context.fetch(FetchDescriptor<Source>())) ?? []
        let settings = TravelBuiltIns.settings(in: context)
        let legs = (try? context.fetch(FetchDescriptor<TravelLeg>())) ?? []

        // §23.6: the campus's automatic lookup, once when first needed.
        let campus = places.first { $0.id == BuiltInPlace.campus.id }
        let lookupDue = campus.map { campusLookupIsDue($0, settings: settings, kind: kind, today: today) } ?? false

        let snapshots = events.map(TravelEventSnapshot.init)
        var existing: [UUID: LegValues] = [:]
        for leg in legs { existing[leg.eventID] = LegValues(leg) }
        let input = TravelLegPlanner.Input(
            events: snapshots, places: places.map(PlaceSnapshot.init), overrides: overrides.map(OverrideSnapshot.init),
            preferredMode: settings.preferredTravelMode, bufferMinutes: settings.travelBufferMinutes,
            chainGapMinutes: settings.travelChainGapMinutes,
            sourceKinds: Dictionary(sources.map { ($0.id, $0.kind) }, uniquingKeysWith: { a, _ in a }),
            cache: TravelETACacheStore(context: context).all().map(ETACacheEntry.init),
            queue: queue.plannerState, existingLegs: existing, refreshes: refreshOutcomes,
            campusLookupPending: campusLookupInFlight || lookupDue,
            providerSource: providerSource, now: now, calendar: calendar)
        let output = TravelLegPlanner.plan(input)
        lastOutput = output

        if lookupDue, let campus, (kind == .launch && looksUpCampusAtLaunch) || output.legs.values.contains(where: {
            $0.originPlaceID == campus.id || $0.destinationPlaceID == campus.id
        }) {
            startCampusLookup(campus, settings: settings, now: now)
        }

        let writes = apply(output, legs: legs, events: events, today: today)
        // The legs now carry the refreshed times: the notification pass this
        // one asks for may treat them as refreshed (§27.6).
        refreshedEvents.formUnion(answeredRefreshes)
        answeredRefreshes = []
        queue.syncPlanned(output.requests)
        planRefreshes(output, events: snapshots, places: places, settings: settings, now: now,
                      catchUp: kind != .ordinary)
        if writes > 0 { revision += 1 }
        onPassCompleted?(kind)
        return writes
    }

    /// §24.5: one transaction. Upsert changed legs, delete owned legs no
    /// longer planned (and legs whose event is gone), never touch a leg of
    /// an event before `startOfDay(today)`.
    private func apply(_ output: TravelLegPlanner.Output, legs: [TravelLeg], events: [Event], today: Date) -> Int {
        let starts = Dictionary(events.map { ($0.id, $0.start) }, uniquingKeysWith: { a, _ in a })
        var writes = 0
        var seen = Set<UUID>()
        for leg in legs {
            guard let start = starts[leg.eventID] else {
                context.delete(leg)        // its event is gone
                writes += 1
                continue
            }
            if start < today { continue }  // history: never recomputed
            if seen.contains(leg.eventID) { context.delete(leg); writes += 1; continue }
            seen.insert(leg.eventID)
            if let planned = output.legs[leg.eventID] {
                if LegValues(leg) != planned {
                    planned.write(to: leg)
                    writes += 1
                }
            } else {
                context.delete(leg)
                writes += 1
            }
        }
        for (eventID, planned) in output.legs where !seen.contains(eventID) {
            let leg = TravelLeg(eventID: eventID)
            planned.write(to: leg)
            context.insert(leg)
            writes += 1
        }
        if writes > 0 { try? context.save() }
        return writes
    }

    // MARK: Routing answers

    private func handleAnswer(_ job: RouteRequestQueue.ETAJob, _ result: Result<TimeInterval, TravelTimeError>,
                              at: Date) {
        let store = TravelETACacheStore(context: context)
        switch job.purpose {
        case .change:
            if case .success(let seconds) = result, let request = job.request {
                store.upsert(request, travelSeconds: seconds, computedAt: at)
            }
        case .refresh(let eventID, let slot, let fromHere) where fromHere:
            let fallback = hereFallbacks.removeValue(forKey: eventID)
            switch result {
            case .success(let seconds):
                writeHereLeg(eventID: eventID, seconds: seconds, at: at)
                answeredRefreshes.insert(eventID)
                refreshOutcomes[eventID] = .init(slot: slot, failure: nil, key: nil, answeredAt: at)
            case .failure:
                // §24.2.1: a failed request from the fix refreshes from the
                // rule origin as usual.
                fallback?()
            }
        case .refresh(let eventID, let slot, let fromHere):
            switch result {
            case .success(let seconds):
                // A refresh ignores freshness; its answer updates the entry
                // (§24.9). A trip from where you are is never cached.
                if !fromHere, let request = job.request {
                    store.upsert(request, travelSeconds: seconds, computedAt: at)
                }
                answeredRefreshes.insert(eventID)
                refreshOutcomes[eventID] = .init(slot: slot, failure: nil, key: job.request?.key, answeredAt: at)
            case .failure(let error):
                refreshOutcomes[eventID] = .init(slot: slot, failure: error.reason,
                                                 retryAt: error == .throttled ? queue.pausedUntil : nil,
                                                 key: job.request?.key)
            }
        }
        requestRecompute()
    }

    // MARK: Departure refreshes (§24.6)

    /// Re-plans the T−3 h / T−45 min refreshes of every leg of a not-started
    /// event today or tomorrow, and sends the ones that are due: a slot that
    /// passed since the last pass, or — at launch or wake — the latest slot
    /// missed while Kadence was not running or the Mac slept, once, before
    /// the start.
    private func planRefreshes(_ output: TravelLegPlanner.Output, events: [TravelEventSnapshot],
                               places: [KnownPlace], settings: AppSettings, now: Date, catchUp: Bool) {
        refreshWake?.cancel()
        refreshWake = nil
        let horizon = calendar.date(byAdding: .day, value: 2, to: calendar.startOfDay(for: now)) ?? now
        let byID = Dictionary(events.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let endpoints = Dictionary(places.map { ($0.id, PlaceSnapshot($0).endpoint) }, uniquingKeysWith: { a, _ in a })
        let candidates = output.legs.values.compactMap { leg -> (LegValues, TravelEventSnapshot)? in
            guard let event = byID[leg.eventID], event.start > now, event.start < horizon else { return nil }
            return (leg, event)
        }
        let nextDeparture = candidates.min { $0.1.start < $1.1.start }?.1.id
        // §24.2.1: the next departure for location — the earliest
        // not-started leg whose departure is due within 45 minutes.
        let locationLeg = candidates.filter { leg, event in
            let departure = leg.departAt ?? event.start.addingTimeInterval(-Self.unknownDepartureLead)
            return departure.addingTimeInterval(-45 * 60) <= now
        }.min { $0.1.start < $1.1.start }?.1.id
        var nextSlot: Date?
        plannedSlots = [:]

        for (leg, event) in candidates {
            let departure = leg.departAt ?? event.start.addingTimeInterval(-Self.unknownDepartureLead)
            if let ran = ranSlots[event.id], ran.start != event.start { ranSlots[event.id] = nil }
            let ran = ranSlots[event.id]?.offsets ?? []
            let slots = Self.refreshOffsets.map { (offset: $0, at: departure.addingTimeInterval(-$0)) }
            plannedSlots[event.id] = slots.map(\.at)
            let due = slots.filter { slot in
                guard !ran.contains(slot.offset), slot.at <= now else { return false }
                return catchUp || slot.at > refreshWatermark
            }.max { $0.at < $1.at }
            if let due {
                // Both earlier slots count as run: one missed refresh runs once.
                var offsets = ran
                for slot in slots where slot.at <= due.at { offsets.insert(slot.offset) }
                ranSlots[event.id] = (event.start, offsets)
                let priority = event.id == nextDeparture ? 1 : 2
                if due.offset == 45 * 60, event.id == locationLeg, settings.useCurrentLocation {
                    // §24.2.1: the next departure's T−45 refresh may route
                    // from where the Mac is.
                    refreshFromHere(leg, event: event, slot: due.at, endpoints: endpoints, priority: priority,
                                    settings: settings)
                } else if leg.status != .pending {
                    // A leg still waiting for its first answer is being asked
                    // right now; that request is the refresh (DEVIATIONS B51).
                    sendRefresh(leg, event: event, slot: due.at, endpoints: endpoints, priority: priority, now: now)
                }
            }
            for slot in slots where slot.at > now && !ran.contains(slot.offset) {
                nextSlot = min(nextSlot ?? slot.at, slot.at)
            }
        }
        refreshWatermark = now
        if let nextSlot {
            refreshWake = clock.wake(at: nextSlot) { [weak self] in
                self?.refreshWake = nil
                self?.recompute()
            }
        }
    }

    private func sendRefresh(_ leg: LegValues, event: TravelEventSnapshot, slot: Date,
                             endpoints: [String: TravelEndpoint?], priority: Int, now: Date) {
        guard let originID = leg.originPlaceID, let origin = endpoints[originID] ?? nil,
              let destination = endpoints[leg.destinationPlaceID] ?? nil else { return }
        let arrival = event.start.addingTimeInterval(-leg.buffer)
        let key = TravelCacheKey(origin: origin, destination: destination, mode: leg.mode, arrival: arrival,
                                 calendar: calendar)
        let request = TravelLegPlanner.Request(
            key: key.string, origin: origin, destination: destination, mode: leg.mode, arrivingBy: arrival,
            priority: priority, eventStart: event.start, eventIDs: [event.id], dayType: key.dayType,
            slotMinutes: key.slotMinutes, originPlaceID: originID, destinationPlaceID: leg.destinationPlaceID)
        let job = RouteRequestQueue.ETAJob(key: key.string, origin: origin, destination: destination, mode: leg.mode,
                                           arrivingBy: arrival,
                                           purpose: .refresh(eventID: event.id, slot: slot, fromHere: false),
                                           request: request)
        queue.enqueueRefresh(job, eventID: event.id, priority: priority, eventStart: event.start)
    }

    // MARK: Where you are (§24.2.1, §24.12)

    /// The next departure's T−45 refresh. Asks once for permission when it
    /// was never asked (that refresh uses the rule origin); with location
    /// allowed, one fix — used if fresh, accurate and more than 300 m from
    /// the rule origin. Never blocks the departure: anything else refreshes
    /// from the rule origin. The fix lives in this function only.
    private func refreshFromHere(_ leg: LegValues, event: TravelEventSnapshot, slot: Date,
                                 endpoints: [String: TravelEndpoint?], priority: Int, settings: AppSettings) {
        let fallback = { [weak self] in
            guard let self else { return }
            // B51: a leg still waiting for its first answer is being asked.
            if leg.status != .pending {
                self.sendRefresh(leg, event: event, slot: slot, endpoints: endpoints, priority: priority, now: self.clock.now)
            }
        }
        guard let originID = leg.originPlaceID, let origin = endpoints[originID] ?? nil,
              let destination = endpoints[leg.destinationPlaceID] ?? nil else { return fallback() }
        let location = location
        let previous = locationTask
        locationTask = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            switch await location.authorization() {
            case .notDetermined:
                if settings.locationRequestedAt == nil {
                    settings.locationRequestedAt = self.clock.now
                    try? self.context.save()
                    _ = await location.requestAuthorization()
                }
                fallback()
            case .denied, .servicesOff:
                self.log.write("location unavailable · denied")
                fallback()
            case .allowed:
                guard let fix = await location.currentFix(timeout: LocationRules.timeout) else {
                    self.log.write("location unavailable · timeout")
                    return fallback()
                }
                switch LocationRules.verdict(fix, origin: origin, now: self.clock.now) {
                case .use:
                    self.log.write("location used")
                    let here = TravelEndpoint(id: nil, latitude: fix.latitude, longitude: fix.longitude)
                    let arrival = event.start.addingTimeInterval(-leg.buffer)
                    let job = RouteRequestQueue.ETAJob(
                        key: "here:" + event.id.uuidString, origin: here, destination: destination, mode: leg.mode,
                        arrivingBy: arrival, purpose: .refresh(eventID: event.id, slot: slot, fromHere: true),
                        request: nil)
                    self.hereFallbacks[event.id] = fallback
                    self.queue.enqueueRefresh(job, eventID: event.id, priority: priority, eventStart: event.start)
                case .withinRadius:
                    self.log.write("location not used · within 300 m")
                    fallback()
                case .unusable:
                    fallback()
                }
            }
        }
    }

    /// The answer from where you are: written onto the leg as
    /// `currentLocation` — no place id, no coordinate (§24.11) — and kept
    /// until the trip's inputs change (§24.2.1).
    private func writeHereLeg(eventID: UUID, seconds: TimeInterval, at: Date) {
        guard let leg = TravelLegs.leg(for: eventID, in: context),
              let event = ((try? context.fetch(FetchDescriptor<Event>(predicate: #Predicate { $0.id == eventID }))) ?? []).first
        else { return }
        let duration = TravelLegPlanner.roundedUp(seconds)
        var values = LegValues(leg)
        values.status = .ready
        values.reason = nil
        values.reasonPlaceID = nil
        values.retryAt = nil
        values.duration = duration
        values.departAt = event.start.addingTimeInterval(-leg.buffer - duration)
        values.originKind = .currentLocation
        values.originPlaceID = nil
        values.source = providerSource
        values.computedAt = at
        values.refreshedAt = at
        values.write(to: leg)
        try? context.save()
        revision += 1
    }

    /// Tests: wait for the location step in flight.
    func settleLocation() async {
        while let task = locationTask {
            await task.value
            if locationTask == task { locationTask = nil }
        }
    }

    // MARK: The campus (§23.6)

    /// Looked up automatically only while its address is Kadence's own and
    /// unconfirmed: the first time it is needed, and after a failed lookup
    /// at most once a day, at launch or wake. Never Home or a user place.
    private func campusLookupIsDue(_ campus: KnownPlace, settings: AppSettings, kind: PassKind, today: Date) -> Bool {
        guard !campusLookupInFlight, campus.geocodeState != .confirmed, !campus.hasCoordinate,
              campus.addressText == BuiltInPlace.campusAddress else { return false }
        guard let attempted = settings.campusLookupAttemptedAt else { return true }
        return kind != .ordinary && campus.geocodeState == .lookupFailed && attempted < today
    }

    private func startCampusLookup(_ campus: KnownPlace, settings: AppSettings, now: Date) {
        campusLookupInFlight = true
        settings.campusLookupAttemptedAt = now
        try? context.save()
        let address = campus.addressText ?? BuiltInPlace.campusAddress
        queue.enqueueLookup(id: campus.id, address: address) { [weak self] result in
            self?.finishCampusLookup(result)
        }
    }

    /// Accepted without confirmation when the first result's one-line
    /// address contains both `Höchstädtplatz 6` and `1200`.
    nonisolated static func campusMatches(_ line: String) -> Bool {
        line.contains("Höchstädtplatz 6") && line.contains("1200")
    }

    private func finishCampusLookup(_ result: Result<[GeocodedAddress], GeocodeError>) {
        campusLookupInFlight = false
        let places = (try? context.fetch(FetchDescriptor<KnownPlace>())) ?? []
        guard let campus = places.first(where: { $0.id == BuiltInPlace.campus.id }),
              campus.addressText == BuiltInPlace.campusAddress, campus.geocodeState != .confirmed
        else { return requestRecompute() }
        switch result {
        case .success(let found):
            if let first = found.first, Self.campusMatches(first.line) {
                campus.confirmedAddress = first.line
                campus.setCoordinate(latitude: first.latitude, longitude: first.longitude)
                campus.geocodeState = .confirmed
                campus.geocodedAt = clock.now
                TravelETACacheStore(context: context).deleteRows(of: campus.id, notAt: first.latitude, first.longitude)
            } else {
                campus.geocodeState = found.isEmpty ? .notFound : .unconfirmed
            }
        case .failure:
            campus.geocodeState = .lookupFailed
        }
        try? context.save()
        requestRecompute()
    }

    // MARK: Reading

    /// The leg the store holds for an event.
    func leg(for eventID: UUID) -> TravelLeg? { TravelLegs.leg(for: eventID, in: context) }

    /// Tests: the refresh outcome recorded for an event.
    func refreshOutcome(for eventID: UUID) -> TravelLegPlanner.RefreshOutcome? { refreshOutcomes[eventID] }
}
