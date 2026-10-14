//
//  Travel.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 1) — components.md §28.1:
//  the travel models. `KnownPlace` (where you travel to and from),
//  `TravelModeOverride` (a pair of places travelled another way),
//  `AppSettings` (the settings that are not per source, place or rule),
//  `TravelLeg` (one event's computed departure — derived data, §24) and
//  `TravelETACache` (Apple Maps' answers, keyed so a semester costs a few
//  dozen requests, §24.9).
//
//  Every stored field has a default, so a slice 1 store opens without a
//  migration step (§28: "as §21.3"). Enums are stored as raw strings with a
//  computed accessor, like `Event` and `Source`.
//
//  Swift note: this target makes everything `@MainActor` by default. The
//  small enums below are `nonisolated` so the pure planners (task 3 on) can
//  use them off the main actor.
//

import Foundation
import SwiftData

// MARK: - Vocabulary

/// §28.1 `KnownPlace.geocodeState` (§23.5). `searching` is not stored.
nonisolated enum GeocodeState: String, Codable, CaseIterable, Sendable {
    case none
    case unconfirmed
    case notFound
    case lookupFailed
    case confirmed
}

/// §24.3 — a missing time is a state, not an absence.
nonisolated enum TravelLegStatus: String, Codable, CaseIterable, Sendable {
    case ready
    case estimate
    case pending
    case unavailable
}

/// §24.3's reasons: why a leg is an estimate, pending or unavailable.
nonisolated enum TravelReason: String, Codable, CaseIterable, Sendable {
    case needsAddress
    case offline
    case noRoute
    case paused
    case failed
    case pending
}

/// §24.2.1: a leg's origin is a known place, or where the Mac is.
nonisolated enum TravelOriginKind: String, Codable, CaseIterable, Sendable {
    case place
    case currentLocation
}

/// §24.9 — the cache key's day type.
nonisolated enum TravelDayType: String, Codable, CaseIterable, Sendable {
    case weekday
    case saturday
    case sunday

    /// Mon–Fri `weekday`, Sat `saturday`, Sun `sunday`, in `calendar`'s zone.
    static func of(_ date: Date, calendar: Calendar) -> TravelDayType {
        switch calendar.component(.weekday, from: date) {
        case 1: .sunday
        case 7: .saturday
        default: .weekday
        }
    }
}

// MARK: - KnownPlace

/// §23.1 / §28.1 — BRIEF-PRODUCT's `Place`, under a new name: the existing
/// `Place` model is an event's stated location text (`HS_A3.15`), which is
/// where in the building, not where you travel to.
@Model
final class KnownPlace {
    /// Fixed ids for the built-ins (`home`, `campus`); a UUID string
    /// otherwise. A String, as `Source.id`.
    var id: String = UUID().uuidString
    var name: String = ""
    /// What the user typed (`campus`: Kadence's own built-in address, §23.6).
    var addressText: String?
    /// MapKit's one-line address that was confirmed (§23.5).
    var confirmedAddress: String?

    /// §28.1: both set or both nil. Swift note: `private(set)` makes the
    /// setter private to this type, so the only way to write a coordinate
    /// is `setCoordinate`, which refuses a half-set pair.
    private(set) var latitude: Double?
    private(set) var longitude: Double?

    private var geocodeStateRaw: String = GeocodeState.none.rawValue
    var geocodeState: GeocodeState {
        get { GeocodeState(rawValue: geocodeStateRaw) ?? .none }
        set { geocodeStateRaw = newValue.rawValue }
    }

    var geocodedAt: Date?
    var isBuiltIn: Bool = false
    var sortIndex: Int = 0

    init(id: String = UUID().uuidString, name: String, addressText: String? = nil,
         geocodeState: GeocodeState = .none, isBuiltIn: Bool = false, sortIndex: Int = 0) {
        self.id = id
        self.name = name
        self.addressText = addressText
        self.geocodeStateRaw = geocodeState.rawValue
        self.isBuiltIn = isBuiltIn
        self.sortIndex = sortIndex
    }

