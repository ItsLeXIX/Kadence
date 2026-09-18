//
//  CalendarState.swift
//  Kadence
//
//  Everything the chrome and the canvases need that is not persisted.
//
//  Swift note: `@Observable` is the modern replacement for ObservableObject —
//  views that read a property automatically re-render when it changes, with no
//  @Published and no objectWillChange.
//

import SwiftUI
import Observation

@MainActor
@Observable
final class CalendarState {

    // MARK: Where we are

    var mode: CalendarMode = .week
    /// The anchor date. Month/Week/Day each derive their range from it.
    var anchor: Date = Date()

    // MARK: Selection and the keyboard cursor (interactions.md §1)

    var selectedEventID: UUID?
    /// Non-nil only in cursor mode: the keyboard's insertion point in time.
    /// This is what makes keyboard-only event creation possible.
    var timeCursor: Date?
    var focusedRegion: FocusRegion = .grid

    /// The new event being typed, if any.
    ///
    /// interactions.md §3 — "a new event appears immediately as a block … with an
    /// inline `TextField` in place of its title" and "an event created with no
    /// title is never persisted". The draft therefore lives here, NOT in the
    /// store: it is laid out and drawn like a block, but nothing reaches
    /// SwiftData until it is committed with a title. Inserting first and deleting
    /// on cancel is what left untitled events behind (DEVIATIONS.md A13).
    var draft: EventDraft?

    // MARK: Chrome

    /// **The** source of truth for sidebar visibility.
    ///
    /// `NavigationSplitView`'s `columnVisibility` is derived from this via
    /// `sidebarColumnVisibility` and a binding that writes back here, so the
    /// Edit-menu toggle, the toolbar button, auto-collapse and the split view's
    /// own divider all move the same value. They used to be two independent
    /// pieces of state that drifted apart.
    var isSidebarVisible = true
    var isInspectorVisible = true
    /// Set when the user explicitly toggles, so auto-collapse never overrides
    /// a deliberate choice (layouts.md §1.1).
    var userSetInspectorVisibility = false
    var userSetSidebarVisibility = false

    // MARK: Filters (layouts.md §2)

    var hiddenSources: Set<SourceKey> = []
    var showAllDayOnly = false
    var showTimedOnly = false
    var hideDone = false
    var hideSkipped = false

    // MARK: Clock

    /// Driven by a timer at `motion.nowLineTick.interval`.
    var now: Date = Date()

    // MARK: Conflicts (components.md §14, interactions.md §10.1/§10.2 — entry
    // point, preview, abandonment, and (P2-T17) `↩` apply.)

    /// Refreshed by `MainWindow` whenever the live `Event`/`RoutineBlock`
    /// queries change (`MainWindow.sortedConflicts(events:routineBlocks:)`,
    /// wired via `.onChange`). Kept here — not only computed inline in
    /// `MainWindow`'s body — so the needs-attention row (`SidebarView`), the
    /// `⌘⇧A` command (`KadenceCommands`) and the inspector's conflict-mode
    /// panel all read the exact same list and can never disagree about
    /// whether there is anything to select or what "first" means. Already
    /// sorted by `ConflictOrdering`, so `.first` always is "the first
    /// unresolved conflict" per that file's stable-order rule.
    ///
    /// "Unresolved" is every conflict `ConflictEngine.detect` currently
    /// reports: this task builds no apply step, so nothing here has a way to
    /// become resolved and drop out of the list on its own yet — that is the
    /// follow-up task's job.
    var conflicts: [Conflict] = []

    /// Which conflict the inspector's conflict-mode panel is showing, if any.
    /// `nil` means the inspector shows its ordinary event-details/day-summary
    /// content. Set by `activateNeedsAttention()`. Deliberately NOT cleared by
    /// `abandonConflictPreview()` — see that method's own doc comment for the
    /// scope decision — nor auto-cleared when the underlying conflict
    /// disappears (still the follow-up task's job, same as `↩` apply itself).
    var selectedConflictID: String?

    /// Which option row inside the active conflict is highlighted.
    ///
    /// P2-T15 wired this to the row highlight only
    /// (`color.interactive.selectedRowFill`). P2-T16 additionally drives a
    /// live canvas preview from it (`DayColumnView`) — every other
    /// consequence of "changing this id" (the proposed frame it previews,
    /// what reverting it means) lives there and in
    /// `moveSelectedConflictOption(by:)`/`abandonConflictPreview()` below.
    var selectedConflictOptionID: UUID?

