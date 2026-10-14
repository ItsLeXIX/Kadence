//
//  LocationSource.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 7) — components.md §24.12,
//  §24.2.1, §24.11. Where the Mac is, behind a protocol like the
//  notification centre: `SystemLocationSource` (CoreLocation, normal launch
//  only, the only file that imports CoreLocation) and `MockLocationSource`
//  (scripted authorization and fix; every test and review launch).
//
//  Location is optional: every leg works from the rule origin without it.
//  A fix is held in memory for one request and never stored or logged.
//

import Foundation

/// §24.12's states, as Kadence names them.
nonisolated enum LocationAuthorization: String, Sendable, Equatable, CaseIterable {
    case allowed
    /// Denied, or restricted.
    case denied
    /// Location Services are off on this Mac.
    case servicesOff
    case notDetermined
}

/// One fix. Never stored, never logged, never cached (§24.11).
nonisolated struct LocationFix: Sendable, Equatable {
    var latitude: Double
    var longitude: Double
    /// Metres.
    var horizontalAccuracy: Double
    var timestamp: Date
}

nonisolated protocol LocationSource: Sendable {
    func authorization() async -> LocationAuthorization
    func requestAuthorization() async -> LocationAuthorization
    /// nil on any failure; never throws.
    func currentFix(timeout: Duration) async -> LocationFix?
}

/// §24.2.1's rules for using a fix — pure.
nonisolated enum LocationRules {
    /// A fix is used if at most 2 minutes old …
    static let maxAge: TimeInterval = 120
    /// … its horizontal accuracy is 200 m or better …
    static let maxAccuracy: Double = 200
    /// … and it is more than 300 m from the rule origin.
    static let minDistance: Double = 300
    /// One request, 10 s.
    static let timeout: Duration = .seconds(10)

    enum Verdict: Equatable, Sendable {
        case use
        case withinRadius
        case unusable
    }

    static func verdict(_ fix: LocationFix, origin: TravelEndpoint, now: Date) -> Verdict {
        guard now.timeIntervalSince(fix.timestamp) <= maxAge, fix.horizontalAccuracy >= 0,
              fix.horizontalAccuracy <= maxAccuracy else { return .unusable }
        let distance = metres(fix.latitude, fix.longitude, origin.latitude, origin.longitude)
        return distance > minDistance ? .use : .withinRadius
    }

    /// Great-circle distance (haversine), metres.
    static func metres(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let r = 6_371_000.0
        let p1 = lat1 * .pi / 180, p2 = lat2 * .pi / 180
        let dp = (lat2 - lat1) * .pi / 180, dl = (lon2 - lon1) * .pi / 180
        let a = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// The scripted location source tests and review launches use. It never
/// shows a prompt and never touches CoreLocation.
actor MockLocationSource: LocationSource {
    /// §30.1 `-KadenceLocation`.
    enum Case: String, Sendable, CaseIterable { case allowed, denied, servicesOff, notDetermined, notAsked }

    enum Fix: Sendable, Equatable {
        /// A fix with a fixed timestamp (tests).
        case absolute(LocationFix)
        /// A fix taken "now" on the wall clock, age 0 (review: §30.1 `cafe`).
        case fresh(latitude: Double, longitude: Double, accuracy: Double)
        case none
    }

    private var state: LocationAuthorization
    /// What the state becomes when Kadence asks (`notDetermined` by default:
    /// the review never answers a prompt — there is none).
    private var afterRequest: LocationAuthorization
    private var fix: Fix
    private(set) var authorizationCalls = 0
    private(set) var requestCalls = 0
    private(set) var fixCalls = 0

    init(authorization: LocationAuthorization = .notDetermined, afterRequest: LocationAuthorization? = nil,
         fix: Fix = .none) {
        state = authorization
        self.afterRequest = afterRequest ?? authorization
        self.fix = fix
    }

    /// §30.1's mock fix `cafe`: 48.2150, 16.3800, accuracy 50 m — 1.7 km
    /// from Home, so it is used.
    static let cafe = (latitude: 48.2150, longitude: 16.3800, accuracy: 50.0)

    func set(authorization: LocationAuthorization) { state = authorization }
    func set(fix: Fix) { self.fix = fix }

    var totalCalls: Int { authorizationCalls + requestCalls + fixCalls }

    func authorization() async -> LocationAuthorization {
        authorizationCalls += 1
        return state
    }

    func requestAuthorization() async -> LocationAuthorization {
        requestCalls += 1
        state = afterRequest
        return state
    }

    func currentFix(timeout: Duration) async -> LocationFix? {
        fixCalls += 1
        guard state == .allowed else { return nil }
        switch fix {
        case .absolute(let fix): return fix
        case .fresh(let latitude, let longitude, let accuracy):
            return LocationFix(latitude: latitude, longitude: longitude, horizontalAccuracy: accuracy, timestamp: Date())
        case .none: return nil
        }
    }
}

@MainActor
enum LocationServices {
    /// `SystemLocationSource` in a normal launch only (§24.11); the mock
    /// otherwise.
    static func make(for kind: LaunchKind, mock: @autoclosure () -> MockLocationSource = MockLocationSource())
    -> any LocationSource {
        switch ServiceImplementation.of(kind) {
        case .real:
            ServiceLaunchLog.record("SystemLocationSource")
            return SystemLocationSource()
        case .mock:
            ServiceLaunchLog.record("MockLocationSource")
            return mock()
        }
    }
}
