//
//  SecretStoreTests.swift
//  KadenceTests
//
//  PHASE3-PLAN.md task 2: `SecretStore` (components.md §21.4). Query
//  dictionaries are asserted without touching the Keychain; the real-Keychain
//  tests use the throwaway account `user01-tests`, delete what they write, and
//  skip (not fail) when the Keychain is unavailable to the test host.
//

import Testing
import Foundation
import Security
import XCTest
@testable import Kadence

/// The test sentinel password (PHASE3-PLAN.md common rules). Defined and used
/// only in this file.
nonisolated private let sentinel = "S3ntinel-pw-⚠"

nonisolated private let account = SecretAccount(host: "cis.technikum-wien.at", port: 443, username: "user01")
nonisolated private let info = SecretItemInfo.forSource(id: "source-1", displayName: "University timetable")

struct SecretStoreTests {

    // MARK: In memory

    @Test("In memory: round trip, replace and delete")
    func inMemory() throws {
        let store = InMemorySecretStore()
        #expect(try store.read(account) == nil)
        try store.save(Password(sentinel), for: account, info: info)
        #expect(try store.read(account) == Password(sentinel))
        try store.save(Password("second"), for: account, info: info)
        #expect(try store.read(account) == Password("second"))
        let moved = SecretAccount(host: "cis.technikum-wien.at", username: "user02")
        try store.replace(account, with: moved, password: Password("third"), info: info)
        #expect(try store.read(account) == nil)
        #expect(try store.read(moved) == Password("third"))
        try store.delete(moved)
        #expect(try store.read(moved) == nil)
        #expect(store.accounts.isEmpty)
    }

    @Test("Replace writes the new item before deleting the old: a failure between them leaves the old readable")
    func replaceOrder() throws {
        let store = InMemorySecretStore()
        try store.save(Password("old"), for: account, info: info)
        let moved = SecretAccount(host: "cis.technikum-wien.at", username: "user02")
        store.failNext("delete")
        #expect(throws: SecretStoreError.injected) {
            try store.replace(account, with: moved, password: Password("new"), info: info)
        }
        #expect(try store.read(account) == Password("old"))
        #expect(try store.read(moved) == Password("new"))
        // A failing write leaves the old alone and adds nothing.
        let store2 = InMemorySecretStore()
        try store2.save(Password("old"), for: account, info: info)
        store2.failNext("save")
        #expect(throws: SecretStoreError.injected) {
            try store2.replace(account, with: moved, password: Password("new"), info: info)
        }
        #expect(try store2.read(account) == Password("old"))
        #expect(try store2.read(moved) == nil)
    }

    @Test("Renaming updates the item's label `Kadence — {name}`")
    func relabel() throws {
        let store = InMemorySecretStore()
        try store.save(Password("x"), for: account, info: info)
        try store.updateInfo(.forSource(id: "source-1", displayName: "FH timetable"), for: account)
        #expect(store.info(for: account)?.label == "Kadence — FH timetable")
        #expect(store.info(for: account)?.comment == "source-1")
    }

    // MARK: Query dictionaries

    private func expectIdentity(_ q: [String: Any]) {
        #expect(q[kSecClass as String] as? String == kSecClassInternetPassword as String)
        #expect(q[kSecAttrServer as String] as? String == "cis.technikum-wien.at")
        #expect(q[kSecAttrPort as String] as? Int == 443)
        #expect(q[kSecAttrProtocol as String] as? String == kSecAttrProtocolHTTPS as String)
        #expect(q[kSecAttrAuthenticationType as String] as? String == kSecAttrAuthenticationTypeDefault as String)
        #expect(q[kSecAttrAccount as String] as? String == "user01")
        #expect(q[kSecAttrSecurityDomain as String] as? String == "Kadence")
        #expect(q[kSecAttrCreator as String] as? UInt32 == 0x4B64_6E63)  // 'Kdnc'
        #expect((q[kSecAttrSynchronizable as String] as? Bool) == false)
    }

    @Test("Save query carries every §21.4 attribute; the value is the UTF-8 password only")
    func saveQuery() {
        let q = KeychainSecretStore.saveQuery(Password(sentinel), for: account, info: info)
        expectIdentity(q)
        #expect(q[kSecAttrLabel as String] as? String == "Kadence — University timetable")
        #expect(q[kSecAttrComment as String] as? String == "source-1")
        #expect(q[kSecAttrAccessible as String] as? String == kSecAttrAccessibleAfterFirstUnlock as String)
        #expect(q[kSecValueData as String] as? Data == Data(sentinel.utf8))
        #expect(Set(q.keys).count == 13)
    }

    @Test("Read and delete queries carry the identity, so they never match a foreign item")
    func readDeleteQueries() {
        let read = KeychainSecretStore.readQuery(account)
        expectIdentity(read)
        #expect(read[kSecReturnData as String] as? Bool == true)
        #expect(read[kSecMatchLimit as String] as? String == kSecMatchLimitOne as String)
        #expect(read[kSecValueData as String] == nil)
        let delete = KeychainSecretStore.deleteQuery(account)
        expectIdentity(delete)
        #expect(delete[kSecValueData as String] == nil)
        #expect(KeychainSecretStore.saveQuery(Password("p"), for: SecretAccount(host: "h.example", port: 8443, username: "u"),
                                              info: info)[kSecAttrPort as String] as? Int == 8443)
    }

    // MARK: Nothing prints the password

    @Test("The sentinel appears in no description, debugDescription, String(reflecting:), dump or error")
    func noLeaks() {
        let password = Password(sentinel)
        var dumped = ""
        dump(password, to: &dumped)
        var dumpedStore = ""
        let store = InMemorySecretStore()
        try? store.save(password, for: account, info: info)
        dump(store, to: &dumpedStore)
        var dumpedKeychain = ""
        dump(KeychainSecretStore(), to: &dumpedKeychain)
        let texts = [
            password.description, password.debugDescription, String(reflecting: password),
            "\(password)", String(describing: [password]), String(describing: Optional(password)),
            dumped, dumpedStore, dumpedKeychain, String(reflecting: store),
            SecretStoreError.keychain(errSecAuthFailed).description,
            String(describing: SecretStoreError.injected),
            (SecretStoreError.keychain(-25300) as Error).localizedDescription,
            account.description, String(reflecting: account), String(describing: info),
        ]
        for text in texts {
            #expect(!text.contains(sentinel) && !text.contains("S3ntinel"))
        }
        #expect(password.description == "Password(•)")
        #expect(dumped.trimmingCharacters(in: .whitespacesAndNewlines) == "- Password(•)")
        #expect(password.withPlaintext { $0 } == sentinel)
    }

}

