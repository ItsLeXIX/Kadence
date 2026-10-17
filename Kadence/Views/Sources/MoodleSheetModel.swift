//
//  MoodleSheetModel.swift
//  Kadence
//
//  Phase 3 slice 3 (PHASE3-SLICE3-PLAN.md task 10) — layouts.md §16 (the
//  Moodle sheet: step 1, step 2, Replace mode); components.md §33, §34.3;
//  interactions.md §16.1, §16.2.
//
//  Nothing is written before `Import` / `Save` (layouts.md §16): the pasted
//  URL and the fetched items live in this model only and go with it. The
//  URL's text is held only in `urlText` — the `SecureField`'s binding — and
//  becomes a `MoodleFeedURL` (which never prints itself) for the fetch and
//  the Keychain.
//

import Foundation
import SwiftData
import Observation

@MainActor
@Observable
final class MoodleSheetModel {
    enum Field: Hashable { case name, url, connect }
    enum Phase: Equatable { case editing, connecting, step2 }

    struct Failure: Equatable {
        var title: String
        var body: String
    }

    struct Sentence: Equatable {
        var text: String
        /// `color.text.primary` (notices, problems) instead of secondary.
        var isPrimary = false
    }

    // MARK: Inputs

    /// Replace mode's source (layouts.md §16.3); nil when connecting.
    let replacing: Source?
    @ObservationIgnored let context: ModelContext
    @ObservationIgnored let secrets: any SecretStore
    @ObservationIgnored let makeTransport: @Sendable () -> any HTTPTransport
    @ObservationIgnored weak var sync: SyncCoordinator?
    @ObservationIgnored let clock: () -> Date
    @ObservationIgnored let zone: TimeZone

    // MARK: Step 1

    var name: String
    /// The `SecureField`'s text. Held here only, for this sheet's lifetime.
    var urlText = ""
    var phase: Phase = .editing
    var failure: Failure?
    var saveFailure: Failure?
    var focus: Field? = .url
    /// Select the URL field's contents (a failure's paste replaces them).
    var selectsURL = false

    // MARK: Step 2

    private(set) var fetched: FeedFetch?
    private(set) var fetchedURL: MoodleFeedURL?
    @ObservationIgnored private var connectTask: Task<Void, Never>?

    init(replacing: Source? = nil, context: ModelContext, secrets: any SecretStore,
         makeTransport: @escaping @Sendable () -> any HTTPTransport, sync: SyncCoordinator?,
         clock: @escaping () -> Date = { Date() }, zone: TimeZone = .current) {
        self.replacing = replacing
        self.context = context
        self.secrets = secrets
        self.makeTransport = makeTransport
        self.sync = sync
        self.clock = clock
        self.zone = zone
        name = replacing?.displayName ?? "Moodle"
    }

    var isReplace: Bool { replacing != nil }

    // MARK: Copy (layouts.md §16.1, §16.3)

    var title: String { isReplace ? "Replace the calendar URL" : "Connect Moodle" }

    var intro: String {
        isReplace
            ? "Moodle makes a new calendar URL when your FH password changes. In Moodle, choose Get calendar URL again and paste the new one here. Your items and done marks stay."
            : "Kadence reads your deadlines from Moodle's calendar export. In Moodle, open Calendar ▸ Import or export calendars ▸ Export calendar, choose All events and Recent and upcoming, then Get calendar URL, and paste the URL here."
    }

    var placeholder: String {
        isReplace ? "Paste the new URL" : "https://moodle.technikum-wien.at/calendar/export_execute.php?…"
    }

    static let footnote = "The URL works like a password: anyone who has it can read your Moodle calendar. Kadence keeps it in the macOS Keychain and shows only its server."

    /// VoiceOver's value for the URL field — never the URL (layouts.md §16.1).
    var urlAccessibilityValue: String { urlText.isEmpty ? "empty" : "filled" }
    static let urlAccessibilityLabel = "Calendar URL"

    // MARK: Validation (components.md §33.2)

