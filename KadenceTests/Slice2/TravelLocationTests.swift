//
//  TravelLocationTests.swift
//  KadenceTests
//
//  PHASE3-SLICE2-PLAN.md task 7 — components.md §24.2.1, §24.11, §24.12:
//  where you are, for the next departure only, at its T−45 refresh. Mock
//  location source and mock provider; no CoreLocation object is built.
//

import Testing
import Foundation
import SwiftData
import CoreLocation
@testable import Kadence

@MainActor
@Suite(.serialized)
struct TravelLocationTests {
    let thu1100 = TravelFixtures.m(3, "11:00")
    let thu1130 = TravelFixtures.m(3, "11:30")

    func cafe(at time: Date, age: TimeInterval = 0, accuracy: Double = 50) -> LocationFix {
        LocationFix(latitude: MockLocationSource.cafe.latitude, longitude: MockLocationSource.cafe.longitude,
                    horizontalAccuracy: accuracy, timestamp: time.addingTimeInterval(-age))
    }

    func rig(_ location: MockLocationSource) async throws -> TravelRig {
        let rig = try TravelRig(now: thu1100, location: location)
        await rig.launchAndSettle()
        return rig
    }

    /// Every Double stored in any slice-2 row, and every cache key: the fix
    /// may appear in none of them (§24.11).
    func assertNoFixStored(_ rig: TravelRig, _ fix: LocationFix) throws {
        func near(_ value: Double?, _ target: Double) -> Bool { value.map { abs($0 - target) < 0.0005 } ?? false }
        for leg in rig.legs() {
            for child in Mirror(reflecting: LegValues(leg)).children {
                #expect(!near(child.value as? Double, fix.latitude) && !near(child.value as? Double, fix.longitude))
            }
        }
        for row in try rig.context.fetch(FetchDescriptor<TravelETACache>()) {
            #expect(!row.key.contains(TravelCacheKey.rounded(fix.latitude)))
            #expect(!row.key.contains(TravelCacheKey.rounded(fix.longitude)))
        }
        for place in try rig.context.fetch(FetchDescriptor<KnownPlace>()) {
            #expect(!near(place.latitude, fix.latitude) || !near(place.longitude, fix.longitude))
        }
        for line in rig.log.lines {
            #expect(!line.contains("48.21") && !line.contains("16.38"))
        }
        try RoutingLogCheck.assertForms(rig.log.lines)
    }

    @Test("§30.1 From where you are: the T−45 refresh routes from `cafe` → 28 min → depart 12:22, currentLocation, no cache row")
    func fromHere() async throws {
        let location = MockLocationSource(authorization: .allowed, fix: .absolute(cafe(at: thu1130)))
        let rig = try await rig(location)
        let cacheRows = try rig.context.fetchCount(FetchDescriptor<TravelETACache>())
        await rig.run(until: TravelFixtures.m(3, "11:31"))
        let leg = try require(rig.leg("EPC-ILV", day: 3))
        #expect(rig.hhmm(leg.departAt) == "12:22")
        #expect(leg.duration == 28 * 60 && leg.status == .ready)
        #expect(leg.originKind == .currentLocation && leg.originPlaceID == nil)
        #expect(try rig.context.fetchCount(FetchDescriptor<TravelETACache>()) == cacheRows)
        #expect(rig.log.lines.contains("location used"))
        #expect(rig.log.lines.contains("eta ok · 28 min · transit · refresh · here"))
        try assertNoFixStored(rig, cafe(at: thu1130))
        #expect(await location.fixCalls == 1)
    }

    @Test("Within 300 m of the rule origin → the rule origin, from Home, `location not used · within 300 m`")
    func withinRadius() async throws {
        // Home + ~100 m (north, a little east).
        let near = LocationFix(latitude: 48.2009, longitude: 16.3903, horizontalAccuracy: 50, timestamp: thu1130)
        let rig = try await rig(MockLocationSource(authorization: .allowed, fix: .absolute(near)))
        await rig.run(until: TravelFixtures.m(3, "11:31"))
        let leg = try require(rig.leg("EPC-ILV", day: 3))
        #expect(leg.originKind == .place && leg.originPlaceID == "home")
        #expect(rig.hhmm(leg.departAt) == "12:15")
        #expect(rig.log.lines.contains("location not used · within 300 m"))
        #expect(!rig.log.lines.contains("location used"))
        try assertNoFixStored(rig, near)
    }

    @Test("Never at T−3 h; a fix 3 min old or with 250 m accuracy is not used")
    func notUsed() async throws {
        // T−3 h of EPC-ILV (09:15): no location call at all.
        let early = MockLocationSource(authorization: .allowed, fix: .absolute(cafe(at: TravelFixtures.m(3, "09:15"))))
        let earlyRig = try TravelRig(now: TravelFixtures.m(3, "06:00"), location: early)
        await earlyRig.launchAndSettle()
        await earlyRig.run(until: TravelFixtures.m(3, "09:16"))
        #expect(await early.totalCalls == 0)
        #expect(earlyRig.queue.history.contains { $0.id.hasPrefix("refresh:") })

        for fix in [cafe(at: thu1130, age: 180), cafe(at: thu1130, accuracy: 250)] {
            let rig = try await rig(MockLocationSource(authorization: .allowed, fix: .absolute(fix)))
            await rig.run(until: TravelFixtures.m(3, "11:31"))
            let leg = try require(rig.leg("EPC-ILV", day: 3))
            #expect(leg.originKind == .place && rig.hhmm(leg.departAt) == "12:15")
            #expect(!rig.log.lines.contains("location used"))
            try assertNoFixStored(rig, fix)
        }
    }

