//
//  RoutinesWindowOpener.swift
//  Kadence
//
//  Task P2-F16 (fixes DEVIATIONS B25). The Routines window is a
//  `WindowGroup(id: "routines")`, and `openWindow(id:)` on a `WindowGroup`
//  creates a NEW window every time — so routing a template conflict there
//  while one was already open left two Routines windows, only the new one
//  in conflict mode. An open Routines window is brought forward instead;
//  it consumes `CalendarState.pendingTemplateConflictID` itself.
//

import SwiftUI
import AppKit

@MainActor
enum RoutinesWindowOpener {
    /// SwiftUI names a `WindowGroup`'s windows after its id
    /// (`routines-AppWindow-1`, …).
    static func isRoutinesWindow(identifier: String?) -> Bool {
        identifier?.hasPrefix("routines") ?? false
    }

    static func open(using openWindow: OpenWindowAction) {
        if let existing = NSApplication.shared.windows.first(where: {
            $0.isVisible && isRoutinesWindow(identifier: $0.identifier?.rawValue)
        }) {
            existing.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "routines")
        }
    }
}
