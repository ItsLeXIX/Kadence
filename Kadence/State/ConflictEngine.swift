//
//  ConflictEngine.swift
//  Kadence
//
//  Conflict detection and resolution-option generation (BRIEF-PRODUCT.md's
//  Phase 2 section; components.md §14.3). Data layer only, mirroring the
//  shape `RoutineEngine.materialize` set in task P2-T08: a pure, testable
//  engine, free of SwiftUI, that produces value-type results and mutates
//  nothing.
//
//  What this file explicitly does NOT do (all separate, future tasks):
//  - Wire detected conflicts into `Presentation.conflicted` /
//    `BlockStyleResolver` / `GridBlockView`.
//  - Build the "Needs your attention" row or the conflict panel
//    (components.md §14, interactions.md §10).
//  - Apply an option to the store, or touch `UndoStack` — that lives in
//    `CalendarState.applyFocusedConflictOption` / `EventStore.swift` (task
//    P2-T17), not here; this file only decides what "still unresolved"
//    means for `detect`'s own next pass (see `.skipped` filter below).
//  - Detect a protected-window conflict — no `TimeWindow` model exists yet
//    (the brief's own next item after this one).
//
//  A conflict is exactly "an overlap between a routine block and an
//  imported/manual event" (BRIEF-PRODUCT.md's own wording) — one event with
//  `origin == .routine`, the other with `origin == .manual` or `.imported`,
//  and the routine side not already `.skipped` (P2-T17, `design/GAPS.md`
//  G-015 — see `detect`'s own inline comment). Two `.routine` events
//  overlapping each other, two `.manual` events overlapping each other, or a
//  `.routine` event overlapping a `.planned` event, are all out of scope: the
//  brief only ever names routine-vs-imported/manual, and nothing else asks
//  for more.
//
//  `Conflict`/`ConflictOption` hold direct `Event` (and, for the option's
//  resolution, the routine's own `RoutineBlock`) references rather than
//  snapshot values. That is a deliberate departure from `EventSnapshot`'s
//  shape (`EventStore.swift`) — that type exists purely because a deleted
//  `@Model` instance cannot be resurrected, which is not this file's problem.
//  Whatever future task applies an option needs the live `Event` to call
//  `EventStore.move`/`resize`/`skip` on; handing it a `UUID` it would then
//  have to re-fetch buys nothing. Both types are therefore `@MainActor`-
//  scoped, same as `RoutineEngine`, and not `Sendable` — same reasoning as
//  `Event` itself.
//

import Foundation
import SwiftData

// MARK: - Result types

/// One overlap between a `.routine` event and a `.manual`/`.imported` event,
/// with its ranked resolution options already attached.
struct Conflict: Identifiable {
    /// Deterministic, not a fresh `UUID` per detection pass — the same pair
    /// of events always yields the same `id`, so a future "select the first
    /// unresolved conflict" (components.md §14.1) can compare across repeated
    /// `detect` calls (e.g. after the surrounding event list changes) without
    /// extra bookkeeping.
    let id: String

    /// The `.routine`-origin side of the overlap.
    let routineEvent: Event
    /// The `.manual`- or `.imported`-origin side of the overlap.
    let otherEvent: Event

    /// The overlap window itself — components.md §14.2's
    /// "13:00–14:30 · 45 min overlap" line is this engine's `overlapStart`/
    /// `overlapEnd` formatted; formatting is the UI task's job, not this one's.
    let overlapStart: Date
    let overlapEnd: Date

    /// 2–3 options in the common case (see `ConflictEngine.makeOptions`'s own
    /// doc comment for the one documented exception), ordered by ascending
    /// disturbance, with exactly one `isRecommended == true`.
    let options: [ConflictOption]
}

/// What kind of change a `ConflictOption` proposes.
enum ConflictOptionKind: String, Sendable, Equatable, CaseIterable {
    /// Move `routineEvent` later by `disturbanceMinutes`, same duration.
    case shiftLater
    /// Trim `routineEvent`'s duration so it no longer overlaps.
    case shorten
    /// Mark this one occurrence of `routineEvent` `.skipped`.
    case skipToday
}

/// One concrete way to resolve a `Conflict`. Carries structured data only — a
/// later UI task formats it into components.md §14.3's title/delta strings
/// (e.g. `"Shift Training 90 min later"`); this engine does not build prose.
struct ConflictOption: Identifiable, Equatable {
    let id: UUID
    let kind: ConflictOptionKind

