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
//  Task P2-T23 adds `create`, the half components.md §13.3 states in as many
//  words and that P2-T20/T21/T22 all deferred by name: "Creating one: drag on
//  empty canvas, then pick the kind from the inspector." This task builds
//  only the drag half — `create` below always inserts a `.protected`-kind,
//  empty-label row over exactly the weekday set its caller supplies (in
//  practice, `RoutinesWindow.swift`'s create-drag always passes the single
//  weekday of the column it ran in). The inspector's kind picker, weekday-set
//  editing, and label editing — the "then pick the kind from the inspector"
//  half of that same sentence — are still explicitly NOT here; a future
//  task's job, same deferral shape T20/T21/T22 each used for their own
//  remainder.
//
//  Task P2-T24 is that future task: `setKind`, `setWeekdays`, `setLabel`
//  below close the sentence out. Same shape as every method above — resolve
//  by `id` through `edit(id) { }`, one named `UndoStack` step per call,
//  guarded against no-op edits so an unchanged Picker selection or an
//  unedited text field never leaves an empty step on the stack.
//  `setWeekdays` additionally refuses (silently, like `create`'s own
//  empty-`weekdays` guard) to commit an empty set — a `TimeWindow` with no
//  weekdays would never render or match on any day, which is not what
//  toggling off the last checked box should mean. `setLabel` is committed
//  once per edit (on `Return` or focus loss), not once per keystroke — see
//  `RoutinesWindow.swift`'s `TimeWindowInspectorView` for the field itself,
//  and DEVIATIONS.md for why this granularity was chosen.
//

import Foundation
import SwiftData

@MainActor
struct TimeWindowStore {
    let context: ModelContext
    let undo: UndoStack
    /// P2-T41: "today" for components.md §13.6.4's withdrawal. A closure,
    /// read at the moment of the edit, so tests can pin it.
    var now: () -> Date = { Date() }
    var calendar: Calendar = .current

    /// One named step for an edit that can change what a protected window
    /// covers. §13.6.4: when an edit makes §13.6.1 start refusing a pair it
    /// previously created (a window moved, widened, re-kinded to
    /// `.protected`, given another weekday, or created over an instance),
    /// that pair's future, non-detached instances are withdrawn **in the same
    /// step**, so one `⌘Z` restores the window and the instances together.
    /// An edit that stops a refusal withdraws nothing; the background pass
    /// creates the freed pairs.
    private func record(_ name: String, redo: @escaping () -> Void, undo inverse: @escaping () -> Void) {
        undo.perform(name) { group in
            group.perform(redo: redo, undo: inverse)
            // P2-F11: withdraw, then rejoin what this edit made the
            // template produce again (§13.6.3, a window that stops refusing).
            RoutineEngine.reconcileAll(store: EventStore(context: context, undo: undo),
                                       today: now(), calendar: calendar)
        }
    }

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

