import SwiftData
import SwiftUI
import Foundation
import AppKit
import ImageIO
import Combine

// MARK: - Device types

enum DeviceType: String, CaseIterable, Codable {
    case iPhone69 = "iPhone 6.9\""
    case iPhone67 = "iPhone 6.7\""
    case iPhone65 = "iPhone 6.5\""
    case iPadPro13 = "iPad Pro 13\""
    case macBook = "MacBook"

    var canvasSize: CGSize {
        switch self {
        case .iPhone69:  return CGSize(width: 1320, height: 2868)
        case .iPhone67:  return CGSize(width: 1290, height: 2796)
        case .iPhone65:  return CGSize(width: 1284, height: 2778)
        case .iPadPro13: return CGSize(width: 2064, height: 2752)
        case .macBook:   return CGSize(width: 2560, height: 1600)
        }
    }

    var aspectRatio: CGFloat { canvasSize.width / canvasSize.height }

    var ascDisplayType: String {
        switch self {
        case .iPhone69:  return "APP_IPHONE_69"
        case .iPhone67:  return "APP_IPHONE_67"
        case .iPhone65:  return "APP_IPHONE_65"
        case .iPadPro13: return "APP_IPAD_PRO_3GEN_129"
        case .macBook:   return "APP_MAC"
        }
    }

}

// MARK: - Device frame options

/// One picker entry per device + color. Orientation is a separate toggle:
/// `portraitAsset` is the canonical/stored id, `landscapeAsset` is its landscape
/// variant when the catalog has one (MacBooks don't).
struct DeviceFrameOption: Identifiable, Hashable {
    var id: String { portraitAsset }
    let group: String
    let label: String
    let portraitAsset: String
    let landscapeAsset: String?

    /// Device + color entry whose asset names follow the "<device> - <color> - <orientation>" pattern.
    private init(group: String, label: String) {
        self.group = group
        self.label = label
        self.portraitAsset = "\(group) - \(label) - Portrait"
        self.landscapeAsset = "\(group) - \(label) - Landscape"
    }

    private init(group: String, label: String, assetName: String) {
        self.group = group
        self.label = label
        self.portraitAsset = assetName
        self.landscapeAsset = nil
    }

    static let all: [DeviceFrameOption] = [
        // iPhone 17 Pro Max
        .init(group: "iPhone 17 Pro Max", label: "Cosmic Orange"),
        .init(group: "iPhone 17 Pro Max", label: "Deep Blue"),
        .init(group: "iPhone 17 Pro Max", label: "Silver"),
        // iPhone 17 Pro
        .init(group: "iPhone 17 Pro", label: "Cosmic Orange"),
        .init(group: "iPhone 17 Pro", label: "Deep Blue"),
        .init(group: "iPhone 17 Pro", label: "Silver"),
        // iPhone Air
        .init(group: "iPhone Air", label: "Cloud White"),
        .init(group: "iPhone Air", label: "Light Gold"),
        .init(group: "iPhone Air", label: "Sky Blue"),
        .init(group: "iPhone Air", label: "Space Black"),
        // iPhone 17
        .init(group: "iPhone 17", label: "Black"),
        .init(group: "iPhone 17", label: "Lavender"),
        .init(group: "iPhone 17", label: "Mist Blue"),
        .init(group: "iPhone 17", label: "Sage"),
        .init(group: "iPhone 17", label: "White"),
        // iPad Pro (M5)
        .init(group: "iPad Pro (M5) 13\"", label: "Silver"),
        .init(group: "iPad Pro (M5) 13\"", label: "Space Black"),
        .init(group: "iPad Pro (M5) 11\"", label: "Silver"),
        .init(group: "iPad Pro (M5) 11\"", label: "Space Black"),
        // MacBook Pro M5 (no landscape variant — single asset)
        .init(group: "MacBook Pro M5 14\"", label: "Silver",      assetName: "MacBook Pro M5 14-inch Silver"),
        .init(group: "MacBook Pro M5 14\"", label: "Space Black", assetName: "MacBook Pro M5 14-inch Space Black"),
        .init(group: "MacBook Pro M5 16\"", label: "Silver",      assetName: "MacBook Pro M5 16-inch Silver"),
        .init(group: "MacBook Pro M5 16\"", label: "Space Black", assetName: "MacBook Pro M5 16-inch Space Black"),
    ]

