import Foundation

/// Errors from the OAuth token endpoint / usage endpoint.
public enum ClaudeNetError: Error, CustomStringConvertible, Sendable {
    /// Non-2xx from the server. `body` is a short prefix for diagnostics only.
    case http(status: Int, body: String)
    case badResponse

    public var description: String {
        switch self {
        case .http(let status, let body): return "HTTP \(status): \(body)"
        case .badResponse: return "malformed response"
        }
    }

    public var status: Int? {
        if case .http(let status, _) = self { return status }
        return nil
    }
}

/// Async network client for the "Sign in with Claude" flow + usage polling.
/// Platform-neutral (iOS app uses it directly; the Mac app keeps its own
/// keychain-piggyback client). All requests are plain HTTPS to Anthropic —
/// tokens never go anywhere else.
public enum ClaudeNet {
    public static let usageURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// The UA Claude Code itself sends; proven to pass the endpoints' bot filters.
    public static let userAgent = "claude-cli/2.1.195"

    // MARK: - OAuth token endpoint

    /// authorization_code → tokens. `code`/`state` come from the pasted
    /// "code#state" string (see `OAuthFlow.parsePastedCode`); fall back to the
    /// state we generated if the user pasted only the code half.
    public static func exchange(
        code: String, verifier: String, state: String, session: URLSession = .shared
    ) async throws -> OAuthTokens {
        let body = OAuthFlow.tokenExchangeBody(code: code, verifier: verifier, state: state)
        return try OAuthFlow.parseTokens(await postToken(body, session: session))
    }

    /// refresh_token → fresh tokens. These are the app's own tokens (its own
    /// grant), so refreshing never disturbs Claude Code's login on a Mac.
    public static func refresh(
        refreshToken: String, session: URLSession = .shared
    ) async throws -> OAuthTokens {
        let body = OAuthFlow.refreshBody(refreshToken: refreshToken)
        return try OAuthFlow.parseTokens(await postToken(body, session: session))
    }

    private static func postToken(_ body: Data, session: URLSession) async throws -> Data {
        var request = URLRequest(url: OAuthConfig.tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = body
        request.timeoutInterval = 30
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeNetError.badResponse }
        guard http.statusCode == 200 else {
            throw ClaudeNetError.http(
                status: http.statusCode,
                body: String(String(data: data, encoding: .utf8)?.prefix(300) ?? "")
            )
        }
        return data
    }

    // MARK: - Usage endpoint

    /// GET /api/oauth/usage. Requires the `user:profile` scope (the endpoint
    /// returns 403 "does not meet scope requirement user:profile" without it).
    public static func fetchUsage(
        accessToken: String, session: URLSession = .shared
    ) async throws -> UsageResponse {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 20
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw ClaudeNetError.badResponse }
        guard http.statusCode == 200 else {
            throw ClaudeNetError.http(
                status: http.statusCode,
                body: String(String(data: data, encoding: .utf8)?.prefix(300) ?? "")
            )
        }
        return try UsageResponse.parse(data)
    }
}
