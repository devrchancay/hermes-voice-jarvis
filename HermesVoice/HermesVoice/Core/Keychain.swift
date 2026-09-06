//  Minimal Keychain wrapper so the API key never touches UserDefaults.

import Foundation
import Security
import os

enum Keychain {
    private static let service = "com.desarol.hermes-voice"
    private static let logger = Logger(subsystem: service, category: "Keychain")

    /// Stores a secret, replacing any existing value for the account.
    @discardableResult
    static func set(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        // Update in place when the item already exists.
        let attributes: [String: Any] = [kSecValueData as String: data]
        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess { return true }

        guard updateStatus == errSecItemNotFound else {
            logger.error("Keychain update failed: \(updateStatus)")
            return false
        }

        var insert = query
        insert[kSecValueData as String] = data
        insert[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        if addStatus != errSecSuccess {
            logger.error("Keychain insert failed: \(addStatus)")
        }
        return addStatus == errSecSuccess
    }

    /// Reads a secret, or nil when it is absent.
    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            if status != errSecItemNotFound {
                logger.error("Keychain read failed: \(status)")
            }
            return nil
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// Removes a secret.
    @discardableResult
    static func delete(account: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
