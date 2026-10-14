//
//  TravelCoordinatorTests.swift
//  KadenceTests
//
//  PHASE3-SLICE2-PLAN.md task 6 — components.md §24.5–§24.8, §24.6
//  (departure refreshes), §23.6 (the campus's automatic lookup), §20.8.4
//  ("Local identity"), §20.9. Dataset `travel` in an in-memory store, the
//  mock provider and geocoder, the injected manual clock.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

@MainActor
@Suite(.serialized)
struct TravelCoordinatorTests {
    let mon0600 = TravelFixtures.m(0, "06:00")

    @Test("The dataset seeds as §30.1 says: 14 VEVENTs → 13 timetable events (2 history), places, Sleep, P1–P5")
    func dataset() throws {
        let rig = try TravelRig(now: mon0600)
        let timetable = rig.events().filter { $0.sourceID == TravelDataset.sourceID }
        #expect(timetable.count == 13)
        #expect(timetable.filter { $0.start < mon0600 }.count == 2)
        #expect(rig.events().filter { $0.origin == .manual && $0.placeID != nil }.count == 4)
        let places = try rig.context.fetch(FetchDescriptor<KnownPlace>(sortBy: [SortDescriptor(\.sortIndex)]))
        #expect(places.map(\.name) == ["Home", "FH Technikum Wien", "Gym"])
        #expect(places.allSatisfy { $0.geocodeState == .confirmed && $0.hasCoordinate })
        #expect(try rig.context.fetchCount(FetchDescriptor<TimeWindow>()) == 1)
        #expect(ReviewTravelTemplate.text.components(separatedBy: "BEGIN:VEVENT").count - 1 == 14)
    }

    @Test("§24.4 through the coordinator; two recomputes of the same inputs write nothing the second time")
    func idempotent() async throws {
        let rig = try TravelRig(now: mon0600)
        await rig.launchAndSettle()
        #expect(rig.hhmm(rig.leg("SWQM-ILV", day: 0)?.departAt) == "08:15")
        #expect(rig.leg("SWQM-ILV", day: 0)?.status == .ready)
        #expect(rig.hhmm(rig.leg("Dinner with flatmates", day: 3)?.departAt) == "17:45")
        #expect(rig.hhmm(rig.leg("Climbing", day: 6)?.departAt) == "17:45")
        #expect(rig.leg("SWEN3-ILV", day: 1) == nil)
        #expect(rig.legs().count == 11)
        #expect(await rig.provider.callCount == 7)
        #expect(rig.coordinator.recompute() == 0)
        #expect(rig.coordinator.recompute() == 0)
        #expect(await rig.provider.callCount == 7)
    }

    @Test("A mode change changes today's and future legs, asks for the new keys, and leaves yesterday's leg byte-equal")
    func modeChange() async throws {
        let rig = try TravelRig(now: mon0600)
        await rig.launchAndSettle()
        let monday = try require(rig.leg("SWQM-ILV", day: 0))
        let before = LegValues(monday)
        // The next day: Monday's leg is history.
        rig.clock.set(TravelFixtures.m(1, "06:00"))
        rig.coordinator.dayChanged()
        await rig.run(for: 60)
        let calls = await rig.provider.callCount
        TravelBuiltIns.settings(in: rig.context).preferredTravelMode = .driving
        try rig.context.save()
        rig.coordinator.recompute()
        await rig.run(for: 120)
        #expect(LegValues(try require(rig.leg("SWQM-ILV", day: 0))) == before)
        #expect(rig.leg("SWEN3-LAB", day: 1)?.mode == .driving)
        #expect(rig.leg("SWQM-ILV", day: 7)?.mode == .driving)
        // The mock has no driving route: noRoute, unavailable, never a guess.
        #expect(rig.leg("SWEN3-LAB", day: 1)?.status == .unavailable)
        #expect(rig.leg("SWEN3-LAB", day: 1)?.unavailableReason == .noRoute)
        let after = await rig.provider.calls.dropFirst(calls)
        #expect(!after.isEmpty && after.allSatisfy { $0.mode == .driving || $0.mode == .walking })
        // Home ↔ Gym keeps its override (walking): already cached, not asked.
        #expect(rig.leg("Climbing", day: 6)?.mode == .walking)
    }

