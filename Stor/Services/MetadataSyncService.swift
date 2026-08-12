import Foundation
import SwiftData

/// Shared listing pull used by the Listing tab and the background scheduler.
enum MetadataSyncService {
    @discardableResult
    @MainActor
    static func sync(
        app: AppRecord,
        versionId: String?,
        credentials: ASCCredentials,
        context: ModelContext
    ) async throws -> MetadataSnapshot {
        let client = ASCAPIClient(credentials: credentials)
        let result = try await client.syncMetadata(appId: app.ascAppId, versionId: versionId)

        let snapshot = MetadataSnapshot(
            capturedAt: .now,
            versionString: result.version?.attributes.versionString,
            versionId: result.version?.id,
            versionState: result.version?.attributes.appStoreState
        )
        snapshot.app = app
        context.insert(snapshot)

        var localeMap: [String: LocalizedMetadata] = [:]

        for vLoc in result.versionLocalizations {
            let meta = LocalizedMetadata(
                locale: vLoc.attributes.locale,
                appDescription: vLoc.attributes.description,
                keywords: vLoc.attributes.keywords,
                promotionalText: vLoc.attributes.promotionalText,
                whatsNew: vLoc.attributes.whatsNew
            )
            meta.versionLocalizationId = vLoc.id
            localeMap[vLoc.attributes.locale] = meta
        }

        for infoLoc in result.appInfoLocalizations {
            if let existing = localeMap[infoLoc.attributes.locale] {
                existing.appName = infoLoc.attributes.name
                existing.subtitle = infoLoc.attributes.subtitle
                existing.appInfoLocalizationId = infoLoc.id
            } else {
                let meta = LocalizedMetadata(
                    locale: infoLoc.attributes.locale,
                    appName: infoLoc.attributes.name,
                    subtitle: infoLoc.attributes.subtitle
                )
                meta.appInfoLocalizationId = infoLoc.id
                localeMap[infoLoc.attributes.locale] = meta
            }
        }

        for meta in localeMap.values {
            meta.snapshot = snapshot
            snapshot.localizations.append(meta)
            context.insert(meta)
        }

        app.snapshots.append(snapshot)
        app.lastSyncedAt = snapshot.capturedAt
        app.lastSyncError = nil
        if let versionId = result.version?.id {
            app.preferredVersionId = versionId
        }
        return snapshot
    }
}
