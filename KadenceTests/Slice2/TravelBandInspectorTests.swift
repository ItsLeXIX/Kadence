//
//  TravelBandInspectorTests.swift
//  KadenceTests
//
//  PHASE3-SLICE2-PLAN.md task 16 — components.md §25 (the band, live), §29
//  (block, inspector), §24.10; layouts.md §6, §6.1; interactions.md §15.1,
//  §15.2. Dataset `travel`, legs from the real coordinator.
//

import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import Kadence

@MainActor
@Suite(.serialized)
struct TravelBandInspectorTests {
    typealias F = TravelFixtures
    let mon0600 = F.m(0, "06:00")
    let cal = TravelFixtures.calendar

    func names(_ rig: TravelRig) -> [String: String] { rig.coordinator.placeNames() }

    func info(_ rig: TravelRig, _ title: String, day: Int) throws -> TravelInfo {
        let leg = try require(rig.leg(title, day: day))
        return TravelPresentation.info(LegValues(leg), placeNames: names(rig), calendar: cal)
    }

    @Test("The band for every §24.4 leg: `Leave 08:15 · 35min`, departAt → start, the mode's glyph; none without a time")
    func bands() async throws {
        let rig = try TravelRig(now: mon0600)
        await rig.launchAndSettle()
        for (title, day, depart, minutes, glyph) in [("SWQM-ILV", 0, "08:15", 35, "tram.fill"),
                                                     ("SWEN3-LAB", 1, "09:15", 35, "tram.fill"),
                                                     ("EPC-ILV", 3, "12:15", 35, "tram.fill"),
                                                     ("Dinner with flatmates", 3, "17:45", 35, "tram.fill"),
                                                     ("SWRM-ILV", 4, "15:15", 35, "tram.fill"),
                                                     ("Early study group", 5, "06:45", 35, "tram.fill"),
                                                     ("Climbing", 6, "17:45", 5, "figure.walk")] {
            let band = try require(try info(rig, title, day: day).band, title)
            let label = TravelPresentation.bandLabel(band, height: 30, calendar: cal)
            #expect(label.time == "Leave \(depart)" && label.minutes == "· \(minutes)min", "\(title)")
            #expect(band.mode.glyph == glyph, "\(title)")
            let event = try require(rig.event(title, day: day))
            #expect(band.departAt.addingTimeInterval(band.duration + 600) == event.start, "\(title)")
        }
        // Same place, online, chained: no leg, no band.
        for (title, day) in [("SWEN3-ILV", 1), ("INNO3-EL", 2), ("REQEN-EXAM", 3), ("Laundry", 2)] {
            #expect(rig.leg(title, day: day) == nil, "\(title)")
        }
        // Below 18pt the minutes drop; below 14pt the glyph only.
        let band = try require(try info(rig, "SWQM-ILV", day: 0).band)
        #expect(TravelPresentation.bandLabel(band, height: 16, calendar: cal) == ("Leave 08:15", nil))
        #expect(TravelPresentation.bandLabel(band, height: 12, calendar: cal) == (nil, nil))
    }

    @Test("Estimates: `Leave 08:15 · ≈35min`, `Leave ≈08:15` below 18pt; pending / unavailable: no band")
    func estimatesAndNoTime() async throws {
        let offline = try TravelRig(now: mon0600, variant: .travelOffline,
                                    provider: ReviewTravel.provider(dataset: .travel, variant: .travelOffline))
        await offline.launchAndSettle()
        let band = try require(try info(offline, "SWQM-ILV", day: 0).band)
        #expect(band.isEstimate)
        #expect(TravelPresentation.bandLabel(band, height: 30, calendar: cal) == ("Leave 08:15", "· ≈35min"))
        #expect(TravelPresentation.bandLabel(band, height: 16, calendar: cal) == ("Leave ≈08:15", nil))
        #expect(try info(offline, "Dinner with flatmates", day: 3).band == nil)
        let pending = try TravelRig(now: mon0600, variant: .travelPending,
                                    provider: ReviewTravel.provider(dataset: .travel, variant: .travelPending))
        pending.coordinator.launched()
        pending.clock.advance(by: 5)
        #expect(try info(pending, "SWQM-ILV", day: 0).band == nil)
    }

