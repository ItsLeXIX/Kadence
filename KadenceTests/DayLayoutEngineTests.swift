//
//  DayLayoutEngineTests.swift
//  KadenceTests
//
//  layouts.md §3.3. This is the piece where a silent bug means a block is drawn
//  on top of another one and you miss it, so it is the piece with the tests.
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

private let weekGeometry = TimeGeometry(dayStart: day, hourHeight: Tokens.Size.hourHeightWeek)
private let dayGeometry = TimeGeometry(dayStart: day, hourHeight: Tokens.Size.hourHeightDay)

// MARK: - Step 1, clustering

@Suite("Clustering")
struct ClusteringTests {

    @Test("Non-overlapping blocks form separate clusters")
    func separateClusters() {
        let items = [item("A", (9, 0), (10, 0)), item("B", (11, 0), (12, 0))]
        let clusters = DayLayoutEngine.cluster(items, minimumDuration: dayGeometry.minimumRenderedDuration)
        #expect(clusters.count == 2)
    }

    @Test("Touching blocks do not overlap")
    func touchingIsNotOverlap() {
        // a.start < b.end && b.start < a.end — 10:00–11:00 does not overlap 09:00–10:00.
        let items = [item("A", (9, 0), (10, 0)), item("B", (10, 0), (11, 0))]
        let clusters = DayLayoutEngine.cluster(items, minimumDuration: 0)
        #expect(clusters.count == 2)
    }

    @Test("Overlap is transitive: A–B and B–C makes one cluster of three")
    func transitiveCluster() {
        let items = [
            item("A", (9, 0), (10, 0)),
            item("B", (9, 30), (10, 30)),
            item("C", (10, 15), (11, 0)),
        ]
        let clusters = DayLayoutEngine.cluster(items, minimumDuration: 0)
        #expect(clusters.count == 1)
        #expect(clusters[0].count == 3)
    }

    @Test("Two short blocks that only collide once clamped are still one cluster")
    func clampedBlocksCollide() {
        // 5 minutes at the Week scale is under the 11pt floor, so the first
        // block's rendered box reaches into the second.
        let items = [item("A", (9, 0), (9, 5)), item("B", (9, 8), (9, 13))]
        let clusters = DayLayoutEngine.cluster(
            items, minimumDuration: weekGeometry.minimumRenderedDuration)
        #expect(clusters.count == 1, "clamped blocks must be treated as overlapping")
    }
}

// MARK: - Step 2, column packing

@Suite("Column packing")
struct PackingTests {

    @Test("Sort is start ascending, then duration descending, then title")
    func sortOrder() {
        let sorted = DayLayoutEngine.sortForLayout([
            item("Zebra", (9, 0), (9, 30)),
            item("Apple", (9, 0), (9, 30)),
            item("Long", (9, 0), (11, 0)),
            item("Early", (8, 0), (8, 30)),
        ])
        #expect(sorted.map(\.title) == ["Early", "Long", "Apple", "Zebra"])
    }

    @Test("Sequential blocks reuse the same sub-column")
    func reusesColumn() {
        let sorted = DayLayoutEngine.sortForLayout([
            item("A", (9, 0), (10, 0)),
            item("B", (10, 0), (11, 0)),
        ])
        let packed = DayLayoutEngine.packIntoSubColumns(sorted, minimumDuration: 0)
        #expect(packed.subColumnCount == 1)
        #expect(packed.indices == [0, 0])
    }

    @Test("Three mutually overlapping blocks need three sub-columns")
    func threeWayOverlap() {
        let sorted = DayLayoutEngine.sortForLayout([
            item("A", (18, 0), (19, 30)),
            item("B", (18, 15), (19, 0)),
            item("C", (18, 45), (19, 45)),
        ])
        let packed = DayLayoutEngine.packIntoSubColumns(sorted, minimumDuration: 0)
        #expect(packed.subColumnCount == 3)
        #expect(Set(packed.indices) == [0, 1, 2])
    }

    @Test("A block expands into a free trailing sub-column")
    func expansion() {
        // A occupies 09:00–09:30 in column 0; B 10:00–11:00 in column 0 as well.
        // C 09:00–09:15 lands in column 1 and, since nothing it overlaps sits to
        // its trailing side, it should NOT expand past the cluster width.
        let sorted = DayLayoutEngine.sortForLayout([
            item("A", (9, 0), (9, 30)),
            item("C", (9, 0), (9, 15)),
        ])
        let packed = DayLayoutEngine.packIntoSubColumns(sorted, minimumDuration: 0)
        #expect(packed.subColumnCount == 2)
        // Neither can expand: they overlap each other.
        #expect(packed.spans == [1, 1])
    }

