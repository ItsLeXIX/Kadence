//
//  CompactRowLayout.swift
//  Kadence
//
//  components.md §3.3, amended 2026-10-05 — "the title beats the time on a
//  shared row". At `.compact` the glyph, the title and the trailing time share
//  one row. When the column is narrow the TIME gives way, never the title:
//
//    1. the title keeps at least `size.blockCascadeMinReadableWidth` (44);
//    2. the time is drawn only if it fits WHOLE in what is left after those
//       44pt and `size.blockGlyphGap` — otherwise it is dropped entirely,
//       never truncated (`07:00-0…` is not a time);
//    3. the title takes all the remaining width and truncates with `…`.
//
//  Pure arithmetic so it can be tested without rendering (task P2-F04).
//

import AppKit
import CoreGraphics

enum CompactRowLayout {

    struct Decision: Equatable, Sendable {
        /// Rule 2: the time is drawn whole or not at all.
        var showsTime: Bool
        /// Rule 3: the width the title is laid out in. It truncates inside it.
        var titleWidth: CGFloat
    }

    /// - Parameters:
    ///   - rowWidth: the content row's width — the block's width minus the
    ///     rail and `size.blockPadding` on both sides (`rowWidth(blockWidth:)`).
    ///   - timeWidth: the time range's natural width in `blockMeta`.
    static func resolve(
        rowWidth: CGFloat,
        timeWidth: CGFloat,
        glyphWidth: CGFloat = Tokens.Size.blockGlyphSize,
        gap: CGFloat = Tokens.Size.blockGlyphGap,
        titleFloor: CGFloat = Tokens.Size.blockCascadeMinReadableWidth
    ) -> Decision {
        // Everything right of the glyph and its gap belongs to title + time.
        let afterGlyph = max(0, rowWidth - glyphWidth - gap)
        let showsTime = timeWidth > 0 && afterGlyph - titleFloor - gap >= timeWidth
        let titleWidth = showsTime ? afterGlyph - gap - timeWidth : afterGlyph
        return Decision(showsTime: showsTime, titleWidth: titleWidth)
    }

    /// The row's width inside a block frame of `blockWidth`: §3.1's rail,
    /// then §3.3's horizontal `size.blockPadding` on both sides.
    static func rowWidth(blockWidth: CGFloat, hasRail: Bool = true) -> CGFloat {
        let rail = hasRail ? Tokens.Size.blockRailWidth : 0
        return max(0, blockWidth - rail - 2 * Tokens.Size.blockPadding)
    }

    /// The natural width of `text` set in `typography.blockMeta` at `size`
    /// (the Dynamic-Type-scaled size the view draws it at). Measured with
    /// AppKit's font, which is the font SwiftUI's `Font.system(size:weight:)
    /// .monospacedDigit()` resolves to on macOS.
    static func metaWidth(_ text: String, size: CGFloat = Tokens.Typography.BlockMeta.size) -> CGFloat {
        let weight = nsWeight(named: Tokens.Typography.BlockMeta.weight)
        let font = Tokens.Typography.BlockMeta.monospacedDigit
            ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
            : NSFont.systemFont(ofSize: size, weight: weight)
        // `ceil` — a fractional width rounded down would let a time that
        // does not quite fit be drawn and clipped by its last pixel.
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
    }

    /// The tokens name weights as strings; AppKit wants `NSFont.Weight`.
    /// Mirrors `TypeStyle.weight(named:)`, which maps to SwiftUI's type.
    static func nsWeight(named name: String) -> NSFont.Weight {
        switch name {
        case "ultraLight": .ultraLight
        case "thin": .thin
        case "light": .light
        case "medium": .medium
        case "semibold": .semibold
        case "bold": .bold
        case "heavy": .heavy
        case "black": .black
        default: .regular
        }
    }
}
