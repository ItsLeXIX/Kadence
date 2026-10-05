//
//  TemplateConflictPanelView.swift
//  Kadence
//
//  components.md §14.6 (task P2-T46): the editor inspector's conflict mode
//  for a routine block a protected window refuses. "It uses the same panel,
//  with three differences and no new components":
//
//  - The collision header is §14.2's amended form: the routine block as a
//    real block above, the **window row** below, `lands in` between them, and
//    the overlap line naming the weekdays.
//  - The options are template-level (`TemplateConflictEngine`), in the same
//    row geometry with the same chip (`ConflictOptionRowView`).
//  - It lives in the Routines window, never the main one.
//

import SwiftUI

struct TemplateConflictPanelView: View {
    let conflict: TemplateConflict
    let template: RoutineTemplate?
    let selectedOptionID: String?
    let onSelectOption: (String) -> Void

    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xl) {
            header
            VStack(spacing: Tokens.Size.conflictOptionGap) {
                ForEach(conflict.options) { option in
                    ConflictOptionRowView(
                        title: TemplateConflictEngine.title(for: option, conflict: conflict),
                        delta: TemplateConflictEngine.delta(for: option, conflict: conflict),
                        isRecommended: option.isRecommended,
                        isSelected: option.id == selectedOptionID,
                        action: { onSelectOption(option.id) })
                }
            }
        }
    }

    // MARK: §14.2 (amended) — block, `lands in`, window row

    private var header: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            VStack(spacing: Tokens.Spacing.xs) {
                GridBlockView(
                    model: blockModel,
                    presentation: [.conflicted],
                    renderedHeight: ConflictPanelView.collisionBlockHeight)
                    .frame(maxWidth: .infinity)
                Text(TemplateConflictEngine.landsIn)
                    .typeStyle(.inspectorLabel)
                    .foregroundStyle(Tokens.Color.Text.secondary)
                windowRow
            }
            Text(TemplateConflictEngine.overlapLine(conflict))
                .typeStyle(.blockMeta)
                .foregroundStyle(Tokens.Color.Text.primary)
        }
    }

    /// The routine block, drawn the way the Routines canvas draws it.
    private var blockModel: GridBlockModel {
        let start = RoutineWeekLayout.referenceDayStart(weekday: conflict.weekdays.first ?? 2, now: Date())
            .addingTimeInterval(TimeInterval(conflict.blockStartMinutes * 60))
        return GridBlockModel(
            id: conflict.blockID, title: conflict.blockTitle,
            start: start, end: start.addingTimeInterval(TimeInterval(conflict.durationMinutes * 60)),
            locationName: nil, kind: .routineTimed,
            flexibility: template?.blocks.first { $0.id == conflict.blockID }?.flexibility ?? .fixed,
            status: .scheduled, source: template?.sourceKey ?? .graphite,
            sourceName: template?.name ?? "Routine", glyphOverride: nil, isMovable: false,
            conflicts: [.protectedWindow(label: conflict.windowLabel)])
    }

    /// §14.2: "full panel width, the same height the 16–27 tier gives the
    /// block above it, filled with the window's own §7 treatment —
    /// `color.window.protectedFill` with its `color.window.protectedEdge`
    /// lines at top and bottom — carrying two labels … No hue, no rail, no
    /// glyph, no corner radius." Increase Contrast takes §7's four-sided
    /// `protectedEdgeHC`, exactly as `BackgroundWindowsLayer` does.
    private var windowRow: some View {
        ZStack {
            Rectangle().fill(Tokens.Color.Window.protectedFill)
            if contrast == .increased {
                Rectangle().strokeBorder(Tokens.Color.Window.protectedEdgeHC, lineWidth: 1)
            } else {
                VStack {
                    Rectangle().fill(Tokens.Color.Window.protectedEdge).frame(height: 1)
                    Spacer(minLength: 0)
                    Rectangle().fill(Tokens.Color.Window.protectedEdge).frame(height: 1)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.sm) {
                Text(conflict.windowLabel)
                    .typeStyle(.windowLabel)
                    .foregroundStyle(Tokens.Color.Window.label)
                Text(TemplateConflictEngine.windowLine(conflict))
                    .typeStyle(.blockMeta)
                    .foregroundStyle(Tokens.Color.Text.secondary)
                Spacer(minLength: 0)
            }
            // SPEC-GAP (design/GAPS.md G-036): §14.2 gives the row's fill,
            // edges and two labels but not their inset or spacing; the
            // block's own `size.blockPadding` / `spacing.sm` are used.
            .padding(.horizontal, Tokens.Size.blockPadding)
        }
        .frame(maxWidth: .infinity)
        .frame(height: ConflictPanelView.collisionBlockHeight)
        .accessibilityElement(children: .combine)
    }
}
