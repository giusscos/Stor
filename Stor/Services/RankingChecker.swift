import Foundation

/// A single app row from an iTunes Search SERP.
struct SearchResult: Identifiable, Hashable {
    var id: String { bundleId }
    let rank: Int
    let trackId: Int64
    let bundleId: String
    let name: String
    let subtitle: String?
    let iconURL: String?
    let userRatingCount: Int
    let averageUserRating: Double

    var strength: SERPAppStrength {
        SERPAppStrength(userRatingCount: userRatingCount, averageUserRating: averageUserRating)
    }
}

// Isolated module: checks App Store search ranking via the public iTunes Search API.
// Rate limits are undocumented — keep batches small and back off on 429/5xx.
final class RankingChecker {
    static let shared = RankingChecker()
    private init() {}

    /// Delay inserted between sequential SERP requests during batch checks.
    static let batchDelayNanoseconds: UInt64 = 350_000_000

    private static let maxAttempts = 4

    /// Returns parsed search results (1-indexed rank), up to `limit` (max 200).
    func search(keyword: String, country: String, limit: Int = 200) async throws -> [SearchResult] {
        let capped = min(max(limit, 1), 200)
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "term",    value: keyword),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "entity",  value: "software"),
            URLQueryItem(name: "limit",   value: String(capped))
        ]
        guard let url = comps.url else { return [] }

        let data = try await get(url)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }

        return results.enumerated().compactMap { index, result in
            parseResult(result, rank: index + 1)
        }
    }

    /// Returns 1-indexed position of the app in search results, or nil if not in top 200.
    func checkRanking(bundleId: String, keyword: String, country: String) async throws -> Int? {
        let results = try await search(keyword: keyword, country: country, limit: 200)
        return results.first(where: { $0.bundleId == bundleId })?.rank
    }

    // MARK: - Private

    private func parseResult(_ result: [String: Any], rank: Int) -> SearchResult? {
        guard let bundleId = result["bundleId"] as? String,
              let name = result["trackName"] as? String else { return nil }
        guard let trackId = int64(result["trackId"]) else { return nil }
        let subtitle = result["subtitle"] as? String
        let iconURL = (result["artworkUrl512"] as? String)
            ?? (result["artworkUrl100"] as? String)
        return SearchResult(
            rank: rank,
            trackId: trackId,
            bundleId: bundleId,
            name: name,
            subtitle: subtitle,
            iconURL: iconURL,
            userRatingCount: intValue(result["userRatingCount"])
                ?? intValue(result["userRatingCountForCurrentVersion"])
                ?? 0,
            averageUserRating: doubleValue(result["averageUserRating"])
                ?? doubleValue(result["averageUserRatingForCurrentVersion"])
                ?? 0
        )
    }

    private func get(_ url: URL) async throws -> Data {
        var lastStatus = 0
        for attempt in 0..<Self.maxAttempts {
            if attempt > 0 {
                try await Task.sleep(for: Self.backoff(forAttempt: attempt))
            }
            let (data, response) = try await URLSession.shared.data(from: url)
            if let http = response as? HTTPURLResponse {
                if (200..<300).contains(http.statusCode) { return data }
                lastStatus = http.statusCode
                let retryable = http.statusCode == 429 || (500..<600).contains(http.statusCode)
                guard retryable else { throw URLError(.badServerResponse) }
            } else {
                return data
            }
        }
        throw lastStatus == 429
            ? URLError(.resourceUnavailable)
            : URLError(.badServerResponse)
    }

    private static func backoff(forAttempt attempt: Int) -> Duration {
        let seconds = pow(2.0, Double(attempt - 1))
        let jitter = Double.random(in: 0...0.3)
        return .seconds(seconds + jitter)
    }

    private func int64(_ value: Any?) -> Int64? {
        if let n = value as? Int64 { return n }
        if let n = value as? Int { return Int64(n) }
        if let n = value as? Double { return Int64(n) }
        return nil
    }

    private func intValue(_ value: Any?) -> Int? {
        if let n = value as? Int { return n }
        if let n = value as? Int64 { return Int(n) }
        if let n = value as? Double { return Int(n) }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let n = value as? Double { return n }
        if let n = value as? Int { return Double(n) }
        if let n = value as? Int64 { return Double(n) }
        return nil
    }
}
