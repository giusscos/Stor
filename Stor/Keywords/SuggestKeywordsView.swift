import SwiftUI
import SwiftData

struct KeywordSuggestion: Identifiable, Hashable {
    var id: String { term.lowercased() }
    let term: String
    let source: String
    var popularity: Int?
}

struct SuggestKeywordsView: View {
    @Bindable var app: AppRecord
    let country: String
    let hasAdsWebSession: Bool

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var suggestions: [KeywordSuggestion] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?
    @State private var showAdsLogin = false
    @State private var adsSessionActive: Bool

    init(app: AppRecord, country: String, hasAdsWebSession: Bool) {
        self.app = app
        self.country = country
        self.hasAdsWebSession = hasAdsWebSession
        _adsSessionActive = State(initialValue: hasAdsWebSession)
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
                header
                Divider()
                if isLoading {
                    VStack {
                        ProgressView("Gathering suggestions…")
                            .padding(.top, 48)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if suggestions.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "lightbulb")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 48)
                        Text("No Suggestions Yet")
                            .font(.headline)
                        Text(emptyDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if !adsSessionActive {
                            Button("Sign in to Apple Ads…") { showAdsLogin = true }
                                .buttonStyle(.borderedProminent)
                                .padding(.top, 8)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, 24)
                } else {
                    suggestionList
                }
            }
            .navigationTitle("Suggest")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await loadSuggestions() }
                    } label: {
                        if isLoading {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(isLoading)
                }
            }
            .alert("Notice", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
            .sheet(isPresented: $showAdsLogin) {
                AppleAdsLoginView { _ in
                    adsSessionActive = true
                    Task { await loadSuggestions() }
                }
            }
            .task {
                await loadSuggestions()
            }
        }
        .frame(minWidth: 520, minHeight: 480)
    }

    private var emptyDescription: String {
        if !adsSessionActive && app.competitors.isEmpty {
            return "Sync listing metadata, save competitors, or sign in to Apple Ads, then refresh."
        }
        if !adsSessionActive {
            return "No related terms found. Sign in to Apple Ads to expand from your best seeds."
        }
        return "No new terms found. Try more specific tracked keywords or save competitors."
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Suggestions for \(Locale.current.localizedString(forRegionCode: country) ?? country)")
                .font(.subheadline)
            Text("Ranked by fit with your listing, then popularity. From your metadata, related App Store titles, Apple Ads, and competitors.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var suggestionList: some View {
        List {
            ForEach(suggestions) { suggestion in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.term)
                            .fontWeight(.medium)
                        Text(suggestion.source)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let score = suggestion.popularity {
                        ScoreBadge(value: KeywordScorer.opportunity(
                            popularity: score,
                            difficulty: 0,
                            rank: nil
                        ))
                    } else {
                        ScoreBadge(value: nil)
                    }
                    Button("Add") {
                        addSuggestion(suggestion)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(trackedKeys.contains(suggestion.term.lowercased()))
                }
            }
        }
        .listStyle(.inset)
    }

    private func loadSuggestions() async {
        isLoading = true
        errorMessage = nil
        statusMessage = nil
        defer { isLoading = false }

        var collected: [String: KeywordSuggestion] = [:]
        var softError: String?

        let session = try? KeychainService.shared.loadAppleAdsWebSession()
        let sessionOK = session.map { !$0.isEmpty } ?? false
        adsSessionActive = sessionOK

        let context = await listingContext()
        let seeds = KeywordSuggestionEngine.expansionSeeds(from: context)

        mergeListingTerms(from: context, into: &collected)

        do {
            try await harvestRelatedAppTitles(seeds: seeds, into: &collected)
        } catch is CancellationError {
            return
        } catch {
            softError = softError ?? error.localizedDescription
        }

        var adamId: Int64?
        if sessionOK {
            do {
                if let cached = app.adamId {
                    adamId = cached
                } else {
                    let resolved = try await AppleAdsWebClient.shared.resolveAdamId(bundleId: app.bundleId)
                    adamId = resolved
                    await MainActor.run { app.adamId = resolved }
                }
            } catch {
                softError = error.localizedDescription
            }
        }

        if sessionOK, let adamId {
            for seed in seeds {
                do {
                    try Task.checkCancellation()
                    let rows = try await SearchAdsAPIClient.shared.fetchRecommendations(
                        seed: seed,
                        country: country,
                        adamId: adamId,
                        limit: 15
                    )
                    for row in rows {
                        merge(
                            term: row.text,
                            source: "Apple Ads · from “\(seed)”",
                            popularity: row.score,
                            into: &collected
                        )
                    }
                } catch is CancellationError {
                    return
                } catch {
                    softError = softError ?? error.localizedDescription
                }
            }
        }

        for competitor in app.competitors {
            do {
                try Task.checkCancellation()
                var lookup = try await ITunesLookupClient.shared.lookup(bundleId: competitor.bundleId)
                if lookup == nil {
                    lookup = try await ITunesLookupClient.shared.lookup(trackId: competitor.trackId)
                }
                guard let lookup else { continue }
                let terms = ITunesLookupClient.shared.suggestionTerms(from: lookup)
                for term in terms.prefix(30) {
                    merge(
                        term: term,
                        source: "Competitor · \(competitor.name)",
                        popularity: nil,
                        into: &collected
                    )
                }
            } catch is CancellationError {
                return
            } catch {
                softError = softError ?? error.localizedDescription
            }
        }

        if sessionOK, let adamId {
            let missing = collected.values
                .filter { $0.popularity == nil }
                .map(\.term)
            if !missing.isEmpty {
                if let scores = try? await AppleAdsWebClient.shared.fetchPopularities(
                    keywords: missing,
                    adamId: adamId,
                    country: country
                ) {
                    for key in collected.keys {
                        guard var item = collected[key], item.popularity == nil else { continue }
                        if let score = scores[key] {
                            item.popularity = score
                            collected[key] = item
                        }
                    }
                }
            }
        }

        let ranked = KeywordSuggestionEngine.rank(
            collected.values.map {
                KeywordSuggestionEngine.Candidate(term: $0.term, source: $0.source, popularity: $0.popularity)
            },
            context: context
        )
        suggestions = ranked.map {
            KeywordSuggestion(term: $0.term, source: $0.source, popularity: $0.popularity)
        }
        statusMessage = suggestions.isEmpty
            ? nil
            : "\(suggestions.count) suggestion\(suggestions.count == 1 ? "" : "s")"
        if let softError, !suggestions.isEmpty {
            statusMessage = (statusMessage ?? "") + " · Ads: \(softError.prefix(80))"
        } else if let softError, suggestions.isEmpty {
            errorMessage = softError
        }
    }

    private func listingContext() async -> KeywordSuggestionEngine.ListingContext {
        let localization = app.listingLocalization(matchingCountry: country)
        var name = localization?.appName ?? app.name
        var subtitle = localization?.subtitle
        var keywords = KeywordBudget.parse(localization?.keywords ?? "")
        var description = localization?.appDescription

        if localization == nil, let lookup = try? await ITunesLookupClient.shared.lookup(bundleId: app.bundleId) {
            name = lookup.name
            subtitle = lookup.subtitle ?? subtitle
            if keywords.isEmpty, let raw = lookup.keywords {
                keywords = KeywordBudget.parse(raw)
            }
            description = lookup.description ?? description
        }

        let tracked = app.trackedKeywords
            .filter { $0.country.caseInsensitiveCompare(country) == .orderedSame }
            .map {
                KeywordSuggestionEngine.TrackedSeed(
                    term: $0.term,
                    popularity: $0.popularityScore,
                    rank: $0.rankPoints.last?.position
                )
            }

        return KeywordSuggestionEngine.ListingContext(
            appName: name,
            subtitle: subtitle,
            keywords: keywords,
            description: description,
            tracked: tracked
        )
    }

    private func mergeListingTerms(
        from context: KeywordSuggestionEngine.ListingContext,
        into collected: inout [String: KeywordSuggestion]
    ) {
        for term in context.keywords {
            merge(term: term, source: "Your listing", popularity: nil, into: &collected)
        }
        for term in KeywordSuggestionEngine.terms(fromAppName: context.appName, subtitle: context.subtitle) {
            guard !KeywordSuggestionEngine.isLikelyBrandToken(term, context: context) else { continue }
            merge(term: term, source: "Your listing", popularity: nil, into: &collected)
        }
    }

    private func harvestRelatedAppTitles(
        seeds: [String],
        into collected: inout [String: KeywordSuggestion]
    ) async throws {
        let serpSeeds = Array(seeds.prefix(KeywordSuggestionEngine.maxSERPSeeds))
        for (index, seed) in serpSeeds.enumerated() {
            try Task.checkCancellation()
            if index > 0 {
                try await Task.sleep(nanoseconds: RankingChecker.batchDelayNanoseconds)
            }
            let results = try await RankingChecker.shared.search(
                keyword: seed,
                country: country,
                limit: KeywordSuggestionEngine.maxSERPAppsPerSeed
            )
            for result in results {
                let terms = KeywordSuggestionEngine.terms(fromAppName: result.name, subtitle: result.subtitle)
                for term in terms {
                    merge(
                        term: term,
                        source: "Apps ranking for “\(seed)”",
                        popularity: nil,
                        into: &collected
                    )
                }
            }
        }
    }

    private func merge(
        term: String,
        source: String,
        popularity: Int?,
        into collected: inout [String: KeywordSuggestion]
    ) {
        let trimmed = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = trimmed.lowercased()
        guard !key.isEmpty, !trackedKeys.contains(key) else { return }
        if key == app.name.lowercased() { return }
        if var existing = collected[key] {
            if existing.popularity == nil { existing.popularity = popularity }
            collected[key] = existing
        } else {
            collected[key] = KeywordSuggestion(term: trimmed, source: source, popularity: popularity)
        }
    }

    private func addSuggestion(_ suggestion: KeywordSuggestion) {
        let key = suggestion.term.lowercased()
        guard !trackedKeys.contains(key) else { return }
        let kw = TrackedKeyword(term: suggestion.term, country: country)
        kw.popularityScore = suggestion.popularity
        if suggestion.popularity != nil {
            kw.popularityLastUpdated = .now
        }
        kw.app = app
        app.trackedKeywords.append(kw)
        modelContext.insert(kw)
        suggestions.removeAll { $0.id == suggestion.id }
        statusMessage = "Added “\(suggestion.term)”"
    }
}
