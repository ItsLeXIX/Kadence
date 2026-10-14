//
//  NotificationScheduler.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 9) — components.md §27.6,
//  §27.8, §27.10, §27.4 (levels and the degrade rule).
//
//  A pass: snapshot the store, run `NotificationPlanner`, read (and, the
//  first time there is something to schedule, ask for) authorization, and
//  — only when `allowed` — diff the plan against the centre by identifier
//  and content hash: add, replace, remove, record. Delivered notifications
//  of ended, deleted, done, skipped or cancelled events are cleared in the
//  same pass. Requests whose identifiers Kadence does not own are never
//  touched.
//
//  Passes: after every leg recompute (`TravelCoordinator.onPassCompleted`),
//  on a rule or `TimeWindow` edit, on an authorization change, hourly.
//  Debounced 1 s on the injected clock, one at a time; a trigger during a
//  pass is coalesced into one more pass after it. The pass after launch and
//  after wake is a catch-up (§27.6).
//
//  G-092 (recorded in STATUS): a main-actor class; the centre's calls are
//  the only `await`s, and the store is read and written on the main actor
//  between them.
//

import Foundation
import Observation
import SwiftData
import AppKit

@MainActor
@Observable
final class NotificationScheduler {
    @ObservationIgnored let context: ModelContext
    @ObservationIgnored let centre: any NotificationCenterClient
    @ObservationIgnored let clock: any TravelClock
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored let log: RoutingLog
    /// Events whose departure refresh may have moved `departAt` earlier
    /// (§27.6's refresh catch-up); read once per pass.
    @ObservationIgnored var consumeRefreshed: () -> Set<UUID> = { [] }
    /// Extra planned requests (the sync-paused N8, task 11).
    @ObservationIgnored var extraRequests: (Date) -> [PlannedNotification] = { _ in [] }

    /// §27.8's state, for Settings ▸ Notifications and the popover.
    private(set) var permission: NotificationPermission = .notAsked
    /// The last plan (review's plan dump, §30 item 14).
    @ObservationIgnored private(set) var lastPlan: [PlannedNotification] = []
    @ObservationIgnored private(set) var passCount = 0

    static let debounce: TimeInterval = 1
    static let hourly: TimeInterval = 3600
    /// §27.6: records are deleted when their event ended more than a day ago.
    static let recordKeep: TimeInterval = 86_400

    @ObservationIgnored private var debounceWake: ScheduledWake?
    @ObservationIgnored private var hourlyWake: ScheduledWake?
    @ObservationIgnored private var passTask: Task<Void, Never>?
    @ObservationIgnored private var again = false
    @ObservationIgnored private var pendingCatchUp = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var isStarted = false

    init(context: ModelContext, centre: any NotificationCenterClient, clock: any TravelClock,
         calendar: Calendar = .current, log: RoutingLog) {
        self.context = context
        self.centre = centre
        self.clock = clock
        self.calendar = calendar
        self.log = log
    }

    // MARK: Triggers

    /// Debounced 1 s; `catchUp` sticks until the pass runs.
    func requestPass(catchUp: Bool = false) {
        if catchUp { pendingCatchUp = true }
        debounceWake?.cancel()
        debounceWake = clock.wake(at: clock.now.addingTimeInterval(Self.debounce)) { [weak self] in
            self?.debounceWake = nil
            self?.startPass()
        }
    }

