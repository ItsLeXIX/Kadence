//
//  NotificationSchedulerTests.swift
//  KadenceTests
//
//  PHASE3-SLICE2-PLAN.md task 9 — components.md §27.6, §27.8, §27.10,
//  §27.4 (levels and the degrade rule). The recording centre and the
//  injected clock; dataset `travel` in an in-memory store. No prompt, no
//  real notification: `SystemNotificationCenter` is never built here.
//

import Testing
import Foundation
import SwiftData
import UserNotifications
@testable import Kadence

@MainActor
final class NotificationRig {
    let travel: TravelRig
    let centre: RecordingNotificationCenter
    let log = RoutingLog(category: "notifications")
    let scheduler: NotificationScheduler

    init(now: Date, centre: RecordingNotificationCenter = RecordingNotificationCenter(), variant: TravelDataset.Variant? = nil,
         provider: MockTravelTimeProvider? = nil) throws {
        travel = try TravelRig(now: now, variant: variant, provider: provider)
        self.centre = centre
        scheduler = NotificationScheduler(context: travel.context, centre: centre, clock: travel.clock,
                                          calendar: TravelFixtures.calendar, log: log)
        let scheduler = scheduler
        travel.coordinator.onPassCompleted = { kind in scheduler.requestPass(catchUp: kind != .ordinary) }
        scheduler.consumeRefreshed = { [weak coordinator = travel.coordinator] in coordinator?.consumeRefreshed() ?? [] }
        // As the app does: event, place and settings saves trigger a recompute.
        travel.coordinator.startObserving()
        travel.extraSettle = { [weak scheduler] in
            await scheduler?.settle()
            await scheduler?.settle()
        }
    }

    /// Launch the legs and let every pass (legs, then notifications) run.
    func launch() async {
        await travel.launchAndSettle()
        await settle()
    }

    func run(for seconds: TimeInterval) async {
        await travel.run(for: seconds)
        await settle()
    }

    func settle() async {
        await scheduler.settle()
        // A pass that coalesced another runs it after the first.
        await scheduler.settle()
    }

    func pending() async -> [String: ScheduledRequest] { await centre.pendingByID }
    func id(_ prefix: String, _ title: String, day: Int) -> String {
        "\(prefix).\(travel.event(title, day: day)!.id.uuidString)"
    }
}

@MainActor
@Suite(.serialized)
struct NotificationSchedulerTests {
    let thu0600 = TravelFixtures.m(3, "06:00")

    @Test("Two passes over the same inputs: the second performs no add and no remove")
    func idempotent() async throws {
        let rig = try NotificationRig(now: thu0600)
        await rig.launch()
        #expect(await rig.pending().count == 4)
        await rig.centre.resetCounters()
        await rig.scheduler.pass()
        await rig.scheduler.pass()
        #expect(await rig.centre.addCalls.isEmpty)
        #expect(await rig.centre.removeCalls.isEmpty)
        // Records: one per scheduled identifier, with the fire date given.
        let records = try rig.travel.context.fetch(FetchDescriptor<NotificationRecord>())
        #expect(records.count == 4)
        let epc = rig.id("leave", "EPC-ILV", day: 3)
        #expect(records.first { $0.identifier == epc }?.fireAt == TravelFixtures.m(3, "12:10"))
    }

    @Test("Move → the same identifier replaced, never duplicated; Done → removed; Delete → removed and delivered cleared")
    func moveDoneDelete() async throws {
        let rig = try NotificationRig(now: thu0600)
        await rig.launch()
        let dinner = try require(rig.travel.event("Dinner with flatmates", day: 3))
        let leaveDinner = "leave.\(dinner.id.uuidString)"
        rig.travel.store.move(dinner, by: 30 * 60)
        rig.travel.coordinator.recompute()
        await rig.run(for: 60)
        var pending = await rig.pending()
        #expect(pending[leaveDinner]?.fireAt == TravelFixtures.m(3, "18:10"))
        #expect(pending.keys.filter { $0 == leaveDinner }.count == 1)
        #expect(await rig.centre.removeCalls.contains(leaveDinner))

        rig.travel.store.toggleDone(dinner)
        rig.travel.coordinator.recompute()
        await rig.run(for: 10)
        pending = await rig.pending()
        #expect(pending[leaveDinner] == nil)

        // Undo the Done, let it be delivered, then delete the event.
        rig.travel.undo.undo()
        rig.travel.coordinator.recompute()
        await rig.run(for: 10)
        #expect(await rig.pending()[leaveDinner] != nil)
        await rig.centre.deliver(leaveDinner)
        rig.travel.store.delete(try require(rig.travel.event("Dinner with flatmates", day: 3)))
        rig.travel.coordinator.recompute()
        await rig.run(for: 10)
        #expect(await rig.pending()[leaveDinner] == nil)
        #expect(await rig.centre.removeDeliveredCalls.contains(leaveDinner))
        #expect(await rig.centre.deliveredList.isEmpty)
    }

