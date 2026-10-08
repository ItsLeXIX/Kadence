//
//  SourcesSettings.swift
//  Kadence
//
//  PHASE3-PLAN.md task 12 — layouts.md §11 (Settings ▸ Sources),
//  interactions.md §13.2 (removal), components.md §19.3 (the inline status
//  block), §21.4 (the Keychain label).
//

import SwiftUI
import SwiftData
import AppKit

// MARK: - Routing (who opens what)

/// Which source Settings shows, and which sheet it should present. Shared by
/// Settings, the sidebar, the popovers and File ▸ Connect Timetable….
@MainActor
@Observable
final class SourcesRouter {
    enum EditFocus: Equatable, Sendable { case password, server, name, none }

    enum Sheet: Equatable, Identifiable {
        case connect
        /// Edit mode (layouts.md §12.3). `autoConnect`: `Choose Calendar…`.
        case edit(sourceID: String, focus: EditFocus, autoConnect: Bool)

        var id: String {
            switch self {
            case .connect: "connect"
            case .edit(let id, _, _): "edit-\(id)"
            }
        }
    }

    var selectedSourceID: String?
    var sheet: Sheet?
}

// MARK: - The model (pure decisions, tested)

@MainActor
enum SourcesSettingsModel {
    /// layouts.md §11 `Sync`: the seven values, no "manually".
    static let intervals: [(seconds: Int, label: String)] = [
        (900, "Every 15 minutes"), (1800, "Every 30 minutes"), (3600, "Every hour"), (10_800, "Every 3 hours"),
        (21_600, "Every 6 hours"), (43_200, "Every 12 hours"), (86_400, "Every day"),
    ]

    static func intervalLabel(_ seconds: Int) -> String {
        intervals.first { $0.seconds == seconds }?.label ?? "Every 30 minutes"
    }

    /// `Calendar` (one) / `Calendars` (several), names comma-separated.
    static func calendarRow(_ source: Source) -> (label: String, value: String) {
        let names = source.calendars.map(\.displayName)
        return (names.count == 1 ? "Calendar" : "Calendars", names.joined(separator: ", "))
    }

    /// `Account` — `{user} @ {host}`. There is no password row (§11).
    static func accountRow(_ source: Source) -> String { source.accountDisplay ?? "" }

    /// `Name`: commits on ↩ or blur; empty reverts to the last name. The
    /// Keychain item's label follows (§21.4). Returns the name now shown.
    @discardableResult
    static func rename(_ source: Source, to typed: String, context: ModelContext, secrets: any SecretStore) -> String {
        let name = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != source.displayName else { return source.displayName }
        source.displayName = name
        try? context.save()
        if let account = secretAccount(source) {
            try? secrets.updateInfo(.forSource(id: source.id, displayName: name), for: account)
        }
        return name
    }

    static func secretAccount(_ source: Source) -> SecretAccount? {
        guard let server = ServerAddress(stored: source.serverURL), let user = source.username else { return nil }
        return SecretAccount(host: server.host, port: server.port, username: user)
    }

    // MARK: Removal (interactions.md §13.2)

    static func removalMessage(_ source: Source) -> String { "Remove “\(source.displayName)”?" }

    static func removalInformative(eventCount: Int) -> String {
        "Its \(SourceStatusCopy.events(eventCount)) — including past weeks and anything you marked done or skipped — "
            + "will be removed from your calendar, and its password deleted from the Keychain. Routine blocks you "
            + "moved for these events stay where they are. You can connect it again at any time; the timetable "
            + "comes back, your done and skipped marks don't."
    }

    static func keychainFollowUp(name: String) -> String {
        "The password for \(name) couldn't be deleted from the Keychain. You can remove the item “Kadence — \(name)” in Keychain Access."
    }

    /// The alert (interactions.md §13.2): warning style; `Cancel` is the
    /// default button (↩ never removes) and ⎋ cancels too; `Remove` is
    /// destructive. Swift note: NSAlert's first button is the rightmost and
    /// takes ↩, so `Cancel` is added first.
    static func makeRemovalAlert(_ source: Source, eventCount: Int) -> NSAlert {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = removalMessage(source)
        alert.informativeText = removalInformative(eventCount: eventCount)
        let cancel = alert.addButton(withTitle: "Cancel")
        cancel.keyEquivalent = "\r"
        let remove = alert.addButton(withTitle: "Remove")
        remove.hasDestructiveAction = true
        remove.keyEquivalent = ""
        return alert
    }

