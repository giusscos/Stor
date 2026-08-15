import SwiftUI
import AppKit
import Foundation

// MARK: - Shape layer types

enum ShapeKind: String, Codable, CaseIterable, Identifiable {
    case rectangle, circle, triangle

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rectangle: return "Rectangle"
        case .circle: return "Circle"
        case .triangle: return "Triangle"
        }
    }

    var systemImage: String {
        switch self {
        case .rectangle: return "square"
        case .circle: return "circle"
        case .triangle: return "triangle"
        }
    }
}

enum ShapeEffect: String, Codable, CaseIterable, Identifiable {
    case none, blur, glass

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "None"
        case .blur: return "Material"
        case .glass: return "Glass"
        }
    }
}

// MARK: - Canvas background

nonisolated enum CanvasBackgroundKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case solid
    case linear
    case radial
    case mesh

    var id: String { rawValue }

    var title: String {
        switch self {
        case .solid: return "Solid"
        case .linear: return "Linear"
        case .radial: return "Radial"
        case .mesh: return "Mesh"
        }
    }

    var symbol: String {
        switch self {
        case .solid: return "paintbrush.fill"
        case .linear: return "line.diagonal"
        case .radial: return "circle.lefthalf.filled"
        case .mesh: return "square.grid.3x3.fill"
        }
    }
}

nonisolated struct GradientStop: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var hex: String
    var location: Double

    init(id: UUID = UUID(), hex: String, location: Double) {
        self.id = id
        self.hex = hex
        self.location = location
    }
}

nonisolated struct MeshControlPoint: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var x: Double
    var y: Double

    init(id: UUID = UUID(), x: Double, y: Double) {
        self.id = id
        self.x = min(1, max(0, x))
        self.y = min(1, max(0, y))
    }

    var simd: SIMD2<Float> { .init(Float(x), Float(y)) }
}

