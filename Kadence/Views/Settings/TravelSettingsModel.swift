//
//  TravelSettingsModel.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 13) — layouts.md §13
//  (Places), components.md §23.1, §23.5, §23.6, interactions.md §15.3,
//  §15.4, components.md §29 (Settings rows).
//
//  The Places section's state and decisions, with no SwiftUI: names,
//  addresses, the lookup (through the routing queue at priority 0), the
//  line and controls under the field in every §23.5 state (copy exact),
//  confirming, cancelling, leaving, adding and removing a place. Settings
//  edits are not undo steps (layouts.md §11); every write ends with a leg
//  recompute.
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class TravelSettingsModel {

    // MARK: The lookup's state (in memory; `searching` is never stored)

    enum Lookup: Equatable {
        case searching
        /// One or more results waiting for confirmation (at most 6 kept).
        case results([GeocodedAddress])
        case notFound(typed: String)
        case failed(GeocodeError, retryAt: Date?)
    }

    /// A control under the field (layouts.md §13).
    enum Control: String, Equatable, Sendable {
        case useThisAddress = "Use This Address"
        case cancel = "Cancel"
        case tryAgain = "Try Again"
        case lookUp = "Look Up"
    }

    /// What is drawn under a place's address field.
    struct Line: Equatable {
        /// The text lines, in order (`Still using …` last).
        var texts: [String]
        var showsSpinner = false
        /// Up to five matches (several results).
        var matches: [GeocodedAddress] = []
        var controls: [Control] = []
        /// The default button of the row (`↩`), if any.
        var defaultControl: Control?
    }

    @ObservationIgnored let context: ModelContext
    @ObservationIgnored let queue: RouteRequestQueue
    @ObservationIgnored let clock: any TravelClock
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored let recompute: () -> Void

    private(set) var lookups: [String: Lookup] = [:]
    /// The field's text while it is being edited (not yet committed).
    var drafts: [String: String] = [:]
    /// The typed text before a lookup changed it, for `Cancel`.
    @ObservationIgnored private var previousText: [String: String?] = [:]
    /// Discards a superseded lookup's answer (interactions.md §15.4).
    @ObservationIgnored private var generation: [String: Int] = [:]
    /// Keyboard selection in a match list (`↓` from the field).
    var selectedMatch: [String: Int] = [:]
    /// A revision bump so views re-read the store after a write.
    private(set) var revision = 0

    init(context: ModelContext, queue: RouteRequestQueue, clock: any TravelClock, calendar: Calendar = .current,
         recompute: @escaping () -> Void) {
        self.context = context
        self.queue = queue
        self.clock = clock
        self.calendar = calendar
        self.recompute = recompute
    }

    convenience init(context: ModelContext, travel: TravelCoordinator) {
        self.init(context: context, queue: travel.queue, clock: travel.clock, calendar: travel.calendar,
                  recompute: { [weak travel] in travel?.requestRecompute() })
    }

    // MARK: Reading

    /// Known places in display order (`sortIndex`).
    var places: [KnownPlace] {
        _ = revision
        return ((try? context.fetch(FetchDescriptor<KnownPlace>())) ?? []).sorted {
            ($0.sortIndex, $0.name) < ($1.sortIndex, $1.name)
        }
    }

    func place(_ id: String) -> KnownPlace? { places.first { $0.id == id } }

    /// The address field: the draft, else the confirmed address, else the
    /// typed text (layouts.md §13). While a new address waits for
    /// confirmation the field shows what was typed.
    func fieldText(_ place: KnownPlace) -> String {
        if let draft = drafts[place.id] { return draft }
        if lookups[place.id] != nil || (place.geocodeState != .confirmed && place.geocodeState != .none) {
            return place.addressText ?? ""
        }
        return place.confirmedAddress ?? place.addressText ?? ""
    }

    /// The line and controls under a place's field (§23.5's table, exact).
    func line(for place: KnownPlace) -> Line? {
        var line: Line?
        switch lookups[place.id] {
        case .searching:
            line = Line(texts: ["Looking up…"], showsSpinner: true)
        case .results(let found) where found.count == 1:
            line = Line(texts: ["Found: \(found[0].line)"], controls: [.cancel, .useThisAddress],
                        defaultControl: .useThisAddress)
        case .results(let found):
            let head = found.count > 5
                ? "More than 5 addresses match. Add the postcode or district, for example 1200 Wien."
                : "\(found.count) addresses match. Choose one:"
            line = Line(texts: [head], matches: Array(found.prefix(5)), controls: [.cancel])
        case .notFound(let typed):
            line = Line(texts: [Self.notFound(typed)], controls: [.cancel])
        case .failed(let error, let retry):
            line = Line(texts: [failure(error, retry: retry)], controls: [.tryAgain, .cancel])
        case nil:
            switch place.geocodeState {
            case .unconfirmed:
                line = Line(texts: ["Not confirmed yet. Kadence can't work out trips to or from \(place.name) until you do."],
                            controls: [.lookUp])
            case .notFound:
                line = Line(texts: [Self.notFound(place.addressText ?? "")], controls: [.lookUp])
            case .lookupFailed:
                line = Line(texts: ["Apple Maps didn't answer. Try again in a moment."], controls: [.tryAgain])
            case .none, .confirmed:
                line = nil
            }
        }
        // A place that keeps an older confirmed address says so.
        if let old = place.confirmedAddress, place.hasCoordinate, line != nil || place.geocodeState != .confirmed,
           fieldText(place) != old {
            line = line ?? Line(texts: [])
            line?.texts.append("Still using \(old).")
        }
        return line
    }

    static func notFound(_ typed: String) -> String {
        "No address found for “\(typed)”. Check the spelling, or add the postcode or district."
    }

    private func failure(_ error: GeocodeError, retry: Date?) -> String {
        switch error {
        case .offline: "Couldn't look up the address because this Mac is offline."
        case .throttled: "Apple Maps asked Kadence to wait. Try again at \(retry.map { TravelCopy.time($0, calendar: calendar) } ?? "a later time")."
        case .failed: "Apple Maps didn't answer. Try again in a moment."
        }
    }

    // MARK: Addresses (§23.5, interactions.md §15.4)

    /// `↩` or blur on the address field. An unchanged text looks nothing up;
    /// a changed one starts exactly one lookup; an empty one clears the
    /// address. Returns whether a lookup started.
    @discardableResult
    func commitAddress(_ id: String) -> Bool {
        guard let place = place(id) else { return false }
        let draft = drafts.removeValue(forKey: id)
        // What the field showed before the edit: committing it again is
        // "unchanged" and looks nothing up.
        let before = fieldText(place).trimmingCharacters(in: .whitespacesAndNewlines)
        let text = (draft ?? before).trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            guard place.addressText != nil || place.hasCoordinate else { return false }
            clear(place)
            return false
        }
        guard text != before else { return false }
        if previousText[id] == nil { previousText[id] = place.addressText }
        place.addressText = text
        try? context.save()
        lookUp(place)
        return true
    }

    /// `Look Up` / `Try Again`: one lookup of the typed text.
    func lookUpAgain(_ id: String) {
        guard let place = place(id), place.addressText?.isEmpty == false else { return }
        lookUp(place)
    }

    private func lookUp(_ place: KnownPlace) {
        let id = place.id
        let address = place.addressText ?? ""
        let token = (generation[id] ?? 0) + 1
        generation[id] = token
        selectedMatch[id] = nil
        // Paused after a throttle: say so rather than wait (§23.5).
        if let until = queue.plannerState.pausedUntil {
            lookups[id] = .failed(.throttled, retryAt: until)
            return
        }
        lookups[id] = .searching
        queue.enqueueLookup(id: id, address: address) { [weak self] result in
            guard let self, self.generation[id] == token else { return }
            self.answer(id, address: address, result)
        }
    }

    private func answer(_ id: String, address: String, _ result: Result<[GeocodedAddress], GeocodeError>) {
        guard let place = place(id) else { return }
        switch result {
        case .success(let found) where found.isEmpty:
            lookups[id] = .notFound(typed: address)
            place.geocodeState = .notFound
        case .success(let found):
            lookups[id] = .results(found)
            selectedMatch[id] = nil   // `↓` from the field enters the list
        case .failure(let error):
            lookups[id] = .failed(error, retryAt: error == .throttled ? queue.pausedUntil : nil)
            place.geocodeState = .lookupFailed
        }
        try? context.save()
        revision += 1
    }

    /// `Use This Address`, a row, or `↩` on the selection: the only write of
    /// a coordinate (§23.5).
    func confirm(_ id: String, _ result: GeocodedAddress) {
        guard let place = place(id) else { return }
        place.confirmedAddress = result.line
        place.setCoordinate(latitude: result.latitude, longitude: result.longitude)
        place.geocodeState = .confirmed
        place.geocodedAt = clock.now
        TravelETACacheStore(context: context).deleteRows(of: id, notAt: result.latitude, result.longitude)
        try? context.save()
        lookups[id] = nil
        previousText[id] = nil
        selectedMatch[id] = nil
        drafts[id] = nil
        generation[id] = (generation[id] ?? 0) + 1
        revision += 1
        recompute()
    }

    /// `Cancel` / `⎋`: drops the lookup and restores the field to the
    /// confirmed address (or empties it). Nothing else is written.
    func cancel(_ id: String) {
        guard let place = place(id) else { return }
        generation[id] = (generation[id] ?? 0) + 1
        lookups[id] = nil
        drafts[id] = nil
        selectedMatch[id] = nil
        if let previous = previousText.removeValue(forKey: id) {
            place.addressText = previous
            if place.hasCoordinate { place.geocodeState = .confirmed }
            else if previous == nil { place.geocodeState = .none }
            try? context.save()
        }
        revision += 1
    }

    /// Leaving the tab or closing Settings: a result left unconfirmed keeps
    /// the typed text and becomes `unconfirmed`. Nothing is confirmed by
    /// leaving.
    func leave() {
        for (id, lookup) in lookups {
            guard let place = place(id) else { continue }
            switch lookup {
            case .results, .searching:
                place.geocodeState = .unconfirmed
            case .notFound, .failed:
                break
            }
            generation[id] = (generation[id] ?? 0) + 1
        }
        lookups = [:]
        previousText = [:]
        selectedMatch = [:]
        drafts = [:]
        try? context.save()
        revision += 1
    }

    private func clear(_ place: KnownPlace) {
        place.addressText = nil
        place.confirmedAddress = nil
        place.setCoordinate(latitude: nil, longitude: nil)
        place.geocodeState = .none
        place.geocodedAt = nil
        TravelETACacheStore(context: context).deleteRows(touching: place.id)
        try? context.save()
        lookups[place.id] = nil
        previousText[place.id] = nil
        revision += 1
        recompute()
    }

    // MARK: The match list's keyboard (interactions.md §15.4)

    /// `↓` from the field enters the list; `↑` / `↓` move within it.
    func moveSelection(_ id: String, by delta: Int) {
        guard case .results(let found) = lookups[id], found.count > 1 else { return }
        let count = min(found.count, 5)
        let current = selectedMatch[id] ?? -1
        selectedMatch[id] = max(0, min(count - 1, current + delta))
    }

    /// `↩`: the default button (one result) or the selected row.
    func confirmSelection(_ id: String) {
        guard case .results(let found) = lookups[id] else { return }
        if found.count == 1 { return confirm(id, found[0]) }
        if let index = selectedMatch[id], found.indices.contains(index) { confirm(id, found[index]) }
    }

    /// A match row's two lines: the first comma-separated part, then the rest.
    static func matchLines(_ line: String) -> (first: String, rest: String) {
        guard let comma = line.firstIndex(of: ",") else { return (line, "") }
        let rest = line[line.index(after: comma)...].trimmingCharacters(in: .whitespaces)
        return (String(line[..<comma]), rest)
    }

    // MARK: Names (§23.1)

    /// Commits a name: trimmed, non-empty and unique (case-insensitive);
    /// anything else reverts. Returns whether it was written.
    @discardableResult
    func commitName(_ id: String, _ text: String) -> Bool {
        guard let place = place(id) else { return false }
        let name = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != place.name,
              !places.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(name) == .orderedSame })
        else { revision += 1; return false }
        place.name = name
        try? context.save()
        revision += 1
        return true
    }

    // MARK: Adding and removing (layouts.md §13)

    /// `Add Place`: `New Place`, `New Place 2` … with no address.
    @discardableResult
    func addPlace() -> String {
        let names = Set(places.map { $0.name.lowercased() })
        var name = "New Place"
        var n = 2
        while names.contains(name.lowercased()) { name = "New Place \(n)"; n += 1 }
        let place = KnownPlace(name: name, sortIndex: (places.map(\.sortIndex).max() ?? 1) + 1)
        context.insert(place)
        try? context.save()
        revision += 1
        return place.id
    }

    /// The manual events at a place.
    func manualEvents(at id: String) -> [Event] {
        ((try? context.fetch(FetchDescriptor<Event>())) ?? []).filter { $0.origin == .manual && $0.placeID == id }
    }

    /// The alert to show before removing (nil: remove at once).
    func removalQuestion(_ id: String) -> (message: String, informative: String)? {
        guard let place = place(id), !place.isBuiltIn else { return nil }
        let count = manualEvents(at: id).count
        guard count > 0 else { return nil }
        let events = count == 1 ? "1 event is" : "\(count) events are"
        return ("Remove “\(place.name)”?", "\(events) at \(place.name). They will have no place, and no leave-by.")
    }

    /// Removes a user place: the place, its mode overrides, its cache rows,
    /// and the manual events' `placeID`. Not an undo step. Built-ins can't.
    func remove(_ id: String) {
        guard let place = place(id), !place.isBuiltIn else { return }
        for event in manualEvents(at: id) { event.placeID = nil }
        for row in (try? context.fetch(FetchDescriptor<TravelModeOverride>())) ?? []
        where row.placeA == id || row.placeB == id {
            context.delete(row)
        }
        TravelETACacheStore(context: context).deleteRows(touching: id)
        context.delete(place)
        try? context.save()
        lookups[id] = nil
        revision += 1
        recompute()
    }

    /// The Places footer, with the campus's current name.
    var footer: String {
        let campus = place(BuiltInPlace.campus.id)?.name ?? BuiltInPlace.campus.defaultName
        return "Timetable rooms are at \(campus). Online lectures need no travel. Addresses are looked up with Apple Maps."
    }

    // MARK: VoiceOver (§29)

    static let nameFieldLabel = "Place name"
    static func addressFieldLabel(_ name: String) -> String { "Address of \(name)" }
    static func removeLabel(_ name: String) -> String { "Remove \(name)" }
    static func matchRowLabel(_ match: GeocodedAddress) -> String {
        let lines = matchLines(match.line)
        return lines.rest.isEmpty ? lines.first : "\(lines.first), \(lines.rest)"
    }
}
