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

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data(("✗ " + message + "\n").utf8))
    exit(1)
}

func openURL(_ url: URL) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    process.arguments = [url.absoluteString]
    try? process.run()
}

// MARK: - Claude Code Keychain (piggyback path; kept for reference)

struct ClaudeCredentials {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date?
}

enum Keychain {
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
            expiresAt = Date(timeIntervalSince1970: ms / 1000)
        } else if let s = oauth["expiresAt"] as? String {
            expiresAt = ISO8601.flexible(s)
        }
        return ClaudeCredentials(accessToken: access, refreshToken: refresh, expiresAt: expiresAt)
    }
}

// MARK: - Network

enum UsageAPI {
    static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    struct Response { let status: Int; let body: Data }

    static func fetchUsage(accessToken: String) throws -> Response {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-cli/2.1.195", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, status) = try Net.send(request)
        return Response(status: status, body: data)
    }
}

/// OAuth token endpoint (in-app login path). We own these tokens, separate from
/// Claude Code's, so refreshing here never touches Claude Code's login.
enum OAuthClient {
    static func exchange(code: String, verifier: String, state: String?) throws -> OAuthTokens {
        let body = OAuthFlow.tokenExchangeBody(code: code, verifier: verifier, state: state)
        return try OAuthFlow.parseTokens(post(body))
    }

    static func refresh(refreshToken: String) throws -> OAuthTokens {
        let body = OAuthFlow.refreshBody(refreshToken: refreshToken)
        return try OAuthFlow.parseTokens(post(body))
    }

    private static func post(_ body: Data) throws -> Data {
        var request = URLRequest(url: OAuthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("claude-cli/2.1.195", forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        request.timeoutInterval = 30
        let (data, status) = try Net.send(request)
        guard status == 200 else {
            throw PollError.network("token endpoint HTTP \(status): \(String(data: data, encoding: .utf8)?.prefix(400) ?? "")")
        }
        return data
    }
}

enum Net {
    static func send(_ request: URLRequest) throws -> (Data, Int) {
        let semaphore = DispatchSemaphore(value: 0)
        var outcome: Result<(Data, Int), Error>!
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                outcome = .failure(PollError.network(error.localizedDescription))
            } else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                outcome = .success((data ?? Data(), code))
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        return try outcome.get()
    }
}

// MARK: - Local persistence

enum StateStore {
    static var fileURL: URL { tokengrassDir().appendingPathComponent("poll-state.json") }

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

enum TokenStore {
    static var fileURL: URL { tokengrassDir().appendingPathComponent("oauth-tokens.json") }

    static func save(_ tokens: OAuthTokens) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(tokens).write(to: fileURL)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }

    static func load() -> OAuthTokens? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(OAuthTokens.self, from: data)
    }
}

func tokengrassDir() -> URL {
    let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".tokengrass", isDirectory: true)
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    return dir
}
