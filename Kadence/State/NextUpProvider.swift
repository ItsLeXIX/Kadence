//
//  NextUpProvider.swift
//  Kadence
//
//  Derives the menu bar extra's "what's next" state (components.md §15,
//  DECISIONS.md 2026-09-10 "Menu bar requirement split between status item
//  and popover") from live `Event` data. Free of SwiftUI and free of the
//  system clock — same shape as `DayLayoutEngine`/`ConflictEngine`: a pure
//  function over value types plus an injected `now`, so it is directly
//  testable without launching the menu bar UI.
//
//  The caller supplies `events` the same way `MainWindow.swift` already
//  fetches them (`@Query(sort: \Event.start) private var events: [Event]`);
//  this type does the "today, not all-day, not done, not skipped" filtering
//  and ordering itself, so every menu bar surface (status item, popover)
//  derives from the same single pass.
//

import Foundation

@MainActor
enum NextUpProvider {

    /// One frozen read of "what's next" and "what's left today".
    struct Result {
        /// The earliest not-done/not-skipped, non-all-day event starting
        /// today, if any.
        let next: Event?
        /// True once `next` has already started (`start <= now`) — the
        /// "Late" state in components.md §15.1/§15.2. Phrased as elapsed
        /// ("12m ago"), never as a deficit — see the callers in
        /// `Kadence/Views/MenuBar/`.
        let isLate: Bool
        /// Every other not-done/not-skipped event starting today, in start
        /// order, after `next`.
        let restOfToday: [Event]

        static let empty = Result(next: nil, isLate: false, restOfToday: [])
    }

    /// - Parameters:
    ///   - events: the live query, unfiltered — this function filters to
    ///     today's non-all-day, not-done/not-skipped events itself.
    ///   - now: injected rather than read from the system clock, so this is
    ///     testable with a fixed reference time.
    static func evaluate(events: [Event], now: Date, calendar: Calendar = .current) -> Result {
        let today = events
            .filter { !$0.isAllDay }
            .filter { $0.status != .done && $0.status != .skipped }
            .filter { calendar.isDate($0.start, inSameDayAs: now) }
            .sorted { $0.start < $1.start }

        guard let next = today.first else { return .empty }
        return Result(next: next, isLate: next.start <= now, restOfToday: Array(today.dropFirst()))
    }

    /// components.md §16 (task P2-T49): while a snooze confirmation is held,
    /// NEXT stays the snoozed event, at its new time, even when the snooze
    /// moved it past midnight and so out of "today".
    ///
    /// Without this, a cross-midnight snooze made the snoozed block stop
    /// being NEXT the moment it moved, so the result row (`Moved to tomorrow
    /// 00:05`) and the NEXT block above it described different things —
    /// `screenshots/2/snooze-next-day.png` shows the row naming the new time
    /// beside the block's old `23:50 – 01:20`. §16: the confirmation "must show
    /// where the block landed"; "the confirmation and the movement are the
    /// same event seen from two places".
    ///
    /// `pinned` is the confirmation's event id and the start it expects. If
    /// that event no longer starts there (an undo put it back), the pin no
    /// longer applies and `result` is returned unchanged. The pinned event is
    /// never late (it was just moved later) and is removed from the rest.
    static func pinning(_ result: Result, events: [Event], to pinned: (id: UUID, start: Date)?) -> Result {
        guard let pinned,
              let event = events.first(where: { $0.id == pinned.id && $0.start == pinned.start })
        else { return result }
        var rest = result.restOfToday.filter { $0.id != event.id }
        if let previous = result.next, previous.id != event.id { rest.insert(previous, at: 0) }
        return Result(next: event, isLate: false, restOfToday: rest)
    }

    /// What "REST OF TODAY" actually renders (components.md §15.2): at most
    /// `cap` rows, then a `+N more` line once there are more than that.
    struct RestDisplay {
        let rows: [Event]
        /// 0 means no `+N more` line.
        let moreCount: Int
    }

    /// - Parameter cap: defaults to `Tokens.Size.popoverMaxRestRows` (6); a
    ///   parameter mainly so the boundary itself is easy to pin in tests.
    static func restDisplay(_ rest: [Event], cap: Int = Tokens.Size.popoverMaxRestRows) -> RestDisplay {
        guard rest.count > cap else { return RestDisplay(rows: rest, moreCount: 0) }
        return RestDisplay(rows: Array(rest.prefix(cap)), moreCount: rest.count - cap)
    }
}
