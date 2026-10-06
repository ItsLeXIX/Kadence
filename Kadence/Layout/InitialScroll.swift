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

    /// True when `position` isn't at the hour's top — clamped to the
    /// largest top the content allows in a `viewportHeight` viewport —
    /// within half a point.
    static func needsAim(_ position: Position, hour: Int, hourHeight: CGFloat, viewportHeight: CGFloat) -> Bool {
        let maxTop = max(0, position.contentHeight - viewportHeight)
        let target = min(CGFloat(hour) * hourHeight, maxTop)
        return abs(position.top - target) >= 0.5
    }

    /// The hold gives up after this many re-aims.
    static let maxAims = 40
}
