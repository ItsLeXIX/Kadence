//
//  ProblemSentenceTests.swift
//  KadenceTests
//
//  PHASE3-REVIEW.md fix 8 — components.md §19.3 "The sentences" (added
//  2026-10-10; closes GAPS G-069): one exact sentence and technical line per
//  problem, from `malformed-partial.ics`, `truncated.ics` and
//  `edge-cases.ics`; §6's done rule on solid fills (closes G-074); tokens
//  1.7.0.
//

import Testing
import Foundation
import SwiftUI
@testable import Kadence

nonisolated private let zone = TestClock.zone
nonisolated private let lvplan = MockCalDAVServer.lvplan

@MainActor
@Suite(.serialized)
struct ProblemSentenceTests {

    /// A fixture file as one calendar object named after it.
    private func derive(_ name: String, edit: (String) -> String = { $0 }, object: String? = nil) throws -> DerivedFeed {
        guard case .calendar(let parsed) = ICSParser.parse(edit(try Fixture.text(name)), currentZone: zone) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return FeedDerivation.derive([FeedObject(calendarHref: lvplan, objectHref: object.map { lvplan + $0 } ?? "",
                                                 calendar: parsed)],
                                     today: Windows.syncStart(now: TestClock.now, zone: zone), zone: zone)
    }

    private func pairs(_ feed: DerivedFeed) -> [[String]] { feed.problems.map { [$0.sentence, $0.technical ?? "—"] } }

    // MARK: malformed-partial.ics — no UID, ends before it starts, no readable start, unsupported rule

