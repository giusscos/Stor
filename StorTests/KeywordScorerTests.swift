import Foundation
import Testing
@testable import Stor

struct KeywordScorerTests {
    private func apps(_ counts: [Int]) -> [SERPAppStrength] {
        counts.map { SERPAppStrength(userRatingCount: $0, averageUserRating: 4.5) }
    }

    @Test func emptySERPIsZeroCompetition() {
        #expect(KeywordScorer.competition(topResults: []) == 0)
        #expect(KeywordScorer.difficulty(topResults: []) == 0)
    }

    @Test func aHandfulOfReviewsStaysEasy() {
        let difficulty = KeywordScorer.difficulty(topResults: apps(Array(repeating: 20, count: 10)))
        #expect(difficulty < 30)
    }

    @Test func millionRatingIncumbentsAreHard() {
        let difficulty = KeywordScorer.difficulty(topResults: apps(Array(repeating: 1_000_000, count: 10)))
        #expect(difficulty >= 85)
    }

    @Test func brandShareRaisesDifficulty() {
        let mixed = KeywordScorer.difficulty(topResults: apps([80_000, 80_000, 80_000, 10, 10, 10, 10, 10, 10, 10]))
        let indie = KeywordScorer.difficulty(topResults: apps(Array(repeating: 10, count: 10)))
        #expect(mixed > indie)
    }

    @Test func opportunityFallsAsDifficultyRises() {
        let easy = KeywordScorer.opportunity(popularity: 80, difficulty: 10, rank: nil)
        let hard = KeywordScorer.opportunity(popularity: 80, difficulty: 90, rank: nil)
        #expect(easy > hard)
    }

    @Test func rankingFirstCutsOpportunity() {
        let unranked = KeywordScorer.opportunity(popularity: 80, difficulty: 20, rank: nil)
        let first = KeywordScorer.opportunity(popularity: 80, difficulty: 20, rank: 1)
        #expect(first < unranked)
        #expect(KeywordScorer.rankFactor(1) == 0.35)
        #expect(KeywordScorer.rankFactor(nil) == 1)
    }

    @Test func scoresClampToZeroThroughOneHundred() {
        let score = KeywordScorer.score(popularity: 400, rank: nil, topResults: [])
        #expect(score.difficulty == 0)
        #expect((0...100).contains(score.opportunity))
        #expect(KeywordScorer.opportunity(popularity: -4, difficulty: 0, rank: nil) == 0)
    }

    @Test func missingPopularityYieldsZeroOpportunity() {
        let score = KeywordScorer.score(
            popularity: nil,
            rank: nil,
            topResults: apps([1_000])
        )
        #expect(score.opportunity == 0)
        #expect(score.difficulty > 0)
    }
}

struct KeywordBudgetTests {
    @Test func encodeUsesCommasWithNoSpaces() {
        #expect(KeywordBudget.encode(["photo", "collage", "edit"]) == "photo,collage,edit")
    }

    @Test func parseTrimsAndDropsBlanks() {
        #expect(KeywordBudget.parse("photo, collage , ,edit") == ["photo", "collage", "edit"])
    }

    @Test func remainingCountsTowardTheHundredCharLimit() {
        #expect(KeywordBudget.remaining(in: String(repeating: "a", count: 90)) == 10)
        #expect(KeywordBudget.remaining(in: String(repeating: "a", count: 120)) == 0)
    }

    @Test func packingPrefersHigherOpportunityAndStaysUnderLimit() {
        let longA = String(repeating: "a", count: 40)
        let longB = String(repeating: "b", count: 40)
        let longC = String(repeating: "c", count: 40)
        let plan = KeywordBudget.pack(
            current: KeywordBudget.encode([longA, longC]),
            candidates: [
                KeywordBudgetCandidate(term: longA, opportunity: 90, currentlyListed: true),
                KeywordBudgetCandidate(term: longB, opportunity: 80, currentlyListed: false),
                KeywordBudgetCandidate(term: longC, opportunity: 5, currentlyListed: true)
            ]
        )

        #expect(plan.proposed.count <= KeywordBudget.limit)
        #expect(plan.proposed.contains(longA))
        #expect(plan.proposed.contains(longB))
        #expect(!plan.proposed.contains(longC))
        #expect(plan.added == [longB])
        #expect(plan.dropped == [longC])
        #expect(plan.didChange)
    }

    @Test func currentlyListedTermsWinTies() {
        let plan = KeywordBudget.pack(
            current: "alpha",
            candidates: [
                KeywordBudgetCandidate(term: "alpha", opportunity: 50, currentlyListed: true),
                KeywordBudgetCandidate(term: "beta", opportunity: 50, currentlyListed: false)
            ]
        )
        #expect(KeywordBudget.parse(plan.proposed).first == "alpha")
    }

    @Test func duplicatesAreCollapsedCaseInsensitively() {
        let plan = KeywordBudget.pack(
            current: "Photo",
            candidates: [
                KeywordBudgetCandidate(term: "photo", opportunity: 80, currentlyListed: false),
                KeywordBudgetCandidate(term: "PHOTO", opportunity: 10, currentlyListed: false)
            ]
        )
        #expect(KeywordBudget.parse(plan.proposed).count == 1)
    }

    @Test func emptyCurrentPacksFromCandidates() {
        let plan = KeywordBudget.pack(
            current: "",
            candidates: [
                KeywordBudgetCandidate(term: "collage", opportunity: 70, currentlyListed: false)
            ]
        )
        #expect(plan.proposed == "collage")
        #expect(plan.added == ["collage"])
        #expect(plan.dropped.isEmpty)
    }
}

struct SyncCadenceTests {
    @Test func offIsNeverDue() {
        #expect(SyncCadence.off.isDue(lastSyncedAt: nil) == false)
        #expect(SyncCadence.off.isDue(lastSyncedAt: .now) == false)
    }

    @Test func dailyIsDueWhenNeverSynced() {
        #expect(SyncCadence.daily.isDue(lastSyncedAt: nil))
    }

    @Test func dailyWaitsAboutADay() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(SyncCadence.daily.isDue(lastSyncedAt: now.addingTimeInterval(-2 * 3600), now: now) == false)
        #expect(SyncCadence.daily.isDue(lastSyncedAt: now.addingTimeInterval(-21 * 3600), now: now))
    }

    @Test func weeklyWaitsAboutAWeek() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        #expect(SyncCadence.weekly.isDue(lastSyncedAt: now.addingTimeInterval(-5 * 24 * 3600), now: now) == false)
        #expect(SyncCadence.weekly.isDue(lastSyncedAt: now.addingTimeInterval(-7 * 24 * 3600), now: now))
    }
}

struct VersionStateDisplayTests {
    @Test func knownStatesHaveReadableNames() {
        #expect(ASCAppStoreVersion.displayName(for: "PREPARE_FOR_SUBMISSION") == "Prepare for Submission")
        #expect(ASCAppStoreVersion.displayName(for: "IN_REVIEW") == "In Review")
        #expect(ASCAppStoreVersion.displayName(for: "READY_FOR_SALE") == "Ready for Sale")
    }

    @Test func snapshotWithoutStateStaysEditable() {
        #expect(MetadataSnapshot().isVersionEditable)
    }

    @Test func liveSnapshotsAreNotEditable() {
        let snapshot = MetadataSnapshot(versionState: "READY_FOR_SALE")
        #expect(snapshot.isVersionEditable == false)
    }

    @Test func prepareForSubmissionIsEditable() {
        let snapshot = MetadataSnapshot(versionState: "PREPARE_FOR_SUBMISSION")
        #expect(snapshot.isVersionEditable)
    }
}
