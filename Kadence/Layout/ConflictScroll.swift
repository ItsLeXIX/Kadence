//
//  ConflictScroll.swift
//  Kadence
//
//  interactions.md §10.1 (amended 2026-10-05) — "Activation brings the
//  conflict into view": if the occurrence's frame is not wholly inside the
//  viewport, the grid scrolls so the earlier of the two colliding starts sits
//  one third from the top (layouts.md §3.1's Today rule), using
//  `motion.paging` (instant under Reduce Motion). The same rule applies to the
//  template block in the Routines window. Task P2-F15.
//
//  Pure arithmetic in minutes-of-day, so it is testable without a scroll view.
//

import SwiftUI

enum ConflictScroll {

    /// Scroll anchors are laid every `anchorStep` minutes; a target is
    /// floored to the anchor at or before it (at most 4 min, ≈ 3pt in Week).
    static let anchorStep = 5

    /// Ids for the anchor views, kept clear of the hour anchors (0…23) the
    /// canvas's initial scroll already uses.
    static func anchorID(minute: Int) -> Int {
        10_000 + (max(0, min(minute, 1439)) / anchorStep) * anchorStep
    }

    /// `ScrollViewReader.scrollTo(_:anchor:)` lines the anchor view's point
    /// at this unit position up with the same point of the viewport. The
    /// anchors are `anchorStep` minutes tall, so `.top` would land a third of
    /// a 5-minute slot off; the target minute is the anchor's TOP, and the
    /// scroll puts the anchor's 1/3 point at the viewport's 1/3 point — at
    /// most 1/3 of 5 minutes (≈ 1pt in Week) from exact.
    static let oneThird = UnitPoint(x: 0, y: 1.0 / 3.0)

    /// The minute to bring to one third from the top, or `nil` when the
    /// occurrence is already wholly in view (§10.1: scroll only if it isn't).
    ///
    /// - Parameters:
    ///   - occurrence: the occurrence's `[start, end)` in minutes of its day.
    ///   - earliestStart: the earlier of the two colliding starts.
    ///   - visibleTop / visibleHeight: the viewport, in content points.
    static func targetMinute(
        occurrence: Range<Int>,
        earliestStart: Int,
        visibleTop: CGFloat,
        visibleHeight: CGFloat,
        hourHeight: CGFloat
    ) -> Int? {
        let top = CGFloat(occurrence.lowerBound) / 60 * hourHeight
        let bottom = CGFloat(occurrence.upperBound) / 60 * hourHeight
        let wholly = top >= visibleTop && bottom <= visibleTop + visibleHeight
        return wholly ? nil : earliestStart
    }

    /// The scroll offset a target minute produces (what `scrollTo` with
    /// `oneThird` does, ignoring the content's ends) — for tests.
    static func offset(forMinute minute: Int, visibleHeight: CGFloat, hourHeight: CGFloat) -> CGFloat {
        CGFloat(minute) / 60 * hourHeight - visibleHeight / 3
    }

    /// `motion.paging`: `easeOut` over its duration, or no animation under
    /// Reduce Motion ("instant swap").
    static func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeOut(duration: Tokens.Motion.Paging.duration)
    }
}

/// Invisible views every `ConflictScroll.anchorStep` minutes, each with its
/// `anchorID`, stacked over a 24-hour canvas so `ScrollViewReader` can scroll
/// to any of them. (SwiftUI scrolls to views by id, not to offsets.)
///
/// They are stacked in a `VStack` — a real layout position — and NOT placed
/// with `.offset(y:)`: `scrollTo` targets a view's LAYOUT frame, and an
/// offset moves only the drawing, so offset anchors all sit at y = 0 and
/// every scroll lands at the top. (Found in task P2-F15.)
struct ConflictScrollAnchors: View {
    let hourHeight: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(stride(from: 0, to: 1440, by: ConflictScroll.anchorStep)), id: \.self) { minute in
                Color.clear
                    .frame(height: CGFloat(ConflictScroll.anchorStep) / 60 * hourHeight)
                    .id(ConflictScroll.anchorID(minute: minute))
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
