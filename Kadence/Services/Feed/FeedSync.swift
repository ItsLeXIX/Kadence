//
//  FeedSync.swift
//  Kadence
//
//  Phase 3 slice 3 (PHASE3-SLICE3-PLAN.md task 6) — components.md §34.4–
//  §34.9, §20.9; interactions.md §16.3; moodle-mocks.md M4.
//
//  `FeedSyncPlanner.plan` is pure: the source's stored items (as values),
//  the fetch, the kind of write and the clock → a `FeedSyncPlan`.
//  `FeedSyncApplier` writes it in one store transaction. Slice 1's rules hold
//  with *events* read as *items*:
//
//  - the Import writes every item fetched (the past as history) and deletes
//    nothing; a sync writes only items starting on or after today;
//  - unchanged content writes nothing (§34.7's hashes);
//  - deletion only on proof of absence, and only inside the window the feed
//    covers: `[startOfDay(today), fetchedAt + observedLookahead − 24 h]`;
//  - an empty feed is proof only 12 h after the first (§34.5);
//  - a sync never writes `status`: a moved deadline keeps its done mark (§38).
//

import Foundation
import SwiftData

// MARK: - Inputs

nonisolated struct StoredFeedItem: Sendable, Equatable {
    var id: UUID
    var externalID: String
    var start: Date
    /// `MoodleHash.of(Event)`, computed when the snapshot is taken (§34.7).
    var hash: String
}

nonisolated struct FeedSourceSnapshot: Sendable, Equatable {
    var feedHash: String?
    var lastFeedEventCount: Int
    var observedLookahead: TimeInterval
    var emptySince: Date?
}

nonisolated enum FeedSyncKind: Sendable, Equatable {
    /// The connect sheet's `Import`.
    case `import`
    /// A sync — and Replace's `Save`, which applies what it fetched as one
    /// (§33.5).
    case sync
}

// MARK: - The plan

nonisolated struct FeedSyncPlan: Sendable {
    var creates: [MoodleItem] = []
    var updates: [(id: UUID, item: MoodleItem)] = []
    var deletes: [UUID] = []
    var feedHash: String?
    /// §34.8 step 4 stopped the sync: nothing written.
    var feedUnchanged = false
    var state: SourceState = .upToDate
    var problems: [ImportProblem] = []
    var change: (added: Int, updated: Int, removed: Int)?
    var lastFeedEventCount: Int?
    var veventCount = 0
    var observedLookahead: TimeInterval = 0
    /// What `Source.emptySince` becomes (nil clears it).
    var emptySince: Date?
    var proofWindow: ClosedRange<Date>?
    var isImport = false

    var writesItems: Bool { !creates.isEmpty || !updates.isEmpty || !deletes.isEmpty }
}