    @Test("A leg pending → ready: N7 is replaced by N1 under leave.")
    func pendingToReady() async throws {
        let provider = TravelServices.defaultMockProvider()
        await provider.hold()
        let rig = try NotificationRig(now: thu0600, provider: provider)
        rig.travel.coordinator.launched()
        // The provider is held: drive the clock past the debounce only (the
        // queue's request stays in flight).
        rig.travel.clock.advance(by: 2)
        await rig.settle()
        let epc = rig.id("leave", "EPC-ILV", day: 3)
        #expect(await rig.pending()[epc]?.title == "EPC-ILV starts at 13:00")
        #expect(await rig.pending()[epc]?.interruption == .timeSensitive)
        await provider.release()
        await rig.run(for: 120)
        let pending = await rig.pending()
        #expect(pending[epc]?.title == "Leave by 12:15 for EPC-ILV")
        #expect(pending.keys.filter { $0.hasSuffix(epc.dropFirst(6)) }.count == 1)
    }

    @Test("`off` → nothing added or removed; switching to `allowed` → the plan added as an ordinary pass")
    func offThenAllowed() async throws {
        let centre = RecordingNotificationCenter(authorization: .off)
        await centre.seedForeign(ScheduledRequest(identifier: "leave.00000000-0000-0000-0000-000000000099",
                                                  fireAt: thu0600, atOnce: false, title: "x", body: "y",
                                                  category: .event, playsSound: true, interruption: .active,
                                                  subjectID: "x", contentHash: "z"))
        let rig = try NotificationRig(now: thu0600, centre: centre)
        await rig.launch()
        #expect(await centre.addCalls.isEmpty)
        #expect(await centre.removeCalls.isEmpty)
        #expect(rig.scheduler.permission == .off)
        #expect(rig.scheduler.lastPlan.count == 4)   // the planner still runs
        await centre.set(authorization: .allowed)
        await rig.scheduler.refreshPermission()
        #expect(rig.scheduler.permission == .allowed)
        await rig.run(for: 5)
        let adds = await centre.addCalls
        #expect(adds.count == 4 && adds.allSatisfy { !$0.atOnce })
    }

    @Test("First pass with a plan, notDetermined, never asked → exactly one request; a second pass → none; all rules off → none")
    func askOnce() async throws {
        let centre = RecordingNotificationCenter(authorization: .notDetermined)
        let rig = try NotificationRig(now: thu0600, centre: centre)
        await rig.launch()
        #expect(await centre.requestAuthorizationCalls == 1)
        let asked = try require(TravelBuiltIns.settings(in: rig.travel.context).notificationsRequestedAt)
        #expect(asked >= thu0600 && asked < thu0600.addingTimeInterval(120))
        #expect(rig.scheduler.permission == .notAllowedYet)
        await rig.scheduler.pass()
        #expect(await centre.requestAuthorizationCalls == 1)
        #expect(await centre.addCalls.isEmpty)

        let quiet = RecordingNotificationCenter(authorization: .notDetermined)
        let off = try NotificationRig(now: thu0600, centre: quiet)
        for rule in try off.travel.context.fetch(FetchDescriptor<NotificationRule>()) { rule.isEnabled = false }
        try off.travel.context.save()
        await off.launch()
        await off.scheduler.pass()
        #expect(await quiet.requestAuthorizationCalls == 0)
        #expect(off.scheduler.permission == .notAsked)
    }

    @Test("The hourly pass at Thu 06:00 + 1 h adds what entered the window")
    func hourly() async throws {
        let rig = try NotificationRig(now: thu0600)
        rig.scheduler.start()
        await rig.launch()
        let early = rig.id("leave", "Early study group", day: 5)
        #expect(await rig.pending()[early] == nil)
        await rig.run(for: 3600 + 5)
        let pending = await rig.pending()
        #expect(pending[early]?.fireAt == TravelFixtures.m(5, "07:00"))
        #expect(pending[early]?.title == "Leave now for Early study group")
    }