    /// components.md §14.1 / interactions.md §10.1's first sentence:
    /// activating the needs-attention row (or `⌘⇧A`) selects the first
    /// unresolved conflict and puts the inspector into conflict mode. A
    /// no-op when there is nothing to select — the same guard that makes
    /// §10.2's row "hidden entirely at zero" and the shortcut "global, when
    /// the count is non-zero" both hold trivially at the call site.
    func activateNeedsAttention() {
        guard let first = conflicts.first else { return }
        selectedConflictID = first.id
        selectedConflictOptionID = nil
        selectedEventID = nil
        userSetInspectorVisibility = true
        isInspectorVisible = true
    }

    /// interactions.md §10.1 — "`↑`/`↓` move between options. Moving focus
    /// onto an option previews it immediately." Clamps at either end rather
    /// than wrapping: there is no "one past the last option" state worth
    /// landing on, the same engineering default `FocusRegion.next` documents
    /// its own (different: wrapping) choice against, and the one
    /// `ConflictEngine`'s own doc comments reach for whenever the spec is
    /// silent on a tie-break. A no-op when there is no active conflict or it
    /// has no options (never true post-`detect`, but a stale
    /// `selectedConflictID` — e.g. the underlying events changed out from
    /// under it — must not crash).
    func moveSelectedConflictOption(by direction: Int) {
        guard let conflict = conflicts.first(where: { $0.id == selectedConflictID }),
              !conflict.options.isEmpty
        else { return }

        let options = conflict.options
        guard let currentIndex = selectedConflictOptionID.flatMap(
            { id in options.firstIndex { $0.id == id } })
        else {
            // Nothing focused yet — either direction lands on the first
            // option; there is nothing "before" it to move up from.
            selectedConflictOptionID = options[0].id
            return
        }
        let nextIndex = max(0, min(options.count - 1, currentIndex + direction))
        selectedConflictOptionID = options[nextIndex].id
    }

    /// interactions.md §10.2 — abandonment is unconditional and needs no
    /// confirmation. Clears only the pending preview
    /// (`selectedConflictOptionID`); `selectedConflictID` is deliberately
    /// left alone.
    ///
    /// **Scope decision, recorded per this task's own brief:** §10.2's
    /// subject is "a pending preview", not "conflict mode" — the panel
    /// itself is not named among the things that revert. Reading it any
    /// wider (clearing `selectedConflictID` too) would mean `⇥` cycling
    /// through the inspector and back, or a stray `⎋`, silently kicks the
    /// user out of the conflict they were looking at with no way back except
    /// re-activating the needs-attention row — worse than doing nothing,
    /// since nothing in `components.md` §14.5 describes focus loss as a way
    /// to leave conflict mode (only "the last conflict is resolved" is).
    /// Documented in DEVIATIONS.md alongside the `.skipToday` preview
    /// treatment, per this task's own instructions.
    func abandonConflictPreview() {
        selectedConflictOptionID = nil
    }

