//
//  CalDAVClientTests.swift
//  KadenceTests
//
//  PHASE3-PLAN.md task 7: the fetch, the fallback chain, re-discovery and the
//  cap, through the URLProtocol stub (components.md §20.8.1–§20.8.4, §21.5;
//  caldav-mocks.md §2–§4).
//

import Testing
import Foundation
@testable import Kadence

private let zone = TestClock.zone
private let syncStart = Windows.syncStart(now: TestClock.now, zone: zone)
private let lvplan = SourceCalendar(href: MockCalDAVServer.lvplan, displayName: "LVPlan")
private let pruefungen = SourceCalendar(href: MockCalDAVServer.pruefungen, displayName: "Prüfungen")

private func account(_ calendars: [SourceCalendar] = [lvplan], mode: FetchMode = .report) -> CalDAVAccount {
    CalDAVAccount(server: ServerAddress(host: MockCalDAVServer.host), username: "user01", calendars: calendars,
                  capabilities: SourceCapabilities(fetchMode: mode, timeRangeHonoured: nil, discoveredAt: TestClock.now))
}

private func sync(_ harness: MockHarness, account a: CalDAVAccount = account(), start: Date = syncStart,
                  timeout: TimeInterval = 5) async -> (Result<ScheduleFetchResult, ScheduleSourceError>, Int) {
    let (session, transport) = harness.session(timeout: timeout)
    defer { transport.invalidate() }
    do {
        let result = try await CalDAVScheduleSource.run(account: a, windowStart: start, session: session,
                                                        zone: zone, now: TestClock.now)
        return (.success(result), await session.requestCount)
    } catch {
        return (.failure(error), await session.requestCount)
    }
}

private func feedHash(_ events: [ExternalEvent]) -> String {
    FeedHash.of(events.map { EventHash.of($0, zone: zone) })
}

struct CalDAVClientTests {

