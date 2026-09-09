//
//  Shapes.swift
//  Kadence
//
//  Small shapes the block and canvas layers share.
//

import SwiftUI

/// A 45° hatch. Used by the travel band (1pt lines, 5pt pitch) and by
/// low-energy windows (1pt lines, 6pt pitch, tightening to 4pt under
/// Increase Contrast) — components.md §4 and §7.
struct HatchPattern: Shape {
    var pitch: CGFloat
    var lineWidth: CGFloat = 1

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard pitch > 0 else { return path }
        // Sweep far enough that the 45° lines cover the whole rect.
        var x = -rect.height
        while x < rect.width {
            path.move(to: CGPoint(x: rect.minX + x, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + x + rect.height, y: rect.minY))
            x += pitch
        }
        return path.strokedPath(StrokeStyle(lineWidth: lineWidth))
    }
}

/// A rounded rect whose top corners can differ from its bottom corners.
/// The travel band rounds only its top; the event it is attached to squares
/// only its top, so the two read as one object (components.md §4).
struct PartialRoundedRectangle: InsettableShape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat
    /// `InsettableShape` conformance is what makes `.strokeBorder` available —
    /// it strokes *inside* the shape rather than straddling its edge, so a 2pt
    /// border does not bleed 1pt outside the block's frame.
    var insetAmount: CGFloat = 0

    func inset(by amount: CGFloat) -> PartialRoundedRectangle {
        var copy = self
        copy.insetAmount += amount
        return copy
    }

    func path(in rect: CGRect) -> Path {
        let rect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        guard rect.width > 0, rect.height > 0 else { return Path() }
        let top = min(topRadius, min(rect.width, rect.height) / 2)
        let bottom = min(bottomRadius, min(rect.width, rect.height) / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.addArc(
            center: CGPoint(x: rect.maxX - top, y: rect.minY + top),
            radius: top, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.addArc(
            center: CGPoint(x: rect.maxX - bottom, y: rect.maxY - bottom),
            radius: bottom, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        path.addArc(
            center: CGPoint(x: rect.minX + bottom, y: rect.maxY - bottom),
            radius: bottom, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + top))
        path.addArc(
            center: CGPoint(x: rect.minX + top, y: rect.minY + top),
            radius: top, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// The leading flexibility rail (components.md §2.3).
struct RailView: View {
    var style: RailStyle
    var color: Color

    var body: some View {
        switch style {
        case .none:
            EmptyView()
        case .solid:
            Rectangle()
                .fill(color)
                .frame(width: Tokens.Size.blockRailWidth)
        case .inset:
            // Reads as "can slide": inset from both ends, rounded caps.
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(color)
                .frame(width: Tokens.Size.blockRailWidth)
                .padding(.vertical, Tokens.Spacing.xs)
        case .dotted:
            // Reads as "can be dropped": 2 on, 2 off, square caps.
            Rectangle()
                .fill(color)
                .frame(width: Tokens.Size.blockRailWidth)
                .mask(
                    VStack(spacing: 2) {
                        ForEach(0..<200, id: \.self) { _ in
                            Rectangle().frame(height: 2)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .clipped()
                )
        }
    }
}
