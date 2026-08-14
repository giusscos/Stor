import SwiftUI
import AppKit

// MARK: - Model

/// Inner or outer shadow on a screenshot layer. Point values (blur, offset) are
/// authored against the same 375pt reference width as font size and radii.
struct LayerShadow: Codable, Equatable {
    var isEnabled: Bool
    var colorHex: String
    var opacity: Double
    var blur: Double
    var offsetX: Double
    var offsetY: Double

    /// Disabled drop shadow with defaults that already look right on a device mockup.
    static let drop = LayerShadow(
        isEnabled: false,
        colorHex: "#000000",
        opacity: 0.4,
        blur: 24,
        offsetX: 0,
        offsetY: 8
    )

    /// Disabled inner shadow with a softer default than the drop shadow.
    static let inner = LayerShadow(
        isEnabled: false,
        colorHex: "#000000",
        opacity: 0.35,
        blur: 16,
        offsetX: 0,
        offsetY: 4
    )

    var color: Color {
        Color(hex: colorHex).opacity(min(1, max(0, opacity)))
    }

    func radius(_ scale: CGFloat) -> CGFloat { max(0, blur) * scale }
    func x(_ scale: CGFloat) -> CGFloat { offsetX * scale }
    func y(_ scale: CGFloat) -> CGFloat { offsetY * scale }

    /// Extra padding so a drop shadow isn't clipped when the layer is rasterized for export.
    func rasterPadding(scale: CGFloat) -> CGFloat {
        guard isEnabled else { return 0 }
        return (blur * 3 + max(abs(offsetX), abs(offsetY))) * scale
    }
}

extension ScreenshotLayer {
    /// Inner shadows need a filled edge to clip against. Plain glyphs don't have one.
    var supportsInnerShadow: Bool { supportsChrome }

    /// Stroke follows the same filled edge as inner shadow (capsule / image clip / shape).
    var supportsStroke: Bool { supportsChrome }

    var supportsChrome: Bool {
        switch type {
        case .text: return hasTextBackground
        case .image, .shape: return true
        }
    }

    /// Shared clip used by inner shadow and stroke, in the layer's local bounds.
    func chromeShape(scale: CGFloat) -> AnyShape? {
        guard supportsChrome else { return nil }
        switch type {
        case .text:
            return AnyShape(
                RoundedRectangle(cornerRadius: textCornerRadiusPt * scale, style: .continuous)
            )
        case .image:
            let radius = imageCornerRadius * scale * max(0.01, frameScale)
            return AnyShape(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
        case .shape:
            switch shapeKind {
            case .rectangle:
                return AnyShape(
                    RoundedRectangle(cornerRadius: shapeCornerRadiusPt * scale, style: .continuous)
                )
            case .circle:
                return AnyShape(Circle())
            case .triangle:
                return AnyShape(TriangleShape())
            }
        }
    }

    /// Shape the inner shadow is clipped to, in the layer's local bounds.
    func innerShadowShape(scale: CGFloat) -> AnyShape? {
        guard innerShadow.isEnabled else { return nil }
        return chromeShape(scale: scale)
    }
}

// MARK: - SwiftUI

/// Even-odd inner shadow: clip to `shape`, then draw a shadowed fill of "everything
/// except the shape" so only the inward umbra remains. Matches the Core Graphics
/// technique used conceptually by SwiftUI's own inner shadows.
struct InnerShadowOverlay: View {
    var shape: AnyShape
    var shadow: LayerShadow
    var scale: CGFloat

    var body: some View {
        let color = shadow.color
        let radius = shadow.radius(scale)
        let x = shadow.x(scale)
        let y = shadow.y(scale)

        Canvas { context, size in
            let bounds = CGRect(origin: .zero, size: size)
            let path = shape.path(in: bounds)
            var ctx = context
            ctx.clip(to: path)

            var hole = Path(bounds.insetBy(dx: -size.width * 2, dy: -size.height * 2))
            hole.addPath(path)
            ctx.addFilter(.shadow(color: color, radius: radius, x: x, y: y))
            ctx.fill(hole, with: .color(.black), style: FillStyle(eoFill: true))
        }
        .allowsHitTesting(false)
    }
}

extension View {
    @ViewBuilder
    func layerInnerShadow(_ shadow: LayerShadow, scale: CGFloat, shape: AnyShape?) -> some View {
        if shadow.isEnabled, let shape {
            overlay { InnerShadowOverlay(shape: shape, shadow: shadow, scale: scale) }
        } else {
            self
        }
    }

