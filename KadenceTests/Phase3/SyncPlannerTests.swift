//
//  SyncPlannerTests.swift
//  KadenceTests
//
//  PHASE3-PLAN.md task 8: change detection by content, windows, guards,
//  deselection, selection/undo/preview, conflicts (components.md §20.1,
//  §20.6, §20.8.3, §20.8.4, guards, §20.9, §20.10, §18.1). Real in-memory
//  ModelContainer; clock 2026-10-08 10:00 Europe/Vienna.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

private let zone = TestClock.zone
private let lvplan = SourceCalendar(href: MockCalDAVServer.lvplan, displayName: "LVPlan")
private let pruefungen = SourceCalendar(href: MockCalDAVServer.pruefungen, displayName: "Prüfungen")

@MainActor
final class SyncFixture {
    let container: ModelContainer
    let context: ModelContext
    let source: Source

    init(calendars: [SourceCalendar] = [lvplan], seedPhase2: Bool = false) throws {
        container = try ModelContainer(for: Schema(KadenceSchema.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        self.context = context
        if seedPhase2 {
            let undo = UndoStack()
            MockData.seedAllIfNeeded(context, now: TestClock.now) {
                RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: TestClock.now)
            }
        }
        let existing = try context.fetch(FetchDescriptor<Source>()).first { $0.id == "timetable" }
        let source = existing ?? Source(id: "timetable")
        source.connection = .caldav
        source.kind = .universityTimetable
        source.displayName = "University timetable"
        source.paletteKey = .blue
        source.serverURL = "https://cis.technikum-wien.at"
        source.username = "user01"
        source.calendars = calendars
        if existing == nil { context.insert(source) }
        try context.save()
        self.source = source
    }

    var account: CalDAVAccount {
        CalDAVAccount(server: ServerAddress(host: MockCalDAVServer.host), username: "user01",
                      calendars: source.calendars, capabilities: source.capabilities)
    }

    var events: [Event] { SyncApplier.events(of: source, in: context).sorted { $0.start < $1.start } }

    func fetch(_ harness: MockHarness, start: Date, now: Date) async throws -> ScheduleFetchResult {
        let (session, transport) = harness.session()
        defer { transport.invalidate() }
        return try await CalDAVScheduleSource.run(account: account, windowStart: start, session: session,
                                                  zone: zone, now: now)
    }

    /// Fetch (Import window for `.import`, sync window otherwise), plan, apply.
    @discardableResult
    func run(_ harness: MockHarness, kind: SyncKind, now: Date = TestClock.now,
             disableStep4: Bool = false) async throws -> (SyncPlan, SyncApplier.Outcome) {
        let start: Date
        if case .sync = kind { start = Windows.syncStart(now: now, zone: zone) }
        else { start = Windows.importStart(now: now, zone: zone) }
        let result = try await fetch(harness, start: start, now: now)
        return try apply(result, kind: kind, now: now, disableStep4: disableStep4)
    }

    @discardableResult
    func apply(_ result: ScheduleFetchResult, kind: SyncKind, now: Date = TestClock.now,
               disableStep4: Bool = false) throws -> (SyncPlan, SyncApplier.Outcome) {
        let plan = SyncPlanner.plan(existing: SyncApplier.snapshot(of: source, in: context, zone: zone),
                                    source: SourceSnapshot(feedHash: source.feedHash,
                                                           lastFeedEventCount: source.lastFeedEventCount,
                                                           calendars: source.calendars, importedAt: source.importedAt),
                                    result: result, kind: kind, now: now, zone: zone, disableStep4: disableStep4)
        let outcome = try SyncApplier.apply(plan, to: source, context: context, now: now)
        return (plan, outcome)
    }

    func event(_ title: String, on day: Int? = nil) -> Event? {
        events.first { e in
            e.title == title && (day.map { Calendar.current.component(.day, from: e.start) == $0 } ?? true)
        }
    }
}

private func result(events: [ExternalEvent] = [], objectCount: Int = 0, read: [String] = [MockCalDAVServer.lvplan],
                    failed: [(SourceCalendar, ScheduleSourceError)] = [],
                    problems: [ImportProblem] = []) -> ScheduleFetchResult {
    ScheduleFetchResult(events: events, problems: problems, objectCount: objectCount, mergedCount: 0,
                        calendarsReadInFully: read, failedCalendars: failed, adoptedCalendars: [],
                        capabilities: SourceCapabilities(), diagnostics: SyncDiagnostics(),
                        principalHref: nil, calendarHomeHref: nil)
}

@MainActor
@Suite(.serialized)
struct SyncPlannerTests {

