//
//  SourceRows.swift
//  Kadence
//
//  PHASE3-PLAN.md task 14 — layouts.md §2.1 (source rows with a connection,
//  the context menu, ↩, the first-run row), components.md §19.2 (the status
//  slot, hover help, VoiceOver value), §19.3 (the source popover), §19.4
//  (the menu bar popover's stale line).
//

import SwiftUI
import SwiftData
import AppKit

// MARK: - What a state's buttons do (pure, tested)

/// components.md §19.1's primary actions and §19.3's `Settings…`, as effects.
@MainActor
enum SourceActionRouting {
    struct Effect: Equatable {
        var sheet: SourcesRouter.Sheet?
        var opensSettings = false
        var syncsNow = false
        var togglesDetails = false
    }

    /// `fromPopover`: a state's own action (popover, sidebar) — `Edit
    /// Account…` focuses `Server`; from Settings' form it focuses `Password`
    /// (layouts.md §12.3's focus table).
    static func effect(of action: PrimaryAction, sourceID: String, fromPopover: Bool) -> Effect {
        switch action {
        case .syncNow:
            return Effect(syncsNow: true)
        case .showDetails:
            return Effect(togglesDetails: true)
        case .updatePassword:
            return Effect(sheet: .edit(sourceID: sourceID, focus: .password, autoConnect: false), opensSettings: fromPopover)
        case .editAccount:
            return Effect(sheet: .edit(sourceID: sourceID, focus: fromPopover ? .server : .password, autoConnect: false),
                          opensSettings: fromPopover)
        case .chooseCalendar:
            return Effect(sheet: .edit(sourceID: sourceID, focus: .none, autoConnect: true), opensSettings: fromPopover)
        case .replaceURL:
            return Effect(sheet: .replaceMoodle(sourceID: sourceID), opensSettings: fromPopover)
        }
    }

    /// `Settings…`: Settings ▸ Sources with this source selected.
    static func settings(sourceID: String) -> Effect { Effect(opensSettings: true) }
}

/// layouts.md §2.1's first-run rule: the `Connect Timetable…` row exists only
/// while no connected source does.
nonisolated enum SidebarSourcesRule {
    static func showsConnectRow(connectedCount: Int) -> Bool { connectedCount == 0 }

    /// layouts.md §2.1 (amended 2026-10-16): each row disappears on its own
    /// condition — `Connect Timetable…` once a timetable (CalDAV) source
    /// exists, `Connect Moodle…` once a Moodle source does.
    static func showsConnectTimetableRow(_ connections: [SourceConnection]) -> Bool { !connections.contains(.caldav) }
    static func showsConnectMoodleRow(_ connections: [SourceConnection]) -> Bool { !connections.contains(.icsFeed) }

    /// components.md §10.2: the Needs attention row is hidden entirely at
    /// zero — no empty-state counter, no zero badge.
    static func showsNeedsAttentionRow(count: Int) -> Bool { count > 0 }

    /// §19.4's lines for the menu bar popover: every connected source's
    /// stale line, two at most, then `+N more sources not synced`.
    @MainActor
    static func staleLines(_ sources: [Source], now: Date) -> [String] {
        SourceStatusCopy.staleLines(sources.filter(\.isConnected).compactMap { s in
            SourceStatusCopy.staleLine(name: s.displayName, state: s.state, lastSuccess: s.lastSyncedAt,
                                       interval: TimeInterval(s.pollInterval), now: now)
        })
    }
}

// MARK: - The sidebar row

struct SidebarSourceRow: View {
    @Environment(CalendarState.self) private var state
    @Environment(SyncCoordinator.self) private var sync
    @Environment(SourcesRouter.self) private var router
    @Environment(\.openSettings) private var openSettings
    @Environment(\.modelContext) private var context
    let source: Source
    @State private var isPopoverShown = false
    @FocusState private var isFocused: Bool

