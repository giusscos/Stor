import Foundation
import AppKit
import UniformTypeIdentifiers

/// Parses and applies App Store metadata from Markdown files.
///
/// Expected format (one file, all locales):
///
///     # Locale: en-US
///
///     ## Name
///     My App
///
///     ## Subtitle
///     Short tagline
///
///     ## Description
///     Full App Store description…
///
///     ## Keywords
///     finance,budget,money
///
///     ## Promotional Text
///     Optional promo line
///
///     ## What's New
///     Optional release notes
///
///     ---
///
///     # Locale: de-DE
///     …
///
/// Single-locale files are also supported: if no `# Locale:` header is present,
/// the locale is taken from the filename (e.g. `de-DE.md`).
enum MetadataMarkdownImporter {

    struct LocaleBlock: Equatable {
        var locale: String
        var name: String?
        var subtitle: String?
        var description: String?
        var keywords: String?
        var promotionalText: String?
        var whatsNew: String?
    }

    struct ImportResult: Equatable {
        var updatedLocales: [String]
        var skippedLocales: [String]
        var unknownLocales: [String]
    }

    enum ImportError: LocalizedError {
        case emptyFile
        case noLocaleBlocks
        case unreadableFile

        var errorDescription: String? {
            switch self {
            case .emptyFile: return "The Markdown file is empty."
            case .noLocaleBlocks: return "No locale sections found. Add a `# Locale: en-US` header (or name the file `en-US.md`)."
            case .unreadableFile: return "Could not read the selected file."
            }
        }
    }

    // MARK: - Parse

    static func parse(markdown: String, fallbackLocale: String? = nil) throws -> [LocaleBlock] {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.emptyFile }

        let lines = markdown.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [LocaleBlock] = []
        var current: LocaleBlock?
        var currentField: Field?
        var buffer: [String] = []

        func flushField() {
            guard var block = current, let field = currentField else {
                buffer = []
                return
            }
            let value = normalizeFieldValue(buffer.joined(separator: "\n"))
            buffer = []
            guard !value.isEmpty else {
                current = block
                return
            }
            switch field {
            case .name: block.name = value
            case .subtitle: block.subtitle = value
            case .description: block.description = value
            case .keywords: block.keywords = value
            case .promotionalText: block.promotionalText = value
            case .whatsNew: block.whatsNew = value
            }
            current = block
        }

        func flushBlock() {
            flushField()
            currentField = nil
            if let block = current, !block.isEmpty {
                blocks.append(block)
            }
            current = nil
        }

        for line in lines {
            if isHorizontalRule(line) {
                flushBlock()
                continue
            }

            if let locale = parseLocaleHeader(line) {
                flushBlock()
                current = LocaleBlock(locale: locale)
                continue
            }

            if let field = parseFieldHeader(line) {
                if current == nil, let fallback = fallbackLocale {
                    current = LocaleBlock(locale: fallback)
                }
                flushField()
                currentField = field
                continue
            }

            if currentField != nil {
                buffer.append(line)
            }
        }

        flushBlock()

        if blocks.isEmpty {
            throw ImportError.noLocaleBlocks
        }

