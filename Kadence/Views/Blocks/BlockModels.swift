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
        guard let location = locationName, !location.isEmpty else { return sourceName }
        return "\(sourceName) · \(location)"
    }

    /// §3.4 — `Title · HH:mm–HH:mm · Source · Kind`.
    var hoverHelp: String {
        let range = "\(BlockFormatters.time.string(from: start))–\(BlockFormatters.time.string(from: end))"
        return "\(title) · \(range) · \(sourceName) · \(accessibilityKindLabel)"
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
        case .scheduled: break
        }
        if presentation.contains(.conflicted) {
            parts.append(contentsOf: conflicts.map(\.spokenPhrase))
        }
        return parts.joined(separator: ", ")
    }

    var accessibilityKindLabel: String {
        switch kind {
        case .fixedTimed: glyphOverride == "building.columns" ? "lecture" : "event"
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
        case .protectedWindow:
            // SPEC-GAP (design/GAPS.md G-030): §11 only gives the
            // block-vs-block form. The wording for a block inside a
            // protected window is unspecified; this is the string the build
            // already spoke, kept as the placeholder. The window's label is
            // carried so the ruling can use it without a model change.
            return "conflicts with a protected window"
        }
    }
}

extension GridBlockModel {
    @MainActor
    init(event: Event, now: Date) {
        self.init(
            id: event.id,
            title: event.title,
            start: event.start,
            end: event.end,
            locationName: event.location?.name,
            kind: event.blockKind,
            flexibility: event.flexibility,
            status: event.blockStatus(now: now),
            source: event.sourceKey,
            sourceName: SourceCatalog.name(for: event.sourceKey),
            glyphOverride: event.glyphOverride,
            isMovable: event.isMovable)
    }
}

/// Phase 1 has no source records, so the sidebar's static list is the catalogue.
/// Phase 3 replaces this with the real connector list.
enum SourceCatalog {
    private static func source(for key: SourceKey) -> CalendarSource? {
        MockData.sources.first { $0.key == key }
    }

    static func name(for key: SourceKey) -> String {
        source(for: key)?.name ?? key.displayName
    }

    /// components.md §10.1 — the symbol comes from the source, and an
    /// unclassified one falls back to a plain disc rather than an error glyph.
    static func symbol(for key: SourceKey) -> String {
        source(for: key)?.symbol ?? CalendarSourceKind.unknown.symbol
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
