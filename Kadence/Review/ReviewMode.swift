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
//  - `-KadenceMockCalDAV <case>` — the mocked server's case (default
//    `reportOK`).
//
//  Without `-KadenceReview` nothing is seeded: an empty store stays empty.
//

import Foundation
import SwiftData

nonisolated enum ReviewMode {
    enum Dataset: String, Sendable { case phase2, phase3 }

    /// The review password (components.md §22.1). In-memory only, never the
    /// Keychain; drawn only as `SecureField` bullets.
    static let password = Password("review-only-not-a-password")

    /// The review mode's secret store. Never a `KeychainSecretStore`.
    static let secrets = InMemorySecretStore()

    static func dataset(_ defaults: UserDefaults = .standard) -> Dataset? {
        defaults.string(forKey: "KadenceReview").flatMap(Dataset.init(rawValue:))
    }

    static func mockCase(_ defaults: UserDefaults = .standard) -> MockCalDAVServer.Case {
        defaults.string(forKey: "KadenceMockCalDAV").flatMap(MockCalDAVServer.Case.init(rawValue:)) ?? .reportOK
    }

    /// The account of the review source.
    static let server = ServerAddress(host: MockCalDAVServer.host)
    static let calendar = SourceCalendar(href: MockCalDAVServer.lvplan, displayName: "LVPlan")

    /// The mocked server for this launch, its feed rendered at `now`.
    static func server(case mockCase: MockCalDAVServer.Case, now: Date, zone: TimeZone = .current) -> MockCalDAVServer {
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
        let fixtures = MockData.seedAllIfNeeded(context, now: now, materialize: materialize)
        if dataset == .phase3 { seedPhase3(context: context, now: now, secrets: secrets) }
        return fixtures
    }

    /// §22.1's review source and the manual all-day event. Idempotent.
    @MainActor
    static func seedPhase3(context: ModelContext, now: Date, secrets: any SecretStore) {
        let sources = (try? context.fetch(FetchDescriptor<Source>())) ?? []
        if let timetable = sources.first(where: { $0.id == "timetable" }), timetable.connection == .local {
            timetable.connection = .caldav
            timetable.serverURL = server.normalized
            timetable.username = MockCalDAVServer.username
            timetable.principalHref = MockCalDAVServer.principal
            timetable.calendarHomeHref = MockCalDAVServer.home
            timetable.calendars = [calendar]
            timetable.capabilities = SourceCapabilities(fetchMode: .report, timeRangeHonoured: nil, discoveredAt: now)
            timetable.state = .neverSynced
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
