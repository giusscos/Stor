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

struct LayerShadowTests {
    @Test func disabledDropShadowNeedsNoRasterPadding() {
        #expect(LayerShadow.drop.rasterPadding(scale: 2) == 0)
    }

    @Test func rasterPaddingGrowsWithBlurOffsetAndScale() {
        var shadow = LayerShadow.drop
        shadow.isEnabled = true
        shadow.blur = 10
        shadow.offsetX = 0
        shadow.offsetY = 8

        #expect(shadow.rasterPadding(scale: 1) == 38)
        #expect(shadow.rasterPadding(scale: 2) == 76)
    }

    @Test func legacyLayerJSONOmittingShadowsStillDecodes() throws {
        let data = Data(#"{"type":"text"}"#.utf8)
        let layer = try JSONDecoder().decode(ScreenshotLayer.self, from: data)

        #expect(layer.dropShadow == .drop)
        #expect(layer.innerShadow == .inner)
    }

    @Test func enabledShadowsRoundTripThroughJSON() throws {
        var layer = ScreenshotLayer(type: .image)
        layer.dropShadow.isEnabled = true
        layer.dropShadow.blur = 30
        layer.dropShadow.offsetY = 12
        layer.innerShadow.isEnabled = true
        layer.innerShadow.opacity = 0.5

        let decoded = try JSONDecoder().decode(
            ScreenshotLayer.self,
            from: try JSONEncoder().encode(layer)
        )

        #expect(decoded.dropShadow == layer.dropShadow)
        #expect(decoded.innerShadow == layer.innerShadow)
    }

    @Test func textInnerShadowRequiresABackground() {
        var layer = ScreenshotLayer(type: .text)
        #expect(layer.supportsInnerShadow == false)

        layer.hasTextBackground = true
        #expect(layer.supportsInnerShadow == true)
    }

    @Test func imageAndShapeAlwaysSupportInnerShadow() {
        #expect(ScreenshotLayer(type: .image).supportsInnerShadow)
        #expect(ScreenshotLayer(type: .shape).supportsInnerShadow)
    }
}

struct LayerAppearanceTests {
    @Test func legacyShapeOpacityMigratesToLayerOpacity() throws {
        let data = Data(#"{"type":"shape","shapeOpacity":0.4}"#.utf8)
        let layer = try JSONDecoder().decode(ScreenshotLayer.self, from: data)
        #expect(abs(layer.opacity - 0.4) < 0.0001)
    }

    @Test func opacityAndLockRoundTrip() throws {
        var layer = ScreenshotLayer(type: .text)
        layer.opacity = 0.55
        layer.isLocked = true
        layer.strokeWidth = 3
        layer.strokeColorHex = "#FF0000"

        let decoded = try JSONDecoder().decode(
            ScreenshotLayer.self,
            from: try JSONEncoder().encode(layer)
        )

        #expect(abs(decoded.opacity - 0.55) < 0.0001)
        #expect(decoded.isLocked)
        #expect(decoded.strokeWidth == 3)
        #expect(decoded.strokeColorHex == "#FF0000")
        #expect(decoded.shapeOpacity == decoded.opacity)
    }

    @Test func textStrokeRequiresABackground() {
        var layer = ScreenshotLayer(type: .text)
        #expect(layer.supportsStroke == false)
        layer.hasTextBackground = true
        #expect(layer.supportsStroke == true)
    }

    @Test func alignToCanvasCentersAndPinsEdges() {
        var layer = ScreenshotLayer(type: .shape)
        layer.widthFraction = 0.4
        layer.heightFraction = 0.2
        layer.xFraction = 0.1
        layer.yFraction = 0.1
        let canvas = CGSize(width: 100, height: 100)

        layer.alignToCanvas(horizontal: .center, canvasSize: canvas, locale: nil, fontScale: 1)
        #expect(abs(layer.xFraction - 0.3) < 0.0001)

        layer.alignToCanvas(vertical: .middle, canvasSize: canvas, locale: nil, fontScale: 1)
        #expect(abs(layer.yFraction - 0.4) < 0.0001)

        layer.alignToCanvas(horizontal: .left, vertical: .top, canvasSize: canvas, locale: nil, fontScale: 1)
        #expect(layer.xFraction == 0)
        #expect(layer.yFraction == 0)

        layer.alignToCanvas(horizontal: .right, vertical: .bottom, canvasSize: canvas, locale: nil, fontScale: 1)
        #expect(abs(layer.xFraction - 0.6) < 0.0001)
        #expect(abs(layer.yFraction - 0.8) < 0.0001)
    }

    @Test func imageAlignAccountsForFrameScale() {
        var layer = ScreenshotLayer(type: .image)
        layer.widthFraction = 0.4
        layer.frameScale = 2
        let canvas = CGSize(width: 100, height: 100)
        layer.alignToCanvas(horizontal: .center, canvasSize: canvas, locale: nil, fontScale: 1)
        // Visual width is 0.8 of the canvas, so x = (1 - 0.8) / 2
        #expect(abs(layer.xFraction - 0.1) < 0.0001)
    }

    @Test func fitToContentAlignUsesMeasuredTextNotStoredWidth() {
        var layer = ScreenshotLayer(type: .text)
        layer.text = "Hi"
        layer.fitWidthToContent = true
        layer.widthFraction = 0.8
        layer.xFraction = 0
        let canvas = CGSize(width: 375, height: 812)

        layer.alignToCanvas(horizontal: .center, canvasSize: canvas, locale: nil, fontScale: 1)
        let visual = layer.resolvedSize(in: canvas, locale: nil, fontScale: 1)
        let expected = (canvas.width - visual.width) / 2 / canvas.width

        #expect(abs(layer.xFraction - expected) < 0.001)
        // Stale widthFraction of 0.8 would have produced 0.1 — that's the bug.
        #expect(abs(layer.xFraction - 0.1) > 0.05)

        layer.alignToCanvas(horizontal: .right, canvasSize: canvas, locale: nil, fontScale: 1)
        let expectedRight = (canvas.width - visual.width) / canvas.width
        #expect(abs(layer.xFraction - expectedRight) < 0.001)
    }

    @Test func normalizedRotationWrapsIntoPlusMinus180() {
        var layer = ScreenshotLayer(type: .text)
        layer.rotation = 270
        #expect(abs(layer.normalizedRotation - (-90)) < 0.0001)
        layer.rotation = -270
        #expect(abs(layer.normalizedRotation - 90) < 0.0001)
        layer.rotation = 15
        #expect(abs(layer.normalizedRotation - 15) < 0.0001)
    }

    @Test func newNonShapeLayersHaveNoStrokeByDefault() {
        #expect(ScreenshotLayer(type: .text).strokeWidth == 0)
        #expect(ScreenshotLayer(type: .image).strokeWidth == 0)
        #expect(ScreenshotLayer(type: .shape).strokeWidth == 2)
    }
}