    // MARK: Import and idempotency

    @Test("Import creates 12 events, 3 of them history, and deletes nothing")
    func importCreates() async throws {
        let f = try SyncFixture()
        let (plan, outcome) = try await f.run(MockHarness(.reportOK), kind: .import)
        #expect(plan.creates.count == 12 && plan.deletes.isEmpty && plan.updates.isEmpty)
        #expect(f.events.count == 12)
        let today = Windows.syncStart(now: TestClock.now, zone: zone)
        #expect(f.events.filter { $0.start < today }.map(\.title) == ["SWQM-ILV", "KOKU-UE", "BPREF-Info"])
        #expect(f.events.allSatisfy { $0.origin == .imported && $0.sourceKey == .blue && $0.sourceID == "timetable" })
        #expect(outcome.deletedIDs.isEmpty)
        #expect(f.source.importedAt == TestClock.now && f.source.feedHash != nil)
        #expect(f.source.lastChangeAt == nil)  // the Import is not a change
        #expect(f.source.state == .upToDate && f.source.lastEventCount == 12 && f.source.lastFeedEventCount == 13)
    }

    @Test("A sync of the same content a day later writes nothing; feedHash re-stored; every Event.id unchanged")
    func sameContentNextDay() async throws {
        let f = try SyncFixture()
        try await f.run(MockHarness(.reportOK), kind: .import)
        let ids = f.events.map(\.id)
        let importHash = f.source.feedHash
        let tomorrow = TestClock.date("2026-10-09 10:00")
        let (plan, outcome) = try await f.run(MockHarness(.reportOK), kind: .sync, now: tomorrow)
        #expect(!plan.writesEvents && !outcome.wrote)
        #expect(f.source.feedHash != importHash)  // the window moved; the new hash is stored
        #expect(f.events.map(\.id) == ids)
        #expect(f.source.lastChangeAt == nil)
        // The third sync of the same content stops at step 4.
        let (third, _) = try await f.run(MockHarness(.reportOK), kind: .sync, now: tomorrow)
        #expect(third.feedUnchanged)
    }

    @Test("etagsOnly: every href and ETag changed → nothing written")
    func etagsOnly() async throws {
        let f = try SyncFixture()
        let harness = MockHarness(.etagsOnly)
        try await f.run(harness, kind: .import)
        let tomorrow = TestClock.date("2026-10-09 10:00")
        let (plan, _) = try await f.run(harness, kind: .sync, now: tomorrow)  // poll 2: renamed hrefs, -b ETags
        #expect(harness.records.contains { $0.path.contains("x-obj-") } == false)  // REPORT returns them, never requests them
        #expect(!plan.writesEvents)
        #expect(f.events.count == 12)
    }

    @Test("ctagOnly: two F1 polls, getctag +55 → the second writes nothing; lastChange unchanged")
    func ctagOnly() async throws {
        let f = try SyncFixture()
        try await f.run(MockHarness(.reportOK), kind: .import)
        let harness = MockHarness(.ctagOnly)
        let first = try await f.fetch(harness, start: Windows.syncStart(now: TestClock.now, zone: zone), now: TestClock.now)
        try f.apply(first, kind: .sync)
        let hashAfterPoll1 = f.source.feedHash
        let change = (f.source.lastChangeAt, f.source.lastChangeAdded, f.source.lastChangeUpdated, f.source.lastChangeRemoved)
        let second = try await f.fetch(harness, start: Windows.syncStart(now: TestClock.now, zone: zone), now: TestClock.now)
        #expect(first.diagnostics.ctags == [MockCalDAVServer.ctag] && second.diagnostics.ctags == [MockCalDAVServer.ctagLater])
        #expect(first.diagnostics.etagSet == second.diagnostics.etagSet)  // multiget content is byte-identical
        #expect(first.capabilities.fetchMode == .multiget && second.capabilities.fetchMode == .multiget)
        let (plan, outcome) = try f.apply(second, kind: .sync)
        #expect(plan.feedUnchanged && !outcome.wrote)
        #expect(f.source.feedHash == hashAfterPoll1)
        #expect(f.source.lastChangeAt == change.0 && f.source.lastChangeAdded == change.1)
        // Step 4 disabled: step 5 still writes nothing.
        let (step5, _) = try f.apply(second, kind: .sync, disableStep4: true)
        #expect(!step5.feedUnchanged && !step5.writesEvents)
    }

