//
//  RedirectProofTests.swift
//  KadenceTests
//
//  PHASE3-REVIEW.md fix 3 — interactions.md §13.1 "What the tests must prove"
//  (tests 1–7); caldav-mocks.md "Redirects that carry the header";
//  components.md §21.4; DECISIONS 2026-10-10 "Kadence builds the Authorization
//  header, so no redirect is ever followed" (DEVIATIONS B40, accepted).
//
//  Kadence sets `Authorization` itself, and a request Foundation re-issues for
//  a redirect carries the headers of the one it replaces. So "the transport
//  never follows a redirect" is a security invariant. These tests put a
//  request that **carries the header** through Foundation's **real** redirect
//  path (the stub's `wasRedirectedTo`) and look at what reaches the stub:
//
//  - through `URLSessionTransport`: nothing at the redirect's target;
//  - through a session whose delegate allows redirects (the control): a
//    request at the target, with `Authorization`. Without that second half
//    the first would prove nothing.
//
//  No network: every request is answered by `StubURLProtocol`.
//  `login.example.invalid` cannot resolve anyway (RFC 2606's reserved TLD).
//

import Testing
import Foundation
@testable import Kadence

nonisolated private let cis = MockCalDAVServer.host
nonisolated private let otherHost = "login.example.invalid"
nonisolated private let zone = TestClock.zone
nonisolated private let lvplan = SourceCalendar(href: MockCalDAVServer.lvplan, displayName: "LVPlan")

/// Which authorised request the server redirects.
nonisolated private enum Step: String, CaseIterable, Sendable {
    /// The `REPORT` of a connect: the session was challenged at D2, so the
    /// `REPORT` carries the header from its first send.
    case report
    /// The `REPORT` of a sync with cached discovery: its first send is
    /// answered `401`, and the **retry** — the first request to carry the
    /// header — is the one redirected.
    case reportRetry
    /// D2's retry after its `401`.
    case d2Retry
    case d3
    case d4

    func matches(_ record: StubRecord) -> Bool {
        switch self {
        case .report, .reportRetry: record.method == "REPORT" && record.path == MockCalDAVServer.lvplan
        case .d2Retry: record.method == "PROPFIND" && record.path == MockCalDAVServer.context
        case .d3: record.method == "PROPFIND" && record.path == MockCalDAVServer.principal
        case .d4: record.method == "PROPFIND" && record.path == MockCalDAVServer.home
        }
    }

    /// `reportRetry` is a sync (cached discovery); the others are a connect.
    var isSync: Bool { self == .reportRetry }
}

nonisolated private enum Destination: String, CaseIterable, Sendable {
    /// `redirectAuthedOffHost`.
    case offHost
    /// `redirectAuthedToHTTP`: the same host, over `http:`.
    case toHTTP

    var location: String {
        switch self {
        case .offHost: "https://login.example.invalid/caldav/"
        case .toHTTP: "http://cis.technikum-wien.at/webdav/lvplan.php/"
        }
    }

    /// §19.1 `redirected`: `otherHost` set → the "sent Kadence to {host}"
    /// body; nil → the `http:` body.
    var expected: ScheduleSourceError {
        switch self {
        case .offHost: .redirected(otherHost: otherHost)
        case .toHTTP: .redirected(otherHost: nil)
        }
    }
}

nonisolated private struct Case: Sendable, CustomTestStringConvertible {
    var step: Step
    var destination: Destination
    var status: Int
    var testDescription: String { "\(step.rawValue) → \(destination.rawValue) \(status)" }

    static let all: [Case] = Step.allCases.flatMap { step in
        Destination.allCases.flatMap { destination in
            [301, 302, 307, 308].map { Case(step: step, destination: destination, status: $0) }
        }
    }
}

/// `reportOK`, with one authorised request answered by a redirect. A request
/// to any other host, or over `http:`, is answered `200` — so if Foundation
/// ever issued one it would be delivered and recorded, not lost.
nonisolated private func harness(redirecting step: Step, to location: String, status: Int) -> MockHarness {
    MockHarness(.reportOK, override: { record in
        guard record.host == cis, record.scheme == "https" else {
            return .response(HTTPResponseSpec(status: 200, body: Data("the redirect's target answered".utf8)))
        }
        guard record.hasAuthorization, step.matches(record) else { return nil }
        return .response(HTTPResponseSpec(status: status, headers: ["Location": location]))
    })
}

