//
//  TravelDataset.swift
//  Kadence
//
//  Phase 3 slice 2 — components.md §30.1 "Dataset `travel` (review)": what
//  `-KadenceReview travel` seeds into its in-memory store, and what the
//  slice 2 tests seed into theirs. Review mode only; a normal launch never
//  sees any of it (G-057).
//
//  - one connected source, `University timetable`, seeded as already
//    imported from `cis-travel.ics.template` (the review template without
//    row 1, plus T1) — 14 VEVENTs, 13 events after the 7a+7b merge, 2 of
//    them history (GAPS G-097);
//  - no routine template (no conflicts, no Needs attention row);
//  - one time window, `Sleep`, protected, every day 22:00–07:00;
//  - three known places, all confirmed with the mock geocoder's results
//    (invented fixture coordinates, never shipped as data);
//  - preferred `transit`; `Home ↔ Gym` `walking`; buffer 10;
//  - the manual events P1–P5 (and P6, the live event, in review).
//
//  The variants (`-KadenceReviewVariant`) change the store here and the
//  mocks in `TravelReviewServices` (task 12).
//

import Foundation
import SwiftData

@MainActor
enum TravelDataset {
    static let sourceID = "timetable"
    static let gymID = "gym"

    enum Variant: String, CaseIterable, Sendable {
        case travelNoAddress, travelOffline, travelPending, travelNoRoute
    }

    /// §30.1's places, as the mock geocoder confirmed them.
    struct SeedPlace {
        var id: String
        var name: String
        var typed: String
        var confirmed: String
        var latitude: Double
        var longitude: Double
    }

    static let home = SeedPlace(id: "home", name: "Home", typed: "Example Gasse 5, 1030 Wien",
                                confirmed: "Example Gasse 5, 1030 Wien, Austria", latitude: 48.2000, longitude: 16.3900)
    static let campus = SeedPlace(id: "campus", name: "FH Technikum Wien", typed: BuiltInPlace.campusAddress,
                                  confirmed: "Höchstädtplatz 6, 1200 Wien, Austria", latitude: 48.2390, longitude: 16.3770)
    static let gym = SeedPlace(id: gymID, name: "Gym", typed: "Example Straße 1, 1020 Wien",
                               confirmed: "Example Straße 1, 1020 Wien, Austria", latitude: 48.2050, longitude: 16.3950)

    /// Seeds the dataset. Idempotent: a second call (the other window's)
    /// finds the source and inserts nothing.
    ///
    /// - `now`: the launch (or test) clock; `today` is its day.
    /// - `m`: the dataset's `M` (review: the first Monday ≥ today + 2;
    ///   tests: Mon 2026-10-12).
    /// - `liveEvent`: P6, `Pick up parcel` (review only; tests don't seed it).
    static func seed(context: ModelContext, now: Date, m: Date, zone: TimeZone = .current,
                     variant: Variant? = nil, liveEvent: Bool = false, template: String = ReviewTravelTemplate.text) {
        BuiltInSource.ensure(in: context)
        TravelBuiltIns.ensure(in: context)
        let sources = (try? context.fetch(FetchDescriptor<Source>())) ?? []
        guard !sources.contains(where: { $0.id == sourceID }) else { return }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone

        // The timetable, as already imported (§22.1's rule).
        let feed = ReviewFeed.reportTravel(template: template, today: now, m: m, zone: zone)
        let result = ReviewMode.fetchResult(of: feed, now: now, zone: zone)
        let source = Source.connected(
            id: sourceID, displayName: "University timetable", serverURL: ReviewMode.server.normalized,
            username: MockCalDAVServer.username, principalHref: MockCalDAVServer.principal,
            calendarHomeHref: MockCalDAVServer.home, calendars: [ReviewMode.calendar], capabilities: result.capabilities,
            paletteKey: Source.paletteKeyForNewSource(existing: sources.map(\.paletteKey)))
        context.insert(source)
        try? ReviewMode.secrets.save(ReviewMode.password,
                                     for: SecretAccount(host: ReviewMode.server.host, username: MockCalDAVServer.username),
                                     info: .forSource(id: source.id, displayName: source.displayName))
        ReviewMode.importFetched(result, into: source, context: context, now: now, zone: zone)

        // Sleep, protected, every day 22:00–07:00.
        context.insert(TimeWindow(weekdays: Set(1...7), startMinutes: 22 * 60, endMinutes: 7 * 60,
                                  kind: .protected, label: "Sleep"))

        // The places, confirmed.
        let places = Dictionary(((try? context.fetch(FetchDescriptor<KnownPlace>())) ?? []).map { ($0.id, $0) },
                                uniquingKeysWith: { a, _ in a })
        for seed in [home, campus] {
            if let place = places[seed.id] { confirm(place, seed, at: now) }
        }
        let gymPlace = KnownPlace(id: gym.id, name: gym.name, sortIndex: 2)
        confirm(gymPlace, gym, at: now)
        context.insert(gymPlace)
        TravelModeOverrides.insert(home.id, gym.id, mode: .walking, in: context)

        let settings = TravelBuiltIns.settings(in: context)
        settings.preferredTravelMode = .transit
        settings.travelBufferMinutes = 10
        settings.travelChainGapMinutes = 120
        settings.useCurrentLocation = true

        // P1–P5 (and P6).
        func at(_ n: Int, _ hour: Int, _ minute: Int) -> Date {
            cal.date(byAdding: .day, value: n, to: cal.startOfDay(for: m))!.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
        }
        func manual(_ title: String, _ start: Date, _ end: Date, _ placeID: String?) {
            let event = Event(title: title, start: start, end: end, origin: .manual,
                              sourceKey: BuiltInSource.personal.paletteKey, sourceID: BuiltInSource.personal.id)
            event.placeID = placeID
            context.insert(event)
        }
        manual("Laundry", at(2, 8, 0), at(2, 8, 45), home.id)
        manual("Dinner with flatmates", at(3, 18, 30), at(3, 20, 0), home.id)
        manual("Early study group", at(5, 7, 30), at(5, 9, 0), campus.id)
        manual("Late call", at(5, 23, 15), at(5, 23, 45), nil)
        manual("Climbing", at(6, 18, 0), at(6, 19, 30), gym.id)
        if liveEvent {
            let start = liveEventStart(launch: now, calendar: cal)
            manual("Pick up parcel", start, start.addingTimeInterval(30 * 60), campus.id)
        }

        switch variant {
        case .travelNoAddress:
            if let place = places[home.id] {
                place.addressText = nil
                place.confirmedAddress = nil
                place.setCoordinate(latitude: nil, longitude: nil)
                place.geocodeState = .none
                place.geocodedAt = nil
            }
        case .travelOffline:
            seedStaleCache(context: context, m: m, calendar: cal)
        case .travelPending, .travelNoRoute, nil:
            break
        }
        try? context.save()
    }

