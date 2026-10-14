//
//  GutterLabelLayoutTests.swift
//  KadenceTests
//
//  PHASE3-SLICE2-PLAN.md task 2 — A42 (G-082): components.md §8 amended
//  2026-10-14, interactions.md §1 (the cursor time), §30 item 22. The time
//  gutter drops an hour label when its drawn text frame and the now time's
//  (or the cursor time's) overlap or come within 2pt. Injected clock; Week
//  (44pt) and Day (60pt) hour heights.
//
//  This replaces the Phase 1 "within 12pt of the times" rule, which no test
//  pinned; the rule change is the spec's (§8), not a regression.
//

import Testing
import Foundation
import SwiftUI
import AppKit
@testable import Kadence

@MainActor
@Suite(.serialized)
struct GutterLabelLayoutTests {
    let week = Tokens.Size.hourHeightWeek
    let day = Tokens.Size.hourHeightDay

    func geometry(_ hourHeight: CGFloat) -> TimeGeometry {
        TimeGeometry(dayStart: TestClock.date("2026-10-15 00:00"), hourHeight: hourHeight)
    }

    func clock(_ hhmm: String) -> Date { TestClock.date("2026-10-15 \(hhmm)") }

    func drawn(_ hourHeight: CGFloat, at time: String) -> [Int] {
        let y = geometry(hourHeight).yForTimeOfDay(clock(time))
        return GutterLabelLayout.drawnHours(hourHeight: hourHeight, markerYs: [y])
    }

    @Test("The label height is the hosted hourLabel's drawn height (13pt at 10pt)")
    func labelHeightAsDrawn() {
        // The two hour heights the parameterised tests use are the tokens'.
        #expect(week == 44 && day == 60)
        #expect(GutterLabelLayout.labelHeight == 13)
        let host = NSHostingView(rootView: Text("10:18").typeStyle(.hourLabel))
        #expect(host.fittingSize.height == GutterLabelLayout.labelHeight)
    }

    @Test("At 10:18 `10:00` is dropped and no drawn label is within 2pt of the now time; at 10:40 both drawn",
          arguments: [CGFloat(44), CGFloat(60)])
    func nowAt1018And1040(hourHeight: CGFloat) {
        let at1018 = drawn(hourHeight, at: "10:18")
        #expect(!at1018.contains(10))
        let now = GutterLabelLayout.markerFrame(y: geometry(hourHeight).yForTimeOfDay(clock("10:18")))
        for hour in at1018 {
            let label = GutterLabelLayout.hourLabelFrame(hour: hour, hourHeight: hourHeight)
            // Clear by at least 2pt: the gap between the frames is ≥ 2.
            #expect(label.bottom + 2 <= now.top || now.bottom + 2 <= label.top)
        }
        let at1040 = drawn(hourHeight, at: "10:40")
        #expect(at1040.contains(10) && at1040.contains(11))
        #expect(at1040.count == 24)
    }

    /// The boundary, from the frames: `10:00`'s label is [y₁₀ + 2, y₁₀ + 15]
    /// (13pt tall); the now time's is [y − 5, y + 8]. Dropped while
    /// `y − 5 < y₁₀ + 17` and `y₁₀ + 2 < y + 10`, i.e. `−8 < y − y₁₀ < 22`.
    /// Week (44pt/h): −10.9 min < m < 30 min → 09:50 … 10:29.
    /// Day (60pt/h, 1pt/min): −8 < m < 22 → 09:53 … 10:21.
    @Test("Boundary: the earliest and latest minutes at which `10:00` is dropped, Week and Day")
    func boundaries() {
        func dropped(_ hourHeight: CGFloat, _ time: String) -> Bool { !drawn(hourHeight, at: time).contains(10) }
        // Week — pinned
        #expect(!dropped(week, "09:49"))
        #expect(dropped(week, "09:50"))
        #expect(dropped(week, "10:29"))
        #expect(!dropped(week, "10:30"))
        // Day — pinned
        #expect(!dropped(day, "09:52"))
        #expect(dropped(day, "09:53"))
        #expect(dropped(day, "10:21"))
        #expect(!dropped(day, "10:22"))
        // The same bounds, computed from the two frames alone (no clock): the
        // first and last whole minute m whose marker frame collides with
        // `10:00`'s label frame.
        func bounds(_ hourHeight: CGFloat) -> (Int, Int) {
            let label = GutterLabelLayout.hourLabelFrame(hour: 10, hourHeight: hourHeight)
            let hits = (-60...60).filter { m in
                let y = 10 * hourHeight + CGFloat(m) * hourHeight / 60
                return GutterLabelLayout.collide(label, GutterLabelLayout.markerFrame(y: y))
            }
            return (hits.first ?? 0, hits.last ?? 0)
        }
        #expect(bounds(week) == (-10, 29))
        #expect(bounds(day) == (-7, 21))
    }

    @Test("The cursor time at 10:18 drops `10:00` by the same rule", arguments: [CGFloat(44), CGFloat(60)])
    func cursor(hourHeight: CGFloat) {
        let gutter = TimeGutterView(geometry: geometry(hourHeight), now: clock("06:00"), showsNow: false,
                                    cursor: clock("10:18"))
        #expect(gutter.markerYs == [geometry(hourHeight).yForTimeOfDay(clock("10:18"))])
        #expect(GutterLabelLayout.isSuppressed(hour: 10, hourHeight: hourHeight, markerYs: gutter.markerYs))
        #expect(!GutterLabelLayout.isSuppressed(hour: 11, hourHeight: hourHeight, markerYs: gutter.markerYs))
    }

    @Test("Item 22 renders (offscreen, clock pinned): Week and Day at 10:18, Week at 10:40")
    func renders() {
        for (name, hourHeight, time) in [("now-label-week-1018", week, "10:18"),
                                         ("now-label-day-1018", day, "10:18"),
                                         ("now-label-week-1040", week, "10:40")] {
            let g = geometry(hourHeight)
            let top = 8 * hourHeight
            let height = 5 * hourHeight
            let view = HStack(alignment: .top, spacing: 0) {
                TimeGutterView(geometry: g, now: clock(time), showsNow: true)
                    .frame(width: Tokens.Size.timeGutterWidth, height: 24 * hourHeight, alignment: .top)
                ZStack(alignment: .top) {
                    HourLinesLayer(geometry: g)
                    NowLineView(geometry: g, now: clock(time), showsDot: true)
                }
                .frame(width: 160, height: 24 * hourHeight, alignment: .top)
            }
            .offset(y: -top)
            .frame(width: Tokens.Size.timeGutterWidth + 160, height: height, alignment: .top)
            .clipped()
            .background(Tokens.Color.Surface.canvas)
            #expect(Phase3Render.render(name, view, size: CGSize(width: Tokens.Size.timeGutterWidth + 160, height: height),
                                        suffix: "p3b") != nil)
        }
    }
}
