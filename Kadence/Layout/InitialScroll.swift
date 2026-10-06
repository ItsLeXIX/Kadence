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
    struct Position: Equatable {
        /// The content y at the top of the visible content area. The scroll
        /// view sometimes reports a top inset (44pt while the window
        /// settles) with a negative offset, so offset + inset.
        var top: CGFloat
        /// The largest `top` the content allows.
        var maxTop: CGFloat

        init(top: CGFloat, maxTop: CGFloat) {
            self.top = top
            self.maxTop = maxTop
        }

        init(_ geometry: ScrollGeometry) {
            top = geometry.contentOffset.y + geometry.contentInsets.top
            maxTop = max(0, geometry.contentSize.height - geometry.containerSize.height)
        }
    }

    /// True when `position` isn't at the hour's top (clamped to what the
    /// content allows), within half a point.
    static func needsAim(_ position: Position, hour: Int, hourHeight: CGFloat) -> Bool {
        let target = min(CGFloat(hour) * hourHeight, position.maxTop)
        return abs(position.top - target) >= 0.5
    }

    /// The hold gives up after this many re-aims.
    static let maxAims = 40
}
