//
//  RoutineEngine.swift
//  Kadence
//
//  Turns a `RoutineTemplate` into ordinary `Event`s on the calendar
//  (BRIEF-PRODUCT.md; components.md §13). This is the data-layer
//  materialisation pass.
//
//  As of task P2-T40 it has call sites (`RoutineMaterialization.run`, below,
//  driven by the triggers in components.md §13.6.5), never writes before
//  today, and refuses pairs inside a `.protected` window (§13.6.1). As of
//  P2-T41 it implements §13.6.3's whole per-pair table (create / update /
//  leave detached / leave tombstoned) and §13.6.4's withdrawal.
//
//  Each materialized event gets a `(sourceID, externalID)` pair —
//  `(template.id.uuidString, "<block.id>#<yyyy-MM-dd>")` — which is exactly
//  the identity `Event.swift`'s doc comment describes as "stable across
//  re-sync, so importing twice updates instead of duplicating". Here that
//  means: calling `materialize` again over an overlapping range creates
//  nothing new for a date/block pair that already exists; it updates it.
//  `ConflictEngine.routineBlock(for:in:)` reverses the same `externalID` to
//  find a routine event's block and its ± minutes.
//
//  `RoutineBlockStore` below (tasks P2-T11, P2-T12) is the Routines-window
//  sibling of `EventStore`: move, resize, delete AND (as of P2-T12) create for
//  `RoutineBlock`s, undoable and named, per interactions.md §11.1 ("Creating,
//  moving and resizing routine blocks uses §3 and §4 unchanged ... `⌫`
//  deletes. `⌘Z` undoes, with names"). Not a UI type — `RoutinesWindow.swift`
//  is what calls it from a drag gesture, a double-click and a key handler.
//  The flexibility control remains out of scope (see `RoutinesWindow.swift`'s
//  own header).
//

import Foundation
import SwiftData

@MainActor
enum RoutineEngine {

