//
//  ReviewTravelTests.swift
//  KadenceTests
//
//  PHASE3-SLICE2-PLAN.md task 12 — components.md §30.1 (datasets, variants,
//  mocks), §22.1 (review rules), §24.11; §30 items 14 and 23 (the plan
//  dump). Everything in memory, every service a mock.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

@MainActor
@Suite(.serialized)
struct ReviewTravelTests {
    let mon0600 = TravelFixtures.m(0, "06:00")

    /// A coordinator on an existing context, all mocks, a manual clock.
    func coordinator(_ context: ModelContext, provider: MockTravelTimeProvider, now: Date,
                     geocoder: any PlaceGeocoder = MockPlaceGeocoder())
    -> (TravelCoordinator, RouteRequestQueue, ManualTravelClock) {
        let clock = ManualTravelClock(now)
        let log = RoutingLog()
        let queue = RouteRequestQueue(provider: provider, geocoder: geocoder, clock: clock, path: ScriptedPathMonitoring(),
                                      calendar: TravelFixtures.calendar, log: log)
        let coordinator = TravelCoordinator(context: context, queue: queue, clock: clock, calendar: TravelFixtures.calendar,
                                            providerSource: "mock", log: log, location: MockLocationSource())
        return (coordinator, queue, clock)
    }

    func hhmm(_ date: Date?) -> String { date.map { RoutingLog.clock($0, calendar: TravelFixtures.calendar) } ?? "—" }