nonisolated struct CanvasBackground: Codable, Equatable, Sendable {
    var kind: CanvasBackgroundKind
    var solidHex: String
    var stops: [GradientStop]
    /// Degrees: 0 = left→right, 90 = top→bottom.
    var linearAngle: Double
    var radialCenterX: Double
    var radialCenterY: Double
    /// Mesh grid size (2…5).
    var meshWidth: Int
    var meshHeight: Int
    /// Row-major mesh colors (`meshWidth * meshHeight`).
    var meshColors: [String]
    /// Row-major control points in unit space (0…1).
    var meshPoints: [MeshControlPoint]

    static let shapeDefault = CanvasBackground(
        kind: .linear,
        solidHex: "#6366F1",
        stops: [
            GradientStop(hex: "#6366F1", location: 0),
            GradientStop(hex: "#8B5CF6", location: 1)
        ],
        linearAngle: 135,
        radialCenterX: 0.5,
        radialCenterY: 0.35,
        meshWidth: 3,
        meshHeight: 3,
        meshColors: [
            "#6366F1", "#7C3AED", "#8B5CF6",
            "#6366F1", "#A78BFA", "#7C3AED",
            "#8B5CF6", "#6366F1", "#7C3AED"
        ],
        meshPoints: defaultMeshPoints(width: 3, height: 3)
    )

    static let `default` = CanvasBackground(
        kind: .solid,
        solidHex: "#1A1A2E",
        stops: [
            GradientStop(hex: "#1A1A2E", location: 0),
            GradientStop(hex: "#0F3460", location: 1)
        ],
        linearAngle: 180,
        radialCenterX: 0.5,
        radialCenterY: 0.35,
        meshWidth: 3,
        meshHeight: 3,
        meshColors: [
            "#1A1A2E", "#16213E", "#0F3460",
            "#1A1A2E", "#E94560", "#16213E",
            "#0F3460", "#1A1A2E", "#16213E"
        ],
        meshPoints: defaultMeshPoints(width: 3, height: 3)
    )

    var sortedStops: [GradientStop] {
        stops.sorted { $0.location < $1.location }
    }

    var meshPointCount: Int { max(1, meshWidth * meshHeight) }

    func linearUnitPoints() -> (UnitPoint, UnitPoint) {
        let radians = linearAngle * .pi / 180
        let dx = cos(radians)
        let dy = sin(radians)
        return (
            UnitPoint(x: 0.5 - dx / 2, y: 0.5 - dy / 2),
            UnitPoint(x: 0.5 + dx / 2, y: 0.5 + dy / 2)
        )
    }

    static func defaultMeshPoints(width: Int, height: Int) -> [MeshControlPoint] {
        let w = max(2, width)
        let h = max(2, height)
        return (0..<h).flatMap { row in
            (0..<w).map { col in
                MeshControlPoint(
                    x: Double(col) / Double(w - 1),
                    y: Double(row) / Double(h - 1)
                )
            }
        }
    }

    static func defaultMeshColors(count: Int, existing: [String] = []) -> [String] {
        var colors = existing
        let fallback = existing.last ?? "#1A1A2E"
        while colors.count < count { colors.append(fallback) }
        if colors.count > count { colors = Array(colors.prefix(count)) }
        return colors
    }

    /// Ensures mesh arrays match `meshWidth × meshHeight`.
    mutating func normalizeMesh() {
        meshWidth = min(5, max(2, meshWidth))
        meshHeight = min(5, max(2, meshHeight))
        let count = meshWidth * meshHeight
        meshColors = Self.defaultMeshColors(count: count, existing: meshColors)
        if meshPoints.count != count {
            meshPoints = Self.defaultMeshPoints(width: meshWidth, height: meshHeight)
        }
    }

    mutating func resizeMesh(width: Int, height: Int) {
        let oldW = meshWidth
        let oldH = meshHeight
        let oldColors = meshColors
        let oldPoints = meshPoints

        meshWidth = min(5, max(2, width))
        meshHeight = min(5, max(2, height))
        let count = meshWidth * meshHeight

        // Sample nearest color/point from the previous grid when possible.
        var newColors: [String] = []
        var newPoints: [MeshControlPoint] = []
        for row in 0..<meshHeight {
            for col in 0..<meshWidth {
                let srcCol = oldW <= 1 ? 0 : Int((Double(col) / Double(meshWidth - 1)) * Double(oldW - 1) + 0.5)
                let srcRow = oldH <= 1 ? 0 : Int((Double(row) / Double(meshHeight - 1)) * Double(oldH - 1) + 0.5)
                let srcIndex = min(oldColors.count - 1, max(0, srcRow * oldW + srcCol))
                newColors.append(srcIndex >= 0 && srcIndex < oldColors.count ? oldColors[srcIndex] : "#1A1A2E")

                if srcIndex >= 0, srcIndex < oldPoints.count, oldW == meshWidth, oldH == meshHeight {
                    newPoints.append(oldPoints[srcIndex])
                } else {
                    newPoints.append(
                        MeshControlPoint(
                            x: Double(col) / Double(meshWidth - 1),
                            y: Double(row) / Double(meshHeight - 1)
                        )
                    )
                }
            }
        }
        meshColors = Self.defaultMeshColors(count: count, existing: newColors)
        meshPoints = newPoints
    }

    mutating func resetMeshPositions() {
        meshPoints = Self.defaultMeshPoints(width: meshWidth, height: meshHeight)
    }

    enum CodingKeys: String, CodingKey {
        case kind, solidHex, stops, linearAngle, radialCenterX, radialCenterY
        case meshWidth, meshHeight, meshColors, meshPoints
    }

    init(
        kind: CanvasBackgroundKind,
        solidHex: String,
        stops: [GradientStop],
        linearAngle: Double,
        radialCenterX: Double,
        radialCenterY: Double,
        meshWidth: Int,
        meshHeight: Int,
        meshColors: [String],
        meshPoints: [MeshControlPoint]
    ) {
        self.kind = kind
        self.solidHex = solidHex
        self.stops = stops
        self.linearAngle = linearAngle
        self.radialCenterX = radialCenterX
        self.radialCenterY = radialCenterY
        self.meshWidth = meshWidth
        self.meshHeight = meshHeight
        self.meshColors = meshColors
        self.meshPoints = meshPoints
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        kind = try c.decodeIfPresent(CanvasBackgroundKind.self, forKey: .kind) ?? .solid
        solidHex = try c.decodeIfPresent(String.self, forKey: .solidHex) ?? "#1A1A2E"
        stops = try c.decodeIfPresent([GradientStop].self, forKey: .stops) ?? [
            GradientStop(hex: "#1A1A2E", location: 0),
            GradientStop(hex: "#0F3460", location: 1)
        ]
        linearAngle = try c.decodeIfPresent(Double.self, forKey: .linearAngle) ?? 180
        radialCenterX = try c.decodeIfPresent(Double.self, forKey: .radialCenterX) ?? 0.5
        radialCenterY = try c.decodeIfPresent(Double.self, forKey: .radialCenterY) ?? 0.35
        meshColors = try c.decodeIfPresent([String].self, forKey: .meshColors) ?? CanvasBackground.default.meshColors
        meshWidth = try c.decodeIfPresent(Int.self, forKey: .meshWidth) ?? 3
        meshHeight = try c.decodeIfPresent(Int.self, forKey: .meshHeight) ?? 3
        meshPoints = try c.decodeIfPresent([MeshControlPoint].self, forKey: .meshPoints)
            ?? Self.defaultMeshPoints(width: meshWidth, height: meshHeight)
        normalizeMesh()
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(solidHex, forKey: .solidHex)
        try c.encode(stops, forKey: .stops)
        try c.encode(linearAngle, forKey: .linearAngle)
        try c.encode(radialCenterX, forKey: .radialCenterX)
        try c.encode(radialCenterY, forKey: .radialCenterY)
        try c.encode(meshWidth, forKey: .meshWidth)
        try c.encode(meshHeight, forKey: .meshHeight)
        try c.encode(meshColors, forKey: .meshColors)
        try c.encode(meshPoints, forKey: .meshPoints)
    }
}

