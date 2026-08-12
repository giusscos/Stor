import SwiftData
import Foundation

@Model
final class MetadataSnapshot {
    var capturedAt: Date
    var versionString: String?
    var versionId: String?
    /// App Store Connect `appStoreState` at capture time (e.g. PREPARE_FOR_SUBMISSION).
    var versionState: String?
    var app: AppRecord?

    @Relationship(deleteRule: .cascade)
    var localizations: [LocalizedMetadata] = []

    init(
        capturedAt: Date = .now,
        versionString: String? = nil,
        versionId: String? = nil,
        versionState: String? = nil
    ) {
        self.capturedAt = capturedAt
        self.versionString = versionString
        self.versionId = versionId
        self.versionState = versionState
    }
}
