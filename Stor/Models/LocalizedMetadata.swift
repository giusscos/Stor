import SwiftData
import Foundation

@Model
final class LocalizedMetadata {
    var locale: String
    var appName: String?
    var subtitle: String?
    var appDescription: String?
    var keywords: String?
    var promotionalText: String?
    var whatsNew: String?
    var versionLocalizationId: String?
    var appInfoLocalizationId: String?
    var snapshot: MetadataSnapshot?

    init(
        locale: String,
        appName: String? = nil,
        subtitle: String? = nil,
        appDescription: String? = nil,
        keywords: String? = nil,
        promotionalText: String? = nil,
        whatsNew: String? = nil
    ) {
        self.locale = locale
        self.appName = appName
        self.subtitle = subtitle
        self.appDescription = appDescription
        self.keywords = keywords
        self.promotionalText = promotionalText
        self.whatsNew = whatsNew
    }
}