    static var orderedGroups: [String] {
        var seen = Set<String>()
        return all.compactMap { seen.insert($0.group).inserted ? $0.group : nil }
    }

    static func options(in group: String) -> [DeviceFrameOption] {
        all.filter { $0.group == group }
    }

    /// Finds the option owning an asset name, matching either orientation.
    static func option(forAsset assetName: String) -> DeviceFrameOption? {
        all.first { $0.portraitAsset == assetName || $0.landscapeAsset == assetName }
    }
}

// MARK: - Layer model

struct ScreenshotLayer: Codable, Identifiable, Equatable {
    var id: UUID
    var type: LayerType
    /// Optional display name shown in the layers list (mainly for image layers).
    var name: String?
    var xFraction: Double
    var yFraction: Double
    var widthFraction: Double
    var heightFraction: Double
    var isVisible: Bool
    var frameAssetName: String?
    var imageCornerRadius: Double
    /// When true, image scales to fill the layer bounds (cropping if needed). False = fit (letterbox).
    var imageFills: Bool
    /// Uniform scale applied to both width and height of the layer (image + frame together). 1 = natural size.
    var frameScale: Double
    /// Extra zoom applied to the image content on top of fit/fill (1 = automatic size).
    var contentScale: Double
    /// Content nudge inside the layer, as a fraction of the layer's width/height.
    /// Positive X moves the image right, positive Y moves it down. Used to line the
    /// screenshot up with the device frame's screen cut-out.
    var contentOffsetX: Double
    var contentOffsetY: Double

    // Text — `text` is the primary/default string; `translations` holds per-locale overrides.
    var text: String?
    var translations: [String: String]
    var fontSizePt: Double
    var colorHex: String
    var isBold: Bool
    var fontFamily: String
    var fontWeightRaw: String
    var isItalic: Bool
    var tracking: Double
    var alignmentRaw: String
    /// When non-nil, draws a rounded rect behind the text (layer frame = background bounds).
    var textBackgroundHex: String?
    var textPaddingPt: Double
    var textCornerRadiusPt: Double
    /// When true, `text` / translations are treated as Markdown inline styles
    /// (`**bold**`, `*italic*`, `~~strike~~`, `` `code` ``, `++underline++`).
    /// Per-run color is intentionally unsupported — not part of standard Markdown.
    var textUsesMarkdown: Bool
    /// When true, width hugs the measured text (plus padding) instead of `widthFraction`.
    var fitWidthToContent: Bool
    /// When true, height hugs the measured text (plus padding) instead of `heightFraction`.
    var fitHeightToContent: Bool

    // Image — the bytes live in ScreenshotImageStore; the layer only carries the digest.
    var imageRef: String?
    /// Only set when decoding a template saved before images moved out of the layer JSON.
    /// Cleared by `ScreenshotLayer.migrateEmbeddedImages` and never re-encoded.
    private var embeddedImageData: Data?

    // Rotation (degrees, clockwise)
    var rotation: Double

    // Shape layer
    var shapeKindRaw: String
    var shapeEffectRaw: String
    var shapeFill: CanvasBackground?
    var shapeCornerRadiusPt: Double
    var shapeBlurRadius: Double
    var shapeOpacity: Double
    var shapeStrokeColorHex: String
    var shapeStrokeWidth: Double

    /// Image bytes for this layer, resolved through the store.
    var imageData: Data? {
        get {
            if let imageRef { return ScreenshotImageStore.shared.data(for: imageRef) }
            return embeddedImageData
        }
        set {
            embeddedImageData = nil
            imageRef = newValue.map { ScreenshotImageStore.shared.store($0) }
        }
    }