    var body: some View {
        @Bindable var state = state
        let presentation = SourceStatusPresentation(source: source, now: state.now, isSyncing: sync.isSyncing(source))
        HStack(spacing: Tokens.Spacing.sm) {
            SourceSwatch(key: source.paletteKey, symbol: source.symbol, isOn: source.isVisible)
            Text(source.displayName)
                .typeStyle(.sidebarItem)
                .foregroundStyle(Tokens.Color.Text.primary)
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 0)
            // §19.2: the slot is reserved on every row so the checkboxes
            // share one column; on a connected row its glyph is a button.
            Group {
                if source.isConnected {
                    Button { isPopoverShown = true } label: {
                        // An empty slot still opens the popover (§19.3: anchored
                        // to the slot, or to the row when the slot is empty).
                        SourceStatusSlot(source: source).contentShape(Rectangle())
                    }
                        .buttonStyle(.plain)
                        .frame(minWidth: 24, minHeight: 24)   // hit target ≥ 24 × 24
                        .accessibilityLabel("Sync status")
                        .popover(isPresented: $isPopoverShown, arrowEdge: .trailing) {
                            SourcePopover(source: source, dismiss: { isPopoverShown = false })
                        }
                } else {
                    SourceStatusSlot(source: nil)
                }
            }
            .frame(width: Tokens.Size.statusSlotWidth)
            .padding(.trailing, Tokens.Spacing.xs)
            // §21.1.1 (fix 2): the checkbox writes `Source.isVisible` on this
            // row's own record, and the store keeps it across launches.
            Toggle("", isOn: Binding(
                get: { source.isVisible },
                set: { isOn in
                    source.isVisible = isOn
                    try? context.save()
                }))
                .labelsHidden()
                .toggleStyle(.checkbox)
        }
        .frame(height: 24)
        .help(source.isConnected ? presentation.hoverHelp : "")
        .accessibilityElement(children: .combine)
        // §19.2: VoiceOver reads `University timetable, Access refused`. The
        // combined row is the checkbox, whose AX value is its on/off state,
        // so the state title rides on the label (DEVIATIONS note).
        .accessibilityLabel(source.isConnected ? presentation.accessibilityValue : source.displayName)
        // layouts.md §2.1: ↩ on a focused connected row opens its popover.
        .focused($isFocused)
        .onKeyPress(.return) {
            guard source.isConnected else { return .ignored }
            isPopoverShown = true
            return .handled
        }
        .contextMenu {
            if source.isConnected {
                Button("Sync Now") { sync.trigger(.syncNow, sourceID: source.id) }
                Button("Show Sync Status") { isPopoverShown = true }
                Divider()
                // layouts.md §2.1 (amended 2026-10-16): a Moodle row adds
                // `Replace URL…`; its `Edit Source…` is Settings with the
                // source selected (no account sheet to open).
                if source.connection == .icsFeed {
                    Button("Replace URL…") {
                        router.selectedSourceID = source.id
                        router.sheet = .replaceMoodle(sourceID: source.id)
                        openSettings()
                    }
                    Button("Edit Source…") {
                        router.selectedSourceID = source.id
                        router.settingsTab = .sources
                        openSettings()
                    }
                } else {
                Button("Edit Source…") {
                    router.selectedSourceID = source.id
                    router.sheet = .edit(sourceID: source.id, focus: .name, autoConnect: false)
                    openSettings()
                }
                }
                Divider()
                Button("Remove Source…") { confirmRemoval() }
            }
        }
    }
}

/// layouts.md §2.1: first run, no connected source — a borderless
/// link-style button, accent, aligned with the source names, no swatch.
/// Slice 3: the same row for `Connect Moodle…` (`moodle`).
struct ConnectTimetableRow: View {
    @Environment(SourcesRouter.self) private var router
    @Environment(\.openSettings) private var openSettings
    var moodle = false

    var body: some View {
        Button(moodle ? "Connect Moodle…" : "Connect Timetable…") {
            router.sheet = moodle ? .connectMoodle : .connect
            openSettings()
        }
        .buttonStyle(.borderless)
        .typeStyle(.sidebarItem)
        .foregroundStyle(Tokens.Color.Interactive.accent)
        // Leading inset aligned with the source names: swatch (11) + spacing.sm.
        .padding(.leading, 11 + Tokens.Spacing.sm)
        .frame(height: 24)
    }
}

extension SidebarSourceRow {
    /// interactions.md §13.2: the same alert and removal as Settings' button.
    fileprivate func confirmRemoval() {
        let count = SyncApplier.events(of: source, in: context).count
        guard SourcesSettingsModel.runRemovalAlert(SourcesSettingsModel.makeRemovalAlert(source, eventCount: count)) else { return }
        let name = source.displayName
        let isFeed = source.connection == .icsFeed
        guard let outcome = try? SourcesSettingsModel.remove(source, context: context, secrets: sync.secrets, sync: sync,
                                                             state: state, undo: nil) else { return }
        if outcome.keychainFailed {
            let followUp = NSAlert()
            followUp.messageText = isFeed ? MoodleSourceSettings.keychainFollowUp(name: name)
                                          : SourcesSettingsModel.keychainFollowUp(name: name)
            followUp.addButton(withTitle: "OK")
            followUp.runModal()
        }
    }
}

// MARK: - The source popover (§19.3)

struct SourcePopover: View {
    let source: Source
    let dismiss: () -> Void
    @State private var showDetails: Bool

    /// `showsDetails`: renders only (§22 item 10's expanded details).
    init(source: Source, dismiss: @escaping () -> Void, showsDetails: Bool = false) {
        self.source = source
        self.dismiss = dismiss
        _showDetails = State(initialValue: showsDetails)
    }

    var body: some View {
        SourceStatusBlock(source: source, showsSettingsButton: true, showDetails: $showDetails, dismiss: dismiss)
            .padding(Tokens.Spacing.xl)
            .frame(width: Tokens.Size.sourcePopoverWidth, alignment: .leading)
            .background(Tokens.Color.Surface.popover)
    }
}

// MARK: - The menu bar popover's stale line (§19.4)

struct StaleSourceLines: View {
    @Query private var sources: [Source]
    let now: Date

    var body: some View {
        let lines = SidebarSourcesRule.staleLines(sources, now: now)
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                ForEach(lines, id: \.self) { line in
                    Text(line)
                        .typeStyle(.popoverRefusalRow)    // 13pt, never truncated
                        .foregroundStyle(Tokens.Color.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, Tokens.Spacing.lg)
            .accessibilityElement(children: .combine)
        }
    }
}
