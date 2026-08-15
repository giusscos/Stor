import Foundation
import AppKit
import UniformTypeIdentifiers

/// Parses and applies screenshot text translations from Markdown files.
///
/// Expected format (one file, all locales):
///
///     # Locale: en-US
///
///     ## Onboarding
///
///     ### 550e8400-e29b-41d4-a716-446655440000
///     Welcome to the app
///
///     ### 550e8400-e29b-41d4-a716-446655440001
///     Track your progress
///
///     ---
///
///     # Locale: de-DE
///     …
///
/// `##` headings are template names (for readability). `###` headings are layer UUIDs
/// used for round-trip matching. Leave a layer blank to skip it on import.
enum ScreenshotMarkdownImporter {

    struct LayerText: Equatable {
        var layerId: UUID
        var text: String
    }

    struct TemplateSection: Equatable {
        var name: String
        var layers: [LayerText]
    }

    struct LocaleBlock: Equatable {
        var locale: String
        var templates: [TemplateSection]
    }

    struct ImportResult: Equatable {
        var updatedLocales: [String]
        var updatedLayerCount: Int
        var unknownLocales: [String]
        var unknownLayerIds: [String]
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
        var currentLocale: String?
        var currentTemplateName: String?
        var currentLayerId: UUID?
        var buffer: [String] = []
        var templates: [TemplateSection] = []
        var layers: [LayerText] = []

        func flushLayer() {
            guard let id = currentLayerId else {
                buffer = []
                return
            }
            let value = normalizeFieldValue(buffer.joined(separator: "\n"))
            buffer = []
            currentLayerId = nil
            guard !value.isEmpty else { return }
            layers.append(LayerText(layerId: id, text: value))
        }

        func flushTemplate() {
            flushLayer()
            if let name = currentTemplateName {
                templates.append(TemplateSection(name: name, layers: layers))
            } else if !layers.isEmpty {
                templates.append(TemplateSection(name: "Untitled", layers: layers))
            }
            currentTemplateName = nil
            layers = []
        }

        func flushBlock() {
            flushTemplate()
            if let locale = currentLocale, !templates.isEmpty {
                blocks.append(LocaleBlock(locale: locale, templates: templates))
            }
            currentLocale = nil
            templates = []
        }