    /// interactions.md §10.1's last paragraph / components.md §14.5 — `↩`
    /// applies the focused/previewed option.
    ///
    /// Writes the option to `store` as ONE named undo step
    /// (`"Resolve Conflict"` — `UndoStack.undoMenuTitle` prepends "Undo ",
    /// so the Edit menu reads exactly "Undo Resolve Conflict",
    /// interactions.md §10.1's own words), same composition pattern
    /// `EventStore.transaction`'s own doc comment documents: the primitive
    /// verb calls inside (`move`/`resize`/`markSkipped`) each open their own
    /// `UndoStack.perform`, but because the outer `"Resolve Conflict"` group
    /// is already open they join it instead of pushing steps of their own,
    /// so one ⌘Z reverts every block this option touched.
    ///
    /// Dropping the canvas's `size.previewCanvasBorder` border needs no code
    /// here beyond clearing `selectedConflictOptionID`: `MainWindow.canvas`'s
    /// `isConflictPreviewActive` (and `DayColumnView`'s matching
    /// `activeConflictPreview`) are already gated on exactly that field being
    /// non-nil, same as `abandonConflictPreview()` above. Likewise, running
    /// `motion.blockMove` on the committed frames needs no new animation
    /// here: `DayColumnView.blockStack` already keys `.animation(...,
    /// value: laidOut.frame)` on that spring for every block unconditionally
    /// (P2-T11), so a `start`/`end` written by `store` animates into place
    /// the same way any drag or resize already does.
    ///
    /// `recomputeConflicts` is the caller's job, not this method's: only
    /// `MainWindow` (or a test's own `ModelContext`) can re-run
    /// `ConflictEngine.detect` against the just-mutated data, since this
    /// class holds no query of its own. Called *after* `store`'s transaction
    /// runs, so its result is "what is still unresolved now" — the input
    /// `ConflictOrdering.firstUnresolved` needs to either preview the next
    /// conflict's first (== recommended — `ConflictEngine.finalize` already
    /// sorts ascending by disturbance and marks index 0 recommended) option,
    /// or, if nothing is left, return the inspector to its ordinary,
    /// non-conflict state: `selectedConflictID = nil` alongside
    /// `selectedConflictOptionID = nil` — components.md §14.5, "the panel
    /// does not congratulate... returns to the ordinary inspector... no 'all
    /// clear' state."
    ///
    /// A no-op (returns `false`, touches nothing) when there is no selected
    /// conflict, it no longer exists in `conflicts`, or no option is
    /// currently focused — `↩` with the panel open but nothing previewed yet
    /// (right after `activateNeedsAttention()`) applies nothing, the same
    /// "an option the user cannot see the consequence of is an option they
    /// cannot rank" reasoning §10.1 gives for preview-on-focus in the first
    /// place: there is no consequence in view to apply.
    @discardableResult
    func applyFocusedConflictOption(
        store: EventStore,
        recomputeConflicts: () -> [Conflict]
    ) -> Bool {
        guard let conflictID = selectedConflictID,
              let conflict = conflicts.first(where: { $0.id == conflictID }),
              let optionID = selectedConflictOptionID,
              let option = conflict.options.first(where: { $0.id == optionID })
        else { return false }

        store.transaction("Resolve Conflict") {
            switch option.kind {
            case .shiftLater:
                // Both endpoints move by the same delta — `move`, not
                // `resize`: `resize` clamps a new start/end against the
                // event's OWN still-live other endpoint, which is correct
                // for a single-boundary drag but wrong here, where both
                // boundaries are moving together.
                if let newStart = option.newStart {
                    store.move(conflict.routineEvent, toStart: newStart)
                }
            case .shorten:
                // Exactly one boundary changes (`ConflictEngine
                // .shortenOption`'s own doc comment); the other is handed
                // back unchanged, so `resize`'s own clamp-against-the-
                // unmoved-boundary logic is exactly the tool this shape
                // needs.
                store.resize(conflict.routineEvent, newStart: option.newStart, newEnd: option.newEnd)
            case .skipToday:
                // §10.1's general apply path is "write the previewed
                // option's proposed frame(s) to the committed store" — for
                // an option with no destination frame
                // (`ConflictOption.newStart`/`newEnd == nil`,
                // `skipsOccurrence == true`) that write is the `.skipped`
                // status itself, not a block move. See `markSkipped`'s own
                // doc comment for why it is not `toggleSkipped`.
                store.markSkipped(conflict.routineEvent)
            }
        }

        selectedConflictOptionID = nil
        let refreshed = recomputeConflicts()
        conflicts = refreshed
        if let next = ConflictOrdering.firstUnresolved(refreshed) {
            selectedConflictID = next.id
            selectedConflictOptionID = next.options.first?.id
        } else {
            selectedConflictID = nil
        }
        return true
    }

    /// interactions.md §1 — the regions `⇥` cycles between, in spec order.
    ///
    /// `⇥` always *leaves* a region rather than moving inside it; the arrow keys
    /// move within one.
    enum FocusRegion: Int, CaseIterable, Sendable {
        case toolbar, sidebar, allDayRow, grid, inspector

        /// The next region in the cycle, skipping any that are not currently
        /// available — the all-day row when it is hidden, the inspector when it
        /// is collapsed — and wrapping at either end.
        ///
        /// Pure, so the skipping and wrapping rules are testable without a view.
        static func next(
            after current: FocusRegion,
            backwards: Bool = false,
            available: Set<FocusRegion>
        ) -> FocusRegion {
            let ordered = allCases
            guard !available.isEmpty else { return current }
            guard let index = ordered.firstIndex(of: current) else {
                return ordered.first { available.contains($0) } ?? current
            }

            let step = backwards ? -1 : 1
            // At most one full lap: if nothing else is available we land back on
            // `current`, which is correct — ⇥ with one region is a no-op.
            for hop in 1...ordered.count {
                let position = ((index + step * hop) % ordered.count + ordered.count) % ordered.count
                let candidate = ordered[position]
                if available.contains(candidate) { return candidate }
            }
            return current
        }
    }