    /// `routineEvent`'s proposed new start/end. Set for `.shiftLater` and
    /// `.shorten`; `nil` for `.skipToday`.
    let newStart: Date?
    let newEnd: Date?

    /// `true` only for `.skipToday`. Marks that this one occurrence goes
    /// `.skipped` (`EventStatus`) — never the whole `RoutineTemplate`.
    let skipsOccurrence: Bool

    /// Disturbance, in minutes, on one shared scale so options sort and
    /// compare directly (components.md §14.3: "ordered by disturbance, least
    /// first"):
    /// - `.shiftLater` — minutes the block moves.
    /// - `.shorten` — minutes trimmed off the original duration.
    /// - `.skipToday` — the occurrence's full original duration in minutes.
    ///   The task text allows "minutes moved, or a count of affected
    ///   occurrences" for this figure; a bare occurrence count would not sit
    ///   on the same axis as the other two kinds' minute figures (a 1 could
    ///   outrank or underrank a 90-minute shift for no principled reason), so
    ///   this engine uses "how many minutes of scheduled time disappear" for
    ///   every kind instead — losing the whole block reads as more
    ///   disturbance than trimming part of it, which is also the intuitive
    ///   reading of the brief's own ranked examples.
    let disturbanceMinutes: Int

    /// Exactly one option per `Conflict` has this `true` — the least-
    /// disturbance option, per `ConflictEngine.finalize`'s own doc comment.
    let isRecommended: Bool
}

// MARK: - Engine

@MainActor
enum ConflictEngine {

    /// 15-minute snap, same as interactions.md §3/§4's own drag/resize snap —
    /// reused here for the `.shiftLater` option's minimal-shift rounding.
    private static let snapMinutes = 15

    /// interactions.md §4's own floor: "minimum resulting duration 15
    /// minutes; the drag clamps rather than inverting."
    private static let minimumDuration: TimeInterval = 15 * 60

    /// Finds every routine-vs-manual/imported overlap in `events` and builds
    /// each one's ranked resolution options. `routineBlocks` supplies the
    /// `shiftableMinutes` range for `.shiftable` routine events — looked up
    /// per event via the `<block.id>#<date>` `externalID` scheme
    /// `RoutineEngine.swift`'s own header documents, not carried on `Event`
    /// itself (STATUS.md §6 already declined to add a field to `Event` for
    /// exactly this reason; this engine makes the same call).
    ///
    /// Pure: reads `events`/`routineBlocks`, mutates nothing, touches no
    /// store and no `UndoStack`. O(n²) over `events` — deliberately simple
    /// pairwise comparison; nothing in scope needs this to run over more than
    /// one day's or one week's worth of events at a time.
    static func detect(events: [Event], routineBlocks: [RoutineBlock]) -> [Conflict] {
        var conflicts: [Conflict] = []
        for i in events.indices {
            for j in (i + 1)..<events.count {
                guard let pair = routineOtherPair(events[i], events[j]) else { continue }
                // A `.skipped` occurrence is not competing for its slot any
                // more (`EventStore.toggleSkipped`'s own doc comment: "puts
                // the item back in the pool to be re-offered"), so it is not
                // "an overlap" in this engine's own sense of the word even
                // though its start/end are untouched. Needed so applying a
                // `.skipToday` conflict option (`CalendarState
                // .applyFocusedConflictOption`) actually resolves the
                // conflict it was applied to, rather than the very next
                // `detect` pass reporting the identical pair again —
                // components.md §14.5's "advance to the next unresolved
                // conflict, or return to normal if that was the last one"
                // only holds if applying an option can make a conflict stop
                // being reported. Neither this file's own original doc
                // comment nor components.md §14 says whether status should
                // gate detection at all; this is a deliberate, narrow answer
                // to that silence, not a guess left unrecorded — see
                // `design/GAPS.md` G-015.
                guard pair.routine.status != .skipped else { continue }
                guard overlaps(pair.routine, pair.other) else { continue }

                let overlapStart = Swift.max(pair.routine.start, pair.other.start)
                let overlapEnd = Swift.min(pair.routine.end, pair.other.end)
                let options = makeOptions(
                    routineEvent: pair.routine, otherEvent: pair.other, routineBlocks: routineBlocks)

                conflicts.append(Conflict(
                    id: "\(pair.routine.id.uuidString)#\(pair.other.id.uuidString)",
                    routineEvent: pair.routine,
                    otherEvent: pair.other,
                    overlapStart: overlapStart,
                    overlapEnd: overlapEnd,
                    options: options))
            }
        }
        return conflicts
    }