    /// Full-resolution image for export.
    func loadImage() -> NSImage? {
        guard let imageRef else { return embeddedImageData.flatMap(NSImage.init(data:)) }
        return ScreenshotImageStore.shared.image(for: imageRef)
    }

    /// Downsampled image for the editor canvas.
    func loadPreviewImage() -> NSImage? {
        guard let imageRef else { return embeddedImageData.flatMap(NSImage.init(data:)) }
        return ScreenshotImageStore.shared.previewImage(for: imageRef)
    }

    var hasImage: Bool { imageRef != nil || embeddedImageData != nil }

    var shapeKind: ShapeKind {
        get { ShapeKind(rawValue: shapeKindRaw) ?? .rectangle }
        set { shapeKindRaw = newValue.rawValue }
    }

    var shapeEffect: ShapeEffect {
        get { ShapeEffect(rawValue: shapeEffectRaw) ?? .none }
        set { shapeEffectRaw = newValue.rawValue }
    }

    var resolvedShapeFill: CanvasBackground {
        shapeFill ?? CanvasBackground.shapeDefault
    }

    /// Moves any legacy inline image bytes into the store. Returns true when something
    /// changed, so the caller knows to persist the slimmed-down JSON.
    static func migrateEmbeddedImages(in layers: inout [ScreenshotLayer]) -> Bool {
        var changed = false
        for index in layers.indices {
            guard let legacy = layers[index].embeddedImageData else { continue }
            layers[index].imageRef = ScreenshotImageStore.shared.store(legacy)
            layers[index].embeddedImageData = nil
            changed = true
        }
        return changed
    }

    enum LayerType: String, Codable {
        case text, image, shape
    }

    var fontWeight: LayerFontWeight {
        get { LayerFontWeight(rawValue: fontWeightRaw) ?? (isBold ? .bold : .regular) }
        set { fontWeightRaw = newValue.rawValue; isBold = (newValue == .bold || newValue == .heavy || newValue == .black) }
    }

    var textAlignment: LayerTextAlignment {
        get { LayerTextAlignment(rawValue: alignmentRaw) ?? .center }
        set { alignmentRaw = newValue.rawValue }
    }

    /// Text for a locale, falling back to the primary `text` string.
    func resolvedText(for locale: String?) -> String? {
        if let locale {
            if let value = translations[locale], !value.isEmpty {
                return value
            }
            if let key = translations.keys.first(where: { $0.caseInsensitiveCompare(locale) == .orderedSame }),
               let value = translations[key], !value.isEmpty {
                return value
            }
        }
        return text
    }

    /// Writes text for a locale. Primary locale (or nil) also updates `text`.
    mutating func setResolvedText(_ value: String, for locale: String?, primaryLocale: String?) {
        if let locale {
            translations[locale] = value
            let isPrimary = primaryLocale.map {
                $0.caseInsensitiveCompare(locale) == .orderedSame
            } ?? false
            if isPrimary {
                text = value
            }
        } else {
            text = value
        }
    }

    init(type: LayerType) {
        self.id = UUID()
        self.type = type
        self.name = nil
        self.xFraction = 0.1
        self.yFraction = 0.1
        self.widthFraction = 0.8
        self.heightFraction = type == .text ? 0.1 : 0.4
        self.isVisible = true
        self.frameAssetName = nil
        self.imageCornerRadius = 0
        self.imageFills = false
        self.frameScale = 1
        self.contentScale = 1
        self.contentOffsetX = 0
        self.contentOffsetY = 0
        self.text = "Your text here"
        self.translations = [:]
        self.fontSizePt = 40
        self.colorHex = "#FFFFFF"
        self.isBold = true
        self.fontFamily = "System"
        self.fontWeightRaw = LayerFontWeight.bold.rawValue
        self.isItalic = false
        self.tracking = 0
        self.alignmentRaw = LayerTextAlignment.center.rawValue
        self.textBackgroundHex = nil
        self.textPaddingPt = 12
        self.textCornerRadiusPt = 20
        self.textUsesMarkdown = true
        self.fitWidthToContent = false
        self.fitHeightToContent = false
        self.imageRef = nil
        self.embeddedImageData = nil
        self.rotation = 0
        self.shapeKindRaw = ShapeKind.rectangle.rawValue
        self.shapeEffectRaw = ShapeEffect.none.rawValue
        self.shapeFill = type == .shape ? CanvasBackground.shapeDefault : nil
        self.shapeCornerRadiusPt = 20
        self.shapeBlurRadius = 10
        self.shapeOpacity = 1.0
        self.shapeStrokeColorHex = "#FFFFFF"
        self.shapeStrokeWidth = type == .shape ? 2.0 : 0
    }

