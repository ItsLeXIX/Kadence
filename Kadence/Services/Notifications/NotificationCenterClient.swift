//
//  NotificationCenterClient.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 9) — components.md §27.10:
//  the notification centre behind a protocol. `SystemNotificationCenter`
//  (the only file that names the system centre's type) is used by a
//  normal launch only; `RecordingNotificationCenter` keeps requests in
//  memory, never shows a prompt and never posts — every test and every
//  review launch uses it (the three-launch rule, B45).
//

import Foundation

/// What the centre says (§27.10).
nonisolated enum NotificationAuthorization: String, Sendable, Equatable {
    case allowed, off, notDetermined
}

/// What Kadence calls the state (§27.8).
nonisolated enum NotificationPermission: String, Sendable, Equatable {
    case allowed
    case off
    /// `notDetermined`, Kadence has asked.
    case notAllowedYet
    /// `notDetermined`, Kadence has not asked: nothing is shown.
    case notAsked

    static func of(_ authorization: NotificationAuthorization, asked: Bool) -> NotificationPermission {
        switch authorization {
        case .allowed: .allowed
        case .off: .off
        case .notDetermined: asked ? .notAllowedYet : .notAsked
        }
    }
}

/// One request as Kadence schedules it, and as the recording centre
/// records it (the interruption level asked for, §27.10).
nonisolated struct ScheduledRequest: Sendable, Equatable {
    var identifier: String
    var fireAt: Date
    /// A 1-second trigger (catch-up, results, N8), else a calendar trigger.
    var atOnce: Bool
    var title: String
    var body: String
    var category: NotificationCategory
    var playsSound: Bool
    var interruption: InterruptionLevel
    /// `userInfo`: `subject` (the event or source id) and `hash` (§27.6).
    var subjectID: String
    var contentHash: String

    init(_ planned: PlannedNotification) {
        identifier = planned.identifier
        fireAt = planned.fireAt
        atOnce = planned.atOnce
        title = planned.text.title
        body = planned.text.body
        category = planned.category
        playsSound = planned.playsSound
        interruption = planned.interruption
        subjectID = planned.subjectID
        contentHash = planned.contentHash
    }

    init(identifier: String, fireAt: Date, atOnce: Bool, title: String, body: String, category: NotificationCategory,
         playsSound: Bool, interruption: InterruptionLevel, subjectID: String, contentHash: String) {
        self.identifier = identifier
        self.fireAt = fireAt
        self.atOnce = atOnce
        self.title = title
        self.body = body
        self.category = category
        self.playsSound = playsSound
        self.interruption = interruption
        self.subjectID = subjectID
        self.contentHash = contentHash
    }
}

nonisolated struct DeliveredNotification: Sendable, Equatable {
    var identifier: String
}

/// §27.7's categories and their actions.
nonisolated struct NotificationCategorySpec: Sendable, Equatable {
    struct Action: Sendable, Equatable {
        var identifier: String
        var title: String
        /// `Open` brings Kadence forward; `Done` and `Snooze` run in the
        /// background.
        var foreground: Bool
    }

    var identifier: String
    var actions: [Action]

    static let done = Action(identifier: "done", title: "Done", foreground: false)
    static let snooze = Action(identifier: "snooze", title: "Snooze", foreground: false)
    static let open = Action(identifier: "open", title: "Open", foreground: true)

    /// `kadence.event`: Done · Snooze · Open. `kadence.readOnly`: Done · Open
    /// (no Snooze: an imported event cannot move). `kadence.result`: none.
    /// `kadence.source`: Open.
    static let all: [NotificationCategorySpec] = [
        NotificationCategorySpec(identifier: NotificationCategory.event.rawValue, actions: [done, snooze, open]),
        NotificationCategorySpec(identifier: NotificationCategory.readOnly.rawValue, actions: [done, open]),
        NotificationCategorySpec(identifier: NotificationCategory.result.rawValue, actions: []),
        NotificationCategorySpec(identifier: NotificationCategory.source.rawValue, actions: [open]),
        // components.md §40.6 (slice 3).
        NotificationCategorySpec(identifier: NotificationCategory.deadline.rawValue, actions: [done, open]),
        NotificationCategorySpec(identifier: NotificationCategory.deadlines.rawValue, actions: [open]),
    ]
}

/// §27.10, exactly.
nonisolated protocol NotificationCenterClient: Sendable {
    func authorization() async -> NotificationAuthorization
    func requestAuthorization() async -> Bool
    func setCategories(_ categories: [NotificationCategorySpec]) async
    func pending() async -> [ScheduledRequest]
    func add(_ request: ScheduledRequest) async throws
    func removePending(_ ids: [String]) async
    func delivered() async -> [DeliveredNotification]
    func removeDelivered(_ ids: [String]) async
}

