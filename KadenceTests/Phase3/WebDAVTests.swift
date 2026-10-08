//
//  WebDAVTests.swift
//  KadenceTests
//
//  PHASE3-PLAN.md task 5: the HTTP transport and the WebDAV XML
//  (components.md §20.8.2, §21.4; interactions.md §13.1; caldav-mocks.md §1–§2).
//

import Testing
import Foundation
import CryptoKit
@testable import Kadence

nonisolated private let sentinel = "S3ntinel-pw-⚠"
private let vienna = TimeZone(identifier: "Europe/Vienna")!
private let base = "/webdav/lvplan.php/calendars/user01/"

private func responses(_ name: String) throws -> [DAVResponse] {
    try #require(MultistatusParser.parse(try Fixture.data(name)))
}

/// A request body from caldav-mocks.md: the first ```xml block after `marker`.
private func mockRequestBody(after marker: String) throws -> Data {
    let md = try String(contentsOf: Fixture.repoRoot.appendingPathComponent("design/caldav-mocks.md"), encoding: .utf8)
    let lines = md.components(separatedBy: "\n")
    let start = try #require(lines.firstIndex { $0.contains(marker) })
    let open = try #require(lines[start...].firstIndex { $0.hasPrefix("```xml") })
    let close = try #require(lines[(open + 1)...].firstIndex { $0 == "```" })
    return Data(lines[(open + 1)..<close].joined(separator: "\n").utf8)
}

/// What a request body means: its root, its requested properties, and its
/// filter, by namespace and name — prefixes and whitespace free.
private struct Meaning: Equatable {
    var root: String
    var props: Set<String>
    var filters: [String]
    var hrefs: [String]

    init(_ data: Data) {
        let tree = MultistatusParser.parseTree(data)
        root = tree.map { "\($0.namespace) \($0.name)" } ?? "?"
        let prop = tree?.child(DAVNamespace.dav, "prop")
        props = Set((prop?.children ?? []).map { "\($0.namespace) \($0.name)" })
        var filters: [String] = []
        func walk(_ e: DAVElement) {
            if e.name == "comp-filter" { filters.append("comp \(e.attributes["name"] ?? "")") }
            if e.name == "time-range" { filters.append("time-range start=\(e.attributes["start"] ?? "") end=\(e.attributes["end"] ?? "")") }
            e.children.forEach(walk)
        }
        if let filter = tree?.child(DAVNamespace.caldav, "filter") { walk(filter) }
        self.filters = filters
        hrefs = tree?.hrefs ?? []
    }
}

struct WebDAVTests {

    // MARK: Parsing the mocked bodies

    @Test("D2: the principal, and calendar-home-set in a 404 propstat")
    func d2() throws {
        let r = try responses("d2-root-207.xml")
        #expect(r.count == 1 && r[0].href == "/webdav/lvplan.php/")
        #expect(r[0].ok(DAVNamespace.dav, "current-user-principal")?.hrefs == ["/webdav/lvplan.php/principals/user01/"])
        #expect(r[0].property(DAVNamespace.caldav, "calendar-home-set")?.status == 404)
        #expect(r[0].ok(DAVNamespace.caldav, "calendar-home-set") == nil)
        #expect(r[0].ok(DAVNamespace.dav, "resourcetype")?.has(DAVNamespace.dav, "collection") == true)
    }

    @Test("D3: the calendar home")
    func d3() throws {
        let r = try responses("d3-principal-207.xml")
        #expect(r[0].ok(DAVNamespace.caldav, "calendar-home-set")?.hrefs == [base])
    }

    @Test("D4: three responses, LVPlan with VEVENT+VTODO and its getctag, sync-token in a 404 propstat")
    func d4() throws {
        let r = try responses("d4-home-207.xml")
        #expect(r.map(\.href) == [base, base + "LVPlan-user01/", base + "outbox/"])
        let types = r.map { $0.ok(DAVNamespace.dav, "resourcetype")?.children.map(\.name) ?? [] }
        #expect(types == [["collection"], ["collection", "calendar"], ["collection", "schedule-outbox"]])
        let lv = r[1]
        #expect(lv.ok(DAVNamespace.dav, "displayname")?.text == "LVPlan")
        let comps = lv.ok(DAVNamespace.caldav, "supported-calendar-component-set")?
            .children(DAVNamespace.caldav, "comp").compactMap { $0.attributes["name"] }
        #expect(comps == ["VEVENT", "VTODO"])
        #expect(lv.ok(DAVNamespace.calendarServer, "getctag")?.text == "LVPlan-user01-1791454967")
        #expect(lv.property(DAVNamespace.dav, "sync-token")?.status == 404)
        #expect(r[0].property(DAVNamespace.dav, "displayname")?.status == 404)
    }

