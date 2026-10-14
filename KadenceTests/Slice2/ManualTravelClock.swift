//
//  ManualTravelClock.swift
//  KadenceTests
//
//  The injected clock the slice 2 tests drive: `now` moves only when a test
//  advances it, and a wake fires only then. Nothing sleeps (PHASE3-SLICE2-
//  PLAN.md: "no … pass reads `Date()` or sleeps").
//

import Foundation
@testable import Kadence

@MainActor
final class ManualTravelClock: TravelClock {
    private(set) var now: Date
    private var wakes: [(id: Int, at: Date, fire: @MainActor () -> Void)] = []
    private var nextID = 0

    init(_ now: Date) { self.now = now }

    func wake(at date: Date, _ fire: @escaping @MainActor () -> Void) -> ScheduledWake {
        nextID += 1
        let id = nextID
        wakes.append((id, date, fire))
        return ScheduledWake { [weak self] in self?.wakes.removeAll { $0.id == id } }
    }

    var nextWakeAt: Date? { wakes.map(\.at).min() }
    var pendingWakes: Int { wakes.count }

    /// Moves to `target`, firing every wake due on the way, in time order.
    func advance(to target: Date) {
        while let next = wakes.filter({ $0.at <= target }).min(by: { ($0.at, $0.id) < ($1.at, $1.id) }) {
            wakes.removeAll { $0.id == next.id }
            now = max(now, next.at)
            next.fire()
        }
        now = max(now, target)
    }

    func advance(by seconds: TimeInterval) { advance(to: now.addingTimeInterval(seconds)) }

    /// Sets `now` without firing anything (a jump, e.g. a wake from sleep).
    func set(_ date: Date) { now = date }
}

extension RouteRequestQueue {
    /// Lets the queue send and finish everything the clock allows up to
    /// `until`, advancing the manual clock wake by wake.
    func run(on clock: ManualTravelClock, until: Date) async {
        while true {
            await settle()
            guard let next = clock.nextWakeAt, next <= until else { break }
            clock.advance(to: next)
        }
        clock.advance(to: until)
        await settle()
    }
}
