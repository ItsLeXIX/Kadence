//
//  ConflictPanelView.swift
//  Kadence
//
//  components.md §14.1–§14.3 — the inspector's conflict mode. Entry point and
//  static content ONLY, per this task's brief:
//
//  - §14.2's collision header: the two colliding blocks rendered as real
//    blocks at the 16–27 density tier (`.titleOnly`, per §3.3's "reading the
//    old numbers" mapping), `spacing.xs` apart, the word "overlaps" between
//    them, then the overlap window and its duration.
//  - §14.3's option rows: title / disturbance line / a `Recommended` chip on
//    the recommended option only, ordered least-disturbance first (already
//    true of `conflict.options` — `ConflictEngine.finalize` sorts it),
//    min height, gap, radius and fills all from tokens.
//
//  What this file explicitly does NOT do: apply an option with `↩`. Selecting
//  a row (`onSelectOption`) still only highlights it here
//  (`color.interactive.selectedRowFill`) — but as of P2-T16, changing
//  `selectedConflictOptionID` (this view's `onSelectOption` callback target)
//  ALSO drives a live canvas preview and its `⎋`/focus-loss abandonment; that
//  wiring lives in `MainWindow.swift`/`DayColumnView.swift`/`CalendarState.swift`,
//  not in this file, since this file has no access to the calendar canvas.
//  See those files for §14.4's preview and interactions.md §10.1–§10.2.
//

import SwiftUI

struct ConflictPanelView: View {
    let conflict: Conflict
    let now: Date
    let selectedOptionID: UUID?
    let onSelectOption: (UUID) -> Void

    /// §14.2 says "the 16–27 density tier" (§3.3's old numbering for
    /// `.titleOnly`, band 18–27 in the current numbering) without pinning an
    /// exact point size — any height in that band resolves to the same
    /// tier and content set, so the specific value is this task's own call,
    /// not an invented token. Midpoint of the band.
    private static let collisionBlockHeight: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xl) {
            collisionHeader
            optionsList
        }
    }

    // MARK: §14.2 — the collision header

    /// Earlier-starting event first, purely for a stable, readable stacking
    /// order — §14.2 does not specify which of the two goes on top.
    private var orderedEvents: (first: Event, second: Event) {
        conflict.routineEvent.start <= conflict.otherEvent.start
            ? (conflict.routineEvent, conflict.otherEvent)
            : (conflict.otherEvent, conflict.routineEvent)
    }

    private var collisionHeader: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            VStack(spacing: Tokens.Spacing.xs) {
                collisionBlock(for: orderedEvents.first)
                Text("overlaps")
                    .typeStyle(.inspectorLabel)
                    .foregroundStyle(Tokens.Color.Text.secondary)
                collisionBlock(for: orderedEvents.second)
            }
            Text(overlapLine)
                .typeStyle(.blockMeta)
                .foregroundStyle(Tokens.Color.Text.primary)
        }
    }

    private func collisionBlock(for event: Event) -> some View {
        GridBlockView(
            model: GridBlockModel(event: event, now: now),
            // Same style resolver, same hue, same rail as the grid — and the
            // grid already carries `.conflicted` for both these events
            // (P2-T14's wiring), so the panel matching that presentation is
            // what makes "recognisably the thing on the grid" (§14.2) true.
            presentation: [.conflicted],
            renderedHeight: Self.collisionBlockHeight)
            .frame(maxWidth: .infinity)
    }

    /// "13:00–14:30 · 45 min overlap" (§14.2).
    private var overlapLine: String {
        let time = BlockFormatters.time
        let minutes = Int((conflict.overlapEnd.timeIntervalSince(conflict.overlapStart) / 60).rounded())
        return "\(time.string(from: conflict.overlapStart))–\(time.string(from: conflict.overlapEnd)) · \(minutes) min overlap"
    }

    // MARK: §14.3 — the option rows

    private var optionsList: some View {
        VStack(spacing: Tokens.Size.conflictOptionGap) {
            ForEach(ConflictOptionFormatting.rows(for: conflict)) { row in
                optionRow(row)
            }
        }
    }

    private func optionRow(_ row: ConflictOptionRowContent) -> some View {
        let isSelected = row.id == selectedOptionID

        return Button {
            onSelectOption(row.id)
        } label: {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                HStack(alignment: .top, spacing: Tokens.Spacing.sm) {
                    Text(row.title)
                        .typeStyle(.conflictOptionTitle)
                        .foregroundStyle(Tokens.Color.Text.primary)
                    Spacer(minLength: Tokens.Spacing.sm)
                    if row.isRecommended {
                        recommendedChip
                    }
                }
                Text(row.delta)
                    .typeStyle(.conflictOptionDelta)
                    .foregroundStyle(Tokens.Color.Text.secondary)
            }
            .padding(Tokens.Spacing.sm)
            .frame(minHeight: Tokens.Size.conflictOptionRowMinHeight, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                    .fill(isSelected ? Tokens.Color.Interactive.selectedRowFill : Tokens.Color.Surface.canvasSunken))
        }
        .buttonStyle(.plain)
    }

    /// §14.3 — "marked with the word Recommended, not a colour and not a
    /// glyph."
    private var recommendedChip: some View {
        Text("Recommended")
            .typeStyle(.blockMeta)
            .foregroundStyle(Tokens.Color.Text.secondary)
            .padding(Tokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip, style: .continuous)
                    .fill(Tokens.Color.Surface.canvasAlt))
    }
}