    /// Writes the coordinate. Both values, or neither: a write of one alone
    /// is refused (returns false and changes nothing).
    @discardableResult
    func setCoordinate(latitude: Double?, longitude: Double?) -> Bool {
        guard (latitude == nil) == (longitude == nil) else { return false }
        self.latitude = latitude
        self.longitude = longitude
        return true
    }

    /// Only a place with a coordinate can be travelled from or to (§23.1).
    var hasCoordinate: Bool { latitude != nil && longitude != nil }
}

/// The ids of §23.1's two built-in places.
nonisolated enum BuiltInPlace: String, CaseIterable, Sendable {
    case home
    case campus

    var id: String { rawValue }

    var defaultName: String {
        switch self {
        case .home: "Home"
        case .campus: "FH Technikum Wien"
        }
    }

    var sortIndex: Int {
        switch self {
        case .home: 0
        case .campus: 1
        }
    }

    /// §23.6: the campus's real address, looked up by Kadence itself. No
    /// coordinate is hard-coded anywhere.
    static let campusAddress = "Höchstädtplatz 6, 1200 Wien"
}

// MARK: - TravelModeOverride

/// §23.3 / §28.1 — a pair of known places travelled in another mode than
/// the preferred one. Symmetric: stored sorted (`placeA < placeB`), one row
/// per pair. Choosing `Usual` in Settings deletes the row.
@Model
final class TravelModeOverride {
    private(set) var placeA: String = ""
    private(set) var placeB: String = ""
    private var modeRaw: String = TravelMode.transit.rawValue
    var mode: TravelMode {
        get { TravelMode(rawValue: modeRaw) ?? .transit }
        set { modeRaw = newValue.rawValue }
    }

    /// Stores the pair sorted, whichever order it is given in.
    init(_ first: String, _ second: String, mode: TravelMode) {
        let (a, b) = Self.sorted(first, second)
        self.placeA = a
        self.placeB = b
        self.modeRaw = mode.rawValue
    }

    nonisolated static func sorted(_ first: String, _ second: String) -> (String, String) {
        first < second ? (first, second) : (second, first)
    }

    func joins(_ first: String, _ second: String) -> Bool {
        let (a, b) = Self.sorted(first, second)
        return placeA == a && placeB == b
    }
}

// MARK: - AppSettings

/// §28.1 — one row, id `app`. In the store, not `UserDefaults`, so a review
/// or test launch (in-memory stores) can never read or write the real ones.
@Model
final class AppSettings {
    var id: String = AppSettings.singletonID
    private var preferredTravelModeRaw: String = TravelMode.transit.rawValue
    var preferredTravelMode: TravelMode {
        get { TravelMode(rawValue: preferredTravelModeRaw) ?? .transit }
        set { preferredTravelModeRaw = newValue.rawValue }
    }

    /// §23.4: 0, 5, 10, 15, 20 or 30.
    var travelBufferMinutes: Int = 10
    /// §24.2: fixed at 120, not in Settings.
    var travelChainGapMinutes: Int = 120
    /// §24.2.1.
    var useCurrentLocation: Bool = true
    /// §24.12: Kadence asked for location once.
    var locationRequestedAt: Date?
    /// §23.6: at most one automatic campus retry a day.
    var campusLookupAttemptedAt: Date?
    /// §27.8: Kadence asked for notification permission once.
    var notificationsRequestedAt: Date?

    nonisolated static let singletonID = "app"

    init() {}
}

// MARK: - TravelLeg

/// §24.3 / §28.1 — the computed departure for one event. Derived data:
/// never an undo step, never written onto the event (§24.7); found by
/// `eventID` (no relationship on `Event`, §28.3).
@Model
final class TravelLeg {
    /// The event's local `id` (not `externalID`). One leg per event.
    var eventID: UUID = UUID()

    private var statusRaw: String = TravelLegStatus.pending.rawValue
    var status: TravelLegStatus {
        get { TravelLegStatus(rawValue: statusRaw) ?? .pending }
        set { statusRaw = newValue.rawValue }
    }

    /// `status == .estimate`, stored so every reader tests one field.
    var isEstimate: Bool = false

