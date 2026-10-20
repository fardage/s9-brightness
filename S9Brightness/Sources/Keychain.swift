import Foundation
import Security

/// Stores the IP Control access token in the login keychain.
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
         kSecAttrAccount as String: account]
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
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Error(status: status) }
    }
}
