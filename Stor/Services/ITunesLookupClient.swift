import Foundation

/// Public App Store metadata from the iTunes Lookup API.
struct ITunesAppLookup: Hashable {
    let trackId: Int64
    let bundleId: String
    let name: String
    let subtitle: String?
    let iconURL: String?
    /// Comma-separated listing keywords (live public metadata).
    let keywords: String?
    let description: String?
}

final class ITunesLookupClient {
    static let shared = ITunesLookupClient()
    private init() {}

    func lookup(bundleId: String) async throws -> ITunesAppLookup? {
        var comps = URLComponents(string: "https://itunes.apple.com/lookup")!
        comps.queryItems = [
            URLQueryItem(name: "bundleId", value: bundleId),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "limit", value: "1")
        ]
        return try await fetchFirst(from: comps)
    }

    func lookup(trackId: Int64) async throws -> ITunesAppLookup? {
        var comps = URLComponents(string: "https://itunes.apple.com/lookup")!
        comps.queryItems = [
            URLQueryItem(name: "id", value: String(trackId)),
            URLQueryItem(name: "entity", value: "software"),
            URLQueryItem(name: "limit", value: "1")
        ]
        return try await fetchFirst(from: comps)
    }

    /// Icon URL only — used by the sidebar when `AppRecord.iconURL` is missing.
    func fetchIconURL(bundleId: String) async -> String? {
        (try? await lookup(bundleId: bundleId))?.iconURL
    }

    /// Tokenize listing keywords + simple title/subtitle/description words for suggestions.
    func suggestionTerms(from lookup: ITunesAppLookup) -> [String] {
        var terms: [String] = []
        if let keywords = lookup.keywords {
            terms.append(contentsOf: keywords
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty })
        }
        for raw in [lookup.name, lookup.subtitle].compactMap({ $0 }) {
            terms.append(contentsOf: tokenize(raw))
        }
        // Light description harvest: first ~40 tokens, skip very short noise.
        if let description = lookup.description {
            terms.append(contentsOf: tokenize(description).prefix(40))
        }
        var seen = Set<String>()
        var unique: [String] = []
        for term in terms {
            let key = term.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            unique.append(term)
        }
        return unique
    }

    // MARK: - Private

    private func fetchFirst(from comps: URLComponents) async throws -> ITunesAppLookup? {
        guard let url = comps.url else { return nil }
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let result = results.first else { return nil }
        return parse(result)
    }

    private func parse(_ result: [String: Any]) -> ITunesAppLookup? {
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
        return ITunesAppLookup(
            trackId: trackId,
            bundleId: bundleId,
            name: name,
            subtitle: result["subtitle"] as? String,
            iconURL: (result["artworkUrl512"] as? String) ?? (result["artworkUrl100"] as? String),
            keywords: result["keywords"] as? String,
            description: result["description"] as? String
        )
    }

    private func tokenize(_ text: String) -> [String] {
        text
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.count >= 3 }
    }
}
