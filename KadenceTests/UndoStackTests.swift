//
//  UndoStackTests.swift
//  KadenceTests
//
//  interactions.md §9. The stack is a plain value-semantics structure with no
//  SwiftData or SwiftUI dependency precisely so the ordering rules can be
//  asserted directly — which is the only way the interleaving case below is
//  checkable at all.
//

import Testing
import Foundation
@testable import Kadence

@MainActor
private func counterStack(depth: Int = UndoStack.defaultDepth) -> (UndoStack, Box) {
    (UndoStack(depth: depth), Box())
}

/// A stand-in for the model layer. `order` is an append-only log, so a test can
/// assert not just the final state but the ORDER changes were unwound in — which
/// is the whole point of the interleaving suite.
@MainActor
private final class Box {
    var n = 0
    var order: [String] = []
}

// MARK: - Depth

@Suite("Undo depth")
@MainActor
struct UndoDepthTests {

    @Test("More than one step can be undone")
    func multiStep() {
        let (stack, box) = counterStack()
        for i in 1...5 {
            stack.perform("Step \(i)", redo: { box.n += 1 }, undo: { box.n -= 1 })
        }
        #expect(box.n == 5)
        stack.undo(); stack.undo(); stack.undo()
        #expect(box.n == 2, "three presses of ⌘Z must undo three steps")
    }

    @Test("The stack is bounded and drops the oldest step first")
    func bounded() {
        let (stack, box) = counterStack(depth: 3)
        for i in 1...6 {
            stack.perform("Step \(i)", redo: { box.n += 1 }, undo: { box.n -= 1 })
        }
        #expect(stack.undoSteps.count == 3)
        #expect(stack.undoSteps.map(\.name) == ["Step 4", "Step 5", "Step 6"])

        // Everything still on the stack unwinds; the dropped steps are simply gone.
        stack.undo(); stack.undo(); stack.undo()
        #expect(box.n == 3)
        #expect(!stack.canUndo)
        stack.undo()
        #expect(box.n == 3, "undoing past the bottom must be a no-op, not a crash")
    }

    @Test("The default depth is a real working depth, not one")
    func defaultDepth() {
        #expect(UndoStack.defaultDepth >= 20)
        #expect(UndoStack().depth == UndoStack.defaultDepth)
    }

    @Test("A depth below one is clamped rather than producing a dead stack")
    func degenerateDepth() {
        let stack = UndoStack(depth: 0)
        #expect(stack.depth == 1)
    }
}

// MARK: - Grouping

@Suite("Grouped mutations")
@MainActor
struct UndoGroupingTests {

    @Test("Several changes in one group undo as ONE step")
    func groupIsOneStep() {
        let (stack, box) = counterStack()
        stack.perform("Resolve Conflict") { group in
            group.perform(redo: { box.n += 1 }, undo: { box.n -= 1 })
            group.perform(redo: { box.n += 10 }, undo: { box.n -= 10 })
            group.perform(redo: { box.n += 100 }, undo: { box.n -= 100 })
        }
        #expect(box.n == 111)
        #expect(stack.undoSteps.count == 1, "three changes, one step")

        stack.undo()
        #expect(box.n == 0, "one ⌘Z must revert the whole group")
        #expect(!stack.canUndo)
    }

    @Test("A group unwinds in reverse order")
    func reverseOrder() {
        let (stack, box) = counterStack()
        stack.perform("Materialise Routine") { group in
            for label in ["a", "b", "c"] {
                group.perform(
                    redo: { box.order.append("+\(label)") },
                    undo: { box.order.append("-\(label)") })
            }
        }
        box.order.removeAll()
        stack.undo()
        #expect(box.order == ["-c", "-b", "-a"],
                "the last change made is the first one reversed")
    }

    @Test("Nested perform calls join the open group instead of pushing steps")
    func reentrant() {
        // This is the Phase 2 shape: a composite operation built by calling the
        // ordinary single-mutation verbs.
        let (stack, box) = counterStack()

        func moveOne() { stack.perform("Move Event", redo: { box.n += 1 }, undo: { box.n -= 1 }) }
        func skipOne() { stack.perform("Skip", redo: { box.n += 2 }, undo: { box.n -= 2 }) }

        stack.perform("Resolve Conflict") { _ in
            moveOne()
            skipOne()
        }

        #expect(stack.undoSteps.count == 1)
        #expect(stack.undoActionName == "Resolve Conflict",
                "the outermost name is the one the user sees")
        stack.undo()
        #expect(box.n == 0)
    }

    @Test("Those same verbs still stand alone outside a group")
    func verbsWorkUngrouped() {
        let (stack, box) = counterStack()
        stack.perform("Move Event", redo: { box.n += 1 }, undo: { box.n -= 1 })
        stack.perform("Skip", redo: { box.n += 2 }, undo: { box.n -= 2 })
        #expect(stack.undoSteps.count == 2)
        #expect(stack.undoActionName == "Skip")
    }

    @Test("A group that changes nothing leaves no step to press ⌘Z through")
    func emptyGroup() {
        let stack = UndoStack()
        stack.perform("Resolve Conflict") { _ in }
        #expect(stack.undoSteps.isEmpty)
        #expect(!stack.canUndo)
    }
}

// MARK: - Interleaving

