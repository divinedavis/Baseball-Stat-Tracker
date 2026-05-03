import Foundation
import Security

/// Thin wrapper over the iOS Keychain for storing small blobs of `Data`.
///
/// Non-synchronizable items use `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`:
///   - accessible only while the device is unlocked,
///   - never included in iCloud or encrypted backups (ThisDeviceOnly),
///   - persist across app relaunches and across app **deletion + reinstall**
///     on the same device.
/// Synchronizable items fall back to `kSecAttrAccessibleWhenUnlocked` because
/// iCloud-syncable items cannot use the ThisDeviceOnly accessibility constants.
enum KeychainStore {
    static let service = "com.divinedavis.BaseballStatTracker"

    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
    }

    private static func accessibility(synchronizable: Bool) -> CFString {
        synchronizable ? kSecAttrAccessibleWhenUnlocked : kSecAttrAccessibleWhenUnlockedThisDeviceOnly
    }

    static func set(_ data: Data, account: String, synchronizable: Bool = false) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synchronizable
        ]

        let access = accessibility(synchronizable: synchronizable)

        // Try update first; fall back to add.
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: access
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = access
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        default:
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    static func get(account: String, synchronizable: Bool = false) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synchronizable,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var out: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        guard status == errSecSuccess else { return nil }
        return out as? Data
    }

    @discardableResult
    static func delete(account: String, synchronizable: Bool = false) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synchronizable
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
