//
//  RoutineTemplate.swift
//  Kadence
//
//  The Phase 2 routine data model: a weekly template of `RoutineBlock`s that
//  `RoutineEngine.materialize` expands into ordinary `Event`s
//  (BRIEF-PRODUCT.md's data-model draft; components.md §13). This file adds
//  no UI and no conflict/detachment logic — see `RoutineEngine.swift`'s header
//  for exactly what materialisation does and does not do yet.
//
//  Follows Event.swift's conventions: a stable `id: UUID`, enums stored as a
//  raw `String` with a computed accessor, and a doc comment at every point
//  this departs from or resolves an ambiguity in the brief.
//

import Foundation
import SwiftData

/// A named weekly routine — a set of `RoutineBlock`s repeated on chosen
/// weekdays. This model only describes the pattern; `RoutineEngine.materialize`
/// is what turns it into events on the calendar.
@Model
final class RoutineTemplate {
    /// Stable local identity. Also what `RoutineEngine` writes into every
    /// materialized event's `sourceID`, so every instance traces back to its
    /// template exactly the way an imported event traces back to its source.
    var id: UUID = UUID()

    var name: String = ""

    /// `Calendar`'s own `weekday` component convention: 1 = Sunday ...
    /// 7 = Saturday. Matching it — rather than inventing a Monday-first
    /// convention, as the BRIEF-PRODUCT draft leaves unspecified — means
    /// `RoutineEngine.materialize` compares directly against
    /// `calendar.component(.weekday, from:)` with no translation table, and a
    /// template's weekday set is directly comparable to any other calendar
    /// computation in the codebase.
    var activeWeekdays: Set<Int> = []

    /// Cascade: deleting a template deletes the blocks that describe it.
    /// Already-materialized `Event`s are untouched by this — they are
    /// independent rows keyed by `(sourceID, externalID)`, not a SwiftData
    /// relationship, which is what lets them survive detachment and outlive
    /// template edits (components.md §13.4 — out of scope for this task, but
    /// the identity scheme has to hold up under it).
    @Relationship(deleteRule: .cascade)
    var blocks: [RoutineBlock] = []

    /// components.md §13.1: "the routine's own palette slot, one hue for the
    /// whole template" — every block in the template shares this hue, unlike
    /// an ordinary `Event`, which is assigned per-source.
    private var sourceKeyRaw: String = SourceKey.graphite.rawValue
    var sourceKey: SourceKey {
        get { SourceKey(rawValue: sourceKeyRaw) ?? .graphite }
        set { sourceKeyRaw = newValue.rawValue }
    }

    init(
        name: String,
        activeWeekdays: Set<Int> = [],
        blocks: [RoutineBlock] = [],
        sourceKey: SourceKey = .graphite
    ) {
        self.id = UUID()
        self.name = name
        self.activeWeekdays = activeWeekdays
        self.blocks = blocks
        self.sourceKeyRaw = sourceKey.rawValue
    }
}

/// One block within a `RoutineTemplate`'s week — "Gym", "Study block", etc.
/// `RoutineEngine.materialize` turns each `(active weekday × block)` pair into
/// one `Event` with `origin == .routine`.
@Model
final class RoutineBlock {
    /// Stable identity, reused by `RoutineEngine.materialize` as the block
    /// half of each materialized event's `externalID` (`"<block id>#<date>"`),
    /// so the same block on the same date always resolves to the same event.
    var id: UUID = UUID()

    var title: String = ""

    /// Time-of-day as minutes since midnight, not `DateComponents(hour:
    /// minute:)`. Both encode the same thing; this was chosen because
    /// `RoutineEngine.materialize` only ever needs to add it to a day's start
    /// as a plain calendar offset
    /// (`calendar.date(byAdding: .minute, value: startMinutes, to: dayStart)`),
    /// which needs no intermediate `DateComponents` round-trip, and because it
    /// makes the value directly comparable to `shiftableMinutes` below —
    /// both are the same unit.
    var startMinutes: Int = 0

    var duration: TimeInterval = 0

    private var flexibilityRaw: String = Flexibility.fixed.rawValue
    var flexibility: Flexibility {
        get { Flexibility(rawValue: flexibilityRaw) ?? .fixed }
        set { flexibilityRaw = newValue.rawValue }
    }

    /// BRIEF-PRODUCT.md's data-model draft gives `.shiftable(±minutes)`, but
    /// the shared `Flexibility` enum (`Enums.swift`) has no associated value —
    /// `Event` uses the very same enum, and Phase 1 never needed one there.
    /// Rather than change a type both models share (and that Phase 1's rail
    /// rendering already depends on), the ± minutes value components.md §13.2
    /// specifies — a stepper, 15-minute steps, range 15–180 — lives here as
    /// its own field, `nil` unless `flexibility == .shiftable`. Range/step
    /// validation belongs to the (not-yet-built) editor UI, not this model.
    var shiftableMinutes: Int?

    var priority: Int = 0

    init(
        title: String,
        startMinutes: Int,
        duration: TimeInterval,
        flexibility: Flexibility = .fixed,
        shiftableMinutes: Int? = nil,
        priority: Int = 0
    ) {
        self.id = UUID()
        self.title = title
        self.startMinutes = startMinutes
        self.duration = duration
        self.flexibilityRaw = flexibility.rawValue
        self.shiftableMinutes = shiftableMinutes
        self.priority = priority
    }
}
