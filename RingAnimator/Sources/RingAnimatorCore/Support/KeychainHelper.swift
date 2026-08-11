import Foundation
import Security

/// Minimal Keychain wrapper for a single sensitive string — used to persist
/// the ElevenLabs API key across launches without putting it in
/// `UserDefaults` (unencrypted plist storage, not appropriate for API
/// keys). Nothing else in `RingConfig` persists at all; this is a
/// deliberate, narrow exception for the one field that's actually a
/// credential.
public enum KeychainHelper {
    private static let service = "com.ringanimator.elevenlabs"

    public static func save(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        // Delete-then-add rather than SecItemUpdate — simpler to reason
        // about, and this is called rarely (only when the API key field
        // changes), so the extra round-trip doesn't matter.
        SecItemDelete(query as CFDictionary)
        var attributes = query
        attributes[kSecValueData as String] = data
        SecItemAdd(attributes as CFDictionary, nil)
    }

    public static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
