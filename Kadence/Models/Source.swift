//
//  Source.swift
//  Kadence
//
//  components.md §21.1 (rewritten 2026-10-08, CalDAV amendment; DECISIONS
//  2026-10-08 "Sources become records"). A calendar source as a persisted
//  record. Phase 1–2 had only the static `MockData.sources` list.
//
//  The password is never a field here, and no field can hold it (§21.4): it
//  lives in one Keychain internet-password item (`SecretStore`). Server,
//  username, hrefs and calendar names are not secret and are stored.
//
//  Swift note (from Java/C#): `@Model` is SwiftData's macro that turns a plain
//  class into a persisted entity — think JPA's `@Entity` with the mapping
//  generated at compile time. Every stored property needs a default so an
//  existing store can gain the column without a migration step.
//
//  Swift note: this target makes everything `@MainActor` by default
//  (SWIFT_DEFAULT_ACTOR_ISOLATION). The small value types below are marked
//  `nonisolated` so the CalDAV client and sync planner can use them — and
//  their `Codable` conformances — off the main actor.
//

import Foundation
import SwiftData

/// §21.1 `connection`: how a source is reached. A raw string on the model so a
/// second transport (G-065) can be added without a migration.
nonisolated enum SourceConnection: String, Codable, CaseIterable, Sendable {
    case local
    case caldav
}

/// §20.8.2: which step of the fallback chain last worked. Remembered so a
/// server that refuses `REPORT` isn't asked again every poll.
nonisolated enum FetchMode: String, Codable, CaseIterable, Sendable {
    case report
    case multiget
    case get
}

/// §20.7.1 / §21.3 `importKind`: decides the glyph only (§2.1).
nonisolated enum ImportKind: String, Codable, CaseIterable, Sendable {
    case lecture
    case exam
}

/// components.md §19.1 — the 18 states a connected source can be in. Raw
/// values are the spec's names exactly; they are stored in `Source.state`.
nonisolated enum SourceState: String, Codable, CaseIterable, Sendable {
    case upToDate
    case syncing
    case neverSynced
    case offline
    case unauthorized
    case forbidden
    case noCalDAV
    case noCalendars
    case calendarMissing
    case fetchFailed
    case notACalendar
    case emptyFeed
    case partialImport
    case certificate
    case passwordMissing
    case redirected
    case unreachable
    case serverError

    /// §19.1's "Kind" column. Only the kind sets the colour (§19.2).
    enum Kind: String, Sendable { case ok, actionable, transient }

    var kind: Kind {
        switch self {
        case .upToDate, .syncing, .neverSynced, .offline: .ok
        case .unreachable, .serverError: .transient
        default: .actionable
        }
    }

    /// interactions.md §13.3: only a refused password pauses automatic sync.
    var pausesAutomaticSync: Bool { self == .unauthorized || self == .forbidden }
}

/// §21.1 `calendars`: one selected calendar. `href` is an absolute path on the
/// source's host. Not identity for events (§20.2) — only where to fetch.
nonisolated struct SourceCalendar: Codable, Equatable, Hashable, Sendable {
    var href: String
    var displayName: String
}

/// §21.1 `capabilities`: what discovery and fetching learned about the server.
nonisolated struct SourceCapabilities: Codable, Equatable, Sendable {
    var fetchMode: FetchMode = .report
    /// nil until the first `REPORT` (§20.8.2).
    var timeRangeHonoured: Bool?
    var discoveredAt: Date = .distantPast
}

/// §21.1 `problems`: one line of `Show Details` — a sentence and an optional
/// technical line (§19.1 rules). Never contains a password, header or body.
nonisolated struct ImportProblem: Codable, Equatable, Hashable, Sendable {
    /// The line in the iCalendar text, when the problem is about one.
    var line: Int?
    var sentence: String
    var technical: String?

    init(line: Int? = nil, sentence: String, technical: String? = nil) {
        self.line = line
        self.sentence = sentence
        self.technical = technical
    }
}

@Model
final class Source {
    /// A UUID string for a new source; mock sources keep their slugs
    /// (`timetable`) because `Event.sourceID` is already a `String` (§21.1).
    var id: String = UUID().uuidString

    private var kindRaw: String = CalendarSourceKind.universityTimetable.rawValue
    var kind: CalendarSourceKind {
        get { CalendarSourceKind(rawValue: kindRaw) ?? .unknown }
        set { kindRaw = newValue.rawValue }
    }

    private var connectionRaw: String = SourceConnection.local.rawValue
    var connection: SourceConnection {
        get { SourceConnection(rawValue: connectionRaw) ?? .local }
        set { connectionRaw = newValue.rawValue }
    }

    var displayName: String = "University timetable"

    private var paletteKeyRaw: String = SourceKey.graphite.rawValue
    var paletteKey: SourceKey {
        get { SourceKey(rawValue: paletteKeyRaw) ?? .graphite }
        set { paletteKeyRaw = newValue.rawValue }
    }

