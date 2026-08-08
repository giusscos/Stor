import SwiftUI

struct MetadataDetailView: View {
    let snapshot: MetadataSnapshot
    let isEditable: Bool

    @State private var selectedLocale: String?

    var sortedLocalizations: [LocalizedMetadata] {
        snapshot.localizations.sorted { $0.locale < $1.locale }
    }

    var selectedLocalization: LocalizedMetadata? {
        sortedLocalizations.first { $0.locale == selectedLocale }
    }

    var body: some View {
        VStack(spacing: 0) {
            if !sortedLocalizations.isEmpty {
                HStack(spacing: 12) {
                    Text("Locale")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)

                    Picker("Locale", selection: $selectedLocale) {
                        ForEach(sortedLocalizations, id: \.locale) { loc in
                            Text(localeName(for: loc.locale))
                                .tag(loc.locale as String?)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 180, idealWidth: 220)

                    Spacer()

                    if let v = snapshot.versionString {
                        Text("v\(v)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.quaternary, in: Capsule())
                    }

                    Text(snapshot.capturedAt, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                Divider()
            }

            if let loc = selectedLocalization {
                ScrollView {
                    LocalizationDetailView(localization: loc, isEditable: isEditable)
                        .padding(20)
                }
            } else {
                ContentUnavailableView("No Localizations", systemImage: "globe")
            }
        }
        .onAppear {
            if selectedLocale == nil {
                selectedLocale = sortedLocalizations.first?.locale
            }
        }
        .onChange(of: snapshot.localizations.count) {
            if selectedLocale == nil {
                selectedLocale = sortedLocalizations.first?.locale
            }
        }
    }

    private func localeName(for code: String) -> String {
        LocaleDisplayName.name(for: code)
    }
}
