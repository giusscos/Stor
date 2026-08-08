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
    @State private var uploadPNGData: Data?

    var templates: [ScreenshotTemplate] {
        app.screenshotTemplates.sorted { $0.createdAt < $1.createdAt }
    }

    var body: some View {
        HSplitView {
            templateListPanel
                .frame(minWidth: 180, idealWidth: 200, maxWidth: 240)

            if let template = selectedTemplate {
                TemplateEditorView(template: template)
            } else {
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
        }
        .toolbar {
            ToolbarItem {
                Button { showNewTemplate = true } label: {
                    Label("New Template", systemImage: "plus")
                }
                .help("New screenshot template")
            }

            if let template = selectedTemplate {
                ToolbarItem {
                    Button { exportTemplate(template) } label: {
                        Label("Export PNG", systemImage: "square.and.arrow.up")
                    }
                    .help("Export as PNG")
                }

                ToolbarItem {
                    Button {
                        if let data = renderTemplate(template) {
                            uploadPNGData = data
                            showUploadSheet = true
                        }
                    } label: {
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
            }
        }
        .sheet(isPresented: $showUploadSheet) {
            if let tmpl = selectedTemplate, let data = uploadPNGData {
                UploadScreenshotSheet(app: app, template: tmpl, pngData: data)
            }
        }
    }

    private var templateListPanel: some View {
        VStack(spacing: 0) {
            Text("Templates")
                .font(.headline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

            Divider()

            List(templates, selection: $selectedTemplate) { template in
                VStack(alignment: .leading, spacing: 2) {
                    Text(template.name).fontWeight(.medium)
                    Text(template.deviceType.rawValue).font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .tag(template)
            }
            .listStyle(.sidebar)
        }
    }

    private func deleteTemplate(_ template: ScreenshotTemplate) {
        if selectedTemplate == template { selectedTemplate = nil }
        modelContext.delete(template)
    }

    private func exportTemplate(_ template: ScreenshotTemplate) {
        let panel = NSSavePanel()
        panel.title = "Export Screenshot"
        panel.nameFieldStringValue = "\(template.name).png"
        panel.allowedContentTypes = [.png]
        if panel.runModal() == .OK, let url = panel.url {
            if let data = renderTemplate(template) {
                try? data.write(to: url)
            }
        }
    }

    private func renderTemplate(_ template: ScreenshotTemplate) -> Data? {
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

        let bgColor = NSColor(Color(hex: template.backgroundColorHex))
        bgColor.setFill()
        NSRect(x: 0, y: 0, width: size.width, height: size.height).fill()

        for layer in template.layers where layer.isVisible {
            let rect = CGRect(
                x: layer.xFraction * size.width,
                y: (1 - layer.yFraction - layer.heightFraction) * size.height,
                width: layer.widthFraction * size.width,
                height: layer.heightFraction * size.height
            )
            switch layer.type {
            case .text:
                if let text = layer.text {
                    let attrs: [NSAttributedString.Key: Any] = [
                        .font: NSFont.systemFont(ofSize: layer.fontSizePt, weight: layer.isBold ? .bold : .regular),
                        .foregroundColor: NSColor(Color(hex: layer.colorHex))
                    ]
                    NSString(string: text).draw(in: rect, withAttributes: attrs)
                }
            case .image:
                if let data = layer.imageData, let img = NSImage(data: data) {
                    img.draw(in: rect)
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
}

// MARK: - Template editor (canvas + properties)

private struct TemplateEditorView: View {
    @Bindable var template: ScreenshotTemplate
    @State private var selectedLayerId: UUID?
    @State private var showAddImage = false

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
                .frame(minWidth: 240, idealWidth: 260, maxWidth: 300)
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
    }

    // MARK: Canvas

    private var canvasArea: some View {
        ScrollView([.horizontal, .vertical]) {
            ScreenshotCanvas(template: template, selectedLayerId: $selectedLayerId)
                .frame(width: 280, height: 280 / template.deviceType.aspectRatio)
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.underPageBackgroundColor))
    }

    // MARK: Properties

    private var propertiesPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Properties")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Canvas settings
                    GroupBox("Canvas") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Device", selection: $template.deviceType) {
                                ForEach(DeviceType.allCases, id: \.self) { dt in
                                    Text(dt.rawValue).tag(dt)
                                }
                            }

                            ColorPicker("Background", selection: Binding(
                                get: { Color(hex: template.backgroundColorHex) },
                                set: { template.backgroundColorHex = $0.toHex() }
                            ))
                        }
                        .frame(maxWidth: .infinity)
                    }

                    // Layer list
                    GroupBox("Layers") {
                        VStack(spacing: 6) {
                            if template.layers.isEmpty {
                                Text("No layers yet")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            } else {
                                ForEach(template.layers) { layer in
                                    LayerListRow(
                                        layer: layer,
                                        isSelected: layer.id == selectedLayerId
                                    ) {
                                        selectedLayerId = layer.id
                                    } onDelete: {
                                        // Clear selection first so the stale Binding is never
                                        // accessed during the re-render triggered by the mutation.
                                        if selectedLayerId == layer.id { selectedLayerId = nil }
                                        template.layers.removeAll { $0.id == layer.id }
                                    }
                                }
                            }

                            HStack(spacing: 8) {
                                Button { addTextLayer() } label: {
                                    Label("Text", systemImage: "textformat")
                                }
                                .buttonStyle(.bordered).controlSize(.small)

                                Button { showAddImage = true } label: {
                                    Label("Image", systemImage: "photo")
                                }
                                .buttonStyle(.bordered).controlSize(.small)
                            }
                            .padding(.top, 4)
                        }
                    }

                    // Selected layer properties
                    if let binding = selectedLayer {
                        GroupBox("Layer Properties") {
                            LayerPropertiesView(layer: binding)
                        }
                    }
                }
                .padding(12)
            }
        }
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
    @State private var dragStart: [UUID: CGPoint] = [:]

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                Color(hex: template.backgroundColorHex)

                ForEach(template.layers.filter { $0.isVisible }) { layer in
                    layerView(layer, in: geo.size)
                        .overlay {
                            if layer.id == selectedLayerId {
                                RoundedRectangle(cornerRadius: 2)
                                    .stroke(Color.accentColor, lineWidth: 1.5)
                            }
                        }
                        .onTapGesture { selectedLayerId = layer.id }
                        .gesture(
                            DragGesture(minimumDistance: 2)
                                .onChanged { value in
                                    // Capture initial fraction once at drag start
                                    if dragStart[layer.id] == nil {
                                        dragStart[layer.id] = CGPoint(x: layer.xFraction, y: layer.yFraction)
                                    }
                                    guard let start = dragStart[layer.id],
                                          let idx = template.layers.firstIndex(where: { $0.id == layer.id })
                                    else { return }
                                    // translation is always relative to drag origin, so arithmetic is stable
                                    let newX = start.x + value.translation.width / geo.size.width
                                    let newY = start.y + value.translation.height / geo.size.height
                                    // Single read-modify-write to avoid a double JSON encode/decode.
                                    var layers = template.layers
                                    layers[idx].xFraction = max(0, min(0.95, newX))
                                    layers[idx].yFraction = max(0, min(0.95, newY))
                                    template.layers = layers
                                }
                                .onEnded { _ in
                                    dragStart.removeValue(forKey: layer.id)
                                    selectedLayerId = layer.id
                                }
                        )
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func layerView(_ layer: ScreenshotLayer, in size: CGSize) -> some View {
        let x = layer.xFraction * size.width
        let y = layer.yFraction * size.height
        let w = layer.widthFraction * size.width
        let h = layer.heightFraction * size.height

        switch layer.type {
        case .text:
            Text(layer.text ?? "")
                .font(.system(size: layer.fontSizePt * size.width / 375,
                              weight: layer.isBold ? .bold : .regular))
                .foregroundStyle(Color(hex: layer.colorHex))
                .frame(width: w, height: h, alignment: .center)
                .position(x: x + w / 2, y: y + h / 2)

        case .image:
            if let data = layer.imageData, let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: w, height: h)
                    .position(x: x + w / 2, y: y + h / 2)
            }
        }
    }
}

