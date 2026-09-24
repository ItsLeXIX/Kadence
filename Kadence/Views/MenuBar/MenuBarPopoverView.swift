//
//  MenuBarPopoverView.swift
//  Kadence
//
//  components.md §15.2 — the menu bar extra's popover: NEXT, then REST OF
//  TODAY, at `Tokens.Size.popoverWidth`.
//
//  Scope for P2-T25 (done): `Done` and the Late state's `Re-offer` are wired
//  to real `EventStore` verbs. Neither closes the popover (interactions.md
//  §12): both just let the next `NextUpProvider.evaluate` pass (driven by
//  SwiftData's own change notification through `@Query`) recompute NEXT/REST
//  OF TODAY, so the resolved item simply drops out.
//
//  Scope for this task (P2-T26): `Snooze` is wired — clicking it, or
//  `⌥⌘↩` while the popover has key focus (interactions.md §12's Snooze row
//  only), calls `EventStore.snooze(_:)` on NEXT and replaces the action row
//  in place with a same-height result row (components.md §16), cross-fading
//  over `motion.selection` and holding for `motion.snoozeConfirmHold`,
//  pausing on hover (interactions.md §12.1). `Undo` in that row and the
//  global `⌘Z` both undo the snooze as the one named step
//  `EventStore.snooze` pushes.
//
//  Still explicitly deferred, same discipline as P2-T25's own scope note:
//  the `Open` button's action; the rest of interactions.md §12's keyboard
//  table (`↑`/`↓`/`↩`/`⌘↩`/`⎋` — only the `⌥⌘↩` binding is wired here); any
//  change to `RoutineEngine`, `ConflictEngine` or `TimeWindow`; and
//  components.md §16's third bullet — "if the main window is open and
//  showing the destination day, the block-move transition runs there too" —
//  which needs animation state coordinated across two separate SwiftUI
//  scenes (this popover's `MenuBarExtra` and `MainWindow`'s `WindowGroup`)
//  and is a separate concern from this task's in-popover result row.
//
//  One deviation this task's own wiring required: making `⌥⌘↩` reachable at
//  all needs the popover to actually hold key focus, and nothing before this
//  task ever granted it any (confirmed live — see the `.focused`/`.onAppear`
//  pair below). `design/`'s "only when opened by keyboard, not by click"
//  distinction is not built here either — this task does not attempt it, the
//  same as P2-T25 left the whole rule alone — so this build claims focus
//  unconditionally on every open instead. See `DEVIATIONS.md`.
//

import SwiftUI
import SwiftData
import Combine

struct MenuBarPopoverView: View {
    @Environment(\.modelContext) private var context
    @Environment(UndoStack.self) private var undoStack
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Query(sort: \Event.start) private var events: [Event]
    @State private var now = Date()

    /// Holds the currently-shown snooze result row, if any. `expectedStart`
    /// is what ties this to a *specific* mutation: if the event's start no
    /// longer matches it (an undo — in-row or global `⌘Z` — put it back, or
    /// `NextUpProvider` resolved a different event into NEXT), the result
    /// row stops matching and the normal action row renders again with no
    /// extra bookkeeping needed.
    private struct SnoozeConfirmation: Equatable {
        let eventID: UUID
        let expectedStart: Date
        let text: String
    }
    @State private var snoozeConfirmation: SnoozeConfirmation?
    @State private var isPointerInside = false
    @State private var revertTask: Task<Void, Never>?
    /// See the `.focused($isKeyFocused)`/`.onAppear` pair below for why this
    /// exists — `DEVIATIONS.md`'s note on it explains what it does and does
    /// not implement.
    @FocusState private var isKeyFocused: Bool

    private var store: EventStore { EventStore(context: context, undo: undoStack) }