    // MARK: - Pairing and overlap

    /// Exactly one of `a`/`b` must be `.routine` and the other `.manual` or
    /// `.imported` — both directions checked, since `detect`'s loop does not
    /// otherwise care which of `events[i]`/`events[j]` is which. Two
    /// `.routine`s, two non-routines, or a `.routine` paired with a
    /// `.planned` event, all return `nil`.
    private static func routineOtherPair(_ a: Event, _ b: Event) -> (routine: Event, other: Event)? {
        func isEligibleOther(_ event: Event) -> Bool {
            event.origin == .manual || event.origin == .imported
        }
        if a.origin == .routine, isEligibleOther(b) { return (a, b) }
        if b.origin == .routine, isEligibleOther(a) { return (b, a) }
        return nil
    }

    /// Strict interval overlap — touching endpoints (one ends exactly when
    /// the other starts) do not count.
    private static func overlaps(_ a: Event, _ b: Event) -> Bool {
        a.start < b.end && b.start < a.end
    }

    // MARK: - Option generation

    /// Item 2's per-flexibility switch, plus item 3's always-present skip
    /// fallback. Both are folded into one call per case rather than "primary
    /// option, then unconditionally append a second skip" — for `.droppable`,
    /// the flexibility-derived option already *is* "skip today", so a second,
    /// literally-identical skip option would be a meaningless duplicate; this
    /// reading (skip appears once per conflict, however it got there) is what
    /// "so every conflict has at least 2 options even when the flexibility-
    /// derived one is unavailable" is read to mean — the fallback exists to
    /// backfill a case where the derived option is something *other than*
    /// skip and unavailable, not to double up when it already is skip.
    ///
    /// One documented consequence: a `.droppable` conflict, and the rare
    /// `.shiftable`/`.fixed` conflict where the derived option doesn't fit
    /// (shift exceeds the block's range, or shortening would go below the
    /// 15-minute floor), end up with exactly 1 option rather than 2–3. That
    /// option is still always marked `isRecommended` — see `finalize` — so
    /// "at least one recommended, never more than one" holds unconditionally;
    /// only the "2–3 typically" shape is what narrows in that edge case, and
    /// "do not let the option list go to zero" (item 3's own, firmer
    /// requirement) always holds.
    private static func makeOptions(
        routineEvent: Event, otherEvent: Event, routineBlocks: [RoutineBlock]
    ) -> [ConflictOption] {
        var raw: [RawOption] = []

        switch routineEvent.flexibility {
        case .shiftable:
            if let shift = shiftLaterOption(routineEvent: routineEvent, otherEvent: otherEvent, routineBlocks: routineBlocks) {
                raw.append(shift)
            }
            raw.append(skipOption(for: routineEvent))

        case .droppable:
            raw.append(skipOption(for: routineEvent))

        case .fixed:
            if let shorten = shortenOption(routineEvent: routineEvent, otherEvent: otherEvent) {
                raw.append(shorten)
            }
            raw.append(skipOption(for: routineEvent))
        }

        return finalize(raw)
    }

    /// Minimal 15-minute-incremented later shift that clears the overlap
    /// (new start at or after `otherEvent.end`), clamped to the routine
    /// block's own `shiftableMinutes`. `nil` when no matching `RoutineBlock`
    /// is found, it has no `shiftableMinutes`, or the needed shift exceeds it.
    private static func shiftLaterOption(
        routineEvent: Event, otherEvent: Event, routineBlocks: [RoutineBlock]
    ) -> RawOption? {
        guard let block = routineBlock(for: routineEvent, in: routineBlocks),
              let range = block.shiftableMinutes, range > 0
        else { return nil }

        let neededSeconds = otherEvent.end.timeIntervalSince(routineEvent.start)
        guard neededSeconds > 0 else { return nil }

        let neededMinutes = Int((neededSeconds / 60).rounded(.up))
        let shiftMinutes = roundUpToStep(neededMinutes, step: snapMinutes)
        guard shiftMinutes <= range else { return nil }

        let delta = TimeInterval(shiftMinutes * 60)
        return RawOption(
            kind: .shiftLater,
            newStart: routineEvent.start.addingTimeInterval(delta),
            newEnd: routineEvent.end.addingTimeInterval(delta),
            skipsOccurrence: false,
            disturbanceMinutes: shiftMinutes)
    }

