//
//  SourceStatusPresentation.swift
//  Kadence
//
//  PHASE3-PLAN.md task 11 — components.md §19.1 (states and their exact
//  copy), §19.2 (kind → slot), §19.3 (status and last-change lines), §19.4
//  (the stale line), §19.5 (time forms); layouts.md §12.1 (step-1 failure
//  bodies and focus). Pure: values in, strings out. Every surface that shows
//  a source's state takes its words from here (§19.1: "from this table and
//  nowhere else").
//

import Foundation

// MARK: - Facts

/// What a state's copy is substituted with (§19.1's placeholders).
nonisolated struct StatusFacts: Sendable, Equatable {
    /// `{host}`
    var host: String
    /// `{user}`
    var user: String
    /// `{name}`
    var name: String
    /// The affected calendars' display names (`{calendar}`).
    var calendars: [String] = []
    /// `{otherHost}`, nil for a redirect to `http:`.
    var otherHost: String?
    /// `{code}`
    var code: Int?
    /// `{k}`, `{n}` — partialImport's skipped and read counts; emptyFeed's
    /// `{n}` (events at the last sync).
    var k: Int = 0
    var n: Int = 0

    /// `{account}` = `{user} @ {host}`.
    var account: String { "\(user) @ \(host)" }
}

nonisolated enum PrimaryAction: String, Sendable, Equatable {
    case syncNow = "Sync Now"
    case updatePassword = "Update Password…"
    case editAccount = "Edit Account…"
    case chooseCalendar = "Choose Calendar…"
    case showDetails = "Show Details"
    /// components.md §34.3, §33.5 (slice 3): a feed source's remedy.
    case replaceURL = "Replace URL…"
}

/// §19.2's status slot.
nonisolated enum StatusGlyph: Sendable, Equatable {
    case none
    case spinner
    /// `exclamationmark.arrow.triangle.2.circlepath` in `text.secondary`.
    case transient
    /// The same symbol in `semantic.alert`.
    case actionable

    static let symbol = "exclamationmark.arrow.triangle.2.circlepath"
}

// MARK: - The copy

