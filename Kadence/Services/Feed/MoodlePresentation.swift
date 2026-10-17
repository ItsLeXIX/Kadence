//
//  MoodlePresentation.swift
//  Kadence
//
//  Phase 3 slice 3 (PHASE3-SLICE3-PLAN.md task 4) — components.md §36
//  (pairing), §37.1–§37.4 (the pill's label, sort, hover help, VoiceOver, the
//  inspector's values), §35.5 (the timetable mapping) and §39 (which
//  deadlines the menu bar shows). Pure: the zone and calendar are injected,
//  no clock is read, nothing is stored — pairing and the mapping are derived
//  each time they are shown (§36, §35.5).
//

import Foundation
import CoreGraphics

// MARK: - The item

/// A Moodle item as every surface reads it: an `Event` of a feed source, or a
/// freshly read `MoodleItem` (the connect sheet, tests).
nonisolated struct MomentItem: Sendable, Equatable, Identifiable {
    var id: UUID
    var externalID: String
    var sourceID: String
    /// §35.3 / §35.4: the displayed title.
    var title: String
    /// §35.3: the raw title.
    var upstreamTitle: String
    var kind: ImportKind
    var wording: MomentWording?
    var start: Date
    var end: Date
    var isAllDay: Bool
    var courseCategory: String?
    var courseCode: String?
    var description: String?
    var isDone: Bool
    /// §38: the start when it was marked done.
    var markedDoneDueAt: Date?

    /// §32.1.
    var isMoment: Bool { !isAllDay && start == end }

    /// §38: the moved-after-done condition.
    var dueTimeChangedAfterDone: Bool { isDone && markedDoneDueAt != nil && markedDoneDueAt != start }

    init(id: UUID = UUID(), externalID: String, sourceID: String, title: String, upstreamTitle: String,
         kind: ImportKind, wording: MomentWording?, start: Date, end: Date, isAllDay: Bool = false,
         courseCategory: String? = nil, courseCode: String? = nil, description: String? = nil,
         isDone: Bool = false, markedDoneDueAt: Date? = nil) {
        self.id = id; self.externalID = externalID; self.sourceID = sourceID; self.title = title
        self.upstreamTitle = upstreamTitle; self.kind = kind; self.wording = wording; self.start = start
        self.end = end; self.isAllDay = isAllDay; self.courseCategory = courseCategory
        self.courseCode = courseCode; self.description = description; self.isDone = isDone
        self.markedDoneDueAt = markedDoneDueAt
    }

    init(_ item: MoodleItem, id: UUID = UUID(), sourceID: String, isDone: Bool = false) {
        self.init(id: id, externalID: item.externalID, sourceID: sourceID, title: item.title,
                  upstreamTitle: item.upstreamTitle, kind: item.kind, wording: item.wording, start: item.start,
                  end: item.end, isAllDay: item.isAllDay, courseCategory: item.courseCategory,
                  courseCode: item.courseCode, description: item.description, isDone: isDone)
    }
}

extension MomentItem {
    /// A stored Moodle event. nil for any other event.
    @MainActor
    init?(_ event: Event) {
        guard event.origin == .imported, event.importKind.isMoodle, let sourceID = event.sourceID else { return nil }
        self.init(id: event.id, externalID: event.externalID ?? event.id.uuidString, sourceID: sourceID,
                  title: event.title, upstreamTitle: event.upstreamTitle ?? event.title, kind: event.importKind,
                  wording: event.momentWording, start: event.start, end: event.end, isAllDay: event.isAllDay,
                  courseCategory: event.courseCategory, courseCode: event.courseCode,
                  description: event.importedDescription, isDone: event.status == .done,
                  markedDoneDueAt: event.markedDoneDueAt)
    }
}

extension Event {
    /// §32.1: `origin == .imported && start == end` on a feed source — a
    /// Moodle item with no duration. Every consumer that would otherwise read
    /// it as a zero-length timed event tests this, never the duration.
    var isMoment: Bool { origin == .imported && importKind.isMoodle && !isAllDay && start == end }

    /// §32.1 / §37.1: drawn in the all-day row — an all-day event or a
    /// moment. Every "timed event" consumer (grid, conflicts, NEXT, scroll,
    /// the Day header's count) skips these.
    var isDrawnAsAllDay: Bool { isAllDay || isMoment }

    /// §38: a done deadline whose due time moved after it was marked.
    var dueTimeChangedAfterDone: Bool {
        status == .done && importKind == .deadline && markedDoneDueAt != nil && markedDoneDueAt != start
    }
}

