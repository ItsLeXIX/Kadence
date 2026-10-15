//
//  ClockChangeTests.swift
//  KadenceTests
//
//  P3S2-F01 — components.md §31.5 T1–T12 (G-100; DECISIONS 2026-10-15
//  "Times are wall-clock times, also on the days the clocks change").
//  Europe/Vienna with the calendar injected, so the Mac's own zone never
//  enters. Sun 25 Oct 2026 has 25 hours (03:00 CEST becomes 02:00 CET),
//  Sun 29 Mar 2026 has 23 (02:00 CET becomes 03:00 CEST). Every moment is
//  built from UTC with an explicit offset, so "02:30 CET" is never read
//  through a formatter's own choice of occurrence.
//

import Testing
import Foundation
import CoreGraphics
import SwiftData
@testable import Kadence

private let vienna = TravelFixtures.calendar

/// A moment at local `h:mi` with UTC offset `offset` hours.
private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, offset: Int) -> Date {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    return utc.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
        .addingTimeInterval(TimeInterval(-offset * 3600))
}
/// Sun 25 Oct 2026 / 26 Oct, Europe/Vienna.
private func oct(_ d: Int, _ h: Int, _ mi: Int, cest: Bool) -> Date { at(2026, 10, d, h, mi, offset: cest ? 2 : 1) }
/// Mar 2026, Europe/Vienna.
private func mar(_ d: Int, _ h: Int, _ mi: Int, cest: Bool) -> Date { at(2026, 3, d, h, mi, offset: cest ? 2 : 1) }

private let oct25 = oct(25, 0, 0, cest: true)
private let mar29 = mar(29, 0, 0, cest: false)
private let oct22 = oct(22, 0, 0, cest: true)

private let hourDay = Tokens.Size.hourHeightDay
private let hourWeek = Tokens.Size.hourHeightWeek

private func geometry(_ day: Date, _ hourHeight: CGFloat = hourDay) -> TimeGeometry {
    TimeGeometry(dayStart: day, hourHeight: hourHeight, calendar: vienna)
}

private func close(_ a: CGFloat, _ b: CGFloat) -> Bool { abs(a - b) < 0.001 }

/// The drawn `[top, bottom)` of an interval on `g`, in hours.
private func drawnHours(_ g: TimeGeometry, _ start: Date, _ end: Date) -> (CGFloat, CGFloat) {
    let top = g.y(for: start) / g.hourHeight
    return (top, top + g.height(from: start, to: end) / g.hourHeight)
}

private func id(_ n: Int) -> UUID { UUID(uuidString: String(format: "00000000-0000-0000-0031-%012d", n))! }

