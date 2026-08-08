import SwiftData
import SwiftUI
import Foundation

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
    var id: UUID = UUID()
    var type: LayerType
    var xFraction: Double = 0.1
    var yFraction: Double = 0.1
    var widthFraction: Double = 0.8
    var heightFraction: Double = 0.1
    var isVisible: Bool = true

    // Text
    var text: String? = "Your text here"
    var fontSizePt: Double = 40
    var colorHex: String = "#FFFFFF"
    var isBold: Bool = true

    // Image
    var imageData: Data?

    enum LayerType: String, Codable {
        case text, image
    }
}

// MARK: - SwiftData model

@Model
final class ScreenshotTemplate {
    var name: String
    var deviceTypeRawValue: String
    var backgroundColorHex: String
    var layersData: Data
    var createdAt: Date
    var app: AppRecord?

    var deviceType: DeviceType {
        get { DeviceType(rawValue: deviceTypeRawValue) ?? .iPhone67 }
        set { deviceTypeRawValue = newValue.rawValue }
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
