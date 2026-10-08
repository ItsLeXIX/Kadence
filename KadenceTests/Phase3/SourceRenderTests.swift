//
//  SourceRenderTests.swift
//  KadenceTests
//
//  Task 14's offscreen renders (§17.2 rule 3): the sidebar row in its four
//  states (§22 item 9) and the source popover in `partialImport` with its
//  details expanded (item 10). Live frames come from Scripts/capture-p3.sh.
//

import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import Kadence

@MainActor
@Suite(.serialized)
struct SourceRenderTests {

    private func connected(_ id: String, _ name: String, state: SourceState, key: SourceKey, in context: ModelContext) -> Source {
        let s = Source.connected(id: id, displayName: name, serverURL: "https://cis.technikum-wien.at", username: "user01",
                                 principalHref: nil, calendarHomeHref: nil,
                                 calendars: [SourceCalendar(href: MockCalDAVServer.lvplan, displayName: "LVPlan")],
                                 capabilities: SourceCapabilities(), paletteKey: key)
        s.state = state
        s.lastSuccessAt = Date().addingTimeInterval(-600)
        s.lastEventCount = 13
        context.insert(s)
        return s
    }

    @Test("Item 9: the sidebar row at syncing, upToDate, transient and actionable")
    func sidebarRowStates() async throws {
        let container = try ModelContainer(for: Schema(KadenceSchema.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        Phase3Render.keep.append(container)
        let context = ModelContext(container)
        let rows = [
            connected("a", "University timetable", state: .upToDate, key: .blue, in: context),
            connected("b", "Exams (upToDate)", state: .upToDate, key: .teal, in: context),
            connected("c", "Mail (transient)", state: .unreachable, key: .amber, in: context),
            connected("d", "Coursework (actionable)", state: .forbidden, key: .orange, in: context),
        ]
        rows[0].displayName = "Timetable (syncing)"
        try context.save()
        let gated = GatedSource(.success(ScheduleFetchResult(
            events: [], problems: [], objectCount: 0, mergedCount: 0, calendarsReadInFully: [], failedCalendars: [],
            adoptedCalendars: [], capabilities: SourceCapabilities(), diagnostics: SyncDiagnostics(),
            principalHref: nil, calendarHomeHref: nil)), held: true)
        let started = Date().addingTimeInterval(-2)
        let coordinator = SyncCoordinator(context: context, secrets: InMemorySecretStore(), scheduling: FakeScheduling(),
                                          path: FakePath(), clock: { started }) { _ in gated }
        Phase3Render.keep.append(coordinator)
        coordinator.trigger(.syncNow, sourceID: "a")
        #expect(coordinator.isSyncing(rows[0]))
        let view = List {
            Section {
                ForEach(rows, id: \.id) { SidebarSourceRow(source: $0) }
            } header: { Text("Sources") }
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 24)
        .environment(CalendarState())
        .environment(coordinator)
        .environment(SourcesRouter())
        .modelContainer(container)
        let image = Phase3Render.render("sidebar-row-states", view, size: CGSize(width: 260, height: 170))
        #expect(image != nil)
        #expect(SourceStatusSlot.showsSpinner(started: coordinator.syncStartedAt["a"], now: Date()))
        gated.release()
        await coordinator.waitUntilIdle()
    }

    @Test("Item 10: the source popover in partialImport with details expanded")
    func popoverPartialDetails() throws {
        let container = try ModelContainer(for: Schema(KadenceSchema.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        Phase3Render.keep.append(container)
        let context = ModelContext(container)
        let source = connected("p", "University timetable", state: .partialImport, key: .blue, in: context)
        source.problems = [
            ImportProblem(line: 9, sentence: "SWQM-ILV couldn't be read", technical: "Object obj-07.ics, line 9: DTEND before DTSTART"),
            ImportProblem(sentence: "1 event couldn't be read", technical: "Object obj-11.ics: not calendar data"),
        ]
        source.stateDetail = SourceStatusPresentation.storedDetail(.partialImport, StatusFacts(
            host: "cis.technikum-wien.at", user: "user01", name: "University timetable", calendars: ["LVPlan"], k: 2, n: 14))
        try context.save()
        let coordinator = SyncCoordinator(context: context, secrets: InMemorySecretStore(), scheduling: FakeScheduling(),
                                          path: FakePath()) { _ in MockScheduleSource(result: .failure(.offline)) }
        Phase3Render.keep.append(coordinator)
        let view = SourcePopover(source: source, dismiss: {}, showsDetails: true)
            .environment(coordinator)
            .environment(SourcesRouter())
            .modelContainer(container)
        #expect(Phase3Render.render("source-popover-partial-details", view, size: CGSize(width: 280, height: 300)) != nil)
        #expect(SourceStatusPresentation(source: source, now: Date()).primaryAction == .showDetails)
    }
}
