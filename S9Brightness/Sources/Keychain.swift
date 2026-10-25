import Foundation
import Security

/// Stores the IP Control access token in the data protection keychain.
///
/// Unlike the legacy login keychain, the data protection keychain grants access by access group
/// (here the app group from the entitlements) rather than by a per-item ACL, so macOS never asks
/// the user to allow access, even when the app's code signature changes.
enum Keychain {
    static let service = Bundle.main.bundleIdentifier ?? "S9Brightness"
    static let account = "ipcontrol-token"
    static let accessGroup = "7C48W538SL.ch.tseng.S9Brightness"

    struct Error: LocalizedError {
        let status: OSStatus
        var errorDescription: String? {
            "Keychain error: " + ((SecCopyErrorMessageString(status, nil) as String?) ?? "\(status)")
        }
    }

    private static var legacyQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private static var baseQuery: [String: Any] {
        var query = legacyQuery
        query[kSecUseDataProtectionKeychain as String] = true
        query[kSecAttrAccessGroup as String] = accessGroup
        return query
    }

    static func readToken() -> String? {
        if let token = read(baseQuery) { return token }
        // Versions up to 1.2.2 stored the token in the login keychain; move it over once.
        guard let token = read(legacyQuery) else { return nil }
        if (try? saveToken(token)) != nil {
            SecItemDelete(legacyQuery as CFDictionary)
        }
        return token
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

    private static func read(_ query: [String: Any]) -> String? {
        var query = query
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
