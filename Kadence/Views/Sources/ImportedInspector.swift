//
//  ImportedInspector.swift
//  Kadence
//
//  PHASE3-PLAN.md task 16 — layouts.md §6.1 (the inspector for an imported
//  event), interactions.md §13.4 (refusals), §13.5 (undo), components.md
//  §18.1, §18.3.
//

import SwiftUI
import SwiftData
import AppKit

// MARK: - Refusals (interactions.md §13.4)

/// Whether a gesture on an event may proceed. Pure.
nonisolated enum ReadOnlyGate {
    enum Gesture: Equatable, Sendable {
        case drag, duplicateDrag, delete, moveKey, resizeKey, doubleClick, done, skip, snooze
    }

    enum Decision: Equatable, Sendable {
        case allow
        /// (a) the system sound for keyboard and menu gestures, (b) the
        /// inspector's read-only line emphasised — always.
        case refuse(sound: Bool)
    }

    static func decide(_ gesture: Gesture, origin: EventOrigin, isCancelled: Bool) -> Decision {
        guard origin == .imported else { return .allow }
        switch gesture {
        case .done, .skip:
            // §18.1: status is local — allowed, except on a cancelled event.
            return isCancelled ? .refuse(sound: true) : .allow
        case .drag, .duplicateDrag, .doubleClick:
            return .refuse(sound: false)   // pointer gestures use the cursor
        case .delete, .moveKey, .resizeKey, .snooze:
            return .refuse(sound: true)
        }
    }
}

// MARK: - The inspector's rows (layouts.md §6.1), pure

@MainActor
enum ImportedInspectorCopy {
    /// Row 2: `Read-only — from University timetable`, or for a cancelled
    /// event `Cancelled by University timetable` (§20.6).
    static func readOnlyLine(sourceName: String, isCancelled: Bool) -> String {
        isCancelled ? "Cancelled by \(sourceName)" : "Read-only — from \(sourceName)"
    }

    /// Row 4: `Lecturer` for one name, `Lecturers` for more.
    static func lecturersLabel(_ names: [String]) -> String { names.count == 1 ? "Lecturer" : "Lecturers" }

    /// Up to `size.inspectorLecturersMaxRows` (4) names never collapse; above,
    /// the first three and `and {n} more`; expanded, every name and `Show fewer`.
    static func lecturerLines(_ names: [String], expanded: Bool) -> (names: [String], button: String?) {
        let max = Tokens.Size.inspectorLecturersMaxRows
        guard names.count > max else { return (names, nil) }
        if expanded { return (names, "Show fewer") }
        return (Array(names.prefix(max - 1)), "and \(names.count - (max - 1)) more")
    }

    /// The row's VoiceOver value: every name, collapsed or not.
    static func lecturersAccessibilityValue(_ names: [String]) -> String {
        "\(names.count) \(names.count == 1 ? "lecturer" : "lecturers"): " + names.joined(separator: ", ")
    }

    static func lecturersButtonAccessibility(_ count: Int, expanded: Bool) -> String {
        expanded ? "Show fewer lecturers" : "Show all \(count) lecturers"
    }

    /// Row 6: `Room` for CIS events, `Location` for others.
    static func locationLabel(isCISProfile: Bool) -> String { isCISProfile ? "Room" : "Location" }

    /// `Online · WEBINAR02` — the word first, then the code.
    static func locationValue(_ location: String, isOnline: Bool) -> String { isOnline ? "Online · \(location)" : location }

    /// Row 7's second line: `Synced 14:02`, or the state title.
    @MainActor
    static func syncLine(_ source: Source?, now: Date, isSyncing: Bool = false) -> String? {
        guard let source, source.isConnected else { return nil }
        let state: SourceState = isSyncing ? .syncing : source.state
        if state == .upToDate, let last = source.lastSuccessAt { return "Synced \(SourceStatusCopy.synced(last, now: now))" }
        return SourceStatusCopy.title(state, host: source.host ?? "")
    }

    /// Row 10: the URL's host.
    static func linkTitle(_ link: String) -> String? {
        guard let url = URL(string: link), let host = url.host() else { return nil }
        return host
    }
}

/// Opens links (NSWorkspace in the app; stubbed in tests).
@MainActor
enum LinkOpener {
    static var open: (URL) -> Void = { NSWorkspace.shared.open($0) }
}

// MARK: - The view

struct ImportedInspectorDetails: View {
    let event: Event
    let now: Date
    let store: EventStore
    @Environment(CalendarState.self) private var state
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var sources: [Source]
    @State private var expandedFor: UUID?
    @State private var isSourcePopoverShown = false

    private var source: Source? { sources.first { $0.id == event.sourceID } }
    private var sourceName: String { source?.displayName ?? SourceCatalog.name(for: event.sourceKey) }