    @Test("report-cis-2026WS.xml: 13 hrefs, ETags, and calendar-data with LF line endings")
    func reportCIS() throws {
        let r = try responses("report-cis-2026WS.xml")
        #expect(r.count == 13)
        #expect(r.map(\.href) == (1...13).map { base + "LVPlan-user01/obj-" + String(format: "%02d", $0) + ".ics" })
        #expect(r.map { $0.ok(DAVNamespace.dav, "getetag")?.text } == (1...13).map { "\"cis-" + String(format: "%02d", $0) + "-a\"" })
        for response in r {
            let data = try #require(response.ok(DAVNamespace.caldav, "calendar-data")?.text)
            #expect(!data.contains("\r"))  // XML end-of-line handling (§20.7)
            #expect(data.hasPrefix("BEGIN:VCALENDAR\nVERSION:1.0\n") && data.hasSuffix("END:VCALENDAR\n"))
        }
        // The file itself carries CRLF inside calendar-data.
        #expect(try Fixture.text("report-cis-2026WS.xml").contains("BEGIN:VCALENDAR\r\nVERSION:1.0\r\n"))
    }

    @Test("The .xml's objects rebuild the .ics VEVENT lines exactly, line for line")
    func reportMatchesExport() throws {
        let r = try responses("report-cis-2026WS.xml")
        let fromXML = r.flatMap { response -> [String] in
            let lines = (response.ok(DAVNamespace.caldav, "calendar-data")?.text ?? "").components(separatedBy: "\n")
            guard let b = lines.firstIndex(of: "BEGIN:VEVENT"), let e = lines.firstIndex(of: "END:VEVENT") else { return [] }
            return Array(lines[b...e])
        }
        let fromICS = try CISFeed.vevents().flatMap { $0 }
        #expect(fromXML == fromICS)
    }

    @Test("The same bodies with other prefixes parse identically")
    func prefixesAreIrrelevant() throws {
        for name in ["d2-root-207.xml", "d3-principal-207.xml", "d4-home-207.xml", "report-cis-2026WS.xml",
                     "f1-propfind-207.xml", "d4-home-multi-207.xml"] {
            let text = try Fixture.text(name)
            let other = text
                .replacingOccurrences(of: "<d:", with: "<D:").replacingOccurrences(of: "</d:", with: "</D:")
                .replacingOccurrences(of: "xmlns:d=", with: "xmlns:D=")
                .replacingOccurrences(of: "<cal:", with: "<C:").replacingOccurrences(of: "</cal:", with: "</C:")
                .replacingOccurrences(of: "xmlns:cal=", with: "xmlns:C=")
                .replacingOccurrences(of: "<cs:", with: "<x1:").replacingOccurrences(of: "</cs:", with: "</x1:")
                .replacingOccurrences(of: "xmlns:cs=", with: "xmlns:x1=")
            #expect(other != text)
            #expect(MultistatusParser.parse(Data(other.utf8)) == MultistatusParser.parse(Data(text.utf8)), "\(name)")
        }
    }

    @Test("A web page is not a multistatus")
    func notMultistatus() throws {
        #expect(MultistatusParser.parse(try Fixture.data("html-login.html")) == nil)
        #expect(MultistatusParser.parse(Data("garbage".utf8)) == nil)
        #expect(MultistatusParser.parse(Data("<?xml version=\"1.0\"?><d:multistatus xmlns:d=\"DAV:\"/>".utf8)) == [])
    }

    // MARK: Request bodies

