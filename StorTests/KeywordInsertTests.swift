import Foundation
import SwiftData
import Testing
@testable import Stor

/// Keyword tracking is per storefront, so dedup has to be per storefront too. Getting this
/// wrong either blocks legitimate keywords or fills the table with duplicates.
@MainActor
struct KeywordInsertTests {
    private func makeContext() throws -> ModelContext {
        let container = try ModelContainer(
            for: AppRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        return ModelContext(container)
    }

    private func makeApp(in context: ModelContext) -> AppRecord {
        let app = AppRecord(
            ascAppId: "123",
            bundleId: "com.example.app",
            name: "Example",
            primaryLocale: "en-US"
        )
        context.insert(app)
        return app
    }

    @Test func insertsNewTerms() throws {
        let context = try makeContext()
        let app = makeApp(in: context)

        let result = app.insertKeywords(["photo editor", "collage"], locale: "en-US", country: "US", into: context)

        #expect(result.added == 2)
        #expect(result.skipped == 0)
        #expect(app.trackedKeywords.count == 2)
    }

    @Test func skipsTermsAlreadyTrackedInTheSameCountry() throws {
        let context = try makeContext()
        let app = makeApp(in: context)
        app.insertKeywords(["photo editor"], locale: "en-US", country: "US", into: context)

        let result = app.insertKeywords(["photo editor", "collage"], locale: "en-US", country: "US", into: context)

        #expect(result.added == 1)
        #expect(result.skipped == 1)
        #expect(app.trackedKeywords.count == 2)
    }

    @Test func dedupIgnoresCase() throws {
        let context = try makeContext()
        let app = makeApp(in: context)
        app.insertKeywords(["Photo Editor"], locale: "en-US", country: "US", into: context)

        let result = app.insertKeywords(["photo editor"], locale: "en-US", country: "US", into: context)

        #expect(result.added == 0)
        #expect(result.skipped == 1)
    }

    @Test func duplicatesWithinOneBatchAreCollapsed() throws {
        let context = try makeContext()
        let app = makeApp(in: context)

        let result = app.insertKeywords(
            ["collage", "Collage", " collage "],
            locale: "en-US",
            country: "US",
            into: context
        )

        #expect(result.added == 1)
        #expect(result.skipped == 2)
    }

    /// The same term is a distinct keyword per storefront and must not be deduped across them.
    @Test func sameTermIsAllowedInAnotherCountry() throws {
        let context = try makeContext()
        let app = makeApp(in: context)
        app.insertKeywords(["collage"], locale: "en-US", country: "US", into: context)

        let result = app.insertKeywords(["collage"], locale: "de-DE", country: "DE", into: context)

        #expect(result.added == 1)
        #expect(result.skipped == 0)
        #expect(app.trackedKeywords.count == 2)
    }

    @Test func countryMatchingIsCaseInsensitive() throws {
        let context = try makeContext()
        let app = makeApp(in: context)
        app.insertKeywords(["collage"], locale: "en-US", country: "US", into: context)

        let result = app.insertKeywords(["collage"], locale: "en-US", country: "us", into: context)

        #expect(result.added == 0)
        #expect(result.skipped == 1)
    }

    @Test func blankTermsAreIgnoredEntirely() throws {
        let context = try makeContext()
        let app = makeApp(in: context)

        let result = app.insertKeywords(["", "   ", "\n"], locale: "en-US", country: "US", into: context)

        #expect(result.isEmpty)
        #expect(app.trackedKeywords.isEmpty)
    }

    @Test func termsAreTrimmedBeforeStoring() throws {
        let context = try makeContext()
        let app = makeApp(in: context)

        app.insertKeywords(["  photo editor  "], locale: "en-US", country: "US", into: context)

        #expect(app.trackedKeywords.first?.term == "photo editor")
    }

    @Test func insertedKeywordsCarryLocaleAndBackReference() throws {
        let context = try makeContext()
        let app = makeApp(in: context)

        app.insertKeywords(["collage"], locale: "de-DE", country: "DE", into: context)
        let keyword = try #require(app.trackedKeywords.first)

        #expect(keyword.locale == "de-DE")
        #expect(keyword.country == "DE")
        #expect(keyword.app === app)
    }
}

struct KeywordInsertSummaryTests {
    @Test func summaryReportsNothingToAdd() {
        let result = AppRecord.KeywordInsertResult()
        #expect(result.summary() == "No keywords to add.")
    }

    @Test func summaryReportsAllDuplicates() {
        let result = AppRecord.KeywordInsertResult(added: 0, skipped: 3)
        #expect(result.summary() == "All 3 keywords are already tracked.")
    }

    @Test func summaryMentionsTheSourceAndDuplicateCount() {
        let result = AppRecord.KeywordInsertResult(added: 2, skipped: 1)
        #expect(result.summary(detail: "en-US") == "Added 2 keywords from en-US. Skipped 1 duplicate.")
    }

    @Test func summaryUsesSingularForms() {
        let result = AppRecord.KeywordInsertResult(added: 1, skipped: 0)
        #expect(result.summary() == "Added 1 keyword.")
    }
}

struct LocaleCountryTests {
    @Test(arguments: [
        ("en-US", "US"),
        ("de-DE", "DE"),
        ("pt_BR", "BR"),
        ("zh-Hans-CN", "CN")
    ])
    func regionIsExtractedFromLocale(locale: String, expected: String) {
        #expect(countryCode(fromLocale: locale) == expected)
    }

    @Test(arguments: ["en", "zh-Hans", "", "es-419"])
    func localesWithoutARegionReturnNil(locale: String) {
        #expect(countryCode(fromLocale: locale) == nil)
    }
}
