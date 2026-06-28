import Foundation

enum UsageClientError: Error, LocalizedError {
    case http(Int, String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .http(let code, let body): return "HTTP \(code): \(body.prefix(160))"
        case .badResponse: return "bad response"
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
        request.timeoutInterval = 20

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageClientError.badResponse }
        guard http.statusCode == 200 else {
            throw UsageClientError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }
        return data
    }
}
