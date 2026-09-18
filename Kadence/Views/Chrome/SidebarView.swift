//
//  SidebarView.swift
//  Kadence
//
//  layouts.md §2.
//

import SwiftUI

struct SidebarView: View {
    @Environment(CalendarState.self) private var state

    var body: some View {
        @Bindable var state = state

        List {
            // components.md §10.2 — hidden entirely at zero (no empty-state
            // counter, no zero badge) and no icon: "its text and its count
            // already separate it from the swatch-prefixed source rows
            // below, and a bare label separates it better than any glyph
            // would." §14.1 — "The needs-attention row (§10.2) is a button.
            // Activating it selects the first unresolved conflict and puts
            // the inspector into conflict mode."
            if !state.conflicts.isEmpty {
                Button {
                    state.activateNeedsAttention()
                } label: {
                    HStack {
                        Text("Needs attention")
                            .typeStyle(.sidebarItem)
                            .foregroundStyle(Tokens.Color.Text.primary)
                        Spacer()
                        countBadge(state.conflicts.count)
                    }
                }
                .buttonStyle(.plain)
                .frame(height: 24)
            }

            Section {
                ForEach(MockData.sources) { source in
                    HStack(spacing: Tokens.Spacing.sm) {
                        SourceSwatch(key: source.key, symbol: source.symbol,
                                     isOn: !state.hiddenSources.contains(source.key))
                        Text(source.name)
                            .typeStyle(.sidebarItem)
                            .foregroundStyle(Tokens.Color.Text.primary)
                        Spacer(minLength: 0)
                        Toggle("", isOn: Binding(
                            get: { !state.hiddenSources.contains(source.key) },
                            set: { isOn in
                                if isOn { state.hiddenSources.remove(source.key) }
                                else { state.hiddenSources.insert(source.key) }
                            }))
                            .labelsHidden()
                            .toggleStyle(.checkbox)
                    }
                    .frame(height: 24)
                    .accessibilityElement(children: .combine)
                }
            } header: {
                Text("Sources")
                    .typeStyle(.sidebarSection)
                    .foregroundStyle(Tokens.Color.Text.secondary)
            }

            Section {
                Toggle("All-day only", isOn: $state.showAllDayOnly).frame(height: 24)
                Toggle("Timed only", isOn: $state.showTimedOnly).frame(height: 24)
                Toggle("Hide done", isOn: $state.hideDone).frame(height: 24)
                Toggle("Hide skipped", isOn: $state.hideSkipped).frame(height: 24)
            } header: {
                Text("Filters")
                    .typeStyle(.sidebarSection)
                    .foregroundStyle(Tokens.Color.Text.secondary)
            }
            .toggleStyle(.checkbox)
        }
        .listStyle(.sidebar)
        .environment(\.defaultMinListRowHeight, 24)
    }

    /// components.md §10.2 — never red, never a filled alert colour.
    private func countBadge(_ count: Int) -> some View {
        Text("\(count)")
            .typeStyle(.blockMeta)
            .foregroundStyle(Tokens.Color.Text.secondary)
            .padding(.horizontal, Tokens.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip, style: .continuous)
                    .fill(Tokens.Color.Surface.canvasSunken))
    }
}

/// components.md §10.1 — the symbol is what makes the legend work without colour.
struct SourceSwatch: View {
    let key: SourceKey
    /// From `CalendarSource.symbol` — components.md §10.1. It belongs to the
    /// source, never to the palette slot.
    let symbol: String
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(isOn ? key.solid : Tokens.Color.Surface.canvas)
            .overlay {
                if !isOn {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(key.rail, lineWidth: 1)
                }
                Image(systemName: symbol)
                    .font(.system(size: 9))
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(isOn ? Tokens.Color.Text.onSolid : key.text)
            }
            .frame(width: 11, height: 11)
            .accessibilityHidden(true)
    }
}
