//
//  MoodleFeedURL.swift
//  Kadence
//
//  Phase 3 slice 3 (PHASE3-SLICE3-PLAN.md task 2) — components.md §33.1,
//  §33.2, §33.4. The Moodle calendar export URL: what the user pastes, how it
//  is validated before anything is sent, and the redacted type that holds it.
//
//  **The URL is the secret** (its query carries `userid` and `authtoken`). It
//  exists in full in three places only: the Keychain item, the `SecureField`
//  while the user pastes, and the one `URLRequest` of a fetch (§33.4). This
//  type prints itself as `{host}/…` in every way Swift turns a value into
//  text, so interpolating it into a log, an error or `dump` cannot leak it.
//

import Foundation

/// A validated, normalised Moodle calendar export URL.
///
/// Swift note: as `Password` (SecretStore.swift), `description`,
/// `debugDescription` and `customMirror` are all overridden, so
/// `"\(url)"`, `String(describing:)`, `String(reflecting:)` and `dump` all
/// give the display form. There is deliberately no `Codable` conformance:
/// nothing persists this value except the Keychain item, as bytes.
nonisolated struct MoodleFeedURL: Sendable, Equatable, CustomStringConvertible,
                                  CustomDebugStringConvertible, CustomReflectable {
    /// §33.2 `preset_what`: what the export includes.
    enum Scope: String, Sendable, Equatable {
        case all
        case courses
    }

    /// The normalised URL: scheme `https`, host lower-cased, everything else
    /// as pasted (§33.2).
    private let raw: String
    /// Lower-cased. Shown, so a typo is visible (§33.2).
    let host: String
    /// nil for the scheme's default.
    let port: Int?
    /// Moodle's `userid` — the account. Not shown anywhere (§33.4: "not
    /// `userid`"); used only for V9 / V10's same-account check.
    let userID: String
    let scope: Scope

    /// §33.4's display form: `{host}/…`, with U+2026.
    var displayForm: String { "\(host)/…" }

    /// §33.2's parsed line, shown under the field at V11.
    var parsedLine: String {
        switch scope {
        case .all: "\(displayForm) · All events, recent and upcoming"
        case .courses: "\(displayForm) · Course events, recent and upcoming"
        }
    }

    var description: String { displayForm }
    var debugDescription: String { displayForm }
    /// No children: `dump` prints the summary line (the display form) only.
    var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }

    /// **The one way to the raw URL for a request** (§33.4 obligation 1).
    /// Used only by the feed transport; a source scan asserts it.
    func withRequestURLString<T>(_ body: (String) throws -> T) rethrows -> T { try body(raw) }

    /// The Keychain item's `kSecValueData`: the normalised URL as UTF-8 and
    /// nothing else (§33.3). Used only by `KeychainSecretStore`.
    var keychainValue: Data { Data(raw.utf8) }

    /// The same account: §33.2 V9 / V10 compare host and `userid`.
    func isSameAccount(as other: MoodleFeedURL) -> Bool { host == other.host && userID == other.userID }

    private init(raw: String, host: String, port: Int?, userID: String, scope: Scope) {
        self.raw = raw
        self.host = host
        self.port = port
        self.userID = userID
        self.scope = scope
    }

    /// Reads back a Keychain item's value. nil if it is not a valid URL any
    /// more (the sync then reads as `urlMissing`, §34.8 step 1).
    init?(keychainValue data: Data) {
        guard let text = String(data: data, encoding: .utf8),
              case .valid(let url) = Self.parse(text) else { return nil }
        self = url
    }

    // MARK: - §33.2 validation

    /// One other Moodle source, for V9: its display name and its URL as read
    /// from its Keychain item. A source whose item cannot be read is left out
    /// by the caller (§33.2: "that source is skipped for the check").
    struct Connected: Sendable {
        var name: String
        var url: MoodleFeedURL
    }

    /// The result of validating the field's text.
    enum Validation: Sendable, Equatable {
        /// V1: nothing pasted. No message; `Connect` disabled.
        case empty
        /// V2–V10: the message under the field; `Connect` disabled.
        case message(String)
        /// V11: the parsed line under the field; `Connect` enabled.
        case valid(MoodleFeedURL)

        var canConnect: Bool { if case .valid = self { true } else { false } }

        /// What sits under the field: the message, or the parsed line.
        var line: String? {
            switch self {
            case .empty: nil
            case .message(let text): text
            case .valid(let url): url.parsedLine
            }
        }
    }

    /// §33.2's messages, exactly.
    enum Message {
        static let notAURL = "Paste the calendar URL from Moodle. It starts with https://."
        static let http = "Kadence only connects over HTTPS."
        static let wrongPath = "That isn't the calendar URL. In Moodle, choose Get calendar URL and copy the address it shows."
        static let incomplete = "The URL is missing part of its address. Copy the whole URL from Moodle again."
        static let fixedPeriod = "This URL exports a fixed period. In Moodle, choose Recent and upcoming, then Get calendar URL."
        static let someEvents = "This URL exports only some of your events. In Moodle, choose All events, then Get calendar URL."
        static func alreadyConnected(_ name: String) -> String { "This Moodle account is already connected as \(name)." }
        static let differentAccount = "This URL is for a different Moodle account. To add another account, connect it as a new source."
    }

    static let exportPath = "/calendar/export_execute.php"

    /// §33.2, rows V1–V11 in order; the first that applies decides.
    /// - Parameters:
    ///   - others: the other Moodle sources (V9). In Replace, the source
    ///     being replaced is not among them.
    ///   - replacing: Replace mode's saved URL (V10), nil when connecting.
    static func validate(_ input: String, others: [Connected] = [], replacing: MoodleFeedURL? = nil) -> Validation {
        switch parse(input) {
        case .empty: return .empty
        case .message(let text): return .message(text)
        case .valid(let url):
            if let other = others.first(where: { $0.url.isSameAccount(as: url) }) {
                return .message(Message.alreadyConnected(other.name))
            }
            if let saved = replacing, !saved.isSameAccount(as: url) { return .message(Message.differentAccount) }
            return .valid(url)
        }
    }

    /// V1–V8 and the normalisation; V9 and V10 need the Keychain and are
    /// `validate`'s.
    private static func parse(_ input: String) -> Validation {
        // Leading and trailing whitespace is trimmed silently.
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty { return .empty }

        guard let schemeEnd = text.range(of: "://"),
              let parts = URLComponents(string: text),
              let scheme = parts.scheme?.lowercased(),
              let host = parts.host, !host.isEmpty,
              ["https", "http", "webcal"].contains(scheme)
        else { return .message(Message.notAURL) }
        // V3. `webcal://` is the same address offered by another name; it is
        // read as `https://` and Kadence connects over HTTPS only.
        if scheme == "http" { return .message(Message.http) }
        // V4: user info in the URL.
        if parts.user != nil || parts.password != nil { return .message(Message.notAURL) }
        // V5: case-sensitive; a trailing `/` is not accepted.
        if parts.percentEncodedPath != exportPath { return .message(Message.wrongPath) }

        // Order of the query parameters, extra parameters and their case are
        // irrelevant (§33.2).
        let items = parts.queryItems ?? []
        func value(_ name: String) -> String? {
            items.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.value
        }
        // V6
        guard let userID = value("userid"), !userID.isEmpty, value("authtoken")?.isEmpty == false
        else { return .message(Message.incomplete) }
        // V7
        guard value("preset_time")?.lowercased() == "recentupcoming" else { return .message(Message.fixedPeriod) }
        // V8
        guard let what = value("preset_what").flatMap({ Scope(rawValue: $0.lowercased()) }) else {
            return .message(Message.someEvents)
        }

        // The normalised form: `https`, the authority lower-cased (it holds
        // only host and port — V4 refused user info), everything after it
        // exactly as pasted.
        let afterScheme = text[schemeEnd.upperBound...]
        let authorityEnd = afterScheme.firstIndex(where: { "/?#".contains($0) }) ?? afterScheme.endIndex
        let authority = afterScheme[..<authorityEnd].lowercased()
        let raw = "https://" + authority + afterScheme[authorityEnd...]
        return .valid(MoodleFeedURL(raw: raw, host: host.lowercased(), port: parts.port, userID: userID, scope: what))
    }
}

extension MoodleFeedURL {
    /// §33.2 V9's input: every other Moodle source's account, read from
    /// Kadence's own Keychain items. A source whose item cannot be read (or
    /// holds no valid URL) is skipped for the check. `excluding`: Replace's
    /// own source.
    @MainActor
    static func connected(_ sources: [Source], secrets: any SecretStore, excluding id: String? = nil) -> [Connected] {
        sources.compactMap { source in
            guard source.connection == .icsFeed, source.feedProfile == .moodle, source.id != id,
                  let url = try? secrets.readFeedURL(sourceID: source.id) else { return nil }
            return Connected(name: source.displayName, url: url)
        }
    }
}
