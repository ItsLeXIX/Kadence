//
//  Place.swift
//  Kadence
//

import Foundation
import SwiftData

/// A location an event happens at.
///
/// `coordinate` is stored as two optional Doubles rather than a CLLocationCoordinate2D
/// because SwiftData persists plain value types and Phase 1 does no geocoding —
/// the coordinate is only populated from Phase 3 onward, by the travel-time provider.
@Model
final class Place {
    var name: String
    var address: String?
    var latitude: Double?
    var longitude: Double?

    init(name: String, address: String? = nil, latitude: Double? = nil, longitude: Double? = nil) {
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
    }
}
