//
//  RoutingSupport.swift
//  Kadence
//
//  Phase 3 slice 2 — the seams the routing queue (task 5) and the travel
//  coordinator (task 6) are driven through: a clock that can wake them, the
//  routing log (§24.11), and which network-path monitor a launch gets.
//
//  G-092 (CA judgement, recorded in STATUS): the queue and the coordinator
//  live on the main actor; every wait is a wake scheduled on an injected
//  `TravelClock`, so tests advance a manual clock and nothing ever sleeps.
//  Only the system clock (normal and review launches) waits in real time.
//

import Foundation
import os

// MARK: - The clock

/// A cancellable scheduled wake.
@MainActor
final class ScheduledWake {
    private var onCancel: (() -> Void)?
    init(onCancel: @escaping () -> Void) { self.onCancel = onCancel }
    func cancel() {
        onCancel?()
        onCancel = nil
    }
}

/// `now`, and a way to be woken at a time. Injected everywhere a routing,
/// refresh or notification pass needs the time (PHASE3-SLICE2-PLAN.md:
/// "no planner, recompute, queue, refresh or notification pass reads
/// `Date()` or sleeps").
@MainActor
protocol TravelClock: AnyObject {
    var now: Date { get }
    @discardableResult
    func wake(at date: Date, _ fire: @escaping @MainActor () -> Void) -> ScheduledWake
}

/// The wall clock. Used by normal and review launches only; tests use a
/// manual clock.
@MainActor
final class SystemTravelClock: TravelClock {
    var now: Date { Date() }

    func wake(at date: Date, _ fire: @escaping @MainActor () -> Void) -> ScheduledWake {
        let task = Task { @MainActor in
            let seconds = max(0, date.timeIntervalSinceNow)
            if seconds > 0 { try? await Task.sleep(for: .seconds(seconds)) }
            guard !Task.isCancelled else { return }
            fire()
        }
        return ScheduledWake { task.cancel() }
    }
}

// MARK: - The routing log (§24.11)

/// The `travel` log category. Every line is one of §24.11's forms and
/// carries no address, coordinate, place name, event title or search text —
/// the callers build lines only from numbers, modes and reason words. Lines
/// are kept in memory (the last 500) so tests can read what was logged.
@MainActor
final class RoutingLog {
    private let logger = Logger(subsystem: "XIX.Kadence", category: "travel")
    private let forwardsToSystem: Bool
    private(set) var lines: [String] = []

    init(forwardsToSystem: Bool = false) {
        self.forwardsToSystem = forwardsToSystem
    }

    func write(_ line: String) {
        lines.append(line)
        if lines.count > 500 { lines.removeFirst(lines.count - 500) }
        // `.public`: the line is built from §24.11's forms only (numbers,
        // modes, reason words) — there is nothing private to redact.
        if forwardsToSystem { logger.info("\(line, privacy: .public)") }
    }

    /// `HH:mm` in the given calendar's zone (`queue paused · until 10:40`).
    static func clock(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// Whole minutes, rounded up as the leg rounds them (B48).
    static func minutes(_ seconds: TimeInterval) -> Int { Int((seconds / 60).rounded(.up)) }
}

// MARK: - Network path monitors

/// The scripted path monitor tests and review launches use instead of
/// `NWPathMonitor` (§24.11: a launch XCTest started, or one with
/// `-KadenceReview`, never constructs one).
@MainActor
final class ScriptedPathMonitoring: PathMonitoring {
    private(set) var isSatisfied: Bool
    var onChange: ((Bool) -> Void)?

    init(satisfied: Bool = true) { isSatisfied = satisfied }

    func set(satisfied: Bool) {
        guard satisfied != isSatisfied else { return }
        isSatisfied = satisfied
        onChange?(satisfied)
    }
}

@MainActor
enum PathMonitors {
    /// A new monitor for one consumer (each has its own `onChange`): the
    /// `NWPathMonitor`-backed one in a normal launch only.
    static func make(for kind: LaunchKind) -> any PathMonitoring {
        switch ServiceImplementation.of(kind) {
        case .real:
            ServiceLaunchLog.record("NetworkPathMonitoring")
            return NetworkPathMonitoring()
        case .mock:
            ServiceLaunchLog.record("ScriptedPathMonitoring")
            return ScriptedPathMonitoring()
        }
    }
}
