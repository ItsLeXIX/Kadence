//
//  FeedDerivation.swift
//  Kadence
//
//  PHASE3-PLAN.md task 4 — parsed objects → `ExternalEvent`s. Pure.
//
//  components.md §20.2 (identity per VEVENT, the content key, the co-teaching
//  merge across objects AND calendars, exact-duplicate tie-breaks; hrefs and
//  ETags are not identity), §20.5 (the recurrence subset), §20.7 / §20.7.1
//  (generic mapping and the CIS profile), §20.8.4 (event and feed hashes).
//

import Foundation
import CryptoKit

// MARK: - ExternalEvent (§21.5)

/// One upstream event after identity, profile, merge and expansion. Exactly
/// §21.5's fields; the first fourteen are what the event hash covers.
nonisolated struct ExternalEvent: Sendable, Equatable {
    var externalID: String
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
    var location: String?
    var isOnline: Bool
    var courseCode: String?
    var group: String?
    var lecturers: [String]
    var kind: ImportKind
    var description: String?
    var link: String?
    var isCancelled: Bool
    var sequence: Int
    var stamp: Date?
}

/// One calendar object as fetched: where it came from, and its parse.
/// The hrefs are carried for problem lines only — never for identity.
nonisolated struct FeedObject: Sendable {
    var calendarHref: String
    var objectHref: String
    var calendar: ParsedCalendar
}

nonisolated struct DerivedFeed: Sendable, Equatable {
    var events: [ExternalEvent]
    var problems: [ImportProblem]
    /// Co-taught lectures merged (groups of two or more VEVENTs).
    var mergedCount: Int
    /// VEVENTs read, before the merge (§21.5 `objectCount`; the emptyFeed guard).
    var objectCount: Int
    /// §20.8.4 `duplicates`: VEVENTs replaced by a strict `SEQUENCE` / stamp
    /// winner with the same UID and start (§20.2). A tie is not one of them.
    var duplicateCount = 0
}

// MARK: - Formatting shared with the hashes