    @Test("Delete an event → its leg is gone in the same transaction; undo → back after the next recompute, no provider call")
    func deleteAndUndo() async throws {
        let rig = try TravelRig(now: mon0600)
        await rig.launchAndSettle()
        let dinner = try require(rig.event("Dinner with flatmates", day: 3))
        let id = dinner.id
        #expect(rig.coordinator.leg(for: id) != nil)
        rig.store.delete(dinner)
        #expect(rig.coordinator.leg(for: id) == nil)
        let calls = await rig.provider.callCount
        rig.undo.undo()
        #expect(rig.coordinator.leg(for: id) == nil)
        rig.coordinator.recompute()
        await rig.run(for: 10)
        #expect(rig.coordinator.leg(for: id)?.status == .ready)
        #expect(rig.hhmm(rig.coordinator.leg(for: id)?.departAt) == "17:45")
        #expect(await rig.provider.callCount == calls)
    }

    @Test("A recompute leaves every event's §20.8.4 hash, the feedHash, lastChange* and the undo stack unchanged")
    func neverWritesEvents() async throws {
        let rig = try TravelRig(now: mon0600)
        func snapshot() throws -> ([UUID: String], String?, [Int], Date?, Bool) {
            let hashes = Dictionary(uniqueKeysWithValues: rig.events().map {
                ($0.id, EventHash.of($0, zone: TravelFixtures.zone) + "|\($0.status)|\($0.placeID ?? "")|\($0.start)")
            })
            let source = try require(try rig.context.fetch(FetchDescriptor<Source>()).first { $0.id == TravelDataset.sourceID })
            return (hashes, source.feedHash, [source.lastChangeAdded, source.lastChangeUpdated, source.lastChangeRemoved],
                    source.lastChangeAt, rig.undo.canUndo)
        }
        let before = try snapshot()
        await rig.launchAndSettle()
        rig.coordinator.recompute()
        let after = try snapshot()
        #expect(after.0 == before.0)
        #expect(after.1 == before.1 && after.2 == before.2 && after.3 == before.3)
        #expect(after.4 == before.4 && !after.4)
    }

    @Test("§30.1 Sync: reportChanged at Mon 06:00 — legs row for row, the moved and new lectures from the cache")
    func syncTable() async throws {
        let rig = try TravelRig(now: mon0600)
        await rig.launchAndSettle()
        let swqm = try require(rig.event("SWQM-ILV", day: 0))
        let swqmLeg = LegValues(try require(rig.coordinator.leg(for: swqm.id)))
        let swrmLeg = LegValues(try require(rig.leg("SWRM-ILV", day: 4)))
        let oldLab = try require(rig.event("SWEN3-LAB", day: 1)).id
        let oldEPC = try require(rig.event("EPC-ILV", day: 3)).id
        #expect(rig.leg("REQEN-EXAM", day: 3) == nil)
        let calls = await rig.provider.callCount

        try rig.sync(ReviewFeed.reportTravelChanged(template: ReviewTravelTemplate.text, today: mon0600, m: TravelRig.m,
                                                    zone: TravelFixtures.zone))
        // The applier deleted the vanished and moved events' legs with them.
        #expect(rig.coordinator.leg(for: oldLab) == nil && rig.coordinator.leg(for: oldEPC) == nil)
        rig.coordinator.recompute()
        await rig.run(for: 60)

        // SWQM-ILV: in place, same id; leg unchanged, computedAt unchanged.
        #expect(rig.event("SWQM-ILV", day: 0)?.id == swqm.id)
        #expect(rig.event("SWQM-ILV", day: 0)?.lecturers == ["L09"])
        #expect(LegValues(try require(rig.coordinator.leg(for: swqm.id))) == swqmLeg)
        // SWEN3-LAB: delete + add; the new event's leg departs 09:15, from
        // the cache; SWEN3-ILV still chained.
        let lab = try require(rig.event("SWEN3-LAB", day: 1))
        #expect(lab.id != oldLab && lab.location?.name == "EDV_F4.26")
        #expect(rig.hhmm(rig.coordinator.leg(for: lab.id)?.departAt) == "09:15")
        #expect(rig.leg("SWEN3-ILV", day: 1) == nil)
        // EPC-ILV gone: REQEN-EXAM loses its chain — home, depart 15:15.
        #expect(rig.event("EPC-ILV", day: 3) == nil)
        #expect(rig.hhmm(rig.leg("REQEN-EXAM", day: 3)?.departAt) == "15:15")
        #expect(rig.leg("REQEN-EXAM", day: 3)?.originPlaceID == "home")
        // SWRM-ILV loses L06 in place: leg unchanged.
        #expect(LegValues(try require(rig.leg("SWRM-ILV", day: 4))) == swrmLeg)
        // New KOKU-UE M + 9 10:00: depart 09:15, the 09:30 slot already cached.
        #expect(rig.hhmm(rig.leg("KOKU-UE", day: 9)?.departAt) == "09:15")
        #expect(await rig.provider.callCount == calls)
    }

