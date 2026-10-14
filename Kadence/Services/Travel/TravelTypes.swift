//
//  TravelTypes.swift
//  Kadence
//
//  Phase 3 slice 2 — the value types the travel planner, the provider seam
//  and the routing queue share (components.md §24.9). Plain values, no
//  MapKit: only `MapKitTravelTimeProvider` / `MapKitPlaceGeocoder` turn them
//  into MapKit requests.
//

import Foundation

/// §24.9: a value snapshot of a `KnownPlace`, or of the current location
/// (`id` nil). No coordinate, no request.
nonisolated struct TravelEndpoint: Sendable, Equatable, Hashable {
    var id: String?
    var latitude: Double
    var longitude: Double
}

/// A known place as the planners read it (§23.1, §28.1).
nonisolated struct PlaceSnapshot: Sendable, Equatable {
    var id: String
    var name: String
    var latitude: Double?
    var longitude: Double?
    var geocodeState: GeocodeState

    var endpoint: TravelEndpoint? {
        guard let latitude, let longitude else { return nil }
        return TravelEndpoint(id: id, latitude: latitude, longitude: longitude)
    }

    @MainActor
    init(_ place: KnownPlace) {
        id = place.id
        name = place.name
        latitude = place.latitude
        longitude = place.longitude
        geocodeState = place.geocodeState
    }

    init(id: String, name: String, latitude: Double? = nil, longitude: Double? = nil,
         geocodeState: GeocodeState = .confirmed) {
        self.id = id
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.geocodeState = geocodeState
    }
}

/// An event as the travel and notification planners read it.
nonisolated struct TravelEventSnapshot: Sendable, Equatable {
    var id: UUID
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var isCancelled: Bool
    var status: EventStatus
    var origin: EventOrigin
    var placeID: String?
    var sourceID: String?
    var locationText: String?
    var isOnline: Bool

    @MainActor
    init(_ event: Event) {
        id = event.id
        title = event.title
        start = event.start
        end = event.end
        isAllDay = event.isAllDay
        isCancelled = event.isCancelled
        status = event.status
        origin = event.origin
        placeID = event.placeID
        sourceID = event.sourceID
        locationText = event.location?.name
        isOnline = event.isOnline
    }

    init(id: UUID = UUID(), title: String, start: Date, end: Date, isAllDay: Bool = false,
         isCancelled: Bool = false, status: EventStatus = .scheduled, origin: EventOrigin = .manual,
         placeID: String? = nil, sourceID: String? = nil, locationText: String? = nil, isOnline: Bool = false) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.isCancelled = isCancelled
        self.status = status
        self.origin = origin
        self.placeID = placeID
        self.sourceID = sourceID
        self.locationText = locationText
        self.isOnline = isOnline
    }
}

/// A cache row as the planner reads it (§24.9 / §28.1 `TravelETACache`).
nonisolated struct ETACacheEntry: Sendable, Equatable {
    var key: String
    var originPlaceID: String
    var destinationPlaceID: String
    var mode: TravelMode
    var dayType: TravelDayType
    var slotMinutes: Int
    var travelSeconds: Double
    var computedAt: Date
    var arrivalDate: Date

    @MainActor
    init(_ row: TravelETACache) {
        key = row.key
        originPlaceID = row.originPlaceID
        destinationPlaceID = row.destinationPlaceID
        mode = row.mode
        dayType = row.dayType
        slotMinutes = row.slotMinutes
        travelSeconds = row.travelSeconds
        computedAt = row.computedAt
        arrivalDate = row.arrivalDate
    }

    init(key: String, originPlaceID: String, destinationPlaceID: String, mode: TravelMode, dayType: TravelDayType,
         slotMinutes: Int, travelSeconds: Double, computedAt: Date, arrivalDate: Date) {
        self.key = key
        self.originPlaceID = originPlaceID
        self.destinationPlaceID = destinationPlaceID
        self.mode = mode
        self.dayType = dayType
        self.slotMinutes = slotMinutes
        self.travelSeconds = travelSeconds
        self.computedAt = computedAt
        self.arrivalDate = arrivalDate
    }
}

/// A leg's values, as stored (`TravelLeg`) and as planned. Equatable, so a
/// recompute writes only what changed (§24.5).
nonisolated struct LegValues: Sendable, Equatable {
    var eventID: UUID
    var status: TravelLegStatus
    var reason: TravelReason?
    var reasonPlaceID: String?
    var retryAt: Date?
    var departAt: Date?
    var duration: TimeInterval?
    var buffer: TimeInterval
    var mode: TravelMode
    var originKind: TravelOriginKind
    var originPlaceID: String?
    var destinationPlaceID: String
    var source: String
    var computedAt: Date?
    var refreshedAt: Date?

    var isEstimate: Bool { status == .estimate }
    var hasTime: Bool { status == .ready || status == .estimate }

    @MainActor
    init(_ leg: TravelLeg) {
        eventID = leg.eventID
        status = leg.status
        reason = leg.unavailableReason
        reasonPlaceID = leg.reasonPlaceID
        retryAt = leg.retryAt
        departAt = leg.departAt
        duration = leg.duration
        buffer = leg.buffer
        mode = leg.mode
        originKind = leg.originKind
        originPlaceID = leg.originPlaceID
        destinationPlaceID = leg.destinationPlaceID
        source = leg.source
        computedAt = leg.computedAt
        refreshedAt = leg.refreshedAt
    }

    init(eventID: UUID, status: TravelLegStatus, reason: TravelReason? = nil, reasonPlaceID: String? = nil,
         retryAt: Date? = nil, departAt: Date? = nil, duration: TimeInterval? = nil, buffer: TimeInterval,
         mode: TravelMode, originKind: TravelOriginKind = .place, originPlaceID: String?,
         destinationPlaceID: String, source: String = "", computedAt: Date? = nil, refreshedAt: Date? = nil) {
        self.eventID = eventID
        self.status = status
        self.reason = reason
        self.reasonPlaceID = reasonPlaceID
        self.retryAt = retryAt
        self.departAt = departAt
        self.duration = duration
        self.buffer = buffer
        self.mode = mode
        self.originKind = originKind
        self.originPlaceID = originPlaceID
        self.destinationPlaceID = destinationPlaceID
        self.source = source
        self.computedAt = computedAt
        self.refreshedAt = refreshedAt
    }

    /// Writes these values onto a stored leg.
    @MainActor
    func write(to leg: TravelLeg) {
        leg.eventID = eventID
        leg.status = status
        leg.isEstimate = isEstimate
        leg.unavailableReason = reason
        leg.reasonPlaceID = reasonPlaceID
        leg.retryAt = retryAt
        leg.departAt = departAt
        leg.duration = duration
        leg.buffer = buffer
        leg.mode = mode
        leg.originKind = originKind
        leg.originPlaceID = originPlaceID
        leg.destinationPlaceID = destinationPlaceID
        leg.source = source
        leg.computedAt = computedAt
        leg.refreshedAt = refreshedAt
    }
}
