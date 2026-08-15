import Foundation
import Testing
@testable import AscendKit

/// The Markdown round trip is how users bulk-edit listings outside the app, so the parser
/// has to survive hand-written files: odd casing, extra blank lines, missing sections.
struct MetadataMarkdownImporterTests {
    @Test func parsesLocaleAndFields() throws {
        let markdown = """
        # Locale: en-US

        ## Name
        Photo Studio

        ## Subtitle
        Edit in seconds

        ## Keywords
        photo,editor,collage
        """

        let blocks = try MetadataMarkdownImporter.parse(markdown: markdown)
        let block = try #require(blocks.first)

        #expect(blocks.count == 1)
        #expect(block.locale == "en-US")
        #expect(block.name == "Photo Studio")
        #expect(block.subtitle == "Edit in seconds")
        #expect(block.keywords == "photo,editor,collage")
        #expect(block.description == nil)
    }

    @Test func parsesMultipleLocales() throws {
        let markdown = """
        # en-US
        ## Name
        Photo Studio

        ---

        # de-DE
        ## Name
        Fotostudio
        """

        let blocks = try MetadataMarkdownImporter.parse(markdown: markdown)

        #expect(blocks.map(\.locale) == ["en-US", "de-DE"])
        #expect(blocks.last?.name == "Fotostudio")
    }

    @Test func preservesParagraphBreaksInLongFields() throws {
        let markdown = """
        # en-US
        ## Description
        First paragraph.

        Second paragraph.
        """

        let block = try #require(try MetadataMarkdownImporter.parse(markdown: markdown).first)

        #expect(block.description == "First paragraph.\n\nSecond paragraph.")
    }

    @Test func fieldHeadersAreCaseAndSeparatorInsensitive() throws {
        let markdown = """
        # en-US
        ## PROMOTIONAL_TEXT
        Limited time offer

        ## whats new
        Bug fixes
        """

        let block = try #require(try MetadataMarkdownImporter.parse(markdown: markdown).first)

        #expect(block.promotionalText == "Limited time offer")
        #expect(block.whatsNew == "Bug fixes")
    }

    @Test func fallbackLocaleIsUsedWhenTheFileHasNoLocaleHeader() throws {
        let markdown = """
        ## Name
        Photo Studio
        """

        let blocks = try MetadataMarkdownImporter.parse(markdown: markdown, fallbackLocale: "fr-FR")

        #expect(blocks.first?.locale == "fr-FR")
        #expect(blocks.first?.name == "Photo Studio")
    }

    @Test func emptyMarkdownThrows() {
        #expect(throws: MetadataMarkdownImporter.ImportError.emptyFile) {
            try MetadataMarkdownImporter.parse(markdown: "   \n  ")
        }
    }

    @Test func markdownWithNoLocaleAndNoFallbackThrows() {
        #expect(throws: MetadataMarkdownImporter.ImportError.noLocaleBlocks) {
            try MetadataMarkdownImporter.parse(markdown: "Just some prose with no headers.")
        }
    }

    // MARK: - Apply

    @Test func applyUpdatesMatchingLocalesAndReportsUnknownOnes() throws {
        let snapshot = MetadataSnapshot()
        snapshot.localizations = [LocalizedMetadata(locale: "en-US", appName: "Old")]

        let blocks = try MetadataMarkdownImporter.parse(markdown: """
        # en-US
        ## Name
        New Name

        ---

        # ja-JP
        ## Name
        Nope
        """)

        let result = MetadataMarkdownImporter.apply(blocks: blocks, to: snapshot)

        #expect(snapshot.localizations.first?.appName == "New Name")
        #expect(result.updatedLocales == ["en-US"])
    }

    @Test func applyMatchesLocalesCaseInsensitively() throws {
        let snapshot = MetadataSnapshot()
        snapshot.localizations = [LocalizedMetadata(locale: "en-US", appName: "Old")]

        let blocks = try MetadataMarkdownImporter.parse(markdown: "# en-us\n## Name\nNew Name")
        MetadataMarkdownImporter.apply(blocks: blocks, to: snapshot)

        #expect(snapshot.localizations.first?.appName == "New Name")
    }

    @Test func applyLeavesOmittedFieldsUntouched() throws {
        let snapshot = MetadataSnapshot()
        snapshot.localizations = [LocalizedMetadata(locale: "en-US", appName: "Old", subtitle: "Keep me")]

        let blocks = try MetadataMarkdownImporter.parse(markdown: "# en-US\n## Name\nNew Name")
        MetadataMarkdownImporter.apply(blocks: blocks, to: snapshot)

        #expect(snapshot.localizations.first?.subtitle == "Keep me")
    }

    // MARK: - Export

    @Test func exportRoundTripsBackThroughTheParser() throws {
        let snapshot = MetadataSnapshot()
        snapshot.localizations = [
            LocalizedMetadata(
                locale: "en-US",
                appName: "Photo Studio",
                subtitle: "Edit in seconds",
                appDescription: "Line one.\n\nLine two.",
                keywords: "photo,editor",
                promotionalText: "Now free",
                whatsNew: "Bug fixes"
            )
        ]

        let blocks = try MetadataMarkdownImporter.parse(markdown: MetadataMarkdownImporter.exportMarkdown(from: snapshot))
        let block = try #require(blocks.first)

        #expect(block.locale == "en-US")
        #expect(block.name == "Photo Studio")
        #expect(block.subtitle == "Edit in seconds")
        #expect(block.description == "Line one.\n\nLine two.")
        #expect(block.keywords == "photo,editor")
        #expect(block.promotionalText == "Now free")
        #expect(block.whatsNew == "Bug fixes")
    }

    /// An empty snapshot exports a blank template to fill in. It has nothing to import yet,
    /// so re-parsing it as-is is expected to find no content.
    @Test func exportOfAnEmptySnapshotIsABlankTemplate() {
        let markdown = MetadataMarkdownImporter.exportMarkdown(from: MetadataSnapshot())

        for locale in ["en-US", "de-DE", "fr-FR"] {
            #expect(markdown.contains("# Locale: \(locale)"))
        }
        for field in ["## Name", "## Subtitle", "## Description", "## Keywords", "## Promotional Text", "## What's New"] {
            #expect(markdown.contains(field))
        }

        #expect(throws: MetadataMarkdownImporter.ImportError.noLocaleBlocks) {
            try MetadataMarkdownImporter.parse(markdown: markdown)
        }
    }

    @Test func aFilledInTemplateParses() throws {
        let template = MetadataMarkdownImporter.sampleTemplate(locales: ["en-US"])
        let filled = template.replacingOccurrences(of: "## Name\n", with: "## Name\nPhoto Studio\n")

        let blocks = try MetadataMarkdownImporter.parse(markdown: filled)

        #expect(blocks.map(\.locale) == ["en-US"])
        #expect(blocks.first?.name == "Photo Studio")
    }
}