// MARK: - Background fill view

struct CanvasBackgroundFill: View {
    let background: CanvasBackground

    var body: some View {
        switch background.kind {
        case .solid:
            Color(hex: background.solidHex)

        case .linear:
            let points = background.linearUnitPoints()
            LinearGradient(
                stops: gradientStops,
                startPoint: points.0,
                endPoint: points.1
            )

        case .radial:
            GeometryReader { geo in
                let radius = hypot(geo.size.width, geo.size.height) * 0.75
                RadialGradient(
                    stops: gradientStops,
                    center: UnitPoint(x: background.radialCenterX, y: background.radialCenterY),
                    startRadius: 0,
                    endRadius: radius
                )
            }

        case .mesh:
            let width = max(2, background.meshWidth)
            let height = max(2, background.meshHeight)
            let count = width * height
            MeshGradient(
                width: width,
                height: height,
                points: resolvedMeshPoints(count: count),
                colors: resolvedMeshColors(count: count)
            )
        }
    }

    private var gradientStops: [Gradient.Stop] {
        background.sortedStops.map {
            Gradient.Stop(color: Color(hex: $0.hex), location: $0.location)
        }
    }

    private func resolvedMeshColors(count: Int) -> [Color] {
        (0..<count).map { index in
            let hex = index < background.meshColors.count ? background.meshColors[index] : "#1A1A2E"
            return Color(hex: hex)
        }
    }

    private func resolvedMeshPoints(count: Int) -> [SIMD2<Float>] {
        if background.meshPoints.count == count {
            return background.meshPoints.map(\.simd)
        }
        return CanvasBackground.defaultMeshPoints(
            width: background.meshWidth,
            height: background.meshHeight
        ).map(\.simd)
    }
}

