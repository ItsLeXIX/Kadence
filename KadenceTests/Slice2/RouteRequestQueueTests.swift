//
//  RouteRequestQueueTests.swift
//  KadenceTests
//
//  PHASE3-SLICE2-PLAN.md task 5 — components.md §24.9 "The routing queue",
//  §24.10 (`paused`), §24.11 (log lines). Mock provider, injected manual
//  clock and scripted path monitor: no test waits on a real clock.
//

import Testing
import Foundation
@testable import Kadence

@MainActor
@Suite(.serialized)
struct RouteRequestQueueTests {
    let start = TravelFixtures.m(0, "06:00")
    let home = TravelEndpoint(id: "home", latitude: 48.2, longitude: 16.39)
    let campus = TravelEndpoint(id: "campus", latitude: 48.239, longitude: 16.377)

    struct Rig {
        let clock: ManualTravelClock
        let provider: MockTravelTimeProvider
        let path: ScriptedPathMonitoring
        let log: RoutingLog
        let queue: RouteRequestQueue
    }

    func rig(at now: Date? = nil) -> Rig {
        let clock = ManualTravelClock(now ?? start)
        let provider = TravelServices.defaultMockProvider()
        let path = ScriptedPathMonitoring()
        let log = RoutingLog()
        let queue = RouteRequestQueue(provider: provider, geocoder: MockPlaceGeocoder(), clock: clock, path: path,
                                      calendar: TravelFixtures.calendar, log: log)
        return Rig(clock: clock, provider: provider, path: path, log: log, queue: queue)
    }

    /// A request with key `k{n}`, home → campus, for an event `n` minutes in.
    func request(_ n: Int, priority: Int = 4) -> TravelLegPlanner.Request {
        let eventStart = start.addingTimeInterval(TimeInterval(3600 + n * 60))
        return TravelLegPlanner.Request(key: "k\(n)", origin: home, destination: campus, mode: .transit,
                                        arrivingBy: eventStart.addingTimeInterval(-600), priority: priority,
                                        eventStart: eventStart, eventIDs: [TravelFixtures.id(n)], dayType: .weekday,
                                        slotMinutes: 510, originPlaceID: "home", destinationPlaceID: "campus")
    }

    func sentIDs(_ queue: RouteRequestQueue) -> [String] { queue.history.map(\.id) }
    func sentOffsets(_ queue: RouteRequestQueue) -> [TimeInterval] { queue.history.map { $0.at.timeIntervalSince(start) } }

    @Test("One in flight; at least 2 s apart")
    func oneInFlightAndSpacing() async {
        let r = rig()
        await r.provider.hold()
        r.queue.syncPlanned([request(1), request(2), request(3)])
        #expect(r.queue.history.count == 1)          // one in flight, the others wait
        r.clock.advance(by: 10)
        #expect(r.queue.history.count == 1)          // still in flight: nothing else leaves
        await r.provider.release()
        await r.queue.run(on: r.clock, until: start.addingTimeInterval(60))
        #expect(sentIDs(r.queue) == ["eta:k1", "eta:k2", "eta:k3"])
        // k1 left at 0, finished at 10 (released); k2 2 s after k1 — already
        // due, so at once on k1's answer; k3 2 s later.
        let offsets = sentOffsets(r.queue)
        #expect(offsets[0] == 0)
        #expect(zip(offsets, offsets.dropFirst()).allSatisfy { $1 - $0 >= 2 })
    }

    @Test("A burst of 30 distinct keys: priority order, 2 s apart, the 21st waits for the rolling window; none twice")
    func burst() async {
        let r = rig()
        // Priorities mixed: every third request is priority 3.
        let requests = (1...30).map { request($0, priority: $0 % 3 == 0 ? 3 : 4) }
        r.queue.syncPlanned(requests)
        await r.queue.run(on: r.clock, until: start.addingTimeInterval(3600))
        let ids = sentIDs(r.queue)
        #expect(ids.count == 30 && Set(ids).count == 30)
        // The ten priority-3 requests leave first, then the priority-4 ones,
        // each group by event start.
        let expected = (1...30).filter { $0 % 3 == 0 }.map { "eta:k\($0)" } + (1...30).filter { $0 % 3 != 0 }.map { "eta:k\($0)" }
        #expect(ids == expected)
        let offsets = sentOffsets(r.queue)
        #expect(Array(offsets.prefix(20)) == (0..<20).map { TimeInterval($0 * 2) })
        // The 21st waits for the first to leave the 10-minute window.
        #expect(offsets[20] == 600)
        #expect(await r.provider.callCount == 30)
    }

