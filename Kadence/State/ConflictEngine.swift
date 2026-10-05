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
//  Task P2-T19 adds the brief's other named conflict clause — "any automatic
//  placement that would land in a protected window" — as
//  `detectWindowConflicts` below, now that `TimeWindow` (Kadence/Models/
//  TimeWindow.swift, task P2-T18) exists. It is a separate function returning
//  a separate `WindowConflict` type rather than folding into `detect`/
//  `Conflict`; see `detectWindowConflicts`'s own doc comment for why, and see
//  its doc comment for the deliberate forward-reference this leaves for
//  whichever task next wires a window conflict into `ConflictPanelView` (out
//  of scope here, per that task's own brief item 4).
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

    /// 1–3 options (§14.3.1's catalogue), ordered by ascending disturbance
    /// then kind order. Two or three carry exactly one `isRecommended`; a
    /// single option carries none (§14.3.3).
    let options: [ConflictOption]
}

/// One overlap between a `.routine` event and a `.protected`-kind
/// `TimeWindow`'s span — BRIEF-PRODUCT.md Phase 2's "any automatic placement
/// that would land in a protected window" clause, distinct from `Conflict`
/// above (which is the brief's other, routine-vs-manual/imported clause).
///
/// Deliberately a sibling type to `Conflict`, not a variant of it — see
/// `ConflictEngine.detectWindowConflicts`'s own doc comment for why.
struct WindowConflict: Identifiable {
    /// Deterministic per (event, window, span) triple, same reasoning as
    /// `Conflict.id`.
    let id: String

    /// The `.routine`-origin event landing in the window.
    let routineEvent: Event
    /// The `.protected` window it lands in.
    let window: TimeWindow

    /// The overlap window itself, same meaning as `Conflict.overlapStart`/
    /// `overlapEnd`.
    let overlapStart: Date
    let overlapEnd: Date

    /// Same option shape, same ranking, as `Conflict.options`.
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

