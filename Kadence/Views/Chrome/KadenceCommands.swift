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

    /// layouts.md §8 — opens the Routines window (`WindowGroup(id: "routines")`
    /// in `KadenceApp.swift`). `Commands` bodies read environment values the
    /// same way a `View`'s does; this is the standard SwiftUI pattern for a
    /// custom "open a named window" menu command.
    @Environment(\.openWindow) private var openWindow

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

        CommandGroup(after: .newItem) {
            Button("New Event") {
                let start = calendar.timeCursor ?? Date()
                NotificationCenter.default.post(name: .kadenceNewEvent, object: start)
            }
            .keyboardShortcut("n", modifiers: .command)
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
            Button("Previous") { calendar.page(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: .command)
            Button("Next") { calendar.page(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: .command)

            Divider()

            Button("Toggle Sidebar") {
                calendar.toggleSidebar()
            }
            .keyboardShortcut("s", modifiers: [.control, .command])

            Button(calendar.isInspectorVisible ? "Hide Inspector" : "Show Inspector") {
                calendar.userSetInspectorVisibility = true
                calendar.isInspectorVisible.toggle()
            }
            .keyboardShortcut("i", modifiers: [.option, .command])

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

extension Notification.Name {
    static let kadenceNewEvent = Notification.Name("kadence.newEvent")
    static let kadenceGoToFirstConflict = Notification.Name("kadence.goToFirstConflict")
}

struct SettingsPlaceholderView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.lg) {
            Text("Settings")
                .typeStyle(.inspectorTitle)
            // Sources, travel mode, notification rules and focus limits are
            // Phase 3–6. Saying so beats an empty pane with tabs that do nothing.
            Text("Sources, travel, notifications and focus limits arrive with later phases.")
                .typeStyle(.inspectorValue)
                .foregroundStyle(Tokens.Color.Text.secondary)
        }
        .padding(Tokens.Spacing.huge)
        .frame(width: 420, height: 200)
    }
}
