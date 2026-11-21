import AppKit
import Metal
import QuartzCore
import XCTest
@testable import NotchIsland

final class LyricCompositingTests: XCTestCase {
    func testExpandedLyricsHaveNoAncestorMaskOrRasterization() throws {
        let preferences = IslandPreferences.shared
        let storedPlacement = preferences.expandedLyricsPlacement
        defer { preferences.expandedLyricsPlacement = storedPlacement }
        for placement in [LyricsPlacement.below, .side] {
            preferences.expandedLyricsPlacement = placement
            let island = IslandView(frame: CGRect(origin: .zero, size: IslandWindow.windowSize))
            island.enabledTabsOverride = [.music]
            let line = LyricLine(time: 2, text: "Daylight")
            let track = MediaInfo(title: "Song", duration: 60, elapsed: 3, lyrics: [line])
            island.render(.music(track), animated: false)
            island.layoutSubtreeIfNeeded()

            let row = try XCTUnwrap(descendants(of: island).compactMap { $0 as? LyricTextView }.first { $0.stringValue == line.text })
            let rowLayer = try XCTUnwrap(row.layer)
            XCTAssertFalse(rowLayer.allowsGroupOpacity)
            var current: CALayer? = rowLayer
            while let layer = current {
                XCTAssertNil(layer.mask)
                XCTAssertFalse(layer.shouldRasterize)
                current = layer.superlayer
            }
        }
    }

    func testSungGlyphsPreserveExtendedBrightnessAfterCoreAnimationCompositesThem() throws {
        guard #available(macOS 26.0, *),
              let screen = NSScreen.screens.first(where: { $0.maximumPotentialExtendedDynamicRangeColorComponentValue >= 1.5 }),
              let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("An EDR display and Metal are required for the compositing check")
        }
        let width = 180
        let height = 48
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: bounds, styleMask: .borderless, backing: .buffered, defer: false, screen: screen)
        window.colorSpace = .extendedSRGB
        let row = LyricTextView(frame: bounds)
        window.contentView = row
        var appearance = LyricsAppearance()
        appearance.hdrEnabled = true
        appearance.hdrStrength = 1
        appearance.glow = 0
        row.update(line: LyricLine(time: 1, text: "Daylight"), next: nil, elapsed: 2,
                   style: .appleMusic, appearance: appearance, font: .boldSystemFont(ofSize: 22),
                   active: true, centered: true, running: false)
        XCTAssertGreaterThan(row.hdrGain, 1)

        let rowLayer = try XCTUnwrap(row.layer)
        let contents = try XCTUnwrap(rowLayer.sublayers?.last)
        let highlight = CALayer()
        highlight.frame = contents.frame
        highlight.contents = contents.contents
        highlight.contentsRect = contents.contentsRect
        highlight.contentsScale = contents.contentsScale
        highlight.preferredDynamicRange = contents.preferredDynamicRange
        highlight.toneMapMode = contents.toneMapMode
        let container = CALayer()
        container.frame = bounds
        container.backgroundColor = NSColor.black.cgColor
        container.masksToBounds = true
        container.addSublayer(highlight)
        let peak = try renderPeak(of: container, bounds: bounds, device: device, queue: queue)
        XCTAssertGreaterThan(peak, 1.15, "Core Animation compressed HDR lyrics into SDR")
    }

    func testFlowingGradientPreservesHDRThroughTheGlyphStencil() throws {
        guard #available(macOS 26.0, *),
              let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw XCTSkip("Metal and macOS 26 are required for the compositing check")
        }
        let bounds = CGRect(x: 0, y: 0, width: 160, height: 42)
        let raster = try XCTUnwrap(LyricRaster(line: "Daylight", font: .boldSystemFont(ofSize: 24), size: bounds.size, scale: 1, centered: true))
        let stencil = try XCTUnwrap(raster.image(color: .white, gain: 1))
        let gradient = try XCTUnwrap(LyricFlowGradient(palette: .rgb, gain: 3))
        let tile = CALayer()
        tile.frame = bounds
        tile.shadowColor = NSColor.systemPurple.cgColor
        tile.shadowOpacity = 0.52
        tile.shadowRadius = 2
        tile.allowsGroupOpacity = false
        tile.addSublayer(gradient.makeLayer(stencil: stencil, rect: CGRect(x: 0, y: 0, width: 1, height: 1),
                                           rowWidth: bounds.width, height: bounds.height))
        let container = CALayer()
        container.frame = bounds
        container.backgroundColor = NSColor.black.cgColor
        container.addSublayer(tile)
        let peak = try renderPeak(of: container, bounds: bounds, device: device, queue: queue)
        XCTAssertGreaterThan(peak, 1.15, "Core Animation compressed the flowing gradient into SDR")
    }

    private func renderPeak(of container: CALayer, bounds: CGRect, device: MTLDevice, queue: MTLCommandQueue) throws -> Float16 {
        let width = Int(bounds.width)
        let height = Int(bounds.height)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.extendedLinearSRGB))
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(device.makeTexture(descriptor: descriptor))
        let renderer = CARenderer(mtlTexture: texture, options: [kCARendererColorSpace: space, kCARendererMetalCommandQueue: queue])
        renderer.layer = container
        renderer.bounds = bounds
        CATransaction.flush()
        renderer.beginFrame(atTime: CACurrentMediaTime(), timeStamp: nil)
        renderer.addUpdate(bounds)
        renderer.render()
        renderer.endFrame()
        let fence = try XCTUnwrap(queue.makeCommandBuffer())
        fence.commit()
        fence.waitUntilCompleted()

        var pixels = [Float16](repeating: 0, count: width * height * 4)
        texture.getBytes(&pixels, bytesPerRow: width * 8, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return stride(from: 0, to: pixels.count, by: 4).map { pixels[$0] }.max() ?? 0
    }

    private func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }
}