    @Test("A duplicate key is queued once; a request whose leg disappeared is dropped; priority order 0 → 4")
    func dedupeDropAndPriority() async {
        let r = rig()
        await r.provider.hold()
        r.queue.syncPlanned([request(1)])                        // in flight
        r.queue.syncPlanned([request(1), request(2), request(2), request(3), request(4)])
        #expect(r.queue.queuedIDs == ["eta:k2", "eta:k3", "eta:k4"])
        r.queue.syncPlanned([request(1), request(2), request(4)])   // k3's leg is gone
        #expect(r.queue.queuedIDs == ["eta:k2", "eta:k4"])
        r.queue.tryAgain(request(4))                                // the user asked: priority 0
        let refresh = RouteRequestQueue.ETAJob(key: "k9", origin: home, destination: campus, mode: .transit,
                                               arrivingBy: start, purpose: .refresh(eventID: TravelFixtures.id(9),
                                                                                    slot: start, fromHere: false),
                                               request: request(9))
        r.queue.enqueueRefresh(refresh, eventID: TravelFixtures.id(9), priority: 1, eventStart: start)
        #expect(r.queue.queuedIDs == ["eta:k4", "refresh:\(TravelFixtures.id(9).uuidString)", "eta:k2"])
        await r.provider.release()
        await r.queue.run(on: r.clock, until: start.addingTimeInterval(60))
        #expect(sentIDs(r.queue) == ["eta:k1", "eta:k4", "refresh:\(TravelFixtures.id(9).uuidString)", "eta:k2"])
    }

    @Test("throttled: pauses 10, 20, 40, 60, 60 min, reset by a success; waiting legs carry retryAt; the log says until HH:mm")
    func throttle() async {
        let r = rig()
        await r.provider.answerEverything(.failure(.throttled))
        r.queue.syncPlanned([request(1), request(2)])
        await r.queue.settle()
        var resume = start.addingTimeInterval(600)
        #expect(r.queue.plannerState.pausedUntil == resume)
        #expect(r.queue.failures["k1"] == .init(reason: .paused, retryAt: resume))
        #expect(r.log.lines.contains("queue paused · until 06:10"))
        // While paused nothing leaves.
        r.clock.advance(to: resume.addingTimeInterval(-1))
        #expect(r.queue.history.count == 1)
        // The planner gives every waiting leg `paused` with the resume time.
        let legs = TravelLegPlanner.plan(TravelFixtures.input(queue: r.queue.plannerState)).legs
        #expect(legs[TravelFixtures.swqm.id]?.reason == .paused && legs[TravelFixtures.swqm.id]?.retryAt == resume)
        // 20, 40, 60, 60.
        for minutes in [20, 40, 60, 60] {
            r.clock.advance(to: resume)
            await r.queue.settle()
            let next = r.clock.now.addingTimeInterval(TimeInterval(minutes * 60))
            #expect(r.queue.plannerState.pausedUntil == next, "\(minutes)")
            resume = next
        }
        // A success resets the back-off: the next throttle pauses 10 again.
        await r.provider.answerEverything(nil)
        r.clock.advance(to: resume)
        await r.queue.settle()
        #expect(r.queue.failures["k1"] == nil)
        await r.provider.answerEverything(.failure(.throttled))
        await r.queue.run(on: r.clock, until: r.clock.now.addingTimeInterval(5))
        #expect(r.queue.plannerState.pausedUntil == r.queue.history.last!.at.addingTimeInterval(600))
    }

