//
//  TravelBandView.swift
//  Kadence
//
//  Geometry B — not a block. A leading edge attached to the event it belongs to
//  (components.md §4).
//

import SwiftUI

struct TravelBandView: View {
    let fixture: TravelFixture
    let renderedHeight: CGFloat

    var body: some View {
        let shape = PartialRoundedRectangle(
            topRadius: Tokens.Radius.travelBand,
            bottomRadius: 0)

        ZStack(alignment: .leading) {
            shape.fill(Tokens.Color.Surface.travelBand)
            HatchPattern(pitch: 5, lineWidth: 1)
                .foregroundStyle(Tokens.Color.Window.lowEnergyHatch)
            content
                .padding(.horizontal, Tokens.Size.blockPadding)
        }
        .clipShape(shape)
        .frame(height: renderedHeight)
        // Not focusable and not independently selectable: the parent event owns
        // both. VoiceOver folds this into the parent's label.
        .help("Leave \(BlockFormatters.time.string(from: fixture.departAt)) · \(Int(fixture.duration / 60)) min \(fixture.mode.label)")
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var content: some View {
        let minutes = Int((fixture.duration / 60).rounded())
        HStack(spacing: Tokens.Size.blockGlyphGap) {
            Image(systemName: fixture.mode.glyph)
                .font(.system(size: Tokens.Size.blockGlyphSize - 1))
            if renderedHeight >= 14 {
                Text("Leave \(BlockFormatters.time.string(from: fixture.departAt))")
            }
            if renderedHeight >= 18 {
                Text("· \(minutes)min")
            }
        }
        .typeStyle(.travelLabel)
        .foregroundStyle(Tokens.Color.Text.secondary)
    }
}
