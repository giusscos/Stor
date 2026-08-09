import AppKit
import Foundation
import SwiftUI

@MainActor
func renderTemplate(_ template: ScreenshotTemplate, locale: String? = nil) -> Data? {
    let size = template.deviceType.canvasSize
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width),
        pixelsHigh: Int(size.height),
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
    guard let rep else { return nil }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    if let bgImage = renderBackgroundImage(template.background, size: size) {
        bgImage.draw(in: NSRect(origin: .zero, size: size))
    } else {
        NSColor(Color(hex: template.backgroundColorHex)).setFill()
        NSRect(origin: .zero, size: size).fill()
    }

    // Point values (font size, padding, radii) are authored against a 375pt reference
    // width — the same reference the canvas preview uses — so scale them up for the
    // full-resolution bitmap to keep the export WYSIWYG with the canvas.
    let exportScale = size.width / 375

    for layer in template.layers where layer.isVisible {
        let layerSize = layer.resolvedSize(in: size, locale: locale, fontScale: exportScale)
        let rect = CGRect(
            x: layer.xFraction * size.width,
            y: (1 - layer.yFraction) * size.height - layerSize.height,
            width: layerSize.width,
            height: layerSize.height
        )
        switch layer.type {
        case .text:
            if let bgHex = layer.textBackgroundHex {
                let radius = layer.textCornerRadiusPt * exportScale
                let path = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
                NSColor(Color(hex: bgHex)).setFill()
                path.fill()
            }
            let pad = layer.textPaddingPt * exportScale
            let textRect = rect.insetBy(dx: pad, dy: pad)
            if let attributed = layer.resolvedAttributedString(
                for: locale,
                fontSize: layer.fontSizePt * exportScale,
                scale: exportScale
            ) {
                attributed.draw(in: textRect)
            }
        case .image:
            if let img = layer.loadImage() {
                let radius = layer.imageCornerRadius * exportScale

                // The bitmap context has a bottom-left origin, while imageContentRect
                // works in top-left space — flip the offset's Y for the shared math.
                var contentLayer = layer
                contentLayer.contentOffsetY = -layer.contentOffsetY
                let drawRect = contentLayer.imageContentRect(imageSize: img.size, in: rect)

                NSGraphicsContext.saveGraphicsState()
                if radius > 0 {
                    // Round the image's own corners (visible in fit mode) and the layer
                    // bounds (visible in fill/zoomed mode) — mirrors the preview clips.
                    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).addClip()
                    NSBezierPath(roundedRect: drawRect, xRadius: radius, yRadius: radius).addClip()
                } else {
                    NSBezierPath(rect: rect).addClip()
                }
                img.draw(in: drawRect)
                NSGraphicsContext.restoreGraphicsState()

                if let assetName = layer.frameAssetName,
                   let frameImg = NSImage(named: assetName) {
                    frameImg.draw(in: ScreenshotLayer.deviceFrameRect(frameSize: frameImg.size, in: rect))
                }
            }

        case .shape:
            let shapeView = ShapeLayerView(layer: layer, scale: exportScale)
                .frame(width: rect.width, height: rect.height)
            let shapeRenderer = ImageRenderer(content: shapeView)
            shapeRenderer.proposedSize = ProposedViewSize(width: rect.width, height: rect.height)
            shapeRenderer.scale = 1
            if let shapeImage = shapeRenderer.nsImage {
                shapeImage.draw(in: rect)
            }
        }
    }

    NSGraphicsContext.restoreGraphicsState()

    let image = NSImage(size: NSSize(width: size.width, height: size.height))
    image.addRepresentation(rep)
    guard let tiff = image.tiffRepresentation,
          let pngRep = NSBitmapImageRep(data: tiff) else { return nil }
    return pngRep.representation(using: .png, properties: [:])
}

@MainActor
func renderBackgroundImage(_ background: CanvasBackground, size: CGSize) -> NSImage? {
    let view = CanvasBackgroundFill(background: background)
        .frame(width: size.width, height: size.height)
    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
    renderer.scale = 1
    return renderer.nsImage
}
