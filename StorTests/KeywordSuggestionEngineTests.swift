import Foundation
import Testing
@testable import Stor

struct KeywordSuggestionEngineTests {
    private func financeContext(tracked: [KeywordSuggestionEngine.TrackedSeed]? = nil) -> KeywordSuggestionEngine.ListingContext {
        KeywordSuggestionEngine.ListingContext(
            appName: "Your Personal Finance - ByJo",
            subtitle: "Budget & cashflow tracker",
            keywords: ["budget", "expense", "savings", "investing"],
            description: "Track spending, bills, and net worth. Plan a budget and watch your cashflow.",
            tracked: tracked ?? [
                .init(term: "offline", popularity: 40, rank: nil),
                .init(term: "investing", popularity: 55, rank: 12),
                .init(term: "cashflow", popularity: 48, rank: nil),
                .init(term: "debt", popularity: 50, rank: nil)
            ]
        )
    }

    @Test func offlineIsAWeakExpansionSeed() {
        #expect(KeywordSuggestionEngine.isWeakExpansionSeed("offline"))
        #expect(KeywordSuggestionEngine.isWeakExpansionSeed("FREE"))
        #expect(KeywordSuggestionEngine.isWeakExpansionSeed("iphone"))
        #expect(!KeywordSuggestionEngine.isWeakExpansionSeed("budget"))
        #expect(!KeywordSuggestionEngine.isWeakExpansionSeed("cashflow"))
    }

    @Test func expansionSeedsPreferListingTermsOverGenericTrackedOnes() {
        let seeds = KeywordSuggestionEngine.expansionSeeds(from: financeContext())
        let keys = seeds.map { $0.lowercased() }

        #expect(keys.contains("budget") || keys.contains("personal finance") || keys.contains("investing"))
        #expect(!keys.contains("offline"))
        #expect(!keys.contains("byjo"))
        #expect(seeds.count <= KeywordSuggestionEngine.maxExpansionSeeds)
    }

    @Test func appNameYieldsPersonalFinancePhrase() {
        let terms = KeywordSuggestionEngine.terms(
            fromAppName: "Your Personal Finance - ByJo",
            subtitle: "Budget & cashflow tracker"
        )
        let keys = Set(terms.map { $0.lowercased() })
        #expect(keys.contains("personal finance"))
        #expect(keys.contains("budget"))
        #expect(keys.contains("cashflow"))
        #expect(!keys.contains("your"))
    }

    @Test func socialBrandsRankBelowFinanceTerms() {
        let ranked = KeywordSuggestionEngine.rank(
            [
                .init(term: "instagram", source: "Apple Ads · from “offline”", popularity: 100),
                .init(term: "tik tok", source: "Apple Ads · from “offline”", popularity: 98),
                .init(term: "expense tracker", source: "Apple Ads · from “budget”", popularity: 55),
                .init(term: "budget planner", source: "Your listing", popularity: 62)
            ],
            context: financeContext()
        )
        let keys = ranked.map { $0.term.lowercased() }

        #expect(keys.contains("expense tracker"))
        #expect(keys.contains("budget planner"))
        #expect(!keys.contains("instagram"))
        #expect(!keys.contains("tik tok"))
        #expect(keys.first == "budget planner" || keys.first == "expense tracker")
    }

    @Test func competitorTermsSurviveEvenWithoutTokenOverlap() {
        let ranked = KeywordSuggestionEngine.rank(
            [
                .init(term: "net worth", source: "Competitor · Mint", popularity: nil),
                .init(term: "instagram", source: "Apple Ads · from “offline”", popularity: 100)
            ],
            context: financeContext()
        )
        let keys = Set(ranked.map { $0.term.lowercased() })
        #expect(keys.contains("net worth"))
        #expect(!keys.contains("instagram"))
    }

    @Test func relevanceIsHighWhenTokensMatchTheListing() {
        let vocab = KeywordSuggestionEngine.vocabulary(from: financeContext())
        #expect(KeywordSuggestionEngine.relevance(of: "budget planner", vocabulary: vocab) > 0.4)
        #expect(KeywordSuggestionEngine.relevance(of: "instagram", vocabulary: vocab) == 0)
        #expect(KeywordSuggestionEngine.relevance(of: "investing", vocabulary: vocab) == 1)
    }

    @Test func byjoIsTreatedAsANameOnlyBrand() {
        let context = financeContext()
        #expect(KeywordSuggestionEngine.isLikelyBrandToken("ByJo", context: context))
        #expect(!KeywordSuggestionEngine.isLikelyBrandToken("finance", context: context))
        #expect(!KeywordSuggestionEngine.isLikelyBrandToken("budget", context: context))
    }

    @Test func stopwordsAreStrippedFromTokens() {
        let tokens = KeywordSuggestionEngine.tokens(in: "Track your budget and cashflow for the month")
        #expect(tokens.contains("budget"))
        #expect(tokens.contains("cashflow"))
        #expect(!tokens.contains("your"))
        #expect(!tokens.contains("and"))
        #expect(!tokens.contains("the"))
    }
}
