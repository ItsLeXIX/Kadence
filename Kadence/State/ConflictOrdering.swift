//
//  ConflictOrdering.swift
//  Kadence
//
//  components.md §14.1 / interactions.md §10.1's first sentence: activating
//  the needs-attention row "selects the first unresolved conflict". Neither
//  section says what "first" means when more than one conflict is open —
//  `ConflictEngine.detect`'s own doc comment only promises a *deterministic*
//  `id` per pair, not an ordering, and its result order is just pairwise
//  iteration order over whatever array it was handed, which is not a
//  meaningful "first" a user would recognise across two calls with a
//  differently-ordered input.
//
//  This task's own call, not a spec value (nothing here is a colour, size or
//  other design token — it is a tie-break rule over data the design docs are
//  silent on): order ascending by the earlier of the two colliding events'
//  start times — the conflict that is happening (or about to happen) soonest
//  is "first" — tie-broken by `Conflict.id` (the engine's own stable string,
//  not a fresh UUID) so two conflicts starting at the exact same instant
//  still sort deterministically rather than depending on array order.
//
//  Pure and free of SwiftUI/the system clock, same shape as
//  `CalendarState.FocusRegion.next`, so it is unit-testable without a view or
//  a store.
//

import Foundation

enum ConflictOrdering {
    /// Stable total order — see the file header for the rule.
    static func sorted(_ conflicts: [Conflict]) -> [Conflict] {
        conflicts.sorted { lhs, rhs in
            let lhsStart = earliestStart(lhs)
            let rhsStart = earliestStart(rhs)
            if lhsStart != rhsStart { return lhsStart < rhsStart }
            return lhs.id < rhs.id
        }
    }

    /// `nil` only when `conflicts` is empty. Every conflict `detect` currently
    /// returns counts as "unresolved" — there is no apply step yet (a
    /// deliberate scope limit of this task, not an oversight; see
    /// STATUS.md), so nothing has a way to become "resolved" and drop out of
    /// this list on its own.
    static func firstUnresolved(_ conflicts: [Conflict]) -> Conflict? {
        sorted(conflicts).first
    }

    private static func earliestStart(_ conflict: Conflict) -> Date {
        min(conflict.routineEvent.start, conflict.otherEvent.start)
    }
}
