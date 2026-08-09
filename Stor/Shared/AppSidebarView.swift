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

    var body: some View {
        List(selection: $selectedApp) {
            ForEach(apps) { app in
                AppSidebarRow(app: app)
                    .tag(app)
            }
        }
        .navigationTitle("Stor")
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
                            removeActiveAccount()
                        }
                    }

                    if accounts.count > 1 {
                        Button("Disconnect All Accounts", role: .destructive) {
                            disconnectAll()
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
            // Keep current selection if switch fails
        }
    }

    private func removeActiveAccount() {
        guard let id = credentials?.id else { return }
        credentials = try? KeychainService.shared.removeAccount(id: id)
        selectedApp = nil
        refreshAccounts()
    }

    private func disconnectAll() {
        try? KeychainService.shared.delete()
        credentials = nil
        selectedApp = nil
        accounts = []
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
                Text(app.bundleId)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .task(id: app.bundleId) {
            guard app.iconURL == nil else { return }
            app.iconURL = await ITunesLookupClient.shared.fetchIconURL(bundleId: app.bundleId)
        }
    }
}
