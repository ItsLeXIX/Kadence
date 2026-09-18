//
//  Enums.swift
//  Kadence
//
//  The vocabulary shared by the data layer, the style resolver and the views.
//
//  Swift note (from Java/C#): a Swift `enum` is a value type and can carry
//  associated values and methods. `CaseIterable` synthesises `allCases`, which
//  is how the mock generator and the sidebar enumerate sources.
//

import Foundation

// MARK: - Data-layer vocabulary

/// Where an event came from. Mirrors `Event.origin` in BRIEF-PRODUCT.md.
///
/// Only `.manual` and `.imported` are produced by real data in Phase 1
/// (DECISIONS.md 2026-09-09); `.routine` and `.planned` exist so the style
/// resolver can be specified and reviewed in full, fed by the mock generator.
enum EventOrigin: String, Codable, CaseIterable, Sendable {
    case manual
    case routine
    case imported
    case planned
}

/// Lifecycle of an event. Deliberately has no "overdue" or "missed" case —
/// BRIEF-PRODUCT.md: skipped items are re-offered, never counted against you.
enum EventStatus: String, Codable, CaseIterable, Sendable {
    case scheduled
    case done
    case skipped
}

/// How much freedom an automatic process has to move a block.
/// In Phase 1 this only drives the rail treatment (components.md §2.3).
enum Flexibility: String, Codable, CaseIterable, Sendable {
    case fixed
    case shiftable
    case droppable
}

enum TravelMode: String, Codable, CaseIterable, Sendable {
    case walking
    case driving
    case transit

    /// components.md §2.1 — the travel band's glyph is chosen by mode.
    var glyph: String {
        switch self {
        case .walking: "figure.walk"
        case .driving: "car.fill"
        case .transit: "tram.fill"
        }
    }

    var label: String {
        switch self {
        case .walking: "walking"
        case .driving: "driving"
        case .transit: "transit"
        }
    }
}

/// The kind of background treatment a time window gets on the grid.
/// `.peakFocus` is stored but deliberately renders nothing in Phase 1
/// (components.md §7).
enum TimeWindowKind: String, Codable, CaseIterable, Sendable {
    case protected
    case lowEnergy
    case peakFocus
}

// MARK: - Presentation vocabulary

/// The *visual* class of a block. Deliberately not the same as `EventOrigin`
/// (components.md §2.1) — the mapping happens at the call site in
/// `BlockKind.init(origin:)` so that the resolver stays a pure function of
/// visual inputs.
enum BlockKind: String, CaseIterable, Sendable {
    case fixedTimed
    case routineTimed
    case plannedTimed
    case travelBand
    case deadlineAllDay
    case examAllDay
}

/// The status channel the resolver consumes. `.inProgress` is derived from the
/// clock rather than stored, which is why it is separate from `EventStatus`.
enum BlockStatus: String, CaseIterable, Sendable {
    case scheduled
    case inProgress
    case done
    case skipped
}

/// Transient states that compose on top of the resolved style.
///
/// Swift note: `OptionSet` is Swift's type-safe bit-flag set — the equivalent of
/// a Java `EnumSet` or a C# `[Flags]` enum. `[.hovered, .selected]` is one value.
struct Presentation: OptionSet, Sendable, Hashable {
    let rawValue: Int
    init(rawValue: Int) { self.rawValue = rawValue }

    static let hovered    = Presentation(rawValue: 1 << 0)
    static let selected   = Presentation(rawValue: 1 << 1)
    static let dragging   = Presentation(rawValue: 1 << 2)
    static let conflicted = Presentation(rawValue: 1 << 3)
    static let past       = Presentation(rawValue: 1 << 4)
    /// components.md §6/§14.4 — the block is shown at a *proposed* frame
    /// during conflict resolution, not a committed one: `opacity.blockPreviewed`
    /// inside a dashed accent outline. "Applied last, after every row above
    /// it" per §6's own table, so `BlockStyleResolver` applies it after the
    /// `status` switch. The block's *current* frame is retained as a ghost
    /// elsewhere (a plain reduced-opacity render at the call site, per §14.4
    /// — see `DayColumnView`), which is deliberately NOT a `Presentation`
    /// flag of its own: it is the same block rendered a second time at its
    /// real frame, not a new visual treatment of this one.
    static let previewed  = Presentation(rawValue: 1 << 5)

    static let none: Presentation = []
}

/// Which calendar canvas is showing. `⌘1` / `⌘2` / `⌘3` (interactions.md §2).
enum CalendarMode: String, CaseIterable, Identifiable, Sendable {
    case month
    case week
    case day

    var id: String { rawValue }

    var label: String {
        switch self {
        case .month: "Month"
        case .week: "Week"
        case .day: "Day"
        }
    }

    /// The hour-row height this mode's grid uses. Month has no hour grid.
    var hourHeight: CGFloat? {
        switch self {
        case .month: nil
        case .week: Tokens.Size.hourHeightWeek
        case .day: Tokens.Size.hourHeightDay
        }
    }
}
