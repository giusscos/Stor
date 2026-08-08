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

    var canvasSize: CGSize {
        switch self {
        case .iPhone69:  return CGSize(width: 1320, height: 2868)
        case .iPhone67:  return CGSize(width: 1290, height: 2796)
        case .iPhone65:  return CGSize(width: 1284, height: 2778)
        case .iPadPro13: return CGSize(width: 2064, height: 2752)
        }
    }

    var aspectRatio: CGFloat { canvasSize.width / canvasSize.height }

    var ascDisplayType: String {
        switch self {
        case .iPhone69:  return "APP_IPHONE_69"
        case .iPhone67:  return "APP_IPHONE_67"
        case .iPhone65:  return "APP_IPHONE_65"
        case .iPadPro13: return "APP_IPAD_PRO_3GEN_129"
        }
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

    // Text
    var text: String?
    var fontSizePt: Double
    var colorHex: String
    var isBold: Bool
    var fontFamily: String
    var fontWeightRaw: String
    var isItalic: Bool
    var tracking: Double
    var alignmentRaw: String

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

    init(type: LayerType) {
        self.id = UUID()
        self.type = type
        self.xFraction = 0.1
        self.yFraction = 0.1
        self.widthFraction = 0.8
        self.heightFraction = type == .text ? 0.1 : 0.4
        self.isVisible = true
        self.text = "Your text here"
        self.fontSizePt = 40
        self.colorHex = "#FFFFFF"
        self.isBold = true
        self.fontFamily = "System"
        self.fontWeightRaw = LayerFontWeight.bold.rawValue
        self.isItalic = false
        self.tracking = 0
        self.alignmentRaw = LayerTextAlignment.center.rawValue
        self.imageData = nil
    }

    enum CodingKeys: String, CodingKey {
        case id, type, xFraction, yFraction, widthFraction, heightFraction, isVisible
        case text, fontSizePt, colorHex, isBold, fontFamily, fontWeightRaw, isItalic, tracking, alignmentRaw
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
        text = try c.decodeIfPresent(String.self, forKey: .text)
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
