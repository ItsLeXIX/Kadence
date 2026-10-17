//
//  MoodleFeedTransport.swift
//  Kadence
//
//  Phase 3 slice 3 (PHASE3-SLICE3-PLAN.md task 5) — components.md §34.1–
//  §34.3, §33.4 (obligations 2 and 3); interactions.md §16.1 "The URL on the
//  wire"; moodle-mocks.md M3.
//
//  One fetch of a Moodle calendar export: one `GET` with no `Authorization`
//  and no cookie, 30 s, at most one same-host redirect, a response over 20 MB
//  not read. The transport never follows a redirect (the client decides,
//  §34.2), and every request is checked against the URL's own host, port and
//  `https` before it is sent.
//
//  **Foundation errors carry the URL** (`URLError.failingURL`,
//  `NSURLErrorFailingURLStringKey`, often `localizedDescription`). They are
//  mapped to states by code only (`TransportError.from`) and nothing here
//  logs, stores or shows an error's description or `userInfo`.
//

import Foundation

// MARK: - The request

nonisolated enum FeedRequest {
    /// §34.1's `Accept`.
    static let accept = "text/calendar, */*;q=0.1"

    /// The fetch's one request. **The only call of `withRequestURLString` in
    /// the app** (§33.4 obligation 1; a source scan asserts it).
    static func get(_ url: MoodleFeedURL) -> HTTPRequest? {
        guard let target = url.withRequestURLString({ URL(string: $0) }) else { return nil }
        return get(target)
    }

    /// A same-host redirect's `GET` (the `Location`, as the server sent it).
    static func get(_ target: URL) -> HTTPRequest {
        HTTPRequest(method: "GET", url: target, headers: ["Accept": accept])
    }
}

// MARK: - The result

/// One fetch read in full (§34.8 steps 2–3).
nonisolated struct FeedFetch: Sendable, Equatable {
    var feed: MoodleFeed
    /// Requests sent: 1, or 2 after a same-host redirect.
    var requests: Int
    var milliseconds: Int
    /// The calendar body's size.
    var bytes: Int
}

/// §42.4: the feed's source. `fetch(windowStart:)` ignores the window — one
/// `GET` returns what Moodle lists.
nonisolated protocol FeedSource: Sendable {
    func fetch(windowStart: Date) async throws(ScheduleSourceError) -> FeedFetch
}

// MARK: - One fetch (§34.1, §34.2)

