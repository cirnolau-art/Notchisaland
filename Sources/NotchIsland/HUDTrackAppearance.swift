import AppKit

struct HUDTrackAppearance: Codable, Equatable {
    private static let linearRGB = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        .flatMap(NSColorSpace.init(cgColorSpace:))

    var lowColorRGB: UInt32 = 0xFFFFFF
    var highColorRGB: UInt32 = 0xFFFFFF
    var hdrEnabled = false

    func color(at level: Double) -> NSColor {
        let fraction = Self.fraction(for: level)
        let low = LyricsAppearance.color(for: lowColorRGB)
        guard fraction > 0, lowColorRGB != highColorRGB else { return low }
        let high = LyricsAppearance.color(for: highColorRGB)
        guard fraction < 1 else { return high }
        guard let space = Self.linearRGB,
              let start = low.usingColorSpace(space),
              let end = high.usingColorSpace(space) else { return low }

        func interpolate(_ start: CGFloat, _ end: CGFloat) -> CGFloat {
            start + fraction * (end - start)
        }
        let components = [
            interpolate(start.redComponent, end.redComponent),
            interpolate(start.greenComponent, end.greenComponent),
            interpolate(start.blueComponent, end.blueComponent),
            1,
        ]
        return NSColor(colorSpace: space, components: components, count: components.count)
    }

    func gain(at level: Double, peak: CGFloat) -> CGFloat {
        guard hdrEnabled, peak.isFinite, peak > 1 else { return 1 }
        let supportedPeak = min(peak, CGFloat(Float16.greatestFiniteMagnitude))
        return 1 + Self.fraction(for: level) * (supportedPeak - 1)
    }

    func extendedImage(at level: Double, peak: CGFloat) -> CGImage? {
        let gain = gain(at: level, peak: peak)
        guard gain > 1,
              let linearSpace = Self.linearRGB, let space = linearSpace.cgColorSpace,
              let linear = color(at: level).usingColorSpace(linearSpace) else { return nil }
        let components: [Float16] = [
            Float16(linear.redComponent * gain),
            Float16(linear.greenComponent * gain),
            Float16(linear.blueComponent * gain),
            1,
        ]
        let data = components.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        let alpha = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        return CGImage(headroom: Float(gain), width: 1, height: 1, bitsPerComponent: 16, bitsPerPixel: 64,
                       bytesPerRow: 8, space: space, bitmapInfo: [alpha, .floatComponents, .byteOrder16Little],
                       provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }

    private static func fraction(for level: Double) -> CGFloat {
        level.isFinite ? CGFloat(min(1, max(0, level))) : 0
    }
}
