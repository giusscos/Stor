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
    /// Identity of the credentials the cached token was issued for. Without this a token
    /// minted for one org keeps being sent after the user switches accounts.
    private var tokenOwner: String?

    // MARK: Public

    /// Returns a popularity score 0–100 for `keyword` in `country`, or nil if unknown.
    func fetchPopularity(
        keyword: String,
        country: String,
        credentials: SearchAdsCredentials
    ) async throws -> Int? {
        let suggestions = try await fetchSpotlightSuggestions(
            query: keyword,
            country: country,
            credentials: credentials
        )
        let target = keyword.lowercased()
        // No exact row means Apple has no score for this term. Returning nil keeps that
        // distinct from a genuine zero so the keyword table can show "unknown".
        return suggestions.first(where: { $0.text.lowercased() == target })?.score
    }

    /// Spotlight suggestion rows (related terms + scores) for a query.
    func fetchSpotlightSuggestions(
        query: String,
        country: String,
        credentials: SearchAdsCredentials
    ) async throws -> [SpotlightSuggestion] {
        let token = try await accessToken(for: credentials)

        var comps = URLComponents(string: "\(base)/search/keywords/spotlight")!
        comps.queryItems = [
            .init(name: "query",           value: query),
            .init(name: "limit",           value: "20"),
            .init(name: "countryOrRegion", value: country)
        ]
        guard let url = comps.url else { return [] }

        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if !credentials.orgId.isEmpty {
            req.setValue("orgId=\(credentials.orgId)", forHTTPHeaderField: "X-AP-Context")
        }

        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw SearchAdsError.httpError(http.statusCode, String(data: data, encoding: .utf8) ?? "")
        }

        return parseSuggestions(from: data)
    }

    /// Refreshes popularity scores in-place, keeping going when individual terms fail so
    /// one bad keyword cannot discard the whole batch.
    @discardableResult
    func refreshPopularity(
        keywords: [TrackedKeyword],
        credentials: SearchAdsCredentials
    ) async throws -> BatchOutcome {
        var outcome = BatchOutcome(total: keywords.count)
        for kw in keywords {
            do {
                kw.popularityScore = try await fetchPopularity(
                    keyword: kw.term,
                    country: kw.country,
                    credentials: credentials
                )
                kw.popularityLastUpdated = .now
                outcome.succeeded += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                outcome.failures.append(.init(term: kw.term, message: error.localizedDescription))
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

    // MARK: - Token

    /// Drops any cached token. Call after credentials change or are removed.
    func invalidateToken() {
        cachedToken = nil
        tokenExpiry = nil
        tokenOwner = nil
    }

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

    // MARK: - Suggestions parsing

    private func parseSuggestions(from data: Data) -> [SpotlightSuggestion] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = json["data"] as? [[String: Any]] else { return [] }

        return items.compactMap { item in
            guard let text = item["text"] as? String, !text.isEmpty else { return nil }
            var score: Int?
            for key in ["score", "popularity", "impressionShare"] {
                if let v = item[key] as? Int {
                    score = min(100, max(0, v))
                    break
                }
                if let v = item[key] as? Double {
                    score = min(100, max(0, Int(v * 100)))
                    break
                }
            }
            return SpotlightSuggestion(text: text, score: score)
        }
    }
}

/// A related keyword from Apple Search Ads spotlight.
struct SpotlightSuggestion: Hashable {
    let text: String
    let score: Int?
}