        record("Move Time Window",
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
        record("Resize Time Window",
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
        record("Delete Time Window",
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

    // MARK: Create

    /// Drag-to-create on empty windows-mode canvas (components.md §13.3:
    /// "Creating one: drag on empty canvas, then pick the kind from the
    /// inspector."). This method is only the drag half of that sentence — the
    /// caller decides `weekdays`/`startMinutes`/`endMinutes` (in practice,
    /// `RoutinesWindow.swift`'s create-drag always passes a single-element
    /// `weekdays` set, the column the drag ran in) and leaves `kind`/`label`
    /// at this method's own defaults, which are `TimeWindow.swift`'s own
    /// model defaults (`.protected`, `""`) — "pick the kind from the
    /// inspector" is next task's job, not this one's.
    ///
    /// The 15-minute minimum duration is enforced here too, defensively —
    /// `RoutinesWindow.swift`'s create-drag already floors it before calling
    /// in (the same `max(upper.timeIntervalSince(lower), 15*60)` shape
    /// `commitDraft` uses for a routine block), but this method does not
    /// trust that and floors again itself, the same belt-and-braces shape
    /// `RoutineBlockStore.create` already uses for its own 15-minute floor.
    /// Computed with `wrapMinutes`/`modularDuration` above — the same
    /// wrap-aware (never clamped into `[0, 1440]`) floor `resize` already
    /// applies, for the same reason given in this file's header: a
    /// `TimeWindow` already supports a span past midnight, so a candidate
    /// `endMinutes` that is less than 15 minutes forward of `startMinutes`
    /// (wrapping, exactly as `spans(on:)` measures) is pushed forward to
    /// exactly `startMinutes + 15`, wrapped, rather than collapsed or left to
    /// invert.
    ///
    /// Reversed shape of `delete`'s own undo, reusing the same
    /// `TimeWindowRestoreSnapshot`/`insertWindow`/`removeWindow` plumbing:
    /// `redo` inserts the new window, `undo` removes it by `id` — mirrors
    /// `RoutineBlockStore.create`'s own reversed-`delete` shape exactly
    /// (`Kadence/State/RoutineEngine.swift`).
    ///
    /// Returns the created window (or `nil` on failure) so the caller can
    /// select it immediately, matching `RoutineBlockStore.create`'s optional-
    /// return convention that `RoutinesWindow.commitDraft()` already relies on
    /// for `RoutineBlock`. The only failure case here is an empty `weekdays`
    /// set — unlike `RoutineBlockStore.create`, there is no title to be blank,
    /// since an empty label is this task's own explicit default, not a reason
    /// to refuse the create.
    @discardableResult
    func create(
        weekdays: Set<Int>, startMinutes: Int, endMinutes: Int,
        kind: TimeWindowKind = .protected, label: String = ""
    ) -> TimeWindow? {
        guard !weekdays.isEmpty else { return nil }

        let minimum = 15
        let start = wrapMinutes(startMinutes)
        let candidateEnd = wrapMinutes(endMinutes)
        let end = modularDuration(from: start, to: candidateEnd) < minimum
            ? wrapMinutes(start + minimum)
            : candidateEnd

        let id = UUID()
        let snapshot = TimeWindowRestoreSnapshot(
            id: id, weekdays: weekdays, startMinutes: start, endMinutes: end,
            kind: kind, label: label)

        record("Create Time Window",
                     redo: { insertWindow(snapshot) },
                     undo: { removeWindow(id) })
        return window(id)
    }

    // MARK: Inspector field edits (kind / weekdays / label)

    /// components.md §13.3: "... then pick the kind from the inspector." A
    /// Picker selection change is one atomic edit, so it is one undo step,
    /// fired the instant the selection changes — no separate "Save" button,
    /// same as every other inspector control in this app.
    func setKind(_ window: TimeWindow, to newKind: TimeWindowKind) {
        let id = window.id
        let oldKind = window.kind
        guard newKind != oldKind else { return }
        record("Set Time Window Kind",
                     redo: { edit(id) { $0.kind = newKind } },
                     undo: { edit(id) { $0.kind = oldKind } })
    }

    /// Replaces the whole weekday set. The inspector's toggle row computes the
    /// new set itself (the existing set plus or minus the one weekday just
    /// toggled) and passes it in whole — this method just commits it, the
    /// same "caller decides, store just commits" split `create`'s own
    /// `weekdays` parameter already uses. Refuses to commit an empty set, for
    /// the same reason `create` refuses an empty `weekdays` set: a window
    /// matching no day would never render or affect scheduling, which is not
    /// what unchecking the last box should silently do.
    func setWeekdays(_ window: TimeWindow, to newWeekdays: Set<Int>) {
        guard !newWeekdays.isEmpty else { return }
        let id = window.id
        let oldWeekdays = window.weekdays
        guard newWeekdays != oldWeekdays else { return }
        record("Set Time Window Weekdays",
                     redo: { edit(id) { $0.weekdays = newWeekdays } },
                     undo: { edit(id) { $0.weekdays = oldWeekdays } })
    }

    /// Commits an edited label. The caller holds the in-flight text in its
    /// own local `@State` (the same "nothing written until commit" shape this
    /// window's `EventDraft` title field already uses) and calls this once,
    /// on `Return` or on the field losing focus — never once per keystroke,
    /// which would flood the undo stack with a step per character. See
    /// DEVIATIONS.md for why this commit point was chosen: there is no
    /// existing precedent in this codebase for editing an ALREADY-persisted
    /// text field (the one existing inline `TextField`, `DraftBlockView`'s
    /// title, only ever edits an in-flight, not-yet-persisted draft), so this
    /// is a fresh judgement call, not a reuse of one.
    func setLabel(_ window: TimeWindow, to newLabel: String) {
        let id = window.id
        let oldLabel = window.label
        guard newLabel != oldLabel else { return }
        undo.perform("Set Time Window Label",
                     redo: { edit(id) { $0.label = newLabel } },
                     undo: { edit(id) { $0.label = oldLabel } })
    }
}

// MARK: - Snapshot (delete/undo)

/// Everything needed to bring a `TimeWindow` back after a delete — same shape
/// and same reason as `RoutineBlockRestoreSnapshot`: a `@Model` instance
/// cannot be re-inserted once deleted, so undo recreates one carrying the
/// same `id` and every other field, including `kind`, `label` and `weekdays`.
///
/// Also (task P2-T23) what `create`'s own `redo` inserts: a brand-new window
/// has never had a `@Model` instance to snapshot *from*, but it needs the
/// same "values in, `insertWindow` builds the `@Model`" shape `delete`'s undo
/// already established — the plain memberwise `init` below supplies it
/// directly, mirroring `RoutineBlockRestoreSnapshot`'s own two-initializer
/// shape (`Kadence/State/RoutineEngine.swift`) exactly.
struct TimeWindowRestoreSnapshot: Sendable {
    var id: UUID
    var weekdays: Set<Int>
    var startMinutes: Int
    var endMinutes: Int
    var kind: TimeWindowKind
    var label: String

    init(
        id: UUID,
        weekdays: Set<Int>,
        startMinutes: Int,
        endMinutes: Int,
        kind: TimeWindowKind = .protected,
        label: String = ""
    ) {
        self.id = id
        self.weekdays = weekdays
        self.startMinutes = startMinutes
        self.endMinutes = endMinutes
        self.kind = kind
        self.label = label
    }

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
