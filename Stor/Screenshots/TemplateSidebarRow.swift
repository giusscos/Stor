import SwiftUI

struct TemplateSidebarRow: View {
    @Bindable var template: ScreenshotTemplate
    let isSelected: Bool
    let isLast: Bool
    var isRenaming: Bool = false
    var onRenameEnd: () -> Void = {}

    @FocusState private var nameFocused: Bool

    private var deviceIcon: String {
        switch template.deviceType {
        case .iPadPro13: return "ipad"
        case .macBook: return "laptopcomputer"
        default: return "iphone"
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            timelineRail

            VStack(alignment: .leading, spacing: 4) {
                if isRenaming {
                    TextField("Name", text: $template.name)
                        .font(.callout.weight(.semibold))
                        .textFieldStyle(.plain)
                        .focused($nameFocused)
                        .onSubmit {
                            if template.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                template.name = "Screenshot"
                            }
                            onRenameEnd()
                        }
                        .onChange(of: nameFocused) { _, focused in
                            if !focused { onRenameEnd() }
                        }
                } else {
                    Text(template.name)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                HStack(spacing: 6) {
                    Image(systemName: deviceIcon)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(template.deviceType.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.trailing, 8)

            Spacer(minLength: 0)
        }
        .padding(.leading, 4)
        .padding(.trailing, 4)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            }
        }
        .animation(.easeOut(duration: 0.12), value: isSelected)
        .onChange(of: isRenaming) { _, renaming in
            if renaming { nameFocused = true }
        }
    }

    private var timelineRail: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.18))
                    .frame(width: 8, height: 8)
                if isSelected {
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.35), lineWidth: 3)
                        .frame(width: 14, height: 14)
                }
            }
            .frame(width: 14, height: 14)
            .padding(.top, 10)

            if !isLast {
                Rectangle()
                    .fill(Color.primary.opacity(0.12))
                    .frame(width: 1.5)
                    .frame(maxHeight: .infinity)
            }
        }
        .frame(width: 14)
    }
}
