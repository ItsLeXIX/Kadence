//
//  DensityTier.swift
//  Kadence
//
//  components.md §3.3. Driven by rendered height in points, never by duration:
//  the same 30-minute event shows more in Day than in Week, which is correct.
//
//  Revised 2026-09-11 (design/GAPS.md G-011 — CLOSED). The bands are now derived
//  from each tier's own content set rather than chosen, and every tier's band
//  bottom is at or above that tier's own minimum. The three boundaries moved
//  16 / 28 / 44 → 18 / 28 / 53.
//

import CoreGraphics

enum DensityTier: Int, Comparable, CaseIterable, Sendable {
    /// rail (full height) + glyph only, no text (11–17pt), and the clamped tier
    /// below it. No vertical padding: at this tier the glyph *is* the block.
    case glyphOnly = 0
    /// glyph + title, 1 line, truncated tail (18–27pt).
    case titleOnly = 1
    /// glyph + compact title + trailing time on one row (28–52pt).
    case compact = 2
    /// glyph + title + time range + meta line, each on its own line (≥53pt).
    case full = 3

    static func < (lhs: DensityTier, rhs: DensityTier) -> Bool { lhs.rawValue < rhs.rawValue }

    /// §3.3's band lookup. This is the *band*, not the final tier: §3.3 asks for
    /// the band containing the available height, then a step down while that
    /// tier's minimum exceeds it. `BlockContentMetrics.resolve` does both.
    init(renderedHeight: CGFloat) {
        switch renderedHeight {
        case ..<18: self = .glyphOnly
        case ..<28: self = .titleOnly
        case ..<53: self = .compact
        default: self = .full
        }
    }

    /// §3.3: `.titleOnly` truncates with no ellipsis character — the clip edge
    /// already reads as truncation, and the ellipsis costs 6pt of a very short
    /// line. `.compact` and `.full` use a standard ellipsis.
    var usesEllipsis: Bool { self >= .compact }

    var showsTitle: Bool { self >= .titleOnly }
    var showsTime: Bool { self >= .compact }
    var showsLocation: Bool { self == .full }

    /// §3.3's per-tier vertical padding table, top and bottom each. Horizontal
    /// padding is `size.blockPadding` at every tier and is not on this ladder.
    var verticalPadding: CGFloat {
        switch self {
        case .glyphOnly: 0
        case .titleOnly: Tokens.Spacing.xxs
        case .compact, .full: Tokens.Size.blockPadding
        }
    }

    /// §11 Dynamic Type: when resolved text no longer fits, drop a tier.
    func droppingOneTier() -> DensityTier {
        DensityTier(rawValue: max(0, rawValue - 1)) ?? .glyphOnly
    }

    /// The height this tier's content set actually needs, from §3.3's
    /// arithmetic. The band bottoms above are at or above these by construction;
    /// under Dynamic Type the minima grow while the bands do not, which is what
    /// makes the step-down in `BlockContentMetrics.resolve` fire (§11).
    func minimumHeight(lineHeights: BlockLineHeights = .standard) -> CGFloat {
        switch self {
        // 5 + 15 + 14 + 14 + 5 = 53
        case .full:
            2 * verticalPadding + lineHeights.title + 2 * lineHeights.meta
        // 5 + 14 + 5 = 24
        case .compact:
            2 * verticalPadding + lineHeights.titleCompact
        // 2 + 14 + 2 = 18
        case .titleOnly:
            2 * verticalPadding + lineHeights.titleCompact
        // 0 + 11 + 0 = 11
        case .glyphOnly:
            2 * verticalPadding + Tokens.Size.blockGlyphSize
        }
    }
}

/// The three line heights §3.3's ladder is derived from.
///
/// §3.3: `lineHeight(style) = ceil(typography.<style>.size × 1.2)`, with no extra
/// line spacing and no gap between rows of the content stack. At the default
/// Dynamic Type size that is `blockTitle` 15, `blockTitleCompact` 14,
/// `blockMeta` 14 — the figures the ladder's minima are quoted from.
struct BlockLineHeights: Equatable, Sendable {
    var title: CGFloat
    var titleCompact: CGFloat
    var meta: CGFloat

