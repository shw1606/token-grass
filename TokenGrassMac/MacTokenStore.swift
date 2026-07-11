import Foundation
import Security
import TokenGrassCore

enum KeychainError: Error { case notFound }

/// The Mac app's OWN OAuth tokens, in its own Keychain item — completely
/// separate from Claude Code's `Claude Code-credentials`. This is what makes
/// the app self-sufficient: it holds its own refresh token and rotates it
/// itself, so it never depends on Claude Code being run, and (critically) never
/// rotates Claude Code's token out from under the CLI.
///
/// We read/write via SecItem (not the `/usr/bin/security` CLI the piggyback
/// path needs): this item is created by THIS app, so the app is in its own ACL
/// and accesses it without a prompt. The partition problem that forced the CLI
/// path for `Claude Code-credentials` was specific to Claude Code recreating
/// that item with an `apple-tool:`-only partition — it doesn't apply here.
enum MacTokenStore {
    private static let service = "dev.yulebuilds.tokengrass.mac.oauth"
    private static let account = "claude-subscription"

    static func save(_ tokens: OAuthTokens) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(tokens)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let add = query.merging(attributes) { _, new in new }
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.notFound }
        } else if status != errSecSuccess {
            throw KeychainError.notFound
        }
    }

    static func load() -> OAuthTokens? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(OAuthTokens.self, from: data)
    }

    static func clear() {
        SecItemDelete([
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ] as CFDictionary)
    }
}
