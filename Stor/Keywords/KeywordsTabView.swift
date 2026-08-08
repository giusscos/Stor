import SwiftUI
import SwiftData

struct KeywordsTabView: View {
    @Bindable var app: AppRecord
    @Environment(\.modelContext) private var modelContext

    @State private var showAddKeyword       = false
    @State private var showConnectAds       = false
    @State private var selectedCountry      = "US"
    @State private var searchText           = ""
    @State private var isRefreshing         = false
    @State private var isCheckingRankings   = false
    @State private var asyncError: String?
    @State private var searchAdsCredentials: SearchAdsCredentials?

    private let countries = ["US", "GB", "DE", "FR", "IT", "ES", "JP", "CA", "AU", "BR"]

    var filteredKeywords: [TrackedKeyword] {
        let byCountry = app.trackedKeywords.filter { $0.country == selectedCountry }
        let terms = searchText.trimmingCharacters(in: .whitespaces)
        guard !terms.isEmpty else { return byCountry.sorted { $0.term < $1.term } }
        return byCountry
            .filter { $0.term.localizedCaseInsensitiveContains(terms) }
            .sorted { $0.term < $1.term }
    }

    var body: some View {
        VStack(spacing: 0) {
            if searchAdsCredentials == nil {
                searchAdsBanner
            }
            controlsBar
            Divider()
            if filteredKeywords.isEmpty {
                emptyState
            } else {
                keywordTable
            }
        }
        .onAppear {
            searchAdsCredentials = try? KeychainService.shared.loadSearchAds()
        }
        .sheet(isPresented: $showAddKeyword) {
            AddKeywordView(app: app, defaultCountry: selectedCountry)
        }
        .sheet(isPresented: $showConnectAds) {
            AddSearchAdsKeyView { creds in
                searchAdsCredentials = creds
            }
        }
        .alert("Error", isPresented: Binding(
            get: { asyncError != nil },
            set: { if !$0 { asyncError = nil } }
        )) {
            Button("OK") { asyncError = nil }
        } message: {
            Text(asyncError ?? "")
        }
    }

    // MARK: - Views

    private var searchAdsBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "chart.bar.xaxis")
                .foregroundStyle(.blue)
            Text("Connect Apple Search Ads to fetch keyword popularity scores (0–100).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Connect") { showConnectAds = true }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.blue.opacity(0.06))
    }

    private var controlsBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search keywords…", text: $searchText)
                    .textFieldStyle(.plain)
            }
            .padding(8)
            .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: 260)

            Picker("Country", selection: $selectedCountry) {
                ForEach(countries, id: \.self) { cc in
                    Text(Locale.current.localizedString(forRegionCode: cc) ?? cc).tag(cc)
                }
            }
            .frame(width: 150)

            Spacer()

            if searchAdsCredentials != nil {
                Button(action: refreshPopularity) {
                    if isRefreshing {
                        ProgressView().scaleEffect(0.7)
                    } else {
                        Label("Refresh Popularity", systemImage: "arrow.clockwise")
                    }
                }
                .buttonStyle(.bordered)
                .disabled(isRefreshing || filteredKeywords.isEmpty)
                .help("Fetch popularity scores from Apple Search Ads")
            }

            Button(action: checkRankings) {
                if isCheckingRankings {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Label("Check Rankings", systemImage: "list.number")
                }
            }
            .buttonStyle(.bordered)
            .disabled(isCheckingRankings || filteredKeywords.isEmpty)
            .help("Check App Store search ranking positions via iTunes Search API")

            Button { showAddKeyword = true } label: {
                Label("Add Keywords", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var keywordTable: some View {
        List {
            Section {
                HStack(spacing: 0) {
                    Text("Keyword").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Popularity").frame(width: 110, alignment: .leading)
                    Text("Updated").frame(width: 110, alignment: .leading)
                    Text("Rank").frame(width: 70, alignment: .leading)
                    Color.clear.frame(width: 36)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }

            ForEach(filteredKeywords) { keyword in
                KeywordRow(keyword: keyword, isRefreshing: isRefreshing, isCheckingRankings: isCheckingRankings) {
                    modelContext.delete(keyword)
                }
            }
        }
        .listStyle(.inset)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
                .padding(.top, 48)
            Text("No Keywords")
                .font(.headline)
            Text("Add keywords to track their App Store ranking\nand monitor search trends.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add Keywords") { showAddKeyword = true }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 24)
    }

    // MARK: - Actions

    private func refreshPopularity() {
        guard let credentials = searchAdsCredentials else {
            showConnectAds = true
            return
        }
        isRefreshing = true
        asyncError = nil
        Task {
            defer { isRefreshing = false }
            do {
                try await SearchAdsAPIClient.shared.refreshPopularity(
                    keywords: filteredKeywords,
                    credentials: credentials
                )
            } catch {
                asyncError = error.localizedDescription
            }
        }
    }

    private func checkRankings() {
        isCheckingRankings = true
        asyncError = nil
        Task {
            defer { isCheckingRankings = false }
            do {
                for keyword in filteredKeywords {
                    let position = try await RankingChecker.shared.checkRanking(
                        bundleId: app.bundleId,
                        keyword: keyword.term,
                        country: keyword.country
                    )
                    let ranking = KeywordRanking(checkedAt: .now, position: position, country: keyword.country)
                    ranking.keyword = keyword
                    keyword.rankingHistory.append(ranking)
                    modelContext.insert(ranking)
                }
            } catch {
                asyncError = error.localizedDescription
            }
        }
    }
}

// MARK: - Row

private struct KeywordRow: View {
    let keyword: TrackedKeyword
    let isRefreshing: Bool
    let isCheckingRankings: Bool
    let onDelete: () -> Void

    var latestRanking: KeywordRanking? {
        keyword.rankingHistory.sorted { $0.checkedAt > $1.checkedAt }.first
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(keyword.term)
                .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if isRefreshing && keyword.popularityScore == nil {
                    ProgressView().scaleEffect(0.6)
                        .frame(width: 110, alignment: .leading)
                } else if let score = keyword.popularityScore {
                    PopularityBar(score: score).frame(width: 110)
                } else {
                    Text("—").foregroundStyle(.tertiary).frame(width: 110, alignment: .leading)
                }
            }

            Group {
                if let updated = keyword.popularityLastUpdated {
                    Text(updated, style: .relative)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .leading)
                } else {
                    Text("Never")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 110, alignment: .leading)
                }
            }

            Group {
                if isCheckingRankings && latestRanking == nil {
                    ProgressView().scaleEffect(0.6).frame(width: 70, alignment: .leading)
                } else if let pos = latestRanking?.position {
                    Text("#\(pos)")
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundStyle(pos <= 10 ? .green : .primary)
                        .frame(width: 70, alignment: .leading)
                } else if latestRanking != nil {
                    Text(">200")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 70, alignment: .leading)
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                        .frame(width: 70, alignment: .leading)
                }
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash").foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.borderless)
            .frame(width: 36)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Popularity bar

private struct PopularityBar: View {
    let score: Int

    var barColor: Color {
        switch score {
        case 0..<30: return .red
        case 30..<60: return .orange
        case 60..<80: return .yellow
        default:      return .green
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(.quinary)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor.gradient)
                        .frame(width: geo.size.width * CGFloat(score) / 100)
                }
            }
            .frame(height: 8)

            Text("\(score)")
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
        }
    }
}
