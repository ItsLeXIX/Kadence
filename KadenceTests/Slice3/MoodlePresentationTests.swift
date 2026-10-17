//
//  MoodlePresentationTests.swift
//  KadenceTests
//
//  PHASE3-SLICE3-PLAN.md task 4 — components.md §36 (pairing), §37.1–§37.4
//  (label, drop-the-time, sort, hover help, VoiceOver, inspector values),
//  §35.5 (the timetable mapping), §39 (the menu bar's selection). Pure, on
//  the fixture's items; Europe/Vienna.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

private typealias F = MoodleFixture

/// The fixture as stored items of one source (`moodle`); `900004` done when
/// asked (the `moodleOnly` dataset's mark).
private func items(_ feedCase: MoodleFeedCase = .feedOK, done: Set<String> = []) -> [MomentItem] {
    (F.feed(feedCase)?.items ?? []).map { MomentItem($0, sourceID: "moodle", isDone: done.contains(F.number($0))) }
}

private func item(_ number: String, in list: [MomentItem]) -> MomentItem? {
    list.first { $0.externalID.hasPrefix(number + "@") }
}

private func presentation(_ number: String, in list: [MomentItem]) throws -> MomentPresentation {
    let it = try #require(item(number, in: list))
    let pairs = MoodlePairing.pairs(list)
    return MomentPresentation(it, opening: pairs.opening(of: it), sourceName: "Moodle", zone: F.zone)
}

@MainActor
struct MoodlePresentationTests {

    @Test("§36: the fixture's four pairs; 900006 and 900007 stand alone")
    func fixturePairs() {
        let all = items()
        let pairs = MoodlePairing.pairs(all)
        func n(_ s: String) -> String { String(s.prefix { $0 != "@" }) }
        let pairsByNumber = Dictionary(uniqueKeysWithValues: pairs.openingOf.map { (n($0.key), n($0.value.externalID)) })
        #expect(pairsByNumber == ["900015": "900002", "900016": "900003", "900011": "900009", "900012": "900010"])
        #expect(Set(pairs.pairedOpenings.map(n)) == ["900002", "900003", "900009", "900010"])
        #expect(pairsByNumber["900006"] == nil && pairsByNumber["900007"] == nil)
    }

    @Test("§36: feedChanged's 900031 unpaired; a re-sync that moves an opening re-pairs; ties by externalID")
    func repairing() throws {
        let changed = items(.feedChanged)
        let pairs = MoodlePairing.pairs(changed)
        let quiz3 = try #require(item("900031", in: changed))
        #expect(!pairs.isPairedOpening(quiz3))
        #expect(pairs.opening(of: try #require(item("900030", in: changed))) == nil)

        // Move 900009 (F2 opens) after its deadline: 900011 loses its opening.
        var moved = items()
        let at = try #require(moved.firstIndex { $0.externalID.hasPrefix("900009@") })
        moved[at].start = F.date("2026-10-22 18:00"); moved[at].end = moved[at].start
        let after = MoodlePairing.pairs(moved)
        #expect(after.opening(of: try #require(item("900011", in: moved))) == nil)
        #expect(!after.isPairedOpening(moved[at]))
        // Two openings at the same time for one key: the latest by externalID wins.
        let base = try #require(item("900009", in: items()))
        var twin = base; twin.externalID = "900008b@moodle.technikum-wien.at"
        var other = base; other.externalID = "900009b@moodle.technikum-wien.at"
        let deadline = try #require(item("900011", in: items()))
        let tie = MoodlePairing.pairs([twin, other, deadline])
        #expect(tie.opening(of: deadline)?.externalID == "900009b@moodle.technikum-wien.at")
    }