    private var unavailableReasonRaw: String?
    var unavailableReason: TravelReason? {
        get { unavailableReasonRaw.flatMap(TravelReason.init(rawValue:)) }
        set { unavailableReasonRaw = newValue?.rawValue }
    }

    /// The place a `needsAddress` names.
    var reasonPlaceID: String?
    /// `paused`: when the queue resumes.
    var retryAt: Date?
    /// Nil for `pending` / `unavailable`.
    var departAt: Date?
    /// Travel only, without the buffer.
    var duration: TimeInterval?
    /// The buffer used, in seconds.
    var buffer: TimeInterval = 0

    private var modeRaw: String = TravelMode.transit.rawValue
    var mode: TravelMode {
        get { TravelMode(rawValue: modeRaw) ?? .transit }
        set { modeRaw = newValue.rawValue }
    }

    private var originKindRaw: String = TravelOriginKind.place.rawValue
    var originKind: TravelOriginKind {
        get { TravelOriginKind(rawValue: originKindRaw) ?? .place }
        set { originKindRaw = newValue.rawValue }
    }

    /// Nil for `currentLocation`: no coordinate is ever stored (§24.11).
    var originPlaceID: String?
    var destinationPlaceID: String = ""
    /// `mapKit` or `mock`; empty for `pending` / `unavailable`.
    var source: String = ""
    var computedAt: Date?
    /// The last departure refresh that succeeded (§24.6).
    var refreshedAt: Date?

    init(eventID: UUID) {
        self.eventID = eventID
    }
}

// MARK: - TravelETACache

/// §24.9 / §28.1 — bookkeeping only, never shown. One row per key.
@Model
final class TravelETACache {
    /// The key's fields joined (§24.9); coordinates of known places only.
    var key: String = ""
    var originPlaceID: String = ""
    var destinationPlaceID: String = ""
    private var modeRaw: String = TravelMode.transit.rawValue
    var mode: TravelMode {
        get { TravelMode(rawValue: modeRaw) ?? .transit }
        set { modeRaw = newValue.rawValue }
    }

    private var dayTypeRaw: String = TravelDayType.weekday.rawValue
    var dayType: TravelDayType {
        get { TravelDayType(rawValue: dayTypeRaw) ?? .weekday }
        set { dayTypeRaw = newValue.rawValue }
    }

    /// Minutes after midnight, a multiple of 30.
    var slotMinutes: Int = 0
    var travelSeconds: Double = 0
    var computedAt: Date = Date.distantPast
    var arrivalDate: Date = Date.distantPast

    init(key: String, originPlaceID: String, destinationPlaceID: String, mode: TravelMode,
         dayType: TravelDayType, slotMinutes: Int, travelSeconds: Double, computedAt: Date, arrivalDate: Date) {
        self.key = key
        self.originPlaceID = originPlaceID
        self.destinationPlaceID = destinationPlaceID
        self.modeRaw = mode.rawValue
        self.dayTypeRaw = dayType.rawValue
        self.slotMinutes = slotMinutes
        self.travelSeconds = travelSeconds
        self.computedAt = computedAt
        self.arrivalDate = arrivalDate
    }
}

// MARK: - Writing overrides

/// Writes `TravelModeOverride` rows so the pair stays unique.
@MainActor
enum TravelModeOverrides {
    /// Inserts an override for the pair. Refused (returns nil, writes
    /// nothing) when the pair already has one, in either order, or when the
    /// two ids are the same place.
    @discardableResult
    static func insert(_ first: String, _ second: String, mode: TravelMode, in context: ModelContext) -> TravelModeOverride? {
        guard first != second, find(first, second, in: context) == nil else { return nil }
        let row = TravelModeOverride(first, second, mode: mode)
        context.insert(row)
        try? context.save()
        return row
    }

    static func find(_ first: String, _ second: String, in context: ModelContext) -> TravelModeOverride? {
        ((try? context.fetch(FetchDescriptor<TravelModeOverride>())) ?? []).first { $0.joins(first, second) }
    }
}
