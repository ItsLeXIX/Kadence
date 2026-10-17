//
//  SourceStatusTests.swift
//  KadenceTests
//
//  PHASE3-PLAN.md task 11: the exact §19.1 strings, §12.1's step-1 rows,
//  primary actions, plurals, the last-change line, §19.5's time forms and
//  §19.4's stale line. Pure — no store except where a `Source` is needed.
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

nonisolated private let sentinel = "S3ntinel-pw-⚠"
private let facts = StatusFacts(host: "cis.technikum-wien.at", user: "user01", name: "University timetable",
                                calendars: ["LVPlan"], otherHost: "login.example.invalid", code: 503, k: 2, n: 142)
private let next = "14:32"
private let last = "today 14:02"
private let zone = TestClock.zone

private func body(_ state: SourceState, _ f: StatusFacts = facts) -> String? {
    SourceStatusCopy.body(state, f, next: next, last: last)
}

struct SourceStatusTests {

    // MARK: §19.1, one test per row

    @Test("upToDate / syncing / neverSynced / offline")
    func okRows() {
        #expect(SourceStatusCopy.title(.upToDate, host: facts.host) == "Up to date" && body(.upToDate) == nil)
        #expect(SourceStatusCopy.title(.syncing, host: facts.host) == "Syncing…" && body(.syncing) == nil)
        #expect(SourceStatusCopy.title(.neverSynced, host: facts.host) == "Waiting for first sync")
        #expect(body(.neverSynced) == "Kadence will sync as soon as cis.technikum-wien.at can be reached.")
        #expect(SourceStatusCopy.title(.offline, host: facts.host) == "Offline")
        #expect(body(.offline) == "Kadence will sync when this Mac is back online. Events from the last sync (today 14:02) are still shown.")
    }

    @Test("unauthorized") func unauthorized() {
        #expect(SourceStatusCopy.title(.unauthorized, host: facts.host) == "Sign-in failed")
        #expect(body(.unauthorized) == "cis.technikum-wien.at didn't accept the password for user01. Automatic sync is paused so the account isn't locked.")
    }

    @Test("forbidden") func forbidden() {
        #expect(SourceStatusCopy.title(.forbidden, host: facts.host) == "Access refused")
        #expect(body(.forbidden) == "cis.technikum-wien.at refused access for user01. Automatic sync is paused so the account isn't locked.")
    }

    @Test("noCalDAV") func noCalDAV() {
        #expect(SourceStatusCopy.title(.noCalDAV, host: facts.host) == "No calendar server found")
        #expect(body(.noCalDAV) == "cis.technikum-wien.at doesn't offer CalDAV calendars. Check the server name. Events from the last sync are kept.")
    }

    @Test("noCalendars") func noCalendars() {
        #expect(SourceStatusCopy.title(.noCalendars, host: facts.host) == "No calendars found")
        #expect(body(.noCalendars) == "user01 @ cis.technikum-wien.at has no calendars with events. Events from the last sync are kept.")
    }

    @Test("calendarMissing, with one, two and three calendars") func calendarMissing() {
        #expect(SourceStatusCopy.title(.calendarMissing, host: facts.host) == "Calendar not found")
        #expect(body(.calendarMissing) == "LVPlan is no longer on cis.technikum-wien.at. Events from the last sync are kept until you choose a calendar or remove the source.")
        var two = facts; two.calendars = ["LVPlan", "Prüfungen"]
        #expect(body(.calendarMissing, two)?.hasPrefix("LVPlan and Prüfungen is no longer on") == true)
        var three = facts; three.calendars = ["LVPlan", "Prüfungen", "Aufgaben"]
        #expect(body(.calendarMissing, three)?.hasPrefix("LVPlan and 2 other calendars is no longer on") == true)
    }

    @Test("fetchFailed") func fetchFailed() {
        #expect(SourceStatusCopy.title(.fetchFailed, host: facts.host) == "Couldn't read the calendar")
        #expect(body(.fetchFailed) == "cis.technikum-wien.at refused every way Kadence asks for events from LVPlan. Nothing was changed.")
    }

    @Test("notACalendar") func notACalendar() {
        #expect(SourceStatusCopy.title(.notACalendar, host: facts.host) == "Not a calendar")
        #expect(body(.notACalendar) == "cis.technikum-wien.at sent a web page instead of calendar data — often a sign-in or maintenance page. Events from the last sync are kept.")
    }

    @Test("emptyFeed") func emptyFeed() {
        #expect(SourceStatusCopy.title(.emptyFeed, host: facts.host) == "The calendar is empty")
        #expect(body(.emptyFeed) == "cis.technikum-wien.at sent no events for LVPlan. It had 142 events at the last sync, so they are kept. If the timetable really is empty, remove the source in Settings.")
        var one = facts; one.n = 1
        #expect(body(.emptyFeed, one)?.contains("It had 1 event at the last sync") == true)
    }

