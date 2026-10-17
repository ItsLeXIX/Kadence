//
//  MoodleProfile.swift
//  Kadence
//
//  Phase 3 slice 3 (PHASE3-SLICE3-PLAN.md task 3) — components.md §35, §34.7.
//  Reading a Moodle calendar export with the `moodle` profile: bytes →
//  `MoodleItem`s, problems and counts. Pure: no I/O, no clock, no store; the
//  zone (the Mac's, in the app) is injected.
//
//  What Moodle 4.5 sends (verified on Parsa's real feed, 16 Oct 2026): CRLF;
//  continuation lines start with a TAB and are cut at 75 characters; every
//  folded property is followed by a line holding only a TAB; no VTIMEZONE,
//  every time UTC with `Z`; `DTSTART == DTEND`; `DTSTAMP` is the fetch time;
//  `CATEGORIES` may carry HTML entities as well as iCalendar escapes
//  (`FK CS&amp\;AM - …`).
//

import Foundation

// MARK: - Output

/// One Moodle item as the profile reads it (§35). Every field the sync
/// writes is here; the derived ones (`title`, `kind`, `wording`,
/// `courseCode`) are functions of `upstreamTitle` and `courseCategory`.
nonisolated struct MoodleItem: Sendable, Equatable {
    /// The `UID` (`900005@moodle.technikum-wien.at`) — §35.2's uid mode.
    var externalID: String
    /// §35.3: `SUMMARY` unescaped, decoded, whitespace collapsed.
    var upstreamTitle: String
    /// §35.3 / §35.4: `upstreamTitle` without its kind affix.
    var title: String
    var kind: ImportKind
    var wording: MomentWording?
    var start: Date
    var end: Date
    var isAllDay: Bool
    /// §35.5: the first `CATEGORIES` value, as decoded (`/id` included).
    var courseCategory: String?
    /// §35.5: the code token of a course shortname (`SWEN3`), else nil.
    var courseCode: String?
    /// §35.5: the term token (`WS2026`) when there is a code.
    var term: String?
    /// §35.3: `DESCRIPTION` unescaped and decoded; nil when empty.
    var description: String?
    /// For §35.2's duplicate rule only; not stored, not hashed.
    var lastModified: Date?
    /// The physical line of `BEGIN:VEVENT`, 1-based.
    var line: Int

    /// §32.1: `DTSTART == DTEND` on a timed item — drawn in the all-day row.
    var isMoment: Bool { !isAllDay && start == end }

    /// §34.7's item hash.
    var hash: String {
        MoodleHash.item(externalID: externalID, upstreamTitle: upstreamTitle, start: start, end: end,
                        isAllDay: isAllDay, courseCategory: courseCategory, description: description)
    }
}

nonisolated struct MoodleFeed: Sendable, Equatable {
    /// After §35.2's duplicate rule, in feed order.
    var items: [MoodleItem]
    /// Skipped VEVENTs, invalid text, conflicting duplicates (§35.1, §35.2).
    var problems: [ImportProblem]
    /// Every `BEGIN:VEVENT` read, before skipping and dedupe (`vevents` in
    /// the log line; `{n}` of `partialImport`).
    var veventCount: Int
    /// §35.2: copies dropped for a repeated `UID`.
    var duplicates: Int

    var deadlines: Int { items.filter { $0.kind == .deadline }.count }
    var openings: Int { items.filter { $0.kind == .opening }.count }
    var notices: Int { items.filter { $0.kind == .notice }.count }
}

nonisolated enum MoodleReadResult: Sendable, Equatable {
    case calendar(MoodleFeed)
    /// §34.2: a `200` whose body is not a calendar.
    case notACalendar
}

// MARK: - Hashes (§34.7)

