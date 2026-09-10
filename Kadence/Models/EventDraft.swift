//
//  EventDraft.swift
//  Kadence
//
//  A new event being typed. interactions.md §3.
//
//  Deliberately not an `Event`: it is laid out and drawn like a block so the
//  user sees where it will land, but it holds no SwiftData identity and never
//  touches the store. Only `EventStore.commit(_:)` turns one into an `Event`,
//  and only when it has a title.
//

import Foundation

struct EventDraft: Identifiable, Equatable, Sendable {
    let id: UUID
    var start: Date
    var end: Date
    var title: String

    init(id: UUID = UUID(), start: Date, end: Date, title: String = "") {
        self.id = id
        self.start = start
        self.end = end
        self.title = title
    }

    var duration: TimeInterval { end.timeIntervalSince(start) }

    /// A draft with nothing but whitespace in it is not a thing the user made.
    var hasUsableTitle: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var trimmedTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
