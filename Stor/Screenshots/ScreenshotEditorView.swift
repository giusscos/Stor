import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

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
    @State private var renamingTemplateId: PersistentIdentifier?
    @State private var showBatchExport = false
    @State private var templatePendingDeletion: ScreenshotTemplate?

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

            ToolbarItem {
                Menu {
                    Button("Export This Screenshot…") {
                        if let template = selectedTemplate { exportTemplate(template) }
                    }
                    .disabled(selectedTemplate == nil)

                    Button("Export All Templates and Languages…") {
                        showBatchExport = true
                    }
                    .disabled(templates.isEmpty || availableLocales.isEmpty)
                } label: {
                    Label("Export PNG", systemImage: "square.and.arrow.up")
                }
                .disabled(templates.isEmpty)
                .help("Export screenshots as PNG")
            }

            if viewMode == .editor, let template = selectedTemplate {

                ToolbarItem {
                    Button { showUploadSheet = true } label: {
                        Label("Upload to ASC", systemImage: "icloud.and.arrow.up")
                    }
                    .help("Upload screenshot to App Store Connect")
                }

                ToolbarItem {
                    Button(role: .destructive) { templatePendingDeletion = template } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .help("Delete template")
                }
            }
        }
        .sheet(isPresented: $showBatchExport) {
            BatchExportSheet(app: app, templates: templates, locales: availableLocales)
        }
        .confirmationDialog(
            "Delete “\(templatePendingDeletion?.name ?? "")”?",
            isPresented: Binding(
                get: { templatePendingDeletion != nil },
                set: { if !$0 { templatePendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Template", role: .destructive) {
                if let template = templatePendingDeletion { deleteTemplate(template) }
                templatePendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { templatePendingDeletion = nil }
        } message: {
            Text("This removes the template and all of its layers. This cannot be undone.")
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
                                isLast: index == templates.count - 1,
                                isRenaming: renamingTemplateId == template.id,
                                onRenameEnd: { renamingTemplateId = nil }
                            )
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) {
                                selectedTemplate = template
                                renamingTemplateId = template.id
                            }
                            .onTapGesture {
                                selectedTemplate = template
                                renamingTemplateId = nil
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
