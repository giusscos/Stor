import Foundation
import Testing
@testable import Stor

/// Over-limit fields are rejected by App Store Connect with a generic 409, so the push path
/// depends on catching them locally first.
struct MetadataValidationTests {
    @Test(arguments: [
        (MetadataField.appName, 30),
        (.subtitle, 30),
        (.keywords, 100),
        (.promotionalText, 170),
        (.appDescription, 4000),
        (.whatsNew, 4000)
    ])
    func limitsMatchAppStoreConnect(field: MetadataField, limit: Int) {
        #expect(field.limit == limit)
    }

    @Test func contentAtTheLimitIsAccepted() {
        let localization = LocalizedMetadata(locale: "en-US", appName: String(repeating: "a", count: 30))
        #expect(localization.limitViolations.isEmpty)
    }

    @Test func contentOneOverTheLimitIsFlagged() {
        let localization = LocalizedMetadata(locale: "en-US", appName: String(repeating: "a", count: 31))
        let violation = localization.limitViolations.first

        #expect(localization.limitViolations.count == 1)
        #expect(violation?.field == .appName)
        #expect(violation?.count == 31)
        #expect(violation?.locale == "en-US")
    }

    @Test func everyOverLongFieldIsReported() {
        let localization = LocalizedMetadata(
            locale: "de-DE",
            appName: String(repeating: "a", count: 40),
            subtitle: String(repeating: "b", count: 40),
            keywords: String(repeating: "c", count: 101)
        )

        #expect(Set(localization.limitViolations.map(\.field)) == [.appName, .subtitle, .keywords])
    }

    @Test func emptyLocalizationHasNoViolations() {
        #expect(LocalizedMetadata(locale: "fr-FR").limitViolations.isEmpty)
    }

    @Test func violationIdsAreUniquePerLocaleAndField() {
        let en = LocalizedMetadata(locale: "en-US", appName: String(repeating: "a", count: 31))
        let de = LocalizedMetadata(locale: "de-DE", appName: String(repeating: "a", count: 31))

        #expect(en.limitViolations.first?.id != de.limitViolations.first?.id)
    }

    @Test func snapshotViolationsAreSortedByLocale() {
        let snapshot = MetadataSnapshot()
        snapshot.localizations = [
            LocalizedMetadata(locale: "fr-FR", appName: String(repeating: "a", count: 31)),
            LocalizedMetadata(locale: "de-DE", appName: String(repeating: "a", count: 31))
        ]

        #expect(snapshot.limitViolations.map(\.locale) == ["de-DE", "fr-FR"])
    }

    /// Locales added since the last sync have no App Store Connect IDs and cannot be PATCHed.
    @Test func onlyLocalesWithRemoteIdsArePushable() {
        let synced = LocalizedMetadata(locale: "en-US")
        synced.versionLocalizationId = "abc"
        let appInfoOnly = LocalizedMetadata(locale: "de-DE")
        appInfoOnly.appInfoLocalizationId = "def"
        let localOnly = LocalizedMetadata(locale: "it-IT")

        let snapshot = MetadataSnapshot()
        snapshot.localizations = [synced, appInfoOnly, localOnly]

        #expect(snapshot.pushableLocalizations.map(\.locale).sorted() == ["de-DE", "en-US"])
        #expect(snapshot.unpushableLocales == ["it-IT"])
    }
}
