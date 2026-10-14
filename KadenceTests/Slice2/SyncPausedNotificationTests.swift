//
//  SyncPausedNotificationTests.swift
//  KadenceTests
//
//  PHASE3-SLICE2-PLAN.md task 11 — components.md §27.1 (`syncPaused`),
//  §27.4 N8 and its rules, §27.6; §19.1; §30.1 "Sync paused". The source's
//  syncs go through the real CalDAV client to `MockCalDAVTransport` (cases
//  `unauthorized`, `forbidden`, `reportOK`) — no network — and the recording
//  centre.
//

import Testing
import Foundation
import SwiftData
import Synchronization
@testable import Kadence

/// The mocked server a sync talks to, switchable between syncs.
nonisolated final class ServerBox: Sendable {
    private let current: Mutex<MockCalDAVServer>
    init(_ server: MockCalDAVServer) { current = Mutex(server) }
    var server: MockCalDAVServer { current.withLock { $0 } }
    func set(_ server: MockCalDAVServer) { current.withLock { $0 = server } }
}

@MainActor
final class SyncPausedRig {
    let rig: NotificationRig
    let box: ServerBox
    let scheduling = FakeScheduling()
    let sync: SyncCoordinator
    var frontmost = false

    init(now: Date, case mockCase: MockCalDAVServer.Case) throws {
        rig = try NotificationRig(now: now)
        let box = ServerBox(Self.server(mockCase, now: now))
        self.box = box
        let clock = rig.travel.clock
        sync = SyncCoordinator(context: rig.travel.context, secrets: ReviewMode.secrets, scheduling: scheduling,
                               path: ScriptedPathMonitoring(), clock: { clock.now }, zone: { TravelFixtures.zone },
                               makeTransport: { MockCalDAVTransport(server: box.server) }) { account in
            CalDAVScheduleSource(account: account, secrets: ReviewMode.secrets,
                                 makeTransport: { MockCalDAVTransport(server: box.server) })
        }
        let scheduler = rig.scheduler
        sync.onStateEvent = { scheduler.sourceStateChanged($0) }
        sync.isFrontmost = { [unowned self] in self.frontmost }
    }

    static func server(_ mockCase: MockCalDAVServer.Case, now: Date) -> MockCalDAVServer {
        ReviewMode.server(case: mockCase, now: now, zone: TravelFixtures.zone)
    }

    var sourceID: String { TravelDataset.sourceID }
    var identifier: String { "sync.\(sourceID)" }

    func source() throws -> Source {
        try require(try rig.travel.context.fetch(FetchDescriptor<Source>()).first { $0.id == sourceID })
    }

    /// One sync of the timetable, as `trigger` starts it, then the passes.
    func sync(_ trigger: SyncCoordinator.Trigger) async {
        sync.trigger(trigger, sourceID: sourceID)
        await sync.waitUntilIdle()
        await rig.run(for: 5)
    }
}

@MainActor
@Suite(.serialized)
struct SyncPausedNotificationTests {
    let thu1000 = TravelFixtures.m(3, "10:00")

    @Test("§30.1 Sync paused: unauthorized and forbidden — both bodies exact, kadence.source, .active, at once")
    func bodies() async throws {
        for (mockCase, body) in [
            (MockCalDAVServer.Case.unauthorized,
             "cis.technikum-wien.at didn't accept the password for user01. Sync is paused until you update it in Kadence."),
            (.forbidden,
             "cis.technikum-wien.at refused access for user01. Sync is paused until you check the account in Kadence."),
        ] {
            let s = try SyncPausedRig(now: thu1000, case: mockCase)
            await s.sync(.interval)
            #expect(try s.source().state == (mockCase == .unauthorized ? .unauthorized : .forbidden))
            let request = try require(await s.rig.pending()[s.identifier])
            #expect(request.title == "University timetable isn't syncing")
            #expect(request.body == body)
            #expect(request.category == .source && request.interruption == .active && request.playsSound)
            #expect(request.atOnce)
            // Never the password or an Authorization value.
            for text in [request.title, request.body] {
                #expect(!text.contains("review-only-not-a-password") && !text.contains("S3ntinel"))
                #expect(!text.contains("Basic ") && !text.contains("Authorization"))
            }
        }
    }

    @Test("A sync at 03:00, inside Sleep → held to 07:00")
    func held() async throws {
        let s = try SyncPausedRig(now: TravelFixtures.m(3, "03:00"), case: .unauthorized)
        await s.sync(.interval)
        let request = try require(await s.rig.pending()[s.identifier])
        #expect(request.fireAt == TravelFixtures.m(3, "07:00") && !request.atOnce)
    }

