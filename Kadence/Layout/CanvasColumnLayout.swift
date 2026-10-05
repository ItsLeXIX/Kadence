//
//  CanvasColumnLayout.swift
//  Kadence
//
//  Task P2-F02 (DEVIATIONS.md B20; layouts.md §6, amended 2026-10-05). Pure
//  column-width arithmetic for the main window's timed canvas, pulled out of
//  `TimedCanvasView` so it can be tested without SwiftUI.
//
//  Why it exists: with System Settings → "Show scroll bars: Always" (the
//  *legacy* scroller style), a SwiftUI `ScrollView(.vertical)` on macOS sizes
//  itself to its content's width PLUS the scroller's width when the content
//  has a fixed width — it does not squeeze the content. The grid's columns are
//  fixed widths computed from the GeometryReader around the scroll view, so
//  the scroll view came out 17pt wider than the slot `MainWindow` gave the
//  canvas (measured live: proxy 939pt, scroll view 956pt). Those 17pt — the
//  scroller and the canvas's own focus ring — were painted over the
//  inspector's leading edge, which is what cut `Starts` to `tarts` and drew a
//  full-height accent line there. Reserving the scroller's width before
//  dividing the columns keeps the whole canvas, scroller included, inside
//  its slot.
//

import AppKit

enum CanvasColumnLayout {

    /// The width a vertical scroll view's scroller takes out of the layout:
    /// `NSScroller.scrollerWidth` for the legacy style, 0 for overlay
    /// scrollers (which float over the content and take no room).
    ///
    /// `@MainActor` because AppKit's `NSScroller` API is main-actor isolated
    /// under Swift 6 strict concurrency (like reading any UI state in Java's
    /// Swing on the EDT). Not a design value: it is the system's own metric.
    @MainActor
    static var systemScrollerReserve: CGFloat {
        scrollerReserve(style: NSScroller.preferredScrollerStyle)
    }

    /// Split out from `systemScrollerReserve` so tests can pass either style.
    @MainActor
    static func scrollerReserve(style: NSScroller.Style) -> CGFloat {
        style == .legacy ? NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy) : 0
    }

    /// One day column's width.
    ///
    /// - Parameters:
    ///   - totalWidth: the width the canvas was given (its GeometryReader).
    ///   - gutterWidth: `size.timeGutterWidth`.
    ///   - dayCount: 7 in Week, 1 in Day.
    ///   - columnMin: `size.dayColumnMin`, applied in Week only (layouts.md §3).
    ///   - scrollerReserve: `systemScrollerReserve`.
    /// - Returns: the column width, and whether it hit the floor (then the
    ///   grid scrolls horizontally instead of shrinking further).
    static func columnWidth(
        totalWidth: CGFloat,
        gutterWidth: CGFloat,
        dayCount: Int,
        columnMin: CGFloat?,
        scrollerReserve: CGFloat
    ) -> (width: CGFloat, needsHorizontalScroll: Bool) {
        let available = max(0, totalWidth - gutterWidth - scrollerReserve)
        let natural = available / CGFloat(max(dayCount, 1))
        guard let columnMin, columnMin > natural else { return (natural, false) }
        return (columnMin, true)
    }

    /// The width the grid's content occupies: gutter + every column. With the
    /// reserve this plus `scrollerReserve` equals `totalWidth` whenever the
    /// columns are above the floor, so nothing is drawn outside the canvas.
    static func contentWidth(columnWidth: CGFloat, gutterWidth: CGFloat, dayCount: Int) -> CGFloat {
        gutterWidth + columnWidth * CGFloat(dayCount)
    }
}
