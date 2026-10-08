//
//  SyncCoordinator.swift
//  Kadence
//
//  PHASE3-PLAN.md task 9 — interactions.md §13.3 (triggers, pause, offline,
//  timeouts, the `get`-mode floor, cancellation), components.md §19.1
//  (transitions), §20.8.2, G-061.
//
//  G-061, recorded (CA judgement): one `NSBackgroundActivityScheduler` per
//  source, re-created when its interval changes; the wake wait is the path
//  monitor's next "satisfied" callback raced against a 60 s timeout task; the
//  CalDAV fetch runs off the main actor (`CalDAVScheduleSource` + the
//  `CalDAVSession` actor) and only the planner's diff is applied on the main
//  actor, in one `ModelContext.save()`.
//

import Foundation
import Network
import Observation
import SwiftData
import AppKit
import Synchronization

// MARK: - Seams (fakes in tests)

/// A repeating background activity for one source.
@MainActor
protocol SyncScheduling: AnyObject {
    func schedule(id: String, interval: TimeInterval, tolerance: TimeInterval, fire: @escaping @MainActor () -> Void)
    func invalidate(id: String)
}

/// Whether the network path is satisfied, and its changes.
@MainActor
protocol PathMonitoring: AnyObject {
    var isSatisfied: Bool { get }
    var onChange: ((Bool) -> Void)? { get set }
}

/// `NSBackgroundActivityScheduler`, one per source (§13.3's table).
@MainActor
final class BackgroundActivityScheduling: SyncScheduling {
    private var schedulers: [String: NSBackgroundActivityScheduler] = [:]

    func schedule(id: String, interval: TimeInterval, tolerance: TimeInterval, fire: @escaping @MainActor () -> Void) {
        invalidate(id: id)
        let scheduler = NSBackgroundActivityScheduler(identifier: "XIX.Kadence.sync.\(id)")
        scheduler.repeats = true
        scheduler.interval = interval
        scheduler.tolerance = tolerance
        scheduler.qualityOfService = .utility
        // Swift note: the block runs on a background queue; `Task { @MainActor
        // in … }` hops back to the main actor, where the coordinator lives.
        scheduler.schedule { completion in
            Task { @MainActor in fire() }
            completion(.finished)
        }
        schedulers[id] = scheduler
    }

    func invalidate(id: String) {
        schedulers.removeValue(forKey: id)?.invalidate()
    }
}

/// `NWPathMonitor` on the main queue.
@MainActor
final class NetworkPathMonitoring: PathMonitoring {
    private let monitor = NWPathMonitor()
    private(set) var isSatisfied = true
    var onChange: ((Bool) -> Void)?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let satisfied = path.status == .satisfied
            Task { @MainActor in
                guard let self, self.isSatisfied != satisfied else { return }
                self.isSatisfied = satisfied
                self.onChange?(satisfied)
            }
        }
        monitor.start(queue: .main)
    }
}

// MARK: - The coordinator

@MainActor
@Observable
final class SyncCoordinator {
    enum Trigger: Equatable, Sendable { case interval, launch, wake, networkRegained, syncNow }

    /// §13.3: 30 s per request (in the transport), 120 s per sync, 600 s in
    /// `get` mode. Injectable for tests.
    struct Limits: Sendable {
        var sync: TimeInterval = 120
        var syncGetMode: TimeInterval = 600
        var wakeWait: TimeInterval = 60
        /// §20.8.2: automatic polls in `get` mode at most every 6 hours.
        var getModeFloor: TimeInterval = 6 * 3600
    }

    @ObservationIgnored let context: ModelContext
    @ObservationIgnored let secrets: any SecretStore
    @ObservationIgnored let scheduling: any SyncScheduling
    @ObservationIgnored let path: any PathMonitoring
    @ObservationIgnored let clock: () -> Date
    @ObservationIgnored let zone: () -> TimeZone
    @ObservationIgnored let limits: Limits
    /// Builds the fetcher for a source (the CalDAV one in the app; a mock in
    /// review mode and tests).
    @ObservationIgnored let makeSource: (CalDAVAccount) -> any ScheduleSource
    @ObservationIgnored weak var calendarState: CalendarState?
    @ObservationIgnored weak var undo: UndoStack?

