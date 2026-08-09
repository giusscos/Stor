import SwiftUI
import SwiftData

struct DiscoverKeywordView: View {
    @Bindable var app: AppRecord
    let country: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var query: String = ""
    @State private var results: [SearchResult] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var savedFlash: String?

    private var trackedSeedTerms: [String] {
        app.trackedKeywords
            .filter { $0.country.caseInsensitiveCompare(country) == .orderedSame }
            .map(\.term)
            .sorted()
    }

    private var savedBundleIds: Set<String> {
        Set(app.competitors.map(\.bundleId))
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchBar
                Divider()
                if isLoading {
                    VStack {
                        ProgressView("Searching App Store…")
                            .padding(.top, 48)
                        Spacer()
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let errorMessage {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 48)
                        Text("Search Failed")
                            .font(.headline)
                        Text(errorMessage)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, 24)
                } else if results.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "binoculars")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 48)
                        Text("Discover Competitors")
                            .font(.headline)
                        Text("Search a keyword to see the top App Store results for \(country).")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, 24)
                } else {
                    resultsList
                }
            }
            .navigationTitle("Discover")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Saved", isPresented: Binding(
                get: { savedFlash != nil },
                set: { if !$0 { savedFlash = nil } }
            )) {
                Button("OK") { savedFlash = nil }
            } message: {
                Text(savedFlash ?? "")
            }
        }
        .frame(minWidth: 520, minHeight: 480)
        .onAppear {
            if query.isEmpty, let first = trackedSeedTerms.first {
                query = first
            }
        }
    }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Keyword", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { runSearch() }

                Button("Search") { runSearch() }
                    .buttonStyle(.borderedProminent)
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }

            if !trackedSeedTerms.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(trackedSeedTerms.prefix(20), id: \.self) { term in
                            Button(term) {
                                query = term
                                runSearch()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                }
            }

            Text("Country: \(Locale.current.localizedString(forRegionCode: country) ?? country)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(16)
    }

    private var resultsList: some View {
        List {
            ForEach(results) { result in
                HStack(spacing: 12) {
                    competitorIcon(url: result.iconURL)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text("#\(result.rank)")
                                .font(.caption)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                            Text(result.name)
                                .fontWeight(.medium)
                            if result.bundleId == app.bundleId {
                                Text("You")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.blue.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.blue)
                            }
                        }
                        if let subtitle = result.subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Text(result.bundleId)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    if result.bundleId == app.bundleId {
                        EmptyView()
                    } else if savedBundleIds.contains(result.bundleId) {
                        Label("Saved", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Button("Save") {
                            saveCompetitor(result)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.inset)
    }

    @ViewBuilder
    private func competitorIcon(url: String?) -> some View {
        Group {
            if let url, let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        RoundedRectangle(cornerRadius: 8).fill(.quinary)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 8).fill(.quinary)
            }
        }
        .frame(width: 40, height: 40)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func runSearch() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        isLoading = true
        errorMessage = nil
        Task {
            defer { isLoading = false }
            do {
                results = try await RankingChecker.shared.search(
                    keyword: term,
                    country: country,
                    limit: 10
                )
            } catch {
                errorMessage = error.localizedDescription
                results = []
            }
        }
    }

    private func saveCompetitor(_ result: SearchResult) {
        guard result.bundleId != app.bundleId else { return }
        guard !savedBundleIds.contains(result.bundleId) else { return }
        let competitor = CompetitorApp(
            trackId: result.trackId,
            bundleId: result.bundleId,
            name: result.name,
            iconURL: result.iconURL,
            subtitle: result.subtitle
        )
        competitor.app = app
        app.competitors.append(competitor)
        modelContext.insert(competitor)
        savedFlash = "Saved \(result.name) as a competitor."
    }
}
