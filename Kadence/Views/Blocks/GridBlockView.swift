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
    /// Width not covered by the block in front of it. `.infinity` outside a cascade.
    var visibleWidth: CGFloat = .infinity
    /// Squared off when a travel band is attached above (components.md §4).
    var squareTopCorners: Bool = false
    /// Height of a travel-band strip occupying the top of this block's own frame
    /// (components.md §4, short-interval case). The density tier is evaluated
    /// against the remaining height, and content starts below the strip.
    var contentTopInset: CGFloat = 0

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
            visibleWidth: visibleWidth,
            glyphOverride: model.glyphOverride,
            increaseContrast: increaseContrast)
    }

    /// §4 — with a strip inside the top, the tier is decided by what is left.
    private var tier: DensityTier {
        contentTopInset > 0
            ? DensityTier(renderedHeight: renderedHeight - contentTopInset)
            : style.contentTier
    }

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
                    .padding(.top, contentTopInset)
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

                // §6 — the resize handles become visible on hover. Only where a
                // resize is actually possible; a locked or imported block shows
                // none, matching interactions.md §4.
                if model.isMovable {
                    VStack {
                        resizeHandle
                        Spacer(minLength: 0)
                        resizeHandle
                    }
                }
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
        // §11: one accessibility element per block, with a fixed label order.
        //
        // `.accessibilityElement(children: .ignore)` alone is NOT enough on
        // macOS: it collapses the subtree into an element that carries a label
        // but no role or traits, and AppKit vends that as an unlabelled
        // AXUnknown — the label is written and never arrives. A trait is what
        // makes it a real element. Blocks are clickable and selectable, so
        // `.isButton` is both the honest role and the one that gives VoiceOver
        // something to activate. See DEVIATIONS.md A20.
        // §3.4 — hover help is the universal carrier of the source name, and the
        // one path that exists at every tier, in every view, in both geometries.
        .help(model.hoverHelp)
        // §11 — one accessibility element per block.
        //
        // `children: .combine` and the `.isButton` trait are BOTH load-bearing,
        // and were arrived at empirically (DEVIATIONS.md A20):
        //   • `.ignore` alone     → the element is vended as an ignored AXUnknown
        //                           and never appears in the tree at all;
        //   • `.ignore` + trait   → still absent;
        //   • `.combine` + trait  → appears as AXButton. This is the only
        //                           configuration that reaches the tree.
        // Known remaining defect: the explicit `.accessibilityLabel` below does
        // not stick — VoiceOver reads the combined/help text instead of the §11
        // order. Tracked as A20b. Verify with Scripts/check-accessibility.sh.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(presentation.contains(.selected) ? [.isSelected] : [])
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
                // §3.3: "no ellipsis character when the tier is 16–27 — the clip
                // edge reads as truncation and the ellipsis costs 6pt of a very
                // short line". SwiftUI always draws one when it truncates, so the
                // text is laid out at its natural width and clipped instead.
                // §3.3: "no ellipsis character when the tier is 16–27 — the clip
                // edge reads as truncation and the ellipsis costs 6pt of a very
                // short line". SwiftUI always draws one when it truncates, so the
                // text is laid out at its natural width and clipped instead.
                Text(model.title)
                    .typeStyle(.blockTitleCompact)
                    .foregroundStyle(style.label)
                    .fixedSize(horizontal: true, vertical: false)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()
            }

        case .compact:
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Size.blockGlyphGap) {
                glyph(style)
                Text(model.title)
                    .typeStyle(.blockTitleCompact)
                    .foregroundStyle(style.label)
                Spacer(minLength: Tokens.Spacing.xs)
                // §6 — the badge wins the trailing-top corner and the time is
                // dropped. Time is recoverable from hover help and the inspector;
                // a conflict is not recoverable from anywhere else on the grid.
                if style.badge == nil {
                    Text(model.timeRange(formatter: BlockFormatters.time))
                        .typeStyle(.blockMeta)
                        .foregroundStyle(style.meta)
                        .layoutPriority(1)
                }
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
                // §3.4 — the source name is required at this tier. Source wins,
                // location truncates first: location is recoverable from the
                // inspector and the travel band, the source name is not.
                Text(model.metaLine)
                    .typeStyle(.blockMeta)
                    .foregroundStyle(style.meta)
                    .truncationMode(.tail)
                if model.status == .skipped {
                    Text("Re-offered")
                        .typeStyle(.blockMeta)
                        .foregroundStyle(style.meta)
                }
            }
        }
    }

    private var resizeHandle: some View {
        Rectangle()
            .fill(Tokens.Color.Interactive.hoverOverlay)
            .frame(height: Tokens.Size.blockResizeHandleHeight)
    }

    private func glyph(_ style: BlockStyle) -> some View {
        Image(systemName: style.glyph)
            .font(.system(size: Tokens.Size.blockGlyphSize))
            .foregroundStyle(style.glyphColor)
            // Aligned to the first text baseline's cap height, not centred.
            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
    }

    private var accessibilityLabel: String {
        model.accessibilityLabel(presentation: presentation)
    }
}
