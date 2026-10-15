//
//  PopoverLeaveLineTests.swift
//  KadenceTests
//
//  P3S2-F03 — components.md §26.2 (amended 2026-10-15): the popover's leave
//  line has `lineLimit` 2 with tail truncation only after the second line;
//  `Leave by HH:mm` / `Leave now` are never split or truncated; the meta line
//  keeps `lineLimit` 1. Measured on the real `PopoverLeaveLineText` at the
//  width the NEXT block gives it, and with TextKit on the same font for
//  where the lines break.
//

import Testing
import SwiftUI
import AppKit
@testable import Kadence

@MainActor
struct PopoverLeaveLineTests {
    /// The leave line's width: the popover less its side padding, the rail
    /// and the rail's gap (`MenuBarPopoverView.nextSection`).
    static let width = Tokens.Size.popoverWidth - 2 * Tokens.Spacing.lg - Tokens.Size.blockRailWidth - Tokens.Spacing.sm

    static func height(_ line: MenuBarFormatting.LeaveLine) -> CGFloat {
        let host = NSHostingView(rootView: PopoverLeaveLineText(line: line).frame(width: width, alignment: .leading))
        return host.fittingSize.height
    }

    static let oneLine = height(.init(text: "Leave by 08:15", tone: .primary))

    /// How many lines the drawn text takes.
    static func lineCount(_ text: String) -> Int {
        let h = height(.init(text: text, tone: .primary))
        return Int((h / oneLine).rounded())
    }

    /// TextKit's line fragments for `text` at the width, in the line's font.
    static func fragments(_ text: String) -> [String] {
        let font = NSFont.monospacedDigitSystemFont(ofSize: Tokens.Typography.PopoverNextMeta.size, weight: .regular)
        let storage = NSTextStorage(string: text, attributes: [.font: font])
        let manager = NSLayoutManager()
        let container = NSTextContainer(size: CGSize(width: width, height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        manager.addTextContainer(container)
        storage.addLayoutManager(manager)
        var lines: [String] = []
        var index = 0
        while index < manager.numberOfGlyphs {
            var range = NSRange()
            manager.lineFragmentRect(forGlyphAt: index, effectiveRange: &range)
            let chars = manager.characterRange(forGlyphRange: range, actualGlyphRange: nil)
            lines.append((text as NSString).substring(with: chars))
            index = NSMaxRange(range)
        }
        return lines
    }

    @Test("The three lines that were cut off are drawn whole on at most two lines")
    func wraps() {
        for text in ["Travel time unavailable · Home has no address",
                     "Leave by 17:45 · 35 min from FH Technikum Wien",
                     "Travel time unavailable · Apple Maps paused until 10:40"] {
            let line = MenuBarFormatting.LeaveLine(text: text, tone: .primary)
            let lines = Self.fragments(line.display)
            #expect(lines.count <= 2, "\(text): \(lines)")
            #expect(lines.joined() == line.display)
            #expect(Self.lineCount(text) == lines.count, "\(text)")
        }
    }

    @Test("`Leave by 12:15 · 35 min from Home` stays one line")
    func oneLine() {
        #expect(Self.lineCount("Leave by 12:15 · 35 min from Home") == 1)
        #expect(Self.fragments("Leave by 12:15 · 35 min from Home").count == 1)
    }

    @Test("A 60-character place truncates on line 2; `Leave by 17:45` is intact on line 1")
    func longPlace() {
        let place = "Universitätsbibliothek der Technischen Universität Wien, Haupt"
        #expect(place.count >= 60)
        let line = MenuBarFormatting.LeaveLine(text: "Leave by 17:45 · 35 min from \(place)", tone: .primary)
        let lines = Self.fragments(line.display)
        #expect(lines.count > 2, "long enough to need truncation")
        #expect(lines[0].hasPrefix("Leave\u{00A0}by\u{00A0}17:45"))
        // Drawn: two lines, the rest truncated.
        #expect(Self.lineCount(line.text) == 2)
    }

    @Test("The lead is never split: `Leave by HH:mm` and `Leave now` use no-break spaces; other lines are unchanged")
    func lead() {
        #expect(MenuBarFormatting.LeaveLine(text: "Leave by 08:15 · 35 min from Home", tone: .primary).display
                == "Leave\u{00A0}by\u{00A0}08:15 · 35 min from Home")
        #expect(MenuBarFormatting.LeaveLine(text: "Leave now · leave-by was ≈08:15", tone: .now).display
                == "Leave\u{00A0}now · leave-by was ≈08:15")
        #expect(MenuBarFormatting.LeaveLine(text: "Leave by ≈08:15 · estimate, offline", tone: .primary).display
                == "Leave\u{00A0}by\u{00A0}≈08:15 · estimate, offline")
        let unavailable = "Travel time unavailable · Home has no address"
        #expect(MenuBarFormatting.LeaveLine(text: unavailable, tone: .secondary).display == unavailable)
        #expect(TypeStyle.popoverLeaveLine.lineLimit == 2)
        #expect(TypeStyle.popoverNextMeta.lineLimit == 1)
    }
}
