import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AddSearchAdsKeyView: View {
    let onSave: (SearchAdsCredentials) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var clientId = ""
    @State private var teamId = ""
    @State private var keyId = ""
    @State private var orgId = ""
    @State private var privateKey = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isDropTargeted = false
    @State private var showHelp = false

    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case clientId, teamId, keyId, orgId, privateKey
    }

    var canSave: Bool {
        ![clientId, teamId, keyId, privateKey]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .contains(where: \.isEmpty)
    }

    private var privateKeyFilled: Bool {
        !privateKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header
                    credentialsCard
                    privateKeyCard

                    if let errorMessage {
                        errorBanner(errorMessage)
                    }

                    helpSection
                }
                .padding(24)
            }
            .navigationTitle("Connect Apple Search Ads")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Text("Connect")
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave || isSaving)
                }
            }
        }
        .frame(minWidth: 540, idealWidth: 560, minHeight: 560, idealHeight: 620)
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.blue.opacity(0.75)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("Unlock keyword popularity")
                    .font(.title3.weight(.semibold))
                Text("Paste your Apple Search Ads API credentials to fetch popularity scores (0–100) for tracked keywords.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var credentialsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("API Credentials")

            VStack(spacing: 12) {
                field(
                    title: "Client ID",
                    placeholder: "SEARCHADS.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
                    text: $clientId,
                    field: .clientId,
                    required: true
                )
                field(
                    title: "Team ID",
                    placeholder: "SEARCHADS.xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
                    text: $teamId,
                    field: .teamId,
                    required: true
                )
                HStack(alignment: .top, spacing: 12) {
                    field(
                        title: "Key ID",
                        placeholder: "XXXXXXXXXX",
                        text: $keyId,
                        field: .keyId,
                        required: true
                    )
                    field(
                        title: "Org ID",
                        placeholder: "Optional — from dashboard URL",
                        text: $orgId,
                        field: .orgId,
                        required: false
                    )
                }
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var privateKeyCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionLabel("Private Key (.p8)")
                Spacer()
                if privateKeyFilled {
                    Button("Clear") {
                        privateKey = ""
                        focusedField = .privateKey
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
                Button {
                    importP8()
                } label: {
                    Label("Import File…", systemImage: "doc.badge.plus")
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isDropTargeted ? Color.blue.opacity(0.08) : Color.primary.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(
                                isDropTargeted
                                    ? Color.blue.opacity(0.55)
                                    : (privateKeyFilled ? Color.green.opacity(0.35) : Color.primary.opacity(0.1)),
                                style: StrokeStyle(
                                    lineWidth: isDropTargeted ? 1.5 : 1,
                                    dash: privateKeyFilled || isDropTargeted ? [] : [6, 4]
                                )
                            )
                    )

                TextEditor(text: $privateKey)
                    .font(.system(.caption, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .focused($focusedField, equals: .privateKey)

                if !privateKeyFilled && focusedField != .privateKey {
                    VStack(spacing: 8) {
                        Image(systemName: isDropTargeted ? "arrow.down.doc.fill" : "key.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(isDropTargeted ? Color.blue : Color.secondary)
                        Text(isDropTargeted ? "Drop .p8 file here" : "Paste key contents or drop a .p8 file")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Begins with -----BEGIN PRIVATE KEY-----")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
                }
            }
            .frame(height: 140)
            .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
                handleDrop(providers)
            }
            .animation(.easeInOut(duration: 0.15), value: isDropTargeted)
            .animation(.easeInOut(duration: 0.15), value: privateKeyFilled)

            HStack(spacing: 6) {
                Image(systemName: "lock.shield.fill")
                    .foregroundStyle(.green)
                Text("Stored in macOS Keychain only — never leaves your Mac.")
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var helpSection: some View {
        DisclosureGroup(isExpanded: $showHelp) {
            VStack(alignment: .leading, spacing: 10) {
                helpRow(
                    icon: "info.circle",
                    text: "Create an API key in Apple Search Ads → Account Settings → API."
                )
                helpRow(
                    icon: "link",
                    text: "Client ID, Team ID, and Key ID appear when you download the key."
                )
                helpRow(
                    icon: "number",
                    text: "Org ID is the numeric ID in your Search Ads dashboard URL (optional for single-org accounts)."
                )
            }
            .padding(.top, 8)
        } label: {
            Label("Where do I find these?", systemImage: "questionmark.circle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Building blocks

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
    }

    private func field(
        title: String,
        placeholder: String,
        text: Binding<String>,
        field: Field,
        required: Bool
    ) -> some View {
        let filled = !text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let isFocused = focusedField == field

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                if !required {
                    Text("optional")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if filled {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            isFocused ? Color.accentColor.opacity(0.7) : Color.primary.opacity(0.08),
                            lineWidth: isFocused ? 1.5 : 1
                        )
                )
                .focused($focusedField, equals: field)
                .onSubmit { advanceFocus(from: field) }
        }
        .animation(.easeInOut(duration: 0.15), value: filled)
    }

    private func helpRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.blue)
                .frame(width: 16)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    // MARK: - Actions

    private func advanceFocus(from field: Field) {
        switch field {
        case .clientId: focusedField = .teamId
        case .teamId: focusedField = .keyId
        case .keyId: focusedField = .orgId
        case .orgId: focusedField = .privateKey
        case .privateKey: break
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            guard
                let data = item as? Data,
                let url = URL(dataRepresentation: data, relativeTo: nil)
            else { return }

            DispatchQueue.main.async {
                loadPrivateKey(from: url)
            }
        }
        return true
    }

    private func importP8() {
        let panel = NSOpenPanel()
        panel.title = "Select .p8 Search Ads Key"
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        if let type = UTType(filenameExtension: "p8") {
            panel.allowedContentTypes = [type]
        }
        if panel.runModal() == .OK, let url = panel.url {
            loadPrivateKey(from: url)
        }
    }

    private func loadPrivateKey(from url: URL) {
        do {
            privateKey = try String(contentsOf: url, encoding: .utf8)
            errorMessage = nil
            focusedField = nil
        } catch {
            errorMessage = "Could not read file: \(error.localizedDescription)"
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        let credentials = SearchAdsCredentials(
            clientId: clientId.trimmingCharacters(in: .whitespacesAndNewlines),
            teamId: teamId.trimmingCharacters(in: .whitespacesAndNewlines),
            keyId: keyId.trimmingCharacters(in: .whitespacesAndNewlines),
            privateKeyPEM: privateKey.trimmingCharacters(in: .whitespacesAndNewlines),
            orgId: orgId.trimmingCharacters(in: .whitespacesAndNewlines)
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
