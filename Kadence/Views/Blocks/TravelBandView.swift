//
//  TravelBandView.swift
//  Kadence
//
//  Geometry B — not a block. A leading edge attached to the event it belongs to
//  (components.md §4). Slice 2 (§25): fed by the event's `TravelLeg` with a
//  time (`ready` or `estimate`); an estimate is marked by `≈`, a character,
//  never a colour.
//

import SwiftUI

struct TravelBandView: View {
    let band: TravelBand
    let renderedHeight: CGFloat
    var calendar: Calendar = .current

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
        // both. VoiceOver folds this into the parent's label (§29).
        .help(TravelPresentation.bandHelp(band, calendar: calendar))
        .accessibilityHidden(true)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var content: some View {
        let label = TravelPresentation.bandLabel(band, height: renderedHeight, calendar: calendar)
        HStack(spacing: Tokens.Size.blockGlyphGap) {
            Image(systemName: band.mode.glyph)
                .font(.system(size: Tokens.Size.blockGlyphSize - 1))
            if let time = label.time { Text(time) }
            if let minutes = label.minutes { Text(minutes) }
        }
        .typeStyle(.travelLabel)
        .foregroundStyle(Tokens.Color.Text.secondary)
    }
}