nonisolated enum FeedSyncPlanner {
    /// §34.5: an empty feed is proof 12 hours after the first.
    static let emptyFeedProof: TimeInterval = 12 * 3600
    /// §34.5: the margin that absorbs the feed's day-granular edge.
    static let proofMargin: TimeInterval = 24 * 3600

    /// §34.5: `observedLookahead` after a fetch read in full.
    static func lookahead(_ old: TimeInterval, items: [MoodleItem], fetchedAt: Date) -> TimeInterval {
        guard let latest = items.map(\.start).max() else { return old }
        return max(old, latest.timeIntervalSince(fetchedAt))
    }

    static func plan(existing: [StoredFeedItem], source: FeedSourceSnapshot, fetch: FeedFetch,
                     kind: FeedSyncKind, now: Date, zone: TimeZone) -> FeedSyncPlan {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let today = cal.startOfDay(for: now)
        let feed = fetch.feed
        let isImport = kind == .import

        var plan = FeedSyncPlan()
        plan.isImport = isImport
        plan.problems = feed.problems
        plan.veventCount = feed.veventCount
        plan.emptySince = source.emptySince

        // Step 4's bookkeeping first: the look-ahead (a fetch read in full).
        let readInFull = feed.problems.isEmpty
        plan.observedLookahead = readInFull
            ? lookahead(source.observedLookahead, items: feed.items, fetchedAt: now) : source.observedLookahead
        let windowEnd = now.addingTimeInterval(plan.observedLookahead - proofMargin)
        let proof = windowEnd >= today ? today...windowEnd : nil
        plan.proofWindow = proof

        // §34.5 `emptyFeed`: zero VEVENTs while the last full read had items.
        var emptyProven = false
        if feed.veventCount == 0 && source.lastFeedEventCount > 0 && !isImport {
            if let since = source.emptySince, now.timeIntervalSince(since) >= emptyFeedProof {
                emptyProven = true
                plan.emptySince = nil
            } else {
                plan.state = .emptyFeed
                if source.emptySince == nil { plan.emptySince = now }
                return plan
            }
        } else if feed.veventCount > 0 {
            plan.emptySince = nil
        }
        if !feed.problems.isEmpty { plan.state = .partialImport }

        // The write window (§34.4).
        let window = isImport ? feed.items : feed.items.filter { $0.start >= today }
        let feedHash = MoodleHash.feed(window, from: isImport ? .distantPast : today)
        if readInFull {
            plan.feedHash = feedHash
            plan.lastFeedEventCount = feed.veventCount
        }
        if !isImport, readInFull, !emptyProven, let stored = source.feedHash, stored == feedHash {
            plan.feedUnchanged = true
            return plan
        }

        // Step 5 — diff by externalID (a sync: on or after today only).
        let candidates = isImport ? existing : existing.filter { $0.start >= today }
        var byID: [String: StoredFeedItem] = [:]
        for e in candidates { byID[e.externalID] = e }
        var seen = Set<String>()
        for item in window {
            seen.insert(item.externalID)
            if let stored = byID[item.externalID] {
                if stored.hash != item.hash { plan.updates.append((stored.id, item)) }
            } else {
                plan.creates.append(item)
            }
        }
        // Deletions: proof of absence, inside the window the feed covers,
        // under §20.8's guards (no problems; an empty feed only once proven).
        if !isImport, readInFull, let proof {
            plan.deletes = candidates.filter { !seen.contains($0.externalID) && proof.contains($0.start) }.map(\.id)
        }

        if !isImport && plan.writesItems {
            let deleted = Set(plan.deletes)
            let removed = existing.filter { deleted.contains($0.id) && $0.start >= today }.count
            let added = plan.creates.filter { $0.start >= today }.count
            let updated = plan.updates.filter { $0.item.start >= today }.count
            if added + updated + removed > 0 { plan.change = (added, updated, removed) }
        }
        return plan
    }
}

// MARK: - The applier

@MainActor
enum FeedSyncApplier {
    static func snapshot(of source: Source, in context: ModelContext, zone: TimeZone = .current) -> [StoredFeedItem] {
        SyncApplier.events(of: source, in: context).map {
            StoredFeedItem(id: $0.id, externalID: $0.externalID ?? "", start: $0.start,
                           hash: MoodleHash.of($0, zone: zone))
        }
    }

    static func sourceSnapshot(_ source: Source) -> FeedSourceSnapshot {
        FeedSourceSnapshot(feedHash: source.feedHash, lastFeedEventCount: source.lastFeedEventCount,
                           observedLookahead: source.observedLookahead, emptySince: source.emptySince)
    }

    /// Applies `plan`. Throws only when the store refused the save; then
    /// nothing is kept.
    @discardableResult
    static func apply(_ plan: FeedSyncPlan, to source: Source, context: ModelContext, now: Date) throws
    -> SyncApplier.Outcome {
        var outcome = SyncApplier.Outcome()
        let stored = SyncApplier.events(of: source, in: context)
        let byID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for item in plan.creates {
            let event = Event(title: item.title, start: item.start, end: item.end, isAllDay: item.isAllDay,
                              origin: .imported, flexibility: .fixed, sourceKey: source.paletteKey,
                              sourceID: source.id, externalID: item.externalID)
            event.applyMoodle(item)
            context.insert(event)
        }
        for update in plan.updates {
            // The same `Event.id`; `status` and the done mark untouched (§38).
            byID[update.id]?.applyMoodle(update.item)
        }
        for id in plan.deletes {
            guard let event = byID[id] else { continue }
            context.delete(event)
            outcome.deletedIDs.insert(id)
        }
        TravelLegs.delete(for: outcome.deletedIDs, in: context)
        outcome.wrote = plan.writesItems

        // Bookkeeping, on every fetch (§34.8 step 6).
        var facts = SourceStatusPresentation.facts(of: source)
        facts.k = plan.problems.count
        facts.n = plan.state == .emptyFeed ? source.lastEventCount : plan.veventCount
        source.stateDetail = FeedStatusCopy.storedDetail(plan.state, facts)
        source.lastAttemptAt = now
        source.state = plan.state
        source.problems = plan.problems
        source.lastSuccessAt = now
        source.observedLookahead = plan.observedLookahead
        source.emptySince = plan.emptySince
        if let hash = plan.feedHash { source.feedHash = hash }
        if let count = plan.lastFeedEventCount { source.lastFeedEventCount = count }
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
        source.lastEventCount = SyncApplier.events(of: source, in: context).count
        try? context.save()
        return outcome
    }

