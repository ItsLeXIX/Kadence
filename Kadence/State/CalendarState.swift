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

    /// The event currently being renamed inline, if any.
    var inlineEditingEventID: UUID?

    // MARK: Chrome

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

    enum FocusRegion: Int, CaseIterable, Sendable {
        case toolbar, sidebar, allDayRow, grid, inspector
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
