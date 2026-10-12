//
//  TieMergeTests.swift
//  KadenceTests
//
//  PHASE3-REVIEW.md fix 4 — components.md §20.2 (exact duplicates, amended
//  2026-10-10), §20.8.4 (the log line's `vevents`, `duplicates`, `merged`;
//  the `connect` and `import` lines); caldav-mocks.md `reportCISSameUID`;
//  GAPS G-077; DECISIONS 2026-10-10 "A tie is not a duplicate".
//
//  The regression: Parsa's `BPREF-Info` of Fri 2 Oct 2026 was stored with one
//  lecturer. The one path that drops a lecturer was the exact-duplicate rule,
//  which ran before the merge and kept "the later VEVENT" of two that share a
//  UID and a start. Built from `fixtures/cis-2026WS-redacted.ics`: its two
//  `BPREF-Info` halves, given one UID in code (`reportCISSameUID`).
//

import Testing
import Foundation
import SwiftData
import Synchronization
@testable import Kadence

nonisolated private let zone = TestClock.zone

/// `reportCISSameUID`, optionally with the two halves in the other order
/// (`obj-04` before `obj-03`).
nonisolated private func sameUID(swapped: Bool = false, edit: ((inout [MockCalDAVServer.Object]) -> Void)? = nil) -> [MockCalDAVServer.Object] {
    var objects = ReviewFeed.reportCISSameUID(export: (try? Fixture.text("cis-2026WS-redacted.ics")) ?? "")
    edit?(&objects)
    if swapped { objects.swapAt(2, 3) }
    return objects
}

/// Rebuilds an object with one line added before `END:VEVENT`, or one line
/// replaced.
nonisolated private func object(_ object: MockCalDAVServer.Object, adding line: String? = nil,
                                replacing: (String, String)? = nil) -> MockCalDAVServer.Object {
    var data = object.data
    if let (from, to) = replacing { data = data.replacingOccurrences(of: from, with: to) }
    if let line { data = data.replacingOccurrences(of: "END:VEVENT", with: line + "\r\nEND:VEVENT") }
    return MockCalDAVServer.Object(href: object.href, etag: object.etag, data: data)
}

nonisolated private func derive(_ objects: [MockCalDAVServer.Object]) -> DerivedFeed {
    let feedObjects = objects.compactMap { o -> FeedObject? in
        guard case .calendar(let parsed) = ICSParser.parse(o.data, currentZone: zone) else { return nil }
        return FeedObject(calendarHref: MockCalDAVServer.lvplan, objectHref: o.href, calendar: parsed)
    }
    return FeedDerivation.derive(feedObjects, today: Windows.syncStart(now: TestClock.now, zone: zone), zone: zone)
}

@MainActor
@Suite(.serialized)
struct TieMergeTests {

    // MARK: The fixture's shape, and the same-UID shape

    @Test("reportCISSameUID is reportCIS with obj-04's UID line replaced by obj-03's — the fixture is not edited")
    func theCaseIsBuiltInCode() throws {
        let cis = MockHarness.reportCIS()
        let same = sameUID()
        #expect(cis.count == 13 && same.count == 13)
        func uid(_ o: MockCalDAVServer.Object) -> String? {
            o.data.components(separatedBy: "\r\n").first { $0.hasPrefix("UID:") }
        }
        #expect(uid(cis[2]) != uid(cis[3]))
        #expect(uid(same[2]) == uid(cis[2]) && uid(same[3]) == uid(cis[2]))
        // Only that one line differs, in that one object.
        for i in cis.indices where i != 3 { #expect(same[i] == cis[i]) }
        let before = cis[3].data.components(separatedBy: "\r\n"), after = same[3].data.components(separatedBy: "\r\n")
        #expect(zip(before, after).filter { $0 != $1 }.count == 1)
        #expect(after.contains("DESCRIPTION:BPREF-Info\\nL06\\nif-5\\nWEBINAR02"))
    }

    @Test("reportCIS (different UIDs): 12 events, BPREF-Info 2 Oct 18:35 [L05, L06], merged 1, duplicates 0")
    func differentUIDsStillMerge() throws {
        let feed = derive(MockHarness.reportCIS())
        #expect(feed.events.count == 12 && feed.objectCount == 13)
        #expect(feed.mergedCount == 1 && feed.duplicateCount == 0)
        let bpref = try #require(feed.events.first { $0.title == "BPREF-Info" })
        #expect(bpref.lecturers == ["L05", "L06"] && bpref.start == TestClock.date("2026-10-02 18:35"))
    }

    @Test("reportCISSameUID: 12 events, BPREF-Info [L05, L06], merged 1, duplicates 0 — in both object orders",
          arguments: [false, true])
    func aTieGoesToTheMerge(swapped: Bool) throws {
        let feed = derive(sameUID(swapped: swapped))
        #expect(feed.objectCount == 13)                // 13 VEVENTs read
        #expect(feed.events.count == 12)
        #expect(feed.mergedCount == 1)
        #expect(feed.duplicateCount == 0)
        #expect(feed.problems.isEmpty)
        let bpref = try #require(feed.events.first { $0.title == "BPREF-Info" })
        #expect(bpref.lecturers == ["L05", "L06"])     // not [L06] — "the later one" — and not [L05]
        #expect(bpref.start == TestClock.date("2026-10-02 18:35") && bpref.end == TestClock.date("2026-10-02 20:15"))
        #expect(bpref.isOnline && bpref.group == "if-5" && bpref.location == "WEBINAR02")
        // The same event, with the same identity, as the fixture's own shape gives.
        let reference = derive(MockHarness.reportCIS())
        #expect(feed.events == reference.events)
        #expect(FeedHash.of(feed.events.map { EventHash.of($0, zone: zone) })
                == FeedHash.of(reference.events.map { EventHash.of($0, zone: zone) }))
    }

