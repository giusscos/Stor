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
    @State private var importMessage: String?
    @State private var importSucceeded = false
    @State private var showPushConfirmation = false
    @State private var pushResult: String?
    @State private var versions: [ASCAppStoreVersion] = []
    @State private var isLoadingVersions = false

    var sortedSnapshots: [MetadataSnapshot] {
        app.snapshots.sorted { $0.capturedAt > $1.capturedAt }
    }

    var body: some View {
        HSplitView {
            snapshotHistoryPanel
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
            contentPanel
        }
        .toolbar {
            ToolbarItemGroup {
                versionPicker

                if sortedSnapshots.count >= 2 {
                    Button { showDiff = true } label: {
                        Label("Compare", systemImage: "plusminus.circle")
                    }
                    .help("Compare last two snapshots")
                }

                Button(action: importMarkdown) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .disabled(sortedSnapshots.isEmpty)
                .help("Import listing metadata from Markdown")

                Button(action: exportCurrentMarkdown) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .disabled(sortedSnapshots.isEmpty)
                .help("Export current metadata as Markdown")

                Button(action: downloadSampleTemplate) {
                    Label("Sample", systemImage: "doc.badge.plus")
                }
                .help("Download a sample Markdown template")

                Button(action: confirmPush) {
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
        .confirmationDialog(
            "Push metadata to App Store Connect?",
            isPresented: $showPushConfirmation,
            titleVisibility: .visible
        ) {
            Button("Push to App Store Connect", role: .destructive, action: pushChanges)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(pushConfirmationMessage)
        }
        .alert("Push Failed", isPresented: Binding(
            get: { pushError != nil },
            set: { if !$0 { pushError = nil } }
        )) {
            Button("OK") { pushError = nil }
        } message: {
            Text(pushError ?? "")
        }
        .alert("Push Complete", isPresented: Binding(
            get: { pushResult != nil },
            set: { if !$0 { pushResult = nil } }
        )) {
            Button("OK") { pushResult = nil }
        } message: {
            Text(pushResult ?? "")
        }
        .alert(importSucceeded ? "Import Complete" : "Import Failed", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("OK") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
        .onAppear {
            if selectedSnapshot == nil {
                selectedSnapshot = sortedSnapshots.first
            }
            Task { await loadVersions() }
        }
    }

    // MARK: - Panels

    private var snapshotHistoryPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("History")
                    .font(.system(.subheadline, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("\(sortedSnapshots.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.06), in: Capsule())
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

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
                .frame(maxWidth: .infinity)
                .padding(.top, 28)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(sortedSnapshots.enumerated()), id: \.element.id) { index, snapshot in
                            SnapshotTimelineRow(
                                snapshot: snapshot,
                                isLatest: index == 0,
                                isSelected: selectedSnapshot == snapshot,
                                isLast: index == sortedSnapshots.count - 1
                            )
                            .contentShape(Rectangle())
                            .onTapGesture { selectedSnapshot = snapshot }
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                }
            }
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var contentPanel: some View {
        Group {
            if let snapshot = selectedSnapshot {
                MetadataDetailView(
                    snapshot: snapshot,
                    app: app,
                    isEditable: snapshot == sortedSnapshots.first && snapshot.isVersionEditable
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

    // MARK: - Version picker

    @ViewBuilder
    private var versionPicker: some View {
        Menu {
            if versions.isEmpty {
                Text("Sync or wait — no versions loaded")
            } else {
                ForEach(versions, id: \.id) { version in
                    Button {
                        app.preferredVersionId = version.id
                    } label: {
                        if version.id == app.preferredVersionId {
                            Label(versionLabel(version), systemImage: "checkmark")
                        } else {
                            Text(versionLabel(version))
                        }
                    }
                }
            }
        } label: {
            if isLoadingVersions {
                ProgressView().controlSize(.small)
            } else if let selected = selectedVersion {
                Label(versionLabel(selected), systemImage: "app.badge")
            } else {
                Label("Version", systemImage: "app.badge")
            }
        }
        .help("Choose which App Store version Sync pulls and Push writes")
        .disabled(isSyncing || isPushing)
    }

    private var selectedVersion: ASCAppStoreVersion? {
        if let id = app.preferredVersionId {
            return versions.first { $0.id == id }
        }
        return versions.first
    }

    private func versionLabel(_ version: ASCAppStoreVersion) -> String {
        "\(version.attributes.versionString) · \(version.displayState)"
    }

    private func loadVersions() async {
        guard let credentials = try? KeychainService.shared.load() else { return }
        isLoadingVersions = true
        defer { isLoadingVersions = false }
        do {
            let fetched = try await ASCAPIClient(credentials: credentials).fetchVersions(appId: app.ascAppId)
            versions = fetched
            if app.preferredVersionId == nil {
                app.preferredVersionId = fetched.first?.id
            }
        } catch {
            // Picker stays empty; Sync still works against the latest editable version.
        }
    }

    // MARK: - Markdown import / export

    private func importMarkdown() {
        guard let latest = sortedSnapshots.first else {
            importSucceeded = false
            importMessage = "Sync metadata first, then import into the latest snapshot."
            return
        }
        guard let urls = MetadataMarkdownImporter.presentOpenPanel(), !urls.isEmpty else { return }

        do {
            var allBlocks: [MetadataMarkdownImporter.LocaleBlock] = []
            for url in urls {
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                allBlocks.append(contentsOf: try MetadataMarkdownImporter.parse(fileURL: url))
            }

            // Last block wins if the same locale appears more than once.
            var merged: [String: MetadataMarkdownImporter.LocaleBlock] = [:]
            for block in allBlocks {
                merged[block.locale] = block
            }

            let result = MetadataMarkdownImporter.apply(
                blocks: Array(merged.values),
                to: latest
            )
            selectedSnapshot = latest
            importSucceeded = !result.updatedLocales.isEmpty

            var lines: [String] = []
            if !result.updatedLocales.isEmpty {
                lines.append("Updated \(result.updatedLocales.count) locale(s): \(result.updatedLocales.joined(separator: ", ")).")
            }
            if !result.unknownLocales.isEmpty {
                lines.append("Skipped unknown locale(s) not in this snapshot: \(result.unknownLocales.joined(separator: ", ")). Sync first if you need them.")
            }
            if result.updatedLocales.isEmpty && result.unknownLocales.isEmpty {
                lines.append("No fields were updated. Check that your ## sections have content.")
            }
            importMessage = lines.joined(separator: "\n")
        } catch {
            importSucceeded = false
            importMessage = error.localizedDescription
        }
    }

    private func exportCurrentMarkdown() {
        guard let snapshot = selectedSnapshot ?? sortedSnapshots.first else { return }
        let markdown = MetadataMarkdownImporter.exportMarkdown(from: snapshot)
        let name = "\(app.name.isEmpty ? "app" : app.name)-metadata.md"
            .replacingOccurrences(of: "/", with: "-")
        _ = MetadataMarkdownImporter.presentSavePanel(defaultName: name, contents: markdown)
    }

    private func downloadSampleTemplate() {
        let markdown = MetadataMarkdownImporter.bundledSampleMarkdown()
        _ = MetadataMarkdownImporter.presentSavePanel(
            defaultName: "stor-metadata-sample.md",
            contents: markdown
        )
    }

    // MARK: - Push

    /// Validates first, then asks for confirmation. Pushing overwrites the live listing,
    /// so it should never happen as the direct result of a single click.
    private func confirmPush() {
        guard let latest = sortedSnapshots.first else { return }

        let violations = latest.limitViolations
        guard violations.isEmpty else {
            pushError = "Fix these fields before pushing:\n"
                + violations.map { "• " + $0.description }.joined(separator: "\n")
            return
        }
        guard !latest.pushableLocalizations.isEmpty else {
            pushError = "No locales have App Store Connect IDs yet. Sync before pushing."
            return
        }
        showPushConfirmation = true
    }

    private var pushConfirmationMessage: String {
        guard let latest = sortedSnapshots.first else { return "" }
        let count = latest.pushableLocalizations.count
        let version = latest.versionString.map { " for version \($0)" } ?? ""
        var message = "This overwrites the live App Store Connect listing"
            + "\(version) across \(count) locale\(count == 1 ? "" : "s"). This cannot be undone from Stor."
        let skipped = latest.unpushableLocales
        if !skipped.isEmpty {
            message += "\n\nNot pushed (never synced): \(skipped.joined(separator: ", "))."
        }
        return message
    }

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

            var pushed: [String] = []
            var failed: [(locale: String, message: String)] = []

            // Each locale is pushed independently: a failure part-way through should not
            // hide the fact that earlier locales are already live.
            for loc in latest.pushableLocalizations.sorted(by: { $0.locale < $1.locale }) {
                do {
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
                    pushed.append(loc.locale)
                } catch {
                    failed.append((loc.locale, error.localizedDescription))
                }
            }

            if failed.isEmpty {
                pushResult = "Pushed \(pushed.count) locale\(pushed.count == 1 ? "" : "s") to App Store Connect."
            } else {
                let detail = failed.map { "• \($0.locale): \($0.message)" }.joined(separator: "\n")
                pushError = pushed.isEmpty
                    ? "Nothing was pushed.\n\(detail)"
                    : "Pushed \(pushed.joined(separator: ", ")). These failed and are unchanged:\n\(detail)"
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
                let snapshot = try await MetadataSyncService.sync(
                    app: app,
                    versionId: app.preferredVersionId,
                    credentials: credentials,
                    context: modelContext
                )
                selectedSnapshot = snapshot
                await loadVersions()
            } catch {
                syncError = error.localizedDescription
            }
        }
    }
}

// MARK: - Snapshot timeline row

private struct SnapshotTimelineRow: View {
    let snapshot: MetadataSnapshot
    let isLatest: Bool
    let isSelected: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            timelineRail

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(snapshot.capturedAt, format: .dateTime.month(.abbreviated).day().year())
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)

                    if isLatest {
                        Text("Latest")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor, in: Capsule())
                    }
                }

                HStack(spacing: 6) {
                    Text(snapshot.capturedAt, format: .dateTime.hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()

                    if let v = snapshot.versionString {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text("v\(v)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    if let state = snapshot.versionState {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(ASCAppStoreVersion.displayName(for: state))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(snapshot.isVersionEditable ? Color.green : Color.secondary)
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, 8)

            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
        .padding(.trailing, 4)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            }
        }
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    private var timelineRail: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(isSelected || isLatest ? Color.accentColor : Color.primary.opacity(0.18))
                    .frame(width: 8, height: 8)
                if isSelected {
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 3)
                        .frame(width: 14, height: 14)
                }
            }
            .frame(width: 14, height: 14)
            .padding(.top, 10)

            if !isLast {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 14)
    }
}

