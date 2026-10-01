//
//  RoutineWeekdayActivationTests.swift
//  KadenceTests
//
//  Task P2-T39 — weekday activation (components.md §13.5.4, interactions.md
//  §11.1.1, layouts.md §8.1):
//
//  - `RoutineTemplateStore.setWeekday` adds and removes exactly one weekday;
//  - each change is ONE undo step, named `Add Saturday to Routine` /
//    `Remove Saturday from Routine`, and undo/redo restore the set exactly;
//  - asking for the state a day is already in records nothing;
//  - removing the last active weekday (spec silent — design/GAPS.md G-027)
//    is allowed and leaves an empty set; these tests pin that placeholder;
//  - the column treatment follows the write (the note goes, the underline
//    comes), and the toggle row's display order stays Mon-first.
//
//  Not covered, because it has no seam below SwiftUI: the `motion.viewChange`
//  cross-fade itself, and the row actually taking focus on `⇥`.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

/// Calendar weekday numbers (1 = Sunday … 7 = Saturday).
private let monday = 2, tuesday = 3, wednesday = 4, friday = 6, saturday = 7, sunday = 1
private let monWedFri: Set<Int> = [monday, wednesday, friday]

/// The undo names are spelled from the calendar's locale, so tests pin
/// English rather than depend on the machine running them.
private var english: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.locale = Locale(identifier: "en_US")
    return calendar
}

@MainActor
private func makeTemplateStore() throws -> (RoutineTemplateStore, ModelContext, UndoStack, RoutineTemplate) {
    let container = try ModelContainer(
        for: Event.self, Place.self, RoutineTemplate.self, RoutineBlock.self, TimeWindow.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let undo = UndoStack()
    let template = RoutineTemplate(
        name: "Daily routine", activeWeekdays: monWedFri,
        blocks: [RoutineBlock(title: "Gym", startMinutes: 18 * 60, duration: 3600)])
    context.insert(template)
    try context.save()
    return (RoutineTemplateStore(context: context, undo: undo), context, undo, template)
}

// MARK: - Pure rules

@Suite("RoutineWeekdayActivation — components.md §13.5.4")
struct RoutineWeekdayActivationRuleTests {

    @Test("Undo names are spec-exact, with the full weekday name")
    func undoNames() {
        #expect(RoutineWeekdayActivation.undoName(weekday: saturday, activating: true, calendar: english)
                == "Add Saturday to Routine")
        #expect(RoutineWeekdayActivation.undoName(weekday: saturday, activating: false, calendar: english)
                == "Remove Saturday from Routine")
        #expect(RoutineWeekdayActivation.undoName(weekday: sunday, activating: true, calendar: english)
                == "Add Sunday to Routine")
        #expect(RoutineWeekdayActivation.undoName(weekday: monday, activating: false, calendar: english)
                == "Remove Monday from Routine")
    }

    @Test("applying adds or removes exactly one weekday")
    func applying() {
        #expect(RoutineWeekdayActivation.applying(saturday, active: true, to: monWedFri) == [2, 4, 6, 7])
        #expect(RoutineWeekdayActivation.applying(wednesday, active: false, to: monWedFri) == [2, 6])
        #expect(RoutineWeekdayActivation.applying(monday, active: true, to: monWedFri) == monWedFri)
        #expect(RoutineWeekdayActivation.applying(tuesday, active: false, to: monWedFri) == monWedFri)
    }

    @Test("←/→ move along the Mon-first row and stop at both ends")
    func focusMovement() {
        let row = RoutineWeekLayout.orderedWeekdays(firstWeekday: 2)
        #expect(row == [2, 3, 4, 5, 6, 7, 1])
        #expect(RoutineWeekdayActivation.movingFocus(from: nil, by: 1, in: row) == monday)
        #expect(RoutineWeekdayActivation.movingFocus(from: monday, by: 1, in: row) == tuesday)
        #expect(RoutineWeekdayActivation.movingFocus(from: saturday, by: 1, in: row) == sunday)
        #expect(RoutineWeekdayActivation.movingFocus(from: sunday, by: 1, in: row) == sunday)
        #expect(RoutineWeekdayActivation.movingFocus(from: monday, by: -1, in: row) == monday)
        #expect(RoutineWeekdayActivation.movingFocus(from: sunday, by: -1, in: row) == saturday)
    }
}