    /// Source ids with a sync in flight (the sidebar's spinner, §19.2).
    private(set) var syncing: Set<String> = []
    /// When each running sync started (the 0.5 s spinner rule).
    private(set) var syncStartedAt: [String: Date] = [:]
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var scheduledIntervals: [String: TimeInterval] = [:]
    @ObservationIgnored private var lastAutomaticAttempt: [String: Date] = [:]
    @ObservationIgnored private var wakeTask: Task<Void, Never>?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    /// Tests count fetches through this.
    @ObservationIgnored private(set) var fetchCount = 0

    init(context: ModelContext, secrets: any SecretStore, scheduling: any SyncScheduling, path: any PathMonitoring,
         clock: @escaping () -> Date = { Date() }, zone: @escaping () -> TimeZone = { .current },
         limits: Limits = Limits(), makeSource: @escaping (CalDAVAccount) -> any ScheduleSource) {
        self.context = context
        self.secrets = secrets
        self.scheduling = scheduling
        self.path = path
        self.clock = clock
        self.zone = zone
        self.limits = limits
        self.makeSource = makeSource
        path.onChange = { [weak self] satisfied in
            if satisfied { self?.networkRegained() }
        }
    }

    /// The app's coordinator: `URLSessionTransport`, the Keychain,
    /// `NSBackgroundActivityScheduler`, `NWPathMonitor`, wake and sleep.
    static func live(context: ModelContext, secrets: any SecretStore = KeychainSecretStore(),
                     makeTransport: @escaping @Sendable () -> any HTTPTransport = { URLSessionTransport() })
        -> SyncCoordinator {
        let coordinator = SyncCoordinator(
            context: context, secrets: secrets, scheduling: BackgroundActivityScheduling(),
            path: NetworkPathMonitoring()) { account in
                CalDAVScheduleSource(account: account, secrets: secrets, makeTransport: makeTransport)
            }
        coordinator.observeWorkspace()
        return coordinator
    }