// MARK: - §36 Pairing

nonisolated struct MoodlePairs: Sendable, Equatable {
    /// deadline externalID → its opening.
    var openingOf: [String: MomentItem] = [:]
    /// The externalIDs of paired openings: not drawn, listed, notified or
    /// selectable (§36).
    var pairedOpenings: Set<String> = []

    func opening(of item: MomentItem) -> MomentItem? { openingOf[item.externalID] }
    func isPairedOpening(_ item: MomentItem) -> Bool { item.kind == .opening && pairedOpenings.contains(item.externalID) }
}

nonisolated enum MoodlePairing {
    /// §36: a pure function over one source's items (call it per source).
    static func pairs(_ items: [MomentItem]) -> MoodlePairs {
        struct Key: Hashable { var category: String?; var title: String }
        func byStart(_ a: MomentItem, _ b: MomentItem) -> Bool {
            a.start != b.start ? a.start < b.start : a.externalID < b.externalID
        }
        var openings: [Key: [MomentItem]] = [:]
        var deadlines: [Key: [MomentItem]] = [:]
        for item in items {
            let key = Key(category: item.courseCategory, title: item.title)
            if item.kind == .opening {
                openings[key, default: []].append(item)
            } else if item.kind == .deadline, item.wording == .closes || item.wording == .due {
                deadlines[key, default: []].append(item)
            }
        }
        var result = MoodlePairs()
        for (key, ds) in deadlines {
            var free = (openings[key] ?? []).sorted(by: byStart)
            for deadline in ds.sorted(by: byStart) {
                // The latest unpaired opening whose start ≤ the deadline's.
                guard let at = free.lastIndex(where: { $0.start <= deadline.start }) else { continue }
                result.openingOf[deadline.externalID] = free[at]
                result.pairedOpenings.insert(free[at].externalID)
                free.remove(at: at)
            }
        }
        return result
    }
}

// MARK: - §37.1 The pill

nonisolated struct MomentFormat: Sendable {
    let calendar: Calendar

    init(zone: TimeZone) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        cal.locale = Locale(identifier: "en_US_POSIX")
        calendar = cal
    }

    private func string(_ date: Date, _ format: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.dateFormat = format
        return f.string(from: date)
    }

    /// `23:59`
    func time(_ date: Date) -> String { string(date, "HH:mm") }
    /// `12 Oct 09:30` — another day's time in hover help.
    func dayTime(_ date: Date) -> String { string(date, "d MMM HH:mm") }
    /// `Tuesday 13 October`
    func spokenDay(_ date: Date) -> String { string(date, "EEEE d MMMM") }
    /// `Tue 13 Oct 2026, 23:59` — the inspector (§37.4).
    func inspector(_ date: Date) -> String { string(date, "EEE d MMM yyyy, HH:mm") }
    /// `Tue 20 Oct, 12:00` — §38's moved line.
    func moved(_ date: Date) -> String { string(date, "EEE d MMM, HH:mm") }
    /// `Tue 13 Oct` — notification copy (§40.5).
    func date(_ date: Date) -> String { string(date, "EEE d MMM") }

    func sameDay(_ a: Date, _ b: Date) -> Bool { calendar.isDate(a, inSameDayAs: b) }
}

nonisolated enum MomentGlyph {
    /// §37.1: deadline, opening, notice — new kind glyphs, in no other table.
    static func of(_ kind: ImportKind) -> String {
        switch kind {
        case .opening: "lock.open.fill"
        case .notice: "info.circle.fill"
        default: "flag.fill"
        }
    }
    static let done = "checkmark.circle.fill"
}

