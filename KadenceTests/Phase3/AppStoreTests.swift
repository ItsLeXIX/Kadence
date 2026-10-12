//
//  AppStoreTests.swift
//  KadenceTests
//
//  PHASE3-REVIEW.md fix 1 — components.md §22.1 "Review mode never touches the
//  real store" (G-076), §21.1.1's two built-in sources.
//
//  None of these tests opens the real store: the "normal launch" ones pass
//  their own `open` closure, which records the configuration the launch asked
//  for and hands back an in-memory container instead.
//

import Testing
import Foundation
import SwiftData
import CryptoKit
import Synchronization
@testable import Kadence

@MainActor
@Suite(.serialized)
struct AppStoreTests {

    /// Records what a launch would open; never opens it.
    private final class Recorder {
        var urls: [URL] = []
        var inMemory: [Bool] = []
        func open(_ schema: Schema, _ configuration: ModelConfiguration) throws -> ModelContainer {
            urls.append(configuration.url)
            inMemory.append(configuration.isStoredInMemoryOnly)
            return try ModelContainer(for: schema, configurations: ModelConfiguration(schema: schema, isStoredInMemoryOnly: true))
        }
    }

    @Test("A review launch builds an in-memory container and never opens the real store's URL",
          arguments: ReviewMode.Dataset.allCases)
    func reviewLaunchIsInMemory(_ dataset: ReviewMode.Dataset) throws {
        let real = AppStore.realStoreURL
        #expect(real.lastPathComponent == "default.store")
        let recorder = Recorder()
        let opened = AppStore.makeContainer(for: .review(dataset), open: recorder.open)
        #expect(recorder.inMemory == [true])
        #expect(!recorder.urls.contains(real))
        #expect(opened.failedToOpenPersistentStore == false)
        // The container the app really builds for a review launch.
        let container = AppStore.makeContainer(for: .review(dataset)).container
        #expect(container.configurations.allSatisfy { $0.isStoredInMemoryOnly })
        #expect(!container.configurations.map { $0.url }.contains(real))
    }

    @Test("The unit tests' host launch is in-memory too; only a normal launch asks for the real store")
    func normalAndTestHost() throws {
        let real = AppStore.realStoreURL
        let host = Recorder()
        _ = AppStore.makeContainer(for: .testHost, open: host.open)
        #expect(host.inMemory == [true])
        #expect(!host.urls.contains(real))

        // A normal launch asks for exactly the real store, persisted — seen
        // through the recorder, which does not open it.
        let normal = Recorder()
        _ = AppStore.makeContainer(for: .normal, open: normal.open)
        #expect(normal.urls == [real])
        #expect(normal.inMemory == [false])
        #expect(LaunchKind.normal.usesRealStore)
        #expect(!LaunchKind.testHost.usesRealStore)
        #expect(!LaunchKind.review(.phase3).usesRealStore)
    }

