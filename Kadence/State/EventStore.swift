//
//  EventStore.swift
//  Kadence
//
//  Every mutation goes through here so that every mutation is undoable and
//  named (interactions.md §9).
//
//  Two rules make the undo behaviour correct rather than approximately correct:
//
//  1. **Events are addressed by `id`, resolved at execution time.** Undoing a
//     delete cannot resurrect the deleted `@Model` instance, so the event comes
//     back as a new object carrying the same `id`. Nothing here captures an
//     `Event` reference inside an undo closure.
//  2. **Composite operations wrap the ordinary verbs.** `EventStore.transaction`
//     opens one named group; anything called inside it — including these same
//     methods — joins that group and undoes as a single step.
//

import Foundation
import SwiftData

@MainActor
struct EventStore {
    let context: ModelContext
    let undo: UndoStack

    // MARK: Composite operations

    /// Apply several mutations as ONE undo step.
    ///
    /// ```swift
    /// store.transaction("Resolve Conflict") {
    ///     store.move(training, by: 90 * 60)
    ///     store.toggleSkipped(gym)
    /// }
    /// ```
    ///
    /// Phase 2's conflict resolution and the routine engine's materialisation
    /// are both this shape: many changes, one ⌘Z.
    func transaction(_ name: String, _ body: () -> Void) {
        undo.perform(name) { _ in body() }
    }

    // MARK: Resolving

    private func event(_ id: UUID) -> Event? {
        var descriptor = FetchDescriptor<Event>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func edit(_ id: UUID, _ change: (Event) -> Void) {
        guard let event = event(id) else { return }
        change(event)
        try? context.save()
    }

    private func insert(_ snapshot: EventSnapshot) {
        context.insert(snapshot.makeEvent())
        try? context.save()
    }

    private func remove(_ id: UUID) {
        guard let event = event(id) else { return }
        context.delete(event)
        try? context.save()
    }

    // MARK: Create

    /// interactions.md §3 — a new event is 60 minutes and starts life with an
    /// inline title field.
    @discardableResult
    func create(at start: Date, duration: TimeInterval = 3600, title: String = "") -> Event {
        let event = Event(
            title: title,
            start: start,
            end: start.addingTimeInterval(duration),
            origin: .manual,
            sourceKey: .graphite)
        let snapshot = EventSnapshot(event)
        let id = event.id

        context.insert(event)
        try? context.save()
        undo.perform("New Event",
                     redo: { insert(snapshot) },
                     undo: { remove(id) })
        return event
    }

    /// An event created with no title is never persisted.
    func commitCreation(_ event: Event, title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            cancelCreation(event)
        } else {
            retitle(event, to: trimmed, named: "New Event")
        }
    }

    func cancelCreation(_ event: Event) {
        remove(event.id)
        // An event the user abandoned before naming never existed as far as they
        // are concerned, so its creation step goes with it.
        undo.discardLastStep()
    }

    // MARK: Mutate

    func delete(_ event: Event) {
        let snapshot = EventSnapshot(event)
        let id = event.id
        undo.perform("Delete Event",
                     redo: { remove(id) },
                     undo: { insert(snapshot) })
    }

    func move(_ event: Event, by offset: TimeInterval) {
        guard event.isMovable, offset != 0 else { return }
        let id = event.id
        let oldStart = event.start
        let oldEnd = event.end
        let newStart = oldStart.addingTimeInterval(offset)
        let newEnd = oldEnd.addingTimeInterval(offset)
        undo.perform("Move Event",
                     redo: { edit(id) { $0.start = newStart; $0.end = newEnd } },
                     undo: { edit(id) { $0.start = oldStart; $0.end = oldEnd } })
    }

    func move(_ event: Event, toStart newStart: Date) {
        guard event.isMovable else { return }
        move(event, by: newStart.timeIntervalSince(event.start))
    }

