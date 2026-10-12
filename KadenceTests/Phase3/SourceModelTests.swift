//
//  SourceModelTests.swift
//  KadenceTests
//
//  PHASE3-PLAN.md task 1: `Source` (components.md §21.1), the `Event`
//  additions (§21.3), and tokens 1.6.0. Persistence runs on a real
//  ModelContainer (in memory, or a temporary file for the Phase 2 store).
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

/// The test sentinel password (PHASE3-PLAN.md common rules). Defined here, used
/// only in this file.
private let sentinel = "S3ntinel-pw-⚠"

/// The Phase 2 schema, frozen: `Event` and `Place` as they were at `dfcc9c8`,
/// before task 1 added fields. Swift note: a `VersionedSchema` is SwiftData's
/// way to name an older shape of the same entities; the nested classes keep
/// the entity names `Event` / `Place`, so a store written with them is exactly
/// what the Phase 2 build wrote.
private enum Phase2Schema: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] { [Event.self, Place.self] }

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
        init(title: String, start: Date, end: Date) {
            self.title = title; self.start = start; self.end = end
        }
    }
}

@MainActor
private func memoryContainer() throws -> ModelContainer {
    try ModelContainer(for: Schema(KadenceSchema.models),
                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
}

@MainActor
struct SourceModelTests {

    @Test("A Phase 2 store opens; every event reads back unchanged with the new fields at their defaults")
    func phase2StoreOpens() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kadence-p3t1-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("phase2.store")

        let start = Date(timeIntervalSince1970: 1_791_000_000)
        var ids: [UUID] = []
        do {
            let old = try ModelContainer(for: Schema(versionedSchema: Phase2Schema.self),
                                         configurations: ModelConfiguration(url: url))
            let context = ModelContext(old)
            let lecture = Phase2Schema.Event(title: "Datenmodellierung", start: start, end: start + 5400)
            lecture.originRaw = "imported"; lecture.sourceKeyRaw = "blue"
            lecture.sourceID = "timetable"; lecture.externalID = "dm-lecture-01"
            lecture.statusRaw = "done"; lecture.notes = "bring laptop"
            lecture.location = Phase2Schema.Place(name: "FH B.2.09")
            let gym = Phase2Schema.Event(title: "Gym", start: start + 86_400, end: start + 90_000)
            gym.originRaw = "routine"; gym.flexibilityRaw = "shiftable"; gym.routineLinkRaw = "detached"
            gym.isLocked = true
            context.insert(lecture); context.insert(gym)
            try context.save()
            ids = [lecture.id, gym.id]
        }

        let container = try ModelContainer(for: Schema(KadenceSchema.models),
                                           configurations: ModelConfiguration(url: url))
        let events = try ModelContext(container).fetch(FetchDescriptor<Event>(sortBy: [SortDescriptor(\.start)]))
        #expect(events.map(\.id) == ids)
        let lecture = try #require(events.first)
        #expect(lecture.title == "Datenmodellierung")
        #expect(lecture.start == start && lecture.end == start + 5400)
        #expect(lecture.origin == .imported && lecture.status == .done && lecture.sourceKey == .blue)
        #expect(lecture.sourceID == "timetable" && lecture.externalID == "dm-lecture-01")
        #expect(lecture.notes == "bring laptop" && lecture.location?.name == "FH B.2.09")
        let gym = events[1]
        #expect(gym.origin == .routine && gym.flexibility == .shiftable && gym.routineLink == .detached && gym.isLocked)
        for event in events {
            #expect(event.isCancelled == false)
            #expect(event.importedDescription == nil)
            #expect(event.lecturers.isEmpty)
            #expect(event.courseCode == nil && event.group == nil && event.link == nil)
            #expect(event.isOnline == false)
            #expect(event.importKind == .lecture)
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<Source>()) == 0)
    }

    @Test("paletteKey: the first unused slot in palette order, never graphite (amended 2026-10-10, G-075)")
    func paletteKeyAssignment() {
        #expect(Source.paletteKeyForNewSource(existing: []) == .blue)
        #expect(Source.paletteKeyForNewSource(existing: [.blue]) == .teal)
        #expect(Source.paletteKeyForNewSource(existing: [.teal, .blue, .amber]) == .green)
        let allButPurple = SourceKey.allCases.filter { $0 != .purple && $0 != .graphite }
        #expect(Source.paletteKeyForNewSource(existing: allButPurple) == .purple)
        // All eight used: the least-used of the seven, the earliest on a tie —
        // not graphite, which was the old fallback (SourceIdentityTests).
        #expect(Source.paletteKeyForNewSource(existing: SourceKey.allCases) == .blue)
        // The order is tokens.json's color.sourcePalette.order.
        #expect(SourceKey.allCases.map(\.rawValue) ==
                ["blue", "teal", "green", "amber", "orange", "pink", "purple", "graphite"])
    }

    @Test("Source round-trips every field, including the three JSON fields")
    func roundTrip() throws {
        let container = try memoryContainer()
        let source = Source(id: "s-1", kind: .universityTimetable, connection: .caldav,
                            displayName: "University timetable", paletteKey: .blue,
                            symbolOverride: "star", isVisible: false)
        let date = Date(timeIntervalSince1970: 1_791_454_967)
        source.serverURL = "https://cis.technikum-wien.at"
        source.username = "user01"
        source.principalHref = "/webdav/lvplan.php/principals/user01/"
        source.calendarHomeHref = "/webdav/lvplan.php/calendars/user01/"
        source.calendars = [SourceCalendar(href: "/webdav/lvplan.php/calendars/user01/LVPlan-user01/", displayName: "LVPlan"),
                            SourceCalendar(href: "/webdav/lvplan.php/calendars/user01/Pruefungen-user01/", displayName: "Prüfungen")]
        source.capabilities = SourceCapabilities(fetchMode: .multiget, timeRangeHonoured: false, discoveredAt: date)
        source.pollInterval = 3600
        source.isAutoSyncPaused = true
        source.importedAt = date
        source.lastAttemptAt = date + 1
        source.lastSuccessAt = date + 2
        source.feedHash = "abc123"
        source.lastFeedEventCount = 13
        source.state = .partialImport
        source.stateDetail = "1 of 13 events couldn't be read and were skipped. Nothing was removed."
        source.problems = [ImportProblem(line: 9, sentence: "1 event couldn't be read", technical: "Object obj-07.ics, line 9: DTEND before DTSTART")]
        source.lastEventCount = 12
        source.lastChangeAt = date + 3
        source.lastChangeAdded = 2
        source.lastChangeUpdated = 2
        source.lastChangeRemoved = 1
        let context = ModelContext(container)
        context.insert(source)
        try context.save()

        let read = try #require(try ModelContext(container).fetch(FetchDescriptor<Source>()).first)
        #expect(read.id == "s-1")
        #expect(read.kind == .universityTimetable && read.connection == .caldav)
        #expect(read.displayName == "University timetable" && read.paletteKey == .blue)
        #expect(read.symbolOverride == "star" && read.isVisible == false)
        #expect(read.serverURL == "https://cis.technikum-wien.at" && read.username == "user01")
        #expect(read.principalHref == "/webdav/lvplan.php/principals/user01/")
        #expect(read.calendarHomeHref == "/webdav/lvplan.php/calendars/user01/")
        #expect(read.calendars == source.calendars)
        #expect(read.capabilities == SourceCapabilities(fetchMode: .multiget, timeRangeHonoured: false, discoveredAt: date))
        #expect(read.pollInterval == 3600 && read.isAutoSyncPaused)
        #expect(read.importedAt == date && read.lastAttemptAt == date + 1 && read.lastSuccessAt == date + 2)
        #expect(read.feedHash == "abc123" && read.lastFeedEventCount == 13)
        #expect(read.state == .partialImport && read.stateDetail == source.stateDetail)
        #expect(read.problems == source.problems)
        #expect(read.lastEventCount == 12 && read.lastChangeAt == date + 3)
        #expect(read.lastChangeAdded == 2 && read.lastChangeUpdated == 2 && read.lastChangeRemoved == 1)
    }

    @Test("A new Source has §21.1's defaults")
    func defaults() {
        let source = Source()
        #expect(source.pollInterval == 1800)
        #expect(source.connection == .local)
        #expect(source.calendars.isEmpty && source.problems.isEmpty)
        #expect(source.capabilities.fetchMode == .report && source.capabilities.timeRangeHonoured == nil)
        #expect(source.state == .neverSynced)
        #expect(source.isAutoSyncPaused == false && source.feedHash == nil)
    }

    /// §21.1's table, with each enum or JSON field under its stored column name.
    private static let allowList: Set<String> = [
        "id", "kindRaw", "connectionRaw", "displayName", "paletteKeyRaw", "symbolOverride",
        "isVisible", "serverURL", "username", "principalHref", "calendarHomeHref",
        "calendarsData", "capabilitiesData", "pollInterval", "isAutoSyncPaused", "importedAt",
        "lastAttemptAt", "lastSuccessAt", "feedHash", "lastFeedEventCount", "stateRaw",
        "stateDetail", "problemsData", "lastEventCount", "lastChangeAt", "lastChangeAdded",
        "lastChangeUpdated", "lastChangeRemoved",
    ]

    @Test("Source's stored properties are exactly §21.1's table — no password, href-per-object, ETag or ctag column")
    func storedPropertiesAllowList() throws {
        let entity = try #require(Schema([Source.self]).entitiesByName["Source"])
        let stored = Set(entity.attributes.map(\.name)).union(entity.relationships.map(\.name))
        #expect(stored == Self.allowList)
        for name in stored {
            let lower = name.lowercased()
            #expect(!lower.contains("password") && !lower.contains("secret") && !lower.contains("etag")
                    && !lower.contains("ctag") && !lower.contains("token") && !lower.contains("credential"))
        }
    }

    @Test("A Source built during a connect that used the sentinel password holds no substring of it")
    func noPasswordInStoredValues() throws {
        // The connect flow's inputs: the password exists alongside, and the
        // factory has no parameter that could take it.
        let password = sentinel
        let container = try memoryContainer()
        let source = Source.connected(
            displayName: "University timetable", serverURL: "https://cis.technikum-wien.at",
            username: "user01", principalHref: "/webdav/lvplan.php/principals/user01/",
            calendarHomeHref: "/webdav/lvplan.php/calendars/user01/",
            calendars: [SourceCalendar(href: "/webdav/lvplan.php/calendars/user01/LVPlan-user01/", displayName: "LVPlan")],
            capabilities: SourceCapabilities(fetchMode: .report, timeRangeHonoured: true, discoveredAt: .now),
            paletteKey: .blue)
        let context = ModelContext(container)
        context.insert(source)
        try context.save()
        let read = try #require(try ModelContext(container).fetch(FetchDescriptor<Source>()).first)
        let values: [String] = [
            read.id, read.kind.rawValue, read.connection.rawValue, read.displayName,
            read.paletteKey.rawValue, read.symbolOverride ?? "", read.serverURL ?? "", read.username ?? "",
            read.principalHref ?? "", read.calendarHomeHref ?? "",
            String(decoding: try JSONEncoder().encode(read.calendars), as: UTF8.self),
            String(decoding: try JSONEncoder().encode(read.capabilities), as: UTF8.self),
            String(decoding: try JSONEncoder().encode(read.problems), as: UTF8.self),
            read.feedHash ?? "", read.state.rawValue, read.stateDetail ?? "",
            String(describing: read.importedAt), String(describing: read.lastAttemptAt),
        ]
        // Every non-trivial substring of the password, down to 4 characters.
        let chars = Array(password)
        for length in 4...chars.count {
            for offset in 0...(chars.count - length) {
                let piece = String(chars[offset..<(offset + length)])
                #expect(!values.contains { $0.contains(piece) }, "a stored value contains part of the password")
            }
        }
    }

    @Test("accountDisplay is `user01 @ cis.technikum-wien.at`")
    func accountDisplay() {
        let source = Source(connection: .caldav)
        source.serverURL = "https://cis.technikum-wien.at"
        source.username = "user01"
        #expect(source.accountDisplay == "user01 @ cis.technikum-wien.at")
        #expect(source.host == "cis.technikum-wien.at")
        #expect(Source().accountDisplay == nil)
    }

    @Test("Tokens 1.6.0: inspectorLecturersMaxRows is an Int; the connect sheet's calendar rows")
    func tokens() {
        // Swift note: `type(of:)` gives the static type of the constant; the
        // check fails to compile-or-run if the generator emitted CGFloat.
        #expect(type(of: Tokens.Size.inspectorLecturersMaxRows) == Int.self)
        #expect(Tokens.Size.inspectorLecturersMaxRows == 4)
        #expect(Tokens.Size.connectCalendarRowHeight == 24)
        #expect(Tokens.Size.connectCalendarListMaxHeight == 144)
    }

    @Test("Mock sources are seeded as local Source records once, with their slots")
    func mockSourcesSeeded() throws {
        let container = try memoryContainer()
        let context = ModelContext(container)
        MockData.seedSourcesIfNeeded(context)
        MockData.seedSourcesIfNeeded(context)
        let sources = try context.fetch(FetchDescriptor<Source>())
        #expect(sources.count == MockData.sources.count)
        let timetable = try #require(sources.first { $0.id == "timetable" })
        #expect(timetable.paletteKey == .blue && timetable.displayName == "University timetable")
        #expect(sources.allSatisfy { $0.connection == .local })
    }
}
