//
//  TravelFixtures.swift
//  KadenceTests
//
//  components.md §30.1 "The test day for the planners": the `travel`
//  dataset's events built in code (no review launch), `M` = Mon 2026-10-12,
//  zone Europe/Vienna, the mock provider's table and its places. Shared by
//  the slice 2 planner tests.
//
//  The timetable rows are the review template's (§22.1) without row 1, plus
//  T1 (§30.1). The coordinates are invented fixture values (§30.1), never
//  shipped as data.
//

import Foundation
@testable import Kadence

nonisolated enum TravelFixtures {
    static let zone = TimeZone(identifier: "Europe/Vienna")!

    static var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = zone
        c.locale = Locale(identifier: "en_US_POSIX")
        return c
    }

    /// `yyyy-MM-dd HH:mm`, Vienna.
    static func date(_ text: String) -> Date { TestClock.date(text) }

    /// `M + n` at `HH:mm`.
    static func m(_ n: Int, _ hhmm: String) -> Date {
        let day = calendar.date(byAdding: .day, value: n, to: date("2026-10-12 00:00"))!
        let parts = hhmm.split(separator: ":").compactMap { Int($0) }
        return day.addingTimeInterval(TimeInterval(parts[0] * 3600 + parts[1] * 60))
    }

    static let gymID = "gym"
    static let timetableID = "timetable"

    static let home = PlaceSnapshot(id: "home", name: "Home", latitude: 48.2000, longitude: 16.3900)
    static let campus = PlaceSnapshot(id: "campus", name: "FH Technikum Wien", latitude: 48.2390, longitude: 16.3770)
    static let gym = PlaceSnapshot(id: gymID, name: "Gym", latitude: 48.2050, longitude: 16.3950)
    static var places: [PlaceSnapshot] { [home, campus, gym] }
    static var placesNoHomeAddress: [PlaceSnapshot] {
        [PlaceSnapshot(id: "home", name: "Home", geocodeState: .none), campus, gym]
    }

    static let overrides = [OverrideSnapshot("home", gymID, mode: .walking)]

    static let sourceKinds: [String: CalendarSourceKind] = [
        timetableID: .universityTimetable, "personal": .manual, "routine": .routine,
    ]

    /// Stable ids, so a test can name an event.
    static func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", n))! }

    static func lecture(_ n: Int, _ title: String, _ start: Date, _ end: Date, room: String,
                        online: Bool = false) -> TravelEventSnapshot {
        TravelEventSnapshot(id: id(n), title: title, start: start, end: end, origin: .imported,
                            sourceID: timetableID, locationText: room, isOnline: online)
    }

    static func manual(_ n: Int, _ title: String, _ start: Date, _ end: Date, place: String?) -> TravelEventSnapshot {
        TravelEventSnapshot(id: id(n), title: title, start: start, end: end, origin: .manual, placeID: place,
                            sourceID: "personal")
    }

    // The dataset's events, by name.
    static let h1 = lecture(1, "SWQM-ILV", m(-6, "14:30"), m(-6, "16:00"), room: "HS_A3.15")
    static let h2 = lecture(2, "KOKU-UE", m(-5, "09:40"), m(-5, "12:50"), room: "UEB_B2.02")
    static let swqm = lecture(10, "SWQM-ILV", m(0, "09:00"), m(0, "10:30"), room: "HS_A3.15")
    static let swen3Lab = lecture(11, "SWEN3-LAB", m(1, "10:00"), m(1, "11:30"), room: "EDV_F4.25")
    static let swen3ILV = lecture(12, "SWEN3-ILV", m(1, "11:45"), m(1, "13:15"), room: "HS_A2.07")
    static let inno3 = lecture(13, "INNO3-EL", m(2, "14:00"), m(2, "15:30"), room: "WEBINAR01", online: true)
    static let epc = lecture(14, "EPC-ILV", m(3, "13:00"), m(3, "14:30"), room: "LAB_F5.12")
    static let reqen = lecture(15, "REQEN-EXAM", m(3, "16:00"), m(3, "17:30"), room: "EDV_A5.09")
    static let swrm = lecture(16, "SWRM-ILV", m(4, "16:00"), m(4, "17:45"), room: "UEB_B2.01")
    static let swqm2 = lecture(17, "SWQM-ILV", m(7, "09:00"), m(7, "10:30"), room: "HS_A3.15")
    static let swen3Lab2 = lecture(18, "SWEN3-LAB", m(8, "10:00"), m(8, "11:30"), room: "EDV_F4.25")
    static let epc2 = lecture(19, "EPC-ILV", m(10, "10:00"), m(10, "11:30"), room: "LAB_F5.12")
    static let rwExam = lecture(20, "RW-EXAM", m(11, "09:40"), m(11, "11:10"), room: "EDV_F2.01")

    static let laundry = manual(30, "Laundry", m(2, "08:00"), m(2, "08:45"), place: "home")
    static let dinner = manual(31, "Dinner with flatmates", m(3, "18:30"), m(3, "20:00"), place: "home")
    static let earlyStudy = manual(32, "Early study group", m(5, "07:30"), m(5, "09:00"), place: "campus")
    static let lateCall = manual(33, "Late call", m(5, "23:15"), m(5, "23:45"), place: nil)
    static let climbing = manual(34, "Climbing", m(6, "18:00"), m(6, "19:30"), place: gymID)

    static var timetable: [TravelEventSnapshot] {
        [h1, h2, swqm, swen3Lab, swen3ILV, inno3, epc, reqen, swrm, swqm2, swen3Lab2, epc2, rwExam]
    }
    static var manualEvents: [TravelEventSnapshot] { [laundry, dinner, earlyStudy, lateCall, climbing] }
    static var events: [TravelEventSnapshot] { timetable + manualEvents }

    /// §30.1's mock provider table, by directed pair and mode. nil = `noRoute`.
    static func mockMinutes(from: String, to: String, mode: TravelMode) -> Int? {
        switch (from, to, mode) {
        case ("home", "campus", .transit), ("campus", "home", .transit): 35
        case ("home", gymID, .walking), (gymID, "home", .walking): 5
        case ("campus", gymID, .transit), (gymID, "campus", .transit): 20
        default: nil
        }
    }

    static func input(events: [TravelEventSnapshot] = events, places: [PlaceSnapshot] = places,
                      overrides: [OverrideSnapshot] = overrides, cache: [ETACacheEntry] = [],
                      queue: TravelLegPlanner.QueueState = .init(), existing: [UUID: LegValues] = [:],
                      refreshes: [UUID: TravelLegPlanner.RefreshOutcome] = [:], buffer: Int = 10,
                      now: Date = m(0, "06:00")) -> TravelLegPlanner.Input {
        TravelLegPlanner.Input(events: events, places: places, overrides: overrides, preferredMode: .transit,
                               bufferMinutes: buffer, chainGapMinutes: 120, sourceKinds: sourceKinds,
                               cache: cache, queue: queue, existingLegs: existing, refreshes: refreshes,
                               providerSource: "mock", now: now, calendar: calendar)
    }

    /// Answers every request with the mock table, as cache rows computed at
    /// `at` (a request the table can't answer adds nothing).
    static func answer(_ requests: [TravelLegPlanner.Request], at: Date) -> [ETACacheEntry] {
        requests.compactMap { request in
            guard let minutes = mockMinutes(from: request.originPlaceID, to: request.destinationPlaceID,
                                            mode: request.mode) else { return nil }
            return ETACacheEntry(key: request.key, originPlaceID: request.originPlaceID,
                                 destinationPlaceID: request.destinationPlaceID, mode: request.mode,
                                 dayType: request.dayType, slotMinutes: request.slotMinutes,
                                 travelSeconds: Double(minutes * 60), computedAt: at, arrivalDate: request.arrivingBy)
        }
    }

    /// The legs at `now` with every key answered by the mock (two passes).
    static func answeredCache(now: Date = m(0, "06:00"), computedAt: Date? = nil,
                              events: [TravelEventSnapshot] = events) -> [ETACacheEntry] {
        let first = TravelLegPlanner.plan(input(events: events, now: now))
        return answer(first.requests, at: computedAt ?? now)
    }
}
