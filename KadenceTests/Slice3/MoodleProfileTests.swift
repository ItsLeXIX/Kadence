//
//  MoodleProfileTests.swift
//  KadenceTests
//
//  PHASE3-SLICE3-PLAN.md task 3 — components.md §35 (incl. §35.7's table),
//  §34.7; `moodle-mocks.md` M1. The fixture and every case derived from it in
//  memory; Europe/Vienna.
//

import Testing
import Foundation
@testable import Kadence

private typealias F = MoodleFixture

/// §35.7, row for row: UID number, local time, kind, wording, course code or
/// `category …`, displayed title.
private let table: [(String, String, ImportKind, MomentWording?, String, String)] = [
    ("900001", "Sun 11 Oct 23:59 CEST", .deadline, .closes, "SWQM", "Voting: the 3 best \"Elevator's Speech\" videos"),
    ("900002", "Mon 12 Oct 09:30 CEST", .opening, .opens, "RW", "Mitarbeit Lektion 5"),
    ("900003", "Mon 12 Oct 09:30 CEST", .opening, .opens, "RW", "Lessons Learned Lektion 5"),
    ("900004", "Mon 12 Oct 23:59 CEST", .deadline, .due, "INNO2", "Retake Submission (till 2026-10-12)"),
    ("900005", "Tue 13 Oct 23:59 CEST", .deadline, .due, "INNO3", "Sprint Review Protocol for Sprint 1 (till Tuesday 23:59 in T0 + 2)"),
    ("900006", "Wed 14 Oct 12:30 CEST", .deadline, .closes, "RW", "Mitarbeit Lektion 4"),
    ("900007", "Wed 14 Oct 12:30 CEST", .deadline, .closes, "RW", "Lessons Learned Lektion 4"),
    ("900008", "Tue 20 Oct 12:00 CEST", .deadline, .due, "SWEN3", "Submission - Sprint 3: Queuing"),
    ("900009", "Thu 22 Oct 16:10 CEST", .opening, .opens, "REQEN", "F2"),
    ("900010", "Thu 22 Oct 16:10 CEST", .opening, .opens, "REQEN", "F3"),
    ("900011", "Thu 22 Oct 17:47 CEST", .deadline, .closes, "REQEN", "F2"),
    ("900012", "Thu 22 Oct 17:48 CEST", .deadline, .closes, "REQEN", "F3"),
    ("900013", "Sun 1 Nov 23:59 CET", .deadline, .closes, "category FK CS&AM - Study Trips & International Initiatives",
     "VERBINDLICHE Anmeldung für die Studienreise nach Manila | BINDING registration for study trip to Manila"),
    ("900014", "Mon 2 Nov 14:20 CET", .deadline, .closes, "UF", "Test Management"),
    ("900015", "Tue 3 Nov 23:50 CET", .deadline, .closes, "RW", "Mitarbeit Lektion 5"),
    ("900016", "Tue 3 Nov 23:50 CET", .deadline, .closes, "RW", "Lessons Learned Lektion 5"),
    ("900017", "Tue 3 Nov 23:59 CET", .deadline, .due, "INNO3", "Sprint Review Protocol for Sprint 2 (till Tuesday 23:59 in T0 + 4)"),
    ("900018", "Sun 8 Nov 23:59 CET", .deadline, .due, "SWEN2", "Panel Exam (2026-11-08)"),
    ("900019", "Mon 9 Nov 14:20 CET", .deadline, .closes, "UF", "Test Strategie"),
    ("900020", "Mon 16 Nov 14:20 CET", .deadline, .closes, "UF", "Test Unternehmenskultur"),
    ("900021", "Tue 17 Nov 23:59 CET", .deadline, .due, "INNO3", "Sprint Review Protocol for Sprint 3 (till Tuesday 23:59 in T0 + 6)"),
    ("900022", "Mon 23 Nov 14:20 CET", .deadline, .closes, "UF", "Test Organisation"),
    ("900023", "Mon 30 Nov 14:20 CET", .deadline, .closes, "UF", "Test Personalmanagement"),
    ("900024", "Mon 30 Nov 23:59 CET", .deadline, .due, "GLD", "🎮Assignment: Level Design"),
    ("900025", "Tue 1 Dec 23:59 CET", .deadline, .due, "INNO3", "Sprint Review Protocol for Sprint 4 (till Tuesday 23:59 in T0 + 8)"),
    ("900026", "Fri 4 Dec 23:59 CET", .deadline, .due, "SWRM", "Submission: Proposal draft"),
    ("900027", "Mon 7 Dec 14:20 CET", .deadline, .closes, "UF", "Test Motivation und Führung"),
    ("900028", "Tue 8 Dec 23:55 CET", .deadline, .registrationEnds, "category Bibliothek",
     "📚 Literaturrecherche-Schulung (Adventsedition mit Tee und Keksen!) 🍪🎄✨"),
    ("900029", "Mon 14 Dec 14:20 CET", .deadline, .closes, "UF", "Test Controlling"),
]

