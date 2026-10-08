//
//  SyncCoordinatorTests.swift
//  KadenceTests
//
//  PHASE3-PLAN.md task 9: triggers, one sync at a time, the 401/403 pause,
//  offline, the `get`-mode floor, cancellation (interactions.md §13.3;
//  components.md §19.1, §20.8.2; G-061). Scheduler, clock, path monitor and
//  wake are fakes.
//

import Testing
import Foundation
import SwiftData
import Synchronization
import SwiftUI
@testable import Kadence

@MainActor
final class FakeScheduling: SyncScheduling {
    struct Entry: Equatable { var id: String; var interval: TimeInterval; var tolerance: TimeInterval }
    var entries: [Entry] = []
    var invalidated: [String] = []
    var fires: [String: @MainActor () -> Void] = [:]

    func schedule(id: String, interval: TimeInterval, tolerance: TimeInterval, fire: @escaping @MainActor () -> Void) {
        entries.append(Entry(id: id, interval: interval, tolerance: tolerance))
        fires[id] = fire
    }
    func invalidate(id: String) { invalidated.append(id); fires.removeValue(forKey: id) }
    func fire(_ id: String) { fires[id]?() }
}

@MainActor
final class FakePath: PathMonitoring {
    var isSatisfied = true
    var onChange: ((Bool) -> Void)?
    func set(_ satisfied: Bool) {
        let changed = satisfied != isSatisfied
        isSatisfied = satisfied
        if changed { onChange?(satisfied) }
    }
}

/// A fetcher that counts calls and can be held until the test releases it.
final class GatedSource: ScheduleSource, @unchecked Sendable {
    private let state = Mutex<(calls: Int, held: Bool, waiters: [CheckedContinuation<Void, Never>])>((0, false, []))
    let result: Result<ScheduleFetchResult, ScheduleSourceError>

    init(_ result: Result<ScheduleFetchResult, ScheduleSourceError>, held: Bool = false) {
        self.result = result
        state.withLock { $0.held = held }
    }

    var calls: Int { state.withLock { $0.calls } }

    func release() {
        let waiters = state.withLock { s -> [CheckedContinuation<Void, Never>] in
            s.held = false
            defer { s.waiters = [] }
            return s.waiters
        }
        waiters.forEach { $0.resume() }
    }

    func fetch(windowStart: Date) async throws(ScheduleSourceError) -> ScheduleFetchResult {
        let held = state.withLock { s -> Bool in s.calls += 1; return s.held }
        if held {
            await withCheckedContinuation { c in
                let stillHeld = state.withLock { s -> Bool in
                    if s.held { s.waiters.append(c) }
                    return s.held
                }
                if !stillHeld { c.resume() }
            }
        }
        return try result.get()
    }
}

private func ok() -> ScheduleFetchResult {
    ScheduleFetchResult(events: [], problems: [], objectCount: 0, mergedCount: 0,
                        calendarsReadInFully: [MockCalDAVServer.lvplan], failedCalendars: [], adoptedCalendars: [],
                        capabilities: SourceCapabilities(), diagnostics: SyncDiagnostics(), principalHref: nil,
                        calendarHomeHref: nil)
}

@MainActor
private final class ClockBox { var now = TestClock.now }

@MainActor
private final class Rig {
    let fixture: SyncFixture
    let scheduling = FakeScheduling()
    let path = FakePath()
    private let clock = ClockBox()
    var now: Date { get { clock.now } set { clock.now = newValue } }
    var source: GatedSource
    let coordinator: SyncCoordinator

    init(_ result: Result<ScheduleFetchResult, ScheduleSourceError> = .success(ok()), held: Bool = false,
         limits: SyncCoordinator.Limits = SyncCoordinator.Limits()) throws {
        fixture = try SyncFixture()
        fixture.source.importedAt = TestClock.date("2026-10-01 10:00")
        try fixture.context.save()
        let gated = GatedSource(result, held: held)
        source = gated
        let clock = clock
        coordinator = SyncCoordinator(context: fixture.context, secrets: InMemorySecretStore(), scheduling: scheduling,
                                      path: path, clock: { clock.now },
                                      zone: { TestClock.zone }, limits: limits) { _ in gated }
    }

    var record: Source { fixture.source }
}

@MainActor
@Suite(.serialized)
struct SyncCoordinatorTests {

    @Test("The default interval is 1800 s")
    func defaultInterval() throws {
        #expect(Source().pollInterval == 1800)
        let rig = try Rig()
        rig.coordinator.refreshSchedules()
        #expect(rig.scheduling.entries == [.init(id: "timetable", interval: 1800, tolerance: 180)])
    }

