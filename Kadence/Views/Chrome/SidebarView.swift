//
//  SidebarView.swift
//  Kadence
//
//  layouts.md §2.
//

import SwiftUI

struct SidebarView: View {
    let needsAttentionCount: Int

    @Environment(CalendarState.self) private var state

    var body: some View {
        @Bindable var state = state

        List {
            // Hidden entirely at zero — no empty-state counter, no zero badge.
            // Phase 1 always supplies zero; Phase 2 supplies the data.
            if needsAttentionCount > 0 {
                Label {
                    HStack {
                        Text("Needs attention").typeStyle(.sidebarItem)
                        Spacer()
                        countBadge(needsAttentionCount)
                    }
                } icon: {
                    Image(systemName: "tray.full")
                }
                .frame(height: 24)
            }

            Section {
                ForEach(MockData.sources) { source in
                    HStack(spacing: Tokens.Spacing.sm) {
                        SourceSwatch(key: source.key, isOn: !state.hiddenSources.contains(source.key))
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
    let isOn: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: 3, style: .continuous)
            .fill(isOn ? key.solid : Tokens.Color.Surface.canvas)
            .overlay {
                if !isOn {
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .strokeBorder(key.rail, lineWidth: 1)
                }
                Image(systemName: key.swatchSymbol)
                    .font(.system(size: 9))
                    .foregroundStyle(isOn ? Tokens.Color.Text.onSolid : key.text)
            }
            .frame(width: 11, height: 11)
            .accessibilityHidden(true)
    }
}