// MARK: - Triangle shape

struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: CGPoint(x: rect.midX, y: rect.minY))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
        }
    }
}

// MARK: - Shape layer view

struct ShapeLayerView: View {
    let layer: ScreenshotLayer
    let scale: CGFloat

    private var cornerRadius: CGFloat { layer.shapeCornerRadiusPt * scale }

    private var clipShape: AnyShape {
        switch layer.shapeKind {
        case .rectangle: AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        case .circle:    AnyShape(Circle())
        case .triangle:  AnyShape(TriangleShape())
        }
    }

    var body: some View {
        ZStack {
            fillView
            if layer.innerShadow.isEnabled {
                InnerShadowOverlay(shape: clipShape, shadow: layer.innerShadow, scale: scale)
            }
            if layer.shapeStrokeWidth > 0 {
                clipShape.stroke(
                    Color(hex: layer.shapeStrokeColorHex),
                    lineWidth: layer.shapeStrokeWidth * scale
                )
            }
        }
    }

    @ViewBuilder
    private var fillView: some View {
        let fill = layer.resolvedShapeFill
        let shape = clipShape
        switch layer.shapeEffect {
        case .none:
            CanvasBackgroundFill(background: fill)
                .clipShape(shape)
        case .blur:
            ZStack {
                Color.clear
                    .background(.regularMaterial)
                    .clipShape(shape)
                CanvasBackgroundFill(background: fill)
                    .clipShape(shape)
            }
        case .glass:
            if #available(macOS 26, *) {
                Color.clear
                    .glassEffect(.regular.tint(glassTint(from: fill)), in: shape)
            } else {
                ZStack {
                    Color.clear
                        .background(.regularMaterial)
                        .clipShape(shape)
                    CanvasBackgroundFill(background: fill)
                        .clipShape(shape)
                }
            }
        }
    }

    private func glassTint(from fill: CanvasBackground) -> Color {
        let hex = fill.kind == .solid
            ? fill.solidHex
            : fill.sortedStops.first?.hex ?? fill.solidHex
        return Color(hex: hex)
    }
}

// MARK: - Font options

enum LayerFontWeight: String, Codable, CaseIterable, Identifiable {
    case ultraLight, thin, light, regular, medium, semibold, bold, heavy, black

    var id: String { rawValue }

    var title: String {
        switch self {
        case .ultraLight: return "Ultralight"
        case .thin: return "Thin"
        case .light: return "Light"
        case .regular: return "Regular"
        case .medium: return "Medium"
        case .semibold: return "Semibold"
        case .bold: return "Bold"
        case .heavy: return "Heavy"
        case .black: return "Black"
        }
    }

    var swiftUI: Font.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }

    var nsWeight: NSFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }
}

enum LayerFontDesign: String, Codable, CaseIterable, Identifiable {
    case `default`, rounded, serif, monospaced

    var id: String { rawValue }

    var title: String {
        switch self {
        case .default: return "Default"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .monospaced: return "Mono"
        }
    }

    var swiftUI: Font.Design {
        switch self {
        case .default: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }
}

enum LayerTextAlignment: String, Codable, CaseIterable, Identifiable {
    case leading, center, trailing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .leading: return "Left"
        case .center: return "Center"
        case .trailing: return "Right"
        }
    }

    var symbol: String {
        switch self {
        case .leading: return "text.alignleft"
        case .center: return "text.aligncenter"
        case .trailing: return "text.alignright"
        }
    }

    var swiftUI: Alignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    var nsTextAlignment: NSTextAlignment {
        switch self {
        case .leading: return .left
        case .center: return .center
        case .trailing: return .right
        }
    }
}

enum ScreenshotFontFamily {
    static let systemFamilies = [
        "System",
        "System Rounded",
        "System Serif",
        "System Mono"
    ]