    @Test("A foreign identifier survives every pass")
    func foreign() async throws {
        let centre = RecordingNotificationCenter()
        let foreign = ScheduledRequest(identifier: "com.example.other", fireAt: thu0600, atOnce: false, title: "x",
                                       body: "y", category: .event, playsSound: true, interruption: .active,
                                       subjectID: "x", contentHash: "z")
        await centre.seedForeign(foreign)
        let rig = try NotificationRig(now: thu0600, centre: centre)
        await rig.launch()
        await rig.scheduler.pass(catchUp: true)
        for rule in try rig.travel.context.fetch(FetchDescriptor<NotificationRule>()) { rule.isEnabled = false }
        try rig.travel.context.save()
        await rig.scheduler.pass()
        let pending = await rig.pending()
        #expect(pending["com.example.other"] == foreign)
        #expect(pending.count == 1)
        #expect(await !centre.removeCalls.contains("com.example.other"))
    }

    @Test("A time-sensitive add rejected → added again once as .active, logged; nothing fails")
    func degrade() async throws {
        let centre = RecordingNotificationCenter(rejectsTimeSensitive: true)
        let rig = try NotificationRig(now: thu0600, centre: centre)
        await rig.launch()
        let pending = await rig.pending()
        #expect(pending.count == 4)
        #expect(pending.values.allSatisfy { $0.interruption == .active })
        // Every time-sensitive add was rejected and followed at once by the
        // same request as `.active`; each retry logged once.
        let adds = await centre.addCalls
        let rejected = adds.enumerated().filter { $0.element.interruption == .timeSensitive }
        #expect(!rejected.isEmpty)
        for (index, request) in rejected {
            #expect(adds.indices.contains(index + 1) && adds[index + 1].identifier == request.identifier
                    && adds[index + 1].interruption == .active)
        }
        #expect(rig.log.lines.count == rejected.count)
        #expect(rig.log.lines.allSatisfy { $0 == "notification degraded · time-sensitive unavailable" })
    }

    @Test("Categories at start: kadence.event Done · Snooze · Open; readOnly no Snooze; result none; source Open only")
    func categories() async throws {
        let rig = try NotificationRig(now: thu0600)
        rig.scheduler.start()
        await rig.run(for: 2)
        for _ in 0..<5 { await Task.yield() }
        let categories = await rig.centre.categories
        let byID = Dictionary(uniqueKeysWithValues: categories.map { ($0.identifier, $0.actions.map(\.title)) })
        #expect(byID["kadence.event"] == ["Done", "Snooze", "Open"])
        #expect(byID["kadence.readOnly"] == ["Done", "Open"])
        #expect(byID["kadence.result"] == [])
        #expect(byID["kadence.source"] == ["Open"])
        #expect(categories.flatMap(\.actions).filter { $0.foreground }.map(\.title).allSatisfy { $0 == "Open" })
    }

    @Test("Test-host and review launches never construct SystemNotificationCenter; only its file names the system centre")
    func factory() throws {
        ServiceLaunchLog.reset()
        for kind in [LaunchKind.testHost] + ReviewMode.Dataset.allCases.map(LaunchKind.review) {
            #expect(NotificationServices.make(for: kind) is RecordingNotificationCenter)
        }
        #expect(ServiceLaunchLog.constructed.allSatisfy { $0 == "RecordingNotificationCenter" })
        #expect(try SourceScan.files(containing: "UNUserNotificationCenter") == ["SystemNotificationCenter.swift"])
    }

    @Test("§27.8's mapping: authorized/provisional/ephemeral with alerts → allowed; style None or denied → off")
    func mapping() {
        #expect(SystemNotificationCenter.map(status: .authorized, alertSetting: .enabled, alertStyle: .banner) == .allowed)
        #expect(SystemNotificationCenter.map(status: .provisional, alertSetting: .enabled, alertStyle: .banner) == .allowed)
        #expect(SystemNotificationCenter.map(status: .authorized, alertSetting: .enabled, alertStyle: .none) == .off)
        #expect(SystemNotificationCenter.map(status: .denied, alertSetting: .disabled, alertStyle: .none) == .off)
        #expect(SystemNotificationCenter.map(status: .notDetermined, alertSetting: .notSupported, alertStyle: .none) == .notDetermined)
        #expect(NotificationPermission.of(.notDetermined, asked: true) == .notAllowedYet)
        #expect(NotificationPermission.of(.notDetermined, asked: false) == .notAsked)
    }
}
