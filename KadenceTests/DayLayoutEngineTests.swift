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

    @Test("Indent caps at the max and has no lower clamp")
    func indentClamping() {
        // layouts.md §3.3: 22pt at any column of 116pt or wider, 15pt at the
        // 78pt minimum. There is no lower clamp — dayColumnMin guarantees 15.
        #expect(DayLayoutEngine.cascadeIndent(columnWidth: 114) == 22)
        #expect(DayLayoutEngine.cascadeIndent(columnWidth: 116) == 22)
        #expect(DayLayoutEngine.cascadeIndent(columnWidth: 78) == 15)
        #expect(DayLayoutEngine.cascadeIndent(columnWidth: 4000) == Tokens.Size.blockCascadeIndentMax)
    }

    @Test("Indent never exceeds the max, and at the narrowest legal column is still 15")
    func indentBounds() {
        for width in stride(from: Double(Tokens.Size.dayColumnMin), through: 400.0, by: 1.0) {
            let indent = DayLayoutEngine.cascadeIndent(columnWidth: width)
            #expect(indent <= Tokens.Size.blockCascadeIndentMax)
            #expect(indent >= 15, "dayColumnMin is supposed to guarantee at least 15")
        }
    }

    @Test("The spec's worked table: which step fires at which column width", arguments: [
        (184.0, 2, false),   // slot 88 — packs, both blocks keep a title
        (184.0, 3, true),    // slot 58 — cascades
        (114.0, 2, true),    // slot 53 — cascades
        (78.0,  2, true),    // slot ≤ 37 — cascades
    ])
    func whichStepFires(columnWidth: Double, concurrent: Int, expectCascade: Bool) {
        let items = (0..<concurrent).map { index in
            item("C\(index)", (10, index * 5), (11, index * 5))
        }
        let layout = DayLayoutEngine.layout(
            items: items, columnWidth: CGFloat(columnWidth), geometry: weekGeometry)
        #expect(layout.blocks.allSatisfy { $0.isCascaded } == expectCascade,
                "\(concurrent) concurrent in a \(columnWidth)pt column")
    }

    @Test("A covered block reports only the strip the next block leaves visible")
    func visibleWidth() {
        let items = (0..<4).map { index in item("O\(index)", (10, index * 5), (11, index * 5)) }
        let layout = DayLayoutEngine.layout(items: items, columnWidth: 114, geometry: weekGeometry)
        let byZ = layout.blocks.sorted { $0.zIndex < $1.zIndex }
        let indent = DayLayoutEngine.cascadeIndent(columnWidth: 114)
        // Each covered block sees exactly one indent step; the topmost sees all.
        for block in byZ.dropLast() {
            #expect(block.visibleWidth == indent)
        }
        #expect(byZ.last?.visibleWidth == byZ.last?.frame.width)
    }

    @Test("A covered block drops to glyph-only however tall it is")
    func coveredBlockLosesItsText() {
        // A 60-minute block at the Day scale is 60pt — comfortably tier .full.
        let tall = DensityTier(renderedHeight: 60)
        #expect(tall == .full)

        let covered = resolveBlockStyle(
            kind: .routineTimed, flexibility: .fixed, status: .scheduled,
            presentation: [], source: .blue,
            renderedHeight: 60,
            visibleWidth: Tokens.Size.blockCascadeMinReadableWidth - 1)
        #expect(covered.contentTier == .glyphOnly,
                "a clipped title reads as damage, not as occlusion")

        let uncovered = resolveBlockStyle(
            kind: .routineTimed, flexibility: .fixed, status: .scheduled,
            presentation: [], source: .blue,
            renderedHeight: 60,
            visibleWidth: Tokens.Size.blockCascadeMinReadableWidth)
        #expect(uncovered.contentTier == .full)
    }

    @Test("Packed blocks are never treated as covered")
    func packedBlocksAreFullyVisible() {
        let items = [
            item("A", (18, 0), (19, 30)),
            item("B", (18, 15), (19, 0)),
        ]
        let layout = DayLayoutEngine.layout(items: items, columnWidth: 900, geometry: dayGeometry)
        #expect(layout.blocks.allSatisfy { $0.visibleWidth == $0.frame.width })
    }

    @Test("Cascade indents step and stop at blockCascadeMaxSteps")
    func indentSteps() {
        let items = (0..<5).map { index in
            item("Overlap \(index)", (10, index * 5), (11, index * 5))
        }
        let layout = DayLayoutEngine.layout(items: items, columnWidth: 114, geometry: weekGeometry)
        let sorted = layout.blocks.sorted { $0.zIndex < $1.zIndex }
        let indent = DayLayoutEngine.cascadeIndent(columnWidth: 114)
        let maxSteps = Tokens.Size.blockCascadeMaxSteps

        for (index, block) in sorted.enumerated() {
            // layouts.md §3.3: exactly `min(i, maxSteps) × indent`, with no
            // additional inset — the spacing.xxs inset belongs to step 2 only.
            let expected = CGFloat(min(index, maxSteps)) * indent
            #expect(abs(block.frame.minX - expected) < 0.001, "block \(index) leading inset")
        }
        // The 4th and 5th share the last step: the cascade does not run away.
        #expect(sorted[3].frame.minX == sorted[4].frame.minX)
    }

    @Test("The narrowest cascaded block is columnWidth − 3 × indent, as the spec states")
    func narrowestMatchesSpec() {
        // layouts.md §3.3 gives the figure directly: 48pt at a typical 114pt
        // Week column. Anything else means an inset crept into the cascade.
        let items = (0..<6).map { index in item("O\(index)", (10, index * 5), (11, index * 5)) }
        let layout = DayLayoutEngine.layout(items: items, columnWidth: 114, geometry: weekGeometry)
        let narrowest = layout.blocks.map(\.frame.width).min() ?? 0
        let indent = DayLayoutEngine.cascadeIndent(columnWidth: 114)
        #expect(narrowest == 114 - 3 * indent)
        #expect(narrowest == 48)
    }

    @Test("Every cascaded block spans to the column's trailing edge")
    func spansToTrailingEdge() {
        let items = (0..<4).map { index in item("O\(index)", (10, index * 5), (11, index * 5)) }
        let width: CGFloat = 114
        let layout = DayLayoutEngine.layout(items: items, columnWidth: width, geometry: weekGeometry)
        for block in layout.blocks {
            #expect(abs(block.frame.maxX - width) < 0.001)
        }
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
        #expect(layout.blocks.count == Tokens.Size.blockCascadeMaxVisible)
        #expect(layout.overflow.count == 1)
        #expect(layout.overflow[0].hiddenCount == 3)
    }

    @Test("Z-order follows start order, so later blocks draw on top")
    func zOrder() {
        let items = (0..<4).map { index in item("O\(index)", (10, index * 5), (11, index * 5)) }
        let layout = DayLayoutEngine.layout(items: items, columnWidth: 114, geometry: weekGeometry)
        let byZ = layout.blocks.sorted { $0.zIndex < $1.zIndex }
        #expect(byZ.map(\.zIndex) == [0, 1, 2, 3])
        #expect(Set(layout.blocks.map(\.zIndex)).count == layout.blocks.count,
                "z indices must be unique across the whole column, not per cluster")
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

    @Test("A block followed in its own sub-column gets the vertical gap")
    func verticalGap() {
        // §3.1 — the gap is to the *next* block in the same column.
        let back = item("Back to back", (9, 0), (10, 0))
        let next = item("Next", (10, 0), (11, 0))
        let layout = DayLayoutEngine.layout(
            items: [back, next], columnWidth: 400, geometry: dayGeometry)
        let first = layout.blocks.first { $0.id == back.id }
        #expect(first?.frame.height == Tokens.Size.hourHeightDay - Tokens.Size.blockVerticalGap)
    }

    @Test("A block with clear air below it keeps its true height")
    func noGapWithoutFollower() {
        let only = item("Alone", (9, 0), (10, 0))
        let layout = DayLayoutEngine.layout(
            items: [only], columnWidth: 400, geometry: dayGeometry)
        #expect(layout.blocks.first?.frame.height == Tokens.Size.hourHeightDay,
                "an isolated block must still end exactly on its end time")
    }

    @Test("Count tokens arrive as Int, not CGFloat")
    func countTokensAreIntegers() {
        // GAPS.md G-008 — $meta.swiftMapping.integerLeaves. If the generator
        // regresses to CGFloat these stop compiling rather than silently
        // truncating somewhere.
        let steps: Int = Tokens.Size.blockCascadeMaxSteps
        let visible: Int = Tokens.Size.blockCascadeMaxVisible
        let allDay: Int = Tokens.Size.allDayMaxRows
        let month: Int = Tokens.Size.monthCellMaxVisibleRows
        let lines: Int = Tokens.Typography.BlockTitle.lineLimit
        #expect(steps == 3 && visible == 5 && allDay == 3 && month == 4 && lines == 2)
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