nonisolated enum MoodleHash {
    /// §34.7: the profile tag. A build that changes §35's rules bumps it, so
    /// every item hash changes once and the next sync re-derives every item
    /// from today on.
    static let profileTag = "moodle-1"

    /// SHA-256 hex over §34.7's nine fields joined by U+001F. `DTSTAMP`,
    /// `LAST-MODIFIED`, `CLASS` and `SEQUENCE` are not in it.
    static func item(externalID: String, upstreamTitle: String, start: Date, end: Date, isAllDay: Bool,
                     courseCategory: String?, description: String?, profileTag: String = profileTag,
                     zone: TimeZone = .current) -> String {
        ICSFormat.sha256Hex([
            profileTag,
            externalID,
            upstreamTitle,
            ICSFormat.stamp(start, allDay: isAllDay, zone: zone),
            ICSFormat.stamp(end, allDay: isAllDay, zone: zone),
            isAllDay ? "1" : "0",
            courseCategory ?? "",
            description ?? "",
            "",  // location: Moodle sends none
        ].joined(separator: EventHash.unit))
    }

    /// The same hash from a stored `Event`'s fields (§34.7: computed when
    /// compared, never stored).
    @MainActor
    static func of(_ e: Event, zone: TimeZone = .current) -> String {
        item(externalID: e.externalID ?? "", upstreamTitle: e.upstreamTitle ?? e.title, start: e.start, end: e.end,
             isAllDay: e.isAllDay, courseCategory: e.courseCategory, description: e.importedDescription, zone: zone)
    }

    /// §34.7 "Feed hash" — §20.8.4's, over the items whose start is in the
    /// write window (on or after `windowStart`).
    static func feed(_ items: [MoodleItem], from windowStart: Date) -> String {
        FeedHash.of(items.filter { $0.start >= windowStart }.map(\.hash))
    }
}

// MARK: - The reader

