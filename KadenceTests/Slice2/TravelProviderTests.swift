//
//  TravelProviderTests.swift
//  KadenceTests
//
//  PHASE3-SLICE2-PLAN.md task 4 — components.md §24.9, §23.5, §24.11: the
//  provider and geocoder seams, the mocks, the cache store and the factory.
//  The MapKit types are exercised only through their pure mapping
//  functions: no `MKDirections` or `MKLocalSearch` is ever started here.
//  (This test file imports MapKit only to name `MKError` codes and
//  transport types; the app's own MapKit imports are the two files the
//  source scan below allows.)
//

import Testing
import Foundation
import SwiftData
import MapKit
@testable import Kadence

@MainActor
@Suite(.serialized)
struct TravelProviderTests {

    func mk(_ code: MKError.Code, underlying: NSError? = nil) -> NSError {
        var info: [String: Any] = [:]
        if let underlying { info[NSUnderlyingErrorKey] = underlying }
        return NSError(domain: MKError.errorDomain, code: Int(code.rawValue), userInfo: info)
    }

    func url(_ code: URLError.Code) -> NSError { URLError(code) as NSError }

    @Test("Error mapping: throttled, noRoute, offline (as the error or underlying), failed")
    func errorMapping() {
        #expect(MapKitTravelTimeProvider.map(mk(.loadingThrottled)) == .throttled)
        #expect(MapKitTravelTimeProvider.map(mk(.directionsNotFound)) == .noRoute)
        #expect(MapKitTravelTimeProvider.map(url(.notConnectedToInternet)) == .offline)
        #expect(MapKitTravelTimeProvider.map(url(.networkConnectionLost)) == .offline)
        #expect(MapKitTravelTimeProvider.map(mk(.serverFailure, underlying: url(.notConnectedToInternet))) == .offline)
        #expect(MapKitTravelTimeProvider.map(mk(.unknown, underlying: url(.networkConnectionLost))) == .offline)
        #expect(MapKitTravelTimeProvider.map(mk(.serverFailure)) == .failed)
        #expect(MapKitTravelTimeProvider.map(mk(.unknown)) == .failed)
        #expect(MapKitTravelTimeProvider.map(url(.timedOut)) == .failed)
        #expect(MapKitTravelTimeProvider.map(NSError(domain: "x", code: 1)) == .failed)
        // An answer whose transport type differs is noRoute.
        let walkingAnswer = MapKitTravelTimeProvider.mode(for: .walking)
        #expect(TravelAnswerRules.accept(seconds: 600, requested: .transit, answered: walkingAnswer) == .failure(.noRoute))
        #expect(TravelAnswerRules.accept(seconds: 600, requested: .transit,
                                         answered: MapKitTravelTimeProvider.mode(for: .any)) == .failure(.noRoute))
        #expect(TravelAnswerRules.accept(seconds: 600, requested: .walking, answered: walkingAnswer) == .success(600))
        // The geocoder's: offline, throttled, not found → [], else failed.
        #expect(MapKitPlaceGeocoder.map(url(.notConnectedToInternet)) == .offline)
        #expect(MapKitPlaceGeocoder.map(mk(.loadingThrottled)) == .throttled)
        #expect(MapKitPlaceGeocoder.map(mk(.placemarkNotFound)) == nil)
        #expect(MapKitPlaceGeocoder.map(mk(.serverFailure)) == .failed)
    }

    @Test("Mode mapping: transit → .transit, walking → .walking, driving → .automobile; nothing else")
    func modeMapping() {
        #expect(MapKitTravelTimeProvider.transportType(for: .transit) == .transit)
        #expect(MapKitTravelTimeProvider.transportType(for: .walking) == .walking)
        #expect(MapKitTravelTimeProvider.transportType(for: .driving) == .automobile)
        let produced = TravelMode.allCases.map { MapKitTravelTimeProvider.transportType(for: $0) }
        #expect(!produced.contains(.any))
        #expect(produced.allSatisfy { [MKDirectionsTransportType.transit, .walking, .automobile].contains($0) })
        for mode in TravelMode.allCases {
            #expect(MapKitTravelTimeProvider.mode(for: MapKitTravelTimeProvider.transportType(for: mode)) == mode)
        }
    }

    @Test("The geocode result mapping keeps at most 6; 0 → []; a result without a line is skipped")
    func geocodeMapping() {
        let eight = (1...8).map { (line: Optional("Example Straße \($0), 1020 Wien, Austria"), latitude: 48.0, longitude: 16.0) }
        let mapped = TravelAnswerRules.geocoded(eight)
        #expect(mapped.count == 6)
        #expect(mapped.first?.line == "Example Straße 1, 1020 Wien, Austria")
        #expect(TravelAnswerRules.geocoded([]) == [])
        #expect(TravelAnswerRules.geocoded([(line: nil, latitude: 1, longitude: 2), (line: " ", latitude: 1, longitude: 2)]) == [])
    }

    @Test("The factory: a test-host and a -KadenceReview launch construct the mocks and never a MapKit type")
    func factory() {
        #expect(ServiceImplementation.of(.normal) == .real)
        #expect(ServiceImplementation.of(.testHost) == .mock)
        for dataset in ReviewMode.Dataset.allCases { #expect(ServiceImplementation.of(.review(dataset)) == .mock) }
        ServiceLaunchLog.reset()
        for kind in [LaunchKind.testHost] + ReviewMode.Dataset.allCases.map(LaunchKind.review) {
            let provider = TravelServices.makeProvider(for: kind)
            let geocoder = TravelServices.makeGeocoder(for: kind)
            #expect(provider is MockTravelTimeProvider)
            #expect(geocoder is MockPlaceGeocoder)
            #expect(TravelServices.providerSource(for: kind) == "mock")
        }
        #expect(!ServiceLaunchLog.constructed.isEmpty)
        #expect(ServiceLaunchLog.constructed.allSatisfy { $0.hasPrefix("Mock") })
        #expect(!ServiceLaunchLog.constructed.contains { $0.contains("MapKit") })
        #expect(TravelServices.providerSource(for: .normal) == "mapKit")
    }

    @Test("Only the two MapKit files import MapKit (source scan of the app target)")
    func mapKitImports() throws {
        let importers = try SourceScan.files(importing: "MapKit")
        #expect(importers == ["MapKitPlaceGeocoder.swift", "MapKitTravelTimeProvider.swift"])
    }

    @Test("The mock: §30.1's table, scripted failures, a mode-mismatch answer, a hold, and a call log")
    func mock() async throws {
        let mock = TravelServices.defaultMockProvider()
        let home = TravelEndpoint(id: "home", latitude: 48.2, longitude: 16.39)
        let campus = TravelEndpoint(id: "campus", latitude: 48.239, longitude: 16.377)
        let gym = TravelEndpoint(id: "gym", latitude: 48.205, longitude: 16.395)
        let cafe = TravelEndpoint(id: nil, latitude: 48.2150, longitude: 16.3800)
        let at = TravelFixtures.m(0, "08:50")
        #expect(try await mock.duration(from: home, to: campus, arrivingBy: at, mode: .transit) == 2100)
        #expect(try await mock.duration(from: gym, to: home, arrivingBy: at, mode: .walking) == 300)
        #expect(try await mock.duration(from: cafe, to: campus, arrivingBy: at, mode: .transit) == 1680)
        await #expect(throws: TravelTimeError.noRoute) {
            try await mock.duration(from: home, to: gym, arrivingBy: at, mode: .transit)
        }
        await mock.set(.answeredIn(.walking, minutes: 30), for: .init(from: "home", to: "campus", mode: .transit))
        await #expect(throws: TravelTimeError.noRoute) {
            try await mock.duration(from: home, to: campus, arrivingBy: at, mode: .transit)
        }
        await mock.answerEverything(.failure(.offline))
        await #expect(throws: TravelTimeError.offline) {
            try await mock.duration(from: gym, to: home, arrivingBy: at, mode: .walking)
        }
        let calls = await mock.calls
        #expect(calls.count == 6)
        #expect(calls[2].from == "cafe")

        // A hold keeps the call in flight until released — no clock.
        let held = TravelServices.defaultMockProvider()
        await held.hold()
        let task = Task { try await held.duration(from: home, to: campus, arrivingBy: at, mode: .transit) }
        while await held.callCount == 0 { await Task.yield() }
        await held.release()
        #expect(try await task.value == 2100)
    }

    @Test("The mock geocoder's cases; the campus query always answers its one result")
    func mockGeocoder() async throws {
        #expect(try await MockPlaceGeocoder(case: .one).lookUp("Example Straße 1").count == 1)
        #expect(try await MockPlaceGeocoder(case: .several).lookUp("Example Straße 1").count == 3)
        #expect(try await MockPlaceGeocoder(case: .many).lookUp("Example Straße 1").count == 6)
        #expect(try await MockPlaceGeocoder(case: .none).lookUp("Exampel Strasse 1").isEmpty)
        await #expect(throws: GeocodeError.offline) { try await MockPlaceGeocoder(case: .offline).lookUp("x") }
        let campus = try await MockPlaceGeocoder(case: .none).lookUp("Höchstädtplatz 6, 1200 Wien")
        #expect(campus == [GeocodedAddress(line: "Höchstädtplatz 6, 1200 Wien, Austria", latitude: 48.2390, longitude: 16.3770)])
    }

    // MARK: The cache store

    func request(from: PlaceSnapshot, to: PlaceSnapshot, at arrival: Date, mode: TravelMode = .transit)
    -> TravelLegPlanner.Request {
        let key = TravelCacheKey(origin: from.endpoint!, destination: to.endpoint!, mode: mode, arrival: arrival,
                                 calendar: TravelFixtures.calendar)
        return TravelLegPlanner.Request(key: key.string, origin: from.endpoint!, destination: to.endpoint!, mode: mode,
                                        arrivingBy: arrival, priority: 4, eventStart: arrival, eventIDs: [],
                                        dayType: key.dayType, slotMinutes: key.slotMinutes,
                                        originPlaceID: from.id, destinationPlaceID: to.id)
    }

    @Test("Cache: two answers for one key keep the later; a new Home coordinate deletes the old key's rows")
    func cacheUpsertAndInvalidate() throws {
        let container = try slice2MemoryContainer()
        let store = TravelETACacheStore(context: container.mainContext)
        let r = request(from: TravelFixtures.home, to: TravelFixtures.campus, at: TravelFixtures.m(0, "08:50"))
        let t1 = TravelFixtures.date("2026-10-12 06:00"), t2 = TravelFixtures.date("2026-10-12 07:00")
        store.upsert(r, travelSeconds: 2100, computedAt: t1)
        store.upsert(r, travelSeconds: 2400, computedAt: t2)
        store.upsert(r, travelSeconds: 1800, computedAt: t1)   // older, arriving late: ignored
        #expect(store.all().count == 1)
        #expect(store.entry(forKey: r.key)?.travelSeconds == 2400 && store.entry(forKey: r.key)?.computedAt == t2)

        let back = request(from: TravelFixtures.campus, to: TravelFixtures.home, at: TravelFixtures.m(3, "18:20"))
        let gym = request(from: TravelFixtures.campus, to: TravelFixtures.gym, at: TravelFixtures.m(3, "18:20"))
        store.upsert(back, travelSeconds: 2100, computedAt: t1)
        store.upsert(gym, travelSeconds: 1200, computedAt: t1)
        // Home's coordinate unchanged: nothing goes.
        store.deleteRows(of: "home", notAt: 48.2000, 16.3900)
        #expect(store.all().count == 3)
        // A new Home coordinate: both Home rows go, the campus → Gym row stays.
        store.deleteRows(of: "home", notAt: 48.2100, 16.3900)
        #expect(store.all().map(\.key) == [gym.key])
        // A removed place: every row touching it.
        store.deleteRows(touching: TravelFixtures.gymID)
        #expect(store.all().isEmpty)
    }

    @Test("Pruning at launch deletes entries older than 28 days, and only those")
    func prune() throws {
        let container = try slice2MemoryContainer()
        let store = TravelETACacheStore(context: container.mainContext)
        let now = TravelFixtures.m(0, "06:00")
        let a = request(from: TravelFixtures.home, to: TravelFixtures.campus, at: TravelFixtures.m(0, "08:50"))
        let b = request(from: TravelFixtures.home, to: TravelFixtures.campus, at: TravelFixtures.m(1, "09:50"))
        store.upsert(a, travelSeconds: 2100, computedAt: now.addingTimeInterval(-28 * 86_400))
        store.upsert(b, travelSeconds: 2100, computedAt: now.addingTimeInterval(-28 * 86_400 - 1))
        #expect(store.prune(now: now) == 1)
        #expect(store.all().map(\.key) == [a.key])
    }
}