/// The in-memory centre. Never prompts, never posts.
actor RecordingNotificationCenter: NotificationCenterClient {
    struct Rejected: Error {}

    private var state: NotificationAuthorization
    /// What asking turns the state into (default: unchanged — no prompt is
    /// ever shown, so nobody answers one).
    private var answer: NotificationAuthorization?
    /// Scripted: `add` throws for a time-sensitive request (§27.4's degrade).
    private var rejectsTimeSensitive: Bool
    private var requests: [String: ScheduledRequest] = [:]
    private var deliveredIDs: [String] = []
    private(set) var categories: [NotificationCategorySpec] = []
    private(set) var requestAuthorizationCalls = 0
    private(set) var addCalls: [ScheduledRequest] = []
    private(set) var removeCalls: [String] = []
    private(set) var removeDeliveredCalls: [String] = []

    init(authorization: NotificationAuthorization = .allowed, answer: NotificationAuthorization? = nil,
         rejectsTimeSensitive: Bool = false) {
        state = authorization
        self.answer = answer
        self.rejectsTimeSensitive = rejectsTimeSensitive
    }

    // Scripting
    func set(authorization: NotificationAuthorization) { state = authorization }
    func set(rejectsTimeSensitive: Bool) { self.rejectsTimeSensitive = rejectsTimeSensitive }
    /// A request already in the centre that Kadence did not schedule.
    func seedForeign(_ request: ScheduledRequest) { requests[request.identifier] = request }
    /// The system delivered it: it leaves pending and enters delivered.
    func deliver(_ id: String) {
        guard requests.removeValue(forKey: id) != nil else { return }
        deliveredIDs.append(id)
    }
    func resetCounters() {
        addCalls = []
        removeCalls = []
        removeDeliveredCalls = []
        requestAuthorizationCalls = 0
    }
    var pendingByID: [String: ScheduledRequest] { requests }
    var deliveredList: [String] { deliveredIDs }

    // NotificationCenterClient
    func authorization() async -> NotificationAuthorization { state }

    func requestAuthorization() async -> Bool {
        requestAuthorizationCalls += 1
        if let answer { state = answer }
        return state == .allowed
    }

    func setCategories(_ categories: [NotificationCategorySpec]) async { self.categories = categories }
    func pending() async -> [ScheduledRequest] { requests.values.sorted { $0.identifier < $1.identifier } }

    func add(_ request: ScheduledRequest) async throws {
        addCalls.append(request)
        if rejectsTimeSensitive, request.interruption == .timeSensitive { throw Rejected() }
        requests[request.identifier] = request
    }

    func removePending(_ ids: [String]) async {
        removeCalls += ids
        for id in ids { requests[id] = nil }
    }

    func delivered() async -> [DeliveredNotification] { deliveredIDs.map(DeliveredNotification.init) }

    func removeDelivered(_ ids: [String]) async {
        removeDeliveredCalls += ids
        deliveredIDs.removeAll { ids.contains($0) }
    }
}

@MainActor
enum NotificationServices {
    /// `SystemNotificationCenter` in a normal launch only; the recording
    /// centre otherwise, with review's `-KadenceNotifications` state.
    static func make(for kind: LaunchKind, review: ReviewNotifications = .allowed) -> any NotificationCenterClient {
        switch ServiceImplementation.of(kind) {
        case .real:
            ServiceLaunchLog.record("SystemNotificationCenter")
            return SystemNotificationCenter()
        case .mock:
            ServiceLaunchLog.record("RecordingNotificationCenter")
            return RecordingNotificationCenter(authorization: review.authorization)
        }
    }
}

/// §27.10: review mode's `-KadenceNotifications
/// allowed|off|notDetermined|notAsked` (default `allowed`).
nonisolated enum ReviewNotifications: String, Sendable, CaseIterable {
    case allowed, off, notDetermined, notAsked

    var authorization: NotificationAuthorization {
        switch self {
        case .allowed: .allowed
        case .off: .off
        case .notDetermined, .notAsked: .notDetermined
        }
    }

    /// `notDetermined` is "after a recorded ask" (§30 item 4).
    var hasAsked: Bool { self == .notDetermined }

    static func current(_ defaults: UserDefaults = .standard) -> ReviewNotifications {
        guard ReviewMode.dataset(defaults) != nil else { return .allowed }
        return defaults.string(forKey: "KadenceNotifications").flatMap(Self.init(rawValue:)) ?? .allowed
    }
}
