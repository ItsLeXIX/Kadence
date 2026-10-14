//
//  NotificationPlannerTests.swift
//  KadenceTests
//
//  PHASE3-SLICE2-PLAN.md task 8 — components.md §27.1–§27.5, §27.6 (the
//  planning half), §27.9; §30.1's notification tables. Pure: events and legs
//  built in code from dataset `travel` (`M` = Mon 2026-10-12), legs planned
//  at the clock with the mock's answers.
//

import Testing
import Foundation
@testable import Kadence

struct NotificationPlannerTests {
    typealias F = TravelFixtures

    static let sleep = QuietWindow(weekdays: Set(1...7), startMinutes: 22 * 60, endMinutes: 7 * 60, label: "Sleep")
    static let defaultRules: [NotificationRuleKind: NotificationPlanner.Rule] = Dictionary(
        uniqueKeysWithValues: NotificationRuleKind.allCases.map { ($0, .init(leadMinutes: $0.defaultLeadMinutes, isEnabled: true)) })

    enum Variant { case travel, offline, noAddress }

    /// Legs as the coordinator would hold them at `now`.
    static func legs(at now: Date, variant: Variant = .travel, events: [TravelEventSnapshot] = F.events) -> [UUID: LegValues] {
        switch variant {
        case .travel:
            return TravelLegPlanner.plan(F.input(events: events, cache: F.answeredCache(now: now, events: events), now: now)).legs
        case .noAddress:
            return TravelLegPlanner.plan(F.input(events: events, places: F.placesNoHomeAddress, now: now)).legs
        case .offline:
            let first = TravelLegPlanner.plan(F.input(events: events, now: now))
            let stale = F.answer(first.requests.filter {
                $0.originPlaceID == "home" && $0.destinationPlaceID == "campus" && $0.dayType == .weekday
            }, at: F.date("2026-09-27 18:00"))
            let failures = Dictionary(uniqueKeysWithValues: first.requests.map {
                ($0.key, TravelLegPlanner.KeyFailure(reason: .offline, retryAt: nil))
            })
            return TravelLegPlanner.plan(F.input(events: events, cache: stale, queue: .init(failures: failures), now: now)).legs
        }
    }

    static func input(at now: Date, variant: Variant = .travel, events: [TravelEventSnapshot] = F.events,
                      legs: [UUID: LegValues]? = nil, rules: [NotificationRuleKind: NotificationPlanner.Rule] = defaultRules,
                      windows: [QuietWindow] = [sleep], records: [String: Date] = [:], catchUp: Bool = false,
                      refreshed: Set<UUID> = []) -> NotificationPlanner.Input {
        let places: Set<String> = ["home", "campus", F.gymID]
        let eventPlaces = Dictionary(uniqueKeysWithValues: events.compactMap { e in
            PlaceResolver.place(of: e, sourceKinds: F.sourceKinds, knownPlaceIDs: places).map { (e.id, $0) }
        })
        return NotificationPlanner.Input(
            events: events, legs: legs ?? Self.legs(at: now, variant: variant, events: events), eventPlaces: eventPlaces,
            placeNames: ["home": "Home", "campus": "FH Technikum Wien", F.gymID: "Gym"],
            sourceNames: [F.timetableID: "University timetable", "personal": "Personal", "routine": "Daily routine"],
            rules: rules, windows: windows, records: records, refreshedEarlier: refreshed, now: now,
            isCatchUp: catchUp, calendar: F.calendar)
    }

    func plan(_ input: NotificationPlanner.Input) -> [PlannedNotification] { NotificationPlanner.plan(input) }

    func leave(_ e: TravelEventSnapshot) -> String { "leave.\(e.id.uuidString)" }
    func start(_ e: TravelEventSnapshot) -> String { "start.\(e.id.uuidString)" }

    func check(_ n: PlannedNotification?, _ id: String, fire: Date, _ title: String, _ body: String,
               _ category: NotificationCategory, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(n?.identifier == id, sourceLocation: sourceLocation)
        #expect(n?.fireAt == fire, sourceLocation: sourceLocation)
        #expect(n?.text.title == title, sourceLocation: sourceLocation)
        #expect(n?.text.body == body, sourceLocation: sourceLocation)
        #expect(n?.category == category, sourceLocation: sourceLocation)
        #expect(n?.playsSound == true, sourceLocation: sourceLocation)
        #expect(n?.interruption == (id.hasPrefix("leave.") ? .timeSensitive : .active), sourceLocation: sourceLocation)
    }

    // MARK: §30.1's tables

