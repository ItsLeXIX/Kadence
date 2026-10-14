//
//  TravelSettingsWaysTests.swift
//  KadenceTests
//
//  PHASE3-SLICE2-PLAN.md task 14 — layouts.md §13 (Ways to travel, Leave
//  by, Where you are); components.md §23.3, §23.4, §24.12; interactions.md
//  §15.5; §29. The model with the mock location source and an injected URL
//  opener; offscreen renders of the real pane.
//

import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import Kadence

@MainActor
@Suite(.serialized)
struct TravelSettingsWaysTests {
    let now = TravelFixtures.m(0, "06:00")

    final class Opened { var urls: [URL] = [] }

    func model(_ rig: TravelRig, location: MockLocationSource? = nil, opened: Opened = Opened()) -> TravelSettingsModel {
        let m = TravelSettingsModel(context: rig.context, queue: rig.queue, clock: rig.clock, calendar: TravelFixtures.calendar,
                                    recompute: { [weak coordinator = rig.coordinator] in coordinator?.requestRecompute() })
        m.location = location ?? rig.location
        m.openURL = { opened.urls.append($0) }
        return m
    }

    @Test("Pair rows in §13's order; Walking stores one override, Usual deletes it; both recompute, asking only uncached keys")
    func pairs() async throws {
        let rig = try TravelRig(now: now)
        await rig.launchAndSettle()
        let m = model(rig)
        #expect(m.pairs.map(\.label) == ["Home ↔ FH Technikum Wien", "Home ↔ Gym", "FH Technikum Wien ↔ Gym"])
        let homeCampus = m.pairs[0]
        #expect(m.mode(for: homeCampus) == nil && m.mode(for: m.pairs[1]) == .walking)
        let calls = await rig.provider.callCount
        m.setMode(.walking, for: homeCampus)
        #expect(try rig.context.fetch(FetchDescriptor<TravelModeOverride>()).count == 2)
        await rig.run(for: 60)
        #expect(rig.leg("SWQM-ILV", day: 0)?.mode == .walking)
        let walkingCalls = await rig.provider.calls.dropFirst(calls)
        #expect(!walkingCalls.isEmpty && walkingCalls.allSatisfy { $0.mode == .walking })
        // Usual: the override goes; the transit answers are still cached.
        let before = await rig.provider.callCount
        m.setMode(nil, for: homeCampus)
        #expect(try rig.context.fetch(FetchDescriptor<TravelModeOverride>()).count == 1)
        await rig.run(for: 60)
        #expect(rig.leg("SWQM-ILV", day: 0)?.mode == .transit && rig.leg("SWQM-ILV", day: 0)?.status == .ready)
        #expect(await rig.provider.callCount == before)
    }

    @Test("The pop-ups never offer Cycling or Any; Usually is Public transport · Walking · Driving")
    func choices() {
        #expect(TravelSettingsModel.modeChoices == [.transit, .walking, .driving])
        #expect(TravelSettingsModel.modeChoices.map(\.settingsLabel) == ["Public transport", "Walking", "Driving"])
        #expect(!TravelMode.allCases.map(\.rawValue).contains { $0.lowercased().contains("cycl") || $0 == "any" })
    }

