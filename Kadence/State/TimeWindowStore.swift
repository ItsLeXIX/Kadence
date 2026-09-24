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
//  Task P2-T22 adds `resize`, the piece both P2-T20 (render-only) and P2-T21
//  (select/move/delete) explicitly deferred: dragging a top or bottom edge,
//  using "the same size.blockResizeHandleHeight handles blocks use"
//  (components.md §13.3, verbatim). Same non-carryover as `move` above, for
//  the same reason: `RoutineBlockStore.resize`'s clamp
//  (`min(max(newStart,0), oldEnd-minimum)` / `max(min(newEnd,1440),
//  start+minimum)`) answers a bounded-single-day question this type was
//  never asked, so it is not reused. What *is* enforced, unchanged from that
//  model, is the 15-minute minimum duration — RoutineBlock's own floor
//  (interactions.md §4) — just computed on the wrapped/modular timeline the
//  same way `move` above already does its wraparound arithmetic: a candidate
//  edge is wrapped mod 1440 (never clamped into [0, 1440]), and if that
//  candidate would leave less than 15 minutes measured forward from the
//  *other*, fixed edge — wrapping past midnight exactly the way `spans(on:)`
//  itself measures a window's own span — the edge is pulled back to exactly
//  15 minutes instead of being allowed to collapse the window or invert it.
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

    // MARK: Resize

    /// Wraps a raw minute value into `[0, 1440)` — the same normalisation
    /// `move` above applies to each end after adding its delta.
    private func wrapMinutes(_ minutes: Int) -> Int {
        ((minutes % 1440) + 1440) % 1440
    }

    /// Minutes from `start` forward to `end`, wrapping past midnight if
    /// necessary — mirrors `spans(on:calendar:)`'s own branching exactly:
    /// `end > start` is the plain same-day case; otherwise the span wraps,
    /// and an *equal* `start`/`end` means a full 24-hour window (`spans(on:)`'s
    /// `else` branch adds the whole day, split across two pieces), never a
    /// zero-length one. Used only to decide whether a candidate edge would
    /// leave at least the 15-minute minimum against the other, fixed edge.
    private func modularDuration(from start: Int, to end: Int) -> Int {
        end > start ? end - start : (1440 - start) + end
    }

    /// Drag a top or bottom edge (components.md §13.3: "the same
    /// size.blockResizeHandleHeight handles blocks use"). Only one of
    /// `newStartMinutes`/`newEndMinutes` is ever supplied by a real drag (one
    /// handle moves one edge), but both are accepted independently, same
    /// shape as `RoutineBlockStore.resize`.
    ///
    /// Each candidate edge is wrapped mod 1440 rather than clamped into
    /// `[0, 1440]` — see this file's header for why `RoutineBlock`'s
    /// day-bounded clamp (G-013) does not transfer to a type that already
    /// supports wrapping past midnight. The only floor enforced is the same
    /// 15-minute minimum `RoutineBlockStore.resize` and `EventStore.resize`
    /// both use, computed with `modularDuration` above (forward, wrapping)
    /// rather than a plain subtraction, so a resize that would collapse or
    /// invert the window is pulled back to exactly 15 minutes instead —
    /// never clamped to a boundary this type does not have, and never left
    /// to invert into a near-24-hour window by accident.
    func resize(_ window: TimeWindow, newStartMinutes: Int? = nil, newEndMinutes: Int? = nil) {
        let minimum = 15
        let id = window.id
        let oldStart = window.startMinutes
        let oldEnd = window.endMinutes

        var start = oldStart
        var end = oldEnd

        if let newStartMinutes {
            let candidate = wrapMinutes(newStartMinutes)
            start = modularDuration(from: candidate, to: end) < minimum
                ? wrapMinutes(end - minimum)
                : candidate
        }
        if let newEndMinutes {
            let candidate = wrapMinutes(newEndMinutes)
            end = modularDuration(from: start, to: candidate) < minimum
                ? wrapMinutes(start + minimum)
                : candidate
        }
        guard start != oldStart || end != oldEnd else { return }

        let finalStart = start
        let finalEnd = end
        undo.perform("Resize Time Window",
                     redo: { edit(id) { $0.startMinutes = finalStart; $0.endMinutes = finalEnd } },
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

    // `create` (drag-to-create on empty windows-mode canvas) is still
    // deliberately NOT here — out of scope for task P2-T22 too, per its own
    // brief. Next task's job.
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
