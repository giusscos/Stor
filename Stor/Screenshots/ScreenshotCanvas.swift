import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ScreenshotCanvas: View {
    let template: ScreenshotTemplate
    @Binding var selectedLayerId: UUID?
    var previewLocale: String? = nil
    /// In-flight layer state while an inspector slider is dragging — rendered in place
    /// of the committed layer so changes show live without a model write per tick.
    var liveOverrideLayer: ScreenshotLayer? = nil
    var isInteractive: Bool = true
    /// Wraps template mutations so the editor can register them with the undo manager.
    /// The read-only gallery preview never mutates, so a pass-through default is fine.
    var onMutate: (String, () -> Void) -> Void = { _, change in change() }
    @State private var dragStart: [UUID: CGPoint] = [:]
    @State private var dragOverride: (id: UUID, x: Double, y: Double)?
    @State private var isDropTargeted = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                CanvasBackgroundFill(background: template.background)

                ForEach(template.layers.filter { $0.isVisible }) { layer in
                    layerView(layer, in: geo.size)
                        .overlay {
                            if isInteractive, layer.id == selectedLayerId {
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color.accentColor, lineWidth: 1.5)
                            }
                        }
                        .onTapGesture { selectedLayerId = layer.id }
                        .gesture(layerDragGesture(layer, in: geo.size))
                }

                if isDropTargeted {
                    Color.accentColor.opacity(0.08)
                        .allowsHitTesting(false)
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 2.5)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers, location in
                guard isInteractive else { return false }
                handleDrop(providers: providers, at: location, canvasSize: geo.size)
                return true
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .allowsHitTesting(isInteractive)
    }

    private func layerDragGesture(_ layer: ScreenshotLayer, in size: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragStart[layer.id] == nil {
                    dragStart[layer.id] = CGPoint(x: layer.xFraction, y: layer.yFraction)
                }
                guard let start = dragStart[layer.id] else { return }
                let newX = max(-0.5, min(0.95, start.x + value.translation.width / size.width))
                let newY = max(0, min(0.95, start.y + value.translation.height / size.height))
                dragOverride = (id: layer.id, x: newX, y: newY)
            }
            .onEnded { _ in
                if let o = dragOverride, o.id == layer.id,
                   let idx = template.layers.firstIndex(where: { $0.id == layer.id }) {
                    onMutate("Move Layer") {
                        var layers = template.layers
                        layers[idx].xFraction = o.x
                        layers[idx].yFraction = o.y
                        template.layers = layers
                    }
                }
                dragOverride = nil
                dragStart.removeValue(forKey: layer.id)
                selectedLayerId = layer.id
            }
    }

    @ViewBuilder
    private func layerView(_ layer: ScreenshotLayer, in size: CGSize) -> some View {
        let effective: ScreenshotLayer = {
            var base = layer
            if let live = liveOverrideLayer, live.id == layer.id {
                base = live
            }
            if let o = dragOverride, o.id == layer.id {
                base.xFraction = o.x
                base.yFraction = o.y
            }
            return base
        }()
        let scale = size.width / 375
        let frame = effective.resolvedFrame(in: size, locale: previewLocale, fontScale: scale)
        let w = frame.width
        let h = frame.height
        let x = frame.minX
        let y = frame.minY

        switch effective.type {
        case .text:
            let pad = effective.textPaddingPt * scale
            let radius = effective.textCornerRadiusPt * scale
            effective.resolvedPreviewText(
                for: previewLocale,
                fontSize: effective.fontSizePt * scale,
                scale: scale
            )
            .multilineTextAlignment(
                effective.textAlignment == .leading ? .leading :
                    effective.textAlignment == .trailing ? .trailing : .center
            )
            .padding(pad)
            .frame(width: w, height: h, alignment: effective.textAlignment.swiftUI)
            .background {
                if let bgHex = effective.textBackgroundHex {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color(hex: bgHex))
                }
            }
            .position(x: x + w / 2, y: y + h / 2)

        case .image:
            if let img = effective.loadPreviewImage() {
                let cornerRadius = effective.imageCornerRadius * scale
                let contentRect = effective.imageContentRect(
                    imageSize: img.size,
                    in: CGRect(x: 0, y: 0, width: w, height: h)
                )
                ZStack {
                    // Radius clips the image's own rect (rounds square screenshots in
                    // fit mode) and the outer clip below rounds the layer bounds when
                    // the content covers them (fill / zoomed in).
                    Image(nsImage: img)
                        .resizable()
                        .frame(width: contentRect.width, height: contentRect.height)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                        .offset(
                            x: contentRect.midX - w / 2,
                            y: contentRect.midY - h / 2
                        )
                        .frame(width: w, height: h)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

                    if let assetName = effective.frameAssetName,
                       let frameImg = NSImage(named: assetName) {
                        Image(nsImage: frameImg)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: w, height: h)
                            .allowsHitTesting(false)
                    }
                }
                .frame(width: w, height: h)
                .position(x: x + w / 2, y: y + h / 2)
            }
        }
    }

    private func handleDrop(providers: [NSItemProvider], at location: CGPoint, canvasSize: CGSize) {
        guard let provider = providers.first else { return }
        let xFrac = max(0, min(0.25, location.x / canvasSize.width - 0.35))
        let yFrac = max(0, min(0.45, location.y / canvasSize.height - 0.25))

        provider.loadObject(ofClass: NSImage.self) { object, _ in
            guard let image = object as? NSImage,
                  let tiff = image.tiffRepresentation else { return }
            DispatchQueue.main.async { self.insertImageLayer(data: tiff, xFrac: xFrac, yFrac: yFrac) }
        }
    }

    private func insertImageLayer(data: Data, xFrac: Double, yFrac: Double) {
        onMutate("Add Image Layer") {
            var newLayer = ScreenshotLayer(type: .image)
            newLayer.imageData = data
            newLayer.widthFraction = 0.7
            newLayer.heightFraction = 0.5
            newLayer.xFraction = xFrac
            newLayer.yFraction = yFrac
            ImageLayerStyleStore.shared.applyDefault(to: &newLayer)
            template.layers.append(newLayer)
            selectedLayerId = newLayer.id
        }
    }
}
