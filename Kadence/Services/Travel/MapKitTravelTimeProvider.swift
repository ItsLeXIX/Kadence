//
//  MapKitTravelTimeProvider.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 4) — components.md §24.9: the
//  slice's only real `TravelTimeProvider`. One `MKDirections.Request` per
//  call: source and destination map items from the coordinates, the
//  transport type by §23.3's table, `arrivalDate = arrivingBy`, no alternate
//  routes; `calculateETA()`; returns `expectedTravelTime`.
//
//  Constructed only by a normal launch (`TravelServices`). One of the two
//  files in the app that import MapKit (a test scans the sources). Its only
//  tested parts are the pure mappings below; nothing in a test, a script or
//  a review launch ever runs `duration`.
//

import Foundation
import MapKit

nonisolated struct MapKitTravelTimeProvider: TravelTimeProvider {
    func duration(from: TravelEndpoint, to: TravelEndpoint,
                  arrivingBy: Date, mode: TravelMode) async throws(TravelTimeError) -> TimeInterval {
        let request = MKDirections.Request()
        request.source = Self.mapItem(from)
        request.destination = Self.mapItem(to)
        request.transportType = Self.transportType(for: mode)
        request.arrivalDate = arrivingBy
        request.requestsAlternateRoutes = false
        let response: MKDirections.ETAResponse
        do {
            response = try await MKDirections(request: request).calculateETA()
        } catch {
            throw Self.map(error as NSError)
        }
        switch TravelAnswerRules.accept(seconds: response.expectedTravelTime, requested: mode,
                                        answered: Self.mode(for: response.transportType)) {
        case .success(let seconds): return seconds
        case .failure(let failure): throw failure
        }
    }

    private static func mapItem(_ endpoint: TravelEndpoint) -> MKMapItem {
        let location = CLLocation(latitude: endpoint.latitude, longitude: endpoint.longitude)
        return MKMapItem(location: location, address: nil)
    }

    // MARK: Pure mappings — the only tested parts

    /// §23.3: `transit` → `.transit`, `walking` → `.walking`, `driving` →
    /// `.automobile`. Never `.any`, never cycling (G-095).
    static func transportType(for mode: TravelMode) -> MKDirectionsTransportType {
        switch mode {
        case .transit: .transit
        case .walking: .walking
        case .driving: .automobile
        }
    }

    /// The mode an answer came back in; nil for any type Kadence has no mode
    /// for (an answer in it is then `noRoute`).
    static func mode(for transportType: MKDirectionsTransportType) -> TravelMode? {
        switch transportType {
        case .transit: .transit
        case .walking: .walking
        case .automobile: .driving
        default: nil
        }
    }

    /// §24.9's error mapping. `loadingThrottled` → `throttled`;
    /// `directionsNotFound` → `noRoute`; a no-network URL error (as the error
    /// or its underlying error) → `offline`; anything else → `failed`.
    static func map(_ error: NSError) -> TravelTimeError {
        if TravelAnswerRules.isOffline(error) { return .offline }
        if error.domain == MKError.errorDomain, let code = MKError.Code(rawValue: UInt(error.code)) {
            switch code {
            case .loadingThrottled: return .throttled
            case .directionsNotFound: return .noRoute
            default: return .failed
            }
        }
        return .failed
    }
}
