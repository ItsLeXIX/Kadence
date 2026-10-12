//
//  ConnectSheetModel.swift
//  Kadence
//
//  PHASE3-PLAN.md task 13 — layouts.md §12 (the connect sheet: step 1,
//  step 2, edit mode), interactions.md §13.1–§13.2, components.md §19.1,
//  §20.1, §20.8.1.
//
//  Nothing is persisted before `Import` / `Save` (DECISIONS 2026-10-08): the
//  discovery result, the fetched objects and the typed password live in this
//  model only, and go with it when the sheet closes.
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class ConnectSheetModel {

    enum Field: Hashable { case name, server, username, password, connect }

    enum Phase: Equatable {
        case editing
        case connecting
        case step2
    }

    // MARK: Inputs

    let editing: Source?
    @ObservationIgnored let context: ModelContext
    @ObservationIgnored let secrets: any SecretStore
    @ObservationIgnored let makeTransport: @Sendable () -> any HTTPTransport
    @ObservationIgnored let clock: () -> Date
    @ObservationIgnored let zone: TimeZone
    @ObservationIgnored weak var sync: SyncCoordinator?

    // MARK: Step 1 fields

    var name: String
    var server: String
    var username: String
    /// Held only here, for this sheet's lifetime (layouts.md §12.2 `Back`).
    var password = ""

    var phase: Phase = .editing
    /// The step-1 failure shown in the footnote's place.
    var failure: ConnectFailurePresentation?
    /// `Password not saved` (Import's Keychain failure, sheet-only copy).
    var saveFailure: (title: String, body: String)?
    var focus: Field?
    /// Select the focused field's contents (§12.1's failure table).
    var selectFocusedContents = false

    // MARK: Step 2 data

    struct FetchedCalendar {
        var calendar: DiscoveredCalendar
        var objects: [FeedObject]
        var problems: [ImportProblem]
        var fetch: CalendarFetch
    }

    private(set) var discovery: DiscoveryResult?
    private(set) var fetched: [FetchedCalendar] = []
    /// Hrefs checked in step 2.
    var checked: Set<String> = []
    /// Selected calendars discovery no longer finds (edit mode).
    private(set) var missingCalendars: [SourceCalendar] = []
    @ObservationIgnored private var connectTask: Task<Void, Never>?
    @ObservationIgnored private var usedSavedPassword = false

    init(editing: Source? = nil, context: ModelContext, secrets: any SecretStore,
         makeTransport: @escaping @Sendable () -> any HTTPTransport, sync: SyncCoordinator?,
         clock: @escaping () -> Date = { Date() }, zone: TimeZone = .current) {
        self.editing = editing
        self.context = context
        self.secrets = secrets
        self.makeTransport = makeTransport
        self.sync = sync
        self.clock = clock
        self.zone = zone
        name = editing?.displayName ?? "University timetable"
        // Server prefilled; for an existing source, what it stored.
        server = editing.flatMap { ServerAddress(stored: $0.serverURL) }.map { a in
            a.port == 443 && a.path == nil ? a.host : a.normalized.replacingOccurrences(of: "https://", with: "")
        } ?? "cis.technikum-wien.at"
        username = editing?.username ?? ""
        focus = editing == nil ? .username : nil
    }

    var isEditMode: Bool { editing != nil }

    // MARK: Validation (layouts.md §12.1's table)

    var serverAddress: ServerAddress? {
        if case .success(let a) = ServerAddress.parse(server) { return a }
        return nil
    }

    var serverMessage: String? {
        guard case .failure(let problem) = ServerAddress.parse(server) else { return nil }
        switch problem {
        case .empty: return nil
        case .http: return "Kadence only connects over HTTPS."
        case .notAServer: return "Enter the server name, like cis.technikum-wien.at."
        case .containsUser: return "Enter the username in its own field."
        case .webdavShare:
            return "That's the WebDAV share, which only works on the FH network. Enter just the server name: cis.technikum-wien.at."
        }
    }

    var trimmedUsername: String { username.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// `{user} @ {host} is already connected as {name}.` (the source itself
    /// excluded in edit mode).
    var usernameMessage: String? {
        guard let address = serverAddress, !trimmedUsername.isEmpty else { return nil }
        let sources = (try? context.fetch(FetchDescriptor<Source>())) ?? []
        guard let other = sources.first(where: { s in
            s.id != editing?.id && s.isConnected && s.username == trimmedUsername
                && ServerAddress(stored: s.serverURL).map { $0.host == address.host && $0.port == address.port } == true
        }) else { return nil }
        return "\(trimmedUsername) @ \(address.host) is already connected as \(other.displayName)."
    }

    /// Edit mode: an empty password means the saved one — unless the server
    /// or username changed (a different account needs its password).
    var accountChanged: Bool {
        guard let editing else { return true }
        return serverAddress?.normalized != ServerAddress(stored: editing.serverURL)?.normalized
            || trimmedUsername != editing.username
    }

    var canConnect: Bool {
        guard phase == .editing, serverAddress != nil, !trimmedUsername.isEmpty, usernameMessage == nil else { return false }
        if password.isEmpty { return isEditMode && !accountChanged }
        return true
    }

    /// The footnote, with `{host}` live from `Server`.
    var footnote: String {
        if let host = serverAddress?.host {
            return "Your password is kept in the macOS Keychain and sent only to \(host), over HTTPS."
        }
        return "Your password is kept in the macOS Keychain and sent only to the server you enter, over HTTPS."
    }

    var connectingLine: String { "Connecting to \(serverAddress?.host ?? "")…" }

    var title: String { isEditMode ? "Edit \(editing?.displayName ?? name)" : "Connect a timetable" }

    var passwordPlaceholder: String { isEditMode ? "Saved in Keychain" : "" }

    // MARK: Connect

    /// Discovery and the Import-window fetch of every listed calendar, as one
    /// step (layouts.md §12.1). Cancel cancels it and leaves nothing behind.
    func connect() {
        guard canConnect, let address = serverAddress else { return }
        failure = nil
        saveFailure = nil
        let typed = password
        let user = trimmedUsername
        let pass: Password
        if typed.isEmpty, let editing, let account = SourcesSettingsModel.secretAccount(editing),
           let saved = try? secrets.read(account) {
            pass = saved
            usedSavedPassword = true
        } else if typed.isEmpty {
            fail(.passwordMissing)
            return
        } else {
            pass = Password(typed)
            usedSavedPassword = false
        }
        phase = .connecting
        let transport = makeTransport()
        let now = clock()
        let zone = zone
        connectTask = Task { [weak self] in
            let session = CalDAVSession(transport: transport, host: address.host, port: address.port,
                                        username: user, password: pass)
            let outcome = await Self.discoverAndFetch(address: address, session: session, now: now, zone: zone)
            (transport as? URLSessionTransport)?.invalidate()
            guard let self, !Task.isCancelled else { return }
            switch outcome {
            case .success(let (discovery, fetched, stats)):
                self.received(discovery, fetched)
                self.logConnect(stats)
            case .failure(let error):
                if error == .cancelled { return }
                self.fail(error)
            }
        }
    }

    /// Cancel mid-connect: back to editing, nothing changed.
    func cancelConnecting() {
        connectTask?.cancel()
        connectTask = nil
        if phase == .connecting { phase = .editing }
    }

    /// What the connect's own requests cost, for its log line (§20.8.4).
    struct ConnectStats: Sendable {
        var requests = 0
        var milliseconds = 0
    }

    nonisolated private static func discoverAndFetch(address: ServerAddress, session: CalDAVSession, now: Date,
                                                     zone: TimeZone)
        async -> Result<(DiscoveryResult, [FetchedCalendar], ConnectStats), ScheduleSourceError> {
        let started = Date()
        do {
            let discovery = try await CalDAVDiscovery.discover(server: address, session: session)
            let start = Windows.importStart(now: now, zone: zone)
            var fetched: [FetchedCalendar] = []
            for calendar in discovery.calendars {
                guard let url = URL(string: calendar.href, relativeTo: address.baseURL)?.absoluteURL else { continue }
                do {
                    let fetch = try await CalDAVClient.fetch(calendar: url, displayName: calendar.displayName,
                                                             windowStart: start, mode: .report, session: session, zone: zone)
                    fetched.append(FetchedCalendar(calendar: calendar, objects: fetch.objects, problems: fetch.problems,
                                                   fetch: fetch))
                } catch .rediscover {
                    return .failure(.calendarMissing)
                } catch .failed(let error) {
                    return .failure(error)
                }
            }
            let stats = ConnectStats(requests: await session.requestCount,
                                     milliseconds: Int(Date().timeIntervalSince(started) * 1000))
            return .success((discovery, fetched, stats))
        } catch {
            return .failure((error as? ScheduleSourceError) ?? .unreachable)
        }
    }

    private func fail(_ error: ScheduleSourceError) {
        phase = .editing
        let host = serverAddress?.host ?? ""
        let presentation = ConnectFailurePresentation(
            error, facts: StatusFacts(host: host, user: trimmedUsername, name: name))
        failure = presentation
        switch presentation.focus {
        case .password(let all): focus = .password; selectFocusedContents = all
        case .username(let all): focus = .username; selectFocusedContents = all
        case .server(let all): focus = .server; selectFocusedContents = all
        case .connect: focus = .connect; selectFocusedContents = false
        }
    }

    private func received(_ discovery: DiscoveryResult, _ fetched: [FetchedCalendar]) {
        self.discovery = discovery
        self.fetched = fetched
        if let editing {
            // The current selection checked; others listed unchecked;
            // selected ones discovery no longer finds named above the list.
            let selected = Set(editing.calendars.map(\.href))
            checked = Set(fetched.map(\.calendar.href).filter(selected.contains))
            missingCalendars = editing.calendars.filter { c in !fetched.contains { $0.calendar.href == c.href } }
        } else {
            checked = Set(fetched.map(\.calendar.href))
            missingCalendars = []
        }
        phase = .step2
        focus = nil
    }

    /// §20.8.4 (amended 2026-10-10): the connect sheet's fetch is logged as
    /// one line of the sync line's shape — `connect {account} · … · previewed
    /// {n} events` — so the VEVENT, duplicate and merge counts of the very
    /// first read are in the log before anything is imported. The account
    /// string is `{user} @ {host}`; never a password, header or body.
    private func logConnect(_ stats: ConnectStats) {
        let feed = derived
        var diagnostics = diagnostics(for: checkedCalendars, feed: feed)
        diagnostics.requests = stats.requests
        diagnostics.milliseconds = stats.milliseconds
        diagnostics.ctags = (discovery?.calendars ?? []).compactMap(\.ctag)
        SourceLogger.shared.connect(account: accountLine, diagnostics: diagnostics, events: feed.events.count)
    }

    /// The counts of a set of fetched calendars, as the log line gives them.
    private func diagnostics(for calendars: [FetchedCalendar], feed: DerivedFeed) -> SyncDiagnostics {
        var diagnostics = SyncDiagnostics()
        diagnostics.calendarNames = calendars.map(\.calendar.displayName)
        if calendars.contains(where: { $0.fetch.mode == .get }) { diagnostics.mode = .get }
        else if calendars.contains(where: { $0.fetch.mode == .multiget }) { diagnostics.mode = .multiget }
        diagnostics.objects = calendars.reduce(0) { $0 + $1.objects.count }
        diagnostics.vevents = feed.objectCount
        diagnostics.duplicates = feed.duplicateCount
        diagnostics.merged = feed.mergedCount
        let honoured = calendars.compactMap(\.fetch.timeRangeHonoured)
        diagnostics.timeRangeHonoured = honoured.isEmpty ? nil : honoured.allSatisfy { $0 }
        diagnostics.etags = calendars.flatMap(\.fetch.etags)
        return diagnostics
    }

    /// Step 2's `Back`: every field as entered, the password too.
    func back() {
        phase = .editing
        focus = .username
    }

    // MARK: Step 2

    var accountLine: String { "\(trimmedUsername) @ \(serverAddress?.host ?? "")" }

    var step2Title: String { isEditMode ? "Update \(name)" : "Import \(name)" }

    /// One calendar → the confirmed row (not a control); several → a checklist.
    var isSingleCalendar: Bool { fetched.count == 1 }

    var calendarLabel: String { fetched.count == 1 ? "Calendar" : "Calendars" }

    var checkedCalendars: [FetchedCalendar] { fetched.filter { checked.contains($0.calendar.href) } }

    /// The merged feed of the checked calendars, from data already fetched.
    var derived: DerivedFeed {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return FeedDerivation.derive(checkedCalendars.flatMap(\.objects), today: cal.startOfDay(for: clock()), zone: zone)
    }

    var problems: [ImportProblem] { checkedCalendars.flatMap(\.problems) + derived.problems }

    private func date(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = zone
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }

    /// `{n} events, {first} – {last}`; `Choose at least one calendar.` with
    /// none checked; the empty-calendar line.
    var rangeLine: String {
        if checked.isEmpty { return "Choose at least one calendar." }
        let events = derived.events
        guard let first = events.map(\.start).min(), let last = events.map(\.start).max() else {
            return "The calendar has no events yet."
        }
        let a = date(first), b = date(last)
        return "\(SourceStatusCopy.events(events.count)), " + (a == b ? a : "\(a) – \(b)")
    }

    var isEmptyCalendar: Bool { !checked.isEmpty && derived.events.isEmpty }

    var isNoneChecked: Bool { checked.isEmpty }

    /// The sentences under the range line, in order, each only when non-zero.
    var sentences: [(text: String, isPrimary: Bool)] {
        guard !checked.isEmpty else { return [] }
        if isEmptyCalendar { return [("Kadence will add them as they appear.", false)] }
        var out: [(String, Bool)] = []
        let feed = derived
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let today = cal.startOfDay(for: clock())
        if isEditMode {
            out.append(("Events before today are not changed.", false))
        } else {
            let h = feed.events.filter { $0.start < today }.count
            if h > 0 {
                if h == feed.events.count {
                    out.append(("All of them are before today. They're imported once, as history, and never changed afterwards.", false))
                } else if h == 1 {
                    out.append(("1 of them is before today. It's imported once, as history, and never changed afterwards.", false))
                } else {
                    out.append(("\(h) of them are before today. They're imported once, as history, and never changed afterwards.", false))
                }
            }
        }
        let m = feed.mergedCount
        if m == 1 { out.append(("1 co-taught lecture is listed once per lecturer and is shown once.", false)) }
        else if m > 1 { out.append(("\(m) co-taught lectures are listed once per lecturer and are shown once.", false)) }
        let k = problems.count
        if k == 1 { out.append(("1 event couldn't be read and will be skipped.", true)) }
        else if k > 1 { out.append(("\(k) events couldn't be read and will be skipped.", true)) }
        if let d = deselectionCount, d > 0 {
            out.append((d == 1 ? "1 event from calendars you unchecked will be removed, including past weeks."
                               : "\(d) events from calendars you unchecked will be removed, including past weeks.", true))
        }
        return out
    }

    /// `{calendar} is no longer on {host}.` (edit mode).
    var missingLine: String? {
        guard !missingCalendars.isEmpty else { return nil }
        return "\(SourceStatusCopy.calendarList(missingCalendars.map(\.displayName))) is no longer on \(serverAddress?.host ?? "")."
    }

    /// Edit mode: did the user uncheck a calendar that was selected?
    var isDeselecting: Bool {
        guard let editing else { return false }
        return editing.calendars.contains { c in fetched.contains { $0.calendar.href == c.href } && !checked.contains(c.href) }
            || !missingCalendars.isEmpty
    }

    /// How many events the deselection removes (layouts.md §12.3).
    var deselectionCount: Int? {
        guard let editing, isDeselecting else { return nil }
        return SyncPlanner.deselectionCount(existing: SyncApplier.snapshot(of: editing, in: context, zone: zone),
                                            keptEvents: derived.events)
    }

    var canImport: Bool { phase == .step2 && !checked.isEmpty }

    /// What Import / Save hand to the planner: the checked calendars' data.
    func fetchResult() -> ScheduleFetchResult {
        let feed = derived
        let checkedList = checkedCalendars
        var capabilities = SourceCapabilities(fetchMode: .report, timeRangeHonoured: nil, discoveredAt: clock())
        if checkedList.contains(where: { $0.fetch.mode == .get }) { capabilities.fetchMode = .get }
        else if checkedList.contains(where: { $0.fetch.mode == .multiget }) { capabilities.fetchMode = .multiget }
        capabilities.timeRangeHonoured = checkedList.compactMap(\.fetch.timeRangeHonoured).allSatisfy { $0 }
        let diagnostics = diagnostics(for: checkedList, feed: feed)
        return ScheduleFetchResult(
            events: feed.events, problems: problems, objectCount: feed.objectCount, mergedCount: feed.mergedCount,
            calendarsReadInFully: checkedList.map(\.calendar.href), failedCalendars: [], adoptedCalendars: [],
            capabilities: capabilities, diagnostics: diagnostics,
            principalHref: discovery?.principalHref, calendarHomeHref: discovery?.calendarHomeHref)
    }

    // MARK: Import (new) and Save (edit)

    /// Keychain → Source → events, with no further request. A Keychain
    /// failure writes nothing else. Returns the source on success.
    @discardableResult
    func importNow() -> Source? {
        guard canImport, let address = serverAddress else { return nil }
        let account = SecretAccount(host: address.host, port: address.port, username: trimmedUsername)
        let id = UUID().uuidString
        // 1. The Keychain item.
        do {
            try secrets.save(Password(password), for: account, info: .forSource(id: id, displayName: name))
        } catch {
            saveFailure = ("Password not saved",
                           "Kadence couldn't save the password in the Keychain, so nothing was saved. Try again.")
            return nil
        }
        // 2. The Source.
        let used = ((try? context.fetch(FetchDescriptor<Source>())) ?? []).map(\.paletteKey)
        let result = fetchResult()
        let source = Source.connected(
            id: id, displayName: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "University timetable" : name,
            serverURL: address.normalized, username: trimmedUsername, principalHref: discovery?.principalHref,
            calendarHomeHref: discovery?.calendarHomeHref,
            calendars: checkedCalendars.map { SourceCalendar(href: $0.calendar.href, displayName: $0.calendar.displayName) },
            capabilities: result.capabilities, paletteKey: Source.paletteKeyForNewSource(existing: used))
        context.insert(source)
        try? context.save()
        // 3. The events already fetched, in one transaction (the Import).
        do {
            if let sync { try sync.applyFetched(result, to: source, kind: .import) }
            else {
                let plan = SyncPlanner.plan(existing: [], source: SourceSnapshot(feedHash: nil, lastFeedEventCount: 0,
                                                                                  calendars: source.calendars, importedAt: nil),
                                            result: result, kind: .import, now: clock(), zone: zone)
                try SyncApplier.apply(plan, to: source, context: context, now: clock())
            }
        } catch {
            return nil
        }
        // §20.8.4: the Import makes no request and logs one line.
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let today = cal.startOfDay(for: clock())
        SourceLogger.shared.imported(account: accountLine, events: result.events.count,
                                     beforeToday: result.events.filter { $0.start < today }.count)
        password = ""
        return source
    }

    /// Edit mode's `Save` (layouts.md §12.3).
    @discardableResult
    func save() -> Bool {
        guard canImport, let editing, let address = serverAddress else { return false }
        let newAccount = SecretAccount(host: address.host, port: address.port, username: trimmedUsername)
        let oldAccount = SourcesSettingsModel.secretAccount(editing)
        if !password.isEmpty || accountChanged {
            do {
                try secrets.replace(oldAccount ?? newAccount, with: newAccount, password: Password(password),
                                    info: .forSource(id: editing.id, displayName: name))
            } catch {
                saveFailure = ("Password not saved",
                               "Kadence couldn't save the password in the Keychain, so nothing was saved. Try again.")
                return false
            }
        } else if name != editing.displayName, let oldAccount {
            try? secrets.updateInfo(.forSource(id: editing.id, displayName: name), for: oldAccount)
        }
        let deselected = isDeselecting
        editing.displayName = name
        editing.serverURL = address.normalized
        editing.username = trimmedUsername
        editing.principalHref = discovery?.principalHref ?? editing.principalHref
        editing.calendarHomeHref = discovery?.calendarHomeHref ?? editing.calendarHomeHref
        editing.calendars = checkedCalendars.map { SourceCalendar(href: $0.calendar.href, displayName: $0.calendar.displayName) }
        var capabilities = editing.capabilities
        capabilities.fetchMode = .report
        capabilities.discoveredAt = clock()
        editing.capabilities = capabilities
        editing.isAutoSyncPaused = false
        try? context.save()
        var result = fetchResult()
        result.capabilities = capabilities
        do {
            if let sync { try sync.applyFetched(result, to: editing, kind: .editSave(deselected: deselected)) }
            else {
                let plan = SyncPlanner.plan(
                    existing: SyncApplier.snapshot(of: editing, in: context, zone: zone),
                    source: SourceSnapshot(feedHash: editing.feedHash, lastFeedEventCount: editing.lastFeedEventCount,
                                           calendars: editing.calendars, importedAt: editing.importedAt),
                    result: result, kind: .editSave(deselected: deselected), now: clock(), zone: zone)
                try SyncApplier.apply(plan, to: editing, context: context, now: clock())
            }
        } catch {
            return false
        }
        password = ""
        return true
    }
}