    @Test("Labels: 23:59 INNO3 · Sprint Review…, 16:10–17:47 REQEN · F2, 23:50 RW · Mitarbeit Lektion 5, no code")
    func labels() throws {
        let all = items()
        let p5 = try presentation("900005", in: all)
        #expect(p5.time == "23:59" && p5.text == "INNO3 · Sprint Review Protocol for Sprint 1 (till Tuesday 23:59 in T0 + 2)")
        let p11 = try presentation("900011", in: all)
        #expect(p11.time == "16:10–17:47" && p11.text == "REQEN · F2")
        #expect(try presentation("900012", in: all).time == "16:10–17:48")
        // The opening is on another day: no window.
        let p15 = try presentation("900015", in: all)
        #expect(p15.time == "23:50" && p15.text == "RW · Mitarbeit Lektion 5")
        let p13 = try presentation("900013", in: all)
        #expect(p13.time == "23:59" && p13.text.hasPrefix("VERBINDLICHE Anmeldung für die Studienreise nach Manila"))
        #expect(!p13.text.contains("FK CS"))
        // Glyphs and the rail.
        #expect(p5.glyph == "flag.fill" && p5.hasRail)
        let opening = MomentPresentation(try #require(item("900031", in: items(.feedChanged))), sourceName: "Moodle", zone: F.zone)
        #expect(opening.glyph == "lock.open.fill" && !opening.hasRail)
        let notice = MomentPresentation(try #require(item("900040", in: items(.feedNotice))), sourceName: "Moodle", zone: F.zone)
        #expect(notice.glyph == "info.circle.fill" && !notice.hasRail)
        #expect(notice.text == "SWQM · Guest lecture: Testing in practice" && notice.time == "10:00")
        let done = try presentation("900004", in: items(done: ["900004"]))
        #expect(done.glyph == "checkmark.circle.fill")
    }

    @Test("Drop-the-time: under 44pt of text after the time, the time goes; below the glyph alone, the glyph alone")
    func dropTheTime() {
        let glyph: CGFloat = 11, time: CGFloat = 30, sp = Tokens.Spacing.xs
        let fits = glyph + sp + time + sp + 44
        #expect(MomentPresentation.layout(available: fits, glyph: glyph, time: time)
                == .init(showsTime: true, showsText: true))
        #expect(MomentPresentation.layout(available: fits - 0.5, glyph: glyph, time: time)
                == .init(showsTime: false, showsText: true))
        #expect(MomentPresentation.layout(available: glyph, glyph: glyph, time: time)
                == .init(showsTime: false, showsText: false))
    }

    @Test("Sort: Tue 3 Nov → Lessons Learned Lektion 5, Mitarbeit Lektion 5 (23:50), then Sprint Review… (23:59)")
    func sort() {
        let all = items()
        let tuesday = all.filter { F.calendar.isDate($0.start, inSameDayAs: F.date("2026-11-03 12:00")) }
        #expect(MomentSort.sorted(tuesday).map(\.title) == [
            "Lessons Learned Lektion 5", "Mitarbeit Lektion 5",
            "Sprint Review Protocol for Sprint 2 (till Tuesday 23:59 in T0 + 4)",
        ])
        // deadline · opening · notice at one time.
        let t = F.date("2026-10-20 10:00")
        func m(_ kind: ImportKind, _ title: String) -> MomentItem {
            MomentItem(externalID: title, sourceID: "moodle", title: title, upstreamTitle: title, kind: kind,
                       wording: kind == .notice ? nil : (kind == .opening ? .opens : .due), start: t, end: t)
        }
        #expect(MomentSort.sorted([m(.notice, "A"), m(.opening, "B"), m(.deadline, "C")]).map(\.title) == ["C", "B", "A"])
    }

    @Test("Hover help: every §37.1 example, exactly")
    func hoverHelp() throws {
        let all = items()
        #expect(try presentation("900005", in: all).hoverHelp
                == "INNO3 · Sprint Review Protocol for Sprint 1 (till Tuesday 23:59 in T0 + 2) · due 23:59 · Moodle · Deadline")
        #expect(try presentation("900011", in: all).hoverHelp == "REQEN · F2 · opens 16:10, closes 17:47 · Moodle · Deadline")
        #expect(try presentation("900015", in: all).hoverHelp
                == "RW · Mitarbeit Lektion 5 · opens 12 Oct 09:30, closes 23:50 · Moodle · Deadline")
        #expect(try presentation("900028", in: all).hoverHelp
                == "📚 Literaturrecherche-Schulung (Adventsedition mit Tee und Keksen!) 🍪🎄✨ · registration ends 23:55 · Moodle · Deadline")
        let opening = MomentPresentation(try #require(item("900031", in: items(.feedChanged))), sourceName: "Moodle", zone: F.zone)
        #expect(opening.hoverHelp == "REQEN · Quiz 3 · opens 09:00 · Moodle · Opening")
        let notice = MomentPresentation(try #require(item("900040", in: items(.feedNotice))), sourceName: "Moodle", zone: F.zone)
        #expect(notice.hoverHelp == "SWQM · Guest lecture: Testing in practice · at 10:00 · Moodle · Item")
        #expect(try presentation("900004", in: items(done: ["900004"])).hoverHelp
                == "INNO2 · Retake Submission (till 2026-10-12) · due 23:59 · Moodle · Deadline · Done")
    }

    @Test("VoiceOver: every §37.1 example, exactly")
    func voiceOver() throws {
        let all = items()
        #expect(try presentation("900005", in: all).accessibilityLabel
                == "INNO3, Sprint Review Protocol for Sprint 1 (till Tuesday 23:59 in T0 + 2), due Tuesday 13 October at 23:59, deadline, Moodle")
        #expect(try presentation("900005", in: items(done: ["900005"])).accessibilityLabel.hasSuffix(", deadline, Moodle, done"))
        #expect(try presentation("900011", in: all).accessibilityLabel
                == "REQEN, F2, opens Thursday 22 October at 16:10, closes at 17:47, deadline, Moodle")
        // An unpaired opening (§37.1: `…, opens Monday 12 October at 09:30, opening, Moodle`).
        var unpaired = try #require(item("900002", in: all))
        unpaired.externalID = "lonely"
        #expect(MomentPresentation(unpaired, sourceName: "Moodle", zone: F.zone).accessibilityLabel
                == "RW, Mitarbeit Lektion 5, opens Monday 12 October at 09:30, opening, Moodle")
        // A notice (`…, at Monday 12 October 10:00, item, Moodle`).
        var notice = try #require(item("900040", in: items(.feedNotice)))
        notice.start = F.date("2026-10-12 10:00"); notice.end = notice.start
        #expect(MomentPresentation(notice, sourceName: "Moodle", zone: F.zone).accessibilityLabel
                == "SWQM, Guest lecture: Testing in practice, at Monday 12 October 10:00, item, Moodle")
        // No code: the title first.
        #expect(try presentation("900028", in: all).accessibilityLabel
                == "📚 Literaturrecherche-Schulung (Adventsedition mit Tee und Keksen!) 🍪🎄✨, registration ends Tuesday 8 December at 23:55, deadline, Moodle")
    }

    @Test("Inspector values for §43 item 15's five items, exactly; In timetable from a store holding travel's timetable")
    func inspector() throws {
        let container = try slice2MemoryContainer()
        let context = container.mainContext
        TravelDataset.seed(context: context, now: TravelFixtures.m(0, "06:00"), m: TravelFixtures.m(0, "00:00"),
                           zone: F.zone, template: ReviewTravelTemplate.text)
        let codes = try context.fetch(FetchDescriptor<Event>()).filter { $0.sourceID == TravelDataset.sourceID }
            .compactMap(\.courseCode)
        #expect(Set(codes).isSuperset(of: ["SWQM-ILV", "SWEN3-LAB", "SWEN3-ILV", "INNO3-EL", "REQEN-EXAM", "SWRM-ILV"]))

        let all = items()
        func values(_ n: String, _ list: [MomentItem] = items()) throws -> MomentInspectorValues {
            let it = try #require(item(n, in: list))
            return MomentInspectorValues(it, opening: MoodlePairing.pairs(list).opening(of: it), sourceName: "Moodle",
                                         timetableCodes: codes, zone: F.zone)
        }
        typealias Row = MomentInspectorValues.Row
        let v8 = try values("900008")
        #expect(v8.title == "Submission - Sprint 3: Queuing" && v8.readOnlyLine == "Read-only — from Moodle")
        #expect(v8.moment == Row(label: "Due", value: "Tue 20 Oct 2026, 12:00"))
        #expect(v8.course == Row(label: "Course", value: "SWEN3", secondLine: "BIF-VZ-5-WS2026-SWEN3-EN"))
        #expect(v8.inTimetable == Row(label: "In timetable", value: "SWEN3-ILV, SWEN3-LAB"))
        #expect(v8.inMoodle == Row(label: "In Moodle", value: "Submission - Sprint 3: Queuing is due"))
        #expect(v8.opens == nil && v8.noticeLine == nil && v8.hasStatus && v8.origin == "Imported")

        let v11 = try values("900011")
        #expect(v11.moment == Row(label: "Closes", value: "Thu 22 Oct 2026, 17:47"))
        #expect(v11.opens == Row(label: "Opens", value: "Thu 22 Oct 2026, 16:10"))
        #expect(v11.inTimetable == Row(label: "In timetable", value: "REQEN-EXAM"))
        #expect(v11.inMoodle == Row(label: "In Moodle", value: "F2 closes"))

        let v13 = try values("900013")
        #expect(v13.course == Row(label: "Category", value: "FK CS&AM - Study Trips & International Initiatives"))
        #expect(v13.inMoodle?.value.hasSuffix(" endet") == true && v13.inTimetable == nil)

        let v28 = try values("900028")
        #expect(v28.moment == Row(label: "Registration ends", value: "Tue 8 Dec 2026, 23:55"))
        #expect(v28.course == Row(label: "Category", value: "Bibliothek"))
        #expect(v28.inMoodle?.value == "Anmeldeende: 📚 Literaturrecherche-Schulung (Adventsedition mit Tee und Keksen!) 🍪🎄✨")
        #expect(v28.title == "📚 Literaturrecherche-Schulung (Adventsedition mit Tee und Keksen!) 🍪🎄✨")

        let v40 = try values("900040", items(.feedNotice))
        #expect(v40.moment == Row(label: "At", value: "Wed 21 Oct 2026, 10:00"))
        #expect(v40.noticeLine == "Kadence couldn't tell whether this is a deadline, so it won't remind you of it.")
        #expect(v40.inMoodle == nil && !v40.hasStatus && v40.glyph == "info.circle.fill")
        #expect(v40.inTimetable == Row(label: "In timetable", value: "SWQM-ILV"))

        let v4 = try values("900004")
        #expect(v4.description?.hasPrefix("Fixture description 4.") == true)
        #expect(v4.inTimetable == nil)  // INNO2 has no lecture

        // §38's moved line.
        var moved = try #require(item("900008", in: all))
        moved.isDone = true; moved.markedDoneDueAt = moved.start; moved.start = F.date("2026-10-22 12:00"); moved.end = moved.start
        let vm = MomentInspectorValues(moved, opening: nil, sourceName: "Moodle", timetableCodes: [], zone: F.zone)
        #expect(vm.movedLine == "Due time changed after you marked it done (was Tue 20 Oct, 12:00).")
        moved.markedDoneDueAt = moved.start
        #expect(MomentInspectorValues(moved, opening: nil, sourceName: "Moodle", timetableCodes: [], zone: F.zone).movedLine == nil)
    }

    @Test("§35.5: stems, case-insensitive, distinct and sorted; no match → nothing")
    func mapping() {
        #expect(MoodleCourseMapping.stem("SWQM-ILV") == "SWQM" && MoodleCourseMapping.stem("REQEN-EXAM") == "REQEN")
        #expect(MoodleCourseMapping.stem("A-B-C") == "A-B" && MoodleCourseMapping.stem("SWQM") == "SWQM")
        #expect(MoodleCourseMapping.matches(courseCode: "swen3", timetableCodes: ["SWEN3-LAB", "SWEN3-ILV", "SWEN3-LAB", "SWEN2-ILV"])
                == ["SWEN3-ILV", "SWEN3-LAB"])
        #expect(MoodleCourseMapping.matches(courseCode: "GLD", timetableCodes: ["SWEN3-LAB"]).isEmpty)
        #expect(MoodleCourseMapping.matches(courseCode: nil, timetableCodes: ["SWEN3-LAB"]).isEmpty)
    }

    @Test("Menu bar: Tue 13 Oct 20:00 → Due NEXT 900005; Tue 3 Nov 20:00 → 900016 + DUE TODAY 900015, 900017; a timed item left → all three in DUE TODAY")
    func menuBar() throws {
        let only = items(done: ["900004"])
        let cal = F.calendar
        func n(_ list: [MomentItem]) -> [String] { list.map { String($0.externalID.prefix(6)) } }
        let tue = DueSelection.select(only, now: F.date("2026-10-13 20:00"), calendar: cal, hasTimedNext: false)
        #expect(tue.next.map { String($0.externalID.prefix(6)) } == "900005" && tue.dueToday.isEmpty)
        let nov = DueSelection.select(only, now: F.date("2026-11-03 20:00"), calendar: cal, hasTimedNext: false)
        #expect(nov.next.map { String($0.externalID.prefix(6)) } == "900016")
        #expect(n(nov.dueToday) == ["900015", "900017"])
        let timed = DueSelection.select(only, now: F.date("2026-11-03 20:00"), calendar: cal, hasTimedNext: true)
        #expect(timed.next == nil && n(timed.dueToday) == ["900016", "900015", "900017"])
        // Done and passed excluded.
        var marked = only
        if let i = marked.firstIndex(where: { $0.externalID.hasPrefix("900016") }) { marked[i].isDone = true }
        #expect(n(DueSelection.dueToday(marked, now: F.date("2026-11-03 20:00"), calendar: cal)) == ["900015", "900017"])
        #expect(n(DueSelection.dueToday(only, now: F.date("2026-11-03 23:55"), calendar: cal)) == ["900017"])
        #expect(DueSelection.dueToday(only, now: F.date("2026-10-13 23:59"), calendar: cal).isEmpty)
        // Done 900004 at Mon 12 Oct 20:00: nothing.
        #expect(DueSelection.dueToday(only, now: F.date("2026-10-12 20:00"), calendar: cal).isEmpty)
        // Never an opening or a notice: Mon 12 Oct 08:00 has two openings at 09:30.
        #expect(n(DueSelection.dueToday(items(), now: F.date("2026-10-12 08:00"), calendar: cal)) == ["900004"])
        let notice = items(.feedNotice)
        #expect(DueSelection.dueToday(notice, now: F.date("2026-10-21 08:00"), calendar: cal).isEmpty)
    }

    @Test("isMoment: an imported Moodle event with start == end; a span and a CIS lecture are not")
    func isMoment() {
        let t = F.date("2026-10-20 12:00")
        let moment = Event(title: "x", start: t, end: t, origin: .imported, sourceID: "moodle")
        moment.importKind = .deadline
        let span = Event(title: "y", start: t, end: t + 3600, origin: .imported)
        span.importKind = .notice
        let lecture = Event(title: "z", start: t, end: t, origin: .imported, sourceID: "timetable")
        let manual = Event(title: "w", start: t, end: t)
        manual.importKind = .deadline
        #expect(moment.isMoment && !span.isMoment && !lecture.isMoment && !manual.isMoment)
        #expect(MomentItem(moment) != nil && MomentItem(lecture) == nil)
    }
}