struct MoodleProfileTests {

    @Test("The fixture parses to 29 items equal to §35.7's table row for row (9 due, 15 closes, 1 registrationEnds, 4 opens)")
    func fixtureTable() throws {
        let feed = try #require(F.feed())
        #expect(feed.items.count == 29 && feed.veventCount == 29 && feed.duplicates == 0 && feed.problems.isEmpty)
        for (item, row) in zip(feed.items, table) {
            let (number, local, kind, wording, course, title) = row
            #expect(F.number(item) == number)
            #expect(F.local(item.start) == local, "\(number)")
            #expect(item.start == item.end && !item.isAllDay && item.isMoment, "\(number)")
            #expect(item.kind == kind && item.wording == wording, "\(number)")
            if course.hasPrefix("category ") {
                #expect(item.courseCode == nil && item.courseCategory == String(course.dropFirst(9)), "\(number)")
            } else {
                #expect(item.courseCode == course, "\(number)")
            }
            #expect(item.title == title, "\(number)")
        }
        #expect(feed.items.filter { $0.wording == .due }.count == 9)
        #expect(feed.items.filter { $0.wording == .closes }.count == 15)
        #expect(feed.items.filter { $0.wording == .registrationEnds }.count == 1)
        #expect(feed.items.filter { $0.wording == .opens }.count == 4)
        #expect(feed.deadlines == 25 && feed.openings == 4 && feed.notices == 0)
    }

    @Test("900005: the fold after `2) ` kept as one space; 900013's category decoded; 900028 keeps every emoji; raw titles")
    func details() throws {
        let feed = try #require(F.feed())
        func item(_ n: String) throws -> MoodleItem { try #require(feed.items.first { F.number($0) == n }) }
        // The real feed folds right after `2) `: the space survives unfolding,
        // and the German wording is read (`ist fällig.`).
        #expect(try item("900005").upstreamTitle == "Sprint Review Protocol for Sprint 1 (till Tuesday 23:59 in T0 + 2) ist fällig.")
        #expect(try item("900013").courseCategory == "FK CS&AM - Study Trips & International Initiatives")
        #expect(try item("900013").upstreamTitle.hasSuffix(" endet"))
        #expect(try item("900028").upstreamTitle
                == "Anmeldeende: 📚 Literaturrecherche-Schulung (Adventsedition mit Tee und Keksen!) 🍪🎄✨")
        #expect(try item("900024").upstreamTitle == "🎮Assignment: Level Design is due")
        #expect(try item("900011").upstreamTitle == "F2 closes")
        // §35.3: descriptions keep their breaks; empty → nil.
        #expect(try item("900001").description == nil)
        let three = try #require(try item("900003").description)
        #expect(three.hasPrefix("Fixture description 3.\nPart one, part two.\nRedacted course text for the fix"))
        #expect(!three.contains("\t") && !three.contains("\r"))
        let four = try #require(try item("900004").description)
        #expect(four.split(separator: "\n").count > 6)
        #expect(four.contains("\t* item one"))
    }

