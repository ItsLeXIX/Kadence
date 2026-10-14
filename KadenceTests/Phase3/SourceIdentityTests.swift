//
//  SourceIdentityTests.swift
//  KadenceTests
//
//  PHASE3-REVIEW.md fix 2 — components.md §21.1, §21.1.1; layouts.md §2.1,
//  §6.1; tokens.json `sourcePalette.assignmentRule` (GAPS G-075).
//
//  The regression: Parsa's real lectures drew grey, read `Personal · {room}`
//  and showed the person glyph, because a source was looked up by palette slot
//  and the timetable shared `graphite` with `Personal`. These tests rebuild
//  that store from `fixtures/cis-2026WS-redacted.ics` (`reportCIS`).
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

@MainActor
@Suite(.serialized)
struct SourceIdentityTests {

    private func memory() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(KadenceSchema.models),
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    /// The two built-ins, `extra` sources, then a timetable on `slot`
    /// imported from `reportCIS` (the real export, one VEVENT per object).
    private func store(timetableSlot slot: SourceKey, extra: [Source] = [],
                       context: ModelContext? = nil) throws -> (ModelContext, Source) {
        let context = try context ?? memory()
        BuiltInSource.ensure(in: context)
        for source in extra { context.insert(source) }
        let timetable = Source.connected(
            id: "tt-1", displayName: "University timetable", serverURL: "https://cis.technikum-wien.at",
            username: "user01", principalHref: nil, calendarHomeHref: nil,
            calendars: [ReviewMode.calendar], capabilities: SourceCapabilities(), paletteKey: slot)
        context.insert(timetable)
        try context.save()
        let result = ReviewMode.fetchResult(of: MockHarness.reportCIS(), now: TestClock.now, zone: TestClock.zone)
        ReviewMode.importFetched(result, into: timetable, context: context, now: TestClock.now, zone: TestClock.zone)
        return (context, timetable)
    }

    private func directory(_ context: ModelContext, slotFallback: Bool = false) throws -> SourceDirectory {
        SourceDirectory(try context.fetch(FetchDescriptor<Source>()), allowsSlotFallback: slotFallback)
    }

    // MARK: The regression (§6.1 of the review)