    /// Label shown in the layers list: custom name when set, otherwise text preview or "Image".
    func listLabel(previewLocale: String?) -> String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return name
        }
        switch type {
        case .text:
            return plainPreviewLabel(for: previewLocale)
        case .image:
            return "Image"
        case .shape:
            return shapeKind.title
        }
    }

    var hasTextBackground: Bool {
        get { textBackgroundHex != nil }
        set {
            if newValue {
                if textBackgroundHex == nil { textBackgroundHex = "#FFFFFF" }
            } else {
                textBackgroundHex = nil
            }
        }
    }

    enum CodingKeys: String, CodingKey {
        case id, type, name, xFraction, yFraction, widthFraction, heightFraction, isVisible, frameAssetName, imageCornerRadius, imageFills
        case frameScale
        case contentScale, contentOffsetX, contentOffsetY
        case text, translations, fontSizePt, colorHex, isBold, fontFamily, fontWeightRaw, isItalic, tracking, alignmentRaw
        case textBackgroundHex, textPaddingPt, textCornerRadiusPt, textUsesMarkdown
        case fitWidthToContent, fitHeightToContent
        case imageRef
        /// Legacy key: inline bytes from templates saved before the image store existed.
        case imageData
        case rotation
        case shapeKindRaw, shapeEffectRaw, shapeFill, shapeCornerRadiusPt, shapeBlurRadius, shapeOpacity
        case shapeStrokeColorHex, shapeStrokeWidth
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try c.decode(LayerType.self, forKey: .type)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        xFraction = try c.decodeIfPresent(Double.self, forKey: .xFraction) ?? 0.1
        yFraction = try c.decodeIfPresent(Double.self, forKey: .yFraction) ?? 0.1
        widthFraction = try c.decodeIfPresent(Double.self, forKey: .widthFraction) ?? 0.8
        heightFraction = try c.decodeIfPresent(Double.self, forKey: .heightFraction) ?? 0.1
        isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        frameAssetName = try c.decodeIfPresent(String.self, forKey: .frameAssetName)
        imageCornerRadius = try c.decodeIfPresent(Double.self, forKey: .imageCornerRadius) ?? 0
        imageFills = try c.decodeIfPresent(Bool.self, forKey: .imageFills) ?? false
        frameScale = try c.decodeIfPresent(Double.self, forKey: .frameScale) ?? 1
        contentScale = try c.decodeIfPresent(Double.self, forKey: .contentScale) ?? 1
        contentOffsetX = try c.decodeIfPresent(Double.self, forKey: .contentOffsetX) ?? 0
        contentOffsetY = try c.decodeIfPresent(Double.self, forKey: .contentOffsetY) ?? 0
        text = try c.decodeIfPresent(String.self, forKey: .text)
        translations = try c.decodeIfPresent([String: String].self, forKey: .translations) ?? [:]
        fontSizePt = try c.decodeIfPresent(Double.self, forKey: .fontSizePt) ?? 40
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? "#FFFFFF"
        isBold = try c.decodeIfPresent(Bool.self, forKey: .isBold) ?? true
        fontFamily = try c.decodeIfPresent(String.self, forKey: .fontFamily) ?? "System"
        fontWeightRaw = try c.decodeIfPresent(String.self, forKey: .fontWeightRaw)
            ?? (isBold ? LayerFontWeight.bold.rawValue : LayerFontWeight.regular.rawValue)
        isItalic = try c.decodeIfPresent(Bool.self, forKey: .isItalic) ?? false
        tracking = try c.decodeIfPresent(Double.self, forKey: .tracking) ?? 0
        alignmentRaw = try c.decodeIfPresent(String.self, forKey: .alignmentRaw)
            ?? LayerTextAlignment.center.rawValue
        textBackgroundHex = try c.decodeIfPresent(String.self, forKey: .textBackgroundHex)
        textPaddingPt = try c.decodeIfPresent(Double.self, forKey: .textPaddingPt) ?? 12
        textCornerRadiusPt = try c.decodeIfPresent(Double.self, forKey: .textCornerRadiusPt) ?? 20
        textUsesMarkdown = try c.decodeIfPresent(Bool.self, forKey: .textUsesMarkdown) ?? true
        fitWidthToContent = try c.decodeIfPresent(Bool.self, forKey: .fitWidthToContent) ?? false
        fitHeightToContent = try c.decodeIfPresent(Bool.self, forKey: .fitHeightToContent) ?? false
        imageRef = try c.decodeIfPresent(String.self, forKey: .imageRef)
        embeddedImageData = imageRef == nil
            ? try c.decodeIfPresent(Data.self, forKey: .imageData)
            : nil
        rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        shapeKindRaw = try c.decodeIfPresent(String.self, forKey: .shapeKindRaw) ?? ShapeKind.rectangle.rawValue
        shapeEffectRaw = try c.decodeIfPresent(String.self, forKey: .shapeEffectRaw) ?? ShapeEffect.none.rawValue
        shapeFill = try c.decodeIfPresent(CanvasBackground.self, forKey: .shapeFill)
        shapeCornerRadiusPt = try c.decodeIfPresent(Double.self, forKey: .shapeCornerRadiusPt) ?? 20
        shapeBlurRadius = try c.decodeIfPresent(Double.self, forKey: .shapeBlurRadius) ?? 10
        shapeOpacity = try c.decodeIfPresent(Double.self, forKey: .shapeOpacity) ?? 1.0
        shapeStrokeColorHex = try c.decodeIfPresent(String.self, forKey: .shapeStrokeColorHex) ?? "#FFFFFF"
        shapeStrokeWidth = try c.decodeIfPresent(Double.self, forKey: .shapeStrokeWidth) ?? 0
    }

    /// Written explicitly so the legacy `imageData` key is never re-emitted.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(type, forKey: .type)
        try c.encodeIfPresent(name, forKey: .name)
        try c.encode(xFraction, forKey: .xFraction)
        try c.encode(yFraction, forKey: .yFraction)
        try c.encode(widthFraction, forKey: .widthFraction)
        try c.encode(heightFraction, forKey: .heightFraction)
        try c.encode(isVisible, forKey: .isVisible)
        try c.encodeIfPresent(frameAssetName, forKey: .frameAssetName)
        try c.encode(imageCornerRadius, forKey: .imageCornerRadius)
        try c.encode(imageFills, forKey: .imageFills)
        try c.encode(frameScale, forKey: .frameScale)
        try c.encode(contentScale, forKey: .contentScale)
        try c.encode(contentOffsetX, forKey: .contentOffsetX)
        try c.encode(contentOffsetY, forKey: .contentOffsetY)
        try c.encodeIfPresent(text, forKey: .text)
        try c.encode(translations, forKey: .translations)
        try c.encode(fontSizePt, forKey: .fontSizePt)
        try c.encode(colorHex, forKey: .colorHex)
        try c.encode(isBold, forKey: .isBold)
        try c.encode(fontFamily, forKey: .fontFamily)
        try c.encode(fontWeightRaw, forKey: .fontWeightRaw)
        try c.encode(isItalic, forKey: .isItalic)
        try c.encode(tracking, forKey: .tracking)
        try c.encode(alignmentRaw, forKey: .alignmentRaw)
        try c.encodeIfPresent(textBackgroundHex, forKey: .textBackgroundHex)
        try c.encode(textPaddingPt, forKey: .textPaddingPt)
        try c.encode(textCornerRadiusPt, forKey: .textCornerRadiusPt)
        try c.encode(textUsesMarkdown, forKey: .textUsesMarkdown)
        try c.encode(fitWidthToContent, forKey: .fitWidthToContent)
        try c.encode(fitHeightToContent, forKey: .fitHeightToContent)
        try c.encodeIfPresent(imageRef, forKey: .imageRef)
        try c.encode(rotation, forKey: .rotation)
        try c.encode(shapeKindRaw, forKey: .shapeKindRaw)
        try c.encode(shapeEffectRaw, forKey: .shapeEffectRaw)
        try c.encodeIfPresent(shapeFill, forKey: .shapeFill)
        try c.encode(shapeCornerRadiusPt, forKey: .shapeCornerRadiusPt)
        try c.encode(shapeBlurRadius, forKey: .shapeBlurRadius)
        try c.encode(shapeOpacity, forKey: .shapeOpacity)
        try c.encode(shapeStrokeColorHex, forKey: .shapeStrokeColorHex)
        try c.encode(shapeStrokeWidth, forKey: .shapeStrokeWidth)
    }
}