    /// components.md §13.6.3's per-pair table, over every `(active weekday ×
    /// block)` pair in `range`:
    ///
    /// | Pair state                         | Does                                   |
    /// |------------------------------------|----------------------------------------|
    /// | no event, no tombstone             | create, unless §13.6.1 refuses         |
    /// | event exists, not detached         | update title/start/end/flexibility     |
    /// | event exists, detached (§13.7)     | leave it completely alone              |
    /// | no event, tombstoned (§13.7.4)     | leave it deleted                       |
    /// | template no longer produces it     | §13.6.4 — `withdraw`, below            |
    ///
    /// An update carries `status` forward unchanged. A pair that exists but
    /// is now refused is not updated here; `withdraw` deletes it.
    ///
    /// Two more rules from §13.6:
    ///
    /// - **The past is never written (§13.6.5).** Days before
    ///   `startOfDay(today)` are skipped, whatever `range` asks for. So
    ///   tombstones before today are never consulted either.
    /// - **Protected windows refuse (§13.6.1).** A pair whose interval
    ///   strictly overlaps a `.protected` span in `timeWindows` gets no event.
    ///   It is not trimmed and not shifted. `ProtectedWindowRule` below makes
    ///   that decision, and the Routines window's `conflicted` presentation
    ///   uses the same rule, so the canvas and the calendar can't disagree.
    ///
    /// Idempotent: with the same inputs a second call creates and updates
    /// nothing.
    ///
    /// Undo: with `recordsUndo == true` (the default), the whole call is one
    /// named step, or it joins the step that is already open if called
    /// inside one (`UndoStack.perform`'s re-entrancy). The background
    /// triggers (`RoutineMaterialization.run`) pass `false`. Launch, a
    /// visible-range change and an edit are not the user asking for these
    /// events, so they put nothing on the Edit menu.
    ///
    /// - Returns: the number of *new* events created (updates are not
    ///   counted). Re-running with the same inputs returns 0.
    @discardableResult
    static func materialize(
        template: RoutineTemplate,
        into range: DateInterval,
        timeWindows: [TimeWindow] = [],
        today: Date = Date(),
        recordsUndo: Bool = true,
        store: EventStore,
        calendar: Calendar = .current,
        isDetached: @MainActor (Event) -> Bool = RoutineDetachment.isDetached
    ) -> Int {
        guard !template.blocks.isEmpty, !template.activeWeekdays.isEmpty else { return 0 }

        let context = store.context
        let sourceID = template.id.uuidString
        // One fetch each instead of one per pair. A dictionary keyed by
        // `externalID` is the in-memory form of the `(sourceID, externalID)`
        // identity: `sourceID` is fixed for this template.
        let existing = instancesByExternalID(sourceID: sourceID, in: context)
        let tombstoned = RoutineTombstones.externalIDs(sourceID: sourceID, in: context)

        var created: [EventSnapshot] = []
        var updated: [(id: UUID, values: EventStore.RoutineValues)] = []

        // §13.6.5: start at today if `range` reaches into the past.
        var day = Swift.max(calendar.startOfDay(for: range.start), calendar.startOfDay(for: today))

        while day < range.end {
            let weekday = calendar.component(.weekday, from: day)
            if template.activeWeekdays.contains(weekday) {
                let key = dayKey(day, calendar: calendar)

                for block in template.blocks {
                    let externalID = "\(block.id.uuidString)#\(key)"
                    // §13.6.1: refuse. Skips this pair only, so the same
                    // block still materialises on its other days. An
                    // existing instance of a refused pair is `withdraw`'s.
                    guard !ProtectedWindowRule.refuses(
                        startMinutes: block.startMinutes, duration: block.duration,
                        weekday: weekday, windows: timeWindows)
                    else { continue }
                    guard let blockStart = calendar.date(
                        byAdding: .minute, value: block.startMinutes, to: day)
                    else { continue }
                    let values = EventStore.RoutineValues(
                        title: block.title,
                        start: blockStart,
                        end: blockStart.addingTimeInterval(block.duration),
                        flexibility: block.flexibility)

                    if let event = existing[externalID] {
                        // Row 3: detached → leave alone. Row 2: update.
                        if isDetached(event) { continue }
                        if EventStore.RoutineValues(event) != values {
                            updated.append((event.id, values))
                        }
                    } else if !tombstoned.contains(externalID) {
                        // Row 1: create. (Row 4, tombstoned, falls through
                        // to nothing.)
                        created.append(EventSnapshot(Event(
                            title: values.title,
                            start: values.start,
                            end: values.end,
                            origin: .routine,
                            flexibility: values.flexibility,
                            sourceKey: template.sourceKey,
                            sourceID: sourceID,
                            externalID: externalID)))
                    }
                }
            }

            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        guard !created.isEmpty || !updated.isEmpty else { return 0 }
        if recordsUndo {
            store.transaction("Materialize \(template.name)") {
                for snapshot in created { store.insertMaterialized(snapshot) }
                for update in updated { store.updateRoutineInstance(update.id, to: update.values) }
            }
        } else {
            store.insertUnrecorded(created)
            store.updateRoutineInstancesUnrecorded(updated)
        }
        return created.count
    }

    /// components.md §13.6.4: deletes every future, non-detached instance of
    /// `template` whose pair the template no longer produces, because its
    /// weekday was deactivated, its block was deleted, or §13.6.1 now refuses
    /// it. Detached instances are kept. Past instances (pair day before
    /// `startOfDay(today)`) are never touched (§13.6.5).
    ///
    /// Not bounded by the horizon: an instance created while the visible
    /// range reached further out is still withdrawn.
    ///
    /// With `recordsUndo == true` each deletion is recorded and joins the
    /// open step, which is how `Remove Saturday from Routine` and `Delete
    /// Routine Block` undo their withdrawals in the same `⌘Z`. Withdrawal
    /// leaves no tombstone (`EventStore.withdraw`).
    ///
    /// - Returns: the number of instances deleted.
    @discardableResult
    static func withdraw(
        template: RoutineTemplate,
        timeWindows: [TimeWindow] = [],
        today: Date = Date(),
        recordsUndo: Bool = true,
        store: EventStore,
        calendar: Calendar = .current,
        isDetached: @MainActor (Event) -> Bool = RoutineDetachment.isDetached
    ) -> Int {
        let todayStart = calendar.startOfDay(for: today)
        let blocksByID = Dictionary(template.blocks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var withdrawn: [UUID] = []
        var released: [UUID] = []

        for event in instancesByExternalID(sourceID: template.id.uuidString, in: store.context).values {
            guard let pair = parse(externalID: event.externalID, calendar: calendar),
                  pair.day >= todayStart
            else { continue }

            let weekday = calendar.component(.weekday, from: pair.day)
            let stillProduced: Bool = {
                guard template.activeWeekdays.contains(weekday),
                      let block = blocksByID[pair.blockID]
                else { return false }
                return !ProtectedWindowRule.refuses(
                    startMinutes: block.startMinutes, duration: block.duration,
                    weekday: weekday, windows: timeWindows)
            }()
            guard !stillProduced else { continue }

            // A `.released` instance is an ordinary event already: kept.
            if event.routineLink == .released { continue }
            if isDetached(event) {
                // §13.6.4: kept, and it "stops being detached" — released,
                // in the same step as the rest of the withdrawal.
                released.append(event.id)
                continue
            }
            withdrawn.append(event.id)
        }

        guard !withdrawn.isEmpty || !released.isEmpty else { return 0 }
        if recordsUndo {
            // Sorted only so the order of the recorded changes doesn't depend
            // on dictionary order.
            for id in withdrawn.sorted(by: { $0.uuidString < $1.uuidString }) { store.withdraw(id) }
            for id in released.sorted(by: { $0.uuidString < $1.uuidString }) { store.release(id) }
        } else {
            store.withdrawUnrecorded(withdrawn)
            store.releaseUnrecorded(released)
        }
        return withdrawn.count
    }

    /// `withdraw` for every template in the store, against every window in
    /// the store, recorded. The store-level edits that can stop a pair being
    /// produced (`RoutineTemplateStore.setWeekday`, `RoutineBlockStore`'s
    /// delete/move/resize, every `TimeWindowStore` edit) call this inside
    /// their own step.
    @discardableResult
    static func withdrawAll(store: EventStore, today: Date, calendar: Calendar) -> Int {
        let context = store.context
        let templates = (try? context.fetch(FetchDescriptor<RoutineTemplate>())) ?? []
        let windows = (try? context.fetch(FetchDescriptor<TimeWindow>())) ?? []
        return templates.reduce(0) { total, template in
            total + withdraw(template: template, timeWindows: windows, today: today,
                             recordsUndo: true, store: store, calendar: calendar)
        }
    }

    // MARK: - Identity

    /// Every materialised instance of one template, keyed by `externalID`.
    /// If a store somehow holds two rows for one pair, the first wins here
    /// and the second is left alone rather than crashing the dictionary.
    private static func instancesByExternalID(sourceID: String, in context: ModelContext) -> [String: Event] {
        let descriptor = FetchDescriptor<Event>(predicate: #Predicate { $0.sourceID == sourceID })
        let events = ((try? context.fetch(descriptor)) ?? []).filter { $0.origin == .routine }
        var byID: [String: Event] = [:]
        for event in events {
            guard let externalID = event.externalID, byID[externalID] == nil else { continue }
            byID[externalID] = event
        }
        return byID
    }

    /// `yyyy-MM-dd` of `date`, read through `calendar`'s own components rather
    /// than a `DateFormatter`, so the key matches exactly the day this engine
    /// iterated to, with no locale or timezone formatting to second-guess.
    private static func dayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    /// The inverse of the `"<block id>#yyyy-MM-dd"` key: which block, and
    /// the start of which day in `calendar`. `nil` for anything else.
    static func parse(externalID: String?, calendar: Calendar) -> (blockID: UUID, day: Date)? {
        guard let externalID else { return nil }
        let parts = externalID.split(separator: "#")
        guard parts.count == 2, let blockID = UUID(uuidString: String(parts[0])) else { return nil }
        let ymd = parts[1].split(separator: "-").compactMap { Int($0) }
        guard ymd.count == 3,
              let day = calendar.date(from: DateComponents(year: ymd[0], month: ymd[1], day: ymd[2]))
        else { return nil }
        return (blockID, calendar.startOfDay(for: day))
    }
}

// MARK: - An instance and its template (task P2-T43)

/// What the main-grid inspector says about a selected routine instance
/// (components.md §13.4 / §13.6.4), and what `Revert to routine` writes.
@MainActor
enum RoutineInstance {

    /// The inspector line's two forms. `nil` for anything else (a linked
    /// instance, a non-routine event, a hand-seeded `.routine` fixture).
    enum Status: Equatable {
        /// `Edited — differs from <routine>`, with `Revert to routine`.
        case edited(routineName: String)
        /// `No longer part of <routine>`, no action (§13.6.4).
        case released(routineName: String)
    }

    static func template(of event: Event, in context: ModelContext) -> RoutineTemplate? {
        guard RoutineTombstones.pair(of: event) != nil,
              let sourceID = event.sourceID, let id = UUID(uuidString: sourceID)
        else { return nil }
        var descriptor = FetchDescriptor<RoutineTemplate>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    static func status(of event: Event, in context: ModelContext) -> Status? {
        guard let template = template(of: event, in: context) else { return nil }
        switch event.routineLink {
        case .linked: return nil
        case .detached: return .edited(routineName: template.name)
        case .released: return .released(routineName: template.name)
        }
    }

    /// The template's **current** values for this instance's pair
    /// (§13.7.2: "read live from the `RoutineBlock`"): its block's title,
    /// start and duration on the pair's own day, and flexibility. `nil` if
    /// the block no longer exists.
    static func templateValues(
        for event: Event, in context: ModelContext, calendar: Calendar = .current
    ) -> EventStore.RoutineValues? {
        guard let template = template(of: event, in: context),
              let pair = RoutineEngine.parse(externalID: event.externalID, calendar: calendar),
              let block = template.blocks.first(where: { $0.id == pair.blockID }),
              let start = calendar.date(byAdding: .minute, value: block.startMinutes, to: pair.day)
        else { return nil }
        return EventStore.RoutineValues(
            title: block.title, start: start, end: start.addingTimeInterval(block.duration),
            flexibility: block.flexibility)
    }

    /// `Revert to routine`: one step, `Revert Instance to Routine`. Only a
    /// detached instance whose block still exists can be reverted.
    @discardableResult
    static func revert(_ event: Event, store: EventStore, calendar: Calendar = .current) -> Bool {
        guard event.routineLink == .detached,
              let values = templateValues(for: event, in: store.context, calendar: calendar)
        else { return false }
        store.revertToRoutine(event, values: values)
        return true
    }

    /// components.md §13.4's exact copy, split at the dash into the
    /// inspector's label and value the way §13.6.2's `Will not run —` line is.
    static let editedLabel = "Edited —"
    static func editedValue(routineName: String) -> String { "differs from \(routineName)" }
    static let revertActionTitle = "Revert to routine"
    /// §13.6.4's exact copy.
    static func releasedLine(routineName: String) -> String { "No longer part of \(routineName)" }
}

// MARK: - Detachment (task P2-T41 seam, filled by P2-T43)

/// Should re-materialisation leave this instance alone (components.md
/// §13.6.3 row 3)? The one place `materialize` and `withdraw` ask: it is
/// their `isDetached` parameter's default. Task P2-T43 replaced the P2-T41
/// seam (which said `false` for everything) with the persisted flag. A
/// `.released` instance (§13.6.4) is left alone too: it is no longer the
/// template's to update. SPEC-GAP (design/GAPS.md G-033) for what happens
/// when its pair is produced again.
@MainActor
enum RoutineDetachment {
    static func isDetached(_ event: Event) -> Bool {
        event.routineLink != .linked
    }
}

// MARK: - Protected-window refusal (components.md §13.6.1, task P2-T40)

/// Does a routine block, on a given weekday, land in a `.protected` window?
///
/// One rule with two readers: `RoutineEngine.materialize` refuses the pair,
/// and the Routines window draws the block `conflicted` in that column and
/// names the window in the inspector (§13.6.2). §13.6.2 calls the canvas half
/// "a static comparison" of template interval against window span. Both
/// readers ask this type, so they always agree.
///
/// Everything is minutes-of-day on a weekday, not `Date`s. A `RoutineBlock`
/// never crosses midnight (interactions.md §11.1, G-013: drags clamp to
/// `0…1440`), so a block lives inside one day. A window can wrap
/// (Sleep 22:00–07:00): its evening part belongs to the weekday it starts
/// on, and its morning part (00:00–07:00) to the **next** day. That is the
/// same reading as `TimeWindow.spans(on:)`. So a 06:00 block on Monday is
/// refused by a Sleep window that is active on Sunday.
@MainActor
enum ProtectedWindowRule {

    /// The parts of `window` that fall on `weekday`, as `[start, end)` in
    /// minutes since midnight. Empty for a window that isn't on that day.
    /// The kind is ignored here; `refusingWindows` filters on it.
    static func minuteSpans(of window: TimeWindow, onWeekday weekday: Int) -> [Range<Int>] {
        let start = window.startMinutes
        let end = window.endMinutes
        var spans: [Range<Int>] = []
        if end > start {
            if window.weekdays.contains(weekday) { spans.append(start..<end) }
        } else {
            // Wraps midnight. `(weekday + 5) % 7 + 1` is the previous weekday
            // in Calendar's 1...7 numbering (Sunday's previous is Saturday, 7).
            let previous = (weekday + 5) % 7 + 1
            if window.weekdays.contains(weekday), start < 1440 { spans.append(start..<1440) }
            if window.weekdays.contains(previous), end > 0 { spans.append(0..<end) }
        }
        return spans
    }

    /// Every `.protected` window whose span on `weekday` strictly overlaps
    /// the block `[startMinutes, startMinutes + duration)`. Touching
    /// endpoints are not an overlap: a block starting at 07:00 is not inside
    /// a window ending at 07:00. This is the same test `ConflictEngine` uses.
    /// `.lowEnergy` and `.peakFocus` never count (§13.6.1 rule 4).
    static func refusingWindows(
        startMinutes: Int, duration: TimeInterval, weekday: Int, windows: [TimeWindow]
    ) -> [TimeWindow] {
        // Seconds, not whole minutes, so a duration that isn't a whole number
        // of minutes is compared exactly.
        let blockStart = TimeInterval(startMinutes * 60)
        let blockEnd = blockStart + duration
        guard blockEnd > blockStart else { return [] }

        return windows.filter { window in
            guard window.kind == .protected else { return false }
            return minuteSpans(of: window, onWeekday: weekday).contains { span in
                let spanStart = TimeInterval(span.lowerBound * 60)
                let spanEnd = TimeInterval(span.upperBound * 60)
                return blockStart < spanEnd && spanStart < blockEnd
            }
        }
    }

    static func refuses(startMinutes: Int, duration: TimeInterval, weekday: Int, windows: [TimeWindow]) -> Bool {
        !refusingWindows(startMinutes: startMinutes, duration: duration, weekday: weekday, windows: windows).isEmpty
    }

    /// One entry per protected window that refuses the block on at least one
    /// of `activeWeekdays`, carrying the weekdays it refuses on. This feeds
    /// the inspector's `Will not run — inside <label> (protected) on <days>`
    /// line (§13.6.2). `orderedWeekdays` is the window's column order, so the
    /// days read in the same order as the columns. Windows come out in
    /// `windows`' order.
    struct Refusal: Equatable {
        let windowID: UUID
        let label: String
        let weekdays: [Int]
    }

    static func refusals(
        startMinutes: Int, duration: TimeInterval,
        activeWeekdays: Set<Int>, orderedWeekdays: [Int], windows: [TimeWindow]
    ) -> [Refusal] {
        windows.compactMap { window in
            let days = orderedWeekdays.filter { weekday in
                activeWeekdays.contains(weekday)
                    && refuses(startMinutes: startMinutes, duration: duration, weekday: weekday, windows: [window])
            }
            return days.isEmpty ? nil : Refusal(windowID: window.id, label: window.label, weekdays: days)
        }
    }

    /// components.md §13.6.2's exact copy:
    /// `Will not run — inside Sleep (protected) on Mon, Wed, Fri`.
    /// Split at the dash into the inspector's label and value (see
    /// `RoutineInspectorView`). Weekday names are the calendar's
    /// `shortWeekdaySymbols`, the same source as the `Add Sat` button.
    static let inspectorLabel = "Will not run —"

    static func inspectorValue(for refusal: Refusal, calendar: Calendar = .current) -> String {
        let days = refusal.weekdays
            .map { calendar.shortWeekdaySymbols[($0 - 1) % 7] }
            .joined(separator: ", ")
        return "inside \(refusal.label) (protected) on \(days)"
    }
}

// MARK: - Horizon and triggers (components.md §13.6.5, task P2-T40)

/// Where `materialize` gets called from. The triggers (§13.6.5) are app
/// launch, any edit to a template, a block or a `TimeWindow`, and a change to
/// the main window's visible range. The views wire them up
/// (`MainWindow`, `RoutinesWindow`, `RoutineMaterializationTriggers`). This
/// type holds the horizon arithmetic and the "run every template" pass, so
/// both are testable without a view.
@MainActor
enum RoutineMaterialization {

    /// §13.6.5: "today + 28 days".
    static let minimumLeadDays = 28
    /// §13.6.5: "(the main window's visible range's end) + 7 days".
    static let visibleRangeLeadDays = 7

    /// "Today through the later of `today + 28 days` and `(visible range's
    /// end) + 7 days`" (§13.6.5), as a half-open `DateInterval`.
    ///
    /// "Through" is read inclusively: day `today + 28` is materialised, so
    /// the interval's exclusive end is the start of day `today + 29`.
    /// `visibleEnd` is `CalendarState.visibleInterval.end`, which is already
    /// exclusive (the start of the day after the last visible day). Adding 7
    /// days to it therefore covers the last visible day + 7, inclusive.
    /// `nil` means no visible range is known, and only the 28 days apply.
    static func horizon(today: Date, visibleEnd: Date?, calendar: Calendar = .current) -> DateInterval {
        let start = calendar.startOfDay(for: today)
        let minimumEnd = calendar.date(byAdding: .day, value: minimumLeadDays + 1, to: start) ?? start
        var end = minimumEnd
        if let visibleEnd,
           let visibleLeadEnd = calendar.date(
               byAdding: .day, value: visibleRangeLeadDays, to: calendar.startOfDay(for: visibleEnd)) {
            end = Swift.max(minimumEnd, visibleLeadEnd)
        }
        return DateInterval(start: start, end: end)
    }

    /// Withdraw (§13.6.4) and then materialise (§13.6.3) every template in
    /// `context` over the horizon, refusing pairs in every `.protected`
    /// window in `context`. Writes are not recorded as an undo step (see `RoutineEngine.materialize`'s doc
    /// comment). Idempotent, so a trigger that fires twice, or two windows
    /// each firing it for the same edit, creates nothing the second time.
    @discardableResult
    static func run(
        context: ModelContext,
        undo: UndoStack,
        visibleEnd: Date?,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> Int {
        let templates = (try? context.fetch(FetchDescriptor<RoutineTemplate>())) ?? []
        let windows = (try? context.fetch(FetchDescriptor<TimeWindow>())) ?? []
        let range = horizon(today: today, visibleEnd: visibleEnd, calendar: calendar)
        let store = EventStore(context: context, undo: undo)

        return templates.reduce(0) { total, template in
            // §13.6.4 first, then §13.6.3. Withdrawal here is what makes an
            // undo of an edit that ADDED pairs (`Add Saturday to Routine`,
            // `Create Routine Block`) take the instances back off the
            // calendar: the undo restores the template, and this pass then
            // withdraws what the template no longer produces. Redo restores
            // the template, and this pass creates them again.
            RoutineEngine.withdraw(
                template: template, timeWindows: windows, today: today,
                recordsUndo: false, store: store, calendar: calendar)
            return total + RoutineEngine.materialize(
                template: template, into: range, timeWindows: windows,
                today: today, recordsUndo: false, store: store, calendar: calendar)
        }
    }

    /// Everything a template, block or window edit can change that affects
    /// which pairs `materialize` creates. A view watches this with
    /// `.onChange(of:)`. SwiftData models are `@Observable`, so reading their
    /// properties while building this value inside a view's `body`
    /// subscribes the view to those properties. An edit made in either
    /// window re-renders the watcher, the value changes, and `onChange` fires.
    struct Fingerprint: Hashable {
        struct Block: Hashable {
            let id: UUID
            let startMinutes: Int
            let duration: TimeInterval
            // P2-T41: an update (§13.6.3) also writes title and flexibility,
            // so a change to either has to trigger a pass too.
            let title: String
            let flexibility: Flexibility
        }
        struct Template: Hashable {
            let id: UUID
            let activeWeekdays: Set<Int>
            let blocks: [Block]
        }
        struct Window: Hashable {
            let id: UUID
            let weekdays: Set<Int>
            let startMinutes: Int
            let endMinutes: Int
            let kind: TimeWindowKind
        }

        let templates: [Template]
        let windows: [Window]

        init(templates: [RoutineTemplate], windows: [TimeWindow]) {
            self.templates = templates.map { template in
                Template(
                    id: template.id,
                    activeWeekdays: template.activeWeekdays,
                    blocks: template.blocks.map {
                        Block(id: $0.id, startMinutes: $0.startMinutes, duration: $0.duration,
                              title: $0.title, flexibility: $0.flexibility)
                    })
            }
            self.windows = windows.map {
                Window(id: $0.id, weekdays: $0.weekdays, startMinutes: $0.startMinutes,
                       endMinutes: $0.endMinutes, kind: $0.kind)
            }
        }
    }
}

// MARK: - Editing (tasks P2-T11, P2-T12)

/// Move, resize, delete AND create for `RoutineBlock`s. Same two rules as
/// `EventStore.swift`'s header, for the same reasons:
///
/// 1. **Blocks are addressed by `id`, resolved at execution time.** Undoing a
///    delete cannot resurrect the deleted `@Model` instance, so the block
///    comes back as a new object carrying the same `id`. Nothing here
///    captures a `RoutineBlock` reference inside an undo closure.
/// 2. Every mutation is one named `UndoStack` step, named exactly as
///    interactions.md §11.1 prescribes ("Move Routine Block" / "Resize
///    Routine Block" / "Delete Routine Block" / "Create Routine Block" —
///    `UndoStack` itself prepends "Undo "/"Redo ").
///
/// The one thing that does NOT carry over from `EventStore`: a `RoutineBlock`
/// has no `Date` of its own (`RoutineTemplate.swift`'s own doc comment on
/// `startMinutes` — it is a time-of-day offset applied uniformly across every
/// active weekday, not an instant). So where `EventStore.move`/`resize` take
/// `Date`s, these take minutes-since-midnight, and clamp to a single day
/// (0...1440) rather than letting a drag roll a block over into "tomorrow",
/// which has no meaning for a template. `RoutinesWindow.swift`'s drag gesture
/// does the Date-to-minutes conversion (via `RoutineWeekLayout.referenceDayStart`)
/// before calling in, exactly the inverse of what `RoutineWeekLayout.layoutItems`
/// already does to turn `startMinutes` into a `Date` for the layout engine.
///
/// Day-boundary clamp — interactions.md §11.1, "Cross-midnight drags clamp"
/// (closes design/GAPS.md G-013): a move clamps `startMinutes` to
/// `0…(1440 − duration)`; a resize clamps the moved edge to `0…1440` and
/// keeps §4's 15-minute minimum. It never wraps to the previous or next
/// column, because a block is not on a column and a template has no "next
/// day". `create` below (task P2-T12) applies the same clamp, which G-013's
/// closure names explicitly.
@MainActor
struct RoutineBlockStore {
    let context: ModelContext
    let undo: UndoStack
    /// P2-T41: "today" for §13.6.4's withdrawal, which must not touch the
    /// past. A closure (read at the moment of the edit), so tests can pin it.
    var now: () -> Date = { Date() }
    var calendar: Calendar = .current

    /// §13.6.4: anything this edit stopped the template producing is
    /// withdrawn in the same step. Called inside each step's `perform` body.
    private func withdrawUnproduced() {
        RoutineEngine.withdrawAll(store: EventStore(context: context, undo: undo),
                                  today: now(), calendar: calendar)
    }

    // MARK: Resolving

    private func block(_ id: UUID) -> RoutineBlock? {
        var descriptor = FetchDescriptor<RoutineBlock>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func template(_ id: UUID) -> RoutineTemplate? {
        var descriptor = FetchDescriptor<RoutineTemplate>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func edit(_ id: UUID, _ change: (RoutineBlock) -> Void) {
        guard let block = block(id) else { return }
        change(block)
        try? context.save()
    }

    // MARK: Move

    func move(_ block: RoutineBlock, toStartMinutes newStart: Int) {
        let durationMinutes = max(1, Int(block.duration / 60))
        let clamped = min(max(newStart, 0), 1440 - durationMinutes)
        guard clamped != block.startMinutes else { return }
        let id = block.id
        let old = block.startMinutes
        // The block form of `perform`, so a withdrawal (a move into a
        // protected window) joins this step.
        undo.perform("Move Routine Block") { group in
            group.perform(redo: { edit(id) { $0.startMinutes = clamped } },
                          undo: { edit(id) { $0.startMinutes = old } })
            withdrawUnproduced()
        }
    }

    // MARK: Resize

    /// The drag clamps rather than inverting; minimum resulting duration is
    /// 15 minutes, same as `EventStore.resize` (interactions.md §4).
    func resize(_ block: RoutineBlock, newStartMinutes: Int? = nil, newEndMinutes: Int? = nil) {
        let minimum = 15
        let id = block.id
        let oldStart = block.startMinutes
        let oldEnd = oldStart + Int(block.duration / 60)

        var start = oldStart
        var end = oldEnd
        if let newStartMinutes { start = min(max(newStartMinutes, 0), oldEnd - minimum) }
        if let newEndMinutes { end = max(min(newEndMinutes, 1440), start + minimum) }
        guard start != oldStart || end != oldEnd else { return }

        let finalStart = start
        let finalDuration = TimeInterval((end - start) * 60)
        let oldDuration = block.duration
        undo.perform("Resize Routine Block") { group in
            group.perform(redo: { edit(id) { $0.startMinutes = finalStart; $0.duration = finalDuration } },
                          undo: { edit(id) { $0.startMinutes = oldStart; $0.duration = oldDuration } })
            withdrawUnproduced()
        }
    }

    // MARK: Delete

    /// Removes `block` from `template.blocks` (SwiftData's cascade rule only
    /// fires when the *template* is deleted, not when one block is dropped
    /// from its array, so both the array membership and the row itself are
    /// cleaned up here). `⌘Z` reinserts a fresh `RoutineBlock` carrying the
    /// same `id` and appends it back onto the same template.
    func delete(_ block: RoutineBlock, from template: RoutineTemplate) {
        let snapshot = RoutineBlockRestoreSnapshot(block)
        let id = block.id
        let templateID = template.id
        // §13.6.4: the block's future instances go in the same step, so one
        // `⌘Z` brings back the block and its instances together.
        undo.perform("Delete Routine Block") { group in
            group.perform(redo: { removeBlock(id, templateID: templateID) },
                          undo: { insertBlock(snapshot, templateID: templateID) })
            withdrawUnproduced()
        }
    }

    private func removeBlock(_ id: UUID, templateID: UUID) {
        guard let template = template(templateID) else { return }
        template.blocks.removeAll { $0.id == id }
        if let block = block(id) {
            context.delete(block)
        }
        try? context.save()
    }

    private func insertBlock(_ snapshot: RoutineBlockRestoreSnapshot, templateID: UUID) {
        guard let template = template(templateID) else { return }
        let block = snapshot.makeBlock()
        context.insert(block)
        template.blocks.append(block)
        try? context.save()
    }

    // MARK: Flexibility (task P2-T42, components.md §13.2)

    /// The inspector's three-segment control. One step, `Set Flexibility`.
    /// Entering `.shiftable` with no stored ± value also writes 30 in the
    /// same step; switching away keeps the number (`ShiftRangeRule`). The
    /// background pass then updates the untouched instances (§13.6.3), so
    /// that isn't part of this step.
    func setFlexibility(_ block: RoutineBlock, to new: Flexibility) {
        let id = block.id
        let oldFlexibility = block.flexibility
        guard new != oldFlexibility else { return }
        let oldMinutes = block.shiftableMinutes
        let newMinutes = ShiftRangeRule.storedValue(afterSwitchingTo: new, current: oldMinutes)
        undo.perform("Set Flexibility",
                     redo: { edit(id) { $0.flexibility = new; $0.shiftableMinutes = newMinutes } },
                     undo: { edit(id) { $0.flexibility = oldFlexibility; $0.shiftableMinutes = oldMinutes } })
    }

    /// The ± stepper. One step, `Set Shift Range`. Clamped to 15–180, and a
    /// change that clamps to the stored value records nothing.
    func setShiftRange(_ block: RoutineBlock, to minutes: Int) {
        let id = block.id
        let old = block.shiftableMinutes
        let new = ShiftRangeRule.clamped(minutes)
        guard new != old else { return }
        undo.perform("Set Shift Range",
                     redo: { edit(id) { $0.shiftableMinutes = new } },
                     undo: { edit(id) { $0.shiftableMinutes = old } })
    }

    /// "A `.shiftable` block with no ± value is a defect, not a state. It
    /// renders the stepper at 30 and writes 30 on first display" (§13.2).
    /// Writes 30 into every such block (or only `blockID`'s), with **no undo
    /// step**: a repair of a defect is not something the user did, and a
    /// `⌘Z` that put the defect back would be worse than none. Called from
    /// both windows' launch `.task` and when the inspector first shows a
    /// block. Returns how many blocks were repaired.
    @discardableResult
    func repairShiftRanges(blockID: UUID? = nil) -> Int {
        let blocks = (try? context.fetch(FetchDescriptor<RoutineBlock>())) ?? []
        var repaired = 0
        for block in blocks where blockID == nil || block.id == blockID {
            if ShiftRangeRule.needsRepair(flexibility: block.flexibility, stored: block.shiftableMinutes) {
                block.shiftableMinutes = ShiftRangeRule.defaultOnEntry
                repaired += 1
            }
        }
        if repaired > 0 { try? context.save() }
        return repaired
    }

    // MARK: Create (task P2-T12)

    /// Turns a draft (title + minutes-since-midnight + duration) into a
    /// persisted `RoutineBlock` appended to `template.blocks` — the "the other
    /// half" of interactions.md §11.1 this task adds. §11.1 points back at §3
    /// unchanged, and §3's own rule is enforced here exactly the way
    /// `EventStore.commit` already enforces it for `Event`: "an event created
    /// with no title is never persisted — cancelling and committing an empty
    /// field both remove it." A blank (or whitespace-only) `title` persists
    /// nothing and pushes no undo step — there is nothing to press `⌘Z`
    /// through, because nothing was ever written.
    ///
    /// Reversed shape of `delete`'s own undo, reusing the same
    /// `RoutineBlockRestoreSnapshot`/`insertBlock`/`removeBlock` plumbing:
    /// `redo` inserts the new block, `undo` removes it by `id`.
    ///
    /// `startMinutes`/`duration` clamp to the same `0...1440` day-boundary
    /// shape `move`/`resize` already use (interactions.md §11.1, see this
    /// type's own header). The 15-minute
    /// minimum duration is interactions.md §3's own rule for a drag-created
    /// block ("drag on empty grid creates a block of the dragged duration,
    /// minimum 15 minutes"), applied here the same way `resize`'s minimum
    /// already applies it.
    @discardableResult
    func create(title: String, startMinutes: Int, duration: TimeInterval, in template: RoutineTemplate) -> RoutineBlock? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let durationMinutes = max(15, Int(duration / 60))
        let clampedStart = min(max(startMinutes, 0), 1440 - durationMinutes)
        let clampedDurationMinutes = min(durationMinutes, 1440 - clampedStart)

        let id = UUID()
        let templateID = template.id
        let snapshot = RoutineBlockRestoreSnapshot(
            id: id, title: trimmed, startMinutes: clampedStart,
            duration: TimeInterval(clampedDurationMinutes * 60))

        undo.perform("Create Routine Block",
                     redo: { insertBlock(snapshot, templateID: templateID) },
                     undo: { removeBlock(id, templateID: templateID) })
        return block(id)
    }
}

// MARK: - Template edits: weekday activation (task P2-T39)

/// Edits to a `RoutineTemplate` itself rather than to one of its blocks.
/// Today that is only components.md §13.5.4's weekday activation; same
/// id-addressed, one-named-step shape as `RoutineBlockStore` above, and the
/// same shared `UndoStack`.
@MainActor
struct RoutineTemplateStore {
    let context: ModelContext
    let undo: UndoStack

    private func template(_ id: UUID) -> RoutineTemplate? {
        var descriptor = FetchDescriptor<RoutineTemplate>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    private func setActiveWeekdays(_ weekdays: Set<Int>, templateID: UUID) {
        guard let template = template(templateID) else { return }
        template.activeWeekdays = weekdays
        try? context.save()
    }

    /// Adds `weekday` to (`active == true`) or removes it from
    /// `template.activeWeekdays`, as ONE named undo step:
    /// `Add Saturday to Routine` / `Remove Saturday from Routine`
    /// (components.md §13.5.4, interactions.md §11.1.1). All three paths in
    /// §13.5.4 — the column note's `Add Sat` button, the inspector toggle
    /// row turning a day on, and the same row turning it off — call this.
    ///
    /// Asking for the state the day is already in records nothing, so there
    /// is no empty step to press `⌘Z` through (`UndoStack.perform`'s own
    /// rule).
    ///
    /// The whole old and new sets are captured, not "insert"/"remove", so
    /// undo restores the set exactly even if it is replayed out of step with
    /// some other edit.
    func setWeekday(_ weekday: Int, active: Bool, in template: RoutineTemplate,
                    today: Date = Date(), calendar: Calendar = .current) {
        let old = template.activeWeekdays
        let new = RoutineWeekdayActivation.applying(weekday, active: active, to: old)
        guard new != old else { return }

        // SPEC-GAP (design/GAPS.md G-027): removing the LAST active weekday.
        // §13.5.4 and interactions.md §11.1.1 give no exception, so it is
        // allowed and leaves an empty set: all seven columns go inactive and
        // each shows its `Add` button, which is the way back. Nothing is
        // refused here, because a refusal needs a rule the spec has not made.

        let templateID = template.id
        let name = RoutineWeekdayActivation.undoName(weekday: weekday, activating: active, calendar: calendar)
        // The block form of `perform` opens one group, so anything else
        // recorded inside the closure joins this step instead of pushing its
        // own (see `UndoStack.perform`'s doc comment).
        undo.perform(name) { group in
            group.perform(
                redo: { setActiveWeekdays(new, templateID: templateID) },
                undo: { setActiveWeekdays(old, templateID: templateID) })
            // components.md §13.6.4 / interactions.md §11.1.1 (P2-T41): on
            // deactivation, this weekday's future, non-detached instances are
            // withdrawn here, through `EventStore` on the same `UndoStack`, so
            // they join this step and one `⌘Z` restores both the weekday and
            // the instances. On activation there is nothing to withdraw; the
            // new day's instances come from the background pass
            // (`RoutineMaterializationTriggers`), which adds no step, and
            // which withdraws them again if this step is undone.
            if let template = self.template(templateID) {
                let windows = (try? context.fetch(FetchDescriptor<TimeWindow>())) ?? []
                RoutineEngine.withdraw(
                    template: template, timeWindows: windows, today: today,
                    recordsUndo: true, store: EventStore(context: context, undo: undo),
                    calendar: calendar)
            }
        }
    }
}

// MARK: - Snapshot (delete/undo)

/// Everything needed to bring a `RoutineBlock` back after a delete — the same
/// shape as `EventStore.swift`'s `EventSnapshot`, and for the same reason: a
/// `@Model` instance cannot be re-inserted once deleted, so undo recreates one
/// carrying the same `id`.
///
/// Also (task P2-T12) what `create`'s own `redo` inserts: a brand-new block
/// has never had a `@Model` instance to snapshot *from*, but it needs the
/// exact same "values in, `insertBlock` builds the `@Model`" shape `delete`'s
/// undo already established, so this plain memberwise init supplies it
/// directly rather than adding a second, parallel insert path.
struct RoutineBlockRestoreSnapshot: Sendable {
    var id: UUID
    var title: String
    var startMinutes: Int
    var duration: TimeInterval
    var flexibility: Flexibility
    var shiftableMinutes: Int?
    var priority: Int

    init(
        id: UUID,
        title: String,
        startMinutes: Int,
        duration: TimeInterval,
        flexibility: Flexibility = .fixed,
        shiftableMinutes: Int? = nil,
        priority: Int = 0
    ) {
        self.id = id
        self.title = title
        self.startMinutes = startMinutes
        self.duration = duration
        self.flexibility = flexibility
        self.shiftableMinutes = shiftableMinutes
        self.priority = priority
    }

    @MainActor
    init(_ block: RoutineBlock) {
        id = block.id
        title = block.title
        startMinutes = block.startMinutes
        duration = block.duration
        flexibility = block.flexibility
        shiftableMinutes = block.shiftableMinutes
        priority = block.priority
    }

    @MainActor
    func makeBlock() -> RoutineBlock {
        let block = RoutineBlock(
            title: title, startMinutes: startMinutes, duration: duration,
            flexibility: flexibility, shiftableMinutes: shiftableMinutes, priority: priority)
        block.id = id
        return block
    }
}
