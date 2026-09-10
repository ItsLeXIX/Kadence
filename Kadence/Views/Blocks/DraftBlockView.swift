//
//  DraftBlockView.swift
//  Kadence
//
//  interactions.md §3 — "a new event appears immediately as a block in
//  `.fixedTimed` / `.manual` style with an inline `TextField` in place of its
//  title, using `blockTitle`. `↩` commits; `⎋` cancels and removes the block
//  entirely."
//
//  It renders through the same `resolveBlockStyle` as every other block, so a
//  draft looks exactly like the manual event it is about to become — that is the
//  point of showing it at all.
//

import SwiftUI

struct DraftBlockView: View {
    @Binding var draft: EventDraft
    let renderedHeight: CGFloat
    /// Called with the committed draft. The caller decides whether it persists.
    let onCommit: () -> Void
    let onDiscard: () -> Void

    @FocusState private var isFieldFocused: Bool
    @Environment(\.colorSchemeContrast) private var contrast

    private var style: BlockStyle {
        resolveBlockStyle(
            kind: .fixedTimed,
            flexibility: .fixed,
            status: .scheduled,
            presentation: [.selected],
            source: .graphite,
            renderedHeight: renderedHeight,
            glyphOverride: "calendar",
            increaseContrast: contrast == .increased)
    }

    var body: some View {
        let style = self.style
        let shape = PartialRoundedRectangle(
            topRadius: style.cornerRadius,
            bottomRadius: style.cornerRadius)

        ZStack(alignment: .topLeading) {
            shape.fill(style.fill)

            HStack(alignment: .firstTextBaseline, spacing: Tokens.Size.blockGlyphGap) {
                Image(systemName: style.glyph)
                    .font(.system(size: Tokens.Size.blockGlyphSize))
                    .foregroundStyle(style.glyphColor)

                TextField("New event", text: $draft.title)
                    .textFieldStyle(.plain)
                    .typeStyle(.blockTitle)
                    .foregroundStyle(style.label)
                    .focused($isFieldFocused)
                    .onSubmit(onCommit)
                    // ⎋ cancels and removes the block entirely.
                    .onExitCommand(perform: onDiscard)
            }
            .padding(Tokens.Size.blockPadding)
        }
        .clipShape(shape)
        .elevation(.level1)
        .overlay {
            RoundedRectangle(cornerRadius: style.cornerRadius + 2, style: .continuous)
                .strokeBorder(
                    Tokens.Color.Interactive.focusRing,
                    lineWidth: Tokens.Size.borderSelected)
                .padding(-(Tokens.Size.borderSelected + 1))
        }
        .onAppear { isFieldFocused = true }
        .onChange(of: isFieldFocused) { _, focused in
            // Losing focus abandons the draft. Nothing was persisted, so there is
            // nothing to clean up — see STATUS.md for the trade-off here.
            if !focused { onDiscard() }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("New event, \(BlockFormatters.time.string(from: draft.start)) to \(BlockFormatters.time.string(from: draft.end))")
    }
}