nonisolated enum SourceStatusCopy {

    // §19.1 rules: digits, and `events` plural except `1 event`.
    static func events(_ n: Int) -> String { n == 1 ? "1 event" : "\(n) events" }

    /// `{calendar}`: one name; two → `A and B`; three or more → `A and 2 other calendars`.
    static func calendarList(_ names: [String]) -> String {
        switch names.count {
        case 0: return "the calendar"
        case 1: return names[0]
        case 2: return "\(names[0]) and \(names[1])"
        default: return "\(names[0]) and \(names.count - 1) other calendars"
        }
    }

    static func title(_ state: SourceState, host: String) -> String {
        switch state {
        case .upToDate: "Up to date"
        case .syncing: "Syncing…"
        case .neverSynced: "Waiting for first sync"
        case .offline: "Offline"
        case .unauthorized: "Sign-in failed"
        case .forbidden: "Access refused"
        case .noCalDAV: "No calendar server found"
        case .noCalendars: "No calendars found"
        case .calendarMissing: "Calendar not found"
        case .fetchFailed: "Couldn't read the calendar"
        case .notACalendar: "Not a calendar"
        case .emptyFeed: "The calendar is empty"
        case .partialImport: "Imported with problems"
        case .certificate: "Secure connection failed"
        case .passwordMissing: "Password not found"
        case .redirected: "Redirected to another server"
        case .unreachable: "Can't reach \(host)"
        case .serverError: "Server error"
        // §34.3: feed sources only.
        case .feedNotFound: "Calendar not found"
        case .urlMissing: "Calendar URL not found"
        }
    }

    /// The body, with `{next}` and `{last}` already resolved by the caller.
    static func body(_ state: SourceState, _ f: StatusFacts, next: String, last: String) -> String? {
        let calendar = calendarList(f.calendars)
        switch state {
        case .upToDate, .syncing: return nil
        case .neverSynced: return "Kadence will sync as soon as \(f.host) can be reached."
        case .offline:
            return "Kadence will sync when this Mac is back online. Events from the last sync (\(last)) are still shown."
        case .unauthorized:
            return "\(f.host) didn't accept the password for \(f.user). Automatic sync is paused so the account isn't locked."
        case .forbidden:
            return "\(f.host) refused access for \(f.user). Automatic sync is paused so the account isn't locked."
        case .noCalDAV:
            return "\(f.host) doesn't offer CalDAV calendars. Check the server name. Events from the last sync are kept."
        case .noCalendars:
            return "\(f.account) has no calendars with events. Events from the last sync are kept."
        case .calendarMissing:
            return "\(calendar) is no longer on \(f.host). Events from the last sync are kept until you choose a calendar or remove the source."
        case .fetchFailed:
            return "\(f.host) refused every way Kadence asks for events from \(calendar). Nothing was changed."
        case .notACalendar:
            return "\(f.host) sent a web page instead of calendar data — often a sign-in or maintenance page. Events from the last sync are kept."
        case .emptyFeed:
            return "\(f.host) sent no events for \(calendar). It had \(events(f.n)) at the last sync, so they are kept. If the timetable really is empty, remove the source in Settings."
        case .partialImport:
            return "\(f.k) of \(events(f.n)) couldn't be read and were skipped. Nothing was removed."
        case .certificate:
            return "The certificate for \(f.host) couldn't be verified, so Kadence sent nothing to it. Nothing was changed."
        case .passwordMissing:
            return "Kadence couldn't read the password for \(f.account) from the Keychain. Enter it again."
        case .redirected:
            if let other = f.otherHost {
                return "\(f.host) sent Kadence to \(other). Kadence didn't follow it, so nothing — and no password — was sent there."
            }
            return "\(f.host) sent Kadence to an address without HTTPS. Kadence didn't follow it."
        case .unreachable:
            return "Kadence will try again at \(next). Events from the last sync (\(last)) are still shown."
        case .serverError:
            return "\(f.host) answered with an error (\(f.code.map(String.init) ?? "?")). Kadence will try again at \(next)."
        // §34.3: feed sources only.
        case .feedNotFound:
            return "\(f.host) has no calendar at the saved URL. Items from the last sync are kept."
        case .urlMissing:
            return "Kadence couldn't read the calendar URL for \(f.name) from the Keychain. Paste it again."
        }
    }

    static func primaryAction(_ state: SourceState) -> PrimaryAction? {
        switch state {
        case .upToDate, .neverSynced, .noCalendars, .fetchFailed, .notACalendar, .emptyFeed, .certificate,
             .unreachable, .serverError:
            .syncNow
        case .syncing, .offline: nil
        case .unauthorized, .passwordMissing: .updatePassword
        case .forbidden, .noCalDAV, .redirected: .editAccount
        case .calendarMissing: .chooseCalendar
        case .partialImport: .showDetails
        case .feedNotFound, .urlMissing: .replaceURL
        }
    }

    /// §19.2: only the kind sets the colour; `offline` shows nothing.
    static func glyph(_ state: SourceState, isSyncingVisibly: Bool) -> StatusGlyph {
        if isSyncingVisibly || state == .syncing { return isSyncingVisibly ? .spinner : .none }
        if state == .offline { return .none }
        switch state.kind {
        case .ok: return .none
        case .transient: return .transient
        case .actionable: return .actionable
        }
    }

    // MARK: §19.5 — time

    private static func formatter(_ format: String, _ zone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = zone
        f.dateFormat = format
        return f
    }

    /// The in-sentence form: `just now`, `today 14:02`, `yesterday 14:02`,
    /// `Mon 14:02`, `6 Oct 14:02`, `6 Oct 2025 14:02`.
    static func when(_ date: Date, now: Date, zone: TimeZone = .current) -> String {
        whenForm(date, now: now, zone: zone, inSentence: true)
    }

    /// After `Synced`: the same, but today is just `14:02`.
    static func synced(_ date: Date, now: Date, zone: TimeZone = .current) -> String {
        whenForm(date, now: now, zone: zone, inSentence: false)
    }

    private static func whenForm(_ date: Date, now: Date, zone: TimeZone, inSentence: Bool) -> String {
        if now.timeIntervalSince(date) < 60 && now >= date { return "just now" }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let time = formatter("HH:mm", zone).string(from: date)
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: date), to: cal.startOfDay(for: now)).day ?? 0
        switch days {
        case 0: return inSentence ? "today \(time)" : time
        case 1: return "yesterday \(time)"
        case 2...6: return "\(formatter("EEE", zone).string(from: date)) \(time)"
        default:
            let sameYear = cal.component(.year, from: date) == cal.component(.year, from: now)
            return formatter(sameYear ? "d MMM" : "d MMM yyyy", zone).string(from: date) + " \(time)"
        }
    }

    /// `{next}`: `HH:mm`, or `tomorrow HH:mm`.
    static func next(_ date: Date, now: Date, zone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let time = formatter("HH:mm", zone).string(from: date)
        return cal.isDate(date, inSameDayAs: now) ? time : "tomorrow \(time)"
    }

    // MARK: §19.3 lines

    /// `Last synced {last} · {count} events`; `upToDate` reads `Synced {last}
    /// · {count} events`. `lastSuccess` is `Source.lastSyncedAt` — the last
    /// success, or the Import (§19.3, amended 2026-10-10) — so `Never synced`
    /// is left only for a source that was never imported.
    static func statusLine(state: SourceState, lastSuccess: Date?, count: Int, now: Date,
                           zone: TimeZone = .current) -> String {
        guard let lastSuccess else { return "Never synced" }
        if state == .upToDate { return "Synced \(synced(lastSuccess, now: now, zone: zone)) · \(events(count))" }
        return "Last synced \(when(lastSuccess, now: now, zone: zone)) · \(events(count))"
    }

    /// `Last change {when}: {a} added · {u} updated · {r} removed`, zero
    /// terms omitted; nil when no sync has written since the Import.
    static func lastChangeLine(at: Date?, added: Int, updated: Int, removed: Int, now: Date,
                               zone: TimeZone = .current) -> String? {
        guard let at else { return nil }
        let terms = [(added, "added"), (updated, "updated"), (removed, "removed")]
            .filter { $0.0 > 0 }.map { "\($0.0) \($0.1)" }
        guard !terms.isEmpty else { return nil }
        return "Last change \(when(at, now: now, zone: zone)): " + terms.joined(separator: " · ")
    }

    // MARK: §19.4 — the popover's stale line

    /// Shown when the source is actionable, or its last success is older
    /// than `max(24 h, 2 × interval)`; never for `offline` or `transient`
    /// alone inside that time.
    static func staleLine(name: String, state: SourceState, lastSuccess: Date?, interval: TimeInterval,
                          now: Date, zone: TimeZone = .current) -> String? {
        let limit = max(24 * 3600, 2 * interval)
        let old = lastSuccess.map { now.timeIntervalSince($0) > limit } ?? true
        guard state.kind == .actionable || old else { return nil }
        guard let lastSuccess else { return "\(name) has not synced yet" }
        return "\(name) not synced since \(when(lastSuccess, now: now, zone: zone))"
    }

    /// Two at most, then `+N more sources not synced`.
    static func staleLines(_ lines: [String]) -> [String] {
        guard lines.count > 2 else { return lines }
        return Array(lines.prefix(2)) + ["+\(lines.count - 2) more sources not synced"]
    }

    // MARK: §19.2 — hover help and VoiceOver

    static func hoverHelp(name: String, state: SourceState, host: String = "", lastSuccess: Date?, now: Date,
                          zone: TimeZone = .current) -> String {
        switch state {
        case .upToDate:
            return "\(name) — " + (lastSuccess.map { "Synced \(synced($0, now: now, zone: zone))" } ?? "Never synced")
        case .offline:
            return "\(name) — Offline" + (lastSuccess.map { ", last synced \(synced($0, now: now, zone: zone))" } ?? "")
        default:
            return "\(name) — \(title(state, host: host))"
        }
    }

    static func accessibilityValue(name: String, state: SourceState, host: String) -> String {
        "\(name), \(title(state, host: host))"
    }
}

