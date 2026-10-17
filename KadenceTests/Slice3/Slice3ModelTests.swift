//
//  Slice3ModelTests.swift
//  KadenceTests
//
//  PHASE3-SLICE3-PLAN.md task 1 — G-103; components.md §42 (the slice 3
//  model additions), §27.1 (amended: the sixth rule), §33.6; tokens 1.10.0.
//  Persistence runs on a real ModelContainer (in memory, or a temporary file
//  for the slice 2 store) — never the real store.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

/// The slice 2 schema, frozen: `Event` (with `placeID`, no slice 3 field),
/// `Place`, `Source` and `NotificationRule` as the slice 2 build wrote them.
/// The nested classes keep the entity names, so a store written with them is
/// what the slice 2 build wrote for these four entities.
private enum Slice2Schema: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 2, 0)
    static var models: [any PersistentModel.Type] { [Event.self, Place.self, Source.self, NotificationRule.self] }

    @Model
    final class Place {
        var name: String
        var address: String?
        var latitude: Double?
        var longitude: Double?
        init(name: String) { self.name = name }
    }

    @Model
    final class Event {
        var id: UUID = UUID()
        var title: String = ""
        var start: Date = Date()
        var end: Date = Date()
        var isAllDay: Bool = false
        var location: Place?
        var originRaw: String = "manual"
        var statusRaw: String = "scheduled"
        var flexibilityRaw: String = "fixed"
        var sourceKeyRaw: String = "graphite"
        var sourceID: String?
        var externalID: String?
        var notes: String = ""
        var isLocked: Bool = false
        var routineLinkRaw: String = "linked"
        var isCancelled: Bool = false
        var importedDescription: String?
        var lecturers: [String] = []
        var courseCode: String?
        var group: String?
        var isOnline: Bool = false
        var importKindRaw: String = "lecture"
        var link: String?
        var placeID: String?
        init(title: String, start: Date, end: Date) {
            self.title = title; self.start = start; self.end = end
        }
    }

    @Model
    final class Source {
        var id: String = UUID().uuidString
        var kindRaw: String = "universityTimetable"
        var connectionRaw: String = "local"
        var displayName: String = "University timetable"
        var paletteKeyRaw: String = "graphite"
        var symbolOverride: String?
        var isVisible: Bool = true
        var serverURL: String?
        var username: String?
        var principalHref: String?
        var calendarHomeHref: String?
        var calendarsData: Data = Data("[]".utf8)
        var capabilitiesData: Data = Data()
        var pollInterval: Int = 1800
        var isAutoSyncPaused: Bool = false
        var importedAt: Date?
        var lastAttemptAt: Date?
        var lastSuccessAt: Date?
        var feedHash: String?
        var lastFeedEventCount: Int = 0
        var stateRaw: String = "neverSynced"
        var stateDetail: String?
        var problemsData: Data = Data("[]".utf8)
        var lastEventCount: Int = 0
        var lastChangeAt: Date?
        var lastChangeAdded: Int = 0
        var lastChangeUpdated: Int = 0
        var lastChangeRemoved: Int = 0
        init(id: String) { self.id = id }
    }

    @Model
    final class NotificationRule {
        var kindRaw: String = "leaveBy"
        var leadMinutes: Int = 0
        var isEnabled: Bool = true
        init(kindRaw: String, leadMinutes: Int, isEnabled: Bool) {
            self.kindRaw = kindRaw; self.leadMinutes = leadMinutes; self.isEnabled = isEnabled
        }
    }
}

@MainActor
struct Slice3ModelTests {

    @Test("A slice 2 store opens: events, sources and rules read back unchanged, new fields at their defaults; one launch adds the sixth rule, a second adds nothing")
    func slice2StoreOpens() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kadence-p3s3t1-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        // B52: the folder is left in the test host's temporary directory, so
        // no SwiftData fault can find its store gone.
        let url = dir.appendingPathComponent("slice2.store")

        let start = Date(timeIntervalSince1970: 1_791_000_000)
        var ids: [UUID] = []
        do {
            let old = try ModelContainer(for: Schema(versionedSchema: Slice2Schema.self),
                                         configurations: ModelConfiguration(url: url))
            let context = ModelContext(old)
            let lecture = Slice2Schema.Event(title: "SWQM-ILV", start: start, end: start + 5400)
            lecture.originRaw = "imported"; lecture.sourceKeyRaw = "blue"; lecture.statusRaw = "done"
            lecture.sourceID = "timetable"; lecture.externalID = "swqm-01"
            lecture.courseCode = "SWQM-ILV"; lecture.lecturers = ["L01"]
            let dinner = Slice2Schema.Event(title: "Dinner", start: start + 86_400, end: start + 90_000)
            dinner.placeID = "home"
            let source = Slice2Schema.Source(id: "timetable")
            source.connectionRaw = "caldav"; source.paletteKeyRaw = "blue"; source.stateRaw = "upToDate"
            source.serverURL = "https://cis.technikum-wien.at"; source.username = "user01"
            source.feedHash = "abc"; source.lastFeedEventCount = 13
            context.insert(lecture); context.insert(dinner); context.insert(source)
            for (kind, lead) in [("leaveBy", 5), ("timetableStart", 45), ("personalStart", 15),
                                 ("routineStart", 5), ("syncPaused", 0)] {
                context.insert(Slice2Schema.NotificationRule(kindRaw: kind, leadMinutes: lead, isEnabled: kind != "routineStart"))
            }
            try context.save()
            ids = [lecture.id, dinner.id]
        }

