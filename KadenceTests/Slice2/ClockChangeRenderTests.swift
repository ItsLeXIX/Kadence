//
//  ClockChangeRenderTests.swift
//  KadenceTests
//
//  P3S2-F01 frames — components.md §30 item 24: Day, Week and Month of Sun
//  25 Oct 2026 and Sun 29 Mar 2026, offscreen, clock pinned at 18:30 local,
//  with §31.5's T2 / T3 events, a 20:00 routine block (materialised by the
//  engine), `Climbing`'s band and Sleep 22:00–07:00. The real views
//  (`TimedCanvasView`, `MonthGridView`) on an in-memory store. They draw in
//  `Calendar.current`, so the frames are only written when this Mac is in
//  Europe/Vienna (it is Parsa's); the geometry itself is tested in
//  `ClockChangeTests` with the calendar injected.
//

import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import Kadence

private func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, offset: Int) -> Date {
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    return utc.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
        .addingTimeInterval(TimeInterval(-offset * 3600))
}

/// Day view, Week view or Month view of one change day.
private struct ClockChangeCanvas: View {
    enum Mode { case day, week, month }
    let mode: Mode
    let days: [Date]
    let events: [Event]
    let fixtures: MockFixtures
    let now: Date
    let store: EventStore
    let state: CalendarState

    @FocusState private var focus: CalendarState.FocusRegion?

    var body: some View {
        Group {
            switch mode {
            case .month:
                MonthGridView(days: days, events: events, fixtures: fixtures, now: now, anchorMonth: now)
            case .day, .week:
                TimedCanvasView(
                    days: days, events: events, fixtures: fixtures,
                    hourHeight: mode == .day ? Tokens.Size.hourHeightDay : Tokens.Size.hourHeightWeek,
                    now: now, store: store, focusedRegion: $focus, onTab: { _ in .ignored })
            }
        }
        .environment(state)
        .background(Tokens.Color.Surface.canvas)
    }
}

@MainActor
struct ClockChangeRenderTests {