/// A connect (D1–D4, then the Import-window `REPORT`) or, for a sync, the
/// `REPORT` alone with cached discovery — on `session`.
nonisolated private func run(_ step: Step, on session: CalDAVSession) async -> Result<Int, ScheduleSourceError> {
    let server = ServerAddress(host: cis)
    do {
        if step.isSync {
            let account = CalDAVAccount(server: server, username: "user01", calendars: [lvplan],
                                        capabilities: SourceCapabilities(fetchMode: .report, timeRangeHonoured: nil,
                                                                         discoveredAt: TestClock.now))
            let result = try await CalDAVScheduleSource.run(account: account,
                                                            windowStart: Windows.syncStart(now: TestClock.now, zone: zone),
                                                            session: session, zone: zone, now: TestClock.now)
            // A redirect ends the calendar as a per-calendar failure or the
            // whole fetch; either way it surfaces as the fetch's error.
            if let failed = result.failedCalendars.first { return .failure(failed.1) }
            return .success(result.objectCount)
        }
        let discovery = try await CalDAVDiscovery.discover(server: server, session: session)
        guard let calendar = discovery.calendars.first,
              let url = URL(string: calendar.href, relativeTo: server.baseURL)?.absoluteURL else { return .failure(.noCalendars) }
        do {
            let fetch = try await CalDAVClient.fetch(calendar: url, displayName: calendar.displayName,
                                                     windowStart: Windows.importStart(now: TestClock.now, zone: zone),
                                                     mode: .report, session: session, zone: zone)
            return .success(fetch.objects.count)
        } catch .failed(let error) {
            return .failure(error)
        } catch {
            return .failure(.calendarMissing)   // `.rediscover`: not a redirect refusal
        }
    } catch {
        return .failure(error)
    }
}

struct RedirectProofTests {

    // MARK: Tests 2, 3, 4 — the real transport

