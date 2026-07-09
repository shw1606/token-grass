import Foundation
import CryptoKit

/// Endpoints + identifiers for the in-app "Sign in with Claude" flow.
/// These MIRROR EXACTLY what the current Claude Code CLI (v2.1.205) sends for a
/// subscription (`claude /login`) sign-in — extracted from its production config
/// constants. The redirect is a page that *displays* the authorization code, so
/// the flow is: open authorize URL → user logs in → copy the shown code → paste
/// into the app → exchange for tokens.
///
/// These are the EXACT values captured from the authorize URL that a live
/// `claude auth login --claudeai` generates on v2.1.205 (captured via PTY, then
/// byte-for-byte matched here). Do not "improve" them — every field is what the
/// working CLI sends.
///
/// Why each value matters:
/// - `authorizeURL`: the subscription login goes through Claude Code's
///   CLAUDE_AI_AUTHORIZE_URL, which is now `claude.com/cai/oauth/authorize`
///   (NOT `claude.ai/oauth/authorize` and NOT the console host). Sending the
///   request to the wrong authorize host is what produced "Invalid request
///   format" on the consent page.
/// - `clientID`: still `9d1c250a-…`. (The binary also carries `22422756-…` as a
///   config constant, but that client is overridden at runtime and the token
///   endpoint reports it "not found" — `9d1c250a` is the live client.)
/// - `redirectURI`: the manual "show the code" callback (MANUAL_REDIRECT_URL).
/// - `scopes`: the exact set/order the CLI requests. `user:profile` is what
///   `/api/oauth/usage` requires; the rest match the CLI so consent validates.
public enum OAuthConfig {
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let authorizeURL = URL(string: "https://claude.com/cai/oauth/authorize")!
    public static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    public static let redirectURI = "https://platform.claude.com/oauth/code/callback"
    public static let scopes = [
        "org:create_api_key", "user:profile", "user:inference",
        "user:sessions:claude_code", "user:mcp_servers", "user:file_upload",
    ]
}

/// PKCE pair (RFC 7636). `challenge` = base64url(SHA256(verifier)).
public struct PKCE: Equatable, Sendable {
    public let verifier: String
    public let challenge: String

    public init(verifier: String) {
        self.verifier = verifier
        let digest = SHA256.hash(data: Data(verifier.utf8))
        self.challenge = Data(digest).base64URLEncodedString()
    }

    /// Cryptographically-random verifier (32 bytes → 43 url-safe chars).
    public static func random() -> PKCE {
        PKCE(verifier: randomURLSafe(byteCount: 32))
    }
}

public struct OAuthTokens: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date
    public let scope: String?

    public init(accessToken: String, refreshToken: String, expiresAt: Date, scope: String?) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scope = scope
    }

    public func isExpired(now: Date = Date(), leeway: TimeInterval = 120) -> Bool {
        now.addingTimeInterval(leeway) >= expiresAt
    }
}

public enum OAuthFlow {
    /// Build the authorize URL the app opens in a browser.
    ///
    /// The query is encoded to match Claude Code's `URLSearchParams` output
    /// BYTE-FOR-BYTE (application/x-www-form-urlencoded: space→`+`, everything
    /// but unreserved+`*-._`→`%XX`, so `:` and `/` in `redirect_uri`/`scope`
    /// become `%3A`/`%2F`). This matters: the authorize server matches
    /// `redirect_uri` against its raw registered string, and a swift-default
    /// URLComponents encoding (literal `:` `/`, space→`%20`) is rejected with
    /// "Invalid request format" even though it decodes to the same value.
    public static func authorizeURL(pkce: PKCE, state: String) -> URL {
        var components = URLComponents(url: OAuthConfig.authorizeURL, resolvingAgainstBaseURL: false)!
        let pairs: [(String, String)] = [
            ("code", "true"), // Claude's "show the code" (manual) mode
            ("client_id", OAuthConfig.clientID),
            ("response_type", "code"),
            ("redirect_uri", OAuthConfig.redirectURI),
            ("scope", OAuthConfig.scopes.joined(separator: " ")),
            ("code_challenge", pkce.challenge),
            ("code_challenge_method", "S256"),
            ("state", state),
        ]
        components.percentEncodedQuery = pairs
            .map { "\($0.0)=\(formURLEncoded($0.1))" }
            .joined(separator: "&")
        return components.url!
    }

    /// application/x-www-form-urlencoded encoding, matching JS `URLSearchParams`.
    static func formURLEncoded(_ value: String) -> String {
        var allowed = CharacterSet()
        allowed.insert(charactersIn:
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789*-._")
        let encoded = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
        return encoded.replacingOccurrences(of: "%20", with: "+")
    }

    /// The callback page shows the code as "code#state"; the user may paste either.
    public static func parsePastedCode(_ pasted: String) -> (code: String, state: String?) {
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hash = trimmed.firstIndex(of: "#") else { return (trimmed, nil) }
        return (String(trimmed[..<hash]), String(trimmed[trimmed.index(after: hash)...]))
    }

    /// JSON body for the authorization_code → token exchange.
    /// `state` is REQUIRED: omitting it makes the endpoint answer 400
    /// "Invalid request format" (verified empirically — this very error is what
    /// once made this flow look "blocked by Anthropic"). With state present,
    /// the same request reaches real grant validation.
    public static func tokenExchangeBody(code: String, verifier: String, state: String) -> Data {
        let fields: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "state": state,
            "redirect_uri": OAuthConfig.redirectURI,
            "client_id": OAuthConfig.clientID,
            "code_verifier": verifier,
        ]
        return (try? JSONSerialization.data(withJSONObject: fields)) ?? Data()
    }

    /// JSON body for refreshing tokens. (We own these tokens — separate from
    /// Claude Code's — so refreshing here doesn't touch Claude Code's login.)
    public static func refreshBody(refreshToken: String) -> Data {
        let fields: [String: String] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": OAuthConfig.clientID,
        ]
        return (try? JSONSerialization.data(withJSONObject: fields)) ?? Data()
    }

    /// Parse a token endpoint response. `expires_in` (seconds) → absolute `expiresAt`.
    public static func parseTokens(_ data: Data, now: Date = Date()) throws -> OAuthTokens {
        struct DTO: Decodable {
            let access_token: String
            let refresh_token: String
            let expires_in: Double?
            let scope: String?
        }
        let dto = try JSONDecoder().decode(DTO.self, from: data)
        return OAuthTokens(
            accessToken: dto.access_token,
            refreshToken: dto.refresh_token,
            expiresAt: now.addingTimeInterval(dto.expires_in ?? 8 * 3600),
            scope: dto.scope
        )
    }

    /// Random URL-safe state value (32 bytes → 43 chars, matching the CLI).
    public static func randomState() -> String { randomURLSafe(byteCount: 32) }
}

// MARK: - Helpers

func randomURLSafe(byteCount: Int) -> String {
    var bytes = [UInt8](repeating: 0, count: byteCount)
    for index in bytes.indices { bytes[index] = .random(in: 0...255) }
    return Data(bytes).base64URLEncodedString()
}

extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