    /// Runs the alert; ⎋ (key code 53) presses `Cancel` through a local
    /// monitor, since a button holds only one key equivalent.
    static func runRemovalAlert(_ alert: NSAlert) -> Bool {
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { alert.buttons.first?.performClick(nil); return nil }
            return event
        }
        defer { if let monitor { NSEvent.removeMonitor(monitor) } }
        return alert.runModal() == .alertSecondButtonReturn
    }

    struct RemovalOutcome: Equatable {
        var removedEventIDs: Set<UUID>
        var keychainFailed: Bool
    }

    /// Cancels its sync, deletes its events (history included) and the
    /// source in one transaction, deletes the Keychain item. A Keychain
    /// failure still removes the source. Conflicts recompute from the store.
    static func remove(_ source: Source, context: ModelContext, secrets: any SecretStore,
                       sync: SyncCoordinator?, state: CalendarState?, undo: UndoStack?) throws -> RemovalOutcome {
        let account = secretAccount(source)
        sync?.sourceRemoved(source.id)
        let ids = try SyncApplier.remove(source, context: context)
        SyncApplier.finish(SyncApplier.Outcome(deletedIDs: ids, wrote: true), state: state, undo: undo)
        var failed = false
        if let account {
            do { try secrets.delete(account) } catch { failed = true }
        }
        return RemovalOutcome(removedEventIDs: ids, keychainFailed: failed)
    }
}

// MARK: - The Settings scene

struct SettingsView: View {
    var body: some View {
        // A tab bar with one tab is on purpose (layouts.md §11): later phases
        // add panes without moving this one.
        TabView {
            SourcesSettingsView()
                .tabItem { Label("Sources", systemImage: "link") }
        }
        .frame(width: Tokens.Size.settingsWindowWidth, height: Tokens.Size.settingsWindowHeight)
    }
}

