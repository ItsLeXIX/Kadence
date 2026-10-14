//
//  TravelSettingsView.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md tasks 13–14) — layouts.md §13:
//  Settings ▸ Travel. A standard grouped form. Task 13: Places (names,
//  addresses, the lookup line and its controls, the match list, `Add
//  Place`, removal). Task 14 adds Ways to travel, Leave by and Where you
//  are. Every decision lives in `TravelSettingsModel`; this file only draws
//  it.
//

import SwiftUI
import SwiftData

/// The Travel tab: builds its model from the environment, and tells it when
/// the tab is left (a result left unconfirmed becomes `unconfirmed`).
struct TravelSettingsPane: View {
    @Environment(\.modelContext) private var context
    @Environment(TravelCoordinator.self) private var travel
    @State private var model: TravelSettingsModel?

    var body: some View {
        Group {
            if let model {
                TravelSettingsForm(model: model)
            } else {
                Color.clear
            }
        }
        .onAppear { if model == nil { model = TravelSettingsModel(context: context, travel: travel) } }
        .onDisappear { model?.leave() }
    }
}

struct TravelSettingsForm: View {
    let model: TravelSettingsModel
    /// Sections after Places (task 14). Off in the Places-only renders.
    var showsTravelSections = true

    var body: some View {
        Form {
            TravelPlacesSection(model: model)
            if showsTravelSections {
                TravelWaysSections(model: model)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Places

struct TravelPlacesSection: View {
    let model: TravelSettingsModel
    @Environment(SourcesRouter.self) private var router
    @State private var removing: String?

    var body: some View {
        Section {
            ForEach(model.places, id: \.id) { place in
                PlaceRow(model: model, place: place, focusAddress: router.travelFocus == .address(placeID: place.id)) {
                    if model.removalQuestion(place.id) != nil { removing = place.id } else { model.remove(place.id) }
                }
            }
        } header: {
            Text("Places")
        } footer: {
            VStack(alignment: .trailing, spacing: Tokens.Spacing.sm) {
                Text(model.footer)
                    .foregroundStyle(Tokens.Color.Text.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Add Place") { model.addPlace() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .alert(removing.flatMap { model.removalQuestion($0)?.message } ?? "",
               isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            Button("Remove", role: .destructive) {
                if let id = removing { model.remove(id) }
                removing = nil
            }
            Button("Cancel", role: .cancel) { removing = nil }
                .keyboardShortcut(.defaultAction)
        } message: {
            Text(removing.flatMap { model.removalQuestion($0)?.informative } ?? "")
        }
    }
}

/// One known place: name, address, the lookup line, remove.
struct PlaceRow: View {
    let model: TravelSettingsModel
    let place: KnownPlace
    var focusAddress = false
    let remove: () -> Void

    @State private var name = ""
    @FocusState private var focus: Field?
    enum Field: Hashable { case name, address }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.md) {
            TextField(TravelSettingsModel.nameFieldLabel, text: $name, prompt: Text("Name"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .typeStyle(.sidebarItem)
                .frame(width: Tokens.Size.settingsPlaceNameFieldWidth)
                .focused($focus, equals: .name)
                .onSubmit { commitName() }
                .accessibilityLabel(TravelSettingsModel.nameFieldLabel)
            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                TextField(TravelSettingsModel.addressFieldLabel(place.name), text: addressBinding,
                          prompt: Text("Address"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .help(model.fieldText(place))
                    .focused($focus, equals: .address)
                    .onSubmit { model.commitAddress(place.id) }
                    .onKeyPress(.downArrow) { model.moveSelection(place.id, by: 1); return .handled }
                    .onKeyPress(.upArrow) { model.moveSelection(place.id, by: -1); return .handled }
                    .onExitCommand { model.cancel(place.id) }
                    .accessibilityLabel(TravelSettingsModel.addressFieldLabel(place.name))
                if let line = model.line(for: place) {
                    LookupLineView(model: model, placeID: place.id, line: line)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !place.isBuiltIn {
                Button(action: remove) {
                    Image(systemName: "minus.circle")
                        .frame(width: 24, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .help(TravelSettingsModel.removeLabel(place.name))
                .accessibilityLabel(TravelSettingsModel.removeLabel(place.name))
            }
        }
        .onAppear {
            name = place.name
            if focusAddress { focus = .address }
        }
        .onChange(of: focus) { old, new in
            if old == .name, new != .name { commitName() }
            if old == .address, new != .address { model.commitAddress(place.id) }
        }
    }

    private var addressBinding: Binding<String> {
        Binding(get: { model.drafts[place.id] ?? model.fieldText(place) },
                set: { model.drafts[place.id] = $0 })
    }

    private func commitName() {
        if !model.commitName(place.id, name) { name = place.name }
    }
}

/// The line and controls under an address field (components.md §23.5;
/// layouts.md §13). No colour: the words carry the state.
struct LookupLineView: View {
    let model: TravelSettingsModel
    let placeID: String
    let line: TravelSettingsModel.Line

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            ForEach(Array(line.texts.enumerated()), id: \.offset) { index, text in
                HStack(spacing: Tokens.Spacing.xs) {
                    if index == 0, line.showsSpinner { ProgressView().controlSize(.small) }
                    // `lineLimit(nil)` inside `typeStyle` (whose own limit is
                    // 1): the innermost environment value wins, and the line
                    // must wrap, never truncate (layouts.md §13: lineLimit 0).
                    Text(text)
                        .lineLimit(nil)
                        .typeStyle(.blockMeta)
                        .foregroundStyle(Tokens.Color.Text.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !line.matches.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(line.matches.enumerated()), id: \.offset) { index, match in
                        MatchRow(match: match, isSelected: model.selectedMatch[placeID] == index) {
                            model.confirm(placeID, match)
                        }
                    }
                }
                .frame(maxHeight: Tokens.Size.settingsAddressMatchListMaxHeight, alignment: .top)
            }
            if !line.controls.isEmpty {
                HStack(spacing: Tokens.Spacing.sm) {
                    Spacer(minLength: 0)
                    ForEach(line.controls, id: \.self) { control in
                        controlButton(control)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func controlButton(_ control: TravelSettingsModel.Control) -> some View {
        let button = Button(control.rawValue) {
            switch control {
            case .useThisAddress: model.confirmSelection(placeID)
            case .cancel: model.cancel(placeID)
            case .tryAgain, .lookUp: model.lookUpAgain(placeID)
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        if control == line.defaultControl {
            button.keyboardShortcut(.defaultAction)
        } else {
            button
        }
    }
}

/// A two-line match row (`settingsAddressMatchRowHeight`).
struct MatchRow: View {
    let match: GeocodedAddress
    let isSelected: Bool
    let choose: () -> Void

    var body: some View {
        let lines = TravelSettingsModel.matchLines(match.line)
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 0) {
                Text(lines.first)
                    .typeStyle(.sidebarItem)
                    .lineLimit(1).truncationMode(.tail)
                Text(lines.rest)
                    .typeStyle(.blockMeta)
                    .foregroundStyle(Tokens.Color.Text.secondary)
                    .lineLimit(1).truncationMode(.tail)
            }
            .padding(.horizontal, Tokens.Spacing.sm)
            .frame(maxWidth: .infinity, minHeight: Tokens.Size.settingsAddressMatchRowHeight,
                   maxHeight: Tokens.Size.settingsAddressMatchRowHeight, alignment: .leading)
            .background(isSelected ? Color(nsColor: .selectedContentBackgroundColor).opacity(0.25) : .clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(match.line)
        .accessibilityLabel(TravelSettingsModel.matchRowLabel(match))
        .accessibilityAddTraits(.isButton)
    }
}

/// Task 14's sections (Ways to travel, Leave by, Where you are).
struct TravelWaysSections: View {
    let model: TravelSettingsModel
    var body: some View { EmptyView() }
}

/// Task 15's pane.
struct NotificationsSettingsPane: View {
    var body: some View { Form {}.formStyle(.grouped) }
}
