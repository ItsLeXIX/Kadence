//
//  NotificationPlanDumpTests.swift
//  KadenceTests
//
//  PHASE3-SLICE2-PLAN.md task 12 (built) and 18 (captured) — components.md
//  §30 items 14 and 23: the notification plan as text, from the real
//  coordinator, scheduler and planner, at §30.1's pinned clocks — produced
//  like the offscreen renders (§17.2 rule 3). With `KADENCE_CAPTURE_DIR`
//  set, written to the test host's temporary `kadence-captures/` as
//  `notification-plan-travel-p3b.txt` (copied to `screenshots/3b/`).
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

@MainActor
@Suite(.serialized)
struct NotificationPlanDumpTests {
    typealias F = TravelFixtures

    func names(_ rig: TravelRig) -> [String: String] {
        var names = Dictionary(rig.events().map { ($0.id.uuidString, $0.title) }, uniquingKeysWith: { a, _ in a })
        names[TravelDataset.sourceID] = "source"
        return names
    }

    func section(_ title: String, _ plan: [PlannedNotification], _ rig: TravelRig) -> String {
        "== \(title)\n\n" + (plan.isEmpty ? "(nothing)\n" : NotificationPlanText.blocks(plan, names: names(rig), calendar: F.calendar))
    }

    func ordinary(_ rig: NotificationRig) -> [PlannedNotification] {
        rig.scheduler.makePlan(now: rig.travel.clock.now)
    }

