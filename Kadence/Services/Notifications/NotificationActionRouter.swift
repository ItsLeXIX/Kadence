//
//  NotificationActionRouter.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 10) — components.md §27.7,
//  interactions.md §14.1: acting on a notification. The popover's
//  semantics, through the same `EventStore` verbs and the same undo stack
//  (`⌘Z` in the main window undoes them), addressed by the event id in
//  `userInfo` and resolved when the action runs (DECISIONS 2026-09-09: no
//  closure holds an `Event`).
//
//  - `Done` marks the event done; already done → nothing.
//  - `Snooze` is `EventStore.snooze` — §16's +15 placeholder with its
//    protected-window refusal — answered at once by N5 (moved) or N6
//    (refused). A moved event's leg and notification follow on the next
//    recompute.
//  - `Open` and a click: Kadence forward, the main window open, paged to the
//    event's day, the event selected. An unknown id: today, nothing selected.
//  - N8's `Open`: Settings ▸ Sources with that source selected.
//  - Dismissing does nothing (§27.9).
//

import Foundation
import Observation
import SwiftData
import SwiftUI
import AppKit

@MainActor
@Observable
final class NotificationActionRouter {
    /// Where an `Open` takes the user. The app performs it (the menu bar
    /// label, which is always alive, opens the window or Settings).
    enum OpenRequest: Equatable, Sendable {
        /// The main window on this event (nil: today, nothing selected).
        case event(UUID?)
        /// Settings ▸ Sources with this source selected.
        case settingsSources(sourceID: String)

        /// The Settings tab an open request names (tests, §30.1 "Actions").
        var settingsTab: String? {
            if case .settingsSources = self { return "Sources" }
            return nil
        }
    }

    @ObservationIgnored let context: ModelContext
    @ObservationIgnored let undo: UndoStack
    @ObservationIgnored let centre: any NotificationCenterClient
    @ObservationIgnored let clock: any TravelClock
    @ObservationIgnored let calendar: Calendar
    @ObservationIgnored weak var calendarState: CalendarState?
    @ObservationIgnored weak var sourcesRouter: SourcesRouter?

    /// The latest open request, for the app to perform; cleared by it.
    var pendingOpen: OpenRequest?
    /// Every open request, in order (tests).
    @ObservationIgnored private(set) var openHistory: [OpenRequest] = []

    init(context: ModelContext, undo: UndoStack, centre: any NotificationCenterClient, clock: any TravelClock,
         calendar: Calendar = .current) {
        self.context = context
        self.undo = undo
        self.centre = centre
        self.clock = clock
        self.calendar = calendar
    }

    private var store: EventStore { EventStore(context: context, undo: undo) }

    private func event(_ subjectID: String?) -> Event? {
        guard let id = subjectID.flatMap(UUID.init(uuidString:)) else { return nil }
        var descriptor = FetchDescriptor<Event>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    /// One response, simulated in tests by calling this directly (§27.10).
    func handle(_ response: NotificationResponse) async {
        if response.category == .source {
            guard response.action == .open, let sourceID = response.subjectID else { return }
            sourcesRouter?.selectedSourceID = sourceID
            request(.settingsSources(sourceID: sourceID))
            return
        }
        switch response.action {
        case .dismiss:
            return
        case .open:
            let event = event(response.subjectID)
            if let event {
                calendarState?.reveal(event)
            } else {
                calendarState?.goToToday()
                calendarState?.selectedEventID = nil
            }
            request(.event(event?.id))
        case .done:
            guard response.category != .result, let event = event(response.subjectID),
                  event.status != .done, !event.isCancelled else { return }
            store.toggleDone(event)
        case .snooze:
            // No `Snooze` on an imported event or a result (§27.7); the
            // store refuses an imported one anyway (`.unchanged`).
            guard response.category == .event, let event = event(response.subjectID) else { return }
            let title = event.title
            let oldStart = event.start
            let id = event.id
            switch store.snooze(event, calendar: calendar) {
            case .moved(let newStart):
                await deliverResult(NotificationCopy.n5(title: title, oldStart: oldStart, newStart: newStart,
                                                        calendar: calendar), eventID: id)
            case .refused(let start, let label):
                await deliverResult(NotificationCopy.n6(title: title, newStart: start, window: label,
                                                        calendar: calendar), eventID: id)
            case .unchanged:
                return
            }
        }
    }

    private func request(_ open: OpenRequest) {
        openHistory.append(open)
        pendingOpen = open
    }

    /// N5 / N6 at once: category `kadence.result`, no sound, `.active`,
    /// identifier `result.{eventID}.{epochSeconds}` (§27.6). Delivered inside
    /// a protected window too: it answers the user's own act (§27.5 rule 6).
    private func deliverResult(_ text: NotificationText, eventID: UUID) async {
        let now = clock.now
        let request = ScheduledRequest(
            identifier: "result.\(eventID.uuidString).\(Int(now.timeIntervalSince1970))", fireAt: now, atOnce: true,
            title: text.title, body: text.body, category: .result, playsSound: false, interruption: .active,
            subjectID: eventID.uuidString, contentHash: NotificationCopy.contentHash(text, category: .result))
        try? await centre.add(request)
    }
}

// MARK: - Performing an open (the app)

/// Performs the router's `Open`: Kadence forward; the main window (opened
/// if closed) on the event, or Settings ▸ Sources. Applied to the main
/// window and to the menu bar label, which is always alive; whichever sees
/// the request first performs it and clears it.
struct NotificationOpenHandler: ViewModifier {
    let actions: NotificationActionRouter
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.onChange(of: actions.pendingOpen) { _, request in
            guard let request else { return }
            actions.pendingOpen = nil
            NSApplication.shared.activate()
            switch request {
            case .event:
                if let main = NSApplication.shared.windows.first(where: {
                    $0.isVisible && $0.canBecomeMain
                        && !RoutinesWindowOpener.isRoutinesWindow(identifier: $0.identifier?.rawValue)
                }) {
                    main.makeKeyAndOrderFront(nil)
                } else {
                    openWindow(id: "main")
                }
            case .settingsSources:
                openSettings()
            }
        }
    }
}

extension View {
    func performsNotificationOpens(_ actions: NotificationActionRouter) -> some View {
        modifier(NotificationOpenHandler(actions: actions))
    }
}
