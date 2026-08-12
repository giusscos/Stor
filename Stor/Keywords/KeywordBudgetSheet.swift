import SwiftUI
import SwiftData

struct KeywordBudgetSheet: View {
    @Bindable var app: AppRecord
    let localization: LocalizedMetadata
    var onApply: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var plan: KeywordBudgetPlan

    init(app: AppRecord, localization: LocalizedMetadata, onApply: @escaping (String) -> Void) {
        self.app = app
        self.localization = localization
        self.onApply = onApply
        let current = localization.keywords ?? ""
        let country = countryCode(fromLocale: localization.locale) ?? "US"
        let candidates = Self.candidates(app: app, country: country, current: current)
        _plan = State(initialValue: KeywordBudget.pack(current: current, candidates: candidates))
    }

    private var country: String {
        countryCode(fromLocale: localization.locale) ?? "US"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Divider()
                HSplitView {
                    termColumn(
                        title: "Current",
                        terms: KeywordBudget.parse(plan.current),
                        highlight: Set(plan.dropped.map { $0.lowercased() }),
                        highlightColor: .red
                    )
                    termColumn(
                        title: "Proposed",
                        terms: KeywordBudget.parse(plan.proposed),
                        highlight: Set(plan.added.map { $0.lowercased() }),
                        highlightColor: .green
                    )
                }
                Divider()
                footer
            }
            .navigationTitle("Keyword Budget")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply to Draft") {
                        onApply(plan.proposed)
                        dismiss()
                    }
                    .disabled(!plan.didChange)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(LocaleDisplayName.name(for: localization.locale)) · \(country)")
                .font(.subheadline)
            Text("Fills the 100-character listing field from tracked keywords, preferring higher opportunity. Applied to the draft only — nothing is pushed to App Store Connect.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                labeled("Current", "\(plan.current.count)/\(KeywordBudget.limit)")
                labeled("Proposed", "\(plan.proposed.count)/\(KeywordBudget.limit)")
                labeled("Added", "\(plan.added.count)")
                labeled("Dropped", "\(plan.dropped.count)")
                labeled("Left", "\(plan.remaining)")
            }
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var footer: some View {
        HStack {
            Text(plan.didChange
                 ? "Apply writes this string into the draft keywords field."
                 : "Already using the best pack from tracked keywords.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
    }

    private func termColumn(title: String, terms: [String], highlight: Set<String>, highlightColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            Divider()
            if terms.isEmpty {
                Text("None")
                    .foregroundStyle(.tertiary)
                    .padding(16)
                Spacer()
            } else {
                List(terms, id: \.self) { term in
                    HStack {
                        Text(term)
                        Spacer()
                        if highlight.contains(term.lowercased()) {
                            Circle()
                                .fill(highlightColor)
                                .frame(width: 7, height: 7)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 240)
    }

    private func labeled(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
        }
    }

    private static func candidates(app: AppRecord, country: String, current: String) -> [KeywordBudgetCandidate] {
        let listed = Set(KeywordBudget.parse(current).map { $0.lowercased() })
        return app.trackedKeywords
            .filter { $0.country.caseInsensitiveCompare(country) == .orderedSame }
            .map { keyword in
                KeywordBudgetCandidate(
                    term: keyword.term,
                    opportunity: keyword.opportunity ?? 0,
                    currentlyListed: listed.contains(keyword.term.lowercased())
                )
            }
    }
}
