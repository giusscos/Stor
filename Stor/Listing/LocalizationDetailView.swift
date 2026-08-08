import SwiftUI

struct LocalizationDetailView: View {
    @Bindable var localization: LocalizedMetadata
    let isEditable: Bool

    var hasAnyContent: Bool {
        localization.appName != nil || localization.subtitle != nil ||
        localization.appDescription != nil || localization.keywords != nil ||
        localization.promotionalText != nil || localization.whatsNew != nil
    }

    var body: some View {
        if hasAnyContent {
            VStack(alignment: .leading, spacing: 20) {
                if let name = localization.appName {
                    MetadataField(title: "App Name", text: name, limit: 30, isEditable: isEditable) {
                        localization.appName = $0
                    }
                }
                if let subtitle = localization.subtitle {
                    MetadataField(title: "Subtitle", text: subtitle, limit: 30, isEditable: isEditable) {
                        localization.subtitle = $0
                    }
                }
                if let desc = localization.appDescription {
                    MetadataField(title: "Description", text: desc, limit: 4000, isEditable: isEditable, multiline: true) {
                        localization.appDescription = $0
                    }
                }
                if let keywords = localization.keywords {
                    KeywordsField(text: keywords, isEditable: isEditable) {
                        localization.keywords = $0
                    }
                }
                if let promo = localization.promotionalText {
                    MetadataField(title: "Promotional Text", text: promo, limit: 170, isEditable: isEditable, multiline: true) {
                        localization.promotionalText = $0
                    }
                }
                if let whatsNew = localization.whatsNew {
                    MetadataField(title: "What's New", text: whatsNew, limit: 4000, isEditable: isEditable, multiline: true) {
                        localization.whatsNew = $0
                    }
                }
            }
        } else {
            ContentUnavailableView("No metadata available", systemImage: "doc.text")
        }
    }
}

// MARK: - Generic field

private struct MetadataField: View {
    let title: String
    let text: String
    let limit: Int
    let isEditable: Bool
    var multiline: Bool = false
    let onEdit: (String) -> Void

    @State private var draft = ""
    @State private var editing = false

    var overLimit: Bool { text.count > limit }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(text.count) / \(limit)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(overLimit ? .red : .secondary)
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
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor.opacity(0.5), lineWidth: 1.5))
                    } else {
                        TextField("", text: $draft)
                            .textFieldStyle(.plain)
                            .padding(8)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor.opacity(0.5), lineWidth: 1.5))
                    }
                    HStack {
                        Button("Cancel") { editing = false }.buttonStyle(.borderless)
                        Button("Save") { onEdit(draft); editing = false }
                            .buttonStyle(.borderedProminent).controlSize(.small)
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
}

// MARK: - Keywords field

private struct KeywordsField: View {
    let text: String
    let isEditable: Bool
    let onEdit: (String) -> Void

    @State private var draft = ""
    @State private var editing = false

    var chips: [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }
    var overLimit: Bool { text.count > 100 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Keywords")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(text.count) / 100")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(overLimit ? .red : .secondary)
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
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.accentColor.opacity(0.5), lineWidth: 1.5))
                    HStack {
                        Text("Comma-separated").font(.caption2).foregroundStyle(.tertiary)
                        Spacer()
                        Button("Cancel") { editing = false }.buttonStyle(.borderless)
                        Button("Save") { onEdit(draft); editing = false }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
            } else {
                ChipCloud(chips: chips)
            }
        }
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
