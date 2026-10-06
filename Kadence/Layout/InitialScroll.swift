//
//  InitialScroll.swift
//  Kadence
//
//  layouts.md §3.1: the canvas opens scrolled to `min(07:00, firstEventStart − 1h)`
//  at the top. Pure, so it can be tested; `TimedCanvasView` scrolls to the
//  `ConflictScrollAnchors` anchor at the start of this hour (task P2-F22).
//

import Foundation
import SwiftUI

/// A caseless `enum` is Swift's idiom for a namespace of static functions —
/// like a Java/C# `static class`: it can't be instantiated.
enum InitialScroll {
    /// The hour (0…7) to put at the top of the viewport on open.
    ///
    /// `firstEventStart` is the earliest timed (not all-day) event starting on
    /// one of the visible days; with none, 07:00. (Moved unchanged from
    /// `TimedCanvasView.initialAnchorHour`.)
    static func hour(events: [Event], days: [Date], calendar: Calendar = .current) -> Int {
        let firstStart = events
            .filter { event in
                !event.isAllDay && days.contains { day in calendar.isDate(event.start, inSameDayAs: day) }
            }
            .map(\.start)
            .min()
        guard let firstStart else { return 7 }
        let hour = calendar.component(.hour, from: firstStart)
        return max(0, min(7, hour - 1))
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
        return max(0, min(7 * 60, earliest - 60))
    }

    /// True when `position` isn't at the hour's top — clamped to the
    /// largest top the content allows in a `viewportHeight` viewport —
    /// within half a point.
    static func needsAim(_ position: Position, hour: Int, hourHeight: CGFloat, viewportHeight: CGFloat) -> Bool {
        needsAim(position, minute: hour * 60, hourHeight: hourHeight, viewportHeight: viewportHeight)
    }

    /// The same, for a target minute. The scroll lands on the
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
