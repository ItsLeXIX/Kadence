//
//  DeadlineNotificationTests.swift
//  KadenceTests
//
//  PHASE3-SLICE3-PLAN.md task 8 — components.md §40, §41 (reminders), §27
//  (amended), §43.2's tables, §43.3 C3/C4. The planner on the fixture's
//  deadlines (dataset `moodleOnly`'s shape: Sleep 22:00–07:00, 900004 done,
//  §42.3's rule), and the scheduler with the recording centre on an
//  in-memory store. Europe/Vienna; the clock injected.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

private typealias F = MoodleFixture

private let sleep = QuietWindow(weekdays: Set(1...7), startMinutes: 22 * 60, endMinutes: 7 * 60, label: "Sleep")

/// The fixture's items as deadline snapshots, ids derived from the UID.
private func snapshots(_ feedCase: MoodleFeedCase = .feedOK, done: Set<String> = ["900004"]) -> [DeadlineSnapshot] {
    (F.feed(feedCase)?.items ?? []).map { item in
        let n = F.number(item)
        return DeadlineSnapshot(id: uuid(n), title: item.title, wording: item.wording, kind: item.kind, due: item.start,
                                end: item.end, isAllDay: item.isAllDay, courseCode: item.courseCode,
                                courseCategory: item.courseCategory, sourceName: "Moodle", isDone: done.contains(n))
    }
}

/// `900005` → a stable UUID, so identifiers read `due.{900005}.ahead`.
private func uuid(_ number: String) -> UUID {
    UUID(uuidString: "00000000-0000-0000-0000-000000\(number)") ?? UUID()
}

/// `due.{900005}.ahead` → the real identifier.
private func id(_ text: String) -> String {
    var out = text
    for n in 900001...900099 { out = out.replacingOccurrences(of: "{\(n)}", with: uuid(String(n)).uuidString) }
    return out
}

private func plan(at text: String, rule: DeadlineRule = DeadlineRule(), deadlines: [DeadlineSnapshot] = snapshots(),
                  records: [String: Date] = [:], catchUp: Bool = false) -> [PlannedNotification] {
    let now = F.date(text)
    return DeadlinePlanner.plan(DeadlinePlanner.Input(deadlines: deadlines, rule: rule, windows: [sleep], records: records,
                                                      now: now, isCatchUp: catchUp, calendar: F.calendar))
        .filter { $0.atOnce || $0.fireAt <= now.addingTimeInterval(NotificationPlanner.window) }
}

/// `Mon 12 Oct 18:00` (local).
private func local(_ d: Date) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = F.zone; f.dateFormat = "EEE d MMM HH:mm"
    return f.string(from: d)
}

private struct Row: Equatable, CustomStringConvertible {
    var identifier: String, fires: String, title: String, body: String, category: NotificationCategory
    var description: String { "\(identifier) \(fires) \(title) / \(body) [\(category.rawValue)]" }
}

private func rows(_ planned: [PlannedNotification]) -> [Row] {
    planned.map { Row(identifier: $0.identifier, fires: local($0.fireAt), title: $0.text.title, body: $0.text.body,
                      category: $0.category) }
}

@MainActor
struct DeadlineNotificationTests {