nonisolated struct MomentPresentation: Sendable {
    let item: MomentItem
    /// The paired opening (§36), for a deadline.
    let opening: MomentItem?
    let sourceName: String
    let format: MomentFormat

    init(_ item: MomentItem, opening: MomentItem? = nil, sourceName: String, zone: TimeZone) {
        self.item = item
        self.opening = item.kind == .deadline ? opening : nil
        self.sourceName = sourceName
        self.format = MomentFormat(zone: zone)
    }

    var glyph: String { item.isDone && item.kind == .deadline ? MomentGlyph.done : MomentGlyph.of(item.kind) }
    /// §37.1: the rail is the deadline's only.
    var hasRail: Bool { item.kind == .deadline }

    /// The window is shown when the opening falls on the deadline's local date.
    var openingIsSameDay: Bool { opening.map { format.sameDay($0.start, item.start) } ?? false }

    /// **time**: `HH:mm`, or `16:10–17:47` for a same-day window.
    var time: String {
        if let opening, openingIsSameDay { return "\(format.time(opening.start))–\(format.time(item.start))" }
        return format.time(item.start)
    }

    /// **text**: `{code} · {title}`, else `{title}`. A category is never in it.
    var text: String { item.courseCode.map { "\($0) · \(item.title)" } ?? item.title }

    /// §37.1's Kind word: `Deadline` / `Opening` / `Item`.
    var kindWord: String {
        switch item.kind {
        case .opening: "Opening"
        case .notice: "Item"
        default: "Deadline"
        }
    }

    /// `due` / `closes` / `registration ends` / `opens` / `at`.
    static func wordingWord(_ wording: MomentWording?) -> String {
        switch wording {
        case .due?: "due"
        case .closes?: "closes"
        case .registrationEnds?: "registration ends"
        case .opens?: "opens"
        case nil: "at"
        }
    }

    /// §37.1 hover help: `{label text} · {wording} {when} · {source} · {Kind}`
    /// (`· Done` when done).
    var hoverHelp: String {
        let own = "\(Self.wordingWord(item.wording)) \(format.time(item.start))"
        let when: String
        if let opening {
            let opens = openingIsSameDay ? format.time(opening.start) : format.dayTime(opening.start)
            when = "opens \(opens), \(own)"
        } else {
            when = own
        }
        var help = "\(text) · \(when) · \(sourceName) · \(kindWord)"
        if item.isDone { help += " · Done" }
        return help
    }

    /// §37.1 VoiceOver, §11's order: title, time, kind, source, status.
    var accessibilityLabel: String {
        var parts: [String] = []
        if let code = item.courseCode { parts.append(code) }
        parts.append(item.title)
        let day = format.spokenDay(item.start), time = format.time(item.start)
        if item.wording == nil {
            parts.append("at \(day) \(time)")
        } else if let opening {
            parts.append("opens \(format.spokenDay(opening.start)) at \(format.time(opening.start))")
            let closing = Self.wordingWord(item.wording)
            parts.append(openingIsSameDay ? "\(closing) at \(time)" : "\(closing) \(day) at \(time)")
        } else {
            parts.append("\(Self.wordingWord(item.wording)) \(day) at \(time)")
        }
        parts.append(kindWord.lowercased())
        parts.append(sourceName)
        if item.isDone { parts.append("done") }
        return parts.joined(separator: ", ")
    }

    // MARK: Truncation (§37.1)

    struct LabelLayout: Equatable, Sendable {
        var showsTime: Bool
        var showsText: Bool
    }

    /// §37.1: the time is never truncated; when the space left for the text
    /// after it would be under `size.blockCascadeMinReadableWidth` (44pt) the
    /// time is dropped and the text gets the room. Below the glyph alone, the
    /// glyph alone.
    /// - Parameters:
    ///   - available: the label's width after the pill's insets.
    ///   - glyph: the glyph's width; `time`: the time's measured width.
    @MainActor
    static func layout(available: CGFloat, glyph: CGFloat, time: CGFloat,
                       spacing: CGFloat = Tokens.Spacing.xs) -> LabelLayout {
        let minText = Tokens.Size.blockCascadeMinReadableWidth
        let afterTime = available - glyph - spacing - time - spacing
        if afterTime >= minText { return LabelLayout(showsTime: true, showsText: true) }
        if available - glyph - spacing > 0 { return LabelLayout(showsTime: false, showsText: true) }
        return LabelLayout(showsTime: false, showsText: false)
    }
}

// MARK: - §37.1 Sort

nonisolated enum MomentSort {
    static func kindRank(_ kind: ImportKind) -> Int {
        switch kind {
        case .deadline: 0
        case .opening: 1
        default: 2
        }
    }

    /// §37.1 among moment items: by date, then time (the instant, so the
    /// CEST occurrence of a repeated hour comes first, §41), then deadline ·
    /// opening · notice, then title. The externalID makes it total.
    static func areInIncreasingOrder(_ a: MomentItem, _ b: MomentItem) -> Bool {
        if a.start != b.start { return a.start < b.start }
        if kindRank(a.kind) != kindRank(b.kind) { return kindRank(a.kind) < kindRank(b.kind) }
        if a.title != b.title { return a.title < b.title }
        return a.externalID < b.externalID
    }

    static func sorted(_ items: [MomentItem]) -> [MomentItem] { items.sorted(by: areInIncreasingOrder) }
}

// MARK: - §35.5 The timetable mapping

