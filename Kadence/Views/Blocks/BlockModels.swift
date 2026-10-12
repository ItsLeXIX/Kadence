//
//  BlockModels.swift
//  Kadence
//
//  Plain value types the block views render. Keeping the views off `Event`
//  directly means the same view renders persisted events and display fixtures,
//  and means a SwiftUI preview needs no model container.
//

import Foundation

struct GridBlockModel: Identifiable, Equatable, Sendable {
    var id: UUID
    var title: String
    var start: Date
    var end: Date
    var locationName: String?
    var kind: BlockKind
    var flexibility: Flexibility
    var status: BlockStatus
    var source: SourceKey
    /// The source's display name, e.g. "University timetable" — not the palette
    /// slot. §3.4 makes this required as text at tier ≥ 44 and in hover help.
    var sourceName: String
    var glyphOverride: String?
    var isMovable: Bool
    /// Phase 3 (components.md §18.2, §20.7.1): for imported events.
    var importKind: ImportKind?
    var isOnline = false
    /// What this block conflicts with, for the spoken label (§11). Only read
    /// when the presentation is `.conflicted`. Empty by default; the call
    /// sites that know the other half fill it in.
    var conflicts: [BlockConflict] = []

    /// `HH:mm-HH:mm`, 24-hour, monospaced digits (components.md §3.1).
    func timeRange(formatter: DateFormatter) -> String {
        "\(formatter.string(from: start))-\(formatter.string(from: end))"
    }

    /// §3.4 — `Source · Location`, or just the source when there is no location.
    var metaLine: String {
        // §6 `cancelled` at `.full`: `Cancelled · University timetable`.
        if status == .cancelled { return "Cancelled · \(sourceName)" }
        // §18.2: an online event reads `Online` where the location would.
        if isOnline { return "\(sourceName) · Online" }
        guard let location = locationName, !location.isEmpty else { return sourceName }
        return "\(sourceName) · \(location)"
    }

    /// §3.4 — `Title · HH:mm–HH:mm · Source · Kind`.
    var hoverHelp: String {
        let range = "\(BlockFormatters.time.string(from: start))–\(BlockFormatters.time.string(from: end))"
        return "\(title) · \(range) · \(sourceName) · \(hoverKindLabel)"
    }

    /// §20.7.1: hover help's Kind reads `Exam` / `Lecture` for imported
    /// events; every other kind keeps its spoken word.
    var hoverKindLabel: String {
        switch importKind {
        case .exam?: "Exam"
        case .lecture?: "Lecture"
        case nil: accessibilityKindLabel
        }
    }

    /// components.md §11 — label order: title, time range, kind, source, status,
    /// then conflict. Kind and status are spoken because they are carried
    /// visually by shape and must not be dropped on the assumption that colour
    /// conveys them.
    func accessibilityLabel(presentation: Presentation) -> String {
        var parts = [
            title,
            "\(BlockFormatters.time.string(from: start)) to \(BlockFormatters.time.string(from: end))",
            accessibilityKindLabel,
            sourceName,
        ]
        switch status {
        case .done: parts.append("done")
        case .skipped: parts.append("skipped, re-offered")
        case .inProgress: parts.append("in progress")
        case .cancelled: parts.append("cancelled")
        case .scheduled: break
        }
        if presentation.contains(.conflicted) {
            parts.append(contentsOf: Self.orderedConflictPhrases(conflicts))
        }
        return parts.joined(separator: ", ")
    }

    /// components.md §11 (amended 2026-10-05, G-030): "Block phrases come
    /// first, then window phrases". Within each kind the caller's order is
    /// kept — block partners arrive in partner start order
    /// (`MainWindow.conflictPartnerTitles`). Swift's `filter` keeps order,
    /// so two passes are a stable partition.
    static func orderedConflictPhrases(_ conflicts: [BlockConflict]) -> [String] {
        let blocks = conflicts.filter { if case .event = $0 { true } else { false } }
        let windows = conflicts.filter { if case .protectedWindow = $0 { true } else { false } }
        return (blocks + windows).map(\.spokenPhrase)
    }

    var accessibilityKindLabel: String {
        switch kind {
        case .fixedTimed:
            importKind == .exam ? "exam" : (glyphOverride == "building.columns" ? "lecture" : "event")
        case .eventAllDay: importKind == .exam ? "exam" : (importKind == .lecture ? "lecture" : "event")
        case .routineTimed: "routine block"
        case .plannedTimed: "planned study session"
        case .travelBand: "travel"
        case .deadlineAllDay: "deadline"
        case .examAllDay: "exam"
        }
    }
}

/// The other half of a conflict, as §11's VoiceOver label speaks it. Two
/// kinds, because a block can collide with another block or land in a
/// protected window, and the label must not say one when it means the other
/// (task P2-T41; before it, every conflicted block said "protected window").
enum BlockConflict: Equatable, Sendable {
    /// Another event or block, by its title.
    case event(title: String)
    /// A `.protected` time window, by its label.
    case protectedWindow(label: String)

    var spokenPhrase: String {
        switch self {
        case .event(let title):
            // components.md §11's own example:
            // "Datenmodellierung, 09:00 to 10:30, lecture, university
            // timetable, conflicts with Training".
            return "conflicts with \(title)"
        case .protectedWindow(let label):
            // components.md §11 (amended 2026-10-05, closes G-030): a block
            // LANDS IN a window (§14.2's verb) — two blocks conflict with
            // each other, a block does not conflict with a window. The
            // visible `(protected)` is spoken as `, a protected window`.
            return label.isEmpty
                ? "lands in a protected window"
                : "lands in \(label), a protected window"
        }
    }
}

extension GridBlockModel {
    /// components.md §21.1.1 (fix 2, G-075): the block's source is the
    /// `Source` record `Event.sourceID` names. Its name and its hue come from
    /// that record — never from whichever source shares the event's stored
    /// palette slot. `sources` defaults to the running app's directory; tests
    /// pass their own.
    @MainActor
    init(event: Event, now: Date, sources: SourceDirectory = SourceCatalog.directory) {
        let source = sources.info(for: event)
        self.init(
            id: event.id,
            title: event.title,
            start: event.start,
            end: event.end,
            locationName: event.location?.name,
            kind: event.blockKind,
            flexibility: event.flexibility,
            status: event.blockStatus(now: now),
            source: source.key,
            sourceName: source.name,
            glyphOverride: event.glyphOverride,
            isMovable: event.isMovable,
            importKind: event.origin == .imported ? event.importKind : nil,
            isOnline: event.isOnline)
    }
}

enum BlockFormatters {
    /// 24-hour, fixed — this app is used in Vienna and the spec says 24-hour,
    /// so the format is not locale-derived.
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}
