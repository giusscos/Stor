import Foundation

enum LocaleDisplayName {
    /// Human-readable label for App Store Connect locale codes like `en-US`, `pt-BR`, `zh-Hans`.
    /// Prefers "English (United States)" over bare "English" so regional variants stay distinct.
    static func name(for code: String) -> String {
        let identifier = code.replacingOccurrences(of: "_", with: "-")

        if let full = Locale.current.localizedString(forIdentifier: identifier), !full.isEmpty {
            return full
        }

        let parts = identifier.split(separator: "-").map(String.init)
        guard let language = parts.first else { return code }

        let languageName = Locale.current.localizedString(forLanguageCode: language) ?? language
        guard parts.count > 1 else { return languageName }

        let suffix = parts[1]
        if let region = Locale.current.localizedString(forRegionCode: suffix) {
            return "\(languageName) (\(region))"
        }
        if let script = Locale.current.localizedString(forScriptCode: suffix) {
            return "\(languageName) (\(script))"
        }
        return "\(languageName) (\(suffix))"
    }
}