// MARK: - The write and its undo step

@Suite("RoutineTemplateStore.setWeekday — one named undo step")
@MainActor
struct RoutineTemplateStoreWeekdayTests {

    @Test("Activating Saturday adds it, as one step named per spec")
    func activate() throws {
        let (store, _, undo, template) = try makeTemplateStore()
        store.setWeekday(saturday, active: true, in: template, calendar: english)

        #expect(template.activeWeekdays == [2, 4, 6, 7])
        #expect(undo.undoSteps.count == 1)
        #expect(undo.undoActionName == "Add Saturday to Routine")
        #expect(undo.undoMenuTitle == "Undo Add Saturday to Routine")
    }

    @Test("Deactivating Wednesday removes it, as one step named per spec")
    func deactivate() throws {
        let (store, _, undo, template) = try makeTemplateStore()
        store.setWeekday(wednesday, active: false, in: template, calendar: english)

        #expect(template.activeWeekdays == [2, 6])
        #expect(undo.undoSteps.count == 1)
        #expect(undo.undoActionName == "Remove Wednesday from Routine")
    }

    @Test("Undo and redo restore the set exactly, and the redo is named too")
    func undoRedoRoundTrip() throws {
        let (store, _, undo, template) = try makeTemplateStore()
        store.setWeekday(saturday, active: true, in: template, calendar: english)

        undo.undo()
        #expect(template.activeWeekdays == monWedFri)
        #expect(undo.redoMenuTitle == "Redo Add Saturday to Routine")
        #expect(!undo.canUndo)

        undo.redo()
        #expect(template.activeWeekdays == [2, 4, 6, 7])
        #expect(undo.undoActionName == "Add Saturday to Routine")
    }

    @Test("Undo of a deactivation restores the weekday")
    func undoDeactivation() throws {
        let (store, _, undo, template) = try makeTemplateStore()
        store.setWeekday(monday, active: false, in: template, calendar: english)
        undo.undo()
        #expect(template.activeWeekdays == monWedFri)
        undo.redo()
        #expect(template.activeWeekdays == [4, 6])
    }

    @Test("Several changes undo one at a time, newest first")
    func stepsAreIndependent() throws {
        let (store, _, undo, template) = try makeTemplateStore()
        store.setWeekday(saturday, active: true, in: template, calendar: english)
        store.setWeekday(monday, active: false, in: template, calendar: english)
        #expect(template.activeWeekdays == [4, 6, 7])
        #expect(undo.undoSteps.map(\.name) == ["Add Saturday to Routine", "Remove Monday from Routine"])

        undo.undo()
        #expect(template.activeWeekdays == [2, 4, 6, 7])
        undo.undo()
        #expect(template.activeWeekdays == monWedFri)
    }

    @Test("Asking for the state a day is already in records no step")
    func noOpPushesNothing() throws {
        let (store, _, undo, template) = try makeTemplateStore()
        store.setWeekday(monday, active: true, in: template, calendar: english)
        store.setWeekday(saturday, active: false, in: template, calendar: english)
        #expect(template.activeWeekdays == monWedFri)
        #expect(!undo.canUndo)
    }

    @Test("Blocks are untouched — they belong to the template, not the column")
    func blocksUntouched() throws {
        let (store, _, _, template) = try makeTemplateStore()
        let before = template.blocks.map(\.id)
        store.setWeekday(saturday, active: true, in: template, calendar: english)
        store.setWeekday(saturday, active: false, in: template, calendar: english)
        #expect(template.blocks.map(\.id) == before)
    }

