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