// MARK: - Layer list row

private struct LayerListRow: View {
    let layer: ScreenshotLayer
    let isSelected: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: layer.type == .text ? "textformat" : "photo")
                .foregroundStyle(.secondary)
                .frame(width: 16)

            Text(layer.type == .text ? (layer.text ?? "Text") : "Image")
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onDelete) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(isSelected ? Color.accentColor.opacity(0.1) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
    }
}

// MARK: - Layer properties

private struct LayerPropertiesView: View {
    @Binding var layer: ScreenshotLayer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if layer.type == .text {
                LabeledContent("Text") {
                    TextField("Text", text: Binding(
                        get: { layer.text ?? "" },
                        set: { layer.text = $0 }
                    ))
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                }

                LabeledContent("Font size") {
                    Slider(value: $layer.fontSizePt, in: 12...120, step: 2)
                    Text("\(Int(layer.fontSizePt))pt")
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 36)
                }

                Toggle("Bold", isOn: $layer.isBold)

                ColorPicker("Color", selection: Binding(
                    get: { Color(hex: layer.colorHex) },
                    set: { layer.colorHex = $0.toHex() }
                ))
            }

            Divider()

            Text("Position & Size")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            LabeledContent("X") {
                Slider(value: $layer.xFraction, in: 0...0.9)
                Text(String(format: "%.0f%%", layer.xFraction * 100))
                    .font(.caption).monospacedDigit().frame(width: 36)
            }

            LabeledContent("Y") {
                Slider(value: $layer.yFraction, in: 0...0.9)
                Text(String(format: "%.0f%%", layer.yFraction * 100))
                    .font(.caption).monospacedDigit().frame(width: 36)
            }

            LabeledContent("Width") {
                Slider(value: $layer.widthFraction, in: 0.05...1.0)
                Text(String(format: "%.0f%%", layer.widthFraction * 100))
                    .font(.caption).monospacedDigit().frame(width: 36)
            }

            LabeledContent("Height") {
                Slider(value: $layer.heightFraction, in: 0.02...1.0)
                Text(String(format: "%.0f%%", layer.heightFraction * 100))
                    .font(.caption).monospacedDigit().frame(width: 36)
            }

            Toggle("Visible", isOn: $layer.isVisible)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - New template sheet

