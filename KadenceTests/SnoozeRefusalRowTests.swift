//
//  SnoozeRefusalRowTests.swift
//  KadenceTests
//
//  Task P2-C1 (PHASE2-REVIEW.md "Closeout — 2026-10-07" CF1; components.md
//  §16 amended 2026-10-07; G-051): the refused snooze row is two lines with a
//  fixed break, then wraps; it is never truncated. The moved row is unchanged.
//
//  Measured on the real `SnoozeResultRow` laid out by `ImageRenderer` at the
//  width the popover gives it: `size.popoverWidth` (300) less two
//  `spacing.lg` insets = 276pt. Line breaking is cross-checked with TextKit
//  (`NSLayoutManager`) on the same font, which is what lets a test see which
//  words landed on which line.
//

import Testing
import Foundation
import SwiftUI
import AppKit
@testable import Kadence

private let rowWidth = Tokens.Size.popoverWidth - 2 * Tokens.Spacing.lg

private func at(_ hour: Int, _ minute: Int) -> Date {
    Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 6, hour: hour, minute: minute))!
}

/// Exactly 40 characters (asserted below): case (c)'s long label.
private let fortyCharLabel = "Wind-down and offline reading before bed"

@MainActor
private func refusal(label: String) -> MenuBarPopoverView.SnoozeConfirmation {
    MenuBarPopoverView.SnoozeConfirmation(
        eventID: UUID(), expectedStart: at(23, 50),
        text: MenuBarFormatting.snoozeRefused(start: at(0, 5), windowLabel: label),
        refusalLines: MenuBarFormatting.snoozeRefusedLines(start: at(0, 5), windowLabel: label))
}

/// The laid-out size of `view` when offered `width` (nil = its ideal width).
@MainActor
private func size<V: View>(of view: V, width: CGFloat?) -> CGSize {
    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(width: width, height: nil)
    renderer.scale = 1
    return renderer.nsImage?.size ?? .zero
}

/// The refused row's text exactly as `SnoozeResultRow` styles it.
@MainActor
private func refusalText(_ string: String) -> some View {
    Text(string)
        .typeStyle(.popoverRefusalRow)
        .fixedSize(horizontal: false, vertical: true)
}

@MainActor
private func lineCount(of string: String) -> Int {
    let one = size(of: refusalText("Not moved").fixedSize(), width: nil).height
    let all = size(of: refusalText(string).frame(width: rowWidth, alignment: .leading), width: rowWidth).height
    return Int((all / one).rounded())
}

/// TextKit's line fragments for `string` at `rowWidth` in the row's font
/// (13pt regular, monospaced digits — `typography.popoverRefusalRow`).
@MainActor
private func textKitLines(_ string: String) -> [String] {
    let font = NSFont.monospacedDigitSystemFont(ofSize: Tokens.Typography.PopoverRefusalRow.size, weight: .regular)
    let storage = NSTextStorage(string: string, attributes: [.font: font])
    let layout = NSLayoutManager()
    let container = NSTextContainer(size: CGSize(width: rowWidth, height: .greatestFiniteMagnitude))
    container.lineFragmentPadding = 0
    layout.addTextContainer(container)
    storage.addLayoutManager(layout)
    var lines: [String] = []
    layout.enumerateLineFragments(forGlyphRange: layout.glyphRange(for: container)) { _, _, _, glyphs, _ in
        let chars = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
        lines.append((string as NSString).substring(with: chars).trimmingCharacters(in: .whitespacesAndNewlines))
    }
    return lines
}

@Suite("CF1 — the refused snooze row: two lines, never truncated (§16, 2026-10-07)")
@MainActor
struct SnoozeRefusalRowTests {

    @Test("Tokens 1.3.0: popoverRefusalRow is 13pt regular with no line limit")
    func token() {
        #expect(Tokens.Typography.PopoverRefusalRow.size == 13)
        #expect(Tokens.Typography.PopoverRefusalRow.lineLimit == 0)
        #expect(TypeStyle.popoverRefusalRow.lineLimit == nil)   // 0 → no limit
        #expect(rowWidth == 276)
    }

