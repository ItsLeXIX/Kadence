//
//  CampusLookupTests.swift
//  KadenceTests
//
//  P3S2-F04 — components.md §23.6 (amended 2026-10-15, closes G-098): FH
//  Technikum Wien is looked up at the first launch, through the queue and the
//  injected geocoder (`MockPlaceGeocoder`), whether or not a leg needs it
//  yet. A failure is retried at most once a day at launch or wake; an
//  address the user edited is never looked up automatically. No review
//  switch. Nothing here touches MapKit or the network.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

/// A geocoder that is offline for every address, the campus included
/// (`MockPlaceGeocoder` always answers the campus, §30.1). A scripted double:
/// no MapKit, no network.
actor OfflineGeocoder: PlaceGeocoder {
    private(set) var lookupCount = 0
    func lookUp(_ address: String) async throws(GeocodeError) -> [GeocodedAddress] {
        lookupCount += 1
        throw .offline
    }
}

@MainActor
struct CampusLookupTests {
    static let now = TravelFixtures.date("2026-10-15 09:00")

    func campus(_ rig: TravelRig) throws -> KnownPlace {
        try require(try rig.context.fetch(FetchDescriptor<KnownPlace>()).first { $0.id == BuiltInPlace.campus.id })
    }

    func freshRig(_ lookup: MockPlaceGeocoder.Case = .one) throws -> (TravelRig, MockPlaceGeocoder) {
        let geocoder = MockPlaceGeocoder(case: lookup)
        return (try TravelRig(now: Self.now, seed: false, geocoder: geocoder), geocoder)
    }

    @Test("A fresh store with no events: one lookup at launch, campus confirmed with the mock's coordinate, no ETA request")
    func firstLaunch() async throws {
        let (rig, geocoder) = try freshRig()
        #expect(try rig.context.fetchCount(FetchDescriptor<Event>()) == 0)
        rig.coordinator.launched()
        await rig.run(for: 30)
        #expect(await geocoder.lookupCount == 1)
        let place = try campus(rig)
        #expect(place.geocodeState == .confirmed)
        #expect(place.latitude == 48.2390 && place.longitude == 16.3770)
        #expect(place.confirmedAddress == "Höchstädtplatz 6, 1200 Wien, Austria")
        #expect(await rig.provider.calls.isEmpty)
        // Once per install: another launch asks nothing.
        rig.coordinator.launched()
        await rig.run(for: 30)
        #expect(await geocoder.lookupCount == 1)
    }

    @Test("Offline at the first launch: lookupFailed, not again that day, retried at the next day's launch")
    func offlineRetriedNextDay() async throws {
        let geocoder = OfflineGeocoder()
        let rig = try TravelRig(now: Self.now, seed: false, geocoder: geocoder)
        rig.coordinator.launched()
        await rig.run(for: 30)
        #expect(await geocoder.lookupCount == 1)
        #expect(try campus(rig).geocodeState == .lookupFailed)

        rig.coordinator.didWake()
        rig.coordinator.launched()
        rig.coordinator.recompute()
        await rig.run(for: 30)
        #expect(await geocoder.lookupCount == 1, "not again the same day")

        rig.clock.set(TravelFixtures.date("2026-10-16 08:00"))
        rig.coordinator.recompute()
        await rig.run(for: 30)
        #expect(await geocoder.lookupCount == 1, "an ordinary pass never retries")
        rig.coordinator.launched()
        await rig.run(for: 30)
        #expect(await geocoder.lookupCount == 2, "retried at the next day's launch")
    }

    @Test("An address the user edited is never looked up automatically")
    func editedAddress() async throws {
        let (rig, geocoder) = try freshRig()
        try campus(rig).addressText = "Höchstädtplatz 6, 1200 Wien, Stiege 3"
        try rig.context.save()
        rig.coordinator.launched()
        await rig.run(for: 30)
        rig.coordinator.didWake()
        await rig.run(for: 30)
        #expect(await geocoder.lookupCount == 0)
        #expect(try campus(rig).geocodeState != .confirmed)
    }

    @Test("The review switch is gone from the app")
    func noSwitch() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Kadence")
        for file in ["KadenceApp.swift", "Services/Travel/TravelCoordinator.swift"] {
            let text = try String(contentsOf: root.appendingPathComponent(file), encoding: .utf8)
            #expect(!text.contains("looksUpCampusAtLaunch"), "\(file)")
        }
    }
}
