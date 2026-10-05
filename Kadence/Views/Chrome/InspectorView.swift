//
//  InspectorView.swift
//  Kadence
//
//  layouts.md §6. Empty selection shows the day's summary, never a
//  "nothing selected" placeholder graphic.
//

import SwiftUI
import SwiftData

struct InspectorView: View {
    let event: Event?
    let dayEvents: [Event]
    let day: Date
    let travel: TravelFixture?
    let now: Date
    let store: EventStore
    /// components.md §14.1 — non-nil puts the inspector into "conflict
    /// mode", which takes over from the ordinary event-details/day-summary
    /// content below entirely. `nil` (the default) is every existing caller
    /// and every existing test — Phase 1 behaviour is unchanged.
    var conflict: Conflict? = nil
    var selectedConflictOptionID: UUID? = nil
    var onSelectConflictOption: (UUID) -> Void = { _ in }
    /// components.md §13.4 / §13.6.4 (task P2-T43): the selected routine
    /// instance's relation to its template. `nil` hides the line.
    var routineStatus: RoutineInstance.Status? = nil
    var onRevertToRoutine: () -> Void = {}

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xl) {
                if let conflict {
                    ConflictPanelView(
                        conflict: conflict,
                        now: now,
                        selectedOptionID: selectedConflictOptionID,
                        onSelectOption: onSelectConflictOption)
                } else if let event {
                    details(for: event)
                } else {
                    daySummary
                }
            }
            .padding(Tokens.Spacing.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Tokens.Color.Surface.inspector)
    }

    // MARK: Selected item

    @ViewBuilder
    private func details(for event: Event) -> some View {
        let model = GridBlockModel(event: event, now: now)

        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.sm) {
            Image(systemName: model.glyphOverride ?? "calendar")
                .foregroundStyle(event.sourceKey.text)
            SourceSwatch(
                key: event.sourceKey,
                symbol: SourceCatalog.symbol(for: event.sourceKey),
                isOn: true)
            Text(event.title)
                .typeStyle(.inspectorTitle)
                .foregroundStyle(Tokens.Color.Text.primary)
        }

        field("Starts", BlockFormatters.time.string(from: event.start))
        field("Ends", BlockFormatters.time.string(from: event.end))
        field("Duration", durationText(event.duration))

        if let location = event.location?.name {
            field("Location", location)
            if let travel {
                field("Travel", "Leave \(BlockFormatters.time.string(from: travel.departAt)) · \(Int(travel.duration / 60)) min \(travel.mode.label)")
            }
        }

        field("Source", event.sourceKey.displayName)
        field("Origin", event.origin.rawValue)

        // §13.4: "one line, `inspectorLabel` / `inspectorValue`, reading
        // `Edited — differs from Gym routine`, with a `Revert to routine`
        // action." Detachment is never a block signal; this line is the only
        // place the main window shows it.
        if let routineStatus {
            routineStatusLine(routineStatus)
        }

        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            label("Status")
            HStack(spacing: Tokens.Spacing.sm) {
                Button(event.status == .done ? "Not done" : "Done") { store.toggleDone(event) }
                Button(event.status == .skipped ? "Unskip" : "Skip") { store.toggleSkipped(event) }
            }
            if !event.isMovable {
                // interactions.md §4 — no alert, no shake, no dialog.
                Text(event.isLocked ? "Locked — cannot be moved." : "Imported — cannot be moved here.")
                    .typeStyle(.blockMeta)
                    .foregroundStyle(Tokens.Color.Text.secondary)
            }
        }

        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            label("Notes")
            TextEditor(text: Binding(
                get: { event.notes },
                set: { store.setNotes(event, to: $0) }))
                .typeStyle(.inspectorValue)
                .frame(minHeight: 80)
                .scrollContentBackground(.hidden)
                .background(Tokens.Color.Surface.canvas)
                .clipShape(RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous))
        }
    }

    @ViewBuilder
    private func routineStatusLine(_ status: RoutineInstance.Status) -> some View {
        switch status {
        case .edited(let name):
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                // Split at the dash, the same way the Routines inspector's
                // `Will not run —` line is (DEVIATIONS.md C, P2-T40).
                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(RoutineInstance.editedLabel + " ")
                        .typeStyle(.inspectorLabel)
                        .foregroundStyle(Tokens.Color.Text.secondary)
                    Text(RoutineInstance.editedValue(routineName: name))
                        .typeStyle(.inspectorValue)
                        .foregroundStyle(Tokens.Color.Text.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .combine)
                // A native button, like the Done/Skip buttons above it.
                Button(RoutineInstance.revertActionTitle, action: onRevertToRoutine)
            }
        case .released(let name):
            // §13.6.4: no `Revert to routine`, "because there is nothing to
            // revert to". One `inspectorValue` run: the sentence has no dash
            // to split a label off at.
            Text(RoutineInstance.releasedLine(routineName: name))
                .typeStyle(.inspectorValue)
                .foregroundStyle(Tokens.Color.Text.primary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Empty selection

    @ViewBuilder
    private var daySummary: some View {
        let timed = dayEvents.filter { !$0.isAllDay }.sorted { $0.start < $1.start }
        let hours = timed.reduce(0) { $0 + $1.duration } / 3600

        Text(dayFormatter.string(from: day))
            .typeStyle(.inspectorTitle)
            .foregroundStyle(Tokens.Color.Text.primary)
        field("Blocks", "\(timed.count)")
        field("Scheduled", String(format: "%.1f h", hours))
        if let first = timed.first {
            field("First", "\(BlockFormatters.time.string(from: first.start)) · \(first.title)")
        } else {
            field("First", "Nothing scheduled")
        }
    }

    // MARK: Building blocks

    private func field(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.md) {
            label(name)
            Text(value)
                .typeStyle(.inspectorValue)
                .foregroundStyle(Tokens.Color.Text.primary)
            Spacer(minLength: 0)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .typeStyle(.inspectorLabel)
            .foregroundStyle(Tokens.Color.Text.secondary)
            .frame(width: 84, alignment: .leading)
    }

    private func durationText(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        let hours = minutes / 60
        let remainder = minutes % 60
        if hours == 0 { return "\(remainder) min" }
        return remainder == 0 ? "\(hours) h" : "\(hours) h \(remainder) min"
    }

    private var dayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }
}
