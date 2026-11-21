import AppKit
import QuartzCore

/// A two-period strip lets Core Animation slide the color behind the glyph stencil.
struct LyricFlowGradient {
    private static let samples = 192
    static let period: TimeInterval = 6
    let palette: LyricFlowPalette
    let image: CGImage

    init?(palette: LyricFlowPalette, gain: CGFloat) {
        self.palette = palette
        guard let space = CGColorSpace(name: CGColorSpace.extendedLinearSRGB),
              let linear = NSColorSpace(cgColorSpace: space) else { return nil }
        var pixels = [Float16]()
        pixels.reserveCapacity(Self.samples * 4)
        for column in 0..<Self.samples {
            let phase = Double(column) / Double(Self.samples)
            guard let rgb = palette.color(at: phase).usingColorSpace(linear) else { return nil }
            pixels.append(contentsOf: [
                Float16((0.67 + 0.33 * rgb.redComponent) * gain),
                Float16((0.67 + 0.33 * rgb.greenComponent) * gain),
                Float16((0.67 + 0.33 * rgb.blueComponent) * gain),
                1
            ])
        }
        pixels += pixels
        let data = pixels.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData),
              let image = CGImage(headroom: Float(gain), width: Self.samples * 2, height: 1,
                                  bitsPerComponent: 16, bitsPerPixel: 64, bytesPerRow: pixels.count * 2,
                                  space: space, bitmapInfo: [.init(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), .floatComponents, .byteOrder16Little],
                                  provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
        else { return nil }
        self.image = image
    }

    func makeLayer(stencil: CGImage, rect: CGRect, rowWidth: CGFloat, height: CGFloat) -> CALayer {
        let clip = CALayer()
        clip.frame = CGRect(x: 0, y: 0, width: rect.width * rowWidth, height: height)
        let mask = CALayer()
        mask.frame = clip.bounds
        mask.contents = stencil
        mask.contentsRect = rect
        clip.mask = mask

        let strip = CALayer()
        strip.anchorPoint = .zero
        strip.frame = CGRect(x: -rect.minX * rowWidth, y: 0, width: rowWidth * 2, height: height)
        strip.contents = image
        let extended = image.contentHeadroom > 1
        if #available(macOS 26.0, *) { strip.preferredDynamicRange = extended ? .high : .standard }
        else { strip.wantsExtendedDynamicRangeContent = extended }
        clip.addSublayer(strip)
        return clip
    }

    func animate(_ tile: CALayer, rowWidth: CGFloat, elapsed: TimeInterval, running: Bool, host: TimeInterval) {
        guard let strip = tile.sublayers?.first?.sublayers?.first else { return }
        let cycles = elapsed.isFinite ? elapsed / Self.period : 0
        let phase = cycles - floor(cycles)
        let offset = tile.frame.midX / rowWidth
        let start = -tile.frame.minX
        strip.removeAnimation(forKey: "flowPosition")
        tile.removeAnimation(forKey: "flowGlow")
        strip.position.x = start - rowWidth * phase
        tile.shadowColor = palette.color(at: phase + offset).cgColor
        guard running else { return }

        let begin = host - phase * Self.period
        let move = CABasicAnimation(keyPath: "position.x")
        move.fromValue = start
        move.toValue = start - rowWidth
        move.beginTime = strip.convertTime(begin, from: nil)
        move.duration = Self.period
        move.repeatCount = .infinity
        move.timingFunction = CAMediaTimingFunction(name: .linear)
        strip.add(move, forKey: "flowPosition")

        guard tile.shadowOpacity > 0 else { return }
        let glow = CAKeyframeAnimation(keyPath: "shadowColor")
        glow.values = (0...16).map { palette.color(at: Double($0) / 16 + offset).cgColor }
        glow.beginTime = tile.convertTime(begin, from: nil)
        glow.duration = Self.period
        glow.repeatCount = .infinity
        tile.add(glow, forKey: "flowGlow")
    }
}
