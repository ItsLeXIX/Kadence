//
//  MapKitPlaceGeocoder.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 4) — components.md §23.5,
//  §24.9: addresses are looked up with MapKit's address search,
//  `MKLocalSearch` with `resultTypes = .address`, the region centred on
//  Vienna (48.21, 16.37) spanning 0.5° — a bias, not a filter. At most the
//  first 6 results are kept. Needs no location permission.
//
//  Constructed only by a normal launch (`TravelServices`). One of the two
//  files in the app that import MapKit. Its only tested parts are the pure
//  mappings below.
//

import Foundation
import MapKit

nonisolated struct MapKitPlaceGeocoder: PlaceGeocoder {
    func lookUp(_ address: String) async throws(GeocodeError) -> [GeocodedAddress] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = address
        request.resultTypes = .address
        request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 48.21, longitude: 16.37),
                                            span: MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5))
        do {
            let response = try await MKLocalSearch(request: request).start()
            return TravelAnswerRules.geocoded(response.mapItems.map(Self.result))
        } catch {
            if let mapped = Self.map(error as NSError) { throw mapped }
            return []
        }
    }

    /// A map item → its one-line address and coordinate.
    private static func result(_ item: MKMapItem) -> (line: String?, latitude: Double, longitude: Double) {
        let line = item.addressRepresentations?.fullAddress(includingRegion: true, singleLine: true)
            ?? item.address?.fullAddress
        let coordinate = item.location.coordinate
        return (line, coordinate.latitude, coordinate.longitude)
    }

    // MARK: Pure mapping — tested

    /// §23.5's lookup states: a no-network error → `offline`; MapKit's
    /// throttle → `throttled`; "nothing found" → nil (the caller answers
    /// `[]`, `notFound`); anything else → `failed`.
    static func map(_ error: NSError) -> GeocodeError? {
        if TravelAnswerRules.isOffline(error) { return .offline }
        if error.domain == MKError.errorDomain, let code = MKError.Code(rawValue: UInt(error.code)) {
            switch code {
            case .loadingThrottled: return .throttled
            case .placemarkNotFound, .directionsNotFound: return nil
            default: return .failed
            }
        }
        return .failed
    }
}