    /// The saved URL in Replace mode (V10), read from the Keychain.
    var savedURL: MoodleFeedURL? {
        guard let replacing else { return nil }
        return try? secrets.readFeedURL(sourceID: replacing.id)
    }

    var validation: MoodleFeedURL.Validation {
        let sources = (try? context.fetch(FetchDescriptor<Source>())) ?? []
        return MoodleFeedURL.validate(urlText, others: MoodleFeedURL.connected(sources, secrets: secrets,
                                                                               excluding: replacing?.id),
                                      replacing: savedURL)
    }

    /// Under the field: the message, or the parsed line (V11).
    var validationLine: String? { validation.line }

    var canConnect: Bool { phase == .editing && validation.canConnect }

    var connectingLine: String {
        guard case .valid(let url) = validation else { return "Connecting…" }
        return "Connecting to \(url.host)…"
    }

    // MARK: Connect

    func connect() {
        guard canConnect, case .valid(let url) = validation else { return }
        failure = nil
        saveFailure = nil
        phase = .connecting
        let transport = makeTransport()
        let zone = zone
        connectTask = Task { [weak self] in
            let result: Result<FeedFetch, ScheduleSourceError>
            do {
                result = .success(try await MoodleFeedFetcher(transport: transport, zone: zone).fetch(url))
            } catch let error as ScheduleSourceError {
                result = .failure(error)
            } catch {
                result = .failure(.unreachable)
            }
            (transport as? URLSessionTransport)?.invalidate()
            guard let self, !Task.isCancelled else { return }
            self.finishConnect(result, url: url)
        }
    }

    /// Tests await the fetch.
    func waitForConnect() async { await connectTask?.value }

    func cancelConnecting() {
        connectTask?.cancel()
        connectTask = nil
        if phase == .connecting { phase = .editing }
    }

    private func finishConnect(_ result: Result<FeedFetch, ScheduleSourceError>, url: MoodleFeedURL) {
        connectTask = nil
        switch result {
        case .success(let fetch):
            fetched = fetch
            fetchedURL = url
            phase = .step2
            SourceLogger.shared.feed(FeedLog.connectLine(display: url.displayForm, fetch: fetch, now: clock()))
        case .failure(.cancelled):
            phase = .editing
        case .failure(let error):
            phase = .editing
            failure = Self.failure(error, host: url.host)
            SourceLogger.shared.feedState(display: url.displayForm, state: error.state)
            switch error {
            case .certificate, .unreachable, .serverError, .offline:
                focus = .connect
                selectsURL = false
            default:
                focus = .url
                selectsURL = true
            }
        }
    }

    /// layouts.md §16.1's failure table: the state's title and the step-1 body.
    static func failure(_ error: ScheduleSourceError, host: String) -> Failure {
        let title = FeedStatusCopy.title(error.state, host: host)
        var facts = StatusFacts(host: host, user: "", name: "")
        let body: String
        switch error {
        case .unauthorized:
            body = "\(host) didn't accept this calendar URL. In Moodle, choose Get calendar URL again and paste the new one."
        case .forbidden:
            body = "\(host) refused access to the calendar."
        case .feedNotFound:
            body = "\(host) has no calendar at this URL. Copy the URL from Moodle again."
        case .notACalendar:
            body = "\(host) sent a web page instead of the calendar. Copy the URL from Moodle's Get calendar URL again."
        case .redirected(let other):
            facts.otherHost = other
            body = FeedStatusCopy.body(.redirected, facts, next: "", last: "", until: "") ?? ""
        case .certificate:
            body = FeedStatusCopy.body(.certificate, facts, next: "", last: "", until: "") ?? ""
        case .serverError(let code):
            body = "\(host) answered with an error (\(code)). Try again later."
        case .offline:
            body = "This Mac is offline. Connect when it's back online."
        default:
            body = "Check your connection, then try again."
        }
        return Failure(title: title, body: body)
    }

    // MARK: Step 2 (layouts.md §16.2)

    var step2Title: String { "\(isReplace ? "Update" : "Import") \(trimmedName)" }

    var trimmedName: String {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return n.isEmpty ? "Moodle" : n
    }