    @Test("§30 items 14 and 23: the plan dump at §30.1's clocks equals the notification tables")
    func dump() async throws {
        var text = "# Notification plan — dataset travel (M = Mon 12 Oct 2026, Europe/Vienna)\n"
        text += "# Produced by NotificationPlanDumpTests from the real TravelCoordinator, NotificationScheduler and\n"
        text += "# NotificationPlanner, mock provider / geocoder / location, recording centre; clocks pinned.\n\n"

        // 1. Thu 06:00, ordinary.
        let thu = try NotificationRig(now: F.m(3, "06:00"))
        await thu.launch()
        let thuPlan = ordinary(thu)
        text += section("Thu 15 Oct 06:00, ordinary pass", thuPlan, thu.travel)
        #expect(thuPlan.map(\.text.title) == ["Leave by 12:15 for EPC-ILV", "REQEN-EXAM starts at 16:00",
                                              "Leave by 17:45 for Dinner with flatmates", "Leave by 15:15 for SWRM-ILV"])

        // 2. Fri 23:00, ordinary.
        let fri = try NotificationRig(now: F.m(4, "23:00"))
        await fri.launch()
        let friPlan = ordinary(fri)
        text += "\n" + section("Fri 16 Oct 23:00, ordinary pass", friPlan, fri.travel)
        #expect(friPlan.map(\.text.title) == ["Leave now for Early study group", "Late call starts at 23:15",
                                              "Leave by 17:45 for Climbing"])

        // 3. travelOffline at Thu 06:00, then recovery.
        let offline = try NotificationRig(now: F.m(3, "06:00"), variant: .travelOffline,
                                          provider: ReviewTravel.provider(dataset: .travel, variant: .travelOffline))
        await offline.launch()
        let offlinePlan = ordinary(offline)
        text += "\n" + section("Routing: travelOffline, Thu 06:00", offlinePlan, offline.travel)
        #expect(offlinePlan.map(\.text.title) == ["Leave by about 12:15 for EPC-ILV", "REQEN-EXAM starts at 16:00",
                                                  "Dinner with flatmates starts at 18:30", "Leave by about 15:15 for SWRM-ILV"])
        #expect(offlinePlan[2].text.body
                == "Home · Travel time from FH Technikum Wien unavailable: offline. Check your route before you leave.")
        await offline.travel.provider.answerEverything(nil)
        offline.travel.path.set(satisfied: false)
        offline.travel.path.set(satisfied: true)
        await offline.run(for: 120)
        let recovered = ordinary(offline)
        text += "\n" + section("Routing: travelOffline after the provider recovers (same identifiers, N1)", recovered,
                               offline.travel)
        #expect(recovered.map(\.identifier) == offlinePlan.map(\.identifier))
        #expect(recovered.map(\.text.title) == thuPlan.map(\.text.title))

        // 4. travelNoAddress at Thu 06:00.
        let noAddress = try NotificationRig(now: F.m(3, "06:00"), variant: .travelNoAddress)
        await noAddress.launch()
        let noAddressPlan = ordinary(noAddress)
        text += "\n" + section("Routing: travelNoAddress, Thu 06:00", noAddressPlan, noAddress.travel)
        #expect(noAddressPlan.first?.text.body
                == "LAB_F5.12 · Travel time from Home unavailable: Home has no address. Check your route before you leave.")
        #expect(await noAddress.travel.provider.callCount == 0)

        // 5. Departure refresh at Thu 11:30: 50, 78 (at once), 30.
        for minutes in [50, 78, 30] {
            let rig = try NotificationRig(now: F.m(3, "11:00"))
            await rig.launch()
            await rig.travel.provider.set(.minutes(minutes), for: .init(from: "home", to: "campus", mode: .transit))
            await rig.travel.run(until: F.m(3, "11:31"))
            await rig.settle()
            let epc = try require(rig.travel.event("EPC-ILV", day: 3), "epc \(minutes)")
            let request = try require(await rig.pending()["leave.\(epc.id.uuidString)"], "pending leave \(minutes)")
            let item = PlannedNotification(identifier: request.identifier, subjectID: request.subjectID, kind: .leave,
                                           fireAt: request.fireAt, atOnce: request.atOnce,
                                           text: NotificationText(title: request.title, body: request.body),
                                           category: request.category, playsSound: request.playsSound,
                                           interruption: request.interruption)
            text += "\n" + section("Departure refresh at Thu 11:30, the mock answering \(minutes) min", [item], rig.travel)
            switch minutes {
            case 50: #expect(request.fireAt == F.m(3, "11:55") && request.title == "Leave by 12:00 for EPC-ILV")
            case 78: #expect(request.atOnce && request.title == "Leave by 11:32 for EPC-ILV")
            default: #expect(request.fireAt == F.m(3, "12:15") && request.title == "Leave by 12:20 for EPC-ILV")
            }
        }

        // 6. From where you are (Thu 11:30, location allowed, fix `cafe`).
        let fix = LocationFix(latitude: MockLocationSource.cafe.latitude, longitude: MockLocationSource.cafe.longitude,
                              horizontalAccuracy: 50, timestamp: F.m(3, "11:30"))
        let hereRig = try TravelRig(now: F.m(3, "11:00"), location: MockLocationSource(authorization: .allowed,
                                                                                      fix: .absolute(fix)))
        let hereCentre = RecordingNotificationCenter()
        let hereScheduler = NotificationScheduler(context: hereRig.context, centre: hereCentre, clock: hereRig.clock,
                                                  calendar: F.calendar, log: RoutingLog(category: "notifications"))
        await hereRig.launchAndSettle()
        await hereRig.run(until: F.m(3, "11:31"))
        let herePlan = hereScheduler.makePlan(now: hereRig.clock.now).filter { $0.text.title.contains("EPC-ILV") }
        text += "\n" + section("From where you are (Thu 11:30, -KadenceLocation allowed, fix cafe)", herePlan, hereRig)
        #expect(herePlan.first?.text.body == "Starts 13:00 · LAB_F5.12 · 28 min from where you are")

        // 7. Catch-up (launch passes, no records).
        for clock in ["12:12", "12:20", "13:05"] {
            // Legs only (no scheduler wired, so no record exists yet), then
            // the launch pass's plan from a fresh scheduler.
            let rig = try TravelRig(now: F.m(3, clock))
            await rig.launchAndSettle()
            let scheduler = NotificationScheduler(context: rig.context, centre: RecordingNotificationCenter(),
                                                  clock: rig.clock, calendar: F.calendar,
                                                  log: RoutingLog(category: "notifications"))
            let plan = scheduler.makePlan(now: rig.clock.now, catchUp: true).filter { $0.atOnce }
            text += "\n" + section("Catch-up at Thu \(clock) (launch pass)", plan, rig)
            switch clock {
            case "12:12": #expect(plan.map(\.text.title) == ["Leave by 12:15 for EPC-ILV"])
            case "12:20": #expect(plan.map(\.text.title) == ["Leave now for EPC-ILV"])
            default: #expect(plan.isEmpty)
            }
        }

        // 8. Snooze results.
        let snooze = try NotificationRig(now: F.m(3, "17:41"))
        await snooze.launch()
        let router = NotificationActionRouter(context: snooze.travel.context, undo: snooze.travel.undo,
                                              centre: snooze.centre, clock: snooze.travel.clock, calendar: F.calendar)
        let dinner = try require(snooze.travel.event("Dinner with flatmates", day: 3), "dinner")
        await router.handle(NotificationResponse(identifier: "leave.\(dinner.id.uuidString)", action: .snooze,
                                                 subjectID: dinner.id.uuidString, category: .event))
        let late = try NotificationRig(now: F.m(5, "23:01"))
        await late.launch()
        let lateRouter = NotificationActionRouter(context: late.travel.context, undo: late.travel.undo,
                                                  centre: late.centre, clock: late.travel.clock, calendar: F.calendar)
        let call = try require(late.travel.event("Late call", day: 5), "late call")
        await lateRouter.handle(NotificationResponse(identifier: "start.\(call.id.uuidString)", action: .snooze,
                                                     subjectID: call.id.uuidString, category: .event))
        var results: [String] = []
        for added in await snooze.centre.addCalls + late.centre.addCalls where added.category == .result {
            results.append("identifier: result.{…}\ntitle:      \(added.title)\nbody:       \(added.body)\n"
                           + "category:   \(added.category.rawValue)\nsound:      none\nlevel:      \(added.interruption.rawValue)")
        }
        text += "\n== Snooze results (N5 at Thu 17:41, N6 at Sat 23:01)\n\n" + results.joined(separator: "\n\n") + "\n"
        #expect(results.count == 2)

        // 9. Sync paused (N8).
        for (mockCase, clock) in [(MockCalDAVServer.Case.unauthorized, F.m(3, "10:00")), (.forbidden, F.m(3, "10:00")),
                                  (.unauthorized, F.m(3, "03:00"))] {
            let s = try SyncPausedRig(now: clock, case: mockCase)
            await s.sync(.interval)
            let alerts = await s.rig.pending().values.filter { $0.identifier.hasPrefix("sync.") }.map {
                PlannedNotification(identifier: $0.identifier, subjectID: $0.subjectID, kind: .sync, fireAt: $0.fireAt,
                                    atOnce: $0.atOnce, text: NotificationText(title: $0.title, body: $0.body),
                                    category: $0.category, playsSound: $0.playsSound, interruption: $0.interruption)
            }
            text += "\n" + section("Sync paused: \(mockCase.rawValue), background sync at \(RoutingLog.clock(clock, calendar: F.calendar))",
                                   alerts, s.rig.travel)
            #expect(alerts.count == 1)
        }

        // The file.
        #expect(!text.contains("48.2") && !text.contains("Example"))
        if ProcessInfo.processInfo.environment["KADENCE_CAPTURE_DIR"].map({ !$0.isEmpty }) == true {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kadence-captures")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: directory.appendingPathComponent("notification-plan-travel-p3b.txt"))
        }
    }
}
