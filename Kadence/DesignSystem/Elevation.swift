//
//  Elevation.swift
//  Kadence
//
//  elevation.* tokens. At most one shadow per level; level0 draws none.
//

import SwiftUI

enum Elevation: Int, Comparable, Sendable {
    case level0 = 0
    case level1 = 1
    case level2 = 2

    static func < (lhs: Elevation, rhs: Elevation) -> Bool { lhs.rawValue < rhs.rawValue }

    var hasShadow: Bool {
        switch self {
        case .level0: Tokens.Elevation.Level0.hasShadow
        case .level1: Tokens.Elevation.Level1.hasShadow
        case .level2: Tokens.Elevation.Level2.hasShadow
        }
    }

    var color: Color {
        switch self {
        case .level0: Tokens.Elevation.Level0.color
        case .level1: Tokens.Elevation.Level1.color
        case .level2: Tokens.Elevation.Level2.color
        }
    }

    /// SwiftUI's `.shadow(radius:)` is roughly half a CSS-style blur.
    var radius: CGFloat {
        switch self {
        case .level0: Tokens.Elevation.Level0.blur / 2
        case .level1: Tokens.Elevation.Level1.blur / 2
        case .level2: Tokens.Elevation.Level2.blur / 2
        }
    }

    var yOffset: CGFloat {
        switch self {
        case .level0: Tokens.Elevation.Level0.y
        case .level1: Tokens.Elevation.Level1.y
        case .level2: Tokens.Elevation.Level2.y
        }
    }
}

extension View {
    @ViewBuilder
    func elevation(_ level: Elevation) -> some View {
        if level.hasShadow {
            shadow(color: level.color, radius: level.radius, x: 0, y: level.yOffset)
        } else {
            self
        }
    }
}