    // MARK: The changed feed (§22.1)

    @Test("reportChanged: room move, vanished lecture, lecturer change, co-teacher removal, a new lecture; H1 untouched")
    func changedFeed() async throws {
        let f = try SyncFixture()
        let harness = MockHarness(.reportChanged, feed: MockHarness.reportReview(), changed: MockHarness.reportChanged())
        try await f.run(harness, kind: .import)
        #expect(f.events.count == 13)
        let swen = try #require(f.event("SWEN3-LAB", on: 13))
        swen.status = .done
        let swqm = try #require(f.event("SWQM-ILV", on: 12))
        swqm.status = .skipped
        let swqmID = swqm.id
        let swrmID = try #require(f.event("SWRM-ILV", on: 16)).id
        let h1 = try #require(f.event("SWQM-ILV", on: 2))
        let h1Location = h1.location?.name
        try f.context.save()

        let (plan, _) = try await f.run(harness, kind: .sync)
        // Room move: the old one deleted, the new one created .scheduled.
        let swens = f.events.filter { $0.title == "SWEN3-LAB" && Calendar.current.component(.day, from: $0.start) == 13 }
        #expect(swens.count == 1 && swens.first?.location?.name == "EDV_F4.26" && swens.first?.status == .scheduled)
        // Vanished.
        #expect(f.event("EPC-ILV", on: 15) == nil)
        #expect(f.event("EPC-ILV", on: 22) != nil)
        // Lecturer change in place: id and status kept.
        let swqmAfter = try #require(f.event("SWQM-ILV", on: 12))
        #expect(swqmAfter.id == swqmID && swqmAfter.lecturers == ["L09"] && swqmAfter.status == .skipped)
        // Co-teacher removal in place.
        let swrm = try #require(f.event("SWRM-ILV", on: 16))
        #expect(swrm.id == swrmID && swrm.lecturers == ["L05"])
        #expect(f.events.filter { $0.title == "SWRM-ILV" }.count == 1)
        // New.
        #expect(f.event("KOKU-UE", on: 21) != nil)
        // H1 untouched, no H1'.
        #expect(f.event("SWQM-ILV", on: 2)?.location?.name == h1Location)
        #expect(f.events.filter { $0.title == "SWQM-ILV" && Calendar.current.component(.day, from: $0.start) == 2 }.count == 1)
        #expect(plan.change.map { [$0.added, $0.updated, $0.removed] } == [2, 2, 2])
        #expect(f.source.lastChangeAdded == 2 && f.source.lastChangeUpdated == 2 && f.source.lastChangeRemoved == 2)
        #expect(f.source.lastChangeAt == TestClock.now)
    }

    // MARK: Guards

    @Test("partialImport: creates and updates, no deletions — the old SWEN3-LAB stays beside the new")
    func partialImportGuard() async throws {
        let f = try SyncFixture()
        try await f.run(MockHarness(.reportOK, feed: MockHarness.reportReview()), kind: .import)
        var changed = MockHarness.reportChanged()
        changed.append(MockCalDAVServer.Object(href: MockCalDAVServer.lvplan + "broken.ics", etag: "\"x\"",
                                               data: try Fixture.text("truncated.ics")))
        let (plan, _) = try await f.run(MockHarness(.reportOK, feed: changed), kind: .sync)
        #expect(plan.state == .partialImport && plan.deletes.isEmpty)
        #expect(f.events.filter { $0.title == "SWEN3-LAB" && Calendar.current.component(.day, from: $0.start) == 13 }.count == 2)
        #expect(f.event("KOKU-UE", on: 21) != nil)
        #expect(f.source.state == .partialImport)
    }

