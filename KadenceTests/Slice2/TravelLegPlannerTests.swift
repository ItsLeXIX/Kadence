//
//  TravelLegPlannerTests.swift
//  KadenceTests
//
//  PHASE3-SLICE2-PLAN.md task 3 — components.md §23.2, §23.3, §24.1–§24.4,
//  §24.9 (the cache key), §24.10 (statuses and the fallback). Events built
//  in code from §30.1's dataset `travel`, clock Mon 12 Oct 06:00, caches
//  built in code. No provider is called: the planner is pure.
//

import Testing
import Foundation
@testable import Kadence

struct TravelLegPlannerTests {
    typealias F = TravelFixtures
    let now = F.m(0, "06:00")

    func plan(_ input: TravelLegPlanner.Input) -> TravelLegPlanner.Output { TravelLegPlanner.plan(input) }

    func hhmm(_ date: Date?) -> String {
        guard let date else { return "—" }
        let f = DateFormatter()
        f.calendar = F.calendar; f.timeZone = F.zone; f.dateFormat = "HH:mm"
        return f.string(from: date)
    }

    // MARK: §24.4

    @Test("§24.4's table, row for row, from a cache holding the mock's answers — and no requests")
    func workedExample() {
        let cache = F.answeredCache()
        let out = plan(F.input(cache: cache))
        #expect(out.requests.isEmpty)

        func ready(_ e: TravelEventSnapshot, depart: String, minutes: Int, mode: TravelMode, from: String, to: String) {
            let leg = out.legs[e.id]
            #expect(leg?.status == .ready, "\(e.title)")
            #expect(hhmm(leg?.departAt) == depart, "\(e.title)")
            #expect(leg?.duration == TimeInterval(minutes * 60), "\(e.title)")
            #expect(leg?.buffer == 600 && leg?.mode == mode && leg?.source == "mock", "\(e.title)")
            #expect(leg?.originPlaceID == from && leg?.destinationPlaceID == to && leg?.originKind == .place, "\(e.title)")
            #expect(leg?.reason == nil && leg?.computedAt == now, "\(e.title)")
        }
        ready(F.swqm, depart: "08:15", minutes: 35, mode: .transit, from: "home", to: "campus")
        ready(F.swen3Lab, depart: "09:15", minutes: 35, mode: .transit, from: "home", to: "campus")
        #expect(out.legs[F.swen3ILV.id] == nil && out.ruleOrigins[F.swen3ILV.id] == "campus")
        #expect(out.legs[F.laundry.id] == nil && out.ruleOrigins[F.laundry.id] == "home")
        #expect(out.legs[F.inno3.id] == nil && out.ruleOrigins[F.inno3.id] == nil)
        ready(F.epc, depart: "12:15", minutes: 35, mode: .transit, from: "home", to: "campus")
        #expect(out.legs[F.reqen.id] == nil && out.ruleOrigins[F.reqen.id] == "campus")
        #expect(out.chainedFrom[F.reqen.id] == F.epc.id)
        ready(F.dinner, depart: "17:45", minutes: 35, mode: .transit, from: "campus", to: "home")
        ready(F.swrm, depart: "15:15", minutes: 35, mode: .transit, from: "home", to: "campus")
        ready(F.earlyStudy, depart: "06:45", minutes: 35, mode: .transit, from: "home", to: "campus")
        #expect(out.legs[F.lateCall.id] == nil)
        ready(F.climbing, depart: "17:45", minutes: 5, mode: .walking, from: "home", to: F.gymID)
        // History is never a leg.
        #expect(out.legs[F.h1.id] == nil && out.legs[F.h2.id] == nil)
        // Week M + 7's lectures have legs too (no horizon, §24.5).
        ready(F.swqm2, depart: "08:15", minutes: 35, mode: .transit, from: "home", to: "campus")
        ready(F.epc2, depart: "09:15", minutes: 35, mode: .transit, from: "home", to: "campus")
        ready(F.rwExam, depart: "08:55", minutes: 35, mode: .transit, from: "home", to: "campus")
        #expect(out.legs.count == 11)
    }