    /// Which regions `⇥` can currently land on.
    ///
    /// The toolbar is deliberately absent — see STATUS.md. Everything else is
    /// gated on whether it is actually on screen.
    ///
    func availableFocusRegions(allDayRowVisible: Bool) -> Set<FocusRegion> {
        var regions: Set<FocusRegion> = [.grid]
        if isSidebarVisible { regions.insert(.sidebar) }
        if allDayRowVisible { regions.insert(.allDayRow) }
        if isInspectorVisible { regions.insert(.inspector) }
        return regions
    }

    // MARK: Creating (interactions.md §3)

    /// Start typing a new event. Nothing is persisted yet.
    func beginDraft(at start: Date, duration: TimeInterval = 3600) {
        selectedEventID = nil
        draft = EventDraft(start: start, end: start.addingTimeInterval(duration))
    }

    /// Abandon the draft. Nothing was persisted, so there is nothing to undo.
    func discardDraft() {
        draft = nil
    }

    /// A binding to the in-flight draft that stays safe to read after the draft
    /// is gone.
    ///
    /// Do **not** replace this with `Binding($state.draft)`. SwiftUI's
    /// `Binding.init?(_ base: Binding<Value?>)` builds a
    /// `BindingOperations.ForceUnwrapping`, and that type unwraps inside its
    /// *getter* — on every read — not once at construction. Both keys that end a
    /// draft clear `draft` from inside the draft field's own event handling
    /// (`↩` → `EventStore.commit` → `discardDraft`, `⎋`/blur → `discardDraft`),
    /// and SwiftUI reads the field's bindings again while tearing the field
    /// down. Those trailing reads unwrapped nil and trapped the whole app in
    /// `BindingOperations.ForceUnwrapping.get(base:)`.
    ///
    /// So: the binding remembers the last value that went through it and serves
    /// that to the trailing reads, and it drops writes once `draft` is nil,
    /// which also stops a field flushing its last text back and resurrecting a
    /// draft the user just cancelled.
    func draftBinding() -> Binding<EventDraft>? {
        guard let current = draft else { return nil }
        // Captured by reference by both closures, so what the user typed is
        // still what a read after the draft ended sees.
        var lastKnown = current
        return Binding(
            get: { self.draft ?? lastKnown },
            set: { newValue in
                guard self.draft != nil else { return }
                lastKnown = newValue
                self.draft = newValue
            })
    }

    // MARK: Sidebar visibility (layouts.md §1.1)

    /// How the split view should render, derived from the one stored flag.
    var sidebarColumnVisibility: NavigationSplitViewVisibility {
        isSidebarVisible ? .all : .detailOnly
    }

    /// Set sidebar visibility, honouring §1.1: "auto-collapse does not overwrite
    /// the user's explicit choice — if the user closed the inspector at 1400pt,
    /// widening the window does not re-open it." The same rule applies to the
    /// sidebar below 900pt.
    ///
    /// Every path that changes the sidebar goes through here — the Edit menu, the
    /// toolbar button, the split view's own divider, and the width-driven
    /// auto-collapse — so there is exactly one place the rule lives.
    func setSidebarVisible(_ visible: Bool, isUserAction: Bool) {
        if isUserAction {
            userSetSidebarVisibility = true
            isSidebarVisible = visible
        } else if !userSetSidebarVisibility {
            isSidebarVisible = visible
        }
    }

    func toggleSidebar() {
        setSidebarVisible(!isSidebarVisible, isUserAction: true)
    }

    // MARK: Derived range

    var calendar: Calendar {
        var calendar = Calendar.current
        calendar.firstWeekday = Calendar.current.firstWeekday
        return calendar
    }

    /// The dates the current mode draws.
    var visibleDays: [Date] {
        switch mode {
        case .day:
            return [calendar.startOfDay(for: anchor)]
        case .week:
            return weekDays(containing: anchor)
        case .month:
            return monthGridDays(containing: anchor)
        }
    }

    var visibleInterval: DateInterval {
        let days = visibleDays
        let start = days.first ?? calendar.startOfDay(for: anchor)
        let endDay = days.last ?? start
        let end = calendar.date(byAdding: .day, value: 1, to: endDay) ?? endDay
        return DateInterval(start: start, end: end)
    }

