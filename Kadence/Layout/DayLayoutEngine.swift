//
//  DayLayoutEngine.swift
//  Kadence
//
//  layouts.md §3.3 — deterministic overlap resolution, three steps, run per day
//  column. Pure functions over value types: no SwiftUI, no SwiftData, no clock.
//  This is the piece a silent bug makes you miss a lecture, so it is the piece
//  with the tests.
//

import Foundation
import CoreGraphics

// MARK: - Input and output

struct LayoutItem: Identifiable, Equatable, Sendable {
    var id: UUID
    var start: Date
    var end: Date
    /// Third sort key, so ordering is total and reproducible.
    var title: String

    init(id: UUID, start: Date, end: Date, title: String) {
        self.id = id
        self.start = start
        self.end = end
        self.title = title
    }
}

struct LaidOutBlock: Identifiable, Equatable, Sendable {
    var id: UUID
    var frame: CGRect
    /// Later blocks draw on top; only meaningful in cascade.
    var zIndex: Int
    /// True when the true height was below `size.blockMinRenderedHeight`.
    var isClamped: Bool
    /// Extra hit area, centred on the true frame, for clamped blocks.
    var hitExtension: CGFloat
    /// True when this block came out of step 3 rather than step 2.
    var isCascaded: Bool
    /// The block's own width minus whatever the block in front of it covers.
    /// Equal to `frame.width` outside a cascade. Drives the content tier:
    /// below `size.blockCascadeMinReadableWidth` a block renders glyph only,
    /// because a clipped title reads as damage rather than as occlusion
    /// (components.md §3.3, layouts.md §3.3).
    var visibleWidth: CGFloat
}

/// The `+N` affordance for a cascade that ran past `size.blockCascadeMaxVisible`.
struct OverflowChip: Identifiable, Equatable, Sendable {
    var id: UUID
    var hiddenCount: Int
    /// Top-trailing corner of the cluster.
    var anchor: CGPoint
}

struct DayLayout: Equatable, Sendable {
    var blocks: [LaidOutBlock] = []
    var overflow: [OverflowChip] = []

    func block(for id: UUID) -> LaidOutBlock? { blocks.first { $0.id == id } }
}

// MARK: - The engine

enum DayLayoutEngine {

    /// Lay out one day column.
    ///
    /// - Parameters:
    ///   - items: timed items only. All-day items are excluded from all three
    ///     steps (layouts.md §3.3), and travel bands are laid out with their
    ///     parent, not as items in their own right.
    ///   - columnWidth: the full width available to this day.
    ///   - geometry: supplies the time-to-point mapping and the clamp duration.
    static func layout(
        items: [LayoutItem],
        columnWidth: CGFloat,
        geometry: TimeGeometry
    ) -> DayLayout {
        guard !items.isEmpty, columnWidth > 0 else { return DayLayout() }

        let clusters = cluster(items, minimumDuration: geometry.minimumRenderedDuration)
        var result = DayLayout()
        // z-order is global across the column, not per cluster, so two clusters
        // can never hand out the same index.
        var zBase = 0

        for cluster in clusters {
            let sorted = sortForLayout(cluster)
            let packed = packIntoSubColumns(sorted, minimumDuration: geometry.minimumRenderedDuration)

            let inset = Tokens.Spacing.xxs
            let available = columnWidth - 2 * inset
            let unit = available / CGFloat(packed.subColumnCount)
            let slotWidth = unit - Tokens.Size.blockColumnGap

            if slotWidth >= Tokens.Size.dayColumnCascadeThreshold || packed.subColumnCount == 1 {
                result.blocks += columnPackedFrames(
                    sorted, packed: packed, inset: inset, unit: unit,
                    zBase: zBase, geometry: geometry)
            } else {
                let (blocks, chip) = cascadeFrames(
                    sorted, columnWidth: columnWidth, zBase: zBase, geometry: geometry)
                result.blocks += blocks
                if let chip { result.overflow.append(chip) }
            }
            zBase += sorted.count
        }

        result.blocks = applyVerticalGaps(result.blocks)
        return result
    }

