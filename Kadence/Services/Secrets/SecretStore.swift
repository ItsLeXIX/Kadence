//
//  SecretStore.swift
//  Kadence
//
//  components.md §21.4 — the password is the only secret. One Keychain
//  internet-password item per source; `KeychainSecretStore` in the app,
//  `InMemorySecretStore` in tests and review mode (PHASE3-PLAN.md task 2).
//
//  Nothing in this file logs, prints or formats a password. Errors carry an
//  `OSStatus` and nothing else.
//

import Foundation
import Security
import Synchronization

// MARK: - Password

/// A password that cannot print itself.
///
/// Swift note: `description` (≈ Java's `toString()` / C#'s `ToString()`),
/// `debugDescription` (what the debugger and `String(reflecting:)` use) and
/// `customMirror` (what `dump` and the debugger walk) are all overridden, so
/// every way Swift turns a value into text yields `Password(•)`. The text is
/// reachable only through `withPlaintext`, which keeps the uses greppable.
nonisolated struct Password: Sendable, Equatable, CustomStringConvertible,
                             CustomDebugStringConvertible, CustomReflectable {
    private let storage: String

    init(_ plaintext: String) { storage = plaintext }

    var isEmpty: Bool { storage.isEmpty }

    /// The only way to the text. Swift note: `rethrows` means this throws only
    /// if the closure does — like a generic `throws` that disappears otherwise.
    func withPlaintext<T>(_ body: (String) throws -> T) rethrows -> T { try body(storage) }

    var description: String { "Password(•)" }
    var debugDescription: String { "Password(•)" }
    /// No children: `dump` prints the type's summary line and nothing inside.
    var customMirror: Mirror { Mirror(self, children: [], displayStyle: .struct) }
}

// MARK: - The account a password belongs to

/// The Keychain item's key: server, port and account (§21.4). Not secret.
nonisolated struct SecretAccount: Sendable, Hashable, CustomStringConvertible {
    var host: String
    var port: Int = 443
    var username: String

    var description: String { "\(username) @ \(host)\(port == 443 ? "" : ":\(port)")" }
}

/// What the Keychain item says about itself (§21.4's label and comment).
nonisolated struct SecretItemInfo: Sendable, Equatable {
    /// `Kadence — {displayName}`.
    var label: String
    /// The `Source.id`.
    var comment: String

    static func forSource(id: String, displayName: String) -> SecretItemInfo {
        SecretItemInfo(label: "Kadence — \(displayName)", comment: id)
    }
}

nonisolated enum SecretStoreError: Error, Equatable, CustomStringConvertible {
    /// The Keychain refused (locked, access denied, missing entitlement…).
    case keychain(OSStatus)
    /// A test double was told to fail.
    case injected

    var description: String {
        switch self {
        case .keychain(let status): "Keychain error \(status)"
        case .injected: "Injected secret-store failure"
        }
    }
}

// MARK: - The protocol

/// Save, read and delete the password for `(host, port, username)`.
nonisolated protocol SecretStore: Sendable {
    func save(_ password: Password, for account: SecretAccount, info: SecretItemInfo) throws(SecretStoreError)
    /// nil when there is no item (§20.8.3 step 1: `passwordMissing`).
    func read(_ account: SecretAccount) throws(SecretStoreError) -> Password?
    func delete(_ account: SecretAccount) throws(SecretStoreError)
    /// Renaming changes the item's label (layouts.md §11) and nothing else.
    func updateInfo(_ info: SecretItemInfo, for account: SecretAccount) throws(SecretStoreError)
}

extension SecretStore {
    /// layouts.md §12.3 `Save`: "the new one is written first, then the old
    /// one is deleted". When the account didn't change, `save` overwrites in
    /// place. A failure after the write leaves the old item readable.
    func replace(_ old: SecretAccount, with new: SecretAccount, password: Password,
                 info: SecretItemInfo) throws(SecretStoreError) {
        try save(password, for: new, info: info)
        if old != new { try delete(old) }
    }
}

// MARK: - In memory (tests, review mode)

