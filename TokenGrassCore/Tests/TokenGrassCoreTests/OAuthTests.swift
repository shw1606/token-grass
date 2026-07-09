import XCTest
@testable import TokenGrassCore

final class OAuthTests: XCTestCase {
    func testPKCEMatchesRFC7636Vector() {
        // RFC 7636 Appendix B test vector.
        let pkce = PKCE(verifier: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
        XCTAssertEqual(pkce.challenge, "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    func testPKCERandomIsUrlSafeAndStable() {
        let pkce = PKCE.random()
        XCTAssertFalse(pkce.verifier.contains("+") || pkce.verifier.contains("/") || pkce.verifier.contains("="))
        XCTAssertFalse(pkce.challenge.contains("+") || pkce.challenge.contains("/") || pkce.challenge.contains("="))
        // Same verifier always yields the same challenge.
        XCTAssertEqual(PKCE(verifier: pkce.verifier).challenge, pkce.challenge)
    }

    func testAuthorizeURLHasRequiredParams() {
        let pkce = PKCE(verifier: "v")
        let url = OAuthFlow.authorizeURL(pkce: pkce, state: "st8")

        XCTAssertEqual(url.host, "claude.com")
        XCTAssertEqual(url.path, "/cai/oauth/authorize")

        // Assert on the RAW wire query — this is what must match Claude Code
        // byte-for-byte (redirect_uri/scope fully percent-encoded, spaces as +).
        let raw = URLComponents(url: url, resolvingAgainstBaseURL: false)!.percentEncodedQuery!
        XCTAssertTrue(raw.contains("client_id=9d1c250a-e61b-44d9-88ed-5944d1962f5e"))
        XCTAssertTrue(raw.contains("response_type=code"))
        XCTAssertTrue(raw.contains("redirect_uri=https%3A%2F%2Fplatform.claude.com%2Foauth%2Fcode%2Fcallback"))
        XCTAssertTrue(raw.contains("scope=org%3Acreate_api_key+user%3Aprofile+user%3Ainference+user%3Asessions%3Aclaude_code+user%3Amcp_servers+user%3Afile_upload"))
        XCTAssertTrue(raw.contains("code_challenge_method=S256"))
        XCTAssertTrue(raw.contains("code_challenge=\(pkce.challenge)"))
        XCTAssertTrue(raw.contains("state=st8"))
    }

    func testFormURLEncodingMatchesURLSearchParams() {
        XCTAssertEqual(OAuthFlow.formURLEncoded("a b"), "a+b")
        XCTAssertEqual(OAuthFlow.formURLEncoded("user:profile"), "user%3Aprofile")
        XCTAssertEqual(
            OAuthFlow.formURLEncoded("https://x.com/y"),
            "https%3A%2F%2Fx.com%2Fy"
        )
    }

    func testParsePastedCode() {
        XCTAssertEqual(OAuthFlow.parsePastedCode("abc#xyz").code, "abc")
        XCTAssertEqual(OAuthFlow.parsePastedCode("abc#xyz").state, "xyz")
        XCTAssertEqual(OAuthFlow.parsePastedCode("  just-code\n").code, "just-code")
        XCTAssertNil(OAuthFlow.parsePastedCode("just-code").state)
    }

    func testTokenExchangeBody() throws {
        let data = OAuthFlow.tokenExchangeBody(code: "C", verifier: "V", state: "S")
        let json = try JSONSerialization.jsonObject(with: data) as! [String: String]
        XCTAssertEqual(json["grant_type"], "authorization_code")
        XCTAssertEqual(json["code"], "C")
        XCTAssertEqual(json["code_verifier"], "V")
        XCTAssertEqual(json["state"], "S")
        XCTAssertEqual(json["client_id"], OAuthConfig.clientID)
        XCTAssertEqual(json["redirect_uri"], OAuthConfig.redirectURI)
    }

    func testRefreshBody() throws {
        let data = OAuthFlow.refreshBody(refreshToken: "R")
        let json = try JSONSerialization.jsonObject(with: data) as! [String: String]
        XCTAssertEqual(json["grant_type"], "refresh_token")
        XCTAssertEqual(json["refresh_token"], "R")
        XCTAssertEqual(json["client_id"], OAuthConfig.clientID)
    }

    func testParseTokens() throws {
        let body = #"{"access_token":"at","refresh_token":"rt","expires_in":28800,"scope":"user:inference user:profile","token_type":"Bearer"}"#
            .data(using: .utf8)!
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let tokens = try OAuthFlow.parseTokens(body, now: now)
        XCTAssertEqual(tokens.accessToken, "at")
        XCTAssertEqual(tokens.refreshToken, "rt")
        XCTAssertEqual(tokens.scope, "user:inference user:profile")
        XCTAssertEqual(tokens.expiresAt, now.addingTimeInterval(28800))
        XCTAssertFalse(tokens.isExpired(now: now))
        XCTAssertTrue(tokens.isExpired(now: now.addingTimeInterval(28800)))
    }
}
