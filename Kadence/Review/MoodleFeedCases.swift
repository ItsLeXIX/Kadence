//
//  MoodleFeedCases.swift
//  Kadence
//
//  Phase 3 slice 3 — `moodle-mocks.md` §M1, §M2: the calendar bodies the
//  mock feed transport serves, derived from one base export (the redacted
//  fixture in tests, the review template rendered at `M` in review mode) by
//  the edits the mocks file lists. The base is never written; every case is
//  built in memory.
//
//  Dates the edits insert are written as the fixture's own UTC values
//  (`20261022T100000Z`); `shift` maps them to the base's week (identity for
//  the fixture, `+ (M − 12 Oct)` at the same local time for review).
//

import Foundation

nonisolated enum MoodleFeedCase: String, CaseIterable, Sendable {
    // M1: calendar bodies
    case feedOK, feedStampOnly, feedLF, feedChanged, feedAged, feedEmpty, feedNotice, feedBroken
    case feedDuplicateUID, feedInvalidUTF8, feedHuge
    // M3: answers that are not a calendar
    case feedHTML, feedError200, feed401, feed403, feed404, feed410, feed500, feed503, feed429
    case feedRedirectSameHost, feedRedirectTwice, feedRedirectCrossHost, feedRedirectHTTP
    case feedTLS, feedOffline, feedTimeout, feedRefused

    /// M1's rows: a `200` with a calendar body.
    var isCalendarBody: Bool {
        switch self {
        case .feedOK, .feedStampOnly, .feedLF, .feedChanged, .feedAged, .feedEmpty, .feedNotice, .feedBroken,
             .feedDuplicateUID, .feedInvalidUTF8, .feedHuge: true
        default: false
        }
    }
}

