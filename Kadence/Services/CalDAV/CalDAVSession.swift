//
//  CalDAVSession.swift
//  Kadence
//
//  One connect or one sync on the wire (interactions.md §13.1;
//  components.md §20.8.2, §21.4):
//
//  - every request goes to the source's own host, port and `https`, or it is
//    not sent at all;
//  - the first request carries no `Authorization`; a `401` from the host is
//    answered once with the password (the retry is not counted); after the
//    host has challenged, later requests of this same session carry it;
//    a second `401` after the password was sent is `unauthorized`;
//  - requests are sequential (each `send` is awaited before the next) and
//    capped at 300 per session.
//

import Foundation

// MARK: - Errors (components.md §21.5)

/// The states a fetch can end in. Per-calendar ones (`calendarMissing`,
/// `fetchFailed`, `notACalendar`) arrive in `failedCalendars`; the rest end
/// the whole fetch. No case carries a password, header or body.
nonisolated enum ScheduleSourceError: Error, Equatable, Sendable {
    case unauthorized
    case forbidden
    case noCalDAV
    case noCalendars
    case certificate
    case passwordMissing
    /// To another host (`otherHost` set) or to `http:` (`otherHost` nil).
    case redirected(otherHost: String?)
    case unreachable
    case serverError(Int)
    case offline
    case calendarMissing
    /// REPORT and every fallback refused, or the request cap; the technical line.
    case fetchFailed(technical: String)
    case notACalendar
    case cancelled
    /// components.md §34.2 (slice 3), a feed: `404` / `410`.
    case feedNotFound
    /// §34.8 step 1, a feed: no calendar URL in the Keychain. No request.
    case urlMissing

    var state: SourceState {
        switch self {
        case .unauthorized: .unauthorized
        case .forbidden: .forbidden
        case .noCalDAV: .noCalDAV
        case .noCalendars: .noCalendars
        case .certificate: .certificate
        case .passwordMissing: .passwordMissing
        case .redirected: .redirected
        case .unreachable, .cancelled: .unreachable
        case .serverError: .serverError
        case .offline: .offline
        case .calendarMissing: .calendarMissing
        case .fetchFailed: .fetchFailed
        case .notACalendar: .notACalendar
        case .feedNotFound: .feedNotFound
        case .urlMissing: .urlMissing
        }
    }

    static func from(_ error: TransportError) -> ScheduleSourceError {
        switch error {
        case .offline: .offline
        case .timeout, .unreachable: .unreachable
        case .certificate: .certificate
        case .tooLarge: .notACalendar      // §20.8.2: a response over 20 MB is not read
        case .cancelled: .cancelled
        }
    }
}

// MARK: - The session

/// Swift note: an `actor` is a class whose methods run one at a time (like a
/// Java object whose every method is `synchronized`, but without blocking a
/// thread). Its state — the challenge flag, the request count — is therefore
/// never touched by two requests at once.
actor CalDAVSession {
    static let requestCap = 300

    let transport: any HTTPTransport
    /// The one protection space: the source's host, port, `https`.
    let host: String
    let port: Int
    private let responder: ChallengeResponder?
    private var challengeScheme: String?
    /// Requests sent (a `401` retry is not counted).
    private(set) var requestCount = 0
    let cap: Int

    init(transport: any HTTPTransport, host: String, port: Int = 443, username: String, password: Password?,
         cap: Int = CalDAVSession.requestCap) {
        self.transport = transport
        self.host = host.lowercased()
        self.port = port
        self.cap = cap
        responder = password.map { ChallengeResponder(host: host, port: port, username: username, password: $0) }
    }

    /// Whether `url` is the source's own host, port and `https`.
    nonisolated func isOwn(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https" && url.host()?.lowercased() == host && (url.port ?? 443) == port
    }

    /// Thrown when the next request would exceed the cap: nothing is sent.
    struct CapReached: Error {}

    /// Sends one request. `401` and `403` are answered here; every other
    /// status is the caller's to read.
    func send(_ request: HTTPRequest) async throws(ScheduleSourceError) -> HTTPResponse {
        guard isOwn(request.url) else { throw .redirected(otherHost: request.url.host()) }
        guard requestCount < cap else { throw .fetchFailed(technical: "Request cap reached (\(cap))") }
        if Task.isCancelled { throw .cancelled }
        var outgoing = request
        var sentPassword = false
        if let scheme = challengeScheme, let responder,
           let header = responder.authorizationAfterChallenge(for: outgoing, scheme: scheme) {
            outgoing.headers["Authorization"] = header
            sentPassword = true
        }
        requestCount += 1
        var response: HTTPResponse
        do { response = try await transport.send(outgoing) } catch { throw .from(error) }

        if response.status == 401 {
            guard !sentPassword, let responder else { throw .unauthorized }
            let challenge = response.header("WWW-Authenticate")
            guard let header = responder.authorization(for: request, challenge: challenge) else { throw .unauthorized }
            challengeScheme = challenge
            outgoing.headers["Authorization"] = header
            if Task.isCancelled { throw .cancelled }
            do { response = try await transport.send(outgoing) } catch { throw .from(error) }
            if response.status == 401 { throw .unauthorized }
        }
        if response.status == 403 { throw .forbidden }
        return response
    }

    /// Resolves an href against the URL of the request that returned it; nil
    /// when it resolves to another host (§20.8.1: ignored, never requested).
    nonisolated func resolve(_ href: String, against base: URL) -> URL? {
        guard let url = URL(string: href, relativeTo: base)?.absoluteURL ?? URL(string: href) else { return nil }
        return isOwn(url) ? url : nil
    }
}

extension HTTPResponse {
    nonisolated var isRedirect: Bool { [301, 302, 303, 307, 308].contains(status) }
}

extension URL {
    /// An absolute path for storage (`/webdav/lvplan.php/principals/user01/`).
    nonisolated var storedPath: String {
        let path = path(percentEncoded: true)
        return path.isEmpty ? "/" : path
    }
}
