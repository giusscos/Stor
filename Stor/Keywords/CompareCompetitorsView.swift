import SwiftUI
import SwiftData

struct CompareCompetitorsView: View {
    @Bindable var app: AppRecord
    let country: String
    let keywords: [TrackedKeyword]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var isChecking = false
    @State private var errorMessage: String?
    @State private var statusMessage: String?

    private var competitors: [CompetitorApp] {
        app.competitors.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if competitors.isEmpty {
                    VStack(spacing: 10) {
                        Image(systemName: "person.2")
                            .font(.system(size: 32))
                            .foregroundStyle(.tertiary)
                            .padding(.top, 48)
                        Text("No Competitors")
                            .font(.headline)
                        Text("Use Discover to find apps in search results and save them as competitors.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .padding(.horizontal, 24)
                } else {
                    competitorsStrip
                    Divider()
                    if keywords.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 32))
                                .foregroundStyle(.tertiary)
                                .padding(.top, 48)
                            Text("No Keywords")
                                .font(.headline)
                            Text("Add tracked keywords for \(country) to compare rankings.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .padding(.horizontal, 24)
                    } else {
                        compareTable
                    }
                }
            }
            .navigationTitle("Compare")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        checkCompetitorRankings()
                    } label: {
                        if isChecking {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Check Rankings", systemImage: "list.number")
                        }
                    }
                    .disabled(isChecking || competitors.isEmpty || keywords.isEmpty)
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
        }
        .frame(minWidth: 720, minHeight: 480)
    }

    private var competitorsStrip: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Competitors")
                .font(.caption)
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(competitors) { competitor in
                        HStack(spacing: 8) {
                            competitorIcon(url: competitor.iconURL, size: 28)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(competitor.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                if let subtitle = competitor.subtitle, !subtitle.isEmpty {
                                    Text(subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                            Button(role: .destructive) {
                                modelContext.delete(competitor)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Remove competitor")
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(.quinary, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
    }

    private var compareTable: some View {
        ScrollView([.horizontal, .vertical]) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
                GridRow {
                    Text("Keyword")
                        .frame(minWidth: 160, alignment: .leading)
                    Text("You")
                        .frame(width: 64, alignment: .leading)
                    ForEach(competitors) { competitor in
                        Text(competitor.name)
                            .lineLimit(1)
                            .frame(width: 88, alignment: .leading)
                            .help(competitor.name)
                    }
                    Text("Popularity")
                        .frame(width: 90, alignment: .leading)
                    Text("Shared")
                        .frame(width: 64, alignment: .leading)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 8)

                Divider()

                ForEach(keywords) { keyword in
                    GridRow {
                        Text(keyword.term)
                            .frame(minWidth: 160, alignment: .leading)

                        rankLabel(yourRankCell(for: keyword))
                            .frame(width: 64, alignment: .leading)

                        ForEach(competitors) { competitor in
                            rankLabel(competitorRankCell(competitor, term: keyword.term))
                                .frame(width: 88, alignment: .leading)
                        }

                        Group {
                            if let score = keyword.popularityScore {
                                Text("\(score)")
                                    .monospacedDigit()
                            } else {
                                Text("—")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .frame(width: 90, alignment: .leading)

                        sharedBadge(for: keyword)
                            .frame(width: 64, alignment: .leading)
                    }
                    .padding(.vertical, 8)

                    Divider()
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func sharedBadge(for keyword: TrackedKeyword) -> some View {
        let youRanked: Bool = {
            if case .ranked = yourRankCell(for: keyword) { return true }
            return false
        }()
        let competitorRanked = competitors.contains {
            if case .ranked = competitorRankCell($0, term: keyword.term) { return true }
            return false
        }
        if youRanked && competitorRanked {
            Image(systemName: "link.circle.fill")
                .foregroundStyle(.blue)
                .help("You and at least one competitor both appear in the top 200")
        } else {
            Text("—")
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func rankLabel(_ cell: RankCell) -> some View {
        switch cell {
        case .unknown:
            Text("—")
                .foregroundStyle(.tertiary)
        case .notInTop200:
            Text(">200")
                .foregroundStyle(.tertiary)
        case .ranked(let position):
            Text("#\(position)")
                .fontWeight(.medium)
                .monospacedDigit()
                .foregroundStyle(position <= 10 ? .green : .primary)
        }
    }

    private enum RankCell {
        case unknown
        case notInTop200
        case ranked(Int)
    }

    private func yourRankCell(for keyword: TrackedKeyword) -> RankCell {
        let latest = keyword.rankingHistory
            .filter { $0.country.caseInsensitiveCompare(country) == .orderedSame }
            .sorted { $0.checkedAt > $1.checkedAt }
            .first
        guard let latest else { return .unknown }
        if let position = latest.position {
            return .ranked(position)
        }
        return .notInTop200
    }

    private func competitorRankCell(_ competitor: CompetitorApp, term: String) -> RankCell {
        let latest = competitor.rankingHistory
            .filter {
                $0.term.caseInsensitiveCompare(term) == .orderedSame
                    && $0.country.caseInsensitiveCompare(country) == .orderedSame
            }
            .sorted { $0.checkedAt > $1.checkedAt }
            .first
        guard let latest else { return .unknown }
        if let position = latest.position {
            return .ranked(position)
        }
        return .notInTop200
    }

    @ViewBuilder
    private func competitorIcon(url: String?, size: CGFloat) -> some View {
        Group {
            if let url, let imageURL = URL(string: url) {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    default:
                        RoundedRectangle(cornerRadius: 6).fill(.quinary)
                    }
                }
            } else {
                RoundedRectangle(cornerRadius: 6).fill(.quinary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func checkCompetitorRankings() {
        isChecking = true
        errorMessage = nil
        statusMessage = nil
        Task {
            defer { isChecking = false }
            do {
                var checks = 0
                for keyword in keywords {
                    for competitor in competitors {
                        let position = try await RankingChecker.shared.checkRanking(
                            bundleId: competitor.bundleId,
                            keyword: keyword.term,
                            country: country
                        )
                        let ranking = CompetitorKeywordRanking(
                            term: keyword.term,
                            country: country,
                            position: position,
                            checkedAt: .now
                        )
                        ranking.competitor = competitor
                        competitor.rankingHistory.append(ranking)
                        modelContext.insert(ranking)
                        checks += 1
                        try await Task.sleep(nanoseconds: RankingChecker.batchDelayNanoseconds)
                    }
                }
                statusMessage = "Updated \(checks) competitor ranking\(checks == 1 ? "" : "s")."
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
