//
//  TravelBuiltIns.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 1) — what every store holds
//  from its first launch, in every launch kind, the same pattern as
//  §21.1.1's built-in sources (`BuiltInSource.ensure`):
//
//  - the two built-in known places (components.md §23.1): `home` (no
//    address, `none`) and `campus` (`Höchstädtplatz 6, 1200 Wien`,
//    `unconfirmed`, **no coordinate** — §23.6: the coordinate is only ever
//    what MapKit returns);
//  - the one `AppSettings` row with §28.1's defaults;
//  - the five `NotificationRule`s with §27.1's defaults. A store that has
//    the four slice-2 rules gains `syncPaused`.
//
//  Idempotent: a second call inserts nothing and changes nothing the user
//  may have edited.
//

import Foundation
import SwiftData

@MainActor
enum TravelBuiltIns {
    static func ensure(in context: ModelContext) {
        var inserted = false

        let places = Set(((try? context.fetch(FetchDescriptor<KnownPlace>())) ?? []).map(\.id))
        for builtIn in BuiltInPlace.allCases where !places.contains(builtIn.id) {
            let place = KnownPlace(id: builtIn.id, name: builtIn.defaultName, isBuiltIn: true,
                                   sortIndex: builtIn.sortIndex)
            if builtIn == .campus {
                place.addressText = BuiltInPlace.campusAddress
                place.geocodeState = .unconfirmed
            }
            context.insert(place)
            inserted = true
        }

        if ((try? context.fetchCount(FetchDescriptor<AppSettings>())) ?? 0) == 0 {
            context.insert(AppSettings())
            inserted = true
        }

        let kinds = Set(((try? context.fetch(FetchDescriptor<NotificationRule>())) ?? []).map(\.kind))
        for kind in NotificationRuleKind.allCases where !kinds.contains(kind) {
            context.insert(NotificationRule(kind: kind, leadMinutes: kind.defaultLeadMinutes))
            inserted = true
        }

        if inserted { try? context.save() }
    }

    /// The settings row, created if missing.
    static func settings(in context: ModelContext) -> AppSettings {
        if let row = (try? context.fetch(FetchDescriptor<AppSettings>()))?.first { return row }
        let row = AppSettings()
        context.insert(row)
        try? context.save()
        return row
    }
}

/// Deleting legs with their events (components.md §24.5: "Deleting an event
/// deletes its leg in the same transaction"). The caller saves.
@MainActor
enum TravelLegs {
    static func delete<S: Sequence>(for eventIDs: S, in context: ModelContext) where S.Element == UUID {
        let ids = Set(eventIDs)
        guard !ids.isEmpty else { return }
        for leg in (try? context.fetch(FetchDescriptor<TravelLeg>())) ?? [] where ids.contains(leg.eventID) {
            context.delete(leg)
        }
    }

    static func leg(for eventID: UUID, in context: ModelContext) -> TravelLeg? {
        var descriptor = FetchDescriptor<TravelLeg>(predicate: #Predicate { $0.eventID == eventID })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }
}
