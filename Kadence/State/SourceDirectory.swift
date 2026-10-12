//
//  SourceDirectory.swift
//  Kadence
//
//  PHASE3-REVIEW.md fix 2 — components.md §21.1.1 "A source is identified by
//  its id, never by its colour" (added 2026-10-10; GAPS G-075; DECISIONS
//  2026-10-10 "A source is its record, never its colour").
//
//  Found in real use: imported lectures drew grey, read `Personal · {room}` and
//  showed the person glyph, because every view looked an event's source up by
//  palette slot and the timetable shared `graphite` with `Personal`. A colour
//  is a property of a source; it cannot be its key. Everything that names,
//  tints or filters by a source goes through `SourceDirectory`, which resolves
//  `Event.sourceID` → the `Source` record.
//

import Foundation
import Observation
import SwiftData
import SwiftUI

/// What the views need of one `Source` record, as a value.
nonisolated struct SourceInfo: Equatable, Sendable {
    /// The record's id; nil only for the last-resort stand-in below.
    var id: String?
    var name: String
    /// The record's palette slot — a block's hue (§21.1.1 "Colour").
    var key: SourceKey
    /// The sidebar swatch's symbol (§10.1).
    var symbol: String
    /// `Source.isVisible`: the only visibility state there is.
    var isVisible = true
    var isConnected = false
}

/// The sources of one store, by id. A value: built from the `Source` records
/// on the main actor, then usable anywhere.
nonisolated struct SourceDirectory: Equatable, Sendable {
    /// In sidebar order (`SourceDirectory.sidebarOrder`).
    private(set) var ordered: [SourceInfo] = []
    private var byID: [String: SourceInfo] = [:]
    /// §22.1: review datasets hold fixture events with no `sourceID` (Phase
    /// 2's mock events, and `phase3`'s detached `Statistik übung`). Those are
    /// resolved for display to the `Source` holding their stored slot — **in
    /// review mode only**. A real store never resolves by slot.
    var allowsSlotFallback = false

    static let empty = SourceDirectory()

    init() {}

    init(infos: [SourceInfo], allowsSlotFallback: Bool = false) {
        ordered = infos
        self.allowsSlotFallback = allowsSlotFallback
        for info in infos { if let id = info.id, byID[id] == nil { byID[id] = info } }
    }

    /// Swift note: `Source` is a SwiftData model and lives on the main actor,
    /// so only this initialiser needs it; the struct it builds does not.
    @MainActor
    init(_ sources: [Source], allowsSlotFallback: Bool = false) {
        self.init(infos: Self.sidebarOrder(sources).map {
            SourceInfo(id: $0.id, name: $0.displayName, key: $0.paletteKey, symbol: $0.symbol,
                       isVisible: $0.isVisible, isConnected: $0.isConnected)
        }, allowsSlotFallback: allowsSlotFallback)
    }

    func info(id: String) -> SourceInfo? { byID[id] }

    /// §21.1.1's resolution, in order:
    /// 1. the record whose id is `sourceID`;
    /// 2. review datasets only — the first record (sidebar order) holding the
    ///    event's stored slot;
    /// 3. by origin: `.manual` → `personal`, `.routine` → `routine`. (A
    ///    routine instance's `sourceID` is its template's id — the §13.6
    ///    materialisation pair — which no `Source` carries, so it lands here.)
    /// 4. a stand-in for the stored slot. Not reachable in a real store: every
    ///    imported event has its source's id, and removing a source removes
    ///    its events.
    func info(sourceID: String?, origin: EventOrigin, storedKey: SourceKey) -> SourceInfo {
        if let sourceID, let found = byID[sourceID] { return found }
        if allowsSlotFallback, let found = ordered.first(where: { $0.key == storedKey }) { return found }
        switch origin {
        case .manual: if let found = byID[BuiltInSource.personal.id] { return found }
        case .routine: if let found = byID[BuiltInSource.routine.id] { return found }
        default: break
        }
        // `circle.fill` is §10.1's symbol for an unclassified source
        // (`CalendarSourceKind.unknown`).
        // The name is the slot's own word, as before this fix
        // (`SourceKey.displayName`, spelled out here because that property is
        // main-actor-isolated and this function is not).
        let slotName = storedKey.rawValue.prefix(1).uppercased() + storedKey.rawValue.dropFirst()
        return SourceInfo(id: nil, name: slotName, key: storedKey, symbol: "circle.fill", isVisible: true)
    }

    @MainActor
    func info(for event: Event) -> SourceInfo {
        info(sourceID: event.sourceID, origin: event.origin, storedKey: event.sourceKey)
    }

    /// The sidebar's order (§21.1.1 "Never two rows for one thing"): the
    /// built-ins first (`Personal`, `Daily routine`), then the connected
    /// sources by name.
    ///
    /// The `phase2` / `phase3` review datasets also hold fixture `local`
    /// sources (`Exams`, `Coursework` …), for which the spec gives no order;
    /// a store that holds any keeps the palette order those datasets were
    /// reviewed in (DEVIATIONS, fix run).
    @MainActor
    static func sidebarOrder(_ sources: [Source]) -> [Source] {
        let builtIns = BuiltInSource.allCases.map(\.id)
        let hasFixtureLocals = sources.contains { !$0.isConnected && !builtIns.contains($0.id) }
        if hasFixtureLocals {
            let order = SourceKey.allCases
            return sources.sorted { lhs, rhs in
                let l = order.firstIndex(of: lhs.paletteKey) ?? order.count
                let r = order.firstIndex(of: rhs.paletteKey) ?? order.count
                if l != r { return l < r }
                if lhs.displayName != rhs.displayName { return lhs.displayName < rhs.displayName }
                return lhs.id < rhs.id
            }
        }
        return sources.sorted { lhs, rhs in
            let l = builtIns.firstIndex(of: lhs.id) ?? builtIns.count
            let r = builtIns.firstIndex(of: rhs.id) ?? builtIns.count
            if l != r { return l < r }
            let byName = lhs.displayName.localizedStandardCompare(rhs.displayName)
            if byName != .orderedSame { return byName == .orderedAscending }
            return lhs.id < rhs.id
        }
    }
}