    /// The app's launch: register the categories, read the state, keep the
    /// hourly pass going and observe the triggers. The first pass comes
    /// from the travel coordinator's launch pass (a catch-up).
    func start() {
        guard !isStarted else { return }
        isStarted = true
        let centre = centre
        Task { await centre.setCategories(NotificationCategorySpec.all) }
        Task { await self.refreshPermission() }
        scheduleHourly()
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: ModelContext.didSave, object: context, queue: nil) { [weak self] note in
            guard Self.touchesRules(note.userInfo) else { return }
            TravelCoordinator.onMain { self?.requestPass() }
        })
        observers.append(center.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil,
                                            queue: nil) { [weak self] _ in
            TravelCoordinator.onMain { Task { await self?.refreshPermission() } }
        })
    }

    /// §27.6: rule and `TimeWindow` edits trigger a pass (event edits do
    /// through the leg recompute).
    nonisolated static func touchesRules(_ userInfo: [AnyHashable: Any]?) -> Bool {
        guard let userInfo else { return false }
        let keys = [ModelContext.NotificationKey.insertedIdentifiers, .updatedIdentifiers, .deletedIdentifiers]
            .map(\.rawValue)
        return keys.contains { key in
            (userInfo[key] as? [PersistentIdentifier])?.contains {
                $0.entityName == "NotificationRule" || $0.entityName == "TimeWindow"
            } ?? false
        }
    }

    private func scheduleHourly() {
        hourlyWake?.cancel()
        hourlyWake = clock.wake(at: clock.now.addingTimeInterval(Self.hourly)) { [weak self] in
            self?.hourlyWake = nil
            self?.requestPass()
            self?.scheduleHourly()
        }
    }

    /// §27.8: re-read on launch, `didBecomeActive`, when Settings or the
    /// popover opens; when it becomes `allowed`, the next pass schedules the
    /// plan (an ordinary pass).
    func refreshPermission() async {
        let before = permission
        let authorization = await centre.authorization()
        permission = NotificationPermission.of(authorization, asked: settings.notificationsRequestedAt != nil)
        if permission != before, permission == .allowed { requestPass() }
    }

    /// `Allow Notifications…` / a rule switched on in Settings: asks the
    /// same way the first pass does (§27.8). Returns whether a request was
    /// made (`false`: already answered — the caller opens System Settings).
    @discardableResult
    func askForPermission() async -> Bool {
        let authorization = await centre.authorization()
        guard authorization == .notDetermined else {
            permission = NotificationPermission.of(authorization, asked: settings.notificationsRequestedAt != nil)
            return false
        }
        settings.notificationsRequestedAt = clock.now
        try? context.save()
        _ = await centre.requestAuthorization()
        await refreshPermission()
        requestPass()
        return true
    }

    // MARK: The pass

    private func startPass() {
        guard passTask == nil else { again = true; return }
        let catchUp = pendingCatchUp
        pendingCatchUp = false
        passTask = Task { [weak self] in
            await self?.pass(catchUp: catchUp)
            guard let self else { return }
            self.passTask = nil
            if self.again {
                self.again = false
                self.startPass()
            }
        }
    }

    private var settings: AppSettings { TravelBuiltIns.settings(in: context) }

    /// One pass, now (tests call it directly).
    func pass(catchUp: Bool = false) async {
        passCount += 1
        let now = clock.now
        let plan = makePlan(now: now, catchUp: catchUp)
        lastPlan = plan

        var authorization = await centre.authorization()
        // §27.8: ask once, the first time a pass has something to schedule.
        if authorization == .notDetermined, settings.notificationsRequestedAt == nil, !plan.isEmpty {
            settings.notificationsRequestedAt = clock.now
            try? context.save()
            _ = await centre.requestAuthorization()
            authorization = await centre.authorization()
        }
        permission = NotificationPermission.of(authorization, asked: settings.notificationsRequestedAt != nil)
        // Not allowed: add nothing, remove nothing pending, record nothing.
        guard authorization == .allowed else { return }
        await apply(plan, now: now)
    }

    /// The planner's input from the store.
    func makePlan(now: Date, catchUp: Bool = false) -> [PlannedNotification] {
        let events = (try? context.fetch(FetchDescriptor<Event>())) ?? []
        let places = (try? context.fetch(FetchDescriptor<KnownPlace>())) ?? []
        let sources = (try? context.fetch(FetchDescriptor<Source>())) ?? []
        let rules = (try? context.fetch(FetchDescriptor<NotificationRule>())) ?? []
        let windows = ((try? context.fetch(FetchDescriptor<TimeWindow>())) ?? []).filter { $0.kind == .protected }
        let legs = (try? context.fetch(FetchDescriptor<TravelLeg>())) ?? []
        let records = (try? context.fetch(FetchDescriptor<NotificationRecord>())) ?? []
        let kinds = Dictionary(sources.map { ($0.id, $0.kind) }, uniquingKeysWith: { a, _ in a })
        let placeIDs = Set(places.map(\.id))
        let snapshots = events.map(TravelEventSnapshot.init)
        let input = NotificationPlanner.Input(
            events: snapshots,
            legs: Dictionary(legs.map { ($0.eventID, LegValues($0)) }, uniquingKeysWith: { a, _ in a }),
            eventPlaces: Dictionary(snapshots.compactMap { event in
                PlaceResolver.place(of: event, sourceKinds: kinds, knownPlaceIDs: placeIDs).map { (event.id, $0) }
            }, uniquingKeysWith: { a, _ in a }),
            placeNames: Dictionary(places.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a }),
            sourceNames: Dictionary(sources.map { ($0.id, $0.displayName) }, uniquingKeysWith: { a, _ in a }),
            rules: Dictionary(rules.map { ($0.kind, NotificationPlanner.Rule(leadMinutes: $0.leadMinutes,
                                                                             isEnabled: $0.isEnabled)) },
                              uniquingKeysWith: { a, _ in a }),
            windows: windows.map(QuietWindow.init),
            records: Dictionary(records.map { ($0.identifier, $0.fireAt) }, uniquingKeysWith: { a, b in max(a, b) }),
            chainGapMinutes: settings.travelChainGapMinutes,
            refreshedEarlier: consumeRefreshed(), now: now, isCatchUp: catchUp, calendar: calendar)
        let plan = NotificationPlanner.plan(input) + extraRequests(now)
        return plan.sorted { ($0.fireAt, $0.identifier) < ($1.fireAt, $1.identifier) }
    }

    /// §27.6's diff. Owned prefixes only; `result.` requests are answers
    /// delivered at once and are left to fire.
    private func apply(_ plan: [PlannedNotification], now: Date) async {
        let records = Dictionary(((try? context.fetch(FetchDescriptor<NotificationRecord>())) ?? [])
            .map { ($0.identifier, $0) }, uniquingKeysWith: { a, _ in a })
        let pending = await centre.pending()
        let planned = Dictionary(plan.map { ($0.identifier, $0) }, uniquingKeysWith: { a, _ in a })
        let pendingByID = Dictionary(pending.map { ($0.identifier, $0) }, uniquingKeysWith: { a, _ in a })

        var removals: [String] = []
        for request in pending {
            guard let prefix = NotificationKindPrefix.of(request.identifier), prefix != .result,
                  planned[request.identifier] == nil else { continue }
            // A request already due (sent at once, or firing now) is left to
            // fire: it is "sent" (§27.6).
            if let record = records[request.identifier], record.fireAt <= now { continue }
            removals.append(request.identifier)
        }
        if !removals.isEmpty { await centre.removePending(removals) }

        for item in plan {
            if let existing = pendingByID[item.identifier], existing.fireAt == item.fireAt,
               existing.contentHash == item.contentHash, existing.atOnce == item.atOnce { continue }
            if pendingByID[item.identifier] != nil { await centre.removePending([item.identifier]) }
            var request = ScheduledRequest(item)
            do {
                try await centre.add(request)
            } catch {
                // §27.4: degrades, never fails — once more as `.active`.
                guard request.interruption == .timeSensitive else { continue }
                request.interruption = .active
                log.write("notification degraded · time-sensitive unavailable")
                guard (try? await centre.add(request)) != nil else { continue }
            }
            record(item)
        }

        await clearDelivered(now: now)
        pruneRecords(now: now)
        try? context.save()
    }

    private func record(_ item: PlannedNotification) {
        let id = item.identifier
        var descriptor = FetchDescriptor<NotificationRecord>(predicate: #Predicate { $0.identifier == id })
        descriptor.fetchLimit = 1
        if let row = try? context.fetch(descriptor).first {
            row.fireAt = item.fireAt
            row.contentHash = item.contentHash
            row.subjectID = item.subjectID
        } else {
            context.insert(NotificationRecord(identifier: id, subjectID: item.subjectID, kind: item.kind.rawValue,
                                              fireAt: item.fireAt, contentHash: item.contentHash))
        }
    }

    /// §27.6 / §27.9: delivered notifications whose event has ended, been
    /// deleted, done, skipped or cancelled are removed.
    private func clearDelivered(now: Date) async {
        let delivered = await centre.delivered()
        guard !delivered.isEmpty else { return }
        let events = Dictionary(((try? context.fetch(FetchDescriptor<Event>())) ?? []).map { ($0.id, $0) },
                                uniquingKeysWith: { a, _ in a })
        let stale = delivered.map(\.identifier).filter { id in
            guard let prefix = NotificationKindPrefix.of(id), prefix != .sync else { return false }
            guard let eventID = Self.eventID(in: id), let event = events[eventID] else { return true }
            return event.end <= now || event.status != .scheduled || event.isCancelled
        }
        if !stale.isEmpty { await centre.removeDelivered(stale) }
    }

    /// Records go with their event, and a day after it ended.
    private func pruneRecords(now: Date) {
        let events = Dictionary(((try? context.fetch(FetchDescriptor<Event>())) ?? []).map { ($0.id, $0) },
                                uniquingKeysWith: { a, _ in a })
        for record in (try? context.fetch(FetchDescriptor<NotificationRecord>())) ?? [] {
            guard record.kind != NotificationKindPrefix.sync.rawValue else { continue }
            guard let id = UUID(uuidString: record.subjectID), let event = events[id] else {
                context.delete(record)
                continue
            }
            if now.timeIntervalSince(event.end) > Self.recordKeep { context.delete(record) }
        }
    }

    /// `leave.{id}`, `start.{id}`, `result.{id}.{epoch}` → the event id.
    nonisolated static func eventID(in identifier: String) -> UUID? {
        let parts = identifier.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        return UUID(uuidString: String(parts[1]))
    }

    // MARK: Tests

    func settle() async {
        while let task = passTask { await task.value }
    }
}
