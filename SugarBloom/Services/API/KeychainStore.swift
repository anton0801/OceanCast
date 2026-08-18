//
//  KeychainStore.swift
//  Ocean Cast
//
//  Tokens live in the Keychain, never in UserDefaults or a plist.
//  `ThisDeviceOnly` keeps them out of iCloud and out of encrypted backups.
//

import Foundation
import Security

enum KeychainStore {
    private static let service = "app.oceancast.tokens"

    enum Key: String {
        case accessToken
        case refreshToken
        case accessExpiry
        case refreshExpiry
    }

    @discardableResult
    static func set(_ value: String?, for key: Key) -> Bool {
        guard let value, !value.isEmpty else { return delete(key) }
        guard let data = value.data(using: .utf8) else { return false }

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound {
            var insert = query
            insert.merge(attributes) { current, _ in current }
            return SecItemAdd(insert as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    static func get(_ key: Key) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let value = String(data: data, encoding: .utf8) else { return nil }
        return value
    }

    @discardableResult
    static func delete(_ key: Key) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }

    static func clearAll() {
        for key in [Key.accessToken, .refreshToken, .accessExpiry, .refreshExpiry] {
            delete(key)
        }
    }

    /// Keychain items outlive an app deletion on iOS. A reinstalled app must not
    /// silently resume somebody's session, so the first launch after install
    /// starts clean — the marker lives in UserDefaults, which is removed with
    /// the app.
    static func purgeIfReinstalled() {
        let marker = "keychain.installMarker"
        guard !UserDefaults.standard.bool(forKey: marker) else { return }
        clearAll()
        UserDefaults.standard.set(true, forKey: marker)
    }
}
