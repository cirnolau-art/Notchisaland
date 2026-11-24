import AppKit
import Metal
import QuartzCore
import XCTest
@testable import NotchIsland

final class LyricCompositingTests: XCTestCase {
    func testActiveWordHighlightUsesFeatherMaskAndLiftAnimation() throws {
        let bounds = CGRect(x: 0, y: 0, width: 220, height: 44)
        let row = LyricTextView(frame: bounds)
        var appearance = LyricsAppearance()
        appearance.hdrEnabled = true
        let segments = [
            LyricSegment(time: 1, text: "唱", endTime: 1.5),
            LyricSegment(time: 1.5, text: "到", endTime: 2)
        ]
        let line = LyricLine(time: 1, text: "唱到", segments: segments)
        row.update(line: line, next: 3, elapsed: 1.2, style: .appleMusic,
                   appearance: appearance, font: .boldSystemFont(ofSize: 22),
                   active: true, centered: true, running: true)

        XCTAssertTrue(row.debugHasGlyphAnimations)
        let highlightLayers = try XCTUnwrap(row.layer?.sublayers).filter { $0 !== row.layer?.sublayers?.first }
        XCTAssertTrue(highlightLayers.contains { $0.animation(forKey: "highlightLift") != nil })
        XCTAssertTrue(highlightLayers.contains {
            guard let mask = $0.mask else { return false }
            return mask is CAGradientLayer && mask.animation(forKey: "highlightFeather") != nil
        })
    }

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
        let line = LyricLine(time: 1, text: "AB", segments: [
            .init(time: 1, text: "A", endTime: 1.5), .init(time: 1.5, text: "B", endTime: 2)
        ])
        func show(_ elapsed: TimeInterval, running: Bool = false) {
            row.update(line: line, next: nil, elapsed: elapsed, style: .appleMusic, appearance: appearance,
                       font: .boldSystemFont(ofSize: 22), active: true, centered: true, running: running)
        }
        show(1)
        XCTAssertGreaterThan(row.hdrGain, 1)

        let rowLayer = try XCTUnwrap(row.layer)
        let tile = try XCTUnwrap(rowLayer.sublayers?.dropFirst().first)
        let contents = try XCTUnwrap(tile.sublayers?.first { $0.name == "lyricHDR" })
        if !IslandPreferences.shared.reduceMotion {
            XCTAssertEqual(contents.opacity, 0)
            show(1.1, running: true)
            let fade = try XCTUnwrap(tile.animation(forKey: "highlight") as? CABasicAnimation)
            let gain = try XCTUnwrap(contents.animation(forKey: "highlightGain") as? CABasicAnimation)
            let lift = try XCTUnwrap(tile.animation(forKey: "highlightLift") as? CABasicAnimation)
            let feather = try XCTUnwrap(tile.mask?.animation(forKey: "highlightFeather") as? CABasicAnimation)
            XCTAssertEqual(gain.duration, fade.duration, accuracy: 0.001)
            XCTAssertEqual(lift.duration, fade.duration, accuracy: 0.001)
            XCTAssertEqual(feather.duration, fade.duration, accuracy: 0.001)
            show(1.1)
            XCTAssertEqual(tile.opacity, 0.5, accuracy: 0.001)
            XCTAssertEqual(contents.opacity, tile.opacity, accuracy: 0.001)
            XCTAssertEqual(tile.transform.m42, -0.8, accuracy: 0.001)
            XCTAssertNil(contents.animation(forKey: "highlightGain"))
        }
        show(1.3)
        XCTAssertEqual(contents.opacity, 1, accuracy: 0.001)
        let highlight = CALayer()
        highlight.frame = tile.frame
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