@MainActor
private func makeStore() throws -> (EventStore, ModelContext, UndoStack) {
    let container = try ModelContainer(
        for: Schema(KadenceSchema.models),
        configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    let context = ModelContext(container)
    let undo = UndoStack()
    return (EventStore(context: context, undo: undo), context, undo)
}

/// R: a template block 20:00–21:00 every day (§31.5).
@MainActor
private func routineR(_ context: ModelContext, at minutes: Int = 20 * 60, length: Int = 60) -> (RoutineTemplate, RoutineBlock) {
    let block = RoutineBlock(title: "R", startMinutes: minutes, duration: TimeInterval(length * 60))
    let template = RoutineTemplate(name: "Daily routine", activeWeekdays: Set(1...7), blocks: [block])
    context.insert(template)
    return (template, block)
}

@MainActor
private func materialize(_ template: RoutineTemplate, on day: Date, store: EventStore) -> Int {
    let next = vienna.date(byAdding: .day, value: 1, to: day)!
    return RoutineEngine.materialize(template: template, into: DateInterval(start: day, end: next),
                                     today: day, recordsUndo: false, store: store, calendar: vienna)
}

@MainActor
private func events(_ context: ModelContext) -> [Event] {
    (try? context.fetch(FetchDescriptor<Event>(sortBy: [SortDescriptor(\.start)]))) ?? []
}

@MainActor
struct ClockChangeTests {

    // MARK: T1 — WallClock

    @Test("T1 · 25 Oct: minuteOfDay and moment read the wall clock")
    func wallClockAutumn() {
        #expect(WallClock.minuteOfDay(oct(25, 1, 30, cest: true), on: oct25, calendar: vienna) == 90)
        #expect(WallClock.minuteOfDay(oct(25, 2, 30, cest: true), on: oct25, calendar: vienna) == 150)
        #expect(WallClock.minuteOfDay(oct(25, 2, 30, cest: false), on: oct25, calendar: vienna) == 150)
        #expect(WallClock.minuteOfDay(oct(25, 3, 30, cest: false), on: oct25, calendar: vienna) == 210)
        #expect(WallClock.minuteOfDay(oct(25, 18, 0, cest: false), on: oct25, calendar: vienna) == 1080)
        #expect(WallClock.moment(minuteOfDay: 150, on: oct25, calendar: vienna) == oct(25, 2, 30, cest: true))
        #expect(WallClock.moment(minuteOfDay: 1080, on: oct25, calendar: vienna) == oct(25, 18, 0, cest: false))
        #expect(WallClock.moment(minuteOfDay: 1440, on: oct25, calendar: vienna) == oct(26, 0, 0, cest: false))
        // Clipping, as the midnight rule.
        #expect(WallClock.minuteOfDay(oct(24, 23, 0, cest: true), on: oct25, calendar: vienna) == 0)
        #expect(WallClock.minuteOfDay(oct(26, 0, 0, cest: false), on: oct25, calendar: vienna) == 1440)
    }

    @Test("T1 · 29 Mar: the missing hour moves forward by the gap")
    func wallClockSpring() {
        #expect(WallClock.minuteOfDay(mar(29, 1, 30, cest: false), on: mar29, calendar: vienna) == 90)
        #expect(WallClock.minuteOfDay(mar(29, 3, 30, cest: true), on: mar29, calendar: vienna) == 210)
        #expect(WallClock.minuteOfDay(mar(29, 18, 0, cest: true), on: mar29, calendar: vienna) == 1080)
        #expect(WallClock.moment(minuteOfDay: 150, on: mar29, calendar: vienna) == mar(29, 3, 30, cest: true))
        #expect(WallClock.moment(minuteOfDay: 1080, on: mar29, calendar: vienna) == mar(29, 18, 0, cest: true))
    }

    @Test("T1 · Thu 22 Oct: both functions agree with elapsed time at every quarter hour")
    func wallClockOrdinaryDay() {
        for quarter in 0..<96 {
            let minutes = quarter * 15
            let elapsed = oct22.addingTimeInterval(TimeInterval(minutes * 60))
            #expect(WallClock.moment(minuteOfDay: minutes, on: oct22, calendar: vienna) == elapsed)
            #expect(WallClock.minuteOfDay(elapsed, on: oct22, calendar: vienna) == Double(minutes))
        }
    }

    // MARK: T2 — Day 25 Oct

    @Test("T2 · Day 25 Oct: every block at its wall-clock rows")
    func dayAutumn() throws {
        let g = geometry(oct25)
        let a = (oct(25, 1, 0, cest: true), oct(25, 1, 45, cest: true))
        let b = (oct(25, 1, 30, cest: true), oct(25, 3, 30, cest: false))
        let b1 = (oct(25, 2, 15, cest: true), oct(25, 2, 45, cest: true))
        let b2 = (oct(25, 2, 15, cest: false), oct(25, 2, 45, cest: false))
        let b3 = (oct(25, 2, 45, cest: true), oct(25, 2, 15, cest: false))
        let c = (oct(25, 18, 0, cest: false), oct(25, 19, 30, cest: false))
        let leave = oct(25, 17, 45, cest: false)

        #expect(drawnHours(g, a.0, a.1) == (1.0, 1.75))
        #expect(drawnHours(g, b.0, b.1) == (1.5, 3.5))
        #expect(drawnHours(g, b1.0, b1.1) == (2.25, 2.75))
        #expect(drawnHours(g, b2.0, b2.1) == (2.25, 2.75))
        #expect(drawnHours(g, b3.0, b3.1) == (2.75, 3.25))
        #expect(drawnHours(g, c.0, c.1) == (18, 19.5))
        #expect(drawnHours(g, leave, c.0) == (17.75, 18))

        // B: block `01:30-03:30`, inspector `Duration 3 h`.
        let formatter = DateFormatter()
        formatter.timeZone = vienna.timeZone
        formatter.dateFormat = "HH:mm"
        let eventB = Event(title: "B", start: b.0, end: b.1)
        #expect(GridBlockModel(event: eventB, now: oct25).timeRange(formatter: formatter) == "01:30-03:30")
        #expect(ImportedInspectorDetails.durationText(eventB.duration) == "3 h")

        // Laid out: B1 and B2 side by side, Climbing's band case 1 at 17:45.
        let items = [
            LayoutItem(id: id(1), start: a.0, end: a.1, title: "A"),
            LayoutItem(id: id(2), start: b.0, end: b.1, title: "B"),
            LayoutItem(id: id(3), start: b1.0, end: b1.1, title: "B1"),
            LayoutItem(id: id(4), start: b2.0, end: b2.1, title: "B2"),
            LayoutItem(id: id(5), start: b3.0, end: b3.1, title: "B3"),
            LayoutItem(id: id(6), start: c.0, end: c.1, title: "Climbing", departAt: leave),
        ]
        let layout = DayLayoutEngine.layout(items: items, columnWidth: 800, geometry: g)
        let frame1 = try #require(layout.block(for: id(3))).frame
        let frame2 = try #require(layout.block(for: id(4))).frame
        #expect(close(frame1.minY, 2.25 * hourDay) && close(frame2.minY, 2.25 * hourDay))
        #expect(frame1.maxX <= frame2.minX, "B1 is left of B2, not on top of it")
        #expect(close(try #require(layout.block(for: id(5))).frame.minY, 2.75 * hourDay))
        #expect(close(try #require(layout.block(for: id(2))).frame.minY, 1.5 * hourDay))
        #expect(close(try #require(layout.block(for: id(6))).frame.minY, 18 * hourDay))

        // No conflict: B1 and B2 do not overlap in time, even with one a routine block.
        let routineB1 = Event(title: "B1", start: b1.0, end: b1.1, origin: .routine)
        let manualB2 = Event(title: "B2", start: b2.0, end: b2.1)
        #expect(routineB1.end <= manualB2.start)
        #expect(ConflictEngine.detect(events: [routineB1, manualB2], routineBlocks: []).isEmpty)
    }

    @Test("T2 · Day 25 Oct: routine 20:00 materialises at 20:00 CET, on the 20:00 row")
    func routineAutumn() throws {
        let (store, context, _) = try makeStore()
        let (template, _) = routineR(context)
        #expect(materialize(template, on: oct25, store: store) == 1)
        let instance = try #require(events(context).first)
        #expect(instance.start == oct(25, 20, 0, cest: false))
        #expect(instance.end == oct(25, 21, 0, cest: false))
        #expect(drawnHours(geometry(oct25), instance.start, instance.end) == (20, 21))
    }

    // MARK: T3 — Day 29 Mar

    @Test("T3 · Day 29 Mar: every block at its wall-clock rows")
    func daySpring() {
        let g = geometry(mar29)
        #expect(drawnHours(g, mar(29, 1, 0, cest: false), mar(29, 1, 45, cest: false)) == (1.0, 1.75))
        let b = (mar(29, 1, 30, cest: false), mar(29, 3, 30, cest: true))
        #expect(drawnHours(g, b.0, b.1) == (1.5, 3.5))
        #expect(ImportedInspectorDetails.durationText(b.1.timeIntervalSince(b.0)) == "1 h")
        #expect(drawnHours(g, mar(29, 18, 0, cest: true), mar(29, 19, 30, cest: true)) == (18, 19.5))
        #expect(drawnHours(g, mar(29, 17, 45, cest: true), mar(29, 18, 0, cest: true)) == (17.75, 18))
    }

    @Test("T3 · Day 29 Mar: routine 20:00 at 20:00 CEST; 02:30 in the gap at 03:30 CEST")
    func routineSpring() throws {
        let (store, context, _) = try makeStore()
        let (evening, _) = routineR(context)
        let (night, _) = routineR(context, at: 2 * 60 + 30, length: 30)
        materialize(evening, on: mar29, store: store)
        materialize(night, on: mar29, store: store)
        let all = events(context)
        #expect(all.count == 2)
        #expect(all[0].start == mar(29, 3, 30, cest: true))
        #expect(all[0].end == mar(29, 4, 0, cest: true))
        #expect(drawnHours(geometry(mar29), all[0].start, all[0].end) == (3.5, 4))
        #expect(all[1].start == mar(29, 20, 0, cest: true))
        #expect(drawnHours(geometry(mar29), all[1].start, all[1].end) == (20, 21))
    }

    @Test("T2 · 25 Oct: a routine block in the repeated hour is the first one")
    func routineRepeatedHour() throws {
        let (store, context, _) = try makeStore()
        let (night, _) = routineR(context, at: 2 * 60 + 30, length: 30)
        materialize(night, on: oct25, store: store)
        #expect(events(context).first?.start == oct(25, 2, 30, cest: true))
    }

    // MARK: T4 — Week

    @Test("T4 · Week of each change: Sunday at T2 / T3's rows, Mon–Sat exactly as before")
    func week() throws {
        for (monday, sunday, climbing, end) in [
            (oct(19, 0, 0, cest: true), oct25, oct(25, 18, 0, cest: false), oct(25, 19, 30, cest: false)),
            (mar(23, 0, 0, cest: false), mar29, mar(29, 18, 0, cest: true), mar(29, 19, 30, cest: true)),
        ] {
            for offset in 0..<6 {
                let day = vienna.date(byAdding: .day, value: offset, to: monday)!
                let g = geometry(day, hourWeek)
                let items = [
                    LayoutItem(id: id(10), start: day.addingTimeInterval(9 * 3600), end: day.addingTimeInterval(10.5 * 3600), title: "L"),
                    LayoutItem(id: id(11), start: day.addingTimeInterval(10 * 3600), end: day.addingTimeInterval(11 * 3600), title: "M",
                               departAt: day.addingTimeInterval(9.25 * 3600)),
                ]
                // The same layout as on a ruler of elapsed time — the old maths.
                #expect(DayLayoutEngine.layout(items: items, columnWidth: 140, geometry: g)
                        == DayLayoutEngine.layout(items: items, columnWidth: 140, geometry: g.elapsedRuler))
            }
            let g = geometry(sunday, hourWeek)
            let layout = DayLayoutEngine.layout(
                items: [LayoutItem(id: id(12), start: climbing, end: end, title: "Climbing",
                                   departAt: climbing.addingTimeInterval(-15 * 60))],
                columnWidth: 140, geometry: g)
            #expect(close(try #require(layout.block(for: id(12))).frame.minY, 18 * hourWeek))
            #expect(drawnHours(g, climbing, end) == (18, 19.5))
        }
    }

    // MARK: T5 — Month

    @Test("T5 · Month: Climbing in the change day's cell at 18:00; a midnight-crossing event in its start cell only")
    func month() {
        let formatter = DateFormatter()
        formatter.timeZone = vienna.timeZone
        formatter.dateFormat = "HH:mm"
        for (sunday, climbing) in [(oct25, oct(25, 18, 0, cest: false)), (mar29, mar(29, 18, 0, cest: true))] {
            let event = Event(title: "Climbing", start: climbing, end: climbing.addingTimeInterval(90 * 60))
            let cell = MonthGridView.timedEvents([event], on: sunday, calendar: vienna)
            #expect(cell.map(\.title) == ["Climbing"])
            #expect(formatter.string(from: cell[0].start) == "18:00")
        }
        let late = Event(title: "Late", start: oct(24, 23, 30, cest: true), end: oct(25, 0, 30, cest: true))
        #expect(MonthGridView.timedEvents([late], on: oct(24, 0, 0, cest: true), calendar: vienna).count == 1)
        #expect(MonthGridView.timedEvents([late], on: oct25, calendar: vienna).isEmpty)
    }

    // MARK: T6 — Now line

    @Test("T6 · The column's now line is level with the gutter's now time at eight clocks, Day and Week")
    func nowLine() {
        let clocks: [(Date, Date, CGFloat)] = [
            (oct25, oct(25, 1, 59, cest: true), 1 + 59.0 / 60),
            (oct25, oct(25, 2, 30, cest: true), 2.5),
            (oct25, oct(25, 2, 30, cest: false), 2.5),
            (oct25, oct(25, 3, 30, cest: false), 3.5),
            (oct25, oct(25, 18, 0, cest: false), 18),
            (mar29, mar(29, 1, 59, cest: false), 1 + 59.0 / 60),
            (mar29, mar(29, 3, 0, cest: true), 3),
            (mar29, mar(29, 18, 0, cest: true), 18),
        ]
        for hourHeight in [hourDay, hourWeek] {
            for (day, now, hours) in clocks {
                let column = geometry(day, hourHeight)
                // Week's gutter is the first column's ruler (Monday).
                let gutter = geometry(vienna.date(byAdding: .day, value: -6, to: day)!, hourHeight)
                let line = NowLineView(geometry: column, now: now).lineY
                let label = gutter.yForTimeOfDay(now)
                #expect(close(line, hours * hourHeight), "\(now)")
                #expect(close(label, line), "\(now)")
                // A42's suppression is computed on the same y.
                let view = TimeGutterView(geometry: gutter, now: now, showsNow: true, cursor: nil)
                #expect(view.markerYs.count == 1 && close(view.markerYs[0], line))
            }
        }
    }

    // MARK: T7 — Initial scroll

    @Test("T7 · Initial scroll opens at 05:00 for a 06:00 first event on both days and in the week")
    func initialScroll() {
        let autumn = Event(title: "Early", start: oct(25, 6, 0, cest: false), end: oct(25, 7, 0, cest: false))
        #expect(InitialScroll.minute(events: [autumn], days: [oct25], calendar: vienna) == 5 * 60)
        let spring = Event(title: "Early", start: mar(29, 6, 0, cest: true), end: mar(29, 7, 0, cest: true))
        #expect(InitialScroll.minute(events: [spring], days: [mar29], calendar: vienna) == 5 * 60)
        let week = (0..<7).map { vienna.date(byAdding: .day, value: $0, to: oct(19, 0, 0, cest: true))! }
        let later = Event(title: "Lecture", start: oct(20, 9, 0, cest: true), end: oct(20, 10, 0, cest: true))
        #expect(InitialScroll.minute(events: [later, autumn], days: week, calendar: vienna) == 5 * 60)
    }

    // MARK: T8 — Windows and the quiet rule

    private static let sleep = (weekdays: Set(1...7), start: 22 * 60, end: 7 * 60)

    private func expectSleepSpans(_ spans: [(start: Date, end: Date)], on day: Date, sourceLocation: SourceLocation = #_sourceLocation) {
        let next = vienna.date(byAdding: .day, value: 1, to: day)!
        let morningEnd = WallClock.moment(minuteOfDay: 7 * 60, on: day, calendar: vienna)
        let eveningStart = WallClock.moment(minuteOfDay: 22 * 60, on: day, calendar: vienna)
        let sorted = spans.sorted { $0.start < $1.start }
        #expect(sorted.count == 2, sourceLocation: sourceLocation)
        #expect(sorted.first?.start == day && sorted.first?.end == morningEnd, sourceLocation: sourceLocation)
        #expect(sorted.last?.start == eveningStart && sorted.last?.end == next, sourceLocation: sourceLocation)
    }

    @Test("T8 · Sleep 22:00–07:00 spans are wall-clock on 24–26 Oct and 28–30 Mar, in all three span builders")
    func sleepSpans() {
        let s = Self.sleep
        let quiet = QuietWindow(weekdays: s.weekdays, startMinutes: s.start, endMinutes: s.end, label: "Sleep")
        let window = TimeWindow(weekdays: s.weekdays, startMinutes: s.start, endMinutes: s.end, kind: .protected, label: "Sleep")
        let fixture = TimeWindowFixture(weekdays: s.weekdays, startMinutes: s.start, endMinutes: s.end, kind: .protected, label: "Sleep")
        let days = [oct(24, 0, 0, cest: true), oct25, oct(26, 0, 0, cest: false),
                    mar(28, 0, 0, cest: false), mar29, mar(30, 0, 0, cest: true)]
        for day in days {
            expectSleepSpans(quiet.spans(on: day, calendar: vienna), on: day)
            expectSleepSpans(window.spans(on: day, calendar: vienna), on: day)
            expectSleepSpans(fixture.spans(on: day, calendar: vienna), on: day)
        }
        // The two change days, spelled out (§31.4).
        let autumn = quiet.spans(on: oct25, calendar: vienna).sorted { $0.start < $1.start }
        #expect(autumn[0].start == oct(25, 0, 0, cest: true) && autumn[0].end == oct(25, 7, 0, cest: false))
        #expect(autumn[0].end.timeIntervalSince(autumn[0].start) == 8 * 3600)
        #expect(autumn[1].start == oct(25, 22, 0, cest: false) && autumn[1].end == oct(26, 0, 0, cest: false))
        let spring = quiet.spans(on: mar29, calendar: vienna).sorted { $0.start < $1.start }
        #expect(spring[0].start == mar(29, 0, 0, cest: false) && spring[0].end == mar(29, 7, 0, cest: true))
        #expect(spring[0].end.timeIntervalSince(spring[0].start) == 6 * 3600)
    }

    @Test("T8 · The quiet rule holds to 07:00 on both days and does not hold 21:30 CET on 25 Oct")
    func quietRule() {
        let s = Self.sleep
        let quiet = [QuietWindow(weekdays: s.weekdays, startMinutes: s.start, endMinutes: s.end, label: "Sleep")]
        func event(_ start: Date) -> TravelEventSnapshot {
            TravelEventSnapshot(title: "E", start: start, end: start.addingTimeInterval(30 * 60), origin: .manual)
        }
        let autumn = NotificationPlanner.hold(oct(25, 6, 40, cest: false), event: event(oct(25, 7, 30, cest: false)),
                                              windows: quiet, calendar: vienna)
        #expect(autumn.0 == oct(25, 7, 0, cest: false) && autumn.1 == "Sleep")
        let spring = NotificationPlanner.hold(mar(29, 6, 40, cest: true), event: event(mar(29, 7, 30, cest: true)),
                                              windows: quiet, calendar: vienna)
        #expect(spring.0 == mar(29, 7, 0, cest: true) && spring.1 == "Sleep")
        let evening = NotificationPlanner.hold(oct(25, 21, 30, cest: false), event: event(oct(25, 21, 45, cest: false)),
                                               windows: quiet, calendar: vienna)
        #expect(evening.0 == oct(25, 21, 30, cest: false) && evening.1 == nil)
    }

    @Test("T8 · A routine block 21:30–22:30 is refused on every day, 25 Oct included")
    func routineRefusal() {
        let s = Self.sleep
        let window = TimeWindow(weekdays: s.weekdays, startMinutes: s.start, endMinutes: s.end, kind: .protected, label: "Sleep")
        for weekday in 1...7 {
            #expect(ProtectedWindowRule.refuses(startMinutes: 21 * 60 + 30, duration: 3600, weekday: weekday, windows: [window]))
        }
    }

    // MARK: T9 — Routine data

    @Test("T9 · R's routineStart notification fires 19:55 CET on 25 Oct and 19:55 CEST on 29 Mar")
    func routineNotification() throws {
        for (day, fire) in [(oct25, oct(25, 19, 55, cest: false)), (mar29, mar(29, 19, 55, cest: true))] {
            let (store, context, _) = try makeStore()
            let (template, _) = routineR(context)
            materialize(template, on: day, store: store)
            let instance = try #require(events(context).first)
            let snapshot = TravelEventSnapshot(id: instance.id, title: "R", start: instance.start, end: instance.end,
                                               origin: .routine, sourceID: "routine")
            let now = WallClock.moment(minuteOfDay: 12 * 60, on: day, calendar: vienna)
            let planned = NotificationPlanner.plan(NotificationPlannerTests.input(at: now, events: [snapshot], legs: [:]))
            let n = try #require(planned.first { $0.subjectID == instance.id.uuidString })
            #expect(n.fireAt == fire)
        }
    }

    @Test("T9 · An instance at 19:00 CET from the old maths is corrected in one update; a detached one stays")
    func oldInstanceCorrected() throws {
        for detached in [false, true] {
            let (store, context, undo) = try makeStore()
            let (template, block) = routineR(context)
            let externalID = "\(block.id.uuidString)#2026-10-25"
            let old = Event(title: "R", start: oct(25, 19, 0, cest: false), end: oct(25, 20, 0, cest: false),
                            origin: .routine, sourceID: template.id.uuidString, externalID: externalID)
            old.routineLink = detached ? .detached : .linked
            context.insert(old)

            #expect(materialize(template, on: oct25, store: store) == 0)
            let all = events(context)
            #expect(all.count == 1)
            #expect(all[0].externalID == externalID)
            #expect(all[0].start == (detached ? oct(25, 19, 0, cest: false) : oct(25, 20, 0, cest: false)))
            #expect(undo.undoSteps.isEmpty)
        }
    }

    // MARK: T10 — Drag

    @Test("T10 · Dropping at y(20) and y(2.5) gives the wall-clock time; nudge and snooze stay elapsed")
    func drag() throws {
        let autumn = geometry(oct25)
        let climbing = oct(25, 18, 0, cest: false)
        let dropped = autumn.dragged(climbing, by: 2 * hourDay, snapMinutes: 15)
        #expect(dropped == oct(25, 20, 0, cest: false))
        #expect(dropped.addingTimeInterval(90 * 60) == oct(25, 21, 30, cest: false))
        #expect(autumn.dragged(climbing, by: 2.5 * hourDay - 18 * hourDay, snapMinutes: 15) == oct(25, 2, 30, cest: true))

        let spring = geometry(mar29)
        let block = mar(29, 5, 0, cest: true)
        #expect(spring.dragged(block, by: 2.5 * hourDay - 5 * hourDay, snapMinutes: 15) == mar(29, 3, 30, cest: true))
        #expect(spring.date(forY: 2.5 * hourDay) == mar(29, 3, 30, cest: true))

        // A move keeps the elapsed duration; ⌥↓ moves by elapsed 15 minutes.
        let (store, context, _) = try makeStore()
        let event = Event(title: "Climbing", start: climbing, end: climbing.addingTimeInterval(90 * 60))
        context.insert(event)
        store.move(event, toStart: dropped)
        #expect(event.start == oct(25, 20, 0, cest: false) && event.end == oct(25, 21, 30, cest: false))
        let night = Event(title: "Night", start: oct(25, 2, 50, cest: true), end: oct(25, 3, 0, cest: false))
        context.insert(night)
        store.move(night, by: 15 * 60)
        #expect(night.start == oct(25, 2, 5, cest: false))
    }

    // MARK: T11 — Travel

    @Test("T11 · Climbing on 25 Oct: leave 17:45 CET, notification 17:40 CET, cache slot sunday 17:30")
    func travel() throws {
        let climbing = TravelFixtures.manual(34, "Climbing", oct(25, 18, 0, cest: false), oct(25, 19, 30, cest: false),
                                             place: TravelFixtures.gymID)
        let now = oct(25, 6, 0, cest: false)
        let first = TravelLegPlanner.plan(TravelFixtures.input(events: [climbing], now: now))
        let request = try #require(first.requests.first)
        #expect(request.dayType == .sunday)
        #expect(request.slotMinutes == 17 * 60 + 30)
        let legs = TravelLegPlanner.plan(TravelFixtures.input(
            events: [climbing], cache: TravelFixtures.answer(first.requests, at: now), now: now)).legs
        #expect(legs[climbing.id]?.departAt == oct(25, 17, 45, cest: false))

        let planned = NotificationPlanner.plan(NotificationPlannerTests.input(at: now, events: [climbing], legs: legs))
        let leave = try #require(planned.first { $0.identifier == "leave.\(climbing.id.uuidString)" })
        #expect(leave.fireAt == oct(25, 17, 40, cest: false))
        #expect(leave.text.title == "Leave by 17:45 for Climbing")
    }

    // MARK: T12 — Source scan

    @Test("T12 · Outside WallClock, nothing adds elapsed minutes or hours to a day start")
    func sourceScan() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Kadence")
        let dayStarts = "(dayStart|referenceDayStart|startOfDay|day)"
        let patterns = [
            // `day.addingTimeInterval(… * 60)` / `* 3600`, or `startOfDay(for: x).addingTimeInterval(…)`.
            try Regex("\\b\(dayStarts)(\\(for: [^)]*\\))?\\s*\\.addingTimeInterval\\([^)]*\\*\\s*(60|3600)\\b"),
            try Regex("byAdding: \\.(minute|hour)\\b"),
        ]
        var offenders: [String] = []
        var scanned = 0
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift", url.lastPathComponent != "WallClock.swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            scanned += 1
            for (number, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
                if patterns.contains(where: { code.contains($0) }) {
                    offenders.append("\(url.lastPathComponent):\(number + 1)")
                }
            }
        }
        #expect(scanned > 100, "the scan read \(scanned) files")
        #expect(offenders.isEmpty, "\(offenders)")
        // The scan is live: it finds the banned form.
        #expect("dayStart.addingTimeInterval(TimeInterval(minutes * 60))".contains(patterns[0]))
        #expect("calendar.date(byAdding: .minute, value: m, to: day)".contains(patterns[1]))
    }
}