private struct NewTemplateSheet: View {
    let app: AppRecord
    let onCreated: (ScreenshotTemplate) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = "Screenshot 1"
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

// MARK: - Upload to ASC sheet

private struct UploadScreenshotSheet: View {
    let app: AppRecord
    let template: ScreenshotTemplate
    let pngData: Data

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

    var body: some View {
        NavigationStack {
            Form {
                Section("Screenshot") {
                    LabeledContent("Device", value: template.deviceType.rawValue)
                    LabeledContent("Display type", value: template.deviceType.ascDisplayType)
                    LabeledContent("File size", value: ByteCountFormatter.string(
                        fromByteCount: Int64(pngData.count), countStyle: .file))
                }

                Section("Target localization") {
                    if availableLocalizations.isEmpty {
                        Text("Sync your metadata first to load localization IDs.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Locale", selection: $selectedLocalizationId) {
                            ForEach(availableLocalizations, id: \.id) { loc in
                                Text(Locale.current.localizedString(forLanguageCode: loc.locale) ?? loc.locale)
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
            selectedLocalizationId = availableLocalizations.first?.id ?? ""
        }
    }

    private func performUpload() {
        guard let credentials = try? KeychainService.shared.load() else {
            uploadError = "No ASC credentials found. Re-connect in Settings."
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
                    fileName: "\(safeName).png",
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
