import SwiftUI

struct ASCScreenshotSetsView: View {
    let app: AppRecord

    @Environment(\.dismiss) private var dismiss

    @State private var localizations: [(id: String, locale: String)] = []
    @State private var selectedLocalizationId = ""
    @State private var sets: [ASCScreenshotSet] = []
    @State private var selectedSetId = ""
    @State private var screenshots: [ASCScreenshot] = []
    @State private var isLoading = false
    @State private var isMutating = false
    @State private var errorMessage: String?
    @State private var pendingDelete: ASCScreenshot?

    private var selectedLocale: String {
        localizations.first { $0.id == selectedLocalizationId }?.locale ?? ""
    }

    private var selectedSet: ASCScreenshotSet? {
        sets.first { $0.id == selectedSetId }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filters
                Divider()
                if isLoading {
                    ProgressView("Loading screenshots…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if localizations.isEmpty {
                    ContentUnavailableView(
                        "Sync listing metadata first",
                        systemImage: "arrow.clockwise",
                        description: Text("Screenshot sets are attached to a version localization.")
                    )
                } else if screenshots.isEmpty {
                    ContentUnavailableView(
                        "No screenshots in this set",
                        systemImage: "photo.on.rectangle.angled",
                        description: Text("Upload from the editor, or pick another device / locale.")
                    )
                } else {
                    screenshotList
                }
            }
            .navigationTitle("App Store Screenshots")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await reloadSetsAndScreenshots() }
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .disabled(isLoading || isMutating || selectedLocalizationId.isEmpty)
                }
            }
            .alert("Error", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .confirmationDialog(
                "Delete this screenshot from App Store Connect?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("Delete Screenshot", role: .destructive) {
                    if let shot = pendingDelete {
                        Task { await deleteScreenshot(shot) }
                    }
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) { pendingDelete = nil }
            } message: {
                Text("This removes it from the live screenshot set. It cannot be undone from AscendKit.")
            }
            .task {
                loadLocalizations()
                await reloadSetsAndScreenshots()
            }
        }
        .frame(minWidth: 640, minHeight: 520)
    }

    private var filters: some View {
        HStack(spacing: 16) {
            Picker("Locale", selection: $selectedLocalizationId) {
                ForEach(localizations, id: \.id) { loc in
                    Text(LocaleDisplayName.name(for: loc.locale)).tag(loc.id)
                }
            }
            .frame(maxWidth: 220)
            .onChange(of: selectedLocalizationId) {
                Task { await reloadSetsAndScreenshots() }
            }

            Picker("Set", selection: $selectedSetId) {
                ForEach(sets) { set in
                    Text(Self.displayName(for: set.attributes.screenshotDisplayType)).tag(set.id)
                }
            }
            .frame(maxWidth: 240)
            .disabled(sets.isEmpty)
            .onChange(of: selectedSetId) {
                Task { await reloadScreenshots() }
            }

            Spacer()

            if isMutating {
                ProgressView().controlSize(.small)
            }
        }
        .padding(16)
    }

    private var screenshotList: some View {
        List {
            ForEach(Array(screenshots.enumerated()), id: \.element.id) { index, shot in
                HStack(spacing: 14) {
                    preview(for: shot)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(shot.attributes.fileName ?? "Screenshot")
                            .fontWeight(.medium)
                            .lineLimit(1)
                        HStack(spacing: 8) {
                            Text("Position \(shot.attributes.displayPosition ?? (index + 1))")
                            if let state = shot.attributes.assetDeliveryState?.state {
                                Text(state.replacingOccurrences(of: "_", with: " ").localizedCapitalized)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        Task { await move(shot, by: -1) }
                    } label: {
                        Image(systemName: "chevron.up")
                    }
                    .buttonStyle(.bordered)
                    .disabled(index == 0 || isMutating)
                    .help("Move earlier")

                    Button {
                        Task { await move(shot, by: 1) }
                    } label: {
                        Image(systemName: "chevron.down")
                    }
                    .buttonStyle(.bordered)
                    .disabled(index == screenshots.count - 1 || isMutating)
                    .help("Move later")

                    Button(role: .destructive) {
                        pendingDelete = shot
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isMutating)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func preview(for shot: ASCScreenshot) -> some View {
        Group {
            if let url = shot.attributes.imageAsset?.previewURL() {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        RoundedRectangle(cornerRadius: 6).fill(.quinary)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 6).fill(.quinary)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .frame(width: 56, height: 100)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func loadLocalizations() {
        guard let snapshot = app.snapshots.sorted(by: { $0.capturedAt > $1.capturedAt }).first else {
            localizations = []
            return
        }
        localizations = snapshot.localizations
            .compactMap { loc -> (id: String, locale: String)? in
                guard let id = loc.versionLocalizationId else { return nil }
                return (id, loc.locale)
            }
            .sorted { $0.locale < $1.locale }
        if selectedLocalizationId.isEmpty {
            selectedLocalizationId = localizations.first?.id ?? ""
        }
    }

    private func client() throws -> ASCAPIClient {
        guard let credentials = try KeychainService.shared.load() else {
            throw ASCAPIError.httpError(401, "No API credentials found.")
        }
        return ASCAPIClient(credentials: credentials)
    }

    private func reloadSetsAndScreenshots() async {
        guard !selectedLocalizationId.isEmpty else {
            sets = []
            screenshots = []
            return
        }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let client = try client()
            sets = try await client.fetchScreenshotSets(localizationId: selectedLocalizationId)
            if sets.contains(where: { $0.id == selectedSetId }) == false {
                selectedSetId = sets.first?.id ?? ""
            }
            try await loadScreenshots(using: client)
        } catch {
            errorMessage = error.localizedDescription
            sets = []
            screenshots = []
        }
    }

    private func reloadScreenshots() async {
        guard !selectedSetId.isEmpty else {
            screenshots = []
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            try await loadScreenshots(using: try client())
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadScreenshots(using client: ASCAPIClient) async throws {
        guard !selectedSetId.isEmpty else {
            screenshots = []
            return
        }
        screenshots = try await client.fetchScreenshots(setId: selectedSetId)
    }

    private func move(_ shot: ASCScreenshot, by delta: Int) async {
        guard let index = screenshots.firstIndex(where: { $0.id == shot.id }) else { return }
        let target = index + delta
        guard screenshots.indices.contains(target) else { return }

        var reordered = screenshots
        reordered.swapAt(index, target)
        isMutating = true
        defer { isMutating = false }
        do {
            let client = try client()
            for (offset, item) in reordered.enumerated() {
                try await client.updateScreenshotPosition(id: item.id, position: offset + 1)
            }
            screenshots = try await client.fetchScreenshots(setId: selectedSetId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteScreenshot(_ shot: ASCScreenshot) async {
        isMutating = true
        defer { isMutating = false }
        do {
            let client = try client()
            try await client.deleteScreenshot(id: shot.id)
            screenshots = try await client.fetchScreenshots(setId: selectedSetId)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    static func displayName(for displayType: String) -> String {
        DeviceType.allCases.first { $0.ascDisplayType == displayType }?.rawValue
            ?? displayType
                .replacingOccurrences(of: "APP_", with: "")
                .replacingOccurrences(of: "_", with: " ")
                .localizedCapitalized
    }
}