    private func observeWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.didWake() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.willSleep() }
        })
    }

    // MARK: Sources

    var connectedSources: [Source] {
        ((try? context.fetch(FetchDescriptor<Source>())) ?? []).filter(\.isConnected)
    }

    /// interactions.md §2: View ▸ Sync Now is disabled while every source is
    /// already syncing (and so with none connected).
    var isSyncNowDisabled: Bool {
        let ids = connectedSources.map(\.id)
        return ids.allSatisfy { syncing.contains($0) }
    }

    func isSyncing(_ source: Source) -> Bool { syncing.contains(source.id) }

    /// The interval automatic polls use: `max(interval, 6 h)` in `get` mode.
    func effectiveInterval(_ source: Source) -> TimeInterval {
        let interval = TimeInterval(source.pollInterval)
        return source.capabilities.fetchMode == .get ? max(interval, limits.getModeFloor) : interval
    }

    /// (Re)creates every connected source's scheduler; drops removed ones.
    func refreshSchedules() {
        let sources = connectedSources
        let ids = Set(sources.map(\.id))
        for id in scheduledIntervals.keys where !ids.contains(id) {
            scheduling.invalidate(id: id)
            scheduledIntervals.removeValue(forKey: id)
        }
        for source in sources {
            let interval = effectiveInterval(source)
            guard scheduledIntervals[source.id] != interval else { continue }
            let id = source.id
            // Re-created, not adjusted, when the interval changes (§13.3).
            if scheduledIntervals[id] != nil { scheduling.invalidate(id: id) }
            scheduling.schedule(id: id, interval: interval, tolerance: interval * 0.1) { [weak self] in
                self?.trigger(.interval, sourceID: id)
            }
            scheduledIntervals[id] = interval
        }
    }

    // MARK: Triggers

    /// At launch, after the store loads: sync sources whose last attempt is
    /// older than the interval, or that never tried.
    func launched() {
        refreshSchedules()
        for source in connectedSources { trigger(.launch, sourceID: source.id) }
    }

    func didWake() {
        wakeTask?.cancel()
        if path.isSatisfied {
            for source in connectedSources { trigger(.wake, sourceID: source.id) }
            return
        }
        // Wait for the path, up to `wakeWait`, then give up quietly.
        let wait = limits.wakeWait
        wakeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(wait))
            self?.wakeTask = nil
        }
        pendingWake = true
    }

    @ObservationIgnored private var pendingWake = false

    func networkRegained() {
        let afterWake = pendingWake && wakeTask != nil
        pendingWake = false
        wakeTask?.cancel()
        wakeTask = nil
        for source in connectedSources { trigger(afterWake ? .wake : .networkRegained, sourceID: source.id) }
    }

    func willSleep() {
        for (_, task) in tasks { task.cancel() }
    }

    /// Sync Now for every connected source (⌘R, the popover, Settings).
    /// Tests: returns once no sync is running.
    func waitUntilIdle() async {
        while let task = tasks.values.first { await task.value }
    }

    func syncNowAll() {
        for source in connectedSources { trigger(.syncNow, sourceID: source.id) }
    }

    /// Cancels a source's sync and its scheduler (removal, §13.2).
    func sourceRemoved(_ id: String) {
        tasks[id]?.cancel()
        scheduling.invalidate(id: id)
        scheduledIntervals.removeValue(forKey: id)
    }

    /// Decides whether `trigger` starts a sync of `sourceID` now.
    func trigger(_ trigger: Trigger, sourceID: String) {
        guard let source = connectedSources.first(where: { $0.id == sourceID }) else { return }
        // One sync per source at a time: a trigger during one is dropped.
        guard !syncing.contains(sourceID) else { return }
        let now = clock()
        if trigger != .syncNow {
            guard !source.isAutoSyncPaused else { return }
            let interval = effectiveInterval(source)
            let last = source.lastAttemptAt
            let stale = last.map { now.timeIntervalSince($0) >= interval } ?? true
            switch trigger {
            case .launch, .wake:
                guard stale else { return }
            case .networkRegained:
                guard stale || source.state == .unreachable || source.state == .offline else { return }
            case .interval:
                // `get` mode: polls at least `getModeFloor` apart.
                if source.capabilities.fetchMode == .get, let last, now.timeIntervalSince(last) < limits.getModeFloor {
                    return
                }
            case .syncNow:
                break
            }
        }
        // Offline is a state, not an error: no attempt (§13.3).
        guard path.isSatisfied else {
            source.state = .offline
            try? context.save()
            return
        }
        start(source, trigger: trigger)
    }

    private func start(_ source: Source, trigger: Trigger) {
        let id = source.id
        guard let server = ServerAddress(stored: source.serverURL), let username = source.username else {
            SyncApplier.recordFailure(.passwordMissing, to: source, context: context, now: clock())
            return
        }
        let account = CalDAVAccount(server: server, username: username, calendars: source.calendars,
                                    capabilities: source.capabilities)
        let fetcher = makeSource(account)
        let now = clock()
        let zone = zone()
        let limit = source.capabilities.fetchMode == .get ? limits.syncGetMode : limits.sync
        let windowStart = source.importedAt == nil ? Windows.importStart(now: now, zone: zone)
                                                   : Windows.syncStart(now: now, zone: zone)
        syncing.insert(id)
        syncStartedAt[id] = now
        fetchCount += 1
        tasks[id] = Task { [weak self] in
            let result = await Self.fetch(fetcher, windowStart: windowStart, limit: limit)
            guard let self else { return }
            self.finish(sourceID: id, result: result, trigger: trigger, now: now, zone: zone)
        }
    }

    /// The fetch, abandoned after `limit` seconds as `unreachable`.
    ///
    /// Swift note: not a task group — a group waits for every child before it
    /// returns, so a fetch stuck past the limit would hold it. Two
    /// unstructured tasks race instead, and the first to finish resumes the
    /// continuation (the `Mutex` makes "first" exact); the loser is cancelled.
    nonisolated private static func fetch(_ source: any ScheduleSource, windowStart: Date,
                                          limit: TimeInterval) async -> Result<ScheduleFetchResult, ScheduleSourceError> {
        let slot = Mutex<CheckedContinuation<Result<ScheduleFetchResult, ScheduleSourceError>, Never>?>(nil)
        let work = Mutex<Task<Void, Never>?>(nil)
        let timer = Mutex<Task<Void, Never>?>(nil)
        @Sendable func finish(_ result: Result<ScheduleFetchResult, ScheduleSourceError>) {
            if let continuation = slot.withLock({ c -> CheckedContinuation<Result<ScheduleFetchResult, ScheduleSourceError>, Never>? in
                defer { c = nil }
                return c
            }) {
                continuation.resume(returning: result)
                work.withLock { $0?.cancel() }
                timer.withLock { $0?.cancel() }
            }
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                slot.withLock { $0 = continuation }
                work.withLock { $0 = Task {
                    do { finish(.success(try await source.fetch(windowStart: windowStart))) }
                    catch { finish(.failure((error as? ScheduleSourceError) ?? .unreachable)) }
                } }
                timer.withLock { $0 = Task {
                    try? await Task.sleep(for: .seconds(limit))
                    if !Task.isCancelled { finish(.failure(.unreachable)) }
                } }
            }
        } onCancel: {
            finish(.failure(.cancelled))
        }
    }

    private func finish(sourceID id: String, result: Result<ScheduleFetchResult, ScheduleSourceError>,
                        trigger: Trigger, now: Date, zone: TimeZone) {
        let cancelled = tasks[id]?.isCancelled ?? true
        tasks.removeValue(forKey: id)
        syncing.remove(id)
        syncStartedAt.removeValue(forKey: id)
        // Sleep, quit, removal: nothing partial is written (§13.3).
        guard !cancelled, let source = connectedSources.first(where: { $0.id == id }) else { return }
        switch result {
        case .failure(.cancelled):
            return
        case .failure(let error):
            SyncApplier.recordFailure(error, to: source, context: context, now: now)
            SourceLogger.shared.state(source, state: error.state)
        case .success(let fetched):
            let write = { [weak self] in
                guard let self else { return }
                let kind: SyncKind = source.importedAt == nil ? .import : .sync
                let plan = SyncPlanner.plan(
                    existing: SyncApplier.snapshot(of: source, in: self.context, zone: zone),
                    source: SourceSnapshot(feedHash: source.feedHash, lastFeedEventCount: source.lastFeedEventCount,
                                           calendars: source.calendars, importedAt: source.importedAt),
                    result: fetched, kind: kind, now: now, zone: zone)
                guard let outcome = try? SyncApplier.apply(plan, to: source, context: self.context, now: now) else { return }
                SyncApplier.finish(outcome, state: self.calendarState, undo: self.undo)
                if trigger == .syncNow, plan.state.kind != .actionable || plan.state == .partialImport {
                    source.isAutoSyncPaused = false
                    try? self.context.save()
                }
                SourceLogger.shared.sync(source, diagnostics: fetched.diagnostics,
                                         outcome: plan.feedUnchanged ? "feed unchanged"
                                             : (plan.writesEvents ? "wrote" : "nothing to write"))
                if source.capabilities.fetchMode == .get { self.refreshSchedules() }
            }
            if let state = calendarState { state.applyOrHoldSyncWrite(write) } else { write() }
        }
    }

    /// The connect sheet's `Import` and edit mode's `Save`: they write the
    /// data the sheet already fetched — no transport call (§13.3).
    @discardableResult
    func applyFetched(_ result: ScheduleFetchResult, to source: Source, kind: SyncKind) throws -> SyncPlan {
        let now = clock()
        let zone = zone()
        let plan = SyncPlanner.plan(
            existing: SyncApplier.snapshot(of: source, in: context, zone: zone),
            source: SourceSnapshot(feedHash: source.feedHash, lastFeedEventCount: source.lastFeedEventCount,
                                   calendars: source.calendars, importedAt: source.importedAt),
            result: result, kind: kind, now: now, zone: zone)
        var thrown: Error?
        let write = { [weak self] in
            guard let self else { return }
            do {
                let outcome = try SyncApplier.apply(plan, to: source, context: self.context, now: now)
                SyncApplier.finish(outcome, state: self.calendarState, undo: self.undo)
            } catch { thrown = error }
        }
        if let state = calendarState { state.applyOrHoldSyncWrite(write) } else { write() }
        if let thrown { throw thrown }
        refreshSchedules()
        return plan
    }
}