    @Test("A second paused sync adds nothing; recovery (reportOK after Update Password…) removes it, pending and delivered")
    func secondAndRecovery() async throws {
        let s = try SyncPausedRig(now: thu1000, case: .unauthorized)
        await s.sync(.interval)
        #expect(await s.rig.pending()[s.identifier] != nil)
        await s.rig.centre.resetCounters()
        // Automatic syncs are paused after a 401; even when one runs again
        // and is refused again, no new N8.
        try s.source().isAutoSyncPaused = false
        await s.sync(.interval)
        #expect(await s.rig.centre.addCalls.filter { $0.identifier == s.identifier }.isEmpty)
        // It was delivered; then the password is fixed and Sync Now succeeds.
        await s.rig.centre.deliver(s.identifier)
        s.box.set(SyncPausedRig.server(.reportOK, now: thu1000))
        await s.sync(.syncNow)
        for _ in 0..<5 { await Task.yield() }
        #expect(try s.source().state == .upToDate)
        #expect(await s.rig.pending()[s.identifier] == nil)
        #expect(await s.rig.centre.deliveredList.isEmpty)
        #expect(await s.rig.centre.removeCalls.contains(s.identifier))
        #expect(await s.rig.centre.removeDeliveredCalls.contains(s.identifier))
        #expect(s.rig.scheduler.syncAlerts.isEmpty)
    }

    @Test("Sync Now, or any sync while Kadence is frontmost, reaching unauthorized sends nothing; so does the Import path")
    func userLooking() async throws {
        let now = try SyncPausedRig(now: thu1000, case: .unauthorized)
        await now.sync(.syncNow)
        #expect(try now.source().state == .unauthorized)
        #expect(await now.rig.pending()[now.identifier] == nil)

        let front = try SyncPausedRig(now: thu1000, case: .unauthorized)
        front.frontmost = true
        await front.sync(.interval)
        #expect(await front.rig.pending()[front.identifier] == nil)

        // The connect sheet's Import / edit mode's Save report as the user's.
        let sheet = try SyncPausedRig(now: thu1000, case: .reportOK)
        var reported: [SyncCoordinator.StateEvent] = []
        sheet.sync.onStateEvent = { reported.append($0); sheet.rig.scheduler.sourceStateChanged($0) }
        let source = try sheet.source()
        source.state = .unauthorized
        let result = ReviewMode.fetchResult(of: ReviewFeed.reportTravel(template: ReviewTravelTemplate.text,
                                                                        today: thu1000, m: TravelRig.m,
                                                                        zone: TravelFixtures.zone),
                                            now: thu1000, zone: TravelFixtures.zone)
        _ = try sheet.sync.applyFetched(result, to: source, kind: .editSave(deselected: false))
        guard case .transition(_, _, _, let userStarted, _) = try require(reported.first) else {
            Issue.record("no transition"); return
        }
        #expect(userStarted)
    }

    @Test("Sync problems off → nothing; on again while still paused → nothing new")
    func ruleOff() async throws {
        let s = try SyncPausedRig(now: thu1000, case: .unauthorized)
        let rule = try require(try s.rig.travel.context.fetch(FetchDescriptor<NotificationRule>()).first { $0.kind == .syncPaused })
        rule.isEnabled = false
        try s.rig.travel.context.save()
        await s.sync(.interval)
        #expect(await s.rig.pending()[s.identifier] == nil)
        rule.isEnabled = true
        try s.rig.travel.context.save()
        await s.rig.scheduler.pass()
        #expect(await s.rig.pending()[s.identifier] == nil)
    }

    @Test("Removing the source removes its sync. notification")
    func removal() async throws {
        let s = try SyncPausedRig(now: thu1000, case: .unauthorized)
        await s.sync(.interval)
        #expect(await s.rig.pending()[s.identifier] != nil)
        s.sync.sourceRemoved(s.sourceID)
        for _ in 0..<5 { await Task.yield() }
        #expect(await s.rig.pending()[s.identifier] == nil)
        #expect(s.rig.scheduler.syncAlerts.isEmpty)
    }

    @Test("Once delivered, an N8 is not planned again")
    func notRepeated() async throws {
        let s = try SyncPausedRig(now: thu1000, case: .unauthorized)
        await s.sync(.interval)
        await s.rig.centre.deliver(s.identifier)
        await s.rig.centre.resetCounters()
        await s.rig.run(for: 3600 + 5)
        await s.rig.scheduler.pass()
        #expect(await s.rig.centre.addCalls.filter { $0.identifier == s.identifier }.isEmpty)
        #expect(await s.rig.centre.removeDeliveredCalls.isEmpty)
    }
}
