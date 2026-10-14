//
//  TravelRig.swift
//  KadenceTests
//
//  A store seeded with §30.1's dataset `travel` (`M` = Mon 2026-10-12,
//  today = the clock's day, Europe/Vienna), the mock provider and geocoder,
//  a scripted path monitor, the routing queue and the travel coordinator,
//  all on one manual clock. In-memory store; no network, no MapKit.
//

import Foundation
import SwiftData
@testable import Kadence

@MainActor
final class TravelRig {
    let container: ModelContainer
    let context: ModelContext
    let clock: ManualTravelClock
    let provider: MockTravelTimeProvider
    let geocoder: any PlaceGeocoder
    let path = ScriptedPathMonitoring()
    let log = RoutingLog()
    let queue: RouteRequestQueue
    let coordinator: TravelCoordinator
    let undo = UndoStack()

    static let m = TravelFixtures.date("2026-10-12 00:00")

    /// `seed`: nil for an empty store with only the built-ins.
    let location: MockLocationSource

    init(now: Date, variant: TravelDataset.Variant? = nil, seed: Bool = true,
         geocoder: (any PlaceGeocoder)? = nil, provider: MockTravelTimeProvider? = nil,
         location: MockLocationSource = MockLocationSource(authorization: .notDetermined)) throws {
        self.location = location
        container = try slice2MemoryContainer()
        context = container.mainContext
        if seed {
            let template = ReviewTravelTemplate.text
            precondition(!template.isEmpty, "cis-travel.ics.template is not in the app bundle")
            TravelDataset.seed(context: context, now: now, m: Self.m, zone: TravelFixtures.zone, variant: variant,
                               template: template)
        } else {
            BuiltInSource.ensure(in: context)
            TravelBuiltIns.ensure(in: context)
        }
        clock = ManualTravelClock(now)
        self.provider = provider ?? TravelServices.defaultMockProvider()
        self.geocoder = geocoder ?? MockPlaceGeocoder()
        queue = RouteRequestQueue(provider: self.provider, geocoder: self.geocoder, clock: clock, path: path,
                                  calendar: TravelFixtures.calendar, log: log)
        coordinator = TravelCoordinator(context: context, queue: queue, clock: clock, calendar: TravelFixtures.calendar,
                                        providerSource: "mock", log: log, location: location)
    }

    var store: EventStore { EventStore(context: context, undo: undo) }

    /// Runs every wake (debounce, queue, refresh) due up to `until`, letting
    /// each request finish.
    /// Other work to let finish between wakes (the notification rig's
    /// scheduler passes), so each runs at the clock time it was due.
    var extraSettle: (() async -> Void)?

    func run(until: Date) async {
        while true {
            await coordinator.settleLocation()
            await queue.settle()
            await coordinator.settleLocation()
            await extraSettle?()
            guard let next = clock.nextWakeAt, next <= until else { break }
            clock.advance(to: next)
        }
        clock.advance(to: until)
        await coordinator.settleLocation()
        await queue.settle()
        await extraSettle?()
    }
    func run(for seconds: TimeInterval) async { await run(until: clock.now.addingTimeInterval(seconds)) }

    /// Launch and let the answers come in (a minute is plenty: 2 s apart).
    func launchAndSettle() async {
        coordinator.launched()
        await run(for: 120)
    }

    func events() -> [Event] { (try? context.fetch(FetchDescriptor<Event>(sortBy: [SortDescriptor(\.start)]))) ?? [] }

    /// The event with this title starting on `M + day`.
    func event(_ title: String, day: Int) -> Event? {
        let start = TravelFixtures.calendar.date(byAdding: .day, value: day, to: Self.m)!
        let end = TravelFixtures.calendar.date(byAdding: .day, value: 1, to: start)!
        return events().first { $0.title == title && $0.start >= start && $0.start < end }
    }

    func leg(_ title: String, day: Int) -> TravelLeg? {
        event(title, day: day).flatMap { coordinator.leg(for: $0.id) }
    }

    func legs() -> [TravelLeg] { (try? context.fetch(FetchDescriptor<TravelLeg>())) ?? [] }

    func hhmm(_ date: Date?) -> String {
        guard let date else { return "—" }
        return RoutingLog.clock(date, calendar: TravelFixtures.calendar)
    }

    /// Applies a feed to the timetable as an automatic sync would (one
    /// planner pass, one applier transaction).
    func sync(_ objects: [MockCalDAVServer.Object]) throws {
        let source = try require(try context.fetch(FetchDescriptor<Source>()).first { $0.id == TravelDataset.sourceID })
        let result = ReviewMode.fetchResult(of: objects, now: clock.now, zone: TravelFixtures.zone)
        let plan = SyncPlanner.plan(
            existing: SyncApplier.snapshot(of: source, in: context, zone: TravelFixtures.zone),
            source: SourceSnapshot(feedHash: source.feedHash, lastFeedEventCount: source.lastFeedEventCount,
                                   calendars: source.calendars, importedAt: source.importedAt),
            result: result, kind: .sync, now: clock.now, zone: TravelFixtures.zone)
        try SyncApplier.apply(plan, to: source, context: context, now: clock.now)
    }
}

/// `#require` outside a test function: a throwing unwrap.
@discardableResult
func require<T>(_ value: T?, _ message: String = "required value was nil") throws -> T {
    guard let value else { throw CocoaError(.coderValueNotFound, userInfo: [NSDebugDescriptionErrorKey: message]) }
    return value
}

/// A geocoder that answers what it is told (§23.6's non-matching and failed
/// automatic lookups).
actor ScriptedGeocoder: PlaceGeocoder {
    var answer: Result<[GeocodedAddress], GeocodeError>
    private(set) var queries: [String] = []
    init(_ answer: Result<[GeocodedAddress], GeocodeError>) { self.answer = answer }
    func set(_ answer: Result<[GeocodedAddress], GeocodeError>) { self.answer = answer }
    func lookUp(_ address: String) async throws(GeocodeError) -> [GeocodedAddress] {
        queries.append(address)
        return try answer.get()
    }
}
