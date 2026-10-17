//
//  MoodleCanvasTests.swift
//  KadenceTests
//
//  PHASE3-SLICE3-PLAN.md task 11 — components.md §32.1, §37.1–§37.3, §2.1
//  (amended), §5 (amended), §6; layouts.md §3.2. Dataset `moodle` at M = Mon
//  12 Oct 2026 on an in-memory store; and §43 items 9–14 as offscreen
//  renders (`-p3ct11`). Europe/Vienna.
//

import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import Kadence

private typealias F = MoodleFixture

@MainActor
final class MoodleCanvasRig {
    let container: ModelContainer
    let context: ModelContext
    let now: Date
    let undo = UndoStack()
    var store: EventStore { EventStore(context: context, undo: undo) }

    init(now: Date = MoodleFixture.date("2026-10-12 06:00"), withTravel: Bool = true) throws {
        self.now = now
        container = try ModelContainer(for: Schema(KadenceSchema.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
        MoodleReview.seed(context: context, now: now, m: MoodleFixture.date("2026-10-12 00:00"), zone: MoodleFixture.zone,
                          secrets: InMemorySecretStore(), withTravel: withTravel)
        let sources = (try? context.fetch(FetchDescriptor<Source>())) ?? []
        SourceCatalog.install(SourceDirectory(sources, allowsSlotFallback: false))
    }

    var events: [Event] { (try? context.fetch(FetchDescriptor<Event>(sortBy: [SortDescriptor(\.start)]))) ?? [] }
    var fixtures: MockFixtures { MockFixtures().adding(events: events, now: now, pairingOver: events) }
    var directory: SourceDirectory { SourceDirectory((try? context.fetch(FetchDescriptor<Source>())) ?? [], allowsSlotFallback: false) }

    func event(_ number: String) -> Event? { events.first { $0.externalID?.hasPrefix(number + "@") == true } }

    /// The pills of `day` as `time text` (moments only).
    func pills(_ day: String) -> [String] {
        fixtures.allDayItems(on: MoodleFixture.date("\(day) 12:00")).compactMap { f in f.moment.map { "\($0.time) \($0.text)" } }
    }

    static func days(from monday: String) -> [Date] {
        (0..<7).compactMap { MoodleFixture.calendar.date(byAdding: .day, value: $0, to: MoodleFixture.date("\(monday) 00:00")) }
    }
}

@MainActor
@Suite(.serialized)
struct MoodleCanvasTests {

    @Test("Week 12–18 Oct: which pills on which day, in which order, with which label; no pill for Mon 12's openings")
    func weekOne() throws {
        let rig = try MoodleCanvasRig()
        #expect(rig.pills("2026-10-11") == ["23:59 SWQM · Voting: the 3 best \"Elevator's Speech\" videos"])
        #expect(rig.pills("2026-10-12") == ["23:59 INNO2 · Retake Submission (till 2026-10-12)"])
        #expect(rig.pills("2026-10-13") == ["23:59 INNO3 · Sprint Review Protocol for Sprint 1 (till Tuesday 23:59 in T0 + 2)"])
        #expect(rig.pills("2026-10-14") == ["12:30 RW · Lessons Learned Lektion 4", "12:30 RW · Mitarbeit Lektion 4"])
        for day in ["2026-10-15", "2026-10-16", "2026-10-17", "2026-10-18"] { #expect(rig.pills(day).isEmpty, "\(day)") }
        // Sun 11 is past; Mon 12's 900004 is done.
        let sun = try #require(rig.fixtures.allDayItems(on: F.date("2026-10-11 12:00")).first)
        #expect(sun.moment?.isPast == true)
        let mon = try #require(rig.fixtures.allDayItems(on: F.date("2026-10-12 12:00")).first { $0.moment != nil })
        #expect(mon.moment?.isDone == true && mon.status == .done)
    }

    @Test("Week 19–25 Oct: Tue 20 SWEN3; Thu 22 the two windows, their openings drawn nowhere")
    func weekTwo() throws {
        let rig = try MoodleCanvasRig()
        #expect(rig.pills("2026-10-20") == ["12:00 SWEN3 · Submission - Sprint 3: Queuing"])
        #expect(rig.pills("2026-10-22") == ["16:10–17:47 REQEN · F2", "16:10–17:48 REQEN · F3"])
        let drawn = Set(rig.fixtures.allDay.compactMap(\.eventID))
        for opening in ["900002", "900003", "900009", "900010"] {
            #expect(!drawn.contains(try #require(rig.event(opening)).id), "\(opening)")
        }
    }

    @Test("Week 2–8 Nov: Mon 2 UF; Tue 3 three pills in order (the row at three); Sun 8 SWEN2")
    func weekThree() throws {
        let rig = try MoodleCanvasRig()
        #expect(rig.pills("2026-11-02") == ["14:20 UF · Test Management"])
        #expect(rig.pills("2026-11-03") == ["23:50 RW · Lessons Learned Lektion 5", "23:50 RW · Mitarbeit Lektion 5",
                                            "23:59 INNO3 · Sprint Review Protocol for Sprint 2 (till Tuesday 23:59 in T0 + 4)"])
        #expect(Tokens.Size.allDayMaxRows == 3)
        #expect(rig.pills("2026-11-08") == ["23:59 SWEN2 · Panel Exam (2026-11-08)"])
    }

    @Test("Style: deadline rail and flag.fill; opening and notice without rail; done blend and checkmark; past blend; never conflicted")
    func style() throws {
        let rig = try MoodleCanvasRig()
        func fixture(_ n: String) throws -> AllDayFixture {
            try #require(rig.fixtures.allDay.first { $0.eventID == rig.event(n)?.id })
        }
        let deadline = AllDayItemView.style(for: try fixture("900005"), presentation: [])
        #expect(deadline.railStyle == .solid && deadline.glyph == "flag.fill" && deadline.fill == SourceKey.teal.tint)
        #expect(deadline.label == Tokens.Color.Text.primary && deadline.meta == Tokens.Color.Text.secondary)
        let done = AllDayItemView.style(for: try fixture("900004"), presentation: [])
        #expect(done.glyph == "checkmark.circle.fill" && done.fillBlendWithCanvas == Tokens.Opacity.blockDoneFillBlend)
        #expect(done.label == Tokens.Color.Text.secondary && done.glyphColor == Tokens.Color.Text.secondary)
        let past = AllDayItemView.style(for: try fixture("900001"), presentation: [])
        #expect(past.contentOpacity == Tokens.Opacity.blockPastContent && past.fillBlendWithCanvas == Tokens.Opacity.blockPastFillBlend)
        #expect(past.badge == nil && done.badge == nil && deadline.badge == nil)

        // An unpaired opening and a notice (feedChanged's 900031; feedNotice's 900040).
        let changed = try MoodleCanvasRig()
        let source = try #require(try changed.context.fetch(FetchDescriptor<Source>()).first { $0.id == MoodleReview.sourceID })
        guard case .calendar(let feed) = MoodleProfile.read(F.body(.feedNotice), zone: F.zone),
              case .calendar(let more) = MoodleProfile.read(F.body(.feedChanged), zone: F.zone) else { return }
        let extra = (feed.items + more.items).filter { ["900040", "900031"].contains(F.number($0)) }
        for item in extra {
            let e = Event(title: item.title, start: item.start, end: item.end, origin: .imported, sourceKey: .teal,
                          sourceID: source.id, externalID: item.externalID)
            e.applyMoodle(item)
            changed.context.insert(e)
        }
        try changed.context.save()
        let opening = try #require(changed.fixtures.allDay.first { $0.eventID == changed.event("900031")?.id })
        let notice = try #require(changed.fixtures.allDay.first { $0.eventID == changed.event("900040")?.id })
        for f in [opening, notice] {
            let s = AllDayItemView.style(for: f, presentation: [])
            #expect(s.railStyle == .none && s.rail == nil && s.border != nil)
        }
        #expect(AllDayItemView.style(for: opening, presentation: []).glyph == "lock.open.fill")
        #expect(AllDayItemView.style(for: notice, presentation: []).glyph == "info.circle.fill")
        #expect(opening.moment?.text == "REQEN · Quiz 3" && opening.moment?.time == "09:00")
    }

    @Test("Month Oct / Nov / Dec: chips sorted as the pills; the Month row carries no time")
    func month() throws {
        let rig = try MoodleCanvasRig()
        let tue = rig.fixtures.allDayItems(on: F.date("2026-11-03 12:00")).compactMap(\.moment?.text)
        #expect(tue == ["RW · Lessons Learned Lektion 5", "RW · Mitarbeit Lektion 5",
                        "INNO3 · Sprint Review Protocol for Sprint 2 (till Tuesday 23:59 in T0 + 4)"])
        let dec8 = rig.fixtures.allDayItems(on: F.date("2026-12-08 12:00")).compactMap(\.moment?.text)
        #expect(dec8 == ["📚 Literaturrecherche-Schulung (Adventsedition mit Tee und Keksen!) 🍪🎄✨"])
        // An exam sorts before moments; a manual all-day event after them.
        let day = F.date("2026-11-03 00:00")
        var mixed = rig.fixtures
        mixed.allDay.append(AllDayFixture(title: "A exam", startDay: day, endDay: day, kind: .exam, source: .teal))
        mixed.allDay.append(AllDayFixture(title: "A event", startDay: day, endDay: day, kind: .event, source: .graphite))
        let order = mixed.allDayItems(on: F.date("2026-11-03 12:00")).map(\.title)
        #expect(order.first == "A exam" && order.last == "A event")
        // Month draws the chip through the same view without the time.
        #expect(MomentPresentation.layout(available: 120, glyph: 10, time: -Tokens.Spacing.xs).showsText)
    }

    @Test("§32.1 row by row: a moment never on the grid, never in conflicts, NEXT, REST OF TODAY, the default scroll or the Day header's count; a span is")
    func exclusions() throws {
        let rig = try MoodleCanvasRig(withTravel: false)
        let moment = try #require(rig.event("900005"))
        #expect(moment.isMoment && moment.isDrawnAsAllDay)
        let source = try #require(try rig.context.fetch(FetchDescriptor<Source>()).first { $0.id == MoodleReview.sourceID })
        // A span from feedNotice (900041, Wed 21 Oct 14:00–15:00).
        guard case .calendar(let feed) = MoodleProfile.read(F.body(.feedNotice), zone: F.zone),
              let spanItem = feed.items.first(where: { F.number($0) == "900041" }) else { Issue.record("no span"); return }
        let span = Event(title: spanItem.title, start: spanItem.start, end: spanItem.end, origin: .imported,
                         sourceKey: .teal, sourceID: source.id, externalID: spanItem.externalID)
        span.applyMoodle(spanItem)
        rig.context.insert(span)
        // A routine block over both.
        let routine = Event(title: "Gym", start: F.date("2026-10-13 23:00"), end: F.date("2026-10-14 00:30"), origin: .routine)
        let routine2 = Event(title: "Study", start: F.date("2026-10-21 13:30"), end: F.date("2026-10-21 15:30"), origin: .routine)
        rig.context.insert(routine); rig.context.insert(routine2)
        try rig.context.save()
        #expect(!span.isMoment && !span.isDrawnAsAllDay)

        let conflicts = ConflictEngine.detect(events: rig.events, routineBlocks: [], today: F.date("2026-10-12 00:00"))
        #expect(!conflicts.contains { $0.otherEvent.id == moment.id })
        #expect(conflicts.contains { $0.otherEvent.id == span.id })

        let tueEvening = NextUpProvider.evaluate(events: rig.events, now: F.date("2026-10-13 20:00"), calendar: F.calendar)
        #expect(tueEvening.next?.id == routine.id && !tueEvening.restOfToday.contains { $0.id == moment.id })
        let wed = NextUpProvider.evaluate(events: rig.events, now: F.date("2026-10-21 08:00"), calendar: F.calendar)
        #expect(wed.next?.id == routine2.id && wed.restOfToday.contains { $0.id == span.id })

        // The default scroll: an early moment (05:30) is ignored, an early
        // span is not (07:00 vs 04:00).
        let earlyMoment = Event(title: "Early", start: F.date("2026-10-21 05:30"), end: F.date("2026-10-21 05:30"),
                                origin: .imported, sourceID: source.id, externalID: "early-moment")
        earlyMoment.importKind = .deadline
        let earlySpan = Event(title: "Early span", start: F.date("2026-10-21 05:30"), end: F.date("2026-10-21 06:30"),
                              origin: .imported, sourceID: source.id, externalID: "early-span")
        earlySpan.importKind = .notice
        let wednesday = [F.date("2026-10-21 00:00")]
        #expect(InitialScroll.minute(events: [earlyMoment], days: wednesday, calendar: F.calendar) == 7 * 60)
        #expect(InitialScroll.minute(events: [earlySpan], days: wednesday, calendar: F.calendar) == 4 * 60)
        // The grid's own filter (DayColumnView, Month's timed list) is `isDrawnAsAllDay`.
        #expect(MonthGridView.timedEvents(rig.events, on: F.date("2026-10-13 00:00"), calendar: F.calendar).allSatisfy { !$0.isMoment })
        #expect(MonthGridView.timedEvents(rig.events, on: F.date("2026-10-21 00:00"), calendar: F.calendar).contains { $0.id == span.id })
        // Travel legs: none (no place, §23.2); §27's notifications: none (task 8's tests).
    }

    @Test("Filters: a moment counts as all-day for All-day only / Timed only; Hide done applies")
    func filters() throws {
        let rig = try MoodleCanvasRig(withTravel: false)
        let moment = try #require(rig.event("900005"))
        let done = try #require(rig.event("900004"))
        let state = CalendarState()
        let directory = rig.directory
        #expect(state.isVisible(moment, sources: directory))
        state.showAllDayOnly = true
        #expect(state.isVisible(moment, sources: directory))
        state.showAllDayOnly = false
        state.showTimedOnly = true
        #expect(!state.isVisible(moment, sources: directory))
        state.showTimedOnly = false
        state.hideDone = true
        #expect(!state.isVisible(done, sources: directory) && state.isVisible(moment, sources: directory))
        // Hiding a done deadline does not unpair its opening.
        let visible = rig.events.filter { state.isVisible($0, sources: directory) }
        let fixtures = MockFixtures().adding(events: visible, now: rig.now, pairingOver: rig.events)
        #expect(!fixtures.allDay.contains { $0.eventID == rig.event("900002")?.id })
    }

    // MARK: §43 items 9–14, rendered (`-p3ct11`)

    @Test("§43 items 9–14 render from the real canvas")
    func renders() throws {
        guard F.calendar.timeZone == TimeZone.current else { return }   // the views draw in the Mac's zone
        let rig = try MoodleCanvasRig()
        Slice3Render.keep.append(rig.container)
        let suffix = "p3ct11"
        func week(_ name: String, monday: String, width: CGFloat = 7 * 130, dark: Bool = false) {
            let days = MoodleCanvasRig.days(from: monday)
            let events = rig.events.filter { e in days.contains { F.calendar.isDate(e.start, inSameDayAs: $0) } }
            let state = CalendarState()
            state.now = rig.now
            Slice3Render.keep.append(state)
            let view = ClockChangeCanvas(mode: .week, days: days, events: events, fixtures: rig.fixtures, now: rig.now,
                                         store: rig.store, state: state)
            #expect(Slice3Render.render(name, view, size: CGSize(width: Tokens.Size.timeGutterWidth + width,
                                                                 height: 24 * Tokens.Size.hourHeightWeek + 80),
                                        dark: dark, suffix: suffix, directory: rig.directory) != nil)
        }
        week("week-1218-oct", monday: "2026-10-12")
        week("week-1218-oct-dark", monday: "2026-10-12", dark: true)
        week("week-1925-oct", monday: "2026-10-19")
        week("week-0208-nov", monday: "2026-11-02")
        // Item 12: a 1100pt window — 7 columns of about 110pt.
        week("week-0208-nov-narrow", monday: "2026-11-02", width: 7 * 104)
        for (name, day) in [("day-thu-22-oct", "2026-10-22"), ("day-sun-01-nov", "2026-11-01")] {
            let days = [F.date("\(day) 00:00")]
            let events = rig.events.filter { F.calendar.isDate($0.start, inSameDayAs: days[0]) }
            let state = CalendarState()
            state.now = rig.now
            Slice3Render.keep.append(state)
            let view = ClockChangeCanvas(mode: .day, days: days, events: events, fixtures: rig.fixtures, now: rig.now,
                                         store: rig.store, state: state)
            #expect(Slice3Render.render(name, view, size: CGSize(width: Tokens.Size.timeGutterWidth + 520,
                                                                 height: 24 * Tokens.Size.hourHeightDay + 80),
                                        suffix: suffix, directory: rig.directory) != nil)
        }
        for (name, first) in [("month-oct-2026", "2026-10-01"), ("month-nov-2026", "2026-11-01"), ("month-dec-2026", "2026-12-01")] {
            let anchor = F.date("\(first) 12:00")
            let start = F.calendar.date(byAdding: .day, value: -((F.calendar.component(.weekday, from: anchor) + 5) % 7),
                                        to: F.calendar.startOfDay(for: anchor)) ?? anchor
            let days = (0..<42).compactMap { F.calendar.date(byAdding: .day, value: $0, to: start) }
            let state = CalendarState()
            state.now = rig.now
            Slice3Render.keep.append(state)
            let view = MonthGridView(days: days, events: rig.events, fixtures: rig.fixtures, now: rig.now, anchorMonth: anchor)
                .environment(state)
                .background(Tokens.Color.Surface.canvas)
            #expect(Slice3Render.render(name, view, size: CGSize(width: 1100, height: 760), suffix: suffix,
                                        directory: rig.directory) != nil)
        }
    }
}
