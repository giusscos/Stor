import Foundation
import CryptoKit

// MARK: - Token response

private struct TokenResponse: Codable {
    let accessToken: String
    let expiresIn: Int
    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn   = "expires_in"
    }
}

// MARK: - Error

enum SearchAdsError: LocalizedError {
    case noCredentials
    case tokenFailed(String)
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .noCredentials:        return "No Apple Search Ads credentials configured."
        case .tokenFailed(let m):   return "Token exchange failed: \(m)"
        case .httpError(let c, let m): return "Search Ads HTTP \(c): \(m.prefix(300))"
        }
    }
}

// MARK: - Client

final class SearchAdsAPIClient {
    static let shared = SearchAdsAPIClient()

    private let base     = "https://api.searchads.apple.com/api/v5"
    private let tokenURL = URL(string: "https://appleid.apple.com/auth/oauth2/token")!

    private var cachedToken: String?
    private var tokenExpiry: Date?

    // MARK: Public

    /// Returns a popularity score 0–100 for `keyword` in `country`, or nil if unknown.
    func fetchPopularity(
        keyword: String,
        country: String,
        credentials: SearchAdsCredentials
    ) async throws -> Int? {
        let token = try await accessToken(for: credentials)

        var comps = URLComponents(string: "\(base)/search/keywords/spotlight")!
        comps.queryItems = [
            .init(name: "query",           value: keyword),
            .init(name: "limit",           value: "20"),
            .init(name: "countryOrRegion", value: country)
        ]
        guard let url = comps.url else { return nil }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if !credentials.orgId.isEmpty {
            req.setValue("orgId=\(credentials.orgId)", forHTTPHeaderField: "X-AP-Context")
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SearchAdsError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        return extractScore(for: keyword, from: data)
    }

    /// Refreshes popularity scores for all keywords and updates them in-place.
    func refreshPopularity(
        keywords: [TrackedKeyword],
        credentials: SearchAdsCredentials
    ) async throws {
        for kw in keywords {
            let score = try await fetchPopularity(keyword: kw.term, country: kw.country, credentials: credentials)
            kw.popularityScore = score
            kw.popularityLastUpdated = .now
        }
    }

    // MARK: Token

    private func accessToken(for credentials: SearchAdsCredentials) async throws -> String {
        if let t = cachedToken, let exp = tokenExpiry, Date() < exp { return t }

        let assertion = try clientAssertion(credentials: credentials)

        var req = URLRequest(url: tokenURL)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let params: [String: String] = [
            "grant_type":    "client_credentials",
            "client_id":     credentials.clientId,
            "client_secret": assertion,
            "scope":         "searchadsorg"
        ]
        req.httpBody = params
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SearchAdsError.tokenFailed(String(data: data, encoding: .utf8) ?? "Unknown")
        }

        let tr = try JSONDecoder().decode(TokenResponse.self, from: data)
        cachedToken  = tr.accessToken
        tokenExpiry  = Date().addingTimeInterval(TimeInterval(tr.expiresIn - 60))
        return tr.accessToken
    }

    private func clientAssertion(credentials: SearchAdsCredentials) throws -> String {
        let now = Date()
        let header  = try b64url(["alg": "ES256", "kid": credentials.keyId])
        let payload = try b64url([
            "sub": credentials.clientId,
            "aud": "https://appleid.apple.com",
            "iat": Int(now.timeIntervalSince1970),
            "exp": Int(now.timeIntervalSince1970) + 180,
            "iss": credentials.teamId
        ] as [String: Any])

        let input = "\(header).\(payload)"
        let key   = try P256.Signing.PrivateKey(pemRepresentation: credentials.privateKeyPEM)
        let sig   = try key.signature(for: Data(input.utf8))
        return "\(input).\(sig.rawRepresentation.base64URLEncoded())"
    }

    private func b64url(_ dict: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys])
        return data.base64URLEncoded()
    }

    // MARK: Score extraction

    private func extractScore(for keyword: String, from data: Data) -> Int? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else { return nil }

        let target = keyword.lowercased()
        for item in items {
            guard (item["text"] as? String)?.lowercased() == target else { continue }
            // Field name varies across API versions; try all known names
            for key in ["score", "popularity", "impressionShare"] {
                if let v = item[key] as? Int    { return min(100, max(0, v)) }
                if let v = item[key] as? Double { return min(100, max(0, Int(v * 100))) }
            }
        }
        // Keyword not found in suggestions → treat as low volume
        return items.isEmpty ? nil : 0
    }
}