nonisolated enum MoodleProfile {

    /// §35.4: the eight verified wordings, prefix first, then suffixes in the
    /// table's order (` ist fällig.` before ` ist fällig`).
    static let prefixes: [(String, ImportKind, MomentWording)] = [
        ("Anmeldeende: ", .deadline, .registrationEnds),
    ]
    static let suffixes: [(String, ImportKind, MomentWording)] = [
        (" is due", .deadline, .due),
        (" ist fällig.", .deadline, .due),
        (" ist fällig", .deadline, .due),
        (" closes", .deadline, .closes),
        (" endet", .deadline, .closes),
        (" opens", .opening, .opens),
        (" beginnt", .opening, .opens),
    ]

    static func read(_ data: Data, zone: TimeZone) -> MoodleReadResult {
        // §34.2: after an optional BOM and whitespace it starts
        // `BEGIN:VCALENDAR` and contains `END:VCALENDAR`.
        guard ICSParser.isCalendar(String(decoding: data, as: UTF8.self)) else { return .notACalendar }
        var reader = Reader(zone: zone)
        return .calendar(reader.read(unfold(data)))
    }

    // MARK: §35.1 lines

    /// One logical line: its bytes after unfolding, and the physical line it
    /// started on.
    struct RawLine: Equatable {
        var bytes: [UInt8]
        var number: Int
    }

    /// **Unfold on bytes, then decode** (§35.1). A line break (`CRLF`, or a
    /// bare `LF`) followed by one space or one TAB is removed together with
    /// that one character. Moodle's lone-TAB line unfolds to nothing. A UTF-8
    /// BOM is skipped.
    static func unfold(_ data: Data) -> [RawLine] {
        var bytes = [UInt8](data)
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) { bytes.removeFirst(3) }
        var lines: [RawLine] = []
        var current: [UInt8] = []
        var physical = 1
        var startedOn = 1
        var i = 0
        while i < bytes.count {
            let b = bytes[i]
            if b == 0x0D || b == 0x0A {
                let breakLength = (b == 0x0D && i + 1 < bytes.count && bytes[i + 1] == 0x0A) ? 2 : 1
                let next = i + breakLength
                physical += 1
                if next < bytes.count, bytes[next] == 0x20 || bytes[next] == 0x09 {
                    i = next + 1  // a fold: the break and the one character go
                    continue
                }
                if !current.isEmpty { lines.append(RawLine(bytes: current, number: startedOn)) }
                current = []
                startedOn = physical
                i = next
                continue
            }
            current.append(b)
            i += 1
        }
        if !current.isEmpty { lines.append(RawLine(bytes: current, number: startedOn)) }
        return lines
    }

    // MARK: §35.3 text

    /// iCalendar unescaping: `\n` `\N` → line break, `\,` `\;` `\\` → the
    /// character; **any other `\x` kept as written**.
    static func unescape(_ value: String) -> String {
        var out = ""
        var iterator = value.makeIterator()
        while let c = iterator.next() {
            guard c == "\\" else { out.append(c); continue }
            guard let next = iterator.next() else { out.append("\\"); break }
            switch next {
            case "n", "N": out.append("\n")
            case ",", ";", "\\": out.append(next)
            default: out.append("\\"); out.append(next)
            }
        }
        return out
    }

    /// HTML entities, after unescaping: `&amp;` `&lt;` `&gt;` `&quot;`
    /// `&#39;` `&apos;` and numeric `&#NNN;` / `&#xHH;`; nothing else. One
    /// left-to-right pass, so `&amp;lt;` decodes to `&lt;`, never `<`.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        let named: [String: String] = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'"]
        var out = ""
        var rest = Substring(text)
        while let amp = rest.firstIndex(of: "&") {
            out += rest[..<amp]
            let after = rest[rest.index(after: amp)...]
            if let semi = after.firstIndex(of: ";"), after.distance(from: after.startIndex, to: semi) <= 10 {
                let name = String(after[..<semi])
                var decoded: String?
                if let value = named[name] {
                    decoded = value
                } else if name.hasPrefix("#x") || name.hasPrefix("#X") {
                    decoded = UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                } else if name.hasPrefix("#") {
                    decoded = UInt32(name.dropFirst(1), radix: 10).flatMap(Unicode.Scalar.init).map { String(Character($0)) }
                }
                if let decoded, !name.isEmpty {
                    out += decoded
                    rest = after[after.index(after: semi)...]
                    continue
                }
            }
            out.append("&")
            rest = after
        }
        out += rest
        return out
    }

    /// §35.3: unescape, then decode.
    static func text(_ value: String) -> String { decodeEntities(unescape(value)) }

    /// §35.3 `upstreamTitle`: whitespace runs → one space, trimmed; empty →
    /// `(No title)`.
    static func upstreamTitle(summary: String?) -> String {
        let collapsed = ICSFormat.collapse(text(summary ?? ""))
        return collapsed.isEmpty ? "(No title)" : collapsed
    }

    /// §35.3 `importedDescription`: line breaks kept, trailing whitespace of
    /// each line trimmed; nil when empty.
    static func description(_ value: String?) -> String? {
        guard let value else { return nil }
        let lines = text(value).split(separator: "\n", omittingEmptySubsequences: false).map { line in
            String(line.reversed().drop { $0.isWhitespace }.reversed())
        }
        let joined = lines.joined(separator: "\n")
        return joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : joined
    }

    // MARK: §35.4 kinds

    /// The kind, the wording and the displayed title of an `upstreamTitle`.
    static func kind(of upstreamTitle: String) -> (kind: ImportKind, wording: MomentWording?, title: String) {
        for (prefix, kind, wording) in prefixes where upstreamTitle.hasPrefix(prefix) {
            let rest = String(upstreamTitle.dropFirst(prefix.count))
            // A match that would leave an empty title is a notice.
            if rest.trimmingCharacters(in: .whitespaces).isEmpty { break }
            return (kind, wording, rest)
        }
        for (suffix, kind, wording) in suffixes where upstreamTitle.hasSuffix(suffix) {
            let rest = String(upstreamTitle.dropLast(suffix.count))
            if rest.trimmingCharacters(in: .whitespaces).isEmpty { break }
            return (kind, wording, rest)
        }
        return (.notice, nil, upstreamTitle)
    }

    // MARK: §35.5 course and category

    /// `courseCategory`: the first comma-separated value of `CATEGORIES`
    /// after §35.3, as decoded; nil when absent or empty.
    static func courseCategory(_ categories: String?) -> String? {
        guard let categories else { return nil }
        let first = text(categories).split(separator: ",", omittingEmptySubsequences: false).first
            .map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        return first.isEmpty ? nil : first
    }

    /// The shortname: `courseCategory` without a trailing `/` + digits.
    static func shortname(_ category: String) -> String {
        guard let slash = category.lastIndex(of: "/") else { return category }
        let tail = category[category.index(after: slash)...]
        return !tail.isEmpty && tail.allSatisfy({ $0.isASCII && $0.isNumber }) ? String(category[..<slash]) : category
    }

    /// §35.5: `(code, term)` when the shortname is
    /// `…-{term}-{code}-{lang}` (`WS`/`SS` + 4 digits, two capitals).
    static func course(_ category: String?) -> (code: String, term: String)? {
        guard let category else { return nil }
        let parts = shortname(category).split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 3 else { return nil }
        let term = parts[parts.count - 3], code = parts[parts.count - 2], language = parts[parts.count - 1]
        guard term.wholeMatch(of: /(WS|SS)[0-9]{4}/) != nil,
              language.wholeMatch(of: /[A-Z]{2}/) != nil,
              !code.isEmpty else { return nil }
        return (code, term)
    }

    // MARK: Reading components

    private struct Property {
        var name: String
        var params: [String: String]
        var value: String
        var line: Int
    }

    private struct Reader {
        let zone: TimeZone
        var problems: [ImportProblem] = []
        var veventCount = 0

        init(zone: TimeZone) { self.zone = zone }

        mutating func read(_ lines: [RawLine]) -> MoodleFeed {
            var read: [(item: MoodleItem, invalidLine: Int?)] = []
            var depth: [String] = []
            var props: [Property] = []
            var invalidLine: Int?
            var veventLine = 0
            for raw in lines {
                // §35.1: invalid UTF-8 is decoded with U+FFFD; the VEVENT is kept
                // and reported once.
                let valid = String(bytes: raw.bytes, encoding: .utf8)
                let text = valid ?? String(decoding: raw.bytes, as: UTF8.self)
                guard let (name, params, value) = ICSParser.split(text) else { continue }
                if name == "BEGIN" {
                    let component = value.trimmingCharacters(in: .whitespaces).uppercased()
                    depth.append(component)
                    if component == "VEVENT" && depth.count == 2 {
                        props = []; invalidLine = nil; veventLine = raw.number; veventCount += 1
                    }
                    continue
                }
                if name == "END" {
                    let component = value.trimmingCharacters(in: .whitespaces).uppercased()
                    if component == "VEVENT" && depth.count == 2 && depth.last == "VEVENT" {
                        if let item = makeItem(props, line: veventLine) { read.append((item, invalidLine)) }
                    }
                    if let at = depth.lastIndex(of: component) {
                        if at == 0, depth.count >= 2, depth[1] == "VEVENT" { unclosed(veventLine) }
                        depth.removeSubrange(at...)
                    }
                    continue
                }
                if depth.count == 2 && depth.last == "VEVENT" {
                    if valid == nil, invalidLine == nil { invalidLine = raw.number }
                    props.append(Property(name: name, params: params, value: value, line: raw.number))
                }
            }
            if depth.count >= 2 && depth[1] == "VEVENT" { unclosed(veventLine) }

            for (item, line) in read {
                guard let line else { continue }
                problems.append(ImportProblem(line: line,
                                              sentence: "\(item.upstreamTitle) contains characters Kadence couldn't read.",
                                              technical: "Line \(line): invalid UTF-8"))
            }
            let (items, duplicates) = dedupe(read.map(\.item))
            return MoodleFeed(items: items, problems: problems, veventCount: veventCount, duplicates: duplicates)
        }

        /// §19.3: `BEGIN:VEVENT` never closed.
        private mutating func unclosed(_ line: Int) {
            problems.append(ImportProblem(line: line, sentence: ProblemSentence.unreadable,
                                          technical: "Line \(line): VEVENT not closed"))
        }

        /// §35.2 "The same UID twice": the later `LAST-MODIFIED` wins; a tie
        /// with equal hashes keeps one; a tie that differs keeps the copy
        /// whose hash sorts lower and reports one problem.
        private mutating func dedupe(_ items: [MoodleItem]) -> ([MoodleItem], Int) {
            var kept: [MoodleItem] = []
            var at: [String: Int] = [:]
            var duplicates = 0
            for item in items {
                guard let index = at[item.externalID] else {
                    at[item.externalID] = kept.count
                    kept.append(item)
                    continue
                }
                duplicates += 1
                let other = kept[index]
                let a = item.lastModified ?? .distantPast, b = other.lastModified ?? .distantPast
                if a != b {
                    if a > b { kept[index] = item }
                } else if item.hash != other.hash {
                    if item.hash < other.hash { kept[index] = item }
                    problems.append(ImportProblem(
                        line: item.line,
                        sentence: "\(other.upstreamTitle) is listed twice with different details; one copy was used.",
                        technical: "Line \(item.line): UID \(item.externalID) repeated"))
                }
            }
            return (kept, duplicates)
        }

        private mutating func skip(_ line: Int, _ reason: ProblemSentence.Skip, technical: String,
                                   summary: String?) -> MoodleItem? {
            let title = summary.map { MoodleProfile.upstreamTitle(summary: $0) } ?? "An event"
            problems.append(ImportProblem(line: line, sentence: reason.sentence(title: title),
                                          technical: "Line \(line): \(technical)"))
            return nil
        }

        private mutating func makeItem(_ props: [Property], line: Int) -> MoodleItem? {
            func first(_ name: String) -> Property? { props.first { $0.name == name } }
            let summary = first("SUMMARY")?.value
            guard let uid = first("UID")?.value.trimmingCharacters(in: .whitespaces), !uid.isEmpty else {
                return skip(line, .noIdentifier, technical: "no UID", summary: summary)
            }
            guard let dtstart = first("DTSTART") else {
                return skip(line, .noStart, technical: "DTSTART", summary: summary)
            }
            guard let start = date(dtstart) else {
                return skip(dtstart.line, .noStart, technical: "DTSTART", summary: summary)
            }
            // §35.4: `DTEND` absent → a moment.
            var end = start
            if let dtend = first("DTEND") {
                guard let value = date(dtend), value.isAllDay == start.isAllDay else {
                    return skip(dtend.line, .unreadable, technical: "DTEND", summary: summary)
                }
                guard value.instant >= start.instant else {
                    return skip(dtend.line, .endsBeforeStart, technical: "DTEND before DTSTART", summary: summary)
                }
                end = value
            }
            if start.isAllDay, end.instant == start.instant {
                end.instant = ICSFormatDays.add(1, to: start.instant, zone: zone)
            }

            let upstream = MoodleProfile.upstreamTitle(summary: summary)
            let (kind, wording, title) = MoodleProfile.kind(of: upstream)
            let category = MoodleProfile.courseCategory(first("CATEGORIES")?.value)
            let course = MoodleProfile.course(category)
            return MoodleItem(
                externalID: uid, upstreamTitle: upstream, title: title, kind: kind, wording: wording,
                start: start.instant, end: end.instant, isAllDay: start.isAllDay,
                courseCategory: category, courseCode: course?.code, term: course?.term,
                description: MoodleProfile.description(first("DESCRIPTION")?.value),
                lastModified: first("LAST-MODIFIED").flatMap { date($0)?.instant }, line: line)
        }

        /// `…Z`, `VALUE=DATE` (all-day, floating in the zone), `TZID=` or
        /// floating (read in the zone, §20.3).
        private func date(_ property: Property) -> (instant: Date, isAllDay: Bool)? {
            let text = property.value.trimmingCharacters(in: .whitespaces)
            let isDate = property.params["VALUE"]?.uppercased() == "DATE" || (text.count == 8 && !text.contains("T"))
            let utc = text.hasSuffix("Z") || text.hasSuffix("z")
            let body = utc ? String(text.dropLast()) : text
            let pattern = isDate ? "yyyyMMdd" : "yyyyMMdd'T'HHmmss"
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.dateFormat = pattern
            formatter.isLenient = false
            if utc && !isDate {
                formatter.timeZone = TimeZone(identifier: "UTC")
            } else if !isDate, let tzid = property.params["TZID"], let named = TimeZone(identifier: tzid) {
                formatter.timeZone = named
            } else {
                formatter.timeZone = zone
            }
            guard body.count == (isDate ? 8 : 15), let instant = formatter.date(from: body) else { return nil }
            return (instant, isDate)
        }
    }
}

/// Calendar-day arithmetic for all-day values (they float in the zone).
nonisolated enum ICSFormatDays {
    static func add(_ days: Int, to date: Date, zone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(byAdding: .day, value: days, to: date) ?? date
    }
}
