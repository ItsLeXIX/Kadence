//
//  ReviewTemplate.swift
//  Kadence
//
//  components.md §22.1 — `Fixtures/ICS/cis-review.ics.template`, the review
//  dataset's timetable: the real export's structure exactly (CRLF,
//  `VERSION:1.0`, the real VTIMEZONE block), 14 VEVENTs in the CIS shape,
//  dates as `{{D+n}}` / `{{T-n}}` / `{{TODAY}}`. Bundled with the app only
//  so review mode can serve it; read nowhere else (G-057: a normal launch
//  never sees fixture data).
//

import Foundation

nonisolated enum ReviewTemplate {
    /// Swift note: the synchronized `Kadence/` folder copies non-source files
    /// into the app bundle's resources, flat, by name.
    static var text: String {
        guard let url = Bundle.main.url(forResource: "cis-review.ics", withExtension: "template"),
              let data = try? Data(contentsOf: url) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// components.md §22.1 `fresh` — `cis-2026WS-redacted.ics`, a byte-for-byte
/// copy of `fixtures/cis-2026WS-redacted.ics` (a test asserts the hash).
/// Bundled with the app only so review mode can serve it; read nowhere else.
nonisolated enum ReviewCISExport {
    static var text: String {
        guard let url = Bundle.main.url(forResource: "cis-2026WS-redacted", withExtension: "ics"),
              let data = try? Data(contentsOf: url) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

/// components.md §30.1 — `Fixtures/ICS/cis-travel.ics.template`, dataset
/// `travel`'s timetable: `cis-review.ics.template` without row 1
/// (`Datenmodellierung` on `{{TODAY}}`) plus row T1 (`SWEN3-ILV`
/// `{{D+1}}` 11:45–13:15, `HS_A2.07`). Bundled only so review mode can serve
/// it.
nonisolated enum ReviewTravelTemplate {
    static var text: String {
        guard let url = Bundle.main.url(forResource: "cis-travel.ics", withExtension: "template"),
              let data = try? Data(contentsOf: url) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}