nonisolated enum MoodleFeedCases {
    static let crlf = "\r\n"

    /// The M1 body of `feedCase` from `base` (a Moodle export, CRLF, as the
    /// fixture). nil for M3's cases, which have no calendar body.
    static func body(_ feedCase: MoodleFeedCase, base: String,
                     shift: @escaping (String) -> String = { $0 }) -> Data? {
        var cal = MoodleCalendarText(base)
        switch feedCase {
        case .feedOK:
            return Data(base.utf8)
        case .feedStampOnly:
            cal.setAll("DTSTAMP", shift("20261016T120712Z"))
            cal.set("LAST-MODIFIED", shift("20261016T120000Z"), uid: "900020")
        case .feedLF:
            return Data(lineFeedsOnly(base).utf8)
        case .feedChanged:
            // E1–E8, then every edited VEVENT a new LAST-MODIFIED.
            cal.set("DTSTART", shift("20261022T100000Z"), uid: "900008")
            cal.set("DTEND", shift("20261022T100000Z"), uid: "900008")
            cal.remove(uid: "900026")
            cal.remove(uid: "900029")
            cal.set("DESCRIPTION", "Fixture description 24.", uid: "900024")
            cal.add(uid: "900030", summary: "Quiz 2 closes", category: "BIF-VZ-4-SS2026-REQEN-EN/166166",
                    start: shift("20261105T224500Z"), end: shift("20261105T224500Z"), stamp: shift("20261016T120712Z"),
                    lastModified: shift("20261016T120000Z"))
            cal.add(uid: "900031", summary: "Quiz 3 opens", category: "BIF-VZ-4-SS2026-REQEN-EN/166166",
                    start: shift("20261210T080000Z"), end: shift("20261210T080000Z"), stamp: shift("20261016T120712Z"),
                    lastModified: shift("20261016T120000Z"))
            cal.remove(uid: "900001")
            cal.set("DESCRIPTION", "Changed after the fact.", uid: "900005")
            for uid in ["900008", "900024", "900020", "900005"] {
                cal.set("LAST-MODIFIED", shift("20261016T120000Z"), uid: uid)
            }
            cal.setAll("DTSTAMP", shift("20261016T120712Z"))
        case .feedAged:
            for n in 1...7 { cal.remove(uid: "90000\(n)") }
            cal.setAll("DTSTAMP", shift("20261022T060000Z"))
        case .feedEmpty:
            cal.events = []
        case .feedNotice:
            cal.add(uid: "900040", summary: "Guest lecture: Testing in practice", category: "BIF-VZ-5-WS2026-SWQM-EN/174454",
                    start: shift("20261021T080000Z"), end: shift("20261021T080000Z"), stamp: cal.firstStamp)
            cal.add(uid: "900041", summary: "Consultation hour", category: "BIF-VZ-5-WS2026-SWQM-EN/174454",
                    start: shift("20261021T120000Z"), end: shift("20261021T130000Z"), stamp: cal.firstStamp)
        case .feedBroken:
            // The four broken VEVENTs' summaries are the mock's own (the
            // mocks file gives only what is broken about each).
            cal.events.append(MoodleCalendarText.event([
                "SUMMARY:Quiz 90 closes", "DESCRIPTION:", "CLASS:PUBLIC", "DTSTAMP:\(cal.firstStamp)",
                "DTSTART:\(shift("20261020T100000Z"))", "DTEND:\(shift("20261020T100000Z"))",
                "CATEGORIES:BIF-VZ-5-WS2026-SWQM-EN/174454",
            ]))
            cal.events.append(MoodleCalendarText.event([
                "UID:900091@moodle.technikum-wien.at", "SUMMARY:Quiz 91 closes", "DESCRIPTION:", "CLASS:PUBLIC",
                "DTSTAMP:\(cal.firstStamp)", "DTEND:\(shift("20261020T100000Z"))",
                "CATEGORIES:BIF-VZ-5-WS2026-SWQM-EN/174454",
            ]))
            cal.events.append(MoodleCalendarText.event([
                "UID:900092@moodle.technikum-wien.at", "SUMMARY:Quiz 92 closes", "DESCRIPTION:", "CLASS:PUBLIC",
                "DTSTAMP:\(cal.firstStamp)", "DTSTART:\(shift("20261020T100000Z"))",
                "DTEND:\(shift("20261020T090000Z"))", "CATEGORIES:BIF-VZ-5-WS2026-SWQM-EN/174454",
            ]))
            // Never closed before END:VCALENDAR.
            cal.unclosedTail = (["BEGIN:VEVENT", "UID:900093@moodle.technikum-wien.at", "SUMMARY:Quiz 93 closes",
                                 "DTSTART:\(shift("20261020T100000Z"))", "DTEND:\(shift("20261020T100000Z"))"])
                .joined(separator: crlf) + crlf
        case .feedDuplicateUID:
            guard var copy = cal.events.first(where: { $0.uid == "900008" }) else { return nil }
            copy.set("DESCRIPTION", "Second copy.")
            cal.events.append(copy)
        case .feedInvalidUTF8:
            var bytes = [UInt8](base.utf8)
            guard let at = invalidUTF8Offset(in: bytes) else { return nil }
            bytes.insert(0xFF, at: at)
            return Data(bytes)
        case .feedHuge:
            // A valid calendar padded with DESCRIPTION text to 21 MB.
            let line = " " + String(repeating: "x", count: 74) + crlf
            let lines = 21 * 1_048_576 / line.utf8.count + 1
            let padding = "DESCRIPTION:" + String(repeating: "x", count: 63) + crlf
                + String(repeating: line, count: lines)
            cal.events = [MoodleCalendarText.Event(lines: [
                "UID:900099@moodle.technikum-wien.at" + crlf, "SUMMARY:Huge is due" + crlf, padding,
                "DTSTAMP:\(cal.firstStamp)" + crlf, "DTSTART:\(shift("20261020T100000Z"))" + crlf,
                "DTEND:\(shift("20261020T100000Z"))" + crlf,
            ])]
        default:
            return nil
        }
        return Data(cal.text.utf8)
    }

    /// `feedLF`: every `CRLF` → `LF`, every fold's TAB → one space, the
    /// lone-TAB lines removed.
    static func lineFeedsOnly(_ base: String) -> String {
        base.components(separatedBy: crlf)
            .filter { $0 != "\t" }
            .map { $0.hasPrefix("\t") ? " " + $0.dropFirst() : $0 }
            .joined(separator: "\n")
    }

    /// Just after `🎮` in `900024`'s `SUMMARY` (`feedInvalidUTF8`).
    static func invalidUTF8Offset(in bytes: [UInt8]) -> Int? {
        let marker = [UInt8]("UID:900024@".utf8)
        let summary = [UInt8]("SUMMARY:".utf8)
        let gamepad = [UInt8]("🎮".utf8)
        guard let uid = bytes.firstRange(of: marker),
              let s = bytes[uid.upperBound...].firstRange(of: summary),
              let g = bytes[s.upperBound...].firstRange(of: gamepad) else { return nil }
        return g.upperBound
    }
}

