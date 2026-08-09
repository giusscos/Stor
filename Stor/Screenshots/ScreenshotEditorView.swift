import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

// MARK: - Main editor

struct ScreenshotEditorView: View {
    @Bindable var app: AppRecord
    @Environment(\.modelContext) private var modelContext

    @State private var selectedTemplate: ScreenshotTemplate?
    @State private var showNewTemplate = false
    @State private var showUploadSheet = false
    @State private var viewMode: ScreenshotsViewMode = .editor
    @State private var previewLocale: String = ""
    @State private var importMessage: String?
    @State private var importSucceeded = false

    private enum ScreenshotsViewMode: String, CaseIterable {
        case editor
        case gallery

        var label: String {
            switch self {
            case .editor: return "Edit"
            case .gallery: return "Gallery"
            }
        }

        var icon: String {
            switch self {
            case .editor: return "slider.horizontal.3"
            case .gallery: return "rectangle.stack"
            }
        }
    }

    var templates: [ScreenshotTemplate] {
        app.screenshotTemplates.sorted { $0.createdAt < $1.createdAt }
    }

    private var availableLocales: [String] {
        if let snapshot = app.snapshots.sorted(by: { $0.capturedAt > $1.capturedAt }).first {
            let locales = snapshot.localizations.map(\.locale).sorted()
            if !locales.isEmpty { return locales }
        }
        return [app.primaryLocale].filter { !$0.isEmpty }
    }

    private var activeLocale: String {
        if !previewLocale.isEmpty, availableLocales.contains(where: { $0.caseInsensitiveCompare(previewLocale) == .orderedSame }) {
            return previewLocale
        }
        return availableLocales.first ?? app.primaryLocale
    }