nonisolated enum ICSFormat {
    /// `yyyyMMdd'T'HHmmss'Z'` in UTC.
    static func utcStamp(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return String(format: "%04d%02d%02dT%02d%02d%02dZ", c.year ?? 0, c.month ?? 0, c.day ?? 0,
                      c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// `yyyyMMdd` of the day `date` falls on in `zone` (all-day values float).
    static func dateStamp(_ date: Date, zone: TimeZone) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let c = cal.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d%02d%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    static func stamp(_ date: Date, allDay: Bool, zone: TimeZone) -> String {
        allDay ? dateStamp(date, zone: zone) : utcStamp(date)
    }

    /// Whitespace runs → one space, trimmed (§20.2's `{summary}`/`{location}`).
    static func collapse(_ text: String) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func sha256Hex(_ text: String) -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - Hashes (§20.8.4)

nonisolated enum EventHash {
    static let unit = "\u{1F}"
    static let record = "\u{1E}"

    /// The fourteen upstream fields, in §20.8.4's order, joined by U+001F.
    static func string(externalID: String, title: String, start: Date, end: Date, isAllDay: Bool,
                       location: String?, isOnline: Bool, courseCode: String?, group: String?,
                       lecturers: [String], kind: ImportKind, description: String?, link: String?,
                       isCancelled: Bool, zone: TimeZone) -> String {
        [externalID, title,
         ICSFormat.stamp(start, allDay: isAllDay, zone: zone),
         ICSFormat.stamp(end, allDay: isAllDay, zone: zone),
         isAllDay ? "1" : "0",
         location ?? "",
         isOnline ? "1" : "0",
         courseCode ?? "",
         group ?? "",
         lecturers.joined(separator: record),
         kind.rawValue,
         description ?? "",
         link ?? "",
         isCancelled ? "1" : "0"].joined(separator: unit)
    }

    static func of(_ e: ExternalEvent, zone: TimeZone = .current) -> String {
        ICSFormat.sha256Hex(string(
            externalID: e.externalID, title: e.title, start: e.start, end: e.end, isAllDay: e.isAllDay,
            location: e.location, isOnline: e.isOnline, courseCode: e.courseCode, group: e.group,
            lecturers: e.lecturers, kind: e.kind, description: e.description, link: e.link,
            isCancelled: e.isCancelled, zone: zone))
    }

    /// The same hash from a stored `Event`'s upstream fields. Never stored.
    @MainActor
    static func of(_ e: Event, zone: TimeZone = .current) -> String {
        ICSFormat.sha256Hex(string(
            externalID: e.externalID ?? "", title: e.title, start: e.start, end: e.end, isAllDay: e.isAllDay,
            location: e.location?.name, isOnline: e.isOnline, courseCode: e.courseCode, group: e.group,
            lecturers: e.lecturers, kind: e.importKind, description: e.importedDescription, link: e.link,
            isCancelled: e.isCancelled, zone: zone))
    }
}

nonisolated enum FeedHash {
    /// SHA-256 hex of the event hashes, sorted ascending, joined by `\n`.
    static func of(_ eventHashes: [String]) -> String {
        ICSFormat.sha256Hex(eventHashes.sorted().joined(separator: "\n"))
    }
}

// MARK: - Derivation

nonisolated enum FeedDerivation {
    /// `today` is `startOfDay(today)` (the open-ended recurrence bound, §20.5);
    /// `zone` is the Mac's current zone (all-day dates float in it).
    static func derive(_ objects: [FeedObject], today: Date, zone: TimeZone) -> DerivedFeed {
        var problems: [ImportProblem] = []
        var zoneUses: [UnknownZoneUse] = []
        var all: [Located] = []
        for object in objects {
            let name = objectName(object.objectHref)
            for problem in object.calendar.problems {
                var p = problem
                if let name, let technical = p.technical { p.technical = "Object \(name), \(technical)" }
                problems.append(p)
            }
            for use in object.calendar.unknownZones {
                if let at = zoneUses.firstIndex(where: { $0.tzid == use.tzid }) { zoneUses[at].count += use.count }
                else { zoneUses.append(use) }
            }
            for event in object.calendar.events { all.append(Located(event: event, order: all.count, object: name)) }
        }
        let objectCount = all.count

        // 1. Exact duplicates (§20.2): same UID and same start (or same
        //    RECURRENCE-ID). The higher SEQUENCE wins, then the later stamp.
        //
        //    Amended 2026-10-10 (G-077; PHASE3-REVIEW fix 4): **a tie is not
        //    a duplicate.** When neither VEVENT wins on SEQUENCE or a stamp —
        //    always, on CIS, which sends neither — both go on to the merge
        //    (step 3), where the same content key makes them one event with
        //    their lecturers unioned. "The later one wins" threw the other
        //    VEVENT's lecturer away before the merge ever saw it, uncounted:
        //    the one path that could lose a co-teacher on real data.
        var kept: [String: [Located]] = [:]     // per key: the winner, or every VEVENT of a tie
        var keyOrder: [String] = []
        var duplicateCount = 0
        for item in all {
            let e = item.event
            let key = (e.uid ?? "") + "\u{1F}" + (e.recurrenceID.map { "R" + ICSFormat.utcStamp($0.instant) }
                                                   ?? "S" + ICSFormat.utcStamp(e.start.instant))
            guard let current = kept[key], let best = current.first else {
                kept[key] = [item]
                keyOrder.append(key)
                continue
            }
            switch precedence(item, over: best) {
            case .wins:
                duplicateCount += current.count
                kept[key] = [item]
            case .loses:
                duplicateCount += 1
            case .ties:
                // A series master or an override has a fixed identity
                // (`UID|start`) and never reaches the merge, so two of them
                // cannot both stand: the later VEVENT, as before.
                if isSeriesMember(e) || isSeriesMember(best.event) {
                    duplicateCount += 1
                    kept[key] = [item]
                } else {
                    var tied = item
                    tied.isTied = true
                    kept[key] = current.map { var t = $0; t.isTied = true; return t } + [tied]
                }
            }
        }
        let unique = keyOrder.flatMap { kept[$0] ?? [] }.sorted { $0.order < $1.order }

        // 2. Split masters and overrides by UID.
        var mastersByUID: [String: [Located]] = [:]
        var overridesByUID: [String: [Located]] = [:]
        for item in unique {
            let uid = item.event.uid ?? ""
            if item.event.recurrenceID != nil { overridesByUID[uid, default: []].append(item) }
            else { mastersByUID[uid, default: []].append(item) }
        }

        var candidates: [Candidate] = []
        var consumedOverrides = Set<Int>()   // `order` of overrides that matched an occurrence
        let horizon = Self.addDays(366, to: today, zone: zone)

        for item in unique where item.event.recurrenceID == nil {
            let e = item.event
            let uid = e.uid ?? ""
            let isRecurring = e.rrule != nil || !e.rdates.isEmpty || e.hasPeriodRDate
            if isRecurring {
                let overrides = overridesByUID[uid] ?? []
                guard let rule = Rule(e.rrule), !e.hasPeriodRDate else {
                    let title = ICSFormat.collapse(e.summary ?? "")
                    problems.append(ImportProblem(
                        line: e.line,
                        sentence: "1 repeating event uses a rule Kadence can't read yet: \(title.isEmpty ? "(No title)" : title)",
                        technical: technical(item, "RRULE \(e.rrule ?? "RDATE;VALUE=PERIOD")")))
                    for o in overrides { consumedOverrides.insert(o.order) }  // its overrides go with it
                    continue
                }
                for occurrence in expand(e, rule: rule, horizon: horizon, zone: zone) {
                    let originalStamp = e.start.isDate
                        ? ICSFormat.dateStamp(occurrence, zone: zone) : ICSFormat.utcStamp(occurrence)
                    let externalID = uid + "|" + originalStamp
                    if let override = overrides.first(where: { o in
                        guard let rid = o.event.recurrenceID else { return false }
                        return e.start.isDate
                            ? ICSFormat.dateStamp(rid.instant, zone: zone) == originalStamp
                            : rid.instant == occurrence
                    }) {
                        consumedOverrides.insert(override.order)
                        if override.event.recurrenceRange == "THISANDFUTURE" { problems.append(rangeProblem(override)) }
                        candidates.append(Candidate(item: override, start: override.event.start, end: override.event.end,
                                                    identity: .fixed(externalID), mergeable: false))
                    } else {
                        let length = e.end.instant.timeIntervalSince(e.start.instant)
                        var s = e.start; s.instant = occurrence
                        var en = e.end
                        en.instant = e.start.isDate
                            ? Self.addDays(Self.dayCount(e.start.instant, e.end.instant, zone: zone), to: occurrence, zone: zone)
                            : occurrence.addingTimeInterval(length)
                        candidates.append(Candidate(item: item, start: s, end: en,
                                                    identity: .fixed(externalID), mergeable: false))
                    }
                }
            } else {
                let masters = mastersByUID[uid] ?? []
                let ownStart = e.start.raw
                // §20.2 (amended 2026-10-10): tied VEVENTs are identified by
                // content — merged when their content keys agree, "both kept
                // as separate events, each under its content key" when not.
                if item.isTied || (!uid.isEmpty && !ownStart.isEmpty && uid.contains(ownStart)) {
                    candidates.append(Candidate(item: item, start: e.start, end: e.end, identity: .content, mergeable: true))
                } else if masters.count > 1, masters.allSatisfy({ $0.event.rrule == nil && $0.event.rdates.isEmpty }) {
                    let s = e.start.isDate ? (e.start.dateString ?? "") : ICSFormat.utcStamp(e.start.instant)
                    candidates.append(Candidate(item: item, start: e.start, end: e.end,
                                                identity: .uidMerged(uid + "|" + s), mergeable: true))
                } else {
                    candidates.append(Candidate(item: item, start: e.start, end: e.end,
                                                identity: .uidMerged(uid), mergeable: true))
                }
            }
        }
        // Overrides that matched no generated occurrence: imported on their own.
        for (uid, overrides) in overridesByUID {
            for o in overrides where !consumedOverrides.contains(o.order) {
                guard let rid = o.event.recurrenceID else { continue }
                if o.event.recurrenceRange == "THISANDFUTURE" { problems.append(rangeProblem(o)) }
                let stamp = rid.isDate ? (rid.dateString ?? "") : ICSFormat.utcStamp(rid.instant)
                candidates.append(Candidate(item: o, start: o.event.start, end: o.event.end,
                                            identity: .fixed(uid + "|" + stamp), mergeable: false))
            }
        }

        // 3. Map, then merge by content key (§20.2): every non-recurring
        //    VEVENT, across objects and calendars.
        var events: [ExternalEvent] = []
        var groups: [String: [(uid: String, event: ExternalEvent, mode: Candidate.Identity, order: Int)]] = [:]
        var groupOrder: [String] = []
        for c in candidates {
            let mapped = map(c, zone: zone)
            let key = contentKey(c, zone: zone)
            if c.mergeable {
                if groups[key] == nil { groupOrder.append(key) }
                groups[key, default: []].append((c.item.event.uid ?? "", mapped, c.identity, c.item.order))
            } else if case .fixed(let id) = c.identity {
                var occurrence = mapped
                occurrence.externalID = id
                events.append(occurrence)
            }
        }
        var mergedCount = 0
        for key in groupOrder {
            guard let members = groups[key] else { continue }
            if members.count == 1, let only = members.first {
                var event = only.event
                switch only.mode {
                case .content: event.externalID = key
                case .uidMerged(let id), .fixed(let id): event.externalID = id
                }
                events.append(event)
                continue
            }
            mergedCount += 1
            // Ascending UID, then the lecturer list joined by `/` (§20.2,
            // amended 2026-10-10): members that share one UID still have a
            // fixed order, so the result never depends on the feed's.
            let sorted = members.sorted {
                ($0.uid, $0.event.lecturers.joined(separator: "/"), $0.order)
                    < ($1.uid, $1.event.lecturers.joined(separator: "/"), $1.order)
            }
            var merged = sorted[0].event
            merged.externalID = key
            var lecturers: [String] = []
            for member in sorted {
                for name in member.event.lecturers where !lecturers.contains(name) { lecturers.append(name) }
            }
            merged.lecturers = lecturers
            merged.isCancelled = sorted.allSatisfy { $0.event.isCancelled }
            events.append(merged)
        }

        events.sort { ($0.start, $0.externalID) < ($1.start, $1.externalID) }
        problems += zoneUses.map {
            ICSParser.unknownZoneProblem($0, zoneID: objects.first?.calendar.currentZoneID ?? zone.identifier)
        }
        return DerivedFeed(events: events, problems: problems, mergedCount: mergedCount, objectCount: objectCount,
                           duplicateCount: duplicateCount)
    }

    // MARK: Pieces

    private struct Located {
        var event: ParsedVEvent
        var order: Int
        var object: String?
        /// Same UID and start as another VEVENT, with no SEQUENCE or stamp
        /// to choose between them (§20.2, amended 2026-10-10).
        var isTied = false
    }

    private struct Candidate {
        enum Identity { case content, uidMerged(String), fixed(String) }
        var item: Located
        var start: ICSDateValue
        var end: ICSDateValue
        var identity: Identity
        var mergeable: Bool
    }

    private static func objectName(_ href: String) -> String? {
        let trimmed = href.hasSuffix("/") ? String(href.dropLast()) : href
        guard let last = trimmed.split(separator: "/").last, !last.isEmpty else { return nil }
        return String(last).removingPercentEncoding ?? String(last)
    }

    private static func technical(_ item: Located, _ text: String) -> String {
        let line = "line \(item.event.line): \(text)"
        return item.object.map { "Object \($0), \(line)" } ?? line
    }

    private static func rangeProblem(_ item: Located) -> ImportProblem {
        let title = ICSFormat.collapse(item.event.summary ?? "")
        // SPEC-GAP G-069: §20.5 says RANGE=THISANDFUTURE "is treated as a
        // single-occurrence override and reported" without a sentence.
        return ImportProblem(line: item.event.line,
                             sentence: "1 change to a repeating event was applied to one occurrence only: \(title)",
                             technical: technical(item, "RECURRENCE-ID;RANGE=THISANDFUTURE"))
    }

    private enum Precedence { case wins, loses, ties }

    /// §20.2's tie-break: the higher SEQUENCE, then the later stamp. With
    /// neither, a tie — which is no longer settled by position in the feed.
    private static func precedence(_ a: Located, over b: Located) -> Precedence {
        if a.event.sequence != b.event.sequence { return a.event.sequence > b.event.sequence ? .wins : .loses }
        switch (a.event.stamp, b.event.stamp) {
        case let (x?, y?) where x != y: return x > y ? .wins : .loses
        case (.some, nil): return .wins
        case (nil, .some): return .loses
        default: return .ties
        }
    }

    /// A series master (`RRULE`/`RDATE`) or an override (`RECURRENCE-ID`).
    private static func isSeriesMember(_ e: ParsedVEvent) -> Bool {
        e.recurrenceID != nil || e.rrule != nil || !e.rdates.isEmpty || e.hasPeriodRDate
    }

    /// `{summary}|{location}|{startUTC}|{endUTC}` (§20.2).
    private static func contentKey(_ c: Candidate, zone: TimeZone) -> String {
        let summary = ICSFormat.collapse(c.item.event.summary ?? "")
        let location = ICSFormat.collapse(c.item.event.location ?? "")
        let allDay = c.start.isDate
        return [summary, location,
                allDay ? (c.start.dateString ?? ICSFormat.dateStamp(c.start.instant, zone: zone)) : ICSFormat.utcStamp(c.start.instant),
                allDay ? ICSFormat.dateStamp(c.end.instant, zone: zone) : ICSFormat.utcStamp(c.end.instant)]
            .joined(separator: "|")
    }

    /// §20.7 generic mapping, or §20.7.1's CIS profile when it matches.
    private static func map(_ c: Candidate, zone: TimeZone) -> ExternalEvent {
        let e = c.item.event
        let summary = ICSFormat.collapse(e.summary ?? "")
        var event = ExternalEvent(
            externalID: "", title: summary.isEmpty ? "(No title)" : summary,
            start: c.start.instant, end: c.end.instant, isAllDay: c.start.isDate,
            location: nil, isOnline: false, courseCode: nil, group: nil, lecturers: [],
            kind: .lecture, description: nil, link: nil,
            isCancelled: e.status == "CANCELLED", sequence: e.sequence, stamp: e.stamp)
        let location = e.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let profile = CISProfile(e) {
            event.courseCode = profile.courseCode
            event.title = profile.courseCode
            event.lecturers = profile.lecturers
            event.group = profile.group
            let room: String = (location?.isEmpty == false ? location : nil) ?? profile.room
            event.location = room.isEmpty ? nil : room
            event.isOnline = event.location.map(CISProfile.isWebinar) ?? false
            event.kind = profile.kind
            event.description = nil
        } else {
            event.location = location?.isEmpty == false ? location : nil
            let description = e.description
            event.description = description?.isEmpty == false ? description : nil
            event.lecturers = e.organizer.map { [$0] } ?? []
            event.link = e.url?.isEmpty == false ? e.url : nil
        }
        return event
    }

    // MARK: Recurrence (§20.5)

    struct Rule {
        enum Frequency { case daily, weekly }
        var frequency: Frequency
        var interval = 1
        var count: Int?
        var until: String?
        var byDay: [Int] = []       // Calendar weekdays, 1 = Sunday
        var weekStart = 2           // Monday

        static let days = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]

        /// nil = unsupported (anything outside the subset, never a guess). A
        /// missing RRULE (RDATE only) is a rule with no generated repeats.
        init?(_ text: String?) {
            // RDATE only (no RRULE): DTSTART is the one generated occurrence.
            guard let text else { frequency = .daily; count = 1; return }
            var frequency: Frequency?
            for part in text.split(separator: ";") {
                let pair = part.split(separator: "=", maxSplits: 1).map { String($0).uppercased() }
                guard pair.count == 2 else { return nil }
                switch pair[0] {
                case "FREQ":
                    switch pair[1] { case "DAILY": frequency = .daily; case "WEEKLY": frequency = .weekly; default: return nil }
                case "INTERVAL": guard let n = Int(pair[1]), n > 0 else { return nil }; interval = n
                case "COUNT": guard let n = Int(pair[1]), n > 0 else { return nil }; count = n
                case "UNTIL": until = pair[1]
                case "BYDAY":
                    for d in pair[1].split(separator: ",") {
                        guard let day = Self.days[String(d)] else { return nil }  // an ordinal (2MO) fails here
                        byDay.append(day)
                    }
                case "WKST": guard let d = Self.days[pair[1]] else { return nil }; weekStart = d
                default: return nil
                }
            }
            guard let frequency else { return nil }
            self.frequency = frequency
        }
    }

    /// The occurrence starts (original starts), RDATEs added, EXDATEs removed.
    private static func expand(_ e: ParsedVEvent, rule: Rule, horizon: Date, zone: TimeZone) -> [Date] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = e.start.isDate ? zone : e.start.zone
        let start = e.start.instant
        let time = cal.dateComponents([.hour, .minute, .second], from: start)
        let untilDate: Date? = rule.until.flatMap { text in
            if text.count == 8, let c = DateComponents.ymd(text) {
                var dayCal = cal
                dayCal.timeZone = e.start.isDate ? zone : e.start.zone
                return dayCal.date(from: c).map { addDays(1, to: $0, zone: dayCal.timeZone).addingTimeInterval(-1) }
            }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = TimeZone(identifier: "UTC")
            f.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
            return f.date(from: text)
        }
        let openEnded = rule.count == nil && untilDate == nil
        let safety = 5000
        var result: [Date] = []

        func onDay(_ day: Date) -> Date? {
            cal.date(bySettingHour: time.hour ?? 0, minute: time.minute ?? 0, second: time.second ?? 0, of: day)
        }
        func accept(_ d: Date) -> Bool {   // false = stop generating
            if let u = untilDate, d > u { return false }
            if openEnded, d >= horizon { return false }
            if let c = rule.count, result.count >= c { return false }
            if result.count >= safety { return false }
            result.append(d)
            return true
        }

        let firstDay = cal.startOfDay(for: start)
        switch rule.frequency {
        case .daily:
            var n = 0
            while n < safety * 7 {
                guard let day = cal.date(byAdding: .day, value: n * rule.interval, to: firstDay),
                      let d = onDay(day) else { break }
                n += 1
                if !rule.byDay.isEmpty, !rule.byDay.contains(cal.component(.weekday, from: d)) { continue }
                if d < start { continue }
                if !accept(d) { break }
            }
        case .weekly:
            let days = rule.byDay.isEmpty ? [cal.component(.weekday, from: start)] : rule.byDay
            // The week containing DTSTART, starting at WKST.
            let weekday = cal.component(.weekday, from: firstDay)
            let back = (weekday - rule.weekStart + 7) % 7
            guard let weekStart = cal.date(byAdding: .day, value: -back, to: firstDay) else { break }
            let offsets = days.map { ($0 - rule.weekStart + 7) % 7 }.sorted()
            var w = 0
            outer: while true {
                for offset in offsets {
                    guard let day = cal.date(byAdding: .day, value: w * 7 * rule.interval + offset, to: weekStart),
                          let d = onDay(day) else { break outer }
                    if d < start { continue }
                    if !accept(d) { break outer }
                }
                w += 1
            }
        }
        for r in e.rdates where !result.contains(r.instant) { result.append(r.instant) }
        result.removeAll { d in
            e.exdates.contains { x in
                x.isDate ? ICSFormat.dateStamp(x.instant, zone: zone) == ICSFormat.dateStamp(d, zone: zone)
                         : x.instant == d
            }
        }
        return result.sorted()
    }

    static func addDays(_ days: Int, to date: Date, zone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        return cal.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(Double(days) * 86_400)
    }

    static func dayCount(_ from: Date, _ to: Date, zone: TimeZone) -> Int {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        return cal.dateComponents([.day], from: from, to: to).day ?? 1
    }
}

// MARK: - The CIS profile (§20.7.1)

nonisolated struct CISProfile {
    var courseCode: String
    var lecturers: [String]
    var group: String
    var room: String

    /// Matches when DESCRIPTION, unescaped and split on line breaks (trailing
    /// empty lines dropped), has exactly four lines, and line 1 trimmed equals
    /// SUMMARY's first whitespace-separated token. Per event, never per feed.
    init?(_ e: ParsedVEvent) {
        guard let description = e.description, let summary = e.summary else { return nil }
        var lines = description.components(separatedBy: "\n").map { $0.replacingOccurrences(of: "\r", with: "") }
        while let last = lines.last, last.trimmingCharacters(in: .whitespaces).isEmpty { lines.removeLast() }
        guard lines.count == 4 else { return nil }
        let code = lines[0].trimmingCharacters(in: .whitespaces)
        guard !code.isEmpty,
              let token = summary.split(whereSeparator: { $0.isWhitespace }).first,
              code == String(token) else { return nil }
        courseCode = code
        lecturers = lines[1].split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        group = lines[2].trimmingCharacters(in: .whitespaces)
        room = lines[3].trimmingCharacters(in: .whitespaces)
    }

    /// `EXAM` suffix → exam; anything else (or no `-`) → lecture, no problem.
    var kind: ImportKind {
        guard let dash = courseCode.lastIndex(of: "-") else { return .lecture }
        return courseCode[courseCode.index(after: dash)...].uppercased() == "EXAM" ? .exam : .lecture
    }

    /// `WEBINAR` + digits, case-insensitive.
    static func isWebinar(_ location: String) -> Bool {
        let upper = location.uppercased()
        guard upper.hasPrefix("WEBINAR") else { return false }
        let digits = upper.dropFirst(7)
        return !digits.isEmpty && digits.allSatisfy { $0.isASCII && $0.isNumber }
    }
}

private extension DateComponents {
    nonisolated static func ymd(_ text: String) -> DateComponents? {
        guard text.count == 8, let y = Int(text.prefix(4)), let m = Int(text.dropFirst(4).prefix(2)),
              let d = Int(text.suffix(2)) else { return nil }
        return DateComponents(year: y, month: m, day: d)
    }
}
