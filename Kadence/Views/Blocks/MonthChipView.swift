//
//  MonthChipView.swift
//  Kadence
//
//  components.md §9 — the same signal system at the 16–27 density tier,
//  compressed to `size.monthCellRowHeight`. The fill-weight ladder is what
//  makes Month readable at a glance, so it is not simplified away.
//

import SwiftUI

struct MonthChipView: View {
    let model: GridBlockModel
    let presentation: Presentation

    @Environment(\.colorSchemeContrast) private var contrast

    private var style: BlockStyle {
        resolveBlockStyle(
            kind: model.kind,
            flexibility: model.flexibility,
            status: model.status,
            presentation: presentation,
            source: model.source,
            renderedHeight: Tokens.Size.monthCellRowHeight,
            glyphOverride: model.glyphOverride,
            increaseContrast: contrast == .increased)
    }

    var body: some View {
        let style = self.style
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.blockCompact, style: .continuous)

        HStack(spacing: 0) {
            if style.railStyle != .none, let rail = style.rail {
                RailView(style: style.railStyle, color: rail)
            }
            HStack(spacing: 3) {
                Image(systemName: style.glyph)
                    .font(.system(size: 9))
                    .foregroundStyle(style.glyphColor)
                Text(model.title)
                    .typeStyle(.blockTitleCompact)
                    .foregroundStyle(style.label)
                    .truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 3)
        }
        .frame(height: Tokens.Size.monthCellRowHeight)
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
        // §3.4 — month chips never carry the source name; hover help does.
        .help(model.hoverHelp)
        // §11 applies here too: one element, same label order.
        .accessibilityElement(children: .combine)
        .accessibilityLabel(model.accessibilityLabel(presentation: presentation))
        .accessibilityAddTraits(.isButton)
        .overlay {
            if presentation.contains(.selected) {
                RoundedRectangle(cornerRadius: Tokens.Radius.blockCompact + 2, style: .continuous)
                    .strokeBorder(Tokens.Color.Interactive.focusRing, lineWidth: Tokens.Size.borderSelected)
                    .padding(-2)
            }
        }
    }
}
