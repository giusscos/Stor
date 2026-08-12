import Foundation
import SwiftData

struct CompetitorScanHit: Identifiable, Hashable {
    var id: String { term.lowercased() }
    let term: String
    let source: String
    let position: Int?
    var popularity: Int?

    var isRanking: Bool { position != nil }
}

/// Local reverse-SERP: seed from a competitor’s listing, optionally expand via Ads,
/// then check whether that competitor appears in each term’s search results.
enum CompetitorKeywordScanner {
    static let maxSeeds = 8
    static let maxCandidates = 30
    static let recommendationsPerSeed = 8

    @MainActor
    static func scan(
        competitor: CompetitorApp,
        country: String,
        adamId: Int64?,
        hasAdsSession: Bool,
        context: ModelContext,
        onProgress: (@MainActor (String) -> Void)? = nil
    ) async throws -> [CompetitorScanHit] {
        var collected: [String: (term: String, source: String)] = [:]

        onProgress?("Looking up \(competitor.name)…")
        var lookup = try await ITunesLookupClient.shared.lookup(bundleId: competitor.bundleId)
        if lookup == nil {
            lookup = try await ITunesLookupClient.shared.lookup(trackId: competitor.trackId)
        }
        if let lookup {
            let terms = ITunesLookupClient.shared.suggestionTerms(from: lookup)
            for term in terms.prefix(20) {
                let key = term.lowercased()
                if collected[key] == nil {
                    collected[key] = (term, "Listing · \(competitor.name)")
                }
            }
        }

        if hasAdsSession, let adamId {
            let seeds = Array(collected.values.prefix(maxSeeds))
            for seed in seeds {
                try Task.checkCancellation()
                onProgress?("Ads suggestions from “\(seed.term)”…")
                do {
                    let rows = try await SearchAdsAPIClient.shared.fetchRecommendations(
                        seed: seed.term,
                        country: country,
                        adamId: adamId,
                        limit: recommendationsPerSeed
                    )
                    for row in rows {
                        let key = row.text.lowercased()
                        if collected[key] == nil {
                            collected[key] = (row.text, "Apple Ads · from “\(seed.term)”")
                        }
                    }
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    continue
                }
            }
        }

        let candidates = Array(collected.values.prefix(maxCandidates))
        var hits: [CompetitorScanHit] = []

        for (index, candidate) in candidates.enumerated() {
            try Task.checkCancellation()
            onProgress?("Checking \(index + 1) of \(candidates.count): “\(candidate.term)”")
            if index > 0 {
                try await Task.sleep(nanoseconds: RankingChecker.batchDelayNanoseconds)
            }
            let results = try await RankingChecker.shared.search(
                keyword: candidate.term,
                country: country,
                limit: 200
            )
            let position = results.first(where: { $0.bundleId == competitor.bundleId })?.rank
            let ranking = CompetitorKeywordRanking(
                term: candidate.term,
                country: country,
                position: position,
                checkedAt: .now
            )
            ranking.competitor = competitor
            competitor.rankingHistory.append(ranking)
            context.insert(ranking)
            hits.append(
                CompetitorScanHit(
                    term: candidate.term,
                    source: candidate.source,
                    position: position
                )
            )
        }

        return hits.sorted { lhs, rhs in
            switch (lhs.position, rhs.position) {
            case let (l?, r?):
                if l != r { return l < r }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                break
            }
            return lhs.term.localizedCaseInsensitiveCompare(rhs.term) == .orderedAscending
        }
    }
}
