//
//  CanvasColumnLayoutTests.swift
//  KadenceTests
//
//  Task P2-F02 (DEVIATIONS B20; layouts.md §6, amended 2026-10-05). The
//  canvas reserves the legacy scroller's width before dividing its columns,
//  so the scroll view — scroller included — never grows past the slot
//  `MainWindow` gives it and paints over the inspector's leading edge. The
//  live half (inspector text ≥ spacing.xl inside both edges, no edge line)
//  is Scripts/check-inspector-inset.sh.
//

import Testing
import Foundation
import AppKit
@testable import Kadence

@Suite("Canvas columns — the scroller is reserved before dividing (B20)")
struct CanvasColumnLayoutTests {

    private let gutter = Tokens.Size.timeGutterWidth
    private let floor = Tokens.Size.dayColumnMin

    @Test("Content plus the reserve fills the slot exactly, for either scroller style",
          arguments: [CGFloat(0), CGFloat(15), CGFloat(17)])
    func fitsSlot(reserve: CGFloat) {
        // 939pt: the canvas slot measured live in the 1500pt main window.
        let total: CGFloat = 939
        let layout = CanvasColumnLayout.columnWidth(totalWidth: total, gutterWidth: gutter,
                                                    dayCount: 7, columnMin: floor,
                                                    scrollerReserve: reserve)
        #expect(!layout.needsHorizontalScroll)
        let content = CanvasColumnLayout.contentWidth(columnWidth: layout.width, gutterWidth: gutter, dayCount: 7)
        #expect(abs(content + reserve - total) < 0.001)
    }

    @Test("Without the reserve the legacy scroller would overflow by its own width")
    func oldArithmeticOverflowed() {
        let reserve: CGFloat = 17
        let unreserved = CanvasColumnLayout.columnWidth(totalWidth: 939, gutterWidth: gutter,
                                                        dayCount: 7, columnMin: floor, scrollerReserve: 0)
        let content = CanvasColumnLayout.contentWidth(columnWidth: unreserved.width, gutterWidth: gutter, dayCount: 7)
        #expect(content + reserve - 939 == reserve, "the 17pt drawn over the inspector")
    }

    @Test("Week hits the column floor and scrolls; Day never does")
    func floorWeekOnly() {
        let narrow = gutter + 17 + floor * 7 - 7
        let week = CanvasColumnLayout.columnWidth(totalWidth: narrow, gutterWidth: gutter,
                                                  dayCount: 7, columnMin: floor, scrollerReserve: 17)
        #expect(week.needsHorizontalScroll)
        #expect(week.width == floor)

        let day = CanvasColumnLayout.columnWidth(totalWidth: 200, gutterWidth: gutter,
                                                 dayCount: 1, columnMin: nil, scrollerReserve: 17)
        #expect(!day.needsHorizontalScroll)
        #expect(day.width == 200 - gutter - 17)
    }

    @Test("A slot narrower than gutter + reserve gives a zero, not negative, column")
    func neverNegative() {
        let layout = CanvasColumnLayout.columnWidth(totalWidth: 10, gutterWidth: gutter,
                                                    dayCount: 1, columnMin: nil, scrollerReserve: 17)
        #expect(layout.width == 0)
    }

    @Test("Overlay scrollers take no room; legacy takes the system's own width")
    @MainActor
    func reservePerStyle() {
        #expect(CanvasColumnLayout.scrollerReserve(style: .overlay) == 0)
        #expect(CanvasColumnLayout.scrollerReserve(style: .legacy)
                == NSScroller.scrollerWidth(for: .regular, scrollerStyle: .legacy))
        #expect(CanvasColumnLayout.scrollerReserve(style: .legacy) > 0)
    }
}
