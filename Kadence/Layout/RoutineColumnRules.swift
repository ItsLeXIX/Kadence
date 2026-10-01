//
//  RoutineColumnRules.swift
//  Kadence
//
//  components.md §13.5 / interactions.md §11.1 (amended 2026-10-01) — the
//  rules that decide what each of the Routines window's seven weekday columns
//  is allowed to do, kept out of the view layer so they can be unit-tested.
//
//  The underlying shape (components.md §13.5, stated once): a `RoutineBlock`
//  is not on a weekday. It is a time of day that runs on every one of the
//  template's active weekdays, so the seven columns are seven read-outs of one
//  pattern, not seven placement surfaces. Every rule below follows from that:
//
//  - a create gesture on an inactive column is refused (§13.5.1);
//  - an inactive column is recessed and carries a note (§13.5.2–§13.5.3);
//  - a block drag is vertical only and has no column of its own, so its drop
//    preview is drawn in every active column at once (interactions.md §11.1);
//  - all of this is Blocks mode only — in Windows mode every column is live
//    (§13.5.5).
//
//  Pure value types and functions — no SwiftUI, no SwiftData — the same
//  convention `RoutineWeekLayout` already follows.
//

import Foundation

/// components.md §13.3's mode control: "Blocks" / "Windows". `.blocks` is the
/// default — the window opens the way P2-T10 through P2-T12 already left it.
/// (Moved here from `RoutinesWindow.swift` by task P2-T38 so the column rules
/// below can take it without depending on a view file.)
enum RoutinesEditorMode: String, CaseIterable, Identifiable {
    case blocks
    case windows

    var id: String { rawValue }

    var label: String {
        switch self {
        case .blocks: "Blocks"
        case .windows: "Windows"
        }
    }
}

// MARK: - Column treatment (components.md §13.5.2, §13.5.5)

/// What one weekday column is, for the purposes of §13.5. Three cases rather
/// than a `Bool`, because Windows mode is not "active" — it is "the template's
/// weekday set is not the layer being edited, so mark nothing" (§13.5.5: "no
/// note, no line reweighting, and no header underline at all").
enum RoutineColumnTreatment: Equatable {
    /// Blocks mode, weekday in `activeWeekdays`: header underline, normal
    /// hour lines, create gestures accepted.
    case active
    /// Blocks mode, weekday NOT in `activeWeekdays`: recessed hour lines, no
    /// underline, the pinned note, create gestures refused.
    case inactive
    /// Windows mode: every column is a first-class editing surface for
    /// `TimeWindow`s, and nothing about the template's weekday set is shown.
    case unmarked

    static func resolve(weekday: Int, activeWeekdays: Set<Int>, mode: RoutinesEditorMode) -> Self {
        switch mode {
        case .windows: .unmarked
        case .blocks: activeWeekdays.contains(weekday) ? .active : .inactive
        }
    }

    /// §13.5.2: "Header underline — `size.borderEmphasis` in the template's
    /// `color.source.<slot>.rail`" on active columns only; "none" otherwise.
    var showsHeaderUnderline: Bool { self == .active }

    /// §13.5.2: hour lines drawn in `color.separator.halfHour` ("hour and
    /// half-hour lines both"). The ground is NOT changed — see the spec's
    /// "Do not sink the ground" paragraph.
    var recessesHourLines: Bool { self == .inactive }

    /// §13.5.3: one note per inactive column.
    var showsInactiveNote: Bool { self == .inactive }

    /// interactions.md §11.1: "Double-click and create-drag on the empty
    /// canvas of an inactive column do nothing: no block, no draft, no
    /// outline." `.unmarked` returns `false` too, but for a different reason
    /// that predates this rule: in Windows mode routine blocks are not the
    /// edited layer at all (§13.3), so the block-create surface is off in
    /// every column there.
    var acceptsBlockCreate: Bool { self == .active }

    /// interactions.md §11.1: "The cursor over that canvas is
    /// `.operationNotAllowed`."
    var refusesBlockCreate: Bool { self == .inactive }
}

// MARK: - Draft abandonment (interactions.md §11.1)

enum RoutineDraftRules {
    /// interactions.md §11.1: "A draft whose column is deactivated mid-edit
    /// is abandoned, per `DECISIONS.md`'s draft rule — if the surface went
    /// away, you did not decide."
    ///
    /// Deliberately keyed on the weekday set only, not on the editor mode: the
    /// spec's trigger is a *deactivated column*. What a Blocks → Windows mode
    /// switch does to an in-flight draft is not part of this rule (and is
    /// unchanged by task P2-T38).
    static func mustAbandonDraft(draftWeekday: Int, activeWeekdays: Set<Int>) -> Bool {
        !activeWeekdays.contains(draftWeekday)
    }
}

// MARK: - Block drag: vertical only, previewed in every active column

/// One in-flight move/resize of a `RoutineBlock` in the Routines window.
///
/// interactions.md §11.1: "A block drag is vertical only. Horizontal
/// translation is ignored outright. A block cannot be moved between columns,
/// active or inactive, because there is no per-column instance to move."
///
/// That rule is structural here rather than enforced by a check: this type is
/// written in minutes-since-midnight and has **no weekday field at all**, and
/// `updated(translationHeight:…)` takes only the vertical component of the
/// pointer's translation. There is nothing a horizontal movement could change.
/// It is also why one value can be shared by all seven columns and each one
/// can draw the same preview (`previewWeekdays`).
struct RoutineBlockDrag: Equatable {
    enum Mode: Equatable { case move, resizeTop, resizeBottom }