extension ScreenshotLayer {
    /// Rect the image content occupies inside `layerRect` (top-left origin space):
    /// fit/fill aspect scaling, then the user's extra `contentScale` zoom and
    /// `contentOffset` nudge. Both preview and PNG export draw through this so the
    /// canvas is a faithful WYSIWYG of the output.
    func imageContentRect(imageSize: CGSize, in layerRect: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return layerRect }
        let baseScale = imageFills
            ? max(layerRect.width / imageSize.width, layerRect.height / imageSize.height)
            : min(layerRect.width / imageSize.width, layerRect.height / imageSize.height)
        let scale = baseScale * max(0.01, contentScale)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: layerRect.midX - width / 2 + contentOffsetX * layerRect.width,
            y: layerRect.midY - height / 2 + contentOffsetY * layerRect.height,
            width: width,
            height: height
        )
    }

    /// Centred aspect-fit rect for a device bezel inside `layerRect`. The preview draws
    /// the frame with SwiftUI's `.fit` content mode, so the export has to letterbox the
    /// same way — `NSImage.draw(in:)` would stretch it to fill instead.
    static func deviceFrameRect(frameSize: CGSize, in layerRect: CGRect) -> CGRect {
        guard frameSize.width > 0, frameSize.height > 0 else { return layerRect }
        let scale = min(layerRect.width / frameSize.width, layerRect.height / frameSize.height)
        let width = frameSize.width * scale
        let height = frameSize.height * scale
        return CGRect(
            x: layerRect.midX - width / 2,
            y: layerRect.midY - height / 2,
            width: width,
            height: height
        )
    }
}

