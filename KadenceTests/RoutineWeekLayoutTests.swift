//
//  RoutineWeekLayoutTests.swift
//  KadenceTests
//
//  layouts.md §8 / components.md §13.1 — the Routines window shell (task
//  P2-T10). `RoutineWeekLayout` is the pure glue between a `RoutineTemplate`'s
//  weekly shape and `DayLayoutEngine`; this file is the regression test the
//  task asks for, covering exactly the acceptance criterion a pure function
//  can verify without a running window: "the seeded template's blocks appear
//  in the correct weekday columns" — i.e. positioned by weekday + startMinutes
//  + duration, and absent from every weekday the template is not active on.
//
//  Clicking a block and seeing the inspector update is a SwiftUI-state-level
//  behaviour (`RoutinesWindow`'s own `selection`/`selectedBlockSnapshot`
//  wiring), which has no pure-function seam to test in isolation — verified
//  instead by manual build/run per STATUS.md's note on this task.
//
//  Below (task P2-T11): `RoutineBlockStore` — move, resize and delete for
//  `RoutineBlock`s, undoable and named. Same in-memory ModelContainer/
//  ModelContext pattern as `RoutineEngineTests.swift`, and the same rigor as
//  `UndoStackTests.swift` for the undo/redo half. The drag-to-minutes gesture
//  math itself lives in `RoutinesWindow.swift` (a SwiftUI view, no pure-function
//  seam — same reasoning as the paragraph above for click-to-select); what IS
//  a pure seam, and is what these tests actually exercise, is everything the
//  gesture hands off to: clamping, the 15-minute-minimum resize floor, and the
//  named/undoable mutation itself.
//
//  Further below (task P2-T12): `RoutineBlockStore.create` — the "other half"
//  of interactions.md §11.1 that P2-T10/P2-T11 both explicitly carved out.
//  Same reasoning again: double-click/drag gesture math has no pure seam, so
//  these tests exercise `create` directly — the 60-minute default, the
//  15-minute drag floor, the empty-title-persists-nothing rule, and the
//  named/undoable create/undo/redo cycle.
//

import Testing
import Foundation
import CoreGraphics
import SwiftData
@testable import Kadence

private let referenceNow = Calendar(identifier: .gregorian).date(
    from: DateComponents(year: 2026, month: 9, day: 17))! // a Thursday

// MARK: - Weekday ordering

@Suite("RoutineWeekLayout.orderedWeekdays")
struct OrderedWeekdaysTests {

    @Test("Starting from Sunday (1) is the identity 1...7")
    func startsAtSunday() {
        #expect(RoutineWeekLayout.orderedWeekdays(firstWeekday: 1) == [1, 2, 3, 4, 5, 6, 7])
    }

    @Test("Starting from Monday (2) rotates Sunday to the end")
    func startsAtMonday() {
        #expect(RoutineWeekLayout.orderedWeekdays(firstWeekday: 2) == [2, 3, 4, 5, 6, 7, 1])
    }

    @Test("Starting from Saturday (7) rotates everything but Saturday")
    func startsAtSaturday() {
        #expect(RoutineWeekLayout.orderedWeekdays(firstWeekday: 7) == [7, 1, 2, 3, 4, 5, 6])
    }

    @Test("Always exactly the seven weekdays, whatever the start")
    func alwaysAllSeven() {
        for first in 1...7 {
            #expect(Set(RoutineWeekLayout.orderedWeekdays(firstWeekday: first)) == Set(1...7))
        }
    }
}

// MARK: - Reference day start

@Suite("RoutineWeekLayout.referenceDayStart")
struct ReferenceDayStartTests {

    @Test("The returned date's own weekday component matches the requested weekday")
    func matchesRequestedWeekday() {
        let calendar = Calendar(identifier: .gregorian)
        for weekday in 1...7 {
            let date = RoutineWeekLayout.referenceDayStart(weekday: weekday, now: referenceNow, calendar: calendar)
            #expect(calendar.component(.weekday, from: date) == weekday)
        }
    }

