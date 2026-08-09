import SwiftData
import SwiftUI
import Foundation
import AppKit

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

struct DeviceFrameOption: Identifiable, Hashable {
    var id: String { assetName }
    let group: String
    let label: String
    let assetName: String

    static let all: [DeviceFrameOption] = [
        // iPhone 17 Pro Max
        .init(group: "iPhone 17 Pro Max", label: "Cosmic Orange — Portrait",  assetName: "iPhone 17 Pro Max - Cosmic Orange - Portrait"),
        .init(group: "iPhone 17 Pro Max", label: "Cosmic Orange — Landscape", assetName: "iPhone 17 Pro Max - Cosmic Orange - Landscape"),
        .init(group: "iPhone 17 Pro Max", label: "Deep Blue — Portrait",      assetName: "iPhone 17 Pro Max - Deep Blue - Portrait"),
        .init(group: "iPhone 17 Pro Max", label: "Deep Blue — Landscape",     assetName: "iPhone 17 Pro Max - Deep Blue - Landscape"),
        .init(group: "iPhone 17 Pro Max", label: "Silver — Portrait",         assetName: "iPhone 17 Pro Max - Silver - Portrait"),
        .init(group: "iPhone 17 Pro Max", label: "Silver — Landscape",        assetName: "iPhone 17 Pro Max - Silver - Landscape"),
        // iPhone 17 Pro
        .init(group: "iPhone 17 Pro", label: "Cosmic Orange — Portrait",  assetName: "iPhone 17 Pro - Cosmic Orange - Portrait"),
        .init(group: "iPhone 17 Pro", label: "Cosmic Orange — Landscape", assetName: "iPhone 17 Pro - Cosmic Orange - Landscape"),
        .init(group: "iPhone 17 Pro", label: "Deep Blue — Portrait",      assetName: "iPhone 17 Pro - Deep Blue - Portrait"),
        .init(group: "iPhone 17 Pro", label: "Deep Blue — Landscape",     assetName: "iPhone 17 Pro - Deep Blue - Landscape"),
        .init(group: "iPhone 17 Pro", label: "Silver — Portrait",         assetName: "iPhone 17 Pro - Silver - Portrait"),
        .init(group: "iPhone 17 Pro", label: "Silver — Landscape",        assetName: "iPhone 17 Pro - Silver - Landscape"),
        // iPhone Air
        .init(group: "iPhone Air", label: "Cloud White — Portrait",  assetName: "iPhone Air - Cloud White - Portrait"),
        .init(group: "iPhone Air", label: "Cloud White — Landscape", assetName: "iPhone Air - Cloud White - Landscape"),
        .init(group: "iPhone Air", label: "Light Gold — Portrait",   assetName: "iPhone Air - Light Gold - Portrait"),
        .init(group: "iPhone Air", label: "Light Gold — Landscape",  assetName: "iPhone Air - Light Gold - Landscape"),
        .init(group: "iPhone Air", label: "Sky Blue — Portrait",     assetName: "iPhone Air - Sky Blue - Portrait"),
        .init(group: "iPhone Air", label: "Sky Blue — Landscape",    assetName: "iPhone Air - Sky Blue - Landscape"),
        .init(group: "iPhone Air", label: "Space Black — Portrait",  assetName: "iPhone Air - Space Black - Portrait"),
        .init(group: "iPhone Air", label: "Space Black — Landscape", assetName: "iPhone Air - Space Black - Landscape"),
        // iPhone 17
        .init(group: "iPhone 17", label: "Black — Portrait",      assetName: "iPhone 17 - Black - Portrait"),
        .init(group: "iPhone 17", label: "Black — Landscape",     assetName: "iPhone 17 - Black - Landscape"),
        .init(group: "iPhone 17", label: "Lavender — Portrait",   assetName: "iPhone 17 - Lavender - Portrait"),
        .init(group: "iPhone 17", label: "Lavender — Landscape",  assetName: "iPhone 17 - Lavender - Landscape"),
        .init(group: "iPhone 17", label: "Mist Blue — Portrait",  assetName: "iPhone 17 - Mist Blue - Portrait"),
        .init(group: "iPhone 17", label: "Mist Blue — Landscape", assetName: "iPhone 17 - Mist Blue - Landscape"),
        .init(group: "iPhone 17", label: "Sage — Portrait",       assetName: "iPhone 17 - Sage - Portrait"),
        .init(group: "iPhone 17", label: "Sage — Landscape",      assetName: "iPhone 17 - Sage - Landscape"),
        .init(group: "iPhone 17", label: "White — Portrait",      assetName: "iPhone 17 - White - Portrait"),
        .init(group: "iPhone 17", label: "White — Landscape",     assetName: "iPhone 17 - White - Landscape"),
        // iPad Pro (M5) 13"
        .init(group: "iPad Pro (M5) 13\"", label: "Silver — Portrait",       assetName: "iPad Pro (M5) 13\" - Silver - Portrait"),
        .init(group: "iPad Pro (M5) 13\"", label: "Silver — Landscape",      assetName: "iPad Pro (M5) 13\" - Silver - Landscape"),
        .init(group: "iPad Pro (M5) 13\"", label: "Space Black — Portrait",  assetName: "iPad Pro (M5) 13\" - Space Black - Portrait"),
        .init(group: "iPad Pro (M5) 13\"", label: "Space Black — Landscape", assetName: "iPad Pro (M5) 13\" - Space Black - Landscape"),
        // iPad Pro (M5) 11"
        .init(group: "iPad Pro (M5) 11\"", label: "Silver — Portrait",       assetName: "iPad Pro (M5) 11\" - Silver - Portrait"),
        .init(group: "iPad Pro (M5) 11\"", label: "Silver — Landscape",      assetName: "iPad Pro (M5) 11\" - Silver - Landscape"),
        .init(group: "iPad Pro (M5) 11\"", label: "Space Black — Portrait",  assetName: "iPad Pro (M5) 11\" - Space Black - Portrait"),
        .init(group: "iPad Pro (M5) 11\"", label: "Space Black — Landscape", assetName: "iPad Pro (M5) 11\" - Space Black - Landscape"),
        // MacBook Pro M5 14-inch
        .init(group: "MacBook Pro M5 14\"", label: "Silver",      assetName: "MacBook Pro M5 14-inch Silver"),
        .init(group: "MacBook Pro M5 14\"", label: "Space Black", assetName: "MacBook Pro M5 14-inch Space Black"),
        // MacBook Pro M5 16-inch
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
}

// MARK: - Image cache

/// Caches decoded NSImage objects so NSImage(data:) is only called once per unique image payload.
@MainActor
final class ImageCache {
    static let shared = ImageCache()
    private var store: [UUID: (count: Int, image: NSImage)] = [:]

    func image(for data: Data, id: UUID) -> NSImage? {
        if let entry = store[id], entry.count == data.count { return entry.image }
        guard let img = NSImage(data: data) else { return nil }
        store[id] = (data.count, img)
        return img
    }

    func invalidate(_ id: UUID) { store.removeValue(forKey: id) }
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

    var deviceType: DeviceType {
        get { DeviceType(rawValue: deviceTypeRawValue) ?? .iPhone67 }
        set { deviceTypeRawValue = newValue.rawValue }
    }

    var background: CanvasBackground {
        get {
            if !backgroundStyleData.isEmpty,
               let decoded = try? JSONDecoder().decode(CanvasBackground.self, from: backgroundStyleData) {
                return decoded
            }
            var fallback = CanvasBackground.default
            fallback.kind = .solid
            fallback.solidHex = backgroundColorHex
            return fallback
        }
        set {
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
            guard !layersData.isEmpty else { return [] }
            return (try? JSONDecoder().decode([ScreenshotLayer].self, from: layersData)) ?? []
        }
        set {
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
