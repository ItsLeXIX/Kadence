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

    /// Insert materialised routine instances **without** an undo step.
    ///
    /// The one deliberate exception to this file's "every mutation is
    /// undoable" rule, and the only caller is the background materialisation
    /// pass (`RoutineMaterialization.run`, task P2-T40). The triggers in
    /// components.md §13.6.5 (launch, a visible-range change, an edit) are
    /// the app keeping the calendar in step with the routine, not a user
    /// action. Recording them would put `Undo Materialize …` on top of the
    /// user's own last step, so one `⌘Z` would remove a routine's instances
    /// instead of undoing what the user just did. One save for the batch.
    func insertUnrecorded(_ snapshots: [EventSnapshot]) {
        guard !snapshots.isEmpty else { return }
        for snapshot in snapshots { context.insert(snapshot.makeEvent()) }
        try? context.save()
    }

    // MARK: Mutate

    /// `⌫` (interactions.md §5). For a materialised routine instance this
    /// also leaves a tombstone (components.md §13.7.4, task P2-T41), in the
    /// SAME step, so one `⌘Z` restores the instance and removes the
    /// tombstone together. Undo replays changes in reverse, so the tombstone
    /// goes first and the event comes back second.
    func delete(_ event: Event) {
        let snapshot = EventSnapshot(event)
        let id = event.id
        let pair = RoutineTombstones.pair(of: event)
        undo.perform("Delete Event") { group in
            group.perform(redo: { remove(id) }, undo: { insert(snapshot) })
            if let pair {
                group.perform(
                    redo: { RoutineTombstones.insert(pair, in: context) },
                    undo: { RoutineTombstones.remove(pair, in: context) })
            }
        }
    }

    // MARK: Detachment (components.md §13.7.1, task P2-T43)

    /// The link before and after an edit to one of the four template-owned
    /// fields (start, end, title, flexibility). A materialised instance that
    /// is `.linked` becomes `.detached`; anything else keeps its link
    /// (a `.released` instance is an ordinary event now, and a non-routine
    /// event has no template). `move`, `resize`, `snooze`, `retitle` and
    /// `setFlexibility` record both values in their own step, so `⌘Z` on the
    /// edit also re-links the instance. Done/skipped, notes and lock never
    /// call this: status is a fact about a day, not a divergence.
    static func linkChange(forTemplateFieldEditOf event: Event) -> (old: RoutineLink, new: RoutineLink) {
        let old = event.routineLink
        let isInstance = RoutineTombstones.pair(of: event) != nil
        return (old, isInstance && old == .linked ? .detached : old)
    }

    /// Change flexibility (a template-owned field, so it detaches). No
    /// main-grid control calls this yet; it exists so §13.7.1's table has
    /// one write per row and the rule is tested.
    func setFlexibility(_ event: Event, to new: Flexibility) {
        let id = event.id
        let old = event.flexibility
        guard new != old else { return }
        let (oldLink, newLink) = Self.linkChange(forTemplateFieldEditOf: event)
        undo.perform("Set Flexibility",
                     redo: { edit(id) { $0.flexibility = new; $0.routineLink = newLink } },
                     undo: { edit(id) { $0.flexibility = old; $0.routineLink = oldLink } })
    }

    /// `Revert to routine` (§13.4, §13.7.3 last paragraph): writes the
    /// template's **current** values into the four fields and links the
    /// instance again, leaving `status` alone. One step, named
    /// `Revert Instance to Routine`. Inside a larger step (Re-sync, P2-T44)
    /// it joins that step instead.
    func revertToRoutine(_ event: Event, values: RoutineValues) {
        let id = event.id
        let oldValues = RoutineValues(event)
        let oldLink = event.routineLink
        guard oldValues != values || oldLink != .linked else { return }
        undo.perform("Revert Instance to Routine",
                     redo: { edit(id) { write(values, to: $0); $0.routineLink = .linked } },
                     undo: { edit(id) { write(oldValues, to: $0); $0.routineLink = oldLink } })
    }

    /// §13.6.4: a detached instance kept by a withdrawal "stops being
    /// detached". Recorded, so it joins the withdrawal's step.
    func release(_ id: UUID) {
        guard let event = event(id), event.routineLink != .released else { return }
        let old = event.routineLink
        undo.perform("Release Routine Instance",
                     redo: { edit(id) { $0.routineLink = .released } },
                     undo: { edit(id) { $0.routineLink = old } })
    }

    /// The same with no undo step, for the background pass. One save.
    func releaseUnrecorded(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        for id in ids { event(id)?.routineLink = .released }
        try? context.save()
    }

    // MARK: Routine instances (components.md §13.6.3 / §13.6.4, task P2-T41)

    /// The four template-owned fields (§13.7.1) of a routine instance.
    /// `status` is deliberately not here: "An update carries the event's own
    /// `status` forward unchanged" (§13.6.3).
    struct RoutineValues: Equatable, Sendable {
        var title: String
        var start: Date
        var end: Date
        var flexibility: Flexibility

        @MainActor
        init(_ event: Event) {
            title = event.title
            start = event.start
            end = event.end
            flexibility = event.flexibility
        }

        init(title: String, start: Date, end: Date, flexibility: Flexibility) {
            self.title = title
            self.start = start
            self.end = end
            self.flexibility = flexibility
        }
    }

    private func write(_ values: RoutineValues, to event: Event) {
        event.title = values.title
        event.start = values.start
        event.end = values.end
        event.flexibility = values.flexibility
    }

    /// Re-materialisation's update, as a recorded change. It joins the step
    /// that is open (it is only called inside one), so its own name is never
    /// shown.
    func updateRoutineInstance(_ id: UUID, to values: RoutineValues) {
        guard let event = event(id) else { return }
        let old = RoutineValues(event)
        guard old != values else { return }
        undo.perform("Update Routine Instance",
                     redo: { edit(id) { write(values, to: $0) } },
                     undo: { edit(id) { write(old, to: $0) } })
    }

    /// The same update with no undo step, for the background pass (see
    /// `insertUnrecorded`). One save for the batch.
    func updateRoutineInstancesUnrecorded(_ updates: [(id: UUID, values: RoutineValues)]) {
        guard !updates.isEmpty else { return }
        for update in updates {
            if let event = event(update.id) { write(update.values, to: event) }
        }
        try? context.save()
    }

    /// §13.6.4 withdrawal: the template stopped producing this instance's
    /// pair. Unlike `delete`, it leaves **no tombstone**: the user didn't
    /// delete this day, the routine stopped containing it. Recorded, so it
    /// joins the step that caused the withdrawal (`Remove Saturday from
    /// Routine`, `Delete Routine Block`, a time-window edit).
    func withdraw(_ id: UUID) {
        guard let event = event(id) else { return }
        let snapshot = EventSnapshot(event)
        undo.perform("Withdraw Routine Instance",
                     redo: { remove(id) },
                     undo: { insert(snapshot) })
    }

    /// Withdrawal with no undo step, for the background pass. One save.
    func withdrawUnrecorded(_ ids: [UUID]) {
        guard !ids.isEmpty else { return }
        for id in ids {
            if let event = event(id) { context.delete(event) }
        }
        try? context.save()
    }

    func move(_ event: Event, by offset: TimeInterval) {
        guard event.isMovable, offset != 0 else { return }
        let id = event.id
        let oldStart = event.start
        let oldEnd = event.end
        let newStart = oldStart.addingTimeInterval(offset)
        let newEnd = oldEnd.addingTimeInterval(offset)
        let (oldLink, newLink) = Self.linkChange(forTemplateFieldEditOf: event)
        undo.perform("Move Event",
                     redo: { edit(id) { $0.start = newStart; $0.end = newEnd; $0.routineLink = newLink } },
                     undo: { edit(id) { $0.start = oldStart; $0.end = oldEnd; $0.routineLink = oldLink } })
    }

    func move(_ event: Event, toStart newStart: Date) {
        guard event.isMovable else { return }
        move(event, by: newStart.timeIntervalSince(event.start))
    }

    /// components.md §16's snooze confirmation needs *some* destination time
    /// to show, but `DECISIONS.md` 2026-09-10 bars real snooze scheduling
    /// logic until Phase 4 ("the design exemption covers surfaces, not the
    /// services behind them"). `snoozeOffset` is a deliberate, narrow
    /// placeholder — a single fixed, well-commented constant, not an invented
    /// design token — in the same spirit as `markSkipped`'s `.skipToday`
    /// exclusion (see `design/GAPS.md`'s most recent entry at the time this
    /// was written, G-015, for the pattern this follows). **15 minutes**:
    /// the smallest common "snooze" increment (the same unit most calendar
    /// and reminder apps default a snooze to), and it reads cleanly against
    /// any `HH:mm` clock with no rounding. Phase 4 replaces this outright
    /// with real scheduling — see `design/GAPS.md`'s new entry for this task.
    static let snoozeOffset: TimeInterval = 15 * 60

    /// Named separately from `move` (its own step, "Snooze") so the Edit menu
    /// and the popover's result row both read correctly, even though the
    /// mechanics are the same shift-by-offset. Returns the new start so the
    /// caller (the menu bar popover) can compose "Moved to HH:mm" without a
    /// second read of the `@Model` after the fact.
    @discardableResult
    func snooze(_ event: Event) -> Date {
        guard event.isMovable else { return event.start }
        let id = event.id
        let oldStart = event.start
        let oldEnd = event.end
        let newStart = oldStart.addingTimeInterval(Self.snoozeOffset)
        let newEnd = oldEnd.addingTimeInterval(Self.snoozeOffset)
        // A snooze moves the start, a template-owned field (§13.7.1).
        let (oldLink, newLink) = Self.linkChange(forTemplateFieldEditOf: event)
        undo.perform("Snooze",
                     redo: { edit(id) { $0.start = newStart; $0.end = newEnd; $0.routineLink = newLink } },
                     undo: { edit(id) { $0.start = oldStart; $0.end = oldEnd; $0.routineLink = oldLink } })
        return newStart
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
        let (oldLink, newLink) = Self.linkChange(forTemplateFieldEditOf: event)
        undo.perform("Resize Event",
                     redo: { edit(id) { $0.start = finalStart; $0.end = finalEnd; $0.routineLink = newLink } },
                     undo: { edit(id) { $0.start = oldStart; $0.end = oldEnd; $0.routineLink = oldLink } })
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
        let (oldLink, newLink) = Self.linkChange(forTemplateFieldEditOf: event)
        undo.perform(name,
                     redo: { edit(id) { $0.title = trimmed; $0.routineLink = newLink } },
                     undo: { edit(id) { $0.title = old; $0.routineLink = oldLink } })
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
    var routineLink: RoutineLink
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
        routineLink = event.routineLink
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
        event.routineLink = routineLink
        return event
    }
}
