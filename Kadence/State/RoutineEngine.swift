//
//  RoutineEngine.swift
//  Kadence
//
//  Turns a `RoutineTemplate` into ordinary `Event`s on the calendar
//  (BRIEF-PRODUCT.md; components.md §13). This is the data-layer
//  materialisation pass:
//
//  - No TimeWindow editor, no menu bar extra, no snooze (layouts.md §8,
//    interactions.md §15, §16).
//  - No conflict detection (components.md §14).
//  - No detachment tracking or re-sync (components.md §13.4, interactions.md
//    §11.2). This engine never touches a materialized event once it exists —
//    it only ever checks whether one is already there and, if so, leaves it
//    alone. Recognising that an existing event has since been hand-edited (so
//    that re-sync can offer to overwrite it) needs the main-grid edit-command
//    path wired up first, which is a separate follow-up task.
//
//  Each materialized event gets a `(sourceID, externalID)` pair —
//  `(template.id.uuidString, "<block.id>#<yyyy-MM-dd>")` — which is exactly
//  the identity `Event.swift`'s doc comment describes as "stable across
//  re-sync, so importing twice updates instead of duplicating". Here that
//  means: calling `materialize` again over an overlapping range creates
//  nothing new for a date/block pair that already exists.
//
//  `RoutineBlockStore` below (tasks P2-T11, P2-T12) is the Routines-window
//  sibling of `EventStore`: move, resize, delete AND (as of P2-T12) create for
//  `RoutineBlock`s, undoable and named, per interactions.md §11.1 ("Creating,
//  moving and resizing routine blocks uses §3 and §4 unchanged ... `⌫`
//  deletes. `⌘Z` undoes, with names"). Not a UI type — `RoutinesWindow.swift`
//  is what calls it from a drag gesture, a double-click and a key handler.
//  The flexibility control remains out of scope (see `RoutinesWindow.swift`'s
//  own header).
//

import Foundation
import SwiftData

@MainActor
enum RoutineEngine {

    /// Create one `Event` per `(active weekday × block)` pair in `range`,
    /// skipping any pair that already has a materialized event. Everything
    /// this call does — every block, every date — is one named, undoable step.
    ///
    /// - Returns: the number of *new* events created. Re-running with the same
    ///   template and range returns 0 and leaves the store unchanged.
    @discardableResult
    static func materialize(
        template: RoutineTemplate,
        into range: DateInterval,
        store: EventStore,
        calendar: Calendar = .current
    ) -> Int {
        guard !template.blocks.isEmpty, !template.activeWeekdays.isEmpty else { return 0 }

        let context = store.context
        let sourceID = template.id.uuidString
        var createdCount = 0

        store.transaction("Materialize \(template.name)") {
            var day = calendar.startOfDay(for: range.start)

            while day < range.end {
                if template.activeWeekdays.contains(calendar.component(.weekday, from: day)) {
                    let key = dayKey(day, calendar: calendar)

                    for block in template.blocks {
                        let externalID = "\(block.id.uuidString)#\(key)"

                        // Idempotence: a pair that already exists is left
                        // alone rather than duplicated or overwritten. Once a
                        // hand-edit can be told apart from an untouched
                        // instance (§13.4, out of scope here), this is where
                        // re-sync would instead offer to replace it.
                        guard !eventExists(sourceID: sourceID, externalID: externalID, in: context) else {
                            continue
                        }
                        guard let blockStart = calendar.date(
                            byAdding: .minute, value: block.startMinutes, to: day)
                        else { continue }

                        let event = Event(
                            title: block.title,
                            start: blockStart,
                            end: blockStart.addingTimeInterval(block.duration),
                            origin: .routine,
                            flexibility: block.flexibility,
                            sourceKey: template.sourceKey,
                            sourceID: sourceID,
                            externalID: externalID)
                        store.insertMaterialized(EventSnapshot(event))
                        createdCount += 1
                    }
                }

                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }

        return createdCount
    }

    // MARK: - Identity

    private static func eventExists(sourceID: String, externalID: String, in context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<Event>(predicate: #Predicate { event in
            event.sourceID == sourceID && event.externalID == externalID
        })
        descriptor.fetchLimit = 1
        return !((try? context.fetch(descriptor)) ?? []).isEmpty
    }

    /// `yyyy-MM-dd` of `date`, read through `calendar`'s own components rather
    /// than a `DateFormatter`, so the key matches exactly the day this engine
    /// iterated to, with no locale or timezone formatting to second-guess.
    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}

// MARK: - Editing (tasks P2-T11, P2-T12)

