import Foundation
import SwiftData

extension AppRecord {
    struct KeywordInsertResult {
        var added: Int = 0
        var skipped: Int = 0

        var isEmpty: Bool { added == 0 && skipped == 0 }
    }

    /// Adds `terms` for one country, skipping terms already tracked there and duplicates
    /// within `terms` itself. Tracking is per country, so the same term can exist for US
    /// and DE independently.
    @discardableResult
    func insertKeywords(
        _ terms: [String],
        locale: String,
        country: String,
        into context: ModelContext
    ) -> KeywordInsertResult {
        var seen = Set(
            trackedKeywords
                .filter { $0.country.caseInsensitiveCompare(country) == .orderedSame }
                .map { $0.term.lowercased() }
        )

        var result = KeywordInsertResult()
        for term in terms {
            let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            guard seen.insert(trimmed.lowercased()).inserted else {
                result.skipped += 1
                continue
            }

            let keyword = TrackedKeyword(term: trimmed, locale: locale, country: country)
            keyword.app = self
            trackedKeywords.append(keyword)
            context.insert(keyword)
            result.added += 1
        }
        return result
    }
}

extension AppRecord.KeywordInsertResult {
    /// User-facing summary of an insert, so callers don't each invent their own wording.
    func summary(detail: String? = nil) -> String {
        let source = detail.map { " from \($0)" } ?? ""
        if added == 0 {
            return skipped == 0
                ? "No keywords to add."
                : "All \(skipped) keyword\(skipped == 1 ? " is" : "s are") already tracked."
        }
        let addedText = "Added \(added) keyword\(added == 1 ? "" : "s")\(source)."
        guard skipped > 0 else { return addedText }
        return addedText + " Skipped \(skipped) duplicate\(skipped == 1 ? "" : "s")."
    }
}

enum KeywordCountries {
    /// Storefronts offered by default in the country pickers. Tracked keywords can use
    /// any storefront; these are just the ones we surface without prior data.
    static let all = ["US", "GB", "DE", "FR", "IT", "ES", "JP", "CA", "AU", "BR"]

    static func displayName(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}

/// Maps an App Store locale such as `de-DE` or `zh-Hans-CN` to its two-letter region.
func countryCode(fromLocale locale: String) -> String? {
    let parts = locale.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
    // A bare language tag such as `en` has no storefront; only trailing subtags qualify.
    guard parts.count > 1, let region = parts.last, region.count == 2, region.allSatisfy(\.isLetter) else {
        return nil
    }
    return region.uppercased()
}
