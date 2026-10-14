//
//  SyncPlanner.swift
//  Kadence
//
//  PHASE3-PLAN.md task 8 — components.md §20.1 (Import vs sync windows,
//  deselection), §20.6, §20.8.3 (one sync), §20.8.4 (change by content),
//  §20.8's guards (deletion only on proof of absence), §20.9, §20.10, §18.1.
//
//  `SyncPlanner.plan` is pure: what the store holds (as values), what the
//  server returned, which kind of write this is, and the clock → a `SyncPlan`.
//  `SyncApplier` writes a plan in one store transaction.
//

import Foundation
import SwiftData

// MARK: - Inputs

/// One stored event of the source, as the planner needs it.
nonisolated struct StoredEvent: Sendable, Equatable {
    var id: UUID
    var externalID: String
    var start: Date
    var end: Date
    /// `EventHash.of(Event)`, computed when the snapshot is taken.
    var hash: String
}

/// What the planner needs of the `Source`.
nonisolated struct SourceSnapshot: Sendable, Equatable {
    var feedHash: String?
    var lastFeedEventCount: Int
    var calendars: [SourceCalendar]
    var importedAt: Date?
}

nonisolated enum SyncKind: Sendable {
    /// The connect sheet's `Import` (or a never-imported source's first write).
    case `import`
    case sync
    /// Edit mode's `Save`: a sync, plus — when calendars were unchecked — the
    /// deletion of events absent from the kept calendars' Import-window read.
    case editSave(deselected: Bool)
}

// MARK: - The plan

nonisolated struct SyncPlan: Sendable {
    var creates: [ExternalEvent] = []
    /// The event's id, its new upstream fields, and whether its time moved in
    /// place (§18.1: status resets to `.scheduled`).
    var updates: [(id: UUID, event: ExternalEvent, resetStatus: Bool)] = []
    var deletes: [UUID] = []
    /// `Source.feedHash` to store, or nil to leave it (§20.8.4: only after a
    /// read of every calendar in full).
    var feedHash: String?
    /// §20.8.3 step 4 stopped the sync: nothing written.
    var feedUnchanged = false
    var state: SourceState = .upToDate
    var stateDetailCalendars: [String] = []
    var problems: [ImportProblem] = []
    /// The last-change counts (§19.3): only events on or after today; nil
    /// when nothing counts (or this is the Import, which is not a change).
    var change: (added: Int, updated: Int, removed: Int)?
    var lastFeedEventCount: Int?
    /// VEVENTs read in this fetch (`partialImport`'s `{n}` with the problems).
    var objectCount = 0
    var adoptedCalendars: [SourceCalendar] = []
    var capabilities: SourceCapabilities?
    var isImport = false
    var principalHref: String?
    var calendarHomeHref: String?

    var writesEvents: Bool { !creates.isEmpty || !updates.isEmpty || !deletes.isEmpty }
}

// MARK: - The planner

