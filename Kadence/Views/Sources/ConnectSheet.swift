//
//  ConnectSheet.swift
//  Kadence
//
//  PHASE3-PLAN.md task 13 — layouts.md §12: two steps in one sheet on the
//  Settings window, width `size.connectSheetWidth`, padding `spacing.xxxl`;
//  the content swaps with `motion.viewChange` (Reduce Motion: a fade). The
//  decisions live in `ConnectSheetModel`; this file only draws them.
//

import SwiftUI
import SwiftData

struct ConnectSheet: View {
    let request: SourcesRouter.Sheet
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(SourcesRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Query private var sources: [Source]
    @State private var model: ConnectSheetModel?

    var body: some View {
        Group {
            if let model { ConnectSheetContent(model: model, done: done) }
        }
        .frame(width: Tokens.Size.connectSheetWidth)
        .onAppear(perform: makeModel)
    }

    private func makeModel() {
        guard model == nil else { return }
        var editing: Source?
        var autoConnect = false
        var focus: ConnectSheetModel.Field?
        if case .edit(let id, let editFocus, let auto) = request {
            editing = sources.first { $0.id == id }
            autoConnect = auto
            focus = switch editFocus {
            case .password: .password
            case .server: .server
            case .name: .name
            case .none: nil
            }
        }
        let m = ConnectSheetModel(editing: editing, context: context, secrets: sync.secrets,
                                  makeTransport: sync.makeTransport, sync: sync)
        if editing != nil { m.focus = focus }
        model = m
        // `Choose Calendar…` starts Connect at once with the saved account.
        if autoConnect { m.connect() }
    }

    private func done(_ source: Source?) {
        if let source { router.selectedSourceID = source.id }
        router.sheet = nil
        dismiss()
    }
}

private struct ConnectSheetContent: View {
    @Bindable var model: ConnectSheetModel
    let done: (Source?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: ConnectSheetModel.Field?
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.phase == .step2 { step2 } else { step1 }
        }
        .padding(Tokens.Spacing.xxxl)
        // `motion.viewChange`: ease-in-out 0.16 s; Reduce Motion: a 0.10 s fade.
        .animation(reduceMotion ? .linear(duration: 0.10) : .easeInOut(duration: Tokens.Motion.ViewChange.duration),
                   value: model.phase)
        .onChange(of: model.focus, initial: true) { _, new in focus = new }
        .onChange(of: focus) { _, new in if new != model.focus { model.focus = new } }
    }

    // MARK: Step 1

    private var fieldsDisabled: Bool { model.phase == .connecting }

