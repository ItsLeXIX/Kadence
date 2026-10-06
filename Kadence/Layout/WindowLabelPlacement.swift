//
//  WindowLabelPlacement.swift
//  Kadence
//
//  components.md §7 rules 2 and 3 (amended 2026-10-05; closes G-025) — where
//  a background window's label is drawn. Pure: the caller supplies each
//  column's day, the frames of the blocks laid out in it, and (Routines,
//  inactive columns) the frame of the §13.5.3 note. Task P2-F06.
//
//  Rule 2 — a label is never drawn half-covered. Labels sit BELOW blocks, so
//  a block over the label's rect leaves a sliced string (`Low energy` under
//  `Errands`). The label goes in the LEADING column the window spans whose
//  label rect meets no block frame, scanning in column order; if there is
//  none it is omitted for that span. Corrected 2026-10-06 (G-044, task
//  P2-SF2): Windows mode (§13.3) uses the SAME scan — a label drawn above a
//  block's border still reads struck out — and differs only in never
//  omitting: with every spanned column covered, the label goes in the
//  leading spanned column, above the dimmed blocks (`omitsWhenCovered:
//  false`).
//
//  Rule 3 — the leading column's corner is shared by stacking. When the
//  label's column carries a note and the two would overlap, the note keeps
//  the corner and the label goes `spacing.xs` below the note's frame.
//

import Foundation
import CoreGraphics
import AppKit

enum WindowLabelPlacement {

    struct Column {
        /// The calendar day this column draws (Routines: its reference day).
        var day: Date
        /// Block frames in this column's own coordinates.
        var blockFrames: [CGRect] = []
        /// The §13.5.3 note's frame in this column's coordinates, if any.
        var noteFrame: CGRect? = nil
    }

    struct Placed: Equatable, Sendable {
        var text: String
        var columnIndex: Int
        /// The label's rect in its column's coordinates.
        var frame: CGRect
    }

    /// - Parameters:
    ///   - labelSize: the label's drawn size (`typography.windowLabel`).
    ///     Injected so tests need no fonts; the views use `measuredSize`.
    static func place<Window: TimeWindowRenderable>(
        windows: [Window],
        columns: [Column],
        hourHeight: CGFloat,
        showsPeakFocus: Bool,
        omitsWhenCovered: Bool,
        calendar: Calendar = .current,
        labelSize: @MainActor (String) -> CGSize = WindowLabelPlacement.measuredSize
    ) -> [Placed] {
        var placed: [Placed] = []
        for window in windows where window.kind != .peakFocus || showsPeakFocus {
            let size = labelSize(window.label)
            // One label per span "top edge". A daily window has a span with
            // the same start time in every column it covers; those are one
            // span seen in several columns, and get ONE label between them.
            var startsSeen: [Int] = []
            var candidates: [Int: [(column: Int, y: CGFloat)]] = [:]
            for (index, column) in columns.enumerated() {
                let dayStart = calendar.startOfDay(for: column.day)
                for span in window.spans(on: column.day, calendar: calendar) {
                    let minute = Int((span.start.timeIntervalSince(dayStart) / 60).rounded())
                    if !startsSeen.contains(minute) { startsSeen.append(minute) }
                    // +1: the label sits just inside the window's top edge
                    // line, as `WindowLabelsLayer` always drew it.
                    let y = CGFloat(minute) / 60 * hourHeight + 1
                    candidates[minute, default: []].append((index, y))
                }
            }
            for minute in startsSeen {
                let spanned = candidates[minute] ?? []
                // The label's rect in a candidate column. Rule 3: the note
                // keeps the corner; the label stacks `spacing.xs` below it.
                func rect(in candidate: (column: Int, y: CGFloat)) -> CGRect {
                    var rect = CGRect(origin: CGPoint(x: Tokens.Spacing.xs, y: candidate.y), size: size)
                    if let note = columns[candidate.column].noteFrame, note.intersects(rect) {
                        rect.origin.y = note.maxY + Tokens.Spacing.xs
                    }
                    return rect
                }
                // Rule 2, both modes: the leading spanned column whose label
                // rect meets no block frame.
                let free = spanned.first { candidate in
                    let r = rect(in: candidate)
                    return !columns[candidate.column].blockFrames.contains { $0.intersects(r) }
                }
                // None free: Blocks mode omits it for this span; Windows
                // mode draws it in the leading spanned column anyway.
                guard let chosen = free ?? (omitsWhenCovered ? nil : spanned.first) else { continue }
                placed.append(Placed(text: window.label, columnIndex: chosen.column, frame: rect(in: chosen)))
            }
        }
        return placed
    }

    /// `typography.windowLabel`'s drawn size: the text's width, and §3.3's
    /// `ceil(size × 1.2)` line height.
    static func measuredSize(_ text: String) -> CGSize {
        let font = NSFont.systemFont(
            ofSize: Tokens.Typography.WindowLabel.size,
            weight: CompactRowLayout.nsWeight(named: Tokens.Typography.WindowLabel.weight))
        let width = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        return CGSize(width: width, height: ceil(Tokens.Typography.WindowLabel.size * 1.2))
    }
}
