//
//  MockHarness.swift
//  KadenceTests
//
//  caldav-mocks.md served to the real `URLSessionTransport` through the
//  tests' `URLProtocol` stub: the stub's handler is the app's
//  `MockCalDAVServer` (the same server review mode uses), optionally with a
//  test's own override for one request. Every request is recorded.
//

import Foundation
@testable import Kadence

/// The test sentinel password (PHASE3-PLAN.md common rules), for the CalDAV
/// tests that use this harness.
nonisolated let caldavSentinel = "S3ntinel-pw-⚠"

nonisolated struct MockHarness: Sendable {
    let server: MockCalDAVServer
    let stub: StubServer

    /// `override` answers a request first when it returns non-nil.
    init(_ mockCase: MockCalDAVServer.Case, feed: [MockCalDAVServer.Object]? = nil,
         changed: [MockCalDAVServer.Object] = [], pruefungen: [MockCalDAVServer.Object] = [],
         ignoresTimeRange: Bool = false,
         override: (@Sendable (StubRecord) -> StubReply?)? = nil) {
        let html = (try? Fixture.data("html-login.html")) ?? Data()
        let server = MockCalDAVServer(case: mockCase, password: Password(caldavSentinel),
                                      feed: feed ?? MockHarness.reportCIS(), changed: changed,
                                      pruefungen: pruefungen, html: html, ignoresTimeRange: ignoresTimeRange)
        self.server = server
        stub = StubServer { record in
            if let reply = override?(record) { return reply }
            let request = HTTPRequest(method: record.method, url: record.url, headers: record.headers,
                                      body: record.body.isEmpty ? nil : record.body)
            switch server.respond(request) {
            case .response(let r), .delayed(_, let r):
                return .response(HTTPResponseSpec(status: r.status, headers: r.headers, body: r.body))
            case .failBeforeSend(let code):
                return .failBeforeSend(code)
            case .noAnswer:
                return .noAnswer
            }
        }
    }

    /// A session for one connect or sync, armed with the sentinel.
    func session(password: String? = caldavSentinel, timeout: TimeInterval = 5,
                 cap: Int = CalDAVSession.requestCap) -> (CalDAVSession, URLSessionTransport) {
        let transport = stub.transport(timeout: timeout)
        let session = CalDAVSession(transport: transport, host: MockCalDAVServer.host, username: "user01",
                                    password: password.map(Password.init), cap: cap)
        return (session, transport)
    }

    var records: [StubRecord] { stub.records }

    /// `reportCIS`: the real export cut one VEVENT per object.
    static func reportCIS() -> [MockCalDAVServer.Object] {
        MockCalDAVServer.objects(fromICS: (try? Fixture.text("cis-2026WS-redacted.ics")) ?? "",
                                 hrefPrefix: "obj-", etagPrefix: "cis")
    }

    /// `reportReview` at the test clock (M = 2026-10-12).
    static func reportReview() -> [MockCalDAVServer.Object] {
        ReviewFeed.reportReview(template: ReviewTemplate.text, today: TestClock.now, zone: TestClock.zone)
    }

    static func reportChanged() -> [MockCalDAVServer.Object] {
        ReviewFeed.reportChanged(template: ReviewTemplate.text, today: TestClock.now, zone: TestClock.zone)
    }

    // MARK: Assertions every transport test makes (caldav-mocks.md §4)

    /// Rule 1 and 2: only the CIS host over https; `Authorization` never on
    /// the first request, and only after a 401 from that host.
    func wireRulesHold(passwordWasArmed: Bool = true) -> Bool {
        let r = records
        guard r.allSatisfy({ $0.host == MockCalDAVServer.host && $0.scheme == "https" }) else { return false }
        guard r.first?.hasAuthorization != true else { return false }
        if let firstAuth = r.firstIndex(where: \.hasAuthorization) {
            // The record before the first authorised one was answered 401
            // (the session retries the same request).
            guard firstAuth > 0, r[firstAuth - 1].path == r[firstAuth].path,
                  !r[firstAuth - 1].hasAuthorization else { return false }
        }
        return stub.maxInFlight <= 1
    }

    /// Rule 3: the sentinel appears nowhere but the stub's Authorization record.
    func sentinelOnlyInAuthorization() -> Bool {
        records.allSatisfy { r in
            !r.url.absoluteString.contains(caldavSentinel) && !r.bodyText.contains(caldavSentinel)
                && r.headers.filter { $0.key.lowercased() != "authorization" }.values.allSatisfy { !$0.contains(caldavSentinel) }
        }
    }
}

/// Every text Swift can make of a value, for the secret-hygiene checks.
nonisolated func texts(of value: Any) -> [String] {
    var dumped = ""
    dump(value, to: &dumped)
    return [String(describing: value), String(reflecting: value), dumped]
}