nonisolated enum SyncPlanner {

    /// §19.1: when calendars end differently, the earlier row wins.
    static let stateOrder: [SourceState] = [
        .upToDate, .syncing, .neverSynced, .offline, .unauthorized, .forbidden, .noCalDAV, .noCalendars,
        .calendarMissing, .fetchFailed, .notACalendar, .emptyFeed, .partialImport, .certificate,
        .passwordMissing, .redirected, .unreachable, .serverError,
    ]

    /// - Parameters:
    ///   - existing: this source's stored events.
    ///   - disableStep4: tests only — §20.8.4: "with step 4 disabled, step 5
    ///     still writes nothing".
    static func plan(existing: [StoredEvent], source: SourceSnapshot, result: ScheduleFetchResult,
                     kind: SyncKind, now: Date, zone: TimeZone, disableStep4: Bool = false) -> SyncPlan {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let today = cal.startOfDay(for: now)
        let isImport: Bool = { if case .import = kind { return true }; return false }()

        var plan = SyncPlan()
        plan.isImport = isImport
        plan.problems = result.problems
        plan.objectCount = result.objectCount
        plan.adoptedCalendars = result.adoptedCalendars
        plan.capabilities = result.capabilities
        plan.principalHref = result.principalHref
        plan.calendarHomeHref = result.calendarHomeHref

        // Every selected calendar read in full? (§20.8 guards)
        let selected = Set(source.calendars.map(\.href))
        let adoptedFor = Dictionary(uniqueKeysWithValues: result.adoptedCalendars.map { ($0.displayName, $0.href) })
        let readHrefs = Set(result.calendarsReadInFully)
        let allRead = result.failedCalendars.isEmpty && selected.allSatisfy { href in
            readHrefs.contains(href) || source.calendars.first { $0.href == href }
                .flatMap { adoptedFor[$0.displayName] }.map(readHrefs.contains) == true
        }

        // The state (one at a time; the earliest §19.1 row among failures).
        if let worst = result.failedCalendars.min(by: { rank($0.1.state) < rank($1.1.state) }) {
            plan.state = worst.1.state
            plan.stateDetailCalendars = result.failedCalendars.filter { $0.1.state == worst.1.state }.map(\.0.displayName)
        }
        let isEmptyFeed = !isImport && allRead && result.objectCount == 0 && source.lastFeedEventCount > 0
        if plan.state == .upToDate {
            if isEmptyFeed {
                plan.state = .emptyFeed
                plan.stateDetailCalendars = source.calendars.map(\.displayName)
            } else if !result.problems.isEmpty {
                plan.state = .partialImport
            }
        }

        // The write window (§20.1).
        let window = isImport ? result.events : result.events.filter { $0.start >= today }
        let hashes = window.map { EventHash.of($0, zone: zone) }
        let feedHash = FeedHash.of(hashes)
        if allRead && !isEmptyFeed {
            plan.feedHash = feedHash
            plan.lastFeedEventCount = result.objectCount
        }

        // Step 4 — change by content.
        let deselecting: Bool = { if case .editSave(let d) = kind { return d }; return false }()
        if !disableStep4, !isImport, !deselecting, allRead, let stored = source.feedHash, stored == feedHash {
            plan.feedUnchanged = true
            return plan
        }

        // Step 5 — diff by externalID (sync: on or after today only).
        let candidates = isImport ? existing : existing.filter { $0.start >= today }
        var byID: [String: StoredEvent] = [:]
        for e in candidates { byID[e.externalID] = e }
        var seen = Set<String>()
        for (event, hash) in zip(window, hashes) {
            seen.insert(event.externalID)
            if let stored = byID[event.externalID] {
                if stored.hash != hash {
                    let moved = stored.start != event.start || stored.end != event.end
                    plan.updates.append((stored.id, event, moved))
                }
            } else {
                plan.creates.append(event)
            }
        }
        // Deletions: proof of absence only.
        let mayDelete = !isImport && allRead && result.problems.isEmpty && !isEmptyFeed
        if mayDelete {
            plan.deletes = candidates.filter { !seen.contains($0.externalID) }.map(\.id)
        }
        // Edit-mode deselection (§20.1 step 2, amended 2026-10-10, G-080):
        // every event absent from the kept calendars' full Import-window read
        // **that starts on or after the server's horizon** — the earliest
        // event start in that read. An older event is kept: the server no
        // longer serves that week for any calendar (CIS served about two and
        // a half weeks of past on 9 Oct), so its absence proves nothing about
        // which calendar it came from. An empty read has no horizon, and then
        // the deselection deletes nothing in the past.
        if deselecting, allRead {
            plan.deletes += deselected(existing: existing, keptEvents: result.events).map(\.id)
                .filter { !plan.deletes.contains($0) }
        }

        if !isImport && plan.writesEvents {
            let deleted = Set(plan.deletes)
            let removedFromToday = existing.filter { deleted.contains($0.id) && $0.start >= today }.count
            let added = plan.creates.filter { $0.start >= today }.count
            let updated = plan.updates.filter { $0.event.start >= today }.count
            if added + updated + removedFromToday > 0 { plan.change = (added, updated, removedFromToday) }
        }
        return plan
    }

    static func rank(_ state: SourceState) -> Int { stateOrder.firstIndex(of: state) ?? stateOrder.count }

    /// §20.1: "The server's horizon is the earliest event start in an
    /// Import-window fetch that was read in full; before it, absence from the
    /// feed proves nothing." Nil for an empty fetch.
    static func horizon(of events: [ExternalEvent]) -> Date? { events.map(\.start).min() }

    /// What a deselection removes: the stored events absent from the kept
    /// calendars' read and inside the horizon.
    static func deselected(existing: [StoredEvent], keptEvents: [ExternalEvent]) -> [StoredEvent] {
        guard let horizon = horizon(of: keptEvents) else { return [] }
        let kept = Set(keptEvents.map(\.externalID))
        return existing.filter { !kept.contains($0.externalID) && $0.start >= horizon }
    }

    /// How many events a deselection would remove (layouts.md §12.3's
    /// sentence) — the same set `Save` deletes, so the count excludes what
    /// the horizon keeps.
    static func deselectionCount(existing: [StoredEvent], keptEvents: [ExternalEvent]) -> Int {
        deselected(existing: existing, keptEvents: keptEvents).count
    }
}

// MARK: - The applier

/// Writes a plan in one store transaction (§20.8.3 step 6). Sync writes are
/// not undo steps (§20.9).
@MainActor
enum SyncApplier {

    /// The source's stored events as planner input.
    static func snapshot(of source: Source, in context: ModelContext, zone: TimeZone = .current) -> [StoredEvent] {
        events(of: source, in: context).map {
            StoredEvent(id: $0.id, externalID: $0.externalID ?? "", start: $0.start, end: $0.end,
                        hash: EventHash.of($0, zone: zone))
        }
    }

