//
//  FlexibilityControlTests.swift
//  KadenceTests
//
//  Task P2-T42: components.md §13.2 and its 2026-10-01 amendment (GAPS
//  G-022) — the flexibility control's value semantics, clamping, undo step
//  names, and "a `.shiftable` block with no ± value is a defect, not a
//  state".
//

import Testing
import Foundation
import SwiftData
import AppKit
@testable import Kadence

@MainActor
private func makeStore() throws -> (RoutineBlockStore, ModelContext, UndoStack) {
    let container = try ModelContainer(
        for: Schema(KadenceSchema.models),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let undo = UndoStack()
    return (RoutineBlockStore(context: context, undo: undo), context, undo)
}

@MainActor
private func insertBlock(_ context: ModelContext, flexibility: Flexibility, minutes: Int?) -> RoutineBlock {
    let block = RoutineBlock(title: "Gym", startMinutes: 420, duration: 3600,
                             flexibility: flexibility, shiftableMinutes: minutes)
    context.insert(RoutineTemplate(name: "R", activeWeekdays: [2], blocks: [block]))
    try? context.save()
    return block
}

@Suite("ShiftRangeRule — §13.2 value semantics")
struct ShiftRangeRuleTests {

    @Test("Entering Shiftable with no value writes 30, not nil and not 15")
    func entryDefault() {
        #expect(ShiftRangeRule.storedValue(afterSwitchingTo: .shiftable, current: nil) == 30)
    }

    @Test("Entering Shiftable with a stored value keeps it")
    func entryKeepsExisting() {
        #expect(ShiftRangeRule.storedValue(afterSwitchingTo: .shiftable, current: 75) == 75)
    }

    @Test("Switching away keeps the number", arguments: [Flexibility.fixed, .droppable])
    func switchingAwayKeeps(_ target: Flexibility) {
        #expect(ShiftRangeRule.storedValue(afterSwitchingTo: target, current: 45) == 45)
        #expect(ShiftRangeRule.storedValue(afterSwitchingTo: target, current: nil) == nil,
                "Fixed/Droppable never invent a value")
    }

    @Test("Clamping to 15–180", arguments: [(0, 15), (14, 15), (15, 15), (90, 90), (180, 180), (181, 180), (999, 180)])
    func clamps(_ pair: (Int, Int)) {
        #expect(ShiftRangeRule.clamped(pair.0) == pair.1)
    }

    @Test("The stepper shows 30 for nil and never a value it would not accept")
    func displayed() {
        #expect(ShiftRangeRule.displayed(nil) == 30)
        #expect(ShiftRangeRule.displayed(5) == 15)
        #expect(ShiftRangeRule.displayed(240) == 180)
        #expect(ShiftRangeRule.displayed(60) == 60)
    }

    @Test("Only .shiftable with nil needs repair")
    func repairPredicate() {
        #expect(ShiftRangeRule.needsRepair(flexibility: .shiftable, stored: nil))
        #expect(!ShiftRangeRule.needsRepair(flexibility: .shiftable, stored: 30))
        #expect(!ShiftRangeRule.needsRepair(flexibility: .fixed, stored: nil))
        #expect(!ShiftRangeRule.needsRepair(flexibility: .droppable, stored: nil))
    }
}

@Suite("RoutineBlockStore — Set Flexibility / Set Shift Range (§13.2)")
@MainActor
struct FlexibilityStoreTests {

    @Test("Fixed → Shiftable with no value: one 'Set Flexibility' step writes 30; ⌘Z restores Fixed and nil")
    func enterShiftable() throws {
        let (store, context, undo) = try makeStore()
        let block = insertBlock(context, flexibility: .fixed, minutes: nil)

        store.setFlexibility(block, to: .shiftable)
        #expect(block.flexibility == .shiftable)
        #expect(block.shiftableMinutes == 30)
        #expect(undo.undoSteps.count == 1)
        #expect(undo.undoMenuTitle == "Undo Set Flexibility")

        undo.undo()
        #expect(block.flexibility == .fixed)
        #expect(block.shiftableMinutes == nil)
        undo.redo()
        #expect(block.flexibility == .shiftable)
        #expect(block.shiftableMinutes == 30)
    }

    @Test("Shiftable → Droppable keeps the number; back to Shiftable restores it")
    func roundTripKeepsNumber() throws {
        let (store, context, _) = try makeStore()
        let block = insertBlock(context, flexibility: .shiftable, minutes: 75)

        store.setFlexibility(block, to: .droppable)
        #expect(block.shiftableMinutes == 75)
        store.setFlexibility(block, to: .shiftable)
        #expect(block.shiftableMinutes == 75)
    }

