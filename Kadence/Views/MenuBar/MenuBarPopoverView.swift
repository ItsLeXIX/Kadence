//
//  MenuBarPopoverView.swift
//  Kadence
//
//  components.md §15.2 — the menu bar extra's popover: NEXT, then REST OF
//  TODAY, at `Tokens.Size.popoverWidth`.
//
//  Scope for this task (P2-T25): `Done` and the Late state's `Re-offer` are
//  wired to real `EventStore` verbs. `Snooze` and `Open` render per §15.2's
//  action-row shape but are disabled/inert — their behaviour (components.md
//  §16, and bringing the main window forward) is explicitly a later task.
//  Neither wired action closes the popover (interactions.md §12): both just
//  let the next `NextUpProvider.evaluate` pass (driven by SwiftData's own
//  change notification through `@Query`) recompute NEXT/REST OF TODAY, so
//  the resolved item simply drops out — not the in-place result-row swap
//  §16 specifies for Snooze, which is out of scope here.
//

import SwiftUI
import SwiftData
import Combine

struct MenuBarPopoverView: View {
    @Environment(\.modelContext) private var context
    @Environment(UndoStack.self) private var undoStack
    @Query(sort: \Event.start) private var events: [Event]
    @State private var now = Date()

    private var store: EventStore { EventStore(context: context, undo: undoStack) }

    private var result: NextUpProvider.Result {
        NextUpProvider.evaluate(events: events, now: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let next = result.next {
                nextSection(next: next, isLate: result.isLate)
                let rest = NextUpProvider.restDisplay(result.restOfToday)
                if !rest.rows.isEmpty {
                    Divider()
                    restSection(rest)
                }
            } else {
                emptySection
            }
        }
        .padding(.vertical, Tokens.Spacing.md)
        .frame(width: Tokens.Size.popoverWidth, alignment: .leading)
        .background(Tokens.Color.Surface.popover)
        .onReceive(
            Timer.publish(every: Tokens.Motion.NowLineTick.interval, on: .main, in: .common).autoconnect()
        ) { date in
            now = date
        }
    }

    // MARK: NEXT

    @ViewBuilder
    private func nextSection(next: Event, isLate: Bool) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            sectionLabel("NEXT")

            HStack(spacing: 0) {
                RailView(style: .solid, color: next.sourceKey.rail)
                VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                    Text(next.title)
                        .typeStyle(.popoverNextTitle)
                        .foregroundStyle(Tokens.Color.Text.primary)
                    Text(MenuBarFormatting.nextMeta(for: next, now: now, isLate: isLate))
                        .typeStyle(.popoverNextMeta)
                        .foregroundStyle(isLate ? Tokens.Color.Semantic.now : Tokens.Color.Text.secondary)
                }
                .padding(.leading, Tokens.Spacing.sm)
            }
            .frame(minHeight: Tokens.Size.popoverNextBlockMinHeight, alignment: .leading)

            actionRow(next: next, isLate: isLate)
        }
        .padding(.horizontal, Tokens.Spacing.lg)
    }

    @ViewBuilder
    private func actionRow(next: Event, isLate: Bool) -> some View {
        HStack(spacing: Tokens.Spacing.sm) {
            // §15.2 — "the late popover always offers Re-offer ... the
            // primary action in that state," leading the row.
            if isLate {
                Button("Re-offer") { store.markSkipped(next) }
            }
            Button("Done") { store.toggleDone(next) }
            // Disabled/inert per this task's own scope — see the file header.
            Button("Snooze") {}
                .disabled(true)
            Button("Open") {}
                .disabled(true)
        }
        .frame(height: Tokens.Size.popoverActionRowHeight)
    }

    // MARK: REST OF TODAY

    @ViewBuilder
    private func restSection(_ rest: NextUpProvider.RestDisplay) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            sectionLabel("REST OF TODAY")
                .padding(.top, Tokens.Spacing.sm)

            // §15.2: "Times are monospaced and left-aligned in a fixed
            // column so the list scans vertically." `design/` names no pixel
            // width for that column, so rather than invent one, `Grid` sizes
            // the time column to its own widest cell — every time in this
            // list is 5 monospaced-digit characters (`HH:mm`), so every row
            // already lines up, with no literal number to get wrong or to
            // have to defend later.
            Grid(alignment: .leading, horizontalSpacing: Tokens.Spacing.sm, verticalSpacing: 0) {
                ForEach(rest.rows, id: \.id) { event in
                    GridRow {
                        Text(MenuBarFormatting.time(event.start))
                            .typeStyle(.popoverRow)
                            .foregroundStyle(Tokens.Color.Text.primary)
                            .frame(height: Tokens.Size.popoverRestRowHeight, alignment: .leading)
                        Text(event.title)
                            .typeStyle(.popoverRow)
                            .foregroundStyle(Tokens.Color.Text.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(height: Tokens.Size.popoverRestRowHeight, alignment: .leading)
                    }
                }
            }

            if rest.moreCount > 0 {
                Text("+\(rest.moreCount) more")
                    .typeStyle(.popoverRow)
                    .foregroundStyle(Tokens.Color.Text.secondary)
                    .frame(height: Tokens.Size.popoverRestRowHeight, alignment: .leading)
            }
        }
        .padding(.horizontal, Tokens.Spacing.lg)
    }

    // MARK: Empty

    private var emptySection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            sectionLabel("NEXT")
            Text("Nothing left today")
                .typeStyle(.popoverNextTitle)
                .foregroundStyle(Tokens.Color.Text.secondary)
                .frame(minHeight: Tokens.Size.popoverNextBlockMinHeight, alignment: .leading)
        }
        .padding(.horizontal, Tokens.Spacing.lg)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .typeStyle(.popoverSectionLabel)
            .foregroundStyle(Tokens.Color.Text.secondary)
    }
}
