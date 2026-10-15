//
//  TravelSettingsPlacesTests.swift
//  KadenceTests
//
//  PHASE3-SLICE2-PLAN.md task 13 — layouts.md §11 (three tabs), §13
//  (Places); components.md §23.1, §23.5, §23.6; interactions.md §15.3,
//  §15.4; §29 (Settings rows). The view model and the store, with the mock
//  geocoder through the routing queue; offscreen renders of the real pane.
//

import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import Kadence

@MainActor
@Suite(.serialized)
struct TravelSettingsPlacesTests {
    let now = TravelFixtures.m(0, "10:00")

    final class Counter { var value = 0 }

    func model(_ rig: TravelRig, recomputes: Counter = Counter()) -> TravelSettingsModel {
        TravelSettingsModel(context: rig.context, queue: rig.queue, clock: rig.clock, calendar: TravelFixtures.calendar,
                            recompute: { recomputes.value += 1 })
    }

    func emptyRig(_ lookup: MockPlaceGeocoder.Case = .one) throws -> (TravelRig, MockPlaceGeocoder) {
        let geocoder = MockPlaceGeocoder(case: lookup)
        return (try TravelRig(now: now, seed: false, geocoder: geocoder), geocoder)
    }

    func home(_ m: TravelSettingsModel) throws -> KnownPlace { try require(m.place("home")) }

    @Test("Committing an unchanged address → no lookup; a changed one → exactly one; typing without committing → none")
    func commitRules() async throws {
        let (rig, geocoder) = try emptyRig()
        let m = model(rig)
        m.drafts["home"] = "Example Straße 1"
        await rig.run(for: 5)
        #expect(await geocoder.lookupCount == 0)
        #expect(m.commitAddress("home"))
        await rig.run(for: 5)
        #expect(await geocoder.queries == ["Example Straße 1"])
        #expect(!m.commitAddress("home"))           // unchanged: the field shows what was typed
        m.confirmSelection("home")
        #expect(!m.commitAddress("home"))           // unchanged: the confirmed address
        await rig.run(for: 5)
        #expect(await geocoder.lookupCount == 1)
    }

    @Test("Each mock case's line and controls, exact (§23.5)", arguments: MockPlaceGeocoder.Case.allCases)
    func lines(_ lookup: MockPlaceGeocoder.Case) async throws {
        let (rig, _) = try emptyRig(lookup)
        let m = model(rig)
        m.drafts["home"] = lookup == .none ? "Exampel Strasse 1" : "Example Straße 1"
        m.commitAddress("home")
        // `searching` holds the lookup in flight (the queue is not run).
        if lookup != .searching { await rig.run(for: 5) }
        let line = try require(m.line(for: try home(m)))
        switch lookup {
        case .one:
            #expect(line.texts == ["Found: Example Straße 1, 1020 Wien, Austria"])
            #expect(line.controls == [.cancel, .useThisAddress] && line.defaultControl == .useThisAddress)
        case .several:
            #expect(line.texts == ["3 addresses match. Choose one:"])
            #expect(line.matches.count == 3 && line.controls == [.cancel] && line.defaultControl == nil)
        case .many:
            #expect(line.texts == ["More than 5 addresses match. Add the postcode or district, for example 1200 Wien."])
            #expect(line.matches.count == 5)
        case .none:
            #expect(line.texts == ["No address found for “Exampel Strasse 1”. Check the spelling, or add the postcode or district."])
            #expect(line.controls == [.cancel])
            #expect(try home(m).geocodeState == .notFound)
        case .offline:
            #expect(line.texts == ["Couldn't look up the address because this Mac is offline."])
            #expect(line.controls == [.tryAgain, .cancel])
            #expect(try home(m).geocodeState == .lookupFailed)
        case .searching:
            #expect(line.texts == ["Looking up…"] && line.showsSpinner && line.controls.isEmpty)
        }
    }

    @Test("Paused after a throttle: `Apple Maps asked Kadence to wait. Try again at HH:mm.`")
    func paused() async throws {
        let (rig, _) = try emptyRig()
        await rig.provider.answerEverything(.failure(.throttled))
        let request = TravelLegPlanner.Request(
            key: "k", origin: TravelFixtures.home.endpoint!, destination: TravelFixtures.campus.endpoint!, mode: .transit,
            arrivingBy: now, priority: 4, eventStart: now, eventIDs: [], dayType: .weekday, slotMinutes: 600,
            originPlaceID: "home", destinationPlaceID: "campus")
        rig.queue.syncPlanned([request])
        await rig.queue.settle()
        let m = model(rig)
        m.drafts["home"] = "Example Straße 1"
        m.commitAddress("home")
        #expect(m.line(for: try home(m))?.texts == ["Apple Maps asked Kadence to wait. Try again at 10:10."])
        #expect(m.line(for: try home(m))?.controls == [.tryAgain, .cancel])
    }

