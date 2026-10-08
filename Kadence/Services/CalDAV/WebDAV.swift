//
//  WebDAV.swift
//  Kadence
//
//  PHASE3-PLAN.md task 5 — the WebDAV/CalDAV XML: a `207 Multi-Status`
//  parser, the request builders of caldav-mocks.md, the Import and sync
//  windows (components.md §20.8.2), and the one source logger (§21.4).
//
//  Foundation only: `XMLParser` with namespace processing on, so elements are
//  matched by (namespace URI, local name) and prefixes never matter.
//

import Foundation
import CryptoKit
import os
import Synchronization

// MARK: - Namespaces

nonisolated enum DAVNamespace {
    static let dav = "DAV:"
    static let caldav = "urn:ietf:params:xml:ns:caldav"
    static let calendarServer = "http://calendarserver.org/ns/"
    static let sabre = "http://sabredav.org/ns"
}

// MARK: - The parsed tree

/// One XML element, by namespace and local name.
nonisolated struct DAVElement: Sendable, Equatable {
    var namespace: String
    var name: String
    var attributes: [String: String] = [:]
    /// The element's own character data (CDATA included), as the parser
    /// delivers it: XML end-of-line handling has already turned CRLF into LF.
    var text: String = ""
    var children: [DAVElement] = []

    func child(_ namespace: String, _ name: String) -> DAVElement? {
        children.first { $0.namespace == namespace && $0.name == name }
    }

    func children(_ namespace: String, _ name: String) -> [DAVElement] {
        children.filter { $0.namespace == namespace && $0.name == name }
    }

    func has(_ namespace: String, _ name: String) -> Bool { child(namespace, name) != nil }

    /// The `d:href` children's texts, trimmed.
    var hrefs: [String] {
        children(DAVNamespace.dav, "href").map { $0.text.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

nonisolated struct DAVPropstat: Sendable, Equatable {
    /// From `HTTP/1.1 200 OK`.
    var status: Int
    var props: [DAVElement]
}

nonisolated struct DAVResponse: Sendable, Equatable {
    var href: String
    var propstats: [DAVPropstat]
    /// A response-level `d:status` (a member `404` in a multiget).
    var status: Int?

    /// A property, with the status of the propstat that carried it.
    func property(_ namespace: String, _ name: String) -> (element: DAVElement, status: Int)? {
        for propstat in propstats {
            if let e = propstat.props.first(where: { $0.namespace == namespace && $0.name == name }) {
                return (e, propstat.status)
            }
        }
        return nil
    }

    /// The property only when its propstat is `200`.
    func ok(_ namespace: String, _ name: String) -> DAVElement? {
        guard let found = property(namespace, name), found.status == 200 else { return nil }
        return found.element
    }
}

// MARK: - The 207 parser

nonisolated enum MultistatusParser {
    /// A `207` body → its responses; nil when the body is not a DAV
    /// `multistatus` document (a web page, garbage).
    static func parse(_ data: Data) -> [DAVResponse]? {
        guard let root = parseTree(data), root.namespace == DAVNamespace.dav, root.name == "multistatus" else {
            return nil
        }
        return root.children(DAVNamespace.dav, "response").map { response in
            DAVResponse(
                href: response.hrefs.first ?? "",
                propstats: response.children(DAVNamespace.dav, "propstat").map { propstat in
                    DAVPropstat(status: statusCode(propstat.child(DAVNamespace.dav, "status")?.text),
                                props: propstat.child(DAVNamespace.dav, "prop")?.children ?? [])
                },
                status: response.child(DAVNamespace.dav, "status").map { statusCode($0.text) })
        }
    }

    /// `HTTP/1.1 404 Not Found` → 404 (0 when unreadable).
    static func statusCode(_ line: String?) -> Int {
        guard let parts = line?.split(separator: " "), parts.count >= 2, let code = Int(parts[1]) else { return 0 }
        return code
    }

    static func parseTree(_ data: Data) -> DAVElement? {
        let delegate = TreeBuilder()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = false
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), let root = delegate.root else { return nil }
        return root
    }

    /// Swift note: `XMLParser` is SAX-style (callbacks, like Java's
    /// `DefaultHandler`); this delegate keeps a stack and builds the tree.
    private final class TreeBuilder: NSObject, XMLParserDelegate {
        var stack: [DAVElement] = []
        var root: DAVElement?

        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
            stack.append(DAVElement(namespace: namespaceURI ?? "", name: elementName, attributes: attributeDict))
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard !stack.isEmpty else { return }
            stack[stack.count - 1].text += string
        }

        func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
            guard !stack.isEmpty else { return }
            stack[stack.count - 1].text += String(decoding: CDATABlock, as: UTF8.self)
        }

        func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?,
                    qualifiedName qName: String?) {
            guard let done = stack.popLast() else { return }
            if stack.isEmpty { root = done } else { stack[stack.count - 1].children.append(done) }
        }
    }
}

