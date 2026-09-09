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
    var glyphOverride: String?
    var isMovable: Bool

    /// `HH:mm-HH:mm`, 24-hour, monospaced digits (components.md §3.1).
    func timeRange(formatter: DateFormatter) -> String {
        "\(formatter.string(from: start))-\(formatter.string(from: end))"
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
            glyphOverride: event.glyphOverride,
            isMovable: event.isMovable)
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
