import AppKit
import SwiftData
import SwiftUI

/// Exports every selected template across every selected locale into one folder.
///
/// Screenshots are produced per locale per device, so exporting them one at a time from
/// the toolbar means N × M save panels. This renders the whole matrix in one pass and
/// lays the files out the way App Store Connect uploads expect: one folder per locale.
struct BatchExportSheet: View {
    let app: AppRecord
    let templates: [ScreenshotTemplate]
    let locales: [String]

    @Environment(\.dismiss) private var dismiss

    @State private var selectedTemplateIds: Set<PersistentIdentifier> = []
    @State private var selectedLocales: Set<String> = []
    @State private var groupByLocale = true
    @State private var isExporting = false
    @State private var progress = 0.0
    @State private var result: ExportOutcome?

    private struct ExportOutcome: Identifiable {
        let id = UUID()
        let written: Int
        let failed: [String]
        let destination: URL

        var message: String {
            var text = "Exported \(written) screenshot\(written == 1 ? "" : "s") to \(destination.lastPathComponent)."
            if !failed.isEmpty {
                text += "\n\nFailed to render: \(failed.joined(separator: ", "))."
            }
            return text
        }
    }

    private var chosenTemplates: [ScreenshotTemplate] {
        templates.filter { selectedTemplateIds.contains($0.persistentModelID) }
    }

    private var chosenLocales: [String] {
        locales.filter { selectedLocales.contains($0) }
    }

    private var fileCount: Int {
        chosenTemplates.count * chosenLocales.count
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 560, height: 480)
        .onAppear {
            selectedTemplateIds = Set(templates.map(\.persistentModelID))
            selectedLocales = Set(locales)
        }
        .alert("Batch Export", isPresented: Binding(
            get: { result != nil },
            set: { if !$0 { result = nil } }
        )) {
            Button("Reveal in Finder") {
                if let destination = result?.destination {
                    NSWorkspace.shared.activateFileViewerSelecting([destination])
                }
                result = nil
                dismiss()
            }
            Button("Done") {
                result = nil
                dismiss()
            }
        } message: {
            Text(result?.message ?? "")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Batch Export")
                .font(.headline)
            Text("Render every selected template in every selected language.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var content: some View {
        HStack(spacing: 0) {
            selectionList(
                title: "Templates",
                isEmpty: templates.isEmpty,
                emptyText: "No templates yet",
                selectAll: { selectedTemplateIds = Set(templates.map(\.persistentModelID)) },
                selectNone: { selectedTemplateIds = [] }
            ) {
                ForEach(templates) { template in
                    Toggle(isOn: Binding(
                        get: { selectedTemplateIds.contains(template.persistentModelID) },
                        set: { isOn in
                            if isOn { selectedTemplateIds.insert(template.persistentModelID) }
                            else { selectedTemplateIds.remove(template.persistentModelID) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(template.name)
                            Text(template.deviceType.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Divider()

            selectionList(
                title: "Languages",
                isEmpty: locales.isEmpty,
                emptyText: "Sync the Listing tab first",
                selectAll: { selectedLocales = Set(locales) },
                selectNone: { selectedLocales = [] }
            ) {
                ForEach(locales, id: \.self) { locale in
                    Toggle(isOn: Binding(
                        get: { selectedLocales.contains(locale) },
                        set: { isOn in
                            if isOn { selectedLocales.insert(locale) } else { selectedLocales.remove(locale) }
                        }
                    )) {
                        Text(LocaleDisplayName.name(for: locale))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func selectionList<Rows: View>(
        title: String,
        isEmpty: Bool,
        emptyText: String,
        selectAll: @escaping () -> Void,
        selectNone: @escaping () -> Void,
        @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button("All", action: selectAll)
                Button("None", action: selectNone)
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            if isEmpty {
                Text(emptyText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        rows()
                    }
                    .toggleStyle(.checkbox)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var footer: some View {
        VStack(spacing: 10) {
            Toggle("Group into a folder per language", isOn: $groupByLocale)
                .toggleStyle(.checkbox)
                .frame(maxWidth: .infinity, alignment: .leading)
                .disabled(isExporting)

            if isExporting {
                ProgressView(value: progress)
            }

            HStack {
                Text(fileCount == 0 ? "Nothing selected" : "\(fileCount) PNG\(fileCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isExporting)
                Button("Choose Folder and Export…") { export() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(fileCount == 0 || isExporting)
            }
        }
        .padding(16)
    }

    private func export() {
        let panel = NSOpenPanel()
        panel.title = "Choose Export Folder"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        guard panel.runModal() == .OK, let root = panel.url else { return }

        let exportTemplates = chosenTemplates
        let exportLocales = chosenLocales

        isExporting = true
        progress = 0

        Task {
            var written = 0
            var failed: [String] = []
            let total = max(1, exportTemplates.count * exportLocales.count)

            for locale in exportLocales {
                let directory = groupByLocale
                    ? root.appendingPathComponent(locale, isDirectory: true)
                    : root
                try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

                for (index, template) in exportTemplates.enumerated() {
                    defer { progress = Double(written + failed.count) / Double(total) }

                    guard let data = renderTemplate(template, locale: locale) else {
                        failed.append("\(template.name) (\(locale))")
                        continue
                    }
                    let url = directory.appendingPathComponent(
                        Self.fileName(
                            template: template,
                            locale: locale,
                            index: index,
                            includeLocale: !groupByLocale
                        )
                    )
                    do {
                        try data.write(to: url)
                        written += 1
                    } catch {
                        failed.append("\(template.name) (\(locale))")
                    }

                    // Rendering is main-actor work; yield so the progress bar can update.
                    await Task.yield()
                }
            }

            isExporting = false
            result = ExportOutcome(written: written, failed: failed, destination: root)
        }
    }

    /// Numeric prefix keeps App Store Connect's screenshot order matching the template order.
    static func fileName(
        template: ScreenshotTemplate,
        locale: String,
        index: Int,
        includeLocale: Bool
    ) -> String {
        let position = String(format: "%02d", index + 1)
        let device = template.deviceType.rawValue
        let parts = includeLocale
            ? [position, locale, device, template.name]
            : [position, device, template.name]
        let joined = parts.joined(separator: "-")
        return sanitized(joined) + ".png"
    }

    static func sanitized(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        return name
            .components(separatedBy: invalid)
            .joined(separator: "-")
            .replacingOccurrences(of: " ", with: "-")
    }
}
