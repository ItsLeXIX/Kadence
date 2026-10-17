//
//  MoodleTestSupport.swift
//  KadenceTests
//
//  Phase 3 slice 3 — the redacted Moodle fixture and the `moodle-mocks.md`
//  M1 bodies derived from it in memory (never by editing `fixtures/`), plus
//  helpers shared by the slice 3 suites. Europe/Vienna throughout.
//

import Foundation
import Testing
@testable import Kadence

nonisolated enum MoodleFixture {
    static let zone = TimeZone(identifier: "Europe/Vienna")!

    static var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }

    /// `fixtures/moodle-2026WS-redacted.ics`, byte for byte.
    static var data: Data {
        (try? Data(contentsOf: Fixture.repoRoot.appendingPathComponent("fixtures/moodle-2026WS-redacted.ics"))) ?? Data()
    }

    static var text: String { String(decoding: data, as: UTF8.self) }

    /// An M1 body, derived from the fixture.
    static func body(_ feedCase: MoodleFeedCase) -> Data {
        MoodleFeedCases.body(feedCase, base: text) ?? Data()
    }

    static func feed(_ feedCase: MoodleFeedCase = .feedOK) -> MoodleFeed? {
        if case .calendar(let feed) = MoodleProfile.read(body(feedCase), zone: zone) { feed } else { nil }
    }

    /// `yyyy-MM-dd HH:mm` in Vienna.
    static func date(_ text: String) -> Date { TestClock.date(text) }

    /// The UID's number.
    static func number(_ item: MoodleItem) -> String { String(item.externalID.prefix { $0 != "@" }) }

    /// `Sun 11 Oct 23:59 CEST`.
    static func local(_ date: Date, zone: TimeZone = zone) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = zone
        f.dateFormat = "EEE d MMM HH:mm zzz"
        // `zzz` gives `GMT+2` in POSIX; map to the spec's names.
        return f.string(from: date).replacingOccurrences(of: "GMT+2", with: "CEST")
            .replacingOccurrences(of: "GMT+1", with: "CET")
    }

    /// No output may contain these (§43.3).
    static func leaks(_ text: String) -> Bool { MoodleMock.leakMarkers.contains { text.contains($0) } }
}