    /// Trims `routineEvent` to end where `otherEvent` starts, or to start
    /// where `otherEvent` ends — whichever leaves more of the original
    /// duration (ties favour trimming from the end, i.e. keeping the
    /// original start). `nil` when the longer of the two candidates would
    /// still fall below the 15-minute floor.
    private static func shortenOption(routineEvent: Event, otherEvent: Event) -> RawOption? {
        let keepFront = Swift.max(0, otherEvent.start.timeIntervalSince(routineEvent.start))
        let keepBack = Swift.max(0, routineEvent.end.timeIntervalSince(otherEvent.end))

        let newStart: Date
        let newEnd: Date
        let keptDuration: TimeInterval
        if keepFront >= keepBack {
            newStart = routineEvent.start
            newEnd = otherEvent.start
            keptDuration = keepFront
        } else {
            newStart = otherEvent.end
            newEnd = routineEvent.end
            keptDuration = keepBack
        }

        guard keptDuration >= minimumDuration else { return nil }

        let trimmedMinutes = Int(((routineEvent.duration - keptDuration) / 60).rounded())
        return RawOption(
            kind: .shorten, newStart: newStart, newEnd: newEnd,
            skipsOccurrence: false, disturbanceMinutes: trimmedMinutes)
    }

    /// "Skip today" — disturbance is the occurrence's own full duration in
    /// minutes (see `ConflictOption.disturbanceMinutes`'s doc comment).
    private static func skipOption(for routineEvent: Event) -> RawOption {
        let minutes = Int((routineEvent.duration / 60).rounded())
        return RawOption(kind: .skipToday, newStart: nil, newEnd: nil, skipsOccurrence: true, disturbanceMinutes: minutes)
    }

    /// Sorts ascending by disturbance and marks index 0 `isRecommended` —
    /// "least disturbance first" (components.md §14.3) as the documented
    /// engineering default the task brief explicitly allows, since the spec
    /// does not mandate a different tie-break. Assigning `id: UUID()` here
    /// (rather than earlier) is what lets `RawOption` stay a plain
    /// comparison-only value with no identity of its own until an option
    /// survives into the final, ordered list.
    private static func finalize(_ raw: [RawOption]) -> [ConflictOption] {
        raw.sorted { $0.disturbanceMinutes < $1.disturbanceMinutes }
            .enumerated()
            .map { index, option in
                ConflictOption(
                    id: UUID(),
                    kind: option.kind,
                    newStart: option.newStart,
                    newEnd: option.newEnd,
                    skipsOccurrence: option.skipsOccurrence,
                    disturbanceMinutes: option.disturbanceMinutes,
                    isRecommended: index == 0)
            }
    }

    // MARK: - RoutineBlock lookup

    /// Reverses `RoutineEngine`'s own `externalID` shape
    /// (`"<block.id>#<yyyy-MM-dd>"`) to find the `RoutineBlock` a
    /// materialized routine `Event` came from. `nil` for any event that is
    /// not `.routine`, has no `externalID`, or whose block id does not
    /// (any longer) match anything in `routineBlocks`.
    private static func routineBlock(for event: Event, in routineBlocks: [RoutineBlock]) -> RoutineBlock? {
        guard event.origin == .routine, let externalID = event.externalID else { return nil }
        guard let blockIDString = externalID.split(separator: "#").first,
              let blockID = UUID(uuidString: String(blockIDString))
        else { return nil }
        return routineBlocks.first { $0.id == blockID }
    }

    private static func roundUpToStep(_ minutes: Int, step: Int) -> Int {
        let remainder = minutes % step
        return remainder == 0 ? minutes : minutes + (step - remainder)
    }
}

/// Pre-ranking working value for one candidate option — no `id`, no
/// `isRecommended` yet, since both only mean something once `finalize` has
/// sorted the whole candidate list.
private struct RawOption {
    var kind: ConflictOptionKind
    var newStart: Date?
    var newEnd: Date?
    var skipsOccurrence: Bool
    var disturbanceMinutes: Int
}