    /// §3.1 — "vertical gap to the next block in the same column".
    ///
    /// A post-pass over the whole column, not something step 2 can do: clusters
    /// are maximal *overlap* groups, so a block and the one starting after it are
    /// by definition in different clusters and never meet during packing.
    ///
    /// Only blocks that actually have something below them are shortened, so an
    /// isolated block still ends exactly on its end time.
    static func applyVerticalGaps(_ blocks: [LaidOutBlock]) -> [LaidOutBlock] {
        let gap = Tokens.Size.blockVerticalGap
        guard gap > 0 else { return blocks }

        return blocks.map { block in
            let hasFollower = blocks.contains { other in
                other.id != block.id
                    && other.frame.minX < block.frame.maxX
                    && block.frame.minX < other.frame.maxX          // shares column space
                    && other.frame.minY >= block.frame.maxY - 0.001 // starts at or below
            }
            guard hasFollower else { return block }

            var shortened = block
            shortened.frame.size.height = Swift.max(
                block.frame.height - gap,
                Tokens.Size.blockMinRenderedHeight)
            return shortened
        }
    }

    // MARK: Step 1 — cluster

    /// Maximal sets connected transitively by overlap, where overlap is tested
    /// after both blocks have been clamped to the minimum rendered height.
    static func cluster(_ items: [LayoutItem], minimumDuration: TimeInterval) -> [[LayoutItem]] {
        let ordered = items.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            return lhs.id.uuidString < rhs.id.uuidString
        }

        var clusters: [[LayoutItem]] = []
        var current: [LayoutItem] = []
        var currentEnd: Date?

