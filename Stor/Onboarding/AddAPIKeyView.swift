import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct AddAPIKeyView: View {
    let onSave: (ASCCredentials) -> Void
    /// Called when Cancel is pressed in non-sheet contexts (e.g. onboarding).
    var onCancel: (() -> Void)? = nil
    /// Existing accounts shown for quick selection (multi-account).
    var existingAccounts: [ASCCredentials] = []
    var initiallyShowForm: Bool = false

    @Environment(\.dismiss) private var dismiss

    @State private var mode: Mode = .form
    @State private var accountName = ""
    @State private var issuerId = ""
    @State private var keyId = ""
    @State private var privateKeyPEM = ""
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var isDropTargeted = false
    @State private var showHelp = false

    @FocusState private var focusedField: Field?

    private enum Mode {
        case pick
        case form
    }

    private enum Field: Hashable {
        case accountName, issuerId, keyId, privateKey
    }

    var canSave: Bool {
        !issuerId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !keyId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var privateKeyFilled: Bool {
        !privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var resolvedAccountName: String {
        let trimmed = accountName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "App Store Connect" : trimmed
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    header

                    if mode == .pick {
                        accountPicker
                    } else {
                        accountNameCard
                        credentialsCard
                        privateKeyCard

                        if let errorMessage {
                            errorBanner(errorMessage)
                        }

                        helpSection
                    }
                }
                .padding(24)
            }
            .navigationTitle(mode == .pick ? "Choose Account" : "Connect App Store Connect")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(mode == .form && canGoBackToPicker ? "Back" : "Cancel") {
                        if mode == .form && canGoBackToPicker {
                            mode = .pick
                            errorMessage = nil
                        } else {
                            cancel()
                        }
                    }
                }

                if mode == .form {
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            saveCredentials()
                        } label: {
                            if isSaving {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text(existingAccounts.isEmpty ? "Connect" : "Add Account")
                            }
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canSave || isSaving)
                    }
                }
            }
            .onAppear {
                if !initiallyShowForm, !existingAccounts.isEmpty {
                    mode = .pick
                } else {
                    mode = .form
                }
            }
        }
        .frame(minWidth: 540, minHeight: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var canGoBackToPicker: Bool {
        !existingAccounts.isEmpty && !initiallyShowForm
    }

    // MARK: - Sections

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: mode == .pick ? "person.2.fill" : "key.horizontal.fill")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(
                    LinearGradient(
                        colors: [Color.blue, Color.indigo.opacity(0.85)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                )

            VStack(alignment: .leading, spacing: 4) {
                Text(mode == .pick ? "Your developer accounts" : "Connect with an API key")
                    .font(.title3.weight(.semibold))
                Text(
                    mode == .pick
                        ? "Switch between Apple Developer accounts you use for different apps or clients."
                        : "Add an App Store Connect API key. Give each account a name so you can switch later."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accountPicker: some View {
        VStack(spacing: 10) {
            ForEach(existingAccounts) { account in
                Button {
                    selectExisting(account)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.blue)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(account.name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(.primary)
                            Text("Key \(account.shortKeyId) · Issuer \(String(account.issuerId.prefix(8)))…")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fontDesign(.monospaced)
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(14)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            Button {
                resetForm()
                mode = .form
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.blue)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Add another account")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.primary)
                        Text("Connect a different Apple Developer team")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(14)
                .background(Color.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.blue.opacity(0.2), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
    }

    private var accountNameCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("Account")

            field(
                title: "Display Name",
                placeholder: "e.g. Personal, Client Co, Agency",
                text: $accountName,
                field: .accountName,
                monospaced: false,
                required: false
            )
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private var credentialsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionLabel("API Key Credentials")

            VStack(spacing: 12) {
                field(
                    title: "Issuer ID",
                    placeholder: "xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
                    text: $issuerId,
                    field: .issuerId,
                    monospaced: true,
                    required: true
                )
                field(
                    title: "Key ID",
                    placeholder: "XXXXXXXXXX",
                    text: $keyId,
                    field: .keyId,
                    monospaced: true,
                    required: true
                )
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
                        privateKeyPEM = ""
                        focusedField = .privateKey
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
                Button {
                    importP8File()
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

                TextEditor(text: $privateKeyPEM)
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
                    text: "Create a key in App Store Connect → Users and Access → Integrations → App Store Connect API."
                )
                helpRow(
                    icon: "person.2",
                    text: "Add multiple keys if you work across different developer teams or client accounts."
                )
                helpRow(
                    icon: "arrow.left.arrow.right",
                    text: "All requests go directly from your Mac to Apple — no third-party relay."
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
        monospaced: Bool,
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
                if filled && required {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                }
            }

            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .font(monospaced ? .system(.body, design: .monospaced) : .body)
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

    private func cancel() {
        if let onCancel {
            onCancel()
        } else {
            dismiss()
        }
    }

    private func finish(_ credentials: ASCCredentials) {
        onSave(credentials)
        // Sheet presentation dismisses itself; inline onboarding is swapped out by the parent.
        if onCancel == nil {
            dismiss()
        }
    }

    private func resetForm() {
        accountName = ""
        issuerId = ""
        keyId = ""
        privateKeyPEM = ""
        errorMessage = nil
        isSaving = false
    }

    private func selectExisting(_ account: ASCCredentials) {
        do {
            try KeychainService.shared.setActiveAccount(id: account.id)
            finish(account)
        } catch {
            errorMessage = error.localizedDescription
            mode = .form
        }
    }

    private func advanceFocus(from field: Field) {
        switch field {
        case .accountName: focusedField = .issuerId
        case .issuerId: focusedField = .keyId
        case .keyId: focusedField = .privateKey
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
            loadPrivateKey(from: url)
        }
    }

    private func loadPrivateKey(from url: URL) {
        do {
            privateKeyPEM = try String(contentsOf: url, encoding: .utf8)
            errorMessage = nil
            focusedField = nil
        } catch {
            errorMessage = "Could not read file: \(error.localizedDescription)"
        }
    }

    private func saveCredentials() {
        isSaving = true
        errorMessage = nil
        let credentials = ASCCredentials(
            name: resolvedAccountName,
            issuerId: issuerId.trimmingCharacters(in: .whitespacesAndNewlines),
            keyId: keyId.trimmingCharacters(in: .whitespacesAndNewlines),
            privateKeyPEM: privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        do {
            try KeychainService.shared.save(credentials)
            finish(credentials)
        } catch {
            errorMessage = error.localizedDescription
            isSaving = false
        }
    }
}
