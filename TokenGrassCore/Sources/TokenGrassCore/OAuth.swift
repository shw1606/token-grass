import Foundation
import CryptoKit

/// Endpoints + identifiers for the in-app "Sign in with Claude" flow.
/// Discovered from the Claude Code binary. The redirect is a page that *displays*
/// the authorization code, so the flow is: open authorize URL → user logs in →
/// copy the shown code → paste into the app → exchange for tokens.
public enum OAuthConfig {
    public static let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    public static let authorizeURL = URL(string: "https://platform.claude.com/oauth/authorize")!
    public static let tokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!
    public static let redirectURI = "https://platform.claude.com/oauth/code/callback"
    public static let scopes = ["user:inference", "user:profile"]
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
    public static func authorizeURL(pkce: PKCE, state: String) -> URL {
        var components = URLComponents(url: OAuthConfig.authorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"), // Claude's "show the code" (manual) mode
            URLQueryItem(name: "client_id", value: OAuthConfig.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: OAuthConfig.redirectURI),
            URLQueryItem(name: "scope", value: OAuthConfig.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: pkce.challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state),
        ]
        return components.url!
    }

    /// The callback page shows the code as "code#state"; the user may paste either.
    public static func parsePastedCode(_ pasted: String) -> (code: String, state: String?) {
        let trimmed = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hash = trimmed.firstIndex(of: "#") else { return (trimmed, nil) }
        return (String(trimmed[..<hash]), String(trimmed[trimmed.index(after: hash)...]))
    }

    /// JSON body for the authorization_code → token exchange.
    public static func tokenExchangeBody(code: String, verifier: String, state: String?) -> Data {
        var fields: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": OAuthConfig.redirectURI,
            "client_id": OAuthConfig.clientID,
            "code_verifier": verifier,
        ]
        if let state { fields["state"] = state }
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

    /// Random URL-safe state value.
    public static func randomState() -> String { randomURLSafe(byteCount: 16) }
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
