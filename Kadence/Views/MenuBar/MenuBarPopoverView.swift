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
//  Task P2-F18 (components.md §15.2, interactions.md §12, both amended
//  2026-10-05): `Open` is wired and always enabled; the whole keyboard table
//  (`↑`/`↓`/`↩`/`⌘↩`/`⌥⌘↩`/`⎋`) runs through `MenuBarPopoverKeys`;
//  `Re-offer` is the late state's prominent primary action. Key focus on
//  every open is now spec, not a deviation.
//
//  Still deferred, by ruling (interactions.md §12, 2026-10-05; logged in
//  DEVIATIONS as an A-entry): components.md §16's third bullet — "if the
//  main window is open and showing the destination day, the block-move
//  transition runs there too" — which needs animation state shared across
//  two scenes (this `MenuBarExtra` and `MainWindow`'s `WindowGroup`).
//

import SwiftUI
import AppKit
import SwiftData
import Combine

struct MenuBarPopoverView: View {
    @Environment(\.modelContext) private var context
    @Environment(UndoStack.self) private var undoStack
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Task P2-F18: `Open` selects the item in the main window.
    @Environment(CalendarState.self) private var calendarState
    @Environment(\.openWindow) private var openWindow
    /// Closes the `MenuBarExtra` window (interactions.md §12's `⎋`).
    @Environment(\.dismiss) private var dismiss
    /// interactions.md §12: 0 is NEXT, 1… the rest rows (`↑`/`↓`).
    @State private var focusIndex = 0
    @Query(sort: \Event.start) private var events: [Event]
    @State private var now = Date()

    /// Holds the currently-shown snooze result row, if any. `expectedStart`
    /// is what ties this to a *specific* mutation: if the event's start no
    /// longer matches it (an undo — in-row or global `⌘Z` — put it back, or
    /// `NextUpProvider` resolved a different event into NEXT), the result
    /// row stops matching and the normal action row renders again with no
    /// extra bookkeeping needed.
    ///
    /// A refusal (components.md §16, amended 2026-10-06) is held the same
    /// way: nothing moved, so `expectedStart` is the unchanged start and the
    /// row shows until the hold ends; `isRefusal` drops `Undo`.
    struct SnoozeConfirmation: Equatable {
        let eventID: UUID
        let expectedStart: Date
        let text: String
        var isRefusal = false

        /// The row for what `EventStore.snooze` returned, or nil when there
        /// is nothing to show (`.unchanged`: no write, no row). The button
        /// and `⌥⌘↩` both come through here, so they can't disagree.
        static func make(for event: Event, oldStart: Date,
                         result: EventStore.SnoozeResult) -> SnoozeConfirmation? {
            switch result {
            case .moved(let newStart):
                return SnoozeConfirmation(
                    eventID: event.id, expectedStart: newStart,
                    text: MenuBarFormatting.snoozeResult(oldStart: oldStart, newStart: newStart))
            case .refused(let start, let label):
                return SnoozeConfirmation(
                    eventID: event.id, expectedStart: oldStart,
                    text: MenuBarFormatting.snoozeRefused(start: start, windowLabel: label),
                    isRefusal: true)
            case .unchanged:
                return nil
            }
        }

        /// Snoozes `event` and returns the row to show. The one path both
        /// the `Snooze` button and `⌥⌘↩` take (via `performSnooze`).
        static func perform(_ event: Event, store: EventStore) -> SnoozeConfirmation? {
            let oldStart = event.start
            return make(for: event, oldStart: oldStart, result: store.snooze(event))
        }
    }
    @State private var snoozeConfirmation: SnoozeConfirmation?

