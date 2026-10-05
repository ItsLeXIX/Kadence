//
//  FlexibilityRules.swift
//  Kadence
//
//  components.md §13.2 and its 2026-10-01 amendment (closes GAPS G-022): the
//  value semantics of the Routines inspector's flexibility control and its
//  ± stepper. Pure, so the rules are unit-testable without a view or a store
//  (task P2-T42). `RoutineBlockStore.setFlexibility` / `setShiftRange` /
//  `repairShiftRanges` apply them.
//

import Foundation

enum ShiftRangeRule {
    /// "range 15–180" (§13.2).
    static let range: ClosedRange<Int> = 15...180
    /// "15-minute steps" (§13.2).
    static let step = 15
    /// "Choosing `Shiftable` for a block that has no ± value writes **30**
    /// immediately — not `nil`, not 15." (§13.2 amendment.)
    static let defaultOnEntry = 30

    /// "Values outside 15–180 clamp to the nearest bound." (§13.2.)
    static func clamped(_ minutes: Int) -> Int {
        Swift.min(Swift.max(minutes, range.lowerBound), range.upperBound)
    }

    /// What the stepper shows for a stored value. "A `.shiftable` block with
    /// no ± value is a defect, not a state. It renders the stepper at 30"
    /// (§13.2). A stored value outside the range shows clamped, because "the
    /// stepper never presents a value it would not accept".
    static func displayed(_ stored: Int?) -> Int {
        clamped(stored ?? defaultOnEntry)
    }

    /// The ± value to store when flexibility changes from whatever it was to
    /// `new`. Entering `.shiftable` with no value writes 30; anything else
    /// keeps the stored number untouched, including switching away
    /// ("Switching away keeps the number", §13.2), so coming back restores it.
    static func storedValue(afterSwitchingTo new: Flexibility, current: Int?) -> Int? {
        if new == .shiftable, current == nil { return defaultOnEntry }
        return current
    }

    /// Does this stored state need repairing? Only `.shiftable` with no value.
    static func needsRepair(flexibility: Flexibility, stored: Int?) -> Bool {
        flexibility == .shiftable && stored == nil
    }
}