struct SourcesSettingsView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(SourcesRouter.self) private var router
    @Environment(CalendarState.self) private var calendarState
    @Environment(UndoStack.self) private var undo
    @Query private var allSources: [Source]

    private var sources: [Source] {
        allSources.filter(\.isConnected).sorted { $0.displayName < $1.displayName }
    }

    private var selected: Source? {
        sources.first { $0.id == router.selectedSourceID } ?? sources.first
    }

    var body: some View {
        @Bindable var router = router
        HStack(spacing: 0) {
            sourceList
            Divider()
            Group {
                if let source = selected {
                    SourceDetailView(source: source, remove: { confirmRemoval(of: source) })
                        .id(source.id)
                } else {
                    emptyState
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear { if router.selectedSourceID == nil { router.selectedSourceID = sources.first?.id } }
        .sheet(item: $router.sheet) { sheet in
            ConnectSheet(request: sheet)
        }
    }

    private var sourceList: some View {
        @Bindable var router = router
        return VStack(spacing: 0) {
            List(selection: Binding(get: { selected?.id }, set: { router.selectedSourceID = $0 })) {
                ForEach(sources, id: \.id) { source in
                    HStack(spacing: Tokens.Spacing.sm) {
                        SourceSwatch(key: source.paletteKey, symbol: source.symbol, isOn: true)
                        Text(source.displayName)
                            .typeStyle(.sidebarItem)
                            .lineLimit(1)
                            .truncationMode(.tail)
                        Spacer(minLength: 0)
                        SourceStatusSlot(source: source)
                    }
                    .tag(source.id)
                }
            }
            .listStyle(.bordered)
            HStack(spacing: 0) {
                Button { router.sheet = .connect } label: { Image(systemName: "plus") }
                    .accessibilityLabel("Connect Timetable…")
                Button { if let s = selected { confirmRemoval(of: s) } } label: { Image(systemName: "minus") }
                    .disabled(selected == nil)
                    .accessibilityLabel("Remove Source…")
                Spacer()
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(Tokens.Spacing.xs)
        }
        .frame(width: Tokens.Size.settingsSourceListWidth)
    }

    private var emptyState: some View {
        VStack(spacing: Tokens.Spacing.lg) {
            Text("No timetable connected.")
                .typeStyle(.inspectorValue)
                .foregroundStyle(Tokens.Color.Text.secondary)
            Button("Connect Timetable…") { router.sheet = .connect }
        }
    }

    /// interactions.md §13.2: a standard warning `NSAlert`; `Cancel` is the
    /// default (↩ does not remove; ⎋ cancels).
    private func confirmRemoval(of source: Source) {
        let count = SyncApplier.events(of: source, in: context).count
        let alert = SourcesSettingsModel.makeRemovalAlert(source, eventCount: count)
        guard SourcesSettingsModel.runRemovalAlert(alert) else { return }
        let name = source.displayName
        let secrets = sync.secrets
        guard let outcome = try? SourcesSettingsModel.remove(source, context: context, secrets: secrets, sync: sync,
                                                             state: calendarState, undo: undo) else { return }
        router.selectedSourceID = sources.first?.id
        if outcome.keychainFailed {
            let followUp = NSAlert()
            followUp.messageText = SourcesSettingsModel.keychainFollowUp(name: name)
            followUp.addButton(withTitle: "OK")
            followUp.runModal()
        }
    }
}

// MARK: - The detail

struct SourceDetailView: View {
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(SourcesRouter.self) private var router
    let source: Source
    let remove: () -> Void

    @State private var name = ""
    @FocusState private var nameFocused: Bool
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            SourceStatusBlock(source: source, showsSettingsButton: false, showDetails: $showDetails)
            Divider()
                .overlay(Tokens.Color.Separator.region)
                .padding(.vertical, Tokens.Spacing.lg)
            Form {
                TextField("Name", text: $name)
                    .focused($nameFocused)
                    .onSubmit(commitName)
                    .onChange(of: nameFocused) { _, focused in if !focused { commitName() } }
                LabeledContent("Account") {
                    VStack(alignment: .trailing, spacing: Tokens.Spacing.sm) {
                        Text(SourcesSettingsModel.accountRow(source))
                            .typeStyle(.inspectorValue)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Button("Edit Account…") {
                            router.sheet = .edit(sourceID: source.id, focus: .password, autoConnect: false)
                        }
                    }
                }
                let calendars = SourcesSettingsModel.calendarRow(source)
                LabeledContent(calendars.label) {
                    Text(calendars.value)
                        .typeStyle(.inspectorValue)
                        .lineLimit(nil)
                }
                Picker("Sync", selection: Binding(get: { source.pollInterval }, set: { setInterval($0) })) {
                    ForEach(SourcesSettingsModel.intervals, id: \.seconds) { option in
                        Text(option.label).tag(option.seconds)
                    }
                }
            }
            .formStyle(.columns)
            Spacer(minLength: Tokens.Spacing.lg)
            Button("Remove Source…", action: remove)
                .buttonStyle(.bordered)
        }
        .padding(Tokens.Spacing.xl)
        .onAppear { name = source.displayName }
    }

    private func commitName() {
        name = SourcesSettingsModel.rename(source, to: name, context: context, secrets: sync.secrets)
    }

    private func setInterval(_ seconds: Int) {
        source.pollInterval = seconds
        try? context.save()
        sync.refreshSchedules()
    }
}

// MARK: - The status block (§19.3 content; Settings inline, popover)

struct SourceStatusBlock: View {
    @Environment(SyncCoordinator.self) private var sync
    @Environment(SourcesRouter.self) private var router
    @Environment(\.openSettings) private var openSettings
    let source: Source
    let showsSettingsButton: Bool
    @Binding var showDetails: Bool
    var dismiss: (() -> Void)?

    var body: some View {
        // §19.5: relative forms update while the block is open.
        TimelineView(.periodic(from: .now, by: 30)) { timeline in
            let p = SourceStatusPresentation(source: source, now: timeline.date, isSyncing: sync.isSyncing(source))
            VStack(alignment: .leading, spacing: 0) {
                Text(p.title)
                    .typeStyle(.sourceStatusTitle)
                    .foregroundStyle(Tokens.Color.Text.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if let body = p.body {
                    Text(body)
                        .typeStyle(.inspectorValue)
                        .lineLimit(nil)
                        .foregroundStyle(Tokens.Color.Text.primary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Tokens.Spacing.sm)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(p.statusLine)
                    if let change = p.lastChangeLine { Text(change).lineLimit(nil) }
                }
                .typeStyle(.blockMeta)
                .foregroundStyle(Tokens.Color.Text.secondary)
                .padding(.top, Tokens.Spacing.lg)
                if showDetails { ProblemList(problems: source.problems).padding(.top, Tokens.Spacing.sm) }
                HStack(spacing: Tokens.Spacing.sm) {
                    Spacer()
                    if showsSettingsButton {
                        Button("Settings…") {
                            router.selectedSourceID = source.id
                            dismiss?()
                            openSettings()
                        }
                    }
                    if let action = p.primaryAction {
                        primaryButton(action)
                    } else if source.state == .syncing || sync.isSyncing(source) {
                        Button(PrimaryAction.syncNow.rawValue) {}.disabled(true)
                    }
                }
                .padding(.top, Tokens.Spacing.lg)
            }
        }
    }

    @ViewBuilder
    private func primaryButton(_ action: PrimaryAction) -> some View {
        let title = action == .showDetails && showDetails ? "Hide Details" : action.rawValue
        Button(title) { perform(action) }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.bordered)
    }

    private func perform(_ action: PrimaryAction) {
        switch action {
        case .syncNow:
            sync.trigger(.syncNow, sourceID: source.id)
        case .showDetails:
            showDetails.toggle()
        case .updatePassword:
            openEdit(.password, autoConnect: false)
        case .editAccount:
            openEdit(showsSettingsButton ? .server : .password, autoConnect: false)
        case .chooseCalendar:
            openEdit(.none, autoConnect: true)
        }
    }

    /// layouts.md §12.3's focus table: a state's `Edit Account…` focuses
    /// `Server`; Settings' own `Edit Account…` focuses `Password`.
    private func openEdit(_ focus: SourcesRouter.EditFocus, autoConnect: Bool) {
        router.selectedSourceID = source.id
        router.sheet = .edit(sourceID: source.id, focus: focus, autoConnect: autoConnect)
        if showsSettingsButton {
            dismiss?()
            openSettings()
        }
    }
}

/// §19.3 `Show Details`: one problem per line, sentence in `text.primary`,
/// technical line in `text.secondary`; at most 8, then `+N more`.
struct ProblemList: View {
    let problems: [ImportProblem]
    static let cap = 8

    static func visible(_ problems: [ImportProblem]) -> (shown: [ImportProblem], more: String?) {
        guard problems.count > cap else { return (problems, nil) }
        return (Array(problems.prefix(cap)), "+\(problems.count - cap) more")
    }

    var body: some View {
        let (shown, more) = Self.visible(problems)
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, problem in
                VStack(alignment: .leading, spacing: 0) {
                    Text(problem.sentence).foregroundStyle(Tokens.Color.Text.primary)
                    if let technical = problem.technical {
                        Text(technical).foregroundStyle(Tokens.Color.Text.secondary)
                    }
                }
                .lineLimit(nil)
            }
            if let more { Text(more).foregroundStyle(Tokens.Color.Text.secondary) }
        }
        .typeStyle(.blockMeta)
    }
}

