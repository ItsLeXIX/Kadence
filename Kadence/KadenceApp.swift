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
    /// hand-built container. Task P2-T18 (`Kadence/Models/TimeWindow.swift`)
    /// added a fifth, `TimeWindow`, the same way, and P2-T41 a sixth,
    /// `RoutineTombstone`. The list now lives in `KadenceSchema.models`
    /// (`RoutineTombstone.swift`), shared with the tests. SwiftData builds the
    /// schema from it; there is no .xcdatamodeld any more.
    let container: ModelContainer

    @State private var calendar = CalendarState()
    /// One stack for the whole app: the Edit menu and every view mutate through
    /// the same instance, so ⌘Z means the same thing everywhere.
    @State private var undoStack = UndoStack()

    init() {
        do {
            container = try ModelContainer(
                for: Schema(KadenceSchema.models))
        } catch {
            // BRIEF-PRODUCT.md: errors surface in the UI, never as a crash.
            // An unopenable store is unrecoverable at launch, so fall back to
            // an in-memory one and let the UI say so rather than trapping.
            let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
            container = (try? ModelContainer(
                for: Schema(KadenceSchema.models),
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

        // layouts.md §8 — "a separate window, not a sheet and not a Settings
        // pane," opened with ⌘⌥R or Window ▸ Routines (see KadenceCommands).
        // `id: "routines"` is what that command's `openWindow(id:)` targets.
        WindowGroup(id: "routines") {
            RoutinesWindow()
                // task P2-T11: without this, `RoutinesWindow`'s
                // `@Environment(UndoStack.self)` (needed so its drag/resize/
                // delete edits go through the same `RoutineBlockStore` undo
                // stack as everywhere else) has nothing to resolve — this is
                // the same instance `MainWindow` uses above, so `⌘Z` means the
                // same thing in both windows and `KadenceCommands`' Edit menu
                // (wired once, app-wide) reads correctly no matter which
                // window is key.
                .environment(undoStack)
                // Task P2-T40: the materialisation horizon depends on the
                // main window's visible range (components.md §13.6.5), so
                // this window reads the same `CalendarState`.
                .environment(calendar)
        }
        .modelContainer(container)
        .defaultSize(
            width: Tokens.Size.routineEditorMinWidth,
            height: Tokens.Size.routineEditorMinHeight)

        Settings {
            SettingsPlaceholderView()
        }

        // components.md §15 / DECISIONS.md 2026-09-10 "Menu bar requirement
        // split between status item and popover." `.window` (not the default
        // `.menu` style) because the popover is an arbitrary SwiftUI layout —
        // a NEXT block with a source-hued rail, a REST OF TODAY list — not a
        // list of menu items. `.environment(undoStack)` is needed because the
        // popover's `Done`/`Re-offer` actions go through the same
        // `EventStore`/`UndoStack` every other mutation in the app does, so
        // ⌘Z in the main window also undoes something done from the menu bar.
        MenuBarExtra {
            MenuBarPopoverView()
                .environment(undoStack)
        } label: {
            MenuBarStatusItemView(container: container)
        }
        .modelContainer(container)
        .menuBarExtraStyle(.window)
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
            return try ModelContainer(
                for: Schema(KadenceSchema.models),
                configurations: configuration)
        } catch {
            fatalError("SwiftData could not create even an in-memory store: \(error)")
        }
    }
}
