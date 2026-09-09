//
//  GridBlockView.swift
//  Kadence
//
//  Geometry A — the timed block in the hour grid. Covers variants 1–3
//  (components.md §3). One view, driven entirely by `resolveBlockStyle`.
//

import SwiftUI

struct GridBlockView: View {
    let model: GridBlockModel
    let presentation: Presentation
    /// Rendered height in points, which drives the density tier — never duration.
    let renderedHeight: CGFloat
    /// Squared off when a travel band is attached above (components.md §4).
    var squareTopCorners: Bool = false

    @Environment(\.colorSchemeContrast) private var contrast

    private var increaseContrast: Bool { contrast == .increased }

    private var style: BlockStyle {
        resolveBlockStyle(
            kind: model.kind,
            flexibility: model.flexibility,
            status: model.status,
            presentation: presentation,
            source: model.source,
            renderedHeight: renderedHeight,
            glyphOverride: model.glyphOverride,
            increaseContrast: increaseContrast)
    }

    private var tier: DensityTier { DensityTier(renderedHeight: renderedHeight) }

    var body: some View {
        let style = self.style
        let shape = PartialRoundedRectangle(
            topRadius: squareTopCorners ? 0 : style.cornerRadius,
            bottomRadius: style.cornerRadius)

        ZStack(alignment: .topLeading) {
            // Fill. The canvas blend for past/done/skipped is composited here,
            // against the current appearance's canvas (components.md §11).
            shape
                .fill(Tokens.Color.Surface.canvas)
                .opacity(style.fillBlendWithCanvas > 0 ? 1 : 0)
            shape
                .fill(style.fill)
                .opacity(1 - style.fillBlendWithCanvas)

            // Border.
            if let border = style.border {
                shape.strokeBorder(
                    border,
                    style: StrokeStyle(
                        lineWidth: style.borderWidth,
                        dash: style.borderDash ?? []))
            }

            HStack(spacing: 0) {
                if style.railStyle != .none, let rail = style.rail {
                    RailView(style: style.railStyle, color: rail)
                }
                content(style: style)
                    .padding(Tokens.Size.blockPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            .opacity(style.contentOpacity)

            // In-progress marker: trailing edge, leading rail untouched.
            if let bar = style.trailingBar {
                HStack {
                    Spacer(minLength: 0)
                    Rectangle().fill(bar).frame(width: 3)
                }
            }

            if let badge = style.badge {
                Image(systemName: badge.symbol)
                    .font(.system(size: badge.size * 0.85))
                    .foregroundStyle(badge.color)
                    .frame(width: badge.size, height: badge.size)
                    .padding(Tokens.Spacing.xxs)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }

            // Hover: 1pt inset ring, drawn inside the border.
            if presentation.contains(.hovered) {
                shape
                    .inset(by: style.borderWidth)
                    .strokeBorder(Tokens.Color.Interactive.hoverOverlay, lineWidth: 1)
            }
        }
        .clipShape(shape)
        .opacity(presentation.contains(.dragging) ? Tokens.Opacity.blockDragging : 1)
        .elevation(style.elevation)
        // Selection ring is drawn OUTSIDE the bounds with a 1pt gap (§6).
        .overlay {
            if presentation.contains(.selected) {
                RoundedRectangle(cornerRadius: style.cornerRadius + 2, style: .continuous)
                    .strokeBorder(
                        Tokens.Color.Interactive.focusRing,
                        lineWidth: Tokens.Size.borderSelected)
                    .padding(-(Tokens.Size.borderSelected + 1))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    // MARK: Content by density tier (§3.3)

    @ViewBuilder
    private func content(style: BlockStyle) -> some View {
        switch tier {
        case .glyphOnly:
            glyph(style)

        case .titleOnly:
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Size.blockGlyphGap) {
                glyph(style)
                Text(model.title)
                    .typeStyle(.blockTitleCompact)
                    .foregroundStyle(style.label)
                    .truncationMode(.tail)
            }

        case .compact:
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Size.blockGlyphGap) {
                glyph(style)
                Text(model.title)
                    .typeStyle(.blockTitleCompact)
                    .foregroundStyle(style.label)
                Spacer(minLength: Tokens.Spacing.xs)
                Text(model.timeRange(formatter: BlockFormatters.time))
                    .typeStyle(.blockMeta)
                    .foregroundStyle(style.meta)
                    .layoutPriority(1)
            }

        case .full:
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Size.blockGlyphGap) {
                    glyph(style)
                    Text(model.title)
                        .typeStyle(.blockTitle)
                        .foregroundStyle(style.label)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(model.timeRange(formatter: BlockFormatters.time))
                    .typeStyle(.blockMeta)
                    .foregroundStyle(style.meta)
                if let location = model.locationName {
                    Text(location)
                        .typeStyle(.blockMeta)
                        .foregroundStyle(style.meta)
                }
                if model.status == .skipped {
                    Text("Re-offered")
                        .typeStyle(.blockMeta)
                        .foregroundStyle(style.meta)
                }
            }
        }
    }

    private func glyph(_ style: BlockStyle) -> some View {
        Image(systemName: style.glyph)
            .font(.system(size: Tokens.Size.blockGlyphSize))
            .foregroundStyle(style.glyphColor)
            // Aligned to the first text baseline's cap height, not centred.
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
    }

    /// components.md §11 — kind and status are spoken because they are carried
    /// visually by shape, and must not be dropped on the assumption that colour
    /// conveys them.
    private var accessibilityLabel: String {
        var parts = [
            model.title,
            "\(BlockFormatters.time.string(from: model.start)) to \(BlockFormatters.time.string(from: model.end))",
            model.accessibilityKindLabel,
            model.source.displayName,
        ]
        switch model.status {
        case .done: parts.append("done")
        case .skipped: parts.append("skipped, re-offered")
        case .inProgress: parts.append("in progress")
        case .scheduled: break
        }
        if presentation.contains(.conflicted) { parts.append("conflicts with a protected window") }
        return parts.joined(separator: ", ")
    }
}
