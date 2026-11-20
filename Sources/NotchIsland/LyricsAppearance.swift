import AppKit

struct LyricsAppearance: Codable, Equatable {
    enum Weight: String, CaseIterable, Codable {
        case regular, medium, semibold, bold

        var title: String {
            switch self {
            case .regular: return "常规"
            case .medium: return "中等"
            case .semibold: return "半粗"
            case .bold: return "粗体"
            }
        }

        var fontWeight: NSFont.Weight {
            switch self {
            case .regular: return .regular
            case .medium: return .medium
            case .semibold: return .semibold
            case .bold: return .bold
            }
        }
    }

    static let widthRange = 128.0...280.0
    static let fontSizeRange = 11.0...16.0
    var width = 188.0
    var opacity = 0.92
    var size = 12.0
    var weight = Weight.semibold
    var colorRGB: UInt32 = 0xFFFFFF
    var glow = 0.0

    var color: NSColor { Self.color(for: colorRGB) }

    static func color(for rgb: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255, green: CGFloat((rgb >> 8) & 255) / 255,
                blue: CGFloat(rgb & 255) / 255, alpha: 1)
    }

    static func rgb(for color: NSColor) -> UInt32? {
        guard let rgb = color.usingColorSpace(.sRGB) else { return nil }
        func byte(_ component: CGFloat) -> UInt32 { UInt32((min(1, max(0, component)) * 255).rounded()) }
        return byte(rgb.redComponent) << 16 | byte(rgb.greenComponent) << 8 | byte(rgb.blueComponent)
    }

    func normalized() -> Self {
        var value = self
        let defaults = Self()
        func clamp(_ value: Double, in range: ClosedRange<Double>, default fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        value.width = clamp(width, in: Self.widthRange, default: defaults.width)
        value.size = clamp(size, in: Self.fontSizeRange, default: defaults.size)
        value.opacity = clamp(opacity, in: 0...1, default: defaults.opacity)
        value.glow = clamp(glow, in: 0...1, default: defaults.glow)
        value.colorRGB &= 0xFFFFFF
        return value
    }
}
