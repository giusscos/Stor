import SwiftUI
import SwiftData

struct CompetitorScanView: View {
    @Bindable var app: AppRecord
    let country: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTrackId: Int64?
    @State private var hits: [CompetitorScanHit] = []
    @State private var isScanning = false
    @State private var progress: String?
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    private var competitors: [CompetitorApp] {
        app.competitors.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var selectedCompetitor: CompetitorApp? {
        competitors.first { $0.trackId == selectedTrackId }
    }

    private var trackedKeys: Set<String> {
        Set(
            app.trackedKeywords
                .filter { $0.country.caseInsensitiveCompare(country) == .orderedSame }
                .map { $0.term.lowercased() }
        )
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                pickerBar
                Divider()
                if isScanning {
                    VStack(spacing: 10) {
                        ProgressView()
                            .padding(.top, 48)
                        Text(progress ?? "Scanning…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.horizontal, 24)
                } else if competitors.isEmpty {
                    emptyCompetitors
                } else if hits.isEmpty {
                    emptyHits
                } else {
                    resultsList
                }
            }
            .navigationTitle("Keywords They Rank For")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await runScan() }
                    } label: {
                        Label("Scan", systemImage: "dot.radiowaves.left.and.right")
                    }
                    .disabled(isScanning || selectedTrackId == nil)
                }
            }
            .alert("Scan Failed", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .onAppear {
                if selectedTrackId == nil {
                    selectedTrackId = competitors.first?.trackId
                    loadStoredHits()
                }
            }
        }
        .frame(minWidth: 560, minHeight: 480)
    }

    private var pickerBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Picker("Competitor", selection: $selectedTrackId) {
                    ForEach(competitors) { competitor in
                        Text(competitor.name).tag(Optional(competitor.trackId))
                    }
                }
                .onChange(of: selectedTrackId) { _, _ in
                    loadStoredHits()
                }

                Spacer()

                Text(country)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("Seeds from their live listing keywords, then checks App Store search. Apple Ads expands the seed list when you’re signed in. This is local and incomplete compared to a crowd-sourced ASO database.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private var emptyCompetitors: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.2")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
                .padding(.top, 48)
            Text("No Competitors")
                .font(.headline)
            Text("Save competitors from Discover first.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var emptyHits: some View {
        VStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
                .padding(.top, 48)
            Text("No Scan Yet")
                .font(.headline)
            Text("Scan this competitor to see which of their listing terms they actually rank for.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 24)
    }

    private var resultsList: some View {
        List {
            ForEach(hits) { hit in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(hit.term)
                            .fontWeight(.medium)
                        Text(hit.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let position = hit.position {
                        Text("#\(position)")
                            .fontWeight(.medium)
                            .monospacedDigit()
                            .foregroundStyle(position <= 10 ? .green : .primary)
                            .frame(width: 52, alignment: .trailing)
                    } else {
                        Text(">200")
                            .foregroundStyle(.tertiary)
                            .frame(width: 52, alignment: .trailing)
                    }
                    Button("Add") {
                        addHit(hit)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(trackedKeys.contains(hit.term.lowercased()) || hit.position == nil)
                }
            }
        }
        .listStyle(.inset)
    }

    private func loadStoredHits() {
        guard let competitor = selectedCompetitor else {
            hits = []
            return
        }
        let latestByTerm = Dictionary(
            grouping: competitor.rankingHistory.filter {
                $0.country.caseInsensitiveCompare(country) == .orderedSame
            },
            by: { $0.term.lowercased() }
        )
        hits = latestByTerm.values.compactMap { group in
            guard let latest = group.max(by: { $0.checkedAt < $1.checkedAt }) else { return nil }
            return CompetitorScanHit(
                term: latest.term,
                source: "Last scan",
                position: latest.position
            )
        }
        .sorted { lhs, rhs in
            switch (lhs.position, rhs.position) {
            case let (l?, r?): return l < r
            case (_?, nil): return true
            case (nil, _?): return false
            default: return lhs.term < rhs.term
            }
        }
        statusMessage = hits.isEmpty ? nil : "\(hits.filter(\.isRanking).count) ranking of \(hits.count) checked."
    }

    private func runScan() async {
        guard let competitor = selectedCompetitor else { return }
        isScanning = true
        errorMessage = nil
        progress = nil
        defer { isScanning = false }

        let hasAds = (try? KeychainService.shared.loadAppleAdsWebSession()) != nil
        var adamId = app.adamId
        if hasAds, adamId == nil {
            adamId = try? await AppleAdsWebClient.shared.resolveAdamId(bundleId: app.bundleId)
            if let adamId { app.adamId = adamId }
        }

        do {
            hits = try await CompetitorKeywordScanner.scan(
                competitor: competitor,
                country: country,
                adamId: adamId,
                hasAdsSession: hasAds,
                context: modelContext,
                onProgress: { progress = $0 }
            )
            let ranked = hits.filter(\.isRanking).count
            statusMessage = "\(ranked) ranking of \(hits.count) checked."
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addHit(_ hit: CompetitorScanHit) {
        let result = app.insertKeywords([hit.term], locale: app.primaryLocale, country: country, into: modelContext)
        statusMessage = result.summary(detail: competitorName)
    }

    private var competitorName: String {
        selectedCompetitor?.name ?? "scan"
    }
}
