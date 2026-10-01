//
//  RoutineMaterializationTriggers.swift
//  Kadence
//
//  components.md §13.6.5's triggers, task P2-T40: "app launch; any edit to a
//  template, a block or a `TimeWindow`; and a change to the main window's
//  visible range." Launch is each window's own `.task` (it has to run after
//  mock seeding, so it can't live here). This modifier covers the other two.
//  `MainWindow` and `RoutinesWindow` both attach it, so an edit made while
//  only the Routines window is open still materialises. When both windows
//  are open, both fire. That is harmless because `materialize` is idempotent.
//

import SwiftUI
import SwiftData

/// Swift note (from Java/C#): a `ViewModifier` is a reusable wrapper around
/// a view, roughly a decorator. It can hold the same property wrappers a
/// view can (`@Query`, `@Environment`), so it can watch the store itself
/// instead of every window threading the queries through.
struct RoutineMaterializationTriggers: ViewModifier {
    /// False until the window's launch `.task` has seeded and run the first
    /// pass, so an `onChange` that fires on first appearance can't run
    /// `materialize` before `MockData` has decided whether the store is
    /// empty (`MockData.seedAllIfNeeded`).
    let isReady: Bool
    /// `CalendarState.visibleInterval.end`, the main window's visible range.
    let visibleEnd: Date

    @Environment(\.modelContext) private var context
    @Environment(UndoStack.self) private var undoStack
    @Query private var templates: [RoutineTemplate]
    @Query private var timeWindows: [TimeWindow]

    func body(content: Content) -> some View {
        content
            // Built inside `body`, so SwiftUI tracks every model property the
            // fingerprint reads. Changing one re-renders this modifier, and
            // `onChange` then sees a different value.
            .onChange(of: RoutineMaterialization.Fingerprint(templates: templates, windows: timeWindows)) {
                run()
            }
            .onChange(of: visibleEnd) {
                run()
            }
    }

    private func run() {
        guard isReady else { return }
        RoutineMaterialization.run(context: context, undo: undoStack, visibleEnd: visibleEnd)
    }
}

extension View {
    func materializesRoutines(isReady: Bool, visibleEnd: Date) -> some View {
        modifier(RoutineMaterializationTriggers(isReady: isReady, visibleEnd: visibleEnd))
    }
}