    @Test("Launch with a stale lastAttemptAt syncs; with a fresh one it doesn't")
    func launch() async throws {
        let rig = try Rig()
        rig.record.lastAttemptAt = TestClock.now.addingTimeInterval(-600)  // fresh
        rig.coordinator.launched()
        await rig.coordinator.waitUntilIdle()
        #expect(rig.source.calls == 0)
        rig.record.lastAttemptAt = TestClock.now.addingTimeInterval(-1801)  // stale
        rig.coordinator.launched()
        await rig.coordinator.waitUntilIdle()
        #expect(rig.source.calls == 1)
        #expect(rig.record.lastAttemptAt == TestClock.now && rig.record.state == .upToDate)
    }

    @Test("An interval change re-creates the scheduler with 10% tolerance")
    func intervalChange() throws {
        let rig = try Rig()
        rig.coordinator.refreshSchedules()
        rig.record.pollInterval = 3600
        rig.coordinator.refreshSchedules()
        #expect(rig.scheduling.entries.last == .init(id: "timetable", interval: 3600, tolerance: 360))
        #expect(rig.scheduling.invalidated.contains("timetable"))
    }

    @Test("A trigger during a running sync is dropped")
    func dropDuringRun() async throws {
        let rig = try Rig(held: true)
        rig.coordinator.trigger(.syncNow, sourceID: "timetable")
        #expect(rig.coordinator.isSyncing(rig.record))
        rig.coordinator.trigger(.syncNow, sourceID: "timetable")
        rig.coordinator.trigger(.interval, sourceID: "timetable")
        #expect(rig.coordinator.isSyncNowDisabled)  // every source is syncing
        rig.source.release()
        await rig.coordinator.waitUntilIdle()
        #expect(rig.source.calls == 1)
        #expect(!rig.coordinator.isSyncNowDisabled)
    }

    @Test("Pause: after unauthorized or forbidden no automatic trigger syncs; Sync Now does; a successful Sync Now clears it",
          arguments: [ScheduleSourceError.unauthorized, .forbidden])
    func pause(error: ScheduleSourceError) async throws {
        let rig = try Rig(.failure(error))
        rig.coordinator.trigger(.syncNow, sourceID: "timetable")
        await rig.coordinator.waitUntilIdle()
        #expect(rig.record.isAutoSyncPaused && rig.record.state == error.state)
        rig.now = rig.now.addingTimeInterval(7200)
        for trigger in [SyncCoordinator.Trigger.interval, .launch, .wake, .networkRegained] {
            rig.coordinator.trigger(trigger, sourceID: "timetable")
        }
        await rig.coordinator.waitUntilIdle()
        #expect(rig.source.calls == 1)
        // Sync Now still syncs; when it succeeds the pause is cleared.
        let fixed = GatedSource(.success(ok()))
        let coordinator = SyncCoordinator(context: rig.fixture.context, secrets: InMemorySecretStore(),
                                          scheduling: rig.scheduling, path: rig.path, clock: { TestClock.now },
                                          zone: { TestClock.zone }) { _ in fixed }
        coordinator.trigger(.interval, sourceID: "timetable")
        await coordinator.waitUntilIdle()
        #expect(fixed.calls == 0)
        coordinator.trigger(.syncNow, sourceID: "timetable")
        await coordinator.waitUntilIdle()
        #expect(fixed.calls == 1 && !rig.record.isAutoSyncPaused && rig.record.state == .upToDate)
    }

    @Test("These do not pause", arguments: [
        ScheduleSourceError.noCalDAV, .noCalendars, .certificate, .passwordMissing,
        .redirected(otherHost: "login.example.invalid"), .calendarMissing, .fetchFailed(technical: "x"), .notACalendar,
    ])
    func noPause(error: ScheduleSourceError) async throws {
        let perCalendar: Bool = { switch error { case .calendarMissing, .fetchFailed, .notACalendar: true; default: false } }()
        var result = ok()
        if perCalendar {
            result.failedCalendars = [(SourceCalendar(href: MockCalDAVServer.lvplan, displayName: "LVPlan"), error)]
            result.calendarsReadInFully = []
        }
        let rig = try Rig(perCalendar ? .success(result) : .failure(error))
        rig.coordinator.trigger(.syncNow, sourceID: "timetable")
        await rig.coordinator.waitUntilIdle()
        #expect(rig.record.state == error.state)
        #expect(!rig.record.isAutoSyncPaused)
    }

    @Test("passwordMissing makes no transport call")
    func passwordMissing() async throws {
        let rig = try Rig()
        let calls = Mutex(0)
        let real = SyncCoordinator(context: rig.fixture.context, secrets: InMemorySecretStore(), scheduling: rig.scheduling,
                                   path: rig.path, clock: { TestClock.now }, zone: { TestClock.zone }) { account in
            CalDAVScheduleSource(account: account, secrets: InMemorySecretStore()) {
                calls.withLock { $0 += 1 }
                return MockHarness(.reportOK).stub.transport()
            }
        }
        real.trigger(.syncNow, sourceID: "timetable")
        await real.waitUntilIdle()
        #expect(rig.record.state == .passwordMissing)
        #expect(calls.withLock { $0 } == 0)
    }