    @Test("emptyCalendar after events → emptyFeed, nothing deleted")
    func emptyFeedGuard() async throws {
        let f = try SyncFixture()
        try await f.run(MockHarness(.reportOK), kind: .import)
        let (plan, _) = try await f.run(MockHarness(.emptyCalendar), kind: .sync)
        #expect(plan.state == .emptyFeed && plan.deletes.isEmpty)
        #expect(f.events.count == 12 && f.source.state == .emptyFeed)
        // At the Import an empty calendar is just empty.
        let g = try SyncFixture()
        let (importPlan, _) = try await g.run(MockHarness(.emptyCalendar), kind: .import)
        #expect(importPlan.state == .upToDate && g.events.isEmpty)
    }

    @Test("Two calendars, one calendarMissing: creates and updates from the other, no deletions, feedHash not written")
    func oneCalendarMissing() async throws {
        let f = try SyncFixture(calendars: [lvplan, pruefungen])
        try await f.run(MockHarness(.reportOK, feed: MockHarness.reportReview()), kind: .import)
        let hash = f.source.feedHash
        let changed = MockHarness.reportChanged()
        let feed = FeedDerivation.derive(changed.map {
            FeedObject(calendarHref: MockCalDAVServer.lvplan, objectHref: $0.href,
                       calendar: { if case .calendar(let c) = ICSParser.parse($0.data, currentZone: zone) { return c }
                                   return ParsedCalendar(events: [], problems: []) }($0))
        }, today: Windows.syncStart(now: TestClock.now, zone: zone), zone: zone)
        let (plan, _) = try f.apply(result(events: feed.events, objectCount: feed.objectCount,
                                           failed: [(pruefungen, .calendarMissing)]), kind: .sync)
        #expect(plan.state == .calendarMissing && plan.deletes.isEmpty && !plan.creates.isEmpty)
        #expect(f.source.feedHash == hash && f.source.state == .calendarMissing)
        #expect(f.events.filter { $0.title == "SWEN3-LAB" && Calendar.current.component(.day, from: $0.start) == 13 }.count == 2)
    }

    @Test("Any thrown error → nothing written but the bookkeeping")
    func thrownError() async throws {
        let f = try SyncFixture()
        try await f.run(MockHarness(.reportOK), kind: .import)
        let ids = f.events.map(\.id)
        let hash = f.source.feedHash
        do {
            try await f.run(MockHarness(.serverError), kind: .sync)
            Issue.record("expected an error")
        } catch let error as ScheduleSourceError {
            SyncApplier.recordFailure(error, to: f.source, context: f.context, now: TestClock.now)
        }
        #expect(f.events.map(\.id) == ids && f.source.feedHash == hash)
        #expect(f.source.state == .serverError && f.source.lastAttemptAt == TestClock.now)
        #expect(!f.source.isAutoSyncPaused)
        SyncApplier.recordFailure(.unauthorized, to: f.source, context: f.context, now: TestClock.now)
        #expect(f.source.isAutoSyncPaused)
    }

    @Test("Removing the source deletes its history too")
    func removeSource() async throws {
        let f = try SyncFixture()
        try await f.run(MockHarness(.reportOK), kind: .import)
        let ids = try SyncApplier.remove(f.source, context: f.context)
        #expect(ids.count == 12)
        #expect(try f.context.fetchCount(FetchDescriptor<Event>()) == 0)
        #expect(try f.context.fetchCount(FetchDescriptor<Source>()) == 0)
    }

    // MARK: Edit-mode Save

    private static let pastUnique = """
        BEGIN:VCALENDAR\r\nVERSION:1.0\r\nBEGIN:VEVENT\r\nUID:FHif-5EDV_A5.09L40PRUEF-EXAM20261001T09000020261001T100000\r\n\
        SUMMARY:PRUEF-EXAM  EDV_A5.09 - if-5\r\nDESCRIPTION:PRUEF-EXAM\\nL40\\nif-5\\nEDV_A5.09\r\nLOCATION:EDV_A5.09\r\n\
        DTSTART;TZID=Europe/Vienna:20261001T090000\r\nDTEND;TZID=Europe/Vienna:20261001T100000\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n
        """

