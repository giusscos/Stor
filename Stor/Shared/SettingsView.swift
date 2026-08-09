import SwiftData
import SwiftUI

/// The standard macOS Settings window. Credential management used to live only in
/// onboarding and a sidebar menu, which meant there was no way to review or disconnect
/// Apple Search Ads once it had been connected.
struct SettingsView: View {
    var body: some View {
        TabView {
            AccountsSettingsView()
                .tabItem { Label("Accounts", systemImage: "person.crop.circle") }

            SearchAdsSettingsView()
                .tabItem { Label("Search Ads", systemImage: "chart.bar") }

            StorageSettingsView()
                .tabItem { Label("Storage", systemImage: "internaldrive") }
        }
        .frame(width: 520, height: 380)
    }
}

// MARK: - App Store Connect accounts

private struct AccountsSettingsView: View {
    @State private var accounts: [ASCCredentials] = []
    @State private var activeId: UUID?
    @State private var showAddAccount = false
    @State private var accountPendingRemoval: ASCCredentials?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("App Store Connect API keys are stored in your Mac's Keychain and never leave this device.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if accounts.isEmpty {
                ContentUnavailableView(
                    "No accounts",
                    systemImage: "key",
                    description: Text("Add an App Store Connect API key to get started.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(accounts) { account in
                        AccountRow(
                            account: account,
                            isActive: account.id == activeId,
                            onActivate: { activate(account) },
                            onRemove: { accountPendingRemoval = account }
                        )
                    }
                }
                .frame(maxHeight: .infinity)
            }

            HStack {
                Button("Add Account…") { showAddAccount = true }
                Spacer()
            }
        }
        .padding(20)
        .onAppear(perform: reload)
        .sheet(isPresented: $showAddAccount) {
            AddAPIKeyView(
                onSave: { _ in reload() },
                existingAccounts: accounts,
                initiallyShowForm: true
            )
        }
        .confirmationDialog(
            "Remove “\(accountPendingRemoval?.name ?? "")”?",
            isPresented: Binding(
                get: { accountPendingRemoval != nil },
                set: { if !$0 { accountPendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Remove Account", role: .destructive) {
                if let account = accountPendingRemoval { remove(account) }
                accountPendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { accountPendingRemoval = nil }
        } message: {
            Text("The API key is deleted from your Keychain. Apps and snapshots already synced stay on this Mac.")
        }
        .alert("Keychain Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func reload() {
        do {
            let store = try KeychainService.shared.loadStore()
            accounts = store?.accounts ?? []
            activeId = store?.active?.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func activate(_ account: ASCCredentials) {
        do {
            try KeychainService.shared.setActiveAccount(id: account.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func remove(_ account: ASCCredentials) {
        do {
            _ = try KeychainService.shared.removeAccount(id: account.id)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AccountRow: View {
    let account: ASCCredentials
    let isActive: Bool
    let onActivate: () -> Void
    let onRemove: () -> Void

    private var subtitle: String {
        "Key \(account.shortKeyId) · Issuer \(String(account.issuerId.prefix(8)))…"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))

            VStack(alignment: .leading, spacing: 1) {
                Text(account.name)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !isActive {
                Button("Use", action: onActivate)
                    .controlSize(.small)
            }

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove account \(account.name)")
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Apple Search Ads

private struct SearchAdsSettingsView: View {
    @State private var credentials: SearchAdsCredentials?
    @State private var showConnect = false
    @State private var confirmDisconnect = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Apple Search Ads supplies the popularity scores shown in the Keywords tab.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let credentials {
                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        labelled("Client ID", credentials.clientId)
                        labelled("Team ID", credentials.teamId)
                        labelled("Key ID", credentials.keyId)
                        labelled("Org ID", credentials.orgId.isEmpty ? "Not set" : credentials.orgId)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }

                HStack {
                    Button("Replace Credentials…") { showConnect = true }
                    Button("Disconnect", role: .destructive) { confirmDisconnect = true }
                    Spacer()
                }
            } else {
                ContentUnavailableView {
                    Label("Not connected", systemImage: "chart.bar")
                } description: {
                    Text("Connect Apple Search Ads to fetch keyword popularity.")
                } actions: {
                    Button("Connect…") { showConnect = true }
                        .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)
        }
        .padding(20)
        .onAppear(perform: reload)
        .sheet(isPresented: $showConnect) {
            AddSearchAdsKeyView { saved in
                credentials = saved
            }
        }
        .confirmationDialog(
            "Disconnect Apple Search Ads?",
            isPresented: $confirmDisconnect,
            titleVisibility: .visible
        ) {
            Button("Disconnect", role: .destructive, action: disconnect)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The private key is removed from your Keychain. Popularity scores already fetched stay in place.")
        }
        .alert("Keychain Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func labelled(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }

    private func reload() {
        do {
            credentials = try KeychainService.shared.loadSearchAds()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func disconnect() {
        do {
            try KeychainService.shared.deleteSearchAds()
            credentials = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Storage

private struct StorageSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var status: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Screenshot images are stored outside the database and shared between layers that use the same file.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button("Reclaim Unused Screenshot Images") { prune() }

            if let status {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    private func prune() {
        let refs = ScreenshotImageStore.referencedImages(in: modelContext)
        ScreenshotImageStore.shared.pruneUnreferenced(keeping: refs)
        status = "Kept \(refs.count) image\(refs.count == 1 ? "" : "s") still in use."
    }
}