// MARK: - The real Keychain (XCTest: `XCTSkip` and `tearDown`, as the plan asks)


// Swift note: `nonisolated` opts this XCTestCase out of the target's default
// `@MainActor`, which XCTest's own initialisers and setUp/tearDown don't share.
nonisolated final class KeychainSecretStoreLiveTests: XCTestCase {
    private let testAccount = SecretAccount(host: "cis.technikum-wien.at", username: "user01-tests")

    /// Deletes everything with the test account's server and account,
    /// Kadence's or foreign.
    private func purge() {
        let q: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
                                kSecAttrServer as String: testAccount.host,
                                kSecAttrAccount as String: testAccount.username]
        for _ in 0..<4 where SecItemDelete(q as CFDictionary) == errSecSuccess {}
    }

    override func setUp() { purge() }
    override func tearDown() { purge() }

    /// Skips, not fails, when the test host can't use the Keychain.
    private func requireKeychain() throws {
        do {
            try KeychainSecretStore().save(Password(sentinel), for: testAccount, info: info)
        } catch {
            throw XCTSkip("Keychain unavailable to the test host (\(error))")
        }
    }

    func testRoundTripOnAThrowawayAccount() throws {
        try requireKeychain()
        let store = KeychainSecretStore()
        XCTAssertEqual(try store.read(testAccount), Password(sentinel))
        try store.save(Password("second-value"), for: testAccount, info: info)
        XCTAssertEqual(try store.read(testAccount), Password("second-value"))
        try store.delete(testAccount)
        XCTAssertNil(try store.read(testAccount))
    }

    func testReadNeverMatchesAForeignItemAndDeleteLeavesIt() throws {
        try requireKeychain()
        let store = KeychainSecretStore()
        try store.delete(testAccount)
        // A foreign item, as another app would save it: no domain, no creator.
        let foreign: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: testAccount.host,
            kSecAttrPort as String: 443,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecAttrAccount as String: testAccount.username,
            kSecValueData as String: Data(sentinel.utf8),
        ]
        let status = SecItemAdd(foreign as CFDictionary, nil)
        guard status == errSecSuccess else { throw XCTSkip("could not add the foreign item (\(status))") }
        XCTAssertNil(try store.read(testAccount))
        try store.delete(testAccount)
        let lookup: [String: Any] = [kSecClass as String: kSecClassInternetPassword,
                                     kSecAttrServer as String: testAccount.host,
                                     kSecAttrAccount as String: testAccount.username,
                                     kSecReturnAttributes as String: true]
        var found: CFTypeRef?
        XCTAssertEqual(SecItemCopyMatching(lookup as CFDictionary, &found), errSecSuccess,
                       "Kadence's delete removed another app's item")
    }
}
