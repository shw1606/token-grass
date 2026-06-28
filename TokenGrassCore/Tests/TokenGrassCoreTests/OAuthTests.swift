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
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        XCTAssertEqual(url.host, "platform.claude.com")
        XCTAssertEqual(url.path, "/oauth/authorize")
        XCTAssertEqual(value("client_id"), OAuthConfig.clientID)
        XCTAssertEqual(value("response_type"), "code")
        XCTAssertEqual(value("redirect_uri"), OAuthConfig.redirectURI)
        XCTAssertEqual(value("code_challenge_method"), "S256")
        XCTAssertEqual(value("code_challenge"), pkce.challenge)
        XCTAssertEqual(value("scope"), "user:inference user:profile")
        XCTAssertEqual(value("state"), "st8")
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
