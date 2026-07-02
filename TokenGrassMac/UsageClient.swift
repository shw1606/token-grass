import Foundation

enum UsageClientError: Error, LocalizedError {
    case http(Int, String)
    case badResponse
    case empty

    var errorDescription: String? {
        switch self {
        case .http(let code, let body): return "HTTP \(code): \(body.prefix(160))"
        case .badResponse: return "bad response"
        case .empty: return "empty response"
        }
    }
}

enum UsageClient {
    static let url = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func fetchUsage(accessToken: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        // The endpoint expects a claude-code-style User-Agent; without one it can
        // rate-limit (429). We're already reusing Claude Code's token, so match it.
        request.setValue("claude-code/1.0 (TokenGrass)", forHTTPHeaderField: "User-Agent")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageClientError.badResponse }
        guard http.statusCode == 200 else {
            throw UsageClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        // A reused-but-dead connection after wake can hand back a 200 with an empty
        // body — surface that as a retryable error, not a cryptic decode failure.
        guard !data.isEmpty else { throw UsageClientError.empty }
        return data
    }
}
