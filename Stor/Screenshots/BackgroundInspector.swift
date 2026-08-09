import AppKit
import SwiftUI

struct BackgroundInspector: View {
    @Binding var background: CanvasBackground
    var title: String? = "Background"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Text(title)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            // Live preview
            CanvasBackgroundFill(background: background)
                .frame(height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                }

            // Kind picker
            HStack(spacing: 4) {
                ForEach(CanvasBackgroundKind.allCases) { kind in
                    Button {
                        background.kind = kind
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: kind.symbol)
                                .font(.system(size: 12, weight: .semibold))
                                .frame(width: 16, height: 16)
                            Text(kind.title)
                                .font(.caption2.weight(.medium))
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .foregroundStyle(background.kind == kind ? Color.accentColor : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 44, maxHeight: 44)
                        .background {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(background.kind == kind ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04))
                        }
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .help(kind.title)
                }
            }

            switch background.kind {
            case .solid:
                InspectorLabeledRow("Color") {
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: background.solidHex) },
                        set: { background.solidHex = $0.toHex() }
                    ))
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

            case .linear:
                gradientStopsEditor
                InspectorLabeledRow("Angle") {
                    Slider(value: $background.linearAngle, in: 0...360, step: 1)
                    Text("\(Int(background.linearAngle))°")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }

            case .radial:
                gradientStopsEditor
                InspectorLabeledRow("Center X") {
                    Slider(value: $background.radialCenterX, in: 0...1)
                    Text("\(Int(background.radialCenterX * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
                InspectorLabeledRow("Center Y") {
                    Slider(value: $background.radialCenterY, in: 0...1)
                    Text("\(Int(background.radialCenterY * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }

            case .mesh:
                MeshGradientEditor(background: $background)
            }
        }
    }

    private var gradientStopsEditor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Colors")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                if background.stops.count < 5 {
                    Button {
                        let last = background.sortedStops.last?.location ?? 0
                        background.stops.append(
                            GradientStop(hex: "#FFFFFF", location: min(1, last + 0.25))
                        )
                    } label: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Add color stop")
                }
            }

            ForEach(Array(background.stops.enumerated()), id: \.element.id) { index, stop in
                HStack(spacing: 8) {
                    ColorPicker("", selection: Binding(
                        get: { Color(hex: background.stops[index].hex) },
                        set: { background.stops[index].hex = $0.toHex() }
                    ))
                    .labelsHidden()
                    .frame(width: 36)

                    Slider(
                        value: Binding(
                            get: { background.stops[index].location },
                            set: { background.stops[index].location = $0 }
                        ),
                        in: 0...1
                    )

                    if background.stops.count > 2 {
                        Button {
                            background.stops.removeAll { $0.id == stop.id }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red.opacity(0.75))
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
        }
    }
}

// MARK: - Mesh gradient editor

struct MeshGradientEditor: View {
    @Binding var background: CanvasBackground
    @State private var selectedIndex: Int = 4