    @Test("Choosing the current segment records nothing")
    func sameSegmentNoStep() throws {
        let (store, context, undo) = try makeStore()
        let block = insertBlock(context, flexibility: .fixed, minutes: nil)
        store.setFlexibility(block, to: .fixed)
        #expect(undo.undoSteps.isEmpty)
    }

    @Test("The stepper writes one 'Set Shift Range' step per change, clamped")
    func shiftRange() throws {
        let (store, context, undo) = try makeStore()
        let block = insertBlock(context, flexibility: .shiftable, minutes: 30)

        store.setShiftRange(block, to: 45)
        #expect(block.shiftableMinutes == 45)
        #expect(undo.undoMenuTitle == "Undo Set Shift Range")

        store.setShiftRange(block, to: 500)
        #expect(block.shiftableMinutes == 180)
        store.setShiftRange(block, to: 999)
        #expect(undo.undoSteps.count == 2, "a write that clamps to the stored value records nothing")

        store.setShiftRange(block, to: 0)
        #expect(block.shiftableMinutes == 15)

        undo.undo()
        #expect(block.shiftableMinutes == 180)
    }
}

@Suite("nil never survives on a .shiftable block (§13.2)")
@MainActor
struct ShiftRangeRepairTests {

    @Test("The repair writes 30 into every .shiftable block with nil, records no undo step, and leaves the others")
    func repairAll() throws {
        let (store, context, undo) = try makeStore()
        let broken = insertBlock(context, flexibility: .shiftable, minutes: nil)
        let fine = insertBlock(context, flexibility: .shiftable, minutes: 60)
        let fixed = insertBlock(context, flexibility: .fixed, minutes: nil)

        #expect(store.repairShiftRanges() == 1)
        #expect(broken.shiftableMinutes == 30)
        #expect(fine.shiftableMinutes == 60)
        #expect(fixed.shiftableMinutes == nil)
        #expect(undo.undoSteps.isEmpty)
        #expect(store.repairShiftRanges() == 0, "idempotent")
    }

    @Test("First display repairs only the shown block")
    func repairOne() throws {
        let (store, context, _) = try makeStore()
        let shown = insertBlock(context, flexibility: .shiftable, minutes: nil)
        let other = insertBlock(context, flexibility: .shiftable, minutes: nil)

        store.repairShiftRanges(blockID: shown.id)
        #expect(shown.shiftableMinutes == 30)
        #expect(other.shiftableMinutes == nil)
    }

    @Test("No path through the store leaves .shiftable with nil")
    func noPathLeavesNil() throws {
        let (store, context, undo) = try makeStore()
        let block = insertBlock(context, flexibility: .droppable, minutes: nil)
        for target in [Flexibility.shiftable, .fixed, .shiftable, .droppable, .shiftable] {
            store.setFlexibility(block, to: target)
            #expect(!ShiftRangeRule.needsRepair(flexibility: block.flexibility, stored: block.shiftableMinutes))
        }
        // Undo all the way back and forward again: every intermediate state too.
        while undo.canUndo {
            undo.undo()
            #expect(!ShiftRangeRule.needsRepair(flexibility: block.flexibility, stored: block.shiftableMinutes))
        }
        while undo.canRedo {
            undo.redo()
            #expect(!ShiftRangeRule.needsRepair(flexibility: block.flexibility, stored: block.shiftableMinutes))
        }
    }
}

/// Task P2-F09 (PHASE2-REVIEW.md §6 item 9; components.md §13.2, amended
/// 2026-10-05; G-032): the rail sample is a template image tinted by the
/// segmented control like its title, and the stepper reads `± 30 min`.
@Suite("Flexibility control — rail sample and stepper copy (P2-F09)")
@MainActor
struct FlexibilitySampleTests {

    @Test("Every segment's rail sample is a template image, title-line tall, 3pt wide",
          arguments: [RailStyle.solid, .inset, .dotted])
    func templateImage(_ style: RailStyle) {
        let image = FlexibilityControl.railSample(style, scale: 2)
        #expect(image.isTemplate)
        #expect(image.size.width == Tokens.Size.blockRailWidth)
        #expect(image.size.height == FlexibilityControl.sampleHeight)
    }

    @Test("Stepper copy is `± N min`, and a missing value reads 30")
    func stepperText() {
        #expect(FlexibilityControl.stepperText(30) == "± 30 min")
        #expect(FlexibilityControl.stepperText(nil) == "± 30 min")
        #expect(FlexibilityControl.stepperText(90) == "± 90 min")
    }
}
