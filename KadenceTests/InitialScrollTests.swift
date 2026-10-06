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

    /// CF4's acceptance line (layouts.md §3.1, amended 2026-10-07; G-052).
    @Test func dayFloorsToTheHour() {
        func day(_ h: Int, _ m: Int) -> Int {
            InitialScroll.minute(events: [event(at(monday, h, m))], days: [monday])
        }
        #expect(day(7, 15) == 6 * 60)
        #expect(day(8, 0) == 7 * 60)
        #expect(day(7, 59) == 6 * 60)
        #expect(day(5, 30) == 4 * 60)
        #expect(day(0, 30) == 0)
        #expect(InitialScroll.minute(events: [], days: [monday]) == 7 * 60)
        // The Routines window over `Daily routine` (Gym 07:00): 06:00.
        let daily = MockData.makeRoutineTemplates()[0].blocks.map(\.startMinutes)
        #expect(InitialScroll.minute(blockStartMinutes: daily) == 6 * 60)
        // Every result is a whole hour.
        for minute in stride(from: 0, to: 1440, by: 5) {
            #expect(InitialScroll.flooredDefault(firstStartMinute: minute) % 60 == 0)
        }
    }

    @Test func noEventsOpensAtSeven() {
        #expect(InitialScroll.minute(events: [], days: [monday]) == 7 * 60)
    }

    @Test func anEarlyEventOpensAnHourBeforeIt() {
        // Gym at 07:00 → 06:00. Floored to the hour since P2-C4 (§3.1,
        // amended 2026-10-07, G-052): 05:30 → 04:00 (P2-SF5 had 04:30).
        #expect(InitialScroll.minute(events: [event(at(monday, 7))], days: [monday]) == 6 * 60)
        #expect(InitialScroll.minute(events: [event(at(monday, 5, 30))], days: [monday]) == 4 * 60)
        #expect(InitialScroll.minute(events: [event(at(monday, 0, 20))], days: [monday]) == 0)
    }

    @Test func aLateFirstEventStillOpensAtSeven() {
        #expect(InitialScroll.minute(events: [event(at(monday, 10))], days: [monday]) == 7 * 60)
    }

    @Test func allDayAndOffCanvasEventsDoNotCount() {
        let tuesday = calendar.date(byAdding: .day, value: 1, to: monday)!
        let events = [event(at(monday, 0), allDay: true), event(at(tuesday, 3))]
        #expect(InitialScroll.minute(events: events, days: [monday]) == 7 * 60)
    }

    // MARK: Week view: a time of day (layouts.md §3.1, amended 2026-10-06; G-042; task P2-SF5)

    private var week: [Date] {
        (0..<7).map { calendar.date(byAdding: .day, value: $0, to: monday)! }
    }
    private func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: monday)! }

    @Test func weekUsesTheEarliestTimeOfDayAcrossColumns() {
        // Tue 08:00 is the first instant; Thu 05:30 is the earliest time of
        // day. Built before (earliest instant): 07:00. P2-SF5: 04:30.
        // P2-C4 (G-052, floored to the hour): 04:00.
        let events = [event(at(day(1), 8)), event(at(day(3), 5, 30))]
        #expect(InitialScroll.minute(events: events, days: week) == 4 * 60)
    }

    @Test func aPreviousDayCarryOverDoesNotCount() {
        // 23:50–01:20 starting Monday: on Tuesday it is a carry-over that
        // starts at 00:00 only by clipping. Tuesday's Day view ignores it…
        let late = Event(title: "Late", start: at(day(0), 23, 50), end: at(day(1), 1, 20))
        let breakfast = event(at(day(1), 7, 15))
        #expect(InitialScroll.minute(events: [late, breakfast], days: [day(1)]) == 6 * 60)   // 07:15 → 06:00 (G-052)
        // …and in a week it counts as 23:50, its own start time of day.
        #expect(InitialScroll.minute(events: [late, breakfast], days: week) == 6 * 60)   // 07:15 → 06:00 (G-052)
    }

    @Test func allDayIsIgnoredInAWeek() {
        let events = [event(at(day(2), 0), allDay: true), event(at(day(4), 9))]
        #expect(InitialScroll.minute(events: events, days: week) == 7 * 60)
    }

    @Test func dayViewIsTheDaysFirstEvent() {
        // One visible day: that day's own first event; other days' earlier
        // events don't count.
        let events = [event(at(day(1), 7)), event(at(day(3), 5, 30))]
        #expect(InitialScroll.minute(events: events, days: [day(1)]) == 6 * 60)
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
        #expect(!InitialScroll.needsAim(.init(top: 264, contentHeight: day), minute: 6 * 60, hourHeight: hh, viewportHeight: 780))
        // Reset to the top by a layout pass: aim.
        #expect(InitialScroll.needsAim(.init(top: 0, contentHeight: day), minute: 6 * 60, hourHeight: hh, viewportHeight: 780))
        // A 780pt viewport can't reach 07:00 (308 > 1056 − 780 = 276): the
        // clamped end counts as there — the clamp uses the real viewport,
        // not the shorter phantom container, so the hold doesn't fight it.
        #expect(!InitialScroll.needsAim(.init(top: 276, contentHeight: day), minute: 7 * 60, hourHeight: hh, viewportHeight: 780))
        // Content shorter than the viewport: 0 is the only position.
        #expect(!InitialScroll.needsAim(.init(top: 0, contentHeight: day), minute: 7 * 60, hourHeight: hh, viewportHeight: 1200))
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

    /// `#expect` can't call a `mutating` method on a captured value (the
    /// macro wraps its argument in a closure), so this does it through
    /// `inout` — Swift's pass-by-reference for a value type.
    private func aim(_ hold: inout InitialScroll.Hold, _ position: InitialScroll.Position,
                     hourHeight: CGFloat, viewportHeight: CGFloat) -> Bool {
        hold.shouldAim(position, hourHeight: hourHeight, viewportHeight: viewportHeight)
    }

    // MARK: The Routines window (layouts.md §8, amended 2026-10-06; G-047; task P2-SF4)

    @Test func routinesDailyRoutineOpensAtSix() {
        // The seeded template: Gym 07:00 is its earliest block.
        let blocks = MockData.makeRoutineTemplates()[0].blocks.map(\.startMinutes)
        #expect(InitialScroll.minute(blockStartMinutes: blocks) == 6 * 60)
    }

    @Test func routinesNoBlocksOpensAtSeven() {
        #expect(InitialScroll.minute(blockStartMinutes: []) == 7 * 60)
    }

    @Test func routinesFirstBlockAtFiveThirtyOpensAtFour() {
        // P2-C4 (G-052): 04:00, not P2-SF4's 04:30.
        #expect(InitialScroll.minute(blockStartMinutes: [9 * 60, 5 * 60 + 30]) == 4 * 60)
        #expect(InitialScroll.minute(blockStartMinutes: [20]) == 0, "never above 00:00")
        #expect(InitialScroll.minute(blockStartMinutes: [10 * 60]) == 7 * 60, "never below 07:00")
    }

    /// The 04:30 target lands on the 04:30 anchor's top, and the hold
    /// counts that as "there".
    @Test func aMinuteTargetIsAnAnchorTop() {
        let hh: CGFloat = 44
        let day = 24 * hh
        #expect(!InitialScroll.needsAim(.init(top: 4.5 * hh, contentHeight: day), minute: 270, hourHeight: hh, viewportHeight: 780))
        #expect(InitialScroll.needsAim(.init(top: 4 * hh, contentHeight: day), minute: 270, hourHeight: hh, viewportHeight: 780))
    }

    @Test func routinesHoldThroughSettlingPasses() {
        let hh: CGFloat = 44
        let day = 24 * hh
        var hold = InitialScroll.Hold(target: 7 * 60)
        hold.retarget(6 * 60)   // the template arrives
        // Layout passes reset the scroll to 0, then a phantom 44pt-inset pass:
        // each one off target re-aims; on target, none.
        #expect(aim(&hold, .init(top: 0, contentHeight: day), hourHeight: hh, viewportHeight: 56))
        #expect(aim(&hold, .init(top: 220, contentHeight: day), hourHeight: hh, viewportHeight: 596))
        #expect(!aim(&hold, .init(top: 264, contentHeight: day), hourHeight: hh, viewportHeight: 780))
        #expect(aim(&hold, .init(top: 0, contentHeight: day), hourHeight: hh, viewportHeight: 780))
        #expect(hold.isHolding)
        // The user scrolls: no more aims.
        hold.release()
        #expect(!aim(&hold, .init(top: 0, contentHeight: day), hourHeight: hh, viewportHeight: 780))
    }

    @Test func routinesReappliedOnTemplateChangeOnly() {
        let hh: CGFloat = 44
        let day = 24 * hh
        var hold = InitialScroll.Hold(target: 7 * 60)
        hold.retarget(InitialScroll.minute(blockStartMinutes: [7 * 60]))   // Daily routine
        hold.release()                                                     // the user scrolled
        // A Blocks/Windows switch or an edit (Gym dragged to 05:30) is not a
        // retarget: the hold stays released and its target unchanged.
        #expect(hold.target == 6 * 60)
        #expect(!aim(&hold, .init(top: 0, contentHeight: day), hourHeight: hh, viewportHeight: 780))
        // Another template: held again at its own default.
        hold.retarget(InitialScroll.minute(blockStartMinutes: [5 * 60 + 30]))
        #expect(hold.target == 4 * 60)
        #expect(hold.isHolding)
        #expect(aim(&hold, .init(top: 0, contentHeight: day), hourHeight: hh, viewportHeight: 780))
    }

    @Test func theHoldGivesUpAfterMaxAims() {
        var hold = InitialScroll.Hold(target: 6 * 60)
        for _ in 0..<InitialScroll.maxAims {
            #expect(aim(&hold, .init(top: 0, contentHeight: 1056), hourHeight: 44, viewportHeight: 780))
        }
        #expect(!aim(&hold, .init(top: 0, contentHeight: 1056), hourHeight: 44, viewportHeight: 780))
        #expect(!hold.isHolding)
    }
}