    var blockID: UUID
    var mode: Mode
    var originStartMinutes: Int
    var originDurationMinutes: Int
    /// The pointer's snapped position, expressed as "where the block's start
    /// would be" — the same quantity `DayColumnView.blockGesture`'s
    /// `session.current` carries, just in minutes instead of a `Date`.
    var currentStartMinutes: Int

    init(blockID: UUID, mode: Mode, startMinutes: Int, durationMinutes: Int) {
        self.blockID = blockID
        self.mode = mode
        self.originStartMinutes = startMinutes
        self.originDurationMinutes = durationMinutes
        self.currentStartMinutes = startMinutes
    }

    /// Returns a copy following a pointer that has moved `translationHeight`
    /// points vertically. Snaps the same way `TimeGeometry.snap` does
    /// (round-to-nearest on the snap grid, measured from midnight): 15
    /// minutes, or 5 with `⌃` (interactions.md §4).
    func updated(translationHeight: Double, hourHeight: Double, snapMinutes: Int) -> Self {
        let rawMinutes = Double(originStartMinutes) + translationHeight / hourHeight * 60
        let step = Double(max(snapMinutes, 1))
        var copy = self
        copy.currentStartMinutes = Int((rawMinutes / step).rounded() * step)
        return copy
    }

    /// The `[start, end)` this drag would write, in minutes, after the same
    /// clamps `RoutineBlockStore.move`/`.resize` apply on drop
    /// (interactions.md §11.1, "Cross-midnight drags clamp"; §4's 15-minute
    /// minimum) — so the drop preview shows what will actually land, not a
    /// frame the store would then silently correct.
    var proposedRange: (start: Int, end: Int) {
        let originEnd = originStartMinutes + originDurationMinutes
        let minimum = 15
        switch mode {
        case .move:
            let start = min(max(currentStartMinutes, 0), 1440 - originDurationMinutes)
            return (start, start + originDurationMinutes)
        case .resizeTop:
            let start = min(max(currentStartMinutes, 0), originEnd - minimum)
            return (start, originEnd)
        case .resizeBottom:
            let delta = currentStartMinutes - originStartMinutes
            let end = max(min(originEnd + delta, 1440), originStartMinutes + minimum)
            return (originStartMinutes, end)
        }
    }

    /// interactions.md §11.1: "The drop preview appears in every active
    /// column at once ... No preview is drawn in an inactive column." Returned
    /// in the window's column order.
    static func previewWeekdays(orderedWeekdays: [Int], activeWeekdays: Set<Int>) -> [Int] {
        orderedWeekdays.filter { activeWeekdays.contains($0) }
    }
}

// MARK: - Weekday activation (components.md §13.5.4, interactions.md §11.1.1)

/// The pure half of activating or deactivating a weekday: the new set, the
/// undo-step name, and where `←`/`→` move focus in the inspector's toggle row.
/// `RoutineTemplateStore.setWeekday` (`RoutineEngine.swift`) does the write.
enum RoutineWeekdayActivation {

    /// `activeWeekdays` with `weekday` added (`active == true`) or removed.
    /// A `Set` has no order, so "Mon-first" is never stored — it is applied
    /// only when the set is displayed, through
    /// `RoutineWeekLayout.orderedWeekdays(firstWeekday:)`.
    static func applying(_ weekday: Int, active: Bool, to activeWeekdays: Set<Int>) -> Set<Int> {
        var result = activeWeekdays
        if active { result.insert(weekday) } else { result.remove(weekday) }
        return result
    }

    /// components.md §13.5.4: "`Add Saturday to Routine` / `Remove Saturday
    /// from Routine`, spelled with the weekday's full name
    /// (`standaloneWeekdaySymbols`) so the Edit menu reads as a sentence."
    /// `UndoStack` adds the leading "Undo "/"Redo " itself.
    ///
    /// `calendar` is a parameter so tests can pin an English locale; the app
    /// passes `.current`. `weekday` is `Calendar`'s 1 = Sunday … 7 = Saturday,
    /// so the symbol array is indexed at `weekday - 1`.
    static func undoName(weekday: Int, activating: Bool, calendar: Calendar = .current) -> String {
        let name = calendar.standaloneWeekdaySymbols[weekday - 1]
        return activating ? "Add \(name) to Routine" : "Remove \(name) from Routine"
    }

    /// interactions.md §11.1.1 / layouts.md §8.1: "`←`/`→` move between the
    /// seven toggles". The spec does not say whether focus wraps at either
    /// end; it stops there, which is the reading that never moves focus
    /// somewhere the user did not point (see STATUS.md §40).
    ///
    /// `ordered` is the row's display order; `offset` is −1 for `←`, +1 for
    /// `→`. A `current` that is not in the row (nothing focused yet) lands on
    /// the first toggle.
    static func movingFocus(from current: Int?, by offset: Int, in ordered: [Int]) -> Int? {
        guard !ordered.isEmpty else { return nil }
        guard let current, let index = ordered.firstIndex(of: current) else { return ordered.first }
        let target = min(max(index + offset, 0), ordered.count - 1)
        return ordered[target]
    }
}
