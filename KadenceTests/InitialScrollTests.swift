//
//  InitialScrollTests.swift
//  KadenceTests
//
//  layouts.md §3.1 — the canvas opens at `min(07:00, firstEventStart − 1h)`
//  (task P2-F22, DEVIATIONS B24). The bug B24 recorded was in WHERE the
//  scroll landed (offset-placed anchors all sat at y = 0), which only a live
//  launch can show — see STATUS.md §75. These pin the hour it aims for and
//  that the anchor it aims at is laid out at that hour's top.
//

import Testing
import Foundation
@testable import Kadence

@MainActor
struct InitialScrollTests {
    private let calendar = Calendar.current
    private var monday: Date {
        calendar.date(from: DateComponents(year: 2026, month: 10, day: 5))!
    }
    private func at(_ day: Date, _ h: Int, _ m: Int = 0) -> Date {
        calendar.date(bySettingHour: h, minute: m, second: 0, of: day)!
    }
    private func event(_ start: Date, allDay: Bool = false) -> Event {
        Event(title: "E", start: start, end: start.addingTimeInterval(3600), isAllDay: allDay)
    }

    @Test func noEventsOpensAtSeven() {
        #expect(InitialScroll.hour(events: [], days: [monday]) == 7)
    }

    @Test func anEarlyEventOpensAnHourBeforeIt() {
        // Gym at 07:00 → 06:00.
        #expect(InitialScroll.hour(events: [event(at(monday, 7))], days: [monday]) == 6)
        #expect(InitialScroll.hour(events: [event(at(monday, 5, 30))], days: [monday]) == 4)
        #expect(InitialScroll.hour(events: [event(at(monday, 0, 20))], days: [monday]) == 0)
    }

    @Test func aLateFirstEventStillOpensAtSeven() {
        #expect(InitialScroll.hour(events: [event(at(monday, 10))], days: [monday]) == 7)
    }

    @Test func allDayAndOffCanvasEventsDoNotCount() {
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!
        let events = [event(at(monday, 0), allDay: true), event(at(tuesday, 3))]
        #expect(InitialScroll.hour(events: events, days: [monday]) == 7)
    }

    /// The scroll target is a real `ConflictScrollAnchors` anchor whose
    /// layout top (anchors are stacked in a `VStack`, each `anchorStep`
    /// minutes tall) is exactly the hour's top.
    @Test func theTargetAnchorSitsAtTheHoursTop() throws {
        let hourHeight: CGFloat = 44
        let anchorMinutes = Array(stride(from: 0, to: 1440, by: ConflictScroll.anchorStep))
        for hour in 0...7 {
            let id = ConflictScroll.anchorID(minute: hour * 60)
            let index = try #require(anchorMinutes.firstIndex { ConflictScroll.anchorID(minute: $0) == id })
            let top = CGFloat(index) * CGFloat(ConflictScroll.anchorStep) / 60 * hourHeight
            #expect(top == CGFloat(hour) * hourHeight)
        }
    }

    @Test func theHoldReAimsOnlyWhenOffTarget() {
        let hh: CGFloat = 44
        let day: CGFloat = 24 * hh   // 1056, the live content height
        // At 06:00 exactly (offset 220 + the 44pt inset seen live): no aim.
        #expect(!InitialScroll.needsAim(.init(top: 264, contentHeight: day), hour: 6, hourHeight: hh, viewportHeight: 780))
        // Reset to the top by a layout pass: aim.
        #expect(InitialScroll.needsAim(.init(top: 0, contentHeight: day), hour: 6, hourHeight: hh, viewportHeight: 780))
        // A 780pt viewport can't reach 07:00 (308 > 1056 − 780 = 276): the
        // clamped end counts as there — the clamp uses the real viewport,
        // not the shorter phantom container, so the hold doesn't fight it.
        #expect(!InitialScroll.needsAim(.init(top: 276, contentHeight: day), hour: 7, hourHeight: hh, viewportHeight: 780))
        // Content shorter than the viewport: 0 is the only position.
        #expect(!InitialScroll.needsAim(.init(top: 0, contentHeight: day), hour: 7, hourHeight: hh, viewportHeight: 1200))
    }

    /// P2-F24: the conflict scroll's "wholly in view" check, fed the real
    /// viewport (780pt, top 264 = 06:00) instead of the phantom 675pt one,
    /// leaves Focus review (20:00–21:00) alone; the phantom made it scroll.
    @Test func focusReviewIsWhollyVisibleInTheRealViewport() {
        let hh: CGFloat = 44
        #expect(ConflictScroll.targetMinute(
            occurrence: (20 * 60)..<(21 * 60), earliestStart: 19 * 60 + 50,
            visibleTop: 264, visibleHeight: 780, hourHeight: hh) == nil)
        #expect(ConflictScroll.targetMinute(
            occurrence: (20 * 60)..<(21 * 60), earliestStart: 19 * 60 + 50,
            visibleTop: 220, visibleHeight: 675, hourHeight: hh) == 19 * 60 + 50)
    }
}
