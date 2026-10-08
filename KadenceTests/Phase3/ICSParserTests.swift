//
//  ICSParserTests.swift
//  KadenceTests
//
//  PHASE3-PLAN.md task 3: the ICS parser on the real export and the parser
//  fixtures (components.md §20.3, §20.4, §20.7, §22.1).
//

import Testing
import Foundation
import CryptoKit
@testable import Kadence

private let vienna = TimeZone(identifier: "Europe/Vienna")!
private let newYork = TimeZone(identifier: "America/New_York")!

private func utc(_ text: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
    return f.date(from: text)!
}

private func calendar(_ name: String, zone: TimeZone = vienna) throws -> ParsedCalendar {
    guard case .calendar(let parsed) = ICSParser.parse(try Fixture.data(name), currentZone: zone) else {
        Issue.record("\(name) is not a calendar"); return ParsedCalendar(events: [], problems: [])
    }
    return parsed
}

struct ICSParserTests {

    // MARK: The real export

    @Test("The bundled real export is byte for byte the repo's fixtures/ file")
    func realExportIsBundledByteForByte() throws {
        let bundled = try Fixture.data("cis-2026WS-redacted.ics")
        let repo = try Data(contentsOf: Fixture.repoRoot.appendingPathComponent("fixtures/cis-2026WS-redacted.ics"))
        #expect(SHA256.hash(data: bundled) == SHA256.hash(data: repo))
        #expect(bundled.count == repo.count)
    }

    @Test("The real export: 13 VEVENTs, 0 problems, VERSION:1.0 accepted")
    func realExportParses() throws {
        let parsed = try calendar("cis-2026WS-redacted.ics")
        #expect(parsed.events.count == 13)
        #expect(parsed.allProblems.isEmpty)
        let summaries = parsed.events.map { $0.summary ?? "" }
        #expect(summaries.first == "SWQM-ILV  HS_A3.15 - BIF-5C ")  // trailing space kept
    }

    // components.md §20.2/§22.1 and PHASE3-PLAN.md task 3 say "186 characters";
    // the fixture's UID value is 185 (189 with `UID:`), counted byte for byte.
    // GAPS G-070 asks the design agent to correct the number.
    @Test("INNO3-EL's 22-name description and its long UID (185 characters; spec says 186, G-070) read intact")
    func longLecturerList() throws {
        let parsed = try calendar("cis-2026WS-redacted.ics")
        let inno = try #require(parsed.events.first { $0.summary?.hasPrefix("INNO3-EL") == true })
        let uid = try #require(inno.uid)
        #expect(uid.count == 185)
        #expect(uid.contains(" / ") && uid.hasSuffix("INNO3-EL20261021T08000020261021T093000"))
        let names = (10...31).map { "L\($0)" }.joined(separator: " / ")
        #expect(inno.description == "INNO3-EL\n\(names)\nBIF-5C \nWEBINAR01")
    }

    @Test("DST: SWQM-ILV 14 Sep 14:30 → 12:30Z; INNO3-EL 21 Oct 08:00 → 06:00Z; UF-ILV 2 Nov 14:30 → 13:30Z")
    func dstRows() throws {
        let parsed = try calendar("cis-2026WS-redacted.ics")
        func start(_ prefix: String) -> Date? { parsed.events.first { $0.summary?.hasPrefix(prefix) == true }?.start.instant }
        #expect(start("SWQM-ILV") == utc("20260914T123000Z"))
        #expect(start("INNO3-EL") == utc("20261021T060000Z"))
        #expect(start("UF-ILV") == utc("20261102T133000Z"))
    }

    @Test("An LF-only copy parses identically; the zone America/New_York changes no instant")
    func lineEndingsAndZone() throws {
        let data = try Fixture.data("cis-2026WS-redacted.ics")
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\r\n"))
        let lf = text.replacingOccurrences(of: "\r\n", with: "\n")
        let original = try calendar("cis-2026WS-redacted.ics")
        guard case .calendar(let fromLF) = ICSParser.parse(lf, currentZone: vienna) else { Issue.record("LF copy"); return }
        #expect(fromLF == original)
        guard case .calendar(let inNY) = ICSParser.parse(data, currentZone: newYork) else { Issue.record("NY"); return }
        #expect(inNY.events.map(\.start.instant) == original.events.map(\.start.instant))
        #expect(inNY.events.map(\.end.instant) == original.events.map(\.end.instant))
    }

    // MARK: edge-cases.ics

