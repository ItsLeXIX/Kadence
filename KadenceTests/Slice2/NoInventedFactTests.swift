//
//  NoInventedFactTests.swift
//  KadenceTests
//
//  P3S2-F02 — components.md §24.10 "No invented fact in the copy either"
//  (DECISIONS 2026-10-15 "No invented fact, in copy as in numbers") and
//  layouts.md §6 row 4 (`Origin` as a word). Each surface is given a leg
//  that lacks a value the recompute normally sets: (a) an origin id that
//  resolves to no place, (b) an estimate with no reason, (c) an unavailable
//  leg with no reason, (d) a `paused` with no retry time, (e) a time with no
//  duration. Every leg's origin is unresolvable, so no surface may say
//  `Home`; none may say `offline`, `0 min`, `This place` or `later` either.
//

import Testing
import Foundation
@testable import Kadence

@MainActor
struct NoInventedFactTests {
    typealias F = TravelFixtures

    static let cal = F.calendar
    static let now = F.date("2026-10-15 07:00")
    static let start = F.date("2026-10-15 09:00")
    static let departAt = F.date("2026-10-15 08:15")
    static let lecture = F.lecture(40, "SWQM-ILV", start, F.date("2026-10-15 10:30"), room: "HS_A3.15")
    static let places = ["home": "Home", "campus": "FH Technikum Wien", F.gymID: "Gym"]

    enum Case: String, CaseIterable { case noOrigin, estimateNoReason, unavailableNoReason, pausedNoRetry, noDuration }

    static func leg(_ c: Case) -> LegValues {
        var leg = LegValues(eventID: lecture.id, status: .ready, departAt: departAt, duration: 35 * 60, buffer: 0,
                            mode: .transit, originPlaceID: "removed-place", destinationPlaceID: "campus",
                            source: "mock", computedAt: now)
        switch c {
        case .noOrigin: break
        case .estimateNoReason: leg.status = .estimate
        case .unavailableNoReason:
            leg.status = .unavailable; leg.departAt = nil; leg.duration = nil
        case .pausedNoRetry:
            leg.status = .unavailable; leg.reason = .paused; leg.departAt = nil; leg.duration = nil
        case .noDuration: leg.duration = nil
        }
        return leg
    }

    /// Every string each surface shows or speaks for `leg`.
    static func strings(_ c: Case) throws -> [String: String] {
        let leg = leg(c)
        var out: [String: String] = [:]
        let info = TravelPresentation.info(leg, placeNames: places, calendar: cal)
        if let band = info.band {
            out["band help"] = TravelPresentation.bandHelp(band, calendar: cal)
            out["band VoiceOver"] = TravelPresentation.spoken(band, calendar: cal)
        } else {
            out["block help suffix"] = info.helpSuffix
            out["block VoiceOver"] = info.spoken
        }
        let row = TravelPresentation.leaveBy(leg, placeNames: places, now: now, pausedUntil: nil, calendar: cal)
        out["inspector"] = ([row.value] + row.lines).joined(separator: " | ")
        out["inspector VoiceOver"] = row.spoken

        let event = Event(title: lecture.title, start: lecture.start, end: lecture.end, origin: .imported,
                          sourceID: F.timetableID)
        let result = NextUpProvider.Result(next: event, isLate: false, restOfToday: [], leg: leg)
        out["popover"] = MenuBarFormatting.leaveLine(result, now: now, placeNames: places, calendar: cal)?.text
        out["popover VoiceOver"] = MenuBarFormatting.nextAccessibilityValue(result, now: now, placeNames: places)
        out["status item"] = MenuBarFormatting.statusAccessibilityLabel(result, now: now)
        if leg.hasTime, let departAt = leg.departAt {
            out["status unit"] = MenuBarFormatting.leaveUnit(departAt: departAt, isEstimate: leg.isEstimate)
        }

        let planned = NotificationPlanner.plan(NotificationPlannerTests.input(at: now, events: [lecture],
                                                                            legs: [lecture.id: leg]))
        let n = try #require(planned.first { $0.subjectID == lecture.id.uuidString })
        out["notification"] = n.text.title + " / " + n.text.body
        return out
    }

    @Test("Each surface says only what the leg carries", arguments: Case.allCases)
    func scan(_ c: Case) throws {
        for (surface, text) in try Self.strings(c) {
            for banned in ["Home", "offline", "0 min", "This place", "this place", "later", "earlier", "didn't answer"] {
                #expect(!text.contains(banned), "\(c) · \(surface): \(text)")
            }
        }
    }

    @Test("(a) No origin: the `from …` clause is left out")
    func noOrigin() throws {
        let s = try Self.strings(.noOrigin)
        #expect(s["band help"] == "Leave 08:15 · 35 min by public transport")
        #expect(s["band VoiceOver"] == "leave by 08:15, 35 minutes by public transport")
        #expect(s["popover"] == "Leave by 08:15 · 35 min")
        #expect(s["inspector"]?.hasPrefix("08:15 | 35 min by public transport | Worked out") == true)
        #expect(s["popover VoiceOver"]?.hasPrefix("Leave by 08:15, 35 minutes. ") == true)
        #expect(s["notification"] == "Leave by 08:15 for SWQM-ILV / Starts 09:00 · HS_A3.15 · 35 min")
    }