    @Test("Dataset travel at Mon 06:00: 13 timetable events from 14 VEVENTs (one merge, G-097), 2 history, no conflicts; §24.4")
    func travel() async throws {
        let rig = try TravelRig(now: mon0600)
        let timetable = rig.events().filter { $0.sourceID == TravelDataset.sourceID }
        #expect(timetable.count == 13 && timetable.filter { $0.start < mon0600 }.count == 2)
        #expect(ReviewFeed.reportTravel(template: ReviewTravelTemplate.text, today: mon0600, m: TravelRig.m,
                                        zone: TravelFixtures.zone).count == 14)
        let conflicts = MainWindow.sortedConflicts(events: rig.events(),
                                                   routineBlocks: try rig.context.fetch(FetchDescriptor<RoutineBlock>()),
                                                   now: mon0600)
        #expect(conflicts.isEmpty)
        await rig.launchAndSettle()
        for (title, day, depart) in [("SWQM-ILV", 0, "08:15"), ("SWEN3-LAB", 1, "09:15"), ("EPC-ILV", 3, "12:15"),
                                     ("Dinner with flatmates", 3, "17:45"), ("SWRM-ILV", 4, "15:15"),
                                     ("Early study group", 5, "06:45"), ("Climbing", 6, "17:45")] {
            #expect(rig.leg(title, day: day)?.status == .ready, "\(title)")
            #expect(hhmm(rig.leg(title, day: day)?.departAt) == depart, "\(title)")
        }
        for (title, day) in [("SWEN3-ILV", 1), ("Laundry", 2), ("INNO3-EL", 2), ("REQEN-EXAM", 3), ("Late call", 5)] {
            #expect(rig.leg(title, day: day) == nil, "\(title)")
        }
    }

    @Test("Variants' legs equal §24.4's variant lines: travelNoAddress, travelOffline, travelPending, travelNoRoute")
    func variants() async throws {
        // travelNoAddress
        let noAddress = try TravelRig(now: mon0600, variant: .travelNoAddress,
                                      provider: ReviewTravel.provider(dataset: .travel, variant: .travelNoAddress))
        await noAddress.launchAndSettle()
        #expect(noAddress.legs().count == 11)
        #expect(noAddress.legs().allSatisfy { $0.status == .unavailable && $0.unavailableReason == .needsAddress
                                                && $0.reasonPlaceID == "home" })
        #expect(await noAddress.provider.callCount == 0)

        // travelOffline: estimates from the stale entry; Dinner and Climbing unavailable · offline.
        let offline = try TravelRig(now: mon0600, variant: .travelOffline,
                                    provider: ReviewTravel.provider(dataset: .travel, variant: .travelOffline))
        await offline.launchAndSettle()
        for (title, day, depart) in [("SWQM-ILV", 0, "08:15"), ("SWEN3-LAB", 1, "09:15"), ("EPC-ILV", 3, "12:15"),
                                     ("SWRM-ILV", 4, "15:15"), ("Early study group", 5, "06:45")] {
            let leg = offline.leg(title, day: day)
            #expect(leg?.status == .estimate && leg?.unavailableReason == .offline, "\(title)")
            #expect(hhmm(leg?.departAt) == depart, "\(title)")
            #expect(leg?.computedAt == TravelFixtures.date("2026-09-27 18:00"), "\(title)")
        }
        for (title, day) in [("Dinner with flatmates", 3), ("Climbing", 6)] {
            #expect(offline.leg(title, day: day)?.status == .unavailable, "\(title)")
            #expect(offline.leg(title, day: day)?.unavailableReason == .offline, "\(title)")
        }

        // travelPending: the provider never answers; every leg pending —
        // within the queue's 20 s timeout of the request in flight (after
        // it, that one key is `failed`).
        let pending = try TravelRig(now: mon0600, variant: .travelPending,
                                    provider: ReviewTravel.provider(dataset: .travel, variant: .travelPending))
        pending.coordinator.launched()
        pending.clock.advance(by: 10)
        #expect(pending.legs().count == 11 && pending.legs().allSatisfy { $0.status == .pending })

        // travelNoRoute: Climbing unavailable · noRoute (walking); the rest ready.
        let noRoute = try TravelRig(now: mon0600, variant: .travelNoRoute,
                                    provider: ReviewTravel.provider(dataset: .travel, variant: .travelNoRoute))
        await noRoute.launchAndSettle()
        #expect(noRoute.leg("Climbing", day: 6)?.status == .unavailable)
        #expect(noRoute.leg("Climbing", day: 6)?.unavailableReason == .noRoute)
        #expect(noRoute.leg("EPC-ILV", day: 3)?.status == .ready)
    }

    @Test("phase3: Datenmodellierung 08:38, 22 min walking; Coffee with Nora 10:54, 6 min walking; phase2 the same",
          arguments: [ReviewMode.Dataset.phase3, .phase2])
    func phaseLegs(_ dataset: ReviewMode.Dataset) async throws {
        let container = try slice2MemoryContainer()
        let context = container.mainContext
        let undo = UndoStack()
        let now = TestClock.now
        AppStore.seedLaunch(.review(dataset), context: context, now: now, secrets: InMemorySecretStore()) {
            RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: now)
        }
        let (coordinator, queue, clock) = coordinator(context, provider: ReviewTravel.provider(dataset: dataset, variant: nil),
                                                      now: now)
        coordinator.launched()
        await queue.run(on: clock, until: now.addingTimeInterval(120))
        let events = try context.fetch(FetchDescriptor<Event>())
        let lecture = try require(events.first { $0.title == "Datenmodellierung" })
        let coffee = try require(events.first { $0.title == "Coffee with Nora" })
        let l = try require(coordinator.leg(for: lecture.id))
        #expect(hhmm(l.departAt) == "08:38" && l.duration == 22 * 60 && l.mode == .walking && l.buffer == 0)
        let c = try require(coordinator.leg(for: coffee.id))
        #expect(hhmm(c.departAt) == "10:54" && c.duration == 6 * 60 && c.mode == .walking)
        #expect(c.originPlaceID == "campus")
        // A leg is never a conflict (§24.8): the counts are ReviewModeTests'.
        #expect(MainWindow.sortedConflicts(events: events, routineBlocks: try context.fetch(FetchDescriptor<RoutineBlock>()),
                                           now: now).count == (dataset == .phase3 ? 14 : 13))
    }

    @Test("empty / fresh: Home none; the campus confirmed by the mock geocoder; transit; buffer 10; six rules",
          arguments: [ReviewMode.Dataset.empty, .fresh])
    func emptyAndFresh(_ dataset: ReviewMode.Dataset) async throws {
        let container = try slice2MemoryContainer()
        let context = container.mainContext
        let now = TestClock.now
        AppStore.seedLaunch(.review(dataset), context: context, now: now, secrets: InMemorySecretStore()) {}
        let (coordinator, queue, clock) = coordinator(context, provider: ReviewTravel.provider(dataset: dataset, variant: nil),
                                                      now: now)
        // No switch (P3S2-F04): every first launch looks the campus up (§23.6).
        coordinator.launched()
        await queue.run(on: clock, until: now.addingTimeInterval(120))
        let places = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<KnownPlace>()).map { ($0.id, $0) })
        #expect(places["home"]?.geocodeState == GeocodeState.none && places["home"]?.hasCoordinate == false)
        #expect(places["campus"]?.geocodeState == .confirmed)
        #expect(places["campus"]?.latitude == 48.2390 && places["campus"]?.longitude == 16.3770)
        #expect(places["campus"]?.confirmedAddress == "Höchstädtplatz 6, 1200 Wien, Austria")
        let settings = TravelBuiltIns.settings(in: context)
        #expect(settings.preferredTravelMode == .transit && settings.travelBufferMinutes == 10)
        // P3S3-T01: six since slice 3 adds `deadline` (components.md §42.3).
        #expect(try context.fetchCount(FetchDescriptor<NotificationRule>()) == 6)
    }

    @Test("A review launch of every dataset and variant constructs no MapKit, CoreLocation, NWPathMonitor or system-centre object")
    func reviewLaunchServices() throws {
        let suite = "ReviewTravelTests.services"
        let defaults = try require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for dataset in ReviewMode.Dataset.allCases {
            for variant in [nil] + TravelDataset.Variant.allCases.map(\.rawValue) {
                defaults.set(dataset.rawValue, forKey: "KadenceReview")
                defaults.set(variant, forKey: "KadenceReviewVariant")
                defaults.set("allowed", forKey: "KadenceLocation")
                ServiceLaunchLog.reset()
                _ = KadenceApp.makeTravelServices(kind: .review(dataset), defaults: defaults)
                _ = PathMonitors.make(for: .review(dataset))
                _ = NotificationServices.make(for: .review(dataset), review: .current(defaults))
                let built = ServiceLaunchLog.constructed
                #expect(built.count == 5)
                #expect(built.allSatisfy { $0.hasPrefix("Mock") || $0.hasPrefix("Scripted") || $0.hasPrefix("Recording") },
                        "\(dataset) \(variant ?? "-"): \(built)")
            }
        }
    }

    @Test("Review arguments: -KadenceGeocode, -KadenceLocation, -KadenceNotifications; notDetermined is after a recorded ask")
    func arguments() throws {
        let suite = "ReviewTravelTests.arguments"
        let defaults = try require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(ReviewTravel.geocodeCase(defaults) == .one && ReviewTravel.locationCase(defaults) == .notAsked)
        defaults.set("travel", forKey: "KadenceReview")
        defaults.set("many", forKey: "KadenceGeocode")
        defaults.set("notDetermined", forKey: "KadenceLocation")
        defaults.set("notDetermined", forKey: "KadenceNotifications")
        defaults.set("travelOffline", forKey: "KadenceReviewVariant")
        #expect(ReviewTravel.geocodeCase(defaults) == .many)
        #expect(ReviewTravel.locationCase(defaults) == .notDetermined)
        #expect(ReviewTravel.variant(defaults) == .travelOffline)
        #expect(ReviewNotifications.current(defaults) == .notDetermined)
        let container = try slice2MemoryContainer()
        TravelBuiltIns.ensure(in: container.mainContext)
        ReviewTravel.applyArguments(context: container.mainContext, now: mon0600, defaults: defaults)
        let settings = TravelBuiltIns.settings(in: container.mainContext)
        #expect(settings.locationRequestedAt == mon0600 && settings.notificationsRequestedAt == mon0600)
    }

    @Test("P6 starts at the launch time rounded up to the quarter hour + 60 min")
    func liveEvent() {
        let cal = TravelFixtures.calendar
        #expect(TravelDataset.liveEventStart(launch: TravelFixtures.m(3, "10:07"), calendar: cal) == TravelFixtures.m(3, "11:15"))
        #expect(TravelDataset.liveEventStart(launch: TravelFixtures.m(3, "10:15"), calendar: cal) == TravelFixtures.m(3, "11:15"))
        #expect(TravelDataset.liveEventStart(launch: TravelFixtures.m(3, "10:15").addingTimeInterval(1), calendar: cal)
                == TravelFixtures.m(3, "11:30"))
    }
}
