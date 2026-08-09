import CoreGraphics
import Foundation
import Testing
@testable import Stor

/// The canvas and the PNG exporter compute these rects independently of each other's
/// rendering code, so a drift here shows up as screenshots that look right in the editor
/// and wrong in the uploaded file.
struct ScreenshotGeometryTests {
    private let layerRect = CGRect(x: 0, y: 0, width: 200, height: 100)

    private func imageLayer() -> ScreenshotLayer {
        ScreenshotLayer(type: .image)
    }

    // MARK: - Device frame

    @Test func deviceFrameLetterboxesTallFramesInsideWideLayers() {
        let rect = ScreenshotLayer.deviceFrameRect(frameSize: CGSize(width: 100, height: 200), in: layerRect)

        // Fit is height-bound here: 100 tall, so the frame is 50 wide.
        #expect(rect.height == 100)
        #expect(rect.width == 50)
    }

    @Test func deviceFrameStaysCentred() {
        let rect = ScreenshotLayer.deviceFrameRect(frameSize: CGSize(width: 100, height: 200), in: layerRect)

        #expect(rect.midX == layerRect.midX)
        #expect(rect.midY == layerRect.midY)
    }

    @Test func deviceFramePreservesAspectRatio() {
        let frameSize = CGSize(width: 300, height: 650)
        let rect = ScreenshotLayer.deviceFrameRect(frameSize: frameSize, in: layerRect)

        let expected = frameSize.width / frameSize.height
        #expect(abs(rect.width / rect.height - expected) < 0.0001)
    }

    @Test func deviceFrameNeverExceedsTheLayer() {
        let rect = ScreenshotLayer.deviceFrameRect(frameSize: CGSize(width: 4000, height: 100), in: layerRect)

        #expect(rect.width <= layerRect.width + 0.0001)
        #expect(rect.height <= layerRect.height + 0.0001)
    }

    @Test func degenerateFrameSizeFallsBackToTheLayer() {
        #expect(ScreenshotLayer.deviceFrameRect(frameSize: .zero, in: layerRect) == layerRect)
    }

    // MARK: - Image content

    @Test func fitLeavesTheWholeImageVisible() {
        var layer = imageLayer()
        layer.imageFills = false

        let rect = layer.imageContentRect(imageSize: CGSize(width: 100, height: 200), in: layerRect)

        #expect(rect.height == 100)
        #expect(rect.width == 50)
    }

    @Test func fillCoversTheLayerAndCrops() {
        var layer = imageLayer()
        layer.imageFills = true

        let rect = layer.imageContentRect(imageSize: CGSize(width: 100, height: 200), in: layerRect)

        // Width-bound at 200, so the image overflows vertically and gets cropped.
        #expect(rect.width == 200)
        #expect(rect.height == 400)
    }

    @Test func contentScaleZoomsAroundTheCentre() {
        var layer = imageLayer()
        layer.contentScale = 2

        let rect = layer.imageContentRect(imageSize: CGSize(width: 100, height: 100), in: layerRect)

        #expect(rect.width == 200)
        #expect(rect.midX == layerRect.midX)
        #expect(rect.midY == layerRect.midY)
    }

    /// Offsets are fractions of the layer so they survive resizing the layer.
    @Test func contentOffsetIsRelativeToTheLayerSize() {
        var layer = imageLayer()
        layer.contentOffsetX = 0.25
        layer.contentOffsetY = -0.5

        let rect = layer.imageContentRect(imageSize: CGSize(width: 100, height: 100), in: layerRect)

        #expect(rect.midX == layerRect.midX + 50)
        #expect(rect.midY == layerRect.midY - 50)
    }

    @Test func nonPositiveContentScaleIsClamped() {
        var layer = imageLayer()
        layer.contentScale = 0

        let rect = layer.imageContentRect(imageSize: CGSize(width: 100, height: 100), in: layerRect)

        #expect(rect.width > 0)
        #expect(rect.height > 0)
    }

    @Test func degenerateImageSizeFallsBackToTheLayer() {
        #expect(imageLayer().imageContentRect(imageSize: .zero, in: layerRect) == layerRect)
    }
}

struct ScreenshotLayerTextTests {
    @Test func translationsWinOverThePrimaryString() {
        var layer = ScreenshotLayer(type: .text)
        layer.text = "Hello"
        layer.translations = ["de-DE": "Hallo"]

        #expect(layer.resolvedText(for: "de-DE") == "Hallo")
        #expect(layer.resolvedText(for: "fr-FR") == "Hello")
        #expect(layer.resolvedText(for: nil) == "Hello")
    }

    @Test func emptyTranslationsFallBackRatherThanRenderingBlank() {
        var layer = ScreenshotLayer(type: .text)
        layer.text = "Hello"
        layer.translations = ["de-DE": ""]

        #expect(layer.resolvedText(for: "de-DE") == "Hello")
    }

    @Test func localeLookupIsCaseInsensitive() {
        var layer = ScreenshotLayer(type: .text)
        layer.text = "Hello"
        layer.translations = ["pt-BR": "Olá"]

        #expect(layer.resolvedText(for: "pt-br") == "Olá")
    }

    /// Editing the primary locale has to update `text`, which is what non-localized
    /// exports and the layers list both read.
    @Test func writingThePrimaryLocaleAlsoUpdatesTheDefaultText() {
        var layer = ScreenshotLayer(type: .text)
        layer.setResolvedText("Hallo", for: "de-DE", primaryLocale: "de-DE")

        #expect(layer.text == "Hallo")
        #expect(layer.translations["de-DE"] == "Hallo")
    }

    @Test func writingASecondaryLocaleLeavesTheDefaultTextAlone() {
        var layer = ScreenshotLayer(type: .text)
        layer.text = "Hello"
        layer.setResolvedText("Hallo", for: "de-DE", primaryLocale: "en-US")

        #expect(layer.text == "Hello")
        #expect(layer.translations["de-DE"] == "Hallo")
    }

    @Test func fontWeightAndBoldStayInSync() {
        var layer = ScreenshotLayer(type: .text)

        layer.fontWeight = .regular
        #expect(layer.isBold == false)

        layer.fontWeight = .heavy
        #expect(layer.isBold == true)
    }
}
