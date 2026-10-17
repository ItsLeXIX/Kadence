//
//  MoodleConnectTests.swift
//  KadenceTests
//
//  PHASE3-SLICE3-PLAN.md task 10 — layouts.md §2.1 (amended), §11 (amended),
//  §15, §16; components.md §33, §34.3; interactions.md §16.1, §16.2, §16.4.
//  The sheet's model on an in-memory store, the in-memory (or ordered)
//  secret store and `MockFeedTransport`; and §43 items 1–8 as offscreen
//  renders (`-p3ct10`). No network, no Keychain.
//

import Testing
import Foundation
import SwiftData
import SwiftUI
import Synchronization
@testable import Kadence

private typealias F = MoodleFixture

@MainActor
final class MoodleSheetRig {
    let container: ModelContainer
    let context: ModelContext
    let secrets: any SecretStore
    var feedCase: MoodleFeedCase
    var now: Date

    init(feedCase: MoodleFeedCase = .feedOK, now: Date = F.date("2026-10-12 06:00"),
         secrets: (any SecretStore)? = nil) throws {
        container = try ModelContainer(for: Schema(KadenceSchema.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = container.mainContext
        BuiltInSource.ensure(in: context)
        TravelBuiltIns.ensure(in: context)
        self.secrets = secrets ?? InMemorySecretStore()
        self.feedCase = feedCase
        self.now = now
    }

    func model(replacing: Source? = nil) -> MoodleSheetModel {
        let feedCase = feedCase
        return MoodleSheetModel(replacing: replacing, context: context, secrets: secrets,
                                makeTransport: { MockFeedTransport(case: feedCase, base: MoodleFixture.text) },
                                sync: nil, clock: { [unowned self] in self.now }, zone: F.zone)
    }

    var moodleSources: [Source] { ((try? context.fetch(FetchDescriptor<Source>())) ?? []).filter { $0.connection == .icsFeed } }
    var eventCount: Int { (try? context.fetchCount(FetchDescriptor<Event>())) ?? -1 }
}

/// Every string the sheet's model can draw.
@MainActor
private func strings(_ m: MoodleSheetModel) -> [String] {
    [m.title, m.intro, m.placeholder, MoodleSheetModel.footnote, m.validationLine ?? "", m.connectingLine,
     m.failure?.title ?? "", m.failure?.body ?? "", m.saveFailure?.title ?? "", m.saveFailure?.body ?? "", m.step2Title,
     m.displayLine, m.rangeLine, m.urlAccessibilityValue, MoodleSheetModel.urlAccessibilityLabel]
        + m.sentences.map(\.text) + m.problems.flatMap { [$0.sentence, $0.technical ?? ""] }
}

@MainActor
@Suite(.serialized)
struct MoodleConnectTests {

    @Test("Validation messages and the parsed line in the model, exact; Connect enabled only on V11; the field's AX value")
    func validation() throws {
        let rig = try MoodleSheetRig()
        let m = rig.model()
        #expect(m.title == "Connect Moodle" && m.name == "Moodle" && m.focus == .url)
        #expect(m.validationLine == nil && !m.canConnect && m.urlAccessibilityValue == "empty")
        m.urlText = MoodleMock.urlString.replacingOccurrences(of: "https://", with: "http://")
        #expect(m.validationLine == "Kadence only connects over HTTPS." && !m.canConnect)
        #expect(m.urlAccessibilityValue == "filled")
        m.urlText = "https://moodle.technikum-wien.at/my/"
        #expect(m.validationLine == "That isn't the calendar URL. In Moodle, choose Get calendar URL and copy the address it shows.")
        m.urlText = MoodleMock.urlString.replacingOccurrences(of: "recentupcoming", with: "weeknow")
        #expect(m.validationLine == "This URL exports a fixed period. In Moodle, choose Recent and upcoming, then Get calendar URL.")
        m.urlText = MoodleMock.urlString
        #expect(m.validationLine == "moodle.technikum-wien.at/… · All events, recent and upcoming" && m.canConnect)
        #expect(m.connectingLine == "Connecting to moodle.technikum-wien.at…")
        for text in strings(m) { #expect(!F.leaks(text), "\(text)") }
    }

    @Test("Step 2 for feedOK at Mon 12 Oct 06:00: every sentence exact")
    func step2OK() async throws {
        let rig = try MoodleSheetRig()
        let m = rig.model()
        m.urlText = MoodleMock.urlString
        m.connect()
        await m.waitForConnect()
        #expect(m.phase == .step2 && m.step2Title == "Import Moodle" && m.displayLine == "moodle.technikum-wien.at/…")
        #expect(m.rangeLine == "29 items, 11 Oct 2026 – 14 Dec 2026")
        #expect(m.sentences.map(\.text) == [
            "25 deadlines from 10 courses and 2 other categories.",
            "4 openings are shown with the deadline they belong to.",
            "1 of them is before today. It's imported once, as history, and never changed afterwards.",
            "Moodle doesn't tell Kadence what you've handed in. Mark a deadline done in Kadence when you have, and its reminders stop.",
        ])
        #expect(m.sentences.allSatisfy { !$0.isPrimary })
        // Nothing written before Import.
        #expect(rig.moodleSources.isEmpty && rig.eventCount == 0)
        for text in strings(m) { #expect(!F.leaks(text), "\(text)") }
    }

    @Test("Step 2 for feedNotice: the notices sentence in text.primary; feedEmpty: the empty form, Import enabled")
    func step2Others() async throws {
        let notice = try MoodleSheetRig(feedCase: .feedNotice)
        let m = notice.model()
        m.urlText = MoodleMock.urlString
        m.connect()
        await m.waitForConnect()
        #expect(m.rangeLine == "31 items, 11 Oct 2026 – 14 Dec 2026")
        let notices = try #require(m.sentences.first { $0.text.hasPrefix("2 items") })
        #expect(notices.text == "2 items aren't a deadline or an opening Kadence recognises. They're shown, but Kadence won't remind you of them.")
        #expect(notices.isPrimary)

        let empty = try MoodleSheetRig(feedCase: .feedEmpty)
        let e = empty.model()
        e.urlText = MoodleMock.urlString
        e.connect()
        await e.waitForConnect()
        #expect(e.phase == .step2 && e.rangeLine == "Moodle has no items for this period yet.")
        #expect(e.sentences.map(\.text) == ["Kadence will add them as they appear."] && e.canImport)
    }

    @Test("Step 1 failures: the state's title and §16.1's body; focus as the table says")
    func failures() async throws {
        let cases: [(MoodleFeedCase, String, String, MoodleSheetModel.Field)] = [
            (.feed401, "Calendar URL refused", "moodle.technikum-wien.at didn't accept this calendar URL. In Moodle, choose Get calendar URL again and paste the new one.", .url),
            (.feed403, "Access refused", "moodle.technikum-wien.at refused access to the calendar.", .url),
            (.feed404, "Calendar not found", "moodle.technikum-wien.at has no calendar at this URL. Copy the URL from Moodle again.", .url),
            (.feedHTML, "Not a calendar", "moodle.technikum-wien.at sent a web page instead of the calendar. Copy the URL from Moodle's Get calendar URL again.", .url),
            (.feedOffline, "Offline", "This Mac is offline. Connect when it's back online.", .connect),
            (.feedTimeout, "Can't reach moodle.technikum-wien.at", "Check your connection, then try again.", .connect),
            (.feed503, "Server error", "moodle.technikum-wien.at answered with an error (503). Try again later.", .connect),
            (.feedTLS, "Secure connection failed", "The certificate for moodle.technikum-wien.at couldn't be verified, so Kadence sent nothing to it. Nothing was changed.", .connect),
            (.feedRedirectCrossHost, "Redirected to another server", "moodle.technikum-wien.at sent Kadence to login.example.invalid. Kadence didn't follow it, so nothing was sent there.", .url),
        ]
        for (feedCase, title, body, focus) in cases {
            let rig = try MoodleSheetRig(feedCase: feedCase)
            let m = rig.model()
            m.urlText = MoodleMock.urlString
            m.connect()
            await m.waitForConnect()
            #expect(m.phase == .editing && m.failure?.title == title && m.failure?.body == body, "\(feedCase)")
            #expect(m.focus == focus, "\(feedCase)")
            #expect(rig.moodleSources.isEmpty && rig.eventCount == 0)
            for text in strings(m) { #expect(!F.leaks(text), "\(text)") }
        }
    }

    @Test("Import's write order: Keychain item → Source → items; the log lines; Settings would select it")
    func importOrder() async throws {
        let ordered = OrderedSecretStore()
        let rig = try MoodleSheetRig(secrets: ordered)
        let m = rig.model()
        m.urlText = MoodleMock.urlString
        m.connect()
        await m.waitForConnect()
        let source = try #require(m.importNow())
        #expect(ordered.log.withLock { $0 } == ["saveFeed \(source.id)"])
        #expect(source.connection == .icsFeed && source.paletteKey == .blue)  // no timetable here: the first free slot
        #expect(source.displayName == "Moodle" && source.pollInterval == 3600 && source.state == .upToDate)
        #expect(rig.eventCount == 29)
        #expect(try ordered.readFeedURL(sourceID: source.id) == MoodleMock.url)
        #expect(ordered.inner.feedLabel(sourceID: source.id) == "Kadence — Moodle")
        #expect(m.urlText.isEmpty)
        #expect(source.serverURL == "https://moodle.technikum-wien.at" && !(source.stateDetail ?? "").contains("SENTINEL"))
    }

    @Test("A scripted Keychain failure at Import writes nothing, with the exact copy")
    func importKeychainFailure() async throws {
        let secrets = InMemorySecretStore()
        let rig = try MoodleSheetRig(secrets: secrets)
        let m = rig.model()
        m.urlText = MoodleMock.urlString
        m.connect()
        await m.waitForConnect()
        secrets.failNext("saveFeed")
        #expect(m.importNow() == nil)
        #expect(m.saveFailure == .init(title: "URL not saved",
                                       body: "Kadence couldn't save the calendar URL in the Keychain, so nothing was saved. Try again."))
        #expect(rig.moodleSources.isEmpty && rig.eventCount == 0 && secrets.feedSourceIDs.isEmpty)
    }

    @Test("Cancel at each step writes nothing; Back keeps the URL for the sheet's lifetime")
    func cancel() async throws {
        let rig = try MoodleSheetRig()
        let m = rig.model()
        m.urlText = MoodleMock.urlString
        m.cancelConnecting()
        m.connect()
        m.cancelConnecting()
        #expect(m.phase == .editing)
        m.connect()
        await m.waitForConnect()
        m.back()
        #expect(m.phase == .editing && m.urlText == MoodleMock.urlString && m.focus == .url)
        #expect(rig.moodleSources.isEmpty && rig.eventCount == 0)
    }

    @Test("Replace: V10; Save updates the item in place, keeps every Event.id, clears the pause; a Keychain failure keeps the old URL")
    func replace() async throws {
        let secrets = InMemorySecretStore()
        let rig = try MoodleSheetRig(secrets: secrets)
        let first = rig.model()
        first.urlText = MoodleMock.urlString
        first.connect()
        await first.waitForConnect()
        let source = try #require(first.importNow())
        let ids = Set(SyncApplier.events(of: source, in: rig.context).map(\.id))
        source.isAutoSyncPaused = true
        source.state = .unauthorized
        try rig.context.save()

        let m = rig.model(replacing: source)
        #expect(m.title == "Replace the calendar URL" && m.placeholder == "Paste the new URL")
        #expect(m.intro == "Moodle makes a new calendar URL when your FH password changes. In Moodle, choose Get calendar URL again and paste the new one here. Your items and done marks stay.")
        m.urlText = MoodleMock.urlString.replacingOccurrences(of: "userid=4711", with: "userid=4799")
        #expect(m.validationLine == "This URL is for a different Moodle account. To add another account, connect it as a new source.")
        #expect(!m.canConnect)
        let newToken = MoodleMock.urlString.replacingOccurrences(of: "SENTINELb0c7", with: "SENTINELffff")
        m.urlText = newToken
        #expect(m.canConnect)
        m.connect()
        await m.waitForConnect()
        #expect(m.step2Title == "Update Moodle")
        #expect(m.sentences.map(\.text).contains("Items before today are not changed."))
        #expect(!m.sentences.contains { $0.text.hasPrefix("Moodle doesn't tell") || $0.text.contains("history") })

        // A Keychain failure keeps the old URL and writes nothing.
        secrets.failNext("updateFeed")
        #expect(!m.save())
        #expect(m.saveFailure?.body == "Kadence couldn't save the new calendar URL in the Keychain. The old one is still in use. Try again.")
        #expect(try secrets.readFeedURL(sourceID: source.id) == MoodleMock.url && source.isAutoSyncPaused)

        #expect(m.save())
        let saved = try #require(try secrets.readFeedURL(sourceID: source.id))
        saved.withRequestURLString { #expect($0 == newToken) }
        #expect(secrets.feedLabel(sourceID: source.id) == "Kadence — Moodle")
        #expect(!source.isAutoSyncPaused && source.state == .upToDate)
        #expect(Set(SyncApplier.events(of: source, in: rig.context).map(\.id)) == ids)
    }

    @Test("The detail: moodle.technikum-wien.at/…, Every hour; the remove alert's text; removal deletes items, source, Keychain item and its notifications")
    func detailAndRemoval() async throws {
        let rig = try DeadlineRig(now: F.date("2026-10-12 06:00"))
        await rig.scheduler.pass()
        let source = try #require(rig.feed.source)
        #expect(MoodleSourceSettings.urlRow(source) == "moodle.technikum-wien.at/…")
        #expect(SourcesSettingsModel.intervalLabel(source.pollInterval) == "Every hour")
        #expect(SourcesSettingsModel.removalMessage(source) == "Remove “Moodle”?")
        let alert = SourcesSettingsModel.makeRemovalAlert(source, eventCount: 29)
        #expect(alert.informativeText == "Its 29 items — including past ones and anything you marked done — will be removed from your calendar, and its calendar URL deleted from the Keychain. You can connect it again at any time; the items Moodle still lists come back, your done marks don't.")
        #expect(alert.buttons.map(\.title) == ["Cancel", "Remove"])
        #expect(MoodleSourceSettings.keychainFollowUp(name: "Moodle")
                == "The calendar URL for Moodle couldn't be deleted from the Keychain. You can remove the item “Kadence — Moodle” in Keychain Access.")
        #expect(await !rig.centre.pendingByID.keys.filter { $0.hasPrefix("due.") }.isEmpty)

        rig.feed.coordinator.onStateEvent = { rig.scheduler.sourceStateChanged($0) }
        let outcome = try SourcesSettingsModel.remove(source, context: rig.context, secrets: rig.feed.secrets,
                                                      sync: rig.feed.coordinator, state: nil, undo: nil)
        #expect(!outcome.keychainFailed && outcome.removedEventIDs.count == 29)
        #expect(try rig.context.fetchCount(FetchDescriptor<Event>()) == 0)
        #expect(try rig.context.fetch(FetchDescriptor<Source>()).allSatisfy { $0.connection != .icsFeed })
        #expect(rig.feed.secrets.feedSourceIDs.isEmpty)
        await rig.scheduler.pass()
        #expect(await rig.centre.pendingByID.keys.filter { $0.hasPrefix("due.") || $0.hasPrefix("sync.") }.isEmpty)
        // Rename updates the Keychain label (§33.3).
        let other = try MoodleSheetRig()
        let m = other.model()
        m.urlText = MoodleMock.urlString
        m.connect()
        await m.waitForConnect()
        let s = try #require(m.importNow())
        SourcesSettingsModel.rename(s, to: "FH Moodle", context: other.context, secrets: other.secrets)
        #expect((other.secrets as? InMemorySecretStore)?.feedLabel(sourceID: s.id) == "Kadence — FH Moodle")
    }

    @Test("The sidebar's rows: Connect Timetable… and Connect Moodle…, each gone on its own condition; the empty line")
    func sidebarRows() {
        #expect(SidebarSourcesRule.showsConnectTimetableRow([.local, .local]))
        #expect(SidebarSourcesRule.showsConnectMoodleRow([.local, .local]))
        #expect(!SidebarSourcesRule.showsConnectTimetableRow([.local, .caldav]))
        #expect(SidebarSourcesRule.showsConnectMoodleRow([.local, .caldav]))
        #expect(SidebarSourcesRule.showsConnectTimetableRow([.local, .icsFeed]))
        #expect(!SidebarSourcesRule.showsConnectMoodleRow([.local, .icsFeed]))
        #expect(SourcesSettingsModel.emptyLine == "Nothing connected yet.")
        #expect(SourceActionRouting.effect(of: .replaceURL, sourceID: "m", fromPopover: true)
                == .init(sheet: .replaceMoodle(sourceID: "m"), opensSettings: true))
    }

