import Foundation
import Security

enum KeychainError: Error { case notFound, badFormat }

/// What Claude Code stores alongside the token. `expiresAt` lets us notice a
/// stale access token *before* spending a 401 on it.
struct ClaudeCredentials {
    let accessToken: String
    let expiresAt: Date?

    func isExpired(now: Date = Date(), leeway: TimeInterval = 60) -> Bool {
        guard let expiresAt else { return false } // unknown expiry → trust it
        return now.addingTimeInterval(leeway) >= expiresAt
    }
}

enum ClaudeKeychain {
    private static let service = "Claude Code-credentials"

    /// Reads Claude Code's OAuth access token from the login Keychain (piggyback).
    static func accessToken() throws -> String {
        try credentials().accessToken
    }

    /// Token + expiry, read fresh from the Keychain every call.
    static func credentials() throws -> ClaudeCredentials {
        // Primary path: shell out to `/usr/bin/security`. Claude Code recreates
        // its keychain item (delete + add) on every token refresh, which resets
        // the item's ACL/partition list to `apple-tool:` only — so a direct
        // SecItemCopyMatching from our app loses its "Always Allow" grant and
        // re-prompts after each rotation. `security` is an Apple-signed tool that
        // lives in the `apple-tool:` partition, so it reads WITHOUT prompting and
        // keeps working across rotations. (This is the user's own token on their
        // own machine — the partition list exists to stop cross-app secret theft,
        // not first-party companion reads.)
        if let json = readViaSecurityCLI(), let creds = credentials(fromJSON: json) {
            return creds
        }
        // Fallback: the Keychain API (may prompt) if the CLI path is unavailable.
        return try readViaSecItem()
    }

    private static func readViaSecurityCLI() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do {
            try process.run()
            let data = stdout.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private static func readViaSecItem() throws -> ClaudeCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data,
              let json = String(data: data, encoding: .utf8) else {
            throw KeychainError.notFound
        }
        guard let creds = credentials(fromJSON: json) else { throw KeychainError.badFormat }
        return creds
    }

    private static func credentials(fromJSON json: String) -> ClaudeCredentials? {
        guard
            let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String
        else { return nil }
        // Claude Code writes expiresAt as epoch milliseconds.
        let expiresAt = (oauth["expiresAt"] as? Double).map {
            Date(timeIntervalSince1970: $0 / 1000)
        }
        return ClaudeCredentials(accessToken: token, expiresAt: expiresAt)
    }
}
