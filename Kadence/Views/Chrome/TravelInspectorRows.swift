//
//  TravelInspectorRows.swift
//  Kadence
//
//  Phase 3 slice 2 (PHASE3-SLICE2-PLAN.md task 16) — layouts.md §6 / §6.1
//  (amended 2026-10-14): the inspector's `Place` and `Leave by` rows.
//  `Place` is a pop-up for a manual event (`None` · places · `Edit
//  Places…`, one `Set Place` undo step) and text for an imported one; a
//  second line says `No travel needed after …` when the event chains from
//  its own place. `Leave by` shows the leg in its four states with §24.10's
//  sentences and buttons. Never `semantic.now` (4.25:1 on the inspector).
//

import SwiftUI
import SwiftData

struct TravelInspectorRows: View {
    let event: Event
    let store: EventStore
    let now: Date

    /// Optional: a view rendered without the travel environment (older
    /// renders and tests) draws no travel rows.
    @Environment(TravelCoordinator.self) private var travelCoordinator: TravelCoordinator?
    @Environment(SourcesRouter.self) private var router: SourcesRouter?
    @Environment(\.openSettings) private var openSettings

    private static let editPlacesTag = "__edit-places__"

    private func places(_ travel: TravelCoordinator) -> [KnownPlace] {
        _ = travel.revision
        return ((try? travel.context.fetch(FetchDescriptor<KnownPlace>())) ?? [])
            .sorted { ($0.sortIndex, $0.name) < ($1.sortIndex, $1.name) }
    }

    /// The event's place (§23.2), resolved the way the planner does.
    private func placeID(_ travel: TravelCoordinator, places: [KnownPlace]) -> String? {
        let kinds = Dictionary(((try? travel.context.fetch(FetchDescriptor<Source>())) ?? []).map { ($0.id, $0.kind) },
                               uniquingKeysWith: { a, _ in a })
        return PlaceResolver.place(of: TravelEventSnapshot(event), sourceKinds: kinds,
                                   knownPlaceIDs: Set(places.map(\.id)))
    }

    var body: some View {
        if let travel = travelCoordinator {
            rows(travel)
        }
    }

    @ViewBuilder
    private func rows(_ travel: TravelCoordinator) -> some View {
        let known = places(travel)
        let names = Dictionary(known.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
        let resolved = placeID(travel, places: known)
        let chained = travel.chainedTitle(for: event.id)

        if event.origin == .manual {
            row("Place") {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                    Picker("Place", selection: Binding(
                        get: { event.placeID ?? "" },
                        set: { choose($0, travel: travel) })) {
                        Text("None").tag("")
                        Divider()
                        ForEach(known, id: \.id) { place in Text(place.name).tag(place.id) }
                        Divider()
                        Text("Edit Places…").tag(Self.editPlacesTag)
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityLabel("Place")
                    .accessibilityValue(event.placeID.flatMap { names[$0] } ?? "None")
                    if resolved != nil, let chained { secondary(TravelPresentation.noTravelLine(previousTitle: chained)) }
                }
            }
        } else if let resolved {
            row("Place") {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                    Text(names[resolved] ?? resolved).typeStyle(.inspectorValue)
                    if let chained { secondary(TravelPresentation.noTravelLine(previousTitle: chained)) }
                }
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Place, \(names[resolved] ?? resolved)"
                                + (chained.map { ", \(TravelPresentation.noTravelLine(previousTitle: $0).lowercasedFirst)" } ?? ""))
        }

        if let leg = travel.leg(for: event.id).map(LegValues.init) {
            let model = TravelPresentation.leaveBy(leg, placeNames: names, now: now,
                                                   pausedUntil: travel.queue.plannerState.pausedUntil,
                                                   calendar: travel.calendar)
            row("Leave by") {
                VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                    HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.xs) {
                        Text(model.value)
                            .typeStyle(.inspectorValue)
                            .monospacedDigit()
                            .foregroundStyle(model.valueIsSecondary ? Tokens.Color.Text.secondary : Tokens.Color.Text.primary)
                        if let word = model.word { secondary(word) }
                    }
                    ForEach(Array(model.lines.enumerated()), id: \.offset) { _, line in secondary(line) }
                    if let action = model.action {
                        Button(action.rawValue) { perform(action, leg: leg, travel: travel) }
                            .buttonStyle(.borderless)
                            .typeStyle(.inspectorValue)
                            .foregroundStyle(Tokens.Color.Interactive.link)
                            .disabled(model.disabledHelp != nil)
                            .help(model.disabledHelp ?? "")
                            .accessibilityLabel(action.rawValue.replacingOccurrences(of: "…", with: ""))
                    }
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(model.spoken)
        }
    }

    private func choose(_ tag: String, travel: TravelCoordinator) {
        if tag == Self.editPlacesTag { return openTravelSettings(focus: nil) }
        store.setPlace(event, to: tag.isEmpty ? nil : tag)
    }

    private func perform(_ action: TravelPresentation.LeaveByRow.Action, leg: LegValues, travel: TravelCoordinator) {
        if let focus = Self.focus(for: action, leg: leg) { return openTravelSettings(focus: focus) }
        travel.tryAgain(eventID: event.id)
    }

    /// Where `Add Address…` and `Change Way to Travel…` take the user
    /// (layouts.md §13 "Focus"); nil for `Try Again`.
    static func focus(for action: TravelPresentation.LeaveByRow.Action, leg: LegValues) -> SourcesRouter.TravelFocus? {
        switch action {
        case .addAddress: .address(placeID: leg.reasonPlaceID ?? BuiltInPlace.home.id)
        case .changeWay: .pair(leg.originPlaceID ?? BuiltInPlace.home.id, leg.destinationPlaceID)
        case .tryAgain: nil
        }
    }

    /// The `Place` pop-up's items, in order: `None`, a separator, the places
    /// by `sortIndex`, a separator, `Edit Places…` (layouts.md §6).
    static func popupItems(placeNames: [String]) -> [String] {
        ["None", "—"] + placeNames + ["—", "Edit Places…"]
    }

    private func openTravelSettings(focus: SourcesRouter.TravelFocus?) {
        router?.settingsTab = .travel
        router?.travelFocus = focus
        openSettings()
    }

    private func row(_ label: String, @ViewBuilder content: () -> some View) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Tokens.Spacing.md) {
            Text(label)
                .typeStyle(.inspectorLabel)
                .foregroundStyle(Tokens.Color.Text.secondary)
                .frame(width: 84, alignment: .leading)
            content()
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
}

extension String {
    /// `No travel needed …` → `no travel needed …` (spoken mid-sentence).
    var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}
