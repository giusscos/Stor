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

// MARK: - Image cache

/// Caches decoded NSImage objects so NSImage(data:) is only called once per unique image payload.
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private var store: [UUID: (count: Int, image: NSImage)] = [:]
    private var previewStore: [UUID: (count: Int, image: NSImage)] = [:]

    /// Longest edge of the downsampled canvas-preview image. The editor canvas is only
    /// a few hundred points wide, so drawing the full-resolution screenshot every frame
    /// wastes GPU/CPU; export still uses `image(for:id:)`.
    private static let previewMaxPixelSize = 1200

    func image(for data: Data, id: UUID) -> NSImage? {
        if let entry = store[id], entry.count == data.count { return entry.image }
        guard let img = NSImage(data: data) else { return nil }
        store[id] = (data.count, img)
        return img
    }

    /// Downsampled version for on-canvas preview. Falls back to the full image.
    func previewImage(for data: Data, id: UUID) -> NSImage? {
        if let entry = previewStore[id], entry.count == data.count { return entry.image }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: Self.previewMaxPixelSize
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return image(for: data, id: id)
        }
        let img = NSImage(cgImage: cg, size: .zero)
        previewStore[id] = (data.count, img)
        return img
    }

    func invalidate(_ id: UUID) {
        store.removeValue(forKey: id)
        previewStore.removeValue(forKey: id)
    }
}

// MARK: - Layer model

struct ScreenshotLayer: Codable, Identifiable {
    var id: UUID
    var type: LayerType
    var xFraction: Double
    var yFraction: Double
    var widthFraction: Double
    var heightFraction: Double
    var isVisible: Bool
    var frameAssetName: String?
    var imageCornerRadius: Double
    /// When true, image scales to fill the layer bounds (cropping if needed). False = fit (letterbox).
    var imageFills: Bool
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

    // Image
    var imageData: Data?

    enum LayerType: String, Codable {
        case text, image
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
        self.xFraction = 0.1
        self.yFraction = 0.1
        self.widthFraction = 0.8
        self.heightFraction = type == .text ? 0.1 : 0.4
        self.isVisible = true
        self.frameAssetName = nil
        self.imageCornerRadius = 0
        self.imageFills = false
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
        self.imageData = nil
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
        case id, type, xFraction, yFraction, widthFraction, heightFraction, isVisible, frameAssetName, imageCornerRadius, imageFills
        case contentScale, contentOffsetX, contentOffsetY
        case text, translations, fontSizePt, colorHex, isBold, fontFamily, fontWeightRaw, isItalic, tracking, alignmentRaw
        case textBackgroundHex, textPaddingPt, textCornerRadiusPt, textUsesMarkdown
        case fitWidthToContent, fitHeightToContent
        case imageData
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        type = try c.decode(LayerType.self, forKey: .type)
        xFraction = try c.decodeIfPresent(Double.self, forKey: .xFraction) ?? 0.1
        yFraction = try c.decodeIfPresent(Double.self, forKey: .yFraction) ?? 0.1
        widthFraction = try c.decodeIfPresent(Double.self, forKey: .widthFraction) ?? 0.8
        heightFraction = try c.decodeIfPresent(Double.self, forKey: .heightFraction) ?? 0.1
        isVisible = try c.decodeIfPresent(Bool.self, forKey: .isVisible) ?? true
        frameAssetName = try c.decodeIfPresent(String.self, forKey: .frameAssetName)
        imageCornerRadius = try c.decodeIfPresent(Double.self, forKey: .imageCornerRadius) ?? 0
        imageFills = try c.decodeIfPresent(Bool.self, forKey: .imageFills) ?? false
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
        imageData = try c.decodeIfPresent(Data.self, forKey: .imageData)
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
}

// MARK: - Image layer style (copy / paste / default)

/// The image-layer settings that travel together when copying between layers or
/// saving as the default for newly added images: device frame, fit/fill, corner
/// radius, content transform, and layout box.
struct ImageLayerStyle: Codable {
    var frameAssetName: String?
    var imageFills: Bool
    var imageCornerRadius: Double
    var contentScale: Double
    var contentOffsetX: Double
    var contentOffsetY: Double
    var xFraction: Double
    var yFraction: Double
    var widthFraction: Double
    var heightFraction: Double

    init(from layer: ScreenshotLayer) {
        frameAssetName = layer.frameAssetName
        imageFills = layer.imageFills
        imageCornerRadius = layer.imageCornerRadius
        contentScale = layer.contentScale
        contentOffsetX = layer.contentOffsetX
        contentOffsetY = layer.contentOffsetY
        xFraction = layer.xFraction
        yFraction = layer.yFraction
        widthFraction = layer.widthFraction
        heightFraction = layer.heightFraction
    }

    func apply(to layer: inout ScreenshotLayer) {
        layer.frameAssetName = frameAssetName
        layer.imageFills = imageFills
        layer.imageCornerRadius = imageCornerRadius
        layer.contentScale = contentScale
        layer.contentOffsetX = contentOffsetX
        layer.contentOffsetY = contentOffsetY
        layer.xFraction = xFraction
        layer.yFraction = yFraction
        layer.widthFraction = widthFraction
        layer.heightFraction = heightFraction
    }
}

/// Session clipboard for image-layer styles plus the persisted default applied to
/// every newly added image layer.
@MainActor
final class ImageLayerStyleStore: ObservableObject {
    static let shared = ImageLayerStyleStore()
    private static let defaultsKey = "ScreenshotEditor.defaultImageLayerStyle"

    @Published var copied: ImageLayerStyle?
    @Published private(set) var savedDefault: ImageLayerStyle?

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.defaultsKey) {
            savedDefault = try? JSONDecoder().decode(ImageLayerStyle.self, from: data)
        }
    }

    func saveAsDefault(_ style: ImageLayerStyle) {
        savedDefault = style
        if let data = try? JSONEncoder().encode(style) {
            UserDefaults.standard.set(data, forKey: Self.defaultsKey)
        }
    }

    func clearDefault() {
        savedDefault = nil
        UserDefaults.standard.removeObject(forKey: Self.defaultsKey)
    }

    /// Applies the saved default (when set) to a freshly created image layer.
    func applyDefault(to layer: inout ScreenshotLayer) {
        savedDefault?.apply(to: &layer)
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
            let decoded = (try? JSONDecoder().decode([ScreenshotLayer].self, from: data)) ?? []
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
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        let r, g, b: UInt64
        switch hex.count {
        case 6:  (r, g, b) = (value >> 16, value >> 8 & 0xFF, value & 0xFF)
        default: (r, g, b) = (0, 0, 0)
        }
        self.init(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    func toHex() -> String {
        guard let components = NSColor(self).usingColorSpace(.sRGB)?.cgColor.components,
              components.count >= 3 else { return "#000000" }
        return String(format: "#%02X%02X%02X",
                      Int(components[0] * 255),
                      Int(components[1] * 255),
                      Int(components[2] * 255))
    }
}
