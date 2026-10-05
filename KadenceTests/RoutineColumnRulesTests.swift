//
//  RoutineColumnRulesTests.swift
//  KadenceTests
//
//  Task P2-T38 — components.md §13.5 (weekday activity) and interactions.md
//  §11.1's 2026-10-01 amendment, at the layer below the view:
//
//  - inactive-column gating: which columns refuse a create gesture, recess
//    their hour lines, carry the note and lose the header underline;
//  - Blocks-only scope (§13.5.5): in Windows mode nothing is marked;
//  - draft abandonment when a column is deactivated;
//  - a block drag is vertical only: `RoutineBlockDrag` has no column, its
//    preview goes to every active column and no inactive one, and the
//    range it previews is exactly what `RoutineBlockStore` then writes.
//
//  What is NOT covered here, because it has no seam below SwiftUI: the cursor
//  actually changing, the note actually staying pinned while scrolling, and
//  the preview actually rendering in several columns. Those are visual and
//  belong to the screenshot/script pass.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

/// Mon/Wed/Fri — the seeded "Daily routine" shape G-018 was found on.
private let monWedFri: Set<Int> = [2, 4, 6]
/// Mon-first column order, as on a Monday-first locale.
private let mondayFirst = RoutineWeekLayout.orderedWeekdays(firstWeekday: 2)

// MARK: - Column treatment

@Suite("RoutineColumnTreatment — components.md §13.5.2 / §13.5.5")
struct RoutineColumnTreatmentTests {

    @Test("Blocks mode, active weekday: underline, normal lines, no note, create accepted")
    func activeColumn() {
        let treatment = RoutineColumnTreatment.resolve(weekday: 2, activeWeekdays: monWedFri, mode: .blocks)
        #expect(treatment == .active)
        #expect(treatment.showsHeaderUnderline)
        #expect(!treatment.recessesHourLines)
        #expect(!treatment.showsInactiveNote)
        #expect(treatment.acceptsBlockCreate)
        #expect(!treatment.refusesBlockCreate)
    }

    @Test("Blocks mode, inactive weekday: no underline, recessed lines, note, create refused")
    func inactiveColumn() {
        let treatment = RoutineColumnTreatment.resolve(weekday: 3, activeWeekdays: monWedFri, mode: .blocks)
        #expect(treatment == .inactive)
        #expect(!treatment.showsHeaderUnderline)
        #expect(treatment.recessesHourLines)
        #expect(treatment.showsInactiveNote)
        #expect(!treatment.acceptsBlockCreate)
        #expect(treatment.refusesBlockCreate)
    }

    @Test("Blocks mode partitions the seven columns exactly by activeWeekdays")
    func partitionsByWeekdaySet() {
        let inactive = mondayFirst.filter {
            RoutineColumnTreatment.resolve(weekday: $0, activeWeekdays: monWedFri, mode: .blocks) == .inactive
        }
        #expect(inactive == [3, 5, 7, 1]) // Tue, Thu, Sat, Sun
    }

    @Test("A template with no active weekdays refuses creation in every column")
    func emptyWeekdaySet() {
        for weekday in 1...7 {
            #expect(RoutineColumnTreatment.resolve(weekday: weekday, activeWeekdays: [], mode: .blocks) == .inactive)
        }
    }

    @Test("Windows mode marks nothing in any column, active or not (§13.5.5)")
    func windowsModeIsUnmarked() {
        for weekday in 1...7 {
            let treatment = RoutineColumnTreatment.resolve(weekday: weekday, activeWeekdays: monWedFri, mode: .windows)
            #expect(treatment == .unmarked)
            #expect(!treatment.showsHeaderUnderline)
            #expect(!treatment.recessesHourLines)
            #expect(!treatment.showsInactiveNote)
            // No refusal cursor/surface either: every column stays a live
            // TimeWindow surface. (Block creation is off in Windows mode for
            // the older §13.3 reason — blocks are not the edited layer.)
            #expect(!treatment.refusesBlockCreate)
        }
    }
}

// MARK: - Draft abandonment

@Suite("RoutineDraftRules — interactions.md §11.1 draft abandonment")
struct RoutineDraftRulesTests {