    static var allFamilies: [String] {
        let installed = NSFontManager.shared.availableFontFamilies
            .filter { !systemFamilies.contains($0) }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return systemFamilies + installed
    }

    static func isSystem(_ family: String) -> Bool {
        systemFamilies.contains(family)
    }

    static func design(for family: String) -> Font.Design {
        switch family {
        case "System Rounded": return .rounded
        case "System Serif": return .serif
        case "System Mono": return .monospaced
        default: return .default
        }
    }
}

extension ScreenshotLayer {
    func resolvedSwiftUIFont(size: CGFloat) -> Font {
        if ScreenshotFontFamily.isSystem(fontFamily) {
            return .system(size: size, weight: fontWeight.swiftUI, design: ScreenshotFontFamily.design(for: fontFamily))
                .italic(isItalic ? true : false)
        }
        return .custom(fontFamily, size: size)
            .weight(fontWeight.swiftUI)
            .italic(isItalic ? true : false)
    }

    func resolvedNSFont(size: CGFloat) -> NSFont {
        if ScreenshotFontFamily.isSystem(fontFamily) {
            let base = NSFont.systemFont(ofSize: size, weight: fontWeight.nsWeight)
            let design: NSFontDescriptor.SystemDesign = {
                switch fontFamily {
                case "System Rounded": return .rounded
                case "System Serif": return .serif
                case "System Mono": return .monospaced
                default: return .default
                }
            }()
            let descriptor = base.fontDescriptor.withDesign(design) ?? base.fontDescriptor
            var traits: [NSFontDescriptor.TraitKey: Any] = [
                .weight: fontWeight.nsWeight
            ]
            if isItalic {
                traits[.symbolic] = NSFontDescriptor.SymbolicTraits.italic.rawValue
            }
            let final = descriptor.addingAttributes([.traits: traits])
            return NSFont(descriptor: final, size: size) ?? base
        }

        let manager = NSFontManager.shared
        var font = NSFont(name: fontFamily, size: size)
            ?? manager.font(withFamily: fontFamily, traits: [], weight: 5, size: size)
            ?? .systemFont(ofSize: size)

        let weightValue: Int = {
            switch fontWeight {
            case .ultraLight: return 1
            case .thin: return 2
            case .light: return 3
            case .regular: return 5
            case .medium: return 6
            case .semibold: return 8
            case .bold: return 9
            case .heavy: return 10
            case .black: return 11
            }
        }()

        var traits: NSFontTraitMask = []
        if isItalic { traits.insert(.italicFontMask) }
        if fontWeight == .bold || fontWeight == .heavy || fontWeight == .black {
            traits.insert(.boldFontMask)
        }
        if let converted = manager.font(withFamily: font.familyName ?? fontFamily,
                                        traits: traits,
                                        weight: weightValue,
                                        size: size) {
            font = converted
        }
        return font
    }