    /// The kept calendar's Import-window read begins with the template's H1
    /// (`{{T-6}}` 14:30 = Fri 2 Oct at the test clock): that is the server's
    /// horizon (§20.1, G-080). `pastUnique` (1 Oct) is older than it.
    @Test("Edit Save follows sync rules; deselecting Prüfungen deletes what only it contributed, past included — inside the server's horizon; RW-EXAM stays")
    func editSaveDeselection() async throws {
        let rwExam = try #require(MockHarness.reportReview().last)
        let futureUnique = Self.pastUnique.replacingOccurrences(of: "20261001", with: "20261030")
        // Past, and inside the horizon: Mon 5 Oct.
        let pastInside = Self.pastUnique.replacingOccurrences(of: "20261001", with: "20261005")
        func pObject(_ name: String, _ data: String) -> MockCalDAVServer.Object {
            MockCalDAVServer.Object(href: MockCalDAVServer.pruefungen + name, etag: "\"p\"", data: data)
        }
        let pFeed = [pObject("p1.ics", rwExam.data), pObject("p2.ics", pastInside), pObject("p3.ics", futureUnique)]
        let f = try SyncFixture(calendars: [lvplan, pruefungen])
        try await f.run(MockHarness(.multiCalendar, feed: MockHarness.reportReview(), pruefungen: pFeed), kind: .import)
        #expect(f.events.count == 15)  // 13 + 2 unique; RW-EXAM merged
        #expect(f.events.filter { $0.title == "RW-EXAM" }.count == 1)

        // Edit mode: Prüfungen unchecked; the kept calendar read with the Import window.
        f.source.calendars = [lvplan]
        let kept = try await f.fetch(MockHarness(.multiCalendar, feed: MockHarness.reportReview(), pruefungen: pFeed),
                                     start: Windows.importStart(now: TestClock.now, zone: zone), now: TestClock.now)
        #expect(SyncPlanner.deselectionCount(existing: SyncApplier.snapshot(of: f.source, in: f.context, zone: zone),
                                             keptEvents: kept.events) == 2)
        let (plan, _) = try f.apply(kept, kind: .editSave(deselected: true))
        #expect(plan.deletes.count == 2)
        #expect(f.event("PRUEF-EXAM") == nil && f.events.count == 13)
        #expect(f.events.filter { $0.title == "RW-EXAM" }.count == 1)
        #expect(plan.creates.isEmpty)  // a past event in the fetched data is not created