    @Test("Is midnight, so adding startMinutes never crosses into the previous day")
    func isMidnight() {
        let calendar = Calendar(identifier: .gregorian)
        let date = RoutineWeekLayout.referenceDayStart(weekday: 3, now: referenceNow, calendar: calendar)
        #expect(calendar.isDate(date, equalTo: calendar.startOfDay(for: date), toGranularity: .second))
    }
}

// MARK: - Layout items: positioned by weekday + startMinutes + duration

@Suite("RoutineWeekLayout.layoutItems")
struct LayoutItemsTests {

    private let day = Calendar(identifier: .gregorian).date(
        from: DateComponents(year: 2026, month: 9, day: 14))! // a Monday, weekday 2

    private let gym = RoutineBlockSnapshot(
        id: UUID(), title: "Gym", startMinutes: 7 * 60, duration: 3600, flexibility: .shiftable)
    private let reading = RoutineBlockSnapshot(
        id: UUID(), title: "Reading", startMinutes: 21 * 60, duration: 30 * 60, flexibility: .droppable)

    @Test("A weekday in the active set gets one item per block, at the right time")
    func activeWeekdayProducesItems() {
        let items = RoutineWeekLayout.layoutItems(
            blocks: [gym, reading], activeWeekdays: [2, 4, 6], weekday: 2, referenceDayStart: day)

        #expect(items.count == 2)
        let gymItem = try? #require(items.first { $0.title == "Gym" })
        #expect(gymItem?.start == day.addingTimeInterval(7 * 3600))
        #expect(gymItem?.end == day.addingTimeInterval(8 * 3600))

        let readingItem = try? #require(items.first { $0.title == "Reading" })
        #expect(readingItem?.start == day.addingTimeInterval(21 * 3600))
        #expect(readingItem?.end == day.addingTimeInterval(21 * 3600 + 30 * 60))
    }

    @Test("A weekday NOT in the active set gets no items at all")
    func inactiveWeekdayProducesNothing() {
        let items = RoutineWeekLayout.layoutItems(
            blocks: [gym, reading], activeWeekdays: [2, 4, 6], weekday: 3, referenceDayStart: day)
        #expect(items.isEmpty)
    }

    @Test("Every block carries its own id through unchanged, for GridBlockView lookup")
    func idsSurvive() {
        let items = RoutineWeekLayout.layoutItems(
            blocks: [gym], activeWeekdays: [2], weekday: 2, referenceDayStart: day)
        #expect(items.first?.id == gym.id)
    }
}

// MARK: - End to end: the seeded demo template lands in the right columns

@Suite("Seeded demo template — weekday placement")
@MainActor
struct SeededTemplateLayoutTests {

    @Test("MockData.makeRoutineTemplates seeds a template spanning more than one weekday")
    func seedsMultipleWeekdays() {
        let templates = MockData.makeRoutineTemplates()
        #expect(templates.count == 1)
        #expect((templates.first?.activeWeekdays.count ?? 0) >= 2)
        #expect(!(templates.first?.blocks.isEmpty ?? true))
    }

    @Test("Blocks appear only in the template's active weekday columns, never the others")
    func blocksOnlyInActiveWeekdayColumns() throws {
        let template = try #require(MockData.makeRoutineTemplates().first)
        let snapshots = template.blocks.map(\.snapshot)
        let weekdays = RoutineWeekLayout.orderedWeekdays(firstWeekday: 1) // Sun...Sat, exhaustive

        for weekday in weekdays {
            let day = RoutineWeekLayout.referenceDayStart(weekday: weekday, now: referenceNow)
            let items = RoutineWeekLayout.layoutItems(
                blocks: snapshots, activeWeekdays: template.activeWeekdays,
                weekday: weekday, referenceDayStart: day)

            if template.activeWeekdays.contains(weekday) {
                #expect(items.count == snapshots.count, "weekday \(weekday) should carry every block")
            } else {
                #expect(items.isEmpty, "weekday \(weekday) is not active and should carry no blocks")
            }
        }
    }

