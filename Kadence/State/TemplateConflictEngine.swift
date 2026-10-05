//
//  TemplateConflictEngine.swift
//  Kadence
//
//  components.md §14.6 (task P2-T46): a template conflict is a §13.6.1
//  refusal — a routine block whose interval lands in a `.protected` window
//  on one or more of the template's active weekdays. There is no event on
//  either side, so this is its own pure engine next to `ConflictEngine`,
//  computed from templates and windows only (the same minutes-of-day
//  comparison `ProtectedWindowRule` makes, so the canvas, `materialize` and
//  this list can't disagree).
//
//  The options edit the ROUTINE, never a day: shift later / shift earlier /
//  shorten / remove, with §14.6's cap (three, `remove` always kept) and
//  §14.3.3's recommendation rule with `remove` in `skipToday`'s place.
//

import Foundation
import SwiftData

/// One block landing in one protected window, on the weekdays named.
struct TemplateConflict: Identifiable, Equatable {
    /// `<template>#<block>#<window>`: stable across recomputation, so a
    /// selection survives the store changing underneath it.
    let id: String
    let templateID: UUID
    let blockID: UUID
    let windowID: UUID
    let blockTitle: String
    let blockStartMinutes: Int
    let durationMinutes: Int
    let windowLabel: String
    let windowStartMinutes: Int
    let windowEndMinutes: Int
    /// The template's active weekdays this window refuses the block on, in
    /// column order.
    let weekdays: [Int]
    /// The overlap, in minutes of the day, on the first of `weekdays`.
    let overlapStartMinutes: Int
    let overlapEndMinutes: Int
    let options: [TemplateConflictOption]
}

/// §14.6's table, in its own kind order (the tie-break everywhere).
enum TemplateConflictOptionKind: String, CaseIterable, Sendable {
    case shiftLater, shiftEarlier, shorten, remove
}

struct TemplateConflictOption: Identifiable, Equatable {
    /// `<conflict id>#<kind>`: one option per kind per conflict.
    let id: String
    let kind: TemplateConflictOptionKind
    /// The block's proposed start and duration in minutes. `nil` for `remove`.
    let newStartMinutes: Int?
    let newDurationMinutes: Int?
    let disturbanceMinutes: Int
    let isRecommended: Bool
}

@MainActor
enum TemplateConflictEngine {

    /// "a 15-minute-stepped later start" (§14.6).
    static let step = 15
    /// §14.3.1's shorten floor, reused by §14.6 ("≥ 15 min").
    static let minimumMinutes = 15
    /// "Cap is three" (§14.6).
    static let cap = 3

    // MARK: Detection

    /// Every (block, protected window) pair that refuses the block on at
    /// least one active weekday, ordered by block start ("each by the start of
    /// what they affect", interactions.md §10.1), then id.
    static func detect(
        templates: [RoutineTemplate], windows: [TimeWindow], orderedWeekdays: [Int]
    ) -> [TemplateConflict] {
        let protected = windows.filter { $0.kind == .protected }
        var result: [TemplateConflict] = []
        for template in templates {
            let active = orderedWeekdays.filter { template.activeWeekdays.contains($0) }
            for block in template.blocks {
                let start = block.startMinutes
                let duration = Int((block.duration / 60).rounded())
                for window in protected {
                    let days = active.filter {
                        ProtectedWindowRule.refuses(startMinutes: start, duration: block.duration,
                                                    weekday: $0, windows: [window])
                    }
                    guard let first = days.first else { continue }
                    let overlap = overlapMinutes(start: start, duration: duration, window: window, weekday: first)
                    let id = "\(template.id.uuidString)#\(block.id.uuidString)#\(window.id.uuidString)"
                    result.append(TemplateConflict(
                        id: id, templateID: template.id, blockID: block.id, windowID: window.id,
                        blockTitle: block.title, blockStartMinutes: start, durationMinutes: duration,
                        windowLabel: window.label,
                        windowStartMinutes: window.startMinutes, windowEndMinutes: window.endMinutes,
                        weekdays: days,
                        overlapStartMinutes: overlap.lowerBound, overlapEndMinutes: overlap.upperBound,
                        options: options(
                            conflictID: id, start: start, duration: duration,
                            spans: protectedSpans(windows: protected, weekdays: active),
                            refusedWeekdayCount: refusedWeekdays(
                                start: start, duration: block.duration, weekdays: active, windows: protected).count)))
                }
            }
        }
        return result.sorted {
            $0.blockStartMinutes != $1.blockStartMinutes ? $0.blockStartMinutes < $1.blockStartMinutes : $0.id < $1.id
        }
    }

    private static func overlapMinutes(start: Int, duration: Int, window: TimeWindow, weekday: Int) -> Range<Int> {
        let end = start + duration
        let hits = ProtectedWindowRule.minuteSpans(of: window, onWeekday: weekday)
            .filter { $0.lowerBound < end && start < $0.upperBound }
        let lower = Swift.max(start, hits.map(\.lowerBound).min() ?? start)
        let upper = Swift.min(end, hits.map(\.upperBound).max() ?? end)
        return lower..<Swift.max(lower, upper)
    }

