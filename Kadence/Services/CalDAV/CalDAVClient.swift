//
//  CalDAVClient.swift
//  Kadence
//
//  PHASE3-PLAN.md task 7 — components.md §20.8.1 (cache, re-discovery),
//  §20.8.2 (windows, the fallback chain F0 → F1 → F2 on 405/501 only, member
//  failures, size and not-a-calendar checks, the 300-request cap), §20.8.4
//  (diagnostics), §21.5 (`ScheduleSource`).
//

import Foundation

// MARK: - ScheduleSource (§21.5)

nonisolated protocol ScheduleSource: Sendable {
    func fetch(windowStart: Date) async throws(ScheduleSourceError) -> ScheduleFetchResult
}

nonisolated struct ScheduleFetchResult: Sendable {
    /// Merged across the selected calendars (§20.2).
    var events: [ExternalEvent]
    var problems: [ImportProblem]
    /// VEVENTs read, before the merge — the emptyFeed guard.
    var objectCount: Int
    var mergedCount: Int
    /// Hrefs read in full — the deletion guard (§20.8).
    var calendarsReadInFully: [String]
    var failedCalendars: [(SourceCalendar, ScheduleSourceError)]
    /// After a re-discovery, the new hrefs (§20.8.1).
    var adoptedCalendars: [SourceCalendar]
    var capabilities: SourceCapabilities
    var diagnostics: SyncDiagnostics
    /// Discovery's hrefs when it ran (connect, or re-discovery).
    var principalHref: String?
    var calendarHomeHref: String?
}

// MARK: - One calendar

nonisolated struct CalendarFetch: Sendable {
    var objects: [FeedObject] = []
    var problems: [ImportProblem] = []
    var mode: FetchMode
    var timeRangeHonoured: Bool?
    var ctag: String?
    var etags: [String] = []
}

nonisolated enum CalendarFetchFailure: Error, Equatable, Sendable {
    /// `404`/`410`, or `301`/`308` to the same host: the calendar moved or went.
    case rediscover
    case failed(ScheduleSourceError)
}