    @Test("Use This Address / a row → confirmed, coordinate, geocodedAt, a recompute; Cancel → the previous address, nothing written")
    func confirmAndCancel() async throws {
        let (rig, _) = try emptyRig(.several)
        let counter = Counter()
        let m = model(rig, recomputes: counter)
        m.drafts["home"] = "Example Straße 1"
        m.commitAddress("home")
        await rig.run(for: 5)
        m.confirm("home", MockPlaceGeocoder.several[1])
        let place = try home(m)
        #expect(place.confirmedAddress == "Example Straße 1, 1210 Wien, Austria")
        #expect(place.latitude == 48.2600 && place.longitude == 16.4000)
        #expect(place.geocodeState == .confirmed && place.geocodedAt == rig.clock.now && counter.value == 1)
        #expect(m.line(for: place) == nil && m.fieldText(place) == "Example Straße 1, 1210 Wien, Austria")
        // A new lookup, then Cancel: the previous confirmed address stays.
        m.drafts["home"] = "Other Street 2"
        m.commitAddress("home")
        await rig.run(for: 5)
        m.cancel("home")
        #expect(place.confirmedAddress == "Example Straße 1, 1210 Wien, Austria" && place.latitude == 48.2600)
        #expect(place.addressText == "Example Straße 1" && place.geocodeState == .confirmed)
        #expect(m.fieldText(place) == "Example Straße 1, 1210 Wien, Austria" && counter.value == 1)
    }