    @Test("Request bodies match caldav-mocks.md on meaning: method, Depth, properties, filter")
    func requestBodies() throws {
        let host = URL(string: "https://cis.technikum-wien.at")!
        let context = URL(string: "https://cis.technikum-wien.at/webdav/lvplan.php/")!
        let calendar = URL(string: "https://cis.technikum-wien.at" + base + "LVPlan-user01/")!
        let d1 = CalDAVRequests.wellKnown(base: host)
        #expect(d1.method == "GET" && d1.url.absoluteString == "https://cis.technikum-wien.at/.well-known/caldav" && d1.body == nil)
        let cases: [(HTTPRequest, String, String, String)] = [
            (CalDAVRequests.contextPropfind(context), "### D2", "PROPFIND", "0"),
            (CalDAVRequests.principalPropfind(context), "### D3", "PROPFIND", "0"),
            (CalDAVRequests.homePropfind(context), "### D4", "PROPFIND", "1"),
            (CalDAVRequests.calendarQuery(calendar, start: Windows.syncStart(now: TestClock.now, zone: vienna)),
             "### F0", "REPORT", "1"),
            (CalDAVRequests.calendarPropfind(calendar), "### F1", "PROPFIND", "1"),
        ]
        for (request, marker, method, depth) in cases {
            let expected = Meaning(try mockRequestBody(after: marker))
            #expect(request.method == method && request.header("Depth") == depth, "\(marker)")
            #expect(Meaning(request.body ?? Data()) == expected, "\(marker)")
            #expect(request.header("Authorization") == nil)
        }
        let multiget = CalDAVRequests.multiget(calendar, hrefs: [base + "LVPlan-user01/r01.ics"])
        let expected = Meaning(try mockRequestBody(after: "Then `calendar-multiget`"))
        #expect(multiget.count == 1 && multiget[0].method == "REPORT" && multiget[0].header("Depth") == "1")
        #expect(Meaning(multiget[0].body ?? Data()) == expected)
    }

    @Test("A multiget for 250 hrefs makes 3 batches")
    func multigetBatches() {
        let url = URL(string: "https://cis.technikum-wien.at" + base + "LVPlan-user01/")!
        let hrefs = (1...250).map { base + "LVPlan-user01/x\($0).ics" }
        let batches = CalDAVRequests.multiget(url, hrefs: hrefs)
        #expect(batches.count == 3)
        #expect(batches.map { Meaning($0.body ?? Data()).hrefs.count } == [100, 100, 50])
        #expect(batches.flatMap { Meaning($0.body ?? Data()).hrefs } == hrefs)
    }

    // MARK: Windows

    @Test("Windows: syncStart 20261007T220000Z, importStart 20251007T220000Z; 20261101T230000Z on 2 Nov")
    func windows() {
        #expect(ICSFormat.utcStamp(Windows.syncStart(now: TestClock.now, zone: vienna)) == "20261007T220000Z")
        #expect(ICSFormat.utcStamp(Windows.importStart(now: TestClock.now, zone: vienna)) == "20251007T220000Z")
        let november = TestClock.date("2026-11-02 10:00")
        #expect(ICSFormat.utcStamp(Windows.syncStart(now: november, zone: vienna)) == "20261101T230000Z")
    }

    // MARK: Transport

    @Test("A 3xx is returned, not followed")
    func redirectNotFollowed() async throws {
        let server = StubServer { _ in
            .response(HTTPResponseSpec(status: 301, headers: ["Location": "https://login.example.invalid/caldav/"]))
        }
        let transport = server.transport()
        defer { transport.invalidate() }
        let response = try await transport.send(HTTPRequest(method: "GET",
                                                            url: URL(string: "https://cis.technikum-wien.at/.well-known/caldav")!))
        #expect(response.status == 301)
        #expect(response.header("Location") == "https://login.example.invalid/caldav/")
        #expect(server.records.count == 1)
        #expect(server.records.allSatisfy { $0.host == "cis.technikum-wien.at" })
        // The delegate itself declines every redirect.
        let task = transport.session.dataTask(with: URL(string: "https://cis.technikum-wien.at/")!)
        let next = await withCheckedContinuation { (done: CheckedContinuation<URLRequest?, Never>) in
            transport.urlSession(transport.session, task: task, willPerformHTTPRedirection: HTTPURLResponse(),
                                 newRequest: URLRequest(url: URL(string: "https://login.example.invalid/")!)) {
                done.resume(returning: $0)
            }
        }
        #expect(next == nil)
    }