    // MARK: §43 items 1–8, rendered (`-p3ct10`)

    @Test("§43 items 1–8 render from the real views")
    func renders() async throws {
        let suffix = "p3ct10"
        // Item 1: the sidebar, first run, and with the timetable connected.
        for (name, connections) in [("sidebar-first-run", [SourceConnection]()), ("sidebar-timetable-connected", [.caldav])] {
            let view = List {
                Section {
                    if SidebarSourcesRule.showsConnectTimetableRow(connections) { ConnectTimetableRow() }
                    if SidebarSourcesRule.showsConnectMoodleRow(connections) { ConnectTimetableRow(moodle: true) }
                } header: { Text("Sources") }
            }
            .listStyle(.sidebar)
            .environment(SourcesRouter())
            #expect(Slice3Render.render(name, view, size: CGSize(width: 240, height: 110), suffix: suffix) != nil)
        }
        // Items 2 and 7: Settings ▸ Sources, empty and with the Moodle source.
        let empty = try MoodleSheetRig()
        Slice3Render.keep.append(empty.container)
        #expect(Slice3Render.render("settings-sources-empty", settings(empty.container, empty.context),
                                    size: CGSize(width: 720, height: 420), suffix: suffix) != nil)
        for (name, mutate) in [("settings-moodle-uptodate", { (_: Source) in }),
                               ("settings-moodle-unauthorized", { (s: Source) in
                                   s.state = .unauthorized; s.isAutoSyncPaused = true
                                   s.stateDetail = FeedStatusCopy.storedDetail(.unauthorized, SourceStatusPresentation.facts(of: s))
                               }),
                               ("settings-moodle-emptyfeed", { (s: Source) in
                                   s.state = .emptyFeed; s.emptySince = Date().addingTimeInterval(-3600)
                                   var facts = SourceStatusPresentation.facts(of: s); facts.n = 29
                                   s.stateDetail = FeedStatusCopy.storedDetail(.emptyFeed, facts)
                               })] {
            let rig = try MoodleSheetRig()
            Slice3Render.keep.append(rig.container)
            let m = rig.model()
            m.urlText = MoodleMock.urlString
            m.connect()
            await m.waitForConnect()
            let source = try #require(m.importNow())
            source.lastSuccessAt = Date().addingTimeInterval(-300)
            mutate(source)
            try rig.context.save()
            #expect(Slice3Render.render(name, settings(rig.container, rig.context, selected: source.id),
                                        size: CGSize(width: 720, height: 420), suffix: suffix) != nil)
            for text in [MoodleSourceSettings.urlRow(source)]
                + { let p = SourceStatusPresentation(source: source, now: Date()); return [p.title, p.body ?? "", p.statusLine] }() {
                #expect(!F.leaks(text))
            }
        }
        // Items 3–6 and 8: the sheet.
        func sheet(_ name: String, feedCase: MoodleFeedCase = .feedOK, text: String = "", connect: Bool = false,
                   replacing: Bool = false) async throws {
            let rig = try MoodleSheetRig(feedCase: feedCase)
            // A view can be re-evaluated after the render returns: what it
            // observes must outlive it (a released container traps SwiftData).
            Slice3Render.keep.append(rig.container)
            var source: Source?
            if replacing {
                let first = rig.model()
                first.urlText = MoodleMock.urlString
                first.connect()
                await first.waitForConnect()
                source = first.importNow()
            }
            let m = rig.model(replacing: source)
            Slice3Render.keep.append(m)
            m.urlText = text
            if connect { m.connect(); await m.waitForConnect() }
            let view = MoodleSheetContent(model: m, done: { _ in }).frame(width: Tokens.Size.connectSheetWidth)
            #expect(Slice3Render.render(name, view, size: CGSize(width: Tokens.Size.connectSheetWidth, height: 520),
                                        suffix: suffix) != nil)
            for line in strings(m) { #expect(!F.leaks(line)) }
        }
        let url = MoodleMock.urlString
        try await sheet("moodle-sheet-empty")
        try await sheet("moodle-sheet-filled", text: url)
        try await sheet("moodle-sheet-v3", text: url.replacingOccurrences(of: "https://", with: "http://"))
        try await sheet("moodle-sheet-v5", text: "https://moodle.technikum-wien.at/my/")
        try await sheet("moodle-sheet-v6", text: url.replacingOccurrences(of: "&authtoken=SENTINELb0c7a1e2d3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8", with: ""))
        try await sheet("moodle-sheet-v7", text: url.replacingOccurrences(of: "recentupcoming", with: "weeknow"))
        for (name, feedCase) in [("moodle-sheet-unauthorized", MoodleFeedCase.feed401), ("moodle-sheet-notacalendar", .feedHTML),
                                 ("moodle-sheet-feednotfound", .feed404), ("moodle-sheet-offline", .feedOffline)] {
            try await sheet(name, feedCase: feedCase, text: url, connect: true)
        }
        try await sheet("moodle-sheet-step2-feedok", text: url, connect: true)
        try await sheet("moodle-sheet-step2-feednotice", feedCase: .feedNotice, text: url, connect: true)
        try await sheet("moodle-sheet-replace-empty", replacing: true)
        try await sheet("moodle-sheet-replace-v10", text: url.replacingOccurrences(of: "userid=4711", with: "userid=4799"),
                        replacing: true)
        try await sheet("moodle-sheet-replace-step2",
                        text: url.replacingOccurrences(of: "SENTINELb0c7", with: "SENTINELffff"), connect: true, replacing: true)
        // V9: already connected.
        let v9 = try MoodleSheetRig()
        Slice3Render.keep.append(v9.container)
        let first = v9.model()
        first.urlText = url
        first.connect()
        await first.waitForConnect()
        _ = first.importNow()
        let again = v9.model()
        Slice3Render.keep.append(again)
        again.urlText = url
        #expect(again.validationLine == "This Moodle account is already connected as Moodle.")
        #expect(Slice3Render.render("moodle-sheet-v9", MoodleSheetContent(model: again, done: { _ in }),
                                    size: CGSize(width: Tokens.Size.connectSheetWidth, height: 520), suffix: suffix) != nil)
        // Item 5: step 1 connecting — the real model in its connecting phase
        // (a fetch held open would need a wall-clock wait, run rule 9).
        let connectingRig = try MoodleSheetRig()
        Slice3Render.keep.append(connectingRig.container)
        let connecting = connectingRig.model()
        Slice3Render.keep.append(connecting)
        connecting.urlText = url
        connecting.phase = .connecting
        #expect(Slice3Render.render("moodle-sheet-connecting", MoodleSheetContent(model: connecting, done: { _ in }),
                                    size: CGSize(width: Tokens.Size.connectSheetWidth, height: 520), suffix: suffix) != nil)
    }

    private func settings(_ container: ModelContainer, _ context: ModelContext, selected: String? = nil) -> some View {
        let coordinator = SyncCoordinator(context: context, secrets: InMemorySecretStore(), scheduling: FakeScheduling(),
                                          path: FakePath(), makeFeedTransport: { MockFeedTransport(case: .feedOffline) },
                                          makeSource: { _ in RefusingScheduleSource() })
        let router = SourcesRouter()
        router.selectedSourceID = selected
        Slice3Render.keep += [container, coordinator, router]
        return SourcesSettingsView()
            .environment(coordinator)
            .environment(router)
            .environment(CalendarState())
            .environment(UndoStack())
            .modelContainer(container)
    }
}