    @Test("Offline → the offline state and no transport call; network regained after unreachable syncs")
    func offlineAndRegained() async throws {
        let rig = try Rig(.failure(.unreachable))
        rig.path.isSatisfied = false
        rig.coordinator.trigger(.syncNow, sourceID: "timetable")
        await rig.coordinator.waitUntilIdle()
        #expect(rig.source.calls == 0 && rig.record.state == .offline)
        rig.path.set(true)  // network regained (last state offline)
        await rig.coordinator.waitUntilIdle()
        #expect(rig.source.calls == 1 && rig.record.state == .unreachable)
        rig.path.set(false)
        rig.path.set(true)  // regained after unreachable
        await rig.coordinator.waitUntilIdle()
        #expect(rig.source.calls == 2)
    }

    @Test("Wake waits for the path")
    func wakeWaits() async throws {
        let rig = try Rig()
        rig.record.lastAttemptAt = TestClock.now.addingTimeInterval(-3600)
        rig.path.isSatisfied = false
        rig.coordinator.didWake()
        await rig.coordinator.waitUntilIdle()
        #expect(rig.source.calls == 0)
        rig.path.set(true)
        await rig.coordinator.waitUntilIdle()
        #expect(rig.source.calls == 1)
    }

    @Test("get mode: automatic polls at least 6 h apart; Sync Now not limited")
    func getModeFloor() async throws {
        var getResult = ok()
        getResult.capabilities.fetchMode = .get
        let rig = try Rig(.success(getResult))
        var capabilities = rig.record.capabilities
        capabilities.fetchMode = .get
        rig.record.capabilities = capabilities
        #expect(rig.coordinator.effectiveInterval(rig.record) == 6 * 3600)
        rig.coordinator.refreshSchedules()
        #expect(rig.scheduling.entries.last.map(\.interval) == TimeInterval(6 * 3600))
        rig.record.lastAttemptAt = TestClock.now.addingTimeInterval(-2 * 3600)
        rig.scheduling.fire("timetable")
        await rig.coordinator.waitUntilIdle()
        #expect(rig.source.calls == 0)
        rig.coordinator.trigger(.syncNow, sourceID: "timetable")
        await rig.coordinator.waitUntilIdle()
        #expect(rig.source.calls == 1)
        rig.now = TestClock.now.addingTimeInterval(6 * 3600 + 1)
        rig.scheduling.fire("timetable")
        await rig.coordinator.waitUntilIdle()
        #expect(rig.source.calls == 2)
    }

    @Test("Import makes no transport call")
    func importNoCall() async throws {
        let rig = try Rig()
        rig.record.importedAt = nil
        let feed = try await rig.fixture.fetch(MockHarness(.reportOK), start: Windows.importStart(now: TestClock.now, zone: TestClock.zone),
                                               now: TestClock.now)
        try rig.coordinator.applyFetched(feed, to: rig.record, kind: .import)
        #expect(rig.source.calls == 0 && rig.coordinator.fetchCount == 0)
        #expect(rig.fixture.events.count == 12 && rig.record.importedAt == TestClock.now)
    }

    @Test("Sleep cancels a sync mid-chain; nothing is written")
    func sleepCancels() async throws {
        var result = ok()
        result.events = [ExternalEvent(externalID: "x", title: "X", start: TestClock.now + 86_400, end: TestClock.now + 90_000,
                                       isAllDay: false, location: nil, isOnline: false, courseCode: nil, group: nil,
                                       lecturers: [], kind: .lecture, description: nil, link: nil, isCancelled: false,
                                       sequence: 0, stamp: nil)]
        let rig = try Rig(.success(result), held: true)
        rig.coordinator.trigger(.syncNow, sourceID: "timetable")
        rig.coordinator.willSleep()
        rig.source.release()
        await rig.coordinator.waitUntilIdle()
        #expect(rig.fixture.events.isEmpty)
        #expect(rig.record.lastAttemptAt == nil)
    }

    @Test("A sync longer than the limit is abandoned as unreachable")
    func syncTimeout() async throws {
        let rig = try Rig(held: true, limits: SyncCoordinator.Limits(sync: 0.2, syncGetMode: 0.2, wakeWait: 0.2))
        rig.coordinator.trigger(.syncNow, sourceID: "timetable")
        await rig.coordinator.waitUntilIdle()
        #expect(rig.record.state == .unreachable)
        rig.source.release()
    }

    @Test("Menu: View ▸ Sync Now ⌘R")
    func menu() {
        #expect(KadenceCommands.syncNowTitle == "Sync Now")
        #expect(KadenceCommands.syncNowKey == "r")
    }
}
