//
//  ICSParser.swift
//  Kadence
//
//  PHASE3-PLAN.md task 3 — one iCalendar text → `ParsedCalendar`, or
//  `.notACalendar`. Pure: no I/O, no clock, no store. The "current zone" (the
//  Mac's, in the app) is injected so tests can pin it.
//
//  Spec: components.md §20.3 (time zones), §20.4 (all-day, DURATION, bad
//  ends), §20.7 (field mapping, line endings, BOM, folding), §20.8.2 (what
//  makes a body a calendar; the 1 MB object limit). Recurrence is only *read*
//  here (RRULE text, RDATE, EXDATE, RECURRENCE-ID); expanding it is task 4.
//
//  RFC 5545 terms, for a Java/C# reader: a "content line" is `NAME;PARAM=V:VALUE`;
//  a long line is "folded" by inserting a line break followed by one space or
//  tab, which the reader removes ("unfolding") before anything else.
//

import Foundation

// MARK: - Output

/// A date or date-time value as written, resolved to an instant.
nonisolated struct ICSDateValue: Sendable, Equatable, Hashable {
    enum Form: Sendable, Equatable, Hashable {
        /// `…Z`
        case utc
        /// `TZID=` a zone `TimeZone` understands (IANA or a mapped Windows name).
        case zoned(String)
        /// `TZID=` an unknown name, read in the current zone (§20.3).
        case unknownZone(String)
        /// No `Z`, no `TZID`: the current zone (§20.3).
        case floating
        /// `VALUE=DATE`: all-day, floats (§20.4).
        case date
    }

    var form: Form
    /// The instant. For a `DATE`, the start of that day in the current zone.
    var instant: Date
    /// The zone recurrence expands in (§20.3: "in the event's own zone").
    var zone: TimeZone
    /// For a `DATE`: `yyyyMMdd` as written.
    var dateString: String?
    /// The value as written, without a trailing `Z` (`20260914T143000`):
    /// §20.2's content-mode test looks for it inside the UID.
    var raw: String = ""

    var isDate: Bool { form == .date }
}

/// One VEVENT, read but not yet derived (identity, profile, merge: task 4).
nonisolated struct ParsedVEvent: Sendable, Equatable {
    var uid: String?
    /// Unescaped, otherwise as written (whitespace is collapsed by task 4).
    var summary: String?
    var description: String?
    var location: String?
    var start: ICSDateValue
    /// `DTEND`, or `DTSTART + DURATION`, or `DTSTART` (+1 day for a date).
    var end: ICSDateValue
    var status: String?
    /// `ORGANIZER`'s `CN`, else the address after `mailto:` (§20.7).
    var organizer: String?
    var url: String?
    /// The `RRULE` value, unparsed (task 4 decides whether it is supported).
    var rrule: String?
    var rdates: [ICSDateValue] = []
    /// `RDATE;VALUE=PERIOD` was present (unsupported, §20.5).
    var hasPeriodRDate = false
    var exdates: [ICSDateValue] = []
    var recurrenceID: ICSDateValue?
    /// `RECURRENCE-ID;RANGE=…` (`THISANDFUTURE` is reported by task 4).
    var recurrenceRange: String?
    var sequence: Int = 0
    /// `LAST-MODIFIED`, else `DTSTAMP` (§20.2's tie-break).
    var stamp: Date?
    /// The physical line of `BEGIN:VEVENT`, 1-based.
    var line: Int
    /// Position among the text's VEVENTs, 0-based (the last tie-break).
    var index: Int
}

nonisolated struct ParsedCalendar: Sendable, Equatable {
    var events: [ParsedVEvent]
    /// Skipped VEVENTs, with line numbers.
    var problems: [ImportProblem]
    /// §20.3: unknown TZIDs and how many events used each, in first-seen
    /// order. Kept apart so a feed of many objects reports one line per zone.
    var unknownZones: [UnknownZoneUse] = []
    /// The zone floating and unknown times were read in.
    var currentZoneID: String = TimeZone.current.identifier

    init(events: [ParsedVEvent], problems: [ImportProblem],
         unknownZones: [UnknownZoneUse] = [], currentZoneID: String = TimeZone.current.identifier) {
        self.events = events; self.problems = problems
        self.unknownZones = unknownZones; self.currentZoneID = currentZoneID
    }

    /// Every problem, the unknown-zone lines last (§20.3's sentence).
    var allProblems: [ImportProblem] {
        problems + unknownZones.map { ICSParser.unknownZoneProblem($0, zoneID: currentZoneID) }
    }
}

