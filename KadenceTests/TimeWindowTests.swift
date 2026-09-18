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

    @Test("makeTimeWindows describes the same two windows as the display-only TimeWindowFixture array")
    func makeTimeWindowsMatchesFixtures() {
        let windows = MockData.makeTimeWindows()
        #expect(windows.count == MockData.timeWindows.count)

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
    }

    @Test("seedTimeWindowsIfNeeded is idempotent: calling it twice still leaves exactly 2 rows")
    func seedingIsIdempotent() throws {
        let context = try makeContext()

        MockData.seedTimeWindowsIfNeeded(context)
        let firstPass = try context.fetch(FetchDescriptor<TimeWindow>())
        #expect(firstPass.count == 2)

        MockData.seedTimeWindowsIfNeeded(context)
        let secondPass = try context.fetch(FetchDescriptor<TimeWindow>())
        #expect(secondPass.count == 2)
    }
}
