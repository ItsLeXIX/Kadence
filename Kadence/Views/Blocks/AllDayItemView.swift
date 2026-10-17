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
    /// components.md §37.3: a Month chip carries no time.
    var showsMomentTime = true

    @Environment(\.colorSchemeContrast) private var contrast

    private var style: BlockStyle {
        Self.style(for: fixture, presentation: presentation, increaseContrast: contrast == .increased)
    }

    /// The pill's style: §5's variant through the resolver, plus slice 3's
    /// moment rules (§37.1) — a passed moment takes `.past`; an opening and a
    /// notice have no rail.
    static func style(for fixture: AllDayFixture, presentation: Presentation, increaseContrast: Bool = false) -> BlockStyle {
        var presentation = presentation
        if fixture.moment?.isPast == true { presentation.insert(.past) }
        var style = resolveBlockStyle(
            kind: fixture.blockKind,
            flexibility: fixture.kind == .exam ? .fixed : .shiftable,
            status: fixture.status,
            presentation: presentation,
            source: fixture.source,
            renderedHeight: Tokens.Size.allDayRowHeight,
            glyphOverride: fixture.glyph,
            increaseContrast: increaseContrast)
        if let moment = fixture.moment, !moment.hasRail {
            style.railStyle = .none
            style.rail = nil
        }
        return style
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
            if let moment = fixture.moment {
                momentLabel(moment, style: style)
                    .padding(.horizontal, Tokens.Size.blockPadding)
            } else {
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
        .help(fixture.moment?.hoverHelp ?? "\(fixture.title) · \(fixture.sourceName) · \(kindWord)")
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
        // Without a trait this is vended as an unlabelled AXUnknown (A20).
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(presentation.contains(.selected) ? [.isSelected] : [])
    }

    /// components.md §37.1: glyph · `spacing.xs` · time · `spacing.xs` ·
    /// text, one line. The text tail-truncates; the time is never truncated
    /// or split — it is dropped when under 44pt would be left for the text
    /// (`MomentPresentation.layout`), and below the glyph alone, the glyph
    /// alone. Month chips carry no time (§37.3).
    private func momentLabel(_ moment: MomentFixture, style: BlockStyle) -> some View {
        GeometryReader { proxy in
            let glyphWidth = Tokens.Size.blockGlyphSize - 1
            let layout = MomentPresentation.layout(
                available: proxy.size.width, glyph: glyphWidth,
                time: showsMomentTime ? Self.timeWidth(moment.time) : -Tokens.Spacing.xs)
            HStack(spacing: Tokens.Spacing.xs) {
                Image(systemName: style.glyph)
                    .font(.system(size: glyphWidth))
                    .foregroundStyle(style.glyphColor)
                if layout.showsTime && showsMomentTime {
                    Text(moment.time)
                        .typeStyle(.allDayTime)
                        .foregroundStyle(style.meta)
                        .fixedSize()
                }
                if layout.showsText {
                    Text(moment.text)
                        .typeStyle(.allDayLabel)
                        .foregroundStyle(style.label)
                        .truncationMode(.tail)
                }
                Spacer(minLength: 0)
            }
            .frame(height: proxy.size.height)
        }
    }

    /// The time's drawn width in `typography.allDayTime` (monospaced digits).
    static func timeWidth(_ text: String) -> CGFloat {
        let font = NSFont.monospacedDigitSystemFont(ofSize: Tokens.Typography.AllDayTime.size, weight: .regular)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
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

    /// The pill's kind, spoken and in hover help.
    private var kindWord: String {
        switch fixture.kind {
        case .exam: "exam"
        case .deadline: "deadline"
        case .event: fixture.importKind == .exam ? "Exam" : (fixture.importKind == .lecture ? "Lecture" : "event")
        }
    }

    private var accessibilityLabel: String {
        if let moment = fixture.moment { return moment.accessibilityLabel }
        var parts = [fixture.title, kindWord.lowercased(), fixture.sourceName]
        if fixture.status == .cancelled { parts.append("cancelled") }
        if let countdown = fixture.countdownLabel(now: now) {
            parts.append(countdown == "today" ? "today" : countdown.replacingOccurrences(of: "T−", with: "in ").replacingOccurrences(of: "d", with: " days"))
        }
        return parts.joined(separator: ", ")
    }
}
