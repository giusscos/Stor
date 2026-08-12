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
            return "Sign in to Apple Ads and/or save competitors, then refresh."
        }
        if !adsSessionActive {
            return "No competitor terms found. Sign in to Apple Ads for related keyword suggestions."
        }
        return "No new terms found. Try more tracked keywords or save competitors."
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Suggestions for \(Locale.current.localizedString(forRegionCode: country) ?? country)")
                .font(.subheadline)
            Text("From Apple Ads recommendations and competitor listing metadata.")
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
                        Text("\(score)")
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(width: 36, alignment: .trailing)
                            .help("Popularity")
                    } else {
                        Text("—")
                            .foregroundStyle(.tertiary)
                            .frame(width: 36, alignment: .trailing)
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

        // Apple Ads recommendations from tracked seeds
        if sessionOK, let adamId {
            let seeds = app.trackedKeywords
                .filter { $0.country.caseInsensitiveCompare(country) == .orderedSame }
                .prefix(8)
            for seed in seeds {
                do {
                    let rows = try await SearchAdsAPIClient.shared.fetchRecommendations(
                        seed: seed.term,
                        country: country,
                        adamId: adamId,
                        limit: 25
                    )
                    for row in rows {
                        let key = row.text.lowercased()
                        guard !trackedKeys.contains(key) else { continue }
                        if var existing = collected[key] {
                            if existing.popularity == nil { existing.popularity = row.score }
                            collected[key] = existing
                        } else {
                            collected[key] = KeywordSuggestion(
                                term: row.text,
                                source: "Apple Ads · from “\(seed.term)”",
                                popularity: row.score
                            )
                        }
                    }
                } catch {
                    softError = softError ?? error.localizedDescription
                }
            }
        }

        // Competitor listing / metadata tokens
        for competitor in app.competitors {
            do {
                var lookup = try await ITunesLookupClient.shared.lookup(bundleId: competitor.bundleId)
                if lookup == nil {
                    lookup = try await ITunesLookupClient.shared.lookup(trackId: competitor.trackId)
                }
                guard let lookup else { continue }
                let terms = ITunesLookupClient.shared.suggestionTerms(from: lookup)
                for term in terms.prefix(30) {
                    let key = term.lowercased()
                    guard !trackedKeys.contains(key) else { continue }
                    if collected[key] == nil {
                        collected[key] = KeywordSuggestion(
                            term: term,
                            source: "Competitor · \(competitor.name)",
                            popularity: nil
                        )
                    }
                }
            } catch {
                softError = softError ?? error.localizedDescription
            }
        }

        // Fill missing popularity when Ads web session is available
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

        suggestions = collected.values.sorted { lhs, rhs in
            let lp = lhs.popularity ?? -1
            let rp = rhs.popularity ?? -1
            if lp != rp { return lp > rp }
            return lhs.term.localizedCaseInsensitiveCompare(rhs.term) == .orderedAscending
        }
        statusMessage = suggestions.isEmpty
            ? nil
            : "\(suggestions.count) suggestion\(suggestions.count == 1 ? "" : "s")"
        // Non-blocking notice — competitor rows may still have succeeded.
        if let softError, !suggestions.isEmpty {
            statusMessage = (statusMessage ?? "") + " · Ads: \(softError.prefix(80))"
        } else if let softError, suggestions.isEmpty {
            errorMessage = softError
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
