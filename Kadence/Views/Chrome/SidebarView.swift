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
                    // §14.1: "The needs-attention row is a button" — the whole
                    // row, not just what it draws. A `.plain` button
                    // hit-tests only its label's drawn pixels, so the
                    // `Spacer()` gap between the text and the badge ignored
                    // clicks (DEVIATIONS.md B17). `.contentShape` declares
                    // the hit area explicitly: the HStack's full rectangle.
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(height: 24)
                // P2-T40: a `.plain` button inside a sidebar `List` row
                // reached the accessibility tree as an unnamed button: its
                // label's `Text`s were neither its description nor visible
                // children, so VoiceOver announced only "button".
                // `.accessibilityLabel` sets the element's name (AXDescription);
                // `.accessibilityValue` sets its value (AXValue). Both replace
                // whatever SwiftUI would derive from the label view.
                //
                // The name is the row's visible text. The count is the badge's
                // own number.
                // SPEC-GAP (design/GAPS.md G-029): neither components.md §10.2
                // nor §11 gives this row's spoken label or value. The bare
                // count is a placeholder; the spec may want e.g. a noun with it.
                .accessibilityLabel("Needs attention")
                .accessibilityValue("\(state.conflicts.count)")
                // Not spoken by VoiceOver. A stable handle for
                // `Scripts/check-conflict-apply-return.sh`, which reads the
                // tree through the AX API (task P2-T41).
                .accessibilityIdentifier("needs-attention-row")
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
