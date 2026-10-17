//
//  MoodleMock.swift
//  Kadence
//
//  Phase 3 slice 3 — components.md §43.1: the review mock's Moodle calendar
//  URL, the only one any test, frame or fixture holds. Its `userid` (`4711`)
//  and `authtoken` (`SENTINEL…`) are invented, as the review account
//  `user01` is; §43.3's leak tests search every output for them.
//
//  Used by review mode's in-memory secret store and the tests only. A normal
//  launch never reads it.
//

import Foundation

nonisolated enum MoodleMock {
    static let host = "moodle.technikum-wien.at"
    /// §43.1, exactly.
    static let urlString = "https://moodle.technikum-wien.at/calendar/export_execute.php?userid=4711&authtoken=SENTINELb0c7a1e2d3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8&preset_what=all&preset_time=recentupcoming"
    /// The substrings no output may contain (§43.3).
    static let leakMarkers = ["SENTINEL", "4711", "authtoken"]

    /// The parsed mock URL. Force-free: a mock that fails validation is a
    /// programming error the tests catch, so review falls back to no URL.
    static var url: MoodleFeedURL? {
        if case .valid(let url) = MoodleFeedURL.validate(urlString) { url } else { nil }
    }
}
