//
//  BlockStyleResolver.swift
//  Kadence
//
//  One pure function, consumed by every block view (components.md §2).
//  No view dependencies, no environment access, no side effects — so it is
//  unit-testable on its own, which is the point.
//

import SwiftUI

/// Resolve the complete visual description of a block.
///
/// - Parameters:
///   - kind: the visual class, not the data origin (components.md §2.1).
///   - flexibility: modulates the rail only, never the fill (§2.3).
///   - status: `.inProgress` is derived from the clock by the caller.
///   - presentation: transient states, composed in the order of §6.
///   - source: the palette slot; hue means source and nothing else (§1).
///   - renderedHeight: points on screen, which drives the density tier (§3.3).
///   - visibleWidth: the block's width minus whatever covers it in a cascade.
///     Below `size.blockCascadeMinReadableWidth` the content set drops to
///     glyph-only, because a clipped title reads as damage, not as occlusion
///     (§3.3). Defaults to `.infinity`, i.e. "nothing is covering this".
///   - glyphOverride: `.fixedTimed` covers both lectures and manual events,
///     which differ only by symbol; the call site supplies it (§2.1).
///   - increaseContrast: see GAPS.md G-003 — §11's contrast rules change border
///     *widths* and *dash patterns*, which no colour token can express, so the
///     resolver has to know. Defaults to `false`, leaving §2's documented
///     signature callable unchanged.
func resolveBlockStyle(
    kind: BlockKind,
    flexibility: Flexibility,
    status: BlockStatus,
    presentation: Presentation,
    source: SourceKey,
    renderedHeight: CGFloat,
    visibleWidth: CGFloat = .infinity,
    glyphOverride: String? = nil,
    increaseContrast: Bool = false
) -> BlockStyle {

    // MARK: Base — §3.2 for timed, §5 for all-day, §4 for travel.

    let regularBorder = increaseContrast ? Tokens.Size.borderEmphasis : Tokens.Size.borderRegular
    var style: BlockStyle

    switch kind {
    case .fixedTimed:
        // The whole block is the source colour, so a rail would be invisible in
        // the same hue and a lie in another. Absence of a rail IS the signal.
        style = BlockStyle(
            fill: source.solid,
            border: nil,
            borderWidth: 0,
            borderDash: nil,
            rail: nil,
            railStyle: .none,
            label: Tokens.Color.Text.onSolid,
            meta: Tokens.Color.Text.onSolid.opacity(0.8),
            glyph: glyphOverride ?? "calendar",
            glyphColor: Tokens.Color.Text.onSolid,
            cornerRadius: Tokens.Radius.block)

    case .routineTimed:
        style = BlockStyle(
            fill: source.tint,
            // §11: under Increase Contrast the routine border drops its opacity
            // and draws at full strength. Applying `.opacity(1)` would still wrap
            // the colour in a modifier, which is not the same value as the bare
            // token — so branch instead of always calling `.opacity`.
            border: increaseContrast ? source.rail : source.rail.opacity(Tokens.Opacity.routineBorder),
            borderWidth: regularBorder,
            borderDash: nil,
            rail: source.rail,
            railStyle: railStyle(for: flexibility),
            label: Tokens.Color.Text.primary,
            meta: Tokens.Color.Text.secondary,
            glyph: glyphOverride ?? "repeat",
            glyphColor: source.text,
            cornerRadius: Tokens.Radius.block)

    case .plannedTimed:
        style = BlockStyle(
            fill: .clear,
            border: source.rail,
            borderWidth: Tokens.Size.borderEmphasis,
            // §11: the dash tightens under Increase Contrast so the outline
            // reads as continuous.
            borderDash: increaseContrast ? [3, 2] : [4, 3],
            rail: source.rail,
            railStyle: railStyle(for: flexibility),
            label: Tokens.Color.Text.primary,
            meta: Tokens.Color.Text.secondary,
            glyph: glyphOverride ?? "pencil.and.outline",
            glyphColor: source.text,
            cornerRadius: Tokens.Radius.block)

    case .travelBand:
        style = BlockStyle(
            fill: Tokens.Color.Surface.travelBand,
            border: nil,
            borderWidth: 0,
            borderDash: nil,
            rail: nil,
            railStyle: .none,
            label: Tokens.Color.Text.secondary,
            meta: Tokens.Color.Text.secondary,
            glyph: glyphOverride ?? "figure.walk",
            glyphColor: Tokens.Color.Text.secondary,
            cornerRadius: Tokens.Radius.travelBand)

    case .deadlineAllDay:
        style = BlockStyle(
            fill: source.tint,
            border: source.rail,
            borderWidth: regularBorder,
            borderDash: nil,
            rail: source.rail,
            railStyle: .solid,
            label: Tokens.Color.Text.primary,
            meta: Tokens.Color.Text.secondary,
            glyph: glyphOverride ?? "flag.fill",
            glyphColor: source.text,
            cornerRadius: Tokens.Radius.allDayPill)

    case .examAllDay:
        style = BlockStyle(
            fill: source.solid,
            border: nil,
            borderWidth: 0,
            borderDash: nil,
            rail: nil,
            railStyle: .none,
            label: Tokens.Color.Text.onSolid,
            meta: Tokens.Color.Text.onSolid.opacity(0.8),
            glyph: glyphOverride ?? "graduationcap.fill",
            glyphColor: Tokens.Color.Text.onSolid,
            cornerRadius: Tokens.Radius.allDayPill)
    }

    // §3.3 — the content set: height ladder, overridden by visible width.
    style.contentTier = visibleWidth < Tokens.Size.blockCascadeMinReadableWidth
        ? .glyphOnly
        : DensityTier(renderedHeight: renderedHeight)

    // §3.1 — compact radius for very short blocks.
    if renderedHeight < 16 && kind != .deadlineAllDay && kind != .examAllDay {
        style.cornerRadius = Tokens.Radius.blockCompact
    }

    // MARK: States — §6, applied in table order.

    if presentation.contains(.selected) {
        // The focus ring itself is drawn outside the bounds by the view;
        // the resolver only owns the lift.
        style.elevation = max(style.elevation, .level1)
    }

    if presentation.contains(.dragging) {
        style.elevation = .level2
    }

    if presentation.contains(.conflicted) {
        // Fill is never changed — it still has to carry source and movability.
        style.border = Tokens.Color.Semantic.alert
        style.borderWidth = Tokens.Size.borderEmphasis
        style.badge = BadgeSpec(
            symbol: "exclamationmark.triangle.fill",
            color: Tokens.Color.Semantic.alert,
            size: Tokens.Size.conflictBadgeSize)
    }

    if presentation.contains(.past) {
        style.contentOpacity = Tokens.Opacity.blockPastContent
        style.fillBlendWithCanvas = Tokens.Opacity.blockPastFillBlend
        style.border = style.border?.opacity(1 - Tokens.Opacity.blockPastFillBlend)
        style.rail = style.rail?.opacity(1 - Tokens.Opacity.blockPastFillBlend)
    }

    switch status {
    case .scheduled:
        break

    case .inProgress:
        // Leading rail and glyph are untouched: type must stay readable while
        // an item is running.
        style.trailingBar = Tokens.Color.Semantic.now
        style.elevation = max(style.elevation, .level1)

    case .done:
        style.fillBlendWithCanvas = Tokens.Opacity.blockDoneFillBlend
        style.glyph = "checkmark.circle.fill"
        style.glyphColor = Tokens.Color.Text.secondary
        style.label = Tokens.Color.Text.secondary

    case .skipped:
        // A skipped item must never look worse than a done one.
        style.fillBlendWithCanvas = Tokens.Opacity.blockSkippedFillBlend
        style.border = Tokens.Color.Separator.strong
        style.borderWidth = Tokens.Size.borderRegular
        style.borderDash = [3, 3]
        style.glyph = "arrow.uturn.forward.circle"
        style.glyphColor = Tokens.Color.Text.secondary
    }

    // §6 conflicted: below 16pt the badge replaces the type glyph.
    if presentation.contains(.conflicted), renderedHeight < 16 {
        style.glyph = "exclamationmark.triangle.fill"
        style.glyphColor = Tokens.Color.Semantic.alert
        style.badge = nil
    }

    return style
}

private func railStyle(for flexibility: Flexibility) -> RailStyle {
    switch flexibility {
    case .fixed: .solid
    case .shiftable: .inset
    case .droppable: .dotted
    }
}
