//
//  MoodleReviewTests.swift
//  KadenceTests
//
//  PHASE3-SLICE3-PLAN.md task 9 — components.md §43.1 (the template, the
//  datasets `moodle` and `moodleOnly`, `-KadenceFeed`), §43.2 (the plan
//  dump, item 20), §22.1's review rules. In-memory stores, the in-memory
//  secret store, the recording centre; Europe/Vienna; M pinned.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

private typealias F = MoodleFixture

/// Every line but `DTSTAMP`.
private func withoutStamps(_ text: String) -> String {
    text.components(separatedBy: "\r\n").filter { !$0.hasPrefix("DTSTAMP:") }.joined(separator: "\r\n")
}

/// A fresh in-memory container. The caller keeps it: a `ModelContext`
/// outlived by its container traps in SwiftData.
@MainActor
private func store() throws -> ModelContainer {
    try ModelContainer(for: Schema(KadenceSchema.models), configurations: ModelConfiguration(isStoredInMemoryOnly: true))
}

@MainActor
struct MoodleReviewTests {
    static let m = F.date("2026-10-12 00:00")

    @Test("The template is in the app bundle and rendered at M = 12 Oct equals the fixture, DTSTAMP aside")
    func templateReproducesFixture() {
        let template = MoodleReviewTemplate.text
        #expect(!template.isEmpty)
        #expect(template.contains("{{M-1 23:59}}") && template.contains("DTSTAMP:{{NOW}}"))
        let rendered = MoodleReviewTemplate.render(template, m: Self.m, now: F.date("2026-10-16 13:07"), zone: F.zone)
        #expect(withoutStamps(rendered) == withoutStamps(F.text))
        #expect(rendered.contains("DTSTAMP:20261016T110700Z"))
        // Byte for byte otherwise: the same length but for the stamps.
        #expect(rendered.utf8.count == F.text.utf8.count)
    }

    @Test("Rendered with M = 19 Oct every item is 7 days later at the same local time — across Sun 25 Oct")
    func templateShifts() throws {
        let later = MoodleReviewTemplate.render(MoodleReviewTemplate.text, m: F.date("2026-10-19 00:00"),
                                                now: F.date("2026-10-19 06:00"), zone: F.zone)
        guard case .calendar(let shifted) = MoodleProfile.read(Data(later.utf8), zone: F.zone),
              let base = F.feed() else { Issue.record("not a calendar"); return }
        #expect(shifted.items.count == 29)
        for (a, b) in zip(base.items, shifted.items) {
            let week = F.calendar.date(byAdding: .day, value: 7, to: a.start)
            let parts = F.calendar.dateComponents([.hour, .minute], from: a.start)
            let expected = WallClock.moment(minuteOfDay: (parts.hour ?? 0) * 60 + (parts.minute ?? 0),
                                            on: F.calendar.startOfDay(for: week ?? a.start), calendar: F.calendar)
            #expect(b.start == expected, "\(a.externalID)")
        }
        // 900005, Tue 13 Oct 23:59 CEST → Tue 20 Oct 23:59 CEST; 900013, Sun
        // 1 Nov 23:59 CET → Sun 8 Nov 23:59 CET; 900008, Tue 20 Oct 12:00
        // CEST → Tue 27 Oct 12:00 CET (the clocks changed in between).
        let n = { (num: String) in shifted.items.first { F.number($0) == num }.map { F.local($0.start) } }
        #expect(n("900005") == "Tue 20 Oct 23:59 CEST")
        #expect(n("900008") == "Tue 27 Oct 12:00 CET")
        #expect(n("900013") == "Sun 8 Nov 23:59 CET")
        // The feed cases' inserted dates move with it.
        let shift = MoodleReviewTemplate.shift(m: F.date("2026-10-19 00:00"), zone: F.zone)
        #expect(shift("20261022T100000Z") == "20261029T110000Z")
        #expect(MoodleReviewTemplate.shift(m: Self.m, zone: F.zone)("20261022T100000Z") == "20261022T100000Z")
    }