    @Test("An authorised request redirected off-host or to http: is refused — `redirected`, and nothing reaches the target",
          arguments: Case.all)
    private func authorisedRedirectIsRefused(_ c: Case) async throws {
        let harness = harness(redirecting: c.step, to: c.destination.location, status: c.status)
        let (session, transport) = harness.session()
        defer { transport.invalidate() }
        let result = await run(c.step, on: session)

        // The fetch ends `redirected`, with the right body.
        #expect(result == .failure(c.destination.expected))
        #expect(c.destination.expected.state == .redirected)

        let asked = harness.stub.asked
        // The request that was redirected carried the header: this test is
        // about a redirect that *could* leak.
        let redirected = try #require(asked.last)
        #expect(redirected.hasAuthorization && c.step.matches(redirected))
        #expect(redirected.host == cis && redirected.scheme == "https")
        // …and nothing was issued for its target: no request to the other
        // host at all, with or without the header, and none over http.
        #expect(!asked.contains { $0.host == otherHost })
        #expect(!asked.contains { $0.scheme == "http" })
        #expect(asked.allSatisfy { $0.host == cis && $0.scheme == "https" })
        // What the stub delivered is exactly what it was asked.
        #expect(harness.records.count == asked.count)

        // Test 7 holds here too: never before the host's own 401.
        #expect(harness.wireRulesHold())
        // The sentinel is in no record but an `Authorization` to the host.
        #expect(harness.sentinelOnlyInAuthorization())
        for record in asked {
            #expect(!record.url.absoluteString.contains(caldavSentinel) && !record.bodyText.contains(caldavSentinel))
        }
        for text in texts(of: result) { #expect(!text.contains(caldavSentinel)) }
    }

    // MARK: Test 5 — the control

    /// The control runs the sync flow (`reportRetry`): one `REPORT`, its
    /// `401`, and the authorised retry that the server redirects. (A connect
    /// would not get that far here: a session that follows redirects also
    /// follows D1's legitimate `301`, and discovery never sees it.)
    @Test("CONTROL: the same redirect through a session that follows it leaves a request at the target WITH Authorization",
          arguments: [301, 302, 307, 308])
    func controlSeesTheLeak(_ status: Int) async throws {
        let harness = harness(redirecting: .reportRetry, to: Destination.offHost.location, status: status)
        let following = RedirectFollowingTransport(server: harness.stub)
        defer { following.invalidate() }
        let session = CalDAVSession(transport: following, host: cis, username: "user01", password: Password(caldavSentinel))
        _ = await run(.reportRetry, on: session)

        let asked = harness.stub.asked
        let original = try #require(asked.last { $0.host == cis && Step.reportRetry.matches($0) })
        #expect(original.hasAuthorization)
        // The leak, seen: Foundation issued the redirected request to the
        // other host, and it carries the very header Kadence built.
        let leaked = try #require(asked.first { $0.host == otherHost })
        #expect(leaked.hasAuthorization)
        #expect(leaked.authorization == original.authorization)
        #expect(leaked.path == "/caldav/")

        // The real transport, the identical case: nothing at the target.
        let real = realHarness(status)
        let (realSession, transport) = real.session()
        defer { transport.invalidate() }
        #expect(await run(.reportRetry, on: realSession) == .failure(.redirected(otherHost: otherHost)))
        #expect(!real.stub.asked.contains { $0.host == otherHost })
        #expect(real.stub.asked.count == 2)   // the REPORT and its authorised retry
    }

    private func realHarness(_ status: Int) -> MockHarness {
        harness(redirecting: .reportRetry, to: Destination.offHost.location, status: status)
    }

    @Test("CONTROL: https → http through a session that follows it leaves an http request WITH Authorization",
          arguments: [301, 302, 307, 308])
    func controlSeesTheHTTPLeak(_ status: Int) async throws {
        let harness = harness(redirecting: .reportRetry, to: Destination.toHTTP.location, status: status)
        let following = RedirectFollowingTransport(server: harness.stub)
        defer { following.invalidate() }
        let session = CalDAVSession(transport: following, host: cis, username: "user01", password: Password(caldavSentinel))
        _ = await run(.reportRetry, on: session)
        let leaked = try #require(harness.stub.asked.first { $0.scheme == "http" })
        #expect(leaked.host == cis && leaked.hasAuthorization)
    }

    // MARK: Test 6 — the session's own refusal

    @Test("CalDAVSession.send refuses an off-host or http: URL before anything is sent — also once it holds the header")
    func sessionRefusesForeignURLs() async throws {
        let harness = MockHarness(.reportOK)
        let (session, transport) = harness.session()
        defer { transport.invalidate() }
        let foreign = [
            "https://login.example.invalid/caldav/",
            "http://cis.technikum-wien.at/webdav/lvplan.php/",
            "https://cis.technikum-wien.at:8443/webdav/lvplan.php/",
            "https://cis.technikum-wien.at.example.invalid/",
        ].compactMap(URL.init(string:))
        #expect(foreign.count == 4)

        func refuse() async {
            for url in foreign {
                for method in ["GET", "PROPFIND", "REPORT"] {
                    do {
                        _ = try await session.send(HTTPRequest(method: method, url: url))
                        Issue.record("\(method) \(url) was sent")
                    } catch {
                        #expect(error.state == .redirected)
                    }
                }
            }
        }
        // Before any challenge: nothing is asked of the stub at all.
        await refuse()
        #expect(harness.stub.asked.isEmpty)
        #expect(await session.requestCount == 0)

        // After the host challenged (the session now adds the header to its
        // own host's requests): still refused, still nothing asked for them.
        _ = try await CalDAVDiscovery.discover(server: ServerAddress(host: cis), session: session)
        let before = harness.stub.asked
        #expect(before.contains { $0.hasAuthorization })
        await refuse()
        #expect(harness.stub.asked.count == before.count)
        #expect(harness.stub.asked.allSatisfy { $0.host == cis && $0.scheme == "https" })
        #expect(harness.wireRulesHold() && harness.sentinelOnlyInAuthorization())
    }

    // MARK: `redirected` at every step (S-5)

    @Test("A 3xx off-host or to http: at D2, D3 and D4 ends `redirected`, never `noCalDAV`",
          arguments: Case.all.filter { [.d2Retry, .d3, .d4].contains($0.step) })
    private func redirectedAtEveryDiscoveryStep(_ c: Case) async throws {
        let harness = harness(redirecting: c.step, to: c.destination.location, status: c.status)
        let (session, transport) = harness.session()
        defer { transport.invalidate() }
        do {
            _ = try await CalDAVDiscovery.discover(server: ServerAddress(host: cis), session: session)
            Issue.record("discovery went on past a redirect")
        } catch {
            #expect(error == c.destination.expected)
            #expect(error != .noCalDAV)
        }
        #expect(!harness.stub.asked.contains { $0.host == otherHost || $0.scheme == "http" })
    }

    @Test("A same-host https 3xx at D2 is still not followed: `noCalDAV`, one request, no second PROPFIND")
    func sameHostRedirectAtD2() async throws {
        let harness = harness(redirecting: .d2Retry, to: "https://cis.technikum-wien.at/elsewhere/", status: 301)
        let (session, transport) = harness.session()
        defer { transport.invalidate() }
        do {
            _ = try await CalDAVDiscovery.discover(server: ServerAddress(host: cis), session: session)
            Issue.record("discovery went on past a redirect")
        } catch {
            #expect(error == .noCalDAV)
        }
        #expect(!harness.stub.asked.contains { $0.path == "/elsewhere/" })
    }
}
