//
//  InspectorRenderTests.swift
//  KadenceTests
//
//  Task 16's offscreen renders (§17.2 rule 3): the cancelled inspector
//  (item 20; no review source sends `STATUS:CANCELLED`), and the menu bar
//  popover with an imported NEXT and with the stale line (item 17).
//

import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import Kadence

@MainActor
@Suite(.serialized)
struct InspectorRenderTests {

    private func container() throws -> ModelContainer {
        let c = try ModelContainer(for: Schema(KadenceSchema.models),
                                   configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        Phase3Render.keep.append(c)
        return c
    }

    private func coordinator(_ context: ModelContext) -> SyncCoordinator {
        let c = SyncCoordinator(context: context, secrets: InMemorySecretStore(), scheduling: FakeScheduling(), path: FakePath()) {
            _ in MockScheduleSource(result: .failure(.offline))
        }
        Phase3Render.keep.append(c)
        return c
    }

    private func timetable(_ context: ModelContext, state: SourceState, lastSuccess: Date?) -> Source {
        let s = Source.connected(id: "timetable", displayName: "University timetable",
                                 serverURL: "https://cis.technikum-wien.at", username: "user01", principalHref: nil,
                                 calendarHomeHref: nil, calendars: [ReviewMode.calendar], capabilities: SourceCapabilities(),
                                 paletteKey: .blue)
        s.state = state
        s.lastSuccessAt = lastSuccess
        context.insert(s)
        return s
    }

    @Test("Item 20: the inspector for the cancelled event")
    func inspectorCancelled() throws {
        let c = try container()
        let context = ModelContext(c)
        _ = timetable(context, state: .upToDate, lastSuccess: Date())
        let event = try CanvasRenderTests.cancelledEvent()
        context.insert(event)
        try context.save()
        let store = EventStore(context: context, undo: UndoStack())
        let view = ImportedInspectorDetails(event: event, now: TestClock.now, store: store)
            .padding(Tokens.Spacing.xl)
            .frame(width: 300, alignment: .topLeading)
            .background(Tokens.Color.Surface.inspector)
            .environment(CalendarState())
            .environment(coordinator(context))
            .modelContainer(c)
        #expect(Phase3Render.render("inspector-cancelled", view, size: CGSize(width: 300, height: 420)) != nil)
    }

    private func popoverStore(stale: Bool) throws -> (ModelContainer, Date) {
        let c = try container()
        let context = ModelContext(c)
        let now = Date()
        let start = now.addingTimeInterval(20 * 60)
        let lecture = Event(title: "SWQM-ILV", start: start, end: start + 5400, origin: .imported, sourceKey: .blue,
                            location: Place(name: "HS_A3.15"), sourceID: "timetable", externalID: "k")
        lecture.courseCode = "SWQM-ILV"
        context.insert(lecture)
        _ = timetable(context, state: stale ? .forbidden : .upToDate,
                      lastSuccess: stale ? now.addingTimeInterval(-26 * 3600) : now)
        try context.save()
        return (c, now)
    }

    @Test("Item 17: the popover with an imported NEXT — Done · Open, no Snooze")
    func popoverImportedNext() throws {
        let (c, now) = try popoverStore(stale: false)
        let view = MenuBarPopoverView(initialNow: now)
            .modelContainer(c)
            .environment(UndoStack())
            .environment(CalendarState())
        #expect(Phase3Render.render("popover-imported-next", view, size: CGSize(width: 300, height: 200)) != nil)
    }

    @Test("Item 17: the same popover with the stale line")
    func popoverStaleLine() throws {
        let (c, now) = try popoverStore(stale: true)
        let view = MenuBarPopoverView(initialNow: now)
            .modelContainer(c)
            .environment(UndoStack())
            .environment(CalendarState())
        #expect(Phase3Render.render("popover-stale-line", view, size: CGSize(width: 300, height: 240)) != nil)
    }
}
