//
//  AllDayItemView.swift
//  Kadence
//
//  Geometry C — the pinned all-day pill. Variants 5–6 (components.md §5).
//

import SwiftUI

struct AllDayItemView: View {
    let fixture: AllDayFixture
    let presentation: Presentation
    let now: Date
    /// Square the inner corners where a multi-day pill crosses a day divider.
    var squareLeading: Bool = false
    var squareTrailing: Bool = false

    @Environment(\.colorSchemeContrast) private var contrast

    private var style: BlockStyle {
        resolveBlockStyle(
            kind: fixture.blockKind,
            flexibility: fixture.kind == .exam ? .fixed : .shiftable,
            status: fixture.status,
            presentation: presentation,
            source: fixture.source,
            renderedHeight: Tokens.Size.allDayRowHeight,
            increaseContrast: contrast == .increased)
    }

    var body: some View {
        let style = self.style
        let radius = Tokens.Radius.allDayPill
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: squareLeading ? 0 : radius,
            bottomLeadingRadius: squareLeading ? 0 : radius,
            bottomTrailingRadius: squareTrailing ? 0 : radius,
            topTrailingRadius: squareTrailing ? 0 : radius,
            style: .continuous)

        HStack(spacing: 0) {
            if style.railStyle != .none, let rail = style.rail {
                RailView(style: style.railStyle, color: rail)
            }
            HStack(spacing: Tokens.Size.blockGlyphGap) {
                Image(systemName: style.glyph)
                    .font(.system(size: Tokens.Size.blockGlyphSize - 1))
                    .foregroundStyle(style.glyphColor)
                Text(fixture.title)
                    .typeStyle(.blockTitleCompact)
                    .foregroundStyle(style.label)
                    .truncationMode(.tail)
                Spacer(minLength: Tokens.Spacing.xs)
                if let countdown = fixture.countdownLabel(now: now) {
                    countdownChip(countdown)
                }
            }
            .padding(.horizontal, Tokens.Size.blockPadding)
        }
        .frame(height: Tokens.Size.allDayRowHeight)
        .background {
            ZStack {
                shape.fill(Tokens.Color.Surface.canvas)
                    .opacity(style.fillBlendWithCanvas > 0 ? 1 : 0)
                shape.fill(style.fill).opacity(1 - style.fillBlendWithCanvas)
                if let border = style.border {
                    shape.strokeBorder(
                        border,
                        style: StrokeStyle(lineWidth: style.borderWidth, dash: style.borderDash ?? []))
                }
            }
        }
        .clipShape(shape)
        .opacity(style.contentOpacity)
        .overlay {
            if presentation.contains(.selected) {
                RoundedRectangle(cornerRadius: radius + 2, style: .continuous)
                    .strokeBorder(Tokens.Color.Interactive.focusRing, lineWidth: Tokens.Size.borderSelected)
                    .padding(-(Tokens.Size.borderSelected + 1))
            }
        }
        // §3.4 — the pill has no room for the source name, so hover help carries it.
        .help("\(fixture.title) · \(SourceCatalog.name(for: fixture.source)) · \(fixture.kind == .exam ? "exam" : "deadline")")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        // Without a trait this is vended as an unlabelled AXUnknown (A20).
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(presentation.contains(.selected) ? [.isSelected] : [])
    }

    /// Never negative, never red, no overdue state.
    private func countdownChip(_ text: String) -> some View {
        Text(text)
            .typeStyle(.countdownChip)
            .foregroundStyle(Tokens.Color.Text.onSolid)
            .padding(.horizontal, Tokens.Spacing.xs)
            .frame(height: 14)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip, style: .continuous)
                    .fill(Tokens.Color.Text.onSolid.opacity(0.18)))
    }

    private var accessibilityLabel: String {
        var parts = [fixture.title, fixture.kind == .exam ? "exam" : "deadline", fixture.source.displayName]
        if let countdown = fixture.countdownLabel(now: now) {
            parts.append(countdown == "today" ? "today" : countdown.replacingOccurrences(of: "T−", with: "in ").replacingOccurrences(of: "d", with: " days"))
        }
        return parts.joined(separator: ", ")
    }
}
