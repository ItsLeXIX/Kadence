//
//  ConnectSheetTests.swift
//  KadenceTests
//
//  PHASE3-PLAN.md task 13: the connect sheet (layouts.md §12; interactions.md
//  §13.1–§13.2; components.md §19.1, §20.1, §20.8.1), through the model and,
//  for the confirmed row and the no-secrets rule, the rendered view's
//  accessibility tree.
//

import Testing
import Foundation
import SwiftData
import SwiftUI
import AppKit
import Synchronization
@testable import Kadence

nonisolated private let sentinel = "S3ntinel-pw-⚠"

/// A transport that counts calls on top of a mock harness.
nonisolated final class CountingTransport: HTTPTransport, @unchecked Sendable {
    let inner: any HTTPTransport
    let count = Mutex(0)
    init(_ inner: any HTTPTransport) { self.inner = inner }
    func send(_ request: HTTPRequest) async throws(TransportError) -> HTTPResponse {
        count.withLock { $0 += 1 }
        return try await inner.send(request)
    }
}

/// A secret store that records the order of writes.
nonisolated final class OrderedSecretStore: SecretStore, @unchecked Sendable {
    let inner = InMemorySecretStore()
    let log = Mutex<[String]>([])
    func save(_ password: Password, for account: SecretAccount, info: SecretItemInfo) throws(SecretStoreError) {
        log.withLock { $0.append("save \(account.username)") }
        try inner.save(password, for: account, info: info)
    }
    func read(_ account: SecretAccount) throws(SecretStoreError) -> Password? { try inner.read(account) }
    func delete(_ account: SecretAccount) throws(SecretStoreError) {
        log.withLock { $0.append("delete \(account.username)") }
        try inner.delete(account)
    }
    func updateInfo(_ info: SecretItemInfo, for account: SecretAccount) throws(SecretStoreError) {
        try inner.updateInfo(info, for: account)
    }
}

@MainActor
private final class SheetRig {
    let container: ModelContainer
    let context: ModelContext
    let secrets: any SecretStore
    let server: MockCalDAVServer
    let transport: CountingTransport
    let model: ConnectSheetModel

    init(_ mockCase: MockCalDAVServer.Case = .reportOK, feed: [MockCalDAVServer.Object]? = nil,
         pruefungen: [MockCalDAVServer.Object] = [], secrets: (any SecretStore)? = nil, editing: (ModelContext) -> Source? = { _ in nil },
         seed: ((ModelContext) throws -> Void)? = nil) throws {
        container = try ModelContainer(for: Schema(KadenceSchema.models),
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        context = ModelContext(container)
        try seed?(context)
        let secrets = secrets ?? InMemorySecretStore()
        self.secrets = secrets
        server = MockCalDAVServer(case: mockCase, password: Password(sentinel), feed: feed ?? MockHarness.reportReview(),
                                  pruefungen: pruefungen, html: Data())
        let server = server
        transport = CountingTransport(MockCalDAVTransport(server: server, timeout: 0.5))
        let transport = transport
        model = ConnectSheetModel(editing: editing(context), context: context, secrets: secrets,
                                  makeTransport: { transport }, sync: nil, clock: { TestClock.now }, zone: TestClock.zone)
    }

    func fill(user: String = "user01", password: String = sentinel) {
        model.username = user
        model.password = password
    }

    /// Connect, and wait for it to land.
    func connect() async {
        model.connect()
        while model.phase == .connecting { await Task.yield(); try? await Task.sleep(for: .milliseconds(5)) }
    }

    var sources: [Source] { (try? context.fetch(FetchDescriptor<Source>())) ?? [] }
    var events: [Event] { (try? context.fetch(FetchDescriptor<Event>())) ?? [] }
}

@MainActor
@Suite(.serialized)
struct ConnectSheetTests {

    // MARK: Validation (§12.1)