    @Test("Thu 15 Oct 06:00, ordinary pass: 4 pending, exactly")
    func thursday() {
        let out = plan(Self.input(at: F.m(3, "06:00")))
        #expect(out.count == 4)
        check(out[0], leave(F.epc), fire: F.m(3, "12:10"), "Leave by 12:15 for EPC-ILV",
              "Starts 13:00 · LAB_F5.12 · 35 min from Home", .readOnly)
        check(out[1], start(F.reqen), fire: F.m(3, "15:30"), "REQEN-EXAM starts at 16:00",
              "EDV_A5.09 · University timetable", .readOnly)
        check(out[2], leave(F.dinner), fire: F.m(3, "17:40"), "Leave by 17:45 for Dinner with flatmates",
              "Starts 18:30 · Home · 35 min from FH Technikum Wien", .event)
        check(out[3], leave(F.swrm), fire: F.m(4, "15:10"), "Leave by 15:15 for SWRM-ILV",
              "Starts 16:00 · UEB_B2.01 · 35 min from Home", .readOnly)
        #expect(out.allSatisfy { !$0.atOnce })
    }

    @Test("Fri 16 Oct 23:00, ordinary pass: 3 pending — the held leave-by (N2), Late call inside Sleep, Climbing")
    func fridayNight() {
        let out = plan(Self.input(at: F.m(4, "23:00")))
        #expect(out.count == 3)
        check(out[0], leave(F.earlyStudy), fire: F.m(5, "07:00"), "Leave now for Early study group",
              "Starts 07:30 · FH Technikum Wien · Leave-by was 06:45, inside Sleep (protected)", .event)
        check(out[1], start(F.lateCall), fire: F.m(5, "23:00"), "Late call starts at 23:15", "Personal", .event)
        check(out[2], leave(F.climbing), fire: F.m(6, "17:40"), "Leave by 17:45 for Climbing",
              "Starts 18:00 · Gym · 5 min from Home", .event)
        // SWRM-ILV's leave-by (Fri 15:10) has passed: not planned, not late.
        #expect(!out.contains { $0.identifier == leave(F.swrm) })
    }

    @Test("Routing states at Thu 06:00: travelOffline (N1e, N7), exactly; after recovery the same ids with N1")
    func offline() {
        let out = plan(Self.input(at: F.m(3, "06:00"), variant: .offline))
        #expect(out.count == 4)
        check(out[0], leave(F.epc), fire: F.m(3, "12:10"), "Leave by about 12:15 for EPC-ILV",
              "Starts 13:00 · LAB_F5.12 · about 35 min from Home · estimate, offline", .readOnly)
        check(out[1], start(F.reqen), fire: F.m(3, "15:30"), "REQEN-EXAM starts at 16:00",
              "EDV_A5.09 · University timetable", .readOnly)
        check(out[2], leave(F.dinner), fire: F.m(3, "17:30"), "Dinner with flatmates starts at 18:30",
              "Home · Travel time from FH Technikum Wien unavailable: offline. Check your route before you leave.", .event)
        check(out[3], leave(F.swrm), fire: F.m(4, "15:10"), "Leave by about 15:15 for SWRM-ILV",
              "Starts 16:00 · UEB_B2.01 · about 35 min from Home · estimate, offline", .readOnly)
        // The provider recovers: the same identifiers, N1 content, new hashes.
        let recovered = plan(Self.input(at: F.m(3, "06:00")))
        #expect(recovered.map(\.identifier) == out.map(\.identifier))
        for (a, b) in zip(out, recovered) where a.identifier.hasPrefix("leave.") {
            #expect(a.contentHash != b.contentHash)
            #expect(b.text.title.hasPrefix("Leave by ") && !b.text.title.contains("about"))
        }
    }

    @Test("travelNoAddress at Thu 06:00: N7 with `Home has no address`; REQEN-EXAM unchanged")
    func noAddress() {
        let out = plan(Self.input(at: F.m(3, "06:00"), variant: .noAddress))
        #expect(out.count == 4)
        check(out[0], leave(F.epc), fire: F.m(3, "12:00"), "EPC-ILV starts at 13:00",
              "LAB_F5.12 · Travel time from Home unavailable: Home has no address. Check your route before you leave.", .readOnly)
        check(out[1], start(F.reqen), fire: F.m(3, "15:30"), "REQEN-EXAM starts at 16:00",
              "EDV_A5.09 · University timetable", .readOnly)
        check(out[2], leave(F.dinner), fire: F.m(3, "17:30"), "Dinner with flatmates starts at 18:30",
              "Home · Travel time from FH Technikum Wien unavailable: Home has no address. Check your route before you leave.", .event)
        check(out[3], leave(F.swrm), fire: F.m(4, "15:00"), "SWRM-ILV starts at 16:00",
              "UEB_B2.01 · Travel time from Home unavailable: Home has no address. Check your route before you leave.", .readOnly)
    }