    @Test("reportOK: 1 request, REPORT Depth 1 from 20261007T220000Z, 9 objects, mode report, time-range honoured")
    func reportOK() async throws {
        let harness = MockHarness(.reportOK)
        let (result, count) = await sync(harness)
        let r = try result.get()
        #expect(count == 1)
        let reports = harness.records.filter { $0.method == "REPORT" }
        #expect(reports.count == 2 && reports.allSatisfy { $0.depth == "1" })  // + the 401 retry
        #expect(reports[0].bodyText.contains("start=\"20261007T220000Z\"") && !reports[0].bodyText.contains("end="))
        #expect(r.objectCount == 9)
        #expect(r.events.map(\.title) == ["SWEN3-LAB", "EPC-ILV", "INNO3-EL", "SWRM-ILV", "REQEN-EXAM", "UF-ILV",
                                          "RW-EXAM", "CGRMR-ILV", "GLD-EXAM"])
        #expect(r.capabilities.fetchMode == .report && r.capabilities.timeRangeHonoured == true)
        #expect(r.calendarsReadInFully == [MockCalDAVServer.lvplan] && r.failedCalendars.isEmpty)
        #expect(r.problems.isEmpty)
        #expect(harness.wireRulesHold() && harness.sentinelOnlyInAuthorization())
        // §20.8.4's line.
        let line = SourceLogger.syncLine(account: "user01 @ cis.technikum-wien.at", diagnostics: r.diagnostics,
                                               outcome: "feed unchanged")
        #expect(line.hasPrefix("sync user01 @ cis.technikum-wien.at · LVPlan · mode report · requests 1 · "))
        #expect(line.contains(" ms · objects 9 · time-range honoured · ctag — · etags 9 (set "))
        #expect(line.hasSuffix(") · feed unchanged"))
        #expect(!line.contains(caldavSentinel))
    }

    @Test("A server that ignores the time-range: timeRangeHonoured false, and all 12 events")
    func timeRangeIgnored() async throws {
        let (result, _) = await sync(MockHarness(.reportOK, ignoresTimeRange: true))
        let r = try result.get()
        #expect(r.objectCount == 13 && r.events.count == 12)
        #expect(r.capabilities.timeRangeHonoured == false)
    }

    @Test("reportRefused: 3 requests (REPORT 405, PROPFIND, multiget), the unfiltered events, mode multiget, no problem")
    func reportRefused() async throws {
        let harness = MockHarness(.reportRefused)
        let (result, count) = await sync(harness)
        let r = try result.get()
        #expect(count == 3)
        #expect(r.events.count == 12 && r.capabilities.fetchMode == .multiget)
        #expect(r.problems.isEmpty && r.failedCalendars.isEmpty)
        let (all, _) = await sync(MockHarness(.reportOK, ignoresTimeRange: true))
        #expect(r.events == (try all.get()).events)
        #expect(r.diagnostics.ctags == [MockCalDAVServer.ctag])
    }

    @Test("multigetRefused: 3 + n requests one at a time, mode get; CRLF from GET hashes like LF from REPORT")
    func multigetRefused() async throws {
        let harness = MockHarness(.multigetRefused)
        let (result, count) = await sync(harness)
        let r = try result.get()
        #expect(count == 3 + 13)
        #expect(r.capabilities.fetchMode == .get && r.events.count == 12)
        #expect(harness.stub.maxInFlight == 1)
        let (report, _) = await sync(MockHarness(.reportOK, ignoresTimeRange: true))
        #expect(feedHash(r.events) == feedHash(try report.get().events))
    }

    @Test("allRefused: fetchFailed with the chain as its technical line")
    func allRefused() async throws {
        let (result, _) = await sync(MockHarness(.allRefused))
        let r = try result.get()
        #expect(r.failedCalendars.count == 1)
        #expect(r.failedCalendars.first?.1 == .fetchFailed(technical: "REPORT 405 · PROPFIND 207 · calendar-multiget 501 · GET 405"))
        #expect(r.calendarsReadInFully.isEmpty && r.events.isEmpty)
    }

    @Test("overCap: fetchFailed after exactly 300 requests")
    func overCap() async throws {
        let harness = MockHarness(.overCap)
        let (result, count) = await sync(harness)
        let r = try result.get()
        #expect(count == 300)
        #expect(harness.records.filter { $0.method == "GET" }.count == 297)
        #expect(r.failedCalendars.first?.1 == .fetchFailed(
            technical: "Request cap reached (300) reading LVPlan one object at a time"))
        #expect(r.events.isEmpty)
    }

    @Test("Mode memory: a fetch in multiget mode starts at PROPFIND")
    func modeMemory() async throws {
        let harness = MockHarness(.reportRefused)
        let (result, count) = await sync(harness, account: account(mode: .multiget))
        #expect(try result.get().capabilities.fetchMode == .multiget)
        #expect(count == 2)
        #expect(harness.records.first?.method == "PROPFIND")
    }

    @Test("calendarMoved: 1 + 4 + 1 requests, the new href adopted, the events read")
    func calendarMoved() async throws {
        let harness = MockHarness(.calendarMoved)
        let (result, count) = await sync(harness)
        let r = try result.get()
        #expect(count == 6)
        #expect(r.adoptedCalendars.map(\.href) == [MockCalDAVServer.lvplanMoved])
        #expect(r.calendarsReadInFully == [MockCalDAVServer.lvplanMoved])
        #expect(r.events.count == 9 && r.failedCalendars.isEmpty)
    }

    @Test("calendarGone: calendarMissing, nothing read in full")
    func calendarGone() async throws {
        let (result, _) = await sync(MockHarness(.calendarGone))
        let r = try result.get()
        #expect(r.failedCalendars.map(\.1) == [.calendarMissing])
        #expect(r.calendarsReadInFully.isEmpty && r.events.isEmpty)
    }

    @Test("htmlOK: notACalendar")
    func htmlOK() async throws {
        let (result, _) = await sync(MockHarness(.htmlOK))
        #expect(try result.get().failedCalendars.map(\.1) == [.notACalendar])
    }

    @Test("One object with truncated.ics as its calendar-data: one problem, the others read")
    func truncatedObject() async throws {
        var feed = MockHarness.reportCIS()
        feed[12].data = try Fixture.text("truncated.ics")
        let (result, _) = await sync(MockHarness(.reportOK, feed: feed))
        let r = try result.get()
        #expect(r.problems.count == 1)
        #expect(r.problems.first?.technical == "Object obj-13.ics: not calendar data")
        #expect(r.objectCount == 8 && r.calendarsReadInFully == [MockCalDAVServer.lvplan])
    }

    @Test("serverError → serverError; timeout → unreachable")
    func transient() async throws {
        let (error, _) = await sync(MockHarness(.serverError))
        #expect(error.failure == .serverError(503))
        let (timeout, _) = await sync(MockHarness(.timeout), timeout: 0.5)
        #expect(timeout.failure == .unreachable)
    }

    @Test("Two calendars, one failing: the first's events, and only it read in full")
    func twoCalendarsOneFailing() async throws {
        let harness = MockHarness(.multiCalendar) { r in
            r.method == "REPORT" && r.path == MockCalDAVServer.pruefungen && r.hasAuthorization
                ? .response(HTTPResponseSpec(status: 200, headers: ["Content-Type": "text/html"],
                                             body: (try? Fixture.data("html-login.html")) ?? Data()))
                : nil
        }
        let (result, _) = await sync(harness, account: account([lvplan, pruefungen]))
        let r = try result.get()
        #expect(r.events.count == 9)
        #expect(r.calendarsReadInFully == [MockCalDAVServer.lvplan])
        #expect(r.failedCalendars.map(\.0) == [pruefungen] && r.failedCalendars.map(\.1) == [.notACalendar])
    }

    @Test("passwordMissing: no transport call")
    func passwordMissing() async throws {
        let harness = MockHarness(.reportOK)
        let source = CalDAVScheduleSource(account: account(), secrets: InMemorySecretStore(), zone: zone,
                                          now: { TestClock.now }) { harness.stub.transport() }
        await #expect(throws: ScheduleSourceError.passwordMissing) { _ = try await source.fetch(windowStart: syncStart) }
        #expect(harness.records.isEmpty)
    }

    @Test("Secret hygiene in every case: no sentinel in results, errors or problems", arguments: MockCalDAVServer.Case.allCases)
    func hygiene(mockCase: MockCalDAVServer.Case) async throws {
        guard mockCase != .slow && mockCase != .timeout else { return }
        let harness = MockHarness(mockCase)
        let (result, _) = await sync(harness, account: account(mockCase == .multiCalendar ? [lvplan, pruefungen] : [lvplan]))
        for text in texts(of: result) { #expect(!text.contains(caldavSentinel)) }
        if case .success(let r) = result {
            for p in r.problems { #expect(!p.sentence.contains(caldavSentinel) && !(p.technical ?? "").contains(caldavSentinel)) }
        }
        #expect(harness.sentinelOnlyInAuthorization())
        #expect(harness.wireRulesHold())
    }
}

extension Result {
    var failure: Failure? { if case .failure(let f) = self { return f } else { return nil } }
}
