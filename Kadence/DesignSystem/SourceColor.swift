//
//  SourceColor.swift
//  Kadence
//
//  Hue means "which source" and nothing else (components.md §1).
//  Red is absent on purpose: it is reserved for `now` and `alert`.
//

import SwiftUI

/// One slot in the source palette. The case order is
/// `tokens.json → color.sourcePalette.order`, which is also the order sources
/// are assigned as they are added.
enum SourceKey: String, CaseIterable, Codable, Sendable, Identifiable {
    case blue, teal, green, amber, orange, pink, purple, graphite

    var id: String { rawValue }

    /// Assign palette slots in order as sources are added; `graphite` is the
    /// fallback for anything unassigned, which is why manual events default to it.
    static func slot(_ index: Int) -> SourceKey {
        let assignable = allCases.filter { $0 != .graphite }
        guard index >= 0, index < assignable.count else { return .graphite }
        return assignable[index]
    }

    var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    /// The sidebar swatch symbol. components.md §10.1: the symbol is what makes
    /// the legend work without colour, so every slot needs a distinct one.
    var swatchSymbol: String {
        switch self {
        case .blue: "building.columns"
        case .teal: "graduationcap"
        case .green: "repeat"
        case .amber: "envelope"
        case .orange: "flag"
        case .pink: "person.2"
        case .purple: "pencil.and.outline"
        case .graphite: "calendar"
        }
    }

    var solid: Color {
        switch self {
        case .blue: Tokens.Color.Source.Blue.solid
        case .teal: Tokens.Color.Source.Teal.solid
        case .green: Tokens.Color.Source.Green.solid
        case .amber: Tokens.Color.Source.Amber.solid
        case .orange: Tokens.Color.Source.Orange.solid
        case .pink: Tokens.Color.Source.Pink.solid
        case .purple: Tokens.Color.Source.Purple.solid
        case .graphite: Tokens.Color.Source.Graphite.solid
        }
    }

    var rail: Color {
        switch self {
        case .blue: Tokens.Color.Source.Blue.rail
        case .teal: Tokens.Color.Source.Teal.rail
        case .green: Tokens.Color.Source.Green.rail
        case .amber: Tokens.Color.Source.Amber.rail
        case .orange: Tokens.Color.Source.Orange.rail
        case .pink: Tokens.Color.Source.Pink.rail
        case .purple: Tokens.Color.Source.Purple.rail
        case .graphite: Tokens.Color.Source.Graphite.rail
        }
    }

    var tint: Color {
        switch self {
        case .blue: Tokens.Color.Source.Blue.tint
        case .teal: Tokens.Color.Source.Teal.tint
        case .green: Tokens.Color.Source.Green.tint
        case .amber: Tokens.Color.Source.Amber.tint
        case .orange: Tokens.Color.Source.Orange.tint
        case .pink: Tokens.Color.Source.Pink.tint
        case .purple: Tokens.Color.Source.Purple.tint
        case .graphite: Tokens.Color.Source.Graphite.tint
        }
    }

    var text: Color {
        switch self {
        case .blue: Tokens.Color.Source.Blue.text
        case .teal: Tokens.Color.Source.Teal.text
        case .green: Tokens.Color.Source.Green.text
        case .amber: Tokens.Color.Source.Amber.text
        case .orange: Tokens.Color.Source.Orange.text
        case .pink: Tokens.Color.Source.Pink.text
        case .purple: Tokens.Color.Source.Purple.text
        case .graphite: Tokens.Color.Source.Graphite.text
        }
    }
}