    @Test("§43.2 at Mon 12 Oct 2026 06:00 — 3 requests, exactly")
    func mondayTwelve() {
        let sprint1 = "Sprint Review Protocol for Sprint 1 (till Tuesday 23:59 in T0 + 2) is due Tue 13 Oct 23:59"
        #expect(rows(plan(at: "2026-10-12 06:00")) == [
            Row(identifier: id("due.{900005}.ahead"), fires: "Mon 12 Oct 18:00", title: sprint1, body: "INNO3 · Moodle",
                category: .deadline),
            Row(identifier: "due.day.20261014.20261013T1600Z", fires: "Tue 13 Oct 18:00",
                title: "2 deadlines on Wed 14 Oct at 12:30",
                body: "12:30 Lessons Learned Lektion 4 (RW) · 12:30 Mitarbeit Lektion 4 (RW)", category: .deadlines),
            Row(identifier: id("due.{900005}.close"), fires: "Tue 13 Oct 21:59", title: sprint1, body: "INNO3 · Moodle",
                category: .deadline),
        ])
        // 900004 not done: its close is added.
        let undone = rows(plan(at: "2026-10-12 06:00", deadlines: snapshots(done: [])))
        #expect(undone.contains(Row(identifier: id("due.{900004}.close"), fires: "Mon 12 Oct 21:59",
                                    title: "Retake Submission (till 2026-10-12) is due Mon 12 Oct 23:59",
                                    body: "INNO2 · Moodle", category: .deadline)))
        #expect(plan(at: "2026-10-12 06:00").allSatisfy { $0.interruption == .active && $0.playsSound && !$0.atOnce })
    }

    @Test("§43.2 at Mon 2 Nov 2026 06:00 — 4 requests, exactly")
    func mondayTwo() {
        #expect(rows(plan(at: "2026-11-02 06:00")) == [
            Row(identifier: id("due.{900014}.close"), fires: "Mon 2 Nov 12:20", title: "Test Management closes Mon 2 Nov 14:20",
                body: "UF · Moodle", category: .deadline),
            Row(identifier: "due.day.20261103.20261102T1700Z", fires: "Mon 2 Nov 18:00", title: "3 deadlines on Tue 3 Nov",
                body: "23:50 Lessons Learned Lektion 5 (RW) · 23:50 Mitarbeit Lektion 5 (RW) · 23:59 Sprint Review Protocol for Sprint 2 (till Tuesday 23:59 in T0 + 4) (INNO3)",
                category: .deadlines),
            Row(identifier: "due.day.20261103.20261103T2050Z", fires: "Tue 3 Nov 21:50",
                title: "2 deadlines on Tue 3 Nov at 23:50",
                body: "23:50 Lessons Learned Lektion 5 (RW) · 23:50 Mitarbeit Lektion 5 (RW)", category: .deadlines),
            Row(identifier: id("due.{900017}.close"), fires: "Tue 3 Nov 21:59",
                title: "Sprint Review Protocol for Sprint 2 (till Tuesday 23:59 in T0 + 4) is due Tue 3 Nov 23:59",
                body: "INNO3 · Moodle", category: .deadline),
        ])
    }

    @Test("§43.2 at Sat 31 Oct 2026 06:00 (CET) — 3 requests, exactly")
    func saturday() {
        let manila = "VERBINDLICHE Anmeldung für die Studienreise nach Manila | BINDING registration for study trip to Manila closes Sun 1 Nov 23:59"
        let fk = "FK CS&AM - Study Trips & International Initiatives · Moodle"
        #expect(rows(plan(at: "2026-10-31 06:00")) == [
            Row(identifier: id("due.{900013}.ahead"), fires: "Sat 31 Oct 18:00", title: manila, body: fk, category: .deadline),
            Row(identifier: id("due.{900014}.ahead"), fires: "Sun 1 Nov 18:00", title: "Test Management closes Mon 2 Nov 14:20",
                body: "UF · Moodle", category: .deadline),
            Row(identifier: id("due.{900013}.close"), fires: "Sun 1 Nov 21:59", title: manila, body: fk, category: .deadline),
        ])
    }

    @Test("Rule variants: final 1 hour → 21:59; early Off; 3 days before at 08:00; the rule off; 900028's copy")
    func variants() {
        let hour = plan(at: "2026-10-12 06:00", rule: DeadlineRule(leadMinutes: 60))
        #expect(hour.first { $0.identifier == id("due.{900005}.close") }.map { local($0.fireAt) } == "Tue 13 Oct 21:59")
        let off = plan(at: "2026-10-12 06:00", rule: DeadlineRule(aheadDays: 0))
        #expect(!off.contains { $0.identifier.hasSuffix(".ahead") || $0.identifier.hasPrefix("due.day.") && local($0.fireAt).hasSuffix("18:00") })
        #expect(off.map(\.identifier) == [id("due.{900005}.close")])
        let three = plan(at: "2026-10-16 06:00", rule: DeadlineRule(aheadDays: 3, aheadMinuteOfDay: 8 * 60))
        #expect(three.first { $0.identifier == id("due.{900008}.ahead") }.map { local($0.fireAt) } == "Sat 17 Oct 08:00")
        #expect(plan(at: "2026-10-12 06:00", rule: DeadlineRule(isEnabled: false)).isEmpty)
        let dec = plan(at: "2026-12-07 06:00")
        let lib = dec.first { $0.identifier == id("due.{900028}.close") }
        #expect(lib?.text.title == "Registration for 📚 Literaturrecherche-Schulung (Adventsedition mit Tee und Keksen!) 🍪🎄✨ ends Tue 8 Dec 23:55")
        #expect(lib?.text.body == "Bibliothek · Moodle")
    }

    @Test("Catch-up: Tue 13 Oct 21:30 delivers the 14 Oct group at once and plans 900005's close; 22:30 nothing for 900005; Wed 00:30 nothing")
    func catchUp() {
        let p = plan(at: "2026-10-13 21:30", catchUp: true)
        let group = p.first { $0.identifier == "due.day.20261014.20261013T1600Z" }
        #expect(group?.atOnce == true && group?.fireAt == F.date("2026-10-13 21:30"))
        #expect(p.first { $0.identifier == id("due.{900005}.close") }.map { local($0.fireAt) } == "Tue 13 Oct 21:59")
        #expect(!p.contains { $0.identifier == id("due.{900005}.ahead") })
        // An ordinary pass sends nothing late.
        #expect(!plan(at: "2026-10-13 21:30").contains { $0.atOnce })

        let late = plan(at: "2026-10-13 22:30", catchUp: true)
        #expect(!late.contains { $0.subjectID == uuid("900005").uuidString })
        // The group missed at 18:00 is held to Sleep's end, before its due moment.
        #expect(late.first { $0.identifier == "due.day.20261014.20261013T1600Z" }.map { local($0.fireAt) } == "Wed 14 Oct 07:00")
        #expect(!plan(at: "2026-10-14 00:30", catchUp: true).contains { $0.subjectID == uuid("900005").uuidString })
        // A recorded reminder is never caught up.
        let recorded = plan(at: "2026-10-13 21:30", records: ["due.day.20261014.20261013T1600Z": F.date("2026-10-13 18:00")],
                            catchUp: true)
        #expect(!recorded.contains { $0.atOnce })
        // Never two catch-ups for one deadline: both of 900008's missed → one.
        let both = plan(at: "2026-10-20 11:00", catchUp: true)
        #expect(both.filter { $0.subjectID == uuid("900008").uuidString }.count == 1)
    }

    @Test("C3 and C4 (§43.3), and §40.3's three examples")
    func clockChanges() {
        let c3 = DeadlineSnapshot(id: UUID(), title: "C3", wording: .due, due: F.date("2026-10-26 23:59"),
                                  courseCode: nil, courseCategory: nil, sourceName: "Moodle")
        #expect(DeadlinePlanner.aheadTime(due: c3.due, rule: DeadlineRule(), calendar: F.calendar)
                == ISO8601DateFormatter().date(from: "2026-10-25T17:00:00Z"))
        // C4: due Sun 25 Oct 01:30 CEST (= Sat 23:30Z), final 2 hours → Sat
        // 23:30 CEST, inside Sleep; held to 07:00 CET Sun, after the due
        // moment → S.start − 1 min = Sat 21:59 CEST.
        let due = ISO8601DateFormatter().date(from: "2026-10-24T23:30:00Z")!
        let close = DeadlinePlanner.closeTime(due: due, rule: DeadlineRule())!
        #expect(close == ISO8601DateFormatter().date(from: "2026-10-24T21:30:00Z"))
        #expect(DeadlinePlanner.quiet(close, due: due, windows: [sleep], calendar: F.calendar)
                == ISO8601DateFormatter().date(from: "2026-10-24T19:59:00Z"))
        // Spring forward: due Mon 30 Mar 2026 23:59 CEST → ahead Sun 29 Mar 18:00 CEST.
        #expect(DeadlinePlanner.aheadTime(due: F.date("2026-03-30 23:59"), rule: DeadlineRule(), calendar: F.calendar)
                == ISO8601DateFormatter().date(from: "2026-03-29T16:00:00Z"))
        // §40.3: Tue 13 Oct 23:59 → ahead Mon 18:00, close 21:59.
        let tue = F.date("2026-10-13 23:59")
        #expect(DeadlinePlanner.aheadTime(due: tue, rule: DeadlineRule(), calendar: F.calendar) == F.date("2026-10-12 18:00"))
        #expect(DeadlinePlanner.quiet(DeadlinePlanner.closeTime(due: tue, rule: DeadlineRule())!, due: tue, windows: [sleep],
                                      calendar: F.calendar) == F.date("2026-10-13 21:59"))
        // Close at 1 hour → 22:59 inside Sleep, S.end after due → 21:59.
        #expect(DeadlinePlanner.quiet(F.date("2026-10-13 22:59"), due: tue, windows: [sleep], calendar: F.calendar)
                == F.date("2026-10-13 21:59"))
        // Due Thu 08:30, close 2 hours → 06:30 inside Sleep, S.end 07:00 before due → 07:00.
        #expect(DeadlinePlanner.quiet(F.date("2026-10-15 06:30"), due: F.date("2026-10-15 08:30"), windows: [sleep],
                                      calendar: F.calendar) == F.date("2026-10-15 07:00"))
        // Collapse: ahead Tue 20:00, final Tue 20:30 (30 min apart) → only
        // the final one; 90 min apart → both.
        let near = DeadlineSnapshot(id: uuid("900077"), title: "Near", wording: .due, due: F.date("2026-10-14 08:00"),
                                    courseCode: nil, courseCategory: nil, sourceName: "Moodle")
        let collapsed = plan(at: "2026-10-13 12:00",
                             rule: DeadlineRule(aheadDays: 1, aheadMinuteOfDay: 20 * 60, leadMinutes: 11 * 60 + 30),
                             deadlines: [near])
        #expect(collapsed.map(\.identifier) == [id("due.{900077}.close")])
        let apart = plan(at: "2026-10-13 12:00",
                         rule: DeadlineRule(aheadDays: 1, aheadMinuteOfDay: 20 * 60, leadMinutes: 10 * 60 + 30),
                         deadlines: [near])
        #expect(apart.map(\.identifier) == [id("due.{900077}.ahead"), id("due.{900077}.close")])
    }

    @Test("No Kadence-written title or body contains late, missed, overdue, a count of undone items, !, today, tomorrow or `in ` + a number")
    func forbiddenWords() {
        var all: [PlannedNotification] = []
        for day in stride(from: 0, through: 70, by: 1) {
            let t = F.calendar.date(byAdding: .day, value: day, to: F.date("2026-10-08 06:00"))!
            all += DeadlinePlanner.plan(DeadlinePlanner.Input(deadlines: snapshots(), rule: DeadlineRule(), windows: [sleep],
                                                              records: [:], now: t, isCatchUp: day % 3 == 0,
                                                              calendar: F.calendar))
        }
        #expect(!all.isEmpty)
        let titles = Set(snapshots().map(\.title))
        for n in all {
            var text = n.text.title + " " + n.text.body
            for title in titles { text = text.replacingOccurrences(of: title, with: "{title}") }
            for word in ["late", "missed", "overdue", "!", "today", "tomorrow", "undone", "not done"] {
                #expect(!text.lowercased().contains(word), "\(text)")
            }
            #expect(text.firstMatch(of: /in [0-9]/) == nil, "\(text)")
        }
        for state in [SourceState.unauthorized, .forbidden, .feedNotFound, .notACalendar] {
            let t = NotificationCopy.n8Feed(name: "Moodle", host: "moodle.technikum-wien.at", state: state)
            #expect(t != nil && !(t!.title + t!.body).contains("!"))
        }
    }

    // MARK: The scheduler

    @Test("Group transitions: shrinking to one → the single; marking a member done replaces the group's body; done, deleted, notice → removed")
    func scheduler() async throws {
        let rig = try DeadlineRig(now: F.date("2026-11-02 06:00"))
        await rig.scheduler.pass()
        var pending = await rig.centre.pendingByID
        #expect(pending["due.day.20261103.20261102T1700Z"]?.title == "3 deadlines on Tue 3 Nov")
        #expect(pending["due.day.20261103.20261103T2050Z"] != nil)
        // Mark 900016 done: the 18:00 group has two members (a new body); the
        // 21:50 group shrinks to one → 900015's single.
        let store = EventStore(context: rig.context, undo: rig.undo)
        store.toggleDone(try #require(rig.event("900016")))
        await rig.scheduler.pass()
        pending = await rig.centre.pendingByID
        #expect(pending["due.day.20261103.20261102T1700Z"]?.title == "2 deadlines on Tue 3 Nov")
        #expect(pending["due.day.20261103.20261102T1700Z"]?.body
                == "23:50 Mitarbeit Lektion 5 (RW) · 23:59 Sprint Review Protocol for Sprint 2 (till Tuesday 23:59 in T0 + 4) (INNO3)")
        #expect(pending["due.day.20261103.20261103T2050Z"] == nil)
        let e15 = try #require(rig.event("900015"))
        #expect(pending["due.\(e15.id.uuidString).close"]?.title == "Mitarbeit Lektion 5 closes Tue 3 Nov 23:50")
        // Growing back: Not done → the group returns, the single goes.
        store.toggleDone(try #require(rig.event("900016")))
        await rig.scheduler.pass()
        pending = await rig.centre.pendingByID
        #expect(pending["due.day.20261103.20261103T2050Z"] != nil && pending["due.\(e15.id.uuidString).close"] == nil)
        // Deleted and turned into a notice: removed.
        let e14 = try #require(rig.event("900014"))
        let id14 = e14.id
        e14.importKind = .notice; e14.momentWording = nil
        try rig.context.save()
        await rig.scheduler.pass()
        #expect(await rig.centre.pendingByID["due.\(id14.uuidString).close"] == nil)
        // Moodle items never get §27's start. / leave. requests.
        #expect(await !rig.centre.pendingByID.keys.contains { $0.hasPrefix("start.") || $0.hasPrefix("leave.") })
    }

    @Test("Delivered reminders of a passed or done deadline are cleared; a group when every member is")
    func delivered() async throws {
        let rig = try DeadlineRig(now: F.date("2026-10-12 06:00"))
        await rig.scheduler.pass()
        let e5 = try #require(rig.event("900005"))
        let single = "due.\(e5.id.uuidString).ahead"
        // The system delivers both (they leave pending).
        await rig.centre.deliver(single)
        await rig.centre.deliver("due.day.20261014.20261013T1600Z")
        rig.clock.set(F.date("2026-10-13 21:00"))
        await rig.scheduler.pass()
        #expect(await rig.centre.deliveredList.contains(single))
        rig.clock.set(F.date("2026-10-14 00:30"))
        await rig.scheduler.pass()
        #expect(await !rig.centre.deliveredList.contains(single))
        #expect(await rig.centre.deliveredList.contains("due.day.20261014.20261013T1600Z"))
        let store = EventStore(context: rig.context, undo: rig.undo)
        store.toggleDone(try #require(rig.event("900006")))
        await rig.scheduler.pass()
        #expect(await rig.centre.deliveredList.contains("due.day.20261014.20261013T1600Z"))
        store.toggleDone(try #require(rig.event("900007")))
        await rig.scheduler.pass()
        #expect(await !rig.centre.deliveredList.contains("due.day.20261014.20261013T1600Z"))
    }

    @Test("Actions: Done on due.{900005}.ahead → done, one Mark Done step, markedDoneDueAt, its close removed next pass; groups offer Open only; Open on the 14 Oct group pages there with nothing selected")
    func actions() async throws {
        let rig = try DeadlineRig(now: F.date("2026-10-12 06:00"))
        await rig.scheduler.pass()
        let e5 = try #require(rig.event("900005"))
        #expect(await rig.centre.pendingByID["due.\(e5.id.uuidString).close"] != nil)
        let router = NotificationActionRouter(context: rig.context, undo: rig.undo, centre: rig.centre, clock: rig.clock,
                                              calendar: F.calendar)
        let state = CalendarState()
        router.calendarState = state
        await router.handle(NotificationResponse(identifier: "due.\(e5.id.uuidString).ahead", action: .done,
                                                 subjectID: e5.id.uuidString, category: .deadline))
        #expect(e5.status == .done && e5.markedDoneDueAt == e5.start)
        #expect(rig.undo.undoSteps.count == 1 && rig.undo.undoActionName == "Mark Done")
        await rig.scheduler.pass()
        #expect(await rig.centre.pendingByID["due.\(e5.id.uuidString).close"] == nil)
        // Done again does nothing.
        await router.handle(NotificationResponse(identifier: "due.\(e5.id.uuidString).close", action: .done,
                                                 subjectID: e5.id.uuidString, category: .deadline))
        #expect(rig.undo.undoSteps.count == 1)

        let specs = Dictionary(uniqueKeysWithValues: NotificationCategorySpec.all.map { ($0.identifier, $0.actions.map(\.title)) })
        #expect(specs["kadence.deadline"] == ["Done", "Open"] && specs["kadence.deadlines"] == ["Open"])

        state.selectedEventID = e5.id
        await router.handle(NotificationResponse(identifier: "due.day.20261014.20261013T1600Z", action: .open,
                                                 subjectID: "20261014", category: .deadlines))
        #expect(state.selectedEventID == nil && F.calendar.isDate(state.anchor, inSameDayAs: F.date("2026-10-14 12:00")))
        #expect(router.openHistory.last == .event(nil))
        // Open on a single selects it.
        await router.handle(NotificationResponse(identifier: "due.\(e5.id.uuidString).ahead", action: .open,
                                                 subjectID: e5.id.uuidString, category: .deadline))
        #expect(state.selectedEventID == e5.id)
    }

    @Test("N8 for a Moodle source: feed401, feed403, feed404, feedHTML from a background sync → one sync. each with §40.7's body; from Sync Now → none; leaving → removed",
          arguments: [(MoodleFeedCase.feed401, "moodle.technikum-wien.at didn't accept the calendar URL. Sync is paused until you paste a new one in Kadence."),
                      (.feed403, "moodle.technikum-wien.at refused access to the calendar. Sync is paused until you paste a new URL in Kadence."),
                      (.feed404, "moodle.technikum-wien.at has no calendar at the saved URL. Paste a new one in Kadence."),
                      (.feedHTML, "moodle.technikum-wien.at sent a web page instead of the calendar. If you changed your FH password, Moodle made a new calendar URL.")])
    func n8(_ feedCase: MoodleFeedCase, _ body: String) async throws {
        let rig = try FeedRig(now: F.date("2026-10-16 13:07"))
        try await rig.importFeed()
        let centre = RecordingNotificationCenter(authorization: .allowed)
        let clock = ManualTravelClock(F.date("2026-10-16 14:07"))
        let scheduler = NotificationScheduler(context: rig.context, centre: centre, clock: clock, calendar: F.calendar,
                                              log: RoutingLog(category: "notifications"))
        rig.coordinator.onStateEvent = { scheduler.sourceStateChanged($0) }
        await rig.sync(feedCase, at: F.date("2026-10-16 14:07"), trigger: .interval)
        await scheduler.pass()
        let identifier = "sync.\(rig.source.id)"
        #expect(await centre.pendingByID[identifier]?.title == "Moodle isn't syncing")
        #expect(await centre.pendingByID[identifier]?.body == body)
        #expect(await centre.pendingByID[identifier]?.category == .source)
        #expect(await !F.leaks(centre.pendingByID[identifier]?.body ?? ""))
        // Not repeated while it stays.
        await rig.sync(feedCase, at: F.date("2026-10-16 15:07"), trigger: .syncNow)
        await scheduler.pass()
        #expect(await centre.addCalls.filter { $0.identifier == identifier }.count == 1)
        // Leaving the state removes it.
        await rig.sync(.feedOK, at: F.date("2026-10-16 16:07"), trigger: .syncNow)
        await scheduler.pass()
        #expect(await centre.pendingByID[identifier] == nil)
    }

    @Test("N8 is not sent for a state the user caused (Sync Now)")
    func n8SyncNow() async throws {
        let rig = try FeedRig(now: F.date("2026-10-16 13:07"))
        try await rig.importFeed()
        let centre = RecordingNotificationCenter(authorization: .allowed)
        let scheduler = NotificationScheduler(context: rig.context, centre: centre, clock: ManualTravelClock(F.date("2026-10-16 14:07")),
                                              calendar: F.calendar, log: RoutingLog(category: "notifications"))
        rig.coordinator.onStateEvent = { scheduler.sourceStateChanged($0) }
        await rig.sync(.feed404, at: F.date("2026-10-16 14:07"), trigger: .syncNow)
        await scheduler.pass()
        #expect(await centre.pendingByID["sync.\(rig.source.id)"] == nil)
    }
}

/// `moodleOnly`'s shape on a real store: the built-ins, Sleep, the Moodle
/// source imported from `feedOK`, 900004 done.
@MainActor
final class DeadlineRig {
    let feed: FeedRig
    let centre = RecordingNotificationCenter(authorization: .allowed)
    let clock: ManualTravelClock
    let undo = UndoStack()
    let scheduler: NotificationScheduler
    var context: ModelContext { feed.context }

    init(now: Date) throws {
        feed = try FeedRig(now: now)
        clock = ManualTravelClock(now)
        scheduler = NotificationScheduler(context: feed.context, centre: centre, clock: clock, calendar: MoodleFixture.calendar,
                                          log: RoutingLog(category: "notifications"))
        TravelBuiltIns.ensure(in: feed.context)
        BuiltInSource.ensure(in: feed.context)
        feed.context.insert(TimeWindow(weekdays: Set(1...7), startMinutes: 22 * 60, endMinutes: 7 * 60, kind: .protected,
                                       label: "Sleep"))
        // The Import, synchronously: the fetch is in memory.
        let url = MoodleMock.url!
        let body = MoodleFeedCases.body(.feedOK, base: MoodleFixture.text) ?? Data()
        guard case .calendar(let parsed) = MoodleProfile.read(body, zone: MoodleFixture.zone) else {
            throw CancellationError()
        }
        let source = Source.moodleFeed(host: url.host, paletteKey: .teal)
        try feed.secrets.saveFeedURL(url, sourceID: source.id, label: "Kadence — Moodle")
        feed.context.insert(source)
        feed.source = source
        try feed.coordinator.applyFeedFetched(FeedFetch(feed: parsed, requests: 1, milliseconds: 1, bytes: 1), to: source,
                                              kind: .import)
        let e4 = feed.event("900004")
        e4?.status = .done; e4?.markedDoneDueAt = e4?.start
        try feed.context.save()
    }

    func event(_ n: String) -> Event? { feed.event(n) }
}
