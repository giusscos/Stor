import SwiftUI
import SwiftData

struct KeywordsTabView: View {
    @Bindable var app: AppRecord
    @Environment(\.modelContext) private var modelContext

    @State private var showAddKeyword       = false
    @State private var showConnectAds       = false
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

    private let baseCountries = ["US", "GB", "DE", "FR", "IT", "ES", "JP", "CA", "AU", "BR"]

    private var countries: [String] {
        let fromKeywords = Set(app.trackedKeywords.map(\.country))
        return Array(Set(baseCountries).union(fromKeywords)).sorted()
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
                searchAdsCredentials: searchAdsCredentials
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
            Text("Connect Apple Search Ads to fetch keyword popularity scores (0–100).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Connect") { showConnectAds = true }
                .buttonStyle(.borderedProminent)
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

                    if searchAdsCredentials != nil {
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
                        .help("Fetch popularity scores from Apple Search Ads")
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

        let added = insertKeywords(source.terms, locale: source.locale, country: selectedCountry)
        let skipped = source.terms.count - added
        importMessage = importSummary(added: added, skipped: skipped, detail: source.locale)
    }

    private func importSelectedSources(_ sources: [(locale: String, country: String, terms: [String])]) {
        guard !sources.isEmpty else {
            importMessage = "No languages selected."
            return
        }

        var added = 0
        var considered = 0
        var countriesHit = Set<String>()
        for source in sources {
            considered += source.terms.count
            let count = insertKeywords(source.terms, locale: source.locale, country: source.country)
            if count > 0 { countriesHit.insert(source.country) }
            added += count
        }
        let skipped = considered - added
        let localeCount = sources.count
        let detail = "\(localeCount) locale\(localeCount == 1 ? "" : "s")"
            + (countriesHit.isEmpty ? "" : " · \(countriesHit.count) countr\(countriesHit.count == 1 ? "y" : "ies")")
        importMessage = importSummary(added: added, skipped: skipped, detail: detail)
    }

    @discardableResult
    private func insertKeywords(_ terms: [String], locale: String, country: String) -> Int {
        let existing = Set(
            app.trackedKeywords
                .filter { $0.country.caseInsensitiveCompare(country) == .orderedSame }
                .map { $0.term.lowercased() }
        )
        var added = 0
        var seen = existing
        for term in terms {
            let key = term.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            let kw = TrackedKeyword(term: term, locale: locale, country: country)
            kw.app = app
            app.trackedKeywords.append(kw)
            modelContext.insert(kw)
            added += 1
        }
        return added
    }

    private func importSummary(added: Int, skipped: Int, detail: String) -> String {
        if added == 0 {
            return skipped == 0
                ? "No keywords to import."
                : "All \(skipped) listing keyword\(skipped == 1 ? "" : "s") are already tracked."
        }
        if skipped == 0 {
            return "Added \(added) keyword\(added == 1 ? "" : "s") from \(detail)."
        }
        return "Added \(added) keyword\(added == 1 ? "" : "s") from \(detail). Skipped \(skipped) duplicate\(skipped == 1 ? "" : "s")."
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

    private func countryCode(fromLocale locale: String) -> String? {
        let parts = locale.replacingOccurrences(of: "_", with: "-").split(separator: "-").map(String.init)
        guard let region = parts.last, region.count == 2, region.allSatisfy(\.isLetter) else {
            return nil
        }
        // Script codes like "Hans" are 4 letters; 2-letter suffix is the region.
        return region.uppercased()
    }

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
    let onDelete: () -> Void

    var latestRanking: KeywordRanking? {
        keyword.rankingHistory.sorted { $0.checkedAt > $1.checkedAt }.first
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
                        .frame(width: 110, height: 14, alignment: .leading)
                } else if let score = keyword.popularityScore {
                    PopularityBar(score: score).frame(width: 110)
                } else {
                    Text("—")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .frame(width: 110, alignment: .leading)
                }
            }

            Group {
                if let updated = keyword.popularityLastUpdated {
                    Text(updated, style: .relative)
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .frame(width: 110, alignment: .leading)
                } else {
                    Text("Never")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .frame(width: 110, alignment: .leading)
                }
            }

            Group {
                if isCheckingRankings && latestRanking == nil {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 70, height: 14, alignment: .leading)
                } else if let pos = latestRanking?.position {
                    Text("#\(pos)")
                        .font(.body)
                        .fontWeight(.medium)
                        .monospacedDigit()
                        .foregroundStyle(pos <= 10 ? .green : .primary)
                        .frame(width: 70, alignment: .leading)
                } else if latestRanking != nil {
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
