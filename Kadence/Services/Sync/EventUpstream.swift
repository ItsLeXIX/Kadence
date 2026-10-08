//
//  EventUpstream.swift
//  Kadence
//
//  components.md §18.1 — an imported event's upstream fields belong to the
//  sync. This is the one place that writes them onto an `Event`. `status` is
//  local and is never written here (§18.1's one exception — a time change in
//  place resets it — is the applier's decision, not this function's).
//

import Foundation
import SwiftData

extension Event {
    /// Writes every upstream field of `upstream` (the fourteen §20.8.4 hashes)
    /// and the identity. Returns whether start or end changed.
    @discardableResult
    func applyUpstream(_ upstream: ExternalEvent) -> Bool {
        let timeChanged = start != upstream.start || end != upstream.end
        externalID = upstream.externalID
        title = upstream.title
        start = upstream.start
        end = upstream.end
        isAllDay = upstream.isAllDay
        if let name = upstream.location {
            if let place = location { if place.name != name { place.name = name } }
            else { location = Place(name: name) }
        } else if location != nil {
            location = nil
        }
        isOnline = upstream.isOnline
        courseCode = upstream.courseCode
        group = upstream.group
        lecturers = upstream.lecturers
        importKind = upstream.kind
        importedDescription = upstream.description
        link = upstream.link
        isCancelled = upstream.isCancelled
        return timeChanged
    }
}