    /// P6: the launch time rounded **up** to the quarter hour, + 60 min.
    static func liveEventStart(launch: Date, calendar: Calendar) -> Date {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: launch)
        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0) + ((parts.second ?? 0) > 0 ? 1 : 0)
        let rounded = (minutes + 14) / 15 * 15
        return calendar.startOfDay(for: launch).addingTimeInterval(TimeInterval((rounded + 60) * 60))
    }

    private static func confirm(_ place: KnownPlace, _ seed: SeedPlace, at now: Date) {
        place.addressText = seed.typed
        place.confirmedAddress = seed.confirmed
        place.setCoordinate(latitude: seed.latitude, longitude: seed.longitude)
        place.geocodeState = .confirmed
        place.geocodedAt = now
    }

    /// `travelOffline`'s cache: one entry per weekday slot of the dataset's
    /// campus lectures, `home → campus` transit 35 min, computed `M − 15
    /// days` 18:00 (stale: older than 14 days, so every leg asks and falls
    /// back to it, §24.10 step 3).
    static func seedStaleCache(context: ModelContext, m: Date, calendar: Calendar) {
        let homeEnd = TravelEndpoint(id: home.id, latitude: home.latitude, longitude: home.longitude)
        let campusEnd = TravelEndpoint(id: campus.id, latitude: campus.latitude, longitude: campus.longitude)
        let computedAt = calendar.date(byAdding: .day, value: -15, to: calendar.startOfDay(for: m))!
            .addingTimeInterval(18 * 3600)
        let store = TravelETACacheStore(context: context)
        var seen = Set<String>()
        let lectures = ((try? context.fetch(FetchDescriptor<Event>())) ?? [])
            .filter { $0.sourceID == sourceID && !$0.isOnline && $0.start >= calendar.startOfDay(for: m) }
        for lecture in lectures.sorted(by: { $0.start < $1.start }) {
            let arrival = lecture.start.addingTimeInterval(-600)
            let key = TravelCacheKey(origin: homeEnd, destination: campusEnd, mode: .transit, arrival: arrival,
                                     calendar: calendar)
            guard key.dayType == .weekday, seen.insert(key.string).inserted else { continue }
            let request = TravelLegPlanner.Request(
                key: key.string, origin: homeEnd, destination: campusEnd, mode: .transit, arrivingBy: arrival,
                priority: 4, eventStart: lecture.start, eventIDs: [], dayType: key.dayType,
                slotMinutes: key.slotMinutes, originPlaceID: home.id, destinationPlaceID: campus.id)
            store.upsert(request, travelSeconds: 35 * 60, computedAt: computedAt)
        }
    }
}