// MARK: - Requests (caldav-mocks.md)

nonisolated enum CalDAVRequests {
    static let xmlType = "application/xml; charset=utf-8"
    /// §20.8.2: `calendar-multiget` batches of at most 100 hrefs.
    static let multigetBatch = 100

    /// D1 — `GET /.well-known/caldav`.
    static func wellKnown(base: URL) -> HTTPRequest {
        HTTPRequest(method: "GET", url: base.appending(path: ".well-known/caldav"))
    }

    /// D2 — `PROPFIND` Depth 0 on the context URL.
    static func contextPropfind(_ url: URL) -> HTTPRequest {
        propfind(url, depth: "0", body: """
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
          <d:prop>
            <d:current-user-principal/>
            <cal:calendar-home-set/>
            <d:resourcetype/>
          </d:prop>
        </d:propfind>
        """)
    }

    /// D3 — `PROPFIND` Depth 0 on the principal.
    static func principalPropfind(_ url: URL) -> HTTPRequest {
        propfind(url, depth: "0", body: """
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
          <d:prop>
            <cal:calendar-home-set/>
          </d:prop>
        </d:propfind>
        """)
    }

    /// D4 — `PROPFIND` Depth 1 on the calendar home.
    static func homePropfind(_ url: URL) -> HTTPRequest {
        propfind(url, depth: "1", body: """
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/">
          <d:prop>
            <d:resourcetype/>
            <d:displayname/>
            <cal:supported-calendar-component-set/>
            <cs:getctag/>
            <d:sync-token/>
          </d:prop>
        </d:propfind>
        """)
    }

    /// F0 — `REPORT calendar-query` with a `start` and no `end`.
    static func calendarQuery(_ url: URL, start: Date) -> HTTPRequest {
        HTTPRequest(method: "REPORT", url: url, headers: ["Depth": "1", "Content-Type": xmlType], body: Data("""
        <?xml version="1.0" encoding="utf-8"?>
        <cal:calendar-query xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
          <d:prop>
            <d:getetag/>
            <cal:calendar-data/>
          </d:prop>
          <cal:filter>
            <cal:comp-filter name="VCALENDAR">
              <cal:comp-filter name="VEVENT">
                <cal:time-range start="\(ICSFormat.utcStamp(start))"/>
              </cal:comp-filter>
            </cal:comp-filter>
          </cal:filter>
        </cal:calendar-query>
        """.utf8))
    }

    /// F1, first half — `PROPFIND` Depth 1 on a calendar.
    static func calendarPropfind(_ url: URL) -> HTTPRequest {
        propfind(url, depth: "1", body: """
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:cs="http://calendarserver.org/ns/">
          <d:prop>
            <d:resourcetype/>
            <d:getetag/>
            <d:getcontenttype/>
            <cs:getctag/>
          </d:prop>
        </d:propfind>
        """)
    }

    /// F1, second half — `calendar-multiget`, one request per ≤ 100 hrefs.
    static func multiget(_ url: URL, hrefs: [String]) -> [HTTPRequest] {
        stride(from: 0, to: hrefs.count, by: multigetBatch).map { offset in
            let batch = hrefs[offset..<min(offset + multigetBatch, hrefs.count)]
            let hrefLines = batch.map { "  <d:href>\(escape($0))</d:href>" }.joined(separator: "\n")
            return HTTPRequest(method: "REPORT", url: url, headers: ["Depth": "1", "Content-Type": xmlType], body: Data("""
            <?xml version="1.0" encoding="utf-8"?>
            <cal:calendar-multiget xmlns:d="DAV:" xmlns:cal="urn:ietf:params:xml:ns:caldav">
              <d:prop>
                <d:getetag/>
                <cal:calendar-data/>
              </d:prop>
            \(hrefLines)
            </cal:calendar-multiget>
            """.utf8))
        }
    }

    /// F2 — `GET` one object.
    static func getObject(_ url: URL) -> HTTPRequest { HTTPRequest(method: "GET", url: url) }

    private static func propfind(_ url: URL, depth: String, body: String) -> HTTPRequest {
        HTTPRequest(method: "PROPFIND", url: url, headers: ["Depth": depth, "Content-Type": xmlType], body: Data(body.utf8))
    }

    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}

