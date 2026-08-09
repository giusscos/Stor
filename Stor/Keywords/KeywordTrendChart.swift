import Charts
import SwiftUI

/// A single rank observation, normalised for charting.
struct RankPoint: Identifiable {
    /// Identity of the backing `KeywordRanking`, which has no UUID of its own.
    let id: ObjectIdentifier
    let date: Date
    /// nil means the app was not found in the top 200 on that check.
    let position: Int?

    var isRanking: Bool { position != nil }
}

extension TrackedKeyword {
    /// Ranking history oldest-first, which is the order charts and trend math expect.
    var rankPoints: [RankPoint] {
        rankingHistory
            .sorted { $0.checkedAt < $1.checkedAt }
            .map { RankPoint(id: ObjectIdentifier($0), date: $0.checkedAt, position: $0.position) }
    }

    var latestRankPoint: RankPoint? { rankPoints.last }

    /// Change between the two most recent checks. Negative means the rank number went
    /// down, which is an improvement.
    var rankDelta: Int? {
        let ranked = rankPoints.compactMap { point in point.position.map { (point.date, $0) } }
        guard ranked.count >= 2 else { return nil }
        return ranked[ranked.count - 1].1 - ranked[ranked.count - 2].1
    }
}

// MARK: - Inline sparkline

/// Compact trend shown in the keyword table. Rank axis is inverted so a rising line
/// means a better position.
struct RankSparkline: View {
    let points: [RankPoint]

    private var ranked: [RankPoint] { points.filter(\.isRanking) }

    var body: some View {
        if ranked.count < 2 {
            Text("—")
                .font(.caption)
                .foregroundStyle(.tertiary)
        } else {
            Chart(ranked) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Rank", point.position ?? 0)
                )
                .interpolationMethod(.monotone)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }
            .chartYScale(domain: .automatic(includesZero: false, reversed: true))
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartLegend(.hidden)
            .accessibilityLabel("Rank trend")
            .accessibilityValue(Self.trendDescription(ranked))
        }
    }

    static func trendDescription(_ points: [RankPoint]) -> String {
        guard let first = points.first?.position, let last = points.last?.position else {
            return "No ranking data"
        }
        if first == last { return "Unchanged at position \(last)" }
        return first > last
            ? "Improved from position \(first) to \(last)"
            : "Dropped from position \(first) to \(last)"
    }
}

// MARK: - Detail chart

/// Full rank history for one keyword. Checks where the app did not rank are drawn as
/// hollow marks pinned below the worst observed position rather than dropped silently,
/// so gaps in coverage stay visible.
struct KeywordTrendSheet: View {
    let keyword: TrackedKeyword

    @Environment(\.dismiss) private var dismiss

    private var points: [RankPoint] { keyword.rankPoints }
    private var ranked: [RankPoint] { points.filter(\.isRanking) }
    private var unranked: [RankPoint] { points.filter { !$0.isRanking } }

    /// Value used to plot "not in the top 200" so it sits below every real position.
    private var floorValue: Int {
        (ranked.compactMap(\.position).max() ?? 100) + 20
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()

            if points.isEmpty {
                ContentUnavailableView(
                    "No ranking history",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Run Check Rankings to start recording positions for this keyword.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                chart
                    .padding(20)
                statistics
            }

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 620, height: 480)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(keyword.term)
                .font(.headline)
            Text("\(KeywordCountries.displayName(keyword.country)) · \(points.count) check\(points.count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    private var chart: some View {
        Chart {
            ForEach(ranked) { point in
                LineMark(
                    x: .value("Date", point.date),
                    y: .value("Rank", point.position ?? 0)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(Color.accentColor)

                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Rank", point.position ?? 0)
                )
                .foregroundStyle(Color.accentColor)
            }

            ForEach(unranked) { point in
                PointMark(
                    x: .value("Date", point.date),
                    y: .value("Rank", floorValue)
                )
                .symbol(.circle)
                .symbolSize(40)
                .foregroundStyle(.tertiary)
            }

            RuleMark(y: .value("Top 10", 10))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                .foregroundStyle(.green.opacity(0.5))
                .annotation(position: .top, alignment: .leading) {
                    Text("Top 10")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
        }
        .chartYScale(domain: .automatic(includesZero: false, reversed: true))
        .chartYAxisLabel("Position")
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5))
        }
    }

    private var statistics: some View {
        HStack(spacing: 24) {
            statistic("Current", value: currentText)
            statistic("Best", value: ranked.compactMap(\.position).min().map { "#\($0)" } ?? "—")
            statistic("Change", value: changeText, tint: changeTint)
            if !unranked.isEmpty {
                statistic("Unranked checks", value: "\(unranked.count)")
            }
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 4)
    }

    private var currentText: String {
        guard let last = points.last else { return "—" }
        return last.position.map { "#\($0)" } ?? "Not ranking"
    }

    private var changeText: String {
        guard let delta = keyword.rankDelta else { return "—" }
        if delta == 0 { return "No change" }
        // A smaller position number is a better rank.
        return delta < 0 ? "▲ \(-delta)" : "▼ \(delta)"
    }

    private var changeTint: Color {
        guard let delta = keyword.rankDelta, delta != 0 else { return .secondary }
        return delta < 0 ? .green : .red
    }

    private func statistic(_ title: String, value: String, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(tint)
        }
    }
}
