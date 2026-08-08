import SwiftUI
import SwiftData

struct AddAppView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var existingApps: [AppRecord]

    @State private var fetchState: FetchState = .loading
    @State private var ascApps: [ASCApp] = []
    @State private var selectedApp: ASCApp?

    private enum FetchState {
        case loading, loaded, error(String)
    }

    var body: some View {
        NavigationStack {
            Group {
                switch fetchState {
                case .loading:
                    ProgressView("Fetching your apps from App Store Connect…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                case .loaded:
                    appList

                case .error(let message):
                    ContentUnavailableView(
                        "Unable to Fetch Apps",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                }
            }
            .navigationTitle("Add App")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addSelectedApp() }
                        .disabled(selectedApp == nil)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 420)
        .task { await loadApps() }
    }

    private var appList: some View {
        List(ascApps, selection: $selectedApp) { app in
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.attributes.name)
                        .fontWeight(.medium)
                    Text(app.attributes.bundleId)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if existingApps.contains(where: { $0.ascAppId == app.id }) {
                    Text("Added")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                }
            }
            .tag(app)
            .disabled(existingApps.contains(where: { $0.ascAppId == app.id }))
        }
    }

    private func loadApps() async {
        guard let credentials = try? KeychainService.shared.load() else {
            fetchState = .error("No API credentials found. Please reconnect your account.")
            return
        }
        do {
            let client = ASCAPIClient(credentials: credentials)
            ascApps = try await client.fetchApps()
            fetchState = .loaded
        } catch {
            fetchState = .error(error.localizedDescription)
        }
    }

    private func addSelectedApp() {
        guard let ascApp = selectedApp else { return }
        let record = AppRecord(
            ascAppId: ascApp.id,
            bundleId: ascApp.attributes.bundleId,
            name: ascApp.attributes.name,
            primaryLocale: ascApp.attributes.primaryLocale
        )
        modelContext.insert(record)
        dismiss()
    }
}