nonisolated enum MoodleCourseMapping {
    /// A timetable code's stem: the part before its last `-` (`SWQM-ILV` →
    /// `SWQM`); a code with no `-` is its own stem.
    static func stem(_ code: String) -> String {
        guard let dash = code.lastIndex(of: "-") else { return code }
        return String(code[..<dash])
    }

    /// Every distinct timetable code whose stem equals the Moodle course code,
    /// case-insensitive, sorted. Derived when shown, never stored.
    static func matches(courseCode: String?, timetableCodes: some Sequence<String>) -> [String] {
        guard let courseCode else { return [] }
        return Set(timetableCodes.filter { stem($0).caseInsensitiveCompare(courseCode) == .orderedSame }).sorted()
    }
}

// MARK: - §37.4 The inspector's values

nonisolated struct MomentInspectorValues: Sendable, Equatable {
    struct Row: Sendable, Equatable {
        var label: String
        var value: String
        var secondLine: String? = nil
    }

    var title: String
    var glyph: String
    var readOnlyLine: String
    /// The moment row (`Due`, `Closes`, `Registration ends`, `Opens`, `At`).
    var moment: Row
    /// A notice's line under the moment row.
    var noticeLine: String?
    var opens: Row?
    var course: Row?
    var inTimetable: Row?
    var inMoodle: Row?
    var origin: String = "Imported"
    /// §38: deadlines only.
    var hasStatus: Bool
    /// §38's moved line, when the condition holds.
    var movedLine: String?
    var description: String?

    static let noticeSentence = "Kadence couldn't tell whether this is a deadline, so it won't remind you of it."

    init(_ item: MomentItem, opening: MomentItem?, sourceName: String, timetableCodes: [String], zone: TimeZone) {
        let format = MomentFormat(zone: zone)
        title = item.title
        glyph = MomentGlyph.of(item.kind)
        readOnlyLine = "Read-only — from \(sourceName)"
        let label: String = switch item.wording {
        case .due?: "Due"
        case .closes?: "Closes"
        case .registrationEnds?: "Registration ends"
        case .opens?: "Opens"
        case nil: "At"
        }
        moment = Row(label: label, value: format.inspector(item.start))
        noticeLine = item.kind == .notice ? Self.noticeSentence : nil
        opens = (item.kind == .deadline ? opening : nil).map { Row(label: "Opens", value: format.inspector($0.start)) }
        if let code = item.courseCode {
            course = Row(label: "Course", value: code,
                         secondLine: item.courseCategory.map(MoodleProfile.shortname))
        } else if let category = item.courseCategory {
            course = Row(label: "Category", value: category)
        }
        let matches = MoodleCourseMapping.matches(courseCode: item.courseCode, timetableCodes: timetableCodes)
        inTimetable = matches.isEmpty ? nil : Row(label: "In timetable", value: matches.joined(separator: ", "))
        inMoodle = item.upstreamTitle == item.title ? nil : Row(label: "In Moodle", value: item.upstreamTitle)
        hasStatus = item.kind == .deadline
        movedLine = item.kind == .deadline && item.dueTimeChangedAfterDone
            ? item.markedDoneDueAt.map { "Due time changed after you marked it done (was \(format.moved($0)))." }
            : nil
        description = item.description
    }
}

// MARK: - §39 Which deadlines the menu bar shows

nonisolated enum DueSelection {
    struct Result: Equatable, Sendable {
        /// The Due state's NEXT (only when nothing timed is left today).
        var next: MomentItem?
        /// DUE TODAY: every other qualifying deadline, in §37.1's order.
        var dueToday: [MomentItem]
    }

    /// The deadlines that qualify today: not done, `now < due`, on today's
    /// local date. Never an opening or a notice.
    static func dueToday(_ items: [MomentItem], now: Date, calendar: Calendar) -> [MomentItem] {
        MomentSort.sorted(items.filter {
            $0.kind == .deadline && $0.isMoment && !$0.isDone && now < $0.start && calendar.isDate($0.start, inSameDayAs: now)
        })
    }

    /// §39.1 / §39.2. `hasTimedNext`: Phase 2's NEXT is not empty (a timed
    /// item, a late item or a departure) — then no deadline takes NEXT and
    /// DUE TODAY lists them all.
    static func select(_ items: [MomentItem], now: Date, calendar: Calendar, hasTimedNext: Bool) -> Result {
        let due = dueToday(items, now: now, calendar: calendar)
        if hasTimedNext { return Result(next: nil, dueToday: due) }
        return Result(next: due.first, dueToday: Array(due.dropFirst()))
    }
}
