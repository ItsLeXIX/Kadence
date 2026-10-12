//
//  ImportedCanvasTests.swift
//  KadenceTests
//
//  PHASE3-PLAN.md task 15: imported events on the canvas (components.md
//  §2.1, §5.1, §6 `cancelled` and the `done` amendment, §18.2, §20.4, §20.6).
//

import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import Kadence

@MainActor
private func imported(_ title: String = "SWQM-ILV", kind: ImportKind = .lecture, allDay: Bool = false,
                      online: Bool = false, location: String? = "HS_A3.15") -> Event {
    let start = TestClock.date("2026-10-12 09:00")
    let event = Event(title: title, start: start, end: start + 5400, isAllDay: allDay, origin: .imported,
                      sourceKey: .blue, location: location.map { Place(name: $0) }, sourceID: "timetable", externalID: "x")
    event.importKind = kind
    event.isOnline = online
    return event
}

@MainActor
struct ImportedCanvasTests {

    private func style(_ kind: BlockKind, status: BlockStatus = .scheduled, presentation: Presentation = [],
                       glyph: String? = nil) -> BlockStyle {
        resolveBlockStyle(kind: kind, flexibility: .fixed, status: status, presentation: presentation, source: .blue,
                          renderedHeight: 60, glyphOverride: glyph)
    }

    @Test("Glyphs: an imported exam → graduationcap.fill, a lecture → building.columns (both .fixedTimed)")
    func glyphs() {
        let exam = imported("REQEN-EXAM", kind: .exam)
        let lecture = imported()
        #expect(exam.blockKind == .fixedTimed && exam.glyphOverride == "graduationcap.fill")
        #expect(lecture.blockKind == .fixedTimed && lecture.glyphOverride == "building.columns")
        #expect(style(.fixedTimed, glyph: exam.glyphOverride).glyph == "graduationcap.fill")
    }

    @Test(".eventAllDay: solid fill, the timed glyph, no rail, no chip — both origins and an imported exam")
    func eventAllDay() {
        let manual = Event(title: "Studieninformationstag", start: TestClock.date("2026-10-14 00:00"),
                           end: TestClock.date("2026-10-15 00:00"), isAllDay: true, origin: .manual, sourceKey: .graphite)
        #expect(manual.blockKind == .eventAllDay && manual.glyphOverride == "calendar")
        let lecture = imported(allDay: true)
        let exam = imported(kind: .exam, allDay: true)
        #expect(lecture.blockKind == .eventAllDay && exam.glyphOverride == "graduationcap.fill")
        for (event, glyph) in [(manual, "calendar"), (lecture, "building.columns"), (exam, "graduationcap.fill")] {
            let s = resolveBlockStyle(kind: event.blockKind, flexibility: .fixed, status: .scheduled, presentation: [],
                                      source: event.sourceKey, renderedHeight: Tokens.Size.allDayRowHeight,
                                      glyphOverride: event.glyphOverride)
            #expect(s.fill == event.sourceKey.solid && s.rail == nil && s.railStyle == .none && s.border == nil)
            #expect(s.glyph == glyph && s.label == Tokens.Color.Text.onSolid)
            #expect(s.cornerRadius == Tokens.Radius.allDayPill)
            let pill = AllDayFixture(event: event, now: TestClock.now)
            #expect(pill.blockKind == .eventAllDay && pill.countdownLabel(now: TestClock.now) == nil)  // no chip
        }
    }

    @Test("The .full meta line: `Online · University timetable` / `HS_A3.15 · …` (§3.4, 2026-10-10); hover Kind Exam / Lecture")
    func metaAndHover() {
        let online = GridBlockModel(event: imported("INNO3-EL", online: true, location: "WEBINAR01"), now: TestClock.now, sources: .testTimetable)
        let room = GridBlockModel(event: imported(), now: TestClock.now, sources: .testTimetable)
        #expect(online.metaLine == "Online · University timetable")
        #expect(room.metaLine == "HS_A3.15 · University timetable")
        #expect(room.hoverHelp == "SWQM-ILV · 09:00–10:30 · University timetable · Lecture")
        let exam = GridBlockModel(event: imported("REQEN-EXAM", kind: .exam), now: TestClock.now, sources: .testTimetable)
        #expect(exam.hoverHelp.hasSuffix("· Exam"))
        #expect(exam.accessibilityLabel(presentation: []).contains("exam"))
    }

