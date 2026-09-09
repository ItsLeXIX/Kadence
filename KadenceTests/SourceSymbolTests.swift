//
//  SourceSymbolTests.swift
//  KadenceTests
//
//  components.md §10.1. Source symbols and block-kind glyphs are two vocabularies
//  that appear on screen together — most directly in the inspector title row,
//  where the kind glyph and the source swatch sit side by side (layouts.md §6).
//  §10.1 makes "no symbol appears in both tables" a rule for anything added
//  later, which is exactly the kind of rule that rots without a test.
//

import Testing
import Foundation
@testable import Kadence

@Suite("Source symbols")
struct SourceSymbolTests {

    /// Every glyph the block layer can put on screen (§2.1, §3.2, §5, §6).
    private static let kindGlyphs: Set<String> = [
        "building.columns", "calendar", "repeat", "pencil.and.outline",
        "figure.walk", "car.fill", "tram.fill",
        "flag.fill", "graduationcap.fill",
        "checkmark.circle.fill", "arrow.uturn.forward.circle",
        "exclamationmark.triangle.fill",
    ]

    @Test("Every source kind has a symbol")
    func everyKindHasASymbol() {
        for kind in CalendarSourceKind.allCases {
            #expect(!kind.symbol.isEmpty, "\(kind) has no symbol")
        }
    }

    @Test("No source symbol is also a block-kind glyph")
    func vocabulariesAreDisjoint() {
        for kind in CalendarSourceKind.allCases {
            #expect(!Self.kindGlyphs.contains(kind.symbol),
                    "\(kind) uses \(kind.symbol), which is a block-kind glyph — §10.1 forbids it")
        }
    }

    @Test("The symbol table matches §10.1 exactly", arguments: [
        (CalendarSourceKind.universityTimetable, "tablecells.fill"),
        (.coursework, "tray.2.fill"),
        (.exams, "seal.fill"),
        (.mail, "envelope.fill"),
        (.routine, "rectangle.stack.fill"),
        (.manual, "person.fill"),
        (.plannedStudy, "sparkles"),
        (.travel, "map.fill"),
        (.other, "tag.fill"),
        (.unknown, "circle.fill"),
    ])
    func normativeTable(kind: CalendarSourceKind, symbol: String) {
        #expect(kind.symbol == symbol)
    }

    @Test("An unclassified source falls back to a plain disc, not an error glyph")
    func fallback() {
        #expect(CalendarSourceKind.unknown.symbol == "circle.fill")
        #expect(!CalendarSourceKind.unknown.symbol.contains("questionmark"))
    }

    @Test("The symbol is independent of the palette slot")
    func symbolIsNotKeyedToHue() {
        // Two sources may share a symbol; they never share a hue.
        let keys = MockData.sources.map(\.key)
        #expect(Set(keys).count == keys.count, "palette slots must be unique")
        // And the symbol comes from the source's kind, not from its slot.
        for source in MockData.sources {
            #expect(source.symbol == source.kind.symbol)
        }
    }
}
