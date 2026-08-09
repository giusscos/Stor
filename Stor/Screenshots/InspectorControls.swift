import SwiftUI

// MARK: - Inspector chrome

struct InspectorSection<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    @State private var isExpanded: Bool

    init(title: String, startsExpanded: Bool = true, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
        self._isExpanded = State(initialValue: startsExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isExpanded ? 10 : 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))

                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                        .tracking(0.4)

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
                .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .help(isExpanded ? "Collapse \(title)" : "Expand \(title)")

            if isExpanded {
                content
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(0.04))
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

struct InspectorLabeledRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title)
                .font(.callout)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            content
        }
    }
}

// MARK: - Buffered sliders (no model writes during drag)

/// Percent-formatted slider (0.0–1.5 → "0%–150%") that only commits to the model on drag
/// end, avoiding a full layers re-encode per tick. `onLiveChange` fires on every tick so
/// the canvas can render the in-flight value through a lightweight preview override.
struct BufferedPercentSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onLiveChange: ((Double) -> Void)? = nil
    var onEditEnd: (() -> Void)? = nil

    @State private var local: Double = 0
    @State private var dragging = false

    var body: some View {
        InspectorLabeledRow(title) {
            Slider(value: $local, in: range) { editing in
                dragging = editing
                if !editing {
                    value = local
                    onEditEnd?()
                }
            }
            Text(String(format: "%.0f%%", local * 100))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
        }
        .onAppear { local = value }
        .onChange(of: local) { _, v in if dragging { onLiveChange?(v) } }
        .onChange(of: value) { _, v in if !dragging { local = v } }
    }
}

/// Plain numeric slider (e.g. corner radius 0–120) that only commits to the model on drag
/// end. Same live-preview hooks as `BufferedPercentSlider`.
struct BufferedValueSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    /// Overrides the default integer readout, e.g. for fractional tracking values.
    var format: ((Double) -> String)? = nil
    var onLiveChange: ((Double) -> Void)? = nil
    var onEditEnd: (() -> Void)? = nil

    @State private var local: Double = 0
    @State private var dragging = false

    var body: some View {
        InspectorLabeledRow(title) {
            Slider(value: $local, in: range, step: step) { editing in
                dragging = editing
                if !editing {
                    value = local
                    onEditEnd?()
                }
            }
            Text(format?(local) ?? "\(Int(local))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)
        }
        .onAppear { local = value }
        .onChange(of: local) { _, v in if dragging { onLiveChange?(v) } }
        .onChange(of: value) { _, v in if !dragging { local = v } }
    }
}

/// Title-less buffered percent slider for use inside an existing labeled row
/// (the Width/Height rows that also carry the "Fit to content" toggle).
struct BufferedFitSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var onLiveChange: ((Double) -> Void)? = nil
    var onEditEnd: (() -> Void)? = nil

    @State private var local: Double = 0
    @State private var dragging = false

    var body: some View {
        Slider(value: $local, in: range) { editing in
            dragging = editing
            if !editing {
                value = local
                onEditEnd?()
            }
        }
        Text(String(format: "%.0f%%", local * 100))
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
            .frame(width: 36, alignment: .trailing)
            .onAppear { local = value }
            .onChange(of: local) { _, v in if dragging { onLiveChange?(v) } }
            .onChange(of: value) { _, v in if !dragging { local = v } }
    }
}
