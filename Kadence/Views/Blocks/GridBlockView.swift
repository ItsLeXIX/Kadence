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

    /// §3.5 rule 6 — with a §4 short-case strip inside the top, the block's
    /// content area is its frame MINUS the strip, and the ladder is evaluated
    /// against that area *and the content is drawn into it*. A tier chosen
    /// against remaining height but rendered into full height is the same bug
    /// one level up.
    private var availableHeight: CGFloat { max(0, renderedHeight - contentTopInset) }

    /// §3.3 — the content set. The height ladder decides against the content
    /// area; "visible width overrides the tier" can drop a mostly-covered block
    /// to `.glyphOnly` whatever its height allows. The narrower of the two wins.
    private func metrics(style: BlockStyle) -> BlockContentMetrics {
        let byHeight = BlockContentMetrics.resolve(availableHeight: availableHeight).tier
        return BlockContentMetrics.metrics(
            tier: min(style.contentTier, byHeight),
            availableHeight: availableHeight)
    }

    var body: some View {
        let style = self.style
        let metrics = self.metrics(style: style)
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
                content(style: style, metrics: metrics)
                    // §3.3 — horizontal padding is `size.blockPadding` at every
                    // tier, measured from the rail's trailing edge; vertical
                    // padding is per tier (5 / 5 / 2 / 0).
                    .padding(.horizontal, metrics.horizontalPadding)
                    .padding(.vertical, metrics.verticalPadding)
                    // §3.5 rule 6 — the strip's height comes off the top of the
                    // content area, it is not drawn over the content.
                    .padding(.top, contentTopInset)
                    // §3.5 rule 2 — top-anchored, laid out from the top inset
                    // downward. The single exception is `.glyphOnly`, whose one
                    // 11pt item against an 11pt band can never overflow and is
                    // centred in the frame (§3.3).
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: metrics.tier == .glyphOnly ? .leading : .topLeading)
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
        // §3.5 rules 1–3 — a block paints only inside its own laid-out frame,
        // clipped to the frame's rounded rect, and whatever does not fit is
        // clipped at the BOTTOM edge. Both halves are load-bearing and they are
        // the fix for STATUS.md §1.7 symptom (a) and the Week half of (c):
        //
        //   • the `.frame` is what makes the view's own bounds equal the frame
        //     `DayLayoutEngine` laid out. Without it the view sized itself to
        //     its content, its caller's `.frame(height:)` centred that content
        //     on the real frame, and a block too small for its content spilled
        //     ~5pt above AND below — onto its neighbour. `alignment: .top` is
        //     the rule-2 half: a height-setting modifier that centres its child
        //     by default is specifically wrong here.
        //   • `.clipShape` after it is rule 1. Before the frame existed it
        //     clipped to the content's bounds, which is not a clip at all.
        //
        // Everything drawn after this point is a §3.5 rule-4 exception: the
        // selection ring (outside by design) and the elevation shadow.
        .frame(height: renderedHeight, alignment: .top)
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
    private func content(style: BlockStyle, metrics: BlockContentMetrics) -> some View {
        switch metrics.tier {
        case .glyphOnly:
            glyph(style)

        case .titleOnly:
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Size.blockGlyphGap) {
                glyph(style)
                // §3.3: no ellipsis character at `.titleOnly` — the clip edge
                // reads as truncation and the ellipsis costs 6pt of a very short
                // line. SwiftUI always draws one when it truncates, so the text
                // is laid out at its natural width and clipped instead.
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
                        // §3.3 — the second title line is paid for, not assumed:
                        // `.full` gets two lines only at ≥ 53 + lineHeight(title),
                        // and one line with an ellipsis below that.
                        .lineLimit(metrics.titleLineLimit)
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
