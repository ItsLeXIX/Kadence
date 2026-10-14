//
//  ReviewTravel.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 12) — components.md §30.1:
//  review mode's travel and notification mocks.
//
//  - `-KadenceReview travel` (with `-KadenceReviewVariant travelNoAddress |
//    travelOffline | travelPending | travelNoRoute`): `TravelDataset`.
//  - `-KadenceGeocode one|several|many|none|offline|searching` (default
//    `one`): the mock geocoder's case.
//  - `-KadenceLocation allowed|denied|servicesOff|notDetermined|notAsked`
//    (default `notAsked`): the mock location source (`allowed` gives the fix
//    `cafe`; `notDetermined` is "after a recorded ask").
//  - `-KadenceNotifications allowed|off|notDetermined|notAsked` (default
//    `allowed`; `NotificationCenterClient.swift`).
//  - `phase2` / `phase3`: the §12 items 7–8 bands come from real legs —
//    `Home`, `FH Technikum Wien` and a user place `Café Sperl`, every pair
//    walking, buffer 0, the mock answering 22 min home ↔ campus and 6 min
//    every Café trip.
//  - `empty` / `fresh`: the built-ins only; the campus is confirmed at launch
//    by the mock geocoder's automatic match (§23.6).
//
//  Review only: none of this runs in a normal launch.
//

import Foundation
import SwiftData

nonisolated enum ReviewTravel {
    // MARK: Arguments

    static func geocodeCase(_ defaults: UserDefaults = .standard) -> MockPlaceGeocoder.Case {
        defaults.string(forKey: "KadenceGeocode").flatMap(MockPlaceGeocoder.Case.init(rawValue:)) ?? .one
    }

    static func locationCase(_ defaults: UserDefaults = .standard) -> MockLocationSource.Case {
        defaults.string(forKey: "KadenceLocation").flatMap(MockLocationSource.Case.init(rawValue:)) ?? .notAsked
    }

    static func variant(_ defaults: UserDefaults = .standard) -> TravelDataset.Variant? {
        ReviewMode.variant(defaults).flatMap(TravelDataset.Variant.init(rawValue:))
    }

    // MARK: Mocks for a launch

    /// Café Sperl's id in the `phase2` / `phase3` datasets.
    static let cafeID = "cafe-sperl"

    /// The phase datasets' table (§30.1 "Other datasets"): home ↔ campus 22
    /// min walking, every Café trip 6 min walking, both directions.
    static func phaseTable() -> [MockTravelTimeProvider.Route: MockTravelTimeProvider.Answer] {
        var table: [MockTravelTimeProvider.Route: MockTravelTimeProvider.Answer] = [
            .init(from: "home", to: "campus", mode: .walking): .minutes(22),
            .init(from: "campus", to: "home", mode: .walking): .minutes(22),
        ]
        for other in ["home", "campus"] {
            table[.init(from: other, to: cafeID, mode: .walking)] = .minutes(6)
            table[.init(from: cafeID, to: other, mode: .walking)] = .minutes(6)
        }
        return table
    }

    /// The mock provider a review launch gets, scripted for its dataset and
    /// variant.
    static func provider(dataset: ReviewMode.Dataset, variant: TravelDataset.Variant?) -> MockTravelTimeProvider {
        switch dataset {
        case .phase2, .phase3:
            return MockTravelTimeProvider(table: phaseTable())
        case .travel, .empty, .fresh:
            var table = MockTravelTimeProvider.reviewTable(gymID: TravelDataset.gymID)
            var everything: MockTravelTimeProvider.Answer?
            var held = false
            switch variant {
            case .travelOffline: everything = .failure(.offline)
            case .travelPending: held = true
            case .travelNoRoute: table[.init(from: "home", to: TravelDataset.gymID, mode: .walking)] = .failure(.noRoute)
            case .travelNoAddress, nil: break
            }
            return MockTravelTimeProvider(table: table, fixes: MockTravelTimeProvider.reviewFixes,
                                          everything: everything, held: held)
        }
    }

    static func location(_ locationCase: MockLocationSource.Case) -> MockLocationSource {
        let cafe = MockLocationSource.cafe
        switch locationCase {
        case .allowed:
            return MockLocationSource(authorization: .allowed,
                                      fix: .fresh(latitude: cafe.latitude, longitude: cafe.longitude, accuracy: cafe.accuracy))
        case .denied: return MockLocationSource(authorization: .denied)
        case .servicesOff: return MockLocationSource(authorization: .servicesOff)
        case .notDetermined, .notAsked: return MockLocationSource(authorization: .notDetermined)
        }
    }

    // MARK: Seeding

    /// What every review launch records before its first pass: "after a
    /// recorded ask" for `-KadenceLocation notDetermined` and
    /// `-KadenceNotifications notDetermined`.
    @MainActor
    static func applyArguments(context: ModelContext, now: Date, defaults: UserDefaults = .standard) {
        let settings = TravelBuiltIns.settings(in: context)
        if locationCase(defaults) == .notDetermined, settings.locationRequestedAt == nil {
            settings.locationRequestedAt = now
        }
        if ReviewNotifications.current(defaults).hasAsked, settings.notificationsRequestedAt == nil {
            settings.notificationsRequestedAt = now
        }
        try? context.save()
    }

    /// `phase2` / `phase3` (§30.1 "Other datasets"): the places, the walking
    /// pairs, buffer 0, and `Coffee with Nora` at `Café Sperl`. Idempotent.
    @MainActor
    static func seedPhase(context: ModelContext, now: Date) {
        let places = Dictionary(((try? context.fetch(FetchDescriptor<KnownPlace>())) ?? []).map { ($0.id, $0) },
                                uniquingKeysWith: { a, _ in a })
        guard places[cafeID] == nil else { return }
        func confirm(_ place: KnownPlace, typed: String, found: String, _ latitude: Double, _ longitude: Double) {
            place.addressText = typed
            place.confirmedAddress = found
            place.setCoordinate(latitude: latitude, longitude: longitude)
            place.geocodeState = .confirmed
            place.geocodedAt = now
        }
        if let home = places["home"] {
            confirm(home, typed: TravelDataset.home.typed, found: TravelDataset.home.confirmed,
                    TravelDataset.home.latitude, TravelDataset.home.longitude)
        }
        if let campus = places["campus"] {
            confirm(campus, typed: TravelDataset.campus.typed, found: TravelDataset.campus.confirmed,
                    TravelDataset.campus.latitude, TravelDataset.campus.longitude)
        }
        let cafe = KnownPlace(id: cafeID, name: "Café Sperl", sortIndex: 2)
        confirm(cafe, typed: "Example Gasse 11, 1060 Wien", found: "Example Gasse 11, 1060 Wien, Austria", 48.2000, 16.3640)
        context.insert(cafe)
        for (a, b) in [("home", "campus"), ("campus", cafeID), ("home", cafeID)] {
            TravelModeOverrides.insert(a, b, mode: .walking, in: context)
        }
        let settings = TravelBuiltIns.settings(in: context)
        settings.preferredTravelMode = .transit
        settings.travelBufferMinutes = 0
        for event in (try? context.fetch(FetchDescriptor<Event>())) ?? [] where event.title == "Coffee with Nora" {
            event.placeID = cafeID
        }
        try? context.save()
    }
}
