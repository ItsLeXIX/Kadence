//
//  KadenceCommands.swift
//  Kadence
//
//  interactions.md §2 — "every one of these is also a menu bar item, with the
//  same key equivalent, so the shortcut set is discoverable without documentation."
//

import SwiftUI

struct KadenceCommands: Commands {
    var calendar: CalendarState
    var undo: UndoStack
    /// Phase 3 task 9: View ▸ Sync Now.
    var sync: SyncCoordinator
    /// Phase 3 task 12: File ▸ Connect Timetable….
    var router: SourcesRouter
    @Environment(\.openSettings) private var openSettings

    /// interactions.md §2 (amended 2026-10-08): `⌘R` Sync Now.
    static let syncNowTitle = "Sync Now"
    static let syncNowKey: KeyEquivalent = "r"

    /// layouts.md §8 — opens the Routines window (`WindowGroup(id: "routines")`
    /// in `KadenceApp.swift`). `Commands` bodies read environment values the
    /// same way a `View`'s does; this is the standard SwiftUI pattern for a
    /// custom "open a named window" menu command.
    @Environment(\.openWindow) private var openWindow
    /// Task P2-SF6: set while a Routines window is key — ⌥⌘I then toggles
    /// its editor inspector (layouts.md §8 → §1.1), not the main window's.
    @FocusedValue(\.routinesInspector) private var routinesInspector
    /// PHASE3-REVIEW fix 10a (interactions.md §2, §13.4; DEVIATIONS A38):
    /// set only while the main window's grid holds key focus.
    @FocusedValue(\.gridDelete) private var gridDelete

    var body: some Commands {
        // interactions.md §9 — each action is named, so the menu reads
        // "Undo Move Event". Replaces AppKit's stock pair, which is driven by an
        // UndoManager this app deliberately does not use (see UndoStack).
        CommandGroup(replacing: .undoRedo) {
            Button(undo.undoMenuTitle) { undo.undo() }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!undo.canUndo)

            Button(undo.redoMenuTitle) { undo.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!undo.canRedo)
        }

        // interactions.md §2 (added 2026-10-10, A38): **Edit ▸ Delete**, `⌫`,
        // below the system's pasteboard group. Enabled when a deletable
        // event is selected in the main window's grid; disabled with nothing
        // selected and for an imported event — "so the menu shows the rule
        // before the key does" (§13.4).
        //
        // Swift note: `@FocusedValue` is nil unless key focus is inside the
        // view that publishes it. That is what keeps a bare `⌫` shortcut
        // safe: while a text field (the inspector's title, the Routines
        // window, Settings) has focus the item is disabled, and a disabled
        // item never takes the key — backspace still edits the text.
        CommandGroup(after: .pasteboard) {
            Button(EditDeleteItem.title) { gridDelete?.perform() }
                .keyboardShortcut(EditDeleteItem.key, modifiers: [])
                .disabled(!EditDeleteItem.isEnabled(gridDelete))
        }

        CommandGroup(after: .newItem) {
            Button("New Event") {
                let start = calendar.timeCursor ?? Date()
                NotificationCenter.default.post(name: .kadenceNewEvent, object: start)
            }
            .keyboardShortcut("n", modifiers: .command)
            // interactions.md §13.1: no key equivalent; the item exists so
            // connecting is reachable from the keyboard and Help search.
            Button("Connect Timetable…") {
                router.sheet = .connect
                openSettings()
            }
        }

