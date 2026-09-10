//
//  FocusRegionTests.swift
//  KadenceTests
//
//  interactions.md §1 — the ⇥ cycle. The skipping and wrapping rules are a pure
//  function on `CalendarState.FocusRegion` precisely so they can be checked here
//  rather than by tabbing around the app by hand.
//

import Testing
import Foundation
@testable import Kadence

private typealias Region = CalendarState.FocusRegion

private let allVisible: Set<Region> = [.sidebar, .allDayRow, .grid, .inspector]

@Suite("Region focus cycling")
@MainActor
struct FocusRegionTests {

    @Test("Forward order follows the spec list")
    func forwardOrder() {
        #expect(Region.next(after: .sidebar, available: allVisible) == .allDayRow)
        #expect(Region.next(after: .allDayRow, available: allVisible) == .grid)
        #expect(Region.next(after: .grid, available: allVisible) == .inspector)
    }

    @Test("The last region wraps to the first")
    func wrapsForward() {
        #expect(Region.next(after: .inspector, available: allVisible) == .sidebar)
    }

    @Test("⇧⇥ walks the same order backwards, and wraps")
    func backwards() {
        #expect(Region.next(after: .grid, backwards: true, available: allVisible) == .allDayRow)
        #expect(Region.next(after: .sidebar, backwards: true, available: allVisible) == .inspector)
    }

    @Test("A hidden all-day row is skipped in both directions")
    func skipsHiddenAllDayRow() {
        let available: Set<Region> = [.sidebar, .grid, .inspector]
        #expect(Region.next(after: .sidebar, available: available) == .grid)
        #expect(Region.next(after: .grid, backwards: true, available: available) == .sidebar)
    }

    @Test("A collapsed inspector is skipped, and the grid wraps to the sidebar")
    func skipsCollapsedInspector() {
        let available: Set<Region> = [.sidebar, .allDayRow, .grid]
        #expect(Region.next(after: .grid, available: available) == .sidebar)
        #expect(Region.next(after: .sidebar, backwards: true, available: available) == .grid)
    }

    @Test("With both hidden, ⇥ toggles between sidebar and grid")
    func twoRegions() {
        let available: Set<Region> = [.sidebar, .grid]
        #expect(Region.next(after: .sidebar, available: available) == .grid)
        #expect(Region.next(after: .grid, available: available) == .sidebar)
    }

    @Test("With one region available, ⇥ is a no-op rather than a trap")
    func singleRegion() {
        #expect(Region.next(after: .grid, available: [.grid]) == .grid)
        #expect(Region.next(after: .grid, backwards: true, available: [.grid]) == .grid)
    }

    @Test("Cycling from a region that is no longer available still lands somewhere")
    func currentRegionVanished() {
        // The inspector can collapse while focused — auto-collapse on resize.
        let available: Set<Region> = [.sidebar, .grid]
        let next = Region.next(after: .inspector, available: available)
        #expect(available.contains(next))
    }

    @Test("An empty availability set cannot spin forever")
    func noRegions() {
        #expect(Region.next(after: .grid, available: []) == .grid)
    }

    @Test("A full forward lap visits every available region exactly once")
    func fullLap() {
        var seen: [Region] = []
        var current = Region.sidebar
        for _ in 0..<allVisible.count {
            seen.append(current)
            current = Region.next(after: current, available: allVisible)
        }
        #expect(Set(seen) == allVisible, "every region must be reachable: \(seen)")
        #expect(seen.count == Set(seen).count, "no region visited twice in one lap")
        #expect(current == .sidebar, "the lap closes")
    }
}

@Suite("Which regions ⇥ can reach")
@MainActor
struct FocusAvailabilityTests {

    @Test("The grid is always reachable")
    func gridAlwaysAvailable() {
        let state = CalendarState()
        state.isInspectorVisible = false
        state.setSidebarVisible(false, isUserAction: true)
        let available = state.availableFocusRegions(allDayRowVisible: false)
        #expect(available == [.grid])
    }

    @Test("Availability tracks what is actually on screen")
    func tracksVisibility() {
        let state = CalendarState()
        state.isInspectorVisible = true
        state.setSidebarVisible(true, isUserAction: true)
        let available = state.availableFocusRegions(allDayRowVisible: true)
        #expect(available == [.sidebar, .allDayRow, .grid, .inspector])
    }

    @Test("The toolbar is not a ⇥ stop in Phase 1")
    func toolbarExcluded() {
        // Deliberate and documented in STATUS.md: SwiftUI toolbar items are not
        // addressable as a focus region. Asserted so that if it ever becomes one,
        // this test is the reminder to update the spec note with it.
        let state = CalendarState()
        state.isInspectorVisible = true
        let available = state.availableFocusRegions(allDayRowVisible: true)
        #expect(!available.contains(.toolbar))
    }
}