    /// Every `.protected` span on every active weekday — what an option has
    /// to clear. All windows, not just the one this conflict names, so an
    /// option never trades one refusal for another.
    static func protectedSpans(windows: [TimeWindow], weekdays: [Int]) -> [Range<Int>] {
        weekdays.flatMap { weekday in
            windows.filter { $0.kind == .protected }
                .flatMap { ProtectedWindowRule.minuteSpans(of: $0, onWeekday: weekday) }
        }
    }

    private static func refusedWeekdays(start: Int, duration: TimeInterval, weekdays: [Int], windows: [TimeWindow]) -> [Int] {
        weekdays.filter {
            ProtectedWindowRule.refuses(startMinutes: start, duration: duration, weekday: $0, windows: windows)
        }
    }

    // MARK: Options (§14.6)

    /// A candidate before ranking: kind, proposed start and duration, cost.
    typealias Raw = (kind: TemplateConflictOptionKind, start: Int?, duration: Int?, disturbance: Int)

    private static func clears(_ start: Int, _ duration: Int, _ spans: [Range<Int>]) -> Bool {
        start >= 0 && start + duration <= 1440
            && !spans.contains { $0.lowerBound < start + duration && start < $0.upperBound }
    }

    /// The §14.6 catalogue for a block at `start` lasting `duration` minutes,
    /// against `spans`. Capped at three with `remove` always kept, then put
    /// in display order (ascending disturbance, kind-order tie-break), with
    /// the recommendation marked. `internal` so tests can drive it directly.
    static func options(
        conflictID: String, start: Int, duration: Int, spans: [Range<Int>], refusedWeekdayCount: Int
    ) -> [TemplateConflictOption] {
        var candidates: [Raw] = []

        // shiftLater / shiftEarlier: the smallest 15-minute step that clears
        // every span, staying inside the day (0…1440).
        var k = 1
        while start + k * step + duration <= 1440 {
            if clears(start + k * step, duration, spans) {
                candidates.append((.shiftLater, start + k * step, duration, k * step)); break
            }
            k += 1
        }
        k = 1
        while start - k * step >= 0 {
            if clears(start - k * step, duration, spans) {
                candidates.append((.shiftEarlier, start - k * step, duration, k * step)); break
            }
            k += 1
        }

        // shorten: keep the larger remainder outside every colliding span
        // (front wins a tie, as in `ConflictEngine.shortenOption`).
        let end = start + duration
        let hits = spans.filter { $0.lowerBound < end && start < $0.upperBound }
        if !hits.isEmpty {
            let front = Swift.max(0, (hits.map(\.lowerBound).min() ?? start) - start)
            let back = Swift.max(0, end - (hits.map(\.upperBound).max() ?? end))
            let kept = Swift.max(front, back)
            if kept >= minimumMinutes {
                candidates.append((.shorten, front >= back ? start : end - kept, kept, duration - kept))
            }
        }

        let remove: Raw = (.remove, nil, nil, duration * refusedWeekdayCount)

        // Cap: `remove` always; the other slots to the lowest disturbance,
        // kind order breaking ties.
        let ordered = sortedForDisplay(candidates)
        let kept = Array(ordered.prefix(cap - 1)) + [remove]
        let display = sortedForDisplay(kept)

        let recommended: TemplateConflictOptionKind? = display.count > 1
            ? recommendedKind(display.map { ($0.kind, $0.disturbance, $0.duration) }, duration: duration)
            : nil

        return display.map { raw in
            TemplateConflictOption(
                id: "\(conflictID)#\(raw.kind.rawValue)", kind: raw.kind,
                newStartMinutes: raw.start, newDurationMinutes: raw.duration,
                disturbanceMinutes: raw.disturbance, isRecommended: raw.kind == recommended)
        }
    }

    private static func sortedForDisplay(_ raw: [Raw]) -> [Raw] {
        let rank = { (kind: TemplateConflictOptionKind) in TemplateConflictOptionKind.allCases.firstIndex(of: kind) ?? 0 }
        return raw.sorted {
            $0.disturbance != $1.disturbance ? $0.disturbance < $1.disturbance : rank($0.kind) < rank($1.kind)
        }
    }

    /// §14.6: "§14.3.3's rule with `remove` in `skipToday`'s place — a
    /// proportionate shift (either direction), else a shorten that keeps
    /// half, else `remove`." Among the offered options only. When both shifts
    /// qualify, the smaller one, kind order breaking a tie (`options` is
    /// already in that order).
    static func recommendedKind(
        _ offered: [(kind: TemplateConflictOptionKind, disturbance: Int, keptDuration: Int?)], duration: Int
    ) -> TemplateConflictOptionKind {
        if let shift = offered.first(where: {
            ($0.kind == .shiftLater || $0.kind == .shiftEarlier) && $0.disturbance <= duration
        }) {
            return shift.kind
        }
        if let shorten = offered.first(where: { $0.kind == .shorten }),
           let kept = shorten.keptDuration, kept * 2 >= duration {
            return .shorten
        }
        return .remove
    }