    @Test("A pending leg's N7: `isn't worked out yet`")
    func pendingN7() {
        let legs = TravelLegPlanner.plan(F.input(now: F.m(3, "06:00"))).legs
        let out = plan(Self.input(at: F.m(3, "06:00"), legs: legs))
        let epc = out.first { $0.identifier == leave(F.epc) }
        #expect(epc?.text.body == "LAB_F5.12 · Travel time from Home isn't worked out yet. Check your route before you leave.")
        #expect(epc?.fireAt == F.m(3, "12:00") && epc?.interruption == .timeSensitive)
    }

    // MARK: Departure refresh (§30.1, the notification half)

    func legsWithEPC(minutes: Int, at now: Date) -> [UUID: LegValues] {
        var legs = Self.legs(at: now)
        legs[F.epc.id]?.duration = TimeInterval(minutes * 60)
        legs[F.epc.id]?.departAt = F.m(3, "13:00").addingTimeInterval(TimeInterval(-600 - minutes * 60))
        return legs
    }

    @Test("Departure refresh: 50 → replaced at 11:55, 30 → 12:15; 78 → delivered at once in an ordinary pass, nothing else late")
    func departureRefresh() {
        let now = F.m(3, "11:30")
        let pending = [leave(F.epc): F.m(3, "12:10")]
        var out = plan(Self.input(at: now, legs: legsWithEPC(minutes: 50, at: now), records: pending, refreshed: [F.epc.id]))
        check(out.first { $0.identifier == leave(F.epc) }, leave(F.epc), fire: F.m(3, "11:55"),
              "Leave by 12:00 for EPC-ILV", "Starts 13:00 · LAB_F5.12 · 50 min from Home", .readOnly)
        out = plan(Self.input(at: now, legs: legsWithEPC(minutes: 30, at: now), records: pending))
        #expect(out.first { $0.identifier == leave(F.epc) }?.fireAt == F.m(3, "12:15"))
        #expect(out.first { $0.identifier == leave(F.epc) }?.text.title == "Leave by 12:20 for EPC-ILV")
        // 78: departAt 11:32, the new F 11:27 has passed, departAt has not.
        let late = F.manual(70, "Errand", F.m(3, "11:40"), F.m(3, "12:00"), place: nil)   // its F (11:25) passed too
        let events = F.events + [late]
        var legs = legsWithEPC(minutes: 78, at: now)
        legs[late.id] = nil
        out = plan(Self.input(at: now, events: events, legs: legs, records: pending, refreshed: [F.epc.id]))
        let epc = out.first { $0.identifier == leave(F.epc) }
        #expect(epc?.atOnce == true && epc?.fireAt == now)
        #expect(epc?.text.title == "Leave by 11:32 for EPC-ILV")
        #expect(epc?.text.body == "Starts 13:00 · LAB_F5.12 · 78 min from Home")
        #expect(out.filter { $0.atOnce }.count == 1)
        #expect(!out.contains { $0.identifier == start(late) })
        // The same without the refresh: an ordinary pass sends nothing late.
        out = plan(Self.input(at: now, events: events, legs: legs, records: pending))
        #expect(!out.contains { $0.identifier == leave(F.epc) })
    }

    // MARK: Catch-up (§27.6)

    @Test("Catch-up: Thu 12:12 → N1 at once; 12:20 → N3 at once; 13:05 → nothing; ordinary passes plan nothing late")
    func catchUp() {
        var out = plan(Self.input(at: F.m(3, "12:12"), catchUp: true))
        let n1 = out.first { $0.identifier == leave(F.epc) }
        #expect(n1?.atOnce == true && n1?.text.title == "Leave by 12:15 for EPC-ILV")
        out = plan(Self.input(at: F.m(3, "12:20"), catchUp: true))
        check(out.first { $0.identifier == leave(F.epc) }, leave(F.epc), fire: F.m(3, "12:20"), "Leave now for EPC-ILV",
              "Starts 13:00 · LAB_F5.12 · Leave-by was 12:15", .readOnly)
        #expect(out.first { $0.identifier == leave(F.epc) }?.atOnce == true)
        out = plan(Self.input(at: F.m(3, "13:05"), catchUp: true))
        #expect(!out.contains { $0.identifier == leave(F.epc) })
        for clock in ["12:12", "12:20", "13:05"] {
            let ordinary = plan(Self.input(at: F.m(3, clock)))
            #expect(!ordinary.contains { $0.identifier == leave(F.epc) }, "\(clock)")
            #expect(ordinary.allSatisfy { !$0.atOnce })
        }
        // A record means it was sent: no catch-up.
        out = plan(Self.input(at: F.m(3, "12:12"), records: [leave(F.epc): F.m(3, "12:10")], catchUp: true))
        #expect(!out.contains { $0.identifier == leave(F.epc) })
    }

