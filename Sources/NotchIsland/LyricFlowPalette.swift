import AppKit

struct LyricFlowPalette: Equatable, Sendable {
    static let rgb = Self(colors: [
        SIMD3(1, 0.12, 0.22),
        SIMD3(0.18, 1, 0.28),
        SIMD3(0.2, 0.48, 1),
    ])
    static let white = Self(colors: [SIMD3(repeating: 1)])

    private let colors: [SIMD3<Double>]
    private static let hueBinCount = 12

    private init(colors: [SIMD3<Double>]) { self.colors = colors }

    init(artwork: CGImage) {
        let swatches = Self.swatches(in: artwork)
        if swatches.count > 1 {
            self.init(colors: swatches.shuffled())
        } else if let color = swatches.first {
            self.init(colors: [color, color + (SIMD3(repeating: 1) - color) * 0.42])
        } else {
            self = .white
        }
    }

    func color(at phase: Double) -> NSColor {
        let cycle = phase.isFinite ? phase - floor(phase) : 0
        let position = cycle * Double(colors.count)
        let index = Int(position)
        let fraction = position - Double(index)
        let smooth = fraction * fraction * (3 - 2 * fraction)
        let start = colors[index % colors.count]
        let end = colors[(index + 1) % colors.count]
        let color = start + (end - start) * smooth
        return NSColor(srgbRed: color.x, green: color.y, blue: color.z, alpha: 1)
    }

    private static func swatches(in artwork: CGImage) -> [SIMD3<Double>] {
        let size = 32
        let pixelCount = size * size
        var bytes = [UInt8](repeating: 0, count: pixelCount * 4)
        let sampled = bytes.withUnsafeMutableBytes { buffer in
            let alpha = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
            let bitmapInfo: CGBitmapInfo = [alpha, .byteOrder32Big]
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: size, height: size, bitsPerComponent: 8,
                                          bytesPerRow: size * 4, space: space, bitmapInfo: bitmapInfo.rawValue) else { return false }
            context.interpolationQuality = .low
            context.draw(artwork, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard sampled else { return [] }

        // Group by hue so differently shaded areas of the same color share a bin.
        var bins = Array(repeating: (sum: SIMD3<Double>.zero, count: 0), count: hueBinCount)
        for offset in stride(from: 0, to: bytes.count, by: 4) {
            let alpha = Double(bytes[offset + 3])
            guard alpha >= 192 else { continue }
            let color = SIMD3(Double(bytes[offset]), Double(bytes[offset + 1]), Double(bytes[offset + 2])) / alpha
            guard let bin = hueBin(for: color) else { continue }
            bins[bin].sum += color
            bins[bin].count += 1
        }

        var chosenBins: [Int] = []
        let candidates = bins.indices.sorted { bins[$0].count > bins[$1].count }
        for index in candidates where bins[index].count >= pixelCount / 64 {
            let neighboringBin = chosenBins.contains { selected in
                let distance = abs(selected - index)
                return min(distance, hueBinCount - distance) <= 1
            }
            guard !neighboringBin else { continue }
            chosenBins.append(index)
            if chosenBins.count == 5 { break }
        }
        return chosenBins.map { bins[$0].sum / Double(bins[$0].count) }
    }

    private static func hueBin(for color: SIMD3<Double>) -> Int? {
        let peak = max(color.x, color.y, color.z)
        let chroma = peak - min(color.x, color.y, color.z)
        guard peak >= 0.25, chroma >= 0.18, chroma / peak >= 0.35 else { return nil }
        let hue: Double
        if peak == color.x {
            hue = (color.y - color.z) / chroma
        } else if peak == color.y {
            hue = 2 + (color.z - color.x) / chroma
        } else {
            hue = 4 + (color.x - color.y) / chroma
        }
        let bin = Int((hue * Double(hueBinCount) / 6).rounded())
        return (bin + hueBinCount) % hueBinCount
    }
}