/// A Moodle export as text: the header, the VEVENT blocks, the footer. Each
/// block keeps its properties' physical lines (folds and the lone-TAB line
/// included), so an untouched block is reproduced byte for byte.
nonisolated struct MoodleCalendarText: Sendable {
    struct Event: Sendable {
        /// One entry per property: its physical lines, CRLF included.
        var lines: [String]

        var uid: String? {
            lines.first { $0.hasPrefix("UID:") }.map {
                String($0.dropFirst(4).prefix { $0 != "@" && $0 != "\r" })
            }
        }

        /// Replaces the property's value (all its physical lines) with one
        /// unfolded line, or appends it.
        mutating func set(_ name: String, _ value: String) {
            let line = "\(name):\(value)\r\n"
            if let at = lines.firstIndex(where: { $0.hasPrefix(name + ":") || $0.hasPrefix(name + ";") }) {
                lines[at] = line
            } else {
                lines.append(line)
            }
        }

        var text: String { "BEGIN:VEVENT\r\n" + lines.joined() + "END:VEVENT\r\n" }
    }

    var header: String
    var events: [Event]
    var footer: String
    /// `feedBroken`: a block left open before `END:VCALENDAR`.
    var unclosedTail = ""

    init(_ text: String) {
        let parts = text.components(separatedBy: "BEGIN:VEVENT\r\n")
        header = parts.first ?? ""
        var events: [Event] = []
        var footer = ""
        for (i, part) in parts.dropFirst().enumerated() {
            let pieces = part.components(separatedBy: "END:VEVENT\r\n")
            events.append(Event(lines: Self.properties(pieces.first ?? "")))
            if i == parts.count - 2 { footer = pieces.dropFirst().joined(separator: "END:VEVENT\r\n") }
        }
        if events.isEmpty, let end = header.range(of: "END:VCALENDAR") {
            footer = String(header[end.lowerBound...])
            header = String(header[..<end.lowerBound])
        }
        self.events = events
        self.footer = footer
    }

    /// Physical lines grouped by property: a line starting with a TAB or a
    /// space (a fold, or the lone-TAB line) belongs to the one before.
    static func properties(_ block: String) -> [String] {
        var out: [String] = []
        for line in block.components(separatedBy: "\r\n").dropLast() {
            let physical = line + "\r\n"
            if (line.hasPrefix("\t") || line.hasPrefix(" ")), !out.isEmpty {
                out[out.count - 1] += physical
            } else {
                out.append(physical)
            }
        }
        return out
    }

    static func event(_ lines: [String]) -> Event { Event(lines: lines.map { $0 + "\r\n" }) }

    var firstStamp: String {
        events.lazy.compactMap { $0.lines.first { $0.hasPrefix("DTSTAMP:") } }.first
            .map { String($0.dropFirst(8).prefix { $0 != "\r" }) } ?? "20261016T110712Z"
    }

    mutating func set(_ name: String, _ value: String, uid: String) {
        guard let at = events.firstIndex(where: { $0.uid == uid }) else { return }
        events[at].set(name, value)
    }

    mutating func setAll(_ name: String, _ value: String) {
        for i in events.indices { events[i].set(name, value) }
    }

    mutating func remove(uid: String) { events.removeAll { $0.uid == uid } }

    /// A new VEVENT in Moodle's property order, with an empty `DESCRIPTION`.
    mutating func add(uid: String, summary: String, category: String, start: String, end: String,
                      stamp: String, lastModified: String? = nil) {
        var lines = ["UID:\(uid)@moodle.technikum-wien.at", "SUMMARY:\(summary)", "DESCRIPTION:", "CLASS:PUBLIC"]
        if let lastModified { lines.append("LAST-MODIFIED:\(lastModified)") }
        lines += ["DTSTAMP:\(stamp)", "DTSTART:\(start)", "DTEND:\(end)", "CATEGORIES:\(category)"]
        events.append(Self.event(lines))
    }

    var text: String { header + events.map(\.text).joined() + unclosedTail + footer }
}
