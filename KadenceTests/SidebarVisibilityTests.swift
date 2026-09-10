//
//  SidebarVisibilityTests.swift
//  KadenceTests
//
//  layouts.md §1.1 — the collapse order, and the rule that matters most in it:
//  "auto-collapse does not overwrite the user's explicit choice."
//
//  Sidebar visibility used to be two independent pieces of state — the Edit menu
//  wrote `CalendarState.isSidebarVisible`, auto-collapse wrote the split view's
//  `columnVisibility` — so the menu could say "Hide Sidebar" while the sidebar
//  was already hidden. These tests pin the single source of truth.
//

import Testing
import Foundation
import SwiftUI
@testable import Kadence

@Suite("Sidebar visibility")
@MainActor
struct SidebarVisibilityTests {

    @Test("The split view's column visibility is derived, not stored separately")
    func derivedColumnVisibility() {
        let state = CalendarState()
        state.setSidebarVisible(true, isUserAction: true)
        #expect(state.sidebarColumnVisibility == .all)

        state.setSidebarVisible(false, isUserAction: true)
        #expect(state.sidebarColumnVisibility == .detailOnly)
    }

    @Test("The menu toggle and auto-collapse move the same value")
    func oneSourceOfTruth() {
        let state = CalendarState()

        // What the Edit menu does.
        state.toggleSidebar()
        #expect(state.isSidebarVisible == false)
        #expect(state.sidebarColumnVisibility == .detailOnly)

        // What auto-collapse does at a wide window, on a fresh state.
        let fresh = CalendarState()
        fresh.setSidebarVisible(true, isUserAction: false)
        #expect(fresh.isSidebarVisible)
        #expect(fresh.sidebarColumnVisibility == .all)
    }

    @Test("Auto-collapse hides the sidebar below 900pt")
    func autoCollapseNarrow() {
        let state = CalendarState()
        state.setSidebarVisible(false, isUserAction: false)   // width < 900
        #expect(!state.isSidebarVisible)
    }

    @Test("Auto-collapse never overwrites an explicit choice")
    func explicitChoiceWins() {
        let state = CalendarState()

        // The user closes it at a wide window.
        state.setSidebarVisible(false, isUserAction: true)
        #expect(!state.isSidebarVisible)

        // Widening must not re-open it (§1.1).
        state.setSidebarVisible(true, isUserAction: false)
        #expect(!state.isSidebarVisible, "widening the window re-opened a sidebar the user closed")
    }

    @Test("An explicitly opened sidebar survives narrowing")
    func explicitOpenSurvivesNarrowing() {
        let state = CalendarState()
        state.setSidebarVisible(true, isUserAction: true)
        state.setSidebarVisible(false, isUserAction: false)   // narrowed past 900
        #expect(state.isSidebarVisible)
    }

    @Test("Before any explicit choice, auto-collapse is free to move it either way")
    func autoCollapseFreeUntilUserActs() {
        let state = CalendarState()
        #expect(!state.userSetSidebarVisibility)

        state.setSidebarVisible(false, isUserAction: false)
        #expect(!state.isSidebarVisible)
        state.setSidebarVisible(true, isUserAction: false)
        #expect(state.isSidebarVisible, "auto-collapse should still be in charge here")
    }

    @Test("A change arriving from the split view itself counts as an explicit choice")
    func splitViewDividerIsAUserAction() {
        // The user can close the column by dragging it, which writes through the
        // derived binding. That must latch, or the next resize would undo it.
        let state = CalendarState()
        state.setSidebarVisible(false, isUserAction: true)
        #expect(state.userSetSidebarVisibility)
        state.setSidebarVisible(true, isUserAction: false)
        #expect(!state.isSidebarVisible)
    }

    @Test("Focus availability reads the same flag")
    func focusFollowsTheSameState() {
        let state = CalendarState()
        state.isInspectorVisible = false

        state.setSidebarVisible(true, isUserAction: true)
        #expect(state.availableFocusRegions(allDayRowVisible: false).contains(.sidebar))

        state.setSidebarVisible(false, isUserAction: true)
        #expect(!state.availableFocusRegions(allDayRowVisible: false).contains(.sidebar),
                "⇥ must not land on a sidebar that is not on screen")
    }
}