    @Test("edge-cases.ics: every §20.3, §20.4 and §20.7 row; one problem, the unknown zone")
    func edgeCases() throws {
        let parsed = try calendar("edge-cases.ics")
        #expect(parsed.events.count == 13)
        func event(_ uid: String) -> ParsedVEvent? { parsed.events.first { $0.uid == uid } }

        // §20.7: escapes, unfolding (CRLF + space, CRLF + tab), ORGANIZER CN, URL; VALARM ignored.
        let e0 = try #require(event("edge-escaped@kadence.test"))
        #expect(e0.summary == "Planning, review; and notes \\ more")
        #expect(e0.description == "First line\nSecond line, foldedafter a spaceand after a tab")
        #expect(e0.location == "Room 1, Building B")
        #expect(e0.organizer == "Dr. Example")
        #expect(e0.url == "https://example.invalid/course/42")
        #expect(e0.start.form == .zoned("Europe/Vienna"))

        // §20.3 rows.
        let e1 = try #require(event("edge-utc@kadence.test"))
        #expect(e1.start.form == .utc && e1.start.instant == utc("20261015T080000Z"))
        #expect(e1.organizer == "someone@example.invalid")  // no CN: the address after mailto:
        let e2 = try #require(event("edge-floating@kadence.test"))
        #expect(e2.start.form == .floating && e2.start.instant == utc("20261016T070000Z"))  // 09:00 Vienna
        let e3 = try #require(event("edge-windows@kadence.test"))
        #expect(e3.start.form == .zoned("W. Europe Standard Time") && e3.start.instant == utc("20261016T100000Z"))
        let e4 = try #require(event("edge-custom@kadence.test"))
        #expect(e4.start.form == .unknownZone("Custom Zone") && e4.start.instant == utc("20261016T120000Z"))

        // §20.4: DURATION, zero length, a two-day date event.
        let e5 = try #require(event("edge-duration@kadence.test"))
        #expect(e5.end.instant.timeIntervalSince(e5.start.instant) == 5400)
        let e6 = try #require(event("edge-zero@kadence.test"))
        #expect(e6.end.instant == e6.start.instant)
        let e7 = try #require(event("edge-allday@kadence.test"))
        #expect(e7.start.isDate && e7.start.dateString == "20261019" && e7.end.dateString == "20261021")
        #expect(e7.start.instant == utc("20261018T220000Z") && e7.end.instant == utc("20261020T220000Z"))

        // §20.5 inputs (expanded by task 4).
        let series = parsed.events.filter { $0.uid == "edge-series@kadence.test" }
        #expect(series.count == 2)
        #expect(series[0].rrule == "FREQ=WEEKLY;COUNT=3" && series[0].rdates.count == 1)
        #expect(series[1].recurrenceID?.instant == utc("20261022T070000Z"))

        // §20.6 / §20.7: STATUS.
        #expect(event("edge-cancelled@kadence.test")?.status == "CANCELLED")
        #expect(event("edge-coteach-a@kadence.test")?.organizer == "Prof A")

        #expect(parsed.allProblems == [ImportProblem(
            sentence: "1 event used an unknown time zone (Custom Zone) and was read in this Mac's time zone (Europe/Vienna)")])
    }

    @Test("Floating and Custom Zone are read in the injected zone")
    func injectedZone() throws {
        let parsed = try calendar("edge-cases.ics", zone: newYork)
        #expect(parsed.events.first { $0.uid == "edge-floating@kadence.test" }?.start.instant == utc("20261016T130000Z"))
        #expect(parsed.events.first { $0.uid == "edge-custom@kadence.test" }?.start.instant == utc("20261016T180000Z"))
        #expect(parsed.events.first { $0.uid == "edge-utc@kadence.test" }?.start.instant == utc("20261015T080000Z"))
        #expect(parsed.allProblems.first?.sentence.hasSuffix("(America/New_York)") == true)
    }

    // MARK: malformed-partial.ics

    @Test("malformed-partial.ics: 3 unparseable VEVENTs with line numbers, 7 parse")
    func malformedPartial() throws {
        let parsed = try calendar("malformed-partial.ics")
        #expect(parsed.events.count == 7)
        #expect(parsed.allProblems.count == 3)
        #expect(parsed.problems.map(\.line) == [16, 31, 42])
        #expect(parsed.problems.map { $0.technical ?? "" } ==
                ["line 16: UID missing", "line 31: DTEND before DTSTART", "line 42: DTSTART can't be read"])
        // The monthly series is read here; skipping it is task 4's fourth problem.
        #expect(parsed.events.contains { $0.rrule == "FREQ=MONTHLY;BYDAY=2MO" })
    }

    // MARK: Not a calendar

    @Test("html-login.html, truncated.ics and a 1.1 MB object are .notACalendar")
    func notACalendar() throws {
        #expect(ICSParser.parse(try Fixture.data("html-login.html"), currentZone: vienna) == .notACalendar)
        #expect(ICSParser.parse(try Fixture.data("truncated.ics"), currentZone: vienna) == .notACalendar)
        let header = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:big\r\nDTSTART:20261012T090000Z\r\nDESCRIPTION:"
        let big = header + String(repeating: "x", count: 1_150_000) + "\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
        #expect(ICSParser.parse(Data(big.utf8), currentZone: vienna) == .notACalendar)
        // The same shape under the limit is a calendar, BOM and leading whitespace allowed.
        let small = "\u{FEFF}\r\n  " + header + "small\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
        guard case .calendar(let ok) = ICSParser.parse(Data(small.utf8), currentZone: vienna) else {
            Issue.record("a small calendar with a BOM was refused"); return
        }
        #expect(ok.events.count == 1)
    }

    @Test("Helpers: DURATION forms, unescaping, parameters with quoted colons")
    func helpers() {
        #expect(ICSParser.duration("PT1H30M") == 5400)
        #expect(ICSParser.duration("P1W") == 604_800)
        #expect(ICSParser.duration("P1DT2H") == 93_600)
        #expect(ICSParser.duration("-PT15M") == -900)
        #expect(ICSParser.duration("garbage") == nil)
        #expect(ICSParser.unescape("a\\,b\\;c\\nd\\\\e\\Nf") == "a,b;c\nd\\e\nf")
        let split = ICSParser.split("DTSTART;TZID=\"Odd:Zone\";X=1:20261012T090000")
        #expect(split?.name == "DTSTART" && split?.params["TZID"] == "Odd:Zone" && split?.value == "20261012T090000")
    }
}
