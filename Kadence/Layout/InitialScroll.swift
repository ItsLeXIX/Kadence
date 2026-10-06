//
//  InitialScroll.swift
//  Kadence
//
//  layouts.md §3.1: the canvas opens scrolled to `min(07:00, firstEventStart − 1h)`
//  at the top. Pure, so it can be tested; `TimedCanvasView` scrolls to the
//  `ConflictScrollAnchors` anchor at that minute (task P2-F22; minute-precise
//  and time-of-day since P2-SF5). The Routines window uses the same rule over
//  its template's blocks (P2-SF4).
//

import Foundation
import SwiftUI

/// A caseless `enum` is Swift's idiom for a namespace of static functions —
/// like a Java/C# `static class`: it can't be instantiated.
enum InitialScroll {
    /// The minute after midnight (0…420) to put at the top of the viewport
    /// on open: `min(07:00, firstEventStart − 1h)`.
    ///
    /// layouts.md §3.1 (amended 2026-10-06, G-042): `firstEventStart` is a
    /// **time of day** — the earliest start time-of-day of any timed event
    /// that *starts* on one of the visible days, measured from that event's
    /// own midnight. In Week view that's the earliest across all columns
    /// (a Thursday 05:30 beats a Tuesday 08:00), not the first event of the
    /// first occupied day (P2-F22 built that, and floored to the hour).
    /// All-day items don't count, and neither does the after-midnight part of
    /// an event that started the day before (it starts on that earlier day).
    /// With no timed event, 07:00.
    static func minute(events: [Event], days: [Date], calendar: Calendar = .current) -> Int {
        let firstMinute = events
            .filter { event in
                !event.isAllDay && days.contains { day in calendar.isDate(event.start, inSameDayAs: day) }
            }
            .map { event in
                Int(event.start.timeIntervalSince(calendar.startOfDay(for: event.start)) / 60)
            }
            .min()
        guard let firstMinute else { return 7 * 60 }
        return flooredDefault(firstStartMinute: firstMinute)
    }

    /// layouts.md §3.1 (amended 2026-10-07, G-052): `min(07:00,
    /// floorToHour(firstEventStart − 1h))`, clamped at 00:00 — the top of
    /// the viewport is always a labelled hour line. 07:15 → 06:00, 07:59 →
    /// 06:00, 08:00 → 07:00, 05:30 → 04:00, 00:30 → 00:00. Shared by Day,
    /// Week and the Routines window (§8).
    static func flooredDefault(firstStartMinute: Int) -> Int {
        let lead = firstStartMinute - 60
        // Swift's `/` on Ints truncates toward zero, so a negative lead
        // (an event before 01:00) is floored by rounding a Double down
        // instead; the clamp then takes it to 00:00 either way.
        let hourFloor = Int((Double(lead) / 60).rounded(.down)) * 60
        return max(0, min(7 * 60, hourFloor))
    }

    /// Where the canvas is scrolled, from the scroll view's geometry.
    /// `Equatable` so `onScrollGeometryChange` calls back only when it changes.
    ///
    /// Only the top and the content height are read from `ScrollGeometry`.
    /// On macOS 26 its reports alternate between the real layout and a second
    /// one with a 44pt top inset (and negative offset) and a shorter
    /// container; offset + inset is the same in both, the container height
    /// isn't, so the viewport height comes from the scroll view's own
    /// laid-out frame instead (task P2-F24).
    struct Position: Equatable {
        /// The content y at the top of the viewport: offset + top inset.
        var top: CGFloat
        var contentHeight: CGFloat

        init(top: CGFloat, contentHeight: CGFloat) {
            self.top = top
            self.contentHeight = contentHeight
        }

        init(_ geometry: ScrollGeometry) {
            top = geometry.contentOffset.y + geometry.contentInsets.top
            contentHeight = geometry.contentSize.height
        }
    }

    /// layouts.md §8 (amended 2026-10-06, G-047): the Routines window's
    /// default scroll — §3.1's rule over the template's blocks:
    /// `min(07:00, earliestBlockStart − 1h)`, in minutes after midnight.
    /// A block's `startMinutes` is its time of day on every active weekday,
    /// so the weekdays don't enter into it. No blocks → 07:00.
    static func minute(blockStartMinutes: [Int]) -> Int {
        guard let earliest = blockStartMinutes.min() else { return 7 * 60 }
        return flooredDefault(firstStartMinute: earliest)
    }

    /// True when `position` isn't at `minute`'s top — clamped to the
    /// largest top the content allows in a `viewportHeight` viewport —
    /// within half a point. The scroll lands on the
    /// `ConflictScrollAnchors` anchor at or before `minute` (5-minute
    /// anchors), so that anchor's top is the target compared against.
    static func needsAim(_ position: Position, minute: Int, hourHeight: CGFloat, viewportHeight: CGFloat) -> Bool {
        let maxTop = max(0, position.contentHeight - viewportHeight)
        let anchorMinute = ConflictScroll.anchorID(minute: minute) - ConflictScroll.anchorID(minute: 0)
        let target = min(CGFloat(anchorMinute) / 60 * hourHeight, maxTop)
        return abs(position.top - target) >= 0.5
    }

    /// The §3.1 hold as a value (task P2-SF4, for the Routines window): the
    /// target is fixed when the hold starts and only `retarget` changes it,
    /// so an edit to a block or a Blocks/Windows switch never moves the
    /// canvas (layouts.md §8, 2026-10-06), while every settling layout pass
    /// is re-aimed until the user scrolls.
    ///
    /// Swift note: a `struct` with `mutating` methods is a value type whose
    /// methods may change its own fields — the caller keeps it in `@State`.
    struct Hold: Equatable {
        private(set) var target: Int
        private(set) var isHolding = true
        private(set) var aims = 0

        init(target: Int) { self.target = target }

        /// A new template was selected: hold again, at its default.
        mutating func retarget(_ minute: Int) {
            target = minute
            isHolding = true
            aims = 0
        }

        /// The user scrolled, or a conflict scroll took over: stop holding.
        mutating func release() { isHolding = false }

        /// Called on every scroll-geometry change: true when the canvas
        /// should be re-aimed at `target` now (and counts the aim). Gives up
        /// after `maxAims`.
        mutating func shouldAim(_ position: Position, hourHeight: CGFloat, viewportHeight: CGFloat) -> Bool {
            guard isHolding,
                  InitialScroll.needsAim(position, minute: target, hourHeight: hourHeight, viewportHeight: viewportHeight)
            else { return false }
            guard aims < InitialScroll.maxAims else {
                isHolding = false
                return false
            }
            aims += 1
            return true
        }
    }

    /// The hold gives up after this many re-aims.
    static let maxAims = 40
}