/// Reads the app target's Swift sources (the repo's `Kadence/` folder).
nonisolated enum SourceScan {
    static var appRoot: URL { Fixture.repoRoot.appendingPathComponent("Kadence") }

    static func swiftFiles() throws -> [URL] {
        let enumerator = FileManager.default.enumerator(at: appRoot, includingPropertiesForKeys: nil)
        var files: [URL] = []
        while let url = enumerator?.nextObject() as? URL {
            if url.pathExtension == "swift" { files.append(url) }
        }
        return files
    }

    /// The file names (sorted) with a line `import <module>`.
    static func files(importing module: String) throws -> [String] {
        try swiftFiles().filter { url in
            let text = try String(contentsOf: url, encoding: .utf8)
            return text.split(separator: "\n").contains {
                $0.trimmingCharacters(in: .whitespaces) == "import \(module)"
                    || $0.trimmingCharacters(in: .whitespaces).hasPrefix("@preconcurrency import \(module)")
            }
        }
        .map(\.lastPathComponent).sorted()
    }

    /// Every app source file containing `text` (comments included).
    static func files(containing text: String) throws -> [String] {
        try swiftFiles().filter { try String(contentsOf: $0, encoding: .utf8).contains(text) }
            .map(\.lastPathComponent).sorted()
    }
}
