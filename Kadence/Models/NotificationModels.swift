//
//  NotificationModels.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 1) — components.md §27.1,
//  §28.1: the five notification rules and the scheduler's bookkeeping
//  record. Every stored field has a default (§28: a slice 1 store opens
//  without a migration step).
//

import Foundation
import SwiftData

/// §27.1's five rule kinds, raw values exactly the spec's.
nonisolated enum NotificationRuleKind: String, Codable, CaseIterable, Sendable {
    case leaveBy
    case timetableStart
    case personalStart
    case routineStart
    case syncPaused

    /// §27.1's defaults, confirmed by Parsa 2026-10-14: leave-by 5,
    /// timetable 30, personal 15, routine 5, every rule on. `syncPaused` has
    /// no lead time (0, unused).
    var defaultLeadMinutes: Int {
        switch self {
        case .leaveBy: 5
        case .timetableStart: 30
        case .personalStart: 15
        case .routineStart: 5
        case .syncPaused: 0
        }
    }

    /// §27.1 "Settings label".
    var settingsLabel: String {
        switch self {
        case .leaveBy: "Leave by"
        case .timetableStart: "Timetable"
        case .personalStart: "Personal events"
        case .routineStart: "Routine"
        case .syncPaused: "Sync problems"
        }
    }
}

/// §28.1 — BRIEF-PRODUCT's `NotificationRule(kind, leadTime, isEnabled)`,
/// with the lead time in whole minutes (every choice is).
@Model
final class NotificationRule {
    private var kindRaw: String = NotificationRuleKind.leaveBy.rawValue
    var kind: NotificationRuleKind {
        get { NotificationRuleKind(rawValue: kindRaw) ?? .leaveBy }
        set { kindRaw = newValue.rawValue }
    }

    var leadMinutes: Int = 0
    var isEnabled: Bool = true

    init(kind: NotificationRuleKind, leadMinutes: Int, isEnabled: Bool = true) {
        self.kindRaw = kind.rawValue
        self.leadMinutes = leadMinutes
        self.isEnabled = isEnabled
    }
}

/// §28.1 / §27.6 — for each scheduled identifier, the fire date it was
/// given. A record whose fire date has passed means "sent". Bookkeeping
/// only, never shown; no notification history beyond this (§28.3).
@Model
final class NotificationRecord {
    /// Unique: `leave.{eventID}`, `start.{eventID}`, `result.…`, `sync.{sourceID}`.
    var identifier: String = ""
    /// The event's `id` as a string, or the source's id for `sync.`.
    var subjectID: String = ""
    /// `leave` / `start` / `result` / `sync` — the identifier's prefix.
    var kind: String = ""
    var fireAt: Date = Date.distantPast
    /// §27.6: SHA-256 of title, body and category.
    var contentHash: String = ""

    init(identifier: String, subjectID: String, kind: String, fireAt: Date, contentHash: String) {
        self.identifier = identifier
        self.subjectID = subjectID
        self.kind = kind
        self.fireAt = fireAt
        self.contentHash = contentHash
    }
}
