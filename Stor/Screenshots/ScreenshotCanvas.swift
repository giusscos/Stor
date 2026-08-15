import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ScreenshotCanvas: View {
    let template: ScreenshotTemplate
    @Binding var selectedLayerId: UUID?
    var previewLocale: String? = nil
    var liveOverrideLayer: ScreenshotLayer? = nil
    var isInteractive: Bool = true
    /// Extends the canvas hit-test/hover region beyond the screenshot frame so layers
    /// moved off-canvas remain hoverable. Match the editor's overflow padding.
    var overflowHitMargin: CGFloat = 0
    /// Wraps template mutations so the editor can register them with the undo manager.
    var onMutate: (String, () -> Void) -> Void = { _, change in change() }

    // Position drag
    @State private var dragStart: [UUID: CGPoint] = [:]
    @State private var dragOverride: (id: UUID, x: Double, y: Double)?
    // Scale drag
    @State private var scaleStart: (id: UUID, layer: ScreenshotLayer)?
    @State private var scaleOverride: (id: UUID, xFrac: Double, yFrac: Double, wFrac: Double, hFrac: Double)?
    // Rotation drag
    @State private var rotationDragState: (id: UUID, initialDegrees: Double)?
    @State private var rotationOverride: (id: UUID, degrees: Double)?

    @State private var isDropTargeted = false
    @State private var hoveredLayerId: UUID?

    private enum ResizeCorner { case topLeft, topRight, bottomLeft, bottomRight }

    /// Named coordinate space of the canvas ZStack, so gestures report canvas-space
    /// values even when attached below a `.rotationEffect`.
    private static let canvasSpace = "screenshotCanvas"

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                // Only the content clips to the screenshot bounds — strokes and handles
                // draw above, unclipped, so off-canvas layers stay discoverable.
                ZStack(alignment: .topLeading) {
                    CanvasBackgroundFill(background: template.background)

                    ForEach(template.layers.filter { $0.isVisible }) { layer in
                        layerView(layer, in: geo.size)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 8))

                if isInteractive {
                    outOfBoundsStrokes(in: geo.size)
                    hoverUI(in: geo.size)
                    selectionUI(in: geo.size)
                }

                if isDropTargeted {
                    Color.accentColor.opacity(0.08)
                        .allowsHitTesting(false)
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 2.5)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle().inset(by: -overflowHitMargin))
            .onContinuousHover(coordinateSpace: .local) { phase in
                guard isInteractive else { return }
                switch phase {
                case .active(let location):
                    let scale = geo.size.width / 375

                    // Handles (corner squares + rotation circle) are part of the selected layer.
                    // When the cursor is inside the selected layer's frame or handle zone, suppress
                    // hover on all other layers so nothing beneath lights up.
                    var inHandleZone = false
                    if let selId = selectedLayerId,
                       let selRaw = template.layers.first(where: { $0.id == selId && $0.isVisible }) {
                        let sel = effectiveLayer(selRaw)
                        let selFrame = sel.resolvedFrame(in: geo.size, locale: previewLocale, fontScale: scale)
                        // Handles rotate with the layer, so test in its unrotated local space
                        let local = Self.unrotated(location, around: CGPoint(x: selFrame.midX, y: selFrame.midY), degrees: sel.rotation)
                        // Expand 4pt to cover the 8×8 corner squares that sit on the frame border
                        let expanded = selFrame.insetBy(dx: -4, dy: -4)
                        // Rotation handle: 10pt circle centered 24pt above top-center
                        let rotZone = CGRect(x: selFrame.midX - 8, y: selFrame.minY - 32, width: 16, height: 16)
                        inHandleZone = expanded.contains(local) || rotZone.contains(local)
                    }

                    if inHandleZone {
                        hoveredLayerId = nil
                    } else {
                        // Exclude the selected layer — it already shows the selection border
                        let hit = template.layers
                            .filter { $0.isVisible && $0.id != selectedLayerId }
                            .reversed()
                            .first { layer in
                                let eff = effectiveLayer(layer)
                                let frame = eff.resolvedFrame(in: geo.size, locale: previewLocale, fontScale: scale)
                                let local = Self.unrotated(location, around: CGPoint(x: frame.midX, y: frame.midY), degrees: eff.rotation)
                                return frame.contains(local)
                            }
                        hoveredLayerId = hit?.id
                    }
                case .ended:
                    hoveredLayerId = nil
                }
            }
            .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers, location in
                guard isInteractive else { return false }
                handleDrop(providers: providers, at: location, canvasSize: geo.size)
                return true
            }
            .coordinateSpace(name: Self.canvasSpace)
        }
        .allowsHitTesting(isInteractive)
    }

    // MARK: - Geometry helpers

    /// Maps a canvas-space point into a layer's unrotated local space by rotating it
    /// `-degrees` around the layer center.
    private static func unrotated(_ point: CGPoint, around center: CGPoint, degrees: Double) -> CGPoint {
        guard degrees != 0 else { return point }
        let theta = -degrees * .pi / 180
        let dx = point.x - center.x
        let dy = point.y - center.y
        return CGPoint(
            x: center.x + dx * cos(theta) - dy * sin(theta),
            y: center.y + dx * sin(theta) + dy * cos(theta)
        )
    }

    /// Rotates a vector by `degrees` (canvas orientation, clockwise-positive in flipped coords).
    private static func rotated(_ vector: CGPoint, degrees: Double) -> CGPoint {
        guard degrees != 0 else { return vector }
        let theta = degrees * .pi / 180
        return CGPoint(
            x: vector.x * cos(theta) - vector.y * sin(theta),
            y: vector.x * sin(theta) + vector.y * cos(theta)
        )
    }

    /// Canvas-space axis-aligned bounding box of the layer after rotation.
    private static func rotatedBounds(of layer: ScreenshotLayer, in size: CGSize, locale: String?) -> CGRect {
        let frame = layer.resolvedFrame(in: size, locale: locale, fontScale: size.width / 375)
        guard layer.rotation != 0 else { return frame }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let corners = [
            CGPoint(x: -frame.width / 2, y: -frame.height / 2),
            CGPoint(x:  frame.width / 2, y: -frame.height / 2),
            CGPoint(x: -frame.width / 2, y:  frame.height / 2),
            CGPoint(x:  frame.width / 2, y:  frame.height / 2)
        ].map { rotated($0, degrees: layer.rotation) }
        let xs = corners.map { center.x + $0.x }
        let ys = corners.map { center.y + $0.y }
        return CGRect(
            x: xs.min() ?? frame.minX,
            y: ys.min() ?? frame.minY,
            width: (xs.max() ?? frame.maxX) - (xs.min() ?? frame.minX),
            height: (ys.max() ?? frame.maxY) - (ys.min() ?? frame.minY)
        )
    }

    // MARK: - Effective layer

    private func effectiveLayer(_ layer: ScreenshotLayer) -> ScreenshotLayer {
        var base = layer
        if let live = liveOverrideLayer, live.id == layer.id { base = live }
        if let o = dragOverride, o.id == layer.id {
            base.xFraction = o.x
            base.yFraction = o.y
        }
        if let o = scaleOverride, o.id == layer.id {
            base.xFraction = o.xFrac
            base.yFraction = o.yFrac
            base.widthFraction = o.wFrac
            base.heightFraction = o.hFrac
        }
        if let o = rotationOverride, o.id == layer.id {
            base.rotation = o.degrees
        }
        return base
    }

    /// Outline stroke drawn in canvas space (above the clipped content), rotated to
    /// match the layer. Used for hover and for layers extending beyond the canvas.
    @ViewBuilder
    private func layerStroke(_ layer: ScreenshotLayer, in size: CGSize, opacity: Double) -> some View {
        let frame = layer.resolvedFrame(in: size, locale: previewLocale, fontScale: size.width / 375)
        RoundedRectangle(cornerRadius: 2)
            .stroke(Color.accentColor.opacity(opacity), lineWidth: 1.5)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            .rotationEffect(
                Angle(degrees: layer.rotation),
                anchor: UnitPoint(
                    x: frame.midX / max(size.width, 1),
                    y: frame.midY / max(size.height, 1)
                )
            )
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private func hoverUI(in size: CGSize) -> some View {
        if let id = hoveredLayerId, id != selectedLayerId,
           let raw = template.layers.first(where: { $0.id == id && $0.isVisible }) {
            layerStroke(effectiveLayer(raw), in: size, opacity: 0.7)
        }
    }

    /// Layers that stick out past the screenshot edges get a persistent faint outline,
    /// since their content is clipped and would otherwise be invisible.
    @ViewBuilder
    private func outOfBoundsStrokes(in size: CGSize) -> some View {
        // Slight outset so layers flush with an edge don't flicker a stroke from rounding.
        let canvasRect = CGRect(origin: .zero, size: size).insetBy(dx: -1, dy: -1)
        ForEach(template.layers.filter { $0.isVisible }) { raw in
            let effective = effectiveLayer(raw)
            if effective.id != selectedLayerId,
               effective.id != hoveredLayerId,
               !canvasRect.contains(Self.rotatedBounds(of: effective, in: size, locale: previewLocale)) {
                layerStroke(effective, in: size, opacity: 0.35)
            }
        }
    }

    // MARK: - Layer rendering

    @ViewBuilder
    private func layerView(_ layer: ScreenshotLayer, in size: CGSize) -> some View {
        let effective = effectiveLayer(layer)
        let scale = size.width / 375
        let frame = effective.resolvedFrame(in: size, locale: previewLocale, fontScale: scale)
        let w = frame.width
        let h = frame.height

        // Gestures go on the content BEFORE .position() so they are scoped to the
        // layer's actual w×h frame, not the full canvas that .position() expands to.
        ScreenshotLayerContent(
            layer: effective,
            scale: scale,
            width: w,
            height: h,
            locale: previewLocale,
            usesPreviewImage: true
        )
        .contentShape(Rectangle())
        .onTapGesture { selectedLayerId = layer.id }
        .gesture(layerDragGesture(layer, in: size), isEnabled: !effective.isLocked)
        .rotationEffect(Angle(degrees: effective.rotation))
        .position(x: frame.midX, y: frame.midY)
    }

    // MARK: - Selection UI (drawn above all layers in canvas space)

    @ViewBuilder
    private func selectionUI(in size: CGSize) -> some View {
        if let id = selectedLayerId,
           let raw = template.layers.first(where: { $0.id == id && $0.isVisible }) {
            let effective = effectiveLayer(raw)
            let frame = effective.resolvedFrame(in: size, locale: previewLocale, fontScale: size.width / 375)
            selectedLayerUI(
                layerId: id,
                frame: frame,
                rotation: effective.rotation,
                isLocked: effective.isLocked,
                canvasSize: size
            )
        }
    }

    @ViewBuilder
    private func selectedLayerUI(layerId: UUID, frame: CGRect, rotation: Double, isLocked: Bool, canvasSize: CGSize) -> some View {
        let rotHandlePos = CGPoint(x: frame.midX, y: frame.minY - 24)

        ZStack(alignment: .topLeading) {
            // Selection border
            RoundedRectangle(cornerRadius: 2)
                .stroke(isLocked ? Color.secondary : Color.accentColor, lineWidth: 2)
                .frame(width: frame.width, height: frame.height)
                .position(x: frame.midX, y: frame.midY)
                .allowsHitTesting(false)

            if !isLocked {
                // Connector line to rotation handle
                Path { p in
                    p.move(to: CGPoint(x: frame.midX, y: frame.minY))
                    p.addLine(to: rotHandlePos)
                }
                .stroke(Color.accentColor, lineWidth: 1)
                .allowsHitTesting(false)

                // Rotation handle (circle above top-center)
                Circle()
                    .fill(Color.white)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(Color.accentColor, lineWidth: 1.5))
                    .gesture(rotationGesture(
                        layerId: layerId,
                        layerCenter: CGPoint(x: frame.midX, y: frame.midY)
                    ))
                    .position(rotHandlePos)

                // Corner scale handles
                cornerHandle(.topLeft,     layerId: layerId, at: CGPoint(x: frame.minX, y: frame.minY), canvasSize: canvasSize)
                cornerHandle(.topRight,    layerId: layerId, at: CGPoint(x: frame.maxX, y: frame.minY), canvasSize: canvasSize)
                cornerHandle(.bottomLeft,  layerId: layerId, at: CGPoint(x: frame.minX, y: frame.maxY), canvasSize: canvasSize)
                cornerHandle(.bottomRight, layerId: layerId, at: CGPoint(x: frame.maxX, y: frame.maxY), canvasSize: canvasSize)
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height)
        // Rotate the whole selection chrome around the layer center so the border
        // and handles stay glued to the rotated content.
        .rotationEffect(
            Angle(degrees: rotation),
            anchor: UnitPoint(
                x: frame.midX / max(canvasSize.width, 1),
                y: frame.midY / max(canvasSize.height, 1)
            )
        )
    }

    @ViewBuilder
    private func cornerHandle(_ corner: ResizeCorner, layerId: UUID, at pos: CGPoint, canvasSize: CGSize) -> some View {
        Rectangle()
            .fill(Color.white)
            .frame(width: 8, height: 8)
            .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1.5))
            .gesture(cornerScaleGesture(corner, layerId: layerId, canvasSize: canvasSize))
            .position(pos)
    }

    // MARK: - Scale gesture

    private func cornerScaleGesture(_ corner: ResizeCorner, layerId: UUID, canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.canvasSpace))
            .onChanged { value in
                if scaleStart?.id != layerId,
                   let raw = template.layers.first(where: { $0.id == layerId }) {
                    scaleStart = (layerId, raw)
                }
                guard let start = scaleStart, start.id == layerId else { return }
                let src = start.layer
                let frame0 = src.resolvedFrame(in: canvasSize, locale: previewLocale, fontScale: canvasSize.width / 375)
                let center0 = CGPoint(x: frame0.midX, y: frame0.midY)

                // Which way this corner points from the center, in the layer's local axes.
                let sign: CGPoint
                switch corner {
                case .topLeft:     sign = CGPoint(x: -1, y: -1)
                case .topRight:    sign = CGPoint(x:  1, y: -1)
                case .bottomLeft:  sign = CGPoint(x: -1, y:  1)
                case .bottomRight: sign = CGPoint(x:  1, y:  1)
                }

                // The opposite corner stays fixed in canvas space while dragging.
                let anchorOffset = Self.rotated(
                    CGPoint(x: -sign.x * frame0.width / 2, y: -sign.y * frame0.height / 2),
                    degrees: src.rotation
                )
                let anchor = CGPoint(x: center0.x + anchorOffset.x, y: center0.y + anchorOffset.y)

                // Drag delta expressed in the layer's local axes.
                let dLocal = Self.rotated(
                    CGPoint(x: value.translation.width, y: value.translation.height),
                    degrees: -src.rotation
                )

                let w = max(0.05 * canvasSize.width, frame0.width + sign.x * dLocal.x)
                let h = max(0.05 * canvasSize.height, frame0.height + sign.y * dLocal.y)

                // Recompute the center so the anchor corner keeps its canvas position.
                let halfDiag = Self.rotated(CGPoint(x: sign.x * w / 2, y: sign.y * h / 2), degrees: src.rotation)
                let center = CGPoint(x: anchor.x + halfDiag.x, y: anchor.y + halfDiag.y)

                // Convert the rendered size back to fractions, preserving any extra
                // scale factors (e.g. image frameScale) baked into the resolved frame.
                let xF = (center.x - w / 2) / canvasSize.width
                let yF = (center.y - h / 2) / canvasSize.height
                let wF = src.widthFraction * (w / max(frame0.width, 1))
                let hF = src.heightFraction * (h / max(frame0.height, 1))
                scaleOverride = (layerId, Double(xF), Double(yF), Double(wF), Double(hF))
            }
            .onEnded { _ in
                if let o = scaleOverride, o.id == layerId,
                   let idx = template.layers.firstIndex(where: { $0.id == layerId }) {
                    onMutate("Resize Layer") {
                        var layers = template.layers
                        layers[idx].xFraction = o.xFrac
                        layers[idx].yFraction = o.yFrac
                        layers[idx].widthFraction = o.wFrac
                        layers[idx].heightFraction = o.hFrac
                        template.layers = layers
                    }
                }
                scaleOverride = nil
                scaleStart = nil
            }
    }

    // MARK: - Rotation gesture

    private func rotationGesture(layerId: UUID, layerCenter: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(Self.canvasSpace))
            .onChanged { value in
                if rotationDragState?.id != layerId {
                    let initial = template.layers.first(where: { $0.id == layerId })?.rotation ?? 0
                    rotationDragState = (layerId, initial)
                }
                guard let state = rotationDragState, state.id == layerId else { return }

                // Angle swept around the layer center, from where the drag started to
                // the current cursor position — both in canvas space, so this holds at
                // any existing rotation. The center is rotation-invariant.
                let startVec = CGPoint(x: value.startLocation.x - layerCenter.x, y: value.startLocation.y - layerCenter.y)
                let curVec = CGPoint(x: value.location.x - layerCenter.x, y: value.location.y - layerCenter.y)
                let delta = (atan2(curVec.y, curVec.x) - atan2(startVec.y, startVec.x)) * 180 / .pi
                rotationOverride = (layerId, state.initialDegrees + Double(delta))
            }
            .onEnded { _ in
                if let o = rotationOverride, o.id == layerId,
                   let idx = template.layers.firstIndex(where: { $0.id == layerId }) {
                    onMutate("Rotate Layer") {
                        var layers = template.layers
                        layers[idx].rotation = o.degrees
                        template.layers = layers
                    }
                }
                rotationOverride = nil
                rotationDragState = nil
            }
    }

    // MARK: - Position drag gesture

    private func layerDragGesture(_ layer: ScreenshotLayer, in size: CGSize) -> some Gesture {
        // Canvas coordinate space: the gesture sits below `.rotationEffect`, so local
        // translations would come back rotated and the layer would drift off-axis.
        DragGesture(minimumDistance: 2, coordinateSpace: .named(Self.canvasSpace))
            .onChanged { value in
                if dragStart[layer.id] == nil {
                    dragStart[layer.id] = CGPoint(x: layer.xFraction, y: layer.yFraction)
                }
                guard let start = dragStart[layer.id] else { return }
                // No edge clamping: layers may move past the screenshot bounds in any
                // direction. Content clips at the canvas edge; an outline stroke keeps
                // off-canvas layers visible and grabbable.
                let newX = start.x + value.translation.width / size.width
                let newY = start.y + value.translation.height / size.height
                dragOverride = (id: layer.id, x: Double(newX), y: Double(newY))
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

    // MARK: - Drop handling

    private func handleDrop(providers: [NSItemProvider], at location: CGPoint, canvasSize: CGSize) {
        guard let provider = providers.first else { return }
        let xFrac = Double(max(0, min(0.25, location.x / canvasSize.width - 0.35)))
        let yFrac = Double(max(0, min(0.45, location.y / canvasSize.height - 0.25)))

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
