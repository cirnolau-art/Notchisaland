import AppKit
import XCTest
@testable import NotchIsland

final class HUDTrackAppearanceTests: XCTestCase {
    func testVolumeAndBrightnessHUDUseSeparateSavedTracks() throws {
        let preferences = IslandPreferences.shared
        let initialVolume = preferences.hudTrackAppearance(for: .volume)
        let initialBrightness = preferences.hudTrackAppearance(for: .brightness)
        defer {
            preferences.setHUDTrackAppearance(initialVolume, for: .volume)
            preferences.setHUDTrackAppearance(initialBrightness, for: .brightness)
        }
        let window = IslandWindow()
        window.reposition()
        let view = try XCTUnwrap(window.contentView as? IslandView)
        let volume = HUDTrackAppearance(lowColorRGB: 0xFF0000, highColorRGB: 0xFFFFFF, hdrEnabled: true)
        let brightness = HUDTrackAppearance(lowColorRGB: 0x0000FF, highColorRGB: 0x00FF00)
        preferences.setHUDTrackAppearance(volume, for: .volume)
        preferences.setHUDTrackAppearance(brightness, for: .brightness)
        XCTAssertEqual(preferences.hudTrackAppearance(for: .volume), volume)
        XCTAssertEqual(preferences.hudTrackAppearance(for: .brightness), brightness)

        func slider(in node: NSView) -> InteractionSlider? {
            if let slider = node as? InteractionSlider { return slider }
            return node.subviews.lazy.compactMap { slider(in: $0) }.first
        }

        view.render(.volume(1, false), animated: false)
        view.layoutSubtreeIfNeeded()
        let volumeSlider = try XCTUnwrap(slider(in: view))
        let volumeFill = try XCTUnwrap(volumeSlider.layer?.sublayers?.last)
        XCTAssertEqual(volumeSlider.hudAppearance, volume)
        if let screen = window.screen, screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1 {
            let image = try XCTUnwrap(volumeFill.contents) as! CGImage
            XCTAssertEqual(CGFloat(image.contentHeadroom), screen.maximumPotentialExtendedDynamicRangeColorComponentValue, accuracy: 0.01)
        }

        view.render(.brightness(1), animated: false)
        view.layoutSubtreeIfNeeded()
        let brightnessSlider = try XCTUnwrap(slider(in: view))
        let brightnessFill = try XCTUnwrap(brightnessSlider.layer?.sublayers?.last)
        XCTAssertEqual(brightnessSlider.hudAppearance, brightness)
        XCTAssertNil(brightnessFill.contents)
        let fillColor = try XCTUnwrap(NSColor(cgColor: XCTUnwrap(brightnessFill.backgroundColor)))
        XCTAssertEqual(LyricsAppearance.rgb(for: fillColor), 0x00FF00)
    }

    func testColorInterpolatesBetweenEndpointsAtTheCurrentLevel() throws {
        let appearance = HUDTrackAppearance(lowColorRGB: 0xFF0000, highColorRGB: 0x0000FF)

        XCTAssertEqual(LyricsAppearance.rgb(for: appearance.color(at: -0.1)), 0xFF0000)
        XCTAssertEqual(LyricsAppearance.rgb(for: appearance.color(at: 1.1)), 0x0000FF)

        let low = try XCTUnwrap(appearance.color(at: 0.25).usingColorSpace(.sRGB))
        let high = try XCTUnwrap(appearance.color(at: 0.75).usingColorSpace(.sRGB))
        XCTAssertGreaterThan(low.redComponent, high.redComponent)
        XCTAssertLessThan(low.blueComponent, high.blueComponent)
        XCTAssertEqual(low.greenComponent, 0, accuracy: 0.005)
        XCTAssertEqual(high.greenComponent, 0, accuracy: 0.005)
        XCTAssertEqual(low.alphaComponent, 1)
        XCTAssertEqual(high.alphaComponent, 1)
    }

    func testHDRGainFollowsTheLevelWithinAvailableHeadroom() {
        var appearance = HUDTrackAppearance()
        XCTAssertEqual(appearance.gain(at: 1, peak: 2), 1)

        appearance.hdrEnabled = true
        XCTAssertEqual(appearance.gain(at: 1, peak: 1), 1)
        XCTAssertEqual(appearance.gain(at: 1, peak: .infinity), 1)
        XCTAssertEqual(appearance.gain(at: .nan, peak: 1.5), 1)
        XCTAssertEqual(appearance.gain(at: 0, peak: 1.5), 1)
        XCTAssertEqual(appearance.gain(at: 0.5, peak: 1.5), 1.25)
        XCTAssertEqual(appearance.gain(at: 1, peak: 1.5), 1.5)
        XCTAssertEqual(appearance.gain(at: 2, peak: 3), 3)
    }

    func testHDRImagePreservesHueAndEncodesExtendedComponents() throws {
        var appearance = HUDTrackAppearance(lowColorRGB: 0xFF8000, highColorRGB: 0xFF8000)
        XCTAssertNil(appearance.extendedImage(at: 1, peak: 2))
        appearance.hdrEnabled = true
        XCTAssertNil(appearance.extendedImage(at: 1, peak: 1))
        XCTAssertNil(appearance.extendedImage(at: 0, peak: 2))

        let image = try XCTUnwrap(appearance.extendedImage(at: 1, peak: 2))
        XCTAssertEqual(image.colorSpace?.name, CGColorSpace.extendedLinearSRGB)
        XCTAssertEqual(image.bitsPerComponent, 16)
        XCTAssertTrue(image.bitmapInfo.contains(.floatComponents))
        XCTAssertEqual(image.contentHeadroom, 2)

        let linearSpace = try XCTUnwrap(NSColorSpace(cgColorSpace: XCTUnwrap(image.colorSpace)))
        let linear = try XCTUnwrap(appearance.color(at: 1).usingColorSpace(linearSpace))
        let data = try XCTUnwrap(image.dataProvider?.data) as Data
        let components = data.withUnsafeBytes { buffer in
            (0 ..< 4).map { buffer.loadUnaligned(fromByteOffset: $0 * 2, as: Float16.self) }
        }
        XCTAssertGreaterThan(components[0], 1)
        XCTAssertEqual(CGFloat(components[0]), linear.redComponent * 2, accuracy: 0.002)
        XCTAssertEqual(CGFloat(components[1]), linear.greenComponent * 2, accuracy: 0.002)
        XCTAssertEqual(CGFloat(components[2]), linear.blueComponent * 2, accuracy: 0.002)
        XCTAssertEqual(components[3], 1)
    }
}
