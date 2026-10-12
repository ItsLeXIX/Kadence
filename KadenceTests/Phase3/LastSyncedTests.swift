//
//  LastSyncedTests.swift
//  KadenceTests
//
//  PHASE3-REVIEW.md fix 9 — components.md §19.3 (the status line, amended
//  2026-10-10) and §22.1 (the review source seeded as already imported).
//
//  The review frames showed `Never synced` under "Events from the last sync
//  are kept": the review source was a never-imported source whose first sync
//  was the Import. A real source is created by an Import that read the
//  server, so `{last}` falls back to `importedAt`.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

@MainActor
@Suite(.serialized)
struct LastSyncedTests {

    private let now = TestClock.now
    private let zone = TestClock.zone
    private let imported = TestClock.date("2026-10-08 09:12")

    private func source(state: SourceState, importedAt: Date?, lastSuccessAt: Date?) -> Source {
        let s = Source.connected(id: UUID().uuidString, displayName: "University timetable",
                                 serverURL: "https://cis.technikum-wien.at", username: "user01",
                                 principalHref: nil, calendarHomeHref: nil, calendars: [ReviewMode.calendar],
                                 capabilities: SourceCapabilities(), paletteKey: .blue)
        s.state = state
        s.importedAt = importedAt
        s.lastSuccessAt = lastSuccessAt
        s.lastEventCount = 13
        return s
    }

    @Test("A source with importedAt and no later success reads `Last synced {importedAt}` in every state, never `Never synced`",
          arguments: SourceState.allCases)
    func importedAtIsTheFallback(_ state: SourceState) {
        let s = source(state: state, importedAt: imported, lastSuccessAt: nil)
        #expect(s.lastSyncedAt == imported)
        let p = SourceStatusPresentation(source: s, now: now, zone: zone)
        if state == .upToDate {
            #expect(p.statusLine == "Synced 09:12 · 13 events")
        } else {
            #expect(p.statusLine == "Last synced today 09:12 · 13 events")
        }
        #expect(!p.statusLine.contains("Never synced"))
        #expect(p.body?.contains("{last}") != true && p.body?.contains("never") != true)
        #expect(!p.hoverHelp.contains("Never synced"))
        #expect(p.staleLine?.contains("has not synced yet") != true)
        // The inspector's second line for an event of this source.
        #expect(ImportedInspectorCopy.syncLine(s, now: now)?.contains("Never") != true)
    }

    @Test("A later success wins over the Import; only a source that was never imported reads `Never synced`")
    func laterSuccessAndNever() {
        let later = TestClock.date("2026-10-08 09:42")
        let synced = source(state: .forbidden, importedAt: imported, lastSuccessAt: later)
        #expect(synced.lastSyncedAt == later)
        #expect(SourceStatusPresentation(source: synced, now: now, zone: zone).statusLine == "Last synced today 09:42 · 13 events")
        let never = source(state: .neverSynced, importedAt: nil, lastSuccessAt: nil)
        #expect(never.lastSyncedAt == nil)
        #expect(SourceStatusPresentation(source: never, now: now, zone: zone).statusLine == "Never synced")
        // An Import that ended in a calendar failure set no success: the Import still counts.
        let failed = source(state: .calendarMissing, importedAt: imported, lastSuccessAt: nil)
        let stale = SourceStatusCopy.staleLine(name: failed.displayName, state: failed.state, lastSuccess: failed.lastSyncedAt,
                                               interval: 1800, now: now, zone: zone)
        #expect(stale == "University timetable not synced since today 09:12")
    }

    // MARK: Review `phase3` seeding performs an Import (§22.1)

    private func seeded() throws -> (ModelContext, Source) {
        let context = ModelContext(try ModelContainer(for: Schema(KadenceSchema.models),
                                                      configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
        let undo = UndoStack()
        let secrets = InMemorySecretStore()
        for _ in 0..<2 {   // both windows seed; the second call changes nothing
            ReviewMode.seedIfRequested(.phase3, context: context, now: now, secrets: secrets) {
                RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: now)
            }
        }
        let timetable = try #require(try context.fetch(FetchDescriptor<Source>()).first { $0.id == "timetable" })
        return (context, timetable)
    }

    @Test("Review `phase3` seeding performs an Import: importedAt and lastSuccessAt are the seeding time, the template's 13 events are written")
    func reviewSourceIsSeededAsImported() throws {
        let (context, timetable) = try seeded()
        #expect(timetable.connection == .caldav)
        #expect(timetable.importedAt == now && timetable.lastSuccessAt == now)
        #expect(timetable.state == .upToDate && timetable.feedHash != nil)
        #expect(timetable.lastFeedEventCount == 14 && timetable.lastEventCount == 13)
        #expect(timetable.lastChangeAt == nil)          // the Import is not a change
        #expect(timetable.lastAttemptAt == nil)         // so the launch sync still runs
        let events = SyncApplier.events(of: timetable, in: context)
        #expect(events.count == 13)
        // The seeded `Datenmodellierung` was updated in place, not duplicated.
        #expect(try context.fetch(FetchDescriptor<Event>()).filter { $0.title == "Datenmodellierung" }.count == 1)
        // Nothing reads `Never synced` before any sync has run.
        let p = SourceStatusPresentation(source: timetable, now: now, zone: zone)
        #expect(p.statusLine == "Synced just now · 13 events")
    }

    @Test("After the launch sync fails, the review source shows a last-synced time and its events are in fact kept",
          arguments: [(MockCalDAVServer.Case.forbidden, SourceState.forbidden), (.calendarGone, .calendarMissing),
                      (.unauthorized, .unauthorized), (.serverError, .serverError)])
    func failureCasesShowLastSynced(mockCase: MockCalDAVServer.Case, expected: SourceState) async throws {
        let (context, timetable) = try seeded()
        let secrets = InMemorySecretStore()
        try secrets.save(ReviewMode.password, for: SecretAccount(host: MockCalDAVServer.host, username: "user01"),
                         info: .forSource(id: timetable.id, displayName: timetable.displayName))
        let server = ReviewMode.server(case: mockCase, now: now)
        let later = now.addingTimeInterval(120)
        let coordinator = SyncCoordinator(context: context, secrets: secrets, scheduling: FakeScheduling(), path: FakePath(),
                                          clock: { later }) { account in
            CalDAVScheduleSource(account: account, secrets: secrets, now: { later }) {
                MockCalDAVTransport(server: server, timeout: 0.5)
            }
        }
        coordinator.launched()
        await coordinator.waitUntilIdle()
        #expect(timetable.state == expected)
        // "Events from the last sync are kept" is now true…
        #expect(SyncApplier.events(of: timetable, in: context).count == 13)
        // …and the line under it says when that was.
        let p = SourceStatusPresentation(source: timetable, now: later, zone: zone)
        #expect(p.statusLine == "Last synced today 10:00 · 13 events")
        #expect(!p.statusLine.contains("Never synced"))
    }
}
