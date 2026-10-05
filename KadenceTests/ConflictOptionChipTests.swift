//
//  ConflictOptionChipTests.swift
//  KadenceTests
//
//  Task P2-F14 (PHASE2-REVIEW.md §6 item 14; components.md §14.3, amended
//  2026-10-05; G-038 (2)). The `Recommended` chip is line 3, so line 1 has
//  the full row width and no §14.3.4 / §14.6 title is ever truncated.
//

import Testing
import Foundation
import CoreGraphics
import SwiftUI
import AppKit
@testable import Kadence

@Suite("Chip on line 3 (P2-F14)")
@MainActor
struct ConflictOptionChipTests {

    /// Every title §14.3.4 and §14.6 write, verbatim. `nonisolated` because
    /// `@Test(arguments:)` reads it outside the suite's main actor.
    nonisolated static let titles = [
        "Shift Training 75 min later", "Shorten Training to 30 min", "Skip Training today",
        "Shift Errands 30 min later in the routine", "Shift Errands 75 min earlier in the routine",
        "Shorten Errands to 15 min", "Remove Errands from this routine",
    ]

    @Test("At `size.editorInspectorWidth` and the main inspector's minimum, every title fits two lines",
          arguments: titles)
    func titlesFit(_ title: String) {
        for inspector in [Tokens.Size.editorInspectorWidth, Tokens.Size.inspectorWidthMin] {
            let width = ConflictOptionRowView.titleWidth(inspectorWidth: inspector)
            let lines = ConflictOptionRowView.titleLineCount(title, width: width)
            #expect(lines <= Tokens.Typography.ConflictOptionTitle.lineLimit,
                    "\(title) takes \(lines) lines at \(width)pt")
        }
    }

    @Test("Line 1 gets the full row width: 260 − 2 × 16 − 2 × 6 = 216pt in the Routines editor")
    func fullWidth() {
        #expect(ConflictOptionRowView.titleWidth(inspectorWidth: Tokens.Size.editorInspectorWidth) == 216)
    }

    @Test("`Remove Errands from this routine` is one line at full width (it wrapped short beside the chip)")
    func removeOneLine() {
        let width = ConflictOptionRowView.titleWidth(inspectorWidth: Tokens.Size.editorInspectorWidth)
        #expect(ConflictOptionRowView.titleLineCount("Remove Errands from this routine", width: width) == 1)
    }

    /// The chip adds its own line: a recommended row is taller than the same
    /// row without it, and both stay within the 228pt row width.
    @Test("A recommended row is laid out a line taller, at the same width")
    func chipIsOwnLine() {
        func size(_ recommended: Bool) -> CGSize {
            let row = ConflictOptionRowView(
                title: "Shift Errands 30 min later in the routine",
                delta: "12:30 → 13:00 · all 45 min kept · every active day",
                isRecommended: recommended, isSelected: false, action: {})
            return NSHostingView(rootView: row.frame(width: 228)).fittingSize
        }
        let with = size(true), without = size(false)
        #expect(with.width == without.width)
        #expect(with.height > without.height)
    }
}