    @Test("The write persists to the context, not just the in-memory object")
    func persists() throws {
        let (store, context, _, template) = try makeTemplateStore()
        store.setWeekday(saturday, active: true, in: template, calendar: english)
        let id = template.id
        let fetched = try context.fetch(FetchDescriptor<RoutineTemplate>(predicate: #Predicate { $0.id == id }))
        #expect(fetched.first?.activeWeekdays == [2, 4, 6, 7])
    }

    /// SPEC-GAP (design/GAPS.md G-027): the spec gives no rule for the last
    /// active weekday. The placeholder allows it; this pins the placeholder
    /// so a ruling that changes it has to change this test too.
    @Test("Removing the last active weekday (G-027 placeholder): allowed, empty set, one undo restores it")
    func removeLastWeekday() throws {
        let (store, _, undo, template) = try makeTemplateStore()
        store.setWeekday(monday, active: false, in: template, calendar: english)
        store.setWeekday(wednesday, active: false, in: template, calendar: english)
        store.setWeekday(friday, active: false, in: template, calendar: english)

        #expect(template.activeWeekdays.isEmpty)
        #expect(undo.undoActionName == "Remove Friday from Routine")
        // Every column is then inactive and offers its `Add` button.
        for weekday in 1...7 {
            #expect(RoutineColumnTreatment.resolve(
                weekday: weekday, activeWeekdays: template.activeWeekdays, mode: .blocks) == .inactive)
        }

        undo.undo()
        #expect(template.activeWeekdays == [friday])
    }
}

// MARK: - What the column shows afterwards

@Suite("Activation drives the column treatment — components.md §13.5.4")
@MainActor
struct RoutineWeekdayActivationColumnTests {

    @Test("After activation the column loses the note and gains the underline; undo puts them back")
    func columnFollowsWrite() throws {
        let (store, _, undo, template) = try makeTemplateStore()
        let before = RoutineColumnTreatment.resolve(
            weekday: saturday, activeWeekdays: template.activeWeekdays, mode: .blocks)
        #expect(before.showsInactiveNote)
        #expect(before.refusesBlockCreate)

        store.setWeekday(saturday, active: true, in: template, calendar: english)
        let after = RoutineColumnTreatment.resolve(
            weekday: saturday, activeWeekdays: template.activeWeekdays, mode: .blocks)
        #expect(after == .active)
        #expect(!after.showsInactiveNote)
        #expect(!after.recessesHourLines)
        #expect(after.showsHeaderUnderline)

        undo.undo()
        #expect(RoutineColumnTreatment.resolve(
            weekday: saturday, activeWeekdays: template.activeWeekdays, mode: .blocks) == .inactive)
    }

    @Test("After activation the column shows every block in the template")
    func blocksAppearInColumn() throws {
        let (store, _, _, template) = try makeTemplateStore()
        let snapshots = template.blocks.map(\.snapshot)
        let saturdayStart = RoutineWeekLayout.referenceDayStart(weekday: saturday, now: Date())

        #expect(RoutineWeekLayout.layoutItems(
            blocks: snapshots, activeWeekdays: template.activeWeekdays,
            weekday: saturday, referenceDayStart: saturdayStart).isEmpty)

        store.setWeekday(saturday, active: true, in: template, calendar: english)
        let items = RoutineWeekLayout.layoutItems(
            blocks: snapshots, activeWeekdays: template.activeWeekdays,
            weekday: saturday, referenceDayStart: saturdayStart)
        #expect(items.map(\.id) == snapshots.map(\.id))
    }

    @Test("Preview columns stay in Mon-first display order after activating Sunday")
    func orderingStaysMonFirst() throws {
        let (store, _, _, template) = try makeTemplateStore()
        store.setWeekday(sunday, active: true, in: template, calendar: english)
        let mondayFirst = RoutineWeekLayout.orderedWeekdays(firstWeekday: 2)
        #expect(RoutineBlockDrag.previewWeekdays(
            orderedWeekdays: mondayFirst, activeWeekdays: template.activeWeekdays) == [2, 4, 6, 1])
    }
}
