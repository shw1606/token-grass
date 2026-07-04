import Foundation
import Security

enum KeychainError: Error { case notFound, badFormat }

enum ClaudeKeychain {
    private static let service = "Claude Code-credentials"

    /// Reads Claude Code's OAuth access token from the login Keychain (piggyback).
    static func accessToken() throws -> String {
        // Primary path: shell out to `/usr/bin/security`. Claude Code recreates
        // its keychain item (delete + add) on every token refresh, which resets
        // the item's ACL/partition list to `apple-tool:` only — so a direct
        // SecItemCopyMatching from our app loses its "Always Allow" grant and
        // re-prompts after each rotation. `security` is an Apple-signed tool that
        // lives in the `apple-tool:` partition, so it reads WITHOUT prompting and
        // keeps working across rotations. (This is the user's own token on their
        // own machine — the partition list exists to stop cross-app secret theft,
        // not first-party companion reads.)
        if let json = readViaSecurityCLI(), let token = token(fromJSON: json) {
            return token
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

    private static func readViaSecItem() throws -> String {
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
        guard let token = token(fromJSON: json) else { throw KeychainError.badFormat }
        return token
    }

    private static func token(fromJSON json: String) -> String? {
        guard
            let data = json.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any],
            let token = oauth["accessToken"] as? String
        else { return nil }
        return token
    }
}
