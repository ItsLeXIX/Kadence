//
//  SourcesSettingsTests.swift
//  KadenceTests
//
//  PHASE3-PLAN.md task 12: Settings ▸ Sources and removal (layouts.md §11;
//  interactions.md §13.2; components.md §19.3, §21.4).
//

import Testing
import Foundation
import SwiftData
import AppKit
@testable import Kadence

nonisolated private let sentinel = "S3ntinel-pw-⚠"

@MainActor
@Suite(.serialized)
struct SourcesSettingsTests {

    private func connectedFixture() async throws -> (SyncFixture, InMemorySecretStore, SecretAccount) {
        let f = try SyncFixture()
        try await f.run(MockHarness(.reportOK, feed: MockHarness.reportReview()), kind: .import)
        let secrets = InMemorySecretStore()
        let account = SecretAccount(host: "cis.technikum-wien.at", username: "user01")
        try secrets.save(Password(sentinel), for: account, info: .forSource(id: f.source.id, displayName: f.source.displayName))
        return (f, secrets, account)
    }

    @Test("Renaming commits, reverts when empty, and updates the Keychain label")
    func rename() async throws {
        let (f, secrets, account) = try await connectedFixture()
        #expect(SourcesSettingsModel.rename(f.source, to: "  FH timetable ", context: f.context, secrets: secrets) == "FH timetable")
        #expect(f.source.displayName == "FH timetable")
        #expect(secrets.info(for: account)?.label == "Kadence — FH timetable")
        #expect(SourcesSettingsModel.rename(f.source, to: "   ", context: f.context, secrets: secrets) == "FH timetable")
        #expect(f.source.displayName == "FH timetable")
    }

    @Test("The Account row reads `user01 @ cis.technikum-wien.at`; no row shows a password or bullets")
    func accountRow() async throws {
        let (f, _, _) = try await connectedFixture()
        #expect(SourcesSettingsModel.accountRow(f.source) == "user01 @ cis.technikum-wien.at")
        let p = SourceStatusPresentation(source: f.source, now: TestClock.now)
        let calendars = SourcesSettingsModel.calendarRow(f.source)
        for text in [SourcesSettingsModel.accountRow(f.source), calendars.label, calendars.value, p.title, p.body ?? "",
                     p.statusLine, p.hoverHelp, p.accessibilityValue,
                     SourcesSettingsModel.intervalLabel(f.source.pollInterval)] {
            #expect(!text.contains(sentinel) && !text.contains("•") && !text.lowercased().contains("password"))
        }
    }

    @Test("Calendar vs Calendars follows the count; names comma-separated")
    func calendarRow() async throws {
        let (f, _, _) = try await connectedFixture()
        #expect(SourcesSettingsModel.calendarRow(f.source) == ("Calendar", "LVPlan"))
        f.source.calendars = [SourceCalendar(href: "/a/", displayName: "LVPlan"), SourceCalendar(href: "/b/", displayName: "Prüfungen")]
        #expect(SourcesSettingsModel.calendarRow(f.source) == ("Calendars", "LVPlan, Prüfungen"))
    }