    var body: some View {
        let model = GridBlockModel(event: event, now: now)
        let emphasised = state.readOnlyEmphasis
        VStack(alignment: .leading, spacing: Tokens.Spacing.xl) {
            // 1–2: the title as text, and the read-only line.
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.sm) {
                    Image(systemName: model.glyphOverride ?? "building.columns")
                        .foregroundStyle(event.sourceKey.text)
                    SourceSwatch(key: event.sourceKey, symbol: SourceCatalog.symbol(for: event.sourceKey), isOn: true)
                    Text(event.title)
                        .lineLimit(3)
                        .typeStyle(.inspectorTitle)
                        .foregroundStyle(Tokens.Color.Text.primary)
                        .textSelection(.enabled)
                }
                Text(ImportedInspectorCopy.readOnlyLine(sourceName: sourceName, isCancelled: event.isCancelled))
                    .typeStyle(.inspectorLabel)
                    .foregroundStyle(emphasised ? Tokens.Color.Text.primary : Tokens.Color.Text.secondary)
                    .animation(reduceMotion ? nil : .easeInOut(duration: Tokens.Motion.Selection.duration),
                               value: emphasised)
                    .accessibilityIdentifier("read-only-line")
            }

            // 3: time, as text.
            if event.isAllDay {
                field("Starts", "All day")
            } else {
                field("Starts", BlockFormatters.time.string(from: event.start))
                field("Ends", BlockFormatters.time.string(from: event.end))
                field("Duration", Self.durationText(event.duration))
            }

            // 4: lecturers.
            if !event.lecturers.isEmpty { lecturersRow }
            // 5: group.
            if let group = event.group, !group.isEmpty { field("Group", group) }
            // 6: room / location.
            if let location = event.location?.name, !location.isEmpty {
                field(ImportedInspectorCopy.locationLabel(isCISProfile: event.courseCode != nil),
                      ImportedInspectorCopy.locationValue(location, isOnline: event.isOnline))
            }
            // 7: source + sync line; origin.
            sourceRow
            field("Origin", "Imported")

            // 8: status — local; refused on a cancelled event.
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                label("Status")
                HStack(spacing: Tokens.Spacing.sm) {
                    Button(event.status == .done ? "Not done" : "Done") { store.toggleDone(event) }
                    Button(event.status == .skipped ? "Unskip" : "Skip") { store.toggleSkipped(event) }
                }
                .disabled(event.isCancelled)
            }

            // 9: description (never `notes`).
            if let description = event.importedDescription, !description.isEmpty {
                VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                    label("Description")
                    Text(description)
                        .lineLimit(nil)
                        .typeStyle(.inspectorValue)
                        .foregroundStyle(Tokens.Color.Text.primary)
                        .textSelection(.enabled)
                }
            }
            // 10: link.
            if let link = event.link, let title = ImportedInspectorCopy.linkTitle(link), let url = URL(string: link) {
                HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.md) {
                    label("Link")
                    Button(title) { LinkOpener.open(url) }
                        .buttonStyle(.link)
                        .typeStyle(.inspectorValue)
                        .foregroundStyle(Tokens.Color.Interactive.link)
                    Spacer(minLength: 0)
                }
            }
        }
        .onChange(of: event.id) { _, _ in expandedFor = nil }
    }

    private var lecturersRow: some View {
        let names = event.lecturers
        let expanded = expandedFor == event.id
        let lines = ImportedInspectorCopy.lecturerLines(names, expanded: expanded)
        return HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.md) {
            label(ImportedInspectorCopy.lecturersLabel(names))
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                ForEach(Array(lines.names.enumerated()), id: \.offset) { _, name in
                    Text(name).lineLimit(2).typeStyle(.inspectorValue).textSelection(.enabled)
                }
                if let button = lines.button {
                    Button(button) { expandedFor = expanded ? nil : event.id }
                        .buttonStyle(.link)
                        .typeStyle(.inspectorValue)
                        .foregroundStyle(Tokens.Color.Interactive.link)
                        .accessibilityLabel(ImportedInspectorCopy.lecturersButtonAccessibility(names.count, expanded: expanded))
                }
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ImportedInspectorCopy.lecturersLabel(names) == "Lecturer" ? "Lecturer" : "Lecturers")
        .accessibilityValue(ImportedInspectorCopy.lecturersAccessibilityValue(names))
    }

    private var sourceRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.md) {
            label("Source")
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                HStack(spacing: Tokens.Spacing.sm) {
                    SourceSwatch(key: event.sourceKey, symbol: SourceCatalog.symbol(for: event.sourceKey), isOn: true)
                    Text(sourceName).typeStyle(.inspectorValue).foregroundStyle(Tokens.Color.Text.primary)
                }
                if let line = ImportedInspectorCopy.syncLine(source, now: now, isSyncing: source.map(sync.isSyncing) ?? false),
                   let source {
                    Button(line) { isSourcePopoverShown = true }
                        .buttonStyle(.plain)
                        .typeStyle(.blockMeta)
                        .foregroundStyle(Tokens.Color.Text.secondary)
                        .popover(isPresented: $isSourcePopoverShown, arrowEdge: .leading) {
                            SourcePopover(source: source, dismiss: { isSourcePopoverShown = false })
                        }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private func field(_ name: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.md) {
            label(name)
            Text(value).typeStyle(.inspectorValue).foregroundStyle(Tokens.Color.Text.primary).textSelection(.enabled)
            Spacer(minLength: 0)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .typeStyle(.inspectorLabel)
            .foregroundStyle(Tokens.Color.Text.secondary)
            .frame(width: 84, alignment: .leading)
    }

    static func durationText(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        let hours = minutes / 60, remainder = minutes % 60
        if hours == 0 { return "\(remainder) min" }
        return remainder == 0 ? "\(hours) h" : "\(hours) h \(remainder) min"
    }
}
