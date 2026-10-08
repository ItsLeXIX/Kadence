//
//  CalDAVDiscoveryTests.swift
//  KadenceTests
//
//  PHASE3-PLAN.md task 6: D1–D4 through the URLProtocol stub
//  (components.md §20.8.1, §19.1; interactions.md §13.1; caldav-mocks.md §1, §3).
//

import Testing
import Foundation
@testable import Kadence

nonisolated private let cis = ServerAddress(host: "cis.technikum-wien.at")
nonisolated private let home = MockCalDAVServer.home

nonisolated private func discover(_ harness: MockHarness, server: ServerAddress = cis, timeout: TimeInterval = 5)
    async -> (Result<DiscoveryResult, ScheduleSourceError>, Int) {
    let (session, transport) = harness.session(timeout: timeout)
    defer { transport.invalidate() }
    do {
        let result = try await CalDAVDiscovery.discover(server: server, session: session)
        return (.success(result), await session.requestCount)
    } catch {
        return (.failure(error), await session.requestCount)
    }
}

/// A D4 body with one extra response appended.
nonisolated private func d4(with extra: String) -> String {
    MockCalDAVServer.multistatus([MockCalDAVServer.homeResponse,
                                  MockCalDAVServer.calendarResponse(href: MockCalDAVServer.lvplan, name: "LVPlan",
                                                                    components: ["VEVENT", "VTODO"],
                                                                    ctag: MockCalDAVServer.ctag),
                                  MockCalDAVServer.outboxResponse, extra])
}

nonisolated private func answer(_ body: String, status: Int = 207) -> StubReply {
    .response(HTTPResponseSpec(status: status, headers: ["Content-Type": "application/xml; charset=utf-8"],
                               body: Data(body.utf8)))
}

struct CalDAVDiscoveryTests {

    @Test("discoveryOK: exactly LVPlan; home and outbox excluded; 4 requests; D1 unauthenticated; the password only after a 401")
    func discoveryOK() async throws {
        let harness = MockHarness(.reportOK)
        let (result, count) = await discover(harness)
        let found = try result.get()
        #expect(found.calendars.map(\.href) == ["/webdav/lvplan.php/calendars/user01/LVPlan-user01/"])
        #expect(found.calendars.map(\.displayName) == ["LVPlan"])
        #expect(found.calendars.first?.components == ["VEVENT", "VTODO"])
        #expect(found.calendars.first?.ctag == "LVPlan-user01-1791454967")
        #expect(found.principalHref == "/webdav/lvplan.php/principals/user01/")
        #expect(found.calendarHomeHref == home)
        #expect(found.contextURL.absoluteString == "https://cis.technikum-wien.at/webdav/lvplan.php/")
        #expect(count == 4)
        let records = harness.records
        #expect(records.count == 5)  // + D2's 401 retry, which is not counted
        #expect(records[0].method == "GET" && records[0].path == "/.well-known/caldav" && !records[0].hasAuthorization)
        #expect(records[1].method == "PROPFIND" && !records[1].hasAuthorization)
        #expect(records[2].hasAuthorization && records[2].path == records[1].path)
        #expect(records[3].hasAuthorization && records[4].hasAuthorization)  // same sync, after the host challenged
        #expect(records[4].depth == "1" && records[4].path == home)
        #expect(harness.wireRulesHold())
        #expect(harness.sentinelOnlyInAuthorization())
    }

    @Test("multiCalendar: LVPlan, Prüfungen in D4 order; Aufgaben (VTODO only) and inbox excluded")
    func multiCalendar() async throws {
        let (result, _) = await discover(MockHarness(.multiCalendar))
        let found = try result.get()
        #expect(found.calendars.map(\.displayName) == ["LVPlan", "Prüfungen"])
        #expect(found.calendars.map(\.href) == [MockCalDAVServer.lvplan, MockCalDAVServer.pruefungen])
    }

