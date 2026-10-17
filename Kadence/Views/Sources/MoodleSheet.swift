//
//  MoodleSheet.swift
//  Kadence
//
//  Phase 3 slice 3 (PHASE3-SLICE3-PLAN.md task 10) — layouts.md §16: the
//  Moodle sheet on the Settings window, width `size.connectSheetWidth`,
//  padding `spacing.xxxl`, two steps in one sheet with `motion.viewChange`.
//  The decisions live in `MoodleSheetModel`; this file only draws them. The
//  URL field is a `SecureField`: never echoed, never copied out, never in an
//  accessibility value.
//

import SwiftUI
import SwiftData

struct MoodleSheet: View {
    let request: SourcesRouter.Sheet
    @Environment(\.modelContext) private var context
    @Environment(SyncCoordinator.self) private var sync
    @Environment(SourcesRouter.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Query private var sources: [Source]
    @State private var model: MoodleSheetModel?

    var body: some View {
        Group {
            if let model { MoodleSheetContent(model: model, done: done) }
        }
        .frame(width: Tokens.Size.connectSheetWidth)
        .onAppear(perform: makeModel)
    }

    private func makeModel() {
        guard model == nil else { return }
        var replacing: Source?
        if case .replaceMoodle(let id) = request { replacing = sources.first { $0.id == id } }
        model = MoodleSheetModel(replacing: replacing, context: context, secrets: sync.secrets,
                                 makeTransport: sync.makeFeedTransport, sync: sync)
    }

    private func done(_ source: Source?) {
        if let source { router.selectedSourceID = source.id }
        router.sheet = nil
        dismiss()
    }
}

struct MoodleSheetContent: View {
    @Bindable var model: MoodleSheetModel
    let done: (Source?) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: MoodleSheetModel.Field?
    @State private var showDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.phase == .step2 { step2 } else { step1 }
        }
        .padding(Tokens.Spacing.xxxl)
        .animation(reduceMotion ? .linear(duration: 0.10) : .easeInOut(duration: Tokens.Motion.ViewChange.duration),
                   value: model.phase)
        .onChange(of: model.focus, initial: true) { _, new in focus = new }
        .onChange(of: focus) { _, new in if new != model.focus { model.focus = new } }
    }

    // MARK: Step 1 (layouts.md §16.1, §16.3)

    private var step1: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.title)
                .typeStyle(.inspectorTitle)
            Text(model.intro)
                .lineLimit(nil)  // before the style: the innermost line limit wins
                .typeStyle(.inspectorValue)
                .foregroundStyle(Tokens.Color.Text.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Tokens.Spacing.sm)
            Form {
                if !model.isReplace {
                    TextField("Name", text: $model.name)
                        .focused($focus, equals: .name)
                }
                VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                    // The only view that ever holds the URL (components.md §33.4).
                    SecureField("URL", text: $model.urlText, prompt: Text(model.placeholder))
                        .autocorrectionDisabled()
                        .focused($focus, equals: .url)
                        .accessibilityLabel(MoodleSheetModel.urlAccessibilityLabel)
                        .accessibilityValue(model.urlAccessibilityValue)
                    if let line = model.validationLine {
                        Text(line)
                            .lineLimit(nil)
                            .typeStyle(.blockMeta)
                            .foregroundStyle(Tokens.Color.Text.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .formStyle(.columns)
            .disabled(model.phase == .connecting)
            .padding(.top, Tokens.Spacing.xl)

            Group {
                if model.phase == .connecting {
                    HStack(spacing: Tokens.Spacing.sm) {
                        ProgressView().controlSize(.mini)
                        Text(model.connectingLine)
                            .lineLimit(nil)
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
                    Text(MoodleSheetModel.footnote)
                        .lineLimit(nil)
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

    // MARK: Step 2 (layouts.md §16.2, §16.3's Update form)

    private var step2: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(model.step2Title)
                .typeStyle(.inspectorTitle)
            Text(model.displayLine)
                .typeStyle(.inspectorValue)
                .foregroundStyle(Tokens.Color.Text.secondary)
            Text(model.rangeLine)
                .lineLimit(nil)
                .typeStyle(.inspectorValue)
                .foregroundStyle(Tokens.Color.Text.primary)
                .padding(.top, Tokens.Spacing.lg)
            VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
                ForEach(Array(model.sentences.enumerated()), id: \.offset) { _, sentence in
                    Text(sentence.text)
                        .lineLimit(nil)
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
                Button(model.isReplace ? "Save" : "Import") {
                    let source = model.isReplace ? (model.save() ? model.replacing : nil) : model.importNow()
                    if let source { done(source) }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.canImport)
            }
            .padding(.top, Tokens.Spacing.xl)
        }
    }
}