    func weekDays(containing date: Date) -> [Date] {
        let startOfDay = calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfDay)
        let delta = (weekday - calendar.firstWeekday + 7) % 7
        guard let first = calendar.date(byAdding: .day, value: -delta, to: startOfDay) else {
            return [startOfDay]
        }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
    }

    /// Always six rows, so the grid never reflows when paging (layouts.md §5).
    func monthGridDays(containing date: Date) -> [Date] {
        let startOfMonth = calendar.date(
            from: calendar.dateComponents([.year, .month], from: date)
        ) ?? calendar.startOfDay(for: date)
        let weekday = calendar.component(.weekday, from: startOfMonth)
        let delta = (weekday - calendar.firstWeekday + 7) % 7
        guard let gridStart = calendar.date(byAdding: .day, value: -delta, to: startOfMonth) else {
            return [startOfMonth]
        }
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: gridStart) }
    }

    // MARK: Navigation (interactions.md §2)

    func goToToday() {
        anchor = Date()
        timeCursor = nil
    }

    func page(by direction: Int) {
        let component: Calendar.Component = switch mode {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
        if let next = calendar.date(byAdding: component, value: direction, to: anchor) {
            anchor = next
        }
    }

    func setMode(_ newMode: CalendarMode) {
        mode = newMode
    }

    // MARK: Filtering

    func isVisible(_ event: Event) -> Bool {
        if hiddenSources.contains(event.sourceKey) { return false }
        if showAllDayOnly && !event.isAllDay { return false }
        if showTimedOnly && event.isAllDay { return false }
        if hideDone && event.status == .done { return false }
        if hideSkipped && event.status == .skipped { return false }
        return true
    }

    // MARK: Title (layouts.md §1.2)

    var toolbarTitle: String {
        let formatter = DateFormatter()
        switch mode {
        case .month:
            formatter.dateFormat = "LLLL yyyy"
            return formatter.string(from: anchor)
        case .day:
            formatter.dateFormat = "EEE d MMM yyyy"
            return formatter.string(from: anchor)
        case .week:
            let days = weekDays(containing: anchor)
            guard let first = days.first, let last = days.last else { return "" }
            let day = DateFormatter(); day.dateFormat = "d"
            let dayMonth = DateFormatter(); dayMonth.dateFormat = "d MMM"
            let full = DateFormatter(); full.dateFormat = "d MMM yyyy"
            let sameMonth = calendar.isDate(first, equalTo: last, toGranularity: .month)
            return "\(sameMonth ? day.string(from: first) : dayMonth.string(from: first)) – \(full.string(from: last))"
        }
    }
}

// MARK: - Conflict preview geometry (components.md §14.4, interactions.md §10.1)

/// The ghost/proposed date-interval pair a focused `ConflictOption` implies —
/// pure geometry, free of SwiftUI and the system clock, so `KadenceTests` can
/// assert on it directly. The same seam `MainWindow.conflictedEventIDs`/
/// `sortedConflicts` already established for the identical reason: a SwiftUI
/// view hosted in a unit test cannot be inspected reliably on this platform
/// (see `AccessibilityTests.swift`'s header), so the decision that would
/// otherwise live inline in `DayColumnView` is pulled out as a `static`
/// function over value types instead.
struct ConflictPreviewFrames: Equatable {
    /// The routine event's real, committed span. Always present — every
    /// option kind dims the real block to `opacity.blockDragOrigin` while a
    /// preview is active (components.md §14.4's own ghost rule), regardless
    /// of whether that option has anywhere to move it.
    let ghost: DateInterval

    /// The option's proposed span, or `nil` for `.skipToday` —
    /// `ConflictOption.newStart`/`newEnd` are `nil` for that kind because
    /// there is nothing to move. §14.4's own wording ("every block the
    /// option would move") is written for shift/shorten and does not say
    /// what previewing a skip looks like; this engine's documented answer
    /// (recorded in DEVIATIONS.md) is "the ghost dims, and there is no
    /// dashed twin, because there is no destination frame to draw one at" —
    /// `proposed == nil` is that answer, not an omission.
    let proposed: DateInterval?

    /// Pure mapping, not a stored transition: calling this again with a
    /// different `option` for the same `conflict` returns `ghost` unchanged
    /// and a fresh `proposed` — there is no intermediate state threaded
    /// through, which is what makes "moving to another option previews the
    /// new one directly, never via the committed frame" (interactions.md
    /// §10.1) true at this layer. The SwiftUI-level guarantee (an
    /// `.animation` keyed on this value, not a remount) is `DayColumnView`'s
    /// job; this function only has to keep returning the one invariant
    /// (`ghost`) and the one thing that actually changes (`proposed`).
    static func resolve(conflict: Conflict, option: ConflictOption) -> ConflictPreviewFrames {
        let ghost = DateInterval(start: conflict.routineEvent.start, end: conflict.routineEvent.end)
        guard let newStart = option.newStart, let newEnd = option.newEnd else {
            return ConflictPreviewFrames(ghost: ghost, proposed: nil)
        }
        return ConflictPreviewFrames(ghost: ghost, proposed: DateInterval(start: newStart, end: newEnd))
    }
}