    @Test("Buffer None … 30 minutes; a change moves every future leg's departAt and its arrival slot (new keys asked)")
    func buffer() async throws {
        #expect(TravelSettingsModel.bufferChoices.map(TravelSettingsModel.bufferLabel)
                == ["None", "5 minutes", "10 minutes", "15 minutes", "20 minutes", "30 minutes"])
        let rig = try TravelRig(now: now)
        await rig.launchAndSettle()
        let m = model(rig)
        let calls = await rig.provider.callCount
        m.setBuffer(0)
        await rig.run(for: 60)
        let leg = try require(rig.leg("SWQM-ILV", day: 0))
        #expect(leg.buffer == 0 && rig.hhmm(leg.departAt) == "08:25")
        // Arrival 09:00 is the 09:00 slot, not 08:30: a new key was asked.
        let asked = await rig.provider.calls.dropFirst(calls)
        #expect(asked.contains { $0.arrivingBy == TravelFixtures.m(0, "09:00") })
        m.setBuffer(7)   // not a choice
        #expect(m.bufferMinutes == 0)
    }

    @Test("Location blocks: denied, servicesOff, notDetermined after an ask — exact; none for allowed, never asked, or the switch off")
    func blocks() async throws {
        let rig = try TravelRig(now: now)
        func block(_ state: LocationAuthorization, asked: Bool = false, on: Bool = true) async -> TravelSettingsModel.LocationBlock? {
            let m = model(rig, location: MockLocationSource(authorization: state))
            TravelBuiltIns.settings(in: rig.context).locationRequestedAt = asked ? now : nil
            m.setUsesCurrentLocation(on)
            await m.refreshLocation()
            return m.locationBlock
        }
        let denied = await block(.denied)
        #expect(denied?.title == "Location is off for Kadence")
        #expect(denied?.body == "Kadence works out each trip from Home or from your previous event instead. To use where you are, allow Kadence in System Settings ▸ Privacy & Security ▸ Location Services.")
        #expect(denied?.button == .openSystemSettings && denied?.button.rawValue == "Open System Settings…")
        let off = await block(.servicesOff)
        #expect(off?.title == "Location Services are off")
        #expect(off?.body == "Location Services are off on this Mac, so Kadence works out each trip from Home or from your previous event.")
        #expect(off?.button == .openSystemSettings)
        let notYet = await block(.notDetermined, asked: true)
        #expect(notYet?.title == "Location isn't allowed yet")
        #expect(notYet?.body == "Kadence can use where you are to work out the trip to your next event.")
        #expect(notYet?.button.rawValue == "Allow Location…")
        #expect(await block(.allowed) == nil)
        #expect(await block(.notDetermined, asked: false) == nil)
        #expect(await block(.denied, on: false) == nil)
    }

    @Test("Open System Settings… → the opener gets the Location Services URL; Allow Location… asks once, or opens it")
    func buttons() async throws {
        let rig = try TravelRig(now: now)
        let opened = Opened()
        let denied = model(rig, location: MockLocationSource(authorization: .denied), opened: opened)
        await denied.locationButton(.openSystemSettings)
        #expect(opened.urls.map(\.absoluteString)
                == ["x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"])
        // notDetermined, and macOS prompts (the mock becomes allowed): one request, no opener.
        let prompts = MockLocationSource(authorization: .notDetermined, afterRequest: .allowed)
        let ask = Opened()
        let a = model(rig, location: prompts, opened: ask)
        await a.allowLocation()
        #expect(await prompts.requestCalls == 1)
        #expect(ask.urls.isEmpty)
        #expect(TravelBuiltIns.settings(in: rig.context).locationRequestedAt != nil)
        // A source that answers without prompting: the opener.
        let silent = MockLocationSource(authorization: .notDetermined)
        let quiet = Opened()
        let b = model(rig, location: silent, opened: quiet)
        await b.allowLocation()
        #expect(await silent.requestCalls == 1)
        #expect(quiet.urls.count == 1)
    }

    @Test("Opening the tab never asks for location")
    func openingNeverAsks() async throws {
        let rig = try TravelRig(now: now)
        let location = MockLocationSource(authorization: .notDetermined)
        let m = model(rig, location: location)
        await m.refreshLocation()
        #expect(await location.requestCalls == 0)
        #expect(await location.fixCalls == 0)
        #expect(m.locationState == .notDetermined && m.locationBlock == nil)
    }

    @Test("§29: Usually, the pair pop-ups and the switch")
    func voiceOver() throws {
        let rig = try TravelRig(now: now)
        let m = model(rig)
        #expect(TravelSettingsModel.usuallyLabel == "Usual way to travel" && m.preferredMode.settingsLabel == "Public transport")
        let homeGym = try require(m.pairs.first { $0.label == "Home ↔ Gym" })
        #expect(TravelSettingsModel.pairLabel(homeGym) == "Way to travel, Home to Gym")
        #expect(m.pairValue(homeGym) == "Walking")
        #expect(m.pairValue(m.pairs[0]) == "Usual, public transport")
        #expect(TravelSettingsModel.locationSwitchLabel == "Use where you are for the next departure")
    }

    // MARK: Renders

    func render(_ name: String, _ m: TravelSettingsModel, height: CGFloat = 440) {
        let view = TravelSettingsForm(model: m)
            .environment(SourcesRouter())
            .frame(width: Tokens.Size.settingsWindowWidth, height: height)
        #expect(Slice2Render.render(name, view, size: CGSize(width: Tokens.Size.settingsWindowWidth, height: height)) != nil)
    }

    @Test("Task 14 renders: ways to travel; the location states")
    func renders() async throws {
        let rig = try TravelRig(now: now)
        let ways = model(rig)
        // The pane scrolls inside its Form (layouts.md §11): a tall render
        // shows every section at once.
        render("settings-travel-ways", ways, height: 900)
        for (name, state, asked, on) in [("denied", LocationAuthorization.denied, false, true),
                                         ("services-off", .servicesOff, false, true),
                                         ("not-allowed-yet", .notDetermined, true, true),
                                         ("switch-off", .denied, false, false)] {
            let r = try TravelRig(now: now)
            let m = model(r, location: MockLocationSource(authorization: state))
            TravelBuiltIns.settings(in: r.context).locationRequestedAt = asked ? now : nil
            m.setUsesCurrentLocation(on)
            await m.refreshLocation()
            render("settings-travel-location-\(name)", m, height: 900)
        }
    }
}