    @Test("Day view packs rather than cascades: the column is wide enough")
    func dayPacks() {
        let items = [
            item("A", (18, 0), (19, 30)),
            item("B", (18, 15), (19, 0)),
            item("C", (18, 45), (19, 45)),
        ]
        // A realistic Day canvas: 1000pt window minus gutter.
        let layout = DayLayoutEngine.layout(items: items, columnWidth: 900, geometry: dayGeometry)
        #expect(layout.blocks.allSatisfy { !$0.isCascaded })
        #expect(layout.overflow.isEmpty)
    }
}

// MARK: - Step 3, cascade

@Suite("Cascade fallback")
struct CascadeTests {

    @Test("Week resolves a two-block overlap by cascade, not packing")
    func weekCascades() {
        // layouts.md §3.3: at a typical 114pt Week column a two-block cluster
        // yields a 53pt slot, below the 96pt threshold, so cascade fires.
        let items = [item("A", (10, 0), (11, 30)), item("B", (10, 15), (11, 45))]
        let layout = DayLayoutEngine.layout(items: items, columnWidth: 114, geometry: weekGeometry)
        #expect(layout.blocks.allSatisfy { $0.isCascaded })
    }

    @Test("Indent is 22pt at a typical Week column and clamps at the extremes")
    func indentClamping() {
        #expect(DayLayoutEngine.cascadeIndent(columnWidth: 114) == 22)
        // layouts.md §3.3 states 15pt at the 78pt minimum column: 78 × 0.19 = 14.82 → 15,
        // so the floor token never actually binds at any real column width.
        #expect(DayLayoutEngine.cascadeIndent(columnWidth: 78) == 15)
        #expect(DayLayoutEngine.cascadeIndent(columnWidth: 4000) == Tokens.Size.blockCascadeIndentMax)
    }

    @Test("Indent never falls below the min or exceeds the max at any width")
    func indentBounds() {
        for width in stride(from: 40.0, through: 400.0, by: 1.0) {
            let indent = DayLayoutEngine.cascadeIndent(columnWidth: width)
            #expect(indent >= Tokens.Size.blockCascadeIndentMin)
            #expect(indent <= Tokens.Size.blockCascadeIndentMax)
        }
    }

    @Test("Cascade indents step and stop at blockCascadeMaxSteps")
    func indentSteps() {
        let items = (0..<5).map { index in
            item("Overlap \(index)", (10, index * 5), (11, index * 5))
        }
        let layout = DayLayoutEngine.layout(items: items, columnWidth: 114, geometry: weekGeometry)
        let sorted = layout.blocks.sorted { $0.zIndex < $1.zIndex }
        let indent = DayLayoutEngine.cascadeIndent(columnWidth: 114)
        let maxSteps = Int(Tokens.Size.blockCascadeMaxSteps)

        for (index, block) in sorted.enumerated() {
            let expected = Tokens.Spacing.xxs + CGFloat(min(index, maxSteps)) * indent
            #expect(abs(block.frame.minX - expected) < 0.001, "block \(index) leading inset")
        }
        // The 4th and 5th share the last step: the cascade does not run away.
        #expect(sorted[3].frame.minX == sorted[4].frame.minX)
    }

    @Test("Every cascaded block keeps at least a rail and a glyph visible")
    func cascadeKeepsRailVisible() {
        // The narrowest block is columnWidth − 3 × indent; the spec's own figure
        // is 48pt at a typical Week column and 42pt at the absolute minimum.
        for width in [78.0, 114.0] {
            let items = (0..<6).map { index in item("O\(index)", (10, index * 5), (11, index * 5)) }
            let layout = DayLayoutEngine.layout(items: items, columnWidth: width, geometry: weekGeometry)
            let narrowest = layout.blocks.map(\.frame.width).min() ?? 0
            let needed = Tokens.Size.blockRailWidth + Tokens.Size.blockPadding + Tokens.Size.blockGlyphSize
            #expect(narrowest >= needed, "at \(width)pt the narrowest block was \(narrowest)pt")
        }
    }

