//
//  SystemNotificationCenter.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 9) — components.md §27.10,
//  §27.4 (levels), §27.7 (`willPresent`), §27.8 (the state mapping). Wraps
//  `UNUserNotificationCenter.current()`; **the only file in the app that
//  names `UNUserNotificationCenter`**. Constructed only by a normal launch
//  (`NotificationServices`), in `KadenceApp.init`, so its delegate is in
//  place before the first launch response is delivered (G-092).
//
//  Tested only through its pure mapping; no test, script or review launch
//  constructs it.
//

import Foundation
import UserNotifications

final class SystemNotificationCenter: NSObject, NotificationCenterClient, UNUserNotificationCenterDelegate,
                                      @unchecked Sendable {
    // Swift note: `@unchecked Sendable` — the one stored property is set
    // once on the main actor before any other thread can see the object, and
    // `UNUserNotificationCenter` is itself thread-safe.
    private nonisolated(unsafe) var responseHandler: (@MainActor @Sendable (NotificationResponse) -> Void)?

    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    /// Where `Done`, `Snooze`, `Open` and a click go (task 10's router).
    @MainActor
    func onResponse(_ handler: @escaping @MainActor @Sendable (NotificationResponse) -> Void) {
        responseHandler = handler
    }

    // MARK: NotificationCenterClient

    nonisolated func authorization() async -> NotificationAuthorization {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        return Self.map(status: settings.authorizationStatus, alertSetting: settings.alertSetting,
                        alertStyle: settings.alertStyle)
    }

    nonisolated func requestAuthorization() async -> Bool {
        // §27.8: alert and sound — never `.badge`, never `.provisional`.
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    nonisolated func setCategories(_ categories: [NotificationCategorySpec]) async {
        let mapped = categories.map { spec in
            UNNotificationCategory(
                identifier: spec.identifier,
                actions: spec.actions.map {
                    UNNotificationAction(identifier: $0.identifier, title: $0.title,
                                         options: $0.foreground ? [.foreground] : [])
                },
                intentIdentifiers: [], options: [])
        }
        UNUserNotificationCenter.current().setNotificationCategories(Set(mapped))
    }

    nonisolated func pending() async -> [ScheduledRequest] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().compactMap(Self.request)
    }

    nonisolated func add(_ request: ScheduledRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.categoryIdentifier = request.category.rawValue
        content.sound = request.playsSound ? .default : nil
        content.interruptionLevel = request.interruption == .timeSensitive ? .timeSensitive : .active
        content.userInfo = ["subject": request.subjectID, "hash": request.contentHash,
                            "fireAt": request.fireAt.timeIntervalSince1970, "atOnce": request.atOnce]
        let trigger: UNNotificationTrigger
        if request.atOnce {
            trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        } else {
            let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second],
                                                        from: request.fireAt)
            trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
        }
        try await UNUserNotificationCenter.current().add(
            UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
    }

    nonisolated func removePending(_ ids: [String]) async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    nonisolated func delivered() async -> [DeliveredNotification] {
        await UNUserNotificationCenter.current().deliveredNotifications()
            .map { DeliveredNotification(identifier: $0.request.identifier) }
    }

    nonisolated func removeDelivered(_ ids: [String]) async {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: ids)
    }

    private static func request(_ request: UNNotificationRequest) -> ScheduledRequest? {
        let info = request.content.userInfo
        guard let subject = info["subject"] as? String, let hash = info["hash"] as? String,
              let fire = info["fireAt"] as? TimeInterval,
              let category = NotificationCategory(rawValue: request.content.categoryIdentifier) else { return nil }
        return ScheduledRequest(
            identifier: request.identifier, fireAt: Date(timeIntervalSince1970: fire),
            atOnce: info["atOnce"] as? Bool ?? false, title: request.content.title, body: request.content.body,
            category: category, playsSound: request.content.sound != nil,
            interruption: request.content.interruptionLevel == .timeSensitive ? .timeSensitive : .active,
            subjectID: subject, contentHash: hash)
    }

    // MARK: Delegate

    /// §27.7: delivered while Kadence is frontmost → a banner with sound;
    /// results without sound.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
    async -> UNNotificationPresentationOptions {
        notification.request.content.categoryIdentifier == NotificationCategory.result.rawValue
            ? [.banner, .list] : [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse)
    async {
        let info = response.notification.request.content.userInfo
        let mapped = NotificationResponse(
            identifier: response.notification.request.identifier,
            action: Self.action(response.actionIdentifier),
            subjectID: info["subject"] as? String,
            category: NotificationCategory(rawValue: response.notification.request.content.categoryIdentifier))
        let handler = responseHandler
        await MainActor.run { handler?(mapped) }
    }

    nonisolated static func action(_ identifier: String) -> NotificationResponse.Action {
        switch identifier {
        case UNNotificationDefaultActionIdentifier: .open
        case UNNotificationDismissActionIdentifier: .dismiss
        case NotificationCategorySpec.done.identifier: .done
        case NotificationCategorySpec.snooze.identifier: .snooze
        case NotificationCategorySpec.open.identifier: .open
        default: .dismiss
        }
    }

    // MARK: Pure mapping — tested

    /// §27.8: authorized / provisional / ephemeral with alerts enabled →
    /// `allowed`; authorized with alert style "None", or denied → `off`;
    /// `notDetermined` → `notDetermined`.
    nonisolated static func map(status: UNAuthorizationStatus, alertSetting: UNNotificationSetting,
                                alertStyle: UNAlertStyle) -> NotificationAuthorization {
        switch status {
        case .notDetermined: return .notDetermined
        case .denied: return .off
        default:
            if alertStyle == .none { return .off }
            return alertSetting == .enabled ? .allowed : .off
        }
    }
}

/// A response to a delivered notification, as Kadence reads it (tests
/// build these directly: §27.10 "no real response object is needed").
nonisolated struct NotificationResponse: Sendable, Equatable {
    enum Action: String, Sendable { case done, snooze, open, dismiss }
    var identifier: String
    var action: Action
    var subjectID: String?
    var category: NotificationCategory?
}