    @Test("cancelled: blend, dashed border, xmark.circle, text.primary label and meta; never conflicted; past takes past only")
    func cancelled() {
        let event = imported("Statistik")
        event.isCancelled = true
        #expect(event.blockStatus(now: TestClock.now) == .cancelled)
        let s = style(.fixedTimed, status: .cancelled, presentation: [.conflicted], glyph: "building.columns")
        #expect(s.fillBlendWithCanvas == Tokens.Opacity.blockSkippedFillBlend)
        #expect(s.borderDash == [3, 3] && s.border == Tokens.Color.Separator.strong && s.borderWidth == Tokens.Size.borderRegular)
        #expect(s.glyph == "xmark.circle" && s.glyphColor == Tokens.Color.Text.primary)
        #expect(s.label == Tokens.Color.Text.primary && s.meta == Tokens.Color.Text.primary)
        #expect(s.badge == nil && s.trailingBar == nil)
        let model = GridBlockModel(event: event, now: TestClock.now, sources: .testTimetable)
        #expect(model.metaLine == "Cancelled · University timetable")
        #expect(model.accessibilityLabel(presentation: []).hasSuffix("cancelled"))
        let past = style(.fixedTimed, status: .cancelled, presentation: [.past], glyph: "building.columns")
        #expect(past.fillBlendWithCanvas == Tokens.Opacity.blockPastFillBlend && past.glyph == "building.columns")
    }

    @Test("done: text.primary on the three solid kinds, text.secondary on the others")
    func doneLabel() {
        for kind in [BlockKind.fixedTimed, .examAllDay, .eventAllDay] {
            let s = style(kind, status: .done)
            #expect(s.label == Tokens.Color.Text.primary && s.glyphColor == Tokens.Color.Text.primary, "\(kind)")
        }
        for kind in [BlockKind.routineTimed, .plannedTimed, .deadlineAllDay] {
            #expect(style(kind, status: .done).label == Tokens.Color.Text.secondary, "\(kind)")
        }
    }

    @Test("Hover shows no handles on an imported block: it is not movable")
    func noHandles() {
        #expect(!imported().isMovable)
        #expect(!GridBlockModel(event: imported(), now: TestClock.now, sources: .testTimetable).isMovable)
    }

    @Test("G-055 regression: a ⌘⌥N all-day event appears in the all-day row")
    func manualAllDayDraws() throws {
        let container = try ModelContainer(for: Schema(KadenceSchema.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let store = EventStore(context: context, undo: UndoStack())
        var draft = EventDraft(start: TestClock.date("2026-10-14 00:00"), end: TestClock.date("2026-10-15 00:00"))
        draft.title = "Studieninformationstag"
        draft.isAllDay = true
        let created = try #require(store.commit(draft))
        #expect(created.isAllDay)
        let fixtures = MockFixtures().adding(events: try context.fetch(FetchDescriptor<Event>()), now: TestClock.now)
        let items = fixtures.allDayItems(on: TestClock.date("2026-10-14 12:00"))
        #expect(items.map(\.title) == ["Studieninformationstag"] && items.first?.blockKind == .eventAllDay)
        #expect(fixtures.allDayItems(on: TestClock.date("2026-10-15 12:00")).isEmpty)  // DTEND is exclusive
        #expect(AllDayRowView.isVisible(days: [TestClock.date("2026-10-14 00:00")], fixtures: fixtures))
    }

    @Test("The all-day row sorts by start day, then exam, deadline, event, then title")
    func allDaySort() {
        let day = TestClock.date("2026-10-14 00:00")
        let earlier = TestClock.date("2026-10-13 00:00")
        var fixtures = MockFixtures()
        fixtures.allDay = [
            AllDayFixture(title: "B event", startDay: day, endDay: day, kind: .event, source: .graphite),
            AllDayFixture(title: "A event", startDay: day, endDay: day, kind: .event, source: .graphite),
            AllDayFixture(title: "Deadline", startDay: day, endDay: day, kind: .deadline, source: .orange),
            AllDayFixture(title: "Exam", startDay: day, endDay: day, kind: .exam, source: .teal),
            AllDayFixture(title: "Z multi-day", startDay: earlier, endDay: day, kind: .event, source: .graphite),
        ]
        #expect(fixtures.allDayItems(on: day).map(\.title) == ["Z multi-day", "Exam", "Deadline", "A event", "B event"])
    }

    @Test("Cancelled events are excluded from conflicts, next-up and firstEventStart")
    func cancelledExcluded() {
        let cancelled = imported("Statistik")
        cancelled.isCancelled = true
        cancelled.start = TestClock.date("2026-10-08 11:00"); cancelled.end = TestClock.date("2026-10-08 12:00")
        #expect(NextUpProvider.evaluate(events: [cancelled], now: TestClock.now).next == nil)
        #expect(InitialScroll.minute(events: [cancelled], days: [TestClock.now]) == 7 * 60)
        let routine = Event(title: "Gym", start: cancelled.start, end: cancelled.end, origin: .routine)
        #expect(ConflictEngine.detect(events: [routine, cancelled], routineBlocks: []).isEmpty)
    }

    @Test("The merged SWRM-ILV is one block after the review Import")
    func mergedIsOneBlock() async throws {
        let f = try SyncFixture()
        try await f.run(MockHarness(.reportOK, feed: MockHarness.reportReview()), kind: .import)
        let swrm = f.events.filter { $0.title == "SWRM-ILV" }
        #expect(swrm.count == 1 && swrm.first?.lecturers == ["L05", "L06"])
    }
}