    /// Builds an attributed string for canvas preview / export, applying layer style
    /// and Markdown inline styles when `textUsesMarkdown` is on:
    /// `**bold**`, `*italic*`, `~~strike~~`, `` `code` ``, `++underline++`.
    func resolvedAttributedString(
        for locale: String?,
        fontSize: CGFloat,
        scale: CGFloat = 1
    ) -> NSAttributedString? {
        guard let raw = resolvedText(for: locale) else { return nil }

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = textAlignment.nsTextAlignment

        let baseFont = resolvedNSFont(size: fontSize)
        let baseColor = NSColor(Color(hex: colorHex))
        let kern = tracking * Double(scale)

        let baseAttrs: [NSAttributedString.Key: Any] = [
            .font: baseFont,
            .foregroundColor: baseColor,
            .paragraphStyle: paragraph,
            .kern: kern
        ]

        guard textUsesMarkdown else {
            return NSAttributedString(string: raw, attributes: baseAttrs)
        }

        // `~~strike~~` and `++underline++` aren't CommonMark — sentinel-encode, parse, then style.
        let markdownSource = Self.encodeCustomInlineMarkers(in: raw)

        let markdownOptions: AttributedString.MarkdownParsingOptions = {
            var options = AttributedString.MarkdownParsingOptions()
            options.interpretedSyntax = .inlineOnlyPreservingWhitespace
            return options
        }()
        guard let markdown = try? AttributedString(markdown: markdownSource, options: markdownOptions) else {
            return NSAttributedString(string: raw, attributes: baseAttrs)
        }

        let result = NSMutableAttributedString()
        for run in markdown.runs {
            let substring = String(markdown[run.range].characters)
            var attrs = baseAttrs
            let intent = run.inlinePresentationIntent
            let wantsBold = intent?.contains(.stronglyEmphasized) == true
            let wantsItalic = intent?.contains(.emphasized) == true
            let wantsCode = intent?.contains(.code) == true

            if wantsCode {
                attrs[.font] = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
            } else if wantsBold || wantsItalic {
                var traits: NSFontTraitMask = []
                if wantsBold { traits.insert(.boldFontMask) }
                if wantsItalic { traits.insert(.italicFontMask) }
                attrs[.font] = NSFontManager.shared.convert(baseFont, toHaveTrait: traits)
            }

            result.append(NSAttributedString(string: substring, attributes: attrs))
        }

        Self.applyAndStripCustomSentinels(in: result, color: baseColor)

        return result
    }

    /// SwiftUI text for canvas preview (plain or Markdown).
    /// Shares the AppKit attributed path with export so inline styles match PNG output.
    func resolvedPreviewText(for locale: String?, fontSize: CGFloat, scale: CGFloat) -> Text {
        guard let nsAttributed = resolvedAttributedString(
            for: locale,
            fontSize: fontSize,
            scale: scale
        ) else {
            return Text("")
        }
        return Text(AttributedString(nsAttributed))
    }

    /// Plain text with Markdown emphasis markers removed (for list labels, etc.).
    func plainPreviewLabel(for locale: String?) -> String {
        let raw = resolvedText(for: locale) ?? "Text"
        guard textUsesMarkdown else { return raw }
        return Self.stripInlineMarkdownMarkers(raw)
    }

    /// Private sentinels so non-CommonMark delimiters survive Markdown parsing without showing on canvas.
    private static let underlineOpen = "\u{FFF0}"
    private static let underlineClose = "\u{FFF1}"
    private static let strikeOpen = "\u{FFF2}"
    private static let strikeClose = "\u{FFF3}"

    /// Converts `~~strike~~` / `++underline++` into sentinel-wrapped text for Markdown parsing.
    static func encodeCustomInlineMarkers(in text: String) -> String {
        var result = encodeDelimited(
            text,
            pattern: #"~~(.+?)~~"#,
            open: strikeOpen,
            close: strikeClose
        )
        result = encodeDelimited(
            result,
            pattern: #"\+\+(.+?)\+\+"#,
            open: underlineOpen,
            close: underlineClose
        )
        return result
    }

    /// - Note: Kept for call sites that only need underline encoding.
    static func encodeUnderlineMarkers(in text: String) -> String {
        encodeCustomInlineMarkers(in: text)
    }

