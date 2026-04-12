import Foundation
import Security

/// Minimal Keychain wrapper used to persist a stable user ID across reinstalls.
enum KeychainStore {
    private static let service = "com.otishlau.screenmates"
    private static let accountUserID = "stable_user_id"

    static func loadStableUserID() -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountUserID,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        // Ensure no UI prompts.
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveStableUserID(_ value: String) {
        let data = Data(value.utf8)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountUserID
        ]

        let attributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            logKeychainError("add stable user ID", status: addStatus)
        } else {
            logKeychainError("update stable user ID", status: status)
        }
    }

    static func deleteStableUserID() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountUserID
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func getOrCreateStableUserID() -> String {
        if let existing = loadStableUserID(), !existing.isEmpty {
            return existing
        }

        let created = String(UUID().uuidString.prefix(8)).uppercased()
        saveStableUserID(created)
        return created
    }

    private static func logKeychainError(_ operation: String, status: OSStatus) {
        guard status != errSecSuccess else { return }
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        print("Keychain \(operation) failed: \(message)")
    }
}
