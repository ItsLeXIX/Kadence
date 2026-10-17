//
//  SecretStore.swift
//  Kadence
//
//  components.md §21.4 — the password is the only secret. One Keychain
//  internet-password item per source; `KeychainSecretStore` in the app,
//  `InMemorySecretStore` in tests and review mode (PHASE3-PLAN.md task 2).
//
//  Phase 3 slice 3 (components.md §33.3) adds a second item kind: one
//  generic-password item per Moodle source, holding its calendar URL — the
//  feed's only secret.
//
//  Nothing in this file logs, prints or formats a password or a feed URL.
//  Errors carry an `OSStatus` and nothing else.
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

    // MARK: Feed URLs (components.md §33.3) — keyed by `Source.id`

    /// The Import's write (layouts.md §16.2 step 1). An item that already
    /// exists for the source is overwritten in place.
    func saveFeedURL(_ url: MoodleFeedURL, sourceID: String, label: String) throws(SecretStoreError)
    /// nil when there is no item, or its value is no valid URL (§34.8 step 1:
    /// `urlMissing`).
    func readFeedURL(sourceID: String) throws(SecretStoreError) -> MoodleFeedURL?
    /// Replace's `Save` (§33.5): the value updated **in place**; the item
    /// keeps its label. Throws if there is no item to update.
    func updateFeedURL(_ url: MoodleFeedURL, sourceID: String) throws(SecretStoreError)
    func deleteFeedURL(sourceID: String) throws(SecretStoreError)
    /// Renaming the source updates the label (§33.3, as §21.4).
    func updateFeedLabel(_ label: String, sourceID: String) throws(SecretStoreError)
}

/// §33.3: `kSecAttrLabel` of a feed item.
nonisolated func feedItemLabel(displayName: String) -> String { "Kadence — \(displayName)" }

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

    // MARK: Feed URLs — the same item kind as the Keychain's (§33.3)

    private struct FeedItem { var url: MoodleFeedURL; var label: String }
    private let feeds = Mutex<[String: FeedItem]>([:])

    func saveFeedURL(_ url: MoodleFeedURL, sourceID: String, label: String) throws(SecretStoreError) {
        try check("saveFeed")
        feeds.withLock { $0[sourceID] = FeedItem(url: url, label: label) }
    }

    func readFeedURL(sourceID: String) throws(SecretStoreError) -> MoodleFeedURL? {
        try check("readFeed")
        return feeds.withLock { $0[sourceID]?.url }
    }

    func updateFeedURL(_ url: MoodleFeedURL, sourceID: String) throws(SecretStoreError) {
        try check("updateFeed")
        let found = feeds.withLock { items -> Bool in
            guard items[sourceID] != nil else { return false }
            items[sourceID]?.url = url
            return true
        }
        if !found { throw .keychain(errSecItemNotFound) }
    }

    func deleteFeedURL(sourceID: String) throws(SecretStoreError) {
        try check("deleteFeed")
        _ = feeds.withLock { $0.removeValue(forKey: sourceID) }
    }

    func updateFeedLabel(_ label: String, sourceID: String) throws(SecretStoreError) {
        try check("updateFeedLabel")
        feeds.withLock { $0[sourceID]?.label = label }
    }

    func feedLabel(sourceID: String) -> String? { feeds.withLock { $0[sourceID]?.label } }
    var feedSourceIDs: [String] { feeds.withLock { Array($0.keys) } }
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

// MARK: - Keychain: feed URLs (components.md §33.3)

extension KeychainSecretStore {
    /// §33.3 `kSecAttrService`.
    static let feedService = "XIX.Kadence.feed"
    /// §33.3 `kSecAttrDescription`.
    static let feedItemDescription = "Calendar URL"

    /// The attributes that identify a source's feed item. Every query carries
    /// service and account, so Kadence never reads an item it did not write.
    static func feedIdentity(sourceID: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: feedService,
            kSecAttrAccount as String: sourceID,
            kSecAttrSynchronizable as String: kCFBooleanFalse as Any,
        ]
    }

    static func feedSaveQuery(_ url: MoodleFeedURL, sourceID: String, label: String) -> [String: Any] {
        var query = feedIdentity(sourceID: sourceID)
        query[kSecAttrLabel as String] = label
        query[kSecAttrDescription as String] = feedItemDescription
        // Background sync while the Mac is locked (§33.3).
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        // §33.3: the normalised URL, UTF-8. Nothing else.
        query[kSecValueData as String] = url.keychainValue
        return query
    }

    static func feedReadQuery(sourceID: String) -> [String: Any] {
        var query = feedIdentity(sourceID: sourceID)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    static func feedUpdateChanges(_ url: MoodleFeedURL) -> [String: Any] {
        [kSecValueData as String: url.keychainValue]
    }

    func saveFeedURL(_ url: MoodleFeedURL, sourceID: String, label: String) throws(SecretStoreError) {
        let add = Self.feedSaveQuery(url, sourceID: sourceID, label: label)
        var status = SecItemAdd(add as CFDictionary, nil)
        if status == errSecDuplicateItem {
            var changes = Self.feedUpdateChanges(url)
            changes[kSecAttrLabel as String] = label
            status = SecItemUpdate(Self.feedIdentity(sourceID: sourceID) as CFDictionary, changes as CFDictionary)
        }
        guard status == errSecSuccess else { throw .keychain(status) }
    }

    func readFeedURL(sourceID: String) throws(SecretStoreError) -> MoodleFeedURL? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(Self.feedReadQuery(sourceID: sourceID) as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw .keychain(status) }
        guard let data = result as? Data else { return nil }
        return MoodleFeedURL(keychainValue: data)
    }

    func updateFeedURL(_ url: MoodleFeedURL, sourceID: String) throws(SecretStoreError) {
        // §33.5: `SecItemUpdate` of the value, in place.
        let status = SecItemUpdate(Self.feedIdentity(sourceID: sourceID) as CFDictionary,
                                   Self.feedUpdateChanges(url) as CFDictionary)
        guard status == errSecSuccess else { throw .keychain(status) }
    }

    func deleteFeedURL(sourceID: String) throws(SecretStoreError) {
        let status = SecItemDelete(Self.feedIdentity(sourceID: sourceID) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw .keychain(status) }
    }

    func updateFeedLabel(_ label: String, sourceID: String) throws(SecretStoreError) {
        let status = SecItemUpdate(Self.feedIdentity(sourceID: sourceID) as CFDictionary,
                                   [kSecAttrLabel as String: label] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw .keychain(status) }
    }
}