    @Test("offline: paused until the path monitor reports satisfied, then resumes at once")
    func offline() async {
        let r = rig()
        r.path.set(satisfied: false)
        await r.provider.answerEverything(.failure(.offline))
        r.queue.syncPlanned([request(1), request(2)])
        await r.queue.settle()
        #expect(r.queue.failures["k1"]?.reason == .offline)
        #expect(r.log.lines.last == "eta failed · offline · transit")
        r.clock.advance(by: 120)
        await r.queue.settle()
        #expect(r.queue.history.count == 1)
        await r.provider.answerEverything(nil)
        r.path.set(satisfied: true)
        await r.queue.settle()
        #expect(r.queue.history.count == 2)
        #expect(r.queue.history[1].at == start.addingTimeInterval(120))
        await r.queue.run(on: r.clock, until: r.clock.now.addingTimeInterval(10))
        #expect(r.queue.failures.isEmpty && r.queue.history.count == 3)
        // With the path looking satisfied, MapKit's offline waits 5 minutes.
        let r2 = rig()
        await r2.provider.answerEverything(.failure(.offline))
        r2.queue.syncPlanned([request(1)])
        await r2.queue.settle()
        r2.clock.advance(by: 299)
        #expect(r2.queue.history.count == 1)
        r2.clock.advance(by: 1)
        await r2.queue.settle()
        #expect(r2.queue.history.count == 2)
    }

    @Test("noRoute and failed are remembered: a recompute does not re-queue them; a 20 s timeout is failed")
    func remembered() async {
        let r = rig()
        await r.provider.set(.failure(.noRoute), for: .init(from: "home", to: "campus", mode: .transit))
        r.queue.syncPlanned([request(1)])
        await r.queue.settle()
        #expect(r.queue.failures["k1"]?.reason == .noRoute)
        r.queue.syncPlanned([request(1)])
        #expect(r.queue.queuedIDs.isEmpty)
        // Timeout.
        let t = rig()
        await t.provider.hold()
        t.queue.syncPlanned([request(2)])
        t.clock.advance(by: 20)
        #expect(t.queue.failures["k2"]?.reason == .failed)
        #expect(t.log.lines == ["eta failed · failed · transit"])
        // The answer arriving late changes nothing.
        await t.provider.release()
        await t.queue.settle()
        #expect(t.queue.failures["k2"]?.reason == .failed)
    }

    @Test("Day budget: the 151st priority-4 request waits until 00:00; a priority-1 request still goes")
    func dayBudget() async {
        let r = rig()
        r.queue.syncPlanned((1...151).map { request($0) })
        await r.queue.run(on: r.clock, until: TravelFixtures.m(0, "23:59"))
        #expect(r.queue.history.count == 150)
        let midnight = TravelFixtures.m(1, "00:00")
        #expect(r.queue.plannerState.budgetResumesAt == midnight)
        // A priority-1 refresh still goes the same day.
        let job = RouteRequestQueue.ETAJob(key: "r1", origin: home, destination: campus, mode: .transit,
                                           arrivingBy: start, purpose: .refresh(eventID: TravelFixtures.id(500),
                                                                                slot: start, fromHere: false),
                                           request: nil)
        r.queue.enqueueRefresh(job, eventID: TravelFixtures.id(500), priority: 1, eventStart: start)
        await r.queue.settle()
        #expect(r.queue.history.count == 151 && r.queue.history.last?.id.hasPrefix("refresh:") == true)
        await r.queue.run(on: r.clock, until: midnight.addingTimeInterval(5))
        #expect(r.queue.history.count == 152 && r.queue.history.last?.at == midnight)
        #expect(r.queue.plannerState.budgetResumesAt == nil)
    }

