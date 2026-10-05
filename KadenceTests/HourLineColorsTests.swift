//
//  HourLineColorsTests.swift
//  KadenceTests
//
//  Task P2-F07 (PHASE2-REVIEW.md §6 item 7; components.md §13.5.2, amended
//  2026-10-05; G-026). An inactive Routines column's lines stay one step
//  lighter than an active column's under Increase Contrast too.
//

import Testing
@testable import Kadence

@Suite("Hour-line colours, standard and Increase Contrast (P2-F07)")
struct HourLineColorsTests {

    @Test("Inactive column: `separator.hour` under Increase Contrast, `separator.halfHour` without — both line kinds")
    func inactive() {
        let ic = HourLineColors.resolve(recessed: true, increaseContrast: true)
        #expect(ic.hour == .hour && ic.halfHour == .hour)
        let standard = HourLineColors.resolve(recessed: true, increaseContrast: false)
        #expect(standard.hour == .halfHour && standard.halfHour == .halfHour)
    }

    @Test("Active column: `hour` normally, `strong` under Increase Contrast (unchanged)")
    func active() {
        #expect(HourLineColors.resolve(recessed: false, increaseContrast: false).hour == .hour)
        #expect(HourLineColors.resolve(recessed: false, increaseContrast: true).hour == .strong)
        #expect(HourLineColors.resolve(recessed: false, increaseContrast: true).halfHour == .halfHour)
    }

    @Test("Inactive is exactly one step below active in both modes")
    func oneStep() {
        let order: [SeparatorToken] = [.halfHour, .hour, .strong]
        for ic in [false, true] {
            let active = order.firstIndex(of: HourLineColors.resolve(recessed: false, increaseContrast: ic).hour)!
            let inactive = order.firstIndex(of: HourLineColors.resolve(recessed: true, increaseContrast: ic).hour)!
            #expect(active - inactive == 1)
        }
    }
}