    /// Task P2-T48: the popover's starting clock and snooze state. Defaults
    /// are a normal open (the real clock, no result row). §17.1 pins items 11
    /// and 12 to fixed times (`now` = 17:10, 17:42, 23:40), which the real
    /// menu bar can't be set to, so `KadenceTests/PopoverCaptureTests.swift`
    /// renders this same view with them. Swift note: `State(initialValue:)`
    /// is how an initializer seeds an `@State` property.
    init(initialNow: Date = Date(), initialSnooze: SnoozeConfirmation? = nil, initialFocusIndex: Int = 0) {
        _now = State(initialValue: initialNow)
        _focusIndex = State(initialValue: initialFocusIndex)
        self.initialFocusIndex = initialFocusIndex
        _snoozeConfirmation = State(initialValue: initialSnooze)
    }
    /// Where focus starts on every open: NEXT (0). Only the render tests
    /// pass another index (P2-SF1's NEXT-focus check).
    private let initialFocusIndex: Int
    @State private var isPointerInside = false
    @State private var revertTask: Task<Void, Never>?
    /// See the `.focused($isKeyFocused)`/`.onAppear` pair below for why this
    /// exists — `DEVIATIONS.md`'s note on it explains what it does and does
    /// not implement.
    @FocusState private var isKeyFocused: Bool

    private var store: EventStore { EventStore(context: context, undo: undoStack) }

    private var result: NextUpProvider.Result {
        // Task P2-T49: a held snooze confirmation keeps its event as NEXT,
        // at the time it landed, even across midnight (§16).
        NextUpProvider.pinning(
            NextUpProvider.evaluate(events: events, now: now),
            events: events,
            to: snoozeConfirmation.map { ($0.eventID, $0.expectedStart) })
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
        // interactions.md §1 / §12 (amended 2026-10-06, G-039): no ring
        // around the popover's root — it showed as a ~1px accent line on
        // the live popover's edge. The `hoverOverlay` behind the focused
        // row (NEXT included) is the popover's only focus indicator.
        .focusEffectDisabled()
        .focused($isKeyFocused)
        // interactions.md §12 (amended 2026-10-05): key focus on EVERY open,
        // click or keyboard — now spec, no longer a deviation.
        .onAppear { isKeyFocused = true; focusIndex = initialFocusIndex }
        // The whole keyboard table (task P2-F18), decided by the pure
        // `MenuBarPopoverKeys`.
        .onKeyPress(keys: [.return, .upArrow, .downArrow, .escape]) { press in
            handleKey(press)
        }
    }

    /// NEXT, then the listed rest rows — what `↑`/`↓` move through.
    private var focusableItems: [Event] {
        guard let next = result.next else { return [] }
        return [next] + NextUpProvider.restDisplay(result.restOfToday).rows
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        let items = focusableItems
        guard let action = MenuBarPopoverKeys.action(
            key: press.key, modifiers: press.modifiers, focus: focusIndex, rowCount: items.count)
        else { return .ignored }
        switch action {
        case .focus(let index): focusIndex = index
        case .open(let index): open(items[index])
        case .done: if let next = result.next { store.toggleDone(next) }
        case .snooze: if let next = result.next { performSnooze(next) }
        case .close: dismiss()
        }
        return .handled
    }

    private func perform(_ kind: MenuBarPopoverKeys.ActionButton.Kind, on next: Event) {
        switch kind {
        case .reoffer: store.markSkipped(next)
        case .done: store.toggleDone(next)
        case .snooze: performSnooze(next)
        case .open: open(next)
        }
    }