    @Test("Every log line matches §24.11's forms; none has a coordinate, an address, a place name or a title")
    func logLines() async throws {
        let r = rig()
        r.queue.syncPlanned([request(1)])
        await r.queue.settle()
        await r.provider.answerEverything(.failure(.throttled))
        r.queue.syncPlanned([request(2)])
        await r.queue.run(on: r.clock, until: r.clock.now.addingTimeInterval(5))
        await r.provider.answerEverything(.failure(.offline))
        r.clock.advance(by: 600)
        await r.queue.settle()
        let here = RouteRequestQueue.ETAJob(key: "", origin: TravelEndpoint(id: nil, latitude: 48.215, longitude: 16.38),
                                            destination: campus, mode: .transit, arrivingBy: start,
                                            purpose: .refresh(eventID: TravelFixtures.id(7), slot: start, fromHere: true),
                                            request: nil)
        await r.provider.answerEverything(nil)
        r.queue.enqueueRefresh(here, eventID: TravelFixtures.id(7), priority: 1, eventStart: start)
        await r.queue.run(on: r.clock, until: r.clock.now.addingTimeInterval(400))
        var done = false
        r.queue.enqueueLookup(id: "home", address: "Example Gasse 5, 1030 Wien") { _ in done = true }
        await r.queue.run(on: r.clock, until: r.clock.now.addingTimeInterval(5))
        #expect(done)
        try RoutingLogCheck.assertForms(r.log.lines)
        #expect(r.log.lines.contains("eta ok · 35 min · transit"))
        #expect(r.log.lines.contains("eta ok · 28 min · transit · refresh · here"))
        #expect(r.log.lines.contains("lookup ok · 1 results"))
    }
}

@MainActor
struct PathMonitorFactoryTests {
    @Test("Test-host and review launches get the scripted path monitor, never NWPathMonitor (§24.11)")
    func factory() throws {
        ServiceLaunchLog.reset()
        for kind in [LaunchKind.testHost] + ReviewMode.Dataset.allCases.map(LaunchKind.review) {
            #expect(PathMonitors.make(for: kind) is ScriptedPathMonitoring)
        }
        #expect(ServiceLaunchLog.constructed.allSatisfy { $0 == "ScriptedPathMonitoring" })
        // The NWPathMonitor wrapper is built in exactly one place: the
        // factory's `.real` branch.
        #expect(try SourceScan.files(containing: "NetworkPathMonitoring()") == ["RoutingSupport.swift"])
        #expect(try SourceScan.files(containing: "NWPathMonitor()") == ["SyncCoordinator.swift"])
    }
}

/// §24.11's forms, and what no routing line may contain. Shared by every
/// slice 2 task that logs.
nonisolated enum RoutingLogCheck {
    static let forms: [String] = [
        #"^eta ok · \d+ min · (transit|walking|driving)( · refresh)?( · here)?$"#,
        #"^eta failed · (offline|noRoute|throttled|failed) · (transit|walking|driving)$"#,
        #"^queue paused · until \d{2}:\d{2}$"#,
        #"^lookup ok · \d+ results$"#, #"^lookup none$"#, #"^lookup failed · (offline|throttled|failed)$"#,
        #"^location used$"#, #"^location not used · within 300 m$"#,
        #"^location unavailable · (denied|timeout)$"#,
    ]

    /// Fixture addresses, place names and event titles of the `travel`
    /// dataset — none may appear in a routing line.
    static let forbidden: [String] = [
        "Example", "Höchstädtplatz", "Wien", "Home", "FH Technikum", "Gym", "cafe", "Café",
        "SWQM", "SWEN3", "EPC", "REQEN", "SWRM", "INNO3", "Dinner", "Laundry", "Climbing", "study group", "Late call",
    ]

    static func assertForms(_ lines: [String], sourceLocation: SourceLocation = #_sourceLocation) throws {
        for line in lines {
            let matches = forms.contains { line.range(of: $0, options: .regularExpression) != nil }
            #expect(matches, "not a §24.11 form: \(line)", sourceLocation: sourceLocation)
            #expect(line.range(of: #"\d+\.\d{3,}"#, options: .regularExpression) == nil,
                    "coordinate in: \(line)", sourceLocation: sourceLocation)
            for word in forbidden {
                #expect(!line.localizedCaseInsensitiveContains(word), "\(word) in: \(line)", sourceLocation: sourceLocation)
            }
        }
    }
}
