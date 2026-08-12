import SwiftUI
import SwiftData

struct LocalizationDetailView: View {
    @Bindable var localization: LocalizedMetadata
    var app: AppRecord?
    let isEditable: Bool
    @State private var showBudget = false

    var hasAnyContent: Bool {
        localization.appName != nil || localization.subtitle != nil ||
        localization.appDescription != nil || localization.keywords != nil ||
        localization.promotionalText != nil || localization.whatsNew != nil
    }

    var body: some View {
        if hasAnyContent {
            VStack(alignment: .leading, spacing: 20) {
                if let name = localization.appName {
                    MetadataFieldRow(field: .appName, text: name, isEditable: isEditable) {
                        localization.appName = $0
                    }
                }
                if let subtitle = localization.subtitle {
                    MetadataFieldRow(field: .subtitle, text: subtitle, isEditable: isEditable) {
                        localization.subtitle = $0
                    }
                }
                if let desc = localization.appDescription {
                    MetadataFieldRow(field: .appDescription, text: desc, isEditable: isEditable, multiline: true) {
                        localization.appDescription = $0
                    }
                }
                if let keywords = localization.keywords {
                    VStack(alignment: .leading, spacing: 8) {
                        KeywordsField(text: keywords, isEditable: isEditable) {
                            localization.keywords = $0
                        }
                        if isEditable, let app, countryCode(fromLocale: localization.locale) != nil {
                            Button("Optimize Budget…") { showBudget = true }
                                .font(.caption)
                                .disabled(app.trackedKeywords.isEmpty)
                        }
                    }
                    .sheet(isPresented: $showBudget) {
                        if let app {
                            KeywordBudgetSheet(app: app, localization: localization) { packed in
                                localization.keywords = packed
                            }
                        }
                    }
                }
                if let promo = localization.promotionalText {
                    MetadataFieldRow(field: .promotionalText, text: promo, isEditable: isEditable, multiline: true) {
                        localization.promotionalText = $0
                    }
                }
                if let whatsNew = localization.whatsNew {
                    MetadataFieldRow(field: .whatsNew, text: whatsNew, isEditable: isEditable, multiline: true) {
                        localization.whatsNew = $0
                    }
                }
            }
        } else {
            ContentUnavailableView("No metadata available", systemImage: "doc.text")
        }
    }
}

// MARK: - Character counter

/// Shared counter that warns before the limit and blocks at it, so the state shown while
/// editing matches the rule that gates Save and Push.
struct CharacterCountLabel: View {
    let count: Int
    let limit: Int

    private var tint: Color {
        if count > limit { return .red }
        if Double(count) >= Double(limit) * MetadataField.warningThreshold { return .orange }
        return .secondary
    }

    var body: some View {
        Text("\(count) / \(limit)")
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(tint)
            .accessibilityLabel("\(count) of \(limit) characters used")
    }
}

// MARK: - Generic field

private struct MetadataFieldRow: View {
    let field: MetadataField
    let text: String
    let isEditable: Bool
    var multiline: Bool = false
    let onEdit: (String) -> Void

    @State private var draft = ""
    @State private var editing = false

    private var limit: Int { field.limit }
    private var overLimit: Bool { text.count > limit }
    private var draftOverLimit: Bool { draft.count > limit }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(field.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                CharacterCountLabel(count: editing ? draft.count : text.count, limit: limit)
                if isEditable && !editing {
                    Button("Edit") { draft = text; editing = true }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.blue)
                }
            }

            if editing {
                VStack(alignment: .trailing, spacing: 8) {
                    if multiline {
                        TextEditor(text: $draft)
                            .font(.body)
                            .frame(minHeight: 100, maxHeight: 280)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderColor, lineWidth: 1.5))
                    } else {
                        TextField("", text: $draft)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(borderColor, lineWidth: 1.5))
                    }
                    HStack {
                        if draftOverLimit {
                            Text("\(draft.count - limit) over the App Store limit")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                        Spacer()
                        Button("Cancel") { editing = false }.buttonStyle(.borderless)
                        Button("Save") { onEdit(draft); editing = false }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                            .disabled(draftOverLimit)
                    }
                }
            } else {
                Text(text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(overLimit ? .red : .primary)
                    .lineLimit(multiline ? nil : 3)
            }
        }
    }

    private var borderColor: Color {
        draftOverLimit ? .red : Color.accentColor.opacity(0.5)
    }
}

// MARK: - Keywords field

private struct KeywordsField: View {
    let text: String
    let isEditable: Bool
    let onEdit: (String) -> Void

    @State private var draft = ""
    @State private var editing = false

    private static let limit = MetadataField.keywords.limit

    var chips: [String] {
        Self.terms(in: text)
    }
    var overLimit: Bool { text.count > Self.limit }

    private var draftTerms: [String] { Self.terms(in: draft) }
    private var draftOverLimit: Bool { draft.count > Self.limit }

    /// Terms repeated in the field. Apple ignores the duplicate but it still costs budget.
    private var duplicateTerms: [String] {
        var seen = Set<String>()
        var duplicates: [String] = []
        for term in draftTerms {
            if !seen.insert(term.lowercased()).inserted, !duplicates.contains(term) {
                duplicates.append(term)
            }
        }
        return duplicates
    }

    private static func terms(in raw: String) -> [String] {
        raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(MetadataField.keywords.rawValue)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                CharacterCountLabel(count: editing ? draft.count : text.count, limit: Self.limit)
                if isEditable && !editing {
                    Button("Edit") { draft = text; editing = true }
                        .font(.caption)
                        .buttonStyle(.borderless)
                        .foregroundStyle(.blue)
                }
            }

            if editing {
                VStack(alignment: .trailing, spacing: 8) {
                    TextField("keyword1,keyword2,keyword3", text: $draft)
                        .textFieldStyle(.plain)
                        .padding(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(draftOverLimit ? .red : Color.accentColor.opacity(0.5), lineWidth: 1.5)
                        )
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(budgetHint)
                                .font(.caption2)
                                .foregroundStyle(draftOverLimit ? AnyShapeStyle(.red) : AnyShapeStyle(.tertiary))
                            if !duplicateTerms.isEmpty {
                                Text("Repeated: \(duplicateTerms.joined(separator: ", "))")
                                    .font(.caption2)
                                    .foregroundStyle(.orange)
                            }
                        }
                        Spacer()
                        Button("Cancel") { editing = false }.buttonStyle(.borderless)
                        Button("Save") { onEdit(draft); editing = false }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                            .disabled(draftOverLimit)
                    }
                }
            } else {
                ChipCloud(chips: chips)
            }
        }
    }

    private var budgetHint: String {
        let remaining = Self.limit - draft.count
        if remaining < 0 { return "\(-remaining) characters over the limit" }
        return "Comma-separated · \(remaining) characters left · \(draftTerms.count) term\(draftTerms.count == 1 ? "" : "s")"
    }
}

// MARK: - Chip cloud layout

struct ChipCloud: View {
    let chips: [String]

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(chips, id: \.self) { chip in
                Text(chip)
                    .font(.caption)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var height: CGFloat = 0
        var rowX: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowX + size.width > maxWidth && rowX > 0 {
                height += rowHeight + spacing
                rowX = 0
                rowHeight = 0
            }
            rowX += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        height += rowHeight
        return CGSize(width: maxWidth, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX && x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
