import SwiftUI
import AppKit

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
                SectionTabControl(selection: $selectedSection)
            }
        }
    }
}

// MARK: - Compact section tabs (AppKit)

/// Native `NSSegmentedControl` sized to its segments — avoids the oversized
/// SwiftUI `.segmented` capsule that stretches across the toolbar.
private struct SectionTabControl: NSViewRepresentable {
    @Binding var selection: AppDetailView.Section

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: $selection)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let images = AppDetailView.Section.allCases.map { section -> NSImage in
            let image = NSImage(systemSymbolName: section.icon, accessibilityDescription: section.rawValue)
                ?? NSImage(size: NSSize(width: 16, height: 16))
            image.isTemplate = true
            return image
        }

        let control = NSSegmentedControl(
            images: images,
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.valueChanged(_:))
        )
        control.segmentStyle = .rounded
        control.selectedSegment = AppDetailView.Section.allCases.firstIndex(of: selection) ?? 0

        for (index, section) in AppDetailView.Section.allCases.enumerated() {
            control.setToolTip(section.rawValue, forSegment: index)
            control.setWidth(36, forSegment: index)
        }

        control.setContentHuggingPriority(.required, for: .horizontal)
        control.setContentCompressionResistancePriority(.required, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selection = $selection
        let index = AppDetailView.Section.allCases.firstIndex(of: selection) ?? 0
        if control.selectedSegment != index {
            control.selectedSegment = index
        }
    }

    final class Coordinator: NSObject {
        var selection: Binding<AppDetailView.Section>

        init(selection: Binding<AppDetailView.Section>) {
            self.selection = selection
        }

        @objc func valueChanged(_ sender: NSSegmentedControl) {
            let sections = AppDetailView.Section.allCases
            guard sender.selectedSegment >= 0, sender.selectedSegment < sections.count else { return }
            selection.wrappedValue = sections[sender.selectedSegment]
        }
    }
}