        let container = try ModelContainer(for: Schema(KadenceSchema.models),
                                           configurations: ModelConfiguration(url: url))
        let context = ModelContext(container)
        let events = try context.fetch(FetchDescriptor<Event>(sortBy: [SortDescriptor(\.start)]))
        #expect(events.map(\.id) == ids)
        let lecture = events[0], dinner = events[1]
        #expect(lecture.title == "SWQM-ILV" && lecture.origin == .imported && lecture.status == .done)
        #expect(lecture.importKind == .lecture && lecture.courseCode == "SWQM-ILV" && lecture.lecturers == ["L01"])
        #expect(dinner.placeID == "home" && dinner.origin == .manual)
        for event in events {
            #expect(event.momentWording == nil && event.upstreamTitle == nil)
            #expect(event.courseCategory == nil && event.markedDoneDueAt == nil)
        }

        let source = try #require(try context.fetch(FetchDescriptor<Source>()).first)
        #expect(source.id == "timetable" && source.connection == .caldav && source.state == .upToDate)
        #expect(source.serverURL == "https://cis.technikum-wien.at" && source.username == "user01")
        #expect(source.feedHash == "abc" && source.lastFeedEventCount == 13)
        #expect(source.feedProfile == nil && source.observedLookahead == 0 && source.emptySince == nil)

        var rules = try context.fetch(FetchDescriptor<NotificationRule>())
        #expect(rules.count == 5)
        #expect(rules.first { $0.kind == .timetableStart }?.leadMinutes == 45)
        #expect(rules.first { $0.kind == .routineStart }?.isEnabled == false)

        TravelBuiltIns.ensure(in: context)
        rules = try context.fetch(FetchDescriptor<NotificationRule>())
        #expect(rules.count == 6)
        let deadline = try #require(rules.first { $0.kind == .deadline })
        #expect(deadline.isEnabled && deadline.leadMinutes == 120)
        #expect(deadline.aheadDays == 1 && deadline.aheadMinuteOfDay == 1080 && deadline.leadEnabled)
        // The five slice 2 rules keep what the user set.
        #expect(rules.first { $0.kind == .timetableStart }?.leadMinutes == 45)
        #expect(rules.first { $0.kind == .routineStart }?.isEnabled == false)

