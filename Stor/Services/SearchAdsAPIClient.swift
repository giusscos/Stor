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
        case .noCredentials:        return "No Apple Search Ads API credentials configured."
        case .tokenFailed(let m):   return "Token exchange failed: \(m)"
        case .httpError(let c, let m): return "Search Ads HTTP \(c): \(m.prefix(300))"
        }
    }
}

// MARK: - Client

/// OAuth Campaign Management API client (`.p8` keys) plus a thin facade over
/// [`AppleAdsWebClient`] for keyword popularity / recommendations, which require
/// an Apple Ads **web session** (dashboard cookies), not OAuth alone.
final class SearchAdsAPIClient {
    static let shared = SearchAdsAPIClient()

    private let base     = "https://api.searchads.apple.com/api/v5"
    private let tokenURL = URL(string: "https://appleid.apple.com/auth/oauth2/token")!

    private var cachedToken: String?
    private var tokenExpiry: Date?
    /// Identity of the credentials the cached token was issued for. Without this a token
    /// minted for one org keeps being sent after the user switches accounts.
    private var tokenOwner: String?

    // MARK: Popularity / recommendations (web session)

    /// Returns a popularity score 0–100 for `keyword` in `country`, or nil if unknown.
    /// Requires a saved Apple Ads web session (see `AppleAdsLoginView`).
    func fetchPopularity(
        keyword: String,
        country: String,
        adamId: Int64
    ) async throws -> Int? {
        let map = try await AppleAdsWebClient.shared.fetchPopularities(
            keywords: [keyword],
            adamId: adamId,
            country: country
        )
        return map[keyword.lowercased()]
    }

    /// Related keyword rows (text + optional popularity) for a seed query.
    func fetchRecommendations(
        seed: String,
        country: String,
        adamId: Int64,
        limit: Int = 25
    ) async throws -> [SpotlightSuggestion] {
        try await AppleAdsWebClient.shared.fetchRecommendations(
            seed: seed,
            adamId: adamId,
            country: country,
            limit: limit
        )
    }

    /// Refreshes popularity scores in-place, keeping going when individual terms fail so
    /// one bad keyword cannot discard the whole batch.
    @discardableResult
    func refreshPopularity(
        keywords: [TrackedKeyword],
        adamId: Int64
    ) async throws -> BatchOutcome {
        var outcome = BatchOutcome(total: keywords.count)
        guard !keywords.isEmpty else { return outcome }

        // Batch by country to cut round-trips.
        let byCountry = Dictionary(grouping: keywords, by: \.country)
        for (country, group) in byCountry {
            do {
                let terms = group.map(\.term)
                let scores = try await AppleAdsWebClient.shared.fetchPopularities(
                    keywords: terms,
                    adamId: adamId,
                    country: country
                )
                for kw in group {
                    if let score = scores[kw.term.lowercased()] {
                        kw.popularityScore = score
                        kw.popularityLastUpdated = .now
                        outcome.succeeded += 1
                    } else {
                        // Apple often omits low-volume terms; treat as unknown, not failure.
                        outcome.succeeded += 1
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                for kw in group {
                    outcome.failures.append(.init(term: kw.term, message: error.localizedDescription))
                }
            }
        }
        return outcome
    }

    struct BatchOutcome {
        struct Failure {
            let term: String
            let message: String
        }

        let total: Int
        var succeeded = 0
        var failures: [Failure] = []

        var didPartiallyFail: Bool { !failures.isEmpty && succeeded > 0 }
        var didCompletelyFail: Bool { succeeded == 0 && !failures.isEmpty }

        /// User-facing summary, or nil when everything succeeded.
        var summary: String? {
            guard !failures.isEmpty else { return nil }
            let detail = failures.prefix(3).map(\.term).joined(separator: ", ")
            let suffix = failures.count > 3 ? " and \(failures.count - 3) more" : ""
            if succeeded == 0 {
                return "All \(total) keywords failed. First error: \(failures[0].message)"
            }
            return "Updated \(succeeded) of \(total). Failed: \(detail)\(suffix)."
        }
    }

    // MARK: - OAuth helpers (Campaign Management API)

    /// Drops any cached token. Call after credentials change or are removed.
    func invalidateToken() {
        cachedToken = nil
        tokenExpiry = nil
        tokenOwner = nil
    }

    /// First adamId found on a campaign in the org (owned-app fallback).
    func firstCampaignAdamId(credentials: SearchAdsCredentials) async throws -> Int64? {
        let token = try await accessToken(for: credentials)
        guard let url = URL(string: "\(base)/campaigns?limit=20") else { return nil }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if !credentials.orgId.isEmpty {
            req.setValue("orgId=\(credentials.orgId)", forHTTPHeaderField: "X-AP-Context")
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SearchAdsError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else { return nil }

        for item in items {
            if let id = item["adamId"] as? Int64 { return id }
            if let id = item["adamId"] as? Int { return Int64(id) }
            if let id = item["adamId"] as? Double { return Int64(id) }
            if let nested = item["adam"] as? [String: Any] {
                if let id = nested["adamId"] as? Int64 { return id }
                if let id = nested["adamId"] as? Int { return Int64(id) }
            }
        }
        return nil
    }

    // MARK: - Token

    private func accessToken(for credentials: SearchAdsCredentials) async throws -> String {
        let owner = credentials.cacheIdentity
        if let t = cachedToken, let exp = tokenExpiry, tokenOwner == owner, Date() < exp { return t }

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
        tokenOwner   = owner
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
}

/// A related keyword from Apple Ads recommendations / popularity lookup.
struct SpotlightSuggestion: Hashable {
    let text: String
    let score: Int?
}
