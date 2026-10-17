//
//  MoodleFeedTransportTests.swift
//  KadenceTests
//
//  PHASE3-SLICE3-PLAN.md task 5 — components.md §34.1–§34.3, §33.4
//  (obligations 2 and 3); interactions.md §16.1 "The URL on the wire";
//  moodle-mocks.md M3, M4 "Other cases".
//
//  Two harnesses, no network:
//  - `MockFeedTransport` answers every M1/M3 case in memory (as review mode);
//  - the `URLProtocol` stub behind the app's real `URLSessionTransport`
//    (feed configuration) proves the redirect rule through Foundation's real
//    redirect path, with a control session that follows — the test of the
//    test (§43.3).
//

import Testing
import Foundation
@testable import Kadence

private typealias F = MoodleFixture

extension StubServer {
    /// The app's feed transport, wired to this stub only.
    func feedTransport(timeout: TimeInterval = 5) -> URLSessionTransport {
        URLSessionTransport(requestTimeout: timeout, cookies: false, protocolClasses: [StubURLProtocol.self]) { c in
            var headers = c.httpAdditionalHeaders ?? [:]
            headers[StubURLProtocol.tokenHeader] = self.token
            c.httpAdditionalHeaders = headers
        }
    }
}

private func mockURL() throws -> MoodleFeedURL { try #require(MoodleMock.url) }

/// A fetch of `feedCase` through the mock; the source reads the URL from an
/// in-memory secret store.
private func fetch(_ feedCase: MoodleFeedCase) async throws -> (Result<FeedFetch, ScheduleSourceError>, MockFeedTransport) {
    let mock = MockFeedTransport(case: feedCase, base: F.text)
    let secrets = InMemorySecretStore()
    try secrets.saveFeedURL(try mockURL(), sourceID: "moodle", label: "Kadence — Moodle")
    let source = MoodleFeedSource(sourceID: "moodle", secrets: secrets, zone: F.zone) { mock }
    do {
        return (.success(try await source.fetch(windowStart: .distantPast)), mock)
    } catch {
        return (.failure(error), mock)
    }
}

private func state(_ result: Result<FeedFetch, ScheduleSourceError>) -> SourceState {
    switch result {
    case .success: .upToDate
    case .failure(let error): error.state
    }
}

/// The stub's M3 answers for the real-transport tests.
private func stubAnswer(_ feedCase: MoodleFeedCase) -> @Sendable (StubRecord) -> StubReply {
    { record in
        let body = F.data
        switch feedCase {
        case .feedRedirectSameHost:
            if record.url.query()?.contains("lang=en") == true {
                return .response(HTTPResponseSpec(status: 200, headers: ["Content-Type": "text/calendar"], body: body))
            }
            return .response(HTTPResponseSpec(status: 302, headers: ["Location": record.url.absoluteString + "&lang=en",
                                                                      "Set-Cookie": "MoodleSession=abc123; Secure"]))
        case .feedRedirectTwice:
            return .response(HTTPResponseSpec(status: 302, headers: ["Location": record.url.absoluteString + "&lang=en"]))
        case .feedRedirectCrossHost:
            if record.host == "login.example.invalid" {
                return .response(HTTPResponseSpec(status: 200, headers: ["Content-Type": "text/html"], body: MockFeedTransport.signInPage))
            }
            return .response(HTTPResponseSpec(status: 302, headers: ["Location": "https://login.example.invalid/sso?return=%2Fcalendar"]))
        case .feedRedirectHTTP:
            if record.scheme == "http" {
                return .response(HTTPResponseSpec(status: 200, headers: ["Content-Type": "text/calendar"], body: body))
            }
            var parts = URLComponents(url: record.url, resolvingAgainstBaseURL: false)
            parts?.scheme = "http"
            return .response(HTTPResponseSpec(status: 301, headers: ["Location": parts?.string ?? ""]))
        default:
            return .response(HTTPResponseSpec(status: 200, headers: ["Content-Type": "text/calendar"], body: body))
        }
    }
}

private func stubFetch(_ server: StubServer) async -> Result<FeedFetch, ScheduleSourceError> {
    let transport = server.feedTransport()
    defer { transport.invalidate() }
    do {
        return .success(try await MoodleFeedFetcher(transport: transport, zone: F.zone).fetch(try mockURL()))
    } catch let error as ScheduleSourceError {
        return .failure(error)
    } catch {
        return .failure(.unreachable)
    }
}

struct MoodleFeedTransportTests {

    @Test("Every M3 case (and M1's feedHuge) → its state, as moodle-mocks.md M4's Other cases table",
          arguments: [
            (MoodleFeedCase.feedOK, SourceState.upToDate), (.feedHTML, .notACalendar), (.feedError200, .notACalendar),
            (.feed401, .unauthorized), (.feed403, .forbidden), (.feed404, .feedNotFound), (.feed410, .feedNotFound),
            (.feed500, .serverError), (.feed503, .serverError), (.feed429, .serverError),
            (.feedRedirectSameHost, .upToDate), (.feedRedirectTwice, .redirected), (.feedRedirectCrossHost, .redirected),
            (.feedRedirectHTTP, .redirected), (.feedTLS, .certificate), (.feedOffline, .offline),
            (.feedTimeout, .unreachable), (.feedRefused, .unreachable), (.feedHuge, .notACalendar),
          ])
    func states(_ feedCase: MoodleFeedCase, _ expected: SourceState) async throws {
        let (result, mock) = try await fetch(feedCase)
        #expect(state(result) == expected)
        // No recorded request carries Authorization or Cookie; every one went
        // to the feed's own host over https.
        for record in mock.records {
            #expect(record.header("Authorization") == nil && record.header("Cookie") == nil)
            #expect(record.host == "moodle.technikum-wien.at" && record.scheme == "https" && record.method == "GET")
            #expect(record.header("Accept") == "text/calendar, */*;q=0.1")
        }
        switch feedCase {
        case .feedTLS, .feedOffline: #expect(mock.records.isEmpty)
        case .feedRedirectSameHost: #expect(mock.records.count == 2)
        case .feedRedirectTwice: #expect(mock.records.count == 2)
        default: #expect(mock.records.count == 1)
        }
    }

    @Test("serverError carries its code; redirected carries the other host (or nil for http:)")
    func details() async throws {
        for (feedCase, code) in [(MoodleFeedCase.feed500, 500), (.feed503, 503), (.feed429, 429)] {
            #expect(try await fetch(feedCase).0.failure == .serverError(code))
        }
        #expect(try await fetch(.feedRedirectCrossHost).0.failure == .redirected(otherHost: "login.example.invalid"))
        #expect(try await fetch(.feedRedirectHTTP).0.failure == .redirected(otherHost: nil))
        let ok = try await fetch(.feedRedirectSameHost).0
        #expect((try? ok.get())?.feed.items.count == 29 && (try? ok.get())?.requests == 2)
    }

    @Test("urlMissing: no Keychain item (or an unreadable one) → urlMissing and no request")
    func urlMissing() async throws {
        let mock = MockFeedTransport(case: .feedOK, base: F.text)
        let secrets = InMemorySecretStore()
        let source = MoodleFeedSource(sourceID: "moodle", secrets: secrets, zone: F.zone) { mock }
        await #expect(throws: ScheduleSourceError.urlMissing) { try await source.fetch(windowStart: .distantPast) }
        try secrets.saveFeedURL(try mockURL(), sourceID: "moodle", label: "Kadence — Moodle")
        secrets.failNext("readFeed")
        await #expect(throws: ScheduleSourceError.urlMissing) { try await source.fetch(windowStart: .distantPast) }
        #expect(mock.records.isEmpty)
    }

    @Test("feedRedirectCrossHost through the real transport: the stub records no request to login.example.invalid; the control that follows does")
    func crossHostProof() async throws {
        let server = StubServer(stubAnswer(.feedRedirectCrossHost))
        let result = await stubFetch(server)
        #expect(result.failure == .redirected(otherHost: "login.example.invalid"))
        #expect(!server.asked.contains { $0.host == "login.example.invalid" })
        #expect(server.asked.count == 1)

        // The test of the test: a session that follows redirects, the same stub.
        let control = StubServer(stubAnswer(.feedRedirectCrossHost))
        let following = RedirectFollowingTransport(server: control)
        defer { following.invalidate() }
        let request = try #require(FeedRequest.get(try mockURL()))
        _ = try? await following.send(request)
        #expect(control.asked.contains { $0.host == "login.example.invalid" })
    }

    @Test("feedRedirectHTTP: no http request; feedRedirectSameHost: 2 requests, both to the host, no Cookie; feedRedirectTwice: redirected")
    func otherRedirects() async throws {
        let http = StubServer(stubAnswer(.feedRedirectHTTP))
        #expect(await stubFetch(http).failure == .redirected(otherHost: nil))
        #expect(!http.asked.contains { $0.scheme == "http" } && http.asked.count == 1)

        let same = StubServer(stubAnswer(.feedRedirectSameHost))
        let ok = await stubFetch(same)
        #expect((try? ok.get())?.feed.items.count == 29)
        #expect(same.asked.count == 2 && same.asked.allSatisfy { $0.host == "moodle.technikum-wien.at" && $0.scheme == "https" })
        // The first answer set a cookie: §33.4 obligation 3 — the second
        // request does not carry it. And no request carries Authorization.
        #expect(same.asked.allSatisfy { r in !r.headers.keys.contains { $0.lowercased() == "cookie" } && !r.hasAuthorization })

        let twice = StubServer(stubAnswer(.feedRedirectTwice))
        #expect(await stubFetch(twice).failure == .redirected(otherHost: "moodle.technikum-wien.at"))
        #expect(twice.asked.count == 2)
    }

    @Test("A URLError holding the mock URL in failingURL and NSErrorFailingURLStringKey, per mapped code: the right state, and no line or description with the URL",
          arguments: [
            (URLError.Code.notConnectedToInternet, SourceState.offline), (.timedOut, .unreachable),
            (.cannotFindHost, .unreachable), (.cannotConnectToHost, .unreachable), (.networkConnectionLost, .unreachable),
            (.dnsLookupFailed, .unreachable), (.serverCertificateUntrusted, .certificate),
            (.serverCertificateHasUnknownRoot, .certificate), (.secureConnectionFailed, .certificate),
          ])
    func urlErrors(_ code: URLError.Code, _ expected: SourceState) async throws {
        let url = try mockURL()
        let raw = MoodleMock.urlString
        let error = URLError(code, userInfo: [NSURLErrorFailingURLErrorKey: URL(string: raw) as Any,
                                              NSURLErrorFailingURLStringErrorKey: raw,
                                              NSLocalizedDescriptionKey: "The request to \(raw) failed."])
        #expect(error.failingURL?.absoluteString == raw)
        let lines = LockedLines()
        let token = SourceLogger.shared.addSink { lines.append($0) }
        defer { SourceLogger.shared.removeSink(token) }
        let server = StubServer { _ in .failBeforeSendError(error) }
        let result = await stubFetch(server)
        #expect(state(result) == expected)
        if case .failure(let failure) = result {
            SourceLogger.shared.feedState(display: url.displayForm, state: failure.state)
            for text in [String(describing: failure), String(reflecting: failure), "\(failure.state)"] {
                #expect(!F.leaks(text), "\(text)")
            }
        }
        #expect(lines.all.contains("state moodle.technikum-wien.at/… · \(expected.rawValue)"))
        #expect(!lines.all.contains { F.leaks($0) })
    }

    @Test("The feed configuration: ephemeral, no cache, no credential storage, no cookies; redirects never followed by Foundation")
    func configuration() {
        let c = URLSessionTransport.configuration(requestTimeout: 30, cookies: false)
        #expect(c.urlCache == nil && c.urlCredentialStorage == nil && c.httpCookieStorage == nil)
        #expect(!c.httpShouldSetCookies && c.httpCookieAcceptPolicy == .never)
        #expect(c.timeoutIntervalForRequest == 30 && c.requestCachePolicy == .reloadIgnoringLocalCacheData)
        // The CalDAV configuration is unchanged.
        let caldav = URLSessionTransport.configuration(requestTimeout: 30)
        #expect(caldav.httpShouldSetCookies && caldav.httpCookieAcceptPolicy == .always)
        #expect(MoodleFeedFetcher.timeout == 30 && MoodleFeedFetcher.maxBytes == 20 * 1_048_576)
    }

    @Test("Source scan: withRequestURLString has exactly one call site, in MoodleFeedTransport.swift")
    func oneCallSite() throws {
        let root = Fixture.repoRoot.appendingPathComponent("Kadence")
        var sites: [String] = []
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift", url.lastPathComponent != "MoodleFeedURL.swift" else { continue }
            for (n, line) in try String(contentsOf: url, encoding: .utf8).split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
                if code.contains(".withRequestURLString") { sites.append("\(url.lastPathComponent):\(n + 1)") }
            }
        }
        #expect(sites.count == 1 && sites.allSatisfy { $0.hasPrefix("MoodleFeedTransport.swift:") }, "\(sites)")
        // No file under Kadence/ logs a URLError's description.
        var described: [String] = []
        let all = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = all?.nextObject() as? URL {
            guard url.pathExtension == "swift" else { continue }
            for line in try String(contentsOf: url, encoding: .utf8).split(separator: "\n") {
                let code = line.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
                if code.contains("localizedDescription") || code.contains("failingURL") { described.append(url.lastPathComponent) }
            }
        }
        #expect(described.isEmpty, "\(described)")
    }

    @Test("The factory: test-host and review launches construct only the mock; a normal launch the feed URLSession")
    @MainActor
    func factory() {
        ServiceLaunchLog.reset()
        _ = FeedTransports.make(for: .testHost)
        _ = FeedTransports.make(for: .review(.empty))
        #expect(ServiceLaunchLog.constructed == ["MockFeedTransport", "MockFeedTransport"])
        #expect(ServiceImplementation.of(.normal) == .real)
        // A normal launch's factory is not called here (it would build a real
        // session only when a fetch asks for one); its table row is asserted.
        let made = FeedTransports.make(for: .testHost)()
        #expect(made is MockFeedTransport)
        ServiceLaunchLog.reset()
    }
}

/// Captured log lines (the sink is called off the main actor).
nonisolated final class LockedLines: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []
    func append(_ line: String) { lock.withLock { lines.append(line) } }
    var all: [String] { lock.withLock { lines } }
}