/// Move, resize, delete AND create for `RoutineBlock`s. Same two rules as
/// `EventStore.swift`'s header, for the same reasons:
///
/// 1. **Blocks are addressed by `id`, resolved at execution time.** Undoing a
///    delete cannot resurrect the deleted `@Model` instance, so the block
///    comes back as a new object carrying the same `id`. Nothing here
///    captures a `RoutineBlock` reference inside an undo closure.
/// 2. Every mutation is one named `UndoStack` step, named exactly as
///    interactions.md §11.1 prescribes ("Move Routine Block" / "Resize
///    Routine Block" / "Delete Routine Block" / "Create Routine Block" —
///    `UndoStack` itself prepends "Undo "/"Redo ").
///
/// The one thing that does NOT carry over from `EventStore`: a `RoutineBlock`
/// has no `Date` of its own (`RoutineTemplate.swift`'s own doc comment on
/// `startMinutes` — it is a time-of-day offset applied uniformly across every
/// active weekday, not an instant). So where `EventStore.move`/`resize` take
/// `Date`s, these take minutes-since-midnight, and clamp to a single day
/// (0...1440) rather than letting a drag roll a block over into "tomorrow",
/// which has no meaning for a template. `RoutinesWindow.swift`'s drag gesture
/// does the Date-to-minutes conversion (via `RoutineWeekLayout.referenceDayStart`)
/// before calling in, exactly the inverse of what `RoutineWeekLayout.layoutItems`
/// already does to turn `startMinutes` into a `Date` for the layout engine.
///
/// SPEC-GAP (design/GAPS.md G-013): interactions.md §11.1 says §3/§4 apply
/// "unchanged", but those sections assume a freely-floating `Date` — they
/// never say what happens when a drag would push a block's start before
/// 00:00 or its end past 24:00 on its own day, which a bounded `startMinutes`
/// field can hit and an `Event` never could. Clamped at the day boundary
/// (same shape as the existing 15-minute-minimum-duration clamp already in
/// §4) rather than left undefined, pending a real answer. `create` below
/// (task P2-T12) reuses this exact same clamp for the same reason — a
/// double-click or drag near either end of the day is just as capable of
/// producing an out-of-range start/end as a move/resize drag is, and G-013
/// is not reopened or re-litigated for it, just applied consistently.
@MainActor
struct RoutineBlockStore {
    let context: ModelContext
    let undo: UndoStack

    // MARK: Resolving