nonisolated enum CalDAVClient {

    /// Fetches one calendar, starting at `mode` (remembered from earlier
    /// polls) and falling back only on `405`/`501`.
    static func fetch(calendar url: URL, displayName: String, windowStart: Date, mode: FetchMode,
                      session: CalDAVSession, zone: TimeZone) async throws(CalendarFetchFailure) -> CalendarFetch {
        var chain: [String] = []
        do {
            if mode == .report {
                let request = CalDAVRequests.calendarQuery(url, start: windowStart)
                let response = try await session.send(request)
                chain.append("REPORT \(response.status)")
                if !refused(response.status) {
                    try check(response, for: request, session: session)
                    var fetch = try read207(response, calendar: url, mode: .report, zone: zone)
                    fetch.timeRangeHonoured = !fetch.objects.contains { object in
                        object.calendar.events.contains { $0.end.instant <= windowStart }
                    }
                    return fetch
                }
            }
            // F1 — the member list, then calendar-multiget.
            let listing = CalDAVRequests.calendarPropfind(url)
            let listed = try await session.send(listing)
            chain.append("PROPFIND \(listed.status)")
            if refused(listed.status) {
                throw CalendarFetchFailure.failed(.fetchFailed(technical: chain.joined(separator: " · ")))
            }
            try check(listed, for: listing, session: session)
            guard let members = MultistatusParser.parse(listed.body) else { throw CalendarFetchFailure.failed(.notACalendar) }
            let collection = members.first { session.resolve($0.href, against: url)?.storedPath == url.storedPath }
            let ctag = collection?.ok(DAVNamespace.calendarServer, "getctag")?.text
            let hrefs = members.compactMap { member -> String? in
                guard let resolved = session.resolve(member.href, against: url),
                      resolved.storedPath != url.storedPath,
                      member.ok(DAVNamespace.dav, "resourcetype")?.has(DAVNamespace.dav, "collection") != true
                else { return nil }
                return resolved.storedPath
            }
            if mode != .get {
                var fetch = CalendarFetch(mode: .multiget, ctag: ctag)
                var refusedMultiget = false
                for request in CalDAVRequests.multiget(url, hrefs: hrefs) {
                    let response = try await session.send(request)
                    if refused(response.status) {
                        chain.append("calendar-multiget \(response.status)")
                        refusedMultiget = true
                        break
                    }
                    try check(response, for: request, session: session)
                    let batch = try read207(response, calendar: url, mode: .multiget, zone: zone)
                    fetch.objects += batch.objects
                    fetch.problems += batch.problems
                    fetch.etags += batch.etags
                }
                if !refusedMultiget { return fetch }
            }
            // F2 — GET each member, one at a time.
            var fetch = CalendarFetch(mode: .get, ctag: ctag)
            for href in hrefs {
                guard let objectURL = session.resolve(href, against: url) else { continue }
                let request = CalDAVRequests.getObject(objectURL)
                let response: HTTPResponse
                do {
                    response = try await session.send(request)
                } catch .fetchFailed {
                    throw CalendarFetchFailure.failed(.fetchFailed(
                        technical: "Request cap reached (\(CalDAVSession.requestCap)) reading \(displayName) one object at a time"))
                }
                if refused(response.status) {
                    chain.append("GET \(response.status)")
                    throw CalendarFetchFailure.failed(.fetchFailed(technical: chain.joined(separator: " · ")))
                }
                let name = objectName(href)
                if response.status == 404 || response.status == 410 {
                    // SPEC-GAP G-069: per-problem sentence.
                    fetch.problems.append(ImportProblem(sentence: "1 event couldn't be read",
                                                        technical: "Object \(name): GET \(response.status)"))
                    continue
                }
                if response.status >= 500 { throw CalendarFetchFailure.failed(.serverError(response.status)) }
                guard response.status == 200 else {
                    fetch.problems.append(ImportProblem(sentence: "1 event couldn't be read",
                                                        technical: "Object \(name): GET \(response.status)"))
                    continue
                }
                let text = String(decoding: response.body, as: UTF8.self)
                guard ICSParser.isCalendar(text) else { throw CalendarFetchFailure.failed(.notACalendar) }
                if let etag = response.header("ETag") { fetch.etags.append("\(href)=\(etag)") }
                read(object: text, href: href, calendar: url, into: &fetch, zone: zone)
            }
            return fetch
        } catch let failure as CalendarFetchFailure {
            throw failure
        } catch let error as ScheduleSourceError {
            if case .fetchFailed = error {
                throw .failed(.fetchFailed(technical: "Request cap reached (\(CalDAVSession.requestCap)) reading \(displayName)"))
            }
            throw .failed(error)
        } catch {
            throw .failed(.unreachable)
        }
    }

    private static func refused(_ status: Int) -> Bool { status == 405 || status == 501 }

    /// Statuses that end the chain at this step (§20.8.2: any failure other
    /// than 405/501 maps to §19.1 there).
    private static func check(_ response: HTTPResponse, for request: HTTPRequest,
                              session: CalDAVSession) throws(CalendarFetchFailure) {
        switch response.status {
        case 200, 207:
            return
        case 404, 410:
            throw .rediscover
        case 301, 308:
            guard let location = response.header("Location"),
                  let target = URL(string: location, relativeTo: request.url)?.absoluteURL else { throw .failed(.noCalDAV) }
            guard target.scheme?.lowercased() == "https" else { throw .failed(.redirected(otherHost: nil)) }
            guard session.isOwn(target) else { throw .failed(.redirected(otherHost: target.host())) }
            throw .rediscover
        case 300..<400:
            throw .failed(.redirected(otherHost: response.header("Location").flatMap { URL(string: $0)?.host() }))
        case 500...:
            throw .failed(.serverError(response.status))
        default:
            throw .failed(.fetchFailed(technical: "\(request.method) \(response.status)"))
        }
    }

    /// A `207` from F0 or a multiget → objects, member failures as problems.
    private static func read207(_ response: HTTPResponse, calendar: URL, mode: FetchMode,
                                zone: TimeZone) throws(CalendarFetchFailure) -> CalendarFetch {
        // A 200 web page where a 207 was expected (§20.8.2).
        guard let responses = MultistatusParser.parse(response.body) else { throw .failed(.notACalendar) }
        var fetch = CalendarFetch(mode: mode)
        for item in responses {
            let name = objectName(item.href)
            if let status = item.status, status != 200 {
                fetch.problems.append(ImportProblem(sentence: "1 event couldn't be read",   // SPEC-GAP G-069
                                                    technical: "Object \(name): \(status)"))
                continue
            }
            guard let found = item.property(DAVNamespace.caldav, "calendar-data") else { continue }
            guard found.status == 200 else {
                fetch.problems.append(ImportProblem(sentence: "1 event couldn't be read",   // SPEC-GAP G-069
                                                    technical: "Object \(name): calendar-data \(found.status)"))
                continue
            }
            if let etag = item.ok(DAVNamespace.dav, "getetag")?.text { fetch.etags.append("\(item.href)=\(etag)") }
            read(object: found.element.text, href: item.href, calendar: calendar, into: &fetch, zone: zone)
        }
        return fetch
    }

    /// One object's `calendar-data`; a bad one is a problem, not a failure.
    private static func read(object text: String, href: String, calendar: URL, into fetch: inout CalendarFetch,
                             zone: TimeZone) {
        switch ICSParser.parse(text, currentZone: zone) {
        case .calendar(let parsed):
            fetch.objects.append(FeedObject(calendarHref: calendar.storedPath, objectHref: href, calendar: parsed))
        case .notACalendar:
            fetch.problems.append(ImportProblem(sentence: "1 event couldn't be read",   // SPEC-GAP G-069
                                                technical: "Object \(objectName(href)): not calendar data"))
        }
    }

    static func objectName(_ href: String) -> String {
        let trimmed = href.hasSuffix("/") ? String(href.dropLast()) : href
        let last = trimmed.split(separator: "/").last.map(String.init) ?? href
        return last.removingPercentEncoding ?? last
    }
}

