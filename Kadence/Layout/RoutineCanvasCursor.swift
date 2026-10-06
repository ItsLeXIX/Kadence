//
//  RoutineCanvasCursor.swift
//  Kadence
//
//  interactions.md §1 (amended 2026-10-07, G-050) and §11.1 (2026-10-07
//  note): the Routines canvas's cursor mode, minimum form. An indicator only:
//  one 1pt accent line across all seven day columns at a time of day, with
//  that time in the gutter. `↑` `↓` move it by 15 minutes; nothing creates at
//  it in Phase 2.
//
//  Times here are minutes from midnight (0…1439), the unit `RoutineBlock`
//  and `TimeWindow` already use: a template has no dates, so the cursor is a
//  time of day, not a `Date` like the main grid's `CalendarState.timeCursor`.
//
//  Pure functions over plain values, so `RoutineCanvasCursorTests` can check
//  every rule without a window. `RoutinesWindow` does the wiring.
//

import CoreGraphics
import Foundation

enum RoutineCanvasCursor {
    /// `↑` `↓` step (§1: "move it 15 minutes").
    static let step = 15
    /// "clamped to 00:00…23:45".
    static let range = 0...(24 * 60 - step)

    /// Whether the canvas is in cursor mode: focused, with nothing selected
    /// (no block, no time window) and no template conflict open (a conflict
    /// always has its block selected, so this is belt and braces).
    static func isCursorMode(canvasFocused: Bool, hasBlockSelection: Bool,
                             hasWindowSelection: Bool, inConflict: Bool) -> Bool {
        canvasFocused && !hasBlockSelection && !hasWindowSelection && !inConflict
    }

    /// Where the cursor goes when focus arrives on the canvas with nothing
    /// selected (§1, "On entry"): the last cursor time of this window
    /// session if it is in the viewport; otherwise the first whole hour
    /// strictly below the viewport's top edge — 07:00 at the default 06:00
    /// scroll. `visibleTop`/`visibleHeight` are in canvas content points.
    static func entryMinute(last: Int?, visibleTop: CGFloat, visibleHeight: CGFloat,
                            hourHeight: CGFloat) -> Int {
        if let last, isInView(last, visibleTop: visibleTop, visibleHeight: visibleHeight, hourHeight: hourHeight) {
            return last
        }
        // "Strictly below": a top edge exactly on 06:00's line gives 07:00,
        // not 06:00. `floor` then `+ 1` does that for both cases (06:00 →
        // 07:00, 06:20 → 07:00). The epsilon absorbs a scroll offset that
        // lands a hair under the line (e.g. 359.9999pt for 06:00).
        let hourAtTop = Int(((visibleTop + 0.001) / hourHeight).rounded(.down))
        return clamp((hourAtTop + 1) * 60)
    }

    /// `↑` (-1) / `↓` (+1): 15 minutes, clamped to 00:00…23:45.
    static func moved(_ minute: Int, by direction: Int) -> Int {
        clamp(minute + direction * step)
    }

    /// The arrow keys in cursor mode (§1): `↑` `↓` move, `←` `→` do nothing
    /// (§11.1 — a template has no dates). Returns the new cursor time.
    enum Arrow: Sendable { case up, down, left, right }
    static func apply(_ arrow: Arrow, to minute: Int) -> Int {
        switch arrow {
        case .up: moved(minute, by: -1)
        case .down: moved(minute, by: 1)
        case .left, .right: minute
        }
    }

    /// What `⎋` does on the focused canvas (§1: selection mode → cursor
    /// mode → unfocused).
    enum EscapeOutcome: Equatable, Sendable {
        /// Drop the selection; focus stays, so the canvas enters cursor mode.
        case deselect
        /// Leave the canvas unfocused.
        case unfocus
    }
    static func escape(hasSelection: Bool) -> EscapeOutcome {
        hasSelection ? .deselect : .unfocus
    }

    /// An empty-canvas click at `y` (column content points): the clicked
    /// slot's time, snapped to 15 minutes as the main grid snaps its click
    /// (`TimeGeometry.snap`, which rounds), clamped like the keys.
    static func minute(forY y: CGFloat, hourHeight: CGFloat) -> Int {
        let raw = Double(y / hourHeight * 60)
        return clamp(Int((raw / Double(step)).rounded()) * step)
    }

    /// The line's y in canvas content points.
    static func y(for minute: Int, hourHeight: CGFloat) -> CGFloat {
        CGFloat(minute) / 60 * hourHeight
    }

    static func isInView(_ minute: Int, visibleTop: CGFloat, visibleHeight: CGFloat,
                         hourHeight: CGFloat) -> Bool {
        guard visibleHeight > 0 else { return false }
        let lineY = y(for: minute, hourHeight: hourHeight)
        // The 1pt line must be wholly inside the viewport.
        return lineY >= visibleTop && lineY + 1 <= visibleTop + visibleHeight
    }

    /// How to keep the line in view after a move, scrolling "only as far as
    /// needed": nothing while it is in view; otherwise the edge it went past.
    enum ScrollEdge: Equatable, Sendable { case top, bottom }
    static func scrollEdge(for minute: Int, visibleTop: CGFloat, visibleHeight: CGFloat,
                           hourHeight: CGFloat) -> ScrollEdge? {
        guard visibleHeight > 0,
              !isInView(minute, visibleTop: visibleTop, visibleHeight: visibleHeight, hourHeight: hourHeight)
        else { return nil }
        return y(for: minute, hourHeight: hourHeight) < visibleTop ? .top : .bottom
    }

    /// The canvas's accessibility value in cursor mode (§1): `07:00`.
    static func accessibilityValue(_ minute: Int) -> String {
        String(format: "%02d:%02d", minute / 60, minute % 60)
    }

    private static func clamp(_ minute: Int) -> Int {
        min(max(minute, range.lowerBound), range.upperBound)
    }
}
