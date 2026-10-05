//
//  RoutineTombstone.swift
//  Kadence
//
//  components.md §13.7.4 (task P2-T41): "Deleting a materialised instance
//  records that the pair was deleted, and re-materialisation never recreates
//  a tombstoned pair." Without this, `⌫` on a routine instance removed the
//  row, and the next materialisation pass found no event for that
//  `(sourceID, externalID)` and created it again (DEVIATIONS.md A29).
//
//  The record is keyed by the same `(sourceID, externalID)` pair the instance
//  had (`RoutineEngine`'s `(template id, "<block id>#yyyy-MM-dd")`), so it needs
//  no new identity scheme. It is not detachment and is never counted as an
//  edited instance (§13.7.4, first bullet).
//
//  Lifetime: components.md §13.7.4 (amended 2026-10-05, closes G-031) — a
//  tombstone is removed only by undoing its own delete (`⌘Z`, same step).
//  Nothing else removes it, withdrawal included, so reactivating a weekday
//  never brings back a day the user deleted.
//

import Foundation
import SwiftData

/// Swift note (from Java/C#): `@Model` is a macro that turns this class into a
/// SwiftData entity, much like a JPA `@Entity`. Stored properties become
/// persisted columns. Defaults on every property let SwiftData add the entity
/// to an existing on-disk store without a hand-written migration.
@Model
final class RoutineTombstone {
    /// `RoutineTemplate.id.uuidString` of the deleted instance.
    var sourceID: String = ""
    /// `"<block id>#yyyy-MM-dd"` of the deleted instance.
    var externalID: String = ""

    init(sourceID: String, externalID: String) {
        self.sourceID = sourceID
        self.externalID = externalID
    }
}

/// Every `@Model` type the app persists, in one list. `KadenceApp` builds its
/// container from this, and so do the tests, so a new entity (like
/// `RoutineTombstone` above) can't be missing from a test container while the
/// code under test writes it. Inserting a type the container doesn't know is
/// a crash, not an error.
enum KadenceSchema {
    static let models: [any PersistentModel.Type] = [
        Event.self, Place.self, RoutineTemplate.self, RoutineBlock.self, TimeWindow.self,
        RoutineTombstone.self,
    ]
}

/// Reading and writing tombstones. Callers are `EventStore.delete` (writes
/// one, recorded in the delete's own step) and `RoutineEngine.materialize`
/// (reads them, so a tombstoned pair is never recreated).
@MainActor
enum RoutineTombstones {

    /// The identity a tombstone is keyed by.
    struct Pair: Hashable, Sendable {
        let sourceID: String
        let externalID: String
    }

    /// The pair of a **materialised routine instance**, or `nil` for any other
    /// event. `origin == .routine` with both ids set is exactly what
    /// `RoutineEngine.materialize` creates. Hand-seeded `.routine` events
    /// (no ids) and Phase 3 imports (`origin == .imported`, which also carry
    /// ids) leave no tombstone: re-materialisation can't recreate them.
    static func pair(of event: Event) -> Pair? {
        guard event.origin == .routine,
              let sourceID = event.sourceID, let externalID = event.externalID
        else { return nil }
        return Pair(sourceID: sourceID, externalID: externalID)
    }

    private static func fetch(_ pair: Pair, in context: ModelContext) -> [RoutineTombstone] {
        let sourceID = pair.sourceID
        let externalID = pair.externalID
        let descriptor = FetchDescriptor<RoutineTombstone>(predicate: #Predicate {
            $0.sourceID == sourceID && $0.externalID == externalID
        })
        return (try? context.fetch(descriptor)) ?? []
    }

    /// Idempotent: a pair is tombstoned at most once.
    static func insert(_ pair: Pair, in context: ModelContext) {
        guard fetch(pair, in: context).isEmpty else { return }
        context.insert(RoutineTombstone(sourceID: pair.sourceID, externalID: pair.externalID))
        try? context.save()
    }

    static func remove(_ pair: Pair, in context: ModelContext) {
        for tombstone in fetch(pair, in: context) { context.delete(tombstone) }
        try? context.save()
    }

    /// Every tombstoned `externalID` of one template (`sourceID`).
    static func externalIDs(sourceID: String, in context: ModelContext) -> Set<String> {
        let descriptor = FetchDescriptor<RoutineTombstone>(predicate: #Predicate { $0.sourceID == sourceID })
        return Set(((try? context.fetch(descriptor)) ?? []).map(\.externalID))
    }

    static func contains(_ pair: Pair, in context: ModelContext) -> Bool {
        !fetch(pair, in: context).isEmpty
    }
}