    @Test("(b) An estimate with no reason says `estimate` alone")
    func estimateNoReason() throws {
        let s = try Self.strings(.estimateNoReason)
        #expect(s["popover"] == "Leave by ≈08:15 · estimate")
        #expect(s["band help"] == "Leave about 08:15 · about 35 min by public transport · estimate")
        #expect(s["inspector"]?.contains("Couldn't update") == false)
        #expect(s["inspector"]?.hasPrefix("08:15 | About 35 min by public transport | Last worked out") == true)
        #expect(s["notification"] == "Leave by about 08:15 for SWQM-ILV / Starts 09:00 · HS_A3.15 · about 35 min · estimate")
    }

    @Test("(c) Unavailable with no reason: `Travel time unavailable`, nothing after it")
    func unavailableNoReason() throws {
        let s = try Self.strings(.unavailableNoReason)
        #expect(s["popover"] == "Travel time unavailable")
        #expect(s["block help suffix"] == "· Travel time unavailable")
        #expect(s["block VoiceOver"] == "travel time unavailable")
        #expect(s["inspector"] == "Unavailable")
        #expect(s["inspector VoiceOver"] == "Leave by, unavailable")
        #expect(s["notification"] == "SWQM-ILV starts at 09:00 / HS_A3.15 · Travel time unavailable. Check your route before you leave.")
    }

    @Test("(d) Paused with no retry time: `Apple Maps paused`, no `until`")
    func pausedNoRetry() throws {
        let s = try Self.strings(.pausedNoRetry)
        #expect(s["popover"] == "Travel time unavailable · Apple Maps paused")
        #expect(s["block help suffix"] == "· Travel time unavailable: Apple Maps paused")
        #expect(s["inspector"] == "Unavailable | Kadence is waiting before it asks Apple Maps again.")
        #expect(s["notification"] == "SWQM-ILV starts at 09:00 / HS_A3.15 · Travel time unavailable: Apple Maps paused. Check your route before you leave.")
    }

    @Test("(e) No duration: the minutes are left out, never `0 min`")
    func noDuration() throws {
        let s = try Self.strings(.noDuration)
        #expect(s["popover"] == "Leave by 08:15")
        #expect(s["notification"] == "Leave by 08:15 for SWQM-ILV / Starts 09:00 · HS_A3.15")
        #expect(s["inspector"]?.hasPrefix("08:15 | By public transport | Worked out") == true)
    }

    @Test("Short reasons fill in nothing; N2, N3, N4 carry no leg values")
    func copyPieces() {
        #expect(TravelCopy.shortReason(.needsAddress, place: nil, mode: .transit, retryAt: nil, calendar: Self.cal) == nil)
        #expect(TravelCopy.shortReason(.needsAddress, place: "Home", mode: .transit, retryAt: nil, calendar: Self.cal)
                == "Home has no address")
        #expect(TravelCopy.shortReason(.paused, place: nil, mode: .transit, retryAt: nil, calendar: Self.cal) == "Apple Maps paused")
        var leg = Self.leg(.unavailableNoReason)
        leg.reason = .needsAddress
        #expect(TravelPresentation.sentence(.needsAddress, leg: leg, placeNames: Self.places, calendar: Self.cal)
                == "Add the address in Settings ▸ Travel so Kadence can work out the trip.")
        leg.originPlaceID = nil
        #expect(TravelPresentation.sentence(.pending, leg: leg, placeNames: Self.places, calendar: Self.cal)
                == "Kadence is asking Apple Maps for the trip.")
        #expect(NotificationCopy.n2(title: "T", depart: "08:15", start: "09:00", where: nil, window: "Sleep", isEstimate: false).body
                == "Starts 09:00 · Leave-by was 08:15, inside Sleep (protected)")
        #expect(NotificationCopy.n3(title: "T", depart: "08:15", start: "09:00", where: nil, isEstimate: true).body
                == "Starts 09:00 · Leave-by was about 08:15")
        #expect(NotificationCopy.n4(title: "T", start: "09:00", where: "HS_A3.15", source: nil).body == "HS_A3.15")
        #expect(NotificationCopy.n7(title: "T", start: "09:00", where: nil, origin: "Home", reason: nil).body
                == "Travel time from Home unavailable. Check your route before you leave.")
        #expect(NotificationCopy.n7(title: "T", start: "09:00", where: nil, origin: nil, reason: nil, isPending: true).body
                == "Travel time isn't worked out yet. Check your route before you leave.")
    }

    @Test("A removed place's legs are rewritten in the same pass: every origin resolves")
    func removedPlace() {
        let withoutGym = F.places.filter { $0.id != F.gymID }
        let out = TravelLegPlanner.plan(F.input(places: withoutGym, now: F.m(0, "06:00")))
        let ids = Set(withoutGym.map(\.id))
        #expect(!out.legs.isEmpty)
        for leg in out.legs.values where leg.originKind == .place {
            #expect(leg.originPlaceID.map(ids.contains) ?? true, "\(leg.originPlaceID ?? "")")
            #expect(leg.reasonPlaceID.map(ids.contains) ?? true)
        }
    }

    @Test("Inspector `Origin` is a word: Manual · Routine · Imported · Planned")
    func originWord() throws {
        #expect(EventOrigin.allCases.map(\.displayName) == ["Manual", "Routine", "Imported", "Planned"])
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Kadence/Views/Chrome/InspectorView.swift")
        let source = try String(contentsOf: url, encoding: .utf8)
        #expect(source.contains("field(\"Origin\", event.origin.displayName)"))
        #expect(!source.contains("event.origin.rawValue"))
    }
}