/// §19.2's status slot (`size.statusSlotWidth`), reserved on every row.
struct SourceStatusSlot: View {
    @Environment(SyncCoordinator.self) private var sync
    let source: Source?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { timeline in
            let glyph = source.map { s in
                SourceStatusCopy.glyph(s.state, isSyncingVisibly: Self.showsSpinner(started: sync.syncStartedAt[s.id],
                                                                                    now: timeline.date))
            } ?? StatusGlyph.none
            Group {
                switch glyph {
                case .none:
                    Color.clear
                case .spinner:
                    ProgressView().controlSize(.mini)
                case .transient:
                    Image(systemName: StatusGlyph.symbol)
                        .font(.system(size: Tokens.Size.blockGlyphSize))
                        .foregroundStyle(Tokens.Color.Text.secondary)
                case .actionable:
                    Image(systemName: StatusGlyph.symbol)
                        .font(.system(size: Tokens.Size.blockGlyphSize))
                        .foregroundStyle(Tokens.Color.Semantic.alert)
                }
            }
            .frame(width: Tokens.Size.statusSlotWidth, height: Tokens.Size.statusSlotWidth)
            .accessibilityHidden(true)
        }
    }

    /// §19.2: the spinner only once a sync has run for 0.5 s.
    static func showsSpinner(started: Date?, now: Date) -> Bool {
        guard let started else { return false }
        return now.timeIntervalSince(started) >= 0.5
    }
}
