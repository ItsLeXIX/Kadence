//
//  MenuBarStatusItemView.swift
//  Kadence
//
//  The status item's own label (components.md §15.1), used as
//  `MenuBarExtra`'s `label:` closure in `KadenceApp.swift`.
//
//  Primary text and title are rendered as a single concatenated `Text` so
//  that the menu bar extra's label reports the full intrinsic width to the
//  system — two separate `Text` views in an `HStack` caused the truncatable
//  title to shrink to zero, leaving only the time visible (`@Query`-in-
//  label workaround commit, same session). The outer `frame(width:)` clips
//  at `statusItemMaxWidth`, so if the full string is wider than 180pt the
//  title truncates with `.tail` as §15.1 specifies.
//

import SwiftUI
import SwiftData
import Combine

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

    private var result: NextUpProvider.Result {
        NextUpProvider.evaluate(events: events, now: now)
    }

    var body: some View {
        content
            .frame(width: Tokens.Size.statusItemMaxWidth, alignment: .leading)
            .fixedSize()
            // interactions.md §12.1 — "the status item's text changes
            // without animation — it updates on a timer and any animation in
            // a menu bar reads as a glitch." Everything `content` reads
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

    @ViewBuilder
    private var content: some View {
        if let next = result.next {
            HStack(spacing: Tokens.Spacing.xxs) {
                if result.isLate {
                    Image(systemName: "clock.badge.exclamationmark")
                        .font(.system(size: Tokens.Size.statusItemGlyphSize))
                }
                primaryAndTitle(
                    primary: result.isLate
                        ? MenuBarFormatting.elapsed(since: next.start, now: now)
                        : MenuBarFormatting.time(next.start),
                    title: next.title)
            }
            .foregroundStyle(result.isLate ? Tokens.Color.Semantic.now : Tokens.Color.Text.primary)
        } else {
            Text("Nothing left today")
                .typeStyle(.statusItem)
                .foregroundStyle(Tokens.Color.Text.secondary)
        }
    }

    @ViewBuilder
    private func primaryAndTitle(primary: String, title: String) -> some View {
        // A single `Text` concatenation — the menu bar extra's label
        // sizing measures `sizeThatFits`, and a separate `Text` with
        // `.truncationMode(.tail)` reports a minimum width of zero,
        // collapsing the title entirely. Concatenating into one `Text`
        // gives the system the full intrinsic width, and the outer
        // `.frame(width:)` clips at `statusItemMaxWidth`.
        if title.isEmpty {
            Text(primary)
                .typeStyle(.statusItem)
        } else {
            Text("\(primary) · \(title)")
                .typeStyle(.statusItem)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