    @Test("denied → the rule origin and no fix requested; useCurrentLocation off → no location call at all")
    func deniedAndOff() async throws {
        let denied = MockLocationSource(authorization: .denied, fix: .absolute(cafe(at: thu1130)))
        let rig = try await rig(denied)
        await rig.run(until: TravelFixtures.m(3, "11:31"))
        #expect(rig.leg("EPC-ILV", day: 3)?.originKind == .place)
        #expect(await denied.fixCalls == 0)
        #expect(await denied.requestCalls == 0)
        #expect(rig.log.lines.contains("location unavailable · denied"))

        let off = MockLocationSource(authorization: .allowed, fix: .absolute(cafe(at: thu1130)))
        let offRig = try TravelRig(now: thu1100, location: off)
        TravelBuiltIns.settings(in: offRig.context).useCurrentLocation = false
        try offRig.context.save()
        await offRig.launchAndSettle()
        await offRig.run(until: TravelFixtures.m(3, "11:31"))
        #expect(await off.totalCalls == 0)
        #expect(offRig.leg("EPC-ILV", day: 3)?.originKind == .place)
        // The refresh still ran, from the rule origin.
        #expect(offRig.log.lines.contains("eta ok · 35 min · transit · refresh"))
    }

    @Test("First wanted fix with notDetermined, never asked → exactly one request, locationRequestedAt set, rule origin; later → no ask")
    func askOnce() async throws {
        let location = MockLocationSource(authorization: .notDetermined)
        let rig = try await rig(location)
        await rig.run(until: TravelFixtures.m(3, "11:31"))
        #expect(await location.requestCalls == 1)
        #expect(TravelBuiltIns.settings(in: rig.context).locationRequestedAt == thu1130)
        #expect(rig.leg("EPC-ILV", day: 3)?.originKind == .place)
        #expect(rig.log.lines.contains("eta ok · 35 min · transit · refresh"))
        // Friday's SWRM-ILV T−45 (14:30): asked before → no second ask, no fix.
        await rig.run(until: TravelFixtures.m(4, "14:31"))
        #expect(await location.requestCalls == 1)
        #expect(await location.fixCalls == 0)
    }

    @Test("A currentLocation leg survives an unrelated recompute; a buffer change replaces it")
    func currentLocationLegLifetime() async throws {
        let rig = try await rig(MockLocationSource(authorization: .allowed, fix: .absolute(cafe(at: thu1130))))
        await rig.run(until: TravelFixtures.m(3, "11:31"))
        #expect(rig.leg("EPC-ILV", day: 3)?.originKind == .currentLocation)
        // Unrelated: a note on another event, a recompute.
        try require(rig.event("Dinner with flatmates", day: 3)).notes = "wine"
        try rig.context.save()
        rig.coordinator.recompute()
        await rig.run(for: 5)
        #expect(rig.leg("EPC-ILV", day: 3)?.originKind == .currentLocation)
        #expect(rig.hhmm(rig.leg("EPC-ILV", day: 3)?.departAt) == "12:22")
        // The buffer changes: back to the rule origin.
        TravelBuiltIns.settings(in: rig.context).travelBufferMinutes = 15
        try rig.context.save()
        rig.coordinator.recompute()
        await rig.run(for: 5)
        let leg = try require(rig.leg("EPC-ILV", day: 3))
        #expect(leg.originKind == .place && leg.originPlaceID == "home")
        #expect(rig.hhmm(leg.departAt) == "12:10")
    }

    @Test("A failed request from the fix refreshes from the rule origin")
    func hereFails() async throws {
        let rig = try await rig(MockLocationSource(authorization: .allowed, fix: .absolute(cafe(at: thu1130))))
        await rig.provider.set(.failure(.failed), for: .init(from: "cafe", to: "campus", mode: .transit))
        await rig.run(until: TravelFixtures.m(3, "11:32"))
        let leg = try require(rig.leg("EPC-ILV", day: 3))
        #expect(leg.originKind == .place && leg.status == .ready)
        #expect(rig.log.lines.contains("eta failed · failed · transit"))
        #expect(rig.log.lines.contains("eta ok · 35 min · transit · refresh"))
    }

    @Test("The authorization mapping: allowed / denied (incl. restricted) / servicesOff / notDetermined")
    func authorizationMapping() {
        #expect(SystemLocationSource.map(status: .authorizedAlways, servicesEnabled: true) == .allowed)
        #expect(SystemLocationSource.map(status: .denied, servicesEnabled: true) == .denied)
        #expect(SystemLocationSource.map(status: .restricted, servicesEnabled: true) == .denied)
        #expect(SystemLocationSource.map(status: .notDetermined, servicesEnabled: true) == .notDetermined)
        #expect(SystemLocationSource.map(status: .authorizedAlways, servicesEnabled: false) == .servicesOff)
        #expect(SystemLocationSource.map(status: .notDetermined, servicesEnabled: false) == .servicesOff)
    }

    @Test("The factory: test-host and review launches never construct SystemLocationSource; only its file imports CoreLocation")
    func factory() throws {
        ServiceLaunchLog.reset()
        for kind in [LaunchKind.testHost] + ReviewMode.Dataset.allCases.map(LaunchKind.review) {
            #expect(LocationServices.make(for: kind) is MockLocationSource)
        }
        #expect(ServiceLaunchLog.constructed.allSatisfy { $0 == "MockLocationSource" })
        #expect(try SourceScan.files(importing: "CoreLocation") == ["SystemLocationSource.swift"])
        #expect(try SourceScan.files(containing: "CLLocationManager()") == ["SystemLocationSource.swift"])
    }
}
