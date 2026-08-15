import Foundation
import Testing
@testable import AscendKit

/// Screenshot translations are matched to layers by UUID, so a parser that loses or
/// mis-associates an id silently drops a translator's work.
@MainActor
struct ScreenshotMarkdownImporterTests {
    private let layerA = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440000")!
    private let layerB = UUID(uuidString: "550e8400-e29b-41d4-a716-446655440001")!

    @Test func parsesLocalesTemplatesAndLayers() throws {
        let markdown = """
        # Locale: en-US

        ## Onboarding

        ### \(layerA.uuidString)
        Welcome to the app

        ### \(layerB.uuidString)
        Track your progress
        """

        let block = try #require(try ScreenshotMarkdownImporter.parse(markdown: markdown).first)

        #expect(block.locale == "en-US")
        #expect(block.templates.map(\.name) == ["Onboarding"])
        #expect(block.templates.first?.layers == [
            .init(layerId: layerA, text: "Welcome to the app"),
            .init(layerId: layerB, text: "Track your progress")
        ])
    }

    @Test func layerHeadersAcceptBareAndLabelledUUIDs() throws {
        let markdown = """
        # en-US
        ## Onboarding
        ### Layer \(layerA.uuidString)
        One
        ### id: \(layerB.uuidString)
        Two
        """

        let layers = try #require(try ScreenshotMarkdownImporter.parse(markdown: markdown).first?.templates.first?.layers)

        #expect(layers.map(\.layerId) == [layerA, layerB])
    }

    /// Blank text is how a translator says "skip this one"; importing it would wipe the
    /// existing string.
    @Test func blankLayerBodiesAreDropped() throws {
        let markdown = """
        # en-US
        ## Onboarding
        ### \(layerA.uuidString)

        ### \(layerB.uuidString)
        Two
        """

        let layers = try #require(try ScreenshotMarkdownImporter.parse(markdown: markdown).first?.templates.first?.layers)

        #expect(layers.map(\.layerId) == [layerB])
    }

    @Test func emptyMarkdownThrows() {
        #expect(throws: ScreenshotMarkdownImporter.ImportError.emptyFile) {
            try ScreenshotMarkdownImporter.parse(markdown: "\n\n  ")
        }
    }

    // MARK: - Apply

    @Test func applyWritesTranslationsOntoMatchingLayers() throws {
        let template = ScreenshotTemplate(name: "Onboarding")
        var layer = ScreenshotLayer(type: .text)
        layer.text = "Welcome"
        template.layers = [layer]

        let markdown = """
        # de-DE
        ## Onboarding
        ### \(layer.id.uuidString)
        Willkommen
        """
        let blocks = try ScreenshotMarkdownImporter.parse(markdown: markdown)

        let result = ScreenshotMarkdownImporter.apply(blocks: blocks, to: [template], primaryLocale: "en-US")

        #expect(result.updatedLocales == ["de-DE"])
        #expect(result.updatedLayerCount == 1)
        #expect(template.layers.first?.resolvedText(for: "de-DE") == "Willkommen")
        #expect(template.layers.first?.text == "Welcome")
    }

    @Test func applyToThePrimaryLocaleAlsoUpdatesTheDefaultText() throws {
        let template = ScreenshotTemplate(name: "Onboarding")
        var layer = ScreenshotLayer(type: .text)
        layer.text = "Welcome"
        template.layers = [layer]

        let blocks = try ScreenshotMarkdownImporter.parse(
            markdown: "# en-US\n## Onboarding\n### \(layer.id.uuidString)\nHello there"
        )
        ScreenshotMarkdownImporter.apply(blocks: blocks, to: [template], primaryLocale: "en-US")

        #expect(template.layers.first?.text == "Hello there")
    }

    @Test func unknownLayerIdsAreReportedRatherThanIgnored() throws {
        let template = ScreenshotTemplate(name: "Onboarding")
        template.layers = [ScreenshotLayer(type: .text)]

        let blocks = try ScreenshotMarkdownImporter.parse(
            markdown: "# de-DE\n## Onboarding\n### \(layerA.uuidString)\nWillkommen"
        )
        let result = ScreenshotMarkdownImporter.apply(blocks: blocks, to: [template], primaryLocale: "en-US")

        #expect(result.updatedLayerCount == 0)
        #expect(result.unknownLayerIds == [layerA.uuidString])
        #expect(result.unknownLocales == ["de-DE"])
    }

    // MARK: - Export

    @Test func exportRoundTripsThroughTheParser() throws {
        let template = ScreenshotTemplate(name: "Onboarding")
        var layer = ScreenshotLayer(type: .text)
        layer.text = "Welcome"
        layer.translations = ["de-DE": "Willkommen"]
        template.layers = [layer]

        let markdown = ScreenshotMarkdownImporter.exportMarkdown(
            templates: [template],
            locales: ["en-US", "de-DE"],
            primaryLocale: "en-US"
        )
        let blocks = try ScreenshotMarkdownImporter.parse(markdown: markdown)

        #expect(Set(blocks.map(\.locale)) == ["en-US", "de-DE"])
        let german = try #require(blocks.first { $0.locale == "de-DE" })
        #expect(german.templates.first?.layers.first?.text == "Willkommen")
    }

    /// Untranslated layers export their primary text so translators overwrite in place
    /// instead of facing an empty file.
    @Test func exportFallsBackToPrimaryTextForMissingTranslations() throws {
        let template = ScreenshotTemplate(name: "Onboarding")
        var layer = ScreenshotLayer(type: .text)
        layer.text = "Welcome"
        template.layers = [layer]

        let markdown = ScreenshotMarkdownImporter.exportMarkdown(
            templates: [template],
            locales: ["fr-FR"],
            primaryLocale: "en-US"
        )
        let block = try #require(try ScreenshotMarkdownImporter.parse(markdown: markdown).first)

        #expect(block.templates.first?.layers.first?.text == "Welcome")
    }

    @Test func imageOnlyTemplatesAreExcludedFromTheExport() throws {
        let template = ScreenshotTemplate(name: "Hero")
        template.layers = [ScreenshotLayer(type: .image)]

        let markdown = ScreenshotMarkdownImporter.exportMarkdown(
            templates: [template],
            locales: ["en-US"],
            primaryLocale: "en-US"
        )

        #expect(!markdown.contains("## Hero"))
    }
}
