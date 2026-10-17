//
//  FeedSyncTests.swift
//  KadenceTests
//
//  PHASE3-SLICE3-PLAN.md task 6 — components.md §34.4–§34.9, §20.9;
//  interactions.md §16.3; moodle-mocks.md M4. The real coordinator on an
//  in-memory store, the in-memory secret store, `MockFeedTransport` and an
//  injected clock (Europe/Vienna). No network.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

private typealias F = MoodleFixture

/// One Moodle source on a real coordinator.
@MainActor
final class FeedRig {
    let container: ModelContainer
    let context: ModelContext
    let secrets = InMemorySecretStore()
    let scheduling = FakeScheduling()
    let path = FakePath()
    var now: Date
    /// The case the next fetch answers.
    var feedCase: MoodleFeedCase = .feedOK
    private(set) var transports: [MockFeedTransport] = []
    let lines = LockedLines()
    private let sink: UUID
    var coordinator: SyncCoordinator!
    var source: Source!

    init(now: Date) throws {
        self.now = now
        container = try ModelContainer(for: Schema(KadenceSchema.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
        let lines = lines
        sink = SourceLogger.shared.addSink { lines.append($0) }
        let secrets = secrets
        coordinator = SyncCoordinator(
            context: context, secrets: secrets, scheduling: scheduling, path: path,
            clock: { [unowned self] in self.now }, zone: { F.zone },
            makeFeedSource: { [unowned self] id in
                let mock = MockFeedTransport(case: self.feedCase, base: F.text)
                self.transports.append(mock)
                return MoodleFeedSource(sourceID: id, secrets: secrets, zone: F.zone, fixedMilliseconds: 412) { mock }
            },
            makeSource: { _ in RefusingScheduleSource() })
        coordinator.isFrontmost = { false }
    }

    deinit { SourceLogger.shared.removeSink(sink) }

    var requests: [MockFeedTransport.Record] { transports.flatMap(\.records) }
    /// This rig's feed lines (other suites log through the same logger).
    var feedLines: [String] { lines.all.filter { $0.contains("moodle.technikum-wien.at/…") } }

    /// The sheet's connect + Import of `feedOK` at `now`: Keychain item →
    /// `Source` → items (layouts.md §16.2).
    @discardableResult
    func importFeed(_ feedCase: MoodleFeedCase = .feedOK) async throws -> FeedSyncPlan {
        let url = try #require(MoodleMock.url)
        let fetch = try await MoodleFeedFetcher(transport: MockFeedTransport(case: feedCase, base: F.text), zone: F.zone,
                                                fixedMilliseconds: 412).fetch(url)
        let source = Source.moodleFeed(host: url.host, paletteKey: .teal)
        try secrets.saveFeedURL(url, sourceID: source.id, label: feedItemLabel(displayName: source.displayName))
        context.insert(source)
        try context.save()
        self.source = source
        return try coordinator.applyFeedFetched(fetch, to: source, kind: .import)
    }

    func sync(_ feedCase: MoodleFeedCase, at time: Date, trigger: SyncCoordinator.Trigger = .syncNow) async {
        self.feedCase = feedCase
        now = time
        coordinator.trigger(trigger, sourceID: source.id)
        await coordinator.waitUntilIdle()
    }

    var events: [Event] { SyncApplier.events(of: source, in: context).sorted { $0.externalID ?? "" < $1.externalID ?? "" } }
    func event(_ number: String) -> Event? { events.first { $0.externalID?.hasPrefix(number + "@") == true } }
    var numbers: [String] { events.compactMap { $0.externalID.map { String($0.prefix(6)) } } }

    /// Every string the store holds for the slice's models, and UserDefaults.
    func storedStrings() throws -> [String] {
        var out: [String] = []
        for e in try context.fetch(FetchDescriptor<Event>()) {
            out += [e.title, e.notes, e.externalID ?? "", e.sourceID ?? "", e.upstreamTitle ?? "", e.courseCategory ?? "",
                    e.courseCode ?? "", e.importedDescription ?? "", e.link ?? "", e.location?.name ?? ""]
        }
        for s in try context.fetch(FetchDescriptor<Source>()) {
            out += [s.id, s.displayName, s.serverURL ?? "", s.username ?? "", s.stateDetail ?? "", s.feedHash ?? "",
                    s.principalHref ?? "", s.calendarHomeHref ?? ""]
            out += s.problems.flatMap { [$0.sentence, $0.technical ?? ""] }
        }
        for r in try context.fetch(FetchDescriptor<NotificationRecord>()) { out += [r.identifier, r.subjectID] }
        out += UserDefaults.standard.dictionaryRepresentation().flatMap { ["\($0.key)", "\($0.value)"] }
        return out
    }

    func expectNoLeak() throws {
        for text in try storedStrings() + lines.all { #expect(!F.leaks(text), "\(text.prefix(120))") }
    }
}

/// Never asked: the rig has no CalDAV source.
nonisolated struct RefusingScheduleSource: ScheduleSource {
    func fetch(windowStart: Date) async throws(ScheduleSourceError) -> ScheduleFetchResult { throw .offline }
}

@MainActor
struct FeedSyncTests {
    static let importTime = F.date("2026-10-16 13:07")
    static let syncTime = F.date("2026-10-16 14:07")

    @Test("M4's sync table row by row: Import feedOK Fri 13:07, 900008 done, sync feedChanged 14:07; a second sync writes nothing")
    func syncTable() async throws {
        let rig = try FeedRig(now: Self.importTime)
        try await rig.importFeed()
        #expect(rig.events.count == 29)
        let source = try #require(rig.source)
        #expect(source.observedLookahead == (59 * 86_400 + 2 * 3600 + 13 * 60))
        #expect(source.importedAt == Self.importTime && source.state == .upToDate)
        let e8 = try #require(rig.event("900008"))
        let id8 = e8.id
        e8.status = .done; e8.markedDoneDueAt = e8.start
        try rig.context.save()

        await rig.sync(.feedChanged, at: Self.syncTime)
        #expect(source.state == .upToDate)
        let moved = try #require(rig.event("900008"))
        #expect(moved.id == id8 && moved.status == .done)
        #expect(F.local(moved.start) == "Thu 22 Oct 12:00 CEST")
        #expect(MomentItem(moved)?.dueTimeChangedAfterDone == true)
        #expect(rig.event("900026") == nil)   // E2: deleted inside the window
        #expect(rig.event("900029") != nil)   // E3: kept, after the window's end
        #expect(rig.event("900024")?.importedDescription == "Fixture description 24.")  // E4
        #expect(rig.event("900030")?.importKind == .deadline)
        #expect(rig.event("900031")?.importKind == .opening)
        #expect(rig.event("900001") != nil)   // E7: history
        #expect(rig.event("900005")?.importedDescription != "Changed after the fact.")  // E8: past, unchanged
        #expect(rig.events.count == 29 - 1 + 2)
        let presentation = SourceStatusPresentation(source: source, now: Self.syncTime.addingTimeInterval(23 * 60), zone: F.zone)
        #expect(presentation.lastChangeLine == "Last change today 14:07: 2 added · 2 updated · 1 removed")
        let kb = FeedLog.kilobytes(F.body(.feedChanged).count)
        // `contains`: other suites log through the same logger in parallel.
        #expect(rig.feedLines.contains("sync moodle.technikum-wien.at/… · feed · requests 1 · 412 ms · \(kb) KB · vevents 28 · duplicates 0 · deadlines 23 · openings 5 · paired 4 · notices 0 · lookahead 59d · wrote"))

        // A second sync of feedChanged writes nothing.
        let before = rig.events.map { "\($0.id)\($0.start)\($0.title)\($0.importedDescription ?? "")" }
        await rig.sync(.feedChanged, at: Self.syncTime.addingTimeInterval(3600))
        #expect(rig.events.map { "\($0.id)\($0.start)\($0.title)\($0.importedDescription ?? "")" } == before)
        #expect(rig.feedLines.contains("sync moodle.technikum-wien.at/… · feed · requests 1 · 412 ms · \(kb) KB · vevents 28 · duplicates 0 · deadlines 23 · openings 5 · paired 4 · notices 0 · lookahead 59d · feed unchanged"))
        #expect(source.lastChangeAt == Self.syncTime)
        try rig.expectNoLeak()
    }

    @Test("The proof window is [16 Oct 00:00 CEST, Sun 13 Dec 14:20Z] for the 14:07 sync")
    func proofWindow() throws {
        let feed = try #require(F.feed(.feedChanged))
        let plan = FeedSyncPlanner.plan(
            existing: [], source: FeedSourceSnapshot(feedHash: nil, lastFeedEventCount: 29,
                                                     observedLookahead: 59 * 86_400 + 2 * 3600 + 13 * 60, emptySince: nil),
            fetch: FeedFetch(feed: feed, requests: 1, milliseconds: 1, bytes: 1), kind: .sync, now: Self.syncTime, zone: F.zone)
        #expect(plan.proofWindow?.lowerBound == F.date("2026-10-16 00:00"))
        #expect(plan.proofWindow?.upperBound == ISO8601DateFormatter().date(from: "2026-12-13T14:20:00Z"))
    }

    @Test("feedOK twice, feedStampOnly, feedLF → nothing written", arguments: [MoodleFeedCase.feedOK, .feedStampOnly, .feedLF])
    func idempotent(_ feedCase: MoodleFeedCase) async throws {
        let rig = try FeedRig(now: Self.importTime)
        try await rig.importFeed()
        let before = rig.events.map { "\($0.id)\($0.start)\($0.title)\($0.importedDescription ?? "")\($0.upstreamTitle ?? "")" }
        await rig.sync(.feedOK, at: Self.syncTime)
        await rig.sync(feedCase, at: Self.syncTime.addingTimeInterval(3600))
        #expect(rig.events.map { "\($0.id)\($0.start)\($0.title)\($0.importedDescription ?? "")\($0.upstreamTitle ?? "")" } == before)
        #expect(rig.source.lastChangeAt == nil && rig.source.state == .upToDate)
        #expect(rig.feedLines.contains { $0.hasPrefix("sync ") && $0.hasSuffix(" · feed unchanged") })
        try rig.expectNoLeak()
    }

    @Test("feedAged at Thu 22 Oct 08:00 → nothing deleted; history keeps 900004's done; the feed hash is stored")
    func aged() async throws {
        let rig = try FeedRig(now: Self.importTime)
        try await rig.importFeed()
        let e4 = try #require(rig.event("900004"))
        e4.status = .done; e4.markedDoneDueAt = e4.start
        try rig.context.save()
        let oldHash = rig.source.feedHash
        await rig.sync(.feedAged, at: F.date("2026-10-22 08:00"))
        #expect(rig.events.count == 29 && rig.source.state == .upToDate)
        #expect(rig.event("900004")?.status == .done)
        #expect(rig.source.feedHash != nil && rig.source.feedHash != oldHash)
        #expect(rig.source.lastChangeAt == nil)
        try rig.expectNoLeak()
    }

    @Test("feedEmpty: emptyFeed with {until}; +11 h 59 min nothing; +12 h deletions in the window only, history kept")
    func emptyFeed() async throws {
        let rig = try FeedRig(now: Self.importTime)
        try await rig.importFeed()
        await rig.sync(.feedEmpty, at: Self.syncTime)
        let source = try #require(rig.source)
        #expect(source.state == .emptyFeed && source.emptySince == Self.syncTime && rig.events.count == 29)
        let p = SourceStatusPresentation(source: source, now: Self.syncTime, zone: F.zone)
        #expect(p.title == "Moodle sent no items")
        #expect(p.body == "moodle.technikum-wien.at sent an empty calendar, though it had 29 items at the last sync. They are kept; if it still sends none after tomorrow 02:07, Kadence removes the ones from today on.")
        await rig.sync(.feedEmpty, at: Self.syncTime.addingTimeInterval(11 * 3600 + 59 * 60))
        #expect(source.state == .emptyFeed && source.emptySince == Self.syncTime && rig.events.count == 29)
        await rig.sync(.feedEmpty, at: Self.syncTime.addingTimeInterval(12 * 3600))
        #expect(source.state == .upToDate && source.emptySince == nil)
        // From today (Sat 17 Oct) on, inside the window, gone; the past and
        // what is beyond the window kept.
        #expect(rig.numbers == ["900001", "900002", "900003", "900004", "900005", "900006", "900007", "900029"])
        #expect(source.lastChangeRemoved == 21)
        try rig.expectNoLeak()
    }

    @Test("A fetch with items between two empty ones clears emptySince")
    func emptyCleared() async throws {
        let rig = try FeedRig(now: Self.importTime)
        try await rig.importFeed()
        await rig.sync(.feedEmpty, at: Self.syncTime)
        await rig.sync(.feedOK, at: Self.syncTime.addingTimeInterval(3600))
        #expect(rig.source.emptySince == nil && rig.source.state == .upToDate)
        await rig.sync(.feedEmpty, at: Self.syncTime.addingTimeInterval(13 * 3600))
        #expect(rig.source.state == .emptyFeed && rig.events.count == 29)
    }

    @Test("An empty feed at the Import is just empty")
    func emptyImport() async throws {
        let rig = try FeedRig(now: Self.importTime)
        let plan = try await rig.importFeed(.feedEmpty)
        #expect(plan.state == .upToDate && rig.events.isEmpty && rig.source.emptySince == nil)
    }

    @Test("feed401 / feed403 → paused; the next interval sends nothing; Sync Now sends one; Replace's Save clears the pause",
          arguments: [(MoodleFeedCase.feed401, SourceState.unauthorized), (.feed403, .forbidden)])
    func pause(_ feedCase: MoodleFeedCase, _ state: SourceState) async throws {
        let rig = try FeedRig(now: Self.importTime)
        try await rig.importFeed()
        await rig.sync(feedCase, at: Self.syncTime, trigger: .interval)
        #expect(rig.source.state == state && rig.source.isAutoSyncPaused)
        #expect(rig.requests.count == 1)
        await rig.sync(.feedOK, at: Self.syncTime.addingTimeInterval(3600), trigger: .interval)
        #expect(rig.requests.count == 1 && rig.source.isAutoSyncPaused)
        await rig.sync(feedCase, at: Self.syncTime.addingTimeInterval(7200), trigger: .syncNow)
        #expect(rig.requests.count == 2 && rig.source.isAutoSyncPaused)
        // Replace's Save: the Keychain item updated in place, the fetched
        // items applied as a sync, the pause cleared.
        let fetch = try await MoodleFeedFetcher(transport: MockFeedTransport(case: .feedOK, base: F.text), zone: F.zone)
            .fetch(try #require(MoodleMock.url))
        try rig.coordinator.applyFeedFetched(fetch, to: rig.source, kind: .sync)
        #expect(!rig.source.isAutoSyncPaused && rig.source.state == .upToDate)
        try rig.expectNoLeak()
    }

    @Test("A Sync Now that succeeds clears the pause")
    func syncNowClears() async throws {
        let rig = try FeedRig(now: Self.importTime)
        try await rig.importFeed()
        await rig.sync(.feed401, at: Self.syncTime, trigger: .interval)
        await rig.sync(.feedOK, at: Self.syncTime.addingTimeInterval(60), trigger: .syncNow)
        #expect(!rig.source.isAutoSyncPaused && rig.source.state == .upToDate)
    }

    @Test("urlMissing: the Keychain item deleted before a sync → urlMissing, no request")
    func urlMissing() async throws {
        let rig = try FeedRig(now: Self.importTime)
        try await rig.importFeed()
        try rig.secrets.deleteFeedURL(sourceID: rig.source.id)
        await rig.sync(.feedOK, at: Self.syncTime)
        #expect(rig.source.state == .urlMissing && rig.requests.isEmpty)
        let p = SourceStatusPresentation(source: rig.source, now: Self.syncTime, zone: F.zone)
        #expect(p.title == "Calendar URL not found")
        #expect(p.body == "Kadence couldn't read the calendar URL for Moodle from the Keychain. Paste it again.")
        #expect(p.primaryAction == .replaceURL)
        #expect(rig.feedLines.contains("state moodle.technikum-wien.at/… · urlMissing"))
    }

    @Test("Every M3 failure after an Import: its state, nothing written, the stored detail is the feed's copy, no leak",
          arguments: [MoodleFeedCase.feedHTML, .feedError200, .feed401, .feed403, .feed404, .feed410, .feed500, .feed503,
                      .feed429, .feedRedirectTwice, .feedRedirectCrossHost, .feedRedirectHTTP, .feedTLS, .feedTimeout,
                      .feedRefused, .feedHuge, .feedBroken, .feedDuplicateUID, .feedInvalidUTF8, .feedNotice,
                      .feedRedirectSameHost])
    func everyCase(_ feedCase: MoodleFeedCase) async throws {
        let rig = try FeedRig(now: Self.importTime)
        try await rig.importFeed()
        let before = Set(rig.events.map(\.id))
        await rig.sync(feedCase, at: Self.syncTime)
        let after = Set(rig.events.map(\.id))
        switch feedCase {
        case .feedBroken, .feedDuplicateUID, .feedInvalidUTF8:
            #expect(rig.source.state == .partialImport)
            #expect(before.isSubset(of: after))   // nothing deleted
        case .feedNotice:
            #expect(rig.source.state == .upToDate && rig.event("900040")?.importKind == .notice)
            #expect(rig.event("900041")?.end.timeIntervalSince(rig.event("900041")?.start ?? .now) == 3600)
        case .feedRedirectSameHost:
            #expect(rig.source.state == .upToDate && rig.requests.count == 2)
        default:
            #expect(before == after)
        }
        let p = SourceStatusPresentation(source: rig.source, now: Self.syncTime, zone: F.zone)
        for text in [p.title, p.body ?? "", p.statusLine, p.hoverHelp, p.accessibilityValue] {
            #expect(!text.contains("Sign-in failed") && !text.contains("password for") && !F.leaks(text), "\(text)")
        }
        try rig.expectNoLeak()
    }

    @Test("feedBroken: partialImport with the exact body; the four problem sentences")
    func broken() async throws {
        let rig = try FeedRig(now: Self.importTime)
        try await rig.importFeed()
        await rig.sync(.feedBroken, at: Self.syncTime)
        let p = SourceStatusPresentation(source: rig.source, now: Self.syncTime, zone: F.zone)
        #expect(p.title == "Imported with problems")
        #expect(p.body == "4 of 33 items couldn't be read and were skipped. Nothing was removed.")
        #expect(p.primaryAction == .showDetails)
        #expect(rig.source.problems.count == 4)
    }

    @Test("A sync during a conflict preview is held until the preview ends (§20.9)")
    func heldDuringPreview() async throws {
        let rig = try FeedRig(now: Self.importTime)
        try await rig.importFeed()
        let state = CalendarState()
        rig.coordinator.calendarState = state
        state.selectedConflictOptionID = UUID()
        await rig.sync(.feedChanged, at: Self.syncTime)
        #expect(rig.event("900026") != nil)   // held
        state.abandonConflictPreview()
        #expect(rig.event("900026") == nil)
    }

    @Test("Log lines exact: feedOK's connect and Import at Mon 12 Oct 06:00; none contains a title or a category")
    func logLines() async throws {
        let now = F.date("2026-10-12 06:00")
        let url = try #require(MoodleMock.url)
        let fetch = try await MoodleFeedFetcher(transport: MockFeedTransport(case: .feedOK, base: F.text), zone: F.zone,
                                                fixedMilliseconds: 412).fetch(url)
        let connect = FeedLog.connectLine(display: url.displayForm, fetch: fetch, now: now)
        #expect(connect == "connect moodle.technikum-wien.at/… · feed · requests 1 · 412 ms · 17 KB · vevents 29 · duplicates 0 · deadlines 25 · openings 4 · paired 4 · notices 0 · lookahead 63d · previewed 29 items")
        let before = fetch.feed.items.filter { $0.start < F.date("2026-10-12 00:00") }.count
        #expect(FeedLog.importLine(display: url.displayForm, items: 29, beforeToday: before)
                == "import moodle.technikum-wien.at/… · 29 items · 1 before today")
        for item in fetch.feed.items {
            #expect(!connect.contains(item.title) || item.title.count < 4)
            #expect(!connect.contains(item.courseCategory ?? "\u{0}"))
        }
        #expect(!F.leaks(connect))
    }

    @Test("Source.moodleFeed: §33.6's record — coursework, icsFeed, moodle, https://{host} only, hourly")
    func record() {
        let s = Source.moodleFeed(host: "Moodle.Technikum-Wien.at", paletteKey: .teal)
        #expect(s.kind == .coursework && s.connection == .icsFeed && s.feedProfile == .moodle)
        #expect(s.displayName == "Moodle" && s.serverURL == "https://moodle.technikum-wien.at" && s.pollInterval == 3600)
        #expect(s.username == nil && s.principalHref == nil && s.calendars.isEmpty && s.symbol == "tray.2.fill")
        #expect(s.feedDisplay == "moodle.technikum-wien.at/…")
    }

    @Test("The hourly default schedules through the per-source scheduler with 10 % tolerance")
    func hourly() async throws {
        let rig = try FeedRig(now: Self.importTime)
        try await rig.importFeed()
        #expect(rig.scheduling.entries.last == FakeScheduling.Entry(id: rig.source.id, interval: 3600, tolerance: 360))
    }
}
