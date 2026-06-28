import Foundation
import Security

enum KeychainError: Error { case notFound, badFormat }

enum ClaudeKeychain {
    /// Reads Claude Code's OAuth access token from the login Keychain (piggyback).
    /// First read triggers a one-time macOS "Always Allow" prompt for this app.
    /// Service name confirmed on-device: "Claude Code-credentials".
    static func accessToken() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw KeychainError.notFound
        }
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String
        else { throw KeychainError.badFormat }
        return token
    }
}
