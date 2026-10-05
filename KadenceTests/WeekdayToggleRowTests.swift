//
//  WeekdayToggleRowTests.swift
//  KadenceTests
//
//  Task P2-F08 (PHASE2-REVIEW.md §6 item 8; layouts.md §8.1 and components.md
//  §13.5.4, amended 2026-10-05; G-027, G-028).
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

@Suite("Weekday toggle row (P2-F08)")
@MainActor
struct WeekdayToggleRowTests {

    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_GB")
        return c
    }
    /// Mon-first, as `RoutineWeekLayout.orderedWeekdays(firstWeekday: 2)`.
    private let monFirst = [2, 3, 4, 5, 6, 7, 1]

    @Test("Each toggle speaks its full weekday name, with `in routine` / `not in routine`")
    func routineLabels() {
        let items = WeekdayToggleItem.items(
            weekdays: monFirst, isOn: { [2, 4, 6].contains($0) }, context: .routine, calendar: calendar)
        #expect(items.map(\.accessibilityLabel) ==
                ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"])
        #expect(items.map(\.letter) == ["M", "T", "W", "T", "F", "S", "S"])
        #expect(items[0].accessibilityValue == "in routine")
        #expect(items[1].accessibilityValue == "not in routine")
        #expect(items.allSatisfy { !$0.isDisabled })
    }

    @Test("Time windows speak `on` / `off`")
    func windowValues() {
        let items = WeekdayToggleItem.items(
            weekdays: monFirst, isOn: { $0 == 2 || $0 == 3 }, context: .window, calendar: calendar)
        #expect(items[0].accessibilityValue == "on")
        #expect(items[2].accessibilityValue == "off")
        #expect(items.allSatisfy { !$0.isDisabled }, "two days on: neither is the last")
    }

    @Test("The row fits the inspector's 228pt content width (192pt)")
    func fits() {
        #expect(WeekdayToggleItem.rowWidth() == 192)
        #expect(WeekdayToggleItem.rowWidth() <= Tokens.Size.editorInspectorWidth - 2 * Tokens.Spacing.xl)
    }

    @Test("A window with one weekday: that toggle reports disabled with the help text; the others don't")
    func lastWindowDayDisabled() {
        let items = WeekdayToggleItem.items(
            weekdays: monFirst, isOn: { $0 == 4 }, context: .window, calendar: calendar)
        let wednesday = items.first { $0.weekday == 4 }!
        #expect(wednesday.isDisabled)
        #expect(wednesday.help == "A window needs at least one day. Delete it instead.")
        #expect(items.filter(\.isDisabled).count == 1)
    }

    @Test("A template's last weekday is never disabled — a paused routine is allowed")
    func lastTemplateDayEnabled() {
        let items = WeekdayToggleItem.items(
            weekdays: monFirst, isOn: { $0 == 4 }, context: .routine, calendar: calendar)
        #expect(items.allSatisfy { !$0.isDisabled })
    }

    @Test("A one-day window can't reach an empty set through the store either")
    func storeRefusesEmpty() throws {
        let container = try ModelContainer(
            for: Schema(KadenceSchema.models),
            configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let store = TimeWindowStore(context: context, undo: UndoStack())
        let window = try #require(store.create(weekdays: [4], startMinutes: 600, endMinutes: 660,
                                               kind: .protected, label: "Test"))
        store.setWeekdays(window, to: [])
        #expect(window.weekdays == [4])
    }

    @Test("The letter style drops `dayHeaderWeekday`'s uppercase transform (it leaked into the AX strings)")
    func letterStyleNotUppercased() {
        #expect(TypeStyle.dayHeaderWeekday.isUppercased)
        #expect(!WeekdayToggleRow.letterStyle.isUppercased)
        #expect(WeekdayToggleRow.letterStyle.size == TypeStyle.dayHeaderWeekday.size)
    }
}