    @Test("A response over 20 MB is refused as too large")
    func tooLarge() async throws {
        let big = Data(repeating: 0x41, count: URLSessionTransport.maxResponseBytes + 1)
        let server = StubServer { _ in .response(HTTPResponseSpec(status: 207, body: big)) }
        let transport = server.transport()
        defer { transport.invalidate() }
        await #expect(throws: TransportError.tooLarge) {
            _ = try await transport.send(HTTPRequest(method: "REPORT", url: URL(string: "https://cis.technikum-wien.at/x")!))
        }
    }

    @Test("URLError codes map to transport errors")
    func errorMapping() {
        #expect(TransportError.from(URLError(.notConnectedToInternet)) == .offline)
        #expect(TransportError.from(URLError(.timedOut)) == .timeout)
        #expect(TransportError.from(URLError(.serverCertificateUntrusted)) == .certificate)
        #expect(TransportError.from(URLError(.cannotFindHost)) == .unreachable)
        #expect(TransportError.from(URLError(.cancelled)) == .cancelled)
    }

    // MARK: Challenges

    @Test("The challenge handler declines login.example.invalid and http://cis.technikum-wien.at")
    func challengeScope() {
        let responder = ChallengeResponder(host: "cis.technikum-wien.at", username: "user01", password: Password(sentinel))
        func request(_ s: String) -> HTTPRequest { HTTPRequest(method: "PROPFIND", url: URL(string: s)!) }
        let basic = "Basic realm=\"placeholder\""
        #expect(responder.authorization(for: request("https://login.example.invalid/caldav/"), challenge: basic) == nil)
        #expect(responder.authorization(for: request("http://cis.technikum-wien.at/webdav/lvplan.php/"), challenge: basic) == nil)
        #expect(responder.authorization(for: request("https://cis.technikum-wien.at:8443/webdav/"), challenge: basic) == nil)
        #expect(responder.authorization(for: request("https://cis.technikum-wien.at/webdav/"), challenge: "Negotiate") == nil)
        let ok = responder.authorization(for: request("https://CIS.technikum-wien.at/webdav/lvplan.php/"), challenge: basic)
        #expect(ok == "Basic " + Data("user01:\(sentinel)".utf8).base64EncodedString())
        #expect(!String(describing: responder).contains(sentinel) && !String(reflecting: responder).contains(sentinel))
    }

    @Test("Digest answers with an MD5 response for the request's method and path")
    func digest() throws {
        let responder = ChallengeResponder(host: "cis.technikum-wien.at", username: "user01", password: Password(sentinel))
        let request = HTTPRequest(method: "PROPFIND", url: URL(string: "https://cis.technikum-wien.at/webdav/lvplan.php/")!)
        let header = try #require(responder.authorization(
            for: request, challenge: "Digest realm=\"placeholder\", nonce=\"abc123\", opaque=\"xyz\""))
        func md5(_ s: String) -> String { Insecure.MD5.hash(data: Data(s.utf8)).map { String(format: "%02x", $0) }.joined() }
        let expected = md5("\(md5("user01:placeholder:\(sentinel)")):abc123:\(md5("PROPFIND:/webdav/lvplan.php/"))")
        #expect(header.contains("response=\"\(expected)\""))
        #expect(header.contains("uri=\"/webdav/lvplan.php/\"") && header.contains("opaque=\"xyz\""))
        #expect(!header.contains(sentinel))
    }

    // MARK: Session state

    @Test("No cookie, cache or credential survives into a new session")
    func freshSessions() async throws {
        let server = StubServer { _ in .response(HTTPResponseSpec(status: 200)) }
        let url = URL(string: "https://cis.technikum-wien.at/webdav/lvplan.php/")!
        let first = server.transport()
        let second = server.transport()
        defer { first.invalidate(); second.invalidate() }
        // Each ephemeral session has its own in-memory cookie store: a cookie
        // set during one connect or sync is invisible to the next.
        let firstJar = try #require(first.session.configuration.httpCookieStorage)
        let secondJar = try #require(second.session.configuration.httpCookieStorage)
        #expect(firstJar !== secondJar)
        let cookie = try #require(HTTPCookie(properties: [.domain: "cis.technikum-wien.at", .path: "/",
                                                          .name: "sid", .value: "abc", .secure: "TRUE"]))
        firstJar.setCookie(cookie)
        #expect(firstJar.cookies(for: url)?.isEmpty == false)
        #expect(secondJar.cookies(for: url)?.isEmpty ?? true)
        _ = try await second.send(HTTPRequest(method: "GET", url: url))
        #expect(server.records.allSatisfy { r in !r.headers.keys.contains { $0.lowercased() == "cookie" } })
        for configuration in [first.session.configuration, second.session.configuration] {
            #expect(configuration.urlCache == nil && configuration.urlCredentialStorage == nil)
            #expect(configuration.requestCachePolicy == .reloadIgnoringLocalCacheData)
        }
        #expect(first.session !== second.session)
    }
}