    @Test("Beyond five blocks the rest become a +N chip")
    func overflowChip() {
        let items = (0..<8).map { index in item("O\(index)", (10, index * 5), (11, index * 5)) }
        let layout = DayLayoutEngine.layout(items: items, columnWidth: 114, geometry: weekGeometry)
        #expect(layout.blocks.count == Int(Tokens.Size.blockCascadeMaxVisible))
        #expect(layout.overflow.count == 1)
        #expect(layout.overflow[0].hiddenCount == 3)
    }

    @Test("Z-order follows start order, so later blocks draw on top")
    func zOrder() {
        let items = (0..<4).map { index in item("O\(index)", (10, index * 5), (11, index * 5)) }
        let layout = DayLayoutEngine.layout(items: items, columnWidth: 114, geometry: weekGeometry)
        let byZ = layout.blocks.sorted { $0.zIndex < $1.zIndex }
        #expect(byZ.map(\.zIndex) == [0, 1, 2, 3])
        // Leading inset increases with z, i.e. the topmost block is the most indented.
        #expect(byZ[0].frame.minX < byZ[3].frame.minX)
    }
}

// MARK: - Frames

@Suite("Frames")
struct FrameTests {

    @Test("A block's y and height come straight from the time geometry")
    func framePosition() throws {
        let items = [item("A", (9, 0), (10, 30))]
        let layout = DayLayoutEngine.layout(items: items, columnWidth: 400, geometry: dayGeometry)
        let block = try #require(layout.blocks.first)
        #expect(block.frame.minY == 9 * Tokens.Size.hourHeightDay)
        #expect(block.frame.height == 1.5 * Tokens.Size.hourHeightDay)
    }

    @Test("Short blocks clamp to the floor and gain a hit extension")
    func clamping() throws {
        let items = [item("Tiny", (9, 0), (9, 10))]
        let layout = DayLayoutEngine.layout(items: items, columnWidth: 400, geometry: weekGeometry)
        let block = try #require(layout.blocks.first)
        #expect(block.isClamped)
        #expect(block.frame.height == Tokens.Size.blockMinRenderedHeight)
        #expect(block.hitExtension == Tokens.Size.blockHitExtension)
    }

    @Test("A comfortable block is not clamped and gets no hit extension")
    func noClamping() throws {
        let items = [item("Normal", (9, 0), (10, 0))]
        let layout = DayLayoutEngine.layout(items: items, columnWidth: 400, geometry: dayGeometry)
        let block = try #require(layout.blocks.first)
        #expect(!block.isClamped)
        #expect(block.hitExtension == 0)
    }

    @Test("Layout is deterministic: same input, byte-identical output")
    func determinism() {
        let items = [
            item("B", (9, 0), (10, 0)),
            item("A", (9, 0), (10, 0)),
            item("C", (9, 30), (10, 30)),
        ]
        let first = DayLayoutEngine.layout(items: items, columnWidth: 300, geometry: dayGeometry)
        let second = DayLayoutEngine.layout(items: items.reversed(), columnWidth: 300, geometry: dayGeometry)
        #expect(first.blocks.sorted { $0.id.uuidString < $1.id.uuidString }
                == second.blocks.sorted { $0.id.uuidString < $1.id.uuidString })
    }

    @Test("No two packed blocks in one cluster overlap on screen")
    func packedBlocksDoNotOverlapVisually() {
        let items = [
            item("A", (18, 0), (19, 30)),
            item("B", (18, 15), (19, 0)),
            item("C", (18, 45), (19, 45)),
        ]
        let layout = DayLayoutEngine.layout(items: items, columnWidth: 900, geometry: dayGeometry)
        for a in layout.blocks {
            for b in layout.blocks where a.id != b.id {
                let overlapping = a.frame.intersects(b.frame)
                #expect(!overlapping, "packed blocks must not overlap: \(a.frame) vs \(b.frame)")
            }
        }
    }

    @Test("An empty day lays out to nothing")
    func emptyDay() {
        let layout = DayLayoutEngine.layout(items: [], columnWidth: 400, geometry: dayGeometry)
        #expect(layout.blocks.isEmpty)
        #expect(layout.overflow.isEmpty)
    }

    @Test("A zero-width column produces no frames rather than negative ones")
    func zeroWidth() {
        let layout = DayLayoutEngine.layout(
            items: [item("A", (9, 0), (10, 0))], columnWidth: 0, geometry: dayGeometry)
        #expect(layout.blocks.isEmpty)
    }
}
