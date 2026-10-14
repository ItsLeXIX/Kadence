//
//  MockTravel.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 4) — components.md §24.9,
//  §30.1: the scripted travel provider and geocoder every test and every
//  review launch uses. No network, no MapKit: answers come from tables.
//
//  Neither ever sleeps on a clock. "A delay" is a hold: a held call waits
//  until the test (or review mode) releases it — or forever, which is how
//  `travelPending` and `-KadenceGeocode searching` keep a request in flight.
//
//  Swift note: an `actor` is a class whose state only one task touches at a
//  time (like a Java object whose every method is `synchronized`, but
//  checked by the compiler); calls into it from outside are `await`ed.
//

import Foundation

// MARK: - Travel times

actor MockTravelTimeProvider: TravelTimeProvider {
    /// What the mock answers.
    enum Answer: Sendable, Equatable {
        case minutes(Int)
        case failure(TravelTimeError)
        /// An answer in another mode than the one asked for (→ `noRoute`
        /// through the same rule MapKit's answers go through).
        case answeredIn(TravelMode, minutes: Int)
    }

    /// A directed trip by endpoint name and mode. An endpoint is named by its
    /// place id, or — for a current-location fix — by the fix's name.
    struct Route: Hashable, Sendable {
        var from: String
        var to: String
        var mode: TravelMode
    }

    /// One call, as the mock saw it.
    struct Call: Sendable, Equatable {
        var from: String
        var to: String
        var mode: TravelMode
        var arrivingBy: Date
    }

    private var table: [Route: Answer]
    /// Every route not in the table (§30.1: "anything else → noRoute").
    private var fallback: Answer = .failure(.noRoute)
    /// Overrides the table for every call (`travelOffline`: `.failure(.offline)`).
    private var everything: Answer?
    /// Named current-location fixes (§30.1 `cafe`), matched by coordinate.
    private var fixes: [String: (latitude: Double, longitude: Double)]
    private var isHeld = false
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var calls: [Call] = []

    init(table: [Route: Answer] = [:], fixes: [String: (latitude: Double, longitude: Double)] = [:],
         everything: Answer? = nil, held: Bool = false) {
        self.table = table
        self.fixes = fixes
        self.everything = everything
        self.isHeld = held
    }

    /// §30.1's table: home ↔ campus 35 min transit, home ↔ Gym 5 min
    /// walking, campus ↔ Gym 20 min transit, fix `cafe` → campus 28 min
    /// transit; anything else `noRoute`.
    static func reviewTable(gymID: String) -> [Route: Answer] {
        [
            Route(from: "home", to: "campus", mode: .transit): .minutes(35),
            Route(from: "campus", to: "home", mode: .transit): .minutes(35),
            Route(from: "home", to: gymID, mode: .walking): .minutes(5),
            Route(from: gymID, to: "home", mode: .walking): .minutes(5),
            Route(from: "campus", to: gymID, mode: .transit): .minutes(20),
            Route(from: gymID, to: "campus", mode: .transit): .minutes(20),
            Route(from: "cafe", to: "campus", mode: .transit): .minutes(28),
        ]
    }

    /// §30.1's mock fix `cafe` (48.2150, 16.3800).
    static let reviewFixes: [String: (latitude: Double, longitude: Double)] = ["cafe": (48.2150, 16.3800)]

    // MARK: Scripting

    func set(_ answer: Answer, for route: Route) { table[route] = answer }
    func answerEverything(_ answer: Answer?) { everything = answer }
    func hold() { isHeld = true }

    /// Lets every held call answer (and later calls answer at once).
    func release() {
        isHeld = false
        let held = waiting
        waiting = []
        for continuation in held { continuation.resume() }
    }

    var callCount: Int { calls.count }

    // MARK: TravelTimeProvider

    func duration(from: TravelEndpoint, to: TravelEndpoint,
                  arrivingBy: Date, mode: TravelMode) async throws(TravelTimeError) -> TimeInterval {
        let route = Route(from: name(of: from), to: name(of: to), mode: mode)
        calls.append(Call(from: route.from, to: route.to, mode: mode, arrivingBy: arrivingBy))
        if isHeld { await withCheckedContinuation { waiting.append($0) } }
        switch everything ?? table[route] ?? fallback {
        case .minutes(let minutes):
            return TimeInterval(minutes * 60)
        case .failure(let failure):
            throw failure
        case .answeredIn(let answered, let minutes):
            switch TravelAnswerRules.accept(seconds: TimeInterval(minutes * 60), requested: mode, answered: answered) {
            case .success(let seconds): return seconds
            case .failure(let failure): throw failure
            }
        }
    }

    private func name(of endpoint: TravelEndpoint) -> String {
        if let id = endpoint.id { return id }
        for (name, fix) in fixes where abs(fix.latitude - endpoint.latitude) < 1e-9
            && abs(fix.longitude - endpoint.longitude) < 1e-9 { return name }
        return "here"
    }
}

// MARK: - Address lookup

actor MockPlaceGeocoder: PlaceGeocoder {
    /// §30.1's `-KadenceGeocode` cases.
    enum Case: String, Sendable, CaseIterable {
        case one, several, many, none, offline, searching
    }

    private var lookupCase: Case
    private var isHeld: Bool
    private var waiting: [CheckedContinuation<Void, Never>] = []
    private(set) var queries: [String] = []

    init(case lookupCase: Case = .one) {
        self.lookupCase = lookupCase
        // `searching`: `one` after a held delay (released by the test).
        isHeld = lookupCase == .searching
    }

    func setCase(_ newCase: Case) { lookupCase = newCase; isHeld = newCase == .searching }

    func release() {
        isHeld = false
        let held = waiting
        waiting = []
        for continuation in held { continuation.resume() }
    }

    var lookupCount: Int { queries.count }

    /// §30.1: the campus query always answers its one result.
    static let campus = GeocodedAddress(line: "Höchstädtplatz 6, 1200 Wien, Austria", latitude: 48.2390, longitude: 16.3770)

    static let one = [GeocodedAddress(line: "Example Straße 1, 1020 Wien, Austria", latitude: 48.2050, longitude: 16.3950)]
    static let several = [
        GeocodedAddress(line: "Example Straße 1, 1020 Wien, Austria", latitude: 48.2050, longitude: 16.3950),
        GeocodedAddress(line: "Example Straße 1, 1210 Wien, Austria", latitude: 48.2600, longitude: 16.4000),
        GeocodedAddress(line: "Example Straße 1, 2340 Mödling, Austria", latitude: 48.0850, longitude: 16.2900),
    ]
    /// Six, so the lookup line says "more than 5" (§23.5).
    static let many: [GeocodedAddress] = several + [
        GeocodedAddress(line: "Example Straße 1, 1100 Wien, Austria", latitude: 48.1750, longitude: 16.3800),
        GeocodedAddress(line: "Example Straße 1, 1140 Wien, Austria", latitude: 48.2000, longitude: 16.2900),
        GeocodedAddress(line: "Example Straße 1, 3400 Klosterneuburg, Austria", latitude: 48.3050, longitude: 16.3250),
    ]

    func lookUp(_ address: String) async throws(GeocodeError) -> [GeocodedAddress] {
        queries.append(address)
        if address.trimmingCharacters(in: .whitespacesAndNewlines) == BuiltInPlace.campusAddress { return [Self.campus] }
        if isHeld { await withCheckedContinuation { waiting.append($0) } }
        switch lookupCase {
        case .one, .searching: return Self.one
        case .several: return Self.several
        case .many: return Self.many
        case .none: return []
        case .offline: throw .offline
        }
    }
}
