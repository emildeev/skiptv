import Foundation
import Security

/// Small Keychain wrapper for the Plex token and the chosen server.
enum Keychain {
    private static let service = "skiptv"

    static func data(_ key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    static func set(_ data: Data?, for key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
        guard let data else { return }
        var attributes = query
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(attributes as CFDictionary, nil)
    }

    static func string(_ key: String) -> String? {
        data(key).flatMap { String(data: $0, encoding: .utf8) }
    }

    static func setString(_ value: String?, for key: String) {
        set(value.map { Data($0.utf8) }, for: key)
    }

    static func codable<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        data(key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    static func setCodable<T: Encodable>(_ value: T?, for key: String) {
        set(value.flatMap { try? JSONEncoder().encode($0) }, for: key)
    }
}

enum StorageKey {
    static let userToken = "plex.userToken"
    static let server = "plex.server"
    static let clientIdentifier = "plex.clientIdentifier"
}
