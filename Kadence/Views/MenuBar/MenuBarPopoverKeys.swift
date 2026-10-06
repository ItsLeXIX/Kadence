//
//  MenuBarPopoverKeys.swift
//  Kadence
//
//  interactions.md §12 (amended 2026-10-05) — the popover's keyboard table,
//  as a pure function so it can be tested without a popover. Task P2-F18.
//
//  Focus index 0 is the NEXT item; 1…rowCount−1 are the REST OF TODAY rows
//  (the `+N more` line is not a row).
//

import SwiftUI

enum MenuBarPopoverKeys {

    enum Action: Equatable {
        /// `↑`/`↓`: move focus to this index.
        case focus(Int)
        /// `↩`: open the focused item in the main window.
        case open(Int)
        /// `⌘↩`: Done (the NEXT item).
        case done
        /// `⌥⌘↩`: Snooze (the NEXT item).
        case snooze
        /// `⎋`: close the popover.
        case close
    }

    /// - Parameters:
    ///   - focus: the focused index.
    ///   - rowCount: NEXT plus the rest rows; 0 when the popover is empty.
    /// - Returns: the action, or `nil` when the key isn't the popover's.
    static func action(key: KeyEquivalent, modifiers: EventModifiers, focus: Int, rowCount: Int) -> Action? {
        let command = modifiers.contains(.command), option = modifiers.contains(.option)
        switch key {
        case .escape:
            return .close
        case .return where command && option:
            return rowCount > 0 ? .snooze : nil
        case .return where command:
            return rowCount > 0 ? .done : nil
        case .return where modifiers.isEmpty:
            return rowCount > 0 ? .open(min(max(focus, 0), rowCount - 1)) : nil
        // Ends stop rather than wrap, like every other list in the app.
        case .upArrow where modifiers.isEmpty:
            return rowCount > 0 ? .focus(max(focus - 1, 0)) : nil
        case .downArrow where modifiers.isEmpty:
            return rowCount > 0 ? .focus(min(focus + 1, rowCount - 1)) : nil
        default:
            return nil
        }
    }

    /// components.md §15.2 (amended 2026-10-05): the action row, in order.
    /// Late: `Re-offer` leads and is the prominent primary. Every button is
    /// enabled — `Open` included (it was drawn disabled in every capture).
    struct ActionButton: Equatable {
        enum Kind: Hashable { case reoffer, done, snooze, open }
        var kind: Kind
        var title: String
        var isProminent: Bool
        var isEnabled: Bool = true
    }

    static func actionButtons(isLate: Bool) -> [ActionButton] {
        var buttons: [ActionButton] = []
        if isLate { buttons.append(ActionButton(kind: .reoffer, title: "Re-offer", isProminent: true)) }
        buttons += [
            ActionButton(kind: .done, title: "Done", isProminent: false),
            ActionButton(kind: .snooze, title: "Snooze", isProminent: false),
            ActionButton(kind: .open, title: "Open", isProminent: false),
        ]
        return buttons
    }
}
