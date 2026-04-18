import Foundation
import Security

/// Thin wrapper over the iOS Keychain for storing small blobs of `Data`.
///
/// Items are written with `kSecAttrAccessibleAfterFirstUnlock` and no
/// `kSecAttrSynchronizable` flag, which means:
///   - they persist across app relaunches,
///   - they persist across app **deletion + reinstall** on the same device
///     (Keychain items are not wiped with the app's container since iOS 10.3),
///   - they are wiped on a full device erase or when the user signs out of iCloud
///     if the device's keychain was migrating, and
///   - they do NOT sync to other devices via iCloud Keychain.
///
/// Flip `synchronizable` to `true` on a per-item basis if we ever want the
/// session to follow the user to their other Apple devices.
enum KeychainStore {
    static let service = "com.divinedavis.BaseballStatTracker"

    enum KeychainError: Error {
        case unexpectedStatus(OSStatus)
    }

    static func set(_ data: Data, account: String, synchronizable: Bool = false) throws {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: synchronizable
        ]

        // Try update first; fall back to add.
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
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
