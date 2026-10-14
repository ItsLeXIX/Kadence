//
//  GutterLabelLayout.swift
//  Kadence
//
//  components.md §8 (amended 2026-10-14, G-082; DEVIATIONS A42): which hour
//  labels the time gutter drops for the now time and the cursor time
//  (interactions.md §1), measured on the labels **as drawn**.
//
//  The gutter hangs each hour label below its line (top edge at the line +
//  2pt) and draws the now time and the cursor time with their top edge 5pt
//  above their own line. The old rule compared the two *times* (within
//  12pt), which let `10:18` print over `10:00` in Week: the hour label hangs
//  down towards the now time. Now an hour label is dropped when its text
//  frame and a marker's text frame would overlap or come within 2pt.
//
//  Pure: hour height, the label height and the marker's y in, frames and
//  the drop decision out. `TimeGutterView` draws exactly these frames.
//

import AppKit
import SwiftUI

enum GutterLabelLayout {
    /// An hour label's top edge sits this far below its hour line.
    static let hourLabelHang: CGFloat = 2
    /// The now / cursor time's top edge sits this far above its line.
    static let markerRise: CGFloat = 5
    /// §8: the clearance a drawn hour label must keep from a marker's text.
    static let clearance: CGFloat = 2

    /// The drawn height of one `hourLabel` line (13pt at 10pt): measured
    /// once on a hosted `Text` in the gutter's own type style, so the frame
    /// the rule compares is the frame the gutter draws — not the font's
    /// nominal line height (12pt), which is what let the old rule miss.
    static let labelHeight: CGFloat = {
        let host = NSHostingView(rootView: AnyView(Text("00:00").typeStyle(.hourLabel)))
        return host.fittingSize.height
    }()

    /// The vertical extent of a drawn label, top and bottom.
    struct Frame: Equatable {
        var top: CGFloat
        var bottom: CGFloat
    }

    static func hourLabelFrame(hour: Int, hourHeight: CGFloat, labelHeight: CGFloat = labelHeight) -> Frame {
        let top = CGFloat(hour) * hourHeight + hourLabelHang
        return Frame(top: top, bottom: top + labelHeight)
    }

    /// The now time's or the cursor time's frame, for a line at `y`.
    static func markerFrame(y: CGFloat, labelHeight: CGFloat = labelHeight) -> Frame {
        let top = y - markerRise
        return Frame(top: top, bottom: top + labelHeight)
    }

    /// True when the two frames overlap or come within `clearance`.
    static func collide(_ a: Frame, _ b: Frame) -> Bool {
        a.top < b.bottom + clearance && b.top < a.bottom + clearance
    }

    /// Whether the label of `hour` is dropped for markers drawn at `markerYs`.
    static func isSuppressed(hour: Int, hourHeight: CGFloat, markerYs: [CGFloat],
                             labelHeight: CGFloat = labelHeight) -> Bool {
        let label = hourLabelFrame(hour: hour, hourHeight: hourHeight, labelHeight: labelHeight)
        return markerYs.contains { collide(label, markerFrame(y: $0, labelHeight: labelHeight)) }
    }

    /// The hours (0–23) whose labels are drawn.
    static func drawnHours(hourHeight: CGFloat, markerYs: [CGFloat], labelHeight: CGFloat = labelHeight) -> [Int] {
        (0..<24).filter { !isSuppressed(hour: $0, hourHeight: hourHeight, markerYs: markerYs, labelHeight: labelHeight) }
    }
}
