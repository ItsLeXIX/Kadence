//
//  ConflictOptionRowStyleTests.swift
//  KadenceTests
//
//  Task P2-F13 (PHASE2-REVIEW.md §6 item 13; components.md §14.3, amended
//  2026-10-05; G-038 (1); tokens.json 1.2.0). A focused option row is a
//  tinted card with a focus-ring border; text colours never change; solid
//  `selectedRowFill` is never used under conflict-panel text.
//

import Testing
import CoreGraphics
@testable import Kadence

@Suite("Selected option row (P2-F13)")
struct ConflictOptionRowStyleTests {

    @Test("Focused: `selectedCardFill` + a `size.borderSelected` focus-ring border")
    func focused() {
        let style = ConflictOptionRowStyle.resolve(isFocused: true)
        #expect(style.fill == .selectedCardFill)
        #expect(style.borderWidth == Tokens.Size.borderSelected)
        #expect(Tokens.Size.borderSelected == 2)
    }

    @Test("Unfocused: `canvasSunken`, no border")
    func unfocused() {
        let style = ConflictOptionRowStyle.resolve(isFocused: false)
        #expect(style.fill == .canvasSunken)
        #expect(style.borderWidth == nil)
    }

    @Test("Text colours are the same whether or not the row is focused")
    func textUnchanged() {
        for focused in [false, true] {
            let style = ConflictOptionRowStyle.resolve(isFocused: focused)
            #expect(style.titleColor == .primary)
            #expect(style.deltaColor == .secondary)
        }
    }

    @Test("The row's fill vocabulary has no `selectedRowFill` (barred under multi-line text)")
    func noSelectedRowFill() {
        // `Fill` is the only way a row picks its ground; it has exactly two
        // cases, so `selectedRowFill` can't be reached from a conflict panel.
        let fills = [false, true].map { ConflictOptionRowStyle.resolve(isFocused: $0).fill }
        #expect(Set(fills.map { "\($0)" }) == ["canvasSunken", "selectedCardFill"])
    }
}
