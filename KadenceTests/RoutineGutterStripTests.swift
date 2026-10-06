//
//  RoutineGutterStripTests.swift
//  KadenceTests
//
//  Task P2-SF3: layouts.md §8 (amended 2026-10-06; G-041; DEVIATIONS B22) —
//  the Routines canvas's time gutter carries the window treatments: protected
//  fill at `Lunch`'s and `Sleep`'s heights, the low-energy hatch at `Low
//  energy`'s, nothing at `Deep work`'s (peak focus is an outline and stays
//  out of the gutter), and no label. The real `RoutineGutterStrip` is
//  rendered offscreen over the canvas colour and its pixels sampled.
//

import Testing
import Foundation
import SwiftUI
import AppKit
@testable import Kadence

@Suite("The Routines gutter carries window treatments (layouts.md §8, G-041)")
@MainActor
struct RoutineGutterStripTests {

    private let hourHeight: CGFloat = 44

    /// Renders the strip at 1× over `surface.canvas`, Monday leading (the
    /// seeded windows: Sleep daily, Low energy and Deep work Mon–Fri, Lunch
    /// Mon/Wed/Fri).
    private func render() throws -> NSBitmapImageRep {
        let view = RoutineGutterStrip(
            windows: MockData.makeTimeWindows(), leadingWeekday: 2, hourHeight: hourHeight)
            .background(Tokens.Color.Surface.canvas)
            .environment(\.colorScheme, .light)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        return NSBitmapImageRep(cgImage: image)
    }

    /// A pixel as 8-bit RGBA, comparable with `==`.
    private func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> [Int] {
        var p = [Int](repeating: 0, count: 4)
        rep.getPixel(&p, atX: x, y: y)
        return p
    }

    /// Every pixel of one row of the strip, left of the trailing hour labels
    /// (labels are trailing-aligned; the left 8pt never carries text).
    private func row(_ rep: NSBitmapImageRep, hour: Int, minute: Int) -> [[Int]] {
        let y = Int((CGFloat(hour) + CGFloat(minute) / 60) * hourHeight)
        return (0..<8).map { pixel(rep, $0, y) }
    }

    @Test("Protected fill at Sleep and Lunch, hatch at Low energy, nothing at Deep work")
    func treatments() throws {
        let rep = try render()
        #expect(rep.pixelsWide == Int(Tokens.Size.timeGutterWidth))
        #expect(rep.pixelsHigh == Int(hourHeight * 24))

        // Plain canvas, for comparison: 10:40, inside no window.
        let canvas = row(rep, hour: 10, minute: 40)
        #expect(Set(canvas).count == 1, "an empty row is one colour")
        let canvasColour = canvas[0]

        // Sleep (22:00–07:00): the protected fill, uniform across the row.
        for (h, m) in [(3, 40), (23, 20)] {
            let r = row(rep, hour: h, minute: m)
            #expect(Set(r).count == 1 && r[0] != canvasColour, "Sleep at \(h):\(m) is filled")
        }
        // Lunch (12:00–13:00, Monday): the same fill.
        let lunch = row(rep, hour: 12, minute: 40)
        let sleep = row(rep, hour: 3, minute: 40)
        #expect(lunch == sleep, "Lunch carries the protected fill")

        // Low energy (13:00–14:30): hatch — canvas between 1pt lines, so the
        // row mixes canvas pixels and line pixels, and is not the fill.
        let low = row(rep, hour: 13, minute: 40)
        #expect(low.contains(canvasColour), "hatch gaps show the canvas")
        #expect(low.contains { $0 != canvasColour }, "hatch lines are drawn")
        #expect(!low.contains(sleep[0]), "not the protected fill")

        // Deep work (15:00–17:00, peak focus): no treatment in the gutter.
        for (h, m) in [(15, 40), (16, 40)] {
            #expect(row(rep, hour: h, minute: m).allSatisfy { $0 == canvasColour },
                    "Deep work at \(h):\(m) leaves the gutter plain")
        }
    }

    @Test("No window label in the gutter: label placement only ever names a day column")
    func noLabelInGutter() {
        // The strip draws no `WindowLabelsLayer`; labels are placed per day
        // column (`WindowLabelPlacement`), whose indices are columns only.
        let columns = (0..<7).map { i in
            WindowLabelPlacement.Column(
                day: RoutineWeekLayout.referenceDayStart(weekday: (i + 1) % 7 + 1, now: Date()))
        }
        let placed = WindowLabelPlacement.place(
            windows: MockData.makeTimeWindows(), columns: columns, hourHeight: hourHeight,
            showsPeakFocus: true, omitsWhenCovered: false, labelSize: { _ in CGSize(width: 50, height: 12) })
        #expect(!placed.isEmpty)
        #expect(placed.allSatisfy { (0..<7).contains($0.columnIndex) && $0.frame.minX >= Tokens.Spacing.xs })
    }
}