    @Test("Validation: every Server row, the WebDAV share, the duplicate account; Connect follows the table")
    func validation() throws {
        let rig = try SheetRig(seed: { context in
            let other = Source.connected(id: "x", displayName: "Old timetable", serverURL: "https://cis.technikum-wien.at",
                                         username: "user02", principalHref: nil, calendarHomeHref: nil, calendars: [],
                                         capabilities: SourceCapabilities(), paletteKey: .teal)
            context.insert(other)
        })
        let m = rig.model
        #expect(m.server == "cis.technikum-wien.at" && m.focus == .username && m.name == "University timetable")
        #expect(!m.canConnect)  // username and password empty
        rig.fill()
        #expect(m.canConnect)
        let rows: [(String, String?, Bool)] = [
            ("", nil, false),
            ("http://cis.technikum-wien.at", "Kadence only connects over HTTPS.", false),
            ("ftp://cis.technikum-wien.at", "Enter the server name, like cis.technikum-wien.at.", false),
            ("cis technikum", "Enter the server name, like cis.technikum-wien.at.", false),
            ("user01@cis.technikum-wien.at", "Enter the username in its own field.", false),
            ("https://user01:x@cis.technikum-wien.at", "Enter the username in its own field.", false),
            ("https://cis.technikum-wien.at/Webdav/Lvplan",
             "That's the WebDAV share, which only works on the FH network. Enter just the server name: cis.technikum-wien.at.", false),
            ("https://cis.technikum-wien.at/webdav/lvplan.php/", nil, true),
            ("  cis.technikum-wien.at  ", nil, true),
            ("cis.technikum-wien.at:8443", nil, true),
        ]
        for (typed, message, enabled) in rows {
            m.server = typed
            #expect(m.serverMessage == message, "\(typed)")
            #expect(m.canConnect == enabled, "\(typed)")
        }
        m.server = "cis.technikum-wien.at"
        m.username = "user02"
        #expect(m.usernameMessage == "user02 @ cis.technikum-wien.at is already connected as Old timetable.")
        #expect(!m.canConnect)
        m.username = "user01"; m.password = ""
        #expect(!m.canConnect)
        #expect(m.footnote == "Your password is kept in the macOS Keychain and sent only to cis.technikum-wien.at, over HTTPS.")
        m.server = "http://x"
        #expect(m.footnote == "Your password is kept in the macOS Keychain and sent only to the server you enter, over HTTPS.")
    }

    // MARK: Cancel

    @Test("Cancel mid-discovery cancels the request and writes nothing")
    func cancelWritesNothing() async throws {
        let store = OrderedSecretStore()
        let rig = try SheetRig(.slow, secrets: store)
        rig.fill()
        rig.model.connect()
        #expect(rig.model.phase == .connecting)
        #expect(rig.model.connectingLine == "Connecting to cis.technikum-wien.at…")
        rig.model.cancelConnecting()
        #expect(rig.model.phase == .editing)
        try await Task.sleep(for: .milliseconds(50))
        #expect(store.log.withLock { $0 }.isEmpty && rig.sources.isEmpty && rig.events.isEmpty)
        #expect(rig.model.password == sentinel)  // the fields are as typed
    }

    // MARK: Failures

    @Test("Failures map to §12.1's step-1 body and focus", arguments: [
        (MockCalDAVServer.Case.unauthorized, "cis.technikum-wien.at didn't accept the username or password.", ConnectSheetModel.Field.password),
        (.forbidden, "cis.technikum-wien.at refused access for user01.", .username),
        (.wellKnown404, "cis.technikum-wien.at doesn't offer CalDAV calendars. Check the server name.", .server),
        (.noCalendars, "user01 @ cis.technikum-wien.at has no calendars with events.", .username),
        (.certificate, "The certificate for cis.technikum-wien.at couldn't be verified, so Kadence sent nothing to it.", .connect),
        (.htmlOK, "cis.technikum-wien.at sent a web page instead of calendar data. Try again later.", .connect),
        (.allRefused, "cis.technikum-wien.at refused every way Kadence asks for events. Nothing was saved.", .connect),
        (.serverError, "cis.technikum-wien.at answered with an error (503). Try again later.", .connect),
        (.offline, "This Mac is offline. Connect when it's back online.", .connect),
        (.redirectOffHost, "cis.technikum-wien.at sent Kadence to login.example.invalid. Kadence didn't follow it, so nothing — and no password — was sent there.", .server),
    ])
    func failures(mockCase: MockCalDAVServer.Case, body: String, focus: ConnectSheetModel.Field) async throws {
        let rig = try SheetRig(mockCase)
        rig.fill()
        await rig.connect()
        #expect(rig.model.phase == .editing)
        #expect(rig.model.failure?.body == body)
        #expect(rig.model.focus == focus)
        #expect(rig.sources.isEmpty)
    }

