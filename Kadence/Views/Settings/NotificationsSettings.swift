//
//  NotificationsSettings.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 15) — layouts.md §14;
//  components.md §27.1, §27.8; interactions.md §14.2; §29. Settings ▸
//  Notifications: the permission status block (copy exact), the five rule
//  rows, the quiet footer. Every change triggers a notification pass.
//

import SwiftUI
import SwiftData
import AppKit
import Observation

@MainActor
@Observable
final class NotificationsSettingsModel {
    @ObservationIgnored let context: ModelContext
    @ObservationIgnored let scheduler: NotificationScheduler
    @ObservationIgnored var openURL: (URL) -> Void
    private(set) var revision = 0

    init(context: ModelContext, scheduler: NotificationScheduler, openURL: @escaping (URL) -> Void = { _ in }) {
        self.context = context
        self.scheduler = scheduler
        self.openURL = openURL
    }

    static let settingsURL = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension?id=XIX.Kadence")!

    /// §27.1's five rules, in order.
    var rules: [NotificationRule] {
        _ = revision
        let all = (try? context.fetch(FetchDescriptor<NotificationRule>())) ?? []
        // The sixth rule, `deadline`, is its own row group (layouts.md §19).
        return NotificationRuleKind.allCases.filter { $0 != .deadline }
            .compactMap { kind in all.first { $0.kind == kind } }
    }

    /// layouts.md §14's second lines.
    static func secondLine(_ kind: NotificationRuleKind) -> String {
        switch kind {
        case .leaveBy: "Events at a place you travel to"
        case .timetableStart: "Lectures and exams with no travel"
        case .personalStart: "Events you created, with no travel"
        case .routineStart: "Routine blocks"
        case .syncPaused: "When a calendar stops syncing and needs you"
        // layouts.md §19.
        case .deadline: "Moodle items with a due time"
        }
    }

    /// Lead choices in minutes (§27.1); `syncPaused` has none.
    static func leadChoices(_ kind: NotificationRuleKind) -> [Int] {
        switch kind {
        case .leaveBy: [0, 5, 10, 15, 30]
        case .syncPaused: []
        default: [0, 5, 10, 15, 30, 60]
        }
    }

    static func leadLabel(_ minutes: Int, kind: NotificationRuleKind) -> String {
        switch minutes {
        case 0: kind == .leaveBy ? "At leave time" : "At start time"
        case 60: "1 hour before"
        default: "\(minutes) minutes before"
        }
    }

    func setLead(_ minutes: Int, for rule: NotificationRule) {
        guard Self.leadChoices(rule.kind).contains(minutes), minutes != rule.leadMinutes else { return }
        rule.leadMinutes = minutes
        save()
    }

    /// A switch. Turning a rule on while Kadence has never asked asks
    /// (§27.8).
    func setEnabled(_ on: Bool, for rule: NotificationRule) async {
        guard on != rule.isEnabled else { return }
        rule.isEnabled = on
        save()
        if on, scheduler.permission == .notAsked { await scheduler.askForPermission() }
    }

    /// §27.8's block: only in `off` / `notAllowedYet`, with at least one
    /// rule on.
    struct Block: Equatable {
        enum Button: String, Equatable {
            case openSystemSettings = "Open System Settings…"
            case allowNotifications = "Allow Notifications…"
        }
        var title: String
        var body: String
        var button: Button
    }

    var block: Block? {
        guard rules.contains(where: \.isEnabled) else { return nil }
        switch scheduler.permission {
        case .off:
            return Block(title: "Notifications are off",
                         body: "macOS isn't showing notifications from Kadence, so it can't tell you when to leave or when something starts. Turn them on in System Settings ▸ Notifications ▸ Kadence.",
                         button: .openSystemSettings)
        case .notAllowedYet:
            return Block(title: "Notifications aren't allowed yet",
                         body: "Kadence needs your permission to tell you when to leave and when something starts.",
                         button: .allowNotifications)
        case .allowed, .notAsked:
            return nil
        }
    }

    func press(_ button: Block.Button) async {
        switch button {
        case .openSystemSettings:
            openURL(Self.settingsURL)
        case .allowNotifications:
            // Asks again; if macOS shows no prompt (answered before), opens
            // System Settings.
            let asked = await scheduler.askForPermission()
            if !asked || scheduler.permission != .allowed { openURL(Self.settingsURL) }
        }
    }

    static let footer = "Kadence stays quiet during Sleep and your other protected windows: a notification due then arrives when the window ends, unless the event itself is inside the window."

    // §29
    static func switchLabel(_ kind: NotificationRuleKind) -> String { "\(kind.settingsLabel) notifications" }
    static func popupLabel(_ kind: NotificationRuleKind) -> String { "\(kind.settingsLabel), notify" }

    private func save() {
        try? context.save()
        revision += 1
        scheduler.requestPass()
    }
}

struct NotificationsSettingsPane: View {
    @Environment(\.modelContext) private var context
    @Environment(NotificationScheduler.self) private var scheduler
    @State private var model: NotificationsSettingsModel?

    var body: some View {
        Group {
            if let model { NotificationsSettingsForm(model: model) } else { Color.clear }
        }
        .onAppear {
            if model == nil {
                model = NotificationsSettingsModel(context: context, scheduler: scheduler,
                                                   openURL: { NSWorkspace.shared.open($0) })
            }
            Task { await scheduler.refreshPermission() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await scheduler.refreshPermission() }
        }
    }
}

struct NotificationsSettingsForm: View {
    let model: NotificationsSettingsModel

    var body: some View {
        Form {
            if let block = model.block {
                Section {
                    StatusBlockView(title: block.title, message: block.body, button: block.button.rawValue) {
                        Task { await model.press(block.button) }
                    }
                }
            }
            Section {
                ForEach(model.rules, id: \.kind) { rule in
                    LabeledContent {
                        HStack(spacing: Tokens.Spacing.sm) {
                            let choices = NotificationsSettingsModel.leadChoices(rule.kind)
                            if !choices.isEmpty {
                                Picker(NotificationsSettingsModel.popupLabel(rule.kind),
                                       selection: Binding(get: { rule.leadMinutes }, set: { model.setLead($0, for: rule) })) {
                                    ForEach(choices, id: \.self) { minutes in
                                        Text(NotificationsSettingsModel.leadLabel(minutes, kind: rule.kind)).tag(minutes)
                                    }
                                }
                                .labelsHidden()
                                .fixedSize()
                                .disabled(!rule.isEnabled)
                            }
                            Toggle(NotificationsSettingsModel.switchLabel(rule.kind),
                                   isOn: Binding(get: { rule.isEnabled },
                                                 set: { on in Task { await model.setEnabled(on, for: rule) } }))
                                .labelsHidden()
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(rule.kind.settingsLabel).typeStyle(.sidebarItem)
                            Text(NotificationsSettingsModel.secondLine(rule.kind))
                                .lineLimit(nil)
                                .typeStyle(.blockMeta)
                                .foregroundStyle(Tokens.Color.Text.secondary)
                        }
                    }
                }
            } header: {
                Text("Notify me")
            } footer: {
                Text(NotificationsSettingsModel.footer).foregroundStyle(Tokens.Color.Text.secondary)
            }
        }
        .formStyle(.grouped)
        .id(model.revision)
    }
}
