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
