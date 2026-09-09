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

    var body: some Commands {
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
                calendar.userSetSidebarVisibility = true
                calendar.isSidebarVisible.toggle()
            }
            .keyboardShortcut("s", modifiers: [.control, .command])

            Button(calendar.isInspectorVisible ? "Hide Inspector" : "Show Inspector") {
                calendar.userSetInspectorVisibility = true
                calendar.isInspectorVisible.toggle()
            }
            .keyboardShortcut("i", modifiers: [.option, .command])

            Divider()
        }
    }
}

extension Notification.Name {
    static let kadenceNewEvent = Notification.Name("kadence.newEvent")
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