    /// The drag clamps rather than inverting; minimum resulting duration is 15 min.
    func resize(_ event: Event, newStart: Date? = nil, newEnd: Date? = nil) {
        guard event.isMovable else { return }
        let minimum: TimeInterval = 15 * 60
        let id = event.id
        let oldStart = event.start
        let oldEnd = event.end

        var start = oldStart
        var end = oldEnd
        if let newStart { start = min(newStart, oldEnd.addingTimeInterval(-minimum)) }
        if let newEnd { end = max(newEnd, start.addingTimeInterval(minimum)) }
        guard start != oldStart || end != oldEnd else { return }

        let finalStart = start
        let finalEnd = end
        undo.perform("Resize Event",
                     redo: { edit(id) { $0.start = finalStart; $0.end = finalEnd } },
                     undo: { edit(id) { $0.start = oldStart; $0.end = oldEnd } })
    }

    @discardableResult
    func duplicate(_ event: Event, at start: Date) -> Event {
        let copy = Event(
            title: event.title,
            start: start,
            end: start.addingTimeInterval(event.duration),
            isAllDay: event.isAllDay,
            origin: .manual,
            status: .scheduled,
            flexibility: event.flexibility,
            sourceKey: event.sourceKey,
            notes: event.notes)
        let snapshot = EventSnapshot(copy)
        let id = copy.id

        context.insert(copy)
        try? context.save()
        undo.perform("Duplicate Event",
                     redo: { insert(snapshot) },
                     undo: { remove(id) })
        return copy
    }

    func retitle(_ event: Event, to title: String, named name: String = "Rename Event") {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != event.title else { return }
        let id = event.id
        let old = event.title
        undo.perform(name,
                     redo: { edit(id) { $0.title = trimmed } },
                     undo: { edit(id) { $0.title = old } })
    }

    func setNotes(_ event: Event, to notes: String) {
        guard notes != event.notes else { return }
        let id = event.id
        let old = event.notes
        undo.perform("Edit Notes",
                     redo: { edit(id) { $0.notes = notes } },
                     undo: { edit(id) { $0.notes = old } })
    }

    func toggleDone(_ event: Event) {
        let id = event.id
        let old = event.status
        let new: EventStatus = old == .done ? .scheduled : .done
        undo.perform(old == .done ? "Mark Not Done" : "Mark Done",
                     redo: { edit(id) { $0.status = new } },
                     undo: { edit(id) { $0.status = old } })
    }

    /// Skipping puts the item back in the pool to be re-offered. It is never a
    /// failure state, which is why it is a sibling of done, not a worse one.
    func toggleSkipped(_ event: Event) {
        let id = event.id
        let old = event.status
        let new: EventStatus = old == .skipped ? .scheduled : .skipped
        undo.perform(old == .skipped ? "Unskip" : "Skip",
                     redo: { edit(id) { $0.status = new } },
                     undo: { edit(id) { $0.status = old } })
    }
}

// MARK: - Snapshot

/// Everything needed to bring an event back after a delete.
///
/// A `@Model` instance cannot be re-inserted once deleted, so undo recreates it.
/// The `id` is carried across, which is what keeps selection, travel-band lookup
/// and any other id-keyed reference working after an undo.
struct EventSnapshot: Sendable {
    var id: UUID
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var origin: EventOrigin
    var status: EventStatus
    var flexibility: Flexibility
    var sourceKey: SourceKey
    var sourceID: String?
    var externalID: String?
    var notes: String
    var isLocked: Bool
    var locationName: String?
    var locationAddress: String?

    @MainActor
    init(_ event: Event) {
        id = event.id
        title = event.title
        start = event.start
        end = event.end
        isAllDay = event.isAllDay
        origin = event.origin
        status = event.status
        flexibility = event.flexibility
        sourceKey = event.sourceKey
        sourceID = event.sourceID
        externalID = event.externalID
        notes = event.notes
        isLocked = event.isLocked
        locationName = event.location?.name
        locationAddress = event.location?.address
    }

    @MainActor
    func makeEvent() -> Event {
        let event = Event(
            title: title,
            start: start,
            end: end,
            isAllDay: isAllDay,
            origin: origin,
            status: status,
            flexibility: flexibility,
            sourceKey: sourceKey,
            location: locationName.map { Place(name: $0, address: locationAddress) },
            sourceID: sourceID,
            externalID: externalID,
            notes: notes,
            isLocked: isLocked)
        event.id = id
        return event
    }
}
