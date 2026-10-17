//
//  MoodleInspector.swift
//  Kadence
//
//  Phase 3 slice 3 (PHASE3-SLICE3-PLAN.md task 12) — layouts.md §17, the
//  inspector for a Moodle item; components.md §37.4 (what the rows say),
//  §38 (the Status row). §6.1's geometry, label column (84) and row styles;
//  rows with no value are not drawn. No Location, Place, Leave by,
//  Lecturers, Group, Room or Link row; no editable Notes.
//

import SwiftUI
import SwiftData
import AppKit

// MARK: - Copy and measurement (pure, tested)

@MainActor
enum MoodleInspectorCopy {
    /// layouts.md §17 row 9.
    static let statusNote = "Your own mark — Moodle doesn't say what you've handed in."
    static func statusValue(isDone: Bool) -> String { isDone ? "Done" : "Not done" }
    static func statusButton(isDone: Bool) -> String { isDone ? "Mark Not Done" : "Mark Done" }
    static func descriptionButton(expanded: Bool) -> String { expanded ? "Show less" : "Show more" }
    static func descriptionButtonAccessibility(expanded: Bool) -> String {
        expanded ? "Show less of the description" : "Show more of the description"
    }

    /// The description's rendered line count at `width` in `inspectorValue`.
    static func renderedLines(_ text: String, width: CGFloat) -> Int {
        guard width > 0 else { return 0 }
        let font = NSFont.systemFont(ofSize: Tokens.Typography.InspectorValue.size)
        let rect = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font])
        let line = NSLayoutManager().defaultLineHeight(for: font)
        return Int((rect.height / line).rounded())
    }

    /// More than `size.inspectorDescriptionMaxLines` (6) rendered lines are
    /// collapsed (layouts.md §17 row 10).
    static func isCollapsible(_ text: String, width: CGFloat) -> Bool {
        renderedLines(text, width: width) > Tokens.Size.inspectorDescriptionMaxLines
    }

    /// The description with every `http://` / `https://` URL a link.
    static func linked(_ text: String) -> AttributedString {
        var out = AttributedString(text)
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return out }
        let ns = text as NSString
        for match in detector.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let url = match.url, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                  let range = Range(match.range, in: text),
                  let lower = AttributedString.Index(range.lowerBound, within: out),
                  let upper = AttributedString.Index(range.upperBound, within: out) else { continue }
            out[lower..<upper].link = url
            out[lower..<upper].foregroundColor = Tokens.Color.Interactive.link
        }
        return out
    }

    /// The links in `text`, for tests.
    static func links(_ text: String) -> [URL] { linked(text).runs.compactMap(\.link) }
}

// MARK: - The view

struct MoodleInspectorDetails: View {
    let event: Event
    let now: Date
    let store: EventStore
    @Environment(CalendarState.self) private var state
    @Environment(SyncCoordinator.self) private var sync
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query private var sources: [Source]
    @Query private var events: [Event]
    @State private var expandedFor: UUID?
    @State private var descriptionWidth: CGFloat = 0
    @State private var isSourcePopoverShown = false

    /// `expanded`: renders only (§43 item 15's expanded description).
    init(event: Event, now: Date, store: EventStore, expanded: Bool = false) {
        self.event = event
        self.now = now
        self.store = store
        _expandedFor = State(initialValue: expanded ? event.id : nil)
    }

    private var source: Source? { sources.first { $0.id == event.sourceID } }
    private var sourceModel: InspectorSourceModel { InspectorSourceModel(event: event) }

    /// §36: the paired opening, from the source's own items.
    private var opening: MomentItem? {
        guard let item = MomentItem(event) else { return nil }
        let pool = events.filter { $0.sourceID == event.sourceID }.compactMap(MomentItem.init)
        return MoodlePairing.pairs(pool).opening(of: item)
    }

    /// §35.5: every timetable course code, from any connected timetable.
    private var timetableCodes: [String] {
        let timetables = Set(sources.filter { $0.connection == .caldav }.map(\.id))
        return events.filter { $0.sourceID.map(timetables.contains) == true }.compactMap(\.courseCode)
    }

    private var values: MomentInspectorValues? {
        MomentItem(event).map {
            MomentInspectorValues($0, opening: opening, sourceName: sourceModel.name, timetableCodes: timetableCodes,
                                  zone: .current)
        }
    }

