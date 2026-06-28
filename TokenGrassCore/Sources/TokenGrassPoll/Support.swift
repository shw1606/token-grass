import Foundation
import Security
import TokenGrassCore

enum PollError: Error, CustomStringConvertible {
    case keychain(OSStatus)
    case credentialFormat
    case network(String)

    var description: String {
        switch self {
        case .keychain(let status): return "Keychain 접근 실패 (OSStatus \(status))"
        case .credentialFormat: return "credential JSON 형식이 예상과 다름"
        case .network(let message): return "네트워크: \(message)"
        }
    }
}

struct ClaudeCredentials {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date?
}

enum Keychain {
    /// Reads Claude Code's OAuth credentials from the login Keychain.
    /// Service name confirmed on-device: "Claude Code-credentials".
    /// First call triggers a macOS "Allow" prompt (this binary isn't in the ACL).
    static func readClaudeCode() throws -> ClaudeCredentials {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else {
            throw PollError.keychain(status)
        }

        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard
            let oauth = root?["claudeAiOauth"] as? [String: Any],
            let access = oauth["accessToken"] as? String,
            let refresh = oauth["refreshToken"] as? String
        else { throw PollError.credentialFormat }

        var expiresAt: Date?
        if let ms = oauth["expiresAt"] as? Double {
            expiresAt = Date(timeIntervalSince1970: ms / 1000) // epoch millis
        } else if let s = oauth["expiresAt"] as? String {
            expiresAt = ISO8601.flexible(s)
        }
        return ClaudeCredentials(accessToken: access, refreshToken: refresh, expiresAt: expiresAt)
    }
}

enum UsageAPI {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    struct Response { let status: Int; let body: Data }

    static func fetchUsage(accessToken: String) throws -> Response {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-cli/2.1.195", forHTTPHeaderField: "User-Agent") // matches the proven-working call
        request.timeoutInterval = 20

        let semaphore = DispatchSemaphore(value: 0)
        var outcome: Result<Response, Error>!
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                outcome = .failure(PollError.network(error.localizedDescription))
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                outcome = .success(Response(status: code, body: data ?? Data()))
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return try outcome.get()
    }
}

enum StateStore {
    static var fileURL: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".tokengrass", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("poll-state.json")
    }

    static func load() -> AccumulatorState {
        guard let data = try? Data(contentsOf: fileURL) else { return AccumulatorState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(AccumulatorState.self, from: data)) ?? AccumulatorState()
    }

    static func save(_ state: AccumulatorState) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: fileURL)
    }
}
