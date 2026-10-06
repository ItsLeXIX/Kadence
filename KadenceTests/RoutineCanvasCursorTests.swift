//
//  RoutineCanvasCursorTests.swift
//  KadenceTests
//
//  Task P2-C3 (PHASE2-REVIEW.md "Closeout — 2026-10-07" CF3; interactions.md
//  §1 amended 2026-10-07, §11.1; G-050; DEVIATIONS A36): the Routines
//  canvas's cursor mode, minimum form. The rules are pure
//  (`RoutineCanvasCursor`); the drawing is checked by rendering the line and
//  the gutter. The wiring (⇥, keys, clicks, ⎋, the AX value) is checked live
//  by `Scripts/check-routines-cursor.sh`.
//

import Testing
import Foundation
import SwiftUI
import AppKit
@testable import Kadence

private let hourHeight = Tokens.Size.hourHeightWeek     // the Routines canvas's scale
private func top(_ hour: Int, _ minute: Int = 0) -> CGFloat { CGFloat(hour * 60 + minute) / 60 * hourHeight }
private let viewport: CGFloat = 600                      // ≈ 13.6 hours visible

@Suite("CF3 — the Routines canvas cursor (§1, 2026-10-07)")
@MainActor
struct RoutineCanvasCursorTests {

    @Test("Entry at the default 06:00 scroll → 07:00, the first whole hour strictly below the top")
    func entryAtDefaultScroll() {
        #expect(RoutineCanvasCursor.entryMinute(last: nil, visibleTop: top(6), visibleHeight: viewport,
                                                hourHeight: hourHeight) == 7 * 60)
        // Strictly below: mid-hour tops go to the next hour too.
        #expect(RoutineCanvasCursor.entryMinute(last: nil, visibleTop: top(6, 20), visibleHeight: viewport,
                                                hourHeight: hourHeight) == 7 * 60)
        #expect(RoutineCanvasCursor.entryMinute(last: nil, visibleTop: 0, visibleHeight: viewport,
                                                hourHeight: hourHeight) == 60)
    }

    @Test("Entry restores the last cursor time when it is in view, else the first hour below the top")
    func entryRestoresLast() {
        // 09:30 is inside 06:00 + 600pt.
        #expect(RoutineCanvasCursor.entryMinute(last: 9 * 60 + 30, visibleTop: top(6), visibleHeight: viewport,
                                                hourHeight: hourHeight) == 9 * 60 + 30)
        // 03:00 is above the viewport → 07:00.
        #expect(RoutineCanvasCursor.entryMinute(last: 3 * 60, visibleTop: top(6), visibleHeight: viewport,
                                                hourHeight: hourHeight) == 7 * 60)
        // 22:00 is below it (06:00 + 13.6h ≈ 19:38) → 07:00.
        #expect(RoutineCanvasCursor.entryMinute(last: 22 * 60, visibleTop: top(6), visibleHeight: viewport,
                                                hourHeight: hourHeight) == 7 * 60)
        // Scrolled to 12:00: the old 09:30 is out of view → 13:00.
        #expect(RoutineCanvasCursor.entryMinute(last: 9 * 60 + 30, visibleTop: top(12), visibleHeight: viewport,
                                                hourHeight: hourHeight) == 13 * 60)
    }

    @Test("↑ ↓ move 15 minutes, clamped at 00:00 and 23:45; ← → change nothing")
    func arrows() {
        #expect(RoutineCanvasCursor.apply(.down, to: 7 * 60) == 7 * 60 + 15)
        #expect(RoutineCanvasCursor.apply(.up, to: 7 * 60) == 6 * 60 + 45)
        #expect(RoutineCanvasCursor.apply(.up, to: 0) == 0)
        #expect(RoutineCanvasCursor.apply(.up, to: 10) == 0)
        #expect(RoutineCanvasCursor.apply(.down, to: 23 * 60 + 45) == 23 * 60 + 45)
        #expect(RoutineCanvasCursor.apply(.down, to: 23 * 60 + 40) == 23 * 60 + 45)
        #expect(RoutineCanvasCursor.apply(.left, to: 7 * 60) == 7 * 60)
        #expect(RoutineCanvasCursor.apply(.right, to: 7 * 60) == 7 * 60)
    }

    @Test("The canvas scrolls only to keep the line in view")
    func scrollOnlyAsNeeded() {
        func edge(_ minute: Int) -> RoutineCanvasCursor.ScrollEdge? {
            RoutineCanvasCursor.scrollEdge(for: minute, visibleTop: top(6), visibleHeight: viewport,
                                           hourHeight: hourHeight)
        }
        #expect(edge(7 * 60) == nil)
        #expect(edge(6 * 60) == nil)                  // exactly at the top edge: in view
        #expect(edge(5 * 60 + 45) == .top)            // one step above
        #expect(edge(19 * 60 + 30) == nil)            // 06:00 + 600pt ≈ 19:38
        #expect(edge(19 * 60 + 45) == .bottom)        // one step past the bottom
        // Before the viewport has a height there is nothing to keep in view.
        #expect(RoutineCanvasCursor.scrollEdge(for: 23 * 60, visibleTop: 0, visibleHeight: 0,
                                               hourHeight: hourHeight) == nil)
    }

    @Test("An empty-canvas click places the cursor at the clicked slot, in active and inactive columns")
    func clickPlaces() {
        #expect(RoutineCanvasCursor.minute(forY: top(10, 7), hourHeight: hourHeight) == 10 * 60)
        #expect(RoutineCanvasCursor.minute(forY: top(10, 8), hourHeight: hourHeight) == 10 * 60 + 15)
        #expect(RoutineCanvasCursor.minute(forY: top(24), hourHeight: hourHeight) == 23 * 60 + 45)
        #expect(RoutineCanvasCursor.minute(forY: 0, hourHeight: hourHeight) == 0)
        // An inactive column (Tuesday in `Daily routine`, Blocks mode)
        // places the same way — and its surface still refuses creation.
        let tuesday = RoutineColumnTreatment.resolve(weekday: 3, activeWeekdays: [2, 4, 6], mode: .blocks)
        #expect(tuesday == .inactive)
        #expect(tuesday.refusesBlockCreate && !tuesday.acceptsBlockCreate)
    }

    @Test("⎋: a selection → cursor mode (deselect, focus stays); cursor mode → unfocused")
    func escape() {
        #expect(RoutineCanvasCursor.escape(hasSelection: true) == .deselect)
        #expect(RoutineCanvasCursor.escape(hasSelection: false) == .unfocus)
        // After the deselect, the still-focused canvas is in cursor mode.
        #expect(RoutineCanvasCursor.isCursorMode(canvasFocused: true, hasBlockSelection: false,
                                                 hasWindowSelection: false, inConflict: false))
        // After the unfocus it is not.
        #expect(!RoutineCanvasCursor.isCursorMode(canvasFocused: false, hasBlockSelection: false,
                                                  hasWindowSelection: false, inConflict: false))
    }

    @Test("A Blocks/Windows switch with a selection and the canvas focused → cursor mode")
    func modeSwitch() {
        // With a block (Blocks) or a window (Windows) selected: selection mode.
        #expect(!RoutineCanvasCursor.isCursorMode(canvasFocused: true, hasBlockSelection: true,
                                                  hasWindowSelection: false, inConflict: false))
        #expect(!RoutineCanvasCursor.isCursorMode(canvasFocused: true, hasBlockSelection: false,
                                                  hasWindowSelection: true, inConflict: false))
        // §11.1 drops the selection on the switch; focus is unchanged.
        #expect(RoutineCanvasCursor.isCursorMode(canvasFocused: true, hasBlockSelection: false,
                                                 hasWindowSelection: false, inConflict: false))
        // A template conflict is never cursor mode.
        #expect(!RoutineCanvasCursor.isCursorMode(canvasFocused: true, hasBlockSelection: false,
                                                  hasWindowSelection: false, inConflict: true))
    }

    @Test("The canvas's accessibility value in cursor mode is the time: 07:00")
    func accessibilityValue() {
        #expect(RoutineCanvasCursor.accessibilityValue(7 * 60) == "07:00")
        #expect(RoutineCanvasCursor.accessibilityValue(23 * 60 + 45) == "23:45")
        #expect(RoutineCanvasCursor.accessibilityValue(0) == "00:00")
    }

    // MARK: Drawing

    private static func render(_ view: some View, width: CGFloat) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .light))
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(width: width, height: hourHeight * 24)
        return NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
    }

    private static func pixel(_ rep: NSBitmapImageRep, _ x: Int, _ y: Int) -> [Int] {
        var p = [Int](repeating: 0, count: 4)
        rep.getPixel(&p, atX: x, y: y)
        return Array(p.prefix(3))
    }

    /// `interactive.accent`, light: #0A6CFF.
    private static let accent = [10, 108, 255]

    @Test("The line spans all seven columns at the cursor's y, and not the gutter")
    func lineSpansColumnsNotGutter() throws {
        let column: CGFloat = 100
        let gutter = Tokens.Size.timeGutterWidth
        let width = gutter + 7 * column
        let view = ZStack(alignment: .topLeading) {
            Tokens.Color.Surface.canvas
            RoutineCursorLine(minute: 7 * 60, hourHeight: hourHeight, columnsWidth: 7 * column)
        }
        .frame(width: width, height: hourHeight * 24, alignment: .topLeading)
        let rep = try Self.render(view, width: width)
        let y = Int(top(7))
        // Every column, sampled near both of its edges and its middle.
        for index in 0..<7 {
            for dx in [2, Int(column / 2), Int(column) - 2] {
                #expect(Self.pixel(rep, Int(gutter) + index * Int(column) + dx, y) == Self.accent,
                        "column \(index) +\(dx)")
            }
        }
        // Nothing in the gutter, nothing a row above or below (1pt line).
        for x in stride(from: 0, to: Int(gutter), by: 4) {
            #expect(Self.pixel(rep, x, y) != Self.accent, "gutter x \(x)")
        }
        #expect(Self.pixel(rep, Int(gutter) + 50, y - 1) != Self.accent)
        #expect(Self.pixel(rep, Int(gutter) + 50, y + 1) != Self.accent)
    }

    @Test("The gutter prints the cursor time in accent where 07:00's hour label was")
    func gutterTime() throws {
        func accentRows(cursor: Int?) throws -> [Int] {
            let strip = RoutineGutterStrip(windows: [], leadingWeekday: 2, hourHeight: hourHeight,
                                           cursorMinute: cursor)
                .background(Tokens.Color.Surface.canvas)
            let rep = try Self.render(strip, width: Tokens.Size.timeGutterWidth)
            // Rows 06:30…07:30 holding a pixel close to accent (antialiased text).
            return (Int(top(6, 30))..<Int(top(7, 30))).filter { y in
                (0..<rep.pixelsWide).contains { x in
                    let p = Self.pixel(rep, x, y)
                    return abs(p[0] - 10) < 40 && abs(p[1] - 108) < 40 && p[2] > 220
                }
            }
        }
        #expect(try accentRows(cursor: nil).isEmpty, "no cursor: no accent in the gutter")
        let rows = try accentRows(cursor: 7 * 60)
        #expect(!rows.isEmpty, "cursor 07:00: accent text in the gutter")
        // Centred on the 07:00 line (the label sits at the line − 5pt).
        #expect(rows.allSatisfy { abs($0 - Int(top(7))) < 12 })
    }
}