    var body: some View {
        HSplitView {
            templateListPanel
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)

            switch viewMode {
            case .editor:
                if let template = selectedTemplate {
                    TemplateEditorView(
                        template: template,
                        previewLocale: activeLocale,
                        primaryLocale: app.primaryLocale,
                        availableLocales: availableLocales,
                        onLocaleChange: { previewLocale = $0 }
                    )
                    .id(template.persistentModelID)
                } else {
                    emptyEditorState
                }
            case .gallery:
                ScreenshotGalleryView(
                    templates: templates,
                    selectedTemplate: $selectedTemplate,
                    previewLocale: activeLocale
                ) {
                    viewMode = .editor
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Picker("View", selection: $viewMode) {
                    ForEach(ScreenshotsViewMode.allCases, id: \.self) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .help("Switch between editor and App Store gallery preview")
            }

            if !availableLocales.isEmpty {
                ToolbarItem {
                    Picker("Locale", selection: Binding(
                        get: { activeLocale },
                        set: { previewLocale = $0 }
                    )) {
                        ForEach(availableLocales, id: \.self) { locale in
                            Text(LocaleDisplayName.name(for: locale)).tag(locale)
                        }
                    }
                    .frame(maxWidth: 200)
                    .help("Preview and edit screenshot text for this locale")
                }
            }

            ToolbarItem {
                Button { showNewTemplate = true } label: {
                    Label("New Template", systemImage: "plus")
                }
                .help("New screenshot template")
            }

            ToolbarItemGroup {
                Button(action: importScreenshotTexts) {
                    Label("Import Texts", systemImage: "square.and.arrow.down")
                }
                .disabled(templates.isEmpty)
                .help("Import translated screenshot texts from Markdown")

                Button(action: exportScreenshotTexts) {
                    Label("Export Texts", systemImage: "doc.badge.arrow.up")
                }
                .disabled(templates.isEmpty)
                .help("Export screenshot texts as Markdown for all locales")
            }

            if viewMode == .editor, let template = selectedTemplate {
                ToolbarItem {
                    Button { exportTemplate(template) } label: {
                        Label("Export PNG", systemImage: "square.and.arrow.up")
                    }
                    .help("Export as PNG")
                }

                ToolbarItem {
                    Button { showUploadSheet = true } label: {
                        Label("Upload to ASC", systemImage: "icloud.and.arrow.up")
                    }
                    .help("Upload screenshot to App Store Connect")
                }

                ToolbarItem {
                    Button(role: .destructive) { deleteTemplate(template) } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .help("Delete template")
                }
            }
        }
        .sheet(isPresented: $showNewTemplate) {
            NewTemplateSheet(app: app) { template in
                selectedTemplate = template
                viewMode = .editor
            }
        }
        .sheet(isPresented: $showUploadSheet) {
            if let tmpl = selectedTemplate {
                UploadScreenshotSheet(app: app, template: tmpl, initialLocale: activeLocale)
            }
        }
        .alert(
            importSucceeded ? "Import Complete" : "Import",
            isPresented: Binding(
                get: { importMessage != nil },
                set: { if !$0 { importMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
        .onAppear {
            syncSelectionToCurrentApp()
        }
        .onChange(of: app.persistentModelID) { _, _ in
            syncSelectionToCurrentApp(force: true)
        }
    }

    /// Keeps canvas/inspector in sync with the template list for the current app.
    private func syncSelectionToCurrentApp(force: Bool = false) {
        if force {
            selectedTemplate = templates.first
            previewLocale = app.primaryLocale
            return
        }
        if let selected = selectedTemplate,
           templates.contains(where: { $0.persistentModelID == selected.persistentModelID }) {
            return
        }
        selectedTemplate = templates.first
        if previewLocale.isEmpty {
            previewLocale = app.primaryLocale
        }
    }

    private var emptyEditorState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.stack")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
                .padding(.top, 48)
            Text("No Template")
                .font(.headline)
            Text("Create a screenshot template to design your App Store screenshots.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("New Template") { showNewTemplate = true }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 32)
    }

    private var templateListPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Templates")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("\(templates.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if templates.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "photo.stack")
                        .font(.title2)
                        .foregroundStyle(.quaternary)
                    Text("No templates yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("Create one to get started")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(templates.enumerated()), id: \.element.id) { index, template in
                            TemplateSidebarRow(
                                template: template,
                                isSelected: selectedTemplate == template,
                                isLast: index == templates.count - 1
                            )
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                selectedTemplate = template
                                viewMode = .editor
                            }
                            .onTapGesture {
                                selectedTemplate = template
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear {
            syncSelectionToCurrentApp()
        }
    }

    private func deleteTemplate(_ template: ScreenshotTemplate) {
        if selectedTemplate == template { selectedTemplate = nil }
        modelContext.delete(template)
    }

    private func exportTemplate(_ template: ScreenshotTemplate) {
        let panel = NSSavePanel()
        panel.title = "Export Screenshot"
        panel.nameFieldStringValue = "\(template.name)-\(activeLocale).png"
        panel.allowedContentTypes = [.png]
        if panel.runModal() == .OK, let url = panel.url {
            if let data = renderTemplate(template, locale: activeLocale) {
                try? data.write(to: url)
            }
        }
    }

    private func exportScreenshotTexts() {
        let markdown = ScreenshotMarkdownImporter.exportMarkdown(
            templates: templates,
            locales: availableLocales,
            primaryLocale: app.primaryLocale
        )
        let name = "\(app.name.isEmpty ? "app" : app.name)-screenshot-texts.md"
            .replacingOccurrences(of: "/", with: "-")
        _ = ScreenshotMarkdownImporter.presentSavePanel(defaultName: name, contents: markdown)
    }

    private func importScreenshotTexts() {
        guard !templates.isEmpty else {
            importSucceeded = false
            importMessage = "Create screenshot templates with text layers first."
            return
        }
        guard let urls = ScreenshotMarkdownImporter.presentOpenPanel(), !urls.isEmpty else { return }

        do {
            var allBlocks: [ScreenshotMarkdownImporter.LocaleBlock] = []
            for url in urls {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                allBlocks.append(contentsOf: try ScreenshotMarkdownImporter.parse(fileURL: url))
            }

            var merged: [String: ScreenshotMarkdownImporter.LocaleBlock] = [:]
            for block in allBlocks {
                merged[block.locale] = block
            }

            let result = ScreenshotMarkdownImporter.apply(
                blocks: Array(merged.values),
                to: templates,
                primaryLocale: app.primaryLocale
            )
            importSucceeded = result.updatedLayerCount > 0

            var lines: [String] = []
            if result.updatedLayerCount > 0 {
                lines.append(
                    "Updated \(result.updatedLayerCount) text layer(s) across \(result.updatedLocales.count) locale(s): \(result.updatedLocales.joined(separator: ", "))."
                )
            }
            if !result.unknownLayerIds.isEmpty {
                lines.append(
                    "Skipped \(result.unknownLayerIds.count) unknown layer id(s). Re-export after editing templates so UUIDs stay in sync."
                )
            }
            if result.updatedLayerCount == 0 && result.unknownLayerIds.isEmpty {
                lines.append("No texts were updated. Check that each ### layer UUID has content underneath.")
            }
            importMessage = lines.joined(separator: "\n")
        } catch {
            importSucceeded = false
            importMessage = error.localizedDescription
        }
    }
}

// MARK: - Render helpers

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

    for layer in template.layers where layer.isVisible {
        let layerSize = layer.resolvedSize(in: size, locale: locale, fontScale: 1)
        let rect = CGRect(
            x: layer.xFraction * size.width,
            y: (1 - layer.yFraction) * size.height - layerSize.height,
            width: layerSize.width,
            height: layerSize.height
        )
        switch layer.type {
        case .text:
            if let bgHex = layer.textBackgroundHex {
                let path = NSBezierPath(
                    roundedRect: rect,
                    xRadius: layer.textCornerRadiusPt,
                    yRadius: layer.textCornerRadiusPt
                )
                NSColor(Color(hex: bgHex)).setFill()
                path.fill()
            }
            let pad = layer.textPaddingPt
            let textRect = rect.insetBy(dx: pad, dy: pad)
            if let attributed = layer.resolvedAttributedString(for: locale, fontSize: layer.fontSizePt) {
                attributed.draw(in: textRect)
            }
        case .image:
            if let data = layer.imageData,
               let img = ImageCache.shared.image(for: data, id: layer.id) {
                let radius = layer.imageCornerRadius
                // Compute the draw rect: fill crops to rect, fit letterboxes centered.
                let drawRect: CGRect
                if layer.imageFills {
                    drawRect = rect
                } else {
                    let iw = img.size.width, ih = img.size.height
                    let scale = max(rect.width / iw, rect.height / ih)
                    let fw = iw * scale, fh = ih * scale
                    drawRect = CGRect(
                        x: rect.midX - fw / 2, y: rect.midY - fh / 2, width: fw, height: fh
                    )
                }
                if radius > 0 {
                    NSGraphicsContext.saveGraphicsState()
                    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).setClip()
                    img.draw(in: drawRect)
                    NSGraphicsContext.restoreGraphicsState()
                } else {
                    img.draw(in: drawRect)
                }
                if let assetName = layer.frameAssetName,
                   let frameImg = NSImage(named: assetName) {
                    frameImg.draw(in: rect)
                }
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
private func renderBackgroundImage(_ background: CanvasBackground, size: CGSize) -> NSImage? {
    let view = CanvasBackgroundFill(background: background)
        .frame(width: size.width, height: size.height)
    let renderer = ImageRenderer(content: view)
    renderer.proposedSize = ProposedViewSize(width: size.width, height: size.height)
    renderer.scale = 1
    return renderer.nsImage
}

// MARK: - Template sidebar row

private struct TemplateSidebarRow: View {
    let template: ScreenshotTemplate
    let isSelected: Bool
    let isLast: Bool

    private var deviceIcon: String {
        switch template.deviceType {
        case .iPadPro13: return "ipad"
        case .macBook: return "laptopcomputer"
        default: return "iphone"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            timelineRail

            VStack(alignment: .leading, spacing: 4) {
                Text(template.name)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Image(systemName: deviceIcon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(template.deviceType.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, 8)

            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
        .padding(.trailing, 4)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            }
        }
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var timelineRail: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.18))
                    .frame(width: 8, height: 8)
                if isSelected {
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 3)
                        .frame(width: 14, height: 14)
                }
            }
            .frame(width: 14, height: 14)
            .padding(.top, 10)

            if !isLast {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 14)
    }
}

// MARK: - Template editor (canvas + properties)

private struct TemplateEditorView: View {
    @Bindable var template: ScreenshotTemplate
    var previewLocale: String
    var primaryLocale: String
    var availableLocales: [String]
    var onLocaleChange: (String) -> Void

    @State private var selectedLayerId: UUID?
    @State private var showAddImage = false
    @State private var canvasZoom: CGFloat = 1.0
    @State private var centerRequest = 0

    private let canvasBaseWidth: CGFloat = 320
    private let zoomStep: CGFloat = 0.25
    private let minZoom: CGFloat = 0.25
    private let maxZoom: CGFloat = 4.0

    var selectedLayer: Binding<ScreenshotLayer>? {
        guard let id = selectedLayerId,
              template.layers.contains(where: { $0.id == id }) else { return nil }
        return Binding(
            get: {
                // Re-search by ID each time so a stale index never causes an out-of-bounds crash.
                self.template.layers.first(where: { $0.id == id }) ?? ScreenshotLayer(type: .text)
            },
            set: { newValue in
                if let idx = self.template.layers.firstIndex(where: { $0.id == id }) {
                    self.template.layers[idx] = newValue
                }
            }
        )
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
        .onAppear {
            // Defer until the AppKit viewport has a non-zero frame.
            DispatchQueue.main.async {
                centerRequest += 1
            }
        }
        .onChange(of: template.persistentModelID) { _, _ in
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
                    previewLocale: previewLocale
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
                            InspectorLabeledRow("Device") {
                                Picker("", selection: $template.deviceType) {
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
                                set: { template.background = $0 }
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
                                        layer: layer,
                                        previewLocale: previewLocale,
                                        isSelected: layer.id == selectedLayerId
                                    ) {
                                        selectedLayerId = layer.id
                                    } onDelete: {
                                        if selectedLayerId == layer.id { selectedLayerId = nil }
                                        template.layers.removeAll { $0.id == layer.id }
                                    }
                                }
                            }

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
                        }
                    }

                    if let binding = selectedLayer {
                        LayerPropertiesView(
                            layer: binding,
                            previewLocale: previewLocale,
                            primaryLocale: primaryLocale,
                            availableLocales: availableLocales,
                            onLocaleChange: onLocaleChange
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
        var newLayer = ScreenshotLayer(type: .text)
        newLayer.yFraction = Double(template.layers.count) * 0.12
        template.layers.append(newLayer)
        selectedLayerId = newLayer.id
    }

    private func addImageLayer(data: Data) {
        var newLayer = ScreenshotLayer(type: .image)
        newLayer.imageData = data
        newLayer.heightFraction = 0.4
        newLayer.yFraction = 0.3
        template.layers.append(newLayer)
        selectedLayerId = newLayer.id
    }
}

// MARK: - Canvas view

private struct ScreenshotCanvas: View {
    let template: ScreenshotTemplate
    @Binding var selectedLayerId: UUID?
    var previewLocale: String? = nil
    var isInteractive: Bool = true
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
                    var layers = template.layers
                    layers[idx].xFraction = o.x
                    layers[idx].yFraction = o.y
                    template.layers = layers
                }
                dragOverride = nil
                dragStart.removeValue(forKey: layer.id)
                selectedLayerId = layer.id
            }
    }

    @ViewBuilder
    private func layerView(_ layer: ScreenshotLayer, in size: CGSize) -> some View {
        let effective: ScreenshotLayer = {
            if let o = dragOverride, o.id == layer.id {
                var c = layer; c.xFraction = o.x; c.yFraction = o.y; return c
            }
            return layer
        }()
        let scale = size.width / 375
        let frame = effective.resolvedFrame(in: size, locale: previewLocale, fontScale: scale)
        let w = frame.width
        let h = frame.height
        let x = frame.minX
        let y = frame.minY

        switch layer.type {
        case .text:
            let pad = layer.textPaddingPt * scale
            let radius = layer.textCornerRadiusPt * scale
            layer.resolvedPreviewText(
                for: previewLocale,
                fontSize: layer.fontSizePt * scale,
                scale: scale
            )
            .multilineTextAlignment(
                layer.textAlignment == .leading ? .leading :
                    layer.textAlignment == .trailing ? .trailing : .center
            )
            .padding(pad)
            .frame(width: w, height: h, alignment: layer.textAlignment.swiftUI)
            .background {
                if let bgHex = layer.textBackgroundHex {
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .fill(Color(hex: bgHex))
                }
            }
            .position(x: x + w / 2, y: y + h / 2)

        case .image:
            if let data = layer.imageData,
               let img = ImageCache.shared.image(for: data, id: effective.id) {
                let cornerRadius = layer.imageCornerRadius * scale
                let contentMode: ContentMode = layer.imageFills ? .fill : .fit
                ZStack {
                    Image(nsImage: img)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                        .frame(width: w, height: h)
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

                    if let assetName = layer.frameAssetName,
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
        var newLayer = ScreenshotLayer(type: .image)
        newLayer.imageData = data
        newLayer.widthFraction = 0.7
        newLayer.heightFraction = 0.5
        newLayer.xFraction = xFrac
        newLayer.yFraction = yFrac
        template.layers.append(newLayer)
        selectedLayerId = newLayer.id
    }
}

// MARK: - App Store gallery preview

private struct ScreenshotGalleryView: View {
    let templates: [ScreenshotTemplate]
    @Binding var selectedTemplate: ScreenshotTemplate?
    var previewLocale: String
    var onOpenEditor: () -> Void

    private struct DeviceGroup: Identifiable {
        let device: DeviceType
        let templates: [ScreenshotTemplate]
        var id: String { device.rawValue }
    }

    private var groups: [DeviceGroup] {
        DeviceType.allCases.compactMap { device in
            let matched = templates.filter { $0.deviceType == device }
            guard !matched.isEmpty else { return nil }
            return DeviceGroup(device: device, templates: matched)
        }
    }

    var body: some View {
        Group {
            if templates.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 36) {
                        header

                        ForEach(groups) { group in
                            deviceSection(group)
                        }
                    }
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.underPageBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("App Store Preview")
                .font(.title2.weight(.semibold))
            Text("Screenshots as they appear on the product page, grouped by device.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
                .padding(.top, 48)
            Text("No Screenshots")
                .font(.headline)
            Text("Create templates to preview them in App Store layout.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 32)
    }

    private func deviceSection(_ group: DeviceGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.device.rawValue)
                    .font(.headline)
                Text("\(group.templates.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            .padding(.horizontal, 28)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 18) {
                    ForEach(group.templates, id: \.persistentModelID) { template in
                        galleryCard(template)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 6)
            }
        }
    }

    private func galleryCard(_ template: ScreenshotTemplate) -> some View {
        let isSelected = selectedTemplate?.persistentModelID == template.persistentModelID
        let cardWidth: CGFloat = template.deviceType == .macBook ? 260 : template.deviceType == .iPadPro13 ? 220 : 180
        let cardHeight = cardWidth / template.deviceType.aspectRatio

        return VStack(spacing: 10) {
            ZStack {
                ScreenshotCanvas(
                    template: template,
                    selectedLayerId: .constant(nil),
                    previewLocale: previewLocale,
                    isInteractive: false
                )
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 18, y: 10)

                if isSelected {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2.5)
                        .padding(-5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onTapGesture(count: 2) {
                selectedTemplate = template
                onOpenEditor()
            }
            .onTapGesture {
                selectedTemplate = template
            }
            .contextMenu {
                Button("Edit Screenshot") {
                    selectedTemplate = template
                    onOpenEditor()
                }
            }

            Text(template.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .lineLimit(1)
                .frame(width: cardWidth)
        }
    }
}

// MARK: - Inspector chrome

private struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @State private var isExpanded: Bool

    init(title: String, startsExpanded: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        self._isExpanded = State(initialValue: startsExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 10 : 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.4)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse \(title)" : "Expand \(title)")

            if isExpanded {
                content
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

private struct InspectorLabeledRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            content
        }
    }
}

// MARK: - Background inspector

private struct BackgroundInspector: View {
    @Binding var background: CanvasBackground

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Background")
                .font(.callout)
                .foregroundStyle(.secondary)

            // Live preview
            CanvasBackgroundFill(background: background)
                .frame(height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                }

            // Kind picker
            HStack(spacing: 4) {
                ForEach(CanvasBackgroundKind.allCases) { kind in
                    Button {
                        background.kind = kind
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 16, height: 16)
                            Text(kind.title)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .foregroundStyle(background.kind == kind ? Color.accentColor : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(background.kind == kind ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04))
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .help(kind.title)
                }
            }

            switch background.kind {
            case .solid:
                InspectorLabeledRow("Color") {
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: background.solidHex) },
                        set: { background.solidHex = $0.toHex() }
                    ))
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

            case .linear:
                gradientStopsEditor
                InspectorLabeledRow("Angle") {
                    Slider(value: $background.linearAngle, in: 0...360, step: 1)
                    Text("\(Int(background.linearAngle))°")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }

            case .radial:
                gradientStopsEditor
                InspectorLabeledRow("Center X") {
                    Slider(value: $background.radialCenterX, in: 0...1)
                    Text("\(Int(background.radialCenterX * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
                InspectorLabeledRow("Center Y") {
                    Slider(value: $background.radialCenterY, in: 0...1)
                    Text("\(Int(background.radialCenterY * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }

            case .mesh:
                MeshGradientEditor(background: $background)
            }
        }
    }

    private var gradientStopsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Colors")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if background.stops.count < 5 {
                    Button {
                        let last = background.sortedStops.last?.location ?? 0
                        background.stops.append(
                            GradientStop(hex: "#FFFFFF", location: min(1, last + 0.25))
                        )
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Add color stop")
                }
            }

            ForEach(Array(background.stops.enumerated()), id: \.element.id) { index, stop in
                HStack(spacing: 8) {
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: background.stops[index].hex) },
                        set: { background.stops[index].hex = $0.toHex() }
                    ))
                    .labelsHidden()
                    .frame(width: 36)

                    Slider(
                        value: Binding(
                            get: { background.stops[index].location },
                            set: { background.stops[index].location = $0 }
                        ),
                        in: 0...1
                    )

                    if background.stops.count > 2 {
                        Button {
                            background.stops.removeAll { $0.id == stop.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red.opacity(0.75))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}

// MARK: - Mesh gradient editor

private struct MeshGradientEditor: View {
    @Binding var background: CanvasBackground
    @State private var selectedIndex: Int = 4

    private var pointCount: Int { background.meshWidth * background.meshHeight }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mesh")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(background.meshWidth)×\(background.meshHeight)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.tertiary)
            }

            InspectorLabeledRow("Columns") {
                Stepper(
                    "",
                    value: Binding(
                        get: { background.meshWidth },
                        set: { newValue in
                            background.resizeMesh(width: newValue, height: background.meshHeight)
                            selectedIndex = min(selectedIndex, pointCount - 1)
                        }
                    ),
                    in: 2...5
                )
                .labelsHidden()
                Text("\(background.meshWidth)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .trailing)
            }

            InspectorLabeledRow("Rows") {
                Stepper(
                    "",
                    value: Binding(
                        get: { background.meshHeight },
                        set: { newValue in
                            background.resizeMesh(width: background.meshWidth, height: newValue)
                            selectedIndex = min(selectedIndex, max(0, background.meshWidth * background.meshHeight - 1))
                        }
                    ),
                    in: 2...5
                )
                .labelsHidden()
                Text("\(background.meshHeight)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .trailing)
            }

            // Interactive point editor
            MeshPointCanvas(background: $background, selectedIndex: $selectedIndex)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                }

            HStack {
                Text("Point \(selectedIndex + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset Positions") {
                    background.resetMeshPositions()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Return all points to a regular grid")
            }

            if selectedIndex >= 0, selectedIndex < background.meshPoints.count {
                InspectorLabeledRow("Color") {
                    ColorPicker("", selection: Binding(
                        get: {
                            let hex = selectedIndex < background.meshColors.count
                                ? background.meshColors[selectedIndex]
                                : "#1A1A2E"
                            return Color(hex: hex)
                        },
                        set: { color in
                            background.normalizeMesh()
                            guard selectedIndex < background.meshColors.count else { return }
                            background.meshColors[selectedIndex] = color.toHex()
                        }
                    ))
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                InspectorLabeledRow("X") {
                    Slider(
                        value: Binding(
                            get: { background.meshPoints[selectedIndex].x },
                            set: { background.meshPoints[selectedIndex].x = min(1, max(0, $0)) }
                        ),
                        in: 0...1
                    )
                    Text("\(Int(background.meshPoints[selectedIndex].x * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }

                InspectorLabeledRow("Y") {
                    Slider(
                        value: Binding(
                            get: { background.meshPoints[selectedIndex].y },
                            set: { background.meshPoints[selectedIndex].y = min(1, max(0, $0)) }
                        ),
                        in: 0...1
                    )
                    Text("\(Int(background.meshPoints[selectedIndex].y * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }

            // Color grid for quick access
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: background.meshWidth),
                spacing: 6
            ) {
                ForEach(0..<pointCount, id: \.self) { index in
                    Button {
                        selectedIndex = index
                    } label: {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(hex: index < background.meshColors.count ? background.meshColors[index] : "#1A1A2E"))
                            .frame(height: 22)
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        selectedIndex == index ? Color.accentColor : Color.primary.opacity(0.12),
                                        lineWidth: selectedIndex == index ? 2 : 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .help("Select point \(index + 1)")
                }
            }
        }
        .onAppear {
            background.normalizeMesh()
            selectedIndex = min(selectedIndex, max(0, pointCount - 1))
        }
        .onChange(of: background.meshWidth) { _, _ in
            selectedIndex = min(selectedIndex, max(0, pointCount - 1))
        }
        .onChange(of: background.meshHeight) { _, _ in
            selectedIndex = min(selectedIndex, max(0, pointCount - 1))
        }
    }
}

private struct MeshPointCanvas: View {
    @Binding var background: CanvasBackground
    @Binding var selectedIndex: Int

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CanvasBackgroundFill(background: background)

                // Light grid guides
                Path { path in
                    let w = background.meshWidth
                    let h = background.meshHeight
                    guard w > 1, h > 1 else { return }
                    for col in 0..<w {
                        for row in 0..<h {
                            let index = row * w + col
                            guard index < background.meshPoints.count else { continue }
                            let point = background.meshPoints[index]
                            let origin = CGPoint(
                                x: point.x * geo.size.width,
                                y: point.y * geo.size.height
                            )
                            if col + 1 < w {
                                let rightIndex = row * w + col + 1
                                if rightIndex < background.meshPoints.count {
                                    let right = background.meshPoints[rightIndex]
                                    path.move(to: origin)
                                    path.addLine(to: CGPoint(
                                        x: right.x * geo.size.width,
                                        y: right.y * geo.size.height
                                    ))
                                }
                            }
                            if row + 1 < h {
                                let belowIndex = (row + 1) * w + col
                                if belowIndex < background.meshPoints.count {
                                    let below = background.meshPoints[belowIndex]
                                    path.move(to: origin)
                                    path.addLine(to: CGPoint(
                                        x: below.x * geo.size.width,
                                        y: below.y * geo.size.height
                                    ))
                                }
                            }
                        }
                    }
                }
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                .allowsHitTesting(false)

                ForEach(Array(background.meshPoints.enumerated()), id: \.element.id) { index, point in
                    let position = CGPoint(
                        x: point.x * geo.size.width,
                        y: point.y * geo.size.height
                    )
                    Circle()
                        .fill(Color(hex: index < background.meshColors.count ? background.meshColors[index] : "#FFFFFF"))
                        .frame(width: selectedIndex == index ? 16 : 12, height: selectedIndex == index ? 16 : 12)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white, lineWidth: selectedIndex == index ? 2.5 : 1.5)
                        }
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .position(position)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("meshCanvas"))
                                .onChanged { value in
                                    selectedIndex = index
                                    background.meshPoints[index] = MeshControlPoint(
                                        id: background.meshPoints[index].id,
                                        x: value.location.x / max(geo.size.width, 1),
                                        y: value.location.y / max(geo.size.height, 1)
                                    )
                                }
                        )
                }
            }
            .coordinateSpace(name: "meshCanvas")
            .contentShape(Rectangle())
        }
    }
}

