//
//  ReviewMode.swift
//  Kadence
//
//  PHASE3-PLAN.md task 10 — components.md §22.1, G-057 (ruled 2026-10-08:
//  "a fresh real store starts empty").
//
//  Launch arguments (macOS puts `-Key value` into UserDefaults' argument
//  domain, which is how they are read here):
//
//  - `-KadenceReview phase3` — the Phase 2 dataset, the `timetable` source as
//    a `caldav` source (`user01`, `LVPlan`) whose password is the review
//    password in an in-memory store, served by `MockCalDAVTransport`, and the
//    manual all-day `Studieninformationstag` on `M + 2`.
//  - `-KadenceReview phase2` — the Phase 2 dataset alone (no connected
//    source, no sync): what the Phase 2 regression scripts launch with
//    (DEVIATIONS B41).
//  - `-KadenceReview empty` — nothing but the two built-in sources: what a
//    real first launch holds (§22.1, added 2026-10-10).
//  - `-KadenceReview fresh` — `empty`, then one connected source imported
//    from `reportCISOverlap` (caldav-mocks.md): the real export plus one
//    overlapping session. Its dates are absolute.
//  - `-KadenceMockCalDAV <case>` — the mocked server's case (default
//    `reportOK`).
//
//  PHASE3-REVIEW.md fix 1 (G-076): every review launch runs on its own
//  in-memory store (`AppStore`), never the real one. Without `-KadenceReview`
//  nothing is seeded but the two built-in sources (§21.1.1).
//

import Foundation
import SwiftData