    private var step1: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.title)
                .typeStyle(.inspectorTitle)
            Text("Sign in with your FH account — the server, username and password Apple Calendar uses. Kadence only reads the timetable; it never changes anything in CIS.")
                .typeStyle(.inspectorValue)
                .foregroundStyle(Tokens.Color.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Tokens.Spacing.sm)
            Form {
                TextField("Name", text: $model.name)
                    .focused($focus, equals: .name)
                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                    TextField("Server", text: $model.server)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .server)
                    if let message = model.serverMessage { guidance(message) }
                }
                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                    TextField("Username", text: $model.username)
                        .textContentType(.username)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .username)
                    if let message = model.usernameMessage { guidance(message) }
                }
                // The only view that ever holds the password (§21.4).
                SecureField("Password", text: $model.password, prompt: Text(model.passwordPlaceholder))
                    .textContentType(.password)
                    .focused($focus, equals: .password)
            }
            .formStyle(.columns)
            .disabled(fieldsDisabled)
            .padding(.top, Tokens.Spacing.xl)

            Group {
                if model.phase == .connecting {
                    HStack(spacing: Tokens.Spacing.sm) {
                        ProgressView().controlSize(.mini)
                        Text(model.connectingLine)
                            .lineLimit(nil)  // before the style: the innermost line limit wins
                            .typeStyle(.blockMeta)
                            .foregroundStyle(Tokens.Color.Text.secondary)
                    }
                } else if let failure = model.failure {
                    VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                        Text(failure.title).typeStyle(.sourceStatusTitle)
                        Text(failure.body).lineLimit(nil).typeStyle(.inspectorValue)
                    }
                    .foregroundStyle(Tokens.Color.Text.primary)
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(model.footnote)
                        .lineLimit(nil)  // before the style: the innermost line limit wins
                        .typeStyle(.blockMeta)
                        .foregroundStyle(Tokens.Color.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, Tokens.Spacing.lg)

            HStack(spacing: Tokens.Spacing.sm) {
                Spacer()
                Button("Cancel") {
                    model.cancelConnecting()
                    done(nil)
                }
                .keyboardShortcut(.cancelAction)
                Button("Connect") { model.connect() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!model.canConnect)
                    .focused($focus, equals: .connect)
            }
            .padding(.top, Tokens.Spacing.xl)
        }
    }

    /// layouts.md §12.1: validation is guidance, not red.
    private func guidance(_ text: String) -> some View {
        Text(text)
            .lineLimit(nil)  // before the style: the innermost line limit wins
            .typeStyle(.blockMeta)
            .foregroundStyle(Tokens.Color.Text.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: Step 2

    private var step2: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.step2Title)
                .typeStyle(.inspectorTitle)
            Text(model.accountLine)
                .typeStyle(.inspectorValue)
                .foregroundStyle(Tokens.Color.Text.secondary)
            if let missing = model.missingLine {
                Text(missing)
                    .typeStyle(.inspectorValue)
                    .foregroundStyle(Tokens.Color.Text.primary)
                    .padding(.top, Tokens.Spacing.lg)
            }
            Text(model.calendarLabel)
                .typeStyle(.inspectorLabel)
                .foregroundStyle(Tokens.Color.Text.secondary)
                .padding(.top, Tokens.Spacing.lg)
                .padding(.bottom, Tokens.Spacing.sm)
            if model.isSingleCalendar, let only = model.fetched.first {
                ConfirmedCalendarRow(name: only.calendar.displayName)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(model.fetched, id: \.calendar.href) { item in
                            Toggle(item.calendar.displayName, isOn: Binding(
                                get: { model.checked.contains(item.calendar.href) },
                                set: { on in
                                    if on { model.checked.insert(item.calendar.href) }
                                    else { model.checked.remove(item.calendar.href) }
                                }))
                            .toggleStyle(.checkbox)
                            .frame(height: Tokens.Size.connectCalendarRowHeight)
                        }
                    }
                }
                .frame(maxHeight: Tokens.Size.connectCalendarListMaxHeight)
                .fixedSize(horizontal: false, vertical: true)
            }
            Text(model.rangeLine)
                .lineLimit(nil)  // before the style: the innermost line limit wins
                .typeStyle(model.isNoneChecked ? .blockMeta : .inspectorValue)
                .foregroundStyle(model.isNoneChecked ? Tokens.Color.Text.secondary : Tokens.Color.Text.primary)
                .padding(.top, Tokens.Spacing.lg)
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                ForEach(Array(model.sentences.enumerated()), id: \.offset) { _, sentence in
                    Text(sentence.text)
                        .typeStyle(.inspectorValue)
                        .foregroundStyle(sentence.isPrimary ? Tokens.Color.Text.primary : Tokens.Color.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !model.problems.isEmpty {
                    Button(showDetails ? "Hide Details" : "Show Details") { showDetails.toggle() }
                        .buttonStyle(.borderless)
                    if showDetails { ProblemList(problems: model.problems) }
                }
            }
            .padding(.top, Tokens.Spacing.lg)
            if let failure = model.saveFailure {
                VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                    Text(failure.title).typeStyle(.sourceStatusTitle)
                    Text(failure.body).lineLimit(nil).typeStyle(.inspectorValue)
                }
                .padding(.top, Tokens.Spacing.lg)
            }
            HStack(spacing: Tokens.Spacing.sm) {
                Spacer()
                Button("Back") { model.back() }
                Button(model.isEditMode ? "Save" : "Import") {
                    let source = model.isEditMode ? (model.save() ? model.editing : nil) : model.importNow()
                    if let source { done(source) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canImport)
            }
            .padding(.top, Tokens.Spacing.xl)
        }
    }
}

/// layouts.md §12.2: one calendar is a confirmed row, not a control —
/// `checkmark` in `text.secondary`, then the name. Not focusable, not
/// clickable; VoiceOver reads `Calendar: LVPlan`.
struct ConfirmedCalendarRow: View {
    let name: String

    var body: some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Image(systemName: "checkmark")
                .font(.system(size: Tokens.Size.blockGlyphSize))
                .foregroundStyle(Tokens.Color.Text.secondary)
            Text(name)
                .typeStyle(.inspectorValue)
                .foregroundStyle(Tokens.Color.Text.primary)
        }
        .frame(height: Tokens.Size.connectCalendarRowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Calendar: \(name)")
    }
}
