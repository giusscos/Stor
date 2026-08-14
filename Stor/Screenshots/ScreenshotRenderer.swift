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

        // Apply rotation around the layer center. CG uses Y-up coords so negate the angle.
        if layer.rotation != 0 {
            NSGraphicsContext.saveGraphicsState()
            let t = NSAffineTransform()
            t.translateX(by: rect.midX, yBy: rect.midY)
            t.rotate(byDegrees: -layer.rotation)
            t.translateX(by: -rect.midX, yBy: -rect.midY)
            t.concat()
        }

        // Rasterize the same SwiftUI view the canvas draws (including shadows) so
        // the PNG stays WYSIWYG. Drop shadows extend outside the layer frame, so
        // the render is padded and then drawn centered on `rect`.
        let pad = layer.dropShadow.rasterPadding(scale: exportScale)
        if let layerImage = renderLayerImage(
            layer,
            size: CGSize(width: rect.width, height: rect.height),
            scale: exportScale,
            locale: locale,
            padding: pad
        ) {
            let drawRect = CGRect(
                x: rect.minX - pad,
                y: rect.minY - pad,
                width: rect.width + pad * 2,
                height: rect.height + pad * 2
            )
            layerImage.draw(in: drawRect)
        }

        if layer.rotation != 0 {
            NSGraphicsContext.restoreGraphicsState()
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
private func renderLayerImage(
    _ layer: ScreenshotLayer,
    size: CGSize,
    scale: CGFloat,
    locale: String?,
    padding: CGFloat
) -> NSImage? {
    let padded = CGSize(width: size.width + padding * 2, height: size.height + padding * 2)
    let view = ScreenshotLayerContent(
        layer: layer,
        scale: scale,
        width: size.width,
        height: size.height,
        locale: locale,
        usesPreviewImage: false
    )
    .padding(padding)
    .frame(width: padded.width, height: padded.height)

    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(width: padded.width, height: padded.height)
    renderer.scale = 1
    return renderer.nsImage
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
