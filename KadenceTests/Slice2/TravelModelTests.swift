//
//  TravelModelTests.swift
//  KadenceTests
//
//  PHASE3-SLICE2-PLAN.md task 1 — components.md §28 (the slice 2 models),
//  §23.1 / §23.6 (the built-in places), §27.1 (the five rules), §28.2
//  (`Event.placeID`), tokens 1.9.0, and the DEVIATIONS entries A41 / A42.
//  Persistence runs on a real ModelContainer (in memory, or a temporary file
//  for the slice 1 store) — never the real store.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

/// The slice 1 schema, frozen: `Event` as the slice 1 build wrote it (every
/// Phase 3 field, no `placeID`), `Place` and `Source` — the entity set before
/// task 1 added seven models. The nested classes keep the entity names, so a
/// store written with them is what the slice 1 build wrote.
private enum Slice1Schema: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 1, 0)
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
        var isCancelled: Bool = false
        var importedDescription: String?
        var lecturers: [String] = []
        var courseCode: String?
        var group: String?
        var isOnline: Bool = false
        var importKindRaw: String = "lecture"
        var link: String?
        init(title: String, start: Date, end: Date) {
            self.title = title; self.start = start; self.end = end
        }
    }
}

@MainActor
func slice2MemoryContainer() throws -> ModelContainer {
    try ModelContainer(for: Schema(KadenceSchema.models),
                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
}

@MainActor
struct TravelModelTests {

    @Test("A slice 1 store opens; events read back unchanged with placeID nil; no slice 2 row until the built-ins run")
    func slice1StoreOpens() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("kadence-p3s2t1-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("slice1.store")

        let start = Date(timeIntervalSince1970: 1_791_000_000)
        var ids: [UUID] = []
        do {
            let old = try ModelContainer(for: Schema(versionedSchema: Slice1Schema.self),
                                         configurations: ModelConfiguration(url: url))
            let context = ModelContext(old)
            let lecture = Slice1Schema.Event(title: "SWQM-ILV", start: start, end: start + 5400)
            lecture.originRaw = "imported"; lecture.sourceKeyRaw = "blue"
            lecture.sourceID = "timetable"; lecture.externalID = "swqm-01"
            lecture.courseCode = "SWQM-ILV"; lecture.lecturers = ["L01", "L02"]
            lecture.location = Slice1Schema.Place(name: "HS_A3.15")
            let dinner = Slice1Schema.Event(title: "Dinner", start: start + 86_400, end: start + 90_000)
            dinner.statusRaw = "done"; dinner.notes = "bring wine"
            context.insert(lecture); context.insert(dinner)
            try context.save()
            ids = [lecture.id, dinner.id]
        }

        let container = try ModelContainer(for: Schema(KadenceSchema.models),
                                           configurations: ModelConfiguration(url: url))
        let context = ModelContext(container)
        let events = try context.fetch(FetchDescriptor<Event>(sortBy: [SortDescriptor(\.start)]))
        #expect(events.map(\.id) == ids)
        #expect(events[0].title == "SWQM-ILV" && events[0].origin == .imported && events[0].courseCode == "SWQM-ILV")
        #expect(events[0].lecturers == ["L01", "L02"] && events[0].location?.name == "HS_A3.15")
        #expect(events[1].status == .done && events[1].notes == "bring wine")
        #expect(events.allSatisfy { $0.placeID == nil })
        #expect(try context.fetchCount(FetchDescriptor<TravelLeg>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<TravelETACache>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<NotificationRecord>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<KnownPlace>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<AppSettings>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<NotificationRule>()) == 0)

        TravelBuiltIns.ensure(in: context)
        #expect(try context.fetchCount(FetchDescriptor<KnownPlace>()) == 2)
        #expect(try context.fetchCount(FetchDescriptor<TravelLeg>()) == 0)
    }

    @Test("Built-ins: two launches leave 2 places, 1 settings row, 5 rules — §28.1 / §27.1 defaults; campus has no coordinate")
    func builtIns() throws {
        let container = try slice2MemoryContainer()
        let context = container.mainContext
        AppStore.seedLaunch(.testHost, context: context, now: TestClock.now, secrets: InMemorySecretStore()) {}
        AppStore.seedLaunch(.testHost, context: context, now: TestClock.now, secrets: InMemorySecretStore()) {}

        let places = try context.fetch(FetchDescriptor<KnownPlace>(sortBy: [SortDescriptor(\.sortIndex)]))
        #expect(places.map(\.id) == ["home", "campus"])
        #expect(places.map(\.name) == ["Home", "FH Technikum Wien"])
        #expect(places.allSatisfy { $0.isBuiltIn })
        let home = places[0], campus = places[1]
        #expect(home.addressText == nil && home.geocodeState == .none && home.latitude == nil && home.longitude == nil)
        #expect(campus.addressText == "Höchstädtplatz 6, 1200 Wien")
        #expect(campus.geocodeState == .unconfirmed)
        #expect(campus.latitude == nil && campus.longitude == nil && campus.confirmedAddress == nil)

        let settings = try context.fetch(FetchDescriptor<AppSettings>())
        #expect(settings.count == 1)
        let s = try #require(settings.first)
        #expect(s.id == "app")
        #expect(s.preferredTravelMode == .transit && s.travelBufferMinutes == 10 && s.travelChainGapMinutes == 120)
        #expect(s.useCurrentLocation)
        #expect(s.locationRequestedAt == nil && s.campusLookupAttemptedAt == nil && s.notificationsRequestedAt == nil)

        let rules = try context.fetch(FetchDescriptor<NotificationRule>())
        #expect(rules.count == 5)
        let byKind = Dictionary(uniqueKeysWithValues: rules.map { ($0.kind, $0) })
        #expect(byKind[.leaveBy]?.leadMinutes == 5)
        #expect(byKind[.timetableStart]?.leadMinutes == 30)
        #expect(byKind[.personalStart]?.leadMinutes == 15)
        #expect(byKind[.routineStart]?.leadMinutes == 5)
        #expect(byKind[.syncPaused]?.leadMinutes == 0)
        #expect(rules.allSatisfy { $0.isEnabled })
    }

    @Test("Built-ins in every launch kind, and a store with four rules gains syncPaused without touching the others")
    func builtInsEveryKindAndFifthRule() throws {
        for kind in [LaunchKind.testHost, .review(.empty), .review(.phase2)] {
            let container = try slice2MemoryContainer()
            AppStore.seedLaunch(kind, context: container.mainContext, now: TestClock.now,
                                secrets: InMemorySecretStore()) {}
            #expect(try container.mainContext.fetchCount(FetchDescriptor<KnownPlace>()) >= 2)
            #expect(try container.mainContext.fetchCount(FetchDescriptor<NotificationRule>()) == 5)
        }

        let container = try slice2MemoryContainer()
        let context = container.mainContext
        for kind in [NotificationRuleKind.leaveBy, .timetableStart, .personalStart, .routineStart] {
            context.insert(NotificationRule(kind: kind, leadMinutes: 10, isEnabled: false))
        }
        try context.save()
        TravelBuiltIns.ensure(in: context)
        let rules = try context.fetch(FetchDescriptor<NotificationRule>())
        #expect(rules.count == 5)
        #expect(rules.filter { $0.kind != .syncPaused }.allSatisfy { $0.leadMinutes == 10 && !$0.isEnabled })
        #expect(rules.first { $0.kind == .syncPaused }?.isEnabled == true)
    }

    @Test("KnownPlace: latitude and longitude are both set or both nil; a write of one alone is refused")
    func coordinatePair() throws {
        let place = KnownPlace(name: "Gym")
        #expect(place.setCoordinate(latitude: 48.2, longitude: nil) == false)
        #expect(place.latitude == nil && place.longitude == nil)
        #expect(place.setCoordinate(latitude: nil, longitude: 16.3) == false)
        #expect(place.latitude == nil && place.longitude == nil)
        #expect(place.setCoordinate(latitude: 48.205, longitude: 16.395))
        #expect(place.latitude == 48.205 && place.longitude == 16.395)
        #expect(place.setCoordinate(latitude: 48.0, longitude: nil) == false)
        #expect(place.latitude == 48.205 && place.longitude == 16.395)
        #expect(place.setCoordinate(latitude: nil, longitude: nil))
        #expect(!place.hasCoordinate)
    }

    @Test("TravelModeOverride stores its pair sorted; a second override for the same pair, either order, is refused")
    func overridePair() throws {
        let container = try slice2MemoryContainer()
        let context = container.mainContext
        let row = try #require(TravelModeOverrides.insert("home", "gym-1", mode: .walking, in: context))
        #expect(row.placeA == "gym-1" && row.placeB == "home")
        #expect(TravelModeOverrides.insert("home", "gym-1", mode: .driving, in: context) == nil)
        #expect(TravelModeOverrides.insert("gym-1", "home", mode: .driving, in: context) == nil)
        #expect(TravelModeOverrides.insert("home", "home", mode: .walking, in: context) == nil)
        let rows = try context.fetch(FetchDescriptor<TravelModeOverride>())
        #expect(rows.count == 1 && rows.first?.mode == .walking)
        #expect(TravelModeOverride("b", "a", mode: .transit).placeA == "a")
    }

    @Test("Delete a manual event with a placeID, undo: placeID is back. Duplicate copies it")
    func placeIDSurvivesUndoAndDuplicate() throws {
        let container = try slice2MemoryContainer()
        let context = container.mainContext
        let undo = UndoStack()
        let store = EventStore(context: context, undo: undo)
        let start = TestClock.date("2026-10-15 18:30")
        let event = Event(title: "Dinner with flatmates", start: start, end: start + 5400, sourceID: "personal")
        event.placeID = "home"
        context.insert(event)
        try context.save()
        let id = event.id

        store.delete(event)
        #expect(try context.fetchCount(FetchDescriptor<Event>()) == 0)
        undo.undo()
        let back = try #require(try context.fetch(FetchDescriptor<Event>()).first)
        #expect(back.id == id && back.placeID == "home")

        let copy = store.duplicate(back, at: start + 86_400)
        #expect(copy.placeID == "home" && copy.id != id)
    }

    @Test("Tokens 1.9.0: the address match row 36, the list 180; settingsMinutesFieldWidth retired")
    func tokens() throws {
        #expect(Tokens.Size.settingsAddressMatchRowHeight == 36)
        #expect(Tokens.Size.settingsAddressMatchListMaxHeight == 180)
        #expect(Tokens.Size.settingsPlaceNameFieldWidth == 160)
        let generated = try String(contentsOf: Fixture.repoRoot.appendingPathComponent("Kadence/DesignSystem/Tokens.swift"),
                                   encoding: .utf8)
        #expect(!generated.contains("settingsMinutesFieldWidth"))
    }

    @Test("TravelMode: transit / walking / driving only, Settings order and §23.3's labels")
    func travelModes() {
        #expect(TravelMode.allCases.map(\.rawValue) == ["transit", "walking", "driving"])
        #expect(TravelMode.allCases.map(\.settingsLabel) == ["Public transport", "Walking", "Driving"])
        #expect(TravelMode.allCases.map(\.copyPhrase) == ["by public transport", "walking", "driving"])
        #expect(TravelMode.allCases.map(\.glyph) == ["tram.fill", "figure.walk", "car.fill"])
    }

    @Test("DEVIATIONS.md logs A41 and A42 under the slice 2 heading")
    func deviations() throws {
        let text = try String(contentsOf: Fixture.repoRoot.appendingPathComponent("DEVIATIONS.md"), encoding: .utf8)
        let heading = "## Phase 3 slice 2 — leave-by and notifications (2026-10-14)"
        let range = try #require(text.range(of: heading))
        let after = text[range.upperBound...]
        #expect(after.contains("A41"))
        #expect(after.contains("A42"))
    }
}