nonisolated struct MoodleFeedFetcher: Sendable {
    /// §34.1.
    static let timeout: TimeInterval = 30
    static let maxBytes = 20 * 1_048_576

    let transport: any HTTPTransport
    let zone: TimeZone
    /// Tests pin the duration so log lines are exact.
    var fixedMilliseconds: Int?

    init(transport: any HTTPTransport, zone: TimeZone, fixedMilliseconds: Int? = nil) {
        self.transport = transport
        self.zone = zone
        self.fixedMilliseconds = fixedMilliseconds
    }

    /// Whether `url` is the feed's own host, port and `https` (§34.2).
    static func isOwn(_ url: URL, host: String, port: Int?) -> Bool {
        url.scheme?.lowercased() == "https" && url.host()?.lowercased() == host
            && (url.port ?? 443) == (port ?? 443)
    }

    func fetch(_ url: MoodleFeedURL) async throws(ScheduleSourceError) -> FeedFetch {
        let clock = ContinuousClock()
        let started = clock.now
        guard var request = FeedRequest.get(url) else { throw .urlMissing }
        var requests = 0
        var followed = false
        while true {
            // Checked before every send: the URL's own host, port, `https`.
            guard Self.isOwn(request.url, host: url.host, port: url.port) else {
                throw .redirected(otherHost: request.url.scheme?.lowercased() == "https" ? request.url.host() : nil)
            }
            if Task.isCancelled { throw .cancelled }
            requests += 1
            let response: HTTPResponse
            do { response = try await transport.send(request) } catch { throw .from(error) }

            switch response.status {
            case 200:
                guard response.body.count <= Self.maxBytes else { throw .notACalendar }
                guard case .calendar(let feed) = MoodleProfile.read(response.body, zone: zone) else {
                    throw .notACalendar
                }
                let elapsed = clock.now - started
                let ms = fixedMilliseconds ?? Int(elapsed.components.seconds * 1000
                                                  + elapsed.components.attoseconds / 1_000_000_000_000_000)
                return FeedFetch(feed: feed, requests: requests, milliseconds: ms, bytes: response.body.count)
            case 301, 302, 303, 307, 308:
                guard let location = response.header("Location"),
                      let target = URL(string: location, relativeTo: request.url)?.absoluteURL else {
                    throw .serverError(response.status)
                }
                // §34.2: to `https` on the same host and port → follow once;
                // anything else, or a second one → `redirected`, not followed.
                // The `Location` is reduced to its host before it is shown.
                guard Self.isOwn(target, host: url.host, port: url.port) else {
                    throw .redirected(otherHost: target.scheme?.lowercased() == "https" ? target.host() : nil)
                }
                guard !followed else { throw .redirected(otherHost: url.host) }
                followed = true
                request = FeedRequest.get(target)
            case 401: throw .unauthorized
            case 403: throw .forbidden
            case 404, 410: throw .feedNotFound
            default: throw .serverError(response.status)
            }
        }
    }
}

// MARK: - The source (§34.8 steps 1–3)

/// A Moodle source's fetch: the URL read from the Keychain at the start and
/// dropped at the end — no property outlives it (§33.4). A fresh transport
/// (an ephemeral session) per fetch.
nonisolated struct MoodleFeedSource: FeedSource {
    let sourceID: String
    let secrets: any SecretStore
    let zone: TimeZone
    let makeTransport: @Sendable () -> any HTTPTransport
    var fixedMilliseconds: Int?

    init(sourceID: String, secrets: any SecretStore, zone: TimeZone = .current,
         fixedMilliseconds: Int? = nil, makeTransport: @escaping @Sendable () -> any HTTPTransport) {
        self.sourceID = sourceID
        self.secrets = secrets
        self.zone = zone
        self.fixedMilliseconds = fixedMilliseconds
        self.makeTransport = makeTransport
    }

    func fetch(windowStart: Date) async throws(ScheduleSourceError) -> FeedFetch {
        // Step 1: missing or denied → `urlMissing`, no request.
        let url: MoodleFeedURL
        do {
            guard let read = try secrets.readFeedURL(sourceID: sourceID) else { throw ScheduleSourceError.urlMissing }
            url = read
        } catch {
            throw .urlMissing
        }
        let transport = makeTransport()
        defer { (transport as? URLSessionTransport)?.invalidate() }
        return try await MoodleFeedFetcher(transport: transport, zone: zone, fixedMilliseconds: fixedMilliseconds)
            .fetch(url)
    }
}

// MARK: - The factory (launch kinds)

@MainActor
enum FeedTransports {
    /// The feed transport of a launch: a fresh `URLSessionTransport` with the
    /// feed's configuration per fetch in a normal launch only; review and the
    /// test host get the mock (`ServiceImplementation`'s table, as B45).
    static func make(for kind: LaunchKind,
                     mock: @escaping @Sendable () -> MockFeedTransport = { MockFeedTransport(case: .feedOffline) })
    -> @Sendable () -> any HTTPTransport {
        switch ServiceImplementation.of(kind) {
        case .real:
            ServiceLaunchLog.record("URLSessionFeedTransport")
            return { URLSessionTransport(requestTimeout: MoodleFeedFetcher.timeout, cookies: false) }
        case .mock:
            ServiceLaunchLog.record("MockFeedTransport")
            return mock
        }
    }
}