    @Test("moodle: travel's events, conflicts and notification plan unchanged; the Moodle source teal, 29 items, 900004 done")
    func moodleDataset() async throws {
        let now = F.date("2026-10-12 06:00")
        let plainStore = try store(), moodleStore = try store()
        let plain = plainStore.mainContext, moodle = moodleStore.mainContext
        TravelDataset.seed(context: plain, now: now, m: Self.m, zone: F.zone, template: ReviewTravelTemplate.text)
        let secrets = InMemorySecretStore()
        MoodleReview.seed(context: moodle, now: now, m: Self.m, zone: F.zone, secrets: secrets, withTravel: true)

        let source = try #require(try moodle.fetch(FetchDescriptor<Source>()).first { $0.id == MoodleReview.sourceID })
        #expect(source.paletteKey == .teal && source.connection == .icsFeed && source.feedProfile == .moodle)
        #expect(source.displayName == "Moodle" && source.serverURL == "https://moodle.technikum-wien.at")
        #expect(source.importedAt == now && source.lastAttemptAt == nil && source.pollInterval == 3600)
        // `teal` is also what the palette rule gives beside the timetable's blue.
        let slots = try plain.fetch(FetchDescriptor<Source>()).map(\.paletteKey)
        #expect(Source.paletteKeyForNewSource(existing: slots) == .teal)
        let items = SyncApplier.events(of: source, in: moodle)
        #expect(items.count == 29)
        let retake = try #require(items.first { $0.externalID?.hasPrefix("900004@") == true })
        #expect(retake.status == .done && retake.markedDoneDueAt == retake.start)
        #expect(try secrets.readFeedURL(sourceID: source.id) == MoodleMock.url)
        #expect(try moodle.fetchCount(FetchDescriptor<NotificationRule>()) == 6)

        // Everything else is `travel`'s, unchanged.
        func others(_ c: ModelContext) throws -> [String] {
            try c.fetch(FetchDescriptor<Event>()).filter { !($0.origin == .imported && $0.importKind.isMoodle) }
                .map { "\($0.title)|\($0.start.timeIntervalSince1970)|\($0.end.timeIntervalSince1970)|\($0.sourceID ?? "")" }.sorted()
        }
        #expect(try others(plain) == others(moodle))
        let conflicts = { (c: ModelContext) throws in
            ConflictEngine.detect(events: try c.fetch(FetchDescriptor<Event>()),
                                  routineBlocks: try c.fetch(FetchDescriptor<RoutineBlock>()), today: now).count
        }
        #expect(try conflicts(plain) == conflicts(moodle))
        func plan(_ c: ModelContext) -> [String] {
            NotificationScheduler(context: c, centre: RecordingNotificationCenter(), clock: ManualTravelClock(now),
                                  calendar: F.calendar, log: RoutingLog(category: "notifications"))
                .makePlan(now: now).filter { !$0.identifier.hasPrefix("due.") }.map { "\($0.fireAt)|\($0.text.title)|\($0.text.body)" }
        }
        #expect(plan(plain) == plan(moodle))
        // Idempotent.
        MoodleReview.seed(context: moodle, now: now, m: Self.m, zone: F.zone, secrets: secrets, withTravel: true)
        #expect(SyncApplier.events(of: source, in: moodle).count == 29)
        #expect(try moodle.fetch(FetchDescriptor<Source>()).filter { $0.id == MoodleReview.sourceID }.count == 1)
    }

    @Test("moodleOnly: the built-ins, Sleep, the Moodle source, nothing else")
    func moodleOnlyDataset() throws {
        let container = try store()
        let context = container.mainContext
        MoodleReview.seed(context: context, now: F.date("2026-10-12 06:00"), m: Self.m, zone: F.zone,
                          secrets: InMemorySecretStore(), withTravel: false)
        let sources = try context.fetch(FetchDescriptor<Source>())
        #expect(Set(sources.map(\.id)) == ["personal", "routine", MoodleReview.sourceID])
        let windows = try context.fetch(FetchDescriptor<TimeWindow>())
        #expect(windows.count == 1 && windows[0].label == "Sleep" && windows[0].kind == .protected)
        #expect(windows[0].startMinutes == 1320 && windows[0].endMinutes == 420 && windows[0].weekdays == Set(1...7))
        let events = try context.fetch(FetchDescriptor<Event>())
        #expect(events.count == 29 && events.allSatisfy { $0.sourceID == MoodleReview.sourceID })
        #expect(try context.fetchCount(FetchDescriptor<RoutineTemplate>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<NotificationRule>()) == 6)
    }

