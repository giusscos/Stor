import SwiftUI

struct ScoreBadge: View {
    let value: Int?
    /// When true, high values are bad (difficulty).
    var inverted: Bool = false

    var body: some View {
        Group {
            if let value {
                Text("\(value)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(tint(for: value))
                    .help(inverted ? "Difficulty \(value)" : "Opportunity \(value)")
            } else {
                Text("—")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 36, alignment: .leading)
    }

    private func tint(for value: Int) -> Color {
        let bucket = inverted ? value : (100 - value)
        switch bucket {
        case 0..<30: return .green
        case 30..<60: return .orange
        default: return .red
        }
    }
}