// MARK: - Image layer style (copy / paste / presets)

/// The image-section settings that travel together when copying between layers or
/// saving as a preset: device frame, fit/fill, corner radius, and content transform.
/// Layout position/size are not included.
struct ImageLayerStyle: Codable, Equatable {
    var frameAssetName: String?
    var imageFills: Bool
    var imageCornerRadius: Double
    var frameScale: Double
    var contentScale: Double
    var contentOffsetX: Double
    var contentOffsetY: Double

    init(from layer: ScreenshotLayer) {
        frameAssetName = layer.frameAssetName
        imageFills = layer.imageFills
        imageCornerRadius = layer.imageCornerRadius
        frameScale = layer.frameScale
        contentScale = layer.contentScale
        contentOffsetX = layer.contentOffsetX
        contentOffsetY = layer.contentOffsetY
    }

    func apply(to layer: inout ScreenshotLayer) {
        layer.frameAssetName = frameAssetName
        layer.imageFills = imageFills
        layer.imageCornerRadius = imageCornerRadius
        layer.frameScale = frameScale
        layer.contentScale = contentScale
        layer.contentOffsetX = contentOffsetX
        layer.contentOffsetY = contentOffsetY
    }

    func matches(_ layer: ScreenshotLayer) -> Bool {
        self == ImageLayerStyle(from: layer)
    }
}

