//
//  CalDAVDiscovery.swift
//  Kadence
//
//  PHASE3-PLAN.md task 6 — components.md §20.8.1: D1 `/.well-known/caldav` →
//  D2 principal → D3 calendar home → D4 the calendars, with the selection
//  rule, the `Server` path shortcut, href resolution (off-host hrefs are
//  ignored) and 401 handling (interactions.md §13.1, via `CalDAVSession`).
//

import Foundation

// MARK: - The server the user typed (layouts.md §12.1)

/// `Server` normalised: `https://` + host (lower-cased) + port when not 443,
/// + the path when one was typed (§21.1 `serverURL`).
nonisolated struct ServerAddress: Sendable, Equatable {
    var host: String
    var port: Int = 443
    /// A typed path skips D1 and is the context URL (§20.8.1).
    var path: String?

    var baseURL: URL {
        var c = URLComponents()
        c.scheme = "https"; c.host = host
        if port != 443 { c.port = port }
        return c.url ?? URL(string: "https://\(host)")!
    }

    /// The context URL when a path was typed.
    var contextURL: URL? {
        guard let path, !path.isEmpty, path != "/" else { return nil }
        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    /// What `Source.serverURL` stores.
    var normalized: String {
        var text = "https://\(host)"
        if port != 443 { text += ":\(port)" }
        if let path, !path.isEmpty, path != "/" { text += path }
        return text
    }

    /// The validation outcomes of layouts.md §12.1's table (`Server` rows).
    enum Problem: Error, Equatable, Sendable {
        case empty
        case http
        case notAServer
        case containsUser
        case webdavShare
    }

    /// Parses `Server` as typed. Leading and trailing whitespace is trimmed
    /// silently.
    static func parse(_ typed: String) -> Result<ServerAddress, Problem> {
        let text = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .failure(.empty) }
        let lower = text.lowercased()
        if lower.hasPrefix("http://") { return .failure(.http) }
        if text.contains(where: \.isWhitespace) { return .failure(.notAServer) }
        var candidate = text
        if let range = lower.range(of: "://") {
            guard lower.hasPrefix("https://") else { return .failure(.notAServer) }
            candidate = String(text[range.upperBound...])
        }
        // `user@` or `user:pass@` in the authority — before the first `/`.
        let authority = candidate.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        if authority.contains("@") { return .failure(.containsUser) }
        guard let components = URLComponents(string: "https://" + candidate),
              let host = components.host, !host.isEmpty,
              host.range(of: #"^[A-Za-z0-9.-]+$"#, options: .regularExpression) != nil,
              !host.hasPrefix("."), !host.hasSuffix("."),
              components.query == nil, components.fragment == nil else { return .failure(.notAServer) }
        let port = components.port ?? 443
        guard (1...65_535).contains(port) else { return .failure(.notAServer) }
        let path = components.percentEncodedPath
        let lowerPath = path.lowercased()
        let trimmedPath = lowerPath.hasSuffix("/") ? String(lowerPath.dropLast()) : lowerPath
        if trimmedPath == "/webdav/lvplan" || lowerPath.hasPrefix("/webdav/lvplan/") { return .failure(.webdavShare) }
        return .success(ServerAddress(host: host.lowercased(), port: port,
                                      path: path.isEmpty || path == "/" ? nil : path))
    }

    /// From a stored `Source.serverURL`.
    init?(stored: String?) {
        guard let stored, case .success(let address) = Self.parse(stored) else { return nil }
        self = address
    }

    init(host: String, port: Int = 443, path: String? = nil) {
        self.host = host; self.port = port; self.path = path
    }
}

// MARK: - The result

nonisolated struct DiscoveredCalendar: Sendable, Equatable {
    /// Absolute path on the source's host.
    var href: String
    var displayName: String
    var components: [String]
    /// Logged, never stored (§20.8.4).
    var ctag: String?
}

nonisolated struct DiscoveryResult: Sendable, Equatable {
    var contextURL: URL
    var principalHref: String
    var calendarHomeHref: String
    var calendars: [DiscoveredCalendar]
    /// Off-host hrefs D4 named and Kadence ignored (logged by the caller).
    var ignoredHrefs: [String] = []
}

// MARK: - Discovery

nonisolated enum CalDAVDiscovery {

    /// D1–D4. Throws the §19.1 state the step ends in.
    static func discover(server: ServerAddress, session: CalDAVSession) async throws(ScheduleSourceError) -> DiscoveryResult {
        // D1 — skipped when `Server` holds a path.
        let context: URL
        if let typed = server.contextURL {
            context = typed
        } else {
            let request = CalDAVRequests.wellKnown(base: server.baseURL)
            let response = try await session.send(request)
            guard response.isRedirect, let location = response.header("Location"),
                  let target = URL(string: location, relativeTo: request.url)?.absoluteURL else { throw .noCalDAV }
            guard target.scheme?.lowercased() == "https" else { throw .redirected(otherHost: nil) }
            guard session.isOwn(target) else { throw .redirected(otherHost: target.host()) }
            context = target
        }

        // D2 — the principal (and maybe the home).
        let d2 = CalDAVRequests.contextPropfind(context)
        let d2Response = try await session.send(d2)
        try refuseForeignRedirect(d2Response, for: d2, session: session)
        guard d2Response.status == 207, let d2Body = MultistatusParser.parse(d2Response.body) else { throw .noCalDAV }
        guard let principalHref = d2Body.lazy.compactMap({ $0.ok(DAVNamespace.dav, "current-user-principal")?.hrefs.first }).first,
              let principal = session.resolve(principalHref, against: d2.url) else { throw .noCalDAV }
        var home = d2Body.lazy.compactMap { $0.ok(DAVNamespace.caldav, "calendar-home-set")?.hrefs.first }.first
            .flatMap { session.resolve($0, against: d2.url) }

        // D3 — the home, unless D2 already gave it.
        if home == nil {
            let d3 = CalDAVRequests.principalPropfind(principal)
            let d3Response = try await session.send(d3)
            try refuseForeignRedirect(d3Response, for: d3, session: session)
            guard d3Response.status == 207, let d3Body = MultistatusParser.parse(d3Response.body) else { throw .noCalDAV }
            home = d3Body.lazy.compactMap { $0.ok(DAVNamespace.caldav, "calendar-home-set")?.hrefs.first }.first
                .flatMap { session.resolve($0, against: d3.url) }
        }
        guard let home else { throw .noCalDAV }

        // D4 — the calendars.
        let (calendars, ignored) = try await listCalendars(home: home, session: session)
        guard !calendars.isEmpty else { throw .noCalendars }
        return DiscoveryResult(contextURL: context, principalHref: principal.storedPath,
                               calendarHomeHref: home.storedPath, calendars: calendars, ignoredHrefs: ignored)
    }

    /// interactions.md §13.1 (ruled 2026-10-10, PHASE3-REVIEW fix 3): a `3xx`
    /// to another host or to `http:` ends `redirected` **at every step** —
    /// D2, D3 and D4 as well as D1 — not `noCalDAV`. The transport never
    /// followed it (its delegate refuses every redirect); this only names
    /// what happened, so the user reads "sent Kadence to {host}" instead of
    /// "no calendar server found". A `3xx` to the same host over `https` at
    /// D2–D4 is left to the caller's `207` check, as before.
    static func refuseForeignRedirect(_ response: HTTPResponse, for request: HTTPRequest,
                                      session: CalDAVSession) throws(ScheduleSourceError) {
        guard (300..<400).contains(response.status), let location = response.header("Location"),
              let target = URL(string: location, relativeTo: request.url)?.absoluteURL else { return }
        guard target.scheme?.lowercased() == "https" else { throw .redirected(otherHost: nil) }
        guard session.isOwn(target) else { throw .redirected(otherHost: target.host()) }
    }

    /// D4 and §20.8.1's selection rule.
    static func listCalendars(home: URL, session: CalDAVSession)
        async throws(ScheduleSourceError) -> ([DiscoveredCalendar], [String]) {
        let d4 = CalDAVRequests.homePropfind(home)
        let response = try await session.send(d4)
        try refuseForeignRedirect(response, for: d4, session: session)
        guard response.status == 207, let body = MultistatusParser.parse(response.body) else { throw .noCalDAV }
        var calendars: [DiscoveredCalendar] = []
        var ignored: [String] = []
        let homePath = normalisedPath(home.storedPath)
        for item in body {
            guard let url = URL(string: item.href, relativeTo: d4.url)?.absoluteURL else { continue }
            guard session.isOwn(url) else { ignored.append(item.href); continue }
            // 1. Not the home itself.
            guard normalisedPath(url.storedPath) != homePath else { continue }
            // 2–3. A calendar, and neither outbox nor inbox.
            guard let type = item.ok(DAVNamespace.dav, "resourcetype"),
                  type.has(DAVNamespace.caldav, "calendar"),
                  !type.has(DAVNamespace.caldav, "schedule-outbox"),
                  !type.has(DAVNamespace.caldav, "schedule-inbox") else { continue }
            // 4. VEVENT, or the set absent / 404 (RFC 4791: every component).
            let comps = item.ok(DAVNamespace.caldav, "supported-calendar-component-set")?
                .children(DAVNamespace.caldav, "comp").compactMap { $0.attributes["name"]?.uppercased() }
            if let comps, !comps.isEmpty, !comps.contains("VEVENT") { continue }
            let name = item.ok(DAVNamespace.dav, "displayname")?.text.trimmingCharacters(in: .whitespacesAndNewlines)
            calendars.append(DiscoveredCalendar(
                href: url.storedPath,
                displayName: (name?.isEmpty == false ? name : nil) ?? lastSegment(url),
                components: comps ?? [],
                ctag: item.ok(DAVNamespace.calendarServer, "getctag")?.text))
        }
        return (calendars, ignored)
    }

    /// The href's last path segment, percent-decoded (`LVPlan-user01`).
    static func lastSegment(_ url: URL) -> String {
        let parts = url.path(percentEncoded: true).split(separator: "/")
        guard let last = parts.last else { return url.host() ?? "" }
        return String(last).removingPercentEncoding ?? String(last)
    }

    private static func normalisedPath(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }
}