    @Test("partialImport") func partialImport() {
        #expect(SourceStatusCopy.title(.partialImport, host: facts.host) == "Imported with problems")
        #expect(body(.partialImport) == "2 of 142 events couldn't be read and were skipped. Nothing was removed.")
    }

    @Test("certificate") func certificate() {
        #expect(SourceStatusCopy.title(.certificate, host: facts.host) == "Secure connection failed")
        #expect(body(.certificate) == "The certificate for cis.technikum-wien.at couldn't be verified, so Kadence sent nothing to it. Nothing was changed.")
    }

    @Test("passwordMissing") func passwordMissing() {
        #expect(SourceStatusCopy.title(.passwordMissing, host: facts.host) == "Password not found")
        #expect(body(.passwordMissing) == "Kadence couldn't read the password for user01 @ cis.technikum-wien.at from the Keychain. Enter it again.")
    }

    @Test("redirected: both bodies") func redirected() {
        #expect(SourceStatusCopy.title(.redirected, host: facts.host) == "Redirected to another server")
        #expect(body(.redirected) == "cis.technikum-wien.at sent Kadence to login.example.invalid. Kadence didn't follow it, so nothing — and no password — was sent there.")
        var http = facts; http.otherHost = nil
        #expect(body(.redirected, http) == "cis.technikum-wien.at sent Kadence to an address without HTTPS. Kadence didn't follow it.")
    }

    @Test("unreachable") func unreachable() {
        #expect(SourceStatusCopy.title(.unreachable, host: facts.host) == "Can't reach cis.technikum-wien.at")
        #expect(body(.unreachable) == "Kadence will try again at 14:32. Events from the last sync (today 14:02) are still shown.")
    }

    @Test("serverError") func serverError() {
        #expect(SourceStatusCopy.title(.serverError, host: facts.host) == "Server error")
        #expect(body(.serverError) == "cis.technikum-wien.at answered with an error (503). Kadence will try again at 14:32.")
    }

    @Test("Every state has a title and the right kind; there are 20 (slice 3 adds feedNotFound, urlMissing)")
    func allStates() {
        #expect(SourceState.allCases.count == 20)
        #expect(SourceState.allCases.filter { $0.kind == .ok } == [.upToDate, .syncing, .neverSynced, .offline])
        #expect(SourceState.allCases.filter { $0.kind == .transient } == [.unreachable, .serverError])
    }

    // MARK: Primary actions

