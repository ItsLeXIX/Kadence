//
//  MenuBarStatusItemView.swift
//  Kadence
//
//  The status item's own label (components.md §15.1), used as
//  `MenuBarExtra`'s `label:` closure in `KadenceApp.swift`.
//
//  Task P2-T47 (resolves DEVIATIONS B14 and B15): the label measures the
//  time, the separator and the title with the `statusItem` font and lets
//  `StatusItemLayout` decide, then builds ONE string with the title already
//  truncated by measurement (`StatusItemLabel.text`). A `MenuBarExtra` label
//  keeps only one image and one text, so the time can't be a separate view;
//  instead it is simply never part of what gets cut. Below
//  `size.statusItemTitleMinWidth` of room the item shows the time alone, and
//  the item is only as wide as its text (at most the budget).
//

import SwiftUI
import SwiftData
import Combine
import AppKit

struct MenuBarStatusItemView: View {
    /// `@Query` does not populate in a `MenuBarExtra` label view on macOS —
    /// the label is hosted as an `NSView` outside the normal SwiftUI scene
    /// hierarchy, so the model-container environment never reaches `@Query`.
    /// Work around this by fetching directly from the container's main
    /// context on each timer tick (the same interval the `now` clock already
    /// uses, so no extra wakeups).
    let container: ModelContainer
    @State private var events: [Event] = []
    @State private var now = Date()

    var body: some View {
        // `MenuBarExtra` gives its label no width to measure against: the
        // menu bar hides an item that doesn't fit rather than narrowing it.
        // So the budget itself is the available width here; the degrade rule
        // still applies whenever the content needs more than it.
        StatusItemLabel(
            result: NextUpProvider.evaluate(events: events, now: now),
            now: now,
            available: Tokens.Size.statusItemMaxWidth)
            // interactions.md §12.1 — "the status item's text changes
            // without animation — it updates on a timer and any animation in
            // a menu bar reads as a glitch." Everything the label reads
            // (`now`, `events`) only ever changes through the timer tick or
            // a SwiftData notification below, so silencing the implicit
            // transaction here covers every update path, not just the timer.
            .transaction { $0.animation = nil }
            .onReceive(
                Timer.publish(every: Tokens.Motion.NowLineTick.interval, on: .main, in: .common).autoconnect()
            ) { date in
                now = date
                fetchEvents()
            }
            .onAppear { fetchEvents() }
    }

    private func fetchEvents() {
        let descriptor = FetchDescriptor<Event>(sortBy: [SortDescriptor(\Event.start)])
        events = (try? container.mainContext.fetch(descriptor)) ?? []
    }
}

/// The status item's drawn content for one `NextUpProvider.Result`, laid out
/// by `StatusItemLayout` within `available` points (task P2-T47). Separate
/// from the fetching wrapper above so it can be rendered for §17.1 item 10's
/// fixed rows (any `now`, any width) without a store.
struct StatusItemLabel: View {
    let result: NextUpProvider.Result
    let now: Date
    let available: CGFloat

    /// The `statusItem` type as an `NSFont`, for measuring: 13pt medium with
    /// monospaced digits, the same face `.typeStyle(.statusItem)` draws.
    static var measuringFont: NSFont {
        NSFont.monospacedDigitSystemFont(
            ofSize: Tokens.Typography.StatusItem.size,
            weight: Tokens.Typography.StatusItem.weight == "medium" ? .medium : .regular)
    }

    static func width(of text: String) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        return ceil((text as NSString).size(withAttributes: [.font: measuringFont]).width)
    }

    static let separator = " · "
    static let lateGlyph = "clock.badge.exclamationmark"

    /// The late glyph's drawn width plus the `spacing.xxs` gap after it:
    /// "the glyph and the elapsed figure together replace the time in this
    /// calculation" (§15.1).
    static var lateGlyphWidth: CGFloat {
        let config = NSImage.SymbolConfiguration(pointSize: Tokens.Size.statusItemGlyphSize, weight: .regular)
        let image = NSImage(systemSymbolName: lateGlyph, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        return ceil(image?.size.width ?? Tokens.Size.statusItemGlyphSize) + Tokens.Spacing.xxs
    }

    /// The single string the item shows (no glyph): `17:30 · Training`,
    /// `17:30 · Statistik Üb…`, `17:30`, or `12m ago · Gym`.
    ///
    /// One string, not a time `Text` beside a title `Text`: a `MenuBarExtra`
    /// label is flattened into the status button's one image and one title,
    /// and a second `Text` is dropped (seen live in P2-T47: the AX title read
    /// `640m ago` with `Breakfast` missing). So the title is truncated here,
    /// by measurement, rather than by `.truncationMode`. The time is never
    /// part of what gets cut.
    static func text(for result: NextUpProvider.Result, now: Date, available: CGFloat) -> String? {
        guard let next = result.next else { return nil }
        let primary = result.isLate
            ? MenuBarFormatting.elapsed(since: next.start, now: now)
            : MenuBarFormatting.time(next.start)
        let separatorWidth = width(of: separator)
        let layout = StatusItemLayout.resolve(
            leadingWidth: width(of: primary) + (result.isLate ? lateGlyphWidth : 0),
            separatorWidth: separatorWidth,
            titleWidth: width(of: next.title),
            available: available)
        guard layout.showsTitle else { return primary }
        return primary + separator + truncated(next.title, toFit: layout.titleSlotWidth - separatorWidth)
    }

    /// `title` if it fits in `width`, otherwise its longest prefix that fits
    /// with `…` after it ("truncates tail-first", §15.1).
    static func truncated(_ title: String, toFit width: CGFloat) -> String {
        guard Self.width(of: title) > width else { return title }
        var prefix = Substring(title)
        while !prefix.isEmpty {
            prefix = prefix.dropLast()
            let candidate = prefix.trimmingCharacters(in: .whitespaces) + "…"
            if Self.width(of: candidate) <= width { return candidate }
        }
        return "…"
    }

    var body: some View {
        if let text = Self.text(for: result, now: now, available: available) {
            HStack(spacing: Tokens.Spacing.xxs) {
                if result.isLate {
                    Image(systemName: Self.lateGlyph)
                        .font(.system(size: Tokens.Size.statusItemGlyphSize))
                }
                Text(text)
                    .typeStyle(.statusItem)
                    .fixedSize()
            }
            .foregroundStyle(result.isLate ? Tokens.Color.Semantic.now : Tokens.Color.Text.primary)
        } else {
            Text("Nothing left today")
                .typeStyle(.statusItem)
                .foregroundStyle(Tokens.Color.Text.secondary)
                .fixedSize()
        }
    }
}
