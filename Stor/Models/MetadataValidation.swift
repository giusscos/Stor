import Foundation

/// Character limits App Store Connect enforces on listing fields. Exceeding one causes the
/// PATCH to be rejected, so we check locally before pushing rather than after.
enum MetadataField: String, CaseIterable {
    case appName = "App Name"
    case subtitle = "Subtitle"
    case appDescription = "Description"
    case keywords = "Keywords"
    case promotionalText = "Promotional Text"
    case whatsNew = "What's New"

    var limit: Int {
        switch self {
        case .appName, .subtitle: return 30
        case .keywords: return 100
        case .promotionalText: return 170
        case .appDescription, .whatsNew: return 4000
        }
    }

    /// Ratio at which the counter should warn before it actually breaks the push.
    static let warningThreshold = 0.9
}

extension LocalizedMetadata {
    func value(for field: MetadataField) -> String? {
        switch field {
        case .appName: return appName
        case .subtitle: return subtitle
        case .appDescription: return appDescription
        case .keywords: return keywords
        case .promotionalText: return promotionalText
        case .whatsNew: return whatsNew
        }
    }

    /// Fields whose current content is too long for App Store Connect to accept.
    var limitViolations: [MetadataValidationIssue] {
        MetadataField.allCases.compactMap { field in
            guard let value = value(for: field), value.count > field.limit else { return nil }
            return MetadataValidationIssue(
                locale: locale,
                field: field,
                count: value.count
            )
        }
    }
}

struct MetadataValidationIssue: Identifiable {
    let locale: String
    let field: MetadataField
    let count: Int

    var id: String { "\(locale).\(field.rawValue)" }

    var description: String {
        "\(LocaleDisplayName.name(for: locale)) · \(field.rawValue): \(count)/\(field.limit)"
    }
}

extension MetadataSnapshot {
    var limitViolations: [MetadataValidationIssue] {
        localizations
            .sorted { $0.locale < $1.locale }
            .flatMap(\.limitViolations)
    }

    /// Locales that carry the App Store Connect IDs needed for a PATCH. Locales added
    /// locally since the last sync have no IDs and cannot be pushed.
    var pushableLocalizations: [LocalizedMetadata] {
        localizations.filter { $0.versionLocalizationId != nil || $0.appInfoLocalizationId != nil }
    }

    var unpushableLocales: [String] {
        localizations
            .filter { $0.versionLocalizationId == nil && $0.appInfoLocalizationId == nil }
            .map(\.locale)
            .sorted()
    }
}
