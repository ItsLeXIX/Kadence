//
//  RoutineResync.swift
//  Kadence
//
//  components.md §13.7.3 and interactions.md §11.2 (task P2-T44): the
//  Routines window's detached-instance count and its Re-sync action.
//
//  - Scope: "the detached, non-tombstoned instances of this template whose
//    day falls in the horizon (§13.6.5), from `startOfDay(today)` forward."
//    A tombstoned pair has no event, so "non-tombstoned" holds by
//    construction. Released instances (§13.6.4, G-033) are not detached and
//    are not in scope.
//  - Copy: `3 instances edited` / `1 instance edited` (no "this week"),
//    hidden at zero; the popover lists the dates, up to six then `+N`; the
//    primary action reads `Re-sync 3 instances` / `Re-sync 1 instance`.
//  - Apply: the template's CURRENT values into every listed instance, every
//    flag cleared, status left alone, as ONE undo step, `Re-sync Routine`
//    (the Edit menu reads `Undo Re-sync Routine`).
//

import Foundation
import SwiftData

@MainActor
enum RoutineResync {

    /// "up to six then `+N`" (§13.4, §13.7.3).
    static let maxListedDates = 6
    /// interactions.md §11.2's step name; `UndoStack` prepends "Undo ".
    static let undoName = "Re-sync Routine"

    /// The detached instances of `template` in scope, in date order.
    static func scope(
        of template: RoutineTemplate, in context: ModelContext,
        today: Date, visibleEnd: Date?, calendar: Calendar = .current
    ) -> [Event] {
        let sourceID = template.id.uuidString
        let descriptor = FetchDescriptor<Event>(predicate: #Predicate { $0.sourceID == sourceID })
        return scope(of: template, among: (try? context.fetch(descriptor)) ?? [],
                     today: today, visibleEnd: visibleEnd, calendar: calendar)
    }

    /// The same, picked out of an already-fetched list (the Routines window
    /// passes its `@Query` result, so an edit in the main window re-renders
    /// the count).
    static func scope(
        of template: RoutineTemplate, among events: [Event],
        today: Date, visibleEnd: Date?, calendar: Calendar = .current
    ) -> [Event] {
        let horizon = RoutineMaterialization.horizon(today: today, visibleEnd: visibleEnd, calendar: calendar)
        let sourceID = template.id.uuidString
        return events
            .compactMap { event -> (Date, Event)? in
                guard event.sourceID == sourceID, event.origin == .routine, event.isDetached,
                      let pair = RoutineEngine.parse(externalID: event.externalID, calendar: calendar),
                      horizon.start <= pair.day, pair.day < horizon.end
                else { return nil }
                return (pair.day, event)
            }
            .sorted { $0.0 != $1.0 ? $0.0 < $1.0 : $0.1.start < $1.1.start }
            .map(\.1)
    }

    /// `3 instances edited` / `1 instance edited`; `nil` at zero, because the
    /// count is "hidden entirely at zero" (§13.4).
    static func countText(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? "1 instance edited" : "\(count) instances edited"
    }

    /// `Re-sync 3 instances` / `Re-sync 1 instance`.
    static func actionTitle(_ count: Int) -> String {
        count == 1 ? "Re-sync 1 instance" : "Re-sync \(count) instances"
    }

    /// The popover's rows: up to six dates, then `+N more` for the rest
    /// (components.md §13.4, amended 2026-10-05, closes G-034 — "with `more`,
    /// matching §15.2's `+N more`"). Dates read `Tue 6`:
    /// `shortStandaloneWeekdaySymbols` and the day of the month. The pair's own day, not the instance's current
    /// start, which a detaching move may have changed.
    static func dateRows(
        for instances: [Event], calendar: Calendar = .current
    ) -> (dates: [String], overflow: String?) {
        let days = instances.compactMap { RoutineEngine.parse(externalID: $0.externalID, calendar: calendar)?.day }
        let labels = days.map { day in
            let weekday = calendar.component(.weekday, from: day)
            return "\(calendar.shortStandaloneWeekdaySymbols[weekday - 1]) \(calendar.component(.day, from: day))"
        }
        let rest = labels.count - maxListedDates
        return (Array(labels.prefix(maxListedDates)), rest > 0 ? "+\(rest) more" : nil)
    }

    /// Re-sync: every instance in `instances` back to the template's current
    /// values, as one step. Each `revertToRoutine` call joins this step
    /// (`UndoStack.perform` is re-entrant), so one `⌘Z` restores every
    /// instance to its edited state and flag. Returns how many were written.
    @discardableResult
    static func apply(_ instances: [Event], store: EventStore, calendar: Calendar = .current) -> Int {
        var written = 0
        store.transaction(undoName) {
            for event in instances where event.isDetached {
                if RoutineInstance.revert(event, store: store, calendar: calendar) { written += 1 }
            }
        }
        return written
    }
}