// MARK: - The presentation of a source

/// Everything a surface draws for one source (§19.1–§19.4). Built from a
/// `Source` on the main actor; pure apart from that read.
nonisolated struct SourceStatusPresentation: Sendable, Equatable {
    var title: String
    var body: String?
    var statusLine: String
    var lastChangeLine: String?
    var primaryAction: PrimaryAction?
    var kind: SourceState.Kind
    var hoverHelp: String
    var staleLine: String?
    var accessibilityValue: String

    @MainActor
    init(source: Source, now: Date, isSyncing: Bool = false, zone: TimeZone = .current) {
        let state: SourceState = isSyncing ? .syncing : source.state
        let host = source.host ?? ""
        let facts = Self.facts(of: source)
        let next = SourceStatusCopy.next(
            (source.lastAttemptAt ?? now).addingTimeInterval(TimeInterval(source.pollInterval)), now: now, zone: zone)
        let last = source.lastSyncedAt.map { SourceStatusCopy.when($0, now: now, zone: zone) } ?? "never"
        // components.md §34.3 (slice 3): a feed source has its own copy.
        let feed = source.connection == .icsFeed
        let until = source.emptySince.map {
            FeedStatusCopy.until($0.addingTimeInterval(FeedSyncPlanner.emptyFeedProof), now: now, zone: zone)
        } ?? ""
        title = feed ? FeedStatusCopy.title(state, host: host) : SourceStatusCopy.title(state, host: host)
        if let stored = source.stateDetail, !isSyncing {
            body = stored.replacingOccurrences(of: "{next}", with: next).replacingOccurrences(of: "{last}", with: last)
                .replacingOccurrences(of: "{until}", with: until)
        } else if feed {
            body = FeedStatusCopy.body(state, facts, next: next, last: last, until: until)
        } else {
            body = SourceStatusCopy.body(state, facts, next: next, last: last)
        }
        statusLine = feed
            ? FeedStatusCopy.statusLine(state: state, lastSuccess: source.lastSyncedAt, count: source.lastEventCount,
                                        now: now, zone: zone)
            : SourceStatusCopy.statusLine(state: state, lastSuccess: source.lastSyncedAt,
                                          count: source.lastEventCount, now: now, zone: zone)
        let changedSinceImport = source.lastChangeAt.map { at in source.importedAt.map { at >= $0 } ?? true } ?? false
        lastChangeLine = changedSinceImport
            ? SourceStatusCopy.lastChangeLine(at: source.lastChangeAt, added: source.lastChangeAdded,
                                              updated: source.lastChangeUpdated, removed: source.lastChangeRemoved,
                                              now: now, zone: zone)
            : nil
        primaryAction = feed ? FeedStatusCopy.primaryAction(state) : SourceStatusCopy.primaryAction(state)
        kind = state.kind
        hoverHelp = SourceStatusCopy.hoverHelp(name: source.displayName, state: state, host: host,
                                               lastSuccess: source.lastSyncedAt,
                                               now: now, zone: zone)
        if feed, ![.upToDate, .offline].contains(state) { hoverHelp = "\(source.displayName) — \(title)" }
        staleLine = SourceStatusCopy.staleLine(name: source.displayName, state: source.state,
                                               lastSuccess: source.lastSyncedAt,
                                               interval: TimeInterval(source.pollInterval), now: now, zone: zone)
        accessibilityValue = feed ? "\(source.displayName), \(title)"
            : SourceStatusCopy.accessibilityValue(name: source.displayName, state: state, host: host)
    }

    @MainActor
    static func facts(of source: Source) -> StatusFacts {
        StatusFacts(host: source.host ?? "", user: source.username ?? "", name: source.displayName,
                    calendars: source.calendars.map(\.displayName), k: source.problems.count,
                    n: source.lastFeedEventCount)
    }

    /// The `stateDetail` a write stores: the body with every fact substituted
    /// and `{next}` / `{last}` left for the display (they move with time).
    /// Never contains a password: its inputs are hosts, names and counts.
    static func storedDetail(_ state: SourceState, _ facts: StatusFacts) -> String? {
        SourceStatusCopy.body(state, facts, next: "{next}", last: "{last}")
    }
}

