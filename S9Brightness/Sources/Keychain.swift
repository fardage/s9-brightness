import Foundation
import Security

/// Stores the IP Control access token in the data protection keychain.
///
/// Unlike the legacy login keychain, the data protection keychain grants access by access group
/// rather than by a per-item ACL, so macOS never asks the user to allow access, even when the app's
/// code signature changes. Items go into the first group in the `keychain-access-groups` entitlement.
enum Keychain {
    static let service = Bundle.main.bundleIdentifier ?? "S9Brightness"
    static let account = "ipcontrol-token"

    struct Error: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "Keychain error: " + ((SecCopyErrorMessageString(status, nil) as String?) ?? "\(status)")
        }
    }

    private static var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account,
         kSecUseDataProtectionKeychain as String: true]
    }

    static func readToken() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        var status = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var item = baseQuery
            item[kSecValueData as String] = data
            item[kSecAttrLabel as String] = "S9 Brightness IP Control token"
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Error(status: status) }
    }
}