    @Test("D2 shortcut: calendar-home-set at 200 skips D3 (3 requests)")
    func d2Shortcut() async throws {
        let d2 = MockCalDAVServer.d2Body.replacingOccurrences(of: """
                    <d:resourcetype>
                      <d:collection/>
                    </d:resourcetype>
            """, with: """
                    <d:resourcetype>
                      <d:collection/>
                    </d:resourcetype>
                    <cal:calendar-home-set>
                      <d:href>/webdav/lvplan.php/calendars/user01/</d:href>
                    </cal:calendar-home-set>
            """)
        #expect(d2 != MockCalDAVServer.d2Body)
        let harness = MockHarness(.reportOK) { r in
            r.method == "PROPFIND" && r.path == MockCalDAVServer.context && r.hasAuthorization ? answer(d2) : nil
        }
        let (result, count) = await discover(harness)
        #expect(try result.get().calendars.map(\.displayName) == ["LVPlan"])
        #expect(count == 3)
        #expect(!harness.records.contains { $0.path == MockCalDAVServer.principal })
    }

    @Test("A Server with a path skips D1")
    func serverPath() async throws {
        let harness = MockHarness(.reportOK)
        guard case .success(let address) = ServerAddress.parse("https://cis.technikum-wien.at/webdav/lvplan.php/") else {
            Issue.record("the path form was refused"); return
        }
        let (result, count) = await discover(harness, server: address)
        #expect(try result.get().calendars.count == 1)
        #expect(count == 3)
        #expect(!harness.records.contains { $0.path == "/.well-known/caldav" })
    }

    @Test("A missing displayname shows the decoded last segment")
    func missingDisplayName() async throws {
        let response = MockCalDAVServer.calendarResponse(href: home + "Mein%20Kalender/", name: "", components: ["VEVENT"],
                                                         ctag: "x")
            .replacingOccurrences(of: "<d:displayname></d:displayname>", with: "")
        let harness = MockHarness(.reportOK) { r in
            r.method == "PROPFIND" && r.path == home && r.hasAuthorization ? answer(d4(with: response)) : nil
        }
        let (result, _) = await discover(harness)
        #expect(try result.get().calendars.map(\.displayName) == ["LVPlan", "Mein Kalender"])
    }