        TravelBuiltIns.ensure(in: context)
        #expect(try context.fetchCount(FetchDescriptor<NotificationRule>()) == 6)
    }

    @Test("§42.1–§42.3: the new raw values and the defaults")
    func rawValues() {
        #expect(ImportKind.allCases.map(\.rawValue) == ["lecture", "exam", "deadline", "opening", "notice"])
        #expect(MomentWording.allCases.map(\.rawValue) == ["due", "closes", "registrationEnds", "opens"])
        #expect(SourceConnection.icsFeed.rawValue == "icsFeed")
        #expect(FeedProfile.moodle.rawValue == "moodle")
        #expect(SourceState(rawValue: "feedNotFound") == .feedNotFound)
        #expect(SourceState(rawValue: "urlMissing") == .urlMissing)
        #expect(SourceState.feedNotFound.kind == .actionable && SourceState.urlMissing.kind == .actionable)
        #expect(!SourceState.feedNotFound.pausesAutomaticSync && !SourceState.urlMissing.pausesAutomaticSync)
        #expect(NotificationRuleKind.deadline.rawValue == "deadline")
        #expect(NotificationRuleKind.deadline.settingsLabel == "Deadlines")
        #expect(NotificationRuleKind.deadline.defaultLeadMinutes == 120)
        // The other five rules keep the three new fields at their plain defaults.
        let leave = NotificationRule(kind: .leaveBy, leadMinutes: 5)
        #expect(leave.aheadDays == 0 && leave.aheadMinuteOfDay == 1080 && leave.leadEnabled)

        let event = Event(title: "x", start: .now, end: .now)
        event.importKind = .deadline
        event.momentWording = .registrationEnds
        #expect(event.importKind == .deadline && event.momentWording == .registrationEnds)
        event.momentWording = nil
        #expect(event.momentWording == nil)

        let source = Source(connection: .icsFeed)
        source.feedProfile = .moodle
        #expect(source.connection == .icsFeed && source.feedProfile == .moodle)
        source.state = .urlMissing
        #expect(source.state == .urlMissing)
    }

    @Test("A fresh launch's built-ins hold six rules, the sixth §42.3's deadline rule")
    func sixRulesInEveryLaunchKind() throws {
        for kind in [LaunchKind.testHost, .review(.empty), .review(.phase2)] {
            let container = try slice2MemoryContainer()
            AppStore.seedLaunch(kind, context: container.mainContext, now: TestClock.now,
                                secrets: InMemorySecretStore()) {}
            let rules = try container.mainContext.fetch(FetchDescriptor<NotificationRule>())
            #expect(rules.count == 6)
            #expect(Set(rules.map(\.kind)) == Set(NotificationRuleKind.allCases))
        }
    }

    @Test("Delete a Moodle event with markedDoneDueAt, undo: it is back, the mark and the Moodle fields with it")
    func markedDoneDueAtSurvivesUndo() throws {
        let container = try slice2MemoryContainer()
        let context = container.mainContext
        let undo = UndoStack()
        let store = EventStore(context: context, undo: undo)
        let due = TestClock.date("2026-10-20 12:00")
        let event = Event(title: "Submission - Sprint 3: Queuing", start: due, end: due, origin: .imported,
                          status: .done, sourceKey: .teal, sourceID: "moodle",
                          externalID: "900008@moodle.technikum-wien.at")
        event.importKind = .deadline
        event.momentWording = .due
        event.upstreamTitle = "Submission - Sprint 3: Queuing is due"
        event.courseCategory = "BIF-VZ-5-WS2026-SWEN3-EN/174462"
        event.courseCode = "SWEN3"
        event.importedDescription = "Fixture description 8."
        event.markedDoneDueAt = due
        context.insert(event)
        try context.save()
        let id = event.id

        store.delete(event)
        #expect(try context.fetchCount(FetchDescriptor<Event>()) == 0)
        undo.undo()
        let back = try #require(try context.fetch(FetchDescriptor<Event>()).first)
        #expect(back.id == id && back.status == .done && back.markedDoneDueAt == due)
        #expect(back.importKind == .deadline && back.momentWording == .due)
        #expect(back.upstreamTitle == "Submission - Sprint 3: Queuing is due")
        #expect(back.courseCategory == "BIF-VZ-5-WS2026-SWEN3-EN/174462" && back.courseCode == "SWEN3")
        #expect(back.importedDescription == "Fixture description 8.")
    }

    @Test("G-103: seedStaleCache's stamp is 18:00 by the wall clock — M = Mon 9 Nov 2026 gives Sun 25 Oct 18:00 CET")
    func staleCacheStampOnAChangeDay() {
        let vienna = TravelFixtures.calendar
        let m = TestClock.date("2026-11-09 00:00")
        let stamp = TravelDataset.staleCacheComputedAt(m: m, now: m, calendar: vienna)
        // 18:00 CET = 17:00Z (the day start + 18 h would be 17:00 CET).
        #expect(stamp == ISO8601DateFormatter().date(from: "2026-10-25T17:00:00Z"))
        let parts = vienna.dateComponents([.year, .month, .day, .hour, .minute], from: stamp)
        #expect(parts.month == 10 && parts.day == 25 && parts.hour == 18 && parts.minute == 0)
        // An ordinary day is unchanged: M = Mon 12 Oct → Sun 27 Sep 18:00 CEST.
        let before = TravelDataset.staleCacheComputedAt(m: TestClock.date("2026-10-12 00:00"),
                                                        now: TestClock.date("2026-10-12 06:00"), calendar: vienna)
        #expect(before == TestClock.date("2026-09-27 18:00"))
    }

    @Test("Tokens 1.10.0: allDayTime with monospaced digits; popoverMaxDueRows 3 and inspectorDescriptionMaxLines 6 as Int")
    func tokens() throws {
        #expect(Tokens.Typography.AllDayTime.monospacedDigit)
        #expect(Tokens.Typography.AllDayTime.size == 11)
        #expect(Tokens.Typography.AllDayTime.weight == "regular")
        #expect(Tokens.Typography.AllDayTime.textStyle == "subheadline")
        #expect(Tokens.Typography.AllDayTime.lineLimit == 1)
        #expect(TypeStyle.allDayTime.monospacedDigit)
        let rows: Int = Tokens.Size.popoverMaxDueRows
        let lines: Int = Tokens.Size.inspectorDescriptionMaxLines
        #expect(rows == 3 && lines == 6)
        let json = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: Fixture.repoRoot.appendingPathComponent("design/tokens.json"))) as? [String: Any])
        let meta = try #require(json["$meta"] as? [String: Any])
        #expect(meta["version"] as? String == "1.10.0")
    }

    @Test("DEVIATIONS.md has the slice 3 heading")
    func deviationsHeading() throws {
        let text = try String(contentsOf: Fixture.repoRoot.appendingPathComponent("DEVIATIONS.md"), encoding: .utf8)
        #expect(text.contains("\n## Phase 3 slice 3 — Moodle deadlines (2026-10-16)\n"))
    }
}
