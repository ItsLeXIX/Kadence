//
//  MenuBarPopoverKeysTests.swift
//  KadenceTests
//
//  Task P2-F18 (PHASE2-REVIEW.md §6 item 18; components.md §15.2 and
//  interactions.md §12, both amended 2026-10-05): `Open` always enabled, the
//  popover's keyboard table, and the late state's prominent `Re-offer`.
//

import Testing
import Foundation
import SwiftUI
@testable import Kadence

@Suite("Popover: Open, keyboard, primary Re-offer (P2-F18)")
@MainActor
struct MenuBarPopoverKeysTests {

    @Test("`Open` is enabled in the normal and late states (and so in overflow, which is normal + `+N more`)")
    func openEnabled() {
        for late in [false, true] {
            let open = MenuBarPopoverKeys.actionButtons(isLate: late).first { $0.kind == .open }
            #expect(open?.isEnabled == true)
        }
    }

    @Test("Late: the first button is `Re-offer`, prominent; nothing else is")
    func reofferPrimary() {
        let late = MenuBarPopoverKeys.actionButtons(isLate: true)
        #expect(late.first?.kind == .reoffer)
        #expect(late.first?.isProminent == true)
        #expect(late.dropFirst().allSatisfy { !$0.isProminent })
        let normal = MenuBarPopoverKeys.actionButtons(isLate: false)
        #expect(normal.map(\.title) == ["Done", "Snooze", "Open"])
        #expect(normal.allSatisfy { !$0.isProminent }, "no primary in the normal state")
    }

    @Test("`↑`/`↓` move focus between NEXT and the rest rows, stopping at the ends")
    func arrows() {
        #expect(MenuBarPopoverKeys.action(key: .downArrow, modifiers: [], focus: 0, rowCount: 4) == .focus(1))
        #expect(MenuBarPopoverKeys.action(key: .downArrow, modifiers: [], focus: 3, rowCount: 4) == .focus(3))
        #expect(MenuBarPopoverKeys.action(key: .upArrow, modifiers: [], focus: 2, rowCount: 4) == .focus(1))
        #expect(MenuBarPopoverKeys.action(key: .upArrow, modifiers: [], focus: 0, rowCount: 4) == .focus(0))
    }

    @Test("`↩` opens the focused item; `⌘↩` Done; `⌥⌘↩` Snooze; `⎋` closes")
    func returnKeys() {
        #expect(MenuBarPopoverKeys.action(key: .return, modifiers: [], focus: 0, rowCount: 4) == .open(0))
        #expect(MenuBarPopoverKeys.action(key: .return, modifiers: [], focus: 2, rowCount: 4) == .open(2))
        #expect(MenuBarPopoverKeys.action(key: .return, modifiers: [.command], focus: 2, rowCount: 4) == .done)
        #expect(MenuBarPopoverKeys.action(key: .return, modifiers: [.command, .option], focus: 0, rowCount: 4) == .snooze)
        #expect(MenuBarPopoverKeys.action(key: .escape, modifiers: [], focus: 0, rowCount: 4) == .close)
    }

    @Test("Empty popover: only `⎋` does anything")
    func empty() {
        #expect(MenuBarPopoverKeys.action(key: .return, modifiers: [], focus: 0, rowCount: 0) == nil)
        #expect(MenuBarPopoverKeys.action(key: .downArrow, modifiers: [], focus: 0, rowCount: 0) == nil)
        #expect(MenuBarPopoverKeys.action(key: .escape, modifiers: [], focus: 0, rowCount: 0) == .close)
    }

    @Test("`Open` pages to the item's day and selects it")
    func revealPagesAndSelects() {
        let state = CalendarState()
        state.setMode(.week)
        let now = Date()
        state.anchor = Calendar.current.date(byAdding: .day, value: -30, to: now)!
        let event = Event(title: "Gym", start: now, end: now.addingTimeInterval(3600))
        state.selectedConflictID = "x"
        state.reveal(event)
        #expect(state.selectedEventID == event.id)
        #expect(state.selectedConflictID == nil)
        #expect(state.mode == .week)
        #expect(state.visibleDays.contains { Calendar.current.isDate($0, inSameDayAs: now) })
    }
}