    @Test("-KadenceFeed <case> selects the mock case, default feedOK; the review transport serves the template at M")
    func feedArgument() async throws {
        let defaults = try #require(UserDefaults(suiteName: "kadence-p3s3t9-\(UUID().uuidString)"))
        #expect(MoodleReview.feedCase(defaults) == .feedOK)
        defaults.set("feed401", forKey: "KadenceFeed")
        #expect(MoodleReview.feedCase(defaults) == .feed401)
        defaults.set("nonsense", forKey: "KadenceFeed")
        #expect(MoodleReview.feedCase(defaults) == .feedOK)
        let mock = MoodleReview.transport(case: .feedOK, m: Self.m, now: F.date("2026-10-12 06:00"), zone: F.zone)
        let fetch = try await MoodleFeedFetcher(transport: mock, zone: F.zone).fetch(try #require(MoodleMock.url))
        #expect(fetch.feed.items.count == 29)
        let changed = MoodleReview.transport(case: .feedChanged, m: F.date("2026-10-19 00:00"), now: F.date("2026-10-19 06:00"),
                                             zone: F.zone)
        let moved = try await MoodleFeedFetcher(transport: changed, zone: F.zone).fetch(try #require(MoodleMock.url))
        // E1 moved with the week: Thu 29 Oct 12:00 CET.
        #expect(moved.feed.items.first { F.number($0) == "900008" }.map { F.local($0.start) } == "Thu 29 Oct 12:00 CET")
    }

    @Test("Review launches construct no real transport, Keychain or notification centre")
    func reviewServices() {
        for dataset in [ReviewMode.Dataset.moodle, .moodleOnly] {
            ServiceLaunchLog.reset()
            let feed = KadenceApp.reviewFeedTransport(kind: .review(dataset))
            _ = NotificationServices.make(for: .review(dataset))
            #expect(ServiceLaunchLog.constructed == ["MockFeedTransport", "RecordingNotificationCenter"])
            #expect(feed() is MockFeedTransport)
            #expect(AppStore.configuration(for: .review(dataset)).isStoredInMemoryOnly)
        }
        #expect(ReviewMode.secrets is InMemorySecretStore)
        ServiceLaunchLog.reset()
    }

    @Test("Item 20: the plan dump at §43.2's clocks, from the real scheduler and planner, equals §43.2's tables")
    func planDump() async throws {
        let rig = try MoodleOnlyRig(now: F.date("2026-10-12 06:00"))
        var text = "# Notification plan — dataset moodleOnly (M = Mon 12 Oct 2026, Europe/Vienna)\n"
        text += "# Produced by MoodleReviewTests from the real NotificationScheduler and DeadlinePlanner,\n"
        text += "# rules at components.md §42.3's defaults, 900004 done, Sleep 22:00–07:00; clocks pinned.\n\n"
        let names = rig.names
        func section(_ title: String, _ plan: [PlannedNotification]) -> String {
            "== \(title)\n\n" + (plan.isEmpty ? "(nothing)\n" : NotificationPlanText.blocks(plan, names: names, calendar: F.calendar))
        }
        func due(_ plan: [PlannedNotification]) -> [PlannedNotification] { plan.filter { $0.identifier.hasPrefix("due.") } }
        let expected: [(String, [String])] = [
            ("2026-10-12 06:00", ["Sprint Review Protocol for Sprint 1 (till Tuesday 23:59 in T0 + 2) is due Tue 13 Oct 23:59",
                                  "2 deadlines on Wed 14 Oct at 12:30",
                                  "Sprint Review Protocol for Sprint 1 (till Tuesday 23:59 in T0 + 2) is due Tue 13 Oct 23:59"]),
            ("2026-11-02 06:00", ["Test Management closes Mon 2 Nov 14:20", "3 deadlines on Tue 3 Nov",
                                  "2 deadlines on Tue 3 Nov at 23:50",
                                  "Sprint Review Protocol for Sprint 2 (till Tuesday 23:59 in T0 + 4) is due Tue 3 Nov 23:59"]),
            ("2026-10-31 06:00", ["VERBINDLICHE Anmeldung für die Studienreise nach Manila | BINDING registration for study trip to Manila closes Sun 1 Nov 23:59",
                                  "Test Management closes Mon 2 Nov 14:20",
                                  "VERBINDLICHE Anmeldung für die Studienreise nach Manila | BINDING registration for study trip to Manila closes Sun 1 Nov 23:59"]),
        ]
        for (clock, titles) in expected {
            let plan = due(rig.scheduler.makePlan(now: F.date(clock)))
            text += section("\(local(F.date(clock))), ordinary pass", plan) + "\n"
            #expect(plan.map(\.text.title) == titles, "\(clock)")
        }
        for (clock, label) in [("2026-10-13 21:30", "Tue 13 Oct 21:30"), ("2026-10-13 22:30", "Tue 13 Oct 22:30"),
                               ("2026-10-14 00:30", "Wed 14 Oct 00:30")] {
            let plan = due(rig.scheduler.makePlan(now: F.date(clock), catchUp: true))
            text += section("Catch-up at \(label) (launch pass, nothing recorded)", plan) + "\n"
            if clock == "2026-10-13 21:30" {
                #expect(plan.first?.identifier == "due.day.20261014.20261013T1600Z" && plan.first?.atOnce == true)
            }
        }
        #expect(text.contains("due.day.20261014.20261013T1600Z") && text.contains("due.{900005}.ahead"))
        #expect(!F.leaks(text))
        if ProcessInfo.processInfo.environment["KADENCE_CAPTURE_DIR"].map({ !$0.isEmpty }) == true {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("kadence-captures")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data(text.utf8).write(to: directory.appendingPathComponent("notification-plan-moodle.txt"))
            Attachment.record(Data(text.utf8), named: "notification-plan-moodle.txt")
        }
    }

    private func local(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = F.zone; f.dateFormat = "EEE d MMM HH:mm"
        return f.string(from: d)
    }
}

/// Dataset `moodleOnly` at `M` = Mon 12 Oct, with a scheduler on the
/// recording centre.
@MainActor
final class MoodleOnlyRig {
    let container: ModelContainer
    let context: ModelContext
    let centre = RecordingNotificationCenter(authorization: .allowed)
    let clock: ManualTravelClock
    let scheduler: NotificationScheduler

    init(now: Date) throws {
        container = try ModelContainer(for: Schema(KadenceSchema.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
        MoodleReview.seed(context: context, now: now, m: MoodleFixture.date("2026-10-12 00:00"), zone: MoodleFixture.zone,
                          secrets: InMemorySecretStore(), withTravel: false)
        clock = ManualTravelClock(now)
        scheduler = NotificationScheduler(context: context, centre: centre, clock: clock, calendar: MoodleFixture.calendar,
                                          log: RoutingLog(category: "notifications"))
    }

    /// Event id → `900005`, for the dump's `due.{900005}.ahead`.
    var names: [String: String] {
        let events = (try? context.fetch(FetchDescriptor<Event>())) ?? []
        return Dictionary(events.compactMap { e in e.externalID.map { (e.id.uuidString, String($0.prefix(6))) } },
                          uniquingKeysWith: { a, _ in a })
    }

    func event(_ number: String) -> Event? {
        ((try? context.fetch(FetchDescriptor<Event>())) ?? []).first { $0.externalID?.hasPrefix(number + "@") == true }
    }
}
