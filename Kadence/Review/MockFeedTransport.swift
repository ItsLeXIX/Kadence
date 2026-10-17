//
//  MockFeedTransport.swift
//  Kadence
//
//  Phase 3 slice 3 (PHASE3-SLICE3-PLAN.md task 5) — `moodle-mocks.md` M1 and
//  M3: the Moodle calendar export as review mode and the tests serve it. No
//  network: every request is answered in memory, and every request that
//  "reached the server" is recorded (host, scheme, path, headers) — the
//  transport-level failures (`feedTLS`, `feedOffline`) record nothing, as
//  nothing was sent.
//
//  Like `MockCalDAVTransport` it hands a `3xx` back as a response: the
//  client decides whether to follow (components.md §34.2). The tests' real
//  redirect proof runs through `URLSessionTransport` and the `URLProtocol`
//  stub instead.
//

import Foundation
import Synchronization

nonisolated final class MockFeedTransport: HTTPTransport, Sendable {
    /// One request as the mock server saw it.
    struct Record: Sendable, Equatable {
        var method: String
        var url: URL
        var headers: [String: String]

        var host: String { url.host() ?? "" }
        var scheme: String { url.scheme ?? "" }
        var path: String { url.path(percentEncoded: true) }
        func header(_ name: String) -> String? {
            headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
    }

    let feedCase: MoodleFeedCase
    /// The base export the M1 bodies are derived from.
    let base: String
    let shift: @Sendable (String) -> String
    private let log = Mutex<[Record]>([])

    init(case feedCase: MoodleFeedCase, base: String = "", shift: @escaping @Sendable (String) -> String = { $0 }) {
        self.feedCase = feedCase
        self.base = base
        self.shift = shift
    }

    var records: [Record] { log.withLock { $0 } }

    static let calendarHeaders = ["content-type": "text/calendar; charset=utf-8"]
    static let htmlHeaders = ["content-type": "text/html; charset=utf-8"]

    /// M3's sign-in page: about 2 KB, no `BEGIN:VCALENDAR` anywhere.
    static var signInPage: Data {
        let filler = String(repeating: "<div class=\"login-form\"><input type=\"text\" name=\"username\"></div>\n", count: 26)
        return Data("<!DOCTYPE html>\n<html><head><title>Moodle: Log in to the site</title></head><body>\n\(filler)</body></html>\n".utf8)
    }

    /// M3's error page shape.
    static var errorPage: Data {
        Data("<!DOCTYPE html>\n<html><head><title>Error</title></head><body><p>Invalid authentication</p></body></html>\n".utf8)
    }

    func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse {
        // Failures before anything is sent: nothing recorded.
        switch feedCase {
        case .feedTLS: throw .certificate
        case .feedOffline: throw .offline
        default: break
        }
        log.withLock { $0.append(Record(method: request.method, url: request.url, headers: request.headers)) }
        let url = request.url
        func page(_ status: Int, _ body: Data = Data()) -> HTTPResponse {
            HTTPResponse(status: status, headers: body.isEmpty ? [:] : Self.htmlHeaders, body: body, url: url)
        }
        func redirect(_ status: Int, _ location: String) -> HTTPResponse {
            HTTPResponse(status: status, headers: ["location": location], url: url)
        }
        if feedCase.isCalendarBody {
            let body = MoodleFeedCases.body(feedCase, base: base, shift: shift) ?? Data()
            return HTTPResponse(status: 200, headers: Self.calendarHeaders, body: body, url: url)
        }
        switch feedCase {
        case .feedHTML: return page(200, Self.signInPage)
        case .feedError200: return page(200, Self.errorPage)
        case .feed401: return page(401)
        case .feed403: return page(403, Self.errorPage)
        case .feed404: return page(404, Self.errorPage)
        case .feed410: return page(410, Self.errorPage)
        case .feed500: return page(500, Self.errorPage)
        case .feed503: return page(503, Self.errorPage)
        case .feed429: return page(429, Self.errorPage)
        case .feedRedirectSameHost:
            if url.query()?.contains("lang=en") == true {
                return HTTPResponse(status: 200, headers: Self.calendarHeaders,
                                    body: MoodleFeedCases.body(.feedOK, base: base, shift: shift) ?? Data(), url: url)
            }
            return redirect(302, url.absoluteString + "&lang=en")
        case .feedRedirectTwice:
            return redirect(302, url.absoluteString + "&lang=en")
        case .feedRedirectCrossHost:
            return redirect(302, "https://login.example.invalid/sso?return=%2Fcalendar")
        case .feedRedirectHTTP:
            var parts = URLComponents(url: url, resolvingAgainstBaseURL: false)
            parts?.scheme = "http"
            return redirect(301, parts?.string ?? "http://\(url.host() ?? "")/")
        case .feedTimeout: throw .timeout
        case .feedRefused: throw .unreachable
        default: return page(500)
        }
    }
}
