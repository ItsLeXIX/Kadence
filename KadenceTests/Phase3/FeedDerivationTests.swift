//
//  FeedDerivationTests.swift
//  KadenceTests
//
//  PHASE3-PLAN.md task 4: identity, the CIS profile, the merge across objects
//  and calendars, recurrence, and the content hashes (components.md §20.2,
//  §20.5, §20.7.1, §20.8.4, §20.10).
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

private let vienna = TimeZone(identifier: "Europe/Vienna")!
/// Test clock 2026-10-08 10:00 Europe/Vienna → today = 2026-10-07T22:00Z.
private let today = CISFeed.utc("20261007T220000Z")
private let lvplan = "/webdav/lvplan.php/calendars/user01/LVPlan-user01/"
private let pruefungen = "/webdav/lvplan.php/calendars/user01/Pruefungen-user01/"

/// The real export cut the way `reportCIS` serves it (caldav-mocks.md):
/// lines 1–20 (header + VTIMEZONE), one VEVENT, `END:VCALENDAR`.
enum CISFeed {
    static func utc(_ text: String) -> Date {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return f.date(from: text)!
    }

    static func lines() throws -> [String] {
        try Fixture.text("cis-2026WS-redacted.ics").components(separatedBy: "\r\n").filter { !$0.isEmpty }
    }

    /// The VEVENT blocks, in file order, each as its lines.
    static func vevents() throws -> [[String]] {
        var blocks: [[String]] = []
        var current: [String]?
        for line in try lines() {
            if line == "BEGIN:VEVENT" { current = [line]; continue }
            if line == "END:VEVENT", var c = current { c.append(line); blocks.append(c); current = nil; continue }
            current?.append(line)
        }
        return blocks
    }

    static func header() throws -> [String] { Array(try lines().prefix(20)) }

    static func object(_ vevents: [[String]], eol: String = "\r\n") throws -> String {
        (try header() + vevents.flatMap { $0 } + ["END:VCALENDAR"]).joined(separator: eol) + eol
    }

    static func parse(_ text: String) -> ParsedCalendar {
        guard case .calendar(let c) = ICSParser.parse(text, currentZone: vienna) else {
            return ParsedCalendar(events: [], problems: [ImportProblem(sentence: "not a calendar")])
        }
        return c
    }

    /// One object per VEVENT (`obj-01.ics` …), in `calendar`.
    static func objects(_ blocks: [[String]]? = nil, calendar: String = lvplan, eol: String = "\r\n",
                        hrefPrefix: String = "obj-") throws -> [FeedObject] {
        try (blocks ?? vevents()).enumerated().map { i, block in
            FeedObject(calendarHref: calendar,
                       objectHref: calendar + hrefPrefix + String(format: "%02d", i + 1) + ".ics",
                       calendar: parse(try object([block], eol: eol)))
        }
    }

    static func derive(_ objects: [FeedObject]) -> DerivedFeed {
        FeedDerivation.derive(objects, today: today, zone: vienna)
    }

    static func feedHash(_ feed: DerivedFeed) -> String {
        FeedHash.of(feed.events.map { EventHash.of($0, zone: vienna) })
    }
}

struct FeedDerivationTests {

    // MARK: Merge and profile

    @Test("reportCIS split per VEVENT: 12 events, mergedCount 1, objectCount 13")
    func mergeCounts() throws {
        let feed = CISFeed.derive(try CISFeed.objects())
        #expect(feed.events.count == 12)
        #expect(feed.mergedCount == 1)
        #expect(feed.objectCount == 13)
        #expect(feed.problems.isEmpty)
    }

    @Test("BPREF-Info 2 Oct has lecturers [L05, L06] whichever object comes first")
    func mergeOrderIndependent() throws {
        var blocks = try CISFeed.vevents()
        let forward = CISFeed.derive(try CISFeed.objects(blocks))
        blocks.swapAt(2, 3)
        let swapped = CISFeed.derive(try CISFeed.objects(blocks))
        let bpref = try #require(forward.events.first { $0.title == "BPREF-Info" })
        #expect(bpref.lecturers == ["L05", "L06"])
        #expect(bpref.isOnline && bpref.group == "if-5" && bpref.location == "WEBINAR02")
        #expect(swapped.events == forward.events)
    }

