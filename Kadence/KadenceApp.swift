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
    /// Phase 3 (interactions.md §13.3): the one sync coordinator. Built in
    /// `init` because it needs the container's main context.
    @State private var sync: SyncCoordinator
    /// Phase 3: which source Settings shows and which sheet it presents.
    @State private var router = SourcesRouter()
    /// Phase 3 slice 2 (components.md §24): the travel recompute, its
    /// routing queue and the departure refreshes. The provider, geocoder and
    /// path monitor come from the launch's factories: MapKit and
    /// `NWPathMonitor` in a normal launch only, mocks otherwise (§24.11).
    @State private var travel: TravelCoordinator

    init() {
        // PHASE3-REVIEW.md fix 1 (components.md §22.1, G-076): the launch
        // decides its store. Only a normal launch opens the real one; a
        // review launch and the unit tests' host run on an in-memory store
        // that is gone when the process quits.
        let kind = LaunchKind.current()
        let opened = AppStore.makeContainer(for: kind)
        container = opened.container
        // BRIEF-PRODUCT.md: errors surface in the UI, never as a crash.
        if opened.failedToOpenPersistentStore { StoreHealth.shared.failedToOpenPersistentStore = true }
        // Swift note: `_sync` is the property wrapper's own storage; assigning
        // `State(initialValue:)` there is how an `init` seeds a `@State`.
        switch kind {
        case .review(let dataset):
            // Review mode (task 10): the mocked CIS server, the review
            // password in memory — no network, no Keychain. `phase2` and
            // `empty` too: they have no connected source, but their connect
            // sheet must still never reach the network.
            let server = ReviewMode.server(case: ReviewMode.mockCase(), now: Date(), dataset: dataset)
            _sync = State(initialValue: SyncCoordinator.live(
                context: container.mainContext, secrets: ReviewMode.secrets, path: PathMonitors.make(for: kind),
                makeTransport: { MockCalDAVTransport(server: server) }))
        case .testHost:
            // The unit tests' host: no Keychain, and every request refused
            // before it is sent.
            _sync = State(initialValue: SyncCoordinator.live(
                context: container.mainContext, secrets: InMemorySecretStore(), path: PathMonitors.make(for: kind),
                makeTransport: { RefusingTransport() }))
        case .normal:
            _sync = State(initialValue: SyncCoordinator.live(context: container.mainContext,
                                                             path: PathMonitors.make(for: kind)))
        }
        _travel = State(initialValue: Self.makeTravel(kind: kind, context: container.mainContext))
    }

    /// The launch's travel coordinator (slice 2), from the per-service
    /// factories.
    @MainActor
    static func makeTravel(kind: LaunchKind, context: ModelContext) -> TravelCoordinator {
        let log = RoutingLog(forwardsToSystem: kind == .normal)
        let clock = SystemTravelClock()
        let queue = RouteRequestQueue(provider: TravelServices.makeProvider(for: kind),
                                      geocoder: TravelServices.makeGeocoder(for: kind), clock: clock,
                                      path: PathMonitors.make(for: kind), log: log)
        return TravelCoordinator(context: context, queue: queue, clock: clock,
                                 providerSource: TravelServices.providerSource(for: kind), log: log)
    }

    var body: some Scene {
        // `id: "main"` (task P2-F18) so the menu bar popover's `Open` can
        // reopen the main window with `openWindow(id:)` when it is closed.
        WindowGroup(id: "main") {
            MainWindow()
                // components.md §21.1.1 (fix 2): every scene keeps the
                // source directory in step with the store's `Source` records.
                .tracksSources()
                .environment(calendar)
                .environment(undoStack)
                .environment(sync)
                .environment(router)
                .environment(travel)
                .preferredColorScheme(Self.reviewColorScheme)
                .frame(
                    minWidth: Tokens.Size.windowMinWidth,
                    minHeight: Tokens.Size.windowMinHeight)
        }
        .modelContainer(container)
        .commands { KadenceCommands(calendar: calendar, undo: undoStack, sync: sync, router: router) }

        // layouts.md §8 — "a separate window, not a sheet and not a Settings
        // pane," opened with ⌘⌥R or Window ▸ Routines (see KadenceCommands).
        // `id: "routines"` is what that command's `openWindow(id:)` targets.
        WindowGroup(id: "routines") {
            RoutinesWindow()
                .tracksSources()
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

        // layouts.md §11 — Settings ▸ Sources (Phase 3 task 12).
        Settings {
            SettingsView()
                .tracksSources()
                .environment(sync)
                .environment(travel)
                .environment(router)
                .environment(calendar)
                .environment(undoStack)
        }
        .modelContainer(container)

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
                .tracksSources()
                .environment(undoStack)
                .environment(travel)
                // Task P2-F18: `Open` selects the item in the main window.
                .environment(calendar)
        } label: {
            MenuBarStatusItemView(container: container)
        }
        .modelContainer(container)
        .menuBarExtraStyle(.window)
    }
}

extension KadenceApp {
    /// `-KadenceAppearance` in review mode; nil (follow the system) otherwise.
    static var reviewColorScheme: ColorScheme? {
        switch ReviewMode.appearance() {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }
}

/// Surfaced in the UI rather than logged, per the brief.
@Observable
final class StoreHealth {
    @MainActor static let shared = StoreHealth()
    var failedToOpenPersistentStore = false
}