    private static func encodeDelimited(
        _ text: String,
        pattern: String,
        open: String,
        close: String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return text }
        let full = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(
            in: text,
            options: [],
            range: full,
            withTemplate: "\(open)$1\(close)"
        )
    }

    static func applyAndStripCustomSentinels(in attributed: NSMutableAttributedString, color: NSColor) {
        applyAndStripSentinelPair(
            in: attributed,
            open: strikeOpen,
            close: strikeClose,
            attributes: [
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: color
            ]
        )
        applyAndStripSentinelPair(
            in: attributed,
            open: underlineOpen,
            close: underlineClose,
            attributes: [
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: color
            ]
        )
    }

    static func applyAndStripUnderlineSentinels(
        in attributed: NSMutableAttributedString,
        underlineColor: NSColor
    ) {
        applyAndStripCustomSentinels(in: attributed, color: underlineColor)
    }

    private static func applyAndStripSentinelPair(
        in attributed: NSMutableAttributedString,
        open: String,
        close: String,
        attributes: [NSAttributedString.Key: Any]
    ) {
        while true {
            let ns = attributed.string as NSString
            let openRange = ns.range(of: open)
            guard openRange.location != NSNotFound else { break }
            let searchFrom = openRange.location + openRange.length
            let closeSearch = NSRange(location: searchFrom, length: ns.length - searchFrom)
            let closeRange = ns.range(of: close, options: [], range: closeSearch)
            guard closeRange.location != NSNotFound else {
                attributed.replaceCharacters(in: openRange, with: "")
                continue
            }
            let content = NSRange(
                location: openRange.location + openRange.length,
                length: closeRange.location - (openRange.location + openRange.length)
            )
            if content.length > 0 {
                attributed.addAttributes(attributes, range: content)
            }
            attributed.replaceCharacters(in: closeRange, with: "")
            attributed.replaceCharacters(in: openRange, with: "")
        }
    }

    static func stripInlineMarkdownMarkers(_ text: String) -> String {
        var result = text
        // Longer / more specific delimiters first.
        let patterns = [
            #"\+\+(.+?)\+\+"#,
            #"~~(.+?)~~"#,
            #"\*\*\*(.+?)\*\*\*"#,
            #"\*\*(.+?)\*\*"#,
            #"\*(.+?)\*"#,
            #"`(.+?)`"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { continue }
            let range = NSRange(result.startIndex..<result.endIndex, in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "$1"
            )
        }
        return result
    }

    /// Resolves the on-canvas size, honoring fit-to-content for text layers.
    /// - Parameter fontScale: `1` for export at device size; `canvasWidth / 375` for preview.
    func resolvedSize(in canvasSize: CGSize, locale: String?, fontScale: CGFloat) -> CGSize {
        let fixedWidth = widthFraction * canvasSize.width
        let fixedHeight = heightFraction * canvasSize.height

        guard type == .text, fitWidthToContent || fitHeightToContent else {
            let scale = (type == .image) ? max(0.01, frameScale) : 1.0
            return CGSize(width: fixedWidth * scale, height: fixedHeight * scale)
        }

        let fontSize = fontSizePt * fontScale
        let pad = textPaddingPt * fontScale
        let maxTextWidth: CGFloat = {
            if fitWidthToContent {
                return max(1, canvasSize.width - pad * 2)
            }
            return max(1, fixedWidth - pad * 2)
        }()

        guard let attributed = resolvedAttributedString(
            for: locale,
            fontSize: fontSize,
            scale: fontScale
        ) else {
            return CGSize(width: fixedWidth, height: fixedHeight)
        }

        let textBounds = attributed.boundingRect(
            with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading]
        )
        // Add a little slack so glyphs aren't clipped at the edges.
        let contentWidth = ceil(textBounds.width) + 2
        let contentHeight = ceil(textBounds.height) + 2

        let width = fitWidthToContent
            ? min(canvasSize.width, contentWidth + pad * 2)
            : fixedWidth
        let height = fitHeightToContent
            ? min(canvasSize.height, contentHeight + pad * 2)
            : fixedHeight

        return CGSize(width: max(1, width), height: max(1, height))
    }

    /// Top-left origin frame in canvas coordinates (SwiftUI / preview space).
    func resolvedFrame(in canvasSize: CGSize, locale: String?, fontScale: CGFloat) -> CGRect {
        let size = resolvedSize(in: canvasSize, locale: locale, fontScale: fontScale)
        return CGRect(
            x: xFraction * canvasSize.width,
            y: yFraction * canvasSize.height,
            width: size.width,
            height: size.height
        )
    }
}

private extension Font {
    func italic(_ enabled: Bool) -> Font {
        enabled ? self.italic() : self
    }
}
