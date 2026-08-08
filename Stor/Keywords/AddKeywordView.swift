import SwiftUI
import SwiftData

struct AddKeywordView: View {
    let app: AppRecord
    let defaultCountry: String

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var keywordsText = ""
    @State private var selectedCountry: String

    private let countries = ["US", "GB", "DE", "FR", "IT", "ES", "JP", "CA", "AU", "BR"]

    init(app: AppRecord, defaultCountry: String) {
        self.app = app
        self.defaultCountry = defaultCountry
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
                            Text(Locale.current.localizedString(forRegionCode: cc) ?? cc).tag(cc)
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
        let existing = Set(app.trackedKeywords.map { $0.term.lowercased() })
        for term in keywordList where !existing.contains(term.lowercased()) {
            let kw = TrackedKeyword(term: term, country: selectedCountry)
            kw.app = app
            app.trackedKeywords.append(kw)
            modelContext.insert(kw)
        }
        dismiss()
    }
}