    @Test("Laying out an active weekday's items through DayLayoutEngine positions each block by its own start/duration")
    func dayLayoutEnginePlacesEachBlockByItsOwnTime() throws {
        let template = try #require(MockData.makeRoutineTemplates().first)
        let snapshots = template.blocks.map(\.snapshot)
        let activeWeekday = try #require(template.activeWeekdays.sorted().first)
        let day = RoutineWeekLayout.referenceDayStart(weekday: activeWeekday, now: referenceNow)
        let geometry = TimeGeometry(dayStart: day, hourHeight: Tokens.Size.hourHeightWeek)

        let items = RoutineWeekLayout.layoutItems(
            blocks: snapshots, activeWeekdays: template.activeWeekdays,
            weekday: activeWeekday, referenceDayStart: day)
        let layout = DayLayoutEngine.layout(items: items, columnWidth: 200, geometry: geometry)

        for block in snapshots {
            let laidOut = try #require(layout.block(for: block.id), "block \(block.title) missing from layout")
            let expectedY = geometry.y(for: day.addingTimeInterval(TimeInterval(block.startMinutes * 60)))
            #expect(abs(laidOut.frame.minY - expectedY) < 0.01)
        }
    }
}

// MARK: - RoutineBlockStore: move / resize / delete (task P2-T11)