/// A named, persisted snapshot of an `ImageLayerStyle`.
struct ImageLayerStylePreset: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var style: ImageLayerStyle

    init(id: UUID = UUID(), name: String, style: ImageLayerStyle) {
        self.id = id
        self.name = name
        self.style = style
    }
}

/// Session clipboard for image-layer styles, plus named presets and an optional
/// favorite used as the default for newly added images and Reset.
@MainActor
final class ImageLayerStyleStore: ObservableObject {
    static let shared = ImageLayerStyleStore()
    private static let defaultsKey = "ScreenshotEditor.defaultImageLayerStyle"
    private static let presetsKey = "ScreenshotEditor.imageLayerStylePresets"
    private static let favoriteKey = "ScreenshotEditor.favoriteImageLayerStylePresetId"

    @Published var copied: ImageLayerStyle?
    @Published private(set) var presets: [ImageLayerStylePreset] = []
    @Published private(set) var favoritePresetId: UUID?

    /// Style of the favorited preset, if any — used for Reset and new image layers.
    var savedDefault: ImageLayerStyle? {
        presets.first(where: { $0.id == favoritePresetId })?.style
    }

    private init() {
        load()
    }

    func addPreset(name: String, style: ImageLayerStyle) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolved = trimmed.isEmpty ? nextPresetName() : trimmed
        presets.append(ImageLayerStylePreset(name: resolved, style: style))
        persistPresets()
    }

    func renamePreset(id: UUID, name: String) {
        guard let index = presets.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        presets[index].name = trimmed
        persistPresets()
    }

    func removePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        if favoritePresetId == id {
            favoritePresetId = nil
            persistFavorite()
        }
        persistPresets()
    }

    func toggleFavorite(id: UUID) {
        if favoritePresetId == id {
            favoritePresetId = nil
        } else {
            favoritePresetId = id
        }
        persistFavorite()
    }

    /// Applies the favorite preset (when set) to a freshly created image layer.
    func applyDefault(to layer: inout ScreenshotLayer) {
        savedDefault?.apply(to: &layer)
    }

    func nextPresetName() -> String {
        "Preset \(presets.count + 1)"
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: Self.presetsKey),
           let decoded = try? JSONDecoder().decode([ImageLayerStylePreset].self, from: data) {
            presets = decoded
        }

        if let idString = UserDefaults.standard.string(forKey: Self.favoriteKey),
           let id = UUID(uuidString: idString),
           presets.contains(where: { $0.id == id }) {
            favoritePresetId = id
        }

        // Migrate the previous single saved-default into a favorited preset.
        if presets.isEmpty,
           let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
           let legacy = try? JSONDecoder().decode(ImageLayerStyle.self, from: data) {
            let preset = ImageLayerStylePreset(name: "Default", style: legacy)
            presets = [preset]
            favoritePresetId = preset.id
            persistPresets()
            persistFavorite()
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        } else if favoritePresetId == nil,
                  let data = UserDefaults.standard.data(forKey: Self.defaultsKey),
                  let legacy = try? JSONDecoder().decode(ImageLayerStyle.self, from: data),
                  let match = presets.first(where: { $0.style == legacy }) {
            favoritePresetId = match.id
            persistFavorite()
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        } else if UserDefaults.standard.data(forKey: Self.defaultsKey) != nil {
            UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
        }
    }

    private func persistPresets() {
        if let data = try? JSONEncoder().encode(presets) {
            UserDefaults.standard.set(data, forKey: Self.presetsKey)
        }
    }

    private func persistFavorite() {
        if let favoritePresetId {
            UserDefaults.standard.set(favoritePresetId.uuidString, forKey: Self.favoriteKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.favoriteKey)
        }
    }
}

// MARK: - SwiftData model

@Model
final class ScreenshotTemplate {
    var name: String
    var deviceTypeRawValue: String
    var backgroundColorHex: String
    var backgroundStyleData: Data = Data()
    var layersData: Data
    var createdAt: Date
    var app: AppRecord?

