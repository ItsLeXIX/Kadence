//
//  SnoozeResultRow.swift
//  Kadence
//
//  The row that replaces the popover's action row after a snooze
//  (components.md §16). Its own view, rather than a `@ViewBuilder` method
//  inside `MenuBarPopoverView`, so `KadenceTests/SnoozeRefusalRowTests.swift`
//  can lay out and measure exactly what the popover draws, without a
//  SwiftData store.
//

import SwiftUI

struct SnoozeResultRow: View {
    let confirmation: MenuBarPopoverView.SnoozeConfirmation
    let undo: () -> Void

    var body: some View {
        if let lines = confirmation.refusalLines {
            refusedRow(lines)
        } else {
            movedRow
        }
    }

    /// The moved row, unchanged by the 2026-10-07 amendment: `popoverRow`
    /// (one line), `Undo`, fixed at `size.popoverActionRowHeight`.
    private var movedRow: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Text(confirmation.text)
                .typeStyle(.popoverRow)
                .foregroundStyle(Tokens.Color.Text.primary)
            Button("Undo", action: undo)
        }
        .frame(height: Tokens.Size.popoverActionRowHeight)
    }

    /// components.md §16 (amended 2026-10-07, G-051): two lines with a fixed
    /// break, then wrap; never truncated. No `Undo` — nothing was written.
    private func refusedRow(_ lines: MenuBarFormatting.RefusalLines) -> some View {
        // One `Text` holding both lines with a hard `\n`, so the row stays a
        // single text run: line 2 wraps at word boundaries on its own when
        // a long label needs it, and the no-break space keeps `(protected)`
        // with the label's last word.
        Text(lines.first + "\n" + lines.second)
            .typeStyle(.popoverRefusalRow)   // lineLimit 0 → `.lineLimit(nil)`
            .foregroundStyle(Tokens.Color.Text.primary)
            // SwiftUI note: by default a `Text` offered less height than it
            // wants will truncate with `…`. `fixedSize(horizontal: false,
            // vertical: true)` says "take the width you're offered, but
            // always the full height your wrapped lines need" — so the row
            // grows instead of eliding.
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Row height = the text's height + `spacing.xs` above and below,
            // never less than `size.popoverActionRowHeight`.
            .padding(.vertical, Tokens.Spacing.xs)
            .frame(minHeight: Tokens.Size.popoverActionRowHeight, alignment: .leading)
            // One accessibility element whose label is the one-line sentence
            // (line break replaced by a space).
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(confirmation.text)
    }
}