    @Test("This very process — the tests' host app — is a test-host launch and holds no descriptor on the real store")
    func hostProcessNeverOpenedTheRealStore() throws {
        #expect(LaunchKind.current() == .testHost)
        // Every open file descriptor of this process, by path. Swift note:
        // `fcntl(fd, F_GETPATH, buffer)` asks the kernel for the path an open
        // descriptor refers to; -1 means the descriptor is not open.
        var paths: [String] = []
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        for fd in 0..<getdtablesize() where fcntl(fd, F_GETPATH, &buffer) != -1 {
            // Up to the terminating NUL, decoded as UTF-8.
            paths.append(String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self))
        }
        #expect(!paths.isEmpty)
        #expect(!paths.contains { $0.contains("default.store") })
    }

    @Test("Launch kind: XCTest wins, then the review argument, else normal")
    func launchKind() throws {
        let suite = "AppStoreTests.launchKind"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        func kind(_ env: [String: String], xctest: Bool = false) -> LaunchKind {
            LaunchKind.isTestHost(environment: env, xctestLoaded: { xctest }) ? .testHost
                : (ReviewMode.dataset(defaults).map(LaunchKind.review) ?? .normal)
        }
        #expect(kind([:]) == .normal)
        for value in ["phase2", "phase3", "empty", "fresh"] {
            defaults.set(value, forKey: "KadenceReview")
            let dataset = try #require(ReviewMode.Dataset(rawValue: value))
            #expect(kind([:]) == .review(dataset))
        }
        defaults.set("nonsense", forKey: "KadenceReview")
        #expect(kind([:]) == .normal)
        for key in ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"] {
            #expect(kind([key: "x"]) == .testHost)
        }
        #expect(kind([:], xctest: true) == .testHost)
    }

    private func memory() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Schema(KadenceSchema.models),
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    private func counts(_ context: ModelContext) throws -> (events: Int, templates: Int, windows: Int, blocks: Int) {
        (try context.fetchCount(FetchDescriptor<Event>()), try context.fetchCount(FetchDescriptor<RoutineTemplate>()),
         try context.fetchCount(FetchDescriptor<TimeWindow>()), try context.fetchCount(FetchDescriptor<RoutineBlock>()))
    }

    @Test("A normal launch on an empty store inserts exactly the two built-in sources and nothing else")
    func normalLaunchSeedsOnlyBuiltIns() throws {
        let context = try memory()
        let spy = SpySecretStore()
        for _ in 0..<2 {    // both windows call it; the second inserts nothing
            AppStore.seedLaunch(.normal, context: context, now: TestClock.now, secrets: spy) {
                RoutineMaterialization.run(context: context, undo: UndoStack(), visibleEnd: nil, today: TestClock.now)
            }
        }
        let sources = try context.fetch(FetchDescriptor<Source>()).sorted { $0.id < $1.id }
        #expect(sources.map(\.id) == ["personal", "routine"])
        #expect(sources.map(\.displayName) == ["Personal", "Daily routine"])
        #expect(sources.map(\.paletteKey) == [.graphite, .green])
        #expect(sources.map(\.symbol) == ["person.fill", "rectangle.stack.fill"])
        #expect(sources.allSatisfy { $0.connection == .local && $0.isVisible })
        let c = try counts(context)
        #expect(c.events == 0 && c.templates == 0 && c.windows == 0 && c.blocks == 0)
        #expect(spy.calls.withLock { $0 } == 0)
    }

    @Test("The test host and `empty` seed the same: two built-in sources, no event")
    func emptyDataset() throws {
        for kind in [LaunchKind.testHost, .review(.empty)] {
            let context = try memory()
            AppStore.seedLaunch(kind, context: context, now: TestClock.now, secrets: InMemorySecretStore()) {}
            #expect(try context.fetchCount(FetchDescriptor<Source>()) == 2)
            #expect(try counts(context).events == 0)
        }
    }

    @Test("The bundled export is the repo fixture, byte for byte")
    func bundledExportIsTheFixture() throws {
        let repo = try Data(contentsOf: Fixture.repoRoot.appendingPathComponent("fixtures/cis-2026WS-redacted.ics"))
        let url = try #require(Bundle.main.url(forResource: "cis-2026WS-redacted", withExtension: "ics"))
        let bundled = try Data(contentsOf: url)
        #expect(SHA256.hash(data: bundled) == SHA256.hash(data: repo))
        #expect(ReviewCISExport.text == String(decoding: repo, as: UTF8.self))
        #expect(ReviewCISExport.text.contains("\r\n"))
    }

    @Test("`fresh`: the two built-ins and one connected source imported from reportCISOverlap — 14 VEVENTs, 13 events")
    func freshDataset() throws {
        let context = try memory()
        let secrets = InMemorySecretStore()
        for _ in 0..<2 {
            AppStore.seedLaunch(.review(.fresh), context: context, now: TestClock.now, secrets: secrets) {}
        }
        let sources = try context.fetch(FetchDescriptor<Source>())
        #expect(sources.count == 3)
        let timetable = try #require(sources.first { $0.isConnected })
        #expect(timetable.displayName == "University timetable")
        #expect(timetable.username == "user01")
        #expect(timetable.paletteKey != .graphite)
        #expect(timetable.importedAt == TestClock.now)
        #expect(timetable.lastFeedEventCount == 14)
        let events = try context.fetch(FetchDescriptor<Event>())
        #expect(events.count == 13)
        #expect(events.allSatisfy { $0.sourceID == timetable.id && $0.origin == .imported })
        let bpref = events.filter { $0.title == "BPREF-Info" }.sorted { $0.start < $1.start }
        #expect(bpref.count == 2)
        #expect(bpref.first?.lecturers == ["L05", "L06"])
        #expect(bpref.last?.lecturers == ["L07"])
        #expect(bpref.last?.start == TestClock.date("2026-10-02 19:30"))
        let c = try counts(context)
        #expect(c.templates == 0 && c.windows == 0)
        // The review password stays in memory, for the review account only.
        #expect(try secrets.read(SecretAccount(host: MockCalDAVServer.host, username: "user01")) != nil)
    }

    @Test("No script names the real store")
    func scriptsNeverNameTheRealStore() throws {
        let scripts = Fixture.repoRoot.appendingPathComponent("Scripts")
        let files = try #require(FileManager.default.enumerator(at: scripts, includingPropertiesForKeys: nil))
        var checked = 0
        for case let url as URL in files where ["sh", "py", "swift"].contains(url.pathExtension) {
            let text = try String(contentsOf: url, encoding: .utf8)
            checked += 1
            #expect(!text.contains("default.store"), "\(url.lastPathComponent) names the real store")
        }
        #expect(checked >= 15)
    }
}