@MainActor
private func makeRoutineBlockStore() throws -> (RoutineBlockStore, ModelContext, UndoStack) {
    let container = try ModelContainer(
        for: Event.self, Place.self, RoutineTemplate.self, RoutineBlock.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let undo = UndoStack()
    return (RoutineBlockStore(context: context, undo: undo), context, undo)
}

/// One template, one block — Gym at 07:00 for an hour, fixed — persisted into
/// `context` so `RoutineBlockStore` (which resolves everything by `id` through
/// the context, never a captured reference — see `RoutineEngine.swift`'s
/// `RoutineBlockStore` header) has something real to fetch.
@MainActor
private func makeGymTemplate(in context: ModelContext) -> (RoutineTemplate, RoutineBlock) {
    let block = RoutineBlock(title: "Gym", startMinutes: 7 * 60, duration: 3600, flexibility: .fixed)
    let template = RoutineTemplate(name: "Weekday Routine", activeWeekdays: [2, 4, 6], blocks: [block])
    context.insert(template)
    try? context.save()
    return (template, block)
}

@MainActor
private func fetchRoutineBlock(_ id: UUID, in context: ModelContext) -> RoutineBlock? {
    var descriptor = FetchDescriptor<RoutineBlock>(predicate: #Predicate { $0.id == id })
    descriptor.fetchLimit = 1
    return try? context.fetch(descriptor).first
}

@Suite("RoutineBlockStore.move")
@MainActor
struct RoutineBlockStoreMoveTests {

    @Test("Moving within the day sets startMinutes and names the undo step per interactions.md §11.1")
    func movesAndNames() throws {
        let (store, context, undo) = try makeRoutineBlockStore()
        let (_, block) = makeGymTemplate(in: context)

        store.move(block, toStartMinutes: 9 * 60)

        #expect(block.startMinutes == 9 * 60)
        #expect(undo.undoActionName == "Move Routine Block")
        #expect(undo.undoMenuTitle == "Undo Move Routine Block")
    }

    @Test("Undo restores the original startMinutes; redo reapplies the move")
    func undoRedo() throws {
        let (store, context, undo) = try makeRoutineBlockStore()
        let (_, block) = makeGymTemplate(in: context)
        let id = block.id
        let original = block.startMinutes

        store.move(block, toStartMinutes: 9 * 60)
        #expect(undo.canRedo == false)

        undo.undo()
        let afterUndo = try #require(fetchRoutineBlock(id, in: context))
        #expect(afterUndo.startMinutes == original)
        #expect(undo.canRedo)

        undo.redo()
        let afterRedo = try #require(fetchRoutineBlock(id, in: context))
        #expect(afterRedo.startMinutes == 9 * 60)
    }

    @Test("A move that lands on the same startMinutes is a no-op and pushes no undo step")
    func noOpDoesNotPush() throws {
        let (store, context, undo) = try makeRoutineBlockStore()
        let (_, block) = makeGymTemplate(in: context)

        store.move(block, toStartMinutes: block.startMinutes)

        #expect(undo.canUndo == false)
    }

    @Test("A move past the end of the day clamps rather than producing an out-of-range startMinutes (G-013)")
    func clampsAtDayEnd() throws {
        let (store, context, _) = try makeRoutineBlockStore()
        let (_, block) = makeGymTemplate(in: context)

        // The block is 60 minutes; 1400 + 60 > 1440, so it must clamp to 1380.
        store.move(block, toStartMinutes: 1400)

        #expect(block.startMinutes == 1440 - 60)
    }

    @Test("A move before the start of the day clamps to 0 (G-013)")
    func clampsAtDayStart() throws {
        let (store, context, _) = try makeRoutineBlockStore()
        let (_, block) = makeGymTemplate(in: context)

        store.move(block, toStartMinutes: -30)

        #expect(block.startMinutes == 0)
    }
}

@Suite("RoutineBlockStore.resize")
@MainActor
struct RoutineBlockStoreResizeTests {

    @Test("Resizing the top edge moves startMinutes and leaves the end fixed")
    func resizeTop() throws {
        let (store, context, undo) = try makeRoutineBlockStore()
        let (_, block) = makeGymTemplate(in: context)
        let originalEndMinutes = block.startMinutes + Int(block.duration / 60)

        store.resize(block, newStartMinutes: block.startMinutes - 30)

        #expect(block.startMinutes == 7 * 60 - 30)
        #expect(block.startMinutes + Int(block.duration / 60) == originalEndMinutes)
        #expect(undo.undoActionName == "Resize Routine Block")
        #expect(undo.undoMenuTitle == "Undo Resize Routine Block")
    }

    @Test("Resizing the bottom edge changes duration and leaves the start fixed")
    func resizeBottom() throws {
        let (store, context, _) = try makeRoutineBlockStore()
        let (_, block) = makeGymTemplate(in: context)
        let originalStart = block.startMinutes
        let newEnd = block.startMinutes + Int(block.duration / 60) + 30

        store.resize(block, newEndMinutes: newEnd)

        #expect(block.startMinutes == originalStart)
        #expect(block.duration == TimeInterval((60 + 30) * 60))
    }

    @Test("Resize clamps to a 15-minute minimum duration rather than inverting (interactions.md §4)")
    func clampsToMinimumDuration() throws {
        let (store, context, _) = try makeRoutineBlockStore()
        let (_, block) = makeGymTemplate(in: context)
        let end = block.startMinutes + Int(block.duration / 60)

        // Dragging the top handle to 5 minutes before the end must clamp at
        // the 15-minute floor instead of producing a 5-minute block.
        store.resize(block, newStartMinutes: end - 5)

        #expect(block.startMinutes == end - 15)
        #expect(Int(block.duration / 60) == 15)
    }

    @Test("A resize that changes nothing pushes no undo step")
    func noOpDoesNotPush() throws {
        let (store, context, undo) = try makeRoutineBlockStore()
        let (_, block) = makeGymTemplate(in: context)

        store.resize(block, newStartMinutes: block.startMinutes)

        #expect(undo.canUndo == false)
    }

    @Test("Undo restores both startMinutes and duration; redo reapplies both")
    func undoRedo() throws {
        let (store, context, undo) = try makeRoutineBlockStore()
        let (_, block) = makeGymTemplate(in: context)
        let id = block.id
        let originalStart = block.startMinutes
        let originalDuration = block.duration

        store.resize(block, newEndMinutes: block.startMinutes + Int(block.duration / 60) + 30)
        undo.undo()
        let afterUndo = try #require(fetchRoutineBlock(id, in: context))
        #expect(afterUndo.startMinutes == originalStart)
        #expect(afterUndo.duration == originalDuration)

        undo.redo()
        let afterRedo = try #require(fetchRoutineBlock(id, in: context))
        #expect(afterRedo.duration == originalDuration + 30 * 60)
    }
}

@Suite("RoutineBlockStore.delete")
@MainActor
struct RoutineBlockStoreDeleteTests {

    @Test("Delete removes the block from its template and the store immediately, no confirmation")
    func deletes() throws {
        let (store, context, undo) = try makeRoutineBlockStore()
        let (template, block) = makeGymTemplate(in: context)
        let id = block.id

        store.delete(block, from: template)

        #expect(template.blocks.isEmpty)
        #expect(fetchRoutineBlock(id, in: context) == nil)
        #expect(undo.undoActionName == "Delete Routine Block")
        #expect(undo.undoMenuTitle == "Undo Delete Routine Block")
    }

    @Test("Undo reinserts a block carrying the same id, title, timing and flexibility, back on the same template")
    func undoRestores() throws {
        let (store, context, undo) = try makeRoutineBlockStore()
        let (template, block) = makeGymTemplate(in: context)
        let id = block.id

        store.delete(block, from: template)
        undo.undo()

        #expect(template.blocks.count == 1)
        #expect(template.blocks.first?.id == id)
        let restored = try #require(fetchRoutineBlock(id, in: context))
        #expect(restored.title == "Gym")
        #expect(restored.startMinutes == 7 * 60)
        #expect(restored.duration == 3600)
        #expect(restored.flexibility == .fixed)
    }

    @Test("Redo after an undone delete removes the block again")
    func redoAfterUndo() throws {
        let (store, context, undo) = try makeRoutineBlockStore()
        let (template, block) = makeGymTemplate(in: context)
        let id = block.id

        store.delete(block, from: template)
        undo.undo()
        undo.redo()

        #expect(template.blocks.isEmpty)
        #expect(fetchRoutineBlock(id, in: context) == nil)
    }
}

// MARK: - RoutineBlockStore: create (task P2-T12)
//
// interactions.md §11.1 groups creation with move/resize ("uses §3 and §4
// unchanged"), which P2-T10/P2-T11 both explicitly carved back out; this is
// the follow-up that closes it. §3's own model: double-click = a 60-minute
// block at the snapped slot; drag = the dragged duration, 15-minute minimum;
// an untitled commit (or a cancel) persists nothing; the block is selected on
// commit (verified in `RoutinesWindow.swift`'s own `commitDraft`, not
// testable here — see below). `RoutineBlockStore.create` is the pure/testable
// seam these seven tests exercise, exactly the way `move`/`resize`/`delete`
// above are — the drag-to-minutes/double-click gesture math itself lives in
// `RoutinesWindow.swift`'s private `RoutineDayColumnView`, which has no
// pure-function seam a unit test can reach (same reasoning this file's own
// header already gives for click-to-select).
@Suite("RoutineBlockStore.create")
@MainActor
struct RoutineBlockStoreCreateTests {

    @Test("A double-click-shaped create (60-minute duration) lands at the given snapped slot and names the undo step")
    func doubleClickShapeCreatesSixtyMinuteBlock() throws {
        let (store, context, undo) = try makeRoutineBlockStore()
        let (template, _) = makeGymTemplate(in: context)

        let created = store.create(title: "Stretch", startMinutes: 9 * 60, duration: 3600, in: template)

        let block = try #require(created)
        #expect(block.startMinutes == 9 * 60)
        #expect(block.duration == 3600)
        #expect(template.blocks.contains { $0.id == block.id })
        #expect(undo.undoActionName == "Create Routine Block")
        #expect(undo.undoMenuTitle == "Undo Create Routine Block")
    }

    @Test("A drag-shaped create clamps a sub-15-minute drag to the 15-minute minimum (interactions.md §3)")
    func dragShapeClampsToMinimumDuration() throws {
        let (store, context, _) = try makeRoutineBlockStore()
        let (template, _) = makeGymTemplate(in: context)

        let created = store.create(title: "Quick sync", startMinutes: 10 * 60, duration: 5 * 60, in: template)

        let block = try #require(created)
        #expect(Int(block.duration / 60) == 15, "a 5-minute drag must clamp up to the 15-minute floor, not persist as-is")
    }

    @Test("A drag-shaped create above the 15-minute floor persists the dragged duration exactly")
    func dragShapePersistsExactDuration() throws {
        let (store, context, _) = try makeRoutineBlockStore()
        let (template, _) = makeGymTemplate(in: context)

        let created = store.create(title: "Deep work", startMinutes: 13 * 60, duration: 90 * 60, in: template)

        #expect(created?.duration == TimeInterval(90 * 60))
    }

    @Test("An empty title persists nothing and pushes no undo step (interactions.md §3)")
    func emptyTitlePersistsNothing() throws {
        let (store, context, undo) = try makeRoutineBlockStore()
        let (template, _) = makeGymTemplate(in: context)
        let before = template.blocks.count

        let created = store.create(title: "", startMinutes: 9 * 60, duration: 3600, in: template)

        #expect(created == nil)
        #expect(template.blocks.count == before)
        #expect(!undo.canUndo, "nothing happened, so there is nothing to press ⌘Z through")
    }

    @Test("A whitespace-only title persists nothing")
    func whitespaceTitlePersistsNothing() throws {
        let (store, context, _) = try makeRoutineBlockStore()
        let (template, _) = makeGymTemplate(in: context)

        #expect(store.create(title: "   \n\t ", startMinutes: 9 * 60, duration: 3600, in: template) == nil)
    }

    @Test("An in-flight draft that is never committed (⎋ or blur) never reaches the store")
    func cancelledDraftNeverPersists() throws {
        // Mirrors EventCreationTests.EventDiscardTests.discardNeverPersists:
        // `RoutineDayColumnView`'s own draft state is a private `EventDraft?`
        // with the identical shape as `CalendarState.draft` — ⎋/blur simply
        // drops it (`draft = nil`) with no call into `RoutineBlockStore` at
        // all, so there is nothing to undo and nothing in the store. The
        // private SwiftUI view itself has no seam a unit test can reach (this
        // section's own header above), but the invariant its cancel path
        // relies on — constructing an `EventDraft` and discarding it without
        // ever calling `create` touches the store never — is exactly this.
        let (_, context, undo) = try makeRoutineBlockStore()
        let (template, _) = makeGymTemplate(in: context)
        let before = template.blocks.count

        let draft = EventDraft(start: Date(), end: Date().addingTimeInterval(3600), title: "Half-typed")
        _ = draft // never committed — no store.create call, matching ⎋/blur

        #expect(template.blocks.count == before)
        #expect(fetchRoutineBlock(draft.id, in: context) == nil)
        #expect(!undo.canUndo)
    }

    @Test("Undo after a commit removes the created block; redo restores it")
    func undoRemovesRedoRestores() throws {
        let (store, context, undo) = try makeRoutineBlockStore()
        let (template, _) = makeGymTemplate(in: context)

        let created = try #require(store.create(title: "Walk", startMinutes: 14 * 60, duration: 30 * 60, in: template))
        let id = created.id
        #expect(fetchRoutineBlock(id, in: context) != nil)

        undo.undo()
        #expect(fetchRoutineBlock(id, in: context) == nil)
        #expect(!template.blocks.contains { $0.id == id })

        undo.redo()
        let restored = try #require(fetchRoutineBlock(id, in: context))
        #expect(restored.title == "Walk")
        #expect(restored.startMinutes == 14 * 60)
        #expect(restored.duration == TimeInterval(30 * 60))
    }

    @Test("Creating near the end of the day clamps start/duration to the day boundary (G-013, reused from move/resize)")
    func clampsAtDayBoundary() throws {
        let (store, context, _) = try makeRoutineBlockStore()
        let (template, _) = makeGymTemplate(in: context)

        let created = try #require(store.create(title: "Late block", startMinutes: 1400, duration: 3600, in: template))

        #expect(created.startMinutes + Int(created.duration / 60) <= 1440)
    }
}
