import AppKit
import SwiftData
import SwiftUI

// MARK: - New template sheet

struct NewTemplateSheet: View {
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
func nextScreenshotName(existing names: [String]) -> String {
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

struct UploadScreenshotSheet: View {
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