    var body: some View {
        if let values {
            let emphasised = state.readOnlyEmphasis
            VStack(alignment: .leading, spacing: Tokens.Spacing.xl) {
                // 1–2: title row and the read-only line.
                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.sm) {
                        Image(systemName: values.glyph).foregroundStyle(sourceModel.key.text)
                        SourceSwatch(key: sourceModel.key, symbol: sourceModel.symbol, isOn: true)
                        Text(values.title)
                            .lineLimit(3)
                            .typeStyle(.inspectorTitle)
                            .foregroundStyle(Tokens.Color.Text.primary)
                            .textSelection(.enabled)
                    }
                    Text(values.readOnlyLine)
                        .typeStyle(.inspectorLabel)
                        .foregroundStyle(emphasised ? Tokens.Color.Text.primary : Tokens.Color.Text.secondary)
                        .animation(reduceMotion ? nil : .easeInOut(duration: Tokens.Motion.Selection.duration),
                                   value: emphasised)
                        .accessibilityIdentifier("read-only-line")
                }
                // 3: the moment (a notice's line under it).
                VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                    row(values.moment, monospaced: true)
                    if let notice = values.noticeLine { secondary(notice).padding(.leading, 84 + Tokens.Spacing.md) }
                }
                // 4–7.
                if let opens = values.opens { row(opens, monospaced: true) }
                if let course = values.course { row(course) }
                if let timetable = values.inTimetable { row(timetable, selectable: false) }
                if let raw = values.inMoodle { row(raw) }
                // 8: source and origin.
                sourceRow
                row(.init(label: "Origin", value: values.origin), selectable: false)
                // 9: status, deadlines only. No Skip.
                if values.hasStatus { statusRow(values) }
                // 10: description.
                if let description = values.description { descriptionRow(description) }
            }
            .onChange(of: event.id) { _, _ in expandedFor = nil }
        }
    }

    private func statusRow(_ values: MomentInspectorValues) -> some View {
        let isDone = event.status == .done
        return HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.md) {
            label("Status")
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                HStack(spacing: Tokens.Spacing.sm) {
                    Text(MoodleInspectorCopy.statusValue(isDone: isDone))
                        .typeStyle(.inspectorValue)
                        .foregroundStyle(Tokens.Color.Text.primary)
                    Button(MoodleInspectorCopy.statusButton(isDone: isDone)) {
                        if state.permits(.done, on: event) { store.toggleDone(event) }
                    }
                    .buttonStyle(.bordered)
                }
                if let moved = values.movedLine {
                    Text(moved)
                        .lineLimit(nil)
                        .typeStyle(.blockMeta)
                        .foregroundStyle(Tokens.Color.Text.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                secondary(MoodleInspectorCopy.statusNote)
            }
            Spacer(minLength: 0)
        }
    }

    private func descriptionRow(_ text: String) -> some View {
        let expanded = expandedFor == event.id
        let collapsible = MoodleInspectorCopy.isCollapsible(text, width: descriptionWidth)
        return VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            label("Description")
            Text(MoodleInspectorCopy.linked(text))
                .lineLimit(collapsible && !expanded ? Tokens.Size.inspectorDescriptionMaxLines : nil)
                .typeStyle(.inspectorValue)
                .foregroundStyle(Tokens.Color.Text.primary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { descriptionWidth = $0 }
                .environment(\.openURL, OpenURLAction { url in LinkOpener.open(url); return .handled })
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Description")
                .accessibilityValue(text)
            if collapsible {
                Button(MoodleInspectorCopy.descriptionButton(expanded: expanded)) {
                    expandedFor = expanded ? nil : event.id
                }
                .buttonStyle(.link)
                .typeStyle(.inspectorValue)
                .foregroundStyle(Tokens.Color.Interactive.link)
                .accessibilityLabel(MoodleInspectorCopy.descriptionButtonAccessibility(expanded: expanded))
            }
        }
    }

    private var sourceRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.md) {
            label("Source")
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                HStack(spacing: Tokens.Spacing.sm) {
                    SourceSwatch(key: sourceModel.key, symbol: sourceModel.symbol, isOn: true)
                    Text(sourceModel.name).typeStyle(.inspectorValue).foregroundStyle(Tokens.Color.Text.primary)
                }
                if let source, let line = ImportedInspectorCopy.syncLine(source, now: now, isSyncing: sync.isSyncing(source)) {
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

    private func row(_ row: MomentInspectorValues.Row, monospaced: Bool = false, selectable: Bool = true) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.md) {
            label(row.label)
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                Group {
                    if selectable {
                        Text(row.value).textSelection(.enabled)
                    } else {
                        Text(row.value)
                    }
                }
                .lineLimit(nil)
                .typeStyle(.inspectorValue)
                .monospacedDigit()
                .foregroundStyle(Tokens.Color.Text.primary)
                .fixedSize(horizontal: false, vertical: true)
                if let second = row.secondLine { secondary(second) }
            }
            Spacer(minLength: 0)
        }
    }

    private func secondary(_ text: String) -> some View {
        Text(text)
            .lineLimit(nil)
            .typeStyle(.blockMeta)
            .foregroundStyle(Tokens.Color.Text.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .typeStyle(.inspectorLabel)
            .foregroundStyle(Tokens.Color.Text.secondary)
            .frame(width: 84, alignment: .leading)
    }
}
