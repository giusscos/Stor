import SwiftUI
import SwiftData

struct AppSidebarView: View {
    @Binding var selectedApp: AppRecord?
    @Binding var credentials: ASCCredentials?
    @Query(sort: \AppRecord.addedAt) private var apps: [AppRecord]
    @State private var showAddApp = false

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
                    Button("Disconnect API Key", role: .destructive) {
                        disconnectAPIKey()
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
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
        .sheet(isPresented: $showAddApp) {
            AddAppView()
        }
    }

    private func disconnectAPIKey() {
        try? KeychainService.shared.delete()
        credentials = nil
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
            app.iconURL = await fetchIconURL(for: app.bundleId)
        }
    }

    private func fetchIconURL(for bundleId: String) async -> String? {
        guard let url = URL(string: "https://itunes.apple.com/lookup?bundleId=\(bundleId)&entity=software&limit=1") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let artworkUrl = results.first?["artworkUrl512"] as? String else { return nil }
        return artworkUrl
    }
}