    var displayLine: String { fetchedURL?.displayForm ?? "" }

    private var items: [MoodleItem] { fetched?.feed.items ?? [] }

    var isEmptyCalendar: Bool { items.isEmpty }

    private func date(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_GB")
        f.timeZone = zone
        f.dateFormat = "d MMM yyyy"
        return f.string(from: d)
    }

    /// `{n} items, {first} – {last}`; one date when they are the same day.
    var rangeLine: String {
        guard let first = items.map(\.start).min(), let last = items.map(\.start).max() else {
            return "Moodle has no items for this period yet."
        }
        let a = date(first), b = date(last)
        return "\(FeedStatusCopy.items(items.count)), " + (a == b ? a : "\(a) – \(b)")
    }

    var problems: [ImportProblem] { fetched?.feed.problems ?? [] }

    private static func plural(_ n: Int, _ one: String, _ many: String) -> String { n == 1 ? "1 \(one)" : "\(n) \(many)" }

    /// The sentences, each only when its number is non-zero, in §16.2's order.
    var sentences: [Sentence] {
        guard !items.isEmpty else { return [Sentence(text: "Kadence will add them as they appear.")] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let today = cal.startOfDay(for: clock())
        let deadlines = items.filter { $0.kind == .deadline }
        let pairs = MoodlePairing.pairs(items.map { MomentItem($0, sourceID: "") })
        let openings = items.filter { $0.kind == .opening }
        let paired = openings.filter { pairs.pairedOpenings.contains($0.externalID) }.count
        let unpaired = openings.count - paired
        let notices = items.filter { $0.kind == .notice }.count
        let history = items.filter { $0.start < today }.count
        var out: [Sentence] = []
        if !deadlines.isEmpty {
            let d = deadlines.count
            let c = Set(deadlines.compactMap(\.courseCode)).count
            let g = Set(deadlines.filter { $0.courseCode == nil }.compactMap(\.courseCategory)).count
            let lead = Self.plural(d, "deadline", "deadlines")
            let text: String
            switch (c, g) {
            case (0, 0): text = "\(lead)."
            case (_, 0): text = "\(lead) from \(Self.plural(c, "course", "courses"))."
            case (0, _): text = "\(lead) from \(Self.plural(g, "category", "categories"))."
            default: text = "\(lead) from \(Self.plural(c, "course", "courses")) and \(Self.plural(g, "other category", "other categories"))."
            }
            out.append(Sentence(text: text))
        }
        if paired > 0 {
            out.append(Sentence(text: paired == 1 ? "1 opening is shown with the deadline it belongs to."
                                    : "\(paired) openings are shown with the deadline they belong to."))
        }
        if unpaired > 0 {
            out.append(Sentence(text: unpaired == 1
                ? "1 opening has no deadline in Moodle's list yet, so it's shown on its own."
                : "\(unpaired) openings have no deadline in Moodle's list yet, so they're shown on their own."))
        }
        if notices > 0 {
            out.append(Sentence(text: notices == 1
                ? "1 item isn't a deadline or an opening Kadence recognises. It's shown, but Kadence won't remind you of it."
                : "\(notices) items aren't a deadline or an opening Kadence recognises. They're shown, but Kadence won't remind you of them.",
                isPrimary: true))
        }
        if isReplace {
            out.append(Sentence(text: "Items before today are not changed."))
        } else if history > 0 {
            let text: String
            if history == items.count {
                text = "All of them are before today. They're imported once, as history, and never changed afterwards."
            } else if history == 1 {
                text = "1 of them is before today. It's imported once, as history, and never changed afterwards."
            } else {
                text = "\(history) of them are before today. They're imported once, as history, and never changed afterwards."
            }
            out.append(Sentence(text: text))
        }
        if !isReplace && !deadlines.isEmpty {
            out.append(Sentence(text: "Moodle doesn't tell Kadence what you've handed in. Mark a deadline done in Kadence when you have, and its reminders stop."))
        }
        if !problems.isEmpty {
            out.append(Sentence(text: problems.count == 1 ? "1 item couldn't be read and will be skipped."
                                    : "\(problems.count) items couldn't be read and will be skipped.", isPrimary: true))
        }
        return out
    }

    var canImport: Bool { phase == .step2 && fetched != nil && fetchedURL != nil }

    func back() {
        guard phase == .step2 else { return }
        phase = .editing
        fetched = nil
        fetchedURL = nil
        saveFailure = nil
        focus = .url
    }

    /// `Import` (layouts.md §16.2): (1) the Keychain item, (2) the `Source`,
    /// (3) every item fetched, in one transaction — no further request.
    func importNow() -> Source? {
        guard canImport, !isReplace, let url = fetchedURL, let fetch = fetched else { return nil }
        let id = UUID().uuidString
        do {
            try secrets.saveFeedURL(url, sourceID: id, label: feedItemLabel(displayName: trimmedName))
        } catch {
            saveFailure = Failure(title: "URL not saved",
                                  body: "Kadence couldn't save the calendar URL in the Keychain, so nothing was saved. Try again.")
            return nil
        }
        let used = ((try? context.fetch(FetchDescriptor<Source>())) ?? []).map(\.paletteKey)
        let source = Source.moodleFeed(id: id, displayName: trimmedName, host: url.host,
                                       paletteKey: Source.paletteKeyForNewSource(existing: used))
        context.insert(source)
        try? context.save()
        do {
            if let sync { try sync.applyFeedFetched(fetch, to: source, kind: .import) }
            else {
                let plan = FeedSyncPlanner.plan(existing: [], source: FeedSyncApplier.sourceSnapshot(source), fetch: fetch,
                                                kind: .import, now: clock(), zone: zone)
                try FeedSyncApplier.apply(plan, to: source, context: context, now: clock())
            }
        } catch {
            return nil
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let today = cal.startOfDay(for: clock())
        SourceLogger.shared.feed(FeedLog.importLine(display: url.displayForm, items: fetch.feed.items.count,
                                                    beforeToday: fetch.feed.items.filter { $0.start < today }.count))
        urlText = ""
        return source
    }

    /// Replace's `Save` (components.md §33.5): the Keychain item updated in
    /// place, the pause cleared, the fetched items applied as a sync. A
    /// Keychain failure keeps the old URL and writes nothing.
    @discardableResult
    func save() -> Bool {
        guard canImport, let replacing, let url = fetchedURL, let fetch = fetched else { return false }
        do {
            try secrets.updateFeedURL(url, sourceID: replacing.id)
        } catch {
            saveFailure = Failure(title: "URL not saved",
                                  body: "Kadence couldn't save the new calendar URL in the Keychain. The old one is still in use. Try again.")
            return false
        }
        do {
            if let sync { try sync.applyFeedFetched(fetch, to: replacing, kind: .sync) }
            else {
                let plan = FeedSyncPlanner.plan(existing: FeedSyncApplier.snapshot(of: replacing, in: context, zone: zone),
                                                source: FeedSyncApplier.sourceSnapshot(replacing), fetch: fetch,
                                                kind: .sync, now: clock(), zone: zone)
                try FeedSyncApplier.apply(plan, to: replacing, context: context, now: clock())
                replacing.isAutoSyncPaused = false
                try? context.save()
            }
        } catch {
            return false
        }
        urlText = ""
        return true
    }
}

// MARK: - Settings ▸ Sources for a Moodle source, and removal (layouts.md §15; interactions.md §16.4)

@MainActor
enum MoodleSourceSettings {
    /// §15's `URL` row: the display form, never more.
    static func urlRow(_ source: Source) -> String { source.feedDisplay }

    static func removalInformative(itemCount: Int) -> String {
        "Its \(FeedStatusCopy.items(itemCount)) — including past ones and anything you marked done — will be removed "
            + "from your calendar, and its calendar URL deleted from the Keychain. You can connect it again at any time; "
            + "the items Moodle still lists come back, your done marks don't."
    }

    static func keychainFollowUp(name: String) -> String {
        "The calendar URL for \(name) couldn't be deleted from the Keychain. You can remove the item “Kadence — \(name)” in Keychain Access."
    }
}