    @Test("Hover help exact: ready, estimate, where you are, each reason; buffer 0 without the buffer term")
    func hoverHelp() {
        let id = UUID()
        func leg(_ status: TravelLegStatus, reason: TravelReason? = nil, buffer: TimeInterval = 600,
                 origin: TravelOriginKind = .place, mode: TravelMode = .transit) -> LegValues {
            LegValues(eventID: id, status: status, reason: reason, reasonPlaceID: reason == .needsAddress ? "home" : nil,
                      retryAt: reason == .paused ? F.m(0, "10:40") : nil,
                      departAt: status == .ready || status == .estimate ? F.m(0, "08:15") : nil,
                      duration: status == .ready || status == .estimate ? 2100 : nil, buffer: buffer, mode: mode,
                      originKind: origin, originPlaceID: origin == .place ? "home" : nil, destinationPlaceID: "campus",
                      source: "mock", computedAt: mon0600)
        }
        let names = ["home": "Home", "campus": "FH Technikum Wien"]
        func help(_ l: LegValues) -> String? {
            let i = TravelPresentation.info(l, placeNames: names, calendar: cal)
            return i.band.map { TravelPresentation.bandHelp($0, calendar: cal) } ?? i.helpSuffix
        }
        #expect(help(leg(.ready)) == "Leave 08:15 · 35 min by public transport from Home · 10 min buffer")
        #expect(help(leg(.ready, buffer: 0)) == "Leave 08:15 · 35 min by public transport from Home")
        #expect(help(leg(.estimate, reason: .offline))
                == "Leave about 08:15 · about 35 min by public transport from Home · 10 min buffer · estimate, offline")
        #expect(help(leg(.ready, origin: .currentLocation)) == "Leave 08:15 · 35 min by public transport from where you are · 10 min buffer")
        #expect(help(leg(.pending, reason: .pending)) == "· Travel time from Home not worked out yet")
        #expect(help(leg(.unavailable, reason: .offline)) == "· Travel time from Home unavailable: offline")
        #expect(help(leg(.unavailable, reason: .needsAddress)) == "· Travel time from Home unavailable: Home has no address")
        #expect(help(leg(.unavailable, reason: .noRoute, mode: .walking)) == "· Travel time from Home unavailable: no route walking")
        #expect(help(leg(.unavailable, reason: .paused)) == "· Travel time from Home unavailable: Apple Maps paused until 10:40")
        #expect(help(leg(.unavailable, reason: .failed)) == "· Travel time from Home unavailable: Apple Maps didn't answer")
    }

    @Test("VoiceOver exactly as §29 for SWQM-ILV: ready, estimate, pending, unavailable")
    func voiceOver() async throws {
        func label(_ rig: TravelRig) throws -> String {
            let event = try require(rig.event("SWQM-ILV", day: 0))
            var model = GridBlockModel(event: event, now: mon0600, sources: .testTimetable)
            model.travelSpoken = rig.coordinator.travelInfo()[event.id]?.spoken
            return model.accessibilityLabel(presentation: [])
        }
        let ready = try TravelRig(now: mon0600)
        await ready.launchAndSettle()
        #expect(try label(ready) == "SWQM-ILV, 09:00 to 10:30, leave by 08:15, 35 minutes by public transport from Home, lecture, University timetable")
        let offline = try TravelRig(now: mon0600, variant: .travelOffline,
                                    provider: ReviewTravel.provider(dataset: .travel, variant: .travelOffline))
        await offline.launchAndSettle()
        #expect(try label(offline) == "SWQM-ILV, 09:00 to 10:30, leave by about 08:15, about 35 minutes by public transport from Home, estimate, lecture, University timetable")
        let pending = try TravelRig(now: mon0600, variant: .travelPending,
                                    provider: ReviewTravel.provider(dataset: .travel, variant: .travelPending))
        pending.coordinator.launched()
        #expect(try label(pending) == "SWQM-ILV, 09:00 to 10:30, travel time from Home not worked out yet, lecture, University timetable")
        let noAddress = try TravelRig(now: mon0600, variant: .travelNoAddress)
        noAddress.coordinator.launched()
        #expect(try label(noAddress) == "SWQM-ILV, 09:00 to 10:30, travel time from Home unavailable, Home has no address, lecture, University timetable")
    }

    func row(_ rig: TravelRig, _ title: String, day: Int, now: Date? = nil) throws -> TravelPresentation.LeaveByRow {
        let leg = try require(rig.leg(title, day: day))
        return TravelPresentation.leaveBy(LegValues(leg), placeNames: names(rig), now: now ?? rig.clock.now,
                                          pausedUntil: rig.queue.plannerState.pausedUntil, calendar: cal)
    }

    @Test("Inspector copy for §30 items 9–12, 20, 21, exact")
    func inspectorCopy() async throws {
        let rig = try TravelRig(now: mon0600)
        await rig.launchAndSettle()
        // Item 9: SWQM-ILV.
        let swqm = try row(rig, "SWQM-ILV", day: 0)
        #expect(swqm.value == "08:15" && swqm.word == nil)
        #expect(swqm.lines == ["35 min by public transport from Home · 10 min buffer", "Worked out today 06:00 by Apple Maps."])
        #expect(swqm.spoken == "Leave by, 08:15, 35 minutes by public transport from Home, plus 10 minutes buffer, worked out at 06:00 by Apple Maps")
        // Item 10: REQEN-EXAM — no leg, `No travel needed after EPC-ILV`.
        let reqen = try require(rig.event("REQEN-EXAM", day: 3))
        #expect(rig.coordinator.leg(for: reqen.id) == nil)
        #expect(rig.coordinator.chainedTitle(for: reqen.id).map(TravelPresentation.noTravelLine) == "No travel needed after EPC-ILV")
        // Item 11: Dinner, from campus.
        #expect(try row(rig, "Dinner with flatmates", day: 3).lines.first == "35 min by public transport from FH Technikum Wien · 10 min buffer")
        // Item 12: no address.
        let noAddress = try TravelRig(now: mon0600, variant: .travelNoAddress)
        noAddress.coordinator.launched()
        let unavailable = try row(noAddress, "SWQM-ILV", day: 0)
        #expect(unavailable.value == "Unavailable" && unavailable.valueIsSecondary)
        #expect(unavailable.lines == ["Add the address of Home in Settings ▸ Travel so Kadence can work out the trip."])
        #expect(unavailable.action == .addAddress && unavailable.action?.rawValue == "Add Address…")
        #expect(unavailable.spoken == "Leave by, unavailable, Add the address of Home in Settings ▸ Travel so Kadence can work out the trip.")
        // Item 20: EPC-ILV estimate; Dinner unavailable · offline.
        let offline = try TravelRig(now: mon0600, variant: .travelOffline,
                                    provider: ReviewTravel.provider(dataset: .travel, variant: .travelOffline))
        await offline.launchAndSettle()
        let epc = try row(offline, "EPC-ILV", day: 3)
        #expect(epc.value == "12:15" && epc.word == "estimate")
        #expect(epc.lines == ["About 35 min by public transport from Home · 10 min buffer",
                              "Last worked out 27 Sep 18:00 by Apple Maps. Couldn't update: this Mac is offline. Kadence will ask Apple Maps again when it's back online."])
        #expect(epc.spoken.hasPrefix("Leave by, about 12:15, estimate, about 35 minutes by public transport from Home"))
        #expect(epc.spoken.hasSuffix("couldn't update, offline"))
        let dinner = try row(offline, "Dinner with flatmates", day: 3)
        #expect(dinner.value == "Unavailable")
        #expect(dinner.lines == ["This Mac is offline. Kadence will ask Apple Maps again when it's back online."])
        // Item 21: Climbing, noRoute.
        let noRoute = try TravelRig(now: mon0600, variant: .travelNoRoute,
                                    provider: ReviewTravel.provider(dataset: .travel, variant: .travelNoRoute))
        await noRoute.launchAndSettle()
        let climbing = try row(noRoute, "Climbing", day: 6)
        #expect(climbing.lines == ["Apple Maps has no route walking for this trip at this time. Choose another way to travel between these places in Settings ▸ Travel."])
        #expect(climbing.action == .changeWay)
        let leg = try require(noRoute.leg("Climbing", day: 6))
        #expect(TravelInspectorRows.focus(for: .changeWay, leg: LegValues(leg)) == .pair("home", TravelDataset.gymID))
        let swqmLeg = try require(noAddress.leg("SWQM-ILV", day: 0))
        #expect(TravelInspectorRows.focus(for: .addAddress, leg: LegValues(swqmLeg)) == .address(placeID: "home"))
        // Never an address or a coordinate in any inspector string.
        for r in [swqm, unavailable, epc, dinner, climbing] {
            for text in r.lines + [r.value, r.spoken] {
                #expect(!text.contains("Example") && !text.contains("Höchstädtplatz"))
                #expect(text.range(of: #"\d+\.\d{3,}"#, options: .regularExpression) == nil)
            }
        }
    }

    @Test("Try Again queues one priority-0 request; while paused it is disabled with `Kadence will try at HH:mm`")
    func tryAgain() async throws {
        let rig = try TravelRig(now: mon0600)
        await rig.launchAndSettle()
        let event = try require(rig.event("EPC-ILV", day: 3))
        let sent = rig.queue.history.count
        rig.coordinator.tryAgain(eventID: event.id)
        await rig.run(for: 5)
        #expect(rig.queue.history.count == sent + 1)
        // Paused: the button is disabled with the resume time.
        let failed = LegValues(eventID: event.id, status: .unavailable, reason: .failed, buffer: 600, mode: .transit,
                               originPlaceID: "home", destinationPlaceID: "campus")
        let paused = TravelPresentation.leaveBy(failed, placeNames: names(rig), now: mon0600,
                                                pausedUntil: F.m(0, "06:20"), calendar: cal)
        #expect(paused.action == .tryAgain && paused.disabledHelp == "Kadence will try at 06:20")
        let free = TravelPresentation.leaveBy(failed, placeNames: names(rig), now: mon0600, pausedUntil: nil, calendar: cal)
        #expect(free.disabledHelp == nil)
    }

    @Test("Set Place is one undo step; the current place writes nothing; the pop-up's items in order")
    func setPlace() async throws {
        let rig = try TravelRig(now: mon0600)
        let dinner = try require(rig.event("Dinner with flatmates", day: 3))
        rig.store.setPlace(dinner, to: TravelDataset.gymID)
        #expect(dinner.placeID == TravelDataset.gymID && rig.undo.undoActionName == "Set Place")
        rig.store.setPlace(dinner, to: TravelDataset.gymID)
        rig.undo.undo()
        #expect(dinner.placeID == "home" && !rig.undo.canUndo)
        // Never on an imported event.
        let epc = try require(rig.event("EPC-ILV", day: 3))
        rig.store.setPlace(epc, to: "home")
        #expect(epc.placeID == nil)
        let places = rig.coordinator.placeNames()
        let ordered = try rig.context.fetch(FetchDescriptor<KnownPlace>(sortBy: [SortDescriptor(\.sortIndex)])).map { places[$0.id]! }
        #expect(TravelInspectorRows.popupItems(placeNames: ordered)
                == ["None", "—", "Home", "FH Technikum Wien", "Gym", "—", "Edit Places…"])
    }

    @Test("The Leave by row never uses semantic.now (source scan)")
    func neverNow() throws {
        let text = try String(contentsOf: Fixture.repoRoot.appendingPathComponent("Kadence/Views/Chrome/TravelInspectorRows.swift"),
                              encoding: .utf8)
        #expect(!text.contains("Semantic.now"))
    }

    // MARK: Renders

    @Test("Task 16 renders: bands (case 1, case 2, estimate) and the inspector items")
    func renders() async throws {
        let rig = try TravelRig(now: mon0600)
        await rig.launchAndSettle()
        let swqm = try require(try info(rig, "SWQM-ILV", day: 0).band)
        let climbing = try require(try info(rig, "Climbing", day: 6).band)
        let bands = VStack(alignment: .leading, spacing: 12) {
            TravelBandView(band: swqm, renderedHeight: 33, calendar: cal).frame(width: 160)
            TravelBandView(band: climbing, renderedHeight: Tokens.Size.travelBandHeight, calendar: cal).frame(width: 160)
            TravelBandView(band: { var b = swqm; b.isEstimate = true; return b }(), renderedHeight: 33, calendar: cal).frame(width: 160)
            TravelBandView(band: { var b = swqm; b.isEstimate = true; return b }(), renderedHeight: 16, calendar: cal).frame(width: 160)
        }
        .padding(12)
        .background(Tokens.Color.Surface.canvas)
        #expect(Slice2Render.render("band-states", bands, size: CGSize(width: 184, height: 150)) != nil)

        func inspector(_ name: String, _ r: TravelRig, _ title: String, day: Int) throws {
            let event = try require(r.event(title, day: day))
            let view = InspectorView(event: event, dayEvents: [], day: event.start, now: r.clock.now,
                                     store: r.store)
                .environment(r.coordinator)
                .environment(SourcesRouter())
                .environment(CalendarState())
                .environment(r.undo)
                .environment(SyncCoordinator(context: r.context, secrets: InMemorySecretStore(), scheduling: FakeScheduling(),
                                             path: FakePath()) { _ in GatedSource(.failure(.offline)) })
                .frame(width: Tokens.Size.inspectorWidthDefault, height: 620)
            #expect(Slice2Render.render(name, view, size: CGSize(width: Tokens.Size.inspectorWidthDefault, height: 620)) != nil)
        }
        try inspector("inspector-swqm-leave", rig, "SWQM-ILV", day: 0)
        try inspector("inspector-reqen-no-travel", rig, "REQEN-EXAM", day: 3)
        try inspector("inspector-dinner-place", rig, "Dinner with flatmates", day: 3)
        let noAddress = try TravelRig(now: mon0600, variant: .travelNoAddress)
        noAddress.coordinator.launched()
        try inspector("inspector-no-address", noAddress, "SWQM-ILV", day: 0)
        let offline = try TravelRig(now: mon0600, variant: .travelOffline,
                                    provider: ReviewTravel.provider(dataset: .travel, variant: .travelOffline))
        await offline.launchAndSettle()
        try inspector("inspector-epc-estimate", offline, "EPC-ILV", day: 3)
        try inspector("inspector-dinner-unavailable", offline, "Dinner with flatmates", day: 3)
        let noRoute = try TravelRig(now: mon0600, variant: .travelNoRoute,
                                    provider: ReviewTravel.provider(dataset: .travel, variant: .travelNoRoute))
        await noRoute.launchAndSettle()
        try inspector("inspector-climbing-no-route", noRoute, "Climbing", day: 6)
    }
}
