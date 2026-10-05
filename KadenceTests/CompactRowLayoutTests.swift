//
//  CompactRowLayoutTests.swift
//  KadenceTests
//
//  Task P2-F04 (PHASE2-REVIEW.md §6 item 4; components.md §3.3 amended
//  2026-10-05, §3.5 rule 1). On a `.compact` row the title beats the time:
//  the time is drawn whole or not at all, and the title keeps ≥ 44pt.
//

import Testing
import Foundation
import CoreGraphics
import AppKit
import SwiftUI
@testable import Kadence

@Suite("Compact row — the title beats the time (P2-F04)")
struct CompactRowLayoutTests {

    /// A lone block's frame is its column minus `spacing.xxs` on each side
    /// (`DayLayoutEngine.layout`); the row is that minus rail and padding.
    private func rowWidth(column: CGFloat) -> CGFloat {
        CompactRowLayout.rowWidth(blockWidth: column - 2 * Tokens.Spacing.xxs)
    }

    private let gymTime = CompactRowLayout.metaWidth("07:00-08:00")

    private func titleWidth(_ title: String) -> CGFloat {
        let font = NSFont.systemFont(
            ofSize: Tokens.Typography.BlockTitleCompact.size,
            weight: CompactRowLayout.nsWeight(named: Tokens.Typography.BlockTitleCompact.weight))
        return ceil((title as NSString).size(withAttributes: [.font: font]).width)
    }

    @Test("`Gym` at 126pt (main Week, 1500pt window) and 104pt (Routines, 780pt) keeps the title whole and drops the time",
          arguments: [126.0, 104.0])
    func narrowDropsTime(column: Double) {
        let decision = CompactRowLayout.resolve(rowWidth: rowWidth(column: column), timeWidth: gymTime)
        #expect(!decision.showsTime)
        #expect(decision.titleWidth >= titleWidth("Gym"))
        #expect(decision.titleWidth >= Tokens.Size.blockCascadeMinReadableWidth)
    }

    @Test("Where the time fits beside ≥ 44pt of title, both show")
    func wideShowsBoth() {
        let decision = CompactRowLayout.resolve(rowWidth: rowWidth(column: 200), timeWidth: gymTime)
        #expect(decision.showsTime)
        #expect(decision.titleWidth >= Tokens.Size.blockCascadeMinReadableWidth)
    }

    @Test("The time is never partially drawn: at every width it is whole or absent, and title + time fit the row")
    func neverPartial() {
        for width in stride(from: 0.0, through: 260.0, by: 1.0) {
            let row = CGFloat(width)
            let d = CompactRowLayout.resolve(rowWidth: row, timeWidth: gymTime)
            let used = Tokens.Size.blockGlyphSize + Tokens.Size.blockGlyphGap + d.titleWidth
                + (d.showsTime ? Tokens.Size.blockGlyphGap + gymTime : 0)
            #expect(used <= max(row, Tokens.Size.blockGlyphSize + Tokens.Size.blockGlyphGap) + 0.001,
                    "row \(width): content \(used) overflows")
            if d.showsTime {
                #expect(d.titleWidth >= Tokens.Size.blockCascadeMinReadableWidth, "row \(width)")
            }
        }
    }

    @Test("The boundary is exactly glyph + gap + 44 + gap + time")
    func boundary() {
        let needed = Tokens.Size.blockGlyphSize + Tokens.Size.blockGlyphGap
            + Tokens.Size.blockCascadeMinReadableWidth + Tokens.Size.blockGlyphGap + gymTime
        #expect(CompactRowLayout.resolve(rowWidth: needed, timeWidth: gymTime).showsTime)
        #expect(!CompactRowLayout.resolve(rowWidth: needed - 1, timeWidth: gymTime).showsTime)
    }

    @Test("`Morning review` at 104pt truncates inside the row: its laid-out width is less than its natural width")
    func morningReviewTruncatesInside() {
        let row = rowWidth(column: 104)
        let d = CompactRowLayout.resolve(rowWidth: row, timeWidth: CompactRowLayout.metaWidth("07:30-08:15"))
        #expect(d.titleWidth < titleWidth("Morning review"))
        #expect(Tokens.Size.blockGlyphSize + Tokens.Size.blockGlyphGap + d.titleWidth <= row)
    }

    @Test("A badge (no time) gives the title the whole row after the glyph")
    func badgeNoTime() {
        let row = rowWidth(column: 104)
        let d = CompactRowLayout.resolve(rowWidth: row, timeWidth: 0)
        #expect(!d.showsTime)
        #expect(d.titleWidth == row - Tokens.Size.blockGlyphSize - Tokens.Size.blockGlyphGap)
    }
}

/// §3.5 rule 1 at the view level: a `.compact` block in a 100pt frame claims
/// exactly 100pt, whatever its title — the bug behind `Morning review`
/// printing across the next column's divider at 780pt.
@Suite("Compact row — confinement (P2-F04)")
@MainActor
struct CompactRowConfinementTests {

    @Test("A compact block with a long title never claims more than its proposed width")
    func viewWidthIsProposedWidth() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let model = GridBlockModel(
            id: UUID(), title: "Morning review and a much longer tail", start: start,
            end: start.addingTimeInterval(45 * 60), locationName: nil, kind: .routineTimed,
            flexibility: .fixed, status: .scheduled, source: .green, sourceName: "Daily routine",
            glyphOverride: nil, isMovable: true)
        let view = GridBlockView(model: model, presentation: [], renderedHeight: 33)
        let host = NSHostingView(rootView: view.frame(width: 100))
        let size = host.fittingSize
        #expect(size.width <= 100.5)
    }
}