    static func events(of source: Source, in context: ModelContext) -> [Event] {
        let id: String? = source.id
        let descriptor = FetchDescriptor<Event>(predicate: #Predicate { $0.sourceID == id })
        return ((try? context.fetch(descriptor)) ?? []).filter { $0.origin == .imported }
    }

    struct Outcome: Equatable {
        var deletedIDs: Set<UUID> = []
        var wrote = false
    }

    /// Applies `plan` to `source`. Throws only when the store refused the
    /// save; then nothing is kept (`rollback`).
    @discardableResult
    static func apply(_ plan: SyncPlan, to source: Source, context: ModelContext, now: Date) throws -> Outcome {
        var outcome = Outcome()
        let stored = events(of: source, in: context)
        let byID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for upstream in plan.creates {
            let event = Event(title: upstream.title, start: upstream.start, end: upstream.end,
                              isAllDay: upstream.isAllDay, origin: .imported, flexibility: .fixed,
                              sourceKey: source.paletteKey, sourceID: source.id, externalID: upstream.externalID)
            event.applyUpstream(upstream)
            context.insert(event)
        }
        for update in plan.updates {
            guard let event = byID[update.id] else { continue }
            event.applyUpstream(update.event)
            if update.resetStatus { event.status = .scheduled }
        }
        for id in plan.deletes {
            guard let event = byID[id] else { continue }
            context.delete(event)
            outcome.deletedIDs.insert(id)
        }
        // Slice 2 (components.md §24.5, §24.7): a deleted event's leg goes in
        // the same transaction.
        TravelLegs.delete(for: outcome.deletedIDs, in: context)
        outcome.wrote = plan.writesEvents

        // Bookkeeping, written on every poll (§20.8.3).
        var facts = SourceStatusPresentation.facts(of: source)
        if !plan.stateDetailCalendars.isEmpty { facts.calendars = plan.stateDetailCalendars }
        facts.k = plan.problems.count
        facts.n = plan.state == .emptyFeed ? source.lastEventCount : plan.objectCount + plan.problems.count
        source.stateDetail = SourceStatusPresentation.storedDetail(plan.state, facts)
        source.lastAttemptAt = now
        source.state = plan.state
        source.problems = plan.problems
        if plan.state.kind != .actionable || plan.state == .partialImport || plan.state == .emptyFeed {
            source.lastSuccessAt = now
        }
        if let hash = plan.feedHash { source.feedHash = hash }
        if let count = plan.lastFeedEventCount { source.lastFeedEventCount = count }
        if let capabilities = plan.capabilities { source.capabilities = capabilities }
        if !plan.adoptedCalendars.isEmpty {
            source.calendars = source.calendars.map { calendar in
                plan.adoptedCalendars.first { $0.displayName == calendar.displayName } ?? calendar
            }
        }
        if let principal = plan.principalHref, !principal.isEmpty { source.principalHref = principal }
        if let home = plan.calendarHomeHref, !home.isEmpty { source.calendarHomeHref = home }
        if plan.isImport && source.importedAt == nil { source.importedAt = now }
        if let change = plan.change {
            source.lastChangeAt = now
            source.lastChangeAdded = change.added
            source.lastChangeUpdated = change.updated
            source.lastChangeRemoved = change.removed
        }
        do {
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
        source.lastEventCount = events(of: source, in: context).count
        try? context.save()
        return outcome
    }

    /// §20.9 after a write: a selected event the sync deleted is deselected
    /// (the inspector returns to its day summary); undo and redo steps that
    /// address a deleted event are dropped. An updated event stays selected.
    static func finish(_ outcome: Outcome, state: CalendarState?, undo: UndoStack?) {
        if let selected = state?.selectedEventID, outcome.deletedIDs.contains(selected) {
            state?.selectedEventID = nil
        }
        undo?.dropSteps(addressing: outcome.deletedIDs)
    }

    /// A failed fetch writes only the bookkeeping fields (§20.8.3).
    static func recordFailure(_ error: ScheduleSourceError, calendars: [String] = [], to source: Source,
                              context: ModelContext, now: Date) {
        var facts = SourceStatusPresentation.facts(of: source)
        if !calendars.isEmpty { facts.calendars = calendars }
        switch error {
        case .redirected(let other): facts.otherHost = other
        case .serverError(let code): facts.code = code
        default: break
        }
        source.stateDetail = SourceStatusPresentation.storedDetail(error.state, facts)
        source.lastAttemptAt = now
        source.state = error.state
        if error.state.pausesAutomaticSync { source.isAutoSyncPaused = true }
        try? context.save()
    }

    /// Removes a source: its events (history included) and the record, in one
    /// transaction (interactions.md §13.2).
    static func remove(_ source: Source, context: ModelContext) throws -> Set<UUID> {
        let events = events(of: source, in: context)
        let ids = Set(events.map(\.id))
        TravelLegs.delete(for: Set(events.map(\.id)), in: context)
        for event in events { context.delete(event) }
        context.delete(source)
        do { try context.save() } catch { context.rollback(); throw error }
        return ids
    }
}
