import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AddSearchAdsKeyView: View {
    let onSave: (SearchAdsCredentials) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var clientId    = ""
    @State private var teamId      = ""
    @State private var keyId       = ""
    @State private var orgId       = ""
    @State private var privateKey  = ""
    @State private var errorMessage: String?
    @State private var isSaving    = false

    var canSave: Bool {
        ![clientId, teamId, keyId, privateKey]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains(where: \.isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Search Ads API Credentials") {
                    LabeledContent("Client ID") {
                        TextField("SEARCHADS.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $clientId)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .monospaced))
                    }
                    LabeledContent("Team ID") {
                        TextField("SEARCHADS.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $teamId)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .monospaced))
                    }
                    LabeledContent("Key ID") {
                        TextField("XXXXXXXXXX", text: $keyId)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .monospaced))
                    }
                    LabeledContent("Org ID") {
                        TextField("123456789 (optional)", text: $orgId)
                            .textFieldStyle(.plain)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .monospaced))
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Private Key (.p8)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Import File…") { importP8() }
                                .font(.caption)
                                .buttonStyle(.borderless)
                        }
                        TextEditor(text: $privateKey)
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 120)
                            .overlay(RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.secondary.opacity(0.2), lineWidth: 1))
                    }
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Find these credentials in Apple Search Ads → Settings → API.", systemImage: "info.circle")
                        Label("Org ID is the numeric ID visible in your Search Ads dashboard URL.", systemImage: "number")
                        Label("Credentials stored in macOS Keychain only.", systemImage: "lock.shield.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Connect Apple Search Ads")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") { save() }
                        .disabled(!canSave || isSaving)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 500)
    }

    private func importP8() {
        let panel = NSOpenPanel()
        panel.title = "Select .p8 Search Ads Key"
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let type = UTType(filenameExtension: "p8") { panel.allowedContentTypes = [type] }
        if panel.runModal() == .OK, let url = panel.url {
            do {
                privateKey = try String(contentsOf: url, encoding: .utf8)
                errorMessage = nil
            } catch {
                errorMessage = "Could not read file: \(error.localizedDescription)"
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        let credentials = SearchAdsCredentials(
            clientId:      clientId.trimmingCharacters(in: .whitespacesAndNewlines),
            teamId:        teamId.trimmingCharacters(in: .whitespacesAndNewlines),
            keyId:         keyId.trimmingCharacters(in: .whitespacesAndNewlines),
            privateKeyPEM: privateKey.trimmingCharacters(in: .whitespacesAndNewlines),
            orgId:         orgId.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            try KeychainService.shared.saveSearchAds(credentials)
            onSave(credentials)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}