    private var pointCount: Int { background.meshWidth * background.meshHeight }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Mesh")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(background.meshWidth)×\(background.meshHeight)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.tertiary)
            }

            InspectorLabeledRow("Columns") {
                Stepper(
                    "",
                    value: Binding(
                        get: { background.meshWidth },
                        set: { newValue in
                            background.resizeMesh(width: newValue, height: background.meshHeight)
                            selectedIndex = min(selectedIndex, pointCount - 1)
                        }
                    ),
                    in: 2...5
                )
                .labelsHidden()
                Text("\(background.meshWidth)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .trailing)
            }

            InspectorLabeledRow("Rows") {
                Stepper(
                    "",
                    value: Binding(
                        get: { background.meshHeight },
                        set: { newValue in
                            background.resizeMesh(width: background.meshWidth, height: newValue)
                            selectedIndex = min(selectedIndex, max(0, background.meshWidth * background.meshHeight - 1))
                        }
                    ),
                    in: 2...5
                )
                .labelsHidden()
                Text("\(background.meshHeight)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 16, alignment: .trailing)
            }

            // Interactive point editor
            MeshPointCanvas(background: $background, selectedIndex: $selectedIndex)
                .frame(height: 150)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                }

            HStack {
                Text("Point \(selectedIndex + 1)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Reset Positions") {
                    background.resetMeshPositions()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .help("Return all points to a regular grid")
            }

            if selectedIndex >= 0, selectedIndex < background.meshPoints.count {
                InspectorLabeledRow("Color") {
                    ColorPicker("", selection: Binding(
                        get: {
                            let hex = selectedIndex < background.meshColors.count
                                ? background.meshColors[selectedIndex]
                                : "#1A1A2E"
                            return Color(hex: hex)
                        },
                        set: { color in
                            background.normalizeMesh()
                            guard selectedIndex < background.meshColors.count else { return }
                            background.meshColors[selectedIndex] = color.toHex()
                        }
                    ))
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }

                InspectorLabeledRow("X") {
                    Slider(
                        value: Binding(
                            get: { background.meshPoints[selectedIndex].x },
                            set: { background.meshPoints[selectedIndex].x = min(1, max(0, $0)) }
                        ),
                        in: 0...1
                    )
                    Text("\(Int(background.meshPoints[selectedIndex].x * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }

                InspectorLabeledRow("Y") {
                    Slider(
                        value: Binding(
                            get: { background.meshPoints[selectedIndex].y },
                            set: { background.meshPoints[selectedIndex].y = min(1, max(0, $0)) }
                        ),
                        in: 0...1
                    )
                    Text("\(Int(background.meshPoints[selectedIndex].y * 100))%")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
            }

            // Color grid for quick access
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: background.meshWidth),
                spacing: 6
            ) {
                ForEach(0..<pointCount, id: \.self) { index in
                    Button {
                        selectedIndex = index
                    } label: {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color(hex: index < background.meshColors.count ? background.meshColors[index] : "#1A1A2E"))
                            .frame(height: 22)
                            .overlay {
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .strokeBorder(
                                        selectedIndex == index ? Color.accentColor : Color.primary.opacity(0.12),
                                        lineWidth: selectedIndex == index ? 2 : 1
                                    )
                            }
                    }
                    .buttonStyle(.plain)
                    .help("Select point \(index + 1)")
                }
            }
        }
        .onAppear {
            background.normalizeMesh()
            selectedIndex = min(selectedIndex, max(0, pointCount - 1))
        }
        .onChange(of: background.meshWidth) { _, _ in
            selectedIndex = min(selectedIndex, max(0, pointCount - 1))
        }
        .onChange(of: background.meshHeight) { _, _ in
            selectedIndex = min(selectedIndex, max(0, pointCount - 1))
        }
    }
}

struct MeshPointCanvas: View {
    @Binding var background: CanvasBackground
    @Binding var selectedIndex: Int

    var body: some View {
        GeometryReader { geo in
            ZStack {
                CanvasBackgroundFill(background: background)

                // Light grid guides
                Path { path in
                    let w = background.meshWidth
                    let h = background.meshHeight
                    guard w > 1, h > 1 else { return }
                    for col in 0..<w {
                        for row in 0..<h {
                            let index = row * w + col
                            guard index < background.meshPoints.count else { continue }
                            let point = background.meshPoints[index]
                            let origin = CGPoint(
                                x: point.x * geo.size.width,
                                y: point.y * geo.size.height
                            )
                            if col + 1 < w {
                                let rightIndex = row * w + col + 1
                                if rightIndex < background.meshPoints.count {
                                    let right = background.meshPoints[rightIndex]
                                    path.move(to: origin)
                                    path.addLine(to: CGPoint(
                                        x: right.x * geo.size.width,
                                        y: right.y * geo.size.height
                                    ))
                                }
                            }
                            if row + 1 < h {
                                let belowIndex = (row + 1) * w + col
                                if belowIndex < background.meshPoints.count {
                                    let below = background.meshPoints[belowIndex]
                                    path.move(to: origin)
                                    path.addLine(to: CGPoint(
                                        x: below.x * geo.size.width,
                                        y: below.y * geo.size.height
                                    ))
                                }
                            }
                        }
                    }
                }
                .stroke(Color.white.opacity(0.22), lineWidth: 1)
                .allowsHitTesting(false)

                ForEach(Array(background.meshPoints.enumerated()), id: \.element.id) { index, point in
                    let position = CGPoint(
                        x: point.x * geo.size.width,
                        y: point.y * geo.size.height
                    )
                    Circle()
                        .fill(Color(hex: index < background.meshColors.count ? background.meshColors[index] : "#FFFFFF"))
                        .frame(width: selectedIndex == index ? 16 : 12, height: selectedIndex == index ? 16 : 12)
                        .overlay {
                            Circle()
                                .strokeBorder(Color.white, lineWidth: selectedIndex == index ? 2.5 : 1.5)
                        }
                        .shadow(color: .black.opacity(0.35), radius: 2, y: 1)
                        .position(position)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("meshCanvas"))
                                .onChanged { value in
                                    selectedIndex = index
                                    background.meshPoints[index] = MeshControlPoint(
                                        id: background.meshPoints[index].id,
                                        x: value.location.x / max(geo.size.width, 1),
                                        y: value.location.y / max(geo.size.height, 1)
                                    )
                                }
                        )
                }
            }
            .coordinateSpace(name: "meshCanvas")
            .contentShape(Rectangle())
        }
    }
}