nonisolated struct UnknownZoneUse: Sendable, Equatable {
    var tzid: String
    var count: Int
}

nonisolated enum ICSParseResult: Sendable, Equatable {
    case calendar(ParsedCalendar)
    case notACalendar
}

// MARK: - Parser

nonisolated enum ICSParser {
    /// §20.8.2: one object's `calendar-data` over 1 MB is not read.
    static let maxObjectBytes = 1_048_576

    /// §20.3: the Windows names with a known mapping.
    static let windowsZones: [String: String] = [
        "W. Europe Standard Time": "Europe/Berlin",
        "Central Europe Standard Time": "Europe/Budapest",
        "Romance Standard Time": "Europe/Paris",
        "GMT Standard Time": "Europe/London",
        "UTC": "UTC",
    ]

    /// §20.3: `{k} events used an unknown time zone ({tzid}) and were read in
    /// this Mac's time zone ({zone})` — `1 event … and was read` for one.
    static func unknownZoneProblem(_ use: UnknownZoneUse, zoneID: String) -> ImportProblem {
        let sentence = use.count == 1
            ? "1 event used an unknown time zone (\(use.tzid)) and was read in this Mac's time zone (\(zoneID))"
            : "\(use.count) events used an unknown time zone (\(use.tzid)) and were read in this Mac's time zone (\(zoneID))"
        return ImportProblem(sentence: sentence)
    }

    static func parse(_ data: Data, currentZone: TimeZone) -> ICSParseResult {
        guard data.count <= maxObjectBytes else { return .notACalendar }
        return parse(String(decoding: data, as: UTF8.self), currentZone: currentZone)
    }

    static func parse(_ text: String, currentZone: TimeZone) -> ICSParseResult {
        guard text.utf8.count <= maxObjectBytes, isCalendar(text) else { return .notACalendar }
        var reader = Reader(currentZone: currentZone)
        return .calendar(reader.read(unfold(text)))
    }

    /// §20.8.2 "A web page where data was expected": starts with
    /// `BEGIN:VCALENDAR` after an optional BOM and whitespace, and contains
    /// `END:VCALENDAR`. `Content-Type` is not consulted.
    static func isCalendar(_ text: String) -> Bool {
        var body = Substring(text)
        if body.first == "\u{FEFF}" { body = body.dropFirst() }
        body = body.drop { $0.isWhitespace }
        return body.uppercased().hasPrefix("BEGIN:VCALENDAR") && text.uppercased().contains("END:VCALENDAR")
    }

    /// One logical line with the physical line it started on.
    struct Line { var text: String; var number: Int }

    /// BOM, CRLF / LF / CR (mixed is fine), then unfolding.
    ///
    /// Swift note: a `Character` in Swift is a grapheme cluster, and "\r\n"
    /// is ONE Character — so splitting on `\n` alone would miss CRLF. Working
    /// on unicode scalars avoids that.
    static func unfold(_ text: String) -> [Line] {
        var physical: [String] = []
        var current = String.UnicodeScalarView()
        var scalars = Array(text.unicodeScalars)
        if scalars.first == "\u{FEFF}" { scalars.removeFirst() }
        var i = 0
        while i < scalars.count {
            let s = scalars[i]
            if s == "\r" || s == "\n" {
                physical.append(String(current)); current = String.UnicodeScalarView()
                if s == "\r", i + 1 < scalars.count, scalars[i + 1] == "\n" { i += 1 }
            } else {
                current.append(s)
            }
            i += 1
        }
        if !current.isEmpty { physical.append(String(current)) }

        var lines: [Line] = []
        for (offset, raw) in physical.enumerated() {
            if let first = raw.unicodeScalars.first, first == " " || first == "\t", !lines.isEmpty {
                lines[lines.count - 1].text += String(raw.unicodeScalars.dropFirst())
            } else if !raw.isEmpty {
                lines.append(Line(text: raw, number: offset + 1))
            }
        }
        return lines
    }

    /// `NAME;P=V;P="V:x":VALUE` → name (upper-cased), params, value. The value
    /// starts at the first `:` outside a quoted parameter value.
    static func split(_ line: String) -> (name: String, params: [String: String], value: String)? {
        var inQuotes = false
        var colon: String.Index?
        for index in line.indices {
            let c = line[index]
            if c == "\"" { inQuotes.toggle() }
            if c == ":" && !inQuotes { colon = index; break }
        }
        guard let colon else { return nil }
        let head = line[..<colon]
        let value = String(line[line.index(after: colon)...])
        var parts: [Substring] = []
        var start = head.startIndex
        inQuotes = false
        for index in head.indices {
            let c = head[index]
            if c == "\"" { inQuotes.toggle() }
            if c == ";" && !inQuotes { parts.append(head[start..<index]); start = head.index(after: index) }
        }
        parts.append(head[start...])
        let name = parts.removeFirst().trimmingCharacters(in: .whitespaces).uppercased()
        var params: [String: String] = [:]
        for part in parts {
            let pair = part.split(separator: "=", maxSplits: 1)
            guard pair.count == 2 else { continue }
            var v = String(pair[1])
            if v.hasPrefix("\""), v.hasSuffix("\""), v.count >= 2 { v = String(v.dropFirst().dropLast()) }
            params[pair[0].trimmingCharacters(in: .whitespaces).uppercased()] = v
        }
        return (name, params, value)
    }

    /// TEXT unescaping (§20.7): `\,` `\;` `\n` `\N` `\\`.
    static func unescape(_ value: String) -> String {
        var out = ""
        var escaping = false
        for c in value {
            if escaping {
                switch c {
                case "n", "N": out.append("\n")
                default: out.append(c)  // `\,` `\;` `\\` and anything else: the character
                }
                escaping = false
            } else if c == "\\" {
                escaping = true
            } else {
                out.append(c)
            }
        }
        if escaping { out.append("\\") }
        return out
    }

    /// `[+-]P[nW][nD][T[nH][nM][nS]]` → seconds.
    static func duration(_ text: String) -> TimeInterval? {
        var s = Substring(text.trimmingCharacters(in: .whitespaces).uppercased())
        var sign: Double = 1
        if s.first == "-" { sign = -1; s = s.dropFirst() } else if s.first == "+" { s = s.dropFirst() }
        guard s.first == "P" else { return nil }
        s = s.dropFirst()
        var total: Double = 0
        var number = ""
        var inTime = false
        var sawUnit = false
        for c in s {
            if c.isNumber { number.append(c); continue }
            if c == "T" { inTime = true; continue }
            guard let n = Double(number) else { return nil }
            number = ""
            sawUnit = true
            switch (c, inTime) {
            case ("W", false): total += n * 7 * 86_400
            case ("D", false): total += n * 86_400
            case ("H", true): total += n * 3600
            case ("M", true): total += n * 60
            case ("S", true): total += n
            default: return nil
            }
        }
        guard number.isEmpty, sawUnit else { return nil }
        return sign * total
    }

    // MARK: Reading components

    private struct Reader {
        let currentZone: TimeZone
        var problems: [ImportProblem] = []
        /// tzid → how many events used it (§20.3's one aggregated problem).
        var unknownZones: [UnknownZoneUse] = []

        init(currentZone: TimeZone) { self.currentZone = currentZone }

        mutating func read(_ lines: [Line]) -> ParsedCalendar {
            var events: [ParsedVEvent] = []
            var stack: [String] = []
            var props: [(name: String, params: [String: String], value: String, line: Int)] = []
            var veventLine = 0
            var index = 0
            for line in lines {
                guard let (name, params, value) = ICSParser.split(line.text) else { continue }
                if name == "BEGIN" {
                    let component = value.trimmingCharacters(in: .whitespaces).uppercased()
                    stack.append(component)
                    if component == "VEVENT" && stack.count == 2 { props = []; veventLine = line.number }
                    continue
                }
                if name == "END" {
                    let component = value.trimmingCharacters(in: .whitespaces).uppercased()
                    if component == "VEVENT" && stack.count == 2 && stack.last == "VEVENT" {
                        if let event = makeEvent(props, line: veventLine, index: index) { events.append(event) }
                        index += 1
                    }
                    if let at = stack.lastIndex(of: component) { stack.removeSubrange(at...) }
                    continue
                }
                // Only the VEVENT's own properties: not its VALARM's, not a
                // VTIMEZONE's (which has DTSTART and RRULE of its own).
                if stack.count == 2 && stack.last == "VEVENT" {
                    props.append((name, params, value, line.number))
                }
            }
            if stack.count >= 2 && stack[1] == "VEVENT" {
                problems.append(ImportProblem(
                    line: veventLine, sentence: "1 event couldn't be read",  // SPEC-GAP G-069
                    technical: "line \(veventLine): VEVENT not closed"))
            }
            return ParsedCalendar(events: events, problems: problems, unknownZones: unknownZones,
                                  currentZoneID: currentZone.identifier)
        }

        private mutating func skip(_ line: Int, _ technical: String, summary: String?) -> ParsedVEvent? {
            let title = summary.map { ICSParser.unescape($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            // SPEC-GAP G-069: §19.1 fixes the state body (`{k} of {n} events
            // couldn't be read…`) and the technical-line form, but not the
            // per-problem sentence for one skipped VEVENT. Placeholder until
            // the design agent rules.
            let sentence = (title?.isEmpty == false) ? "\(title!) couldn't be read" : "1 event couldn't be read"
            problems.append(ImportProblem(line: line, sentence: sentence, technical: "line \(line): \(technical)"))
            return nil
        }

        private mutating func makeEvent(
            _ props: [(name: String, params: [String: String], value: String, line: Int)],
            line: Int, index: Int
        ) -> ParsedVEvent? {
            func first(_ name: String) -> (params: [String: String], value: String, line: Int)? {
                props.first { $0.name == name }.map { ($0.params, $0.value, $0.line) }
            }
            let summary = first("SUMMARY")?.value
            guard let uid = first("UID")?.value.trimmingCharacters(in: .whitespaces), !uid.isEmpty else {
                return skip(line, "UID missing", summary: summary)
            }
            guard let dtstart = first("DTSTART") else {
                return skip(line, "DTSTART missing", summary: summary)
            }
            var usedUnknown: String?
            guard let start = dateValue(dtstart.value, params: dtstart.params, unknown: &usedUnknown) else {
                return skip(dtstart.line, "DTSTART can't be read", summary: summary)
            }
            var end: ICSDateValue
            if let dtend = first("DTEND") {
                guard let value = dateValue(dtend.value, params: dtend.params, unknown: &usedUnknown) else {
                    return skip(dtend.line, "DTEND can't be read", summary: summary)
                }
                guard value.instant >= start.instant else {
                    return skip(dtend.line, "DTEND before DTSTART", summary: summary)
                }
                end = value
            } else if let dur = first("DURATION") {
                guard let seconds = ICSParser.duration(dur.value) else {
                    return skip(dur.line, "DURATION can't be read", summary: summary)
                }
                guard seconds >= 0 else { return skip(dur.line, "negative DURATION", summary: summary) }
                end = start
                end.instant = start.isDate
                    ? Self.addDays(Int(seconds / 86_400), to: start.instant, zone: currentZone)
                    : start.instant.addingTimeInterval(seconds)
            } else {
                end = start
                if start.isDate { end.instant = Self.addDays(1, to: start.instant, zone: currentZone) }
            }
            if start.isDate, end.instant == start.instant {
                end.instant = Self.addDays(1, to: start.instant, zone: currentZone)
            }
            if let tzid = usedUnknown {
                if let at = unknownZones.firstIndex(where: { $0.tzid == tzid }) { unknownZones[at].count += 1 }
                else { unknownZones.append(UnknownZoneUse(tzid: tzid, count: 1)) }
            }

            var event = ParsedVEvent(uid: uid, summary: summary.map(ICSParser.unescape),
                                     start: start, end: end, line: line, index: index)
            event.description = first("DESCRIPTION").map { ICSParser.unescape($0.value) }
            event.location = first("LOCATION").map { ICSParser.unescape($0.value) }
            event.status = first("STATUS")?.value.trimmingCharacters(in: .whitespaces).uppercased()
            event.url = first("URL")?.value.trimmingCharacters(in: .whitespaces)
            if let organizer = first("ORGANIZER") {
                if let cn = organizer.params["CN"], !cn.isEmpty {
                    event.organizer = cn
                } else {
                    let v = organizer.value.trimmingCharacters(in: .whitespaces)
                    event.organizer = v.lowercased().hasPrefix("mailto:") ? String(v.dropFirst(7)) : v
                }
            }
            event.rrule = first("RRULE")?.value
            for prop in props where prop.name == "RDATE" {
                if prop.params["VALUE"]?.uppercased() == "PERIOD" { event.hasPeriodRDate = true; continue }
                for part in prop.value.split(separator: ",") {
                    var ignored: String?
                    if let v = dateValue(String(part), params: prop.params, unknown: &ignored) { event.rdates.append(v) }
                }
            }
            for prop in props where prop.name == "EXDATE" {
                for part in prop.value.split(separator: ",") {
                    var ignored: String?
                    if let v = dateValue(String(part), params: prop.params, unknown: &ignored) { event.exdates.append(v) }
                }
            }
            if let rid = first("RECURRENCE-ID") {
                var ignored: String?
                event.recurrenceID = dateValue(rid.value, params: rid.params, unknown: &ignored)
                event.recurrenceRange = rid.params["RANGE"]?.uppercased()
            }
            event.sequence = first("SEQUENCE").flatMap { Int($0.value.trimmingCharacters(in: .whitespaces)) } ?? 0
            var ignored: String?
            event.stamp = (first("LAST-MODIFIED") ?? first("DTSTAMP"))
                .flatMap { dateValue($0.value, params: $0.params, unknown: &ignored)?.instant }
            return event
        }

        /// `DATE` / `DATE-TIME` / `Z` / `TZID` / floating → an instant (§20.3, §20.4).
        func dateValue(_ raw: String, params: [String: String], unknown: inout String?) -> ICSDateValue? {
            let text = raw.trimmingCharacters(in: .whitespaces)
            let isDate = params["VALUE"]?.uppercased() == "DATE" || (text.count == 8 && !text.contains("T"))
            if isDate {
                guard text.count == 8, let c = Self.components(text, time: false) else { return nil }
                var cal = Calendar(identifier: .gregorian); cal.timeZone = currentZone
                guard let instant = cal.date(from: c) else { return nil }
                return ICSDateValue(form: .date, instant: instant, zone: currentZone, dateString: text, raw: text)
            }
            let isUTC = text.hasSuffix("Z") || text.hasSuffix("z")
            let body = isUTC ? String(text.dropLast()) : text
            guard body.count == 15, let c = Self.components(body, time: true) else { return nil }
            let zone: TimeZone
            let form: ICSDateValue.Form
            if isUTC {
                zone = TimeZone(identifier: "UTC")!
                form = .utc
            } else if let tzid = params["TZID"] {
                if let known = ICSParser.windowsZones[tzid].flatMap(TimeZone.init(identifier:))
                    ?? TimeZone(identifier: tzid) {
                    zone = known; form = .zoned(tzid)
                } else {
                    zone = currentZone; form = .unknownZone(tzid); unknown = tzid
                }
            } else {
                zone = currentZone; form = .floating
            }
            var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
            guard let instant = cal.date(from: c) else { return nil }
            return ICSDateValue(form: form, instant: instant, zone: zone, dateString: nil, raw: body)
        }

        /// `yyyyMMdd` or `yyyyMMdd'T'HHmmss` → validated components.
        static func components(_ text: String, time: Bool) -> DateComponents? {
            let chars = Array(text)
            func number(_ from: Int, _ count: Int) -> Int? {
                guard from + count <= chars.count else { return nil }
                let slice = chars[from..<(from + count)]
                guard slice.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
                return Int(String(slice))
            }
            guard let y = number(0, 4), let m = number(4, 2), let d = number(6, 2),
                  (1...12).contains(m), (1...31).contains(d) else { return nil }
            var c = DateComponents(year: y, month: m, day: d)
            if time {
                guard chars.count == 15, chars[8] == "T" || chars[8] == "t",
                      let h = number(9, 2), let mi = number(11, 2), let s = number(13, 2),
                      h < 24, mi < 60, s < 61 else { return nil }
                c.hour = h; c.minute = mi; c.second = min(s, 59)
            } else {
                c.hour = 0; c.minute = 0; c.second = 0
            }
            return c
        }

        static func addDays(_ days: Int, to date: Date, zone: TimeZone) -> Date {
            var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
            return cal.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(Double(days) * 86_400)
        }
    }
}
