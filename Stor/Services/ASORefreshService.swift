import Foundation
import SwiftData

/// Popularity + ranking refresh used by the Keywords tab and the background scheduler.
enum ASORefreshService {
    @MainActor
    static func resolveAdamId(for app: AppRecord) async throws -> Int64 {
        if let cached = app.adamId { return cached }
        let id = try await AppleAdsWebClient.shared.resolveAdamId(bundleId: app.bundleId)
        app.adamId = id
        return id
    }

    @MainActor
    @discardableResult
    static func refreshPopularity(keywords: [TrackedKeyword], adamId: Int64) async throws -> SearchAdsAPIClient.BatchOutcome {
        try await SearchAdsAPIClient.shared.refreshPopularity(keywords: keywords, adamId: adamId)
    }

    /// One SERP per keyword: stores rank history and updates difficulty from the top 10.
    @MainActor
    static func checkRankings(
        bundleId: String,
        keywords: [TrackedKeyword],
        context: ModelContext
    ) async throws {
        for (index, keyword) in keywords.enumerated() {
            try Task.checkCancellation()
            if index > 0 {
                try await Task.sleep(nanoseconds: RankingChecker.batchDelayNanoseconds)
            }
            let results = try await RankingChecker.shared.search(
                keyword: keyword.term,
                country: keyword.country,
                limit: 200
            )
            let position = results.first(where: { $0.bundleId == bundleId })?.rank
            let ranking = KeywordRanking(checkedAt: .now, position: position, country: keyword.country)
            ranking.keyword = keyword
            keyword.rankingHistory.append(ranking)
            context.insert(ranking)

            let top10 = Array(results.prefix(10))
            keyword.difficultyScore = KeywordScorer.difficulty(topResults: top10.map(\.strength))
        }
    }

    /// Full ASO pass for scheduled refresh: popularity (if signed in) then ranks.
    @MainActor
    static func refreshAll(app: AppRecord, context: ModelContext) async throws {
        let keywords = app.trackedKeywords
        guard !keywords.isEmpty else {
            app.lastASORefreshAt = .now
            return
        }

        if (try? KeychainService.shared.loadAppleAdsWebSession()) != nil {
            do {
                let adamId = try await resolveAdamId(for: app)
                _ = try await refreshPopularity(keywords: keywords, adamId: adamId)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Rankings can still run if Ads is down.
            }
        }

        try await checkRankings(bundleId: app.bundleId, keywords: keywords, context: context)
        app.lastASORefreshAt = .now
    }
}
