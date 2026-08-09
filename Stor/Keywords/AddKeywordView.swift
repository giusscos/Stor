import SwiftUI
import SwiftData

struct AddKeywordView: View {
    let app: AppRecord
    let defaultCountry: String
    let onAdd: (AppRecord.KeywordInsertResult) -> Void

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var keywordsText = ""
    @State private var selectedCountry: String

    private let countries = KeywordCountries.all

    init(
        app: AppRecord,
        defaultCountry: String,
        onAdd: @escaping (AppRecord.KeywordInsertResult) -> Void = { _ in }
    ) {
        self.app = app
        self.defaultCountry = defaultCountry
        self.onAdd = onAdd
        _selectedCountry = State(initialValue: defaultCountry)
    }

    var keywordList: [String] {
        keywordsText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Country", selection: $selectedCountry) {
                        ForEach(countries, id: \.self) { cc in
                            Text(KeywordCountries.displayName(cc)).tag(cc)
                        }
                    }
                }

                Section {
                    TextEditor(text: $keywordsText)
                        .font(.body)
                        .frame(minHeight: 180)
                } header: {
                    Text("Keywords — one per line")
                } footer: {
                    Text(keywordList.isEmpty
                         ? "Enter each keyword on its own line."
                         : "\(keywordList.count) keyword\(keywordList.count == 1 ? "" : "s") to add")
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add Keywords")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { addKeywords() }
                        .disabled(keywordList.isEmpty)
                }
            }
        }
        .frame(minWidth: 400, minHeight: 360)
    }

    private func addKeywords() {
        let result = app.insertKeywords(
            keywordList,
            locale: localeForCountry(selectedCountry),
            country: selectedCountry,
            into: modelContext
        )
        onAdd(result)
        dismiss()
    }

    /// Records the locale that actually matches the chosen storefront instead of always
    /// defaulting to `en-US`. Prefers a real localization the app already ships there.
    private func localeForCountry(_ country: String) -> String {
        if countryCode(fromLocale: app.primaryLocale) == country {
            return app.primaryLocale
        }
        if let shipped = app.snapshots
            .flatMap(\.localizations)
            .map(\.locale)
            .first(where: { countryCode(fromLocale: $0) == country }) {
            return shipped
        }
        let language = app.primaryLocale.split(separator: "-").first.map(String.init) ?? "en"
        return "\(language)-\(country)"
    }
}