    @Test("The interval picker offers exactly the seven values, default Every 30 minutes")
    func intervals() {
        #expect(SourcesSettingsModel.intervals.map(\.label) == ["Every 15 minutes", "Every 30 minutes", "Every hour",
                                                                "Every 3 hours", "Every 6 hours", "Every 12 hours", "Every day"])
        #expect(SourcesSettingsModel.intervals.map(\.seconds) == [900, 1800, 3600, 10_800, 21_600, 43_200, 86_400])
        #expect(SourcesSettingsModel.intervalLabel(Source().pollInterval) == "Every 30 minutes")
    }

    @Test("Remove: events (history included) and the source in one transaction; Keychain item deleted; slot freed; conflicts drop")
    func remove() async throws {
        let f = try SyncFixture(seedPhase2: true)
        try await f.run(MockHarness(.reportOK, feed: MockHarness.reportReview()), kind: .import)
        let secrets = InMemorySecretStore()
        let account = SecretAccount(host: "cis.technikum-wien.at", username: "user01")
        try secrets.save(Password(sentinel), for: account, info: .forSource(id: f.source.id, displayName: "x"))
        func conflicts() throws -> Int {
            MainWindow.sortedConflicts(events: try f.context.fetch(FetchDescriptor<Event>()),
                                       routineBlocks: try f.context.fetch(FetchDescriptor<RoutineBlock>()), now: TestClock.now).count
        }
        #expect(try conflicts() == 14)
        let outcome = try SourcesSettingsModel.remove(f.source, context: f.context, secrets: secrets, sync: nil,
                                                      state: nil, undo: nil)
        #expect(!outcome.keychainFailed && outcome.removedEventIDs.count >= 13)
        #expect(try secrets.read(account) == nil)
        #expect(try f.context.fetch(FetchDescriptor<Source>()).allSatisfy { $0.id != "timetable" })
        #expect(try f.context.fetch(FetchDescriptor<Event>()).allSatisfy { $0.sourceID != "timetable" })
        #expect(try conflicts() == 13)  // the source's one conflict (SWRM-ILV × Training) is gone
        let used = try f.context.fetch(FetchDescriptor<Source>()).map(\.paletteKey).filter { $0 != .blue }
        #expect(Source.firstUnusedPaletteKey(existing: used) == .blue)  // the slot is free again
    }

    @Test("The alert: Cancel is the default button; the text says `password deleted from the Keychain`")
    func alert() async throws {
        let (f, _, _) = try await connectedFixture()
        let alert = SourcesSettingsModel.makeRemovalAlert(f.source, eventCount: 142)
        #expect(alert.messageText == "Remove “University timetable”?")
        #expect(alert.informativeText == "Its 142 events — including past weeks and anything you marked done or skipped — will be removed from your calendar, and its password deleted from the Keychain. Routine blocks you moved for these events stay where they are. You can connect it again at any time; the timetable comes back, your done and skipped marks don't.")
        #expect(alert.alertStyle == .warning)
        #expect(alert.buttons.map(\.title) == ["Cancel", "Remove"])
        #expect(alert.buttons[0].keyEquivalent == "\r" && alert.buttons[1].keyEquivalent.isEmpty)
        #expect(alert.buttons[1].hasDestructiveAction)
    }

    @Test("A Keychain delete failure still removes the source and gives the follow-up copy")
    func keychainFailure() async throws {
        let (f, secrets, _) = try await connectedFixture()
        secrets.failNext("delete")
        let outcome = try SourcesSettingsModel.remove(f.source, context: f.context, secrets: secrets, sync: nil, state: nil, undo: nil)
        #expect(outcome.keychainFailed)
        #expect(try f.context.fetchCount(FetchDescriptor<Source>()) == 0)
        #expect(SourcesSettingsModel.keychainFollowUp(name: "University timetable") ==
                "The password for University timetable couldn't be deleted from the Keychain. You can remove the item “Kadence — University timetable” in Keychain Access.")
    }

    @Test("Review mode: Settings opens on the source, in upToDate")
    func reviewOpensUpToDate() async throws {
        let container = try ModelContainer(for: Schema(KadenceSchema.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let secrets = InMemorySecretStore()
        ReviewMode.seedIfRequested(.phase3, context: context, now: TestClock.now, secrets: secrets) {}
        let server = ReviewMode.server(case: .reportOK, now: TestClock.now)
        let coordinator = SyncCoordinator(context: context, secrets: secrets, scheduling: FakeScheduling(), path: FakePath(),
                                          clock: { TestClock.now }) { account in
            CalDAVScheduleSource(account: account, secrets: secrets, now: { TestClock.now }) { MockCalDAVTransport(server: server) }
        }
        coordinator.launched()
        await coordinator.waitUntilIdle()
        let connected = coordinator.connectedSources
        #expect(connected.map(\.id) == ["timetable"])
        let p = SourceStatusPresentation(source: connected[0], now: TestClock.now)
        #expect(p.title == "Up to date" && p.primaryAction == .syncNow)
        #expect(SourcesSettingsModel.calendarRow(connected[0]) == ("Calendar", "LVPlan"))
        #expect(SourcesSettingsModel.intervalLabel(connected[0].pollInterval) == "Every 30 minutes")
    }

    @Test("Show Details: at most 8, then +N more")
    func detailsCap() {
        let problems = (1...11).map { ImportProblem(sentence: "p\($0)") }
        let (shown, more) = ProblemList.visible(problems)
        #expect(shown.count == 8 && more == "+3 more")
        #expect(ProblemList.visible(Array(problems.prefix(8))).more == nil)
    }
}