    // MARK: Copy (§14.6's table, §14.2's amended header)

    static func hhmm(_ minutes: Int) -> String {
        String(format: "%02d:%02d", (minutes / 60) % 24, minutes % 60)
    }

    static func days(_ weekdays: [Int], calendar: Calendar = .current) -> String {
        weekdays.map { calendar.shortWeekdaySymbols[($0 - 1) % 7] }.joined(separator: ", ")
    }

    private static func minutes(_ value: Int) -> String { ConflictOptionFormatting.minutes(value) }

    static func title(for option: TemplateConflictOption, conflict: TemplateConflict) -> String {
        let name = conflict.blockTitle
        switch option.kind {
        case .shiftLater: return "Shift \(name) \(minutes(option.disturbanceMinutes)) later in the routine"
        case .shiftEarlier: return "Shift \(name) \(minutes(option.disturbanceMinutes)) earlier in the routine"
        case .shorten: return "Shorten \(name) to \(minutes(option.newDurationMinutes ?? 0))"
        case .remove: return "Remove \(name) from this routine"
        }
    }

    static func delta(for option: TemplateConflictOption, conflict: TemplateConflict, calendar: Calendar = .current) -> String {
        let total = conflict.durationMinutes
        switch option.kind {
        case .shiftLater, .shiftEarlier:
            return "\(hhmm(conflict.blockStartMinutes)) → \(hhmm(option.newStartMinutes ?? 0))"
                + " · all \(minutes(total)) kept · every active day"
        case .shorten:
            let kept = option.newDurationMinutes ?? 0
            return "\(minutes(total)) → \(minutes(kept)) · \(minutes(total - kept)) lost · every active day"
        case .remove:
            return "Deletes the block · \(minutes(option.disturbanceMinutes)) lost across \(days(conflict.weekdays, calendar: calendar))"
        }
    }

    /// `22:30–23:15 · 45 min · Mon, Wed, Fri` (§14.6).
    static func overlapLine(_ conflict: TemplateConflict, calendar: Calendar = .current) -> String {
        "\(hhmm(conflict.overlapStartMinutes))–\(hhmm(conflict.overlapEndMinutes))"
            + " · \(minutes(conflict.overlapEndMinutes - conflict.overlapStartMinutes))"
            + " · \(days(conflict.weekdays, calendar: calendar))"
    }

    /// The window row's second label: `protected · 22:00–07:00` (§14.2).
    static func windowLine(_ conflict: TemplateConflict) -> String {
        "protected · \(hhmm(conflict.windowStartMinutes))–\(hhmm(conflict.windowEndMinutes))"
    }

    /// The word between the block and the window row (§14.2).
    static let landsIn = "lands in"
}

// MARK: - Applying a template option (§14.6, task P2-T46)

@MainActor
enum TemplateConflictResolver {

    /// The step's name; the Edit menu reads `Undo Resolve Routine Conflict`.
    static let undoName = "Resolve Routine Conflict"

    /// Writes `option` to the routine as ONE named undo step, and
    /// re-materialises the template inside that same step ("§13.6.3
    /// re-materialises behind it inside the same step", §14.6), so one `⌘Z`
    /// restores both the block and the calendar. Shift and shorten go through
    /// `RoutineBlockStore.move`/`resize` and `remove` through its `delete`,
    /// whose own §13.6.4 withdrawals join this step too (`UndoStack.perform`
    /// is re-entrant; the outermost name wins). Returns `false`, writing
    /// nothing, if the block or template no longer exists.
    @discardableResult
    static func apply(
        _ option: TemplateConflictOption, of conflict: TemplateConflict,
        context: ModelContext, undo: UndoStack,
        today: Date = Date(), visibleEnd: Date? = nil, calendar: Calendar = .current
    ) -> Bool {
        let templates = (try? context.fetch(FetchDescriptor<RoutineTemplate>())) ?? []
        guard let template = templates.first(where: { $0.id == conflict.templateID }),
              let block = template.blocks.first(where: { $0.id == conflict.blockID })
        else { return false }

        let blockStore = RoutineBlockStore(context: context, undo: undo, now: { today }, calendar: calendar)
        let eventStore = EventStore(context: context, undo: undo)
        undo.perform(undoName) { _ in
            switch option.kind {
            case .shiftLater, .shiftEarlier:
                if let start = option.newStartMinutes { blockStore.move(block, toStartMinutes: start) }
            case .shorten:
                if let start = option.newStartMinutes, let duration = option.newDurationMinutes {
                    blockStore.resize(block, newStartMinutes: start, newEndMinutes: start + duration)
                }
            case .remove:
                blockStore.delete(block, from: template)
            }
            let windows = (try? context.fetch(FetchDescriptor<TimeWindow>())) ?? []
            RoutineEngine.materialize(
                template: template,
                into: RoutineMaterialization.horizon(today: today, visibleEnd: visibleEnd, calendar: calendar),
                timeWindows: windows, today: today, recordsUndo: true, store: eventStore, calendar: calendar)
        }
        return true
    }
}