    @Test("Item 24 renders (offscreen, clock pinned 18:30): Day, Week, Month of 25 Oct and 29 Mar")
    func renders() throws {
        let calendar = Calendar.current
        guard calendar.timeZone.identifier == "Europe/Vienna" else {
            // The views draw in the Mac's zone; elsewhere the frames would
            // show another zone's day. The geometry is tested regardless.
            return
        }
        for (name, sunday, monday, summerAfter) in [
            ("1025", at(2026, 10, 25, 0, 0, offset: 2), at(2026, 10, 19, 0, 0, offset: 2), false),
            ("0329", at(2026, 3, 29, 0, 0, offset: 1), at(2026, 3, 23, 0, 0, offset: 1), true),
        ] {
            let container = try ModelContainer(for: Schema(KadenceSchema.models),
                                               configurations: ModelConfiguration(isStoredInMemoryOnly: true))
            let context = ModelContext(container)
            let store = EventStore(context: context, undo: UndoStack())
            Phase3Render.keep.append(container)

            // After the change the offset is `late`, before it `early`.
            let early = summerAfter ? 1 : 2, late = summerAfter ? 2 : 1
            let y = summerAfter ? 2026 : 2026, mo = summerAfter ? 3 : 10, d = summerAfter ? 29 : 25
            func event(_ title: String, _ start: Date, _ end: Date, origin: EventOrigin = .manual) -> Event {
                let e = Event(title: title, start: start, end: end, origin: origin, sourceKey: .graphite, sourceID: "personal")
                context.insert(e)
                return e
            }
            event("A before", at(y, mo, d, 1, 0, offset: early), at(y, mo, d, 1, 45, offset: early))
            event("B across", at(y, mo, d, 1, 30, offset: early), at(y, mo, d, 3, 30, offset: late))
            if !summerAfter {
                event("B1 first 02:00", at(y, mo, d, 2, 15, offset: early), at(y, mo, d, 2, 45, offset: early))
                event("B2 second 02:00", at(y, mo, d, 2, 15, offset: late), at(y, mo, d, 2, 45, offset: late))
                event("B3 back through", at(y, mo, d, 2, 45, offset: early), at(y, mo, d, 2, 15, offset: late))
            }
            let climbing = event("Climbing", at(y, mo, d, 18, 0, offset: late), at(y, mo, d, 19, 30, offset: late))
            event("Lecture", monday.addingTimeInterval(9 * 3600), monday.addingTimeInterval(10.5 * 3600))
            // T5: across Saturday's midnight — in Saturday's Month cell only.
            event("Late Saturday", at(y, mo, d - 1, 23, 30, offset: early), at(y, mo, d, 0, 30, offset: early))

            var blocks = [RoutineBlock(title: "Evening review", startMinutes: 20 * 60, duration: 3600)]
            if summerAfter { blocks.append(RoutineBlock(title: "R2 in the gap", startMinutes: 2 * 60 + 30, duration: 1800)) }
            let template = RoutineTemplate(name: "Daily routine", activeWeekdays: [1], blocks: blocks)
            context.insert(template)
            let next = calendar.date(byAdding: .day, value: 1, to: sunday)!
            RoutineEngine.materialize(template: template, into: DateInterval(start: sunday, end: next),
                                      today: sunday, recordsUndo: false, store: store, calendar: calendar)
            try context.save()
            let events = (try context.fetch(FetchDescriptor<Event>(sortBy: [SortDescriptor(\.start)])))

            let departAt = climbing.start.addingTimeInterval(-15 * 60)
            let band = TravelBand(eventID: climbing.id, departAt: departAt, duration: 5 * 60, mode: .walking,
                                  isEstimate: false, originName: "Home", bufferMinutes: 10, reasonShort: nil)
            let fixtures = MockFixtures(
                windows: [TimeWindowFixture(weekdays: Set(1...7), startMinutes: 22 * 60, endMinutes: 7 * 60,
                                            kind: .protected, label: "Sleep")],
                travelInfo: [climbing.id: TravelInfo(band: band, helpSuffix: nil, spoken: "")])
            let now = at(y, mo, d, 18, 30, offset: late)
            let state = CalendarState()
            state.now = now
            let week = (0..<7).map { calendar.date(byAdding: .day, value: $0, to: monday)! }
            let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: sunday))!
            let gridStart = calendar.date(byAdding: .day,
                                          value: -((calendar.component(.weekday, from: monthStart) + 5) % 7),
                                          to: monthStart)!
            let month = (0..<42).map { calendar.date(byAdding: .day, value: $0, to: gridStart)! }

            let gutter = Tokens.Size.timeGutterWidth
            let renders: [(String, ClockChangeCanvas.Mode, [Date], CGSize)] = [
                ("dst-day-\(name)", .day, [sunday], CGSize(width: gutter + 420, height: 24 * Tokens.Size.hourHeightDay + 60)),
                ("dst-week-\(name)", .week, week, CGSize(width: gutter + 7 * 130, height: 24 * Tokens.Size.hourHeightWeek + 60)),
                ("dst-month-\(name)", .month, month, CGSize(width: 980, height: 720)),
            ]
            for (frame, mode, days, size) in renders {
                // Month shows T5's set, so `Climbing` is not behind `+N more`.
                let visible = events.filter { e in
                    days.contains { calendar.isDate(e.start, inSameDayAs: $0) }
                        && (mode != .month || !(e.title.hasPrefix("A ") || e.title.hasPrefix("B")))
                }
                let view = ClockChangeCanvas(mode: mode, days: days, events: visible, fixtures: fixtures,
                                             now: now, store: store, state: state)
                #expect(Slice2Render.render(frame, view, size: size, suffix: "p3bf01") != nil)
            }
        }
    }
}