    @Test("malformed-partial.ics as an object: the three skipped events and the unsupported rule, sentence and technical line")
    func malformedPartialAsObject() throws {
        let feed = try derive("malformed-partial.ics", object: "obj-07.ics")
        #expect(feed.events.count == 6)
        #expect(pairs(feed) == [
            ["No UID has no identifier, so it was skipped.", "Object obj-07.ics, line 16: no UID"],
            ["End before start ends before it starts, so it was skipped.", "Object obj-07.ics, line 31: DTEND before DTSTART"],
            ["Garbage start has no readable start time, so it was skipped.", "Object obj-07.ics, line 42: DTSTART"],
            ["1 repeating event uses a rule Kadence can't read yet: Mathe Tutorium",
             "Object obj-07.ics, line 51: RRULE FREQ=MONTHLY;BYDAY=2MO"],
        ])
    }

    @Test("Without an object name (a plain file) the technical line starts at `Line 16:`")
    func plainFile() throws {
        let feed = try derive("malformed-partial.ics")
        #expect(feed.problems.map { $0.technical ?? "" } == [
            "Line 16: no UID", "Line 31: DTEND before DTSTART", "Line 42: DTSTART",
            "Line 51: RRULE FREQ=MONTHLY;BYDAY=2MO",
        ])
        #expect(feed.problems.map(\.line) == [16, 31, 42, 51])
    }

    @Test("{title}: the course code for a CIS-profile event, `An event` with no readable SUMMARY; a missing DTSTART; a negative DURATION")
    func titlesAndTheOtherCauses() throws {
        func problems(_ lines: [String]) -> [[String]] {
            let text = (["BEGIN:VCALENDAR", "VERSION:2.0", "BEGIN:VEVENT"] + lines + ["END:VEVENT", "END:VCALENDAR"])
                .joined(separator: "\r\n") + "\r\n"
            guard case .calendar(let parsed) = ICSParser.parse(text, currentZone: zone) else { return [["not a calendar"]] }
            return parsed.problems.map { [$0.sentence, $0.technical ?? "—"] }
        }
        // A CIS-shaped VEVENT (four-line DESCRIPTION, SUMMARY's first token) → its course code.
        #expect(problems([
            "SUMMARY:SWQM-ILV  HS_A3.15 - BIF-5C ", "DESCRIPTION:SWQM-ILV\\nL01\\nBIF-5C \\nHS_A3.15",
            "DTSTART;TZID=Europe/Vienna:20261012T143000", "DTEND;TZID=Europe/Vienna:20261012T160000",
        ]) == [["SWQM-ILV has no identifier, so it was skipped.", "Line 3: no UID"]])
        // The same, ending before it starts.
        #expect(problems([
            "UID:x", "SUMMARY:SWQM-ILV  HS_A3.15 - BIF-5C ", "DESCRIPTION:SWQM-ILV\\nL01\\nBIF-5C \\nHS_A3.15",
            "DTSTART;TZID=Europe/Vienna:20261012T143000", "DTEND;TZID=Europe/Vienna:20261012T140000",
        ]) == [["SWQM-ILV ends before it starts, so it was skipped.", "Line 8: DTEND before DTSTART"]])
        // No SUMMARY at all, or an empty one.
        #expect(problems(["DTSTART:20261012T090000Z"]) == [["An event has no identifier, so it was skipped.", "Line 3: no UID"]])
        #expect(problems(["UID:x", "SUMMARY:   ", "DTEND:20261012T090000Z"])
                == [["An event has no readable start time, so it was skipped.", "Line 3: DTSTART"]])
        // DTSTART missing (the VEVENT's line) and a negative DURATION (its own line).
        #expect(problems(["UID:x", "SUMMARY:Lab"]) == [["Lab has no readable start time, so it was skipped.", "Line 3: DTSTART"]])
        #expect(problems(["UID:x", "SUMMARY:Lab", "DTSTART:20261012T090000Z", "DURATION:-PT1H"])
                == [["Lab ends before it starts, so it was skipped.", "Line 7: negative DURATION"]])
        // A whitespace-collapsed SUMMARY, as §20.7 treats a title.
        #expect(problems(["SUMMARY:Planning   and\\, notes ", "DTSTART:20261012T090000Z"])
                == [["Planning and, notes has no identifier, so it was skipped.", "Line 3: no UID"]])
    }

    // MARK: truncated.ics, an object that is not calendar data, a failed member, an object over 1 MB

    /// A sync whose `REPORT` serves `objects`.
    private func fetch(_ objects: [MockCalDAVServer.Object],
                       override: (@Sendable (StubRecord) -> StubReply?)? = nil) async throws -> ScheduleFetchResult {
        let harness = MockHarness(.reportOK, feed: objects, ignoresTimeRange: true, override: override)
        let (session, transport) = harness.session()
        defer { transport.invalidate() }
        let account = CalDAVAccount(server: ServerAddress(host: MockCalDAVServer.host), username: "user01",
                                    calendars: [SourceCalendar(href: lvplan, displayName: "LVPlan")],
                                    capabilities: SourceCapabilities(fetchMode: .report, timeRangeHonoured: nil, discoveredAt: TestClock.now))
        return try await CalDAVScheduleSource.run(account: account, windowStart: Windows.importStart(now: TestClock.now, zone: zone),
                                                  session: session, zone: zone, now: TestClock.now)
    }

    @Test("truncated.ics (BEGIN:VEVENT never closed) and a web page as objects: `1 event couldn't be read.` / `Object …: not calendar data`")
    func truncatedAndNotCalendarData() async throws {
        let good = try #require(MockHarness.reportCIS().first)
        let truncated = MockCalDAVServer.Object(href: lvplan + "obj-11.ics", etag: "\"t\"", data: try Fixture.text("truncated.ics"))
        let page = MockCalDAVServer.Object(href: lvplan + "obj-12.ics", etag: "\"h\"", data: try Fixture.text("html-login.html"))
        let result = try await fetch([good, truncated, page])
        #expect(result.events.count == 1)
        #expect(result.problems.map { [$0.sentence, $0.technical ?? "—"] } == [
            ["1 event couldn't be read.", "Object obj-11.ics: not calendar data"],
            ["1 event couldn't be read.", "Object obj-12.ics: not calendar data"],
        ])
        // A VEVENT left open inside an otherwise closed calendar: the same sentence, by line.
        let open = "BEGIN:VCALENDAR\r\nVERSION:2.0\r\nBEGIN:VEVENT\r\nUID:x\r\nSUMMARY:Open\r\nDTSTART:20261012T090000Z\r\nEND:VCALENDAR\r\n"
        guard case .calendar(let parsed) = ICSParser.parse(open, currentZone: zone) else { Issue.record("not a calendar"); return }
        #expect(parsed.problems.map { [$0.sentence, $0.technical ?? "—"] } == [["1 event couldn't be read.", "Line 3: VEVENT not closed"]])
    }

    @Test("An object over 1 MB: `1 event was too large to read.` / `Object obj-11.ics: over 1 MB`")
    func tooLarge() async throws {
        let good = try #require(MockHarness.reportCIS().first)
        // A valid calendar whose one VEVENT carries a description over the limit.
        let padding = String(repeating: "x", count: ICSParser.maxObjectBytes + 1)
        let big = MockCalDAVServer.Object(href: lvplan + "obj-11.ics", etag: "\"b\"",
                                          data: good.data.replacingOccurrences(of: "LOCATION:HS_A3.15", with: "LOCATION:HS_A3.15\r\nX-PAD:\(padding)"))
        #expect(big.data.utf8.count > ICSParser.maxObjectBytes)
        let result = try await fetch([good, big])
        #expect(result.events.count == 1)
        #expect(result.problems.map { [$0.sentence, $0.technical ?? "—"] } == [["1 event was too large to read.", "Object obj-11.ics: over 1 MB"]])
    }

    @Test("A failed member of a 207: `1 event couldn't be read.` / `Object obj-11.ics: 404`")
    func failedMember() async throws {
        let good = try #require(MockHarness.reportCIS().first)
        let body = MockCalDAVServer.reportResponse([good], extra: ["""
            <d:response>
              <d:href>\(lvplan)obj-11.ics</d:href>
              <d:status>HTTP/1.1 404 Not Found</d:status>
            </d:response>
            """])
        let result = try await fetch([good]) { record in
            guard record.method == "REPORT", record.hasAuthorization else { return nil }
            return .response(HTTPResponseSpec(status: 207, headers: MockCalDAVServer.xmlHeaders, body: Data(body.utf8)))
        }
        #expect(result.problems.map { [$0.sentence, $0.technical ?? "—"] } == [["1 event couldn't be read.", "Object obj-11.ics: 404"]])
    }

    // MARK: edge-cases.ics — a THISANDFUTURE override, the unknown zone

    @Test("edge-cases.ics with its override marked RANGE=THISANDFUTURE: the event is kept and the change reported")
    func thisAndFuture() throws {
        let plain = try derive("edge-cases.ics", object: "obj-07.ics")
        let feed = try derive("edge-cases.ics", edit: {
            $0.replacingOccurrences(of: "RECURRENCE-ID;TZID=Europe/Vienna:", with: "RECURRENCE-ID;RANGE=THISANDFUTURE;TZID=Europe/Vienna:")
        }, object: "obj-07.ics")
        // The override still replaces its one occurrence; nothing is skipped.
        #expect(feed.events == plain.events)
        #expect(feed.events.contains { $0.title == "Weekly seminar (moved)" })
        #expect(pairs(feed).first == ["A change to Weekly seminar (moved) and its later repeats was applied to one occurrence only.",
                                      "Object obj-07.ics, line 84: RECURRENCE-ID;RANGE=THISANDFUTURE"])
        // The unknown time zone (§20.3; kept) — its sentence unchanged, no technical line.
        #expect(pairs(feed).last == pairs(plain).last)
        #expect(pairs(plain) == [["1 event used an unknown time zone (Custom Zone) and was read in this Mac's time zone (Europe/Vienna)", "—"]])
    }

    // MARK: No placeholder left; tokens; §6 done

    @Test("No `SPEC-GAP G-069` or `G-074` is left in the app; the old placeholder strings are gone")
    func noPlaceholdersLeft() throws {
        let root = Fixture.repoRoot.appendingPathComponent("Kadence")
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var checked = 0
        for case let url as URL in files where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            checked += 1
            #expect(!text.contains("SPEC-GAP G-069") && !text.contains("SPEC-GAP G-074"), "\(url.lastPathComponent)")
            #expect(!text.contains("couldn't be read\"") && !text.contains("applied to one occurrence only:"), "\(url.lastPathComponent)")
        }
        #expect(checked > 80)
        #expect(ProblemSentence.unreadable == "1 event couldn't be read.")
        #expect(ProblemSentence.tooLarge == "1 event was too large to read.")
    }

    @Test("Tokens are 1.9.0 and generated from it; the palette rule is the amended one")
    func tokensAtOneSevenZero() throws {
        let json = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: Fixture.repoRoot.appendingPathComponent("design/tokens.json"))) as? [String: Any])
        let meta = try #require(json["$meta"] as? [String: Any])
        // P3S2-T01: 1.9.0 since the slice 2 spec commit (the pin moves with it).
        #expect(meta["version"] as? String == "1.9.0")
        // 1.7.0 changed no value; the one generated string it amended is the palette rule.
        #expect(Tokens.Color.SourcePalette.assignmentRule.hasPrefix("Assign in listed order as sources are added, skipping graphite"))
    }

    @Test("A done block on a solid fill: label, glyph, time and meta are all text.primary — in every solid kind",
          arguments: [BlockKind.fixedTimed, .examAllDay, .eventAllDay])
    func doneOnSolidFills(_ kind: BlockKind) {
        let done = resolveBlockStyle(kind: kind, flexibility: .fixed, status: .done, presentation: [], source: .blue, renderedHeight: 66)
        // The time and the meta line are both drawn in `style.meta`.
        #expect(done.meta == Tokens.Color.Text.primary)
        #expect(done.label == Tokens.Color.Text.primary)
        #expect(done.glyphColor == Tokens.Color.Text.primary)
        #expect(done.glyph == "checkmark.circle.fill")
        #expect(done.fillBlendWithCanvas == Tokens.Opacity.blockDoneFillBlend)
        // Not done: the solid fill's own text.onSolid (meta at 0.8) is kept.
        let scheduled = resolveBlockStyle(kind: kind, flexibility: .fixed, status: .scheduled, presentation: [], source: .blue, renderedHeight: 66)
        #expect(scheduled.label == Tokens.Color.Text.onSolid && scheduled.meta != Tokens.Color.Text.primary)
        // Past as well as done (a lecture marked after it happened): still text.primary.
        let past = resolveBlockStyle(kind: kind, flexibility: .fixed, status: .done, presentation: [.past], source: .blue, renderedHeight: 66)
        #expect(past.meta == Tokens.Color.Text.primary && past.label == Tokens.Color.Text.primary)
    }

    @Test("A done routine or planned block keeps text.secondary: the rule is for solid fills")
    func doneElsewhere() {
        for kind in [BlockKind.routineTimed, .plannedTimed] {
            let done = resolveBlockStyle(kind: kind, flexibility: .fixed, status: .done, presentation: [], source: .green, renderedHeight: 66)
            #expect(done.label == Tokens.Color.Text.secondary && done.meta == Tokens.Color.Text.secondary)
        }
    }
}