    @Test("A draft in a still-active column survives")
    func activeColumnKeepsDraft() {
        #expect(!RoutineDraftRules.mustAbandonDraft(draftWeekday: 4, activeWeekdays: monWedFri))
    }

    @Test("A draft whose column is deactivated mid-edit is abandoned")
    func deactivatedColumnAbandonsDraft() {
        var weekdays = monWedFri
        weekdays.remove(4)
        #expect(RoutineDraftRules.mustAbandonDraft(draftWeekday: 4, activeWeekdays: weekdays))
    }
}

// MARK: - Block drag: vertical only, multi-column preview

@Suite("RoutineBlockDrag — vertical only (interactions.md §11.1)")
struct RoutineBlockDragTests {

    private let hourHeight = 48.0

    @Test("The drag carries no column: nothing on it names a weekday")
    func hasNoColumn() {
        // Structural check: if someone later adds a weekday/column field,
        // a block drag could start changing columns, which §11.1 forbids.
        let drag = RoutineBlockDrag(blockID: UUID(), mode: .move, startMinutes: 420, durationMinutes: 60)
        let labels = Mirror(reflecting: drag).children.compactMap(\.label).map { $0.lowercased() }
        #expect(!labels.contains { $0.contains("weekday") || $0.contains("column") || $0.contains("day") })
    }

    @Test("Vertical translation moves the start, snapped to 15 minutes")
    func verticalMoveSnaps() {
        let drag = RoutineBlockDrag(blockID: UUID(), mode: .move, startMinutes: 420, durationMinutes: 60)
            .updated(translationHeight: hourHeight * 1.1, hourHeight: hourHeight, snapMinutes: 15)
        // 07:00 + 66 min → nearest 15 = 08:00 (480).
        #expect(drag.proposedRange.start == 480)
        #expect(drag.proposedRange.end == 540)
    }

    @Test("⌃ snaps to 5 minutes instead")
    func controlSnapsToFive() {
        let drag = RoutineBlockDrag(blockID: UUID(), mode: .move, startMinutes: 420, durationMinutes: 60)
            .updated(translationHeight: hourHeight * 0.13, hourHeight: hourHeight, snapMinutes: 5)
        // 07:00 + 7.8 min → nearest 5 = 07:10 (430).
        #expect(drag.proposedRange.start == 430)
    }

    @Test("Zero vertical translation leaves the block where it was")
    func noVerticalMovementIsNoMove() {
        let drag = RoutineBlockDrag(blockID: UUID(), mode: .move, startMinutes: 420, durationMinutes: 60)
            .updated(translationHeight: 0, hourHeight: hourHeight, snapMinutes: 15)
        #expect(drag.proposedRange.start == 420)
        #expect(drag.proposedRange.end == 480)
    }

    @Test("The preview goes to every active column, in column order, and no inactive one")
    func previewInEveryActiveColumn() {
        #expect(RoutineBlockDrag.previewWeekdays(orderedWeekdays: mondayFirst, activeWeekdays: monWedFri) == [2, 4, 6])
        let sundayFirst = RoutineWeekLayout.orderedWeekdays(firstWeekday: 1)
        #expect(RoutineBlockDrag.previewWeekdays(orderedWeekdays: sundayFirst, activeWeekdays: [1, 7]) == [1, 7])
        #expect(RoutineBlockDrag.previewWeekdays(orderedWeekdays: mondayFirst, activeWeekdays: []).isEmpty)
    }

    @Test("A move past midnight clamps in the preview, not wraps (G-013, §11.1)")
    func moveClampsAtDayEnd() {
        let drag = RoutineBlockDrag(blockID: UUID(), mode: .move, startMinutes: 22 * 60, durationMinutes: 120)
            .updated(translationHeight: hourHeight * 3, hourHeight: hourHeight, snapMinutes: 15)
        #expect(drag.proposedRange.start == 22 * 60)
        #expect(drag.proposedRange.end == 1440)
    }

