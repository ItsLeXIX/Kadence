//
//  UndoStack.swift
//  Kadence
//
//  interactions.md §9 — every mutation is undoable, and each registers a *named*
//  action so the Edit menu reads "Undo Move Event", not "Undo".
//
//  Why this rather than SwiftData's `ModelContext.undoManager`:
//
//  1. **Grouping is the requirement, not a nicety.** Phase 2's conflict
//     resolution applies two or three changes at once and must revert as a
//     unit; the routine engine will materialise many blocks at once and must
//     undo as a unit. `UndoManager` groups by begin/end pairs around whatever
//     SwiftData happens to register per property, which is the wrong grain and
//     is not re-entrant in the way we need.
//  2. **Deletion has to survive a round trip.** Undoing a delete cannot reuse
//     the deleted `@Model` instance, so the object comes back as a new one with
//     the same `id`. Closures that captured the old instance would be holding a
//     tombstone. Everything here addresses events by `id` and resolves them at
//     execution time, so an event can be deleted, restored and moved again in
//     any order.
//  3. It is a plain value-semantics stack with no SwiftData or SwiftUI
//     dependency, so the ordering rules can actually be tested.
//
//  Swift note (from Java/C#): a closure that outlives the call stores its
//  captures, so `undo` below is a pair of closures — one to apply a change and
//  one to reverse it — recorded at the moment the change is made.
//

import Foundation
import Observation

@MainActor
@Observable
final class UndoStack {

    /// How many steps are kept. Older steps fall off the bottom.
    ///
    /// 50 is deep enough that a working session is never silently truncated and
    /// shallow enough that the retained closures (and the values they capture)
    /// stay trivial. Configurable per instance so tests can use a small stack.
    static let defaultDepth = 50

    /// One reversible change. `redo` must be safe to run more than once, and
    /// `undo` must return the world to exactly the state before `redo` ran.
    struct Change {
        let redo: () -> Void
        let undo: () -> Void
    }

    /// One user-visible step. Several changes, one entry in the Edit menu, one
    /// press of ⌘Z.
    struct Step {
        var name: String
        var changes: [Change]
    }

    /// Handed to the body of `perform` so it can record changes as it makes them.
    @MainActor
    final class Group {
        fileprivate var changes: [Change] = []

        /// Apply a change now and record how to reverse it.
        func perform(redo: @escaping () -> Void, undo: @escaping () -> Void) {
            redo()
            changes.append(Change(redo: redo, undo: undo))
        }
    }

    let depth: Int

    private(set) var undoSteps: [Step] = []
    private(set) var redoSteps: [Step] = []

    /// The group currently being recorded into, if a `perform` is open.
    private var openGroup: Group?
    /// True while an undo or redo is replaying, so mutations made by the
    /// replayed closures do not record themselves as new steps.
    private var isReplaying = false

    init(depth: Int = UndoStack.defaultDepth) {
        self.depth = max(1, depth)
    }

    // MARK: What the menu shows

    var canUndo: Bool { !undoSteps.isEmpty }
    var canRedo: Bool { !redoSteps.isEmpty }

    var undoActionName: String? { undoSteps.last?.name }
    var redoActionName: String? { redoSteps.last?.name }

    var undoMenuTitle: String {
        undoActionName.map { "Undo \($0)" } ?? "Undo"
    }
    var redoMenuTitle: String {
        redoActionName.map { "Redo \($0)" } ?? "Redo"
    }

    // MARK: Recording

    /// Run `body`, recording everything it does as ONE named step.
    ///
    /// Re-entrant on purpose. A composite operation is written by calling the
    /// ordinary single-mutation methods:
    ///
    /// ```swift
    /// undo.perform("Resolve Conflict") { _ in
    ///     store.move(training, by: 90 * 60)
    ///     store.resize(lecture, newEnd: newEnd)
    /// }
    /// ```
    ///
    /// Those inner calls each open their own `perform`; because a group is
    /// already open they join it instead of pushing steps of their own, and the
    /// **outermost** name is the one the user sees. That is what lets Phase 2
    /// compose conflict resolution out of the existing verbs without either
    /// duplicating them or leaving three separate steps on the stack.
    func perform(_ name: String, _ body: (Group) -> Void) {
        // Never record the work an undo/redo is itself doing.
        if isReplaying {
            body(Group())
            return
        }

        if let openGroup {
            body(openGroup)
            return
        }

        let group = Group()
        openGroup = group
        body(group)
        openGroup = nil

        // A call that changed nothing (a no-op move, a rename to the same text)
        // must not leave an empty step for the user to press ⌘Z through.
        guard !group.changes.isEmpty else { return }
        push(Step(name: name, changes: group.changes))
    }

    /// Convenience for the common single-change case.
    func perform(_ name: String, redo: @escaping () -> Void, undo: @escaping () -> Void) {
        perform(name) { group in
            group.perform(redo: redo, undo: undo)
        }
    }

    private func push(_ step: Step) {
        undoSteps.append(step)
        if undoSteps.count > depth {
            undoSteps.removeFirst(undoSteps.count - depth)
        }
        // Any new action invalidates the redo branch.
        redoSteps.removeAll()
    }

    // MARK: Replaying

    func undo() {
        guard let step = undoSteps.popLast() else { return }
        replay { 
            // Reverse order: the last change made is the first undone.
            for change in step.changes.reversed() { change.undo() }
        }
        redoSteps.append(step)
    }

    func redo() {
        guard let step = redoSteps.popLast() else { return }
        replay {
            for change in step.changes { change.redo() }
        }
        undoSteps.append(step)
    }

    private func replay(_ body: () -> Void) {
        isReplaying = true
        body()
        isReplaying = false
    }

    // MARK: Housekeeping

    func removeAll() {
        undoSteps.removeAll()
        redoSteps.removeAll()
    }
}
