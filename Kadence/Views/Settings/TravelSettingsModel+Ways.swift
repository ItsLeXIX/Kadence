//
//  TravelSettingsModel+Ways.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 14) — layouts.md §13 (Ways
//  to travel, Leave by, Where you are); components.md §23.3, §23.4, §24.12;
//  interactions.md §15.5; §29. Settings edits: written at once, not undo
//  steps, followed by a leg recompute.
//

import Foundation
import SwiftData

extension TravelSettingsModel {

    // MARK: Ways to travel (§23.3)

    var settings: AppSettings { TravelBuiltIns.settings(in: context) }

    /// `Usually`: `Public transport` · `Walking` · `Driving` — never cycling,
    /// never `.any` (G-095).
    static let modeChoices: [TravelMode] = TravelMode.allCases

    var preferredMode: TravelMode {
        _ = revision
        return settings.preferredTravelMode
    }

    func setPreferredMode(_ mode: TravelMode) {
        guard mode != settings.preferredTravelMode else { return }
        settings.preferredTravelMode = mode
        save()
    }

    /// One row per unordered pair of known places: pairs with `home` first
    /// (by the other place's `sortIndex`), then the rest by `sortIndex`.
    struct Pair: Identifiable, Equatable {
        var a: KnownPlaceRef
        var b: KnownPlaceRef
        var id: String { "\(a.id)|\(b.id)" }
        var label: String { "\(a.name) ↔ \(b.name)" }
    }

    struct KnownPlaceRef: Equatable {
        var id: String
        var name: String
    }

    var pairs: [Pair] {
        let list = places.map { KnownPlaceRef(id: $0.id, name: $0.name) }
        var result: [Pair] = []
        if let home = list.first(where: { $0.id == BuiltInPlace.home.id }) {
            for other in list where other.id != home.id { result.append(Pair(a: home, b: other)) }
        }
        let rest = list.filter { $0.id != BuiltInPlace.home.id }
        for (i, a) in rest.enumerated() {
            for b in rest[(i + 1)...] { result.append(Pair(a: a, b: b)) }
        }
        return result
    }

    /// A pair's mode, or nil for `Usual`.
    func mode(for pair: Pair) -> TravelMode? {
        _ = revision
        return TravelModeOverrides.find(pair.a.id, pair.b.id, in: context)?.mode
    }

    /// Choosing a mode stores one override; `Usual` (nil) deletes it.
    func setMode(_ mode: TravelMode?, for pair: Pair) {
        let existing = TravelModeOverrides.find(pair.a.id, pair.b.id, in: context)
        switch (existing, mode) {
        case (nil, nil): return
        case (let row?, nil): context.delete(row)
        case (let row?, let mode?):
            guard row.mode != mode else { return }
            row.mode = mode
        case (nil, let mode?):
            context.insert(TravelModeOverride(pair.a.id, pair.b.id, mode: mode))
        }
        save()
    }

    // MARK: Leave by (§23.4)

    static let bufferChoices = [0, 5, 10, 15, 20, 30]

    static func bufferLabel(_ minutes: Int) -> String { minutes == 0 ? "None" : "\(minutes) minutes" }

    var bufferMinutes: Int {
        _ = revision
        return settings.travelBufferMinutes
    }

    func setBuffer(_ minutes: Int) {
        guard Self.bufferChoices.contains(minutes), minutes != settings.travelBufferMinutes else { return }
        settings.travelBufferMinutes = minutes
        save()
    }

    // MARK: Where you are (§24.2.1, §24.12)

    var usesCurrentLocation: Bool {
        _ = revision
        return settings.useCurrentLocation
    }

    func setUsesCurrentLocation(_ on: Bool) {
        guard on != settings.useCurrentLocation else { return }
        settings.useCurrentLocation = on
        save()
    }

    static let locationSettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")!

    /// §24.12's status block: title, body and button — shown only while the
    /// switch is on, for `denied`, `servicesOff`, or `notDetermined` after
    /// Kadence asked.
    struct LocationBlock: Equatable {
        enum Button: String, Equatable { case openSystemSettings = "Open System Settings…", allowLocation = "Allow Location…" }
        var title: String
        var body: String
        var button: Button
    }

    var locationBlock: LocationBlock? {
        guard usesCurrentLocation, let state = locationState else { return nil }
        switch state {
        case .denied:
            return LocationBlock(
                title: "Location is off for Kadence",
                body: "Kadence works out each trip from Home or from your previous event instead. To use where you are, allow Kadence in System Settings ▸ Privacy & Security ▸ Location Services.",
                button: .openSystemSettings)
        case .servicesOff:
            return LocationBlock(
                title: "Location Services are off",
                body: "Location Services are off on this Mac, so Kadence works out each trip from Home or from your previous event.",
                button: .openSystemSettings)
        case .notDetermined:
            guard settings.locationRequestedAt != nil else { return nil }
            return LocationBlock(title: "Location isn't allowed yet",
                                 body: "Kadence can use where you are to work out the trip to your next event.",
                                 button: .allowLocation)
        case .allowed:
            return nil
        }
    }

    /// Re-read on launch, `didBecomeActive` and when the tab opens. Reading
    /// never asks.
    func refreshLocation() async {
        guard let location else { return }
        locationState = await location.authorization()
    }

    /// The block's button.
    func locationButton(_ button: LocationBlock.Button) async {
        switch button {
        case .openSystemSettings:
            openURL(Self.locationSettingsURL)
        case .allowLocation:
            await allowLocation()
        }
    }

    /// `Allow Location…`: asks the same way the first refresh does; if the
    /// answer is not `allowed` (macOS showed no prompt — it was answered
    /// before), opens System Settings.
    func allowLocation() async {
        guard let location else { return }
        let state = await location.authorization()
        guard state == .notDetermined else {
            openURL(Self.locationSettingsURL)
            return
        }
        if settings.locationRequestedAt == nil {
            settings.locationRequestedAt = clock.now
            try? context.save()
        }
        let after = await location.requestAuthorization()
        locationState = after
        if after != .allowed { openURL(Self.locationSettingsURL) }
    }

    // MARK: VoiceOver (§29)

    static let usuallyLabel = "Usual way to travel"
    static func pairLabel(_ pair: Pair) -> String { "Way to travel, \(pair.a.name) to \(pair.b.name)" }
    func pairValue(_ pair: Pair) -> String {
        if let mode = mode(for: pair) { return mode.settingsLabel }
        return "Usual, \(preferredMode.settingsLabel.lowercased())"
    }
    static let locationSwitchLabel = "Use where you are for the next departure"

    private func save() {
        try? context.save()
        markChanged()
        recompute()
    }
}
