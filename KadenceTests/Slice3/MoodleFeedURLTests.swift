//
//  MoodleFeedURLTests.swift
//  KadenceTests
//
//  PHASE3-SLICE3-PLAN.md task 2 — components.md §33.1–§33.5: validation V1–
//  V11, the redacted type, and the Keychain's generic-password item. Only the
//  mock URL (§43.1) appears here; nothing calls Security.
//

import Testing
import Foundation
import Security
import SwiftData
@testable import Kadence

/// The mock URL with one part changed, for the rows that need a variant.
private func mock(_ edit: (String) -> String) -> String { edit(MoodleMock.urlString) }

private func message(_ input: String, others: [MoodleFeedURL.Connected] = [],
                     replacing: MoodleFeedURL? = nil) -> String? {
    MoodleFeedURL.validate(input, others: others, replacing: replacing).line
}

private func valid(_ input: String) throws -> MoodleFeedURL {
    guard case .valid(let url) = MoodleFeedURL.validate(input) else {
        Issue.record("not valid")
        throw CancellationError()
    }
    return url
}

@MainActor
struct MoodleFeedURLTests {

    @Test("V1–V11 row by row: exact messages, and Connect only on V11")
    func rows() throws {
        typealias M = MoodleFeedURL.Message
        // V1
        #expect(MoodleFeedURL.validate("") == .empty)
        #expect(MoodleFeedURL.validate("   \n") == .empty)
        #expect(!MoodleFeedURL.validate("").canConnect && MoodleFeedURL.validate("").line == nil)
        // V2: not a URL, no host, another scheme.
        for text in ["hello", "moodle.technikum-wien.at/calendar/export_execute.php?userid=1", "https://",
                     "ftp://moodle.technikum-wien.at/calendar/export_execute.php"] {
            #expect(message(text) == M.notAURL, "\(text)")
        }
        #expect(M.notAURL == "Paste the calendar URL from Moodle. It starts with https://.")
        // V3
        #expect(message(mock { $0.replacingOccurrences(of: "https://", with: "http://") })
                == "Kadence only connects over HTTPS.")
        // V4: user info.
        #expect(message(mock { $0.replacingOccurrences(of: "https://", with: "https://user@") }) == M.notAURL)
        #expect(message(mock { $0.replacingOccurrences(of: "https://", with: "https://user:pass@") }) == M.notAURL)
        // V5: another path; case-sensitive; no trailing slash.
        let wrongPath = "That isn't the calendar URL. In Moodle, choose Get calendar URL and copy the address it shows."
        #expect(message("https://moodle.technikum-wien.at/my/") == wrongPath)
        #expect(message(mock { $0.replacingOccurrences(of: "export_execute.php", with: "Export_Execute.php") }) == wrongPath)
        #expect(message(mock { $0.replacingOccurrences(of: "export_execute.php", with: "export_execute.php/") }) == wrongPath)
        // V6: no `authtoken`, an empty `userid`.
        let incomplete = "The URL is missing part of its address. Copy the whole URL from Moodle again."
        #expect(message(mock { $0.replacingOccurrences(of: "&authtoken=SENTINELb0c7a1e2d3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8", with: "") }) == incomplete)
        #expect(message(mock { $0.replacingOccurrences(of: "userid=4711", with: "userid=") }) == incomplete)
        // V7: absent or a fixed period.
        let fixed = "This URL exports a fixed period. In Moodle, choose Recent and upcoming, then Get calendar URL."
        #expect(message(mock { $0.replacingOccurrences(of: "recentupcoming", with: "weeknow") }) == fixed)
        #expect(message(mock { $0.replacingOccurrences(of: "&preset_time=recentupcoming", with: "") }) == fixed)
        // V8: absent or another scope.
        let some = "This URL exports only some of your events. In Moodle, choose All events, then Get calendar URL."
        #expect(message(mock { $0.replacingOccurrences(of: "preset_what=all", with: "preset_what=user") }) == some)
        #expect(message(mock { $0.replacingOccurrences(of: "preset_what=all&", with: "") }) == some)
        // V11: the two parsed-line forms; Connect enabled.
        let all = MoodleFeedURL.validate(MoodleMock.urlString)
        #expect(all.canConnect)
        #expect(all.line == "moodle.technikum-wien.at/… · All events, recent and upcoming")
        #expect(message(mock { $0.replacingOccurrences(of: "preset_what=all", with: "preset_what=courses") })
                == "moodle.technikum-wien.at/… · Course events, recent and upcoming")
    }

    @Test("Row order: an http:// page URL gets V3, not V5; http + user info gets V3")
    func order() {
        #expect(message("http://moodle.technikum-wien.at/my/") == "Kadence only connects over HTTPS.")
        #expect(message("http://user@moodle.technikum-wien.at/my/") == "Kadence only connects over HTTPS.")
        // V5 before V6: a page with no query at all.
        #expect(message("https://moodle.technikum-wien.at/calendar/view.php")?.hasPrefix("That isn't") == true)
    }

    @Test("webcal:// reads as https; whitespace trimmed; query order, extra parameters and their case irrelevant; host lower-cased")
    func normalisation() throws {
        let webcal = try valid(mock { $0.replacingOccurrences(of: "https://", with: "webcal://") })
        let plain = try valid(MoodleMock.urlString)
        #expect(webcal == plain)
        webcal.withRequestURLString { #expect($0 == MoodleMock.urlString) }
        #expect(try valid("  \(MoodleMock.urlString)\n") == plain)

        let reordered = "https://moodle.technikum-wien.at/calendar/export_execute.php?preset_time=recentupcoming&lang=en&preset_what=all&authtoken=SENTINELb0c7a1e2d3f4a5b6c7d8e9f0a1b2c3d4e5f6a7b8&userid=4711"
        let r = try valid(reordered)
        #expect(r.isSameAccount(as: plain) && r.scope == .all)
        // Stored exactly as pasted after the authority.
        r.withRequestURLString { #expect($0 == reordered) }
        let shouty = try valid(mock { $0.replacingOccurrences(of: "preset_time=recentupcoming", with: "PRESET_TIME=RecentUpcoming")
            .replacingOccurrences(of: "moodle.technikum-wien.at", with: "Moodle.Technikum-Wien.AT") })
        #expect(shouty.host == "moodle.technikum-wien.at")
        #expect(shouty.parsedLine == "moodle.technikum-wien.at/… · All events, recent and upcoming")
        shouty.withRequestURLString { #expect($0.hasPrefix("https://moodle.technikum-wien.at/calendar/export_execute.php?")) }
        shouty.withRequestURLString { #expect($0.contains("PRESET_TIME=RecentUpcoming")) }
    }

    @Test("V9 against two stored sources, one unreadable and skipped; this source excluded in Replace; V10 in Replace")
    func sameAccount() throws {
        let container = try ModelContainer(for: Schema(KadenceSchema.models),
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let secrets = InMemorySecretStore()
        let url = try valid(MoodleMock.urlString)
        let other = try valid(mock { $0.replacingOccurrences(of: "userid=4711", with: "userid=4712") })
        func source(_ id: String, _ name: String) -> Source {
            let s = Source(id: id, kind: .coursework, connection: .icsFeed, displayName: name, paletteKey: .teal)
            s.feedProfile = .moodle
            context.insert(s)
            return s
        }
        let a = source("a", "Moodle"), b = source("b", "Moodle 2")
        try secrets.saveFeedURL(url, sourceID: a.id, label: feedItemLabel(displayName: a.displayName))
        // b has no readable item: skipped.
        var others = MoodleFeedURL.connected([a, b], secrets: secrets)
        #expect(others.map(\.name) == ["Moodle"])
        #expect(message(MoodleMock.urlString, others: others) == "This Moodle account is already connected as Moodle.")
        // Another account on the same host is V11.
        #expect(MoodleFeedURL.validate(mock { $0.replacingOccurrences(of: "userid=4711", with: "userid=4712") },
                                       others: others) == .valid(other))
        // An item that fails to read is skipped too.
        try secrets.saveFeedURL(other, sourceID: b.id, label: "Kadence — Moodle 2")
        secrets.failNext("readFeed")
        others = MoodleFeedURL.connected([a, b], secrets: secrets)
        #expect(others.map(\.name) == ["Moodle 2"])

        // Replace a: a itself is excluded from V9; the same account is V11.
        others = MoodleFeedURL.connected([a, b], secrets: secrets, excluding: a.id)
        #expect(others.map(\.name) == ["Moodle 2"])
        let newToken = mock { $0.replacingOccurrences(of: "SENTINELb0c7", with: "SENTINELffff") }
        #expect(MoodleFeedURL.validate(newToken, others: others, replacing: url).canConnect)
        // V10: another userid, or another host.
        let tenth = "This URL is for a different Moodle account. To add another account, connect it as a new source."
        let fourth = mock { $0.replacingOccurrences(of: "userid=4711", with: "userid=4713") }
        #expect(message(fourth, others: others, replacing: url) == tenth)
        let host = mock { $0.replacingOccurrences(of: "moodle.technikum-wien.at", with: "moodle.example.invalid") }
        #expect(message(host, others: others, replacing: url) == tenth)
        // V9 comes before V10: b's account pasted while replacing a.
        #expect(message(mock { $0.replacingOccurrences(of: "userid=4711", with: "userid=4712") }, others: others,
                        replacing: url) == "This Moodle account is already connected as Moodle 2.")
    }

    @Test("The redacted type: interpolation, describing, reflecting, debugDescription and dump give the display form")
    func redacted() throws {
        let url = try valid(MoodleMock.urlString)
        #expect("\(url)" == "moodle.technikum-wien.at/…")
        #expect(String(describing: url) == "moodle.technikum-wien.at/…")
        #expect(String(reflecting: url) == "moodle.technikum-wien.at/…")
        #expect(url.debugDescription == "moodle.technikum-wien.at/…")
        var dumped = ""
        dump(url, to: &dumped)
        #expect(dumped == "- moodle.technikum-wien.at/…\n")
        var dumpedValidation = ""
        dump(MoodleFeedURL.validate(MoodleMock.urlString), to: &dumpedValidation)
        #expect(Mirror(reflecting: url).children.isEmpty)
        for text in [dumped, dumpedValidation, "\(MoodleFeedURL.validate(MoodleMock.urlString))", url.parsedLine] {
            for marker in MoodleMock.leakMarkers { #expect(!text.contains(marker), "\(text)") }
        }
        // `userid` is a field, but never in any text the type produces.
        #expect(url.userID == "4711")
    }

    @Test("Source scan: the raw accessor is used only by the feed transport; the Keychain bytes only by KeychainSecretStore")
    func rawAccessorCallSites() throws {
        let root = Fixture.repoRoot.appendingPathComponent("Kadence")
        var request: [String] = [], keychain: [String] = []
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        while let url = files?.nextObject() as? URL {
            guard url.pathExtension == "swift", url.lastPathComponent != "MoodleFeedURL.swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            for (n, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
                let code = line.split(separator: "//", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
                if code.contains(".withRequestURLString") { request.append("\(url.lastPathComponent):\(n + 1)") }
                if code.contains(".keychainValue") { keychain.append("\(url.lastPathComponent):\(n + 1)") }
            }
        }
        // P3S3-T02: no transport yet — task 5 adds the one call site, in
        // `MoodleFeedTransport.swift`.
        #expect(request.allSatisfy { $0.hasPrefix("MoodleFeedTransport.swift:") } && request.count <= 1, "\(request)")
        #expect(!keychain.isEmpty && keychain.allSatisfy { $0.hasPrefix("SecretStore.swift:") }, "\(keychain)")
    }

    @Test("§33.3: the Keychain feed item's query dictionaries, built without calling Security")
    func keychainAttributes() throws {
        let url = try valid(MoodleMock.urlString)
        let save = KeychainSecretStore.feedSaveQuery(url, sourceID: "S-1", label: feedItemLabel(displayName: "Moodle"))
        #expect(save[kSecClass as String] as? String == kSecClassGenericPassword as String)
        #expect(save[kSecAttrService as String] as? String == "XIX.Kadence.feed")
        #expect(save[kSecAttrAccount as String] as? String == "S-1")
        #expect(save[kSecAttrLabel as String] as? String == "Kadence — Moodle")
        #expect(save[kSecAttrDescription as String] as? String == "Calendar URL")
        #expect(save[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlock as String)
        #expect(save[kSecAttrSynchronizable as String] as? Bool == false)
        #expect(save[kSecValueData as String] as? Data == Data(MoodleMock.urlString.utf8))
        #expect(save.count == 8)
        // Every query carries service and account.
        for query in [KeychainSecretStore.feedReadQuery(sourceID: "S-1"), KeychainSecretStore.feedIdentity(sourceID: "S-1")] {
            #expect(query[kSecAttrService as String] as? String == "XIX.Kadence.feed")
            #expect(query[kSecAttrAccount as String] as? String == "S-1")
            #expect(query[kSecClass as String] as? String == kSecClassGenericPassword as String)
        }
        let read = KeychainSecretStore.feedReadQuery(sourceID: "S-1")
        #expect(read[kSecReturnData as String] as? Bool == true)
        #expect(read[kSecValueData as String] == nil)
        // Replace's in-place update changes the value only.
        let changes = KeychainSecretStore.feedUpdateChanges(url)
        #expect(Array(changes.keys) == [kSecValueData as String])
        // The value reads back as the same URL.
        #expect(MoodleFeedURL(keychainValue: url.keychainValue) == url)
        #expect(MoodleFeedURL(keychainValue: Data("https://example.invalid/".utf8)) == nil)
    }

    @Test("In-memory store: write, read, update in place (label kept), delete — by Source.id")
    func inMemory() throws {
        let secrets = InMemorySecretStore()
        let url = try valid(MoodleMock.urlString)
        let replaced = try valid(mock { $0.replacingOccurrences(of: "SENTINELb0c7", with: "SENTINELffff") })
        #expect(try secrets.readFeedURL(sourceID: "S-1") == nil)
        #expect(throws: SecretStoreError.self) { try secrets.updateFeedURL(url, sourceID: "S-1") }
        try secrets.saveFeedURL(url, sourceID: "S-1", label: "Kadence — Moodle")
        #expect(try secrets.readFeedURL(sourceID: "S-1") == url)
        try secrets.updateFeedURL(replaced, sourceID: "S-1")
        #expect(try secrets.readFeedURL(sourceID: "S-1") == replaced)
        #expect(secrets.feedLabel(sourceID: "S-1") == "Kadence — Moodle")
        try secrets.updateFeedLabel("Kadence — FH Moodle", sourceID: "S-1")
        #expect(secrets.feedLabel(sourceID: "S-1") == "Kadence — FH Moodle")
        secrets.failNext("updateFeed")
        #expect(throws: SecretStoreError.injected) { try secrets.updateFeedURL(url, sourceID: "S-1") }
        #expect(try secrets.readFeedURL(sourceID: "S-1") == replaced)
        try secrets.deleteFeedURL(sourceID: "S-1")
        #expect(try secrets.readFeedURL(sourceID: "S-1") == nil)
        // The password kind is separate.
        #expect(secrets.accounts.isEmpty && secrets.feedSourceIDs.isEmpty)
    }
}