    // MARK: The test day's extras

    @Test("Two protected spans back to back (22:00–07:00, 07:00–07:30): a notification due 06:50 is held to 07:30")
    func backToBackSpans() {
        let breakfast = F.manual(71, "Breakfast meeting", F.m(3, "07:50"), F.m(3, "08:30"), place: nil)
        var rules = Self.defaultRules
        rules[.personalStart] = .init(leadMinutes: 60, isEnabled: true)
        let early = QuietWindow(weekdays: Set(1...7), startMinutes: 7 * 60, endMinutes: 7 * 60 + 30, label: "Wake up")
        let out = plan(Self.input(at: F.m(2, "23:00"), events: [breakfast], legs: [:], rules: rules,
                                  windows: [Self.sleep, early]))
        #expect(out.first?.fireAt == F.m(3, "07:30"))
        #expect(out.first?.text.title == "Breakfast meeting starts at 07:50")
    }

    @Test("Leave by off → EPC-ILV gets start. at 12:30 under timetableStart; all rules off → empty")
    func rulesOff() {
        var rules = Self.defaultRules
        rules[.leaveBy]?.isEnabled = false
        var out = plan(Self.input(at: F.m(3, "06:00"), rules: rules))
        check(out.first { $0.identifier == start(F.epc) }, start(F.epc), fire: F.m(3, "12:30"), "EPC-ILV starts at 13:00",
              "LAB_F5.12 · University timetable", .readOnly)
        #expect(!out.contains { $0.identifier.hasPrefix("leave.") })
        for kind in NotificationRuleKind.allCases { rules[kind]?.isEnabled = false }
        out = plan(Self.input(at: F.m(3, "06:00"), rules: rules))
        #expect(out.isEmpty)
    }

    @Test("Exclusions: done, skipped, cancelled, all-day, events before today, a subject time in the past")
    func exclusions() {
        var done = F.epc; done.status = .done
        var skipped = F.reqen; skipped.status = .skipped
        var cancelled = F.swrm; cancelled.isCancelled = true
        var allDay = F.manual(72, "Trip", F.m(3, "00:00"), F.m(4, "00:00"), place: nil); allDay.isAllDay = true
        let yesterday = F.manual(73, "Yesterday", F.m(2, "23:30"), F.m(3, "00:30"), place: nil)
        let past = F.manual(74, "Earlier", F.m(3, "05:00"), F.m(3, "05:30"), place: nil)
        let events = [done, skipped, cancelled, allDay, yesterday, past]
        let out = plan(Self.input(at: F.m(3, "06:00"), events: events, catchUp: true))
        #expect(out.isEmpty)
    }

    @Test("At most one of leave. / start. per event, in every case, including N7")
    func oneEach() {
        let inputs = [Self.input(at: F.m(3, "06:00")), Self.input(at: F.m(4, "23:00")),
                      Self.input(at: F.m(3, "06:00"), variant: .offline), Self.input(at: F.m(3, "06:00"), variant: .noAddress),
                      Self.input(at: F.m(3, "12:20"), catchUp: true), Self.input(at: F.m(0, "06:00"))]
        for input in inputs {
            let subjects = plan(input).map(\.subjectID)
            #expect(Set(subjects).count == subjects.count)
        }
    }

    @Test("Window edges: now + 48 h planned, a second later not; 60 candidates → the 48 earliest")
    func windowEdges() {
        let now = F.m(3, "06:00")
        let edge = F.manual(75, "Edge", now.addingTimeInterval(48 * 3600 + 15 * 60), now.addingTimeInterval(49 * 3600), place: nil)
        let beyond = F.manual(76, "Beyond", now.addingTimeInterval(48 * 3600 + 15 * 60 + 1), now.addingTimeInterval(49 * 3600), place: nil)
        let out = plan(Self.input(at: now, events: [edge, beyond], legs: [:], windows: []))
        #expect(out.map(\.subjectID) == [edge.id.uuidString])
        let many = (0..<60).map { i in
            F.manual(100 + i, "E\(i)", now.addingTimeInterval(TimeInterval(3600 + i * 600)),
                     now.addingTimeInterval(TimeInterval(3900 + i * 600)), place: nil)
        }
        let capped = plan(Self.input(at: now, events: many, legs: [:], windows: []))
        #expect(capped.count == 48)
        #expect(capped.map(\.subjectID) == many.prefix(48).map(\.id.uuidString))
    }