    var symbolOverride: String?
    var isVisible: Bool = true

    /// What the user typed, normalised: `https://` + host (+ port, + path).
    var serverURL: String?
    /// Not secret: shown as `{user} @ {host}` and the Keychain item's account.
    var username: String?
    var principalHref: String?
    var calendarHomeHref: String?

    /// Swift note: SwiftData stores a `Codable` value type as an encoded blob.
    /// These three are the spec's "Codable JSON" fields; each is kept behind a
    /// `Data` column with a computed accessor, so the column type never
    /// depends on how SwiftData chooses to flatten a nested struct.
    private var calendarsData: Data = Data("[]".utf8)
    var calendars: [SourceCalendar] {
        get { (try? JSONDecoder().decode([SourceCalendar].self, from: calendarsData)) ?? [] }
        set { calendarsData = (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8) }
    }

    private var capabilitiesData: Data = Data()
    var capabilities: SourceCapabilities {
        get { (try? JSONDecoder().decode(SourceCapabilities.self, from: capabilitiesData)) ?? SourceCapabilities() }
        set { capabilitiesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var pollInterval: Int = 1800
    var isAutoSyncPaused: Bool = false
    var importedAt: Date?
    var lastAttemptAt: Date?
    var lastSuccessAt: Date?
    var feedHash: String?
    var lastFeedEventCount: Int = 0

    private var stateRaw: String = SourceState.neverSynced.rawValue
    var state: SourceState {
        get { SourceState(rawValue: stateRaw) ?? .neverSynced }
        set { stateRaw = newValue.rawValue }
    }

    var stateDetail: String?

    private var problemsData: Data = Data("[]".utf8)
    var problems: [ImportProblem] {
        get { (try? JSONDecoder().decode([ImportProblem].self, from: problemsData)) ?? [] }
        set { problemsData = (try? JSONEncoder().encode(newValue)) ?? Data("[]".utf8) }
    }

    var lastEventCount: Int = 0
    var lastChangeAt: Date?
    var lastChangeAdded: Int = 0
    var lastChangeUpdated: Int = 0
    var lastChangeRemoved: Int = 0

    init(
        id: String = UUID().uuidString,
        kind: CalendarSourceKind = .universityTimetable,
        connection: SourceConnection = .local,
        displayName: String = "University timetable",
        paletteKey: SourceKey = .graphite,
        symbolOverride: String? = nil,
        isVisible: Bool = true
    ) {
        self.id = id
        self.kindRaw = kind.rawValue
        self.connectionRaw = connection.rawValue
        self.displayName = displayName
        self.paletteKeyRaw = paletteKey.rawValue
        self.symbolOverride = symbolOverride
        self.isVisible = isVisible
    }
}

extension Source {
    @MainActor var symbol: String { symbolOverride ?? kind.symbol }

    /// `{host}` in §19 — the host of `serverURL`.
    var host: String? {
        guard let serverURL, let url = URL(string: serverURL) else { return nil }
        return url.host()
    }

    /// `{user} @ {host}` (§19.1 `{account}`, layouts.md §11). Computed, never
    /// stored (§21.1).
    var accountDisplay: String? {
        guard let username, let host else { return nil }
        return "\(username) @ \(host)"
    }

    var isConnected: Bool { connection != .local }

    /// The sidebar's legacy value type, so existing views keep one shape.
    @MainActor var calendarSource: CalendarSource {
        CalendarSource(id: id, name: displayName, key: paletteKey, kind: kind,
                       symbolOverride: symbolOverride)
    }

    /// §21.1 `paletteKey` at creation: the first slot in
    /// `color.sourcePalette.order` no other `Source` uses, or `graphite`
    /// when all are used (the rule's own fallback).
    static func firstUnusedPaletteKey(existing: [SourceKey]) -> SourceKey {
        let used = Set(existing)
        return SourceKey.allCases.first { !used.contains($0) } ?? .graphite
    }
}

extension Source {
    /// The record the connect sheet's `Import` writes (layouts.md §12.2 step
    /// 2): a `caldav` source with what discovery learned. Takes no password
    /// parameter on purpose — the password goes only to the `SecretStore`
    /// (§21.4), so this initialiser cannot store it even by mistake.
    static func connected(
        id: String = UUID().uuidString,
        displayName: String,
        serverURL: String,
        username: String,
        principalHref: String?,
        calendarHomeHref: String?,
        calendars: [SourceCalendar],
        capabilities: SourceCapabilities,
        paletteKey: SourceKey
    ) -> Source {
        let source = Source(id: id, kind: .universityTimetable, connection: .caldav,
                            displayName: displayName, paletteKey: paletteKey)
        source.serverURL = serverURL
        source.username = username
        source.principalHref = principalHref
        source.calendarHomeHref = calendarHomeHref
        source.calendars = calendars
        source.capabilities = capabilities
        return source
    }
}
