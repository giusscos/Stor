import Foundation

/// Inputs for SERP-based difficulty: rating volume of apps in the top 10.
struct SERPAppStrength: Equatable {
    var userRatingCount: Int
    var averageUserRating: Double
}

struct KeywordScore: Equatable {
    /// 0–100. Higher means harder to rank.
    var difficulty: Int
    /// 0–100. Higher means more worth chasing.
    var opportunity: Int
}

/// Opportunity and difficulty from popularity + SERP strength + current rank.
///
///     competition = clamp(0.7 * log10(avgTop10Ratings + 1) / 6 + 0.3 * brandShare, 0…1)
///     difficulty  = round(competition * 100)
///     opportunity = round(popularity * (1 - competition) * rankFactor)
enum KeywordScorer {
    /// Used when opportunity is derived without a SERP (vacancy = 1).
    static let unknownDifficulty = 0

    /// Rating-count threshold treated as a “brand” incumbent in the top 10.
    static let brandRatingThreshold = 50_000

    static func difficulty(topResults: [SERPAppStrength]) -> Int {
        Int((competition(topResults: topResults) * 100).rounded())
    }

    static func opportunity(popularity: Int, difficulty: Int, rank: Int?) -> Int {
        let pop = clamp(popularity)
        let vacancy = 1 - Double(clamp(difficulty)) / 100
        let value = Double(pop) * vacancy * rankFactor(rank)
        return clamp(Int(value.rounded()))
    }

    static func score(
        popularity: Int?,
        rank: Int?,
        topResults: [SERPAppStrength]
    ) -> KeywordScore {
        let difficulty = topResults.isEmpty ? unknownDifficulty : self.difficulty(topResults: topResults)
        let opportunity = self.opportunity(
            popularity: popularity ?? 0,
            difficulty: difficulty,
            rank: rank
        )
        return KeywordScore(difficulty: difficulty, opportunity: opportunity)
    }

    /// 0…1 competition from the top of the SERP.
    static func competition(topResults: [SERPAppStrength]) -> Double {
        let top = Array(topResults.prefix(10))
        guard !top.isEmpty else { return 0 }

        let avgCount = Double(top.map(\.userRatingCount).reduce(0, +)) / Double(top.count)
        // 1e6 ratings → 1.0. A handful of reviews stays well below 0.3.
        let logStrength = min(1, log10(avgCount + 1) / 6)
        let brandShare = Double(top.filter { $0.userRatingCount >= brandRatingThreshold }.count)
            / Double(top.count)
        return min(1, max(0, 0.7 * logStrength + 0.3 * brandShare))
    }

    /// Already ranking well reduces opportunity — the term is partly captured.
    static func rankFactor(_ rank: Int?) -> Double {
        guard let rank else { return 1 }
        switch rank {
        case 1...3: return 0.35
        case 4...10: return 0.55
        case 11...25: return 0.75
        case 26...50: return 0.9
        default: return 1
        }
    }

    private static func clamp(_ value: Int) -> Int {
        min(100, max(0, value))
    }
}

extension TrackedKeyword {
    /// Live opportunity from stored popularity, difficulty, and latest rank.
    var opportunity: Int? {
        guard let popularityScore else { return nil }
        return KeywordScorer.opportunity(
            popularity: popularityScore,
            difficulty: difficultyScore ?? KeywordScorer.unknownDifficulty,
            rank: rankPoints.last?.position
        )
    }
}
