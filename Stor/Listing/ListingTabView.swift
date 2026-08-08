import SwiftUI
import SwiftData

struct ListingTabView: View {
    @Bindable var app: AppRecord
    @Environment(\.modelContext) private var modelContext

    @State private var selectedSnapshot: MetadataSnapshot?
    @State private var isSyncing = false
    @State private var isPushing = false
    @State private var syncError: String?
    @State private var pushError: String?
    @State private var showDiff = false

    var sortedSnapshots: [MetadataSnapshot] {
        app.snapshots.sorted { $0.capturedAt > $1.capturedAt }
    }

    var body: some View {
        HSplitView {
            snapshotHistoryPanel
                .frame(minWidth: 180, idealWidth: 210, maxWidth: 260)
            contentPanel
        }
        .toolbar {
            ToolbarItemGroup {
                if sortedSnapshots.count >= 2 {
                    Button { showDiff = true } label: {
                        Label("Compare", systemImage: "plusminus.circle")
                    }
                    .help("Compare last two snapshots")
                }

                Button(action: pushChanges) {
                    if isPushing {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Label("Push", systemImage: "arrow.up.to.line")
                    }
                }
                .disabled(isPushing || isSyncing || sortedSnapshots.isEmpty)
                .help("Push current metadata to App Store Connect")

                Button(action: syncMetadata) {
                    if isSyncing {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Label("Sync", systemImage: "arrow.clockwise")
                    }
                }
                .disabled(isSyncing)
                .help("Pull latest metadata from App Store Connect")
            }
        }
        .sheet(isPresented: $showDiff) {
            if sortedSnapshots.count >= 2 {
                MetadataDiffView(older: sortedSnapshots[1], newer: sortedSnapshots[0])
            }
        }
        .alert("Sync Failed", isPresented: Binding(
            get: { syncError != nil },
            set: { if !$0 { syncError = nil } }
        )) {
            Button("OK") { syncError = nil }
        } message: {
            Text(syncError ?? "")
        }
        .alert("Push Failed", isPresented: Binding(
            get: { pushError != nil },
            set: { if !$0 { pushError = nil } }
        )) {
            Button("OK") { pushError = nil }
        } message: {
            Text(pushError ?? "")
        }
        .onAppear {
            if selectedSnapshot == nil {
                selectedSnapshot = sortedSnapshots.first
            }
        }
    }

    // MARK: - Panels

    private var snapshotHistoryPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Snapshots")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(sortedSnapshots.count)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider()

            if sortedSnapshots.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.title2)
                        .foregroundStyle(.quaternary)
                    Text("No snapshots yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("Press Sync to pull metadata")
                        .font(.caption2)
                        .foregroundStyle(.quaternary)
                }
                .padding(.top, 24)
                Spacer()
            } else {
                List(sortedSnapshots, selection: $selectedSnapshot) { snapshot in
                    SnapshotRow(
                        snapshot: snapshot,
                        isLatest: snapshot == sortedSnapshots.first
                    )
                    .tag(snapshot as MetadataSnapshot?)
                }
                .listStyle(.sidebar)
            }
        }
    }

    private var contentPanel: some View {
        Group {
            if let snapshot = selectedSnapshot {
                MetadataDetailView(
                    snapshot: snapshot,
                    isEditable: snapshot == sortedSnapshots.first
                )
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 32))
                        .foregroundStyle(.tertiary)
                        .padding(.top, 48)
                    Text("No Snapshot Selected")
                        .font(.headline)
                    Text("Click Sync to pull your app's metadata from App Store Connect.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 32)
            }
        }
    }

    // MARK: - Push

    private func pushChanges() {
        guard let latest = sortedSnapshots.first else { return }
        guard let credentials = try? KeychainService.shared.load() else {
            pushError = "No API credentials found."
            return
        }

        isPushing = true
        pushError = nil

        Task {
            defer { isPushing = false }
            let client = ASCAPIClient(credentials: credentials)
            do {
                for loc in latest.localizations {
                    if let id = loc.versionLocalizationId {
                        try await client.updateVersionLocalization(
                            id: id,
                            description: loc.appDescription,
                            keywords: loc.keywords,
                            promotionalText: loc.promotionalText,
                            whatsNew: loc.whatsNew
                        )
                    }
                    if let id = loc.appInfoLocalizationId {
                        try await client.updateAppInfoLocalization(
                            id: id,
                            name: loc.appName,
                            subtitle: loc.subtitle
                        )
                    }
                }
            } catch {
                pushError = error.localizedDescription
            }
        }
    }

    // MARK: - Sync

    private func syncMetadata() {
        guard let credentials = try? KeychainService.shared.load() else {
            syncError = "No API credentials found."
            return
        }

        isSyncing = true
        syncError = nil

        Task {
            defer { isSyncing = false }
            do {
                let client = ASCAPIClient(credentials: credentials)
                let result = try await client.syncMetadata(appId: app.ascAppId)

                let snapshot = MetadataSnapshot(
                    capturedAt: .now,
                    versionString: result.version?.attributes.versionString,
                    versionId: result.version?.id
                )
                snapshot.app = app
                modelContext.insert(snapshot)

                var localeMap: [String: LocalizedMetadata] = [:]

                for vLoc in result.versionLocalizations {
                    let meta = LocalizedMetadata(
                        locale: vLoc.attributes.locale,
                        appDescription: vLoc.attributes.description,
                        keywords: vLoc.attributes.keywords,
                        promotionalText: vLoc.attributes.promotionalText,
                        whatsNew: vLoc.attributes.whatsNew
                    )
                    meta.versionLocalizationId = vLoc.id
                    localeMap[vLoc.attributes.locale] = meta
                }

                for infoLoc in result.appInfoLocalizations {
                    if let existing = localeMap[infoLoc.attributes.locale] {
                        existing.appName = infoLoc.attributes.name
                        existing.subtitle = infoLoc.attributes.subtitle
                        existing.appInfoLocalizationId = infoLoc.id
                    } else {
                        let meta = LocalizedMetadata(
                            locale: infoLoc.attributes.locale,
                            appName: infoLoc.attributes.name,
                            subtitle: infoLoc.attributes.subtitle
                        )
                        meta.appInfoLocalizationId = infoLoc.id
                        localeMap[infoLoc.attributes.locale] = meta
                    }
                }

                for meta in localeMap.values {
                    meta.snapshot = snapshot
                    snapshot.localizations.append(meta)
                    modelContext.insert(meta)
                }

                app.snapshots.append(snapshot)
                selectedSnapshot = snapshot

            } catch {
                syncError = error.localizedDescription
            }
        }
    }
}

// MARK: - Snapshot row

private struct SnapshotRow: View {
    let snapshot: MetadataSnapshot
    let isLatest: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text(snapshot.capturedAt, style: .date)
                    .fontWeight(.medium)
                    .font(.callout)
                if isLatest {
                    Text("Latest")
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(.blue.opacity(0.15), in: Capsule())
                        .foregroundStyle(.blue)
                }
            }
            Text(snapshot.capturedAt, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let v = snapshot.versionString {
                Text("v\(v)")
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.vertical, 2)
    }
}