/// The running app's directory, kept in step with the store by
/// `tracksSources()` on each scene's root view.
///
/// Swift note: `@Observable` makes reads of `directory` inside a SwiftUI
/// `body` register a dependency, exactly like reading a `@State` — even
/// through this shared instance — so a view that names or filters by a source
/// redraws when a source is renamed, recoloured, hidden or removed. Value-type
/// models built outside a view (`GridBlockModel(event:now:)`) read it the
/// same way; tests pass their own directory instead.
@MainActor
@Observable
final class SourceCatalog {
    static let shared = SourceCatalog()
    private(set) var directory = SourceDirectory.empty

    static var directory: SourceDirectory { shared.directory }

    /// Slot fallback is for review datasets only (§22.1).
    static let isReviewLaunch: Bool = {
        if case .review = LaunchKind.current() { return true }
        return false
    }()

    /// Tests and offscreen renders only: stands a directory in for the
    /// store's, so a view rendered outside a scene can name its sources.
    static func install(_ directory: SourceDirectory) {
        if directory != shared.directory { shared.directory = directory }
    }

    static func update(_ sources: [Source]) {
        let next = SourceDirectory(sources, allowsSlotFallback: isReviewLaunch)
        if next != shared.directory { shared.directory = next }
    }
}

/// Mirrors the store's `Source` records into `SourceCatalog`.
private struct SourceCatalogTracker: ViewModifier {
    @Query private var sources: [Source]

    func body(content: Content) -> some View {
        // The directory itself is the watched value: it is `Equatable` and
        // covers every field a view can show (name, slot, symbol, visibility).
        content.onChange(of: SourceDirectory(sources, allowsSlotFallback: SourceCatalog.isReviewLaunch), initial: true) { _, _ in
            SourceCatalog.update(sources)
        }
    }
}

extension View {
    /// Keeps `SourceCatalog` current for this scene. Needs the scene's
    /// `modelContainer`.
    func tracksSources() -> some View { modifier(SourceCatalogTracker()) }
}

/// The inspector's title swatch and its Source row (layouts.md §6 row 4,
/// §6.1 rows 1 and 7): the name, slot and symbol of the `Source` record the
/// event's `sourceID` names — "never of whichever source shares its palette
/// slot" (in real use this row showed `Personal`'s person glyph beside
/// `University timetable`).
struct InspectorSourceModel: Equatable, Sendable {
    var name: String
    var key: SourceKey
    var symbol: String

    @MainActor
    init(event: Event, sources: SourceDirectory = SourceCatalog.directory) {
        let info = sources.info(for: event)
        name = info.name
        key = info.key
        symbol = info.symbol
    }
}