    @ViewBuilder
    func layerDropShadow(_ shadow: LayerShadow, scale: CGFloat) -> some View {
        if shadow.isEnabled {
            self.shadow(
                color: shadow.color,
                radius: shadow.radius(scale),
                x: shadow.x(scale),
                y: shadow.y(scale)
            )
        } else {
            self
        }
    }
}

// MARK: - Shared layer rendering (canvas + PNG export)

/// Visual content of a layer, including shadows. The canvas draws this directly;
/// export rasterizes the same view so the PNG matches the editor.
struct ScreenshotLayerContent: View {
    let layer: ScreenshotLayer
    let scale: CGFloat
    let width: CGFloat
    let height: CGFloat
    var locale: String? = nil
    var usesPreviewImage: Bool = true

    var body: some View {
        rawContent
            .frame(width: width, height: height)
            .compositingGroup()
            .layerDropShadow(layer.dropShadow, scale: scale)
            .opacity(min(1, max(0, layer.opacity)))
    }

    @ViewBuilder
    private var rawContent: some View {
        switch layer.type {
        case .text:
            textContent
        case .image:
            imageContent
        case .shape:
            ShapeLayerView(layer: layer, scale: scale)
                .frame(width: width, height: height)
        }
    }

    @ViewBuilder
    private var textContent: some View {
        let pad = layer.textPaddingPt * scale
        let radius = layer.textCornerRadiusPt * scale
        layer.resolvedPreviewText(
            for: locale,
            fontSize: layer.fontSizePt * scale,
            scale: scale
        )
        .multilineTextAlignment(
            layer.textAlignment == .leading ? .leading :
                layer.textAlignment == .trailing ? .trailing : .center
        )
        .padding(pad)
        .frame(width: width, height: height, alignment: layer.textAlignment.swiftUI)
        .background {
            if let bgHex = layer.textBackgroundHex {
                let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
                ZStack {
                    shape.fill(Color(hex: bgHex))
                    if layer.innerShadow.isEnabled {
                        InnerShadowOverlay(
                            shape: AnyShape(shape),
                            shadow: layer.innerShadow,
                            scale: scale
                        )
                    }
                    if layer.strokeWidth > 0 {
                        shape.stroke(
                            Color(hex: layer.strokeColorHex),
                            lineWidth: layer.strokeWidth * scale
                        )
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var imageContent: some View {
        if let img = usesPreviewImage ? layer.loadPreviewImage() : layer.loadImage() {
            let cornerRadius = layer.imageCornerRadius * scale * max(0.01, layer.frameScale)
            let contentRect = layer.imageContentRect(
                imageSize: img.size,
                in: CGRect(x: 0, y: 0, width: width, height: height)
            )
            let clip = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            ZStack {
                Image(nsImage: img)
                    .resizable()
                    .frame(width: contentRect.width, height: contentRect.height)
                    .clipShape(clip)
                    .offset(
                        x: contentRect.midX - width / 2,
                        y: contentRect.midY - height / 2
                    )
                    .frame(width: width, height: height)
                    .clipShape(clip)
                    .layerInnerShadow(
                        layer.innerShadow,
                        scale: scale,
                        shape: layer.innerShadowShape(scale: scale)
                    )
                    .overlay {
                        if layer.strokeWidth > 0 {
                            clip.stroke(
                                Color(hex: layer.strokeColorHex),
                                lineWidth: layer.strokeWidth * scale
                            )
                        }
                    }

                if let assetName = layer.frameAssetName,
                   let frameImg = NSImage(named: assetName) {
                    Image(nsImage: frameImg)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: width, height: height)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: width, height: height)
        }
    }
}