// MARK: - Windows (§20.8.2)

nonisolated enum Windows {
    /// The sync window's `start`: `startOfDay(today)`.
    static func syncStart(now: Date, zone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.startOfDay(for: now)
    }

    /// The Import window's `start`. §20.8.2 writes `startOfDay(today) − 366
    /// days` but pins the value `20251007T220000Z` for 8 Oct 2026, which is
    /// one calendar year back (366 days back is 7 Oct 2025). The pinned value
    /// is what the tests and caldav-mocks.md assert, so this is one calendar
    /// year (GAPS G-071, DEVIATIONS D7).
    static func importStart(now: Date, zone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let today = cal.startOfDay(for: now)
        return cal.date(byAdding: .year, value: -1, to: today) ?? today.addingTimeInterval(-366 * 86_400)
    }
}

// MARK: - Diagnostics and the source logger (§20.8.4, §21.4)

/// The values of one §20.8.4 log line. Never stored.
nonisolated struct SyncDiagnostics: Sendable, Equatable {
    var calendarNames: [String] = []
    var mode: FetchMode = .report
    var requests = 0
    var milliseconds = 0
    var objects = 0
    var timeRangeHonoured: Bool?
    var ctags: [String] = []
    /// `href=etag` lines.
    var etags: [String] = []

    /// The first 8 hex digits of SHA-256 over the sorted `href=etag` lines.
    var etagSet: String {
        String(ICSFormat.sha256Hex(etags.sorted().joined(separator: "\n")).prefix(8))
    }
}

/// Every log line about a source goes through here. It takes a source's
/// account and name — never a request, a header or a body (§21.4).
///
/// Swift note: `nonisolated` + `Sendable` so the CalDAV client can log from
/// off the main actor; the test sink sits behind a `Mutex`.
nonisolated final class SourceLogger: Sendable {
    static let shared = SourceLogger()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "XIX.Kadence", category: "sync")
    private let sinks = Mutex<[UUID: @Sendable (String) -> Void]>([:])

    /// Tests capture lines: returns a token to pass to `removeSink`.
    @discardableResult
    func addSink(_ sink: @escaping @Sendable (String) -> Void) -> UUID {
        let id = UUID()
        sinks.withLock { $0[id] = sink }
        return id
    }

    func removeSink(_ id: UUID) { _ = sinks.withLock { $0.removeValue(forKey: id) } }

    /// The §20.8.4 line: `sync user01 @ cis.technikum-wien.at · LVPlan · mode
    /// report · requests 1 · 412 ms · objects 287 · time-range honoured ·
    /// ctag — · etags 287 (set 3f9a01c2) · feed unchanged`.
    static func syncLine(account: String, diagnostics d: SyncDiagnostics, outcome: String) -> String {
        let range = switch d.timeRangeHonoured {
        case true?: "time-range honoured"
        case false?: "time-range ignored"
        case nil: "time-range —"
        }
        return ["sync \(account)",
                d.calendarNames.isEmpty ? "—" : d.calendarNames.joined(separator: ", "),
                "mode \(d.mode.rawValue)",
                "requests \(d.requests)",
                "\(d.milliseconds) ms",
                "objects \(d.objects)",
                range,
                "ctag \(d.ctags.isEmpty ? "—" : d.ctags.joined(separator: ", "))",
                "etags \(d.etags.count) (set \(d.etagSet))",
                outcome].joined(separator: " · ")
    }

    @MainActor
    func sync(_ source: Source, diagnostics: SyncDiagnostics, outcome: String) {
        emit(Self.syncLine(account: source.accountDisplay ?? source.displayName, diagnostics: diagnostics,
                           outcome: outcome))
    }

    /// An error in §19.1's vocabulary: the state name and its title.
    @MainActor
    func state(_ source: Source, state: SourceState, technical: String? = nil) {
        var line = "state \(source.accountDisplay ?? source.displayName) · \(state.rawValue)"
        if let technical { line += " · \(technical)" }
        emit(line)
    }

    /// A non-secret event (an adopted href, an ignored off-host href).
    @MainActor
    func note(_ source: Source, _ text: String) {
        emit("note \(source.accountDisplay ?? source.displayName) · \(text)")
    }

    func note(account: String, _ text: String) { emit("note \(account) · \(text)") }

    private func emit(_ line: String) {
        // Swift note: `privacy: .public` — the unified log redacts dynamic
        // strings by default. Nothing in these lines is secret (§21.4).
        logger.info("\(line, privacy: .public)")
        for sink in sinks.withLock({ Array($0.values) }) { sink(line) }
    }
}
