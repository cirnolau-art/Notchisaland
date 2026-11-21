import AppKit
import XCTest
@testable import NotchIsland

final class LyricFlowPaletteTests: XCTestCase {
    func testRGBPaletteSmoothlyWrapsAroundTheCycle() {
        let palette = LyricFlowPalette.rgb
        let start = palette.color(at: 0)
        let blend = palette.color(at: 1.0 / 6)

        XCTAssertGreaterThan(start.redComponent, 0.8)
        XCTAssertGreaterThan(blend.redComponent, 0.3)
        XCTAssertGreaterThan(blend.greenComponent, 0.3)
        XCTAssertEqual(palette.color(at: 1), start)
        XCTAssertEqual(palette.color(at: -0.25), palette.color(at: 0.75))
        XCTAssertEqual(palette.color(at: 0.25), palette.color(at: 4.25))
        XCTAssertEqual(palette.color(at: .nan), start)
    }

    func testArtworkSamplesSeveralDistinctVibrantColors() throws {
        let palette = LyricFlowPalette(artwork: try artwork([
            (255, 0, 0, 255), (0, 255, 0, 255), (0, 0, 255, 255), (50, 50, 50, 255)
        ]))
        let swatches = (0..<3).map { palette.color(at: Double($0) / 3) }
        let dominantChannels = swatches.map { color in
            let channels = [color.redComponent, color.greenComponent, color.blueComponent]
            return channels.firstIndex(of: channels.max()!)
        }
        XCTAssertEqual(Set(dominantChannels), Set([0, 1, 2]))
        for color in swatches {
            let channels = [color.redComponent, color.greenComponent, color.blueComponent].sorted()
            XCTAssertGreaterThan(channels[2], 0.85)
            XCTAssertLessThan(channels[1], 0.15)
        }
    }

    func testGrayArtworkUsesWhiteAndSingleHueKeepsItsTint() throws {
        let gray = try artwork([(15, 15, 15, 255), (127, 127, 127, 255), (241, 241, 241, 255)])
        let oneHue = try artwork([(180, 25, 27, 255), (230, 5, 5, 255), (222, 35, 50, 255), (0, 0, 0, 0)])
        XCTAssertEqual(LyricFlowPalette(artwork: gray), .white)
        let palette = LyricFlowPalette(artwork: oneHue)
        XCTAssertGreaterThan(palette.color(at: 0).redComponent, palette.color(at: 0).blueComponent + 0.4)
        XCTAssertGreaterThan(palette.color(at: 0.5).greenComponent, palette.color(at: 0).greenComponent)
    }

    private func artwork(_ colors: [(UInt8, UInt8, UInt8, UInt8)]) throws -> CGImage {
        let stripeWidth = 12
        let width = stripeWidth * colors.count
        let height = 24
        let row = colors.flatMap { red, green, blue, alpha in
            Array(repeating: [red, green, blue, alpha], count: stripeWidth).joined()
        }
        let pixels = Array(repeating: row, count: height).flatMap { $0 }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let alpha = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
        return try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
                                     bytesPerRow: width * 4, space: space, bitmapInfo: [alpha, .byteOrder32Big],
                                     provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }
}
