import Foundation

// Isolated module: checks App Store search ranking via the public iTunes Search API.
// Rate limits are undocumented — keep batches small and add delays if you hit 429s.
final class RankingChecker {
    static let shared = RankingChecker()
    private init() {}

    /// Returns 1-indexed position of the app in search results, or nil if not in top 200.
    func checkRanking(bundleId: String, keyword: String, country: String) async throws -> Int? {
        var comps = URLComponents(string: "https://itunes.apple.com/search")!
        comps.queryItems = [
            URLQueryItem(name: "term",    value: keyword),
            URLQueryItem(name: "country", value: country),
            URLQueryItem(name: "entity",  value: "software"),
            URLQueryItem(name: "limit",   value: "200")
        ]
        guard let url = comps.url else { return nil }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]] else { return nil }

        for (index, result) in results.enumerated() {
            if let bid = result["bundleId"] as? String, bid == bundleId {
                return index + 1
            }
        }
        return nil
    }
}
