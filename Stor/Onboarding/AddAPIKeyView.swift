import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AddAPIKeyView: View {
    let onSave: (ASCCredentials) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var issuerId = ""
    @State private var keyId = ""
    @State private var privateKeyPEM = ""
    @State private var errorMessage: String?
    @State private var isSaving = false

    var canSave: Bool {
        !issuerId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !keyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("API Key Credentials") {
                    LabeledContent("Issuer ID") {
                        TextField("xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx", text: $issuerId)
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
                }

                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Private Key (.p8)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Import File…") { importP8File() }
                                .font(.caption)
                                .buttonStyle(.borderless)
                        }

                        TextEditor(text: $privateKeyPEM)
                            .font(.system(.caption, design: .monospaced))
                            .frame(height: 130)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )

                        if privateKeyPEM.isEmpty {
                            Text("Paste the .p8 contents or click Import File.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
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
                        Label("Credentials stored in the macOS Keychain — never leave your Mac.", systemImage: "lock.shield.fill")
                        Label("All requests go directly from your Mac to Apple's servers.", systemImage: "arrow.left.arrow.right")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Connect App Store Connect")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") { saveCredentials() }
                        .disabled(!canSave || isSaving)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 480)
    }

    private func importP8File() {
        let panel = NSOpenPanel()
        panel.title = "Select .p8 API Key File"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let type = UTType(filenameExtension: "p8") {
            panel.allowedContentTypes = [type]
        }
        if panel.runModal() == .OK, let url = panel.url {
            do {
                privateKeyPEM = try String(contentsOf: url, encoding: .utf8)
                errorMessage = nil
            } catch {
                errorMessage = "Could not read file: \(error.localizedDescription)"
            }
        }
    }

    private func saveCredentials() {
        isSaving = true
        errorMessage = nil
        let credentials = ASCCredentials(
            issuerId: issuerId.trimmingCharacters(in: .whitespacesAndNewlines),
            keyId: keyId.trimmingCharacters(in: .whitespacesAndNewlines),
            privateKeyPEM: privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            try KeychainService.shared.save(credentials)
            onSave(credentials)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}