    @Test("The same pair with a higher SEQUENCE on one: that one's lecturers only, duplicates 1, merged 0",
          arguments: [(2, ["L05"]), (3, ["L06"])])
    func aStrictWinnerIsStillADuplicate(winner: Int, lecturers: [String]) throws {
        for swapped in [false, true] {
            let feed = derive(sameUID(swapped: swapped) { $0[winner] = object($0[winner], adding: "SEQUENCE:2") })
            #expect(feed.events.count == 12)
            #expect(feed.duplicateCount == 1 && feed.mergedCount == 0)
            let bpref = try #require(feed.events.first { $0.title == "BPREF-Info" })
            #expect(bpref.lecturers == lecturers)
        }
        // A later stamp wins the same way when the sequences are equal.
        let stamped = derive(sameUID {
            $0[2] = object($0[2], adding: "DTSTAMP:20261001T080000Z")
            $0[3] = object($0[3], adding: "DTSTAMP:20261001T090000Z")
        })
        #expect(stamped.duplicateCount == 1 && stamped.mergedCount == 0)
        #expect(stamped.events.first { $0.title == "BPREF-Info" }?.lecturers == ["L06"])
    }

    @Test("A tie with different summaries is two events, each under its content key")
    func aTieWithDifferentContentIsTwoEvents() throws {
        for swapped in [false, true] {
            let feed = derive(sameUID(swapped: swapped) {
                $0[3] = object($0[3], replacing: ("SUMMARY:BPREF-Info  WEBINAR02 - if-5", "SUMMARY:BPREF-Info  WEBINAR02 - if-6"))
            })
            #expect(feed.events.count == 13)
            #expect(feed.mergedCount == 0 && feed.duplicateCount == 0)
            let pair = feed.events.filter { $0.title == "BPREF-Info" }
            #expect(pair.count == 2)
            #expect(Set(pair.map(\.lecturers)) == [["L05"], ["L06"]])
            #expect(Set(pair.map(\.externalID)) == [
                "BPREF-Info WEBINAR02 - if-5|WEBINAR02|20261002T163500Z|20261002T181500Z",
                "BPREF-Info WEBINAR02 - if-6|WEBINAR02|20261002T163500Z|20261002T181500Z",
            ])
        }
    }

    @Test("Three VEVENTs with one UID and start: lecturers unioned in a fixed order; identical VEVENTs collapse to one event")
    func threeWayTie() throws {
        let three = derive(sameUID { objects in
            objects.append(MockCalDAVServer.Object(
                href: MockCalDAVServer.lvplan + "obj-14.ics", etag: "\"cis-14-a\"",
                data: objects[2].data.replacingOccurrences(of: "\\nL05\\n", with: "\\nL04\\n")))
        })
        #expect(three.events.count == 12 && three.mergedCount == 1 && three.duplicateCount == 0)
        #expect(three.events.first { $0.title == "BPREF-Info" }?.lecturers == ["L04", "L05", "L06"])
        // The same VEVENT twice (same lecturer too): still one event, one lecturer.
        let twice = derive(sameUID { $0[3] = MockCalDAVServer.Object(href: $0[3].href, etag: $0[3].etag, data: $0[2].data) })
        #expect(twice.events.count == 12)
        #expect(twice.events.first { $0.title == "BPREF-Info" }?.lecturers == ["L05"])
    }

    // MARK: Through the REPORT, the planner and the store

    @Test("Import then sync of reportCISSameUID: BPREF-Info stored with both lecturers; the second write is nothing",
          arguments: [false, true])
    func importThenSyncWritesNothing(swapped: Bool) async throws {
        let f = try SyncFixture()
        let harness = MockHarness(.reportOK, feed: sameUID(swapped: swapped))
        let (plan, _) = try await f.run(harness, kind: .import)
        #expect(plan.creates.count == 12)
        let stored = try #require(f.event("BPREF-Info"))
        #expect(stored.lecturers == ["L05", "L06"])
        // The inspector's row for it (layouts.md §6.1 row 4).
        #expect(ImportedInspectorCopy.lecturersLabel(stored.lecturers) == "Lecturers")
        let rows = ImportedInspectorCopy.lecturerLines(stored.lecturers, expanded: false)
        #expect(rows.names == ["L05", "L06"] && rows.button == nil)
        #expect(ImportedInspectorCopy.lecturersAccessibilityValue(stored.lecturers) == "2 lecturers: L05, L06")

        // The same feed again, the other object order: nothing is written.
        let ids = f.events.map(\.id)
        let again = MockHarness(.reportOK, feed: sameUID(swapped: !swapped), ignoresTimeRange: true)
        let (second, outcome) = try await f.run(again, kind: .sync, now: TestClock.date("2026-09-01 10:00"))
        #expect(!second.writesEvents && second.creates.isEmpty && second.updates.isEmpty && second.deletes.isEmpty)
        #expect(!outcome.wrote && outcome.deletedIDs.isEmpty)
        #expect(f.events.map(\.id) == ids)
        #expect(f.event("BPREF-Info")?.lecturers == ["L05", "L06"])
        // And with step 4 disabled, the diff itself finds nothing.
        let (third, _) = try await f.run(again, kind: .sync, now: TestClock.date("2026-09-01 10:00"), disableStep4: true)
        #expect(!third.writesEvents)
    }

    // MARK: The log (§20.8.4)

    @Test("The sync line carries vevents, duplicates and merged, after objects")
    func syncLineFields() async throws {
        let f = try SyncFixture()
        let harness = MockHarness(.reportOK, feed: sameUID())
        let result = try await f.fetch(harness, start: Windows.importStart(now: TestClock.now, zone: zone), now: TestClock.now)
        #expect(result.diagnostics.objects == 13 && result.diagnostics.vevents == 13)
        #expect(result.diagnostics.duplicates == 0 && result.diagnostics.merged == 1)
        let line = SourceLogger.syncLine(account: "user01 @ cis.technikum-wien.at", diagnostics: result.diagnostics,
                                         outcome: "wrote")
        #expect(line.hasPrefix("sync user01 @ cis.technikum-wien.at · LVPlan · mode report · requests 1 · "))
        #expect(line.contains(" ms · objects 13 · vevents 13 · duplicates 0 · merged 1 · time-range honoured · ctag — · etags 13 (set "))
        #expect(line.hasSuffix(") · wrote"))
        #expect(!line.contains(caldavSentinel))

        // With a strict winner the counts say so.
        let won = MockHarness(.reportOK, feed: sameUID { $0[3] = object($0[3], adding: "SEQUENCE:1") })
        let r2 = try await f.fetch(won, start: Windows.importStart(now: TestClock.now, zone: zone), now: TestClock.now)
        let line2 = SourceLogger.syncLine(account: "user01 @ cis.technikum-wien.at", diagnostics: r2.diagnostics, outcome: "wrote")
        #expect(line2.contains("· objects 13 · vevents 13 · duplicates 1 · merged 0 ·"))

        // §20.8.4's own example, field for field.
        var d = SyncDiagnostics()
        d.calendarNames = ["LVPlan"]; d.requests = 1; d.milliseconds = 412; d.objects = 287; d.vevents = 287
        d.duplicates = 0; d.merged = 9; d.timeRangeHonoured = true
        let example = SourceLogger.syncLine(account: "user01 @ cis.technikum-wien.at", diagnostics: d, outcome: "feed unchanged")
        #expect(example.hasPrefix("sync user01 @ cis.technikum-wien.at · LVPlan · mode report · requests 1 · 412 ms · objects 287 · vevents 287 · duplicates 0 · merged 9 · time-range honoured · ctag — · etags 0 (set "))
        #expect(example.hasSuffix(" · feed unchanged"))
        #expect(SourceLogger.connectLine(account: "user01 @ cis.technikum-wien.at", diagnostics: d, events: 91)
            .hasSuffix(" · previewed 91 events"))
        #expect(SourceLogger.connectLine(account: "user01 @ cis.technikum-wien.at", diagnostics: d, events: 91)
            .hasPrefix("connect user01 @ cis.technikum-wien.at · LVPlan · mode report · "))
        #expect(SourceLogger.importLine(account: "user01 @ cis.technikum-wien.at", events: 91, beforeToday: 21)
                == "import user01 @ cis.technikum-wien.at · 91 events · 21 before today")
        #expect(SourceLogger.importLine(account: "u @ h", events: 1, beforeToday: 0) == "import u @ h · 1 event · 0 before today")
    }
}
