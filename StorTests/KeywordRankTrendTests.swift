import Foundation
import Testing
@testable import AscendKit

/// Rank charts invert the usual "up is better" intuition — position 3 beats position 40 —
/// so the direction of every delta is asserted explicitly.
@MainActor
struct KeywordRankTrendTests {
    private func keyword(_ positions: [Int?]) -> TrackedKeyword {
        let keyword = TrackedKeyword(term: "collage")
        // Inserted newest-first to prove the accessors sort rather than trust input order.
        keyword.rankingHistory = positions.enumerated().reversed().map { index, position in
            KeywordRanking(
                checkedAt: Date(timeIntervalSince1970: 1_700_000_000 + Double(index) * 86_400),
                position: position
            )
        }
        return keyword
    }

    @Test func pointsAreReturnedOldestFirst() {
        let points = keyword([30, 20, 10]).rankPoints

        #expect(points.map(\.position) == [30, 20, 10])
        #expect(points.map(\.date) == points.map(\.date).sorted())
    }

    @Test func latestPointIsTheMostRecentCheck() {
        #expect(keyword([30, 20, 10]).latestRankPoint?.position == 10)
    }

    /// A smaller position number is a better rank, so improvement is a negative delta.
    @Test func improvingRankProducesANegativeDelta() {
        #expect(keyword([20, 10]).rankDelta == -10)
    }

    @Test func decliningRankProducesAPositiveDelta() {
        #expect(keyword([10, 25]).rankDelta == 15)
    }

    @Test func unchangedRankProducesZero() {
        #expect(keyword([10, 10]).rankDelta == 0)
    }

    @Test func deltaNeedsTwoRankedChecks() {
        #expect(keyword([10]).rankDelta == nil)
        #expect(keyword([]).rankDelta == nil)
    }

    /// Checks where the app didn't rank are kept as points but skipped by the delta, so a
    /// coverage gap doesn't read as a rank change.
    @Test func unrankedChecksAreExcludedFromTheDelta() {
        let keyword = keyword([20, nil, 10])

        #expect(keyword.rankPoints.count == 3)
        #expect(keyword.rankDelta == -10)
    }

    @Test func trailingUnrankedCheckIsStillTheLatestPoint() {
        let keyword = keyword([20, nil])

        #expect(keyword.latestRankPoint?.position == nil)
        #expect(keyword.latestRankPoint?.isRanking == false)
    }

    @Test func sparklineDescribesTheDirectionOfTravel() {
        let improving = keyword([40, 12]).rankPoints.filter(\.isRanking)
        let declining = keyword([12, 40]).rankPoints.filter(\.isRanking)
        let flat = keyword([12, 12]).rankPoints.filter(\.isRanking)

        #expect(RankSparkline.trendDescription(improving) == "Improved from position 40 to 12")
        #expect(RankSparkline.trendDescription(declining) == "Dropped from position 12 to 40")
        #expect(RankSparkline.trendDescription(flat) == "Unchanged at position 12")
        #expect(RankSparkline.trendDescription([]) == "No ranking data")
    }
}
