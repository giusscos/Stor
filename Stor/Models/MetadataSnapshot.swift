import SwiftData
import Foundation

@Model
final class MetadataSnapshot {
    var capturedAt: Date
    var versionString: String?
    var versionId: String?
    var app: AppRecord?

    @Relationship(deleteRule: .cascade)
    var localizations: [LocalizedMetadata] = []

    init(capturedAt: Date = .now, versionString: String? = nil, versionId: String? = nil) {
        self.capturedAt = capturedAt
        self.versionString = versionString
        self.versionId = versionId
    }
}
