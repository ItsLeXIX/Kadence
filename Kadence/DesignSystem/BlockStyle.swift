//
//  BlockStyle.swift
//  Kadence
//
//  The output of `resolveBlockStyle`. components.md §2.2.
//

import SwiftUI

/// How the leading rail is drawn. Flexibility rides here and nowhere else
/// (components.md §2.3) — fill weight is already spoken for by kind.
enum RailStyle: Sendable, Equatable {
    case none
    case solid
    case inset
    case dotted
}

struct BadgeSpec: Sendable, Equatable {
    var symbol: String
    var color: Color
    var size: CGFloat
}

struct BlockStyle: Sendable, Equatable {
    var fill: Color
    /// Fraction of `surface.canvas` composited OVER the fill. 0 = untouched.
    var fillBlendWithCanvas: CGFloat = 0
    var border: Color?
    var borderWidth: CGFloat = 0
    /// nil = solid.
    var borderDash: [CGFloat]?
    var rail: Color?
    var railStyle: RailStyle = .none
    var label: Color
    var meta: Color
    var glyph: String
    var glyphColor: Color
    var cornerRadius: CGFloat
    var elevation: Elevation = .level0
    /// In-progress marker only, trailing edge.
    var trailingBar: Color?
    var badge: BadgeSpec?
    var contentOpacity: CGFloat = 1

    /// The fill actually painted, with the canvas blend already applied.
    ///
    /// The blend is composited against `surface.canvas` for the *current*
    /// appearance (components.md §11), which is why it is done here at render
    /// time rather than baked into a token.
    var resolvedFill: some ShapeStyle {
        fill.opacity(1 - fillBlendWithCanvas)
    }
}