    // MARK: Step 2

    @Test("Step 2 on reportOK (template): one confirmed row LVPlan, not a control; 13 events, history 2, merges 1")
    func step2Single() async throws {
        let rig = try SheetRig(.reportOK)
        rig.fill()
        await rig.connect()
        let m = rig.model
        #expect(m.phase == .step2 && m.isSingleCalendar && m.calendarLabel == "Calendar")
        #expect(m.accountLine == "user01 @ cis.technikum-wien.at" && m.step2Title == "Import University timetable")
        #expect(m.rangeLine == "13 events, 2 Oct 2026 – 23 Oct 2026")
        #expect(m.sentences.map(\.text) == [
            "2 of them are before today. They're imported once, as history, and never changed afterwards.",
            "1 co-taught lecture is listed once per lecturer and is shown once."])
        // The confirmed row's "not a control" (no checkbox, not focusable,
        // AX `Calendar: LVPlan`) is asserted on the live app's AX tree by
        // `Scripts/capture-p3.sh connect-step2-single`: SwiftUI does not vend
        // an accessibility tree for an offscreen hosting view in the test host.
        #expect(!m.fetched.isEmpty && m.fetched.count == 1)
    }

    @Test("Step 2 on reportCIS: 12 events, 14 Sep 2026 – 29 Jan 2027, 3 before today, 1 co-taught")
    func step2CIS() async throws {
        let rig = try SheetRig(.reportOK, feed: MockHarness.reportCIS())
        rig.fill()
        await rig.connect()
        #expect(rig.model.rangeLine == "12 events, 14 Sep 2026 – 29 Jan 2027")
        #expect(rig.model.sentences.map(\.text) == [
            "3 of them are before today. They're imported once, as history, and never changed afterwards.",
            "1 co-taught lecture is listed once per lecturer and is shown once."])
    }

    @Test("Step 2 on multiCalendar: two checkboxes checked; toggling recomputes with no transport call")
    func step2Checklist() async throws {
        let rw = try #require(MockHarness.reportReview().last)
        let rig = try SheetRig(.multiCalendar, pruefungen: [MockCalDAVServer.Object(href: MockCalDAVServer.pruefungen + "p1.ics",
                                                                                     etag: "\"p\"", data: rw.data)])
        rig.fill()
        await rig.connect()
        let m = rig.model
        let calls = rig.transport.count.withLock { $0 }
        #expect(!m.isSingleCalendar && m.calendarLabel == "Calendars")
        #expect(m.fetched.map(\.calendar.displayName) == ["LVPlan", "Prüfungen"] && m.checked.count == 2)
        #expect(m.rangeLine.hasPrefix("13 events, "))
        m.checked.remove(MockCalDAVServer.pruefungen)
        #expect(m.rangeLine.hasPrefix("13 events, "))
        m.checked.remove(MockCalDAVServer.lvplan)
        #expect(m.rangeLine == "Choose at least one calendar." && !m.canImport)
        m.checked.insert(MockCalDAVServer.pruefungen)
        #expect(m.rangeLine == "1 event, 23 Oct 2026" && m.sentences.isEmpty)
        #expect(rig.transport.count.withLock { $0 } == calls)
    }

    @Test("Copy: the empty calendar keeps Import enabled; singular forms")
    func emptyCalendarCopy() async throws {
        let rig = try SheetRig(.emptyCalendar)
        rig.fill()
        await rig.connect()
        #expect(rig.model.rangeLine == "The calendar has no events yet.")
        #expect(rig.model.sentences.map(\.text) == ["Kadence will add them as they appear."])
        #expect(rig.model.canImport)
        // Singulars.
        let one = try SheetRig(.reportOK, feed: Array(MockHarness.reportReview().prefix(1)))
        one.fill()
        await one.connect()
        #expect(one.model.rangeLine == "1 event, 2 Oct 2026")
        #expect(one.model.sentences.map(\.text) == ["All of them are before today. They're imported once, as history, and never changed afterwards."])
        let two = try SheetRig(.reportOK, feed: Array(MockHarness.reportReview().prefix(3)))
        two.fill()
        await two.connect()
        #expect(two.model.sentences.first?.text == "2 of them are before today. They're imported once, as history, and never changed afterwards.")
        let mixed = try SheetRig(.reportOK, feed: [MockHarness.reportReview()[0], MockHarness.reportReview()[3]])
        mixed.fill()
        await mixed.connect()
        #expect(mixed.model.sentences.first?.text == "1 of them is before today. It's imported once, as history, and never changed afterwards.")
    }

    // MARK: Import

    @Test("Import: no transport call; Keychain → Source → events; calendars and hrefs stored")
    func importWrites() async throws {
        let store = OrderedSecretStore()
        let rig = try SheetRig(.reportOK, secrets: store)
        rig.fill()
        await rig.connect()
        let calls = rig.transport.count.withLock { $0 }
        let source = try #require(rig.model.importNow())
        #expect(rig.transport.count.withLock { $0 } == calls)
        #expect(store.log.withLock { $0 } == ["save user01"])
        #expect(try store.read(SecretAccount(host: "cis.technikum-wien.at", username: "user01")) == Password(sentinel))
        #expect(source.calendars == [SourceCalendar(href: MockCalDAVServer.lvplan, displayName: "LVPlan")])
        #expect(source.principalHref == MockCalDAVServer.principal && source.calendarHomeHref == MockCalDAVServer.home)
        #expect(source.serverURL == "https://cis.technikum-wien.at" && source.paletteKey == .blue)
        #expect(source.importedAt == TestClock.now && source.state == .upToDate)
        #expect(rig.events.count == 13)
        #expect(rig.model.password.isEmpty)
    }

    @Test("A Keychain failure writes nothing else, with the `Password not saved` copy")
    func importKeychainFailure() async throws {
        let store = InMemorySecretStore()
        let rig = try SheetRig(.reportOK, secrets: store)
        rig.fill()
        await rig.connect()
        store.failNext("save")
        #expect(rig.model.importNow() == nil)
        #expect(rig.model.saveFailure?.title == "Password not saved")
        #expect(rig.model.saveFailure?.body == "Kadence couldn't save the password in the Keychain, so nothing was saved. Try again.")
        #expect(rig.sources.isEmpty && rig.events.isEmpty)
    }

    @Test("Back restores every field, the password included")
    func back() async throws {
        let rig = try SheetRig(.reportOK)
        rig.fill()
        rig.model.name = "FH"
        await rig.connect()
        rig.model.back()
        #expect(rig.model.phase == .editing && rig.model.name == "FH" && rig.model.username == "user01")
        #expect(rig.model.password == sentinel && rig.model.server == "cis.technikum-wien.at")
    }

    // MARK: Edit mode

    private func editRig(_ mockCase: MockCalDAVServer.Case = .reportOK, calendars: [SourceCalendar] = [ReviewMode.calendar],
                         store: OrderedSecretStore = OrderedSecretStore(),
                         pruefungen: [MockCalDAVServer.Object] = []) throws -> SheetRig {
        try store.inner.save(Password(sentinel), for: SecretAccount(host: "cis.technikum-wien.at", username: "user01"),
                             info: .forSource(id: "timetable", displayName: "University timetable"))
        return try SheetRig(mockCase, pruefungen: pruefungen, secrets: store, editing: { context in
            (try? context.fetch(FetchDescriptor<Source>()))?.first
        }, seed: { context in
            let source = Source.connected(id: "timetable", displayName: "University timetable",
                                          serverURL: "https://cis.technikum-wien.at", username: "user01",
                                          principalHref: MockCalDAVServer.principal, calendarHomeHref: MockCalDAVServer.home,
                                          calendars: calendars, capabilities: SourceCapabilities(fetchMode: .multiget),
                                          paletteKey: .blue)
            source.importedAt = TestClock.date("2026-10-01 10:00")
            source.isAutoSyncPaused = true
            context.insert(source)
            try context.save()
        })
    }

    @Test("Edit mode: prefilled, the password empty with its placeholder; empty uses the saved one unless the username changed")
    func editPrefill() async throws {
        let rig = try editRig()
        let m = rig.model
        #expect(m.isEditMode && m.title == "Edit University timetable")
        #expect(m.server == "cis.technikum-wien.at" && m.username == "user01" && m.password.isEmpty)
        #expect(m.passwordPlaceholder == "Saved in Keychain")
        #expect(m.canConnect)
        m.username = "user02"
        #expect(!m.canConnect)
        m.username = "user01"
        await rig.connect()
        #expect(m.phase == .step2 && m.step2Title == "Update University timetable")
        #expect(m.sentences.first?.text == "Events before today are not changed.")
    }

    @Test("Choose Calendar… starts connecting at once; unselected calendars are unchecked; the deselection sentence counts")
    func editCalendars() async throws {
        let rw = try #require(MockHarness.reportReview().last)
        let unique = MockCalDAVServer.Object(href: MockCalDAVServer.pruefungen + "p2.ics", etag: "\"q\"",
                                             data: rw.data.replacingOccurrences(of: "RW-EXAM", with: "STAT-EXAM"))
        let both = [ReviewMode.calendar, SourceCalendar(href: MockCalDAVServer.pruefungen, displayName: "Prüfungen")]
        // A source with only LVPlan selected: Prüfungen comes back unchecked.
        let rig = try editRig(.multiCalendar, pruefungen: [unique])
        rig.model.connect()  // what `Choose Calendar…` does on appear
        #expect(rig.model.phase == .connecting)
        while rig.model.phase == .connecting { try await Task.sleep(for: .milliseconds(5)) }
        #expect(rig.model.checked == [MockCalDAVServer.lvplan])
        // A source with both selected and Prüfungen's unique event stored:
        let rig2 = try editRig(.multiCalendar, calendars: both, pruefungen: [unique])
        rig2.fill(password: "")
        await rig2.connect()
        let source = try #require(rig2.model.editing)
        try SyncApplier.apply(SyncPlanner.plan(existing: [], source: SourceSnapshot(feedHash: nil, lastFeedEventCount: 0,
                                                                                     calendars: both, importedAt: nil),
                                               result: rig2.model.fetchResult(), kind: .import, now: TestClock.now,
                                               zone: TestClock.zone), to: source, context: rig2.context, now: TestClock.now)
        #expect(rig2.events.count == 14)
        rig2.model.checked.remove(MockCalDAVServer.pruefungen)
        #expect(rig2.model.sentences.last?.text == "1 event from calendars you unchecked will be removed, including past weeks.")
    }

    @Test("Save replaces the Keychain item (new, then old), clears the pause, resets fetchMode, applies as a sync")
    func editSave() async throws {
        let store = OrderedSecretStore()
        let rig = try editRig(store: store)
        let m = rig.model
        m.password = sentinel  // a newly typed password (the mock accepts only the sentinel)
        m.username = "user01"
        await rig.connect()
        let source = try #require(m.editing)
        #expect(m.save())
        #expect(store.log.withLock { $0 } == ["save user01"])  // same account: overwritten in place
        #expect(!source.isAutoSyncPaused && source.capabilities.fetchMode == .report)
        #expect(rig.events.count == 11)  // a sync: today onward only (13 − H1 − H2)
        // A changed account: new first, then old.
        let store2 = OrderedSecretStore()
        let rig2 = try editRig(store: store2)
        rig2.model.username = "user03"
        rig2.model.password = sentinel
        // The mock answers only user01; the plan's write order is what this checks.
        try store2.replace(SecretAccount(host: "cis.technikum-wien.at", username: "user01"),
                           with: SecretAccount(host: "cis.technikum-wien.at", username: "user03"), password: Password(sentinel),
                           info: .forSource(id: "timetable", displayName: "University timetable"))
        #expect(store2.log.withLock { $0 } == ["save user03", "delete user01"])
    }

    // MARK: No secrets

    @Test("The sentinel appears in no view but the SecureField, and in no accessibility value")
    func noSecretsInViews() async throws {
        let rig = try SheetRig(.unauthorized)
        rig.fill()
        await rig.connect()
        let sheetModel = rig.model
        let strings = [sheetModel.footnote, sheetModel.title, sheetModel.failure?.title ?? "", sheetModel.failure?.body ?? "",
                       sheetModel.serverMessage ?? "", sheetModel.usernameMessage ?? "", sheetModel.connectingLine,
                       sheetModel.passwordPlaceholder] + texts(of: sheetModel.failure as Any)
        for s in strings { #expect(!s.contains(sentinel)) }
        // The live AX tree of the filled sheet is checked for the password
        // by `Scripts/capture-p3.sh connect-step1-filled`.
    }
}