    @Test("Empty cache: every leg pending; exactly one request per distinct key; priorities by §24.9")
    func emptyCache() {
        let out = plan(F.input())
        #expect(out.legs.values.allSatisfy { $0.status == .pending && $0.reason == .pending && $0.departAt == nil })
        #expect(out.legs.count == 11)
        // One request per distinct key: home → campus transit at the weekday
        // slots 08:30, 09:30 (SWEN3-LAB ×2, EPC-ILV M+10, RW-EXAM), 12:30,
        // 15:30 and the Saturday 07:00; campus → home 18:00 (Dinner);
        // home → Gym walking, Sunday 17:30.
        #expect(out.requests.count == 7)
        #expect(Set(out.requests.map(\.key)).count == 7)
        let keys = out.requests.map { "\($0.originPlaceID)>\($0.destinationPlaceID)|\($0.mode.rawValue)|\($0.dayType.rawValue)|\($0.slotMinutes)" }
        #expect(Set(keys) == [
            "home>campus|transit|weekday|510", "home>campus|transit|weekday|570",
            "home>campus|transit|weekday|750", "home>campus|transit|weekday|930", "home>campus|transit|saturday|420",
            "campus>home|transit|weekday|1080", "home>gym|walking|sunday|1050",
        ])
        // §24.9 priorities: 3 for today and tomorrow (Mon, Tue), 4 the rest.
        let byKey = Dictionary(uniqueKeysWithValues: out.requests.map { ("\($0.dayType.rawValue)|\($0.slotMinutes)|\($0.originPlaceID)", $0) })
        #expect(byKey["weekday|510|home"]?.priority == 3)          // SWQM Mon
        #expect(byKey["weekday|570|home"]?.priority == 3)          // SWEN3-LAB Tue (shared with EPC M+10)
        #expect(byKey["weekday|570|home"]?.eventIDs.count == 4)    // SWEN3-LAB ×2, EPC M+10, RW-EXAM
        #expect(byKey["weekday|750|home"]?.priority == 4)          // EPC Thu
        #expect(byKey["weekday|1080|campus"]?.priority == 4)
        #expect(out.requests.first?.priority == 3)
        // Sorted: priority, then event start.
        #expect(out.requests.map(\.priority) == out.requests.map(\.priority).sorted())
        // The arrival asked for is start − buffer of the earliest event.
        #expect(byKey["weekday|510|home"]?.arrivingBy == F.m(0, "08:50"))
    }

    @Test("A second plan with every key answered sends nothing (cache sharing, never one per event)")
    func cacheSharing() {
        let first = plan(F.input())
        let cache = F.answer(first.requests, at: now)
        #expect(cache.count == 7)
        #expect(plan(F.input(cache: cache)).requests.isEmpty)
    }

    @Test("Directional: campus → home and home → campus are two keys; an answer for one never fills the other")
    func directional() {
        let first = plan(F.input())
        let outward = first.requests.filter { $0.originPlaceID == "home" && $0.destinationPlaceID == "campus" }
        let cache = F.answer(outward, at: now)
        let out = plan(F.input(cache: cache))
        #expect(out.legs[F.dinner.id]?.status == .pending)
        #expect(out.requests.contains { $0.originPlaceID == "campus" && $0.destinationPlaceID == "home" })
    }

    // MARK: Variants

    @Test("travelNoAddress: every leg touching Home is unavailable · needsAddress (home), and no requests")
    func noAddress() {
        let out = plan(F.input(places: F.placesNoHomeAddress))
        #expect(out.requests.isEmpty)
        #expect(out.legs.count == 11)
        for leg in out.legs.values {
            #expect(leg.status == .unavailable && leg.reason == .needsAddress && leg.reasonPlaceID == "home")
            #expect(leg.departAt == nil && leg.duration == nil)
        }
    }

    @Test("travelOffline: campus legs from home are estimates (≈, offline); Dinner and Climbing unavailable · offline")
    func offline() {
        // The cache: home → campus transit, weekday, every slot of the
        // campus lectures, 35 min, computed M − 15 days 18:00 (stale).
        let stale = F.date("2026-09-27 18:00")
        let first = plan(F.input())
        let seeded = F.answer(first.requests.filter {
            $0.originPlaceID == "home" && $0.destinationPlaceID == "campus" && $0.dayType == .weekday
        }, at: stale)
        // Every request is asked and fails offline.
        let failures = Dictionary(uniqueKeysWithValues: first.requests.map {
            ($0.key, TravelLegPlanner.KeyFailure(reason: .offline, retryAt: nil))
        })
        let out = plan(F.input(cache: seeded, queue: .init(failures: failures)))
        for e in [F.swqm, F.swen3Lab, F.epc, F.swrm, F.earlyStudy, F.swqm2, F.swen3Lab2, F.epc2, F.rwExam] {
            let leg = out.legs[e.id]
            #expect(leg?.status == .estimate && leg?.reason == .offline, "\(e.title)")
            #expect(leg?.duration == 2100 && leg?.computedAt == stale, "\(e.title)")
        }
        #expect(hhmm(out.legs[F.swqm.id]?.departAt) == "08:15")
        #expect(hhmm(out.legs[F.epc.id]?.departAt) == "12:15")
        #expect(hhmm(out.legs[F.earlyStudy.id]?.departAt) == "06:45")   // nearest slot, any day type
        #expect(out.legs[F.dinner.id]?.status == .unavailable && out.legs[F.dinner.id]?.reason == .offline)
        #expect(out.legs[F.climbing.id]?.status == .unavailable && out.legs[F.climbing.id]?.reason == .offline)
        // Failed keys are remembered by the queue, not re-queued.
        #expect(out.requests.isEmpty)
    }

    @Test("Fallback order: own last time → exact key → nearest slot same day type → any day type → unavailable")
    func fallbackOrder() {
        let first = plan(F.input())
        let epcKey = first.requests.first { $0.eventIDs.contains(F.epc.id) }!
        let failures = [epcKey.key: TravelLegPlanner.KeyFailure(reason: .failed, retryAt: nil)]
        let old = F.date("2026-09-25 10:00")   // 17 days: stale, kept
        let older = F.date("2026-09-24 10:00")
        func entry(_ request: TravelLegPlanner.Request, minutes: Int, at: Date) -> ETACacheEntry {
            ETACacheEntry(key: request.key, originPlaceID: request.originPlaceID,
                          destinationPlaceID: request.destinationPlaceID, mode: request.mode, dayType: request.dayType,
                          slotMinutes: request.slotMinutes, travelSeconds: Double(minutes * 60), computedAt: at,
                          arrivalDate: request.arrivingBy)
        }
        let exact = entry(epcKey, minutes: 40, at: old)
        let sat = first.requests.first { $0.dayType == .saturday }!
        let sameType = first.requests.first { $0.slotMinutes == 930 && $0.originPlaceID == "home" }!   // 15:30, weekday
        let near = entry(sameType, minutes: 44, at: old)
        let otherType = entry(sat, minutes: 50, at: old)

        // 1 → own last time wins over everything.
        let own = LegValues(eventID: F.epc.id, status: .ready, departAt: F.m(3, "12:13"), duration: 37 * 60,
                            buffer: 600, mode: .transit, originPlaceID: "home", destinationPlaceID: "campus",
                            source: "mock", computedAt: older)
        var out = plan(F.input(cache: [exact, near, otherType], queue: .init(failures: failures),
                               existing: [F.epc.id: own]))
        #expect(out.legs[F.epc.id]?.status == .estimate && out.legs[F.epc.id]?.duration == TimeInterval(37 * 60))
        #expect(out.legs[F.epc.id]?.computedAt == older && out.legs[F.epc.id]?.reason == .failed)
        // 2 → the exact key.
        out = plan(F.input(cache: [exact, near, otherType], queue: .init(failures: failures)))
        #expect(out.legs[F.epc.id]?.duration == TimeInterval(40 * 60))
        // 3 → the nearest slot of the same day type, before another day type.
        out = plan(F.input(cache: [near, otherType], queue: .init(failures: failures)))
        #expect(out.legs[F.epc.id]?.duration == TimeInterval(44 * 60) && out.legs[F.epc.id]?.status == .estimate)
        // 4 → any day type.
        out = plan(F.input(cache: [otherType], queue: .init(failures: failures)))
        #expect(out.legs[F.epc.id]?.duration == TimeInterval(50 * 60))
        // 5 → nothing: unavailable with the reason.
        out = plan(F.input(cache: [], queue: .init(failures: failures)))
        #expect(out.legs[F.epc.id]?.status == .unavailable && out.legs[F.epc.id]?.reason == .failed)
        // Ties to the earlier slot: 12:30 is between 12:00 and 13:00.
        let prefix = epcKey.key.split(separator: "|").first.map(String.init)!
        let e1 = ETACacheEntry(key: prefix + "|transit|weekday|720", originPlaceID: "home", destinationPlaceID: "campus",
                               mode: .transit, dayType: .weekday, slotMinutes: 720, travelSeconds: 31 * 60,
                               computedAt: old, arrivalDate: old)
        let e2 = ETACacheEntry(key: prefix + "|transit|weekday|780", originPlaceID: "home", destinationPlaceID: "campus",
                               mode: .transit, dayType: .weekday, slotMinutes: 780, travelSeconds: 33 * 60,
                               computedAt: old, arrivalDate: old)
        out = plan(F.input(cache: [e2, e1], queue: .init(failures: failures)))
        #expect(out.legs[F.epc.id]?.duration == TimeInterval(31 * 60))
    }

    @Test("noRoute and needsAddress never fall back, even with an older time; a mode-mismatch answer is noRoute")
    func noFallback() {
        let first = plan(F.input())
        let climbKey = first.requests.first { $0.eventIDs.contains(F.climbing.id) }!
        let cache = F.answer([climbKey], at: F.date("2026-09-25 10:00"))   // stale: asked again
        let own = LegValues(eventID: F.climbing.id, status: .ready, departAt: F.m(6, "17:45"), duration: 300,
                            buffer: 600, mode: .walking, originPlaceID: "home", destinationPlaceID: F.gymID,
                            source: "mock", computedAt: F.date("2026-09-25 10:00"))
        // The provider maps an answer in another mode to `noRoute` (task 4).
        let out = plan(F.input(cache: cache, queue: .init(failures: [climbKey.key: .init(reason: .noRoute)]),
                               existing: [F.climbing.id: own]))
        #expect(out.legs[F.climbing.id]?.status == .unavailable && out.legs[F.climbing.id]?.reason == .noRoute)
        #expect(out.legs[F.climbing.id]?.departAt == nil)
        // needsAddress, with an own last time: still unavailable.
        let swqmOwn = LegValues(eventID: F.swqm.id, status: .ready, departAt: F.m(0, "08:15"), duration: 2100,
                                buffer: 600, mode: .transit, originPlaceID: "home", destinationPlaceID: "campus",
                                source: "mock", computedAt: now)
        let noHome = plan(F.input(places: F.placesNoHomeAddress, cache: F.answeredCache(),
                                  existing: [F.swqm.id: swqmOwn]))
        #expect(noHome.legs[F.swqm.id]?.status == .unavailable && noHome.legs[F.swqm.id]?.reason == .needsAddress)
    }

    // MARK: Freshness and refresh windows

    @Test("Freshness: 14 days → ready, no request; 14 days + 1 s → ready and a request; failing → estimate")
    func freshness() {
        let only = [F.epc]
        let first = plan(F.input(events: only))
        let fourteen = now.addingTimeInterval(-14 * 86_400)
        var out = plan(F.input(events: only, cache: F.answer(first.requests, at: fourteen)))
        #expect(out.legs[F.epc.id]?.status == .ready && out.requests.isEmpty)
        let stale = fourteen.addingTimeInterval(-1)
        let cache = F.answer(first.requests, at: stale)
        out = plan(F.input(events: only, cache: cache))
        #expect(out.legs[F.epc.id]?.status == .ready && out.legs[F.epc.id]?.computedAt == stale)
        #expect(out.requests.count == 1)
        out = plan(F.input(events: only, cache: cache,
                           queue: .init(failures: [first.requests[0].key: .init(reason: .offline)])))
        #expect(out.legs[F.epc.id]?.status == .estimate && out.legs[F.epc.id]?.computedAt == stale)
        #expect(out.legs[F.epc.id]?.reason == .offline && out.requests.isEmpty)
        // Older than 28 days is never used (deleted at launch, §24.9).
        let gone = now.addingTimeInterval(-28 * 86_400 - 1)
        out = plan(F.input(events: only, cache: F.answer(first.requests, at: gone),
                           queue: .init(failures: [first.requests[0].key: .init(reason: .offline)])))
        #expect(out.legs[F.epc.id]?.status == .unavailable)
    }

    @Test("Inside a refresh window: refreshedAt at the slot → ready; the slot's refresh failed → estimate, reason carried")
    func refreshWindow() {
        let clock = F.m(3, "11:31")
        let cache = F.answeredCache(now: clock)
        let base = plan(F.input(cache: cache, now: clock)).legs[F.epc.id]!
        var existing = base
        existing.refreshedAt = F.m(3, "11:30")
        var out = plan(F.input(cache: cache, existing: [F.epc.id: existing],
                               refreshes: [F.epc.id: .init(slot: F.m(3, "11:30"), failure: nil)], now: clock))
        #expect(out.legs[F.epc.id]?.status == .ready && out.legs[F.epc.id]?.refreshedAt == F.m(3, "11:30"))
        out = plan(F.input(cache: cache, existing: [F.epc.id: base],
                           refreshes: [F.epc.id: .init(slot: F.m(3, "11:30"), failure: .offline)], now: clock))
        #expect(out.legs[F.epc.id]?.status == .estimate && out.legs[F.epc.id]?.reason == .offline)
        #expect(hhmm(out.legs[F.epc.id]?.departAt) == "12:15")
    }

    @Test("A throttle pause: a leg with nothing to fall back on is unavailable · paused with the resume time")
    func paused() {
        let until = F.m(0, "06:20")
        let out = plan(F.input(queue: .init(pausedUntil: until)))
        let leg = out.legs[F.swqm.id]
        #expect(leg?.status == .unavailable && leg?.reason == .paused && leg?.retryAt == until)
        // The requests are still handed to the queue, which holds them.
        #expect(out.requests.count == 7)
    }

    // MARK: §30.1 "The test day"

    @Test("Overlap: a manual event at Home 12:00–12:30 while EPC-ILV runs 11:00–13:00 → origin campus, depart 11:15")
    func overlap() {
        let epc = F.lecture(14, "EPC-ILV", F.m(3, "11:00"), F.m(3, "13:00"), room: "LAB_F5.12")
        let lunch = F.manual(40, "Lunch at home", F.m(3, "12:00"), F.m(3, "12:30"), place: "home")
        let events = [epc, lunch]
        let out = plan(F.input(events: events, cache: F.answeredCache(events: events)))
        #expect(out.legs[lunch.id]?.originPlaceID == "campus")
        #expect(hhmm(out.legs[lunch.id]?.departAt) == "11:15")
    }

    @Test("Chain through a placeless event: Coffee (no place) between EPC-ILV and REQEN-EXAM → still no leg")
    func chainThroughPlaceless() {
        let coffee = F.manual(41, "Coffee", F.m(3, "14:40"), F.m(3, "15:00"), place: nil)
        let out = plan(F.input(events: F.events + [coffee], cache: F.answeredCache()))
        #expect(out.legs[F.reqen.id] == nil && out.ruleOrigins[F.reqen.id] == "campus")
    }

    @Test("Exactly chainGap (120 min) → chained; 121 → home")
    func chainGap() {
        let a = F.lecture(50, "A", F.m(3, "08:00"), F.m(3, "10:00"), room: "HS_1")
        let b = F.lecture(51, "B", F.m(3, "12:00"), F.m(3, "13:00"), room: "HS_2")
        var out = plan(F.input(events: [a, b]))
        #expect(out.ruleOrigins[b.id] == "campus" && out.legs[b.id] == nil)
        let c = F.lecture(51, "B", F.m(3, "12:01"), F.m(3, "13:00"), room: "HS_2")
        out = plan(F.input(events: [a, c]))
        #expect(out.ruleOrigins[c.id] == "home" && out.legs[c.id] != nil)
    }

    @Test("Skipped previous: EPC-ILV skipped → REQEN-EXAM from home, depart 15:15; EPC-ILV gets no leg")
    func skippedPrevious() {
        var epc = F.epc; epc.status = .skipped
        let events = F.events.map { $0.id == epc.id ? epc : $0 }
        let out = plan(F.input(events: events, cache: F.answeredCache(events: events)))
        #expect(out.legs[F.epc.id] == nil)
        #expect(out.ruleOrigins[F.reqen.id] == "home")
        #expect(hhmm(out.legs[F.reqen.id]?.departAt) == "15:15")
    }

    @Test("Cancelled and all-day events are never candidates; a routine block between two lectures changes nothing")
    func nonCandidates() {
        var cancelled = F.epc; cancelled.isCancelled = true
        var allDay = F.manual(42, "Trip", F.m(3, "00:00"), F.m(4, "00:00"), place: "campus"); allDay.isAllDay = true
        let routine = TravelEventSnapshot(id: F.id(43), title: "Gym", start: F.m(3, "14:35"), end: F.m(3, "15:30"),
                                          origin: .routine, placeID: F.gymID, sourceID: "routine")
        let events = F.events.map { $0.id == cancelled.id ? cancelled : $0 } + [allDay, routine]
        let out = plan(F.input(events: events))
        #expect(out.legs[cancelled.id] == nil && out.legs[allDay.id] == nil && out.legs[routine.id] == nil)
        #expect(out.ruleOrigins[F.reqen.id] == "home")   // the cancelled EPC-ILV is no origin either
        let withRoutine = plan(F.input(events: F.events + [routine]))
        #expect(withRoutine.ruleOrigins[F.reqen.id] == "campus" && withRoutine.legs[F.reqen.id] == nil)
    }

    @Test("An online lecture is never an origin; a .done previous event still is")
    func onlineAndDone() {
        let online = F.lecture(44, "INNO3-EL", F.m(2, "11:00"), F.m(2, "12:00"), room: "WEBINAR01", online: true)
        let after = F.manual(45, "Study", F.m(2, "12:30"), F.m(2, "13:30"), place: "campus")
        var out = plan(F.input(events: [online, after]))
        #expect(out.ruleOrigins[after.id] == "home")
        var done = F.epc; done.status = .done
        out = plan(F.input(events: [done, F.reqen]))
        #expect(out.ruleOrigins[F.reqen.id] == "campus" && out.legs[F.reqen.id] == nil)
        // A done event still has its own leg (§24.1).
        #expect(out.legs[done.id] != nil)
    }

    @Test("Origin ties resolve by the later start, then the smaller id")
    func ties() {
        // Both end 12:00; the later start (11:00, at Gym) wins.
        let a = F.manual(60, "A", F.m(3, "10:00"), F.m(3, "12:00"), place: "campus")
        let b = F.manual(61, "B", F.m(3, "11:00"), F.m(3, "12:00"), place: F.gymID)
        let e = F.manual(62, "E", F.m(3, "12:30"), F.m(3, "13:00"), place: "home")
        var out = plan(F.input(events: [a, b, e]))
        #expect(out.ruleOrigins[e.id] == F.gymID)
        // Same end and start: the smaller id (60) wins.
        let b2 = F.manual(61, "B", F.m(3, "10:00"), F.m(3, "12:00"), place: F.gymID)
        out = plan(F.input(events: [b2, a, e]))
        #expect(out.ruleOrigins[e.id] == "campus")
    }

    // MARK: §23.2

    @Test("§23.2: another kind's import, an empty location and an unknown placeID have no place")
    func placeRules() {
        let ids: Set<String> = ["home", "campus", F.gymID]
        let kinds = F.sourceKinds.merging(["mail-1": .mail]) { a, _ in a }
        let other = TravelEventSnapshot(title: "Mail meeting", start: now, end: now, origin: .imported,
                                        sourceID: "mail-1", locationText: "Room 1")
        #expect(PlaceResolver.place(of: other, sourceKinds: kinds, knownPlaceIDs: ids) == nil)
        let blank = TravelEventSnapshot(title: "X", start: now, end: now, origin: .imported,
                                        sourceID: F.timetableID, locationText: "  ")
        #expect(PlaceResolver.place(of: blank, sourceKinds: kinds, knownPlaceIDs: ids) == nil)
        let unknown = TravelEventSnapshot(title: "Y", start: now, end: now, origin: .manual, placeID: "deleted-place")
        #expect(PlaceResolver.place(of: unknown, sourceKinds: kinds, knownPlaceIDs: ids) == nil)
        #expect(PlaceResolver.place(of: F.swqm, sourceKinds: kinds, knownPlaceIDs: ids) == "campus")
        #expect(PlaceResolver.place(of: F.inno3, sourceKinds: kinds, knownPlaceIDs: ids) == nil)
        // Mode: the pair's override either way round, else preferred.
        #expect(PlaceResolver.mode(from: F.gymID, to: "home", overrides: F.overrides, preferred: .transit) == .walking)
        #expect(PlaceResolver.mode(from: "campus", to: F.gymID, overrides: F.overrides, preferred: .driving) == .driving)
    }

    @Test("The cache key: direction, day type, the 30-minute arrival slot, coordinates to 5 decimals")
    func cacheKey() {
        let home = F.home.endpoint!, campus = F.campus.endpoint!
        let k = TravelCacheKey(origin: home, destination: campus, mode: .transit, arrival: F.m(0, "08:50"),
                               calendar: F.calendar)
        #expect(k.string == "home@48.20000,16.39000>campus@48.23900,16.37700|transit|weekday|510")
        let back = TravelCacheKey(origin: campus, destination: home, mode: .transit, arrival: F.m(0, "08:50"),
                                  calendar: F.calendar)
        #expect(back.string != k.string)
        #expect(TravelCacheKey(origin: home, destination: campus, mode: .transit, arrival: F.m(5, "07:20"),
                               calendar: F.calendar).dayType == .saturday)
        #expect(TravelCacheKey(origin: home, destination: campus, mode: .transit, arrival: F.m(6, "07:20"),
                               calendar: F.calendar).dayType == .sunday)
        var moved = home; moved.latitude = 48.200004
        #expect(TravelCacheKey(origin: moved, destination: campus, mode: .transit, arrival: F.m(0, "08:50"),
                               calendar: F.calendar).string == k.string)
        moved.latitude = 48.20001
        #expect(TravelCacheKey(origin: moved, destination: campus, mode: .transit, arrival: F.m(0, "08:50"),
                               calendar: F.calendar).string != k.string)
    }
}