    /// §3.3's formula, so the ladder follows a `typography.*` size change rather
    /// than carrying a second copy of these numbers.
    static func lineHeight(forFontSize size: CGFloat) -> CGFloat {
        (size * 1.2).rounded(.up)
    }

    /// Derived from the tokens at the default Dynamic Type size.
    static let standard = BlockLineHeights(
        title: lineHeight(forFontSize: Tokens.Typography.BlockTitle.size),
        titleCompact: lineHeight(forFontSize: Tokens.Typography.BlockTitleCompact.size),
        meta: lineHeight(forFontSize: Tokens.Typography.BlockMeta.size))

    /// The same three line heights at a resolved (scaled) text size — §3.3 asks
    /// the implementation to read the *resolved* font's line height, which is
    /// what keeps the ladder correct under Dynamic Type (§11).
    static func scaled(by factor: CGFloat) -> BlockLineHeights {
        BlockLineHeights(
            title: lineHeight(forFontSize: Tokens.Typography.BlockTitle.size * factor),
            titleCompact: lineHeight(forFontSize: Tokens.Typography.BlockTitleCompact.size * factor),
            meta: lineHeight(forFontSize: Tokens.Typography.BlockMeta.size * factor))
    }
}

/// What a block's content stack is, and how tall it is, inside a given content
/// area — components.md §3.3 (the ladder, tier selection, the paid-for second
/// title line) and §3.5 (confinement).
///
/// Pure over value types: no SwiftUI, no clock, no environment. The view layer
/// reads `tier`, `verticalPadding` and `titleLineLimit` off this and nothing
/// else, so the arithmetic that decides what a block shows is the arithmetic the
/// tests can check.
struct BlockContentMetrics: Equatable, Sendable {
    /// The tier actually rendered, after §3.3's step-down.
    var tier: DensityTier
    /// Top and bottom inset for the content stack (§3.3's padding table).
    var verticalPadding: CGFloat
    /// Leading and trailing inset, measured from the rail's trailing edge (§3.1).
    var horizontalPadding: CGFloat
    /// §3.3: `.full` earns its second title line only at ≥ 53 + lineHeight(title).
    /// "Up to 2 lines" is a permission that must be paid for in real height.
    var titleLineLimit: Int
    /// The height `tier`'s content set needs, second title line included.
    var contentHeight: CGFloat
    /// The content area the stack was resolved against — the block's frame minus
    /// a §4 short-case travel strip, never the full frame (§3.5 rule 6).
    var availableHeight: CGFloat
    /// False only when even `.glyphOnly` does not fit, i.e. an area below
    /// `size.blockMinRenderedHeight`. The view then clips at the bottom edge and
    /// shows less than the tier claims — §3.5 rule 3. It never overflows.
    var fits: Bool { contentHeight <= availableHeight }

    /// §3.3's tier selection: take the tier whose band contains the available
    /// height, then step down while that tier's minimum exceeds it.
    static func resolve(
        availableHeight: CGFloat,
        lineHeights: BlockLineHeights = .standard
    ) -> BlockContentMetrics {
        var tier = DensityTier(renderedHeight: availableHeight)
        while tier > .glyphOnly, tier.minimumHeight(lineHeights: lineHeights) > availableHeight {
            tier = tier.droppingOneTier()
        }
        return metrics(tier: tier, availableHeight: availableHeight, lineHeights: lineHeights)
    }

    /// The same arithmetic for a tier chosen elsewhere — §3.3's "visible width
    /// overrides the tier" drops a mostly-covered block to `.glyphOnly`
    /// whatever its height allows, and that tier still needs its geometry.
    static func metrics(
        tier: DensityTier,
        availableHeight: CGFloat,
        lineHeights: BlockLineHeights = .standard
    ) -> BlockContentMetrics {
        let minimum = tier.minimumHeight(lineHeights: lineHeights)
        let secondTitleLine = tier == .full && availableHeight >= minimum + lineHeights.title
        return BlockContentMetrics(
            tier: tier,
            verticalPadding: tier.verticalPadding,
            horizontalPadding: Tokens.Size.blockPadding,
            titleLineLimit: secondTitleLine ? 2 : 1,
            contentHeight: minimum + (secondTitleLine ? lineHeights.title : 0),
            availableHeight: availableHeight)
    }
}