    @Test("A sent record is never planned again; a later subject is")
    func records() {
        let now = F.m(3, "12:11")
        let sent = [leave(F.epc): F.m(3, "12:10")]
        #expect(!plan(Self.input(at: now, records: sent)).contains { $0.identifier == leave(F.epc) })
        // The event moved an hour later: a new fire date in the future.
        var epc = F.epc
        epc.start = F.m(3, "14:00"); epc.end = F.m(3, "15:30")
        let events = F.events.map { $0.id == epc.id ? epc : $0 }
        let moved = plan(Self.input(at: now, events: events, records: sent))
        #expect(moved.first { $0.identifier == leave(F.epc) }?.fireAt == F.m(3, "13:10"))
    }

    @Test("No title or body contains late, missed, overdue or `!`; none an address or a coordinate")
    func copyBans() {
        let all = [Self.input(at: F.m(3, "06:00")), Self.input(at: F.m(4, "23:00")),
                   Self.input(at: F.m(3, "06:00"), variant: .offline), Self.input(at: F.m(3, "06:00"), variant: .noAddress),
                   Self.input(at: F.m(3, "12:20"), catchUp: true), Self.input(at: F.m(3, "12:12"), catchUp: true)]
            .flatMap { plan($0) }
        #expect(!all.isEmpty)
        // The user's own titles (`Late call`) are not Kadence's words.
        let titles = F.events.map(\.title)
        for n in all {
            for full in [n.text.title, n.text.body] {
                let text = titles.reduce(full) { $0.replacingOccurrences(of: $1, with: "") }
                for banned in ["late", "missed", "overdue", "!", "Example", "Höchstädtplatz", "1030 Wien", "1200 Wien"] {
                    #expect(!text.localizedCaseInsensitiveContains(banned), "\(banned) in \(text)")
                }
                #expect(text.range(of: #"\d+\.\d{3,}"#, options: .regularExpression) == nil)
            }
        }
        // N5, N6, N8 too.
        let cal = F.calendar
        let more = [NotificationCopy.n5(title: "Dinner with flatmates", oldStart: F.m(3, "18:30"), newStart: F.m(3, "18:45"), calendar: cal),
                    NotificationCopy.n6(title: "Late call", newStart: F.m(5, "23:30"), window: "Sleep", calendar: cal),
                    NotificationCopy.n8(name: "University timetable", host: "cis.technikum-wien.at", user: "user01", forbidden: false)]
        for text in more { #expect(!text.title.contains("!") && !text.body.lowercased().contains("late ")) }
    }

    @Test("The copy of N5, N6, N8 and N2's unlabelled window, exact")
    func otherCopy() {
        let cal = F.calendar
        let n5 = NotificationCopy.n5(title: "Dinner with flatmates", oldStart: F.m(3, "18:30"), newStart: F.m(3, "18:45"), calendar: cal)
        #expect(n5 == NotificationText(title: "Dinner with flatmates moved to 18:45", body: "Snoozed from 18:30 · ⌘Z in Kadence undoes it"))
        let tomorrow = NotificationCopy.n5(title: "Reading", oldStart: F.m(3, "23:50"), newStart: F.m(4, "00:05"), calendar: cal)
        #expect(tomorrow.title == "Reading moved to tomorrow 00:05")
        #expect(NotificationCopy.n6(title: "Late call", newStart: F.m(5, "23:30"), window: "Sleep", calendar: cal)
                == NotificationText(title: "Late call not moved", body: "23:30 is inside Sleep (protected)"))
        #expect(NotificationCopy.n6(title: "X", newStart: F.m(5, "23:30"), window: "", calendar: cal).body
                == "23:30 is inside a protected window")
        #expect(NotificationCopy.n8(name: "University timetable", host: "cis.technikum-wien.at", user: "user01", forbidden: false)
                == NotificationText(title: "University timetable isn't syncing",
                                    body: "cis.technikum-wien.at didn't accept the password for user01. Sync is paused until you update it in Kadence."))
        #expect(NotificationCopy.n8(name: "University timetable", host: "cis.technikum-wien.at", user: "user01", forbidden: true).body
                == "cis.technikum-wien.at refused access for user01. Sync is paused until you check the account in Kadence.")
        #expect(NotificationCopy.n2(title: "A", depart: "06:45", start: "07:30", where: nil, window: "", isEstimate: true).body
                == "Starts 07:30 · Leave-by was about 06:45, inside a protected window")
    }
}
