import AppKit
import SwiftData
import SwiftUI

struct ScreenshotGalleryView: View {
    let templates: [ScreenshotTemplate]
    @Binding var selectedTemplate: ScreenshotTemplate?
    var previewLocale: String
    var onOpenEditor: () -> Void

    private struct DeviceGroup: Identifiable {
        let device: DeviceType
        let templates: [ScreenshotTemplate]
        var id: String { device.rawValue }
    }

    private var groups: [DeviceGroup] {
        DeviceType.allCases.compactMap { device in
            let matched = templates.filter { $0.deviceType == device }
            guard !matched.isEmpty else { return nil }
            return DeviceGroup(device: device, templates: matched)
        }
    }

    var body: some View {
        Group {
            if templates.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 36) {
                        header

                        ForEach(groups) { group in
                            deviceSection(group)
                        }
                    }
                    .padding(.vertical, 28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.underPageBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("App Store Preview")
                .font(.title2.weight(.semibold))
            Text("Screenshots as they appear on the product page, grouped by device.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 28)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.stack")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
                .padding(.top, 48)
            Text("No Screenshots")
                .font(.headline)
            Text("Create templates to preview them in App Store layout.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.horizontal, 32)
    }

    private func deviceSection(_ group: DeviceGroup) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(group.device.rawValue)
                    .font(.headline)
                Text("\(group.templates.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }
            .padding(.horizontal, 28)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 18) {
                    ForEach(group.templates, id: \.persistentModelID) { template in
                        galleryCard(template)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 6)
            }
        }
    }

    private func galleryCard(_ template: ScreenshotTemplate) -> some View {
        let isSelected = selectedTemplate?.persistentModelID == template.persistentModelID
        let cardWidth: CGFloat = template.deviceType == .macBook ? 260 : template.deviceType == .iPadPro13 ? 220 : 180
        let cardHeight = cardWidth / template.deviceType.aspectRatio

        return VStack(spacing: 10) {
            ZStack {
                ScreenshotCanvas(
                    template: template,
                    selectedLayerId: .constant(nil),
                    previewLocale: previewLocale,
                    isInteractive: false
                )
                .frame(width: cardWidth, height: cardHeight)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.22), radius: 18, y: 10)

                if isSelected {
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2.5)
                        .padding(-5)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onTapGesture(count: 2) {
                selectedTemplate = template
                onOpenEditor()
            }
            .onTapGesture {
                selectedTemplate = template
            }
            .contextMenu {
                Button("Edit Screenshot") {
                    selectedTemplate = template
                    onOpenEditor()
                }
            }

            Text(template.name)
                .font(.caption.weight(.medium))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                .lineLimit(1)
                .frame(width: cardWidth)
        }
    }
}
