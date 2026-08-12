import SwiftUI
import SwiftData

struct KeywordsTabView: View {
    @Bindable var app: AppRecord
    @Environment(\.modelContext) private var modelContext

    @State private var showAddKeyword       = false
    @State private var showConnectAds       = false
    @State private var showAdsLogin         = false
    @State private var showDiscover         = false
    @State private var showCompare          = false
    @State private var showSuggest          = false
    @State private var showImportLanguages  = false
    @State private var selectedCountry      = "US"
    @State private var searchText           = ""
    @State private var isRefreshing         = false
    @State private var isCheckingRankings   = false
    @State private var asyncError: String?
    @State private var importMessage: String?
    @State private var searchAdsCredentials: SearchAdsCredentials?
    @State private var adsWebSession: AppleAdsWebSession?
    @State private var trendKeyword: TrackedKeyword?
    @State private var keywordPendingDeletion: TrackedKeyword?

    private var countries: [String] {
        let fromKeywords = Set(app.trackedKeywords.map(\.country))
        return Array(Set(KeywordCountries.all).union(fromKeywords)).sorted()
    }

    var filteredKeywords: [TrackedKeyword] {
        let byCountry = app.trackedKeywords.filter { $0.country == selectedCountry }
        let terms = searchText.trimmingCharacters(in: .whitespaces)
        guard !terms.isEmpty else { return byCountry.sorted { $0.term < $1.term } }
        return byCountry
            .filter { $0.term.localizedCaseInsensitiveContains(terms) }
            .sorted { $0.term < $1.term }
    }

    /// Latest listing snapshot, if any.
    private var latestSnapshot: MetadataSnapshot? {
        app.snapshots.sorted(by: { $0.capturedAt > $1.capturedAt }).first
    }

    /// Listing keywords from every localization that maps to a storefront country.
    private var listingKeywordSources: [(locale: String, country: String, terms: [String])] {
        guard let snapshot = latestSnapshot else { return [] }
        return snapshot.localizations.compactMap { localization in
            guard let country = countryCode(fromLocale: localization.locale) else { return nil }
            let terms = parseKeywordTerms(localization.keywords)
            guard !terms.isEmpty else { return nil }
            return (localization.locale, country, terms)
        }
        .sorted { $0.locale < $1.locale }
    }

    /// Comma-separated ASC keywords from the latest listing snapshot for the selected country.
    private var listingKeywordsForSelectedCountry: (locale: String, terms: [String])? {
        let matches = listingKeywordSources.filter {
            $0.country.caseInsensitiveCompare(selectedCountry) == .orderedSame
        }
        let source =
            matches.first(where: { $0.locale.caseInsensitiveCompare(app.primaryLocale) == .orderedSame })
            ?? matches.first
        guard let source else { return nil }
        return (source.locale, source.terms)
    }