    /// components.md §15.2 (amended 2026-10-05): `Open` is always enabled —
    /// activate the main window (opening it if it is closed), page to the
    /// item's day and select it. The popover then closes, as a menu does when
    /// it takes you somewhere.
    private func open(_ event: Event) {
        calendarState.reveal(event)
        NSApplication.shared.activate()
        if let main = NSApplication.shared.windows.first(where: {
            $0.isVisible && $0.canBecomeMain && !RoutinesWindowOpener.isRoutinesWindow(identifier: $0.identifier?.rawValue)
        }) {
            main.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        dismiss()
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
            .frame(maxWidth: .infinity, minHeight: Tokens.Size.popoverNextBlockMinHeight, alignment: .leading)
            // interactions.md §12 (amended 2026-10-06): while NEXT is focused
            // (every open starts there), `hoverOverlay` behind the next-item
            // block's full width at `radius.card` — the rest rows' focus
            // treatment, so the popover has one focus vocabulary.
            .background {
                if focusIndex == 0 {
                    RoundedRectangle(cornerRadius: Tokens.Radius.card, style: .continuous)
                        .fill(Tokens.Color.Interactive.hoverOverlay)
                }
            }

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
            ForEach(MenuBarPopoverKeys.actionButtons(isLate: isLate), id: \.kind) { button in
                let action = { perform(button.kind, on: next) }
                // §15.2 (amended 2026-10-05): `Re-offer` is the late state's
                // primary — `.borderedProminent` (accent), leading, NO key
                // equivalent (`↩` opens the focused item). The rest are
                // `.bordered`; `Open` is always enabled.
                if button.isProminent {
                    Button(button.title, action: action).buttonStyle(.borderedProminent)
                } else {
                    Button(button.title, action: action).buttonStyle(.bordered)
                }
            }
        }
        .frame(height: Tokens.Size.popoverActionRowHeight)
    }

    /// components.md §16: "the action row is replaced in place by a result
    /// row of the same height: `Moved to 19:15` + `Undo`, `popoverRow` type."
    /// A refusal (amended 2026-10-06) is the same row with no `Undo` —
    /// nothing was written, so there is nothing to undo.
    @ViewBuilder
    private func snoozeResultRow(_ confirmation: SnoozeConfirmation) -> some View {
        HStack(spacing: Tokens.Spacing.sm) {
            // SPEC-GAP G-051: the refused copy (`Not moved — 00:05 is inside
            // Sleep (protected)`) is wider than `popoverWidth` less the
            // insets in `popoverRow`, and the row's height is fixed, so it
            // tail-truncates. Left as is until design/ rules.
            Text(confirmation.text)
                .typeStyle(.popoverRow)
                .foregroundStyle(Tokens.Color.Text.primary)
            if !confirmation.isRefusal {
                Button("Undo") { undoSnooze() }
            }
        }
        .frame(height: Tokens.Size.popoverActionRowHeight)
    }

    // MARK: Snooze

    private func performSnooze(_ event: Event) {
        // `.unchanged` (a locked/imported event — see `EventStore.snooze`'s
        // own guard) gives no row; nothing was written, no undo step pushed.
        // `.refused` gives the `Not moved — …` row, also with no write.
        guard let confirmation = SnoozeConfirmation.perform(event, store: store) else { return }
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
            // One `HStack` per row (task P2-F18: was a `Grid`, whose
            // `GridRow` backgrounds are per cell, so a focused row could not
            // be one full-width highlight). The time column still lines up:
            // every time is 5 monospaced-digit characters (`HH:mm`).
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(rest.rows.enumerated()), id: \.element.id) { offset, event in
                    HStack(spacing: Tokens.Spacing.sm) {
                        Text(MenuBarFormatting.time(event.start))
                            .typeStyle(.popoverRow)
                            .foregroundStyle(Tokens.Color.Text.primary)
                        Text(event.title)
                            .typeStyle(.popoverRow)
                            .foregroundStyle(Tokens.Color.Text.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(maxWidth: .infinity, minHeight: Tokens.Size.popoverRestRowHeight,
                           maxHeight: Tokens.Size.popoverRestRowHeight, alignment: .leading)
                    // interactions.md §12 (amended 2026-10-05): the focused
                    // rest row draws `hoverOverlay` behind its full width at
                    // `radius.chip` — the hovered-row treatment. Index 0 is
                    // NEXT, so rest row `offset` is focus index `offset + 1`.
                    .background {
                        if focusIndex == offset + 1 {
                            RoundedRectangle(cornerRadius: Tokens.Radius.chip, style: .continuous)
                                .fill(Tokens.Color.Interactive.hoverOverlay)
                        }
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