        return blocks
    }

    static func parse(fileURL: URL) throws -> [LocaleBlock] {
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8) else {
            throw ImportError.unreadableFile
        }
        let fallback = localeFromFilename(fileURL.deletingPathExtension().lastPathComponent)
        return try parse(markdown: text, fallbackLocale: fallback)
    }

    // MARK: - Apply

    @discardableResult
    static func apply(blocks: [LocaleBlock], to snapshot: MetadataSnapshot) -> ImportResult {
        var updated: [String] = []
        var skipped: [String] = []
        var unknown: [String] = []

        let byLocale = Dictionary(uniqueKeysWithValues: snapshot.localizations.map { ($0.locale, $0) })

        for block in blocks {
            guard let localization = byLocale[block.locale]
                    ?? byLocale.first(where: { $0.key.caseInsensitiveCompare(block.locale) == .orderedSame })?.value else {
                unknown.append(block.locale)
                continue
            }

            var changed = false
            if let name = block.name {
                localization.appName = name
                changed = true
            }
            if let subtitle = block.subtitle {
                localization.subtitle = subtitle
                changed = true
            }
            if let description = block.description {
                localization.appDescription = description
                changed = true
            }
            if let keywords = block.keywords {
                localization.keywords = keywords
                changed = true
            }
            if let promo = block.promotionalText {
                localization.promotionalText = promo
                changed = true
            }
            if let whatsNew = block.whatsNew {
                localization.whatsNew = whatsNew
                changed = true
            }

            if changed {
                updated.append(localization.locale)
            } else {
                skipped.append(localization.locale)
            }
        }

        return ImportResult(
            updatedLocales: updated.sorted(),
            skippedLocales: skipped.sorted(),
            unknownLocales: unknown.sorted()
        )
    }

    // MARK: - Export / sample

    /// Builds a Markdown document from an existing snapshot (filled with current values).
    static func exportMarkdown(from snapshot: MetadataSnapshot) -> String {
        let locales = snapshot.localizations.sorted { $0.locale < $1.locale }
        if locales.isEmpty {
            return sampleTemplate(locales: ["en-US", "de-DE", "fr-FR"])
        }
        return locales.map { exportBlock(for: $0) }.joined(separator: "\n---\n\n")
    }

    /// Empty template users can fill in.
    static func sampleTemplate(locales: [String] = ["en-US", "de-DE", "fr-FR"]) -> String {
        let header = """
        <!--
        Stor metadata import template
        1. Keep the `# Locale: xx-XX` headers (App Store Connect locale codes).
        2. Fill in each ## field. Leave a field blank to skip it on import.
        3. Import this file from the Listing tab → Import Markdown.
        Character limits: Name 30 · Subtitle 30 · Description 4000 · Keywords 100 · Promotional Text 170 · What's New 4000
        -->

        """
        let body = locales.map { locale in
            """
            # Locale: \(locale)

            ## Name


            ## Subtitle


            ## Description


            ## Keywords


            ## Promotional Text


            ## What's New

            """
        }.joined(separator: "\n---\n\n")
        return header + body
    }

    static func exportBlock(for localization: LocalizedMetadata) -> String {
        func section(_ title: String, _ value: String?) -> String {
            "## \(title)\n\(value ?? "")\n"
        }
        return """
        # Locale: \(localization.locale)

        \(section("Name", localization.appName))\
        \(section("Subtitle", localization.subtitle))\
        \(section("Description", localization.appDescription))\
        \(section("Keywords", localization.keywords))\
        \(section("Promotional Text", localization.promotionalText))\
        \(section("What's New", localization.whatsNew))
        """
    }

    // MARK: - File panels

    static func presentOpenPanel() -> [URL]? {
        let panel = NSOpenPanel()
        var types: [UTType] = [.plainText, .text]
        if let md = UTType(filenameExtension: "md") { types.insert(md, at: 0) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Select one Markdown file with all locales, or multiple per-locale files (e.g. en-US.md)."
        panel.prompt = "Import"
        guard panel.runModal() == .OK else { return nil }
        return panel.urls
    }

    static func presentSavePanel(defaultName: String, contents: String) -> Bool {
        let panel = NSSavePanel()
        if let md = UTType(filenameExtension: "md") {
            panel.allowedContentTypes = [md]
        } else {
            panel.allowedContentTypes = [.plainText]
        }
        panel.nameFieldStringValue = defaultName
        panel.message = "Save a Markdown file you can edit and re-import."
        panel.prompt = "Save"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    static func bundledSampleMarkdown() -> String {
        if let url = Bundle.main.url(forResource: "metadata-sample", withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        return sampleTemplate()
    }

    // MARK: - Internals

    private enum Field {
        case name, subtitle, description, keywords, promotionalText, whatsNew
    }

    private static func parseLocaleHeader(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
        // Only H1
        guard !trimmed.hasPrefix("##") else { return nil }

        let rest = trimmed
            .drop(while: { $0 == "#" })
            .trimmingCharacters(in: .whitespaces)

        let patterns = [
            #"^(?i)locale\s*:\s*([A-Za-z]{2}(?:[-_][A-Za-z]{2,4})?)\s*$"#,
            #"^([A-Za-z]{2}(?:[-_][A-Za-z]{2,4})?)\s*$"#,
        ]

        for pattern in patterns {
            if let match = firstCapture(in: rest, pattern: pattern) {
                return normalizeLocale(match)
            }
        }
        return nil
    }

    private static func parseFieldHeader(_ line: String) -> Field? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("##") else { return nil }
        guard !trimmed.hasPrefix("###") else { return nil }

        let name = trimmed
            .drop(while: { $0 == "#" })
            .trimmingCharacters(in: .whitespaces)
            .lowercased()
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        switch name {
        case "name", "app name", "title":
            return .name
        case "subtitle", "sub title":
            return .subtitle
        case "description", "app description", "desc":
            return .description
        case "keywords", "keyword":
            return .keywords
        case "promotional text", "promotionaltext", "promo", "promo text":
            return .promotionalText
        case "what's new", "whats new", "whatsnew", "release notes", "release note":
            return .whatsNew
        default:
            return nil
        }
    }

    private static func isHorizontalRule(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.count >= 3 else { return false }
        return t.allSatisfy { $0 == "-" } || t.allSatisfy { $0 == "*" }
    }

    private static func normalizeFieldValue(_ raw: String) -> String {
        var lines = raw.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        while lines.first?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeFirst()
        }
        while lines.last?.trimmingCharacters(in: .whitespaces).isEmpty == true {
            lines.removeLast()
        }
        return lines.joined(separator: "\n")
    }

    private static func normalizeLocale(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: "-")
    }

    private static func localeFromFilename(_ name: String) -> String? {
        let pattern = #"^[A-Za-z]{2}(?:[-_][A-Za-z]{2,4})?$"#
        guard name.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return normalizeLocale(name)
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[captureRange])
    }
}

private extension MetadataMarkdownImporter.LocaleBlock {
    var isEmpty: Bool {
        name == nil && subtitle == nil && description == nil
            && keywords == nil && promotionalText == nil && whatsNew == nil
    }
}