        // A deselection whose read was not full deletes nothing.
        let g = try SyncFixture(calendars: [lvplan, pruefungen])
        try await g.run(MockHarness(.multiCalendar, feed: MockHarness.reportReview(), pruefungen: pFeed), kind: .import)
        g.source.calendars = [lvplan]
        let (partial, _) = try g.apply(result(events: kept.events, objectCount: kept.objectCount, read: [],
                                              failed: [(lvplan, .fetchFailed(technical: "x"))]),
                                       kind: .editSave(deselected: true))
        #expect(partial.deletes.isEmpty && g.events.count == 15)
    }

    // MARK: The deselection horizon (§20.1 step 2, amended 2026-10-10; G-080)

    /// PHASE3-REVIEW.md fix 9. CIS served only about two and a half weeks of
    /// past on 9 Oct, so an older lecture is absent from every later read —
    /// which says nothing about the calendar it came from.
    @Test("A deselection never deletes an event older than the earliest event the server returned; inside the horizon it deletes as before")
    func deselectionHorizon() async throws {
        let rwExam = try #require(MockHarness.reportReview().last)
        func pObject(_ name: String, _ data: String) -> MockCalDAVServer.Object {
            MockCalDAVServer.Object(href: MockCalDAVServer.pruefungen + name, etag: "\"p\"", data: data)
        }
        // Prüfungen's own events: one older than the horizon (Thu 1 Oct — as
        // served at the Import, weeks ago), one past and inside it (Mon 5
        // Oct), one in the future (30 Oct).
        let older = Self.pastUnique.replacingOccurrences(of: "PRUEF-EXAM", with: "ALT-EXAM")
        let inside = Self.pastUnique.replacingOccurrences(of: "20261001", with: "20261005")
        let future = Self.pastUnique.replacingOccurrences(of: "20261001", with: "20261030").replacingOccurrences(of: "PRUEF-EXAM", with: "NEU-EXAM")
        let pFeed = [pObject("p1.ics", rwExam.data), pObject("p2.ics", older), pObject("p3.ics", inside), pObject("p4.ics", future)]
        let f = try SyncFixture(calendars: [lvplan, pruefungen])
        try await f.run(MockHarness(.multiCalendar, feed: MockHarness.reportReview(), pruefungen: pFeed), kind: .import)
        #expect(f.events.count == 16)
        // …and a lecture of the **kept** calendar that the server has stopped
        // serving: older than everything it still returns.
        let oldLecture = Event(title: "SWQM-ILV", start: TestClock.date("2026-09-14 14:30"), end: TestClock.date("2026-09-14 16:00"),
                               origin: .imported, sourceKey: .blue, sourceID: f.source.id,
                               externalID: "SWQM-ILV HS_A3.15 - BIF-5C|HS_A3.15|20260914T123000Z|20260914T140000Z")
        oldLecture.status = .done
        f.context.insert(oldLecture)
        try f.context.save()
        #expect(f.events.count == 17)

        // Edit mode: Prüfungen unchecked; LVPlan read with the Import window.
        f.source.calendars = [lvplan]
        let kept = try await f.fetch(MockHarness(.multiCalendar, feed: MockHarness.reportReview(), pruefungen: pFeed),
                                     start: Windows.importStart(now: TestClock.now, zone: zone), now: TestClock.now)
        let horizon = try #require(SyncPlanner.horizon(of: kept.events))
        #expect(horizon == TestClock.date("2026-10-02 14:30"))   // the template's H1
        let stored = SyncApplier.snapshot(of: f.source, in: f.context, zone: zone)
        // Step 2's sentence counts what `Save` will delete: the two inside
        // the horizon, not the two older than it.
        #expect(SyncPlanner.deselectionCount(existing: stored, keptEvents: kept.events) == 2)
        #expect(Set(SyncPlanner.deselected(existing: stored, keptEvents: kept.events).map(\.start))
                == [TestClock.date("2026-10-05 09:00"), TestClock.date("2026-10-30 09:00")])

        let (plan, _) = try f.apply(kept, kind: .editSave(deselected: true))
        #expect(plan.deletes.count == 2)
        // Inside the horizon and absent: deleted, as before — past included.
        #expect(f.event("PRUEF-EXAM") == nil && f.event("NEU-EXAM") == nil)
        // Older than the horizon: kept, the kept calendar's lecture with its mark…
        let survivor = try #require(f.event("SWQM-ILV", on: 14))
        #expect(survivor.id == oldLecture.id && survivor.status == .done)
        // …and the unchecked calendar's old exam too: it errs on the side of keeping (§20.1).
        #expect(f.event("ALT-EXAM") != nil)
        #expect(f.events.count == 15)

        // An empty read has no horizon: the deselection deletes nothing in the past.
        let empty = result(events: [], objectCount: 0)
        #expect(SyncPlanner.horizon(of: []) == nil)
        #expect(SyncPlanner.deselectionCount(existing: SyncApplier.snapshot(of: f.source, in: f.context, zone: zone), keptEvents: []) == 0)
        let (none, _) = try f.apply(empty, kind: .editSave(deselected: true))
        #expect(none.deletes.isEmpty && f.events.count == 15)
    }

    @Test("Edit Save never creates a past event the fetch returned")
    func editSavePast() async throws {
        let f = try SyncFixture()
        try await f.run(MockHarness(.reportOK, feed: MockHarness.reportReview()), kind: .import)
        let h1 = try #require(f.event("SWQM-ILV", on: 2))
        f.context.delete(h1)
        try f.context.save()
        let (plan, _) = try await f.run(MockHarness(.reportOK, feed: MockHarness.reportReview()), kind: .editSave(deselected: false))
        #expect(plan.creates.isEmpty && f.event("SWQM-ILV", on: 2) == nil)
    }

    // MARK: Selection, undo, preview (§20.9)

    @Test("A deleted selected event clears the selection; undo steps addressing it are dropped; a sync during a preview is held")
    func selectionUndoPreview() async throws {
        let f = try SyncFixture()
        let harness = MockHarness(.reportChanged, feed: MockHarness.reportReview(), changed: MockHarness.reportChanged())
        try await f.run(harness, kind: .import)
        let epc = try #require(f.event("EPC-ILV", on: 15))
        let state = CalendarState()
        let undo = UndoStack()
        let store = EventStore(context: f.context, undo: undo)
        store.toggleDone(epc)  // a step addressing the event a sync will delete
        let swqm = try #require(f.event("SWQM-ILV", on: 12))
        store.toggleDone(swqm)
        #expect(undo.undoSteps.count == 2)
        state.selectedEventID = epc.id

        // A preview is active: the finished sync is held.
        state.selectedConflictOptionID = UUID()
        let result = try await f.fetch(harness, start: Windows.syncStart(now: TestClock.now, zone: zone), now: TestClock.now)
        var applied = false
        state.applyOrHoldSyncWrite {
            if let (_, outcome) = try? f.apply(result, kind: .sync) {
                SyncApplier.finish(outcome, state: state, undo: undo)
            }
            applied = true
        }
        #expect(!applied && f.event("EPC-ILV", on: 15) != nil)
        state.abandonConflictPreview()
        #expect(applied)
        #expect(f.event("EPC-ILV", on: 15) == nil)
        #expect(state.selectedEventID == nil)
        #expect(undo.undoSteps.count == 1 && undo.undoActionName == "Mark Done")
        // An updated selected event stays selected.
        state.selectedEventID = swqm.id
        SyncApplier.finish(SyncApplier.Outcome(deletedIDs: [], wrote: true), state: state, undo: undo)
        #expect(state.selectedEventID == swqm.id)
    }

    // MARK: Conflicts

    @Test("History never conflicts: an H-event on a past routine occurrence adds nothing; cancelled adds nothing")
    func historyAndCancelledNeverConflict() throws {
        let past = TestClock.date("2026-10-02 14:30")
        let routine = Event(title: "Training", start: past, end: past + 5400, origin: .routine, flexibility: .shiftable)
        let lecture = Event(title: "SWQM-ILV", start: past, end: past + 5400, origin: .imported)
        // Without a clock the Phase 2 engine reports it: the exclusion is new
        // in task 8 (it does not come from materialisation alone).
        #expect(ConflictEngine.detect(events: [routine, lecture], routineBlocks: []).count == 1)
        #expect(ConflictEngine.detect(events: [routine, lecture], routineBlocks: [], today: TestClock.now).isEmpty)
        let future = TestClock.date("2026-10-23 10:00")
        let gym = Event(title: "Gym", start: future, end: future + 3600, origin: .routine)
        let cancelled = Event(title: "Statistik", start: future, end: future + 5400, origin: .imported)
        cancelled.isCancelled = true
        #expect(ConflictEngine.detect(events: [gym, cancelled], routineBlocks: [], today: TestClock.now).isEmpty)
        cancelled.isCancelled = false
        #expect(ConflictEngine.detect(events: [gym, cancelled], routineBlocks: [], today: TestClock.now).count == 1)
    }

    @Test("After the review Import: 14 day conflicts, needs-attention 15; Friday's three rows")
    func reviewConflictCounts() async throws {
        let f = try SyncFixture(seedPhase2: true)
        try await f.run(MockHarness(.reportOK, feed: MockHarness.reportReview()), kind: .import)
        let all = try f.context.fetch(FetchDescriptor<Event>())
        let blocks = try f.context.fetch(FetchDescriptor<RoutineBlock>())
        let conflicts = MainWindow.sortedConflicts(events: all, routineBlocks: blocks, now: TestClock.now)
        #expect(conflicts.count == 14)
        let state = CalendarState()
        state.conflicts = conflicts
        state.templateConflicts = TemplateConflictEngine.detect(
            templates: try f.context.fetch(FetchDescriptor<RoutineTemplate>()),
            windows: try f.context.fetch(FetchDescriptor<TimeWindow>()),
            orderedWeekdays: RoutineWeekLayout.orderedWeekdays(firstWeekday: Calendar.current.firstWeekday))
        #expect(state.needsAttentionCount == 15)
        let friday = try #require(conflicts.first { $0.otherEvent.title == "SWRM-ILV" })
        #expect(friday.routineEvent.title == "Training")
        let rows = ConflictOptionFormatting.rows(for: friday)
        #expect(rows.map(\.title) == ["Shift Training 45 min later", "Shorten Training to 45 min", "Skip Training today"])
        #expect(friday.options.first?.isRecommended == true)
        // k = d + 1, d = (M + 4) − today = 8.
        #expect(conflicts.firstIndex { $0.id == friday.id }.map { $0 + 1 } == 9)
    }
}