    private func block(_ id: UUID) -> RoutineBlock? {
        var descriptor = FetchDescriptor<RoutineBlock>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func template(_ id: UUID) -> RoutineTemplate? {
        var descriptor = FetchDescriptor<RoutineTemplate>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func edit(_ id: UUID, _ change: (RoutineBlock) -> Void) {
        guard let block = block(id) else { return }
        change(block)
        try? context.save()
    }

    // MARK: Move

    func move(_ block: RoutineBlock, toStartMinutes newStart: Int) {
        let durationMinutes = max(1, Int(block.duration / 60))
        let clamped = min(max(newStart, 0), 1440 - durationMinutes)
        guard clamped != block.startMinutes else { return }
        let id = block.id
        let old = block.startMinutes
        undo.perform("Move Routine Block",
                     redo: { edit(id) { $0.startMinutes = clamped } },
                     undo: { edit(id) { $0.startMinutes = old } })
    }

    // MARK: Resize

    /// The drag clamps rather than inverting; minimum resulting duration is
    /// 15 minutes, same as `EventStore.resize` (interactions.md §4).
    func resize(_ block: RoutineBlock, newStartMinutes: Int? = nil, newEndMinutes: Int? = nil) {
        let minimum = 15
        let id = block.id
        let oldStart = block.startMinutes
        let oldEnd = oldStart + Int(block.duration / 60)

        var start = oldStart
        var end = oldEnd
        if let newStartMinutes { start = min(max(newStartMinutes, 0), oldEnd - minimum) }
        if let newEndMinutes { end = max(min(newEndMinutes, 1440), start + minimum) }
        guard start != oldStart || end != oldEnd else { return }

        let finalStart = start
        let finalDuration = TimeInterval((end - start) * 60)
        let oldDuration = block.duration
        undo.perform("Resize Routine Block",
                     redo: { edit(id) { $0.startMinutes = finalStart; $0.duration = finalDuration } },
                     undo: { edit(id) { $0.startMinutes = oldStart; $0.duration = oldDuration } })
    }

    // MARK: Delete

    /// Removes `block` from `template.blocks` (SwiftData's cascade rule only
    /// fires when the *template* is deleted, not when one block is dropped
    /// from its array, so both the array membership and the row itself are
    /// cleaned up here). `⌘Z` reinserts a fresh `RoutineBlock` carrying the
    /// same `id` and appends it back onto the same template.
    func delete(_ block: RoutineBlock, from template: RoutineTemplate) {
        let snapshot = RoutineBlockRestoreSnapshot(block)
        let id = block.id
        let templateID = template.id
        undo.perform("Delete Routine Block",
                     redo: { removeBlock(id, templateID: templateID) },
                     undo: { insertBlock(snapshot, templateID: templateID) })
    }

    private func removeBlock(_ id: UUID, templateID: UUID) {
        guard let template = template(templateID) else { return }
        template.blocks.removeAll { $0.id == id }
        if let block = block(id) {
            context.delete(block)
        }
        try? context.save()
    }

    private func insertBlock(_ snapshot: RoutineBlockRestoreSnapshot, templateID: UUID) {
        guard let template = template(templateID) else { return }
        let block = snapshot.makeBlock()
        context.insert(block)
        template.blocks.append(block)
        try? context.save()
    }

    // MARK: Create (task P2-T12)

    /// Turns a draft (title + minutes-since-midnight + duration) into a
    /// persisted `RoutineBlock` appended to `template.blocks` — the "the other
    /// half" of interactions.md §11.1 this task adds. §11.1 points back at §3
    /// unchanged, and §3's own rule is enforced here exactly the way
    /// `EventStore.commit` already enforces it for `Event`: "an event created
    /// with no title is never persisted — cancelling and committing an empty
    /// field both remove it." A blank (or whitespace-only) `title` persists
    /// nothing and pushes no undo step — there is nothing to press `⌘Z`
    /// through, because nothing was ever written.
    ///
    /// Reversed shape of `delete`'s own undo, reusing the same
    /// `RoutineBlockRestoreSnapshot`/`insertBlock`/`removeBlock` plumbing:
    /// `redo` inserts the new block, `undo` removes it by `id`.
    ///
    /// `startMinutes`/`duration` clamp to the same `0...1440` day-boundary
    /// shape `move`/`resize` already use (this type's own header, G-013) —
    /// reused for consistency, not a new answer to that gap. The 15-minute
    /// minimum duration is interactions.md §3's own rule for a drag-created
    /// block ("drag on empty grid creates a block of the dragged duration,
    /// minimum 15 minutes"), applied here the same way `resize`'s minimum
    /// already applies it.
    @discardableResult
    func create(title: String, startMinutes: Int, duration: TimeInterval, in template: RoutineTemplate) -> RoutineBlock? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let durationMinutes = max(15, Int(duration / 60))
        let clampedStart = min(max(startMinutes, 0), 1440 - durationMinutes)
        let clampedDurationMinutes = min(durationMinutes, 1440 - clampedStart)

        let id = UUID()
        let templateID = template.id
        let snapshot = RoutineBlockRestoreSnapshot(
            id: id, title: trimmed, startMinutes: clampedStart,
            duration: TimeInterval(clampedDurationMinutes * 60))

        undo.perform("Create Routine Block",
                     redo: { insertBlock(snapshot, templateID: templateID) },
                     undo: { removeBlock(id, templateID: templateID) })
        return block(id)
    }
}

// MARK: - Snapshot (delete/undo)

/// Everything needed to bring a `RoutineBlock` back after a delete — the same
/// shape as `EventStore.swift`'s `EventSnapshot`, and for the same reason: a
/// `@Model` instance cannot be re-inserted once deleted, so undo recreates one
/// carrying the same `id`.
///
/// Also (task P2-T12) what `create`'s own `redo` inserts: a brand-new block
/// has never had a `@Model` instance to snapshot *from*, but it needs the
/// exact same "values in, `insertBlock` builds the `@Model`" shape `delete`'s
/// undo already established, so this plain memberwise init supplies it
/// directly rather than adding a second, parallel insert path.
struct RoutineBlockRestoreSnapshot: Sendable {
    var id: UUID
    var title: String
    var startMinutes: Int
    var duration: TimeInterval
    var flexibility: Flexibility
    var shiftableMinutes: Int?
    var priority: Int

    init(
        id: UUID,
        title: String,
        startMinutes: Int,
        duration: TimeInterval,
        flexibility: Flexibility = .fixed,
        shiftableMinutes: Int? = nil,
        priority: Int = 0
    ) {
        self.id = id
        self.title = title
        self.startMinutes = startMinutes
        self.duration = duration
        self.flexibility = flexibility
        self.shiftableMinutes = shiftableMinutes
        self.priority = priority
    }

    @MainActor
    init(_ block: RoutineBlock) {
        id = block.id
        title = block.title
        startMinutes = block.startMinutes
        duration = block.duration
        flexibility = block.flexibility
        shiftableMinutes = block.shiftableMinutes
        priority = block.priority
    }

    @MainActor
    func makeBlock() -> RoutineBlock {
        let block = RoutineBlock(
            title: title, startMinutes: startMinutes, duration: duration,
            flexibility: flexibility, shiftableMinutes: shiftableMinutes, priority: priority)
        block.id = id
        return block
    }
}