    @Test("Imported events name their own source when another source shares its slot", arguments: [
        SourceKey.graphite,   // Parsa's store: the timetable on Personal's slot
        .green,               // …or on Daily routine's
        .blue,                // …or on a second source placed there on purpose
    ])
    func importedEventsResolveByID(_ slot: SourceKey) throws {
        // A second source deliberately placed on the timetable's slot, with a
        // name and id that sort before it, so a lookup by slot finds it first.
        let decoy = Source(id: "a-decoy", kind: .other, connection: .local, displayName: "Another source", paletteKey: slot)
        let (context, timetable) = try store(timetableSlot: slot, extra: [decoy])
        let sources = try directory(context)
        let events = try context.fetch(FetchDescriptor<Event>())
        #expect(events.count == 12)
        for event in events {
            #expect(event.origin == .imported && event.sourceID == timetable.id)
            let model = GridBlockModel(event: event, now: TestClock.now, sources: sources)
            #expect(model.sourceName == "University timetable")
            #expect(model.source == slot)
            // The `.full` meta line, hover help and the spoken label.
            #expect(model.metaLine.contains("University timetable"))
            #expect(!model.metaLine.contains("Personal") && !model.metaLine.contains("Another source"))
            #expect(model.hoverHelp.contains("· University timetable ·"))
            #expect(model.accessibilityLabel(presentation: []).contains("University timetable"))
            #expect(!model.accessibilityLabel(presentation: []).contains("Personal"))
            // The inspector: title swatch and Source row (layouts.md §6.1).
            let inspector = InspectorSourceModel(event: event, sources: sources)
            #expect(inspector.name == "University timetable")
            #expect(inspector.symbol == "tablecells.fill")
            #expect(inspector.symbol != "person.fill")
            #expect(inspector.key == slot)
            #expect(InspectorView.sourceRowName(for: event, sources: sources) == "University timetable")
            #expect(ImportedInspectorCopy.readOnlyLine(sourceName: inspector.name, isCancelled: false)
                    == "Read-only — from University timetable")
        }
        // The same holds with review mode's slot fallback on: an id always wins.
        let review = try directory(context, slotFallback: true)
        #expect(events.allSatisfy { review.info(for: $0).id == timetable.id })
    }

    @Test("Events without a sourceID resolve by origin: manual → Personal, routine → Daily routine")
    func builtInsByOrigin() throws {
        let (context, _) = try store(timetableSlot: .graphite)
        let sources = try directory(context)
        let day = TestClock.date("2026-10-08 12:00")
        let manual = Event(title: "Dentist", start: day, end: day.addingTimeInterval(3600), origin: .manual)
        // A routine instance's sourceID is its template's id (§13.6), which no Source carries.
        let routine = Event(title: "Gym", start: day, end: day.addingTimeInterval(3600), origin: .routine,
                            sourceKey: .green, sourceID: UUID().uuidString, externalID: "x#1")
        #expect(sources.info(for: manual).id == "personal")
        #expect(InspectorSourceModel(event: manual, sources: sources).symbol == "person.fill")
        #expect(GridBlockModel(event: manual, now: day, sources: sources).sourceName == "Personal")
        #expect(sources.info(for: routine).id == "routine")
        #expect(GridBlockModel(event: routine, now: day, sources: sources).sourceName == "Daily routine")
        #expect(InspectorSourceModel(event: routine, sources: sources).symbol == "rectangle.stack.fill")
    }

    @Test("⌘N's event carries `personal` from creation")
    func manualEventsCarryPersonal() throws {
        let context = try memory()
        BuiltInSource.ensure(in: context)
        let store = EventStore(context: context, undo: UndoStack())
        let day = TestClock.date("2026-10-08 12:00")
        var draft = EventDraft(start: day, end: day.addingTimeInterval(3600))
        draft.title = "Dentist"
        let event = try #require(store.commit(draft))
        #expect(event.sourceID == "personal" && event.sourceKey == .graphite && event.origin == .manual)
        #expect(try directory(context).info(for: event).name == "Personal")
    }

    // MARK: The palette (§21.1; tokens.json assignmentRule)

    @Test("A connected source never takes graphite: first free of the seven, else the least used, ties earlier")
    func paletteRule() {
        let seven: [SourceKey] = [.blue, .teal, .green, .amber, .orange, .pink, .purple]
        #expect(Source.paletteKeyForNewSource(existing: []) == .blue)
        #expect(Source.paletteKeyForNewSource(existing: [.graphite, .green]) == .blue)   // a real first connection
        #expect(Source.paletteKeyForNewSource(existing: [.graphite, .green, .blue]) == .teal)
        #expect(Source.paletteKeyForNewSource(existing: seven) == .blue)                  // all used once: the earliest
        #expect(Source.paletteKeyForNewSource(existing: seven + [.graphite]) == .blue)    // Parsa's store on 9 Oct
        #expect(Source.paletteKeyForNewSource(existing: seven + [.blue, .teal]) == .green)
        #expect(Source.paletteKeyForNewSource(existing: seven + seven.filter { $0 != .pink }) == .pink)
        for used in [[], seven, seven + [.graphite], seven + seven, SourceKey.allCases + SourceKey.allCases] {
            #expect(Source.paletteKeyForNewSource(existing: used) != .graphite)
        }
        // The rule in tokens.json says the same.
        #expect(Tokens.Color.SourcePalette.assignmentRule.contains("never assigned to a connected source"))
    }

    @Test("An Import into a store whose seven non-graphite slots are all used does not take graphite")
    func importIntoAFullPalette() throws {
        // The Phase 2 dataset's eight sources: every slot taken, as on 9 Oct.
        let context = try memory()
        MockData.seedSourcesIfNeeded(context)
        #expect(Set(try context.fetch(FetchDescriptor<Source>()).map(\.paletteKey)) == Set(SourceKey.allCases))
        ReviewMode.seedFresh(context: context, now: TestClock.now, secrets: InMemorySecretStore(), zone: TestClock.zone)
        let timetable = try #require(try context.fetch(FetchDescriptor<Source>()).first { $0.isConnected })
        #expect(timetable.paletteKey != .graphite)
        #expect(timetable.paletteKey == .blue)
        // …and its lectures are still its own, though the mock timetable holds blue too.
        let sources = try directory(context)
        let lectures = try context.fetch(FetchDescriptor<Event>()).filter { $0.origin == .imported }
        #expect(lectures.count == 13)
        #expect(lectures.allSatisfy { sources.info(for: $0).id == timetable.id })
    }

    // MARK: Visibility (§21.1.1)

    @Test("Unchecking Personal hides manual events and no imported one — and survives a relaunch")
    func visibilityIsTheRecordsAndPersists() throws {
        // A store on disk, in this test's own temporary folder (never the app's).
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("kadence-fix2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        // P3S2-T13: the folder is left for the process, not removed here.
        // SwiftData can still fault this store's objects on a timer after the
        // test returns; with the file gone that fault traps the test host
        // (seen once slice 2's suites made the run longer). The test host's
        // temporary directory is the sandbox's own and is cleared by macOS.
        let url = folder.appendingPathComponent("test.store")
        #expect(url != AppStore.realStoreURL)
        let schema = Schema(KadenceSchema.models)
        let day = TestClock.date("2026-10-08 12:00")
        do {
            let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
            // The timetable on Personal's slot: the worst case for a slot lookup.
            let (context, _) = try store(timetableSlot: .graphite, context: ModelContext(container))
            context.insert(Event(title: "Dentist", start: day, end: day.addingTimeInterval(3600), origin: .manual,
                                 sourceID: "personal"))
            let personal = try #require(try context.fetch(FetchDescriptor<Source>()).first { $0.id == "personal" })
            personal.isVisible = false      // the sidebar checkbox's write
            try context.save()
        }
        // "Relaunch": a new container on the same file.
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, url: url))
        let context = ModelContext(container)
        let records = try context.fetch(FetchDescriptor<Source>())
        #expect(records.first { $0.id == "personal" }?.isVisible == false)
        #expect(records.filter { $0.id != "personal" }.allSatisfy { $0.isVisible })
        let sources = SourceDirectory(records)
        let state = CalendarState()
        let events = try context.fetch(FetchDescriptor<Event>())
        let imported = events.filter { $0.origin == .imported }
        #expect(imported.count == 12)
        #expect(imported.allSatisfy { state.isVisible($0, sources: sources) })
        let manual = try #require(events.first { $0.origin == .manual })
        #expect(!state.isVisible(manual, sources: sources))
        // Unchecking the timetable hides the lectures and not the manual event.
        records.first { $0.id == "personal" }?.isVisible = true
        records.first { $0.isConnected }?.isVisible = false
        let flipped = SourceDirectory(records)
        #expect(imported.allSatisfy { !state.isVisible($0, sources: flipped) })
        #expect(state.isVisible(manual, sources: flipped))
    }

    // MARK: The sidebar (layouts.md §2.1)

    @Test("`fresh` lists Personal, Daily routine, University timetable — three, in that order")
    func freshSidebarRows() throws {
        let context = try memory()
        AppStore.seedLaunch(.review(.fresh), context: context, now: TestClock.now, secrets: InMemorySecretStore()) {}
        let rows = SourceDirectory.sidebarOrder(try context.fetch(FetchDescriptor<Source>()))
        #expect(rows.map(\.displayName) == ["Personal", "Daily routine", "University timetable"])
        #expect(rows.map(\.paletteKey) == [.graphite, .green, .blue])
        #expect(rows.map(\.symbol) == ["person.fill", "rectangle.stack.fill", "tablecells.fill"])
        // The same list is the directory's order.
        #expect(try directory(context).ordered.map(\.name) == ["Personal", "Daily routine", "University timetable"])
    }

    @Test("Connected sources follow the built-ins by name; a real store never lists a fixture source")
    func sidebarOrderRule() throws {
        let context = try memory()
        BuiltInSource.ensure(in: context)
        for (id, name) in [("z", "Zeta feed"), ("a", "alpha feed"), ("m", "Mensa")] {
            context.insert(Source.connected(id: id, displayName: name, serverURL: "https://example.invalid", username: "user01",
                                            principalHref: nil, calendarHomeHref: nil, calendars: [],
                                            capabilities: SourceCapabilities(), paletteKey: .blue))
        }
        try context.save()
        let rows = SourceDirectory.sidebarOrder(try context.fetch(FetchDescriptor<Source>()))
        #expect(rows.map(\.displayName) == ["Personal", "Daily routine", "alpha feed", "Mensa", "Zeta feed"])
        // A normal launch creates no local source but the two built-ins.
        let real = try memory()
        AppStore.seedLaunch(.normal, context: real, now: TestClock.now, secrets: SpySecretStore()) {}
        #expect(try real.fetch(FetchDescriptor<Source>()).map(\.displayName).sorted() == ["Daily routine", "Personal"])
    }

    // MARK: Review datasets (§22.1)

    @Test("Review only: an event with no sourceID resolves to the source holding its stored slot")
    func slotFallbackIsReviewOnly() throws {
        let context = try memory()
        let undo = UndoStack()
        ReviewMode.seedIfRequested(.phase3, context: context, now: TestClock.now, secrets: InMemorySecretStore()) {
            RoutineMaterialization.run(context: context, undo: undo, visibleEnd: nil, today: TestClock.now)
        }
        let events = try context.fetch(FetchDescriptor<Event>())
        // `Statistik übung`: imported, detached from the review source (G-073).
        let detached = try #require(events.first { $0.externalID == "stat-ue-04" })
        #expect(detached.sourceID == nil && detached.origin == .imported && detached.sourceKey == .blue)
        let review = try directory(context, slotFallback: true)
        #expect(review.info(for: detached).name == "University timetable")
        // Phase 2's mock manual events keep the mock source of their slot in review.
        let amber = try #require(events.first { $0.origin == .manual && $0.sourceKey == .amber })
        #expect(review.info(for: amber).name == "Mail appointments")
        // Without review mode nothing is looked up by slot.
        let real = try directory(context)
        #expect(real.info(for: detached).id == nil)
        #expect(real.info(for: amber).id == "personal")
    }

    // MARK: Production code (§21.1.1)

    private func productionSources() throws -> [(name: String, text: String)] {
        let root = Fixture.repoRoot.appendingPathComponent("Kadence")
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var out: [(String, String)] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            let path = url.path
            // Review-only code: the mock data and review mode themselves.
            if path.contains("/Kadence/Mock/") || path.contains("/Kadence/Review/") { continue }
            out.append((url.lastPathComponent, try String(contentsOf: url, encoding: .utf8)))
        }
        return out
    }

    @Test("Production code never reads MockData.sources, keeps no hidden-slot set, and has no lookup by slot")
    func noLookupBySlotInProduction() throws {
        let files = try productionSources()
        #expect(files.count > 60)
        for (name, text) in files {
            let code = text.split(separator: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            #expect(!code.contains("MockData.sources"), "\(name) reads MockData.sources")
            #expect(!code.contains("hiddenSources"), "\(name) still has a hidden palette-slot set")
            #expect(!code.contains("SourceCatalog.name(for"), "\(name) names a source by slot")
            #expect(!code.contains("SourceCatalog.symbol(for"), "\(name) takes a source's symbol by slot")
        }
    }

    @Test("No production path creates an imported event without a sourceID")
    func importedEventsAlwaysCarryTheirSource() throws {
        // By behaviour: every event the Import and a later sync write has it.
        let (context, timetable) = try store(timetableSlot: .blue)
        let later = ReviewMode.fetchResult(of: ReviewFeed.reportCISOverlap(export: try Fixture.text("cis-2026WS-redacted.ics")),
                                           now: TestClock.date("2026-10-01 10:00"), zone: TestClock.zone)
        let plan = SyncPlanner.plan(
            existing: SyncApplier.snapshot(of: timetable, in: context, zone: TestClock.zone),
            source: SourceSnapshot(feedHash: timetable.feedHash, lastFeedEventCount: timetable.lastFeedEventCount,
                                   calendars: timetable.calendars, importedAt: timetable.importedAt),
            result: later, kind: .sync, now: TestClock.date("2026-10-01 10:00"), zone: TestClock.zone)
        try SyncApplier.apply(plan, to: timetable, context: context, now: TestClock.date("2026-10-01 10:00"))
        let imported = try context.fetch(FetchDescriptor<Event>()).filter { $0.origin == .imported }
        #expect(imported.count == 13)
        #expect(imported.allSatisfy { $0.sourceID == timetable.id })
        // By construction: the one place production code builds an imported
        // `Event` passes the source's id.
        var sites = 0
        for (name, text) in try productionSources() {
            for range in text.ranges(of: "origin: .imported") {
                let line = text[text.lineRange(for: range)]
                guard line.contains("Event(") || text[..<range.lowerBound].suffix(200).contains("Event(") else { continue }
                sites += 1
                let after = text[range.upperBound...].prefix(200)
                #expect(after.contains("sourceID: source.id"), "\(name) builds an imported Event without its source's id")
            }
        }
        #expect(sites == 1)
    }
}
