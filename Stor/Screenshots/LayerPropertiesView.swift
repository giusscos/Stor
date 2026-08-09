import AppKit
import SwiftUI

// MARK: - Layer list row

struct LayerListRow: View {
    @Binding var layer: ScreenshotLayer
    var previewLocale: String
    let isSelected: Bool
    var isRenaming: Bool = false
    var onRenameEnd: () -> Void = {}
    let onSelect: () -> Void
    var onBeginRename: () -> Void = {}
    let onDelete: () -> Void

    @FocusState private var nameFocused: Bool
    @State private var draftName: String = ""

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: layer.type == .text ? "textformat" : "photo")
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .frame(width: 16)

            if isRenaming {
                TextField("Image", text: $draftName)
                    .textFieldStyle(.plain)
                    .focused($nameFocused)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onSubmit { commitRename() }
                    .onChange(of: nameFocused) { _, focused in
                        if !focused { commitRename() }
                    }
            } else {
                Text(layer.listLabel(previewLocale: previewLocale))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

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
        .onTapGesture(count: 2) {
            guard layer.type == .image else { return }
            onBeginRename()
        }
        .onTapGesture {
            if !isRenaming { onSelect() }
        }
        .onChange(of: isRenaming) { _, renaming in
            if renaming {
                draftName = layer.name ?? ""
                nameFocused = true
            }
        }
    }

    private func commitRename() {
        guard isRenaming else { return }
        let trimmed = draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        layer.name = trimmed.isEmpty ? nil : trimmed
        onRenameEnd()
    }
}

// MARK: - Layer properties

struct LayerPropertiesView: View {
    @Binding var layer: ScreenshotLayer
    var previewLocale: String
    var primaryLocale: String
    var availableLocales: [String]
    var onLocaleChange: (String) -> Void
    @Binding var livePreview: ScreenshotLayer?

    @ObservedObject private var styleStore = ImageLayerStyleStore.shared
    @State private var activeMarkdownFormats: Set<MarkdownInlineFormat> = []
    @State private var pendingMarkdownAction: MarkdownEditorAction?
    @State private var showSavePresetAlert = false
    @State private var newPresetName = ""
    @State private var renamingPresetId: UUID?
    @State private var renamePresetDraft = ""

    /// Live-preview hook for a buffered slider: renders the in-flight value on the
    /// canvas by overriding one property on top of the committed layer.
    private func liveUpdate(_ keyPath: WritableKeyPath<ScreenshotLayer, Double>) -> (Double) -> Void {
        { newValue in
            var preview = layer
            preview[keyPath: keyPath] = newValue
            livePreview = preview
        }
    }

    private func endLivePreview() {
        livePreview = nil
    }

    private var fontFamilies: [String] { ScreenshotFontFamily.allFamilies }

    private var contentTextBinding: Binding<String> {
        Binding(
            get: { layer.resolvedText(for: previewLocale) ?? "" },
            set: { layer.setResolvedText($0, for: previewLocale, primaryLocale: primaryLocale) }
        )
    }

    /// Picker selection is the option id (device + color); orientation is preserved
    /// across option changes when the new option also has a landscape variant.
    private var frameOptionBinding: Binding<String?> {
        Binding(
            get: {
                guard let asset = layer.frameAssetName else { return nil }
                return DeviceFrameOption.option(forAsset: asset)?.id ?? asset
            },
            set: { newId in
                guard let newId, let option = DeviceFrameOption.all.first(where: { $0.id == newId }) else {
                    layer.frameAssetName = nil
                    return
                }
                let wasLandscape = layer.frameAssetName.flatMap {
                    DeviceFrameOption.option(forAsset: $0)?.landscapeAsset == $0
                } ?? false
                layer.frameAssetName = (wasLandscape ? option.landscapeAsset : nil) ?? option.portraitAsset
            }
        )
    }

