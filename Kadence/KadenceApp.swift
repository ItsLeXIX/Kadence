//
//  KadenceApp.swift
//  Kadence
//

import SwiftUI
import SwiftData

@main
struct KadenceApp: App {
    /// Phase 1 persisted exactly two model types. Phase 2's routine data layer
    /// (task P2-T08, `Kadence/Models/RoutineTemplate.swift`) added two more —
    /// `RoutineTemplate` and `RoutineBlock` — that must be registered here too,
    /// or `RoutineEngine.materialize`'s `EventStore` (built on this same
    /// container) can never persist or fetch one outside of a test's own
    /// hand-built container. SwiftData builds the schema from this list; there
    /// is no .xcdatamodeld any more.
    let container: ModelContainer

    @State private var calendar = CalendarState()
    /// One stack for the whole app: the Edit menu and every view mutate through
    /// the same instance, so ⌘Z means the same thing everywhere.
    @State private var undoStack = UndoStack()

    init() {
        do {
            container = try ModelContainer(for: Event.self, Place.self, RoutineTemplate.self, RoutineBlock.self)
        } catch {
            // BRIEF-PRODUCT.md: errors surface in the UI, never as a crash.
            // An unopenable store is unrecoverable at launch, so fall back to
            // an in-memory one and let the UI say so rather than trapping.
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            container = (try? ModelContainer(
                for: Event.self, Place.self, RoutineTemplate.self, RoutineBlock.self,
                configurations: configuration))
                ?? ModelContainer.emptyFallback()
            StoreHealth.shared.failedToOpenPersistentStore = true
        }
    }

    var body: some Scene {
        WindowGroup {
            MainWindow()
                .environment(calendar)
                .environment(undoStack)
                .frame(
                    minWidth: Tokens.Size.windowMinWidth,
                    minHeight: Tokens.Size.windowMinHeight)
        }
        .modelContainer(container)
        .commands { KadenceCommands(calendar: calendar, undo: undoStack) }

        Settings {
            SettingsPlaceholderView()
        }
    }
}

/// Surfaced in the UI rather than logged, per the brief.
@Observable
final class StoreHealth {
    @MainActor static let shared = StoreHealth()
    var failedToOpenPersistentStore = false
}

private extension ModelContainer {
    /// Last resort so `init` never traps. If even this fails the app is in a
    /// state no UI can help with, and `fatalError` is honest about it.
    static func emptyFallback() -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: Event.self, configurations: configuration)
        } catch {
            fatalError("SwiftData could not create even an in-memory store: \(error)")
        }
    }
}
