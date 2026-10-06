//
//  WindowLabelPlacementTests.swift
//  KadenceTests
//
//  Task P2-F06 (PHASE2-REVIEW.md §6 item 6; components.md §7 rules 2 and 3,
//  amended 2026-10-05; G-025). A window label is never drawn half-covered,
//  and an inactive column's note keeps the corner with the label stacked
//  `spacing.xs` below it.
//

import Testing
import Foundation
import CoreGraphics
@testable import Kadence

@Suite("Window label placement (P2-F06)")
@MainActor
struct WindowLabelPlacementTests {

    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Vienna")!
        return c
    }()
    private let hourHeight: CGFloat = 44
    private let labelSize = CGSize(width: 50, height: 12)

    /// 4 Oct 2026 is a Sunday; 5 is Monday.
    private func october(_ day: Int) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: day))!
    }
    private func y(_ hour: Int, _ minute: Int = 0) -> CGFloat {
        (CGFloat(hour) + CGFloat(minute) / 60) * hourHeight
    }
    /// A block frame in a 104pt column, the way `DayLayoutEngine` insets one.
    private func block(_ h0: Int, _ m0: Int, _ h1: Int, _ m1: Int) -> CGRect {
        CGRect(x: 2, y: y(h0, m0), width: 100, height: y(h1, m1) - y(h0, m0))
    }
    private var lowEnergy: [TimeWindow] { MockData.makeTimeWindows().filter { $0.label == "Low energy" } }
    private var sleep: [TimeWindow] { MockData.makeTimeWindows().filter { $0.label == "Sleep" } }

    /// Monday-first week, Mon 5 … Sun 11.
    private func mondayFirst(_ frames: [Int: [CGRect]] = [:]) -> [WindowLabelPlacement.Column] {
        (0..<7).map { WindowLabelPlacement.Column(day: october(5 + $0), blockFrames: frames[$0] ?? []) }
    }

    /// `windowsMode`: peak focus drawn, labels never omitted (§13.3, §7
    /// rule 2 as corrected 2026-10-06).
    private func place(_ windows: [TimeWindow], _ columns: [WindowLabelPlacement.Column],
                       windowsMode: Bool = false) -> [WindowLabelPlacement.Placed] {
        WindowLabelPlacement.place(
            windows: windows, columns: columns, hourHeight: hourHeight,
            showsPeakFocus: windowsMode, omitsWhenCovered: !windowsMode,
            calendar: calendar, labelSize: { _ in labelSize })
    }

    @Test("`Low energy` at 13:00 with `Errands` 12:30–13:15 in Monday is placed in Tuesday")
    func movesPastErrands() {
        let placed = place(lowEnergy, mondayFirst([0: [block(12, 30, 13, 15)]]))
        #expect(placed.count == 1)
        #expect(placed.first?.columnIndex == 1)
        #expect(placed.first?.frame.minY == y(13) + 1)
        #expect(placed.first?.frame.minX == Tokens.Spacing.xs)
    }

    @Test("With nothing in the way the label stays in the leading column")
    func leadingByDefault() {
        #expect(place(lowEnergy, mondayFirst()).first?.columnIndex == 0)
    }

    @Test("Omitted when every column the window spans is covered at its label")
    func omittedWhenAllCovered() {
        let covered = Dictionary(uniqueKeysWithValues: (0..<5).map { ($0, [block(12, 30, 13, 15)]) })
        #expect(place(lowEnergy, mondayFirst(covered)).isEmpty)
        // Saturday has no Low energy span, so it is never a candidate.
    }

    @Test("A block that misses the label's rect does not displace it")
    func blockElsewhere() {
        let placed = place(lowEnergy, mondayFirst([0: [block(13, 30, 14, 0)]]))
        #expect(placed.first?.columnIndex == 0)
    }

    // components.md §7 rule 2, corrected 2026-10-06 (G-044), task P2-SF2.

    @Test("Windows mode: `Low energy` with `Errands` in Monday is placed in Tuesday, uncrossed")
    func windowsModeAvoidsBlocks() {
        let errands = block(12, 30, 13, 15)
        let placed = place(lowEnergy, mondayFirst([0: [errands]]), windowsMode: true)
        #expect(placed.count == 1)
        #expect(placed.first?.columnIndex == 1)
        // Frames are column-local: Tuesday has no block, so nothing crosses it.
        #expect(placed.first?.frame.minY == y(13) + 1)
    }

    @Test("Windows mode, every spanned column covered: drawn in the leading column, not omitted")
    func windowsModeNeverOmits() {
        let covered = Dictionary(uniqueKeysWithValues: (0..<5).map { ($0, [block(12, 30, 13, 15)]) })
        let placed = place(lowEnergy, mondayFirst(covered), windowsMode: true)
        #expect(placed.count == 1)
        #expect(placed.first?.columnIndex == 0)
        #expect(placed.first?.frame.minY == y(13) + 1)
    }

    @Test("Blocks mode unchanged: still omitted when every spanned column is covered")
    func blocksModeStillOmits() {
        let covered = Dictionary(uniqueKeysWithValues: (0..<5).map { ($0, [block(12, 30, 13, 15)]) })
        #expect(place(lowEnergy, mondayFirst(covered)).isEmpty)
        #expect(place(lowEnergy, mondayFirst([0: [block(12, 30, 13, 15)]])).first?.columnIndex == 1)
    }

    @Test("Sunday-first calendar, Mon–Fri template: `Sleep`'s label goes `spacing.xs` below Sunday's note (G-025)")
    func stacksBelowNote() {
        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        let note = CGRect(x: Tokens.Spacing.xs, y: Tokens.Spacing.xs, width: 76, height: 40)
        let columns = (0..<7).map { i in
            WindowLabelPlacement.Column(day: october(4 + i), noteFrame: i == 0 ? note : nil)
        }
        let placed = WindowLabelPlacement.place(
            windows: sleep, columns: columns, hourHeight: hourHeight, showsPeakFocus: false,
            omitsWhenCovered: true, calendar: sundayFirst, labelSize: { _ in labelSize })
        let top = placed.first { $0.frame.minY < y(7) }
        #expect(top?.columnIndex == 0)
        #expect(top?.frame.minY == note.maxY + Tokens.Spacing.xs)
        #expect(top.map { !$0.frame.intersects(note) } == true)
        // Sleep's 22:00 edge is its own span top, labelled once too.
        #expect(placed.contains { $0.frame.minY == y(22) + 1 })
    }

    @Test("A note far above the label leaves it at the window's edge")
    func noteDoesNotMoveDistantLabel() {
        let note = CGRect(x: Tokens.Spacing.xs, y: Tokens.Spacing.xs, width: 76, height: 40)
        var columns = mondayFirst()
        columns[0].noteFrame = note
        #expect(place(lowEnergy, columns).first?.frame.minY == y(13) + 1)
    }

    @Test("Peak focus is labelled only when it is drawn (Windows mode)")
    func peakFocusGated() {
        let all = MockData.makeTimeWindows()
        #expect(!place(all, mondayFirst()).contains { $0.text == "Deep work" })
        #expect(place(all, mondayFirst(), windowsMode: true).contains { $0.text == "Deep work" })
    }
}