    @Test("Resizes keep §4's 15-minute minimum in the preview")
    func resizeMinimum() {
        let top = RoutineBlockDrag(blockID: UUID(), mode: .resizeTop, startMinutes: 420, durationMinutes: 60)
            .updated(translationHeight: hourHeight * 2, hourHeight: hourHeight, snapMinutes: 15)
        #expect(top.proposedRange.start == 465)
        #expect(top.proposedRange.end == 480)

        let bottom = RoutineBlockDrag(blockID: UUID(), mode: .resizeBottom, startMinutes: 420, durationMinutes: 60)
            .updated(translationHeight: -hourHeight * 2, hourHeight: hourHeight, snapMinutes: 15)
        #expect(bottom.proposedRange.start == 420)
        #expect(bottom.proposedRange.end == 435)
    }
}

// MARK: - The drag against the real store

@MainActor
private func makeStore() throws -> (RoutineBlockStore, ModelContext) {
    let container = try ModelContainer(
        for: Schema(KadenceSchema.models),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    return (RoutineBlockStore(context: context, undo: UndoStack()), context)
}

@Suite("RoutineBlockDrag → RoutineBlockStore — what is previewed is what lands")
@MainActor
struct RoutineBlockDragStoreTests {

    private let hourHeight = 48.0

    private func apply(_ drag: RoutineBlockDrag, to block: RoutineBlock, store: RoutineBlockStore) {
        // Same switch `RoutineDayColumnView.blockGesture`'s `.onEnded` runs.
        let range = drag.proposedRange
        switch drag.mode {
        case .move: store.move(block, toStartMinutes: range.start)
        case .resizeTop: store.resize(block, newStartMinutes: range.start)
        case .resizeBottom: store.resize(block, newEndMinutes: range.end)
        }
    }

    @Test("Move, top and bottom resize — including past both ends of the day",
          arguments: [
            (RoutineBlockDrag.Mode.move, 2.5), (.move, -20.0), (.move, 30.0),
            (.resizeTop, -1.25), (.resizeTop, 5.0), (.resizeTop, -20.0),
            (.resizeBottom, 1.5), (.resizeBottom, -5.0), (.resizeBottom, 30.0),
          ])
    func previewMatchesStore(mode: RoutineBlockDrag.Mode, hours: Double) throws {
        let (store, context) = try makeStore()
        let block = RoutineBlock(title: "Gym", startMinutes: 7 * 60, duration: 3600)
        let template = RoutineTemplate(name: "Daily routine", activeWeekdays: monWedFri, blocks: [block])
        context.insert(template)
        try context.save()

        let drag = RoutineBlockDrag(blockID: block.id, mode: mode, startMinutes: 7 * 60, durationMinutes: 60)
            .updated(translationHeight: hourHeight * hours, hourHeight: hourHeight, snapMinutes: 15)
        apply(drag, to: block, store: store)

        #expect(block.startMinutes == drag.proposedRange.start)
        #expect(block.startMinutes + Int(block.duration / 60) == drag.proposedRange.end)
    }

    @Test("A drag changes the block's time, never the columns it appears in")
    func dragNeverChangesColumns() throws {
        let (store, context) = try makeStore()
        let block = RoutineBlock(title: "Gym", startMinutes: 7 * 60, duration: 3600)
        let template = RoutineTemplate(name: "Daily routine", activeWeekdays: monWedFri, blocks: [block])
        context.insert(template)
        try context.save()

        let drag = RoutineBlockDrag(blockID: block.id, mode: .move, startMinutes: 7 * 60, durationMinutes: 60)
            .updated(translationHeight: hourHeight * 2, hourHeight: hourHeight, snapMinutes: 15)
        apply(drag, to: block, store: store)

        #expect(block.startMinutes == 9 * 60)
        #expect(template.activeWeekdays == monWedFri)
        let snapshot = [block.snapshot]
        let reference = Date(timeIntervalSinceReferenceDate: 0)
        for weekday in mondayFirst {
            let items = RoutineWeekLayout.layoutItems(
                blocks: snapshot, activeWeekdays: template.activeWeekdays,
                weekday: weekday, referenceDayStart: reference)
            #expect(items.count == (monWedFri.contains(weekday) ? 1 : 0))
        }
    }
}
