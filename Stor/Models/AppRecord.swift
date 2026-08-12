import SwiftData
import Foundation

@Model
final class AppRecord {
    var ascAppId: String
    var bundleId: String
    var name: String
    var primaryLocale: String
    var addedAt: Date
    var iconURL: String?
    /// App Store adamId (iTunes `trackId`), cached for Apple Ads popularity calls.
    var adamId: Int64?

    @Relationship(deleteRule: .cascade)
    var snapshots: [MetadataSnapshot] = []

    @Relationship(deleteRule: .cascade)
    var trackedKeywords: [TrackedKeyword] = []

    @Relationship(deleteRule: .cascade)
    var competitors: [CompetitorApp] = []

    @Relationship(deleteRule: .cascade)
    var screenshotTemplates: [ScreenshotTemplate] = []

    init(ascAppId: String, bundleId: String, name: String, primaryLocale: String, iconURL: String? = nil) {
        self.ascAppId = ascAppId
        self.bundleId = bundleId
        self.name = name
        self.primaryLocale = primaryLocale
        self.addedAt = Date()
        self.iconURL = iconURL
    }
}