    private var frameLandscapeBinding: Binding<Bool> {
        Binding(
            get: {
                guard let asset = layer.frameAssetName,
                      let option = DeviceFrameOption.option(forAsset: asset) else { return false }
                return option.landscapeAsset == asset
            },
            set: { landscape in
                guard let asset = layer.frameAssetName,
                      let option = DeviceFrameOption.option(forAsset: asset) else { return }
                layer.frameAssetName = landscape
                    ? (option.landscapeAsset ?? option.portraitAsset)
                    : option.portraitAsset
            }
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

                        textSlider("Size", value: $layer.fontSizePt, range: 12...140, live: \.fontSizePt)

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

                        textSlider(
                            "Tracking",
                            value: $layer.tracking,
                            range: -6...16,
                            step: 0.5,
                            format: { String(format: "%.1f", $0) },
                            live: \.tracking
                        )

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

                            textSlider(
                                "Padding",
                                value: $layer.textPaddingPt,
                                range: 0...64,
                                live: \.textPaddingPt
                            )

                            textSlider(
                                "Radius",
                                value: $layer.textCornerRadiusPt,
                                range: 0...120,
                                live: \.textCornerRadiusPt
                            )

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
                            Picker("", selection: frameOptionBinding) {
                                Text("None").tag(nil as String?)
                                ForEach(DeviceFrameOption.orderedGroups, id: \.self) { group in
                                    Section(group) {
                                        ForEach(DeviceFrameOption.options(in: group)) { option in
                                            Text(option.label).tag(option.id as String?)
                                        }
                                    }
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        }

                        if let assetName = layer.frameAssetName,
                           DeviceFrameOption.option(forAsset: assetName)?.landscapeAsset != nil {
                            Toggle("Landscape", isOn: frameLandscapeBinding)
                                .toggleStyle(.checkbox)
                                .controlSize(.small)
                                .help("Use the landscape version of this device frame")
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
                            range: 0...120,
                            onLiveChange: liveUpdate(\.imageCornerRadius),
                            onEditEnd: endLivePreview
                        )

                        Divider()

                        Text("Content")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        BufferedPercentSlider(
                            title: "Scale",
                            value: Binding(get: { layer.contentScale }, set: { layer.contentScale = $0 }),
                            range: 0.25...3,
                            onLiveChange: liveUpdate(\.contentScale),
                            onEditEnd: endLivePreview
                        )
                        BufferedPercentSlider(
                            title: "Offset X",
                            value: Binding(get: { layer.contentOffsetX }, set: { layer.contentOffsetX = $0 }),
                            range: -0.5...0.5,
                            onLiveChange: liveUpdate(\.contentOffsetX),
                            onEditEnd: endLivePreview
                        )
                        BufferedPercentSlider(
                            title: "Offset Y",
                            value: Binding(get: { layer.contentOffsetY }, set: { layer.contentOffsetY = $0 }),
                            range: -0.5...0.5,
                            onLiveChange: liveUpdate(\.contentOffsetY),
                            onEditEnd: endLivePreview
                        )

                        Button("Reset Position") {
                            layer.contentScale = 1
                            layer.contentOffsetX = 0
                            layer.contentOffsetY = 0
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(layer.contentScale == 1 && layer.contentOffsetX == 0 && layer.contentOffsetY == 0)
                        .help("Undo scale and offset — back to automatic fit")

                        Divider()

                        Text("Style")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 8) {
                            Button("Copy") {
                                styleStore.copied = ImageLayerStyle(from: layer)
                            }
                            .help("Copy frame, fill, radius, and scale/offset from this image")

                            Button("Paste") {
                                if let style = styleStore.copied {
                                    var updated = layer
                                    style.apply(to: &updated)
                                    layer = updated
                                }
                            }
                            .disabled(styleStore.copied == nil)
                            .help("Apply the copied image options to this layer")

                            Button("Reset") {
                                if let style = styleStore.savedDefault {
                                    var updated = layer
                                    style.apply(to: &updated)
                                    layer = updated
                                }
                            }
                            .disabled(styleStore.savedDefault?.matches(layer) != false)
                            .help("Restore frame, fill, radius, and scale/offset to the favorite preset")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button("Save Preset") {
                            newPresetName = styleStore.nextPresetName()
                            showSavePresetAlert = true
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("Save this image’s frame, fill, radius, and scale/offset as a named preset")

                        if !styleStore.presets.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(styleStore.presets) { preset in
                                    stylePresetRow(preset)
                                }
                            }
                        }

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
                .alert("Save Preset", isPresented: $showSavePresetAlert) {
                    TextField("Name", text: $newPresetName)
                    Button("Save") {
                        styleStore.addPreset(
                            name: newPresetName,
                            style: ImageLayerStyle(from: layer)
                        )
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Presets store frame, fill, radius, and content scale/offset.")
                }
            }

            InspectorSection(title: "Layout") {
                VStack(alignment: .leading, spacing: 10) {
                    layoutSlider("X", value: $layer.xFraction, range: -0.5...0.95, live: \.xFraction)
                    layoutSlider("Y", value: $layer.yFraction, range: 0...0.9, live: \.yFraction)

                    if layer.type == .text {
                        layoutFitSlider(
                            "Width",
                            value: $layer.widthFraction,
                            range: 0.05...1.0,
                            fit: $layer.fitWidthToContent,
                            live: \.widthFraction
                        )
                        layoutFitSlider(
                            "Height",
                            value: $layer.heightFraction,
                            range: 0.02...1.0,
                            fit: $layer.fitHeightToContent,
                            live: \.heightFraction
                        )
                    } else {
                        layoutSlider("Width", value: $layer.widthFraction, range: 0.05...1.5, live: \.widthFraction)
                        layoutSlider("Height", value: $layer.heightFraction, range: 0.02...1.5, live: \.heightFraction)
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

    private func stylePresetRow(_ preset: ImageLayerStylePreset) -> some View {
        let isFavorite = styleStore.favoritePresetId == preset.id
        let isActive = preset.style.matches(layer)
        let isRenaming = renamingPresetId == preset.id

        return HStack(spacing: 6) {
            if isRenaming {
                TextField("Name", text: $renamePresetDraft)
                    .textFieldStyle(.plain)
                    .font(.caption)
                    .onSubmit { commitPresetRename() }
                    .onExitCommand { renamingPresetId = nil }
            } else {
                Button {
                    var updated = layer
                    preset.style.apply(to: &updated)
                    layer = updated
                } label: {
                    Text(preset.name)
                        .font(.caption)
                        .foregroundStyle(isActive ? Color.accentColor : .primary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Apply this preset")
                .contextMenu {
                    Button("Rename") {
                        renamePresetDraft = preset.name
                        renamingPresetId = preset.id
                    }
                    Button(isFavorite ? "Remove Favorite" : "Make Favorite") {
                        styleStore.toggleFavorite(id: preset.id)
                    }
                    Divider()
                    Button("Delete", role: .destructive) {
                        styleStore.removePreset(id: preset.id)
                    }
                }
            }

            Button {
                styleStore.toggleFavorite(id: preset.id)
            } label: {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .font(.caption)
                    .foregroundStyle(isFavorite ? Color.accentColor : .secondary)
            }
            .buttonStyle(.borderless)
            .help(isFavorite
                  ? "Favorite — used for Reset and new images. Click to clear."
                  : "Mark as favorite for Reset and new images")

            Button {
                styleStore.removePreset(id: preset.id)
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Delete preset")
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isActive ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.04))
        )
    }

    private func commitPresetRename() {
        guard let id = renamingPresetId else { return }
        styleStore.renamePreset(id: id, name: renamePresetDraft)
        renamingPresetId = nil
    }

    /// Text sliders go through the same buffering as the layout ones: a raw `Slider`
    /// bound to the model re-encodes the whole layer array on every tick of the drag.
    private func textSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double = 1,
        format: ((Double) -> String)? = nil,
        live keyPath: WritableKeyPath<ScreenshotLayer, Double>
    ) -> some View {
        BufferedValueSlider(
            title: title,
            value: value,
            range: range,
            step: step,
            format: format,
            onLiveChange: liveUpdate(keyPath),
            onEditEnd: endLivePreview
        )
    }

    private func layoutSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        live keyPath: WritableKeyPath<ScreenshotLayer, Double>
    ) -> some View {
        BufferedPercentSlider(
            title: title,
            value: value,
            range: range,
            onLiveChange: liveUpdate(keyPath),
            onEditEnd: endLivePreview
        )
    }

    private func layoutFitSlider(
        _ title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        fit: Binding<Bool>,
        live keyPath: WritableKeyPath<ScreenshotLayer, Double>
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            InspectorLabeledRow(title) {
                if fit.wrappedValue {
                    Text("Fit")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                } else {
                    BufferedFitSlider(
                        value: value,
                        range: range,
                        onLiveChange: liveUpdate(keyPath),
                        onEditEnd: endLivePreview
                    )
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