    private var result: NextUpProvider.Result {
        NextUpProvider.evaluate(events: events, now: now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let next = result.next {
                nextSection(next: next, isLate: result.isLate)
                let rest = NextUpProvider.restDisplay(result.restOfToday)
                if !rest.rows.isEmpty {
                    Divider()
                    restSection(rest)
                }
            } else {
                emptySection
            }
        }
        .padding(.vertical, Tokens.Spacing.md)
        .frame(width: Tokens.Size.popoverWidth, alignment: .leading)
        .background(Tokens.Color.Surface.popover)
        .onReceive(
            Timer.publish(every: Tokens.Motion.NowLineTick.interval, on: .main, in: .common).autoconnect()
        ) { date in
            now = date
        }
        // interactions.md §12.1 — the result row "holds ... pausing while
        // hovered". The popover is small enough that pointer-anywhere-inside
        // is the right granularity; components.md §16 does not ask for a
        // narrower hover target.
        .onHover { isPointerInside = $0 }
        // interactions.md §12's keyboard table: "`⌥⌘↩` Snooze", only while
        // the popover has key focus. `keys: [.return]` filters before the
        // closure runs, so every other key this task does not own
        // (↑/↓/↩/⌘↩/⎋) passes through unhandled, exactly as the scope note
        // above requires.
        //
        // SwiftUI's `onKeyPress` only calls its handler while the modified
        // view (or a focused descendant) actually holds focus — `.focusable()`
        // alone makes this view ELIGIBLE for focus, it does not GRANT it, and
        // nothing else in this build ever does (confirmed live: without this
        // pair, `AXFocused` on every element here reads `false` even with the
        // popover's window key, and the handler never ran). `.onAppear` claims
        // focus unconditionally, every time the popover is shown — this build
        // does not implement interactions.md §12's finer "only when opened by
        // keyboard, not by click" distinction (that distinction was already
        // out of scope for the whole §12 keyboard table per P2-T25's own scope
        // note, and remains so here); see `DEVIATIONS.md`.
        .focusable()
        .focused($isKeyFocused)
        .onAppear { isKeyFocused = true }
        .onKeyPress(keys: [.return]) { press in
            guard press.modifiers.contains(.command), press.modifiers.contains(.option) else { return .ignored }
            guard let next = result.next else { return .ignored }
            performSnooze(next)
            return .handled
        }
    }

    // MARK: NEXT

    @ViewBuilder
    private func nextSection(next: Event, isLate: Bool) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            sectionLabel("NEXT")

