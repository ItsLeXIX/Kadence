//
//  TimeWindowStore.swift
//  Kadence
//
//  components.md §13.3 — "protected / low-energy / peak-focus regions are
//  editable" in the Routines window's Windows mode: creating, dragging,
//  resizing. Task P2-T20 built only the render-only layer (`GridLayers.swift`'s
//  `BackgroundWindowsLayer`/`WindowLabelsLayer`, generalized over
//  `TimeWindowRenderable`) — windows drew, but were not selectable or editable
//  in either mode. This task (P2-T21) is the first slice of the editable half:
//  select, whole-span move, and delete for an EXISTING `TimeWindow` row.
//  Resize (drag a top/bottom edge) and create (drag-to-create on empty
//  windows-mode canvas) are explicitly NOT here — a later task's job, same as
//  `RoutineBlockStore`'s own move/resize/delete landed one task ahead of its
//  own `create`.
//
//  Same shape as `RoutineBlockStore` (`Kadence/State/RoutineEngine.swift`,
//  task P2-T11/T12's pattern): a `@MainActor struct` holding `context:
//  ModelContext` and `undo: UndoStack`, resolving everything by `id` through
//  the context rather than closing over a captured `@Model` reference (the
//  same reason `RoutineBlockStore`'s own header gives — undoing a delete
//  cannot resurrect the deleted instance, so it comes back as a new object
//  carrying the same `id`), and one named `UndoStack` step per mutation.
//
//  What does NOT carry over from `RoutineBlockStore.move`: a `RoutineBlock`
//  is bounded to a single day (G-013) because it has no notion of "tomorrow";
//  a `TimeWindow` already does — its own doc comment and `spans(on:calendar:)`
//  both describe a window whose `endMinutes` can be less than `startMinutes`,
//  meaning it wraps past midnight (a 22:00–07:00 protected window is two
//  spans on consecutive days). So `move` here is a pure modular translation:
//  both `startMinutes` and `endMinutes` wrap independently mod 1440, no
//  clamping, and duration is preserved implicitly because the same delta is
//  applied to both ends. G-013's clamp is deliberately NOT reused — it would
//  be answering a question this type was never asked, since the model that
//  motivated G-013 (a bounded single-day field) does not apply here.
//

import Foundation
import SwiftData

@MainActor
struct TimeWindowStore {
    let context: ModelContext
    let undo: UndoStack

    // MARK: Resolving

    private func window(_ id: UUID) -> TimeWindow? {
        var descriptor = FetchDescriptor<TimeWindow>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func edit(_ id: UUID, _ change: (TimeWindow) -> Void) {
        guard let window = window(id) else { return }
        change(window)
        try? context.save()
    }

    // MARK: Move

    /// Whole-span drag: both ends translate by the same `delta`, wrapping
    /// independently mod 1440 rather than clamping — a `TimeWindow` already
    /// supports spanning midnight (this type's own header, and
    /// `spans(on:calendar:)`), so a drag that pushes either end past 00:00 or
    /// 24:00 just continues on the other side of it, same as the span the
    /// window already describes when `endMinutes < startMinutes`. Duration is
    /// preserved implicitly: both ends move by the identical delta.
    func move(_ window: TimeWindow, byDeltaMinutes delta: Int) {
        guard delta != 0 else { return }
        let id = window.id
        let oldStart = window.startMinutes
        let oldEnd = window.endMinutes
        let newStart = ((oldStart + delta) % 1440 + 1440) % 1440
        let newEnd = ((oldEnd + delta) % 1440 + 1440) % 1440

        undo.perform("Move Time Window",
                     redo: { edit(id) { $0.startMinutes = newStart; $0.endMinutes = newEnd } },
                     undo: { edit(id) { $0.startMinutes = oldStart; $0.endMinutes = oldEnd } })
    }

    // MARK: Delete

    /// Simpler than `RoutineBlockStore.delete`: a `TimeWindow` has no parent
    /// array membership to maintain (it is not held in any other model's
    /// array the way a `RoutineBlock` is held in `RoutineTemplate.blocks`),
    /// so this just inserts/deletes the row itself. Every field is snapshotted
    /// so undo reconstructs the row exactly, including `kind` and `weekdays`.
    func delete(_ window: TimeWindow) {
        let snapshot = TimeWindowRestoreSnapshot(window)
        let id = window.id
        undo.perform("Delete Time Window",
                     redo: { removeWindow(id) },
                     undo: { insertWindow(snapshot) })
    }

    private func removeWindow(_ id: UUID) {
        guard let window = window(id) else { return }
        context.delete(window)
        try? context.save()
    }

    private func insertWindow(_ snapshot: TimeWindowRestoreSnapshot) {
        context.insert(snapshot.makeWindow())
        try? context.save()
    }

    // Resize and create are deliberately NOT here — out of scope for this
    // task, per its own brief. Next task's job.
}

// MARK: - Snapshot (delete/undo)

/// Everything needed to bring a `TimeWindow` back after a delete — same shape
/// and same reason as `RoutineBlockRestoreSnapshot`: a `@Model` instance
/// cannot be re-inserted once deleted, so undo recreates one carrying the
/// same `id` and every other field, including `kind`, `label` and `weekdays`.
struct TimeWindowRestoreSnapshot: Sendable {
    var id: UUID
    var weekdays: Set<Int>
    var startMinutes: Int
    var endMinutes: Int
    var kind: TimeWindowKind
    var label: String

    @MainActor
    init(_ window: TimeWindow) {
        id = window.id
        weekdays = window.weekdays
        startMinutes = window.startMinutes
        endMinutes = window.endMinutes
        kind = window.kind
        label = window.label
    }

    @MainActor
    func makeWindow() -> TimeWindow {
        let window = TimeWindow(
            weekdays: weekdays, startMinutes: startMinutes, endMinutes: endMinutes,
            kind: kind, label: label)
        window.id = id
        return window
    }
}
