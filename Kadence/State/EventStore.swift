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

    /// Turn a draft into a persisted event.
    ///
    /// Returns nil — and persists nothing — when the draft has no usable title.
    /// interactions.md §3: "an event created with no title is never persisted —
    /// cancelling and committing an empty field both remove it." Because the
    /// draft was never in the store, discarding it needs no delete and leaves no
    /// undo step to press ⌘Z through.
    @discardableResult
    func commit(_ draft: EventDraft) -> Event? {
        guard draft.hasUsableTitle else { return nil }

        // The template is never inserted — it exists only to make the snapshot.
        // `UndoStack.perform` runs `redo` immediately, so inserting here as well
        // would create the event twice (with the same id, which is worse than it
        // sounds). Recording the insert as the redo is the single write.
        let template = Event(
            title: draft.trimmedTitle,
            start: draft.start,
            end: draft.end,
            origin: .manual,
            sourceKey: .graphite)
        let snapshot = EventSnapshot(template)

        undo.perform("New Event",
                     redo: { insert(snapshot) },
                     undo: { remove(snapshot.id) })
        return event(snapshot.id)
    }

    /// Insert an already-fully-formed event as part of an open transaction.
    ///
    /// Unlike `commit`, this takes no draft, does no title validation and
    /// forces no `origin`/`sourceKey` — the caller (currently only
    /// `RoutineEngine.materialize`) already knows every field. Called inside
    /// `store.transaction(...)`, so it joins that transaction's undo group
    /// instead of pushing a step of its own (see `UndoStack.perform`'s
    /// re-entrancy).
    @discardableResult
    func insertMaterialized(_ snapshot: EventSnapshot) -> Event? {
        undo.perform("Insert Event",
                     redo: { insert(snapshot) },
                     undo: { remove(snapshot.id) })
        return event(snapshot.id)
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
        // Same as `commit`: the redo closure performs the one insert.
        let snapshot = EventSnapshot(copy)

        undo.perform("Duplicate Event",
                     redo: { insert(snapshot) },
                     undo: { remove(snapshot.id) })
        // `self.` because the parameter is also called `event`.
        return self.event(snapshot.id) ?? copy
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

    /// Conflict resolution's `.skipToday` option (`ConflictEngine.swift`,
    /// `CalendarState.applyFocusedConflictOption`) — interactions.md §10.1's
    /// apply step is "write the previewed option to the store"; for a
    /// destination-less option (`ConflictOption.newStart`/`newEnd == nil`)
    /// that write is a status change, not a block move. Deliberately NOT
    /// `toggleSkipped`: that method flips between `.skipped` and
    /// `.scheduled`, and applying the same option twice (or applying it to
    /// an occurrence some other path had already skipped) must still land on
    /// `.skipped`, not silently un-skip it. A no-op — no undo step pushed —
    /// when the event is already `.skipped`, matching every other verb
    /// here's "changed nothing" guard (`move`'s `offset != 0`, `resize`'s
    /// `start != oldStart || end != oldEnd`, `retitle`'s `trimmed !=
    /// event.title`).
    func markSkipped(_ event: Event) {
        let id = event.id
        let old = event.status
        guard old != .skipped else { return }
        undo.perform("Skip",
                     redo: { edit(id) { $0.status = .skipped } },
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