    @Test("50 event writes in 0.2 s → one pass; 10 answers arriving together → one pass")
    func debounce() async throws {
        let rig = try TravelRig(now: mon0600)
        rig.coordinator.startObserving()
        await rig.launchAndSettle()
        let passes = rig.coordinator.passCount
        let laundry = try require(rig.event("Laundry", day: 2))
        for i in 0..<50 {
            laundry.notes = "note \(i)"
            try rig.context.save()
            rig.clock.advance(by: 0.004)
        }
        await rig.run(for: 5)
        #expect(rig.coordinator.passCount == passes + 1)
        // Ten answers at once.
        let job = RouteRequestQueue.ETAJob(key: "x", origin: TravelEndpoint(id: "home", latitude: 48.2, longitude: 16.39),
                                           destination: TravelEndpoint(id: "campus", latitude: 48.239, longitude: 16.377),
                                           mode: .transit, arrivingBy: mon0600, purpose: .change, request: nil)
        for _ in 0..<10 { rig.queue.onETA?(job, .failure(.failed), rig.clock.now) }
        await rig.run(for: 5)
        #expect(rig.coordinator.passCount == passes + 2)
        // A leg write is not an input: no further pass.
        await rig.run(for: 5)
        #expect(rig.coordinator.passCount == passes + 2)
    }

    @Test("Refresh schedule: 09:15 and 11:30 for a 12:15 departure; a moved event re-plans; a missed slot runs once at wake, never after the start")
    func refreshSchedule() async throws {
        let rig = try TravelRig(now: TravelFixtures.m(3, "06:00"))
        await rig.launchAndSettle()
        let epc = try require(rig.event("EPC-ILV", day: 3))
        #expect(rig.coordinator.plannedSlots[epc.id]?.map { rig.hhmm($0) } == ["09:15", "11:30"])
        let dinner = try require(rig.event("Dinner with flatmates", day: 3))
        #expect(rig.coordinator.plannedSlots[dinner.id]?.map { rig.hhmm($0) } == ["14:45", "17:00"])
        rig.store.move(dinner, by: 30 * 60)
        rig.coordinator.recompute()
        await rig.run(for: 10)
        #expect(rig.coordinator.plannedSlots[dinner.id]?.map { rig.hhmm($0) } == ["15:15", "17:30"])
        // Asleep from 06:02 to 10:00: EPC-ILV's 09:15 slot was missed.
        let sent = rig.queue.history.count
        rig.clock.set(TravelFixtures.m(3, "10:00"))
        rig.coordinator.didWake()
        await rig.run(for: 10)
        let refreshes = rig.queue.history.dropFirst(sent).filter { $0.id.hasPrefix("refresh:") }
        #expect(refreshes.map(\.id) == ["refresh:\(epc.id.uuidString)"])
        // A second wake in the same window: not again.
        rig.coordinator.didWake()
        await rig.run(for: 10)
        #expect(rig.queue.history.dropFirst(sent).filter { $0.id.hasPrefix("refresh:") }.count == 1)
        // After the start: none.
        let after = rig.queue.history.count
        rig.clock.set(TravelFixtures.m(3, "13:05"))
        rig.coordinator.didWake()
        await rig.run(for: 10)
        #expect(!rig.queue.history.dropFirst(after).contains { $0.id == "refresh:\(epc.id.uuidString)" })
    }

