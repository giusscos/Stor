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
}

// Isolated module: checks App Store search ranking via the public iTunes Search API.
// Rate limits are undocumented — keep batches small and add delays if you hit 429s.
final class RankingChecker {
    static let shared = RankingChecker()
    private init() {}

    /// Delay inserted between sequential SERP requests during batch checks.
    static let batchDelayNanoseconds: UInt64 = 350_000_000

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

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return [] }

        return results.enumerated().compactMap { index, result in
            guard let bundleId = result["bundleId"] as? String,
                  let name = result["trackName"] as? String else { return nil }
            let trackId: Int64
            if let n = result["trackId"] as? Int64 {
                trackId = n
            } else if let n = result["trackId"] as? Int {
                trackId = Int64(n)
            } else if let n = result["trackId"] as? Double {
                trackId = Int64(n)
            } else {
                return nil
            }
            let subtitle = result["subtitle"] as? String
            let iconURL = (result["artworkUrl512"] as? String)
                ?? (result["artworkUrl100"] as? String)
            return SearchResult(
                rank: index + 1,
                trackId: trackId,
                bundleId: bundleId,
                name: name,
                subtitle: subtitle,
                iconURL: iconURL
            )
        }
    }

    /// Returns 1-indexed position of the app in search results, or nil if not in top 200.
    func checkRanking(bundleId: String, keyword: String, country: String) async throws -> Int? {
        let results = try await search(keyword: keyword, country: country, limit: 200)
        return results.first(where: { $0.bundleId == bundleId })?.rank
    }
}