nonisolated enum ReviewMode {
    /// Slice 2 adds `travel` (components.md §30.1).
    enum Dataset: String, Sendable, CaseIterable { case phase2, phase3, empty, fresh, travel }

    /// The review password (components.md §22.1). In-memory only, never the
    /// Keychain; drawn only as `SecureField` bullets.
    static let password = Password("review-only-not-a-password")

    /// The review mode's secret store. Never a `KeychainSecretStore`.
    static let secrets = InMemorySecretStore()

    static func dataset(_ defaults: UserDefaults = .standard) -> Dataset? {
        defaults.string(forKey: "KadenceReview").flatMap(Dataset.init(rawValue:))
    }

    /// Review captures only: `-KadenceAppearance light|dark` sets Kadence's
    /// own appearance (§22 item 19's light and dark frames), so no capture
    /// ever changes the system's. Ignored without `-KadenceReview`.
    static func appearance(_ defaults: UserDefaults = .standard) -> String? {
        guard dataset(defaults) != nil else { return nil }
        return defaults.string(forKey: "KadenceAppearance")
    }

    static func mockCase(_ defaults: UserDefaults = .standard) -> MockCalDAVServer.Case {
        defaults.string(forKey: "KadenceMockCalDAV").flatMap(MockCalDAVServer.Case.init(rawValue:)) ?? .reportOK
    }

    /// Review captures only: `-KadenceReviewVariant singleOption` — the Phase 2
    /// "single option" frame (components.md §17.1): `Training` ±15 and
    /// `Supervisor meeting` 16:45–18:45. The capture scripts used to make
    /// these two edits in the store file with `sqlite3` between launches; a
    /// review store is in memory now (fix 1), so the launch makes them.
    static func variant(_ defaults: UserDefaults = .standard) -> String? {
        guard dataset(defaults) != nil else { return nil }
        return defaults.string(forKey: "KadenceReviewVariant")
    }

    @MainActor
    static func applySingleOptionVariant(context: ModelContext) {
        for block in (try? context.fetch(FetchDescriptor<RoutineBlock>())) ?? [] where block.title == "Training" {
            block.shiftableMinutes = 15
        }
        for event in (try? context.fetch(FetchDescriptor<Event>())) ?? [] where event.title == "Supervisor meeting" {
            event.start = event.start.addingTimeInterval(-2700)
            event.end = event.end.addingTimeInterval(1800)
        }
        try? context.save()
    }

    /// The account of the review source.
    static let server = ServerAddress(host: MockCalDAVServer.host)
    static let calendar = SourceCalendar(href: MockCalDAVServer.lvplan, displayName: "LVPlan")

    /// The mocked server for this launch, its feed rendered at `now`.
    /// `fresh` serves `reportCISOverlap` (absolute dates) instead of the
    /// review template.
    static func server(case mockCase: MockCalDAVServer.Case, now: Date, zone: TimeZone = .current,
                       dataset: Dataset? = nil) -> MockCalDAVServer {
        if dataset == .fresh {
            let feed = ReviewFeed.reportCISOverlap(export: ReviewCISExport.text)
            return MockCalDAVServer(case: mockCase, password: password, feed: feed, changed: feed,
                                    html: Data(signInPage.utf8), acceptsAnyPassword: true)
        }
        if dataset == .travel {
            // §30.1: the travel template, `M` the first Monday ≥ today + 2.
            let m = ReviewFeed.firstMonday(after: now, zone: zone)
            let template = ReviewTravelTemplate.text
            return MockCalDAVServer(
                case: mockCase, password: password,
                feed: ReviewFeed.reportTravel(template: template, today: now, m: m, zone: zone),
                changed: ReviewFeed.reportTravelChanged(template: template, today: now, m: m, zone: zone),
                html: Data(signInPage.utf8), acceptsAnyPassword: true)
        }
        let template = ReviewTemplate.text
        return MockCalDAVServer(
            case: mockCase, password: password,
            feed: ReviewFeed.reportReview(template: template, today: now, zone: zone),
            changed: ReviewFeed.reportChanged(template: template, today: now, zone: zone),
            pruefungen: [ReviewFeed.reportReview(template: template, today: now, zone: zone).last].compactMap {
                $0.map { MockCalDAVServer.Object(href: MockCalDAVServer.pruefungen + "p01.ics", etag: "\"p-01-a\"", data: $0.data) }
            },
            html: Data(signInPage.utf8), acceptsAnyPassword: true)
    }

    /// A web page where calendar data was expected (`htmlOK`, `propfindNot207`).
    static let signInPage = """
        <!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>Sign in</title></head>
        <body><h1>Sign in</h1><form method="post" action="/login"><input name="username"></form></body></html>
        """

    // MARK: Seeding

    /// Seeds what `dataset` asks for, then runs `materialize`. Without a
    /// dataset it only materialises routines: nothing is inserted.
    @MainActor
    @discardableResult
    static func seedIfRequested(_ dataset: Dataset?, context: ModelContext, now: Date = Date(),
                                secrets: any SecretStore = ReviewMode.secrets,
                                materialize: () -> Void) -> MockFixtures {
        guard let dataset else {
            materialize()
            return MockFixtures()
        }
        // Slice 2: `-KadenceLocation notDetermined` / `-KadenceNotifications
        // notDetermined` are "after a recorded ask".
        ReviewTravel.applyArguments(context: context, now: now)
        switch dataset {
        case .empty:
            materialize()
            return MockFixtures()
        case .travel:
            // components.md §30.1: dataset `travel` and its variants; P6, the
            // live event, only here.
            TravelDataset.seed(context: context, now: now, m: ReviewFeed.firstMonday(after: now, zone: .current),
                               zone: .current, variant: ReviewTravel.variant(), liveEvent: true)
            materialize()
            return MockFixtures()
        case .fresh:
            seedFresh(context: context, now: now, secrets: secrets)
            materialize()
            return MockFixtures()
        case .phase2, .phase3:
            let wasSeeded = ((try? context.fetchCount(FetchDescriptor<Event>())) ?? 0) > 0
            let fixtures = MockData.seedAllIfNeeded(context, now: now, materialize: materialize)
            if dataset == .phase3 { seedPhase3(context: context, now: now, secrets: secrets) }
            // Slice 2 (§30.1 "Other datasets"): §12's bands from real legs.
            ReviewTravel.seedPhase(context: context, now: now)
            if !wasSeeded, variant() == "singleOption" { applySingleOptionVariant(context: context) }
            return fixtures
        }
    }

    /// The id of `fresh`'s connected source. Fixed, so a second seeding call
    /// (the other window's) finds it.
    static let freshSourceID = "review-fresh-timetable"

    /// §22.1 `fresh`: the two built-ins, then one connected source imported
    /// from `reportCISOverlap` — written by the same planner and applier the
    /// connect sheet's `Import` uses, with no request. Idempotent.
    @MainActor
    static func seedFresh(context: ModelContext, now: Date, secrets: any SecretStore, zone: TimeZone = .current) {
        BuiltInSource.ensure(in: context)
        let sources = (try? context.fetch(FetchDescriptor<Source>())) ?? []
        guard !sources.contains(where: { $0.id == freshSourceID }) else { return }
        let result = fetchResult(of: ReviewFeed.reportCISOverlap(export: ReviewCISExport.text), now: now, zone: zone)
        let source = Source.connected(
            id: freshSourceID, displayName: "University timetable", serverURL: server.normalized,
            username: MockCalDAVServer.username, principalHref: MockCalDAVServer.principal,
            calendarHomeHref: MockCalDAVServer.home, calendars: [calendar], capabilities: result.capabilities,
            paletteKey: Source.paletteKeyForNewSource(existing: sources.map(\.paletteKey)))
        context.insert(source)
        try? secrets.save(password, for: SecretAccount(host: server.host, username: MockCalDAVServer.username),
                          info: .forSource(id: source.id, displayName: source.displayName))
        importFetched(result, into: source, context: context, now: now, zone: zone)
    }

    /// What a full Import-window read of `objects` hands the planner: the
    /// connect sheet's `fetchResult()` for one calendar, built without a
    /// request.
    static func fetchResult(of objects: [MockCalDAVServer.Object], now: Date, zone: TimeZone) -> ScheduleFetchResult {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        let feedObjects = objects.compactMap { object -> FeedObject? in
            guard case .calendar(let parsed) = ICSParser.parse(object.data, currentZone: zone) else { return nil }
            return FeedObject(calendarHref: calendar.href, objectHref: object.href, calendar: parsed)
        }
        let feed = FeedDerivation.derive(feedObjects, today: cal.startOfDay(for: now), zone: zone)
        var diagnostics = SyncDiagnostics()
        diagnostics.calendarNames = [calendar.displayName]
        diagnostics.objects = feedObjects.count
        diagnostics.vevents = feed.objectCount
        diagnostics.duplicates = feed.duplicateCount
        diagnostics.merged = feed.mergedCount
        diagnostics.etags = objects.map { "\($0.href)=\($0.etag)" }
        return ScheduleFetchResult(
            events: feed.events, problems: feed.problems, objectCount: feed.objectCount, mergedCount: feed.mergedCount,
            calendarsReadInFully: [calendar.href], failedCalendars: [], adoptedCalendars: [],
            capabilities: SourceCapabilities(fetchMode: .report, timeRangeHonoured: true, discoveredAt: now),
            diagnostics: diagnostics, principalHref: MockCalDAVServer.principal,
            calendarHomeHref: MockCalDAVServer.home)
    }

    /// The Import: one planner pass and one applier transaction.
    @MainActor
    static func importFetched(_ result: ScheduleFetchResult, into source: Source, context: ModelContext, now: Date,
                              zone: TimeZone) {
        let plan = SyncPlanner.plan(
            existing: SyncApplier.snapshot(of: source, in: context, zone: zone),
            source: SourceSnapshot(feedHash: source.feedHash, lastFeedEventCount: source.lastFeedEventCount,
                                   calendars: source.calendars, importedAt: source.importedAt),
            result: result, kind: .import, now: now, zone: zone)
        _ = try? SyncApplier.apply(plan, to: source, context: context, now: now)
        try? context.save()
    }

    /// §22.1's review source and the manual all-day event. Idempotent.
    @MainActor
    static func seedPhase3(context: ModelContext, now: Date, secrets: any SecretStore) {
        let sources = (try? context.fetch(FetchDescriptor<Source>())) ?? []
        var needsImport = false
        if let timetable = sources.first(where: { $0.id == "timetable" }), timetable.connection == .local {
            timetable.connection = .caldav
            timetable.serverURL = server.normalized
            timetable.username = MockCalDAVServer.username
            timetable.principalHref = MockCalDAVServer.principal
            timetable.calendarHomeHref = MockCalDAVServer.home
            timetable.calendars = [calendar]
            timetable.capabilities = SourceCapabilities(fetchMode: .report, timeRangeHonoured: nil, discoveredAt: now)
            timetable.state = .neverSynced
            needsImport = true
        }
        // GAPS G-073: Phase 2's `Statistik übung` (§12's done imported block)
        // is not in the review template, so a sync of the connected source
        // would remove it and §22.1's `2 removed` would read 3. Detached from
        // the source (no `sourceID`), it stays exactly as Phase 2 drew it.
        for event in (try? context.fetch(FetchDescriptor<Event>())) ?? []
        where event.sourceID == "timetable" && event.externalID == "stat-ue-04" {
            event.sourceID = nil
        }
        if let timetable = sources.first(where: { $0.id == "timetable" }) {
            try? secrets.save(password, for: SecretAccount(host: server.host, username: MockCalDAVServer.username),
                              info: .forSource(id: timetable.id, displayName: timetable.displayName))
        }
        // §22.1 (amended 2026-10-10; PHASE3-REVIEW fix 9): the review source
        // is seeded **as already imported** — `importedAt` and
        // `lastSuccessAt` are the seeding time and the template's events are
        // written by an Import — so the failure cases (`forbidden`,
        // `calendarGone` …) show what a real source shows when a later sync
        // fails: a last-synced time, and events that are in fact kept. It
        // was a never-imported source whose first sync was the Import, which
        // is how `Never synced` appeared under "Events from the last sync
        // are kept". `lastAttemptAt` is cleared again so the launch sync
        // still runs and reaches the mocked case.
        if needsImport, let timetable = sources.first(where: { $0.id == "timetable" }) {
            let zone = TimeZone.current
            let feed = ReviewFeed.reportReview(template: ReviewTemplate.text, today: now, zone: zone)
            importFetched(fetchResult(of: feed, now: now, zone: zone), into: timetable, context: context, now: now, zone: zone)
            timetable.lastAttemptAt = nil
        }
        // `Studieninformationstag` on M + 2, manual, graphite, all-day.
        let m = ReviewFeed.firstMonday(after: now, zone: .current)
        let calendar = Calendar.current
        if let day = calendar.date(byAdding: .day, value: 2, to: m),
           let next = calendar.date(byAdding: .day, value: 1, to: day) {
            let title = "Studieninformationstag"
            let existing = ((try? context.fetch(FetchDescriptor<Event>())) ?? []).contains { $0.title == title }
            if !existing {
                context.insert(Event(title: title, start: day, end: next, isAllDay: true, origin: .manual,
                                     sourceKey: .graphite))
            }
        }
        try? context.save()
    }
}

// MARK: - The transport

/// Serves `MockCalDAVServer` as an `HTTPTransport` — no network. Review mode
/// only.
nonisolated struct MockCalDAVTransport: HTTPTransport {
    let server: MockCalDAVServer
    /// The real transport's per-request timeout (§13.3).
    var timeout: TimeInterval = 30

    func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse {
        switch server.respond(request) {
        case .response(let response):
            return HTTPResponse(status: response.status, headers: response.headers, body: response.body, url: request.url)
        case .delayed(let seconds, let response):
            do { try await Task.sleep(for: .seconds(seconds)) } catch { throw .cancelled }
            return HTTPResponse(status: response.status, headers: response.headers, body: response.body, url: request.url)
        case .failBeforeSend(let code):
            throw TransportError.from(URLError(code))
        case .noAnswer:
            do { try await Task.sleep(for: .seconds(timeout)) } catch { throw .cancelled }
            throw .timeout
        }
    }
}
