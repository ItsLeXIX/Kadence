//
//  BlockHitRegionTests.swift
//  KadenceTests
//
//  Regression cover for P2-T02: clicking an event block did nothing.
//
//  The defect itself was a SwiftUI modifier-ordering mistake (`.contentShape`
//  applied after `.offset`), and modifier ordering is not reachable from a unit
//  test — Scripts/check-block-hit-regions.sh and
//  Scripts/check-block-click-selects.sh cover that end of it, in a real window.
//
//  What IS reachable, and what these tests pin down, is the geometry the view
//  hands to `.contentShape`: `LaidOutBlock.hitInset` / `.hitRect`. The rule the
//  bug violated, stated over value types: a block's hit region is anchored to
//  that block's own laid-out frame, so two blocks at different times must have
//  hit regions at different places. Under the bug every block in a column
//  shared one hit region at the column's top-left corner.
//

import Testing
import Foundation
import CoreGraphics
@testable import Kadence

private let day = Calendar(identifier: .gregorian).date(
    from: DateComponents(year: 2026, month: 9, day: 9))!

private func at(_ hour: Int, _ minute: Int = 0) -> Date {
    day.addingTimeInterval(TimeInterval(hour * 3600 + minute * 60))
}

private func item(_ title: String, _ from: (Int, Int), _ to: (Int, Int)) -> LayoutItem {
    LayoutItem(id: UUID(), start: at(from.0, from.1), end: at(to.0, to.1), title: title)
}

private let dayGeometry = TimeGeometry(dayStart: day, hourHeight: Tokens.Size.hourHeightDay)

@Suite("Block hit regions")
struct BlockHitRegionTests {

    // MARK: The inset itself

    @Test("An unclamped block's hit region is exactly its frame")
    func unclampedHitRectEqualsFrame() {
        let layout = DayLayoutEngine.layout(items: [item("Long", (9, 0), (10, 30))], columnWidth: 200, geometry: dayGeometry)
        let block = try! #require(layout.blocks.first)

        #expect(block.isClamped == false)
        #expect(block.hitExtension == 0)
        #expect(block.hitInset == 0)
        #expect(block.hitRect == block.frame)
    }

    @Test("A clamped block's hit region is larger, and stays centred on the frame")
    func clampedHitRectIsCentred() {
        // 5 minutes renders below size.blockMinRenderedHeight, so it clamps.
        let layout = DayLayoutEngine.layout(items: [item("Tiny", (9, 0), (9, 5))], columnWidth: 200, geometry: dayGeometry)
        let block = try! #require(layout.blocks.first)

        #expect(block.isClamped)
        #expect(block.hitExtension == Tokens.Size.blockHitExtension)

        // Grows by exactly hitExtension in each axis...
        #expect(block.hitRect.width == block.frame.width + Tokens.Size.blockHitExtension)
        #expect(block.hitRect.height == block.frame.height + Tokens.Size.blockHitExtension)

        // ...and the growth is split evenly, so the centre does not move. This
        // is the "centred on the true frame" promise in LaidOutBlock.
        #expect(abs(block.hitRect.midX - block.frame.midX) < 0.0001)
        #expect(abs(block.hitRect.midY - block.frame.midY) < 0.0001)
    }

    // MARK: The invariant the bug broke

    @Test("Every block's hit region contains that block's own centre")
    func hitRectContainsOwnCentre() {
        let items = [
            item("Breakfast", (7, 15), (7, 45)),
            item("Morning review", (8, 0), (9, 0)),
            item("Datenmodellierung", (9, 0), (10, 30)),
            item("Stand-up", (12, 30), (12, 45)),
            item("Gym", (16, 15), (17, 0)),
            item("Reading", (21, 0), (21, 30)),
        ]
        let layout = DayLayoutEngine.layout(items: items, columnWidth: 200, geometry: dayGeometry)
        #expect(layout.blocks.count == items.count)

        for block in layout.blocks {
            #expect(
                block.hitRect.contains(CGPoint(x: block.frame.midX, y: block.frame.midY)),
                "hit region must sit on the block it belongs to")
        }
    }

    @Test("Blocks at different times get hit regions at different places")
    func hitRegionsDoNotCollapse() {
        // The direct analogue of the shell check: order by start time, and the
        // hit regions must march down the column. Under the P2-T02 bug every
        // one of these collapsed onto the same origin.
        let items = [
            item("07:15", (7, 15), (7, 45)),
            item("08:00", (8, 0), (9, 0)),
            item("09:00", (9, 0), (10, 30)),
            item("12:30", (12, 30), (12, 45)),
            item("16:15", (16, 15), (17, 0)),
            item("21:00", (21, 0), (21, 30)),
        ]
        let layout = DayLayoutEngine.layout(items: items, columnWidth: 200, geometry: dayGeometry)
        let sorted = layout.blocks.sorted { $0.frame.minY < $1.frame.minY }

        let origins = Set(sorted.map { "\($0.hitRect.minX)|\($0.hitRect.minY)" })
        #expect(origins.count == items.count, "every block needs its own hit region")

        for (a, b) in zip(sorted, sorted.dropFirst()) {
            #expect(a.hitRect.minY < b.hitRect.minY, "a later block must sit lower")
        }
    }

    @Test("A hit region tracks its frame rather than the column origin")
    func hitRegionIsNotAtTheColumnOrigin() {
        // The bug's actual signature: the hit region ended up at the column's
        // top-left corner regardless of the block's time.
        let layout = DayLayoutEngine.layout(items: [item("Afternoon", (14, 30), (16, 0))], columnWidth: 200, geometry: dayGeometry)
        let block = try! #require(layout.blocks.first)

        #expect(block.frame.minY > 0)
        #expect(block.hitRect.minY > 0)
        #expect(block.hitRect.contains(CGPoint(x: 0, y: 0)) == false)
    }
}
