//
//  AppStore.swift
//  Kadence
//
//  PHASE3-REVIEW.md fix 1 — components.md §22.1 "Review mode never touches
//  the real store" (added 2026-10-10; GAPS G-076; DECISIONS 2026-10-10
//  "Review mode has its own store"), and §21.1.1's two built-in sources.
//
//  Which store a launch opens is decided here, once, from the launch itself:
//
//  - a normal launch opens the real store (`default.store` in the app's
//    Application Support) and seeds nothing but the two built-in sources;
//  - a launch with `-KadenceReview <dataset>` gets an in-memory store, created
//    fresh for that launch and gone when it quits, and the in-memory secret
//    store. It never opens, reads, writes or deletes the real store;
//  - a launch as the unit tests' host (the test bundle is injected into
//    Kadence.app, so `KadenceApp.init` runs in every test run) also gets an
//    in-memory store, the in-memory secret store and a transport that refuses
//    every request — a test run can neither open the real store nor reach a
//    server.
//

import Foundation
import SwiftData

/// What kind of launch this is. Decides the store, the secret store and the
/// transport together, so no combination can mix real and review parts.
nonisolated enum LaunchKind: Equatable, Sendable {
    case normal
    case review(ReviewMode.Dataset)
    case testHost

    /// Only a normal launch may touch the real store, the Keychain and the
    /// network.
    var usesRealStore: Bool { self == .normal }

    /// Swift note: `ProcessInfo.processInfo.environment` is the process's
    /// environment variables as a dictionary (`System.getenv()` in Java).
    static func current(defaults: UserDefaults = .standard,
                        environment: [String: String] = ProcessInfo.processInfo.environment) -> LaunchKind {
        if isTestHost(environment: environment) { return .testHost }
        if let dataset = ReviewMode.dataset(defaults) { return .review(dataset) }
        return .normal
    }

    /// Whether XCTest launched this process. `xcodebuild test` sets these
    /// variables for the host app before `main` runs; the class check covers
    /// a runner that sets none of them (the XCTest framework is then already
    /// loaded into the process).
    static func isTestHost(environment: [String: String],
                           xctestLoaded: () -> Bool = { NSClassFromString("XCTestCase") != nil }) -> Bool {
        let keys = ["XCTestConfigurationFilePath", "XCTestBundlePath", "XCTestSessionIdentifier"]
        if keys.contains(where: { environment[$0] != nil }) { return true }
        // The injection library that loads a test bundle into a host app.
        if environment["DYLD_INSERT_LIBRARIES"]?.contains("XCTest") == true { return true }
        return xctestLoaded()
    }
}

@MainActor
enum AppStore {
    static var schema: Schema { Schema(KadenceSchema.models) }

    /// The store configuration of a launch. Creating a `ModelConfiguration`
    /// opens nothing: it is only a description (a URL and flags) until a
    /// `ModelContainer` is built from it.
    static func configuration(for kind: LaunchKind) -> ModelConfiguration {
        switch kind {
        case .normal:
            // The default configuration: `default.store` in Application
            // Support — the same file `ModelContainer(for:)` has always used.
            ModelConfiguration(schema: schema)
        case .review, .testHost:
            ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        }
    }

    /// Where the real store lives. Computed, never opened here.
    static var realStoreURL: URL { configuration(for: .normal).url }

    struct Opened {
        var container: ModelContainer
        /// The persistent store could not be opened and an in-memory one
        /// stands in (BRIEF-PRODUCT: surfaced in the UI, never a crash).
        var failedToOpenPersistentStore = false
    }

    /// Builds the launch's container. `open` is the one call that touches a
    /// file; tests pass their own to see exactly which configuration a launch
    /// would open, without opening it.
    static func makeContainer(
        for kind: LaunchKind,
        open: (Schema, ModelConfiguration) throws -> ModelContainer = { try ModelContainer(for: $0, configurations: $1) }
    ) -> Opened {
        do {
            return Opened(container: try open(schema, configuration(for: kind)))
        } catch {
            // An unopenable store is unrecoverable at launch, so fall back to
            // an in-memory one and let the UI say so rather than trapping.
            let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                return Opened(container: try ModelContainer(for: schema, configurations: memory),
                              failedToOpenPersistentStore: kind.usesRealStore)
            } catch {
                fatalError("SwiftData could not create even an in-memory store: \(error)")
            }
        }
    }

    /// What a launch writes into its store before the first materialisation
    /// pass: the two built-in sources always (§21.1.1), a review dataset only
    /// in review mode, and nothing else. Both windows call this; whichever
    /// opens first does the work and the second call inserts nothing.
    @discardableResult
    static func seedLaunch(_ kind: LaunchKind, context: ModelContext, now: Date = Date(),
                           secrets: any SecretStore = ReviewMode.secrets, materialize: () -> Void) -> MockFixtures {
        BuiltInSource.ensure(in: context)
        // Slice 2 (components.md §23.1, §28.1, §27.1): the built-in places,
        // the settings row and the five rules, in every launch kind.
        TravelBuiltIns.ensure(in: context)
        // Swift note: `if case .review(let dataset) = kind` is pattern
        // matching on one enum case, binding its payload — an `instanceof`
        // with a cast in one step.
        if case .review(let dataset) = kind {
            return ReviewMode.seedIfRequested(dataset, context: context, now: now, secrets: secrets,
                                              materialize: materialize)
        }
        materialize()
        return MockFixtures()
    }
}

// MARK: - The two built-in sources (§21.1.1)

/// Every store has exactly two `local` sources, with fixed ids: the app's own
/// taxonomy, not fixture data, because this build has a creator for each
/// (`⌘N`; the Routines window).
nonisolated enum BuiltInSource: String, CaseIterable, Sendable {
    case personal
    case routine

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .personal: "Personal"
        case .routine: "Daily routine"
        }
    }

    var kind: CalendarSourceKind {
        switch self {
        case .personal: .manual
        case .routine: .routine
        }
    }

    var paletteKey: SourceKey {
        switch self {
        case .personal: .graphite
        case .routine: .green
        }
    }

    /// Creates the missing ones. Idempotent: a second call inserts nothing.
    @MainActor
    static func ensure(in context: ModelContext) {
        let existing = Set(((try? context.fetch(FetchDescriptor<Source>())) ?? []).map(\.id))
        var inserted = false
        for builtIn in allCases where !existing.contains(builtIn.id) {
            context.insert(Source(id: builtIn.id, kind: builtIn.kind, connection: .local,
                                  displayName: builtIn.displayName, paletteKey: builtIn.paletteKey))
            inserted = true
        }
        if inserted { try? context.save() }
    }
}

// MARK: - The test host's transport

/// Refuses every request before anything is sent. The unit tests' host app
/// gets this instead of `URLSessionTransport`, so a test run cannot reach a
/// server whatever a test (or the launch) asks of the app's own coordinator.
nonisolated struct RefusingTransport: HTTPTransport {
    func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse { throw .offline }
}