    @Test("Primary action per state")
    func primaryActions() {
        let expected: [SourceState: PrimaryAction?] = [
            .upToDate: .syncNow, .syncing: nil, .neverSynced: .syncNow, .offline: nil,
            .unauthorized: .updatePassword, .forbidden: .editAccount, .noCalDAV: .editAccount, .noCalendars: .syncNow,
            .calendarMissing: .chooseCalendar, .fetchFailed: .syncNow, .notACalendar: .syncNow, .emptyFeed: .syncNow,
            .partialImport: .showDetails, .certificate: .syncNow, .passwordMissing: .updatePassword,
            .redirected: .editAccount, .unreachable: .syncNow, .serverError: .syncNow,
            // Slice 3 (components.md §34.3): the two feed-only states.
            .feedNotFound: .replaceURL, .urlMissing: .replaceURL,
        ]
        for state in SourceState.allCases { #expect(SourceStatusCopy.primaryAction(state) == expected[state]!, "\(state)") }
        #expect(PrimaryAction.updatePassword.rawValue == "Update Password…")
        #expect(PrimaryAction.editAccount.rawValue == "Edit Account…")
        #expect(PrimaryAction.chooseCalendar.rawValue == "Choose Calendar…")
    }

    // MARK: §12.1's failure rows

    @Test("Step-1 failures: body and focus")
    func connectFailures() {
        func p(_ e: ScheduleSourceError) -> ConnectFailurePresentation { ConnectFailurePresentation(e, facts: facts) }
        #expect(p(.unauthorized).body == "cis.technikum-wien.at didn't accept the username or password.")
        #expect(p(.unauthorized).focus == .password(selectAll: true))
        #expect(p(.forbidden).body == "cis.technikum-wien.at refused access for user01." && p(.forbidden).focus == .username(selectAll: true))
        #expect(p(.noCalDAV).body == "cis.technikum-wien.at doesn't offer CalDAV calendars. Check the server name.")
        #expect(p(.noCalDAV).focus == .server(selectAll: true))
        #expect(p(.noCalendars).body == "user01 @ cis.technikum-wien.at has no calendars with events." && p(.noCalendars).focus == .username(selectAll: false))
        #expect(p(.redirected(otherHost: "login.example.invalid")).body == "cis.technikum-wien.at sent Kadence to login.example.invalid. Kadence didn't follow it, so nothing — and no password — was sent there.")
        #expect(p(.redirected(otherHost: nil)).body == "cis.technikum-wien.at sent Kadence to an address without HTTPS. Kadence didn't follow it.")
        #expect(p(.redirected(otherHost: nil)).focus == .server(selectAll: false))
        #expect(p(.notACalendar).body == "cis.technikum-wien.at sent a web page instead of calendar data. Try again later." && p(.notACalendar).focus == .connect)
        #expect(p(.fetchFailed(technical: "x")).body == "cis.technikum-wien.at refused every way Kadence asks for events. Nothing was saved.")
        #expect(p(.certificate).body == "The certificate for cis.technikum-wien.at couldn't be verified, so Kadence sent nothing to it.")
        #expect(p(.unreachable).body == "Check the server name and your connection, then try again." && p(.unreachable).focus == .connect)
        #expect(p(.serverError(503)).body == "cis.technikum-wien.at answered with an error (503). Try again later.")
        #expect(p(.offline).body == "This Mac is offline. Connect when it's back online.")
        #expect(p(.unauthorized).title == "Sign-in failed" && p(.certificate).title == "Secure connection failed")
    }

    // MARK: Plurals, lines, time

    @Test("Plurals: 1 event / 2 events")
    func plurals() {
        #expect(SourceStatusCopy.events(1) == "1 event" && SourceStatusCopy.events(2) == "2 events" && SourceStatusCopy.events(0) == "0 events")
    }

    @Test("The last-change line: every combination of zero terms omitted; nil with nothing")
    func lastChange() {
        let at = TestClock.date("2026-10-08 09:30")
        func line(_ a: Int, _ u: Int, _ r: Int) -> String? {
            SourceStatusCopy.lastChangeLine(at: at, added: a, updated: u, removed: r, now: TestClock.now, zone: zone)
        }
        #expect(line(2, 2, 2) == "Last change today 09:30: 2 added · 2 updated · 2 removed")
        #expect(line(1, 0, 0) == "Last change today 09:30: 1 added")
        #expect(line(0, 3, 0) == "Last change today 09:30: 3 updated")
        #expect(line(0, 0, 1) == "Last change today 09:30: 1 removed")
        #expect(line(1, 1, 0) == "Last change today 09:30: 1 added · 1 updated")
        #expect(line(1, 0, 1) == "Last change today 09:30: 1 added · 1 removed")
        #expect(line(0, 1, 1) == "Last change today 09:30: 1 updated · 1 removed")
        #expect(line(0, 0, 0) == nil)
        #expect(SourceStatusCopy.lastChangeLine(at: nil, added: 1, updated: 0, removed: 0, now: TestClock.now) == nil)
    }

    @Test("A source with no write since its Import has no last-change line")
    @MainActor
    func lastChangeNilAfterImport() throws {
        let source = Source(connection: .caldav)
        source.serverURL = "https://cis.technikum-wien.at"; source.username = "user01"
        source.importedAt = TestClock.now; source.lastSuccessAt = TestClock.now; source.state = .upToDate
        #expect(SourceStatusPresentation(source: source, now: TestClock.now, zone: zone).lastChangeLine == nil)
        source.lastChangeAt = TestClock.now.addingTimeInterval(60); source.lastChangeRemoved = 1
        #expect(SourceStatusPresentation(source: source, now: TestClock.now.addingTimeInterval(90), zone: zone).lastChangeLine
                == "Last change just now: 1 removed")
    }