    @Test("The lone-TAB lines produce no property and no stray character; feedLF gives byte-equal items; a BOM is skipped")
    func lines() throws {
        let lines = MoodleProfile.unfold(F.data)
        #expect(!lines.contains { $0.bytes.isEmpty || $0.bytes == [0x09] || $0.bytes.first == 0x09 || $0.bytes.first == 0x20 })
        #expect(!lines.contains { $0.bytes.contains(0x0D) || $0.bytes.contains(0x0A) })
        let ok = try #require(F.feed())
        #expect(!ok.items.contains { $0.upstreamTitle.contains("\t") || ($0.description ?? "").contains("\t\n") })
        let lf = try #require(F.feed(.feedLF))
        #expect(F.body(.feedLF).count < F.data.count && !String(decoding: F.body(.feedLF), as: UTF8.self).contains("\r"))
        // Equal items except the physical line numbers, which LF without the
        // lone-TAB lines shifts.
        #expect(lf.items.map { var i = $0; i.line = 0; return i } == ok.items.map { var i = $0; i.line = 0; return i })
        var bom = Data([0xEF, 0xBB, 0xBF]); bom.append(F.data)
        guard case .calendar(let withBOM) = MoodleProfile.read(bom, zone: F.zone) else {
            Issue.record("a BOM made it not a calendar"); return
        }
        #expect(withBOM.items == ok.items)
        // Physical line numbers are 1-based and those of BEGIN:VEVENT.
        #expect(ok.items.first?.line == 5)
    }

    @Test("§35.4 row by row, the space before a suffix, an empty remainder, prefix before suffix")
    func kinds() {
        let rows: [(String, ImportKind, MomentWording?, String)] = [
            ("Anmeldeende: 📚 Schulung", .deadline, .registrationEnds, "📚 Schulung"),
            ("Assignment 1 is due", .deadline, .due, "Assignment 1"),
            ("Abgabe 2 ist fällig.", .deadline, .due, "Abgabe 2"),
            ("Abgabe 3 ist fällig", .deadline, .due, "Abgabe 3"),
            ("Quiz 1 closes", .deadline, .closes, "Quiz 1"),
            ("Test Controlling endet", .deadline, .closes, "Test Controlling"),
            ("Quiz 1 opens", .opening, .opens, "Quiz 1"),
            ("Mitarbeit Lektion 5 beginnt", .opening, .opens, "Mitarbeit Lektion 5"),
            ("Guest lecture: Testing in practice", .notice, nil, "Guest lecture: Testing in practice"),
            ("Fooopens", .notice, nil, "Fooopens"),
            ("is due", .notice, nil, "is due"),
            ("Anmeldeende: ", .notice, nil, "Anmeldeende: "),
            ("Quiz IS DUE", .notice, nil, "Quiz IS DUE"),
            ("Anmeldeende: Quiz closes", .deadline, .registrationEnds, "Quiz closes"),
        ]
        for (upstream, kind, wording, title) in rows {
            let r = MoodleProfile.kind(of: upstream)
            #expect(r.kind == kind && r.wording == wording && r.title == title, "\(upstream)")
        }
        // `is due` alone: §35.3 collapses `SUMMARY:is due` to `is due`.
        #expect(MoodleProfile.upstreamTitle(summary: "  is   due ") == "is due")
        #expect(MoodleProfile.upstreamTitle(summary: "") == "(No title)")
        #expect(MoodleProfile.upstreamTitle(summary: nil) == "(No title)")
    }

