//
//  Event.swift
//  Kadence
//
//  The single persisted model in Phase 1. BRIEF-PRODUCT.md's first-draft data
//  model, with the corrections noted per field.
//

import Foundation
import SwiftData

@Model
final class Event {
    /// Stable local identity, distinct from `externalID`. Survives re-sync.
    var id: UUID = UUID()

    var title: String = ""
    var start: Date = Date()
    var end: Date = Date()
    var isAllDay: Bool = false

    var location: Place?

    /// Stored as the enum's raw value. SwiftData handles `Codable` enums, but a
    /// raw `String` keeps the store readable and migration-friendly, which
    /// matters once Phase 3 starts writing imported data into it.
    private var originRaw: String = EventOrigin.manual.rawValue
    var origin: EventOrigin {
        get { EventOrigin(rawValue: originRaw) ?? .manual }
        set { originRaw = newValue.rawValue }
    }

    private var statusRaw: String = EventStatus.scheduled.rawValue
    var status: EventStatus {
        get { EventStatus(rawValue: statusRaw) ?? .scheduled }
        set { statusRaw = newValue.rawValue }
    }

    private var flexibilityRaw: String = Flexibility.fixed.rawValue
    var flexibility: Flexibility {
        get { Flexibility(rawValue: flexibilityRaw) ?? .fixed }
        set { flexibilityRaw = newValue.rawValue }
    }

    /// Correction to the brief: `colorTag` is replaced by `sourceKey`.
    /// components.md §1 makes hue mean *source and nothing else*, so a free
    /// colour tag would be a second, conflicting hue channel. The palette slot
    /// is derived from the source, not chosen per event.
    private var sourceKeyRaw: String = SourceKey.graphite.rawValue
    var sourceKey: SourceKey {
        get { SourceKey(rawValue: sourceKeyRaw) ?? .graphite }
        set { sourceKeyRaw = newValue.rawValue }
    }

    /// The `(sourceID, externalID)` pair from the brief: stable across re-sync,
    /// so importing twice updates instead of duplicating. Both nil for manual events.
    var sourceID: String?
    var externalID: String?

    var notes: String = ""

    /// Blocks the user from dragging this event (interactions.md §4).
    var isLocked: Bool = false

    init(
        title: String,
        start: Date,
        end: Date,
        isAllDay: Bool = false,
        origin: EventOrigin = .manual,
        status: EventStatus = .scheduled,
        flexibility: Flexibility = .fixed,
        sourceKey: SourceKey = .graphite,
        location: Place? = nil,
        sourceID: String? = nil,
        externalID: String? = nil,
        notes: String = "",
        isLocked: Bool = false
    ) {
        self.id = UUID()
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.location = location
        self.originRaw = origin.rawValue
        self.statusRaw = status.rawValue
        self.flexibilityRaw = flexibility.rawValue
        self.sourceKeyRaw = sourceKey.rawValue
        self.sourceID = sourceID
        self.externalID = externalID
        self.notes = notes
        self.isLocked = isLocked
    }
}

extension Event {
    var duration: TimeInterval { end.timeIntervalSince(start) }

    /// interactions.md §4 — imported and locked blocks do not drag.
    var isMovable: Bool { origin != .imported && !isLocked }

    /// components.md §2.1 — data origin maps to a *visual* class.
    var blockKind: BlockKind {
        switch origin {
        case .manual, .imported: .fixedTimed
        case .routine: .routineTimed
        case .planned: .plannedTimed
        }
    }

    /// The glyph depends on origin, not only on `blockKind`: an imported lecture
    /// and a manual event share `.fixedTimed` but differ by symbol.
    var glyphOverride: String? {
        switch origin {
        case .imported: "building.columns"
        case .manual: "calendar"
        default: nil
        }
    }

    func blockStatus(now: Date) -> BlockStatus {
        switch status {
        case .done: return .done
        case .skipped: return .skipped
        case .scheduled:
            return (start <= now && now < end) ? .inProgress : .scheduled
        }
    }

    func isPast(now: Date) -> Bool { end <= now }
}