/// Holds passwords in process memory only. Review mode's password lives here,
/// never in the Keychain (components.md §22.1).
///
/// Swift note: `Mutex` (Synchronization, macOS 15) is a lock that owns the
/// value it protects — the only way in is `withLock`, so the dictionary can't
/// be touched unlocked. That is what makes this class safely `Sendable`.
nonisolated final class InMemorySecretStore: SecretStore {
    private struct Item { var password: Password; var info: SecretItemInfo }
    private let items = Mutex<[SecretAccount: Item]>([:])
    /// Test hooks: make the next operation of that kind fail.
    private let failures = Mutex<Set<String>>([])

    init() {}

    func failNext(_ operation: String) { failures.withLock { _ = $0.insert(operation) } }

    private func check(_ operation: String) throws(SecretStoreError) {
        let fail = failures.withLock { $0.remove(operation) != nil }
        if fail { throw .injected }
    }

    func save(_ password: Password, for account: SecretAccount, info: SecretItemInfo) throws(SecretStoreError) {
        try check("save")
        items.withLock { $0[account] = Item(password: password, info: info) }
    }

    func read(_ account: SecretAccount) throws(SecretStoreError) -> Password? {
        try check("read")
        return items.withLock { $0[account]?.password }
    }

    func delete(_ account: SecretAccount) throws(SecretStoreError) {
        try check("delete")
        _ = items.withLock { $0.removeValue(forKey: account) }
    }

    func updateInfo(_ info: SecretItemInfo, for account: SecretAccount) throws(SecretStoreError) {
        try check("updateInfo")
        items.withLock { $0[account]?.info = info }
    }

    func info(for account: SecretAccount) -> SecretItemInfo? { items.withLock { $0[account]?.info } }
    var accounts: [SecretAccount] { items.withLock { Array($0.keys) } }
}

// MARK: - Keychain

/// One internet-password item per source, exactly §21.4's attributes. Every
/// query carries server, port, protocol, account, security domain `Kadence`
/// and creator `Kdnc`, so Kadence never reads or replaces an item another app
/// (Apple Calendar) saved for the same account.
nonisolated struct KeychainSecretStore: SecretStore {
    static let securityDomain = "Kadence"
    /// The four-char code 'Kdnc' as the UInt32 the Keychain stores.
    static let creator: UInt32 = {
        "Kdnc".utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
    }()

    init() {}

    // The dictionaries are built by these static functions so a test can
    // assert every attribute without touching the Keychain.

    /// The attributes that identify Kadence's item for an account.
    static func identity(_ account: SecretAccount) -> [String: Any] {
        [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: account.host,
            kSecAttrPort as String: account.port,
            kSecAttrProtocol as String: kSecAttrProtocolHTTPS,
            kSecAttrAuthenticationType as String: kSecAttrAuthenticationTypeDefault,
            kSecAttrAccount as String: account.username,
            kSecAttrSecurityDomain as String: securityDomain,
            kSecAttrCreator as String: creator,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    static func saveQuery(_ password: Password, for account: SecretAccount, info: SecretItemInfo) -> [String: Any] {
        var query = identity(account)
        query[kSecAttrLabel as String] = info.label
        query[kSecAttrComment as String] = info.comment
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        // §21.4: the value is the UTF-8 password and nothing else.
        query[kSecValueData as String] = password.withPlaintext { Data($0.utf8) }
        return query
    }

    static func readQuery(_ account: SecretAccount) -> [String: Any] {
        var query = identity(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    static func deleteQuery(_ account: SecretAccount) -> [String: Any] { identity(account) }

    func save(_ password: Password, for account: SecretAccount, info: SecretItemInfo) throws(SecretStoreError) {
        let add = Self.saveQuery(password, for: account, info: info)
        var status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            // Same account already saved: overwrite the value and the label in place.
            var changes: [String: Any] = [:]
            changes[kSecValueData as String] = add[kSecValueData as String]
            changes[kSecAttrLabel as String] = info.label
            changes[kSecAttrComment as String] = info.comment
            status = SecItemUpdate(Self.identity(account) as CFDictionary, changes as CFDictionary)
        }
        guard status == errSecSuccess else { throw .keychain(status) }
    }

    func read(_ account: SecretAccount) throws(SecretStoreError) -> Password? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(Self.readQuery(account) as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw .keychain(status) }
        guard let data = result as? Data, let text = String(data: data, encoding: .utf8) else { return nil }
        return Password(text)
    }

    func delete(_ account: SecretAccount) throws(SecretStoreError) {
        let status = SecItemDelete(Self.deleteQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw .keychain(status) }
    }

    func updateInfo(_ info: SecretItemInfo, for account: SecretAccount) throws(SecretStoreError) {
        let changes: [String: Any] = [kSecAttrLabel as String: info.label,
                                      kSecAttrComment as String: info.comment]
        let status = SecItemUpdate(Self.identity(account) as CFDictionary, changes as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw .keychain(status) }
    }
}