    @Test("All 12 in content mode; SWQM-ILV's externalID is exactly the content key")
    func contentMode() throws {
        let feed = CISFeed.derive(try CISFeed.objects())
        let swqm = try #require(feed.events.first { $0.title == "SWQM-ILV" })
        #expect(swqm.externalID == "SWQM-ILV HS_A3.15 - BIF-5C|HS_A3.15|20260914T123000Z|20260914T140000Z")
        for event in feed.events {
            let parts = event.externalID.split(separator: "|", omittingEmptySubsequences: false)
            #expect(parts.count == 4)
            #expect(parts[2] == ICSFormat.utcStamp(event.start) && parts[3] == ICSFormat.utcStamp(event.end))
            #expect(!event.externalID.hasPrefix("FH"))  // never the CIS UID
        }
    }

    @Test("Titles are course codes, groups trimmed, INNO3-EL has 22 lecturers and is online, exactly three exams, no description")
    func profile() throws {
        let feed = CISFeed.derive(try CISFeed.objects())
        #expect(feed.events.map(\.title) == ["SWQM-ILV", "KOKU-UE", "BPREF-Info", "SWEN3-LAB", "EPC-ILV",
                                             "INNO3-EL", "SWRM-ILV", "REQEN-EXAM", "UF-ILV", "RW-EXAM",
                                             "CGRMR-ILV", "GLD-EXAM"])
        #expect(feed.events.allSatisfy { $0.courseCode == $0.title })
        #expect(feed.events.first { $0.title == "SWQM-ILV" }?.group == "BIF-5C")
        #expect(feed.events.allSatisfy { $0.group == $0.group?.trimmingCharacters(in: .whitespaces) })
        let inno = try #require(feed.events.first { $0.title == "INNO3-EL" })
        #expect(inno.lecturers == (10...31).map { "L\($0)" })
        #expect(inno.isOnline && inno.location == "WEBINAR01")
        #expect(Set(feed.events.filter { $0.kind == .exam }.map(\.title)) == ["REQEN-EXAM", "RW-EXAM", "GLD-EXAM"])
        #expect(feed.events.allSatisfy { $0.description == nil })
        #expect(feed.events.filter(\.isOnline).map(\.title) == ["BPREF-Info", "INNO3-EL"])
    }

    @Test("The whole file as one object gives the identical result")
    func wholeFile() throws {
        let one = FeedObject(calendarHref: lvplan, objectHref: lvplan + "all.ics",
                             calendar: CISFeed.parse(try Fixture.text("cis-2026WS-redacted.ics")))
        let whole = CISFeed.derive([one])
        let split = CISFeed.derive(try CISFeed.objects())
        #expect(whole.events == split.events)
        #expect(whole.mergedCount == 1 && whole.objectCount == 13)
    }

    // MARK: Hrefs are not identity

    @Test("Renamed hrefs, and BPREF-Info's halves in two calendars, give identical events and feed hash")
    func hrefsNotIdentity() throws {
        let base = CISFeed.derive(try CISFeed.objects())
        let renamed = CISFeed.derive(try CISFeed.objects(hrefPrefix: "x-renamed-"))
        #expect(renamed.events == base.events)
        var moved = try CISFeed.objects()
        moved[3].calendarHref = pruefungen
        moved[3].objectHref = pruefungen + "elsewhere.ics"
        let split = CISFeed.derive(moved)
        #expect(split.events == base.events)
        #expect(CISFeed.feedHash(split) == CISFeed.feedHash(base))
        #expect(CISFeed.feedHash(renamed) == CISFeed.feedHash(base))
    }

    @Test("A duplicate RW-EXAM in a second calendar merges to one event")
    func duplicateAcrossCalendars() throws {
        let blocks = try CISFeed.vevents()
        let rw = try #require(blocks.first { $0.contains("SUMMARY:RW-EXAM  EDV_F2.01 - BIF-5C ") })
        let objects = try CISFeed.objects() + CISFeed.objects([rw], calendar: pruefungen)
        let feed = CISFeed.derive(objects)
        #expect(feed.events.count == 12)
        #expect(feed.events.filter { $0.title == "RW-EXAM" }.count == 1)
        #expect(feed.objectCount == 14)
    }

    // MARK: Hashes

    @Test("Feed hash is invariant under object order and CRLF → LF")
    func feedHashInvariance() throws {
        let base = CISFeed.feedHash(CISFeed.derive(try CISFeed.objects()))
        let reversed = CISFeed.feedHash(CISFeed.derive(try CISFeed.objects().reversed()))
        let lf = CISFeed.feedHash(CISFeed.derive(try CISFeed.objects(eol: "\n")))
        #expect(reversed == base)
        #expect(lf == base)
    }

    @Test("One lecturer added: the feed hash changes and exactly one event hash differs")
    func oneLecturerAdded() throws {
        var blocks = try CISFeed.vevents()
        blocks[0] = blocks[0].map { $0 == "DESCRIPTION:SWQM-ILV\\nL01\\nBIF-5C \\nHS_A3.15"
            ? "DESCRIPTION:SWQM-ILV\\nL01 / L02\\nBIF-5C \\nHS_A3.15" : $0 }
        let before = CISFeed.derive(try CISFeed.objects())
        let after = CISFeed.derive(try CISFeed.objects(blocks))
        #expect(CISFeed.feedHash(before) != CISFeed.feedHash(after))
        let a = before.events.map { EventHash.of($0, zone: vienna) }
        let b = after.events.map { EventHash.of($0, zone: vienna) }
        #expect(zip(a, b).filter { $0 != $1 }.count == 1)
        #expect(after.events[0].lecturers == ["L01", "L02"] && after.events[0].externalID == before.events[0].externalID)
    }

    @Test("EventHash.of(Event) of an event written from an ExternalEvent equals EventHash.of that ExternalEvent")
    @MainActor
    func storedHashMatches() throws {
        let container = try ModelContainer(for: Schema(KadenceSchema.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let feed = CISFeed.derive(try CISFeed.objects())
        let extra = FeedDerivation.derive([FeedObject(calendarHref: "", objectHref: "",
                                                      calendar: CISFeed.parse(try Fixture.text("edge-cases.ics")))],
                                          today: today, zone: vienna)
        for upstream in feed.events + extra.events {
            let event = Event(title: "", start: .now, end: .now)
            event.applyUpstream(upstream)
            context.insert(event)
            try context.save()
            #expect(EventHash.of(event, zone: vienna) == EventHash.of(upstream, zone: vienna), "\(upstream.title)")
        }
    }

    /// Computed once from §20.8.4's definition (P3-T04, STATUS §105) and pinned.
    static let swqmGolden = "907da4033bbcf4527e97f7c2727156684180455c13ab5020d79004e3ed521775"

    @Test("Golden: SWQM-ILV's event hash")
    func golden() throws {
        let feed = CISFeed.derive(try CISFeed.objects())
        let swqm = try #require(feed.events.first { $0.title == "SWQM-ILV" })
        let string = EventHash.string(
            externalID: swqm.externalID, title: swqm.title, start: swqm.start, end: swqm.end,
            isAllDay: false, location: swqm.location, isOnline: false, courseCode: swqm.courseCode,
            group: swqm.group, lecturers: swqm.lecturers, kind: swqm.kind, description: nil, link: nil,
            isCancelled: false, zone: vienna)
        #expect(string == ["SWQM-ILV HS_A3.15 - BIF-5C|HS_A3.15|20260914T123000Z|20260914T140000Z",
                           "SWQM-ILV", "20260914T123000Z", "20260914T140000Z", "0", "HS_A3.15", "0",
                           "SWQM-ILV", "BIF-5C", "L01", "lecture", "", "", "0"].joined(separator: "\u{1F}"))
        #expect(EventHash.of(swqm, zone: vienna) == Self.swqmGolden)
    }

    // MARK: Merge survival

    private func bprefCoTeacher(_ lecturer: String, from block: [String]) -> [String] {
        block.map { line in
            if line.hasPrefix("UID:") { return line.replacingOccurrences(of: "L05", with: lecturer) }
            if line.hasPrefix("DESCRIPTION:") { return line.replacingOccurrences(of: "\\nL05\\n", with: "\\n\(lecturer)\\n") }
            return line
        }
    }

    @Test("Adding or removing a co-teacher keeps the externalID and changes only lecturers; a room change gives a new one")
    func mergeSurvival() throws {
        let blocks = try CISFeed.vevents()
        let base = CISFeed.derive(try CISFeed.objects(blocks))
        let bpref = try #require(base.events.first { $0.title == "BPREF-Info" })
        let three = CISFeed.derive(try CISFeed.objects(blocks + [bprefCoTeacher("L07", from: blocks[2])]))
        let bpref3 = try #require(three.events.first { $0.title == "BPREF-Info" })
        #expect(bpref3.externalID == bpref.externalID)
        #expect(bpref3.lecturers == ["L05", "L06", "L07"])
        var withoutLecturers = bpref3; withoutLecturers.lecturers = bpref.lecturers
        #expect(withoutLecturers == bpref)
        var one = blocks; one.remove(at: 3)
        let single = CISFeed.derive(try CISFeed.objects(one))
        let bpref1 = try #require(single.events.first { $0.title == "BPREF-Info" })
        #expect(bpref1.externalID == bpref.externalID && bpref1.lecturers == ["L05"])
        #expect(single.mergedCount == 0)
        var moved = blocks
        moved[0] = moved[0].map { $0.replacingOccurrences(of: "HS_A3.15", with: "HS_A3.13") }
        let roomChange = CISFeed.derive(try CISFeed.objects(moved))
        #expect(roomChange.events[0].externalID == "SWQM-ILV HS_A3.13 - BIF-5C|HS_A3.13|20260914T123000Z|20260914T140000Z")
        #expect(!roomChange.events.contains { $0.externalID == base.events[0].externalID })
    }

    @Test("Kind fallback: Datenmodellierung and FOO-XYZ are lectures, with no problem")
    func kindFallback() throws {
        func cis(_ code: String) -> [String] {
            ["BEGIN:VEVENT", "UID:FHBIF-5CFH B.2.09L08\(code)20261012T09000020261012T103000",
             "SUMMARY:\(code)  FH B.2.09 - BIF-5C", "DESCRIPTION:\(code)\\nL08\\nBIF-5C\\nFH B.2.09",
             "LOCATION:FH B.2.09", "DTSTART;TZID=Europe/Vienna:20261012T090000",
             "DTEND;TZID=Europe/Vienna:20261012T103000", "END:VEVENT"]
        }
        let feed = CISFeed.derive(try CISFeed.objects([cis("Datenmodellierung"), cis("FOO-XYZ")]))
        #expect(feed.events.map(\.title) == ["Datenmodellierung", "FOO-XYZ"])
        #expect(feed.events.allSatisfy { $0.kind == .lecture && $0.courseCode == $0.title })
        #expect(feed.problems.isEmpty)
    }

    // MARK: Generic feeds

    private func generic(_ name: String) throws -> DerivedFeed {
        FeedDerivation.derive([FeedObject(calendarHref: lvplan, objectHref: lvplan + name,
                                          calendar: CISFeed.parse(try Fixture.text(name)))],
                              today: today, zone: vienna)
    }

    @Test("edge-cases.ics: the stable-UID pair merges, keyed by the content key")
    func genericMerge() throws {
        let feed = try generic("edge-cases.ics")
        let merged = try #require(feed.events.first { $0.title == "Algorithmen" })
        #expect(merged.externalID == "Algorithmen|HS 1|20261023T120000Z|20261023T133000Z")
        #expect(merged.lecturers == ["Prof A", "Prof B"])
        #expect(feed.events.filter { $0.title == "Algorithmen" }.count == 1)
        #expect(feed.mergedCount == 1)
        let cancelled = try #require(feed.events.first { $0.title == "Statistik" })
        #expect(cancelled.isCancelled && cancelled.externalID == "edge-cancelled@kadence.test")
        let escaped = try #require(feed.events.first { $0.externalID == "edge-escaped@kadence.test" })
        #expect(escaped.description == "First line\nSecond line, foldedafter a spaceand after a tab")
        #expect(escaped.link == "https://example.invalid/course/42" && escaped.lecturers == ["Dr. Example"])
        #expect(escaped.location == "Room 1, Building B")
        let allDay = try #require(feed.events.first { $0.title == "Two-day workshop" })
        #expect(allDay.isAllDay && allDay.externalID == "edge-allday@kadence.test")
        #expect(feed.problems.count == 1)  // the unknown zone
    }

    @Test("flat-series.ics → 4 externalIDs UID|start")
    func flatSeries() throws {
        let feed = try generic("flat-series.ics")
        #expect(feed.events.map(\.externalID) == [
            "flat-series@kadence.test|20261013T070000Z", "flat-series@kadence.test|20261020T070000Z",
            "flat-series@kadence.test|20261027T080000Z", "flat-series@kadence.test|20261103T080000Z"])
    }

    @Test("A weekly 09:00 Europe/Vienna series stays at 09:00 local across 25 Oct 2026; RDATE and the orphan override")
    func weeklyAcrossDST() throws {
        let feed = try generic("edge-cases.ics")
        let series = feed.events.filter { $0.externalID.hasPrefix("edge-series@kadence.test|") }
        #expect(series.map(\.externalID) == [
            "edge-series@kadence.test|20261020T070000Z", "edge-series@kadence.test|20261022T070000Z",
            "edge-series@kadence.test|20261027T080000Z", "edge-series@kadence.test|20261029T080000Z",
            "edge-series@kadence.test|20261103T080000Z"])
        var cal = Calendar(identifier: .gregorian); cal.timeZone = vienna
        for event in series where event.title == "Weekly seminar" {
            #expect(cal.component(.hour, from: event.start) == 9 && cal.component(.minute, from: event.start) == 0)
            #expect(event.end.timeIntervalSince(event.start) == 3600)
        }
        let orphan = try #require(series.first { $0.externalID.hasSuffix("20261022T070000Z") })
        #expect(orphan.title == "Weekly seminar (moved)" && cal.component(.hour, from: orphan.start) == 11)
    }

    @Test("An open-ended FREQ=DAILY stops at today + 366 days; EXDATE removes; BYDAY and COUNT")
    func openEndedDaily() throws {
        func feed(_ rrule: String, extra: [String] = []) -> DerivedFeed {
            let text = (["BEGIN:VCALENDAR", "VERSION:2.0", "BEGIN:VEVENT", "UID:daily@kadence.test", "SUMMARY:Daily",
                         "DTSTART;TZID=Europe/Vienna:20261012T090000", "DTEND;TZID=Europe/Vienna:20261012T093000",
                         "RRULE:" + rrule] + extra + ["END:VEVENT", "END:VCALENDAR"]).joined(separator: "\r\n")
            return FeedDerivation.derive([FeedObject(calendarHref: "", objectHref: "", calendar: CISFeed.parse(text))],
                                         today: today, zone: vienna)
        }
        let open = feed("FREQ=DAILY")
        let horizon = FeedDerivation.addDays(366, to: today, zone: vienna)
        #expect(open.events.last.map { $0.start < horizon } == true)
        #expect(open.events.last.map { $0.start.addingTimeInterval(86_400) >= horizon } == true)
        #expect(open.events.count == 362)  // 12 Oct 2026 … 8 Oct 2027
        let ex = feed("FREQ=DAILY;COUNT=3", extra: ["EXDATE;TZID=Europe/Vienna:20261013T090000"])
        #expect(ex.events.map(\.externalID) == ["daily@kadence.test|20261012T070000Z", "daily@kadence.test|20261014T070000Z"])
        let weekdays = feed("FREQ=WEEKLY;BYDAY=TU,TH;COUNT=4")
        #expect(weekdays.events.map { ICSFormat.utcStamp($0.start) } ==
                ["20261013T070000Z", "20261015T070000Z", "20261020T070000Z", "20261022T070000Z"])
        let until = feed("FREQ=WEEKLY;INTERVAL=2;UNTIL=20261109T080000Z")
        #expect(until.events.map { ICSFormat.utcStamp($0.start) } ==
                ["20261012T070000Z", "20261026T080000Z", "20261109T080000Z"])
    }

    @Test("FREQ=MONTHLY skips its series with §20.5's sentence: malformed-partial.ics → 6 imported, 4 problems")
    func unsupportedRule() throws {
        let feed = try generic("malformed-partial.ics")
        #expect(feed.events.count == 6)
        #expect(feed.problems.count == 4)
        #expect(feed.problems.last?.sentence == "1 repeating event uses a rule Kadence can't read yet: Mathe Tutorium")
        #expect(feed.problems.last?.technical == "Object malformed-partial.ics, line 51: RRULE FREQ=MONTHLY;BYDAY=2MO")
        #expect(feed.problems.first?.technical == "Object malformed-partial.ics, line 16: no UID")
    }
}