        // These go INTO the system View menu rather than a CommandMenu named
        // "View", which would give the app two menus with the same name.
        CommandGroup(after: .sidebar) {
            Button("Month") { calendar.setMode(.month) }
                .keyboardShortcut("1", modifiers: .command)
            Button("Week") { calendar.setMode(.week) }
                .keyboardShortcut("2", modifiers: .command)
            Button("Day") { calendar.setMode(.day) }
                .keyboardShortcut("3", modifiers: .command)

            Divider()

            Button("Today") { calendar.goToToday() }
                .keyboardShortcut("t", modifiers: .command)
            // §13.3: every connected source, regardless of interval and
            // pause; disabled while every source is already syncing.
            Button(Self.syncNowTitle) { sync.syncNowAll() }
                .keyboardShortcut(Self.syncNowKey, modifiers: .command)
                .disabled(sync.isSyncNowDisabled)
            Button("Previous") { calendar.page(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button("Next") { calendar.page(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)

            Divider()

            Button("Toggle Sidebar") {
                calendar.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.control, .command])

            if let routinesInspector {
                Button(routinesInspector.isVisible ? "Hide Inspector" : "Show Inspector") {
                    routinesInspector.toggle()
                }
                .keyboardShortcut("i", modifiers: [.option, .command])
            } else {
                Button(calendar.isInspectorVisible ? "Hide Inspector" : "Show Inspector") {
                    calendar.userSetInspectorVisibility = true
                    calendar.isInspectorVisible.toggle()
                }
                .keyboardShortcut("i", modifiers: [.option, .command])
            }

            Divider()

            // components.md §14.1 / interactions.md's global shortcut table —
            // "Go to the first unresolved conflict", "global, when the count
            // is non-zero". Does exactly what activating the sidebar's
            // needs-attention row does (`CalendarState.activateNeedsAttention()`),
            // via the same cross-scene notification `⌘N` already uses for
            // `.kadenceNewEvent`: `KadenceCommands` has no query of its own
            // onto the live event/routine-block data, but `MainWindow` does,
            // and keeps `calendar.conflicts` in sync with it.
            Button("Go to First Conflict") {
                NotificationCenter.default.post(name: .kadenceGoToFirstConflict, object: nil)
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(calendar.needsAttentionCount == 0)
        }

        // layouts.md §8 — "Opened with ⌘⌥R or Window ▸ Routines." Placed in
        // the Window menu (`.windowArrangement`'s placement), alongside the
        // standard window-arrangement commands macOS already puts there.
        CommandGroup(after: .windowArrangement) {
            Button("Routines") {
                openWindow(id: "routines")
            }
            .keyboardShortcut("r", modifiers: [.command, .option])
        }
    }
}

// MARK: - Edit ▸ Delete (interactions.md §2, §13.4)

/// What the main window's grid offers the Edit menu while it holds key focus.
struct GridDeleteAction {
    /// A deletable event is selected.
    var isEnabled: Bool
    /// Deletes it exactly as `⌫` on the grid does (one undo step).
    var perform: () -> Void
}

extension FocusedValues {
    /// Swift note: `@Entry` declares a focused-value key and its accessor in
    /// one line (the macro writes the `FocusedValueKey` type).
    @Entry var gridDelete: GridDeleteAction?
}

/// The Edit ▸ Delete item, as a model a test can read.
enum EditDeleteItem {
    static let title = "Delete"
    /// `⌫`, no modifiers.
    static let key = KeyEquivalent.delete

    /// Whether `⌫` / Edit ▸ Delete may delete `selection`: something is
    /// selected, and the read-only gate allows it (§13.4: never an imported
    /// event). Pure — it does not sound or emphasise anything.
    static func canDelete(_ selection: Event?) -> Bool {
        guard let selection else { return false }
        return ReadOnlyGate.decide(.delete, origin: selection.origin, isCancelled: selection.isCancelled) == .allow
    }

    /// What the grid publishes: enabled for a deletable selection.
    static func action(selection: Event?, delete: @escaping (Event) -> Void) -> GridDeleteAction {
        GridDeleteAction(isEnabled: canDelete(selection)) {
            if let selection, canDelete(selection) { delete(selection) }
        }
    }

    /// The menu item's state: disabled when the grid is not focused (no
    /// action is published), when nothing is selected, and for an imported
    /// selection.
    static func isEnabled(_ action: GridDeleteAction?) -> Bool { action?.isEnabled == true }
}

extension Notification.Name {
    static let kadenceNewEvent = Notification.Name("kadence.newEvent")
    static let kadenceGoToFirstConflict = Notification.Name("kadence.goToFirstConflict")
}
