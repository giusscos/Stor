import AppKit
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct TemplateEditorView: View {
    @Bindable var template: ScreenshotTemplate
    var previewLocale: String
    var primaryLocale: String
    var availableLocales: [String]
    var onLocaleChange: (String) -> Void

    @Environment(\.undoManager) private var undoManager

    @State private var selectedLayerId: UUID?
    @State private var renamingLayerId: UUID?
    @State private var showAddImage = false
    @State private var canvasZoom: CGFloat = 1.0
    @State private var centerRequest = 0
    /// Layer state previewed while an inspector slider drags; committed on release.
    @State private var livePreviewLayer: ScreenshotLayer?
    @State private var history = TemplateEditHistory()
    @State private var clipboardLayer: ScreenshotLayer?

    private let canvasBaseWidth: CGFloat = 320
    private let zoomStep: CGFloat = 0.25
    private let minZoom: CGFloat = 0.25
    private let maxZoom: CGFloat = 4.0

    var selectedLayer: Binding<ScreenshotLayer>? {
        guard let id = selectedLayerId,
              template.layers.contains(where: { $0.id == id }) else { return nil }
        return layerBinding(for: id)
    }

    /// Records an undo snapshot, then performs the change. Every template mutation in the
    /// editor goes through here so nothing is silently unrecoverable.
    private func mutate(_ actionName: String, coalesce: Bool = false, _ change: () -> Void) {
        history.record(
            on: template,
            undoManager: undoManager,
            actionName: actionName,
            coalesce: coalesce
        )
        change()
    }

    var body: some View {
        HSplitView {
            canvasArea
            propertiesPanel
                .frame(minWidth: 260, idealWidth: 280, maxWidth: 320)
        }
        .fileImporter(
            isPresented: $showAddImage,
            allowedContentTypes: [.image]
        ) { result in
            guard case .success(let url) = result,
                  url.startAccessingSecurityScopedResource() else { return }
            defer { url.stopAccessingSecurityScopedResource() }
            if let data = try? Data(contentsOf: url) {
                addImageLayer(data: data)
            }
        }
        .focusedSceneValue(\.screenshotLayerCommands, layerCommands)
        .onAppear {
            // Defer until the AppKit viewport has a non-zero frame.
            DispatchQueue.main.async {
                centerRequest += 1
            }
        }
        .onChange(of: template.persistentModelID) { _, _ in
            history.endCoalescing()
            DispatchQueue.main.async {
                resetCanvasView()
            }
        }
    }

    // MARK: Canvas

    private var canvasArea: some View {
        ZStack(alignment: .bottomTrailing) {
            InfiniteCanvasView(
                magnification: $canvasZoom,
                minMagnification: minZoom,
                maxMagnification: maxZoom,
                centerRequest: centerRequest
            ) {
                ScreenshotCanvas(
                    template: template,
                    selectedLayerId: $selectedLayerId,
                    previewLocale: previewLocale,
                    liveOverrideLayer: livePreviewLayer,
                    onMutate: { name, change in mutate(name, change) }
                )
                    .frame(
                        width: canvasBaseWidth,
                        height: canvasBaseWidth / template.deviceType.aspectRatio
                    )
                    .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            zoomControls
                .padding(14)
        }
        .background(Color(NSColor.underPageBackgroundColor))
        .focusable()
        .onKeyPress("+") {
            zoomCentered(by: +zoomStep)
            return .handled
        }
        .onKeyPress("=") {
            zoomCentered(by: +zoomStep)
            return .handled
        }
        .onKeyPress("-") {
            zoomCentered(by: -zoomStep)
            return .handled
        }
        .onKeyPress("0") {
            resetCanvasView()
            return .handled
        }
        .onKeyPress(.delete) { deleteSelectedIfPossible() }
        .onKeyPress(.deleteForward) { deleteSelectedIfPossible() }
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { press in
            switch press.key {
            case .upArrow: return nudge(dx: 0, dy: -1, modifiers: press.modifiers)
            case .downArrow: return nudge(dx: 0, dy: 1, modifiers: press.modifiers)
            case .leftArrow: return nudge(dx: -1, dy: 0, modifiers: press.modifiers)
            default: return nudge(dx: 1, dy: 0, modifiers: press.modifiers)
            }
        }
        .onKeyPress(.escape) {
            guard selectedLayerId != nil else { return .ignored }
            selectedLayerId = nil
            return .handled
        }
    }

    private func deleteSelectedIfPossible() -> KeyPress.Result {
        guard selectedLayerId != nil else { return .ignored }
        deleteSelectedLayer()
        return .handled
    }

    /// One step is 0.2% of the canvas; Shift jumps by 2% for coarse positioning.
    private func nudge(dx: Double, dy: Double, modifiers: EventModifiers) -> KeyPress.Result {
        guard selectedLayerId != nil else { return .ignored }
        let step = modifiers.contains(.shift) ? 0.02 : 0.002
        nudgeSelectedLayer(dx: dx * step, dy: dy * step)
        return .handled
    }

    /// Published to the scene so the Layer menu in the menu bar can drive the editor.
    private var layerCommands: ScreenshotLayerCommands {
        ScreenshotLayerCommands(
            hasSelection: selectedLayerId != nil,
            canPaste: clipboardLayer != nil,
            canMoveForward: selectedLayerIndex.map { $0 < template.layers.count - 1 } ?? false,
            canMoveBackward: selectedLayerIndex.map { $0 > 0 } ?? false,
            duplicate: duplicateSelectedLayer,
            copy: copySelectedLayer,
            paste: pasteLayer,
            bringToFront: { moveSelectedLayerToEdge(front: true) },
            bringForward: { moveSelectedLayer(by: 1) },
            sendBackward: { moveSelectedLayer(by: -1) },
            sendToBack: { moveSelectedLayerToEdge(front: false) },
            delete: deleteSelectedLayer
        )
    }

    private var zoomControls: some View {
        HStack(spacing: 6) {
            Button {
                zoomCentered(by: -zoomStep)
            } label: {
                Image(systemName: "minus.magnifyingglass")
            }
            .disabled(canvasZoom <= minZoom)
            .help("Zoom out (centered)")

            Text("\(Int((canvasZoom * 100).rounded()))%")
                .font(.caption.monospacedDigit().weight(.medium))
                .frame(minWidth: 40)
                .foregroundStyle(.secondary)

            Button {
                zoomCentered(by: +zoomStep)
            } label: {
                Image(systemName: "plus.magnifyingglass")
            }
            .disabled(canvasZoom >= maxZoom)
            .help("Zoom in (centered)")

            Divider()
                .frame(height: 14)

            Button("Reset") {
                resetCanvasView()
            }
            .help("Reset zoom and center the screenshot")
        }
        .buttonStyle(.borderless)
        .controlSize(.small)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    /// Zoom controls always re-center the screenshot in the viewport.
    private func zoomCentered(by delta: CGFloat) {
        canvasZoom = min(maxZoom, max(minZoom, canvasZoom + delta))
        centerRequest += 1
    }

    private func resetCanvasView() {
        canvasZoom = 1.0
        centerRequest += 1
    }

    // MARK: Properties

    private var propertiesPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Inspector")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    InspectorSection(title: "Canvas") {
                        VStack(alignment: .leading, spacing: 12) {
                            InspectorLabeledRow("Name") {
                                TextField("", text: $template.name)
                                    .textFieldStyle(.plain)
                                    .multilineTextAlignment(.trailing)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                            }

                            InspectorLabeledRow("Device") {
                                Picker("", selection: Binding(
                                    get: { template.deviceType },
                                    set: { newValue in
                                        mutate("Change Device") { template.deviceType = newValue }
                                    }
                                )) {
                                    ForEach(DeviceType.allCases, id: \.self) { dt in
                                        Text(dt.rawValue).tag(dt)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            }

                            BackgroundInspector(background: Binding(
                                get: { template.background },
                                set: { newValue in
                                    mutate("Change Background", coalesce: true) {
                                        template.background = newValue
                                    }
                                }
                            ))
                        }
                    }

                    InspectorSection(title: "Layers") {
                        VStack(spacing: 8) {
                            if template.layers.isEmpty {
                                Text("No layers yet")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 10)
                            } else {
                                ForEach(template.layers) { layer in
                                    LayerListRow(
                                        layer: layerBinding(for: layer.id),
                                        previewLocale: previewLocale,
                                        isSelected: layer.id == selectedLayerId,
                                        isRenaming: renamingLayerId == layer.id,
                                        onRenameEnd: { renamingLayerId = nil },
                                        onSelect: {
                                            selectedLayerId = layer.id
                                            renamingLayerId = nil
                                        },
                                        onBeginRename: {
                                            selectedLayerId = layer.id
                                            renamingLayerId = layer.id
                                        },
                                        onDelete: { deleteLayer(layer.id) }
                                    )
                                }
                            }

                            if selectedLayerId != nil && template.layers.count > 1 {
                                HStack(spacing: 4) {
                                    Button {
                                        moveSelectedLayerToEdge(front: false)
                                    } label: {
                                        Image(systemName: "arrow.down.to.line")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .disabled(!(selectedLayerIndex.map { $0 > 0 } ?? false))
                                    .help("Send to Back")

                                    Button {
                                        moveSelectedLayer(by: -1)
                                    } label: {
                                        Image(systemName: "arrow.down")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .disabled(!(selectedLayerIndex.map { $0 > 0 } ?? false))
                                    .help("Send Backward")

                                    Button {
                                        moveSelectedLayer(by: 1)
                                    } label: {
                                        Image(systemName: "arrow.up")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .disabled(!(selectedLayerIndex.map { $0 < template.layers.count - 1 } ?? false))
                                    .help("Bring Forward")

                                    Button {
                                        moveSelectedLayerToEdge(front: true)
                                    } label: {
                                        Image(systemName: "arrow.up.to.line")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .disabled(!(selectedLayerIndex.map { $0 < template.layers.count - 1 } ?? false))
                                    .help("Bring to Front")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }

                            VStack(spacing: 6) {
                                HStack(spacing: 8) {
                                    Button { addTextLayer() } label: {
                                        Label("Text", systemImage: "textformat")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button { showAddImage = true } label: {
                                        Label("Image", systemImage: "photo")
                                            .frame(maxWidth: .infinity)
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }

                                Button { addShapeLayer() } label: {
                                    Label("Shape", systemImage: "square.on.circle")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }

                    if let binding = selectedLayer {
                        LayerPropertiesView(
                            layer: binding,
                            previewLocale: previewLocale,
                            primaryLocale: primaryLocale,
                            availableLocales: availableLocales,
                            onLocaleChange: onLocaleChange,
                            livePreview: $livePreviewLayer
                        )
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 20)
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func addTextLayer() {
        mutate("Add Text Layer") {
            var newLayer = ScreenshotLayer(type: .text)
            newLayer.yFraction = Double(template.layers.count) * 0.12
            template.layers.append(newLayer)
            selectedLayerId = newLayer.id
        }
    }

    private func addImageLayer(data: Data) {
        mutate("Add Image Layer") {
            var newLayer = ScreenshotLayer(type: .image)
            newLayer.imageData = data
            newLayer.heightFraction = 0.4
            newLayer.yFraction = 0.3
            ImageLayerStyleStore.shared.applyDefault(to: &newLayer)
            template.layers.append(newLayer)
            selectedLayerId = newLayer.id
        }
    }

    private func addShapeLayer() {
        mutate("Add Shape Layer") {
            var newLayer = ScreenshotLayer(type: .shape)
            newLayer.widthFraction = 0.5
            newLayer.heightFraction = 0.3
            newLayer.xFraction = 0.25
            newLayer.yFraction = max(0, 0.1 + Double(template.layers.count) * 0.04)
            template.layers.append(newLayer)
            selectedLayerId = newLayer.id
        }
    }

    private func layerBinding(for id: UUID) -> Binding<ScreenshotLayer> {
        Binding(
            get: {
                // Re-search by ID each time so a stale index never causes an out-of-bounds crash.
                template.layers.first(where: { $0.id == id }) ?? ScreenshotLayer(type: .text)
            },
            set: { newValue in
                guard let idx = template.layers.firstIndex(where: { $0.id == id }) else { return }
                // Inspector edits arrive in bursts (typing, slider commits), so they
                // coalesce into one undo step per run rather than one per keystroke.
                mutate("Edit Layer", coalesce: true) {
                    template.layers[idx] = newValue
                }
            }
        )
    }

    // MARK: Layer commands

    private var selectedLayerIndex: Int? {
        guard let selectedLayerId else { return nil }
        return template.layers.firstIndex { $0.id == selectedLayerId }
    }

    private func deleteSelectedLayer() {
        guard let id = selectedLayerId else { return }
        deleteLayer(id)
    }

    private func deleteLayer(_ id: UUID) {
        mutate("Delete Layer") {
            if selectedLayerId == id { selectedLayerId = nil }
            if renamingLayerId == id { renamingLayerId = nil }
            template.layers.removeAll { $0.id == id }
        }
    }

    private func duplicateSelectedLayer() {
        guard let index = selectedLayerIndex else { return }
        mutate("Duplicate Layer") {
            var copy = template.layers[index]
            copy.id = UUID()
            // Offset slightly so the duplicate is visibly distinct from the original.
            copy.xFraction = min(0.95, copy.xFraction + 0.02)
            copy.yFraction = min(0.95, copy.yFraction + 0.02)
            template.layers.insert(copy, at: index + 1)
            selectedLayerId = copy.id
        }
    }

    private func copySelectedLayer() {
        guard let index = selectedLayerIndex else { return }
        clipboardLayer = template.layers[index]
    }

    private func pasteLayer() {
        guard var copy = clipboardLayer else { return }
        mutate("Paste Layer") {
            copy.id = UUID()
            copy.xFraction = min(0.95, copy.xFraction + 0.02)
            copy.yFraction = min(0.95, copy.yFraction + 0.02)
            template.layers.append(copy)
            selectedLayerId = copy.id
        }
    }

    /// Layers paint in array order, so "forward" means later in the array.
    private func moveSelectedLayer(by offset: Int) {
        guard let index = selectedLayerIndex else { return }
        let target = index + offset
        guard template.layers.indices.contains(target) else { return }
        mutate(offset > 0 ? "Bring Forward" : "Send Backward") {
            template.layers.swapAt(index, target)
        }
    }

    private func moveSelectedLayerToEdge(front: Bool) {
        guard let index = selectedLayerIndex else { return }
        guard front ? index < template.layers.count - 1 : index > 0 else { return }
        mutate(front ? "Bring to Front" : "Send to Back") {
            let layer = template.layers.remove(at: index)
            template.layers.insert(layer, at: front ? template.layers.count : 0)
        }
    }

    /// Arrow-key nudge. Shift moves in larger steps, matching common design tools.
    private func nudgeSelectedLayer(dx: Double, dy: Double) {
        guard let index = selectedLayerIndex else { return }
        mutate("Move Layer", coalesce: true) {
            var layer = template.layers[index]
            layer.xFraction = min(1, max(-0.5, layer.xFraction + dx))
            layer.yFraction = min(1, max(-0.5, layer.yFraction + dy))
            template.layers[index] = layer
        }
    }
}