    @Test("A new address on a confirmed place keeps the old coordinate until confirmed (`Still using …`); clearing → none, legs needsAddress")
    func stillUsingAndClear() async throws {
        let rig = try TravelRig(now: now)
        await rig.launchAndSettle()
        let m = model(rig)
        let gym = try require(m.place(TravelDataset.gymID))
        m.drafts[gym.id] = "Example Straße 9"
        m.commitAddress(gym.id)
        await rig.run(for: 5)
        #expect(gym.latitude == 48.2050 && gym.longitude == 16.3950)
        let line = try require(m.line(for: gym))
        #expect(line.texts == ["Found: Example Straße 1, 1020 Wien, Austria",
                               "Still using Example Straße 1, 1020 Wien, Austria."])
        // Clearing Home: none, and every leg touching Home needs its address.
        m.drafts["home"] = ""
        m.commitAddress("home")
        let home = try require(m.place("home"))
        #expect(home.geocodeState == GeocodeState.none && !home.hasCoordinate && home.addressText == nil)
        rig.coordinator.recompute()
        await rig.run(for: 5)
        #expect(rig.leg("EPC-ILV", day: 3)?.unavailableReason == .needsAddress)
        #expect(rig.leg("EPC-ILV", day: 3)?.reasonPlaceID == "home")
    }

    @Test("Leaving with a result unconfirmed → unconfirmed; `Look Up` → one lookup")
    func leaveUnconfirmed() async throws {
        let (rig, geocoder) = try emptyRig()
        let m = model(rig)
        m.drafts["home"] = "Example Straße 1"
        m.commitAddress("home")
        await rig.run(for: 5)
        m.leave()
        let place = try home(m)
        #expect(place.geocodeState == .unconfirmed && place.addressText == "Example Straße 1" && !place.hasCoordinate)
        #expect(m.line(for: place)?.texts == ["Not confirmed yet. Kadence can't work out trips to or from Home until you do."])
        #expect(m.line(for: place)?.controls == [.lookUp])
        m.lookUpAgain("home")
        await rig.run(for: 5)
        #expect(await geocoder.lookupCount == 2)
    }

    @Test("Names revert when empty or taken; Add Place → New Place, New Place 2; removal asks with the exact text")
    func namesAddRemove() async throws {
        let rig = try TravelRig(now: now)
        let m = model(rig)
        #expect(!m.commitName("home", "  "))
        #expect(!m.commitName("home", "gym"))
        #expect(m.place("home")?.name == "Home")
        #expect(m.commitName("home", " Flat "))
        #expect(m.place("home")?.name == "Flat")
        let first = m.addPlace(), second = m.addPlace()
        #expect(m.place(first)?.name == "New Place" && m.place(second)?.name == "New Place 2")
        #expect(m.place(first)?.geocodeState == GeocodeState.none)
        // Gym: Climbing is at it, plus one more manual event.
        let extra = Event(title: "Stretch", start: TravelFixtures.m(8, "18:00"), end: TravelFixtures.m(8, "19:00"),
                          sourceID: "personal")
        extra.placeID = TravelDataset.gymID
        rig.context.insert(extra)
        try rig.context.save()
        let question = try require(m.removalQuestion(TravelDataset.gymID))
        #expect(question.message == "Remove “Gym”?")
        #expect(question.informative == "2 events are at Gym. They will have no place, and no leave-by.")
        m.remove(TravelDataset.gymID)
        #expect(m.place(TravelDataset.gymID) == nil)
        #expect(rig.events().allSatisfy { $0.placeID != TravelDataset.gymID })
        #expect(try rig.context.fetch(FetchDescriptor<TravelModeOverride>()).isEmpty)
        #expect(try rig.context.fetch(FetchDescriptor<TravelETACache>()).allSatisfy {
            $0.originPlaceID != TravelDataset.gymID && $0.destinationPlaceID != TravelDataset.gymID
        })
        // Unused: removed at once. One event: singular.
        #expect(m.removalQuestion(first) == nil)
        m.remove(first)
        #expect(m.place(first) == nil)
        let lone = m.addPlace()
        extra.placeID = lone
        try rig.context.save()
        #expect(m.removalQuestion(lone)?.informative.hasPrefix("1 event is at New Place") == true)
        // Built-ins have no remove.
        #expect(m.removalQuestion("home") == nil && m.removalQuestion("campus") == nil)
        m.remove("campus")
        #expect(m.place("campus") != nil)
    }

    @Test("Keyboard: ↓ into the match list, ↑ / ↓ within it, ↩ confirms, ⎋ cancels")
    func keyboard() async throws {
        let (rig, _) = try emptyRig(.several)
        let m = model(rig)
        m.drafts["home"] = "Example Straße 1"
        m.commitAddress("home")
        await rig.run(for: 5)
        #expect(m.selectedMatch["home"] == nil)
        m.moveSelection("home", by: 1)
        #expect(m.selectedMatch["home"] == 0)
        m.moveSelection("home", by: 1); m.moveSelection("home", by: 1); m.moveSelection("home", by: 1)
        #expect(m.selectedMatch["home"] == 2)
        m.moveSelection("home", by: -1)
        m.confirmSelection("home")
        #expect(try home(m).confirmedAddress == "Example Straße 1, 1210 Wien, Austria")
        m.drafts["home"] = "Another 3"
        m.commitAddress("home")
        await rig.run(for: 5)
        m.cancel("home")
        #expect(m.line(for: try home(m)) == nil)
    }

    @Test("§29: the Settings ▸ Travel rows' labels")
    func voiceOver() {
        #expect(TravelSettingsModel.nameFieldLabel == "Place name")
        #expect(TravelSettingsModel.addressFieldLabel("Home") == "Address of Home")
        #expect(TravelSettingsModel.removeLabel("Gym") == "Remove Gym")
        #expect(TravelSettingsModel.matchRowLabel(MockPlaceGeocoder.one[0]) == "Example Straße 1, 1020 Wien, Austria")
        #expect(TravelSettingsModel.matchLines("Example Straße 1, 1020 Wien, Austria") == ("Example Straße 1", "1020 Wien, Austria"))
    }

    // MARK: Renders (offscreen, §17.2 rule 3)

    func render(_ name: String, _ m: TravelSettingsModel, rig: TravelRig, height: CGFloat = 300) {
        rig.keepAlive()
        let view = TravelSettingsForm(model: m, showsTravelSections: false)
            .environment(SourcesRouter())
            .frame(width: Tokens.Size.settingsWindowWidth, height: height)
        #expect(Slice2Render.render(name, view, size: CGSize(width: Tokens.Size.settingsWindowWidth, height: height)) != nil)
    }

    @Test("Task 13 renders: first run, filled, and item 18's lookup frames")
    func renders() async throws {
        let (first, _) = try emptyRig()
        let firstModel = model(first)
        // §30 item 1: the campus as the mock geocoder confirmed it at the
        // first launch (§23.6, P3S2-F04: no review switch).
        first.coordinator.launched()
        await first.run(for: 10)
        render("settings-travel-first-run", firstModel, rig: first)

        let filled = try TravelRig(now: now)
        render("settings-travel-filled", model(filled), rig: filled)

        for lookup in MockPlaceGeocoder.Case.allCases {
            let (rig, _) = try emptyRig(lookup)
            // Dataset `empty`: the campus confirmed at the first launch.
            rig.coordinator.launched()
            await rig.run(for: 10)
            let m = model(rig)
            m.drafts["home"] = lookup == .none ? "Exampel Strasse 1" : "Example Straße 1"
            m.commitAddress("home")
            if lookup != .searching { await rig.run(for: 5) }
            render("settings-travel-lookup-\(lookup.rawValue)", m, rig: rig, height: lookup == .many || lookup == .several ? 440 : 300)
        }
        let still = try TravelRig(now: now)
        let m = model(still)
        m.drafts[TravelDataset.gymID] = "Example Straße 9"
        m.commitAddress(TravelDataset.gymID)
        await still.run(for: 5)
        render("settings-travel-lookup-still-using", m, rig: still, height: 380)
    }
}