    @Test("§30.1 Departure refresh: the T−45 refresh answering 50 / 78 / 30 min moves departAt to 12:00 / 11:32 / 12:20",
          arguments: [(50, "12:00"), (78, "11:32"), (30, "12:20")])
    func departureRefresh(minutes: Int, depart: String) async throws {
        let rig = try TravelRig(now: TravelFixtures.m(3, "11:00"))
        // Launch at 11:00: the leg has no time yet, so its first request
        // (35 min) stands for the missed T−3 h refresh (B51).
        await rig.launchAndSettle()
        let epc = try require(rig.event("EPC-ILV", day: 3))
        #expect(rig.hhmm(rig.coordinator.leg(for: epc.id)?.departAt) == "12:15")
        await rig.provider.set(.minutes(minutes), for: .init(from: "home", to: "campus", mode: .transit))
        await rig.run(until: TravelFixtures.m(3, "11:31"))
        let leg = try require(rig.coordinator.leg(for: epc.id))
        #expect(rig.hhmm(leg.departAt) == depart)
        #expect(leg.duration == TimeInterval(minutes * 60) && leg.status == .ready)
        #expect(leg.refreshedAt != nil && rig.hhmm(leg.refreshedAt) == "11:30")
        #expect(rig.log.lines.contains("eta ok · \(minutes) min · transit · refresh"))
        // One refresh — the 11:30 one — and no second T−45 refresh when the
        // new departure moves the slot.
        await rig.run(until: TravelFixtures.m(3, "12:00"))
        #expect(rig.queue.history.filter { $0.id == "refresh:\(epc.id.uuidString)" }.count == 1)
        try RoutingLogCheck.assertForms(rig.log.lines)
    }

    @Test("Ready vs estimate in a refresh window: the 11:30 refresh failing offline → estimate (offline)")
    func refreshFailure() async throws {
        let rig = try TravelRig(now: TravelFixtures.m(3, "11:00"))
        await rig.launchAndSettle()
        await rig.provider.answerEverything(.failure(.offline))
        await rig.run(until: TravelFixtures.m(3, "11:31"))
        let leg = try require(rig.leg("EPC-ILV", day: 3))
        #expect(leg.status == .estimate && leg.unavailableReason == .offline && leg.isEstimate)
        #expect(rig.hhmm(leg.departAt) == "12:15")
    }

    // MARK: The campus (§23.6)

    /// An empty store (built-ins only) with Home confirmed and one lecture.
    func campusRig(now: Date, geocoder: any PlaceGeocoder) throws -> TravelRig {
        let rig = try TravelRig(now: now, seed: false, geocoder: geocoder)
        let home = try require(try rig.context.fetch(FetchDescriptor<KnownPlace>()).first { $0.id == "home" })
        home.addressText = "Example Gasse 5, 1030 Wien"
        home.confirmedAddress = "Example Gasse 5, 1030 Wien, Austria"
        home.setCoordinate(latitude: 48.2, longitude: 16.39)
        home.geocodeState = .confirmed
        let source = Source.connected(id: TravelDataset.sourceID, displayName: "University timetable",
                                      serverURL: "https://cis.technikum-wien.at", username: "user01",
                                      principalHref: nil, calendarHomeHref: nil, calendars: [],
                                      capabilities: SourceCapabilities(), paletteKey: .blue)
        rig.context.insert(source)
        rig.context.insert(Event(title: "EPC-ILV", start: TravelFixtures.m(3, "13:00"), end: TravelFixtures.m(3, "14:30"),
                                 origin: .imported, sourceKey: .blue, location: Place(name: "LAB_F5.12"),
                                 sourceID: TravelDataset.sourceID, externalID: "epc"))
        try rig.context.save()
        return rig
    }

    func campus(_ rig: TravelRig) throws -> KnownPlace {
        try require(try rig.context.fetch(FetchDescriptor<KnownPlace>()).first { $0.id == "campus" })
    }

