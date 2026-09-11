//
//  RoutineEngine.swift
//  Kadence
//
//  Turns a `RoutineTemplate` into ordinary `Event`s on the calendar
//  (BRIEF-PRODUCT.md; components.md §13). This is the data-layer
//  materialisation pass only:
//
//  - No Routines window, no TimeWindow editor, no menu bar extra, no snooze
//    (components.md §13, layouts.md §8, interactions.md §11, §15, §16).
//  - No conflict detection (components.md §14).
//  - No detachment tracking or re-sync (components.md §13.4, interactions.md
//    §11.2). This engine never touches a materialized event once it exists —
//    it only ever checks whether one is already there and, if so, leaves it
//    alone. Recognising that an existing event has since been hand-edited (so
//    that re-sync can offer to overwrite it) needs the main-grid edit-command
//    path wired up first, which is a separate follow-up task.
//
//  Each materialized event gets a `(sourceID, externalID)` pair —
//  `(template.id.uuidString, "<block.id>#<yyyy-MM-dd>")` — which is exactly
//  the identity `Event.swift`'s doc comment describes as "stable across
//  re-sync, so importing twice updates instead of duplicating". Here that
//  means: calling `materialize` again over an overlapping range creates
//  nothing new for a date/block pair that already exists.
//

import Foundation
import SwiftData

@MainActor
enum RoutineEngine {

    /// Create one `Event` per `(active weekday × block)` pair in `range`,
    /// skipping any pair that already has a materialized event. Everything
    /// this call does — every block, every date — is one named, undoable step.
    ///
    /// - Returns: the number of *new* events created. Re-running with the same
    ///   template and range returns 0 and leaves the store unchanged.
    @discardableResult
    static func materialize(
        template: RoutineTemplate,
        into range: DateInterval,
        store: EventStore,
        calendar: Calendar = .current
    ) -> Int {
        guard !template.blocks.isEmpty, !template.activeWeekdays.isEmpty else { return 0 }

        let context = store.context
        let sourceID = template.id.uuidString
        var createdCount = 0

        store.transaction("Materialize \(template.name)") {
            var day = calendar.startOfDay(for: range.start)

            while day < range.end {
                if template.activeWeekdays.contains(calendar.component(.weekday, from: day)) {
                    let key = dayKey(day, calendar: calendar)

                    for block in template.blocks {
                        let externalID = "\(block.id.uuidString)#\(key)"

                        // Idempotence: a pair that already exists is left
                        // alone rather than duplicated or overwritten. Once a
                        // hand-edit can be told apart from an untouched
                        // instance (§13.4, out of scope here), this is where
                        // re-sync would instead offer to replace it.
                        guard !eventExists(sourceID: sourceID, externalID: externalID, in: context) else {
                            continue
                        }
                        guard let blockStart = calendar.date(
                            byAdding: .minute, value: block.startMinutes, to: day)
                        else { continue }

                        let event = Event(
                            title: block.title,
                            start: blockStart,
                            end: blockStart.addingTimeInterval(block.duration),
                            origin: .routine,
                            flexibility: block.flexibility,
                            sourceKey: template.sourceKey,
                            sourceID: sourceID,
                            externalID: externalID)
                        store.insertMaterialized(EventSnapshot(event))
                        createdCount += 1
                    }
                }

                guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                day = next
            }
        }

        return createdCount
    }

    // MARK: - Identity

    private static func eventExists(sourceID: String, externalID: String, in context: ModelContext) -> Bool {
        var descriptor = FetchDescriptor<Event>(predicate: #Predicate { event in
            event.sourceID == sourceID && event.externalID == externalID
        })
        descriptor.fetchLimit = 1
        return !((try? context.fetch(descriptor)) ?? []).isEmpty
    }

    /// `yyyy-MM-dd` of `date`, read through `calendar`'s own components rather
    /// than a `DateFormatter`, so the key matches exactly the day this engine
    /// iterated to, with no locale or timezone formatting to second-guess.
    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }
}
