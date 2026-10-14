//
//  TravelProvider.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 4) — components.md §24.9: the
//  travel-time provider and the address geocoder, behind protocols. The
//  slice's only real implementations are `MapKitTravelTimeProvider` and
//  `MapKitPlaceGeocoder` (the only two files that import MapKit); tests and
//  review use `MockTravelTimeProvider` / `MockPlaceGeocoder`
//  (`MockTravel.swift`). Nothing here imports MapKit.
//

import Foundation

/// §24.9, exactly.
nonisolated enum TravelTimeError: Error, Equatable, Sendable {
    /// No network (`URLError.notConnectedToInternet` and kin).
    case offline
    /// `MKError.directionsNotFound`, or an answer in another mode.
    case noRoute
    /// `MKError.loadingThrottled`.
    case throttled
    /// Anything else (`serverFailure`, unknown, a timeout of 20 s).
    case failed

    /// The leg's reason for this failure (§24.3): a throttle is a pause.
    var reason: TravelReason {
        switch self {
        case .offline: .offline
        case .noRoute: .noRoute
        case .throttled: .paused
        case .failed: .failed
        }
    }

    /// The routing log's word (§24.11: `eta failed · offline · transit`).
    var logWord: String {
        switch self {
        case .offline: "offline"
        case .noRoute: "noRoute"
        case .throttled: "throttled"
        case .failed: "failed"
        }
    }
}

/// BRIEF-PRODUCT's signature, typed (§24.9).
nonisolated protocol TravelTimeProvider: Sendable {
    func duration(from: TravelEndpoint, to: TravelEndpoint,
                  arrivingBy: Date, mode: TravelMode) async throws(TravelTimeError) -> TimeInterval
}

/// §24.9: one MapKit address result.
nonisolated struct GeocodedAddress: Sendable, Equatable {
    var line: String
    var latitude: Double
    var longitude: Double
}

nonisolated enum GeocodeError: Error, Equatable, Sendable {
    case offline, throttled, failed
}

nonisolated protocol PlaceGeocoder: Sendable {
    /// `[]` = not found.
    func lookUp(_ address: String) async throws(GeocodeError) -> [GeocodedAddress]
}

/// The provider-independent rules both the MapKit provider and the mock
/// apply to an answer, so the mock behaves as the real one would.
nonisolated enum TravelAnswerRules {
    /// §24.9: "An answer whose `transportType` is not the requested one is
    /// `noRoute` (never accepted as a different mode)." `answered` nil: a
    /// transport type Kadence has no mode for (`.any`, cycling).
    static func accept(seconds: TimeInterval, requested: TravelMode,
                       answered: TravelMode?) -> Result<TimeInterval, TravelTimeError> {
        answered == requested ? .success(seconds) : .failure(.noRoute)
    }

    /// §24.9: at most the first 6 results are kept (5 shown, the 6th only
    /// tells "more than 5"). A result without an address line is skipped.
    static let geocodeResultCap = 6

    static func geocoded(_ results: [(line: String?, latitude: Double, longitude: Double)]) -> [GeocodedAddress] {
        results.compactMap { result -> GeocodedAddress? in
            guard let line = result.line?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty
            else { return nil }
            return GeocodedAddress(line: line, latitude: result.latitude, longitude: result.longitude)
        }
        .prefix(geocodeResultCap)
        .map { $0 }
    }

    /// The URL errors that mean "no network" (§24.9: `offline`).
    static let offlineURLCodes: Set<Int> = [
        URLError.notConnectedToInternet.rawValue, URLError.networkConnectionLost.rawValue,
        URLError.dataNotAllowed.rawValue, URLError.internationalRoamingOff.rawValue,
    ]

    /// Whether `error`, or the error underlying it, is a no-network URL error.
    static func isOffline(_ error: NSError) -> Bool {
        if error.domain == NSURLErrorDomain, offlineURLCodes.contains(error.code) { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { return isOffline(underlying) }
        return false
    }
}
