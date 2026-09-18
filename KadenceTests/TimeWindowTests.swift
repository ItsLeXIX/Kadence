//
//  TimeWindowTests.swift
//  KadenceTests
//
//  Task P2-T18's persisted `TimeWindow` data model (Kadence/Models/TimeWindow.swift).
//  Same in-memory ModelContainer/ModelContext pattern as RoutineEngineTests.swift.
//  Data-layer-only: no UI, no scheduling change, so these tests cover model
//  init, SwiftData round-tripping, and seeding idempotency — nothing else.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

@MainActor
private func makeContext() throws -> ModelContext {
    let container = try ModelContainer(
        for: Event.self, Place.self, RoutineTemplate.self, RoutineBlock.self, TimeWindow.self,
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    return ModelContext(container)
}

@Suite("TimeWindow model")
@MainActor
struct TimeWindowModelTests {

    @Test("init sets all fields correctly")
    func initSetsFields() {
        let window = TimeWindow(
            weekdays: [2, 3, 4, 5, 6],
            startMinutes: 13 * 60,
            endMinutes: 14 * 60 + 30,
            kind: .lowEnergy,
            label: "Low energy")

        #expect(window.weekdays == [2, 3, 4, 5, 6])
        #expect(window.startMinutes == 13 * 60)
        #expect(window.endMinutes == 14 * 60 + 30)
        #expect(window.kind == .lowEnergy)
        #expect(window.label == "Low energy")
    }

    @Test("kind round-trips for every case, same computed-property pattern as RoutineBlock.flexibility",
          arguments: TimeWindowKind.allCases)
    func kindRoundTripsForEveryCase(_ kind: TimeWindowKind) {
        let window = TimeWindow(kind: kind)
        #expect(window.kind == kind)
    }

    @Test("round-trips through a real in-memory ModelContainer/ModelContext")
    func roundTripsThroughPersistence() throws {
        let context = try makeContext()
        let window = TimeWindow(
            weekdays: Set(1...7),
            startMinutes: 22 * 60,
            endMinutes: 7 * 60,
            kind: .protected,
            label: "Sleep")
        context.insert(window)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<TimeWindow>())
        #expect(fetched.count == 1)
        let round = try #require(fetched.first)
        #expect(round.id == window.id)
        #expect(round.weekdays == Set(1...7))
        #expect(round.startMinutes == 22 * 60)
        #expect(round.endMinutes == 7 * 60)
        #expect(round.kind == .protected)
        #expect(round.label == "Sleep")
    }
}

@Suite("MockData time window seeding")
@MainActor
struct TimeWindowSeedingTests {

    // Task P2-T20 added a third, peak-focus entry to `makeTimeWindows()`
    // (components.md §17 item 2: "a protected, a low-energy AND a peak-focus
    // window" must exist for review). `MockData.timeWindows` — the separate,
    // display-only fixture array the main grid actually renders — stays at
    // two on purpose (peak-focus never renders there, §7), so the two lists
    // are no longer the same length; this test no longer asserts they are.
    @Test("makeTimeWindows describes the same Sleep/Low-energy pair as the display-only TimeWindowFixture array, plus a peak-focus window")
    func makeTimeWindowsMatchesFixtures() {
        let windows = MockData.makeTimeWindows()
        #expect(windows.count == 3)
        #expect(MockData.timeWindows.count == 2)

        let sleep = windows.first { $0.label == "Sleep" }
        let sleepFixture = MockData.timeWindows.first { $0.label == "Sleep" }
        #expect(sleep?.weekdays == sleepFixture?.weekdays)
        #expect(sleep?.startMinutes == sleepFixture?.startMinutes)
        #expect(sleep?.endMinutes == sleepFixture?.endMinutes)
        #expect(sleep?.kind == sleepFixture?.kind)

        let lowEnergy = windows.first { $0.label == "Low energy" }
        let lowEnergyFixture = MockData.timeWindows.first { $0.label == "Low energy" }
        #expect(lowEnergy?.weekdays == lowEnergyFixture?.weekdays)
        #expect(lowEnergy?.startMinutes == lowEnergyFixture?.startMinutes)
        #expect(lowEnergy?.endMinutes == lowEnergyFixture?.endMinutes)
        #expect(lowEnergy?.kind == lowEnergyFixture?.kind)

        // The new peak-focus fixture has no display-only counterpart to
        // compare against (§7 — peak-focus never renders on the main grid),
        // so it is checked against its own literal values instead.
        let peakFocus = windows.first { $0.kind == .peakFocus }
        #expect(peakFocus?.label == "Deep work")
        #expect(peakFocus?.weekdays == [2, 3, 4, 5, 6])
        #expect(peakFocus?.startMinutes == 15 * 60)
        #expect(peakFocus?.endMinutes == 17 * 60)

        // Chosen (per this task's own header comment) to sit clear of the
        // low-energy window rather than overlap it — pin that down, since a
        // future edit to either window's hours could silently reintroduce
        // an overlap the "legible side by side" reasoning depends on.
        #expect((lowEnergyFixture?.endMinutes ?? 0) <= (peakFocus?.startMinutes ?? 0))
    }

    @Test("seedTimeWindowsIfNeeded is idempotent: calling it twice still leaves exactly 3 rows")
    func seedingIsIdempotent() throws {
        let context = try makeContext()

        MockData.seedTimeWindowsIfNeeded(context)
        let firstPass = try context.fetch(FetchDescriptor<TimeWindow>())
        #expect(firstPass.count == 3)

        MockData.seedTimeWindowsIfNeeded(context)
        let secondPass = try context.fetch(FetchDescriptor<TimeWindow>())
        #expect(secondPass.count == 3)
    }
}