    /// components.md §14.3.3: exactly one option carries the chip when there
    /// are two or three, chosen by the preservation rule (not necessarily the
    /// first row); a single-option conflict has none (task P2-T45).
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
                    routineEvent: pair.routine,
                    otherInterval: Interval(start: pair.other.start, end: pair.other.end),
                    routineBlocks: routineBlocks)

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

    /// The brief's other named conflict clause: "any automatic placement
    /// that would land in a protected window" (BRIEF-PRODUCT.md Phase 2),
    /// now buildable since `TimeWindow` (task P2-T18) exists. Only
    /// `.protected`-kind windows count — `.lowEnergy`/`.peakFocus` are not
    /// named by that clause, so a routine event landing only in one of those
    /// produces no conflict here, unlike `detect` above which has no such
    /// kind filter to begin with.
    ///
    /// Reuses `makeOptions`/`finalize` — same option kinds
    /// (shiftLater/shorten/skipToday), same disturbance-minutes scale, same
    /// "exactly one `isRecommended`, ascending order" ranking as `detect`'s
    /// event-vs-event conflicts. `shiftLaterOption`/`shortenOption` were
    /// generalized to take a plain `Interval` (start/end) rather than a full
    /// `Event` so they could serve both this function and `detect` above
    /// without a protected window having to masquerade as an `Event`.
    ///
    /// Surfaced as `WindowConflict`, a sibling type to `Conflict`, rather
    /// than a variant of `Conflict` itself: `Conflict.otherEvent` is a live
    /// `Event` that this file's own header comment says a future task will
    /// call `EventStore.move`/`resize`/`skip` on; a `TimeWindow` supports none
    /// of those operations, so folding it into the same field would mean
    /// either weakening `otherEvent`'s non-optional guarantee for every
    /// existing call site or inventing a lossy stand-in `Event` for a window
    /// — neither is warranted just to avoid a second, tiny result type. How
    /// (or whether) `WindowConflict` surfaces next to `Conflict` in
    /// `ConflictPanelView` — e.g. what the collision header shows when the
    /// "other side" is a window, not a block (components.md §14.2) — is left
    /// as a forward reference for that follow-up task; this file does not
    /// touch `ConflictPanelView.swift`, per this task's own brief. Nothing
    /// about `components.md` §14 answers that question today, but nothing in
    /// this function's own scope needs it answered either, so no
    /// `design/GAPS.md` entry is filed for it (contrast `detect`'s G-015,
    /// which *did* need an answer to keep working).
    ///
    /// Pure: reads `events`/`routineBlocks`/`timeWindows`, mutates nothing.
    /// `calendar` defaults to `.current`, same as `TimeWindow.spans(on:)`
    /// itself; a caller with a fixed test calendar can still pass one in.
    static func detectWindowConflicts(
        events: [Event], routineBlocks: [RoutineBlock], timeWindows: [TimeWindow], calendar: Calendar = .current
    ) -> [WindowConflict] {
        let protectedWindows = timeWindows.filter { $0.kind == .protected }
        guard !protectedWindows.isEmpty else { return [] }

        var conflicts: [WindowConflict] = []
        for event in events {
            // Same `.skipped` filter, same reasoning, as `detect`'s own
            // inline comment / G-015: a skipped occurrence is not "landing"
            // anywhere any more.
            guard event.origin == .routine, event.status != .skipped else { continue }

            for window in protectedWindows {
                for span in window.spans(on: event.start, calendar: calendar) {
                    guard event.start < span.end && span.start < event.end else { continue }

                    let overlapStart = Swift.max(event.start, span.start)
                    let overlapEnd = Swift.min(event.end, span.end)
                    let options = makeOptions(
                        routineEvent: event,
                        otherInterval: Interval(start: span.start, end: span.end),
                        routineBlocks: routineBlocks)

                    conflicts.append(WindowConflict(
                        id: "\(event.id.uuidString)#\(window.id.uuidString)#\(Int(span.start.timeIntervalSinceReferenceDate))",
                        routineEvent: event,
                        window: window,
                        overlapStart: overlapStart,
                        overlapEnd: overlapEnd,
                        options: options))
                }
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

    /// components.md §14.3.1's catalogue (task P2-T45, closes G-017 in
    /// code): exactly three kinds, each added when it is available.
    ///
    /// - `shiftLater`: `.shiftable` only, when the smallest 15-minute-stepped
    ///   later shift that clears the collision is within the block's ±.
    /// - `shorten`: **any** flexibility, when the larger remainder is ≥ 15
    ///   min. Before P2-T45 this was gated behind `.fixed`, which no spec
    ///   asked for, so `.droppable` got one option and `.shiftable` never
    ///   reached three.
    /// - `skipToday`: always, and never removed (§14.3.2).
    ///
    /// No `shiftEarlier` at day level (§14.3.1). The cap is three, which the
    /// catalogue can't exceed, so nothing is ever dropped.
    private static func makeOptions(
        routineEvent: Event, otherInterval: Interval, routineBlocks: [RoutineBlock]
    ) -> [ConflictOption] {
        var raw: [RawOption] = []
        if routineEvent.flexibility == .shiftable,
           let shift = shiftLaterOption(routineEvent: routineEvent, otherInterval: otherInterval, routineBlocks: routineBlocks) {
            raw.append(shift)
        }
        if let shorten = shortenOption(routineEvent: routineEvent, otherInterval: otherInterval) {
            raw.append(shorten)
        }
        raw.append(skipOption(for: routineEvent))
        return finalize(raw, occurrenceMinutes: Int((routineEvent.duration / 60).rounded()))
    }

    /// Minimal 15-minute-incremented later shift that clears the overlap
    /// (new start at or after `otherInterval.end`), clamped to the routine
    /// block's own `shiftableMinutes`. `nil` when no matching `RoutineBlock`
    /// is found, it has no `shiftableMinutes`, or the needed shift exceeds it.
    ///
    /// Takes a plain `Interval` rather than a full `Event` — generalized in
    /// task P2-T19 so this same function serves both `detect` (the other
    /// side is a real `Event`) and `detectWindowConflicts` (the other side is
    /// a `TimeWindow` span, which is not an `Event`). Behavior for existing
    /// `detect` call sites is unchanged: they pass `Interval(start:
    /// otherEvent.start, end: otherEvent.end)`, identical to reading
    /// `otherEvent.start`/`.end` directly as this function did before.
    private static func shiftLaterOption(
        routineEvent: Event, otherInterval: Interval, routineBlocks: [RoutineBlock]
    ) -> RawOption? {
        guard let block = routineBlock(for: routineEvent, in: routineBlocks),
              let range = block.shiftableMinutes, range > 0
        else { return nil }

        let neededSeconds = otherInterval.end.timeIntervalSince(routineEvent.start)
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

    /// Trims `routineEvent` to end where `otherInterval` starts, or to start
    /// where `otherInterval` ends — whichever leaves more of the original
    /// duration (ties favour trimming from the end, i.e. keeping the
    /// original start). `nil` when the longer of the two candidates would
    /// still fall below the 15-minute floor.
    ///
    /// Same generalization as `shiftLaterOption` above, same "no behavior
    /// change for `detect`'s existing call sites" guarantee.
    private static func shortenOption(routineEvent: Event, otherInterval: Interval) -> RawOption? {
        let keepFront = Swift.max(0, otherInterval.start.timeIntervalSince(routineEvent.start))
        let keepBack = Swift.max(0, routineEvent.end.timeIntervalSince(otherInterval.end))

        let newStart: Date
        let newEnd: Date
        let keptDuration: TimeInterval
        if keepFront >= keepBack {
            newStart = routineEvent.start
            newEnd = otherInterval.start
            keptDuration = keepFront
        } else {
            newStart = otherInterval.end
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

    /// Display order and the recommendation, which are deliberately two
    /// different rules (components.md §14.3.2 / §14.3.3):
    ///
    /// - **Order:** ascending `disturbanceMinutes`, ties broken by kind order
    ///   (`ConflictOptionKind.allCases`: shiftLater, shorten, skipToday).
    /// - **Recommendation:** the first kind that preserves the occurrence
    ///   proportionately — `recommendedKind` below. It can be the second or
    ///   third row.
    /// - **A single option carries no recommendation at all** — "a
    ///   recommendation among one is noise".
    ///
    /// `id: UUID()` is assigned here, once an option survives into the final
    /// list.
    private static func finalize(_ raw: [RawOption], occurrenceMinutes: Int) -> [ConflictOption] {
        let recommended = raw.count > 1 ? recommendedKind(raw, occurrenceMinutes: occurrenceMinutes) : nil
        return displayOrder(raw).map { option in
            ConflictOption(
                id: UUID(),
                kind: option.kind,
                newStart: option.newStart,
                newEnd: option.newEnd,
                skipsOccurrence: option.skipsOccurrence,
                disturbanceMinutes: option.disturbanceMinutes,
                isRecommended: option.kind == recommended)
        }
    }

    /// Ascending disturbance, then kind order (§14.3.2).
    private static func displayOrder(_ raw: [RawOption]) -> [RawOption] {
        let rank = { (kind: ConflictOptionKind) in ConflictOptionKind.allCases.firstIndex(of: kind) ?? 0 }
        return raw.sorted {
            $0.disturbanceMinutes != $1.disturbanceMinutes
                ? $0.disturbanceMinutes < $1.disturbanceMinutes
                : rank($0.kind) < rank($1.kind)
        }
    }

    /// §14.3.3, first that qualifies:
    /// 1. `shiftLater` if its minutes ≤ the occurrence's own duration;
    /// 2. `shorten` if it keeps ≥ half the original duration;
    /// 3. `skipToday` otherwise.
    /// `internal` (not `private`) only so tests can pin the rule directly.
    static func recommendedKind(
        shiftMinutes: Int?, shortenTrimmedMinutes: Int?, occurrenceMinutes: Int
    ) -> ConflictOptionKind {
        if let shiftMinutes, shiftMinutes <= occurrenceMinutes { return .shiftLater }
        if let trimmed = shortenTrimmedMinutes, (occurrenceMinutes - trimmed) * 2 >= occurrenceMinutes {
            return .shorten
        }
        return .skipToday
    }

    private static func recommendedKind(_ raw: [RawOption], occurrenceMinutes: Int) -> ConflictOptionKind {
        recommendedKind(
            shiftMinutes: raw.first { $0.kind == .shiftLater }?.disturbanceMinutes,
            shortenTrimmedMinutes: raw.first { $0.kind == .shorten }?.disturbanceMinutes,
            occurrenceMinutes: occurrenceMinutes)
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

/// A plain start/end span — what `shiftLaterOption`/`shortenOption`/
/// `makeOptions` compare the routine event against, whether "the other side"
/// is a real `Event` (`detect`) or a `TimeWindow` span (`detectWindowConflicts`).
/// Exists solely so those functions don't need a full `Event` just to read
/// two `Date`s off it.
private struct Interval {
    let start: Date
    let end: Date
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
