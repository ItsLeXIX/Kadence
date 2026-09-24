//
//  MenuBarStatusItemView.swift
//  Kadence
//
//  The status item's own label (components.md §15.1), used as
//  `MenuBarExtra`'s `label:` closure in `KadenceApp.swift`.
//
//  The primary text — the clock time normally, the elapsed phrase once late
//  — is wrapped in `.fixedSize()`, which stops SwiftUI compressing it no
//  matter how little room `Tokens.Size.statusItemMaxWidth` leaves. The title
//  is the one `Text` given `.lineLimit(1)`/`.truncationMode(.tail)`, so it is
//  the only thing that can shrink or disappear. That makes "the time is
//  never truncated" (§15.1) a structural property of the view tree, not a
//  rule that merely usually holds at the widths this task happened to try.
//

import SwiftUI
import SwiftData
import Combine

struct MenuBarStatusItemView: View {
    @Query(sort: \Event.start) private var events: [Event]
    @State private var now = Date()

    private var result: NextUpProvider.Result {
        NextUpProvider.evaluate(events: events, now: now)
    }

    var body: some View {
        content
            .frame(maxWidth: Tokens.Size.statusItemMaxWidth, alignment: .leading)
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
            }
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
        HStack(spacing: Tokens.Spacing.xxs) {
            Text(primary)
                .typeStyle(.statusItem)
                .fixedSize()
            if !title.isEmpty {
                Text("· \(title)")
                    .typeStyle(.statusItem)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }
}