// MARK: - CalDAVScheduleSource

/// What a sync needs of a `Source`, as a value (the source itself stays on
/// the main actor).
nonisolated struct CalDAVAccount: Sendable, Equatable {
    var server: ServerAddress
    var username: String
    var calendars: [SourceCalendar]
    var capabilities: SourceCapabilities

    var secretAccount: SecretAccount { SecretAccount(host: server.host, port: server.port, username: username) }
}

nonisolated final class CalDAVScheduleSource: ScheduleSource {
    let account: CalDAVAccount
    let secrets: any SecretStore
    /// A fresh transport per sync (§21.4).
    let makeTransport: @Sendable () -> any HTTPTransport
    let zone: TimeZone
    let now: @Sendable () -> Date

    init(account: CalDAVAccount, secrets: any SecretStore, zone: TimeZone = .current,
         now: @escaping @Sendable () -> Date = { Date() },
         makeTransport: @escaping @Sendable () -> any HTTPTransport) {
        self.account = account
        self.secrets = secrets
        self.zone = zone
        self.now = now
        self.makeTransport = makeTransport
    }

    func fetch(windowStart: Date) async throws(ScheduleSourceError) -> ScheduleFetchResult {
        // §20.8.3 step 1: the password, or no request at all.
        let password: Password
        do {
            guard let saved = try secrets.read(account.secretAccount) else { throw ScheduleSourceError.passwordMissing }
            password = saved
        } catch { throw .passwordMissing }

        let transport = makeTransport()
        defer { (transport as? URLSessionTransport)?.invalidate() }
        let session = CalDAVSession(transport: transport, host: account.server.host, port: account.server.port,
                                    username: account.username, password: password)
        return try await Self.run(account: account, windowStart: windowStart, session: session, zone: zone, now: now())
    }

    /// The sync's body, also used by the connect sheet with its own session.
    static func run(account: CalDAVAccount, windowStart: Date, session: CalDAVSession, zone: TimeZone,
                    now: Date, discovery: DiscoveryResult? = nil) async throws(ScheduleSourceError) -> ScheduleFetchResult {
        let started = Date()
        var capabilities = account.capabilities
        var mode = capabilities.fetchMode
        var objects: [FeedObject] = []
        var problems: [ImportProblem] = []
        var readInFully: [String] = []
        var failed: [(SourceCalendar, ScheduleSourceError)] = []
        var adopted: [SourceCalendar] = []
        var diagnostics = SyncDiagnostics()
        var rediscovered: DiscoveryResult? = discovery
        var didRediscover = false
        var modes: [FetchMode] = []

        for calendar in account.calendars {
            var current = calendar
            var attempt = 0
            while true {
                attempt += 1
                guard let url = URL(string: current.href, relativeTo: account.server.baseURL)?.absoluteURL,
                      session.isOwn(url) else { failed.append((calendar, .calendarMissing)); break }
                do {
                    let fetch = try await CalDAVClient.fetch(calendar: url, displayName: current.displayName,
                                                             windowStart: windowStart, mode: mode,
                                                             session: session, zone: zone)
                    objects += fetch.objects
                    problems += fetch.problems
                    readInFully.append(current.href)
                    if current != calendar { adopted.append(current) }
                    modes.append(fetch.mode)
                    if fetch.mode == .report { capabilities.timeRangeHonoured = fetch.timeRangeHonoured }
                    if let ctag = fetch.ctag { diagnostics.ctags.append(ctag) }
                    diagnostics.etags += fetch.etags
                    diagnostics.calendarNames.append(current.displayName)
                    break
                } catch .rediscover {
                    // Once per sync (§20.8.1): D1–D4 again, match by href,
                    // then by a unique display name.
                    guard attempt == 1 else { failed.append((calendar, .calendarMissing)); break }
                    if !didRediscover {
                        didRediscover = true
                        do {
                            rediscovered = try await CalDAVDiscovery.discover(server: account.server, session: session)
                        } catch .noCalendars {
                            rediscovered = DiscoveryResult(contextURL: account.server.baseURL, principalHref: "",
                                                           calendarHomeHref: "", calendars: [])
                        }
                        capabilities.discoveredAt = now
                        mode = .report
                    }
                    let listed = rediscovered?.calendars ?? []
                    if let byHref = listed.first(where: { $0.href == current.href && current.href != calendar.href }) {
                        current = SourceCalendar(href: byHref.href, displayName: byHref.displayName)
                    } else {
                        let named = listed.filter { $0.displayName == current.displayName }
                        if named.count == 1, named[0].href != current.href {
                            current = SourceCalendar(href: named[0].href, displayName: named[0].displayName)
                        } else {
                            failed.append((calendar, .calendarMissing))
                            diagnostics.calendarNames.append(calendar.displayName)
                            break
                        }
                    }
                } catch {
                    // Swift note: with typed throws, `error` here is a
                    // `CalendarFetchFailure`; `.rediscover` was caught above.
                    guard case .failed(let error) = error else { throw .unreachable }
                    switch error {
                    case .calendarMissing, .fetchFailed, .notACalendar:
                        failed.append((calendar, error))
                        diagnostics.calendarNames.append(calendar.displayName)
                    default:
                        throw error
                    }
                    break
                }
            }
        }
        // The slowest mode any calendar needed is what later polls start at.
        if modes.contains(.get) { mode = .get } else if modes.contains(.multiget) { mode = .multiget }
        else if !modes.isEmpty { mode = .report }
        capabilities.fetchMode = mode

        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        let feed = FeedDerivation.derive(objects, today: cal.startOfDay(for: now), zone: zone)
        diagnostics.mode = mode
        diagnostics.requests = await session.requestCount
        diagnostics.milliseconds = Int(Date().timeIntervalSince(started) * 1000)
        diagnostics.objects = feed.objectCount
        diagnostics.timeRangeHonoured = capabilities.timeRangeHonoured
        return ScheduleFetchResult(
            events: feed.events, problems: problems + feed.problems, objectCount: feed.objectCount,
            mergedCount: feed.mergedCount, calendarsReadInFully: readInFully, failedCalendars: failed,
            adoptedCalendars: adopted, capabilities: capabilities, diagnostics: diagnostics,
            principalHref: rediscovered?.principalHref, calendarHomeHref: rediscovered?.calendarHomeHref)
    }
}

// MARK: - The mock (§21.5: "returns fixture results directly")

nonisolated struct MockScheduleSource: ScheduleSource {
    var result: Result<ScheduleFetchResult, ScheduleSourceError>
    func fetch(windowStart: Date) async throws(ScheduleSourceError) -> ScheduleFetchResult { try result.get() }
}
