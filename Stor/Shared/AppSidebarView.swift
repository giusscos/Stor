import SwiftUI
import SwiftData

struct AppSidebarView: View {
    @Binding var selectedApp: AppRecord?
    @Binding var credentials: ASCCredentials?
    @Query(sort: \AppRecord.addedAt) private var apps: [AppRecord]
    @State private var showAddApp = false
    @State private var showAddAccount = false
    @State private var showAccountPicker = false
    @State private var accounts: [ASCCredentials] = []
    @State private var pendingRemoval: PendingRemoval?
    @State private var errorMessage: String?

    private enum PendingRemoval: Identifiable {
        case active(String)
        case all

        var id: String {
            switch self {
            case .active(let name): return "active-\(name)"
            case .all: return "all"
            }
        }

        var title: String {
            switch self {
            case .active(let name): return "Remove “\(name)”?"
            case .all: return "Disconnect all accounts?"
            }
        }

        var message: String {
            switch self {
            case .active:
                return "The API key is removed from your Keychain. Apps and snapshots already on this Mac are kept."
            case .all:
                return "Every App Store Connect API key is removed from your Keychain and you'll return to onboarding."
            }
        }

        var confirmLabel: String {
            switch self {
            case .active: return "Remove Account"
            case .all: return "Disconnect All"
            }
        }
    }

    var body: some View {
        List(selection: $selectedApp) {
            ForEach(apps) { app in
                AppSidebarRow(app: app)
                    .tag(app)
            }
        }
        .navigationTitle("AscendKit")
        .toolbar {
            ToolbarItem {
                Button { showAddApp = true } label: {
                    Image(systemName: "plus")
                }
                .help("Add App")
            }

            ToolbarItem {
                Menu {
                    if !accounts.isEmpty {
                        Section(accounts.count == 1 ? "Account" : "Accounts") {
                            ForEach(accounts) { account in
                                Button {
                                    switchToAccount(account)
                                } label: {
                                    if account.id == credentials?.id {
                                        Label(account.name, systemImage: "checkmark")
                                    } else {
                                        Text(account.name)
                                    }
                                }
                            }
                        }
                    }

                    Button("Add Account…") {
                        showAddAccount = true
                    }

                    if accounts.count > 1 {
                        Button("Switch Account…") {
                            showAccountPicker = true
                        }
                    }

                    Divider()

                    if let credentials {
                        Button("Remove “\(credentials.name)”", role: .destructive) {
                            pendingRemoval = .active(credentials.name)
                        }
                    }

                    if accounts.count > 1 {
                        Button("Disconnect All Accounts", role: .destructive) {
                            pendingRemoval = .all
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help(credentials.map { "Account: \($0.name)" } ?? "Accounts")
            }
        }
        .overlay {
            if apps.isEmpty {
                ContentUnavailableView {
                    Label("No Apps", systemImage: "plus.app")
                } description: {
                    Text("Add your App Store Connect apps to get started.")
                } actions: {
                    Button("Add App") { showAddApp = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let credentials {
                accountFooter(credentials)
            }
        }
        .sheet(isPresented: $showAddApp) {
            AddAppView()
        }
        .sheet(isPresented: $showAddAccount) {
            AddAPIKeyView(
                onSave: { saved in
                    credentials = saved
                    refreshAccounts()
                },
                existingAccounts: accounts,
                initiallyShowForm: true
            )
        }
        .sheet(isPresented: $showAccountPicker) {
            AddAPIKeyView(
                onSave: { saved in
                    credentials = saved
                    refreshAccounts()
                },
                existingAccounts: accounts,
                initiallyShowForm: false
            )
        }
        .confirmationDialog(
            pendingRemoval?.title ?? "",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingRemoval {
                Button(pendingRemoval.confirmLabel, role: .destructive) {
                    switch pendingRemoval {
                    case .active: removeActiveAccount()
                    case .all: disconnectAll()
                    }
                    self.pendingRemoval = nil
                }
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text(pendingRemoval?.message ?? "")
        }
        .alert("Account Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .onAppear { refreshAccounts() }
        .onChange(of: credentials?.id) { _, _ in
            refreshAccounts()
        }
    }

    private func accountFooter(_ account: ASCCredentials) -> some View {
        Button {
            showAccountPicker = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.blue)

                VStack(alignment: .leading, spacing: 1) {
                    Text(account.name)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(accounts.count > 1 ? "\(accounts.count) accounts · Switch" : "Key \(account.shortKeyId)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)
        }
        .buttonStyle(.plain)
        .help("Switch App Store Connect account")
    }

    private func refreshAccounts() {
        accounts = (try? KeychainService.shared.allAccounts()) ?? []
    }

    private func switchToAccount(_ account: ASCCredentials) {
        do {
            try KeychainService.shared.setActiveAccount(id: account.id)
            credentials = account
            selectedApp = nil
        } catch {
            errorMessage = "Could not switch to “\(account.name)”. \(error.localizedDescription)"
        }
    }

    private func removeActiveAccount() {
        guard let id = credentials?.id else { return }
        do {
            credentials = try KeychainService.shared.removeAccount(id: id)
            selectedApp = nil
            refreshAccounts()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func disconnectAll() {
        do {
            try KeychainService.shared.delete()
            credentials = nil
            selectedApp = nil
            accounts = []
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AppSidebarRow: View {
    @Bindable var app: AppRecord

    var body: some View {
        HStack(spacing: 10) {
            AsyncImage(url: URL(string: app.iconURL ?? "")) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(.quaternary)
                        .overlay {
                            Image(systemName: "app.fill")
                                .foregroundStyle(.tertiary)
                                .font(.callout)
                        }
                }
            }
            .frame(width: 32, height: 32)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .fontWeight(.medium)
                HStack(spacing: 6) {
                    Text(app.bundleId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if let error = app.lastSyncError, !error.isEmpty {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help(error)
                    } else if let last = app.lastSyncedAt {
                        Text(last, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .help("Last synced \(last.formatted(date: .abbreviated, time: .shortened))")
                    }
                }
            }
        }
        .padding(.vertical, 2)
        .contextMenu {
            Menu("Auto-Sync") {
                ForEach(SyncCadence.allCases) { cadence in
                    Button {
                        app.syncCadence = cadence
                    } label: {
                        if app.syncCadence == cadence {
                            Label(cadence.label, systemImage: "checkmark")
                        } else {
                            Text(cadence.label)
                        }
                    }
                }
            }
        }
        .task(id: app.bundleId) {
            guard app.iconURL == nil else { return }
            app.iconURL = await ITunesLookupClient.shared.fetchIconURL(bundleId: app.bundleId)
        }
    }
}