    @Test("(a) Sleep → exactly two lines, `Not moved — 00:05 is inside` / `Sleep (protected)`, untruncated")
    func sleep() throws {
        let row = refusal(label: "Sleep")
        let lines = try #require(row.refusalLines)
        #expect(lines.first == "Not moved — 00:05 is inside")
        #expect(lines.second == "Sleep\u{00A0}(protected)")
        // Each line's ideal (unwrapped) width fits the row: nothing is cut.
        #expect(size(of: refusalText(lines.first).fixedSize(), width: nil).width <= rowWidth)
        #expect(size(of: refusalText(lines.second).fixedSize(), width: nil).width <= rowWidth)
        let drawn = lines.first + "\n" + lines.second
        #expect(lineCount(of: drawn) == 2)
        #expect(textKitLines(drawn) == ["Not moved — 00:05 is inside", "Sleep\u{00A0}(protected)"])
        #expect(!drawn.contains("…"))
    }

    @Test("(b) empty and whitespace-only labels → `… is inside` / `a protected window`")
    func unlabelled() throws {
        for label in ["", "   "] {
            let lines = try #require(refusal(label: label).refusalLines)
            #expect(lines.first == "Not moved — 00:05 is inside")
            #expect(lines.second == "a protected window")
            #expect(size(of: refusalText(lines.second).fixedSize(), width: nil).width <= rowWidth)
            #expect(lineCount(of: lines.first + "\n" + lines.second) == 2)
        }
    }

    @Test("(c) a 40-character label wraps to ≥ 3 lines, no `…`, `(protected)` never alone")
    func longLabel() throws {
        #expect(fortyCharLabel.count == 40)
        let lines = try #require(refusal(label: fortyCharLabel).refusalLines)
        let drawn = lines.first + "\n" + lines.second
        #expect(lineCount(of: drawn) >= 3)
        let fragments = textKitLines(drawn)
        #expect(fragments.count >= 3)
        #expect(fragments.allSatisfy { $0 != "(protected)" }, "\(fragments)")
        #expect(fragments.last?.hasSuffix("\u{00A0}(protected)") == true)
        // Every word of the label survives into the laid-out text.
        #expect(fragments.joined(separator: " ").contains("before bed"))
        #expect(!drawn.contains("…"))
        // TextKit and SwiftUI agree on how many lines that is.
        #expect(fragments.count == lineCount(of: drawn))
    }

    @Test("(d) row height = text height + 8, never < 28")
    func rowHeight() throws {
        for label in ["Sleep", "", fortyCharLabel] {
            let row = refusal(label: label)
            let lines = try #require(row.refusalLines)
            let text = size(of: refusalText(lines.first + "\n" + lines.second)
                .frame(width: rowWidth, alignment: .leading), width: rowWidth).height
            let height = size(of: SnoozeResultRow(confirmation: row, undo: {}).frame(width: rowWidth),
                              width: rowWidth).height
            #expect(height == max(text + 2 * Tokens.Spacing.xs, Tokens.Size.popoverActionRowHeight),
                    "\(label): row \(height), text \(text)")
            #expect(height >= Tokens.Size.popoverActionRowHeight)
        }
    }

    @Test("(e) the accessibility label is the one-line sentence")
    func accessibilityLabel() {
        #expect(refusal(label: "Sleep").text == "Not moved — 00:05 is inside Sleep (protected)")
        #expect(refusal(label: "").text == "Not moved — 00:05 is inside a protected window")
        #expect(!refusal(label: "Sleep").text.contains("\n"))
        #expect(!refusal(label: "Sleep").text.contains("\u{00A0}"))
    }

    @Test("(f) the moved rows still render at 28pt, one line, with Undo")
    func movedRows() {
        for text in ["Moved to 17:45", "Moved to tomorrow 00:05"] {
            let row = MenuBarPopoverView.SnoozeConfirmation(eventID: UUID(), expectedStart: at(0, 5), text: text)
            #expect(!row.isRefusal)   // → `Undo` is drawn
            let laidOut = size(of: SnoozeResultRow(confirmation: row, undo: {}), width: rowWidth)
            #expect(laidOut.height == Tokens.Size.popoverActionRowHeight)
            // Text + Undo at their ideal (unconstrained) widths fit the row:
            // one line, nothing elided.
            #expect(size(of: SnoozeResultRow(confirmation: row, undo: {}), width: nil).width <= rowWidth)
            #expect(TypeStyle.popoverRow.lineLimit == 1)
        }
    }
}