    @Test("Failures map to their states", arguments: [
        (MockCalDAVServer.Case.wellKnown404, ScheduleSourceError.noCalDAV),
        (.propfindNot207, .noCalDAV),
        (.noCalendars, .noCalendars),
        (.unauthorized, .unauthorized),
        (.forbidden, .forbidden),
        (.certificate, .certificate),
        (.redirectOffHost, .redirected(otherHost: "login.example.invalid")),
        (.redirectToHTTP, .redirected(otherHost: nil)),
        (.offline, .offline),
    ])
    func failures(mockCase: MockCalDAVServer.Case, expected: ScheduleSourceError) async throws {
        let harness = MockHarness(mockCase)
        let (result, _) = await discover(harness)
        #expect(result == .failure(expected))
        #expect(expected.state.rawValue == SourceState(rawValue: expected.state.rawValue)?.rawValue)
        let records = harness.records
        switch mockCase {
        case .unauthorized:
            #expect(records.filter(\.hasAuthorization).count == 1)
            #expect(records.firstIndex(where: \.hasAuthorization) == 2)
        case .certificate, .offline:
            #expect(records.isEmpty)  // nothing was delivered
        case .redirectOffHost:
            #expect(!records.contains { $0.host == "login.example.invalid" })
            #expect(records.count == 1)
        case .redirectToHTTP:
            #expect(!records.contains { $0.scheme == "http" })
            #expect(records.count == 1)
        default:
            break
        }
        #expect(harness.wireRulesHold())
        // Secret hygiene: the error and its texts carry no password.
        for text in texts(of: result) { #expect(!text.contains(caldavSentinel)) }
        #expect(harness.sentinelOnlyInAuthorization())
    }

    @Test("timeout → unreachable")
    func timeout() async throws {
        let harness = MockHarness(.reportOK) { r in r.path == "/.well-known/caldav" ? .noAnswer : nil }
        let (result, _) = await discover(harness, timeout: 0.5)
        #expect(result == .failure(.unreachable))
        #expect(ScheduleSourceError.unreachable.state == .unreachable)
    }

    @Test("An off-host href in D4 is never requested")
    func offHostHref() async throws {
        let evil = MockCalDAVServer.calendarResponse(href: "https://elsewhere.example.invalid/cal/", name: "Evil",
                                                     components: ["VEVENT"], ctag: "x")
        let harness = MockHarness(.reportOK) { r in
            r.method == "PROPFIND" && r.path == home && r.hasAuthorization ? answer(d4(with: evil)) : nil
        }
        let (result, _) = await discover(harness)
        let found = try result.get()
        #expect(found.calendars.map(\.displayName) == ["LVPlan"])
        #expect(found.ignoredHrefs == ["https://elsewhere.example.invalid/cal/"])
        #expect(harness.records.allSatisfy { $0.host == MockCalDAVServer.host })
    }

    @Test("Secret hygiene: a successful result's dump carries no password")
    func hygiene() async throws {
        let (result, _) = await discover(MockHarness(.multiCalendar))
        for text in texts(of: try result.get()) { #expect(!text.contains(caldavSentinel)) }
    }

    @Test("ServerAddress: §12.1's Server rows")
    func serverValidation() {
        func problem(_ s: String) -> ServerAddress.Problem? {
            if case .failure(let p) = ServerAddress.parse(s) { return p }
            return nil
        }
        #expect(problem("") == .empty && problem("   ") == .empty)
        #expect(problem("http://cis.technikum-wien.at") == .http)
        #expect(problem("ftp://cis.technikum-wien.at") == .notAServer)
        #expect(problem("cis technikum") == .notAServer)
        #expect(problem("user01@cis.technikum-wien.at") == .containsUser)
        #expect(problem("https://user01:x@cis.technikum-wien.at") == .containsUser)
        #expect(problem("https://cis.technikum-wien.at/Webdav/Lvplan") == .webdavShare)
        #expect(problem("cis.technikum-wien.at/webdav/lvplan/2026") == .webdavShare)
        #expect(problem("  cis.technikum-wien.at ") == nil)
        #expect(problem("https://cis.technikum-wien.at/webdav/lvplan.php/") == nil)
        if case .success(let a) = ServerAddress.parse("CIS.technikum-wien.at:8443") {
            #expect(a.normalized == "https://cis.technikum-wien.at:8443")
        } else { Issue.record("host:port refused") }
        if case .success(let a) = ServerAddress.parse("cis.technikum-wien.at") {
            #expect(a.normalized == "https://cis.technikum-wien.at" && a.contextURL == nil)
        } else { Issue.record("host refused") }
    }

    @Test("The mock server's D2–D4 bodies parse exactly like caldav-mocks.md's byte-for-byte fixtures")
    func mockBodiesMatchFixtures() throws {
        func parsed(_ text: String) -> [DAVResponse]? { MultistatusParser.parse(Data(text.utf8)) }
        #expect(parsed(MockCalDAVServer.d2Body) == MultistatusParser.parse(try Fixture.data("d2-root-207.xml")))
        #expect(parsed(MockCalDAVServer.d3Body) == MultistatusParser.parse(try Fixture.data("d3-principal-207.xml")))
        let d4 = MockCalDAVServer.multistatus([
            MockCalDAVServer.homeResponse,
            MockCalDAVServer.calendarResponse(href: MockCalDAVServer.lvplan, name: "LVPlan",
                                              components: ["VEVENT", "VTODO"], ctag: MockCalDAVServer.ctag),
            MockCalDAVServer.outboxResponse])
        #expect(parsed(d4) == MultistatusParser.parse(try Fixture.data("d4-home-207.xml")))
        let report = MockCalDAVServer.reportResponse(MockHarness.reportCIS())
        #expect(parsed(report) == MultistatusParser.parse(try Fixture.data("report-cis-2026WS.xml")))
    }
}
