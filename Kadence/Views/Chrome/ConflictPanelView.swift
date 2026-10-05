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
//  What this file still does NOT do: apply an option with `↩`, or anything
//  else `EventStore`/`UndoStack`-shaped. Selecting a row (`onSelectOption`)
//  still only highlights it here (`ConflictOptionRowStyle`: a tinted card with
//  a focus-ring border since P2-F13, never solid `selectedRowFill`) — as
//  of P2-T16, changing `selectedConflictOptionID` (this view's
//  `onSelectOption` callback target) ALSO drives a live canvas preview and
//  its `⎋`/focus-loss abandonment, and as of P2-T17, pressing `↩` while that
//  same field is non-nil applies it — but all of that wiring (the preview,
//  the abandonment, and now the apply) lives in
//  `MainWindow.swift`/`DayColumnView.swift`/`CalendarState.swift`, not in
//  this file, since this file has no access to the calendar canvas or the
//  store. See those files for §14.4's preview, interactions.md §10.1–§10.2,
//  and §14.5's "resolved and empty" state.
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
    static let collisionBlockHeight: CGFloat = 22

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
        // §11: the spoken label names the other half of THIS conflict.
        var model = GridBlockModel(event: event, now: now)
        let other = event.id == conflict.routineEvent.id ? conflict.otherEvent : conflict.routineEvent
        model.conflicts = [.event(title: other.title)]
        return GridBlockView(
            model: model,
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
        ConflictOptionRowView(
            title: row.title, delta: row.delta, isRecommended: row.isRecommended,
            isSelected: row.id == selectedOptionID,
            action: { onSelectOption(row.id) })
    }
}

/// One §14.3 option row: title, disturbance line, and the `Recommended` chip
/// on the recommended option only. Shared by the day panel and the template
/// panel (§14.6: "same row geometry, same chip"); task P2-T46 moved it here
/// out of `ConflictPanelView` unchanged.
/// components.md §14.3 (amended 2026-10-05, closes G-038 (1)) — how an option
/// row is drawn, as token names so a test can check it without comparing
/// `Color`s. A focused row is a tinted CARD: `selectedCardFill` plus a
/// `size.borderSelected` inner border in `focusRing` at `radius.card`, the
/// border carrying selection. Text colours never change. Solid
/// `selectedRowFill` is barred here: line 2 measured 1.41:1 on it.
struct ConflictOptionRowStyle: Equatable, Sendable {
    enum Fill: Equatable, Sendable { case canvasSunken, selectedCardFill }
    enum TextColor: Equatable, Sendable { case primary, secondary }

    var fill: Fill
    /// The inner border's width, or `nil` for none. Its colour is always
    /// `interactive.focusRing`.
    var borderWidth: CGFloat?
    var titleColor: TextColor
    var deltaColor: TextColor

    static func resolve(isFocused: Bool) -> ConflictOptionRowStyle {
        ConflictOptionRowStyle(
            fill: isFocused ? .selectedCardFill : .canvasSunken,
            borderWidth: isFocused ? Tokens.Size.borderSelected : nil,
            titleColor: .primary,
            deltaColor: .secondary)
    }
}

extension ConflictOptionRowStyle.Fill {
    var color: Color {
        switch self {
        case .canvasSunken: Tokens.Color.Surface.canvasSunken
        case .selectedCardFill: Tokens.Color.Interactive.selectedCardFill
        }
    }
}

extension ConflictOptionRowStyle.TextColor {
    var color: Color {
        switch self {
        case .primary: Tokens.Color.Text.primary
        case .secondary: Tokens.Color.Text.secondary
        }
    }
}

struct ConflictOptionRowView: View {
    let title: String
    let delta: String
    let isRecommended: Bool
    let isSelected: Bool
    let action: () -> Void

    private var style: ConflictOptionRowStyle { .resolve(isFocused: isSelected) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                HStack(alignment: .top, spacing: Tokens.Spacing.sm) {
                    Text(title)
                        .typeStyle(.conflictOptionTitle)
                        .foregroundStyle(style.titleColor.color)
                    Spacer(minLength: Tokens.Spacing.sm)
                    if isRecommended {
                        recommendedChip
                    }
                }
                Text(delta)
                    .typeStyle(.conflictOptionDelta)
                    .foregroundStyle(style.deltaColor.color)
            }
            .padding(Tokens.Spacing.sm)
            .frame(minHeight: Tokens.Size.conflictOptionRowMinHeight, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(style.fill.color))
            .overlay {
                // INNER border (`strokeBorder` strokes inside the shape), so
                // the 2pt never bleeds into the `conflictOptionGap`.
                if let width = style.borderWidth {
                    shape.strokeBorder(Tokens.Color.Interactive.focusRing, lineWidth: width)
                }
            }
            .contentShape(shape)
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
