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

        for cluster in clusters {
            let sorted = sortForLayout(cluster)
            let packed = packIntoSubColumns(sorted, minimumDuration: geometry.minimumRenderedDuration)

            let inset = Tokens.Spacing.xxs
            let available = columnWidth - 2 * inset
            let unit = available / CGFloat(packed.subColumnCount)
            let slotWidth = unit - Tokens.Size.blockColumnGap

            if slotWidth >= Tokens.Size.dayColumnCascadeThreshold || packed.subColumnCount == 1 {
                result.blocks += columnPackedFrames(
                    sorted, packed: packed, inset: inset, unit: unit, geometry: geometry)
            } else {
                let (blocks, chip) = cascadeFrames(
                    sorted, columnWidth: columnWidth, inset: inset, geometry: geometry)
                result.blocks += blocks
                if let chip { result.overflow.append(chip) }
            }
        }

        return result
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
                zIndex: i,
                isCascaded: false,
                geometry: geometry)
        }
    }

    // MARK: Step 3 — cascade fallback

    /// The indent step, computed per column. At a typical Week column of 114pt
    /// this is 22pt — exactly rail + padding + glyph + 3, i.e. enough to keep a
    /// rail and a glyph visible on a block that is partly covered.
    static func cascadeIndent(columnWidth: CGFloat) -> CGFloat {
        let raw = (columnWidth * Tokens.Size.blockCascadeIndentRatio).rounded()
        return Swift.min(Swift.max(raw, Tokens.Size.blockCascadeIndentMin), Tokens.Size.blockCascadeIndentMax)
    }

    private static func cascadeFrames(
        _ sorted: [LayoutItem],
        columnWidth: CGFloat,
        inset: CGFloat,
        geometry: TimeGeometry
    ) -> ([LaidOutBlock], OverflowChip?) {
        let indent = cascadeIndent(columnWidth: columnWidth)
        let maxSteps = Int(Tokens.Size.blockCascadeMaxSteps)
        let maxVisible = Int(Tokens.Size.blockCascadeMaxVisible)

        let visible = Array(sorted.prefix(maxVisible))
        let hidden = sorted.count - visible.count

        let blocks = visible.indices.map { i -> LaidOutBlock in
            let leading = inset + CGFloat(Swift.min(i, maxSteps)) * indent
            let width = columnWidth - inset - leading
            return makeBlock(
                visible[i],
                x: leading,
                width: width,
                zIndex: i,
                isCascaded: true,
                geometry: geometry)
        }

        guard hidden > 0, let first = blocks.first else { return (blocks, nil) }
        let chip = OverflowChip(
            id: first.id,
            hiddenCount: hidden,
            anchor: CGPoint(x: columnWidth - inset, y: first.frame.minY))
        return (blocks, chip)
    }

    // MARK: Shared frame construction

    private static func makeBlock(
        _ item: LayoutItem,
        x: CGFloat,
        width: CGFloat,
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
            isCascaded: isCascaded)
    }
}