        for line in lines {
            if isHorizontalRule(line) {
                flushBlock()
                continue
            }

            if let locale = parseLocaleHeader(line) {
                flushBlock()
                currentLocale = locale
                continue
            }

            if let templateName = parseTemplateHeader(line) {
                if currentLocale == nil, let fallback = fallbackLocale {
                    currentLocale = fallback
                }
                flushTemplate()
                currentTemplateName = templateName
                continue
            }

            if let layerId = parseLayerHeader(line) {
                if currentLocale == nil, let fallback = fallbackLocale {
                    currentLocale = fallback
                }
                flushLayer()
                currentLayerId = layerId
                continue
            }

            if currentLayerId != nil {
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
    static func apply(blocks: [LocaleBlock], to templates: [ScreenshotTemplate], primaryLocale: String) -> ImportResult {
        var updatedLocales = Set<String>()
        var updatedLayerCount = 0
        var unknownLayerIds = Set<String>()

        var layerIndex: [UUID: (templateIndex: Int, layerIndex: Int)] = [:]
        for (ti, template) in templates.enumerated() {
            for (li, layer) in template.layers.enumerated() where layer.type == .text {
                layerIndex[layer.id] = (ti, li)
            }
        }

        for block in blocks {
            var localeTouched = false
            for section in block.templates {
                for item in section.layers {
                    guard let indices = layerIndex[item.layerId] else {
                        unknownLayerIds.insert(item.layerId.uuidString)
                        continue
                    }
                    var layers = templates[indices.templateIndex].layers
                    layers[indices.layerIndex].setResolvedText(
                        item.text,
                        for: block.locale,
                        primaryLocale: primaryLocale
                    )
                    templates[indices.templateIndex].layers = layers
                    updatedLayerCount += 1
                    localeTouched = true
                }
            }
            if localeTouched {
                updatedLocales.insert(block.locale)
            }
        }

        let unknownLocaleCodes = Set(blocks.map(\.locale))
            .subtracting(updatedLocales)
            .filter { locale in
                guard let block = blocks.first(where: {
                    $0.locale.caseInsensitiveCompare(locale) == .orderedSame
                }) else { return false }
                let ids = block.templates.flatMap(\.layers).map(\.layerId)
                return !ids.isEmpty && ids.allSatisfy { layerIndex[$0] == nil }
            }

        return ImportResult(
            updatedLocales: updatedLocales.sorted(),
            updatedLayerCount: updatedLayerCount,
            unknownLocales: unknownLocaleCodes.sorted(),
            unknownLayerIds: unknownLayerIds.sorted()
        )
    }

    // MARK: - Export

    /// Builds a Markdown document from current templates for the given locales.
    /// Missing translations fall back to the primary `text` so translators can replace in place.
    static func exportMarkdown(
        templates: [ScreenshotTemplate],
        locales: [String],
        primaryLocale: String
    ) -> String {
        let sortedTemplates = templates.sorted { $0.createdAt < $1.createdAt }
        let textTemplates = sortedTemplates.filter { $0.layers.contains { $0.type == .text } }

        if textTemplates.isEmpty {
            return sampleTemplate(locales: locales.isEmpty ? [primaryLocale] : locales)
        }

        let resolvedLocales = locales.isEmpty ? [primaryLocale] : locales.sorted()
        let header = """
        <!--
        AscendKit screenshot text import template
        1. Keep `# Locale: xx-XX` headers (App Store Connect locale codes).
        2. Keep `### <layer-uuid>` headings — they match text layers on import.
        3. Translate the text under each layer. Leave blank to skip that layer.
        4. Import from the Screenshots tab → Import Texts.
        -->

        """

        let body = resolvedLocales.map { locale in
            exportBlock(templates: textTemplates, locale: locale, primaryLocale: primaryLocale)
        }.joined(separator: "\n---\n\n")

        return header + body
    }

    static func sampleTemplate(locales: [String] = ["en-US", "de-DE", "fr-FR"]) -> String {
        let header = """
        <!--
        AscendKit screenshot text import template
        Create screenshot templates with text layers first, then Export Texts to get a filled file.
        -->

        """
        let body = locales.map { locale in
            """
            # Locale: \(locale)

            ## Example Template

            ### 00000000-0000-0000-0000-000000000001
            Your screenshot headline

            ### 00000000-0000-0000-0000-000000000002
            Supporting line of text
            """
        }.joined(separator: "\n---\n\n")
        return header + body
    }

    static func exportBlock(
        templates: [ScreenshotTemplate],
        locale: String,
        primaryLocale: String
    ) -> String {
        var parts: [String] = ["# Locale: \(locale)\n"]
        for template in templates {
            let textLayers = template.layers.filter { $0.type == .text }
            guard !textLayers.isEmpty else { continue }
            parts.append("## \(template.name)\n")
            for layer in textLayers {
                let value = layer.resolvedText(for: locale)
                    ?? layer.resolvedText(for: primaryLocale)
                    ?? layer.text
                    ?? ""
                parts.append("### \(layer.id.uuidString)\n\(value)\n")
            }
        }
        return parts.joined(separator: "\n")
    }

    // MARK: - File panels

    static func presentOpenPanel() -> [URL]? {
        let panel = NSOpenPanel()
        var types: [UTType] = [.plainText, .text]
        if let md = UTType(filenameExtension: "md") { types.insert(md, at: 0) }
        panel.allowedContentTypes = types
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Select a Markdown file with screenshot texts for all locales, or multiple per-locale files."
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
        panel.message = "Save a Markdown file you can translate and re-import."
        panel.prompt = "Save"
        guard panel.runModal() == .OK, let url = panel.url else { return false }
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Internals

    private static func parseLocaleHeader(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("#") else { return nil }
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

    private static func parseTemplateHeader(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("##") else { return nil }
        guard !trimmed.hasPrefix("###") else { return nil }
        let name = trimmed
            .drop(while: { $0 == "#" })
            .trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? nil : name
    }

    private static func parseLayerHeader(_ line: String) -> UUID? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("###") else { return nil }
        guard !trimmed.hasPrefix("####") else { return nil }

        let rest = trimmed
            .drop(while: { $0 == "#" })
            .trimmingCharacters(in: .whitespaces)

        // Accept bare UUID, or "Layer <uuid>", or "id: <uuid>"
        let patterns = [
            #"(?i)^(?:layer|id)\s*:?\s*([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\s*$"#,
            #"^([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\s*$"#,
        ]

        for pattern in patterns {
            if let match = firstCapture(in: rest, pattern: pattern) {
                return UUID(uuidString: match)
            }
        }
        return nil
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
        // Strip HTML comments used as translator hints
        let joined = lines.joined(separator: "\n")
        return joined.replacingOccurrences(
            of: #"<!--[\s\S]*?-->"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespacesAndNewlines)
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