    /// A failed fetch writes only the bookkeeping fields, with §34.3's copy.
    static func recordFailure(_ error: ScheduleSourceError, to source: Source, context: ModelContext, now: Date) {
        var facts = SourceStatusPresentation.facts(of: source)
        switch error {
        case .redirected(let other): facts.otherHost = other
        case .serverError(let code): facts.code = code
        default: break
        }
        source.stateDetail = FeedStatusCopy.storedDetail(error.state, facts)
        source.lastAttemptAt = now
        source.state = error.state
        if error.state.pausesAutomaticSync { source.isAutoSyncPaused = true }
        try? context.save()
    }
}

extension Event {
    /// The sync-owned fields of a Moodle item (§42.1). Never `status`, never
    /// `markedDoneDueAt`, never `notes` (§38).
    func applyMoodle(_ item: MoodleItem) {
        title = item.title
        start = item.start
        end = item.end
        isAllDay = item.isAllDay
        importKind = item.kind
        momentWording = item.wording
        upstreamTitle = item.upstreamTitle
        courseCategory = item.courseCategory
        courseCode = item.courseCode
        importedDescription = item.description
        location = nil
        isOnline = false
        isCancelled = false
    }
}

// MARK: - The log lines (§34.9)

nonisolated enum FeedLog {
    /// `{n} KB`, rounded.
    static func kilobytes(_ bytes: Int) -> Int { Int((Double(bytes) / 1024).rounded()) }

    static func lookaheadDays(_ seconds: TimeInterval) -> Int { Int(max(0, seconds) / 86_400) }

    /// The paired count: §36 over the fetched items.
    static func paired(_ feed: MoodleFeed) -> Int {
        MoodlePairing.pairs(feed.items.map { MomentItem($0, sourceID: "") }).pairedOpenings.count
    }

    /// `sync moodle.technikum-wien.at/… · feed · requests 1 · 412 ms · 151 KB ·
    /// vevents 29 · duplicates 0 · deadlines 25 · openings 4 · paired 4 ·
    /// notices 0 · lookahead 59d · feed unchanged`. Never a title, a category,
    /// a description, the path or the query.
    static func line(_ kind: String, display: String, fetch: FeedFetch, lookahead: TimeInterval,
                     outcome: String) -> String {
        let f = fetch.feed
        return ["\(kind) \(display)", "feed", "requests \(fetch.requests)", "\(fetch.milliseconds) ms",
                "\(kilobytes(fetch.bytes)) KB", "vevents \(f.veventCount)", "duplicates \(f.duplicates)",
                "deadlines \(f.deadlines)", "openings \(f.openings)", "paired \(paired(f))", "notices \(f.notices)",
                "lookahead \(lookaheadDays(lookahead))d", outcome].joined(separator: " · ")
    }

    static func connectLine(display: String, fetch: FeedFetch, now: Date) -> String {
        line("connect", display: display, fetch: fetch,
             lookahead: FeedSyncPlanner.lookahead(0, items: fetch.feed.items, fetchedAt: now),
             outcome: "previewed \(FeedStatusCopy.items(fetch.feed.items.count))")
    }

    /// `import moodle.technikum-wien.at/… · 29 items · 1 before today`.
    static func importLine(display: String, items: Int, beforeToday: Int) -> String {
        "import \(display) · \(FeedStatusCopy.items(items)) · \(beforeToday) before today"
    }
}

extension Source {
    /// §33.4's display form from the stored record: `https://{host}` → `{host}/…`.
    var feedDisplay: String { "\(host ?? "")/…" }

    /// §33.6: the record a Moodle `Import` writes. It takes no URL: the URL
    /// goes only to the Keychain (§33.3), so this cannot store it even by
    /// mistake.
    static func moodleFeed(id: String = UUID().uuidString, displayName: String = "Moodle", host: String,
                           paletteKey: SourceKey) -> Source {
        let source = Source(id: id, kind: .coursework, connection: .icsFeed, displayName: displayName,
                            paletteKey: paletteKey)
        source.feedProfile = .moodle
        source.serverURL = "https://\(host.lowercased())"
        source.pollInterval = 3600
        return source
    }
}