    // Decode caches: `layersData` embeds image payloads (base64 in JSON), so decoding
    // it on every SwiftUI body evaluation is what made the canvas lag. All reads and
    // writes go through the computed properties below, keeping the caches coherent.
    @Transient private var layersCache: [ScreenshotLayer]? = nil
    @Transient private var backgroundCache: CanvasBackground? = nil

    var deviceType: DeviceType {
        get { DeviceType(rawValue: deviceTypeRawValue) ?? .iPhone67 }
        set { deviceTypeRawValue = newValue.rawValue }
    }

    var background: CanvasBackground {
        get {
            // Read the persisted property even on a cache hit — @Transient caches are
            // not observation-tracked, so this access is what keeps SwiftUI views
            // subscribed to background changes.
            let data = backgroundStyleData
            if let backgroundCache { return backgroundCache }
            let decoded: CanvasBackground
            if !data.isEmpty,
               let stored = try? JSONDecoder().decode(CanvasBackground.self, from: data) {
                decoded = stored
            } else {
                var fallback = CanvasBackground.default
                fallback.kind = .solid
                fallback.solidHex = backgroundColorHex
                decoded = fallback
            }
            backgroundCache = decoded
            return decoded
        }
        set {
            backgroundCache = newValue
            backgroundStyleData = (try? JSONEncoder().encode(newValue)) ?? Data()
            if newValue.kind == .solid {
                backgroundColorHex = newValue.solidHex
            } else if let first = newValue.sortedStops.first {
                backgroundColorHex = first.hex
            }
        }
    }

    var layers: [ScreenshotLayer] {
        get {
            // Same observation-keeping read as `background`: without it, views stop
            // updating on direct layer writes once the cache is warm.
            let data = layersData
            if let layersCache { return layersCache }
            guard !data.isEmpty else { return [] }
            var decoded = (try? JSONDecoder().decode([ScreenshotLayer].self, from: data)) ?? []
            // Templates saved before the image store carried their PNG bytes inline.
            // Move them out once, on first read, and persist the slimmer JSON.
            if ScreenshotLayer.migrateEmbeddedImages(in: &decoded),
               let migrated = try? JSONEncoder().encode(decoded) {
                layersData = migrated
            }
            layersCache = decoded
            return decoded
        }
        set {
            layersCache = newValue
            layersData = (try? JSONEncoder().encode(newValue)) ?? Data()
        }
    }

    init(name: String, deviceType: DeviceType = .iPhone67) {
        self.name = name
        self.deviceTypeRawValue = deviceType.rawValue
        self.backgroundColorHex = "#1A1A2E"
        self.backgroundStyleData = (try? JSONEncoder().encode(CanvasBackground.default)) ?? Data()
        self.layersData = Data()
        self.createdAt = .now
    }
}

// MARK: - Color hex helpers

extension Color {
    /// Parses #RRGGBB (6-char) or #RRGGBBAA (8-char) hex strings.
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        switch hex.count {
        case 8:
            self.init(
                red:     Double((value >> 24) & 0xFF) / 255,
                green:   Double((value >> 16) & 0xFF) / 255,
                blue:    Double((value >>  8) & 0xFF) / 255,
                opacity: Double( value        & 0xFF) / 255
            )
        case 6:
            self.init(
                red:   Double((value >> 16) & 0xFF) / 255,
                green: Double((value >>  8) & 0xFF) / 255,
                blue:  Double( value        & 0xFF) / 255
            )
        default:
            self.init(red: 0, green: 0, blue: 0)
        }
    }

    /// Returns #RRGGBB for fully-opaque colors, #RRGGBBAA when alpha < 1.
    func toHex() -> String {
        guard let components = NSColor(self).usingColorSpace(.sRGB)?.cgColor.components,
              components.count >= 3 else { return "#000000" }
        let r = Int((components[0] * 255).rounded())
        let g = Int((components[1] * 255).rounded())
        let b = Int((components[2] * 255).rounded())
        let a = components.count >= 4 ? Int((components[3] * 255).rounded()) : 255
        if a >= 255 {
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        return String(format: "#%02X%02X%02X%02X", r, g, b, a)
    }
}
