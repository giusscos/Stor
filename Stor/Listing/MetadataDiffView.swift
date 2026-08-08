import SwiftUI

struct MetadataDiffView: View {
    let older: MetadataSnapshot
    let newer: MetadataSnapshot
    @Environment(\.dismiss) private var dismiss

    @State private var selectedLocale: String?

    var availableLocales: [String] {
        let s = Set(older.localizations.map { $0.locale })
            .union(newer.localizations.map { $0.locale })
        return s.sorted()
    }

    var olderLoc: LocalizedMetadata? {
        older.localizations.first { $0.locale == selectedLocale }
    }

    var newerLoc: LocalizedMetadata? {
        newer.localizations.first { $0.locale == selectedLocale }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Picker("Locale", selection: $selectedLocale) {
                        ForEach(availableLocales, id: \.self) { locale in
                            Text(LocaleDisplayName.name(for: locale))
                                .tag(locale as String?)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 180, idealWidth: 220)

                    Spacer()

                    HStack(spacing: 16) {
                        DiffLegend(color: .red.opacity(0.2), label: "Before", date: older.capturedAt)
                        DiffLegend(color: .green.opacity(0.2), label: "After", date: newer.capturedAt)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

                Divider()

                ScrollView {
                    if let old = olderLoc, let new = newerLoc {
                        VStack(alignment: .leading, spacing: 16) {
                            DiffRow(title: "App Name", old: old.appName, new: new.appName)
                            DiffRow(title: "Subtitle", old: old.subtitle, new: new.subtitle)
                            DiffRow(title: "Description", old: old.appDescription, new: new.appDescription, multiline: true)
                            DiffRow(title: "Keywords", old: old.keywords, new: new.keywords)
                            DiffRow(title: "Promotional Text", old: old.promotionalText, new: new.promotionalText, multiline: true)
                            DiffRow(title: "What's New", old: old.whatsNew, new: new.whatsNew, multiline: true)
                        }
                        .padding(20)
                    } else {
                        ContentUnavailableView("No data for selected locale", systemImage: "globe")
                    }
                }
            }
            .navigationTitle("Metadata Changes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 720, minHeight: 520)
        .onAppear { selectedLocale = availableLocales.first }
    }
}

// MARK: - Legend

private struct DiffLegend: View {
    let color: Color
    let label: String
    let date: Date

    var body: some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(color.opacity(2), lineWidth: 1))
                .frame(width: 14, height: 14)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption).fontWeight(.medium)
                Text(date, style: .date).font(.caption2).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Row

private struct DiffRow: View {
    let title: String
    let old: String?
    let new: String?
    var multiline: Bool = false

    var changed: Bool { old != new }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline).fontWeight(.semibold)
                if changed {
                    Text("Changed")
                        .font(.caption2)
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(.orange.opacity(0.2), in: Capsule())
                        .foregroundStyle(.orange)
                } else {
                    Text("Unchanged").font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
            }

            if changed {
                HStack(alignment: .top, spacing: 12) {
                    DiffBlock(text: old, color: .red, label: "Before")
                    DiffBlock(text: new, color: .green, label: "After")
                }
            } else {
                Text(old ?? "—")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 8))
                    .lineLimit(multiline ? nil : 2)
            }
        }
    }
}

private struct DiffBlock: View {
    let text: String?
    let color: Color
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2).foregroundStyle(.secondary).textCase(.uppercase)
            Text(text ?? "—")
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.3), lineWidth: 1))
        }
        .frame(maxWidth: .infinity)
    }
}