// MARK: - The connect sheet's step-1 failures (layouts.md §12.1)

nonisolated struct ConnectFailurePresentation: Sendable, Equatable {
    enum Focus: Sendable, Equatable {
        case password(selectAll: Bool)
        case username(selectAll: Bool)
        case server(selectAll: Bool)
        /// Stays on `Connect`.
        case connect
    }

    var title: String
    var body: String
    var focus: Focus

    init(_ error: ScheduleSourceError, facts f: StatusFacts) {
        let state = error.state
        title = SourceStatusCopy.title(state, host: f.host)
        switch error {
        case .unauthorized:
            body = "\(f.host) didn't accept the username or password."; focus = .password(selectAll: true)
        case .forbidden:
            body = "\(f.host) refused access for \(f.user)."; focus = .username(selectAll: true)
        case .noCalDAV:
            body = "\(f.host) doesn't offer CalDAV calendars. Check the server name."; focus = .server(selectAll: true)
        case .noCalendars:
            body = "\(f.account) has no calendars with events."; focus = .username(selectAll: false)
        case .redirected(let other):
            var facts = f
            facts.otherHost = other
            body = SourceStatusCopy.body(.redirected, facts, next: "", last: "") ?? ""
            focus = .server(selectAll: false)
        case .notACalendar:
            body = "\(f.host) sent a web page instead of calendar data. Try again later."; focus = .connect
        case .fetchFailed:
            body = "\(f.host) refused every way Kadence asks for events. Nothing was saved."; focus = .connect
        case .certificate:
            body = "The certificate for \(f.host) couldn't be verified, so Kadence sent nothing to it."; focus = .connect
        case .unreachable, .cancelled:
            body = "Check the server name and your connection, then try again."; focus = .connect
        case .serverError(let code):
            body = "\(f.host) answered with an error (\(code)). Try again later."; focus = .connect
        case .offline:
            body = "This Mac is offline. Connect when it's back online."; focus = .connect
        case .passwordMissing:
            body = SourceStatusCopy.body(.passwordMissing, f, next: "", last: "") ?? ""; focus = .password(selectAll: false)
        case .calendarMissing:
            body = SourceStatusCopy.body(.calendarMissing, f, next: "", last: "") ?? ""; focus = .connect
        // Feed sources only (the Moodle sheet has its own failures,
        // layouts.md §16.1); the state's body.
        case .feedNotFound:
            body = SourceStatusCopy.body(.feedNotFound, f, next: "", last: "") ?? ""; focus = .connect
        case .urlMissing:
            body = SourceStatusCopy.body(.urlMissing, f, next: "", last: "") ?? ""; focus = .connect
        }
    }
}