@Suite("Interleaved single and grouped mutations")
@MainActor
struct UndoInterleavingTests {

    /// single → group → single, unwound one press at a time.
    @Test("A single, then a group, then a single unwind in the right order")
    func interleavedUnwind() {
        let (stack, box) = counterStack()

        stack.perform("Move Event",
                      redo: { box.order.append("+move") },
                      undo: { box.order.append("-move") })

        stack.perform("Resolve Conflict") { group in
            group.perform(redo: { box.order.append("+shift") }, undo: { box.order.append("-shift") })
            group.perform(redo: { box.order.append("+shorten") }, undo: { box.order.append("-shorten") })
        }

        stack.perform("Skip",
                      redo: { box.order.append("+skip") },
                      undo: { box.order.append("-skip") })

        #expect(box.order == ["+move", "+shift", "+shorten", "+skip"])
        #expect(stack.undoSteps.count == 3, "the group counts once")

        box.order.removeAll()

        stack.undo()
        #expect(box.order == ["-skip"])
        #expect(stack.undoActionName == "Resolve Conflict")

        stack.undo()
        #expect(box.order == ["-skip", "-shorten", "-shift"],
                "the whole group reverses on one press, innermost-last-first")
        #expect(stack.undoActionName == "Move Event")

        stack.undo()
        #expect(box.order == ["-skip", "-shorten", "-shift", "-move"])
        #expect(!stack.canUndo)
    }

    @Test("Redoing the interleaved sequence replays it forwards")
    func interleavedRedo() {
        let (stack, box) = counterStack()
        stack.perform("Move Event", redo: { box.order.append("+move") }, undo: { box.order.append("-move") })
        stack.perform("Resolve Conflict") { group in
            group.perform(redo: { box.order.append("+shift") }, undo: { box.order.append("-shift") })
            group.perform(redo: { box.order.append("+shorten") }, undo: { box.order.append("-shorten") })
        }
        stack.undo(); stack.undo()
        box.order.removeAll()

        stack.redo()
        #expect(box.order == ["+move"])
        stack.redo()
        #expect(box.order == ["+move", "+shift", "+shorten"],
                "a group redoes in the order it was originally applied")
        #expect(!stack.canRedo)
    }
}

// MARK: - Redo

@Suite("Redo")
@MainActor
struct RedoTests {

    @Test("Undo then redo returns to the same state")
    func roundTrip() {
        let (stack, box) = counterStack()
        stack.perform("Move Event", redo: { box.n += 5 }, undo: { box.n -= 5 })
        stack.undo()
        #expect(box.n == 0)
        stack.redo()
        #expect(box.n == 5)
        #expect(!stack.canRedo)
        #expect(stack.canUndo)
    }

    @Test("A new action clears the redo branch")
    func newActionClearsRedo() {
        let (stack, box) = counterStack()
        stack.perform("A", redo: { box.n += 1 }, undo: { box.n -= 1 })
        stack.undo()
        #expect(stack.canRedo)

        stack.perform("B", redo: { box.n += 2 }, undo: { box.n -= 2 })
        #expect(!stack.canRedo, "redoing onto a diverged history would corrupt state")
        #expect(stack.undoActionName == "B")
    }

    @Test("Redoing with nothing to redo is a no-op")
    func emptyRedo() {
        let (stack, box) = counterStack()
        stack.redo()
        #expect(box.n == 0)
    }

    @Test("Mutations made *by* an undo do not record new steps")
    func replayDoesNotRecord() {
        // Undo closures in EventStore call back into the same code paths that
        // record. Without the replay guard, one ⌘Z would push a fresh step and
        // the stack would never empty.
        let (stack, box) = counterStack()
        stack.perform("Move Event",
                      redo: { box.n += 1 },
                      undo: { stack.perform("Sneaky", redo: { box.n -= 1 }, undo: {}) })
        stack.undo()
        #expect(box.n == 0)
        #expect(stack.undoSteps.isEmpty, "the undo must not have recorded itself")
        #expect(stack.redoSteps.count == 1)
    }
}

// MARK: - Names

@Suite("Undo names")
@MainActor
struct UndoNameTests {

    @Test("The menu reads Undo <action>, not Undo")
    func menuTitles() {
        let stack = UndoStack()
        #expect(stack.undoMenuTitle == "Undo")
        #expect(stack.redoMenuTitle == "Redo")

        stack.perform("Move Event", redo: {}, undo: {})
        #expect(stack.undoMenuTitle == "Undo Move Event")

        stack.undo()
        #expect(stack.redoMenuTitle == "Redo Move Event")
        #expect(stack.undoMenuTitle == "Undo")
    }

    @Test("A grouped operation is named once, by the group")
    func groupName() {
        let stack = UndoStack()
        stack.perform("Resolve Conflict") { group in
            group.perform(redo: {}, undo: {})
            group.perform(redo: {}, undo: {})
        }
        #expect(stack.undoMenuTitle == "Undo Resolve Conflict")
    }

    @Test("An abandoned creation is dropped, not left for ⌘Z")
    func discard() {
        let (stack, box) = counterStack()
        stack.perform("New Event", redo: { box.n += 1 }, undo: { box.n -= 1 })
        #expect(stack.canUndo)
        stack.discardLastStep()
        #expect(!stack.canUndo, "an event the user never named is not undoable history")
    }
}
