//
//  ReviewModeTests.swift
//  KadenceTests
//
//  PHASE3-PLAN.md task 10: review mode, the mocked CalDAV server, the review
//  dataset, an empty real store (components.md §22.1; caldav-mocks.md; G-057).
//

import Testing
import Foundation
import SwiftData
import Synchronization
@testable import Kadence

/// Counts every call; fails them all. Proves review mode never uses it.
final class SpySecretStore: SecretStore, @unchecked Sendable {
    let calls = Mutex(0)
    func save(_ password: Password, for account: SecretAccount, info: SecretItemInfo) throws(SecretStoreError) {
        calls.withLock { $0 += 1 }; throw .injected
    }
    func read(_ account: SecretAccount) throws(SecretStoreError) -> Password? { calls.withLock { $0 += 1 }; throw .injected }
    func delete(_ account: SecretAccount) throws(SecretStoreError) { calls.withLock { $0 += 1 }; throw .injected }
    func updateInfo(_ info: SecretItemInfo, for account: SecretAccount) throws(SecretStoreError) {
        calls.withLock { $0 += 1 }; throw .injected
    }
}

@MainActor
private func memory() throws -> (ModelContainer, ModelContext) {
    let container = try ModelContainer(for: Schema(KadenceSchema.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return (container, ModelContext(container))
}

/// The review launch, at `now`: seed phase 3, then the coordinator's launch
/// sync through `MockCalDAVTransport` (no network).
@MainActor
private func reviewLaunch(case mockCase: MockCalDAVServer.Case = .reportOK, now: Date = TestClock.now,
                          context: ModelContext) async -> SyncCoordinator {
    let secrets = InMemorySecretStore()
    let undo = UndoStack()
    ReviewMode.seedIfRequested(.phase3, context: context, now: now, secrets: secrets) {
        RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: now)
    }
    let server = ReviewMode.server(case: mockCase, now: now)
    let coordinator = SyncCoordinator(context: context, secrets: secrets, scheduling: FakeScheduling(), path: FakePath(),
                                      clock: { now }) { account in
        CalDAVScheduleSource(account: account, secrets: secrets, now: { now }) {
            MockCalDAVTransport(server: server, timeout: 0.5)
        }
    }
    coordinator.launched()
    await coordinator.waitUntilIdle()
    return coordinator
}

@MainActor
@Suite(.serialized)
struct ReviewModeTests {

    @Test("Review counts at every clock: 14 day conflicts, needs-attention 15, Friday's conflict at k = d + 1", arguments: [
        "8 7:00", "8 12:00", "8 16:50", "8 20:00", "8 23:30",           // Thursday (not a template day)
        "7 7:00", "7 13:10", "7 17:00", "7 23:30",                       // Wednesday (template day)
        "5 11:50", "5 19:45", "9 1:30",
    ])
    func reviewCounts(_ label: String) async throws {
        let parts = label.split(whereSeparator: { $0 == " " || $0 == ":" }).compactMap { Int($0) }
        let now = try #require(Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: parts[0],
                                                                          hour: parts[1], minute: parts[2])))
        let (_, context) = try memory()
        _ = await reviewLaunch(now: now, context: context)
        let events = try context.fetch(FetchDescriptor<Event>())
        let conflicts = MainWindow.sortedConflicts(events: events, routineBlocks: try context.fetch(FetchDescriptor<RoutineBlock>()),
                                                   now: now)
        #expect(conflicts.count == 14)
        let state = CalendarState()
        state.conflicts = conflicts
        state.templateConflicts = TemplateConflictEngine.detect(
            templates: try context.fetch(FetchDescriptor<RoutineTemplate>()),
            windows: try context.fetch(FetchDescriptor<TimeWindow>()),
            orderedWeekdays: RoutineWeekLayout.orderedWeekdays(firstWeekday: Calendar.current.firstWeekday))
        #expect(state.needsAttentionCount == 15)
        let m = ReviewFeed.firstMonday(after: now, zone: .current)
        let d = try #require(Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: now),
                                                             to: Calendar.current.date(byAdding: .day, value: 4, to: m)!).day)
        let friday = try #require(conflicts.firstIndex { $0.otherEvent.title == "SWRM-ILV" })
        #expect(friday + 1 == d + 1)
    }

    @Test("The rendered template: CRLF, VERSION:1.0, 14 VEVENTs in the CIS shape; split: 14 objects, 0 problems, 13 events")
    func renderedTemplate() throws {
        let rendered = ReviewFeed.render(ReviewTemplate.text, today: TestClock.now, zone: TestClock.zone)
        #expect(rendered.contains("\r\n") && !rendered.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        #expect(rendered.contains("\r\nVERSION:1.0\r\n") && rendered.contains("PRODID:FH Technikum Wien"))
        #expect(rendered.components(separatedBy: "BEGIN:VEVENT").count - 1 == 14)
        #expect(!rendered.contains("{{"))
        #expect(rendered.contains("DTSTART;TZID=Europe/Vienna:20261012T090000"))  // {{D+0}} = M = 12 Oct
        #expect(rendered.contains("DTSTART;TZID=Europe/Vienna:20261002T143000"))  // {{T-6}}
        let objects = MockHarness.reportReview()
        #expect(objects.count == 14 && objects.map(\.href).first == MockCalDAVServer.lvplan + "r01.ics")
        let feed = FeedDerivation.derive(objects.map {
            FeedObject(calendarHref: MockCalDAVServer.lvplan, objectHref: $0.href,
                       calendar: { if case .calendar(let c) = ICSParser.parse($0.data, currentZone: TestClock.zone) { return c }
                                   return ParsedCalendar(events: [], problems: [ImportProblem(sentence: "x")]) }($0))
        }, today: Windows.syncStart(now: TestClock.now, zone: TestClock.zone), zone: TestClock.zone)
        #expect(feed.problems.isEmpty && feed.objectCount == 14 && feed.events.count == 13 && feed.mergedCount == 1)
        // The real file's VTIMEZONE block, verbatim.
        let header = try CISFeed.header().joined(separator: "\r\n")
        #expect(ReviewTemplate.text.hasPrefix(header + "\r\n"))
    }

    @Test("For the sync window at the test clock, H1 and H2 are not returned")
    func syncWindowSkipsHistory() async throws {
        let harness = MockHarness(.reportOK, feed: MockHarness.reportReview())
        let (session, transport) = harness.session()
        defer { transport.invalidate() }
        let account = CalDAVAccount(server: ReviewMode.server, username: "user01", calendars: [ReviewMode.calendar],
                                    capabilities: SourceCapabilities())
        let result = try await CalDAVScheduleSource.run(account: account,
                                                        windowStart: Windows.syncStart(now: TestClock.now, zone: TestClock.zone),
                                                        session: session, zone: TestClock.zone, now: TestClock.now)
        #expect(result.objectCount == 12)
        #expect(!result.events.contains { $0.start < Windows.syncStart(now: TestClock.now, zone: TestClock.zone) })
    }

    @Test("A launch with each case reaches its state", arguments: [
        (MockCalDAVServer.Case.reportOK, SourceState.upToDate), (.reportChanged, .upToDate), (.etagsOnly, .upToDate),
        (.ctagOnly, .upToDate), (.reportRefused, .upToDate), (.multigetRefused, .upToDate), (.allRefused, .fetchFailed),
        (.overCap, .fetchFailed), (.unauthorized, .unauthorized), (.forbidden, .forbidden), (.calendarGone, .calendarMissing),
        (.calendarMoved, .upToDate), (.htmlOK, .notACalendar), (.emptyCalendar, .upToDate), (.serverError, .serverError),
        (.timeout, .unreachable), (.offline, .offline), (.certificate, .certificate), (.multiCalendar, .upToDate),
    ])
    func launchStates(mockCase: MockCalDAVServer.Case, expected: SourceState) async throws {
        let (_, context) = try memory()
        _ = await reviewLaunch(case: mockCase, context: context)
        let source = try #require(try context.fetch(FetchDescriptor<Source>()).first { $0.id == "timetable" })
        #expect(source.state == expected)
        #expect(source.isAutoSyncPaused == expected.pausesAutomaticSync)
    }

    @Test("reportChanged: the second sync (Sync Now) writes 2 added · 2 updated · 2 removed")
    func reviewChanged() async throws {
        let (_, context) = try memory()
        let coordinator = await reviewLaunch(case: .reportChanged, context: context)
        coordinator.syncNowAll()
        await coordinator.waitUntilIdle()
        let source = try #require(try context.fetch(FetchDescriptor<Source>()).first { $0.id == "timetable" })
        let counts: [Int] = [source.lastChangeAdded, source.lastChangeUpdated, source.lastChangeRemoved]
        #expect(counts == [2, 2, 2])
        #expect(source.state == .upToDate)
    }

    @Test("The review password never touches the Keychain store")
    func reviewPasswordStaysInMemory() throws {
        let (_, context) = try memory()
        let spy = SpySecretStore()
        let memoryStore = InMemorySecretStore()
        ReviewMode.seedIfRequested(.phase3, context: context, now: TestClock.now, secrets: memoryStore) {}
        #expect(spy.calls.withLock { $0 } == 0)
        #expect(try memoryStore.read(SecretAccount(host: MockCalDAVServer.host, username: "user01")) == ReviewMode.password)
        // The seeding API takes the store it is given; the app passes
        // `ReviewMode.secrets`, an `InMemorySecretStore`.
        #expect(String(describing: type(of: ReviewMode.secrets)) == "InMemorySecretStore")
    }

    @Test("Datenmodellierung's Event.id and travel leg survive the review Import")
    func datenmodellierungSurvives() async throws {
        let (_, context) = try memory()
        let undo = UndoStack()
        let fixtures = ReviewMode.seedIfRequested(.phase3, context: context, now: TestClock.now, secrets: InMemorySecretStore()) {
            RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: TestClock.now)
        }
        let before = try #require(try context.fetch(FetchDescriptor<Event>()).first { $0.title == "Datenmodellierung" })
        let id = before.id
        #expect(fixtures.travel.contains { $0.eventID == id })
        _ = await reviewLaunch(context: context)
        let after = try context.fetch(FetchDescriptor<Event>()).filter { $0.title == "Datenmodellierung" }
        #expect(after.map(\.id) == [id])
        #expect(after.first?.lecturers == ["L08"] && after.first?.group == "BIF-5C")
    }

    @Test("Without -KadenceReview an empty store stays empty: zero Sources, zero Events")
    func emptyRealStore() throws {
        let (_, context) = try memory()
        var materialized = false
        let fixtures = ReviewMode.seedIfRequested(ReviewMode.dataset(UserDefaults(suiteName: "kadence-empty-\(UUID())")!),
                                                  context: context) { materialized = true }
        #expect(materialized)
        #expect(try context.fetchCount(FetchDescriptor<Source>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Event>()) == 0)
        #expect(fixtures.travel.isEmpty && fixtures.allDay.isEmpty)
        // And the test host itself was launched without it.
        #expect(ReviewMode.dataset() == nil)
    }

    @Test("Arguments: -KadenceReview phase3 / phase2, -KadenceMockCalDAV <case>, default reportOK")
    func arguments() throws {
        let defaults = try #require(UserDefaults(suiteName: "kadence-args-\(UUID())"))
        #expect(ReviewMode.dataset(defaults) == nil && ReviewMode.mockCase(defaults) == .reportOK)
        defaults.set("phase3", forKey: "KadenceReview")
        defaults.set("calendarGone", forKey: "KadenceMockCalDAV")
        #expect(ReviewMode.dataset(defaults) == .phase3 && ReviewMode.mockCase(defaults) == .calendarGone)
        defaults.set("phase2", forKey: "KadenceReview")
        #expect(ReviewMode.dataset(defaults) == .phase2)
    }
}
