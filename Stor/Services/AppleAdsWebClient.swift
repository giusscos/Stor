import Foundation

/// Unofficial Apple Ads Campaign Management web APIs used for Search Popularity
/// and keyword recommendations (same class of endpoints Astro / ASO tools use).
final class AppleAdsWebClient {
    static let shared = AppleAdsWebClient()

    private let base = "https://app-ads.apple.com/cm/api/v2"
    private var ownedAdamIdCache: Int64?

    private init() {}

    func clearCaches() {
        ownedAdamIdCache = nil
    }

    // MARK: - Public

    /// Popularity scores (typically 5–100) keyed by lowercased keyword text.
    ///
    /// CM contract (dashboard):
    /// `POST /cm/api/v2/keywords/popularities?adamId=…`
    /// body `{ "storefronts": ["US"], "terms": ["keyword", …] }`
    /// response `data: [{ "name": "keyword", "popularity": 45 }, …]`
    func fetchPopularities(
        keywords: [String],
        adamId: Int64,
        country: String
    ) async throws -> [String: Int] {
        let cleaned = keywords
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return [:] }

        let storefront = country.uppercased()
        // Prefer the selected storefront; some sessions only accept the empty list
        // (org default / US) — retry once on generic 400 Client Error.
        do {
            let data = try await post(
                path: "/keywords/popularities",
                query: ["adamId": String(adamId)],
                body: [
                    "storefronts": [storefront],
                    "terms": cleaned
                ],
                adamId: adamId
            )
            return parsePopularities(from: data)
        } catch let error as AppleAdsWebError {
            guard case .httpError(400, _) = error else { throw error }
            let data = try await post(
                path: "/keywords/popularities",
                query: ["adamId": String(adamId)],
                body: [
                    "storefronts": [] as [String],
                    "terms": cleaned
                ],
                adamId: adamId
            )
            return parsePopularities(from: data)
        }
    }

    /// Related keyword recommendations for a seed term.
    func fetchRecommendations(
        seed: String,
        adamId: Int64,
        country: String,
        limit: Int = 25
    ) async throws -> [SpotlightSuggestion] {
        let text = seed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }

        let storefront = country.uppercased()
        let bodies: [[String: Any]] = [
            [
                "storefronts": [storefront],
                "text": text,
                "limit": limit
            ],
            [
                "storefronts": [storefront],
                "terms": [text],
                "limit": limit
            ],
            [
                "storefronts": [] as [String],
                "text": text,
                "limit": limit
            ]
        ]

        var lastError: Error?
        for body in bodies {
            do {
                let data = try await post(
                    path: "/keywords/recommendation",
                    query: ["adamId": String(adamId)],
                    body: body,
                    adamId: adamId
                )
                return parseRecommendations(from: data, limit: limit)
            } catch let error as AppleAdsWebError {
                if case .httpError(400, _) = error {
                    lastError = error
                    continue
                }
                if case .httpError(404, _) = error {
                    lastError = error
                    continue
                }
                throw error
            }
        }
        if let lastError { throw lastError }
        return []
    }

    /// Resolve App Store adamId for a bundle, caching on success.
    func resolveAdamId(bundleId: String) async throws -> Int64 {
        if let lookup = try await ITunesLookupClient.shared.lookup(bundleId: bundleId) {
            return lookup.trackId
        }
        throw AppleAdsWebError.decodeFailed
    }

    // MARK: - Networking

    private func loadSession() throws -> AppleAdsWebSession {
        guard let session = try KeychainService.shared.loadAppleAdsWebSession(),
              !session.isEmpty else {
            throw AppleAdsWebError.noSession
        }
        return session
    }

    private func post(
        path: String,
        query: [String: String],
        body: [String: Any],
        adamId: Int64
    ) async throws -> Data {
        do {
            return try await performPost(path: path, query: query, body: body)
        } catch let error as AppleAdsWebError {
            if case .ownedAppRequired = error {
                let owned = try await fetchOwnedAdamId()
                guard owned != adamId else { throw error }
                var retryQuery = query
                retryQuery["adamId"] = String(owned)
                return try await performPost(path: path, query: retryQuery, body: body)
            }
            throw error
        }
    }

    private func performPost(
        path: String,
        query: [String: String],
        body: [String: Any]
    ) async throws -> Data {
        let session = try loadSession()
        var comps = URLComponents(string: base + path)!
        if !query.isEmpty {
            comps.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }
        guard let url = comps.url else {
            throw AppleAdsWebError.decodeFailed
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")
        if let xsrf = session.xsrfToken, !xsrf.isEmpty {
            request.setValue(xsrf, forHTTPHeaderField: "X-XSRF-TOKEN-CM")
        }
        request.setValue("https://app-ads.apple.com", forHTTPHeaderField: "Origin")
        request.setValue("https://app-ads.apple.com/", forHTTPHeaderField: "Referer")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AppleAdsWebError.decodeFailed
        }

        let text = String(data: data, encoding: .utf8) ?? ""

        if http.statusCode == 401 {
            throw AppleAdsWebError.sessionExpired
        }

        // 403 can be session expiry OR "app not linked to Ads org".
        if http.statusCode == 403 {
            if text.contains("KWS_NO_ORG_CONTENT_PROVIDERS")
                || text.contains("NO_USER_OWNED_APPS_FOUND") {
                throw AppleAdsWebError.ownedAppRequired
            }
            throw AppleAdsWebError.sessionExpired
        }

        // CM sometimes returns HTTP 200 with status:"error" in the JSON envelope.
        if let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let status = root["status"] as? String,
           status.caseInsensitiveCompare("error") == .orderedSame
            || status.caseInsensitiveCompare("failure") == .orderedSame {
            if text.contains("KWS_NO_ORG_CONTENT_PROVIDERS")
                || text.contains("NO_USER_OWNED_APPS_FOUND") {
                throw AppleAdsWebError.ownedAppRequired
            }
            throw AppleAdsWebError.httpError(http.statusCode, text)
        }

        if !(200..<300).contains(http.statusCode) {
            if text.contains("NO_USER_OWNED_APPS_FOUND")
                || text.contains("KWS_NO_ORG_CONTENT_PROVIDERS") {
                throw AppleAdsWebError.ownedAppRequired
            }
            throw AppleAdsWebError.httpError(http.statusCode, text)
        }

        return data
    }

    /// Best-effort owned adamId from the Ads account (campaigns list).
    private func fetchOwnedAdamId() async throws -> Int64 {
        if let cached = ownedAdamIdCache { return cached }

        // Prefer OAuth Campaign API when .p8 credentials exist.
        if let credentials = try? KeychainService.shared.loadSearchAds() {
            if let id = try? await SearchAdsAPIClient.shared.firstCampaignAdamId(credentials: credentials) {
                ownedAdamIdCache = id
                return id
            }
        }

        // Fallback: CM apps list (shape varies; parse leniently).
        let session = try loadSession()
        guard let url = URL(string: "https://app-ads.apple.com/cm/api/v1/apps") else {
            throw AppleAdsWebError.ownedAppRequired
        }
        var request = URLRequest(url: url)
        request.setValue(session.cookieHeader, forHTTPHeaderField: "Cookie")
        if let xsrf = session.xsrfToken, !xsrf.isEmpty {
            request.setValue(xsrf, forHTTPHeaderField: "X-XSRF-TOKEN-CM")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw AppleAdsWebError.ownedAppRequired
        }
        if let id = firstAdamId(in: data) {
            ownedAdamIdCache = id
            return id
        }
        throw AppleAdsWebError.ownedAppRequired
    }

    // MARK: - Parsing

    private func parsePopularities(from data: Data) -> [String: Int] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [:] }
        var result: [String: Int] = [:]

        func ingest(_ text: String?, _ score: Int?) {
            guard let text, !text.isEmpty, let score else { return }
            result[text.lowercased()] = min(100, max(0, score))
        }

        // Preferred contract: { data: [ { name, popularity }, … ] }
        if let dict = root as? [String: Any],
           let items = dict["data"] as? [[String: Any]] {
            for item in items {
                let text = (item["name"] as? String)
                    ?? (item["text"] as? String)
                    ?? (item["keyword"] as? String)
                let score = intValue(item["popularity"])
                    ?? intValue(item["searchPopularity"])
                    ?? intValue(item["score"])
                // Apple may return popularity: null for low-volume terms — skip.
                ingest(text, score)
            }
            if !result.isEmpty { return result }
        }

        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                let text = (dict["name"] as? String)
                    ?? (dict["text"] as? String)
                    ?? (dict["keyword"] as? String)
                    ?? (dict["query"] as? String)
                let score = intValue(dict["popularity"])
                    ?? intValue(dict["searchPopularity"])
                    ?? intValue(dict["score"])
                    ?? intValue(dict["popularityScore"])
                ingest(text, score)
                for value in dict.values { walk(value) }
            } else if let array = node as? [Any] {
                for item in array { walk(item) }
            }
        }

        walk(root)
        return result
    }

    private func parseRecommendations(from data: Data, limit: Int) -> [SpotlightSuggestion] {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return [] }
        var rows: [SpotlightSuggestion] = []
        var seen = Set<String>()

        func ingest(_ text: String?, _ score: Int?) {
            guard let text, !text.isEmpty else { return }
            let key = text.lowercased()
            guard !seen.contains(key) else { return }
            seen.insert(key)
            let clamped = score.map { min(100, max(0, $0)) }
            rows.append(SpotlightSuggestion(text: text, score: clamped))
        }

        func walk(_ node: Any) {
            if let dict = node as? [String: Any] {
                let text = (dict["text"] as? String)
                    ?? (dict["name"] as? String)
                    ?? (dict["keyword"] as? String)
                    ?? (dict["query"] as? String)
                let score = intValue(dict["popularity"])
                    ?? intValue(dict["searchPopularity"])
                    ?? intValue(dict["score"])
                    ?? intValue(dict["popularityScore"])
                // Only treat dicts that look like keyword rows.
                if text != nil, score != nil || dict["matchType"] != nil || dict["bidAmount"] != nil || dict["recommendation"] != nil {
                    ingest(text, score)
                } else if text != nil, dict.keys.contains(where: { ["popularity", "searchPopularity", "score", "popularityScore"].contains($0) }) {
                    ingest(text, score)
                } else if text != nil, dict.count <= 8, score != nil || dict["storefront"] != nil {
                    ingest(text, score)
                }

                for value in dict.values { walk(value) }
            } else if let array = node as? [Any] {
                for item in array { walk(item) }
            }
        }

        walk(root)

        // If walk was too strict, try a second pass that accepts any text+score pairs.
        if rows.isEmpty {
            func loose(_ node: Any) {
                if let dict = node as? [String: Any] {
                    let text = (dict["text"] as? String)
                        ?? (dict["name"] as? String)
                        ?? (dict["keyword"] as? String)
                    let score = intValue(dict["popularity"])
                        ?? intValue(dict["searchPopularity"])
                        ?? intValue(dict["score"])
                    ingest(text, score)
                    for value in dict.values { loose(value) }
                } else if let array = node as? [Any] {
                    for item in array { loose(item) }
                }
            }
            loose(root)
        }

        return Array(rows.prefix(limit))
    }

    private func firstAdamId(in data: Data) -> Int64? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var found: Int64?

        func walk(_ node: Any) {
            if found != nil { return }
            if let dict = node as? [String: Any] {
                if let id = int64Value(dict["adamId"]) ?? int64Value(dict["appAdamId"]) {
                    found = id
                    return
                }
                for value in dict.values { walk(value) }
            } else if let array = node as? [Any] {
                for item in array { walk(item) }
            }
        }

        walk(root)
        return found
    }

    private func intValue(_ any: Any?) -> Int? {
        switch any {
        case let v as Int: return v
        case let v as Int64: return Int(v)
        case let v as Double: return Int(v.rounded())
        case let v as NSNumber: return v.intValue
        case let v as String: return Int(v)
        default: return nil
        }
    }

    private func int64Value(_ any: Any?) -> Int64? {
        switch any {
        case let v as Int64: return v
        case let v as Int: return Int64(v)
        case let v as Double: return Int64(v)
        case let v as NSNumber: return v.int64Value
        case let v as String: return Int64(v)
        default: return nil
        }
    }
}