// MARK: - Layer list row

private struct LayerListRow: View {
    let layer: ScreenshotLayer
    var previewLocale: String
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: layer.type == .text ? "textformat" : "photo")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 16)

            Text(layer.type == .text ? layer.plainPreviewLabel(for: previewLocale) : "Image")
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}

// MARK: - Layer properties

private struct LayerPropertiesView: View {
    @Binding var layer: ScreenshotLayer
    var previewLocale: String
    var primaryLocale: String
    var availableLocales: [String]
    var onLocaleChange: (String) -> Void

    @State private var activeMarkdownFormats: Set<MarkdownInlineFormat> = []
    @State private var pendingMarkdownAction: MarkdownEditorAction?

    private var fontFamilies: [String] { ScreenshotFontFamily.allFamilies }

    private var contentTextBinding: Binding<String> {
        Binding(
            get: { layer.resolvedText(for: previewLocale) ?? "" },
            set: { layer.setResolvedText($0, for: previewLocale, primaryLocale: primaryLocale) }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if layer.type == .text {
                InspectorSection(title: "Text") {
                    VStack(alignment: .leading, spacing: 12) {
                        if !availableLocales.isEmpty {
                            InspectorLabeledRow("Locale") {
                                Picker("", selection: Binding(
                                    get: { previewLocale },
                                    set: { onLocaleChange($0) }
                                )) {
                                    ForEach(availableLocales, id: \.self) { locale in
                                        Text(LocaleDisplayName.name(for: locale)).tag(locale)
                                    }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Content")
                                .font(.callout)
                                .foregroundStyle(.secondary)

                            contentEditor
                        }
                        .onAppear {
                            if !layer.textUsesMarkdown {
                                layer.textUsesMarkdown = true
                            }
                        }

                        InspectorLabeledRow("Font") {
                            Picker("", selection: $layer.fontFamily) {
                                ForEach(fontFamilies, id: \.self) { family in
                                    Text(family)
                                        .font(previewFont(for: family))
                                        .tag(family)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        InspectorLabeledRow("Weight") {
                            Picker("", selection: Binding(
                                get: { layer.fontWeight },
                                set: { layer.fontWeight = $0 }
                            )) {
                                ForEach(LayerFontWeight.allCases) { weight in
                                    Text(weight.title).tag(weight)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        InspectorLabeledRow("Size") {
                            Slider(value: $layer.fontSizePt, in: 12...140, step: 1)
                            Text("\(Int(layer.fontSizePt))")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .trailing)
                        }

                        InspectorLabeledRow("Align") {
                            Picker("", selection: Binding(
                                get: { layer.textAlignment },
                                set: { layer.textAlignment = $0 }
                            )) {
                                ForEach(LayerTextAlignment.allCases) { alignment in
                                    Image(systemName: alignment.symbol)
                                        .tag(alignment)
                                        .help(alignment.title)
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                        }

                        InspectorLabeledRow("Tracking") {
                            Slider(value: $layer.tracking, in: -6...16, step: 0.5)
                            Text(String(format: "%.1f", layer.tracking))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .trailing)
                        }

                        Toggle("Italic", isOn: $layer.isItalic)

                        InspectorLabeledRow("Color") {
                            ColorPicker("", selection: Binding(
                                get: { Color(hex: layer.colorHex) },
                                set: { layer.colorHex = $0.toHex() }
                            ))
                            .labelsHidden()
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }
                    }
                }

                InspectorSection(title: "Background") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("Fill", isOn: Binding(
                            get: { layer.hasTextBackground },
                            set: { layer.hasTextBackground = $0 }
                        ))

                        if layer.hasTextBackground {
                            InspectorLabeledRow("Color") {
                                ColorPicker("", selection: Binding(
                                    get: { Color(hex: layer.textBackgroundHex ?? "#FFFFFF") },
                                    set: { layer.textBackgroundHex = $0.toHex() }
                                ))
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .trailing)
                            }

                            InspectorLabeledRow("Padding") {
                                Slider(value: $layer.textPaddingPt, in: 0...64, step: 1)
                                Text("\(Int(layer.textPaddingPt))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, alignment: .trailing)
                            }

                            InspectorLabeledRow("Radius") {
                                Slider(value: $layer.textCornerRadiusPt, in: 0...120, step: 1)
                                Text("\(Int(layer.textCornerRadiusPt))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 28, alignment: .trailing)
                            }

                            Button("Make Capsule") {
                                layer.textCornerRadiusPt = 120
                                if layer.textPaddingPt < 8 {
                                    layer.textPaddingPt = 12
                                }
                                if !layer.hasTextBackground {
                                    layer.hasTextBackground = true
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }

            if layer.type == .image {
                InspectorSection(title: "Image") {
                    VStack(alignment: .leading, spacing: 10) {
                        InspectorLabeledRow("Frame") {
                            Picker("", selection: Binding(
                                get: { layer.frameAssetName },
                                set: { layer.frameAssetName = $0 }
                            )) {
                                Text("None").tag(nil as String?)
                                ForEach(DeviceFrameOption.orderedGroups, id: \.self) { group in
                                    Section(group) {
                                        ForEach(DeviceFrameOption.options(in: group)) { option in
                                            Text(option.label).tag(option.assetName as String?)
                                        }
                                    }
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        Toggle("Fill frame", isOn: Binding(
                            get: { layer.imageFills },
                            set: { layer.imageFills = $0 }
                        ))
                        .toggleStyle(.checkbox)
                        .controlSize(.small)
                        .help("Fill: image crops to fill the layer box. Uncheck to letterbox (fit).")

                        BufferedValueSlider(
                            title: "Radius",
                            value: Binding(get: { layer.imageCornerRadius }, set: { layer.imageCornerRadius = $0 }),
                            range: 0...120
                        )

                        if let assetName = layer.frameAssetName,
                           let img = NSImage(named: assetName) {
                            Image(nsImage: img)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(maxWidth: .infinity)
                                .frame(height: 80)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                                }
                        }
                    }
                }
            }

            InspectorSection(title: "Layout") {
                VStack(alignment: .leading, spacing: 10) {
                    layoutSlider("X", value: $layer.xFraction, range: -0.5...0.95)
                    layoutSlider("Y", value: $layer.yFraction, range: 0...0.9)

                    if layer.type == .text {
                        layoutFitSlider(
                            "Width",
                            value: $layer.widthFraction,
                            range: 0.05...1.0,
                            fit: $layer.fitWidthToContent
                        )
                        layoutFitSlider(
                            "Height",
                            value: $layer.heightFraction,
                            range: 0.02...1.0,
                            fit: $layer.fitHeightToContent
                        )
                    } else {
                        layoutSlider("Width", value: $layer.widthFraction, range: 0.05...1.5)
                        layoutSlider("Height", value: $layer.heightFraction, range: 0.02...1.5)
                    }

                    Toggle("Visible", isOn: $layer.isVisible)
                }
            }
        }
    }

    @ViewBuilder
    private var contentEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                ForEach(MarkdownInlineFormat.toolbarOrder, id: \.self) { format in
                    markdownFormatButton(
                        systemName: format.systemImage,
                        help: format.help,
                        isActive: activeMarkdownFormats.contains(format)
                    ) {
                        ensureMarkdownEnabled()
                        pendingMarkdownAction = MarkdownEditorAction(.toggle(format))
                    }
                }

                markdownFormatButton(
                    systemName: "xmark.circle",
                    help: "Clear Formatting",
                    isActive: false
                ) {
                    ensureMarkdownEnabled()
                    pendingMarkdownAction = MarkdownEditorAction(.clear)
                }

                Spacer(minLength: 0)
            }

            MarkdownRichTextEditor(
                markdown: contentTextBinding,
                activeFormats: $activeMarkdownFormats,
                pendingAction: $pendingMarkdownAction,
                textColorHex: layer.colorHex,
                alignment: layer.textAlignment.nsTextAlignment,
                minHeight: 88
            )
            .frame(minHeight: 88, maxHeight: 140)
        }
    }

    private func markdownFormatButton(
        systemName: String,
        help: String,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 24, height: 22)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .background {
            if isActive {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.accentColor.opacity(0.22))
            }
        }
        .overlay {
            if isActive {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.65), lineWidth: 1)
            }
        }
        .help(help)
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func ensureMarkdownEnabled() {
        if !layer.textUsesMarkdown {
            layer.textUsesMarkdown = true
        }
    }

    private func layoutSlider(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        BufferedPercentSlider(title: title, value: value, range: range)
    }

    private func layoutFitSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        fit: Binding<Bool>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            InspectorLabeledRow(title) {
                if fit.wrappedValue {
                    Text("Fit")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    Slider(value: value, in: range)
                    Text(String(format: "%.0f%%", value.wrappedValue * 100))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }
            Toggle("Fit to content", isOn: fit)
                .toggleStyle(.checkbox)
                .controlSize(.small)
        }
    }

    private func previewFont(for family: String) -> Font {
        if ScreenshotFontFamily.isSystem(family) {
            return .system(.body, design: ScreenshotFontFamily.design(for: family))
        }
        return .custom(family, size: NSFont.systemFontSize)
    }
}

// MARK: - Buffered sliders (no model writes during drag)

/// Percent-formatted slider (0.0–1.5 → "0%–150%") that only commits to the model on drag end.
/// Eliminates per-frame SwiftUI canvas re-renders while the thumb is moving.
private struct BufferedPercentSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    @State private var local: Double = 0
    @State private var dragging = false

    var body: some View {
        InspectorLabeledRow(title) {
            Slider(value: $local, in: range) { editing in
                dragging = editing
                if !editing { value = local }
            }
            Text(String(format: "%.0f%%", local * 100))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .onAppear { local = value }
        .onChange(of: value) { _, v in if !dragging { local = v } }
    }
}

/// Plain numeric slider (e.g. corner radius 0–120) that only commits to the model on drag end.
private struct BufferedValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1

    @State private var local: Double = 0
    @State private var dragging = false

    var body: some View {
        InspectorLabeledRow(title) {
            Slider(value: $local, in: range, step: step) { editing in
                dragging = editing
                if !editing { value = local }
            }
            Text("\(Int(local))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
        .onAppear { local = value }
        .onChange(of: value) { _, v in if !dragging { local = v } }
    }
}

// MARK: - New template sheet

private struct NewTemplateSheet: View {
    let app: AppRecord
    let onCreated: (ScreenshotTemplate) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var deviceType: DeviceType = .iPhone67

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                }
                Section("Device") {
                    Picker("Device Type", selection: $deviceType) {
                        ForEach(DeviceType.allCases, id: \.self) { dt in
                            VStack(alignment: .leading) {
                                Text(dt.rawValue)
                                Text("\(Int(dt.canvasSize.width)) × \(Int(dt.canvasSize.height))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .tag(dt)
                        }
                    }
                    .pickerStyle(.radioGroup)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Template")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { createTemplate() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .frame(minWidth: 360, minHeight: 320)
        .onAppear {
            if name.isEmpty {
                name = nextScreenshotName(existing: app.screenshotTemplates.map(\.name))
            }
        }
    }

    private func createTemplate() {
        let template = ScreenshotTemplate(name: name.trimmingCharacters(in: .whitespacesAndNewlines), deviceType: deviceType)
        template.app = app
        app.screenshotTemplates.append(template)
        modelContext.insert(template)
        onCreated(template)
        dismiss()
    }
}

/// Picks the next "Screenshot N" name that is not already used.
private func nextScreenshotName(existing names: [String]) -> String {
    let pattern = /^Screenshot\s+(\d+)$/
    var used = Set<Int>()
    for name in names {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if let match = trimmed.wholeMatch(of: pattern),
           let value = Int(match.1) {
            used.insert(value)
        }
    }
    var next = 1
    while used.contains(next) { next += 1 }
    return "Screenshot \(next)"
}

// MARK: - Upload to ASC sheet

private struct UploadScreenshotSheet: View {
    let app: AppRecord
    let template: ScreenshotTemplate
    var initialLocale: String

    @Environment(\.dismiss) private var dismiss
    @State private var selectedLocalizationId = ""
    @State private var isUploading = false
    @State private var uploadError: String?
    @State private var uploadSuccess = false

    private var availableLocalizations: [(id: String, locale: String)] {
        guard let snapshot = app.snapshots.sorted(by: { $0.capturedAt > $1.capturedAt }).first else { return [] }
        return snapshot.localizations
            .compactMap { loc -> (id: String, locale: String)? in
                guard let id = loc.versionLocalizationId else { return nil }
                return (id: id, locale: loc.locale)
            }
            .sorted { $0.locale < $1.locale }
    }

    private var selectedLocale: String {
        availableLocalizations.first { $0.id == selectedLocalizationId }?.locale ?? initialLocale
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Screenshot") {
                    LabeledContent("Device", value: template.deviceType.rawValue)
                    LabeledContent("Display type", value: template.deviceType.ascDisplayType)
                    LabeledContent("Locale text", value: LocaleDisplayName.name(for: selectedLocale))
                }

                Section("Target localization") {
                    if availableLocalizations.isEmpty {
                        Text("Sync your metadata first to load localization IDs.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Locale", selection: $selectedLocalizationId) {
                            ForEach(availableLocalizations, id: \.id) { loc in
                                Text(LocaleDisplayName.name(for: loc.locale))
                                    .tag(loc.id)
                            }
                        }
                    }
                }

                if let error = uploadError {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .font(.callout)
                    }
                }

                if uploadSuccess {
                    Section {
                        Label("Screenshot uploaded successfully.", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Upload to App Store Connect")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isUploading {
                        ProgressView().scaleEffect(0.8)
                    } else {
                        Button("Upload", action: performUpload)
                            .disabled(selectedLocalizationId.isEmpty || uploadSuccess || availableLocalizations.isEmpty)
                    }
                }
            }
        }
        .frame(minWidth: 420, minHeight: 340)
        .onAppear {
            if let match = availableLocalizations.first(where: {
                $0.locale.caseInsensitiveCompare(initialLocale) == .orderedSame
            }) {
                selectedLocalizationId = match.id
            } else {
                selectedLocalizationId = availableLocalizations.first?.id ?? ""
            }
        }
    }

    private func performUpload() {
        guard let credentials = try? KeychainService.shared.load() else {
            uploadError = "No ASC credentials found. Re-connect in Settings."
            return
        }
        guard let pngData = renderTemplate(template, locale: selectedLocale) else {
            uploadError = "Could not render screenshot for \(selectedLocale)."
            return
        }
        isUploading = true
        uploadError = nil
        Task {
            defer { isUploading = false }
            do {
                let client = ASCAPIClient(credentials: credentials)
                let safeName = template.name
                    .components(separatedBy: .whitespacesAndNewlines)
                    .joined(separator: "_")
                try await client.uploadScreenshot(
                    data: pngData,
                    fileName: "\(safeName)-\(selectedLocale).png",
                    versionLocalizationId: selectedLocalizationId,
                    screenshotDisplayType: template.deviceType.ascDisplayType
                )
                uploadSuccess = true
            } catch {
                uploadError = error.localizedDescription
            }
        }
    }
}