    @Test("§35.3 text: iCalendar unescaping first, then HTML entities; other escapes kept as written")
    func text() {
        #expect(MoodleProfile.text("FK CS&amp\\;AM - Study Trips &amp\\; International Initiatives")
                == "FK CS&AM - Study Trips & International Initiatives")
        #expect(MoodleProfile.unescape("a\\nb\\Nc\\,d\\;e\\\\f\\xg") == "a\nb\nc,d;e\\f\\xg")
        #expect(MoodleProfile.decodeEntities("&lt;b&gt; &quot;x&quot; &#39;y&#39; &apos;z&apos; &#228; &#xE4; &#X1F393;")
                == "<b> \"x\" 'y' 'z' ä ä 🎓")
        // One pass: `&amp;lt;` → `&lt;`; unknown and unterminated entities stay.
        #expect(MoodleProfile.decodeEntities("&amp;lt; &nbsp; & a &amp") == "&lt; &nbsp; & a &amp")
        // Line breaks kept, each line's trailing whitespace trimmed.
        #expect(MoodleProfile.description("line one  \nline two\t\n") == "line one\nline two\n")
        #expect(MoodleProfile.description("   ") == nil && MoodleProfile.description("") == nil)
    }

    @Test("Course code: the 10 codes and 2 categories; `/174462` stripped for the shortname, kept in courseCategory")
    func courses() throws {
        let feed = try #require(F.feed())
        let codes = Set(feed.items.compactMap(\.courseCode))
        #expect(codes == ["SWQM", "RW", "INNO2", "INNO3", "SWEN3", "REQEN", "UF", "SWEN2", "GLD", "SWRM"])
        let categories = Set(feed.items.filter { $0.courseCode == nil }.compactMap(\.courseCategory))
        #expect(categories == ["Bibliothek", "FK CS&AM - Study Trips & International Initiatives"])
        let swen3 = try #require(feed.items.first { F.number($0) == "900008" })
        #expect(swen3.courseCategory == "BIF-VZ-5-WS2026-SWEN3-EN/174462")
        #expect(MoodleProfile.shortname(swen3.courseCategory ?? "") == "BIF-VZ-5-WS2026-SWEN3-EN")
        #expect(swen3.term == "WS2026")
        let inno2 = try #require(feed.items.first { F.number($0) == "900004" })
        #expect(inno2.term == "SS2026" && inno2.courseCode == "INNO2")
        // No `/id` at all: still a course (900002, RW).
        #expect(MoodleProfile.course("BIF-VZ-5-WS2026-RW-DE")?.code == "RW")
        #expect(MoodleProfile.course("Bibliothek") == nil)
        #expect(MoodleProfile.course("A-WS26-X-EN") == nil)
        #expect(MoodleProfile.course("A-WS2026-X-en") == nil)
        #expect(MoodleProfile.courseCategory(nil) == nil && MoodleProfile.courseCategory("") == nil)
        #expect(MoodleProfile.courseCategory("A,B") == "A")
    }

    @Test("feedDuplicateUID, feedInvalidUTF8, feedBroken: the problems and sentences, exactly")
    func problems() throws {
        let dup = try #require(F.feed(.feedDuplicateUID))
        #expect(dup.veventCount == 30 && dup.items.count == 29 && dup.duplicates == 1)
        #expect(dup.problems.map(\.sentence)
                == ["Submission - Sprint 3: Queuing is due is listed twice with different details; one copy was used."])
        // The copy whose item hash sorts lower is kept.
        let copies = MoodleProfile.unfoldCopies(of: "900008", in: F.body(.feedDuplicateUID))
        let kept = try #require(dup.items.first { F.number($0) == "900008" })
        #expect(kept.hash == copies.map(\.hash).min())

        let bad = try #require(F.feed(.feedInvalidUTF8))
        #expect(bad.items.count == 29)
        let gld = try #require(bad.items.first { F.number($0) == "900024" })
        #expect(gld.upstreamTitle == "🎮\u{FFFD}Assignment: Level Design is due")
        #expect(bad.problems.count == 1)
        #expect(bad.problems.first?.sentence == "🎮\u{FFFD}Assignment: Level Design is due contains characters Kadence couldn't read.")
        #expect(bad.problems.first?.technical?.hasSuffix(": invalid UTF-8") == true)

        let broken = try #require(F.feed(.feedBroken))
        #expect(broken.veventCount == 33 && broken.items.count == 29)
        #expect(broken.problems.map(\.sentence) == [
            "Quiz 90 closes has no identifier, so it was skipped.",
            "Quiz 91 closes has no readable start time, so it was skipped.",
            "Quiz 92 closes ends before it starts, so it was skipped.",
            "1 event couldn't be read.",
        ])
        #expect(broken.problems.map { $0.technical?.split(separator: ":").last.map(String.init) ?? "" }
                == [" no UID", " DTSTART", " DTEND before DTSTART", " VEVENT not closed"])
    }

    @Test("feedNotice: 900040 a notice moment; 900041 a timed notice span")
    func notices() throws {
        let feed = try #require(F.feed(.feedNotice))
        let moment = try #require(feed.items.first { F.number($0) == "900040" })
        #expect(moment.kind == .notice && moment.wording == nil && moment.isMoment)
        #expect(moment.title == "Guest lecture: Testing in practice" && moment.courseCode == "SWQM")
        #expect(F.local(moment.start) == "Wed 21 Oct 10:00 CEST")
        let span = try #require(feed.items.first { F.number($0) == "900041" })
        #expect(span.kind == .notice && !span.isMoment && !span.isAllDay)
        #expect(span.end.timeIntervalSince(span.start) == 3600)
        #expect(feed.notices == 2)
    }

    @Test("Hashes: feedStampOnly → equal feed hash; any §34.7 field changed → that item's hash changes; the profile tag changes every hash")
    func hashes() throws {
        let ok = try #require(F.feed()), stamp = try #require(F.feed(.feedStampOnly))
        let window = F.date("2026-10-16 00:00")
        #expect(MoodleHash.feed(ok.items, from: window) == MoodleHash.feed(stamp.items, from: window))
        #expect(ok.items.map(\.hash) == stamp.items.map(\.hash))
        #expect(MoodleHash.feed(ok.items, from: window) != MoodleHash.feed(ok.items, from: F.date("2026-10-30 00:00")))

        let base = try #require(ok.items.first { F.number($0) == "900008" })
        var variants: [MoodleItem] = []
        var v = base; v.externalID = "x"; variants.append(v)
        v = base; v.upstreamTitle += "!"; variants.append(v)
        v = base; v.start = v.start.addingTimeInterval(-60); variants.append(v)
        v = base; v.end = v.end.addingTimeInterval(60); variants.append(v)
        v = base; v.isAllDay = true; variants.append(v)
        v = base; v.courseCategory = "BIF-VZ-5-WS2026-SWEN3-EN"; variants.append(v)
        v = base; v.description = "Changed."; variants.append(v)
        for variant in variants { #expect(variant.hash != base.hash) }
        // Derived fields and LAST-MODIFIED are not hashed.
        v = base; v.title = "x"; v.kind = .notice; v.wording = nil; v.courseCode = nil; v.lastModified = .now; v.line = 1
        #expect(v.hash == base.hash)

        let tagged = ok.items.map {
            MoodleHash.item(externalID: $0.externalID, upstreamTitle: $0.upstreamTitle, start: $0.start, end: $0.end,
                            isAllDay: $0.isAllDay, courseCategory: $0.courseCategory, description: $0.description,
                            profileTag: "moodle-2")
        }
        #expect(zip(tagged, ok.items.map(\.hash)).allSatisfy { $0 != $1 })
        #expect(MoodleHash.profileTag == "moodle-1")
    }

    @Test("M1 bodies: the case text reproduces the fixture; feedEmpty has no VEVENT; feedAged lacks 900001–900007; feedHuge is over 20 MB")
    func bodies() throws {
        #expect(MoodleCalendarText(F.text).text == F.text)
        #expect(F.body(.feedOK) == F.data)
        let empty = try #require(F.feed(.feedEmpty))
        #expect(empty.veventCount == 0 && empty.items.isEmpty)
        #expect(String(decoding: F.body(.feedEmpty), as: UTF8.self)
                == "BEGIN:VCALENDAR\r\nMETHOD:PUBLISH\r\nPRODID:-//Moodle Pty Ltd//NONSGML Moodle Version 2024100712.01//EN\r\nVERSION:2.0\r\nEND:VCALENDAR\r\n")
        let aged = try #require(F.feed(.feedAged))
        #expect(aged.items.count == 22 && aged.items.first.map(F.number) == "900008")
        let changed = try #require(F.feed(.feedChanged))
        #expect(changed.veventCount == 28)
        #expect(F.body(.feedHuge).count > 20 * 1_048_576)
        #expect(MoodleProfile.read(Data("<!DOCTYPE html><title>Moodle</title>".utf8), zone: F.zone) == .notACalendar)
    }
}

extension MoodleProfile {
    /// Test helper: every copy of one UID as read, before §35.2's dedupe.
    static func unfoldCopies(of number: String, in data: Data) -> [MoodleItem] {
        let text = String(decoding: data, as: UTF8.self)
        let cal = MoodleCalendarText(text)
        return cal.events.filter { $0.uid == number }.compactMap { event in
            var single = cal
            single.events = [event]
            guard case .calendar(let feed) = read(Data(single.text.utf8), zone: MoodleFixture.zone) else { return nil }
            return feed.items.first
        }
    }
}
