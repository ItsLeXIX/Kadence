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

    @Environment(CalendarState.self) private var state

    private var itemsPerDay: [(day: Date, items: [AllDayFixture])] {
        days.map { ($0, fixtures.allDayItems(on: $0)) }
    }

    private var maxRows: Int {
        itemsPerDay.map(\.items.count).max() ?? 0
    }

    private var isEmpty: Bool { maxRows == 0 }

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
                                presentation: [],
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
            }
            .frame(height: height, alignment: .top)
            .padding(.vertical, Tokens.Spacing.xxs)
            .background(Tokens.Color.Surface.allDayRow)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(Tokens.Color.Separator.region)
                    .frame(height: Tokens.Size.hairline)
            }
        }
    }
}