    private var hasListingKeywords: Bool {
        !listingKeywordSources.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            if adsWebSession == nil {
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
            reloadAdsAuth()
        }
        .sheet(isPresented: $showAddKeyword) {
            AddKeywordView(app: app, defaultCountry: selectedCountry) { result in
                if result.skipped > 0 { importMessage = result.summary() }
            }
        }
        .sheet(isPresented: $showAdsLogin) {
            AppleAdsLoginView { session in
                adsWebSession = session
            }
        }
        .sheet(isPresented: $showConnectAds) {
            AddSearchAdsKeyView { creds in
                searchAdsCredentials = creds
            }
        }
        .sheet(isPresented: $showDiscover) {
            DiscoverKeywordView(app: app, country: selectedCountry)
        }
        .sheet(isPresented: $showCompare) {
            CompareCompetitorsView(
                app: app,
                country: selectedCountry,
                keywords: filteredKeywords
            )
        }
        .sheet(isPresented: $showSuggest) {
            SuggestKeywordsView(
                app: app,
                country: selectedCountry,
                hasAdsWebSession: adsWebSession != nil
            )
        }
        .sheet(isPresented: $showImportLanguages) {
            ImportLanguagesSheet(sources: listingKeywordSources) { selected in
                importSelectedSources(selected)
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
        .alert("Import from Listing", isPresented: Binding(
            get: { importMessage != nil },
            set: { if !$0 { importMessage = nil } }
        )) {
            Button("OK") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }

    // MARK: - Views

    private var searchAdsBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .foregroundStyle(.blue)
            Text("Sign in to Apple Ads to fetch keyword popularity scores (0–100).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Sign In") { showAdsLogin = true }
                .buttonStyle(.borderedProminent)
            if searchAdsCredentials == nil {
                Button("API Key…") { showConnectAds = true }
                    .buttonStyle(.bordered)
                    .help("Optional Campaign Management API credentials")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.blue.opacity(0.06))
    }

    private var controlsBar: some View {
        VStack(spacing: 0) {
            // Row 1: search + country + primary actions
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

                Menu {
                    ForEach(countries, id: \.self) { cc in
                        Button(Locale.current.localizedString(forRegionCode: cc) ?? cc) {
                            selectedCountry = cc
                        }
                    }
                } label: {
                    Text(Locale.current.localizedString(forRegionCode: selectedCountry) ?? selectedCountry)
                }
                .fixedSize()

                Spacer()

                Button { showImportLanguages = true } label: {
                    Label("Import", systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(!hasListingKeywords)
                .help("Import keywords from the latest listing snapshot")

                Button { showAddKeyword = true } label: {
                    Label("Add Keywords", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Divider()

            // Row 2: scrollable tool buttons
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Button { showDiscover = true } label: {
                        Label("Discover", systemImage: "binoculars")
                    }
                    .buttonStyle(.bordered)
                    .help("See top App Store results for a keyword and save competitors")

                    Button { showCompare = true } label: {
                        Label("Compare", systemImage: "person.2")
                    }
                    .buttonStyle(.bordered)
                    .help("Compare your rankings against saved competitors")

                    Button { showSuggest = true } label: {
                        Label("Suggest", systemImage: "lightbulb")
                    }
                    .buttonStyle(.bordered)
                    .help("Suggest keywords from Search Ads and competitor listings")

                    if adsWebSession != nil {
                        Button(action: refreshPopularity) {
                            Label {
                                Text("Refresh Popularity")
                            } icon: {
                                if isRefreshing {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Image(systemName: "arrow.clockwise")
                                }
                            }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isRefreshing || filteredKeywords.isEmpty)
                        .help("Fetch popularity scores from Apple Ads")
                    }

                    Button(action: checkRankings) {
                        Label {
                            Text("Check Rankings")
                        } icon: {
                            if isCheckingRankings {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "list.number")
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isCheckingRankings || filteredKeywords.isEmpty)
                    .help("Check App Store search ranking positions via iTunes Search API")
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    private var keywordTable: some View {
        List {
            Section {
                HStack(spacing: 0) {
                    Text("Keyword").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Popularity").frame(width: 130, alignment: .leading)
                    Text("Updated").frame(width: 88, alignment: .leading)
                    Text("Rank").frame(width: 70, alignment: .leading)
                    Text("Trend").frame(width: 80, alignment: .leading)
                    Color.clear.frame(width: 36)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
            }

            ForEach(filteredKeywords) { keyword in
                KeywordRow(
                    keyword: keyword,
                    isRefreshing: isRefreshing,
                    isCheckingRankings: isCheckingRankings,
                    onShowTrend: { trendKeyword = keyword },
                    onDelete: { keywordPendingDeletion = keyword }
                )
            }
        }
        .listStyle(.inset)
        .sheet(item: $trendKeyword) { keyword in
            KeywordTrendSheet(keyword: keyword)
        }
        .confirmationDialog(
            "Stop tracking “\(keywordPendingDeletion?.term ?? "")”?",
            isPresented: Binding(
                get: { keywordPendingDeletion != nil },
                set: { if !$0 { keywordPendingDeletion = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Keyword", role: .destructive) {
                if let keyword = keywordPendingDeletion { modelContext.delete(keyword) }
                keywordPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) { keywordPendingDeletion = nil }
        } message: {
            Text("Its popularity scores and ranking history are deleted too.")
        }
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
            HStack(spacing: 10) {
                if listingKeywordsForSelectedCountry != nil {
                    Button("Import from Listing") { importFromListing() }
                        .buttonStyle(.bordered)
                }
                if hasListingKeywords {
                    Button("Import Languages…") { showImportLanguages = true }
                        .buttonStyle(.bordered)
                }
                Button("Add Keywords") { showAddKeyword = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 24)
    }

    // MARK: - Actions

    private func importFromListing() {
        guard let source = listingKeywordsForSelectedCountry else {
            importMessage = "No listing keywords found for \(selectedCountry). Sync the Listing tab first."
            return
        }

        let result = app.insertKeywords(
            source.terms,
            locale: source.locale,
            country: selectedCountry,
            into: modelContext
        )
        importMessage = result.summary(detail: source.locale)
    }

    private func importSelectedSources(_ sources: [(locale: String, country: String, terms: [String])]) {
        guard !sources.isEmpty else {
            importMessage = "No languages selected."
            return
        }

        var total = AppRecord.KeywordInsertResult()
        var countriesHit = Set<String>()
        for source in sources {
            let result = app.insertKeywords(
                source.terms,
                locale: source.locale,
                country: source.country,
                into: modelContext
            )
            if result.added > 0 { countriesHit.insert(source.country) }
            total.added += result.added
            total.skipped += result.skipped
        }
        let localeCount = sources.count
        let detail = "\(localeCount) locale\(localeCount == 1 ? "" : "s")"
            + (countriesHit.isEmpty ? "" : " · \(countriesHit.count) countr\(countriesHit.count == 1 ? "y" : "ies")")
        importMessage = total.summary(detail: detail)
    }

    private func parseKeywordTerms(_ raw: String?) -> [String] {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return []
        }
        return raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func reloadAdsAuth() {
        adsWebSession = try? KeychainService.shared.loadAppleAdsWebSession()
        searchAdsCredentials = try? KeychainService.shared.loadSearchAds()
    }

    private func resolveAdamId() async throws -> Int64 {
        if let cached = app.adamId { return cached }
        let id = try await AppleAdsWebClient.shared.resolveAdamId(bundleId: app.bundleId)
        await MainActor.run { app.adamId = id }
        return id
    }

    private func refreshPopularity() {
        guard adsWebSession != nil else {
            showAdsLogin = true
            return
        }
        isRefreshing = true
        asyncError = nil
        Task {
            defer { isRefreshing = false }
            do {
                let adamId = try await resolveAdamId()
                let outcome = try await SearchAdsAPIClient.shared.refreshPopularity(
                    keywords: filteredKeywords,
                    adamId: adamId
                )
                if let summary = outcome.summary {
                    asyncError = summary
                }
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
                for (index, keyword) in filteredKeywords.enumerated() {
                    if index > 0 {
                        try await Task.sleep(nanoseconds: RankingChecker.batchDelayNanoseconds)
                    }
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

// MARK: - Import Languages Sheet

private struct ImportLanguagesSheet: View {
    let sources: [(locale: String, country: String, terms: [String])]
    let onImport: ([(locale: String, country: String, terms: [String])]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selectedLocales: Set<String>

    init(
        sources: [(locale: String, country: String, terms: [String])],
        onImport: @escaping ([(locale: String, country: String, terms: [String])]) -> Void
    ) {
        self.sources = sources
        self.onImport = onImport
        _selectedLocales = State(initialValue: Set(sources.map(\.locale)))
    }

    private var allSelected: Bool { selectedLocales.count == sources.count }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Import Languages")
                        .font(.headline)
                    Text("Choose which locales to import keywords from")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(allSelected ? "Deselect All" : "Select All") {
                    if allSelected {
                        selectedLocales.removeAll()
                    } else {
                        selectedLocales = Set(sources.map(\.locale))
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(20)

            Divider()

            // Locale list
            List(sources, id: \.locale) { source in
                HStack(spacing: 12) {
                    Image(systemName: selectedLocales.contains(source.locale)
                          ? "checkmark.circle.fill"
                          : "circle")
                        .foregroundStyle(selectedLocales.contains(source.locale) ? .blue : .secondary)
                        .font(.system(size: 18))
                        .onTapGesture { toggle(source.locale) }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(localeName(source.locale))
                            .font(.body)
                        Text("\(source.country) · \(source.terms.count) keyword\(source.terms.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { toggle(source.locale) }
                .padding(.vertical, 2)
            }
            .listStyle(.inset)

            Divider()

            // Footer
            HStack {
                Text("\(selectedLocales.count) of \(sources.count) selected")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Import") {
                    let chosen = sources.filter { selectedLocales.contains($0.locale) }
                    dismiss()
                    onImport(chosen)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedLocales.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(minWidth: 400, minHeight: 360)
    }

    private func toggle(_ locale: String) {
        if selectedLocales.contains(locale) {
            selectedLocales.remove(locale)
        } else {
            selectedLocales.insert(locale)
        }
    }

    private func localeName(_ locale: String) -> String {
        Locale.current.localizedString(forIdentifier: locale) ?? locale
    }
}

// MARK: - Row

private struct KeywordRow: View {
    let keyword: TrackedKeyword
    let isRefreshing: Bool
    let isCheckingRankings: Bool
    let onShowTrend: () -> Void
    let onDelete: () -> Void

    /// Computed once per body evaluation and shared by the rank cell and the sparkline,
    /// rather than re-sorting the history for each.
    private var points: [RankPoint] { keyword.rankPoints }

    /// Compact relative time for the Updated column (`Just now`, `12m`, `3h`, `2d`).
    private static func compactRelative(from date: Date, now: Date = .now) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 60 { return "Just now" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 14 { return "\(days)d ago" }
        return date.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(keyword.term)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if isRefreshing && keyword.popularityScore == nil {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 130, height: 14, alignment: .leading)
                } else if let score = keyword.popularityScore {
                    PopularityBar(score: score)
                        .frame(width: 130, alignment: .leading)
                } else {
                    Text("—")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .frame(width: 130, alignment: .leading)
                }
            }

            Group {
                if let updated = keyword.popularityLastUpdated {
                    Text(Self.compactRelative(from: updated))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(width: 88, alignment: .leading)
                        .help(updated.formatted(date: .abbreviated, time: .shortened))
                } else {
                    Text("Never")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(width: 88, alignment: .leading)
                }
            }

            Group {
                let latest = points.last
                if isCheckingRankings && latest == nil {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 70, height: 14, alignment: .leading)
                } else if let pos = latest?.position {
                    Text("#\(pos)")
                        .font(.body)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundStyle(pos <= 10 ? .green : .primary)
                        .frame(width: 70, alignment: .leading)
                } else if latest != nil {
                    Text(">200")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .frame(width: 70, alignment: .leading)
                } else {
                    Text("—")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .frame(width: 70, alignment: .leading)
                }
            }

            Button(action: onShowTrend) {
                RankSparkline(points: points)
                    .frame(width: 72, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 80, alignment: .leading)
            .help("Show ranking history")

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash").foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.borderless)
            .frame(width: 36)
            .accessibilityLabel("Delete keyword \(keyword.term)")
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Show Ranking History", action: onShowTrend)
            Divider()
            Button("Delete Keyword", role: .destructive, action: onDelete)
        }
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
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(.quinary)
                    RoundedRectangle(cornerRadius: 4)
                        .fill(barColor.gradient)
                        .frame(width: geo.size.width * CGFloat(min(100, max(0, score))) / 100)
                }
            }
            .frame(height: 8)

            Text("\(score)")
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
                .help("Popularity \(score)")
        }
        .padding(.trailing, 12)
    }
}
