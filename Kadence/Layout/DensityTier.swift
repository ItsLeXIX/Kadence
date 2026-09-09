//
//  DensityTier.swift
//  Kadence
//
//  components.md §3.3. Driven by rendered height in points, never by duration:
//  the same 30-minute event shows more in Day than in Week, which is correct.
//

import CoreGraphics

enum DensityTier: Int, Comparable, CaseIterable, Sendable {
    /// rail + glyph only, no text (11–15pt), and the clamped tier below it.
    case glyphOnly = 0
    /// glyph + title, 1 line, truncated tail (16–27pt).
    case titleOnly = 1
    /// glyph + compact title + trailing time on one row (28–43pt).
    case compact = 2
    /// glyph + title (2 lines) + time range + location, each on its own line (≥44pt).
    case full = 3

    static func < (lhs: DensityTier, rhs: DensityTier) -> Bool { lhs.rawValue < rhs.rawValue }

    init(renderedHeight: CGFloat) {
        switch renderedHeight {
        case ..<16: self = .glyphOnly
        case ..<28: self = .titleOnly
        case ..<44: self = .compact
        default: self = .full
        }
    }

    /// §3.3: tiers 16–27 truncate with no ellipsis character — the clip edge
    /// already reads as truncation, and the ellipsis costs 6pt of a very short
    /// line. Tiers ≥ 28 use a standard ellipsis.
    var usesEllipsis: Bool { self >= .compact }

    var showsTitle: Bool { self >= .titleOnly }
    var showsTime: Bool { self >= .compact }
    var showsLocation: Bool { self == .full }

    /// §11 Dynamic Type: when resolved text no longer fits, drop a tier.
    func droppingOneTier() -> DensityTier {
        DensityTier(rawValue: max(0, rawValue - 1)) ?? .glyphOnly
    }
}
