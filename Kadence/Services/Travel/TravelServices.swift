//
//  TravelServices.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md common rules; components.md
//  §24.11, §27.10; DECISIONS 2026-10-14 "The test runner is a third
//  launch"): which implementation of each external service a launch gets.
//  The same three-launch rule as the store and the transport (B45): only a
//  normal launch constructs the real ones (MapKit, CoreLocation,
//  `NWPathMonitor`, `UNUserNotificationCenter`); a launch XCTest started
//  and a `-KadenceReview` launch get the mocks. One factory per service,
//  each with its launch-kind table, and a launch log of what was
//  constructed — the evidence tests and review read.
//

import Foundation

/// What a factory built, by type name — never an address, a coordinate or
/// a title. Tests and the review launch read it (§24.11: "asserted as B45's
/// store is").
@MainActor
enum ServiceLaunchLog {
    private(set) static var constructed: [String] = []

    static func record(_ typeName: String) { constructed.append(typeName) }

    /// Tests only: forget what earlier tests built.
    static func reset() { constructed = [] }
}

/// The kind of implementation a launch gets for a service.
nonisolated enum ServiceImplementation: String, Sendable, Equatable {
    case real
    case mock

    /// The table: a normal launch gets the real service, review and the test
    /// host the mock. Every factory reads this one function.
    static func of(_ kind: LaunchKind) -> ServiceImplementation {
        switch kind {
        case .normal: .real
        case .review, .testHost: .mock
        }
    }
}

@MainActor
enum TravelServices {
    /// The travel-time provider for a launch. Review and tests get the mock
    /// with §30.1's table (the review variant scripts it further, task 12).
    static func makeProvider(for kind: LaunchKind,
                             mock: @autoclosure () -> MockTravelTimeProvider = defaultMockProvider())
    -> any TravelTimeProvider {
        switch ServiceImplementation.of(kind) {
        case .real:
            ServiceLaunchLog.record("MapKitTravelTimeProvider")
            return MapKitTravelTimeProvider()
        case .mock:
            ServiceLaunchLog.record("MockTravelTimeProvider")
            return mock()
        }
    }

    static func makeGeocoder(for kind: LaunchKind,
                             mock: @autoclosure () -> MockPlaceGeocoder = MockPlaceGeocoder()) -> any PlaceGeocoder {
        switch ServiceImplementation.of(kind) {
        case .real:
            ServiceLaunchLog.record("MapKitPlaceGeocoder")
            return MapKitPlaceGeocoder()
        case .mock:
            ServiceLaunchLog.record("MockPlaceGeocoder")
            return mock()
        }
    }

    /// `mapKit` for the real provider, `mock` otherwise (`TravelLeg.source`).
    static func providerSource(for kind: LaunchKind) -> String {
        ServiceImplementation.of(kind) == .real ? "mapKit" : "mock"
    }

    /// The review / test provider: §30.1's table with the review places'
    /// ids (`gym` is the review dataset's Gym).
    static func defaultMockProvider() -> MockTravelTimeProvider {
        MockTravelTimeProvider(table: MockTravelTimeProvider.reviewTable(gymID: "gym"),
                               fixes: MockTravelTimeProvider.reviewFixes)
    }
}
