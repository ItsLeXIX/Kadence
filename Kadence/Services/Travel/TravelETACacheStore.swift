//
//  TravelETACacheStore.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 4) — components.md §24.9
//  "The ETA cache": upsert an answer, read by key, delete by place or by an
//  old coordinate, prune entries older than 28 days at launch. Current-
//  location trips are never written here (§24.2.1, §24.11): the store takes
//  a planner `Request`, whose endpoints are known places.
//

import Foundation
import SwiftData

@MainActor
struct TravelETACacheStore {
    let context: ModelContext

    func all() -> [TravelETACache] {
        (try? context.fetch(FetchDescriptor<TravelETACache>())) ?? []
    }

    func entry(forKey key: String) -> TravelETACache? {
        var descriptor = FetchDescriptor<TravelETACache>(predicate: #Predicate { $0.key == key })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// Records an answer for a request's key. With a row already there, the
    /// later answer wins (an older answer arriving late changes nothing).
    @discardableResult
    func upsert(_ request: TravelLegPlanner.Request, travelSeconds: Double, computedAt: Date) -> TravelETACache {
        if let row = entry(forKey: request.key) {
            if computedAt >= row.computedAt {
                row.travelSeconds = travelSeconds
                row.computedAt = computedAt
                row.arrivalDate = request.arrivingBy
                try? context.save()
            }
            return row
        }
        let row = TravelETACache(key: request.key, originPlaceID: request.originPlaceID,
                                 destinationPlaceID: request.destinationPlaceID, mode: request.mode,
                                 dayType: request.dayType, slotMinutes: request.slotMinutes,
                                 travelSeconds: travelSeconds, computedAt: computedAt, arrivalDate: request.arrivingBy)
        context.insert(row)
        try? context.save()
        return row
    }

    /// A removed place: every row to or from it.
    func deleteRows(touching placeID: String) {
        var deleted = false
        for row in all() where row.originPlaceID == placeID || row.destinationPlaceID == placeID {
            context.delete(row)
            deleted = true
        }
        if deleted { try? context.save() }
    }

    /// A place's new coordinate: every row keyed by any other coordinate of
    /// that place (§28.1: "rows … of an old coordinate are deleted with the
    /// change"). `latitude` / `longitude` nil (the address was cleared)
    /// deletes every row of the place.
    func deleteRows(of placeID: String, notAt latitude: Double?, _ longitude: Double?) {
        guard let latitude, let longitude else { return deleteRows(touching: placeID) }
        let current = "\(placeID)@\(TravelCacheKey.rounded(latitude)),\(TravelCacheKey.rounded(longitude))"
        var deleted = false
        for row in all() where row.originPlaceID == placeID || row.destinationPlaceID == placeID {
            let parts = row.key.split(separator: "|").first.map(String.init) ?? ""
            let ends = parts.components(separatedBy: ">")
            let mine = row.originPlaceID == placeID ? ends.first : ends.last
            if mine != current {
                context.delete(row)
                deleted = true
            }
        }
        if deleted { try? context.save() }
    }

    /// §24.9: entries older than 28 days are deleted at launch; younger are
    /// kept (they are a fallback, §24.10).
    @discardableResult
    func prune(now: Date) -> Int {
        var count = 0
        for row in all() where now.timeIntervalSince(row.computedAt) > TravelLegPlanner.keptFor {
            context.delete(row)
            count += 1
        }
        if count > 0 { try? context.save() }
        return count
    }
}
