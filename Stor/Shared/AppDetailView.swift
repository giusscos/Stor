import SwiftUI

struct AppDetailView: View {
    let app: AppRecord
    @State private var selectedSection: Section = .listing

    enum Section: String, CaseIterable {
        case listing = "Listing"
        case keywords = "Keywords"
        case screenshots = "Screenshots"

        var icon: String {
            switch self {
            case .listing: return "doc.text"
            case .keywords: return "magnifyingglass"
            case .screenshots: return "photo.stack"
            }
        }
    }

    var body: some View {
        Group {
            switch selectedSection {
            case .listing:
                ListingTabView(app: app)
            case .keywords:
                KeywordsTabView(app: app)
            case .screenshots:
                ScreenshotEditorView(app: app)
            }
        }
        .navigationTitle(app.name)
        .navigationSubtitle(app.bundleId)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Section", selection: $selectedSection) {
                    ForEach(Section.allCases, id: \.self) { section in
                        Label(section.rawValue, systemImage: section.icon)
                            .tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }
        }
    }
}