            HStack(spacing: 0) {
                RailView(style: .solid, color: next.sourceKey.rail)
                VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
                    Text(next.title)
                        .typeStyle(.popoverNextTitle)
                        .foregroundStyle(Tokens.Color.Text.primary)
                    Text(MenuBarFormatting.nextMeta(for: next, now: now, isLate: isLate))
                        .typeStyle(.popoverNextMeta)
                        .foregroundStyle(isLate ? Tokens.Color.Semantic.now : Tokens.Color.Text.secondary)
                }
                .padding(.leading, Tokens.Spacing.sm)
            }
            .frame(minHeight: Tokens.Size.popoverNextBlockMinHeight, alignment: .leading)

            actionRow(next: next, isLate: isLate)
        }
        .padding(.horizontal, Tokens.Spacing.lg)
    }

    @ViewBuilder
    private func actionRow(next: Event, isLate: Bool) -> some View {
        // The result row only matches THIS `next` at THIS start — see
        // `SnoozeConfirmation`'s own doc comment for why that is what makes
        // an undo (in-row or global `⌘Z`) revert the swap automatically.
        let confirmation = snoozeConfirmation.flatMap {
            $0.eventID == next.id && $0.expectedStart == next.start ? $0 : nil
        }
        Group {
            if let confirmation {
                snoozeResultRow(confirmation)
            } else {
                normalActionRow(next: next, isLate: isLate)
            }
        }
        // components.md §16 / interactions.md §12.1 — cross-fade over
        // `motion.selection` (0.09s); Reduce Motion makes it an instant swap
        // (the same `reduceMotion ? nil : .easeInOut(...)` shape
        // `MainWindow.swift` already uses for its own Reduce-Motion gated
        // transitions).
        .animation(reduceMotion ? nil : .easeInOut(duration: Tokens.Motion.Selection.duration),
                   value: confirmation != nil)
    }

    @ViewBuilder
    private func normalActionRow(next: Event, isLate: Bool) -> some View {
        HStack(spacing: Tokens.Spacing.sm) {
            // §15.2 — "the late popover always offers Re-offer ... the
            // primary action in that state," leading the row.
            if isLate {
                Button("Re-offer") { store.markSkipped(next) }
            }
            Button("Done") { store.toggleDone(next) }
            Button("Snooze") { performSnooze(next) }
            // Disabled/inert per this task's own scope — see the file header.
            Button("Open") {}
                .disabled(true)
        }
        .frame(height: Tokens.Size.popoverActionRowHeight)
    }

    /// components.md §16: "the action row is replaced in place by a result
    /// row of the same height: `Moved to 19:15` + `Undo`, `popoverRow` type."
    @ViewBuilder
    private func snoozeResultRow(_ confirmation: SnoozeConfirmation) -> some View {
        HStack(spacing: Tokens.Spacing.sm) {
            Text(confirmation.text)
                .typeStyle(.popoverRow)
                .foregroundStyle(Tokens.Color.Text.primary)
            Button("Undo") { undoSnooze() }
        }
        .frame(height: Tokens.Size.popoverActionRowHeight)
    }

    // MARK: Snooze

    private func performSnooze(_ event: Event) {
        let oldStart = event.start
        let newStart = store.snooze(event)
        // A no-op `snooze` (e.g. a locked/imported event — see
        // `EventStore.snooze`'s own guard) returns the unchanged start; there
        // is nothing to confirm, so no result row and no undo step were
        // pushed. Matches every other guarded verb in `EventStore`.
        guard newStart != oldStart else { return }
        let confirmation = SnoozeConfirmation(
            eventID: event.id,
            expectedStart: newStart,
            text: MenuBarFormatting.snoozeResult(oldStart: oldStart, newStart: newStart))
        snoozeConfirmation = confirmation
        scheduleAutoRevert(matching: confirmation)
    }

    private func undoSnooze() {
        revertTask?.cancel()
        revertTask = nil
        undoStack.undo()
        snoozeConfirmation = nil
    }

    /// interactions.md §12.1: holds for `motion.snoozeConfirmHold` (4s),
    /// pausing while the pointer is inside the popover. Polled in short
    /// slices rather than one long `Task.sleep` so hover can pause it
    /// mid-hold; each slice re-checks `isPointerInside` and cancellation.
    private func scheduleAutoRevert(matching confirmation: SnoozeConfirmation) {
        revertTask?.cancel()
        revertTask = Task { @MainActor in
            var remaining = Tokens.Motion.SnoozeConfirmHold.duration
            let slice: Double = 0.1
            while remaining > 0 {
                if Task.isCancelled { return }
                if isPointerInside {
                    try? await Task.sleep(nanoseconds: UInt64(slice * 1_000_000_000))
                    continue
                }
                let step = min(slice, remaining)
                try? await Task.sleep(nanoseconds: UInt64(step * 1_000_000_000))
                if Task.isCancelled { return }
                remaining -= step
            }
            // Only revert if nothing else (a second snooze, an undo) already
            // changed what is showing.
            guard snoozeConfirmation == confirmation else { return }
            snoozeConfirmation = nil
        }
    }

    // MARK: REST OF TODAY

    @ViewBuilder
    private func restSection(_ rest: NextUpProvider.RestDisplay) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            sectionLabel("REST OF TODAY")
                .padding(.top, Tokens.Spacing.sm)

            // §15.2: "Times are monospaced and left-aligned in a fixed
            // column so the list scans vertically." `design/` names no pixel
            // width for that column, so rather than invent one, `Grid` sizes
            // the time column to its own widest cell — every time in this
            // list is 5 monospaced-digit characters (`HH:mm`), so every row
            // already lines up, with no literal number to get wrong or to
            // have to defend later.
            Grid(alignment: .leading, horizontalSpacing: Tokens.Spacing.sm, verticalSpacing: 0) {
                ForEach(rest.rows, id: \.id) { event in
                    GridRow {
                        Text(MenuBarFormatting.time(event.start))
                            .typeStyle(.popoverRow)
                            .foregroundStyle(Tokens.Color.Text.primary)
                            .frame(height: Tokens.Size.popoverRestRowHeight, alignment: .leading)
                        Text(event.title)
                            .typeStyle(.popoverRow)
                            .foregroundStyle(Tokens.Color.Text.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(height: Tokens.Size.popoverRestRowHeight, alignment: .leading)
                    }
                }
            }

            if rest.moreCount > 0 {
                Text("+\(rest.moreCount) more")
                    .typeStyle(.popoverRow)
                    .foregroundStyle(Tokens.Color.Text.secondary)
                    .frame(height: Tokens.Size.popoverRestRowHeight, alignment: .leading)
            }
        }
        .padding(.horizontal, Tokens.Spacing.lg)
    }

    // MARK: Empty

    private var emptySection: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.sm) {
            sectionLabel("NEXT")
            Text("Nothing left today")
                .typeStyle(.popoverNextTitle)
                .foregroundStyle(Tokens.Color.Text.secondary)
                .frame(minHeight: Tokens.Size.popoverNextBlockMinHeight, alignment: .leading)
        }
        .padding(.horizontal, Tokens.Spacing.lg)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .typeStyle(.popoverSectionLabel)
            .foregroundStyle(Tokens.Color.Text.secondary)
    }
}