        for item in ordered {
            let itemEnd = effectiveEnd(item, minimumDuration: minimumDuration)
            if let end = currentEnd, item.start < end {
                current.append(item)
                currentEnd = Swift.max(end, itemEnd)
            } else {
                if !current.isEmpty { clusters.append(current) }
                current = [item]
                currentEnd = itemEnd
            }
        }
        if !current.isEmpty { clusters.append(current) }
        return clusters
    }

    static func effectiveEnd(_ item: LayoutItem, minimumDuration: TimeInterval) -> Date {
        let natural = item.end
        let clamped = item.start.addingTimeInterval(minimumDuration)
        return Swift.max(natural, clamped)
    }

    // MARK: Step 2 — column packing

    /// Start ascending, then duration descending, then title ascending.
    /// `id` is the final tiebreak so the sort is total even for identical items.
    static func sortForLayout(_ items: [LayoutItem]) -> [LayoutItem] {
        items.sorted { lhs, rhs in
            if lhs.start != rhs.start { return lhs.start < rhs.start }
            let lhsDuration = lhs.end.timeIntervalSince(lhs.start)
            let rhsDuration = rhs.end.timeIntervalSince(rhs.start)
            if lhsDuration != rhsDuration { return lhsDuration > rhsDuration }
            if lhs.title != rhs.title { return lhs.title < rhs.title }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    struct Packing: Equatable, Sendable {
        /// Sub-column index per item, parallel to the sorted input.
        var indices: [Int]
        /// How many adjacent sub-columns each item expands across.
        var spans: [Int]
        var subColumnCount: Int
    }

    /// Place each block in the lowest-index sub-column whose last block ends at
    /// or before this block's start, then expand trailing-ward.
    static func packIntoSubColumns(_ sorted: [LayoutItem], minimumDuration: TimeInterval) -> Packing {
        var columnEnds: [Date] = []
        var indices: [Int] = []

        for item in sorted {
            let itemEnd = effectiveEnd(item, minimumDuration: minimumDuration)
            var placed = false
            for index in columnEnds.indices where columnEnds[index] <= item.start {
                columnEnds[index] = itemEnd
                indices.append(index)
                placed = true
                break
            }
            if !placed {
                indices.append(columnEnds.count)
                columnEnds.append(itemEnd)
            }
        }

        let count = columnEnds.count

        // Expansion: grow trailing-ward until we hit a sub-column occupied by
        // something we overlap.
        var spans = [Int](repeating: 1, count: sorted.count)
        for i in sorted.indices {
            let item = sorted[i]
            let itemEnd = effectiveEnd(item, minimumDuration: minimumDuration)
            var span = 1
            var candidate = indices[i] + 1
            while candidate < count {
                let blocked = sorted.indices.contains { j in
                    guard j != i, indices[j] == candidate else { return false }
                    let otherEnd = effectiveEnd(sorted[j], minimumDuration: minimumDuration)
                    return item.start < otherEnd && sorted[j].start < itemEnd
                }
                if blocked { break }
                span += 1
                candidate += 1
            }
            spans[i] = span
        }

        return Packing(indices: indices, spans: spans, subColumnCount: count)
    }

    private static func columnPackedFrames(
        _ sorted: [LayoutItem],
        packed: Packing,
        inset: CGFloat,
        unit: CGFloat,
        zBase: Int,
        geometry: TimeGeometry
    ) -> [LaidOutBlock] {
        sorted.indices.map { i in
            let item = sorted[i]
            let x = inset + CGFloat(packed.indices[i]) * unit
            let width = CGFloat(packed.spans[i]) * unit - Tokens.Size.blockColumnGap
            return makeBlock(
                item,
                x: x,
                width: width,
                visibleWidth: width,   // packing never covers anything
                zIndex: zBase + i,
                isCascaded: false,
                geometry: geometry)
        }
    }

    // MARK: Step 3 — cascade fallback

    /// The indent step, computed per column: 22pt at any column of 116pt or
    /// wider, 15pt at the 78pt minimum. There is no lower clamp —
    /// `size.dayColumnMin` already guarantees at least 15 (GAPS.md G-006).
    static func cascadeIndent(columnWidth: CGFloat) -> CGFloat {
        let raw = (columnWidth * Tokens.Size.blockCascadeIndentRatio).rounded()
        return Swift.min(raw, Tokens.Size.blockCascadeIndentMax)
    }

    private static func cascadeFrames(
        _ sorted: [LayoutItem],
        columnWidth: CGFloat,
        zBase: Int,
        geometry: TimeGeometry
    ) -> ([LaidOutBlock], OverflowChip?) {
        let indent = cascadeIndent(columnWidth: columnWidth)
        let maxSteps = Tokens.Size.blockCascadeMaxSteps
        let maxVisible = Tokens.Size.blockCascadeMaxVisible

        let visible = Array(sorted.prefix(maxVisible))
        let hidden = sorted.count - visible.count

        func leading(_ i: Int) -> CGFloat {
            CGFloat(Swift.min(i, maxSteps)) * indent
        }

        // No `spacing.xxs` inset here, deliberately. layouts.md §3.3 gives block i
        // a leading inset of exactly `min(i, maxSteps) × indent` and has it span
        // "to the column's trailing edge" — the inset belongs to step 2, where the
        // slot width is derived from `columnWidth − 2 × spacing.xxs`.
        let blocks = visible.indices.map { i -> LaidOutBlock in
            let x = leading(i)
            let width = columnWidth - x
            // Block i is covered by block i+1, so only the strip before the next
            // block's leading edge is actually readable. Blocks past `maxSteps`
            // share a leading edge and therefore cover each other completely.
            let visibleWidth = i + 1 < visible.count ? leading(i + 1) - x : width
            return makeBlock(
                visible[i],
                x: x,
                width: width,
                visibleWidth: visibleWidth,
                zIndex: zBase + i,
                isCascaded: true,
                geometry: geometry)
        }

        guard hidden > 0, let first = blocks.first else { return (blocks, nil) }
        let chip = OverflowChip(
            // The cluster's identity, so an identical layout compares equal.
            id: first.id,
            hiddenCount: hidden,
            // The cluster's top trailing corner.
            anchor: CGPoint(x: columnWidth, y: first.frame.minY))
        return (blocks, chip)
    }

    // MARK: Shared frame construction

    private static func makeBlock(
        _ item: LayoutItem,
        x: CGFloat,
        width: CGFloat,
        visibleWidth: CGFloat,
        zIndex: Int,
        isCascaded: Bool,
        geometry: TimeGeometry
    ) -> LaidOutBlock {
        let y = geometry.y(for: item.start)
        let trueHeight = geometry.height(from: item.start, to: item.end)
        let minimum = Tokens.Size.blockMinRenderedHeight
        let isClamped = trueHeight < minimum
        let height = Swift.max(trueHeight, minimum)

        return LaidOutBlock(
            id: item.id,
            frame: CGRect(x: x, y: y, width: Swift.max(width, 0), height: height),
            zIndex: zIndex,
            isClamped: isClamped,
            hitExtension: isClamped ? Tokens.Size.blockHitExtension : 0,
            isCascaded: isCascaded,
            visibleWidth: Swift.max(visibleWidth, 0))
    }
}
