//
//  MenuBarDueTests.swift
//  KadenceTests
//
//  PHASE3-SLICE3-PLAN.md task 13 — components.md §39; layouts.md §18;
//  interactions.md §16.6. Dataset `moodleOnly` at M = Mon 12 Oct 2026; the
//  status item's text from the real `StatusItemLabel`, the popover's from the
//  real `MenuBarPopoverView`; §43 item 18 as offscreen renders (`-p3ct13`).
//

import Testing
import Foundation
import SwiftUI
import SwiftData
@testable import Kadence

private typealias F = MoodleFixture

@MainActor
@Suite(.serialized)
struct MenuBarDueTests {

    private func status(_ rig: MoodleCanvasRig, at text: String, width: CGFloat) -> String? {
        let now = F.date(text)
        let result = NextUpProvider.evaluate(events: rig.events, now: now, calendar: F.calendar)
        let due = MenuBarFormatting.dueSelection(events: rig.events, now: now, hasTimedNext: result.next != nil,
                                                 calendar: F.calendar).next
        return StatusItemLabel.text(for: result, now: now, available: width, due: due)
    }

    @Test("Status item at Tue 13 Oct 20:00 at 180pt and 110pt; 23:59 → Nothing left today; 900005 done at 20:00 → Nothing left today")
    func statusItem() throws {
        let rig = try MoodleCanvasRig(withTravel: false)
        let wide = try #require(status(rig, at: "2026-10-13 20:00", width: 180))
        #expect(wide.hasPrefix("Due 23:59 · INNO3 · Sprint") && wide.hasSuffix("…"))
        #expect(StatusItemLabel.width(of: wide) <= 180)
        let narrow = try #require(status(rig, at: "2026-10-13 20:00", width: 110))
        #expect(narrow.hasPrefix("Due 23:59") && StatusItemLabel.width(of: narrow) <= 110)
        #expect(status(rig, at: "2026-10-13 20:00", width: 80) == "Due 23:59")
        #expect(status(rig, at: "2026-10-13 23:59", width: 180) == nil)
        rig.store.toggleDone(try #require(rig.event("900005")))
        #expect(status(rig, at: "2026-10-13 20:00", width: 180) == nil)
        // Never a late state for a deadline, never `ago`.
        #expect(!(wide.contains("ago")))
    }

    @Test("Popover at Tue 3 Nov 20:00: NEXT 900016 with its meta, DUE TODAY 900015 and 900017; Done replaces NEXT with 900015; +N more beyond 3")
    func popover() throws {
        let rig = try MoodleCanvasRig(withTravel: false)
        let now = F.date("2026-11-03 20:00")
        var due = MenuBarFormatting.dueSelection(events: rig.events, now: now, hasTimedNext: false, calendar: F.calendar)
        let next = try #require(due.next)
        #expect(next.title == "Lessons Learned Lektion 5")
        #expect(MenuBarFormatting.dueMeta(next, sourceName: "Moodle") == "Closes 23:50 · RW · Moodle")
        #expect(due.dueToday.map(MenuBarFormatting.dueText)
                == ["RW · Mitarbeit Lektion 5", "INNO3 · Sprint Review Protocol for Sprint 2 (till Tuesday 23:59 in T0 + 4)"])
        rig.store.toggleDone(try #require(rig.event("900016")))
        due = MenuBarFormatting.dueSelection(events: rig.events, now: now, hasTimedNext: false, calendar: F.calendar)
        #expect(due.next?.title == "Mitarbeit Lektion 5" && due.dueToday.count == 1)
        // More than three: `+N more`.
        let source = try #require(try rig.context.fetch(FetchDescriptor<Source>()).first { $0.id == MoodleReview.sourceID })
        for n in 1...3 {
            let t = F.date("2026-11-03 22:0\(n)")
            let e = Event(title: "Extra \(n)", start: t, end: t, origin: .imported, sourceKey: .teal, sourceID: source.id,
                          externalID: "extra-\(n)")
            e.importKind = .deadline; e.momentWording = .due
            rig.context.insert(e)
        }
        due = MenuBarFormatting.dueSelection(events: rig.events, now: now, hasTimedNext: false, calendar: F.calendar)
        #expect(due.dueToday.count == 4 && Tokens.Size.popoverMaxDueRows == 3)
        // Registration and category forms of the meta.
        let libEvent = try #require(rig.event("900028"))
        let lib = try #require(MomentItem(libEvent))
        #expect(MenuBarFormatting.dueMeta(lib, sourceName: "Moodle") == "Registration ends 23:55 · Bibliothek · Moodle")
    }

    @Test("With a timed item left, NEXT is the timed item and DUE TODAY lists the deadlines")
    func timedFirst() throws {
        let rig = try MoodleCanvasRig(withTravel: false)
        let call = Event(title: "Late call", start: F.date("2026-11-03 21:00"), end: F.date("2026-11-03 21:30"))
        rig.context.insert(call)
        let now = F.date("2026-11-03 20:00")
        let result = NextUpProvider.evaluate(events: rig.events, now: now, calendar: F.calendar)
        #expect(result.next?.id == call.id)
        let due = MenuBarFormatting.dueSelection(events: rig.events, now: now, hasTimedNext: true, calendar: F.calendar)
        #expect(due.next == nil && due.dueToday.count == 3)
        #expect(StatusItemLabel.text(for: result, now: now, available: 180, due: nil) == "21:00 · Late call")
    }

    @Test("Accessibility labels, exact")
    func accessibility() throws {
        let rig = try MoodleCanvasRig(withTravel: false)
        let event = try #require(rig.event("900005"))
        let item = try #require(MomentItem(event))
        #expect(MenuBarFormatting.dueAccessibilityLabel(item)
                == "Due at 23:59, Sprint Review Protocol for Sprint 1 (till Tuesday 23:59 in T0 + 2), INNO3")
        #expect(MenuBarFormatting.dueRowAccessibilityLabel(item)
                == "23:59, INNO3, Sprint Review Protocol for Sprint 1 (till Tuesday 23:59 in T0 + 2), deadline")
    }

    // MARK: §43 item 18, rendered (`-p3ct13`)

    @Test("§43 item 18 renders: status item at 180pt and degraded; the popover at Tue 13 Oct and Tue 3 Nov 20:00")
    func renders() throws {
        guard F.calendar.timeZone == TimeZone.current else { return }
        let rig = try MoodleCanvasRig(withTravel: false)
        Slice3Render.keep.append(rig.container)
        let suffix = "p3ct13"
        for width in [CGFloat(180), 110, 80] {
            let now = F.date("2026-10-13 20:00")
            let result = NextUpProvider.evaluate(events: rig.events, now: now, calendar: F.calendar)
            let due = MenuBarFormatting.dueSelection(events: rig.events, now: now, hasTimedNext: false, calendar: F.calendar).next
            let view = StatusItemLabel(result: result, now: now, available: width, due: due)
                .padding(6).background(Tokens.Color.Surface.popover)
            #expect(Slice3Render.render("status-item-due-\(Int(width))", view, size: CGSize(width: width + 12, height: 34),
                                        suffix: suffix, directory: rig.directory) != nil)
        }
        for (name, clock) in [("popover-due-1013-2000", "2026-10-13 20:00"), ("popover-due-1103-2000", "2026-11-03 20:00")] {
            let view = MenuBarPopoverView(initialNow: F.date(clock))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxHeight: .infinity, alignment: .top)
                .background(Tokens.Color.Surface.popover)
                .modelContainer(rig.container)
                .environment(rig.undo)
                .environment(CalendarState())
            #expect(Slice3Render.render(name, view, size: CGSize(width: Tokens.Size.popoverWidth, height: 360),
                                        suffix: suffix, directory: rig.directory) != nil)
        }
    }
}
