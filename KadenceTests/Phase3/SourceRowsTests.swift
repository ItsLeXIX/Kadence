//
//  SourceRowsTests.swift
//  KadenceTests
//
//  PHASE3-PLAN.md task 14: sidebar rows, the source popover, the stale line
//  (layouts.md §2.1; components.md §19.2–§19.4).
//

import Testing
import Foundation
import SwiftData
@testable import Kadence

nonisolated private let sentinel = "S3ntinel-pw-⚠"

@MainActor
struct SourceRowsTests {

    @Test("Slot content per kind; nothing for offline; the spinner only after 0.5 s")
    func slot() {
        #expect(SourceStatusCopy.glyph(.upToDate, isSyncingVisibly: false) == .none)
        #expect(SourceStatusCopy.glyph(.neverSynced, isSyncingVisibly: false) == .none)
        #expect(SourceStatusCopy.glyph(.offline, isSyncingVisibly: false) == .none)
        #expect(SourceStatusCopy.glyph(.unreachable, isSyncingVisibly: false) == .transient)
        #expect(SourceStatusCopy.glyph(.serverError, isSyncingVisibly: false) == .transient)
        for state in SourceState.allCases where state.kind == .actionable {
            #expect(SourceStatusCopy.glyph(state, isSyncingVisibly: false) == .actionable, "\(state)")
        }
        #expect(SourceStatusCopy.glyph(.forbidden, isSyncingVisibly: true) == .spinner)
        let start = TestClock.now
        #expect(!SourceStatusSlot.showsSpinner(started: start, now: start.addingTimeInterval(0.49)))
        #expect(SourceStatusSlot.showsSpinner(started: start, now: start.addingTimeInterval(0.5)))
        #expect(!SourceStatusSlot.showsSpinner(started: nil, now: start))
        #expect(StatusGlyph.symbol == "exclamationmark.arrow.triangle.2.circlepath")
    }

    @Test("The popover's default button is the state's primary action, with the right edit focus")
    func popoverActions() {
        func effect(_ a: PrimaryAction) -> SourceActionRouting.Effect {
            SourceActionRouting.effect(of: a, sourceID: "s", fromPopover: true)
        }
        #expect(effect(.updatePassword).sheet == .edit(sourceID: "s", focus: .password, autoConnect: false))
        #expect(effect(.editAccount).sheet == .edit(sourceID: "s", focus: .server, autoConnect: false))
        #expect(effect(.chooseCalendar).sheet == .edit(sourceID: "s", focus: .none, autoConnect: true))
        #expect(effect(.updatePassword).opensSettings && effect(.chooseCalendar).opensSettings)
        #expect(effect(.syncNow).syncsNow && effect(.syncNow).sheet == nil)
        #expect(effect(.showDetails).togglesDetails)
        #expect(SourceActionRouting.settings(sourceID: "s").opensSettings)
        // Settings' own Edit Account… focuses Password.
        #expect(SourceActionRouting.effect(of: .editAccount, sourceID: "s", fromPopover: false).sheet
                == .edit(sourceID: "s", focus: .password, autoConnect: false))
    }

    @Test("The details list is capped at 8, then +N more")
    func detailsCap() {
        let (shown, more) = ProblemList.visible((1...20).map { ImportProblem(sentence: "\($0)") })
        #expect(shown.count == 8 && more == "+12 more")
    }

    @Test("The first-run row is present with no connected source and gone with one")
    func firstRun() {
        #expect(SidebarSourcesRule.showsConnectRow(connectedCount: 0))
        #expect(!SidebarSourcesRule.showsConnectRow(connectedCount: 1))
    }

    private func source(_ name: String = "University timetable", state: SourceState, lastSuccess: Date?) -> Source {
        let s = Source(connection: .caldav, displayName: name)
        s.serverURL = "https://cis.technikum-wien.at"; s.username = "user01"
        s.state = state; s.lastSuccessAt = lastSuccess
        return s
    }

    @Test("The stale line follows task 11's model and is never truncated at a 60-character name")
    func staleLine() {
        let now = TestClock.now
        #expect(SidebarSourcesRule.staleLines([source(state: .upToDate, lastSuccess: now.addingTimeInterval(-3600))], now: now).isEmpty)
        #expect(SidebarSourcesRule.staleLines([source(state: .forbidden, lastSuccess: now.addingTimeInterval(-3600))], now: now)
                == ["University timetable not synced since today 09:00"])
        let long = String(repeating: "L", count: 60)
        let lines = SidebarSourcesRule.staleLines([source(long, state: .unauthorized, lastSuccess: nil)], now: now)
        #expect(lines == ["\(long) has not synced yet"])
        // Local sources never show one.
        #expect(SidebarSourcesRule.staleLines([Source(connection: .local)], now: now).isEmpty)
        #expect(SidebarSourcesRule.staleLines((1...3).map { source("S\($0)", state: .forbidden, lastSuccess: nil) }, now: now)
                == ["S1 has not synced yet", "S2 has not synced yet", "+1 more sources not synced"])
    }

    @Test("Needs attention: source errors do not change the count")
    func needsAttention() throws {
        let state = CalendarState()
        let before = state.needsAttentionCount
        _ = source(state: .forbidden, lastSuccess: nil)
        _ = source(state: .calendarMissing, lastSuccess: nil)
        #expect(state.needsAttentionCount == before)
    }

    @Test("No hover help or AX value contains a password")
    func noSecrets() throws {
        let store = InMemorySecretStore()
        try store.save(Password(sentinel), for: SecretAccount(host: "cis.technikum-wien.at", username: "user01"),
                       info: .forSource(id: "s", displayName: "University timetable"))
        for state in SourceState.allCases {
            let p = SourceStatusPresentation(source: source(state: state, lastSuccess: TestClock.now), now: TestClock.now)
            #expect(!p.hoverHelp.contains(sentinel) && !p.accessibilityValue.contains(sentinel))
        }
        let p = SourceStatusPresentation(source: source(state: .forbidden, lastSuccess: nil), now: TestClock.now)
        #expect(p.accessibilityValue == "University timetable, Access refused")
    }
}
