//
//  MockCalDAVServer.swift
//  Kadence
//
//  design/caldav-mocks.md as code: the mocked CIS SabreDAV server. No
//  network — it answers `HTTPRequest`s in memory. Two front ends use it:
//  `MockCalDAVTransport` (review mode, task 10) and the tests' `URLProtocol`
//  stub, so both serve exactly the same shapes.
//
//  The username is `user01`. The password it checks is whatever it was built
//  with: the review password in review mode, the sentinel in tests.
//  Fixture data reaches the app only through review mode (G-057).
//

import Foundation
import Synchronization

nonisolated final class MockCalDAVServer: Sendable {

    /// caldav-mocks.md §3 and components.md §22.1's mocked-case table.
    enum Case: String, CaseIterable, Sendable {
        case reportOK, reportChanged, etagsOnly, ctagOnly, reportRefused, multigetRefused, allRefused, overCap
        case unauthorized, forbidden, wellKnown404, propfindNot207, noCalendars, multiCalendar
        case calendarGone, calendarMoved, htmlOK, emptyCalendar, serverError, timeout, offline, certificate
        case redirectOffHost, redirectToHTTP, slow
    }

    /// One calendar object: an href, its ETag and its `calendar-data` (CRLF).
    struct Object: Sendable, Equatable {
        var href: String
        var etag: String
        var data: String
        /// The VEVENT's end, for the time-range filter (nil = always returned).
        var end: Date?

        init(href: String, etag: String, data: String) {
            self.href = href; self.etag = etag; self.data = data
            if case .calendar(let parsed) = ICSParser.parse(data, currentZone: TimeZone(identifier: "UTC")!) {
                end = parsed.events.map(\.end.instant).max()
            }
        }
    }

    enum Reply: Sendable {
        case response(HTTPResponse)
        /// Nothing reached the server (TLS failure, offline).
        case failBeforeSend(URLError.Code)
        /// No answer; the client's timeout fires.
        case noAnswer
        /// `slow`: the response after a delay (review only).
        case delayed(TimeInterval, HTTPResponse)
    }

    static let host = "cis.technikum-wien.at"
    static let username = "user01"
    static let realm = "placeholder"
    static let context = "/webdav/lvplan.php/"
    static let principal = "/webdav/lvplan.php/principals/user01/"
    static let home = "/webdav/lvplan.php/calendars/user01/"
    static let lvplan = "/webdav/lvplan.php/calendars/user01/LVPlan-user01/"
    static let lvplanMoved = "/webdav/lvplan.php/calendars/user01/LVPlan-user01-ws26/"
    static let pruefungen = "/webdav/lvplan.php/calendars/user01/Pruefungen-user01/"
    static let ctag = "LVPlan-user01-1791454967"
    static let ctagLater = "LVPlan-user01-1791455022"

    let mockCase: Case
    private let expectedAuthorization: String
    private let feed: [Object]
    private let changed: [Object]
    private let pruefungenFeed: [Object]
    private let html: Data
    /// When true the `REPORT` ignores its time-range (task 7's
    /// `timeRangeHonoured == false` case).
    let ignoresTimeRange: Bool
    /// Review mode only: any password for `user01` is accepted, so the
    /// captures type a non-secret filler instead of a password (DEVIATIONS
    /// B43). Tests leave it off and check the sentinel.
    let acceptsAnyPassword: Bool

    private struct State {
        var reports = 0
        var propfinds = 0
        var gone = false
        var moved = false
    }
    private let state = Mutex(State())

    init(case mockCase: Case, password: Password, feed: [Object], changed: [Object] = [],
         pruefungen: [Object] = [], html: Data = Data(), ignoresTimeRange: Bool = false,
         acceptsAnyPassword: Bool = false) {
        self.acceptsAnyPassword = acceptsAnyPassword
        self.mockCase = mockCase
        expectedAuthorization = password.withPlaintext {
            "Basic " + Data("\(Self.username):\($0)".utf8).base64EncodedString()
        }
        self.feed = feed
        self.changed = changed
        pruefungenFeed = pruefungen
        self.html = html
        self.ignoresTimeRange = ignoresTimeRange
    }

    // MARK: Routing

    func respond(_ request: HTTPRequest) -> Reply {
        switch mockCase {
        case .certificate: return .failBeforeSend(.serverCertificateUntrusted)
        case .offline: return .failBeforeSend(.notConnectedToInternet)
        default: break
        }
        guard request.url.scheme == "https", request.url.host() == Self.host else {
            return .failBeforeSend(.cannotFindHost)
        }
        let path = request.url.path(percentEncoded: true)
        let method = request.method.uppercased()

        // D1: answered without a challenge, as on CIS.
        if method == "GET" && path == "/.well-known/caldav" { return d1() }

        // Every other request: 401 without (the right) Authorization.
        let auth = request.header("Authorization")
        let accepted = auth == expectedAuthorization
            || (acceptsAnyPassword && auth.map(Self.isBasicForUser01) == true)
        if mockCase == .unauthorized || !accepted {
            return reply(401, headers: ["WWW-Authenticate": "Basic realm=\"\(Self.realm)\""])
        }

        // `forbidden`: D2 — and, so a sync reaches the state too (review
        // item 10), every later request — answer 403 after the password.
        if mockCase == .forbidden { return reply(403) }
        switch (method, path) {
        case ("PROPFIND", Self.context):
            if mockCase == .propfindNot207 { return reply(200, headers: ["Content-Type": "text/html"], body: html) }
            return xml(Self.d2Body)
        case ("PROPFIND", Self.principal):
            return xml(Self.d3Body)
        case ("PROPFIND", Self.home):
            return xml(d4Body())
        default:
            break
        }
        if let calendar = calendarPath(path) {
            switch method {
            case "REPORT":
                let body = String(decoding: request.body ?? Data(), as: UTF8.self)
                return body.contains("calendar-multiget") ? multiget(calendar, body: body) : calendarQuery(calendar, body: body)
            case "PROPFIND":
                return calendarListing(calendar)
            default:
                return reply(405)
            }
        }
        if method == "GET", let object = object(at: path) {
            if [.allRefused].contains(mockCase) { return reply(405) }
            return reply(200, headers: ["Content-Type": "text/calendar; charset=utf-8", "ETag": object.etag],
                         body: Data(object.data.utf8))
        }
        return reply(404)
    }

    /// `Basic base64("user01:…")`, any password.
    static func isBasicForUser01(_ header: String) -> Bool {
        guard header.hasPrefix("Basic "), let data = Data(base64Encoded: String(header.dropFirst(6))),
              let text = String(data: data, encoding: .utf8) else { return false }
        return text.hasPrefix(username + ":")
    }

    // MARK: Discovery

    private func d1() -> Reply {
        switch mockCase {
        case .wellKnown404:
            return reply(404, headers: ["Content-Type": "text/html"], body: Data("<html><body>Not Found</body></html>".utf8))
        case .redirectOffHost:
            return reply(301, headers: ["Location": "https://login.example.invalid/caldav/"])
        case .redirectToHTTP:
            return reply(301, headers: ["Location": "http://cis.technikum-wien.at/webdav/lvplan.php/"])
        default:
            return reply(301, headers: ["Location": "https://cis.technikum-wien.at/webdav/lvplan.php/"])
        }
    }

    private func d4Body() -> String {
        let (gone, moved) = state.withLock { ($0.gone, $0.moved) }
        var responses = [Self.homeResponse]
        if mockCase != .noCalendars && !gone {
            responses.append(Self.calendarResponse(href: moved ? Self.lvplanMoved : Self.lvplan, name: "LVPlan",
                                                   components: ["VEVENT", "VTODO"], ctag: Self.ctag))
        }
        responses.append(Self.outboxResponse)
        if mockCase == .multiCalendar {
            responses.append(Self.calendarResponse(href: Self.pruefungen, name: "Prüfungen", components: ["VEVENT"],
                                                   ctag: "Pruefungen-user01-1791454967"))
            responses.append(Self.calendarResponse(href: Self.home + "Aufgaben-user01/", name: "Aufgaben",
                                                   components: ["VTODO"], ctag: "Aufgaben-user01-1791454967"))
            responses.append(Self.inboxResponse)
        }
        return Self.multistatus(responses)
    }

    // MARK: Events

    private func calendarPath(_ path: String) -> String? {
        let moved = state.withLock { $0.moved }
        if path == Self.lvplan || (moved && path == Self.lvplanMoved) { return path }
        if mockCase == .multiCalendar && path == Self.pruefungen { return path }
        return nil
    }

    private func objects(for calendar: String, poll: Int) -> [Object] {
        if calendar == Self.pruefungen { return pruefungenFeed }
        switch mockCase {
        case .reportChanged where poll > 1:
            return changed
        case .etagsOnly where poll > 1:
            return feed.map { o in
                var renamed = o
                let name = o.href.split(separator: "/").last.map(String.init) ?? o.href
                renamed.href = String(o.href.dropLast(name.count)) + "x-" + name
                renamed.etag = o.etag.replacingOccurrences(of: "-a\"", with: "-b\"")
                return renamed
            }
        case .overCap:
            return (0..<400).map { i in
                var o = feed[i % max(feed.count, 1)]
                o.href = Self.lvplan + String(format: "c%03d.ics", i + 1)
                return o
            }
        default:
            return feed
        }
    }

    private func calendarQuery(_ calendar: String, body: String) -> Reply {
        let poll = state.withLock { s -> Int in
            if calendar != Self.pruefungen { s.reports += 1 }
            return s.reports
        }
        switch mockCase {
        case .ctagOnly, .reportRefused, .multigetRefused, .allRefused, .overCap:
            return reply(405)
        case .calendarGone where calendar == Self.lvplan:
            state.withLock { $0.gone = true }
            return reply(404)
        case .calendarMoved where calendar == Self.lvplan:
            state.withLock { $0.moved = true }
            return reply(301, headers: ["Location": "https://cis.technikum-wien.at" + Self.lvplanMoved])
        case .htmlOK:
            return reply(200, headers: ["Content-Type": "text/html; charset=utf-8"], body: html)
        case .emptyCalendar:
            return xml(Self.multistatus([]))
        case .serverError:
            return reply(503)
        case .timeout:
            return .noAnswer
        default:
            break
        }
        var list = objects(for: calendar, poll: poll)
        if !ignoresTimeRange, let start = Self.timeRangeStart(body) {
            list = list.filter { ($0.end ?? .distantFuture) > start }
        }
        let response = Self.reportResponse(list)
        if mockCase == .slow { return .delayed(3, HTTPResponse(status: 207, headers: Self.xmlHeaders, body: Data(response.utf8),
                                                                  url: URL(string: "https://\(Self.host)\(calendar)")!)) }
        return xml(response)
    }

    private func calendarListing(_ calendar: String) -> Reply {
        let poll = state.withLock { s -> Int in s.propfinds += 1; return s.propfinds }
        let later = mockCase == .ctagOnly && poll > 1
        let members = objects(for: calendar, poll: 1)
        var responses = ["""
          <d:response>
            <d:href>\(calendar)</d:href>
            <d:propstat>
              <d:prop>
                <d:resourcetype>
                  <d:collection/>
                  <cal:calendar/>
                </d:resourcetype>
                <cs:getctag>\(later ? Self.ctagLater : Self.ctag)</cs:getctag>
              </d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
          </d:response>
        """]
        for o in members {
            let etag = later ? o.etag.replacingOccurrences(of: "-a\"", with: "-b\"") : o.etag
            responses.append("""
              <d:response>
                <d:href>\(o.href)</d:href>
                <d:propstat>
                  <d:prop>
                    <d:resourcetype/>
                    <d:getetag>\(Self.escape(etag))</d:getetag>
                    <d:getcontenttype>text/calendar; charset=utf-8; component=vevent</d:getcontenttype>
                  </d:prop>
                  <d:status>HTTP/1.1 200 OK</d:status>
                </d:propstat>
              </d:response>
            """)
        }
        return xml(Self.multistatus(responses))
    }

    private func multiget(_ calendar: String, body: String) -> Reply {
        if [.multigetRefused, .allRefused, .overCap].contains(mockCase) { return reply(501) }
        let hrefs = MultistatusParser.parseTree(Data(body.utf8))?.hrefs ?? []
        let all = objects(for: calendar, poll: 1)
        var responses: [String] = []
        var found: [Object] = []
        for href in hrefs {
            if let o = all.first(where: { $0.href == href }) { found.append(o) }
            else {
                responses.append("""
                  <d:response>
                    <d:href>\(Self.escape(href))</d:href>
                    <d:status>HTTP/1.1 404 Not Found</d:status>
                  </d:response>
                """)
            }
        }
        return xml(Self.reportResponse(found, extra: responses))
    }

    private func object(at path: String) -> Object? {
        objects(for: Self.lvplan, poll: 1).first { $0.href == path }
            ?? (mockCase == .multiCalendar ? pruefungenFeed.first { $0.href == path } : nil)
    }

    // MARK: Bodies

    static let xmlHeaders = ["Content-Type": "application/xml; charset=utf-8"]

    private func xml(_ body: String) -> Reply { reply(207, headers: Self.xmlHeaders, body: Data(body.utf8)) }

    private func reply(_ status: Int, headers: [String: String] = [:], body: Data = Data()) -> Reply {
        var lower: [String: String] = [:]
        for (k, v) in headers { lower[k.lowercased()] = v }
        return .response(HTTPResponse(status: status, headers: lower, body: body, url: URL(string: "https://\(Self.host)/")!))
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func timeRangeStart(_ body: String) -> Date? {
        guard let tree = MultistatusParser.parseTree(Data(body.utf8)) else { return nil }
        func find(_ e: DAVElement) -> String? {
            if e.name == "time-range" { return e.attributes["start"] }
            return e.children.lazy.compactMap(find).first
        }
        guard let text = find(tree) else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.date(from: text)
    }

    static func multistatus(_ responses: [String]) -> String {
        """
        <?xml version="1.0" encoding="utf-8"?>
        <d:multistatus xmlns:d="DAV:" xmlns:s="http://sabredav.org/ns" xmlns:cal="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/">
        \(responses.joined(separator: "\n"))
        </d:multistatus>

        """
    }

    /// A `REPORT` `207`: each object's `calendar-data` written raw, CRLF kept
    /// (the client's XML parser delivers LF, §20.7).
    static func reportResponse(_ objects: [Object], extra: [String] = []) -> String {
        multistatus(objects.map { o in
            """
              <d:response>
                <d:href>\(escape(o.href))</d:href>
                <d:propstat>
                  <d:prop>
                    <d:getetag>\(escape(o.etag))</d:getetag>
                    <cal:calendar-data>\(escape(o.data))</cal:calendar-data>
                  </d:prop>
                  <d:status>HTTP/1.1 200 OK</d:status>
                </d:propstat>
              </d:response>
            """
        } + extra)
    }

    static let d2Body = multistatus(["""
      <d:response>
        <d:href>/webdav/lvplan.php/</d:href>
        <d:propstat>
          <d:prop>
            <d:current-user-principal>
              <d:href>/webdav/lvplan.php/principals/user01/</d:href>
            </d:current-user-principal>
            <d:resourcetype>
              <d:collection/>
            </d:resourcetype>
          </d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
        <d:propstat>
          <d:prop>
            <cal:calendar-home-set/>
          </d:prop>
          <d:status>HTTP/1.1 404 Not Found</d:status>
        </d:propstat>
      </d:response>
    """])

    static let d3Body = multistatus(["""
      <d:response>
        <d:href>/webdav/lvplan.php/principals/user01/</d:href>
        <d:propstat>
          <d:prop>
            <cal:calendar-home-set>
              <d:href>/webdav/lvplan.php/calendars/user01/</d:href>
            </cal:calendar-home-set>
          </d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
      </d:response>
    """])

    static let homeResponse = """
      <d:response>
        <d:href>/webdav/lvplan.php/calendars/user01/</d:href>
        <d:propstat>
          <d:prop>
            <d:resourcetype>
              <d:collection/>
            </d:resourcetype>
          </d:prop>
          <d:status>HTTP/1.1 200 OK</d:status>
        </d:propstat>
        <d:propstat>
          <d:prop>
            <d:displayname/>
            <cal:supported-calendar-component-set/>
            <cs:getctag/>
            <d:sync-token/>
          </d:prop>
          <d:status>HTTP/1.1 404 Not Found</d:status>
        </d:propstat>
      </d:response>
    """

    static let outboxResponse = scheduleBox("outbox/", type: "schedule-outbox")
    static let inboxResponse = scheduleBox("inbox/", type: "schedule-inbox")

    private static func scheduleBox(_ name: String, type: String) -> String {
        """
          <d:response>
            <d:href>/webdav/lvplan.php/calendars/user01/\(name)</d:href>
            <d:propstat>
              <d:prop>
                <d:resourcetype>
                  <d:collection/>
                  <cal:\(type)/>
                </d:resourcetype>
              </d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
            <d:propstat>
              <d:prop>
                <d:displayname/>
                <cal:supported-calendar-component-set/>
                <cs:getctag/>
                <d:sync-token/>
              </d:prop>
              <d:status>HTTP/1.1 404 Not Found</d:status>
            </d:propstat>
          </d:response>
        """
    }

    static func calendarResponse(href: String, name: String, components: [String], ctag: String) -> String {
        """
          <d:response>
            <d:href>\(href)</d:href>
            <d:propstat>
              <d:prop>
                <d:resourcetype>
                  <d:collection/>
                  <cal:calendar/>
                </d:resourcetype>
                <d:displayname>\(escape(name))</d:displayname>
                <cal:supported-calendar-component-set>
        \(components.map { "          <cal:comp name=\"\($0)\"/>" }.joined(separator: "\n"))
                </cal:supported-calendar-component-set>
                <cs:getctag>\(ctag)</cs:getctag>
              </d:prop>
              <d:status>HTTP/1.1 200 OK</d:status>
            </d:propstat>
            <d:propstat>
              <d:prop>
                <d:sync-token/>
              </d:prop>
              <d:status>HTTP/1.1 404 Not Found</d:status>
            </d:propstat>
          </d:response>
        """
    }

    // MARK: Feeds

    /// One object per VEVENT, `prefix` + `NN.ics`, ETag `"<etagPrefix>-NN-a"` —
    /// how `reportCIS` and `reportReview` are cut (caldav-mocks.md §2): the
    /// calendar's header and VTIMEZONE, one VEVENT, `END:VCALENDAR`, CRLF.
    static func objects(fromICS text: String, calendar: String = lvplan, hrefPrefix: String,
                        etagPrefix: String) -> [Object] {
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
        guard let firstEvent = lines.firstIndex(of: "BEGIN:VEVENT") else { return [] }
        let header = Array(lines[..<firstEvent])
        var blocks: [[String]] = []
        var current: [String]?
        for line in lines[firstEvent...] {
            if line == "BEGIN:VEVENT" { current = [line] }
            else if line == "END:VEVENT" { current?.append(line); if let c = current { blocks.append(c) }; current = nil }
            else { current?.append(line) }
        }
        return blocks.enumerated().map { i, block in
            let n = String(format: "%02d", i + 1)
            return Object(href: calendar + hrefPrefix + n + ".ics", etag: "\"\(etagPrefix)-\(n)-a\"",
                          data: (header + block + ["END:VCALENDAR"]).joined(separator: "\r\n") + "\r\n")
        }
    }
}

// MARK: - The review feed (components.md §22.1)

nonisolated enum ReviewFeed {
    /// `M`: the first Monday at least two days after today.
    static func firstMonday(after today: Date, zone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let start = cal.startOfDay(for: today)
        for offset in 2...8 {
            if let day = cal.date(byAdding: .day, value: offset, to: start), cal.component(.weekday, from: day) == 2 {
                return day
            }
        }
        return start
    }

    /// Renders `{{D+n}}` (`M + n`), `{{T-n}}` and `{{TODAY}}` as `yyyyMMdd`.
    static func render(_ template: String, today: Date, zone: TimeZone) -> String {
        render(template, today: today, m: firstMonday(after: today, zone: zone), zone: zone)
    }

    /// The same with `M` given (slice 2's planner tables pin `M` = Mon
    /// 2026-10-12 with today = the clock's day, §30.1).
    static func render(_ template: String, today: Date, m: Date, zone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let start = cal.startOfDay(for: today)
        let m = cal.startOfDay(for: m)
        func stamp(_ d: Date) -> String { ICSFormat.dateStamp(d, zone: zone) }
        var out = template.replacingOccurrences(of: "{{TODAY}}", with: stamp(start))
        let pattern = try? NSRegularExpression(pattern: #"\{\{(D\+|T-)(\d+)\}\}"#)
        let ns = out as NSString
        let matches = pattern?.matches(in: out, range: NSRange(location: 0, length: ns.length)) ?? []
        for match in matches.reversed() {
            let kind = ns.substring(with: match.range(at: 1))
            let n = Int(ns.substring(with: match.range(at: 2))) ?? 0
            let day = kind == "D+" ? cal.date(byAdding: .day, value: n, to: m)! : cal.date(byAdding: .day, value: -n, to: start)!
            out = (out as NSString).replacingCharacters(in: match.range, with: stamp(day))
        }
        return out
    }

    /// `reportReview`: the rendered template, `r01.ics` … `r14.ics`.
    static func reportReview(template: String, today: Date, zone: TimeZone) -> [MockCalDAVServer.Object] {
        MockCalDAVServer.objects(fromICS: render(template, today: today, zone: zone), hrefPrefix: "r", etagPrefix: "rev")
    }

    /// Slice 2 dataset `travel` (components.md §30.1): the rendered
    /// `cis-travel.ics.template` — the review template without row 1, plus
    /// T1 — one VEVENT per object, `t01.ics` … `t14.ics`.
    static func reportTravel(template: String, today: Date, m: Date, zone: TimeZone) -> [MockCalDAVServer.Object] {
        MockCalDAVServer.objects(fromICS: render(template, today: today, m: m, zone: zone), hrefPrefix: "t",
                                 etagPrefix: "trv")
    }

    /// §30.1 "Sync": `reportChanged`'s differences (§22.1's table) applied
    /// to the `travel` feed, found by content rather than by row (the travel
    /// template has no row 1 and gains T1): #2 `SWQM-ILV` `M` lecturer L01 →
    /// L09; #3 `SWEN3-LAB` `M + 1` room `EDV_F4.26` (a new object); #5
    /// `EPC-ILV` `M + 3` and #7b (`SWRM-ILV`, `L06`) absent; `KOKU-UE` on
    /// `M + 9` 10:00–11:30 added. T1 is untouched.
    static func reportTravelChanged(template: String, today: Date, m: Date, zone: TimeZone) -> [MockCalDAVServer.Object] {
        var objects = reportTravel(template: template, today: today, m: m, zone: zone)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        func day(_ n: Int) -> String { ICSFormat.dateStamp(cal.date(byAdding: .day, value: n, to: cal.startOfDay(for: m))!, zone: zone) }
        func index(_ needle: String, _ date: String) -> Int? {
            objects.firstIndex { $0.data.contains(needle) && $0.data.contains("DTSTART;TZID=Europe/Vienna:" + date) }
        }
        if let i = index("SUMMARY:SWQM-ILV", day(0)) {
            objects[i].data = objects[i].data.replacingOccurrences(of: "HS_A3.15L01", with: "HS_A3.15L09")
                .replacingOccurrences(of: "\\nL01\\n", with: "\\nL09\\n")
            objects[i].etag = objects[i].etag.replacingOccurrences(of: "-a\"", with: "-b\"")
        }
        if let i = index("SUMMARY:SWEN3-LAB", day(1)) {
            objects[i].data = objects[i].data.replacingOccurrences(of: "EDV_F4.25", with: "EDV_F4.26")
            objects[i].href = objects[i].href.replacingOccurrences(of: ".ics", with: "b.ics")
        }
        if let i = index("SUMMARY:EPC-ILV", day(3)) { objects.remove(at: i) }
        if let i = objects.firstIndex(where: { $0.data.contains("SUMMARY:SWRM-ILV") && $0.data.contains("\\nL06\\n") }) {
            objects.remove(at: i)
        }
        if let h2 = objects.first(where: { $0.data.contains("SUMMARY:KOKU-UE") }) {
            let h2Date = h2.data.components(separatedBy: "DTSTART;TZID=Europe/Vienna:").last?.prefix(8).description ?? ""
            objects.append(MockCalDAVServer.Object(
                href: h2.href.replacingOccurrences(of: "t02.ics", with: "t15.ics"), etag: "\"trv-15-a\"",
                data: h2.data.replacingOccurrences(of: h2Date + "T094000", with: day(9) + "T100000")
                    .replacingOccurrences(of: h2Date + "T125000", with: day(9) + "T113000")))
        }
        return objects
    }

    /// `reportCIS` (caldav-mocks.md §2): the real export, one VEVENT per
    /// object, `obj-01.ics` … `obj-13.ics`, ETag `"cis-NN-a"`.
    static func reportCIS(export: String) -> [MockCalDAVServer.Object] {
        MockCalDAVServer.objects(fromICS: export, hrefPrefix: "obj-", etagPrefix: "cis")
    }

    /// `reportCISOverlap` (caldav-mocks.md §2, added 2026-10-10): `reportCIS`
    /// plus `obj-14.ics`, built here from the export's own first
    /// `BPREF-Info` VEVENT (`obj-03.ics`) — a second session of the course,
    /// 19:30–20:15, lecturer `L07`, inside the co-taught 18:35–20:15 one. The
    /// shape Parsa's real feed has on Fri 2 Oct 2026. The export is never
    /// edited.
    static func reportCISOverlap(export: String) -> [MockCalDAVServer.Object] {
        var objects = reportCIS(export: export)
        guard objects.count == 13 else { return objects }
        let data = objects[2].data
            .replacingOccurrences(of: "WEBINAR02L05BPREF-Info20261002T183500", with: "WEBINAR02L07BPREF-Info20261002T193000")
            .replacingOccurrences(of: "\\nL05\\n", with: "\\nL07\\n")
            .replacingOccurrences(of: "DTSTART;TZID=Europe/Vienna:20261002T183500",
                                  with: "DTSTART;TZID=Europe/Vienna:20261002T193000")
        objects.append(MockCalDAVServer.Object(href: MockCalDAVServer.lvplan + "obj-14.ics", etag: "\"cis-14-a\"", data: data))
        return objects
    }

    /// `reportCISSameUID` (caldav-mocks.md §2): `obj-04.ics`'s `UID` line is
    /// `obj-03.ics`'s, so the two `BPREF-Info` halves share one UID and one
    /// start and differ only in the lecturer line.
    static func reportCISSameUID(export: String) -> [MockCalDAVServer.Object] {
        var objects = reportCIS(export: export)
        guard objects.count == 13 else { return objects }
        objects[3] = MockCalDAVServer.Object(
            href: objects[3].href, etag: objects[3].etag,
            data: objects[3].data.replacingOccurrences(of: "UID:FHif-5WEBINAR02L06BPREF-Info",
                                                       with: "UID:FHif-5WEBINAR02L05BPREF-Info"))
        return objects
    }

    /// `reportChanged` (§22.1's table), applied by template row: #2 lecturer
    /// L01 → L09 (new UID, same href, ETag `-b`); #3 room EDV_F4.26 (a new
    /// object); #5 and #7b absent; `KOKU-UE` on `{{D+9}}` added; H1's room →
    /// HS_A3.13 (history: never returned for a sync window).
    static func reportChanged(template: String, today: Date, zone: TimeZone) -> [MockCalDAVServer.Object] {
        var objects = reportReview(template: template, today: today, zone: zone)
        guard objects.count == 14 else { return objects }
        let m = firstMonday(after: today, zone: zone)
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        let d9 = ICSFormat.dateStamp(cal.date(byAdding: .day, value: 9, to: m)!, zone: zone)
        func edit(_ i: Int, _ from: String, _ to: String) {
            objects[i].data = objects[i].data.replacingOccurrences(of: from, with: to)
        }
        edit(0, "HS_A3.15", "HS_A3.13")                           // H1
        objects[0].etag = "\"rev-01-b\""
        // #2: L01 → L09 in the UID and the DESCRIPTION.
        objects[3].data = objects[3].data.replacingOccurrences(of: "HS_A3.15L01", with: "HS_A3.15L09")
            .replacingOccurrences(of: "\\nL01\\n", with: "\\nL09\\n")
        objects[3].etag = "\"rev-04-b\""
        edit(4, "EDV_F4.25", "EDV_F4.26")                         // #3 room move
        objects[4].href = objects[4].href.replacingOccurrences(of: "r05.ics", with: "r05b.ics")
        // New: KOKU-UE {{D+9}} 10:00–11:30, from H2's lines.
        let h2 = objects[1]
        let h2Date = h2.data.components(separatedBy: "DTSTART;TZID=Europe/Vienna:").last?.prefix(8).description ?? ""
        let new = MockCalDAVServer.Object(
            href: h2.href.replacingOccurrences(of: "r02.ics", with: "r15.ics"), etag: "\"rev-15-a\"",
            data: h2.data.replacingOccurrences(of: h2Date + "T094000", with: d9 + "T100000")
                .replacingOccurrences(of: h2Date + "T125000", with: d9 + "T113000"))
        for i in [9, 6] { objects.remove(at: i) }                 // #7b, #5
        objects.append(new)
        return objects.map { MockCalDAVServer.Object(href: $0.href, etag: $0.etag, data: $0.data) }
    }
}
