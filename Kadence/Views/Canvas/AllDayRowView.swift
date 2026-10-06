//
//  AllDayRowView.swift
//  Kadence
//
//  layouts.md §3.2 — pinned above the hour grid, hidden entirely when the
//  visible range has no all-day items. No empty row, no residual separator.
//

import SwiftUI

struct AllDayRowView: View {
    let days: [Date]
    let fixtures: MockFixtures
    let now: Date
    /// Task P2-F02: see `DayHeaderRow.trailingReserve`.
    var trailingReserve: CGFloat = 0
    /// interactions.md §1 (amended 2026-10-06, task P2-SF1): while the row
    /// holds ⇥ focus, its focused pill takes §6's selected ring, and the
    /// arrow keys move between pills. Nothing is selected by this — it is
    /// focus, drawn the way §1's table says.
    var isFocused = false
    @State private var focusIndex = 0

    @Environment(CalendarState.self) private var state

    private var itemsPerDay: [(day: Date, items: [AllDayFixture])] {
        days.map { ($0, fixtures.allDayItems(on: $0)) }
    }

    private var maxRows: Int {
        itemsPerDay.map(\.items.count).max() ?? 0
    }

    private var isEmpty: Bool { maxRows == 0 }

    /// The pills in focus order: day by day, top to bottom (only those
    /// drawn — beyond `allDayMaxRows` they are a `+N`).
    private var focusOrder: [AllDayFixture.ID] {
        itemsPerDay.flatMap { $0.items.prefix(Tokens.Size.allDayMaxRows).map(\.id) }
    }

    private var focusedItemID: AllDayFixture.ID? {
        guard isFocused, !focusOrder.isEmpty else { return nil }
        return focusOrder[min(focusIndex, focusOrder.count - 1)]
    }

    /// layouts.md §3.2 — hidden entirely when there is nothing to show, which is
    /// also what makes ⇥ skip it (interactions.md §1).
    static func isVisible(days: [Date], fixtures: MockFixtures) -> Bool {
        days.contains { !fixtures.allDayItems(on: $0).isEmpty }
    }

    var body: some View {
        if !isEmpty {
            let cap = Tokens.Size.allDayMaxRows
            let rows = min(maxRows, cap)
            let height = CGFloat(rows) * Tokens.Size.allDayRowHeight
                + CGFloat(max(rows - 1, 0)) * Tokens.Size.allDayRowGap

            HStack(alignment: .top, spacing: 0) {
                Text("all-day")
                    .typeStyle(.allDayLabel)
                    .foregroundStyle(Tokens.Color.Text.tertiary)
                    .frame(width: Tokens.Size.allDayLabelWidth, alignment: .trailing)
                    .padding(.trailing, Tokens.Spacing.md)

                ForEach(itemsPerDay, id: \.day) { entry in
                    VStack(alignment: .leading, spacing: Tokens.Size.allDayRowGap) {
                        ForEach(entry.items.prefix(cap)) { item in
                            AllDayItemView(
                                fixture: item,
                                presentation: item.id == focusedItemID ? [.selected] : [],
                                now: now)
                        }
                        if entry.items.count > cap {
                            Text("+\(entry.items.count - cap)")
                                .typeStyle(.countdownChip)
                                .foregroundStyle(Tokens.Color.Text.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Tokens.Spacing.xxs)
                }
                Color.clear.frame(width: trailingReserve)
            }
            .frame(height: height, alignment: .top)
            .padding(.vertical, Tokens.Spacing.xxs)
            .background(Tokens.Color.Surface.allDayRow)
            // §1: "Within a region, ↑ ↓ ← → move focus between its items."
            // `.ignored` when the row isn't focused, so the grid's own arrow
            // handling (further up the chain) is untouched.
            .onKeyPress(keys: [.leftArrow, .rightArrow, .upArrow, .downArrow]) { press in
                guard isFocused, !focusOrder.isEmpty else { return .ignored }
                let step = (press.key == .leftArrow || press.key == .upArrow) ? -1 : 1
                focusIndex = max(0, min(focusOrder.count - 1, min(focusIndex, focusOrder.count - 1) + step))
                return .handled
            }
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Tokens.Color.Separator.region)
                    .frame(height: Tokens.Size.hairline)
            }
        }
    }
}