    @Test("Campus lookup: a matching first result → confirmed, the coordinate stored; legs pending until it answers")
    func campusConfirmed() async throws {
        let rig = try campusRig(now: TravelFixtures.m(0, "06:00"), geocoder: MockPlaceGeocoder(case: .none))
        rig.coordinator.launched()
        #expect(rig.leg("EPC-ILV", day: 3)?.status == .pending)
        await rig.run(for: 120)
        let campus = try campus(rig)
        #expect(campus.geocodeState == .confirmed)
        #expect(campus.latitude == 48.2390 && campus.longitude == 16.3770)
        #expect(campus.confirmedAddress == "Höchstädtplatz 6, 1200 Wien, Austria")
        #expect(rig.leg("EPC-ILV", day: 3)?.status == .ready)
        #expect(rig.log.lines.contains("lookup ok · 1 results"))
        // Never an automatic lookup for Home: one query, the campus's.
        #expect(await (rig.geocoder as! MockPlaceGeocoder).queries == ["Höchstädtplatz 6, 1200 Wien"])
    }

    @Test("Campus lookup: a non-matching first result → unconfirmed, legs unavailable · needsAddress (campus)")
    func campusNotMatching() async throws {
        let geocoder = ScriptedGeocoder(.success([GeocodedAddress(line: "Höchstädtplatz 6, 3500 Krems, Austria",
                                                                  latitude: 48.4, longitude: 15.6)]))
        let rig = try campusRig(now: TravelFixtures.m(0, "06:00"), geocoder: geocoder)
        await rig.launchAndSettle()
        #expect(try campus(rig).geocodeState == .unconfirmed && !(try campus(rig).hasCoordinate))
        let leg = try require(rig.leg("EPC-ILV", day: 3))
        #expect(leg.status == .unavailable && leg.unavailableReason == .needsAddress && leg.reasonPlaceID == "campus")
        // Answered: never looked up again on its own.
        rig.clock.set(TravelFixtures.m(1, "06:00"))
        rig.coordinator.launched()
        await rig.run(for: 60)
        #expect(await geocoder.queries.count == 1)
    }

    @Test("Campus lookup: offline → lookupFailed, no second attempt the same day; retried at the next launch")
    func campusOffline() async throws {
        let geocoder = ScriptedGeocoder(.failure(.offline))
        let rig = try campusRig(now: TravelFixtures.m(0, "06:00"), geocoder: geocoder)
        await rig.launchAndSettle()
        #expect(try campus(rig).geocodeState == .lookupFailed)
        #expect(rig.leg("EPC-ILV", day: 3)?.unavailableReason == .needsAddress)
        rig.coordinator.recompute()
        rig.coordinator.didWake()
        rig.coordinator.launched()
        await rig.run(for: 600)
        #expect(await geocoder.queries.count == 1)
        await geocoder.set(.success([MockPlaceGeocoder.campus]))
        rig.clock.set(TravelFixtures.m(1, "06:00"))
        rig.coordinator.launched()
        await rig.run(for: 120)
        #expect(await geocoder.queries.count == 2)
        #expect(try campus(rig).geocodeState == .confirmed)
        #expect(rig.leg("EPC-ILV", day: 3)?.status == .ready)
    }

    @Test("NSCalendarDayChanged at midnight moves the ownership window")
    func dayChangeMovesWindow() async throws {
        let rig = try TravelRig(now: TravelFixtures.m(0, "23:50"))
        rig.coordinator.startObserving()
        await rig.launchAndSettle()
        // Mon's SWQM-ILV is today until midnight: a change of the buffer
        // still rewrites it.
        let before = LegValues(try require(rig.leg("SWQM-ILV", day: 0)))
        rig.clock.set(TravelFixtures.m(1, "00:00"))
        NotificationCenter.default.post(name: .NSCalendarDayChanged, object: nil)
        await rig.run(for: 5)
        TravelBuiltIns.settings(in: rig.context).travelBufferMinutes = 20
        try rig.context.save()
        await rig.run(for: 120)
        #expect(LegValues(try require(rig.leg("SWQM-ILV", day: 0))) == before)
        #expect(rig.leg("SWEN3-LAB", day: 1)?.buffer == 1200)
    }

    @Test("A recompute during a conflict preview changes no event (a preview only moves routine blocks, transparent to travel)")
    func previewUntouched() async throws {
        let rig = try TravelRig(now: mon0600)
        await rig.launchAndSettle()
        let before = rig.events().map { ($0.id, $0.start, $0.end, $0.title, $0.status) }
        rig.coordinator.recompute()
        let after = rig.events().map { ($0.id, $0.start, $0.end, $0.title, $0.status) }
        #expect(before.elementsEqual(after) { $0 == $1 })
    }
}