    @Test("§19.5's five forms")
    func timeForms() {
        let now = TestClock.date("2026-10-08 15:00")
        #expect(SourceStatusCopy.when(now.addingTimeInterval(-30), now: now, zone: zone) == "just now")
        #expect(SourceStatusCopy.when(TestClock.date("2026-10-08 14:02"), now: now, zone: zone) == "today 14:02")
        #expect(SourceStatusCopy.synced(TestClock.date("2026-10-08 14:02"), now: now, zone: zone) == "14:02")
        #expect(SourceStatusCopy.when(TestClock.date("2026-10-07 14:02"), now: now, zone: zone) == "yesterday 14:02")
        #expect(SourceStatusCopy.synced(TestClock.date("2026-10-07 14:02"), now: now, zone: zone) == "yesterday 14:02")
        #expect(SourceStatusCopy.when(TestClock.date("2026-10-05 14:02"), now: now, zone: zone) == "Mon 14:02")
        #expect(SourceStatusCopy.when(TestClock.date("2026-10-01 14:02"), now: now, zone: zone) == "1 Oct 14:02")
        #expect(SourceStatusCopy.when(TestClock.date("2025-10-06 14:02"), now: now, zone: zone) == "6 Oct 2025 14:02")
        #expect(SourceStatusCopy.next(TestClock.date("2026-10-08 15:30"), now: now, zone: zone) == "15:30")
        #expect(SourceStatusCopy.next(TestClock.date("2026-10-09 00:10"), now: now, zone: zone) == "tomorrow 00:10")
        #expect(SourceStatusCopy.statusLine(state: .upToDate, lastSuccess: TestClock.date("2026-10-08 14:02"), count: 142,
                                            now: now, zone: zone) == "Synced 14:02 · 142 events")
        #expect(SourceStatusCopy.statusLine(state: .forbidden, lastSuccess: TestClock.date("2026-10-08 14:02"), count: 1,
                                            now: now, zone: zone) == "Last synced today 14:02 · 1 event")
        #expect(SourceStatusCopy.statusLine(state: .neverSynced, lastSuccess: nil, count: 0, now: now) == "Never synced")
    }

    @Test("The stale line: 23 h 59 / 24 h 01 at 30 minutes; 2 × 1 day; never for offline alone")
    func staleLine() {
        let now = TestClock.now
        func line(_ state: SourceState, ago: TimeInterval, interval: TimeInterval = 1800) -> String? {
            SourceStatusCopy.staleLine(name: "University timetable", state: state, lastSuccess: now.addingTimeInterval(-ago),
                                       interval: interval, now: now, zone: zone)
        }
        #expect(line(.upToDate, ago: 23 * 3600 + 59 * 60) == nil)
        #expect(line(.upToDate, ago: 24 * 3600 + 60) == "University timetable not synced since yesterday 09:59")
        #expect(line(.upToDate, ago: 2 * 86_400 - 60, interval: 86_400) == nil)
        #expect(line(.upToDate, ago: 2 * 86_400 + 60, interval: 86_400) != nil)
        #expect(line(.offline, ago: 3600) == nil)
        #expect(line(.unreachable, ago: 3600) == nil)
        #expect(line(.forbidden, ago: 3600) == "University timetable not synced since today 09:00")
        #expect(SourceStatusCopy.staleLine(name: "University timetable", state: .neverSynced, lastSuccess: nil, interval: 1800,
                                           now: now) == "University timetable has not synced yet")
        let long = String(repeating: "N", count: 60)
        #expect(SourceStatusCopy.staleLine(name: long, state: .forbidden, lastSuccess: nil, interval: 1800, now: now)?
            .hasPrefix(long) == true)
        #expect(SourceStatusCopy.staleLines(["a", "b", "c", "d"]) == ["a", "b", "+2 more sources not synced"])
    }

    @Test("Hover help and VoiceOver value")
    func hoverAndValue() {
        let now = TestClock.date("2026-10-08 15:00")
        #expect(SourceStatusCopy.hoverHelp(name: "University timetable", state: .upToDate,
                                           lastSuccess: TestClock.date("2026-10-08 14:02"), now: now, zone: zone)
                == "University timetable — Synced 14:02")
        #expect(SourceStatusCopy.hoverHelp(name: "University timetable", state: .unauthorized, lastSuccess: nil, now: now)
                == "University timetable — Sign-in failed")
        #expect(SourceStatusCopy.hoverHelp(name: "University timetable", state: .offline,
                                           lastSuccess: TestClock.date("2026-10-08 14:02"), now: now, zone: zone)
                == "University timetable — Offline, last synced 14:02")
        #expect(SourceStatusCopy.accessibilityValue(name: "University timetable", state: .forbidden, host: "x")
                == "University timetable, Access refused")
    }

    @Test("No output string, for any state, built while the sentinel is in the secret store, contains it")
    @MainActor
    func noSecrets() throws {
        let store = InMemorySecretStore()
        try store.save(Password(sentinel), for: SecretAccount(host: "cis.technikum-wien.at", username: "user01"),
                       info: .forSource(id: "s", displayName: "University timetable"))
        let source = Source(connection: .caldav)
        source.serverURL = "https://cis.technikum-wien.at"; source.username = "user01"
        source.calendars = [SourceCalendar(href: MockCalDAVServer.lvplan, displayName: "LVPlan")]
        for state in SourceState.allCases {
            source.state = state
            source.stateDetail = SourceStatusPresentation.storedDetail(state, SourceStatusPresentation.facts(of: source))
            let p = SourceStatusPresentation(source: source, now: TestClock.now)
            for text in [p.title, p.body ?? "", p.statusLine, p.lastChangeLine ?? "", p.hoverHelp, p.staleLine ?? "",
                         p.accessibilityValue, p.primaryAction?.rawValue ?? ""] + texts(of: p) {
                #expect(!text.contains(sentinel) && !text.contains("S3ntinel"))
            }
        }
        for error in [ScheduleSourceError.unauthorized, .forbidden, .noCalDAV, .certificate, .offline] {
            for text in texts(of: ConnectFailurePresentation(error, facts: facts)) { #expect(!text.contains(sentinel)) }
        }
    }
}
