import AppKit
import XCTest
@testable import NotchIsland

final class GlassBackdropTests: XCTestCase {
    func testCompactActivityDoesNotCreateNativeGlass() throws {
        guard #available(macOS 26.0, *), !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else {
            throw XCTSkip("Native glass is unavailable with the current system settings")
        }
        let backdrop = IslandBackdropView(frame: CGRect(x: 0, y: 0, width: 480, height: 340))
        let idle = CGRect(x: 140, y: 308, width: 200, height: 32)
        let compact = idle.insetBy(dx: -46, dy: 0)
        let configuration = IslandBackdropConfiguration(style: .glass, opacity: 0.12)

        backdrop.update(configuration: configuration, rect: compact, path: CGPath(rect: compact, transform: nil),
                        previous: nil, notchRect: idle, spring: nil)
        XCTAssertNil(nativeGlass(in: backdrop))
        backdrop.update(configuration: configuration, rect: idle, path: CGPath(rect: idle, transform: nil),
                        previous: nil, notchRect: idle, spring: nil)
        XCTAssertNil(nativeGlass(in: backdrop))
    }

    func testNativeGlassUsesAnUnmaskedAppKitHierarchy() throws {
        guard #available(macOS 26.0, *), !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else {
            throw XCTSkip("Native glass is unavailable with the current system settings")
        }
        let backdrop = IslandBackdropView(frame: CGRect(x: 0, y: 0, width: 480, height: 340))
        let rect = CGRect(x: 60, y: 100, width: 360, height: 240)
        let notch = CGRect(x: 140, y: 308, width: 200, height: 32)
        backdrop.update(
            configuration: .init(style: .glass, opacity: 0.12),
            rect: rect,
            path: CGPath(rect: rect, transform: nil),
            previous: nil,
            notchRect: notch,
            spring: nil
        )
        let effect = try XCTUnwrap(nativeGlass(in: backdrop))
        XCTAssertEqual(effect.frame.origin, rect.origin)
        XCTAssertEqual(effect.frame.width, rect.width)
        XCTAssertEqual(effect.style, .regular)
        XCTAssertEqual(effect.tintColor?.alphaComponent ?? 0, 0.066, accuracy: 0.001)
        XCTAssertNotNil(effect.contentView)
        var ancestor = effect.superview
        while let view = ancestor {
            XCTAssertNil(view.layer?.mask, "A parent mask isolates the native compositor")
            ancestor = view.superview
        }
    }

    func testGradientFadesDownwardAndCanBeDisabledWithoutRemovingGlass() throws {
        guard #available(macOS 26.0, *), !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else {
            throw XCTSkip("Native glass is unavailable with the current system settings")
        }
        let backdrop = IslandBackdropView(frame: CGRect(x: 0, y: 0, width: 480, height: 340))
        let rect = CGRect(x: 60, y: 100, width: 360, height: 240)
        let notch = CGRect(x: 140, y: 308, width: 200, height: 32)
        let path = CGPath(rect: rect, transform: nil)
        var configuration = IslandBackdropConfiguration(style: .glass, opacity: 0)
        backdrop.update(configuration: configuration, rect: rect, path: path, previous: nil, notchRect: notch, spring: nil)
        let effect = try XCTUnwrap(nativeGlass(in: backdrop))
        let gradient = try XCTUnwrap(backdrop.subviews.lazy.flatMap { $0.layer?.sublayers ?? [] }
            .compactMap { $0 as? CAGradientLayer }.first)
        let top = try alpha(at: CGPoint(x: 240, y: 330), in: gradient)
        let high = try alpha(at: CGPoint(x: 240, y: 270), in: gradient)
        let low = try alpha(at: CGPoint(x: 240, y: 210), in: gradient)
        let bottom = try alpha(at: CGPoint(x: 240, y: 110), in: gradient)
        XCTAssertGreaterThan(top, 245)
        XCTAssertGreaterThan(top, high)
        XCTAssertGreaterThan(high, low)
        XCTAssertGreaterThan(low, bottom)
        XCTAssertLessThan(bottom, 5)
        XCTAssertEqual(try alpha(at: CGPoint(x: 16, y: 330), in: gradient), 0)

        configuration.showsGradient = false
        backdrop.update(configuration: configuration, rect: rect, path: path, previous: nil, notchRect: notch, spring: nil)
        XCTAssertFalse(backdrop.debugGradientActive)
        XCTAssertTrue(nativeGlass(in: backdrop) === effect)
    }

    func testTransparentExpansionKeepsUntintedClearGlassWithoutOverlays() throws {
        guard #available(macOS 26.0, *), !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else {
            throw XCTSkip("Native glass is unavailable with the current system settings")
        }
        let backdrop = IslandBackdropView(frame: CGRect(x: 0, y: 0, width: 480, height: 340))
        let rect = CGRect(x: 60, y: 100, width: 360, height: 240)
        let notch = CGRect(x: 140, y: 308, width: 200, height: 32)
        let path = CGPath(rect: rect, transform: nil)
        backdrop.update(configuration: .init(style: .glass, opacity: 0.5, rimStrength: 1), rect: rect, path: path,
                        previous: nil, notchRect: notch, spring: nil)
        let effect = try XCTUnwrap(nativeGlass(in: backdrop))
        XCTAssertEqual(effect.style, .regular)
        XCTAssertTrue(backdrop.debugGradientActive)
        backdrop.update(configuration: .init(style: .glass, material: .transparent, opacity: 1, rimStrength: 1), rect: rect, path: path,
                        previous: nil, notchRect: notch, spring: nil)
        XCTAssertTrue(backdrop.usesTranslucentBackground)
        XCTAssertTrue(nativeGlass(in: backdrop) === effect)
        XCTAssertEqual(effect.style, .clear)
        XCTAssertNil(effect.tintColor)
        XCTAssertFalse(backdrop.debugGradientActive)
        XCTAssertFalse(backdrop.isHidden)
    }

    func testAppearanceRefreshPreservesInFlightGlassCollapseAndReopening() throws {
        guard #available(macOS 26.0, *), !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else {
            throw XCTSkip("Native glass is unavailable with the current system settings")
        }
        let backdrop = IslandBackdropView(frame: CGRect(x: 0, y: 0, width: 480, height: 340))
        let expanded = CGRect(x: 60, y: 100, width: 360, height: 240)
        let idle = CGRect(x: 140, y: 308, width: 200, height: 32)
        let expandedPath = CGPath(rect: expanded, transform: nil)
        let idlePath = CGPath(rect: idle, transform: nil)
        let configuration = IslandBackdropConfiguration(style: .glass, opacity: 0.12)
        let spring = CASpringAnimation(keyPath: "path")
        spring.duration = 0.05

        backdrop.update(configuration: configuration, rect: expanded, path: expandedPath,
                        previous: nil, notchRect: idle, spring: nil)
        let material = try XCTUnwrap(nativeGlass(in: backdrop))
        backdrop.update(configuration: configuration, rect: idle, path: idlePath,
                        previous: expandedPath, notchRect: idle, spring: spring, drivesMaterialFrame: true)
        let opacityAnimation = try XCTUnwrap(material.layer?.animation(forKey: "backdropOpacity") as? CASpringAnimation)
        XCTAssertFalse(backdrop.usesTranslucentBackground, "The black base should engage at the start of collapse")
        XCTAssertEqual(material.frame.origin, expanded.origin)
        let intermediate = CGRect(x: 90, y: 180, width: 300, height: 160)
        backdrop.syncMaterial(to: intermediate)
        XCTAssertEqual(material.frame.origin, intermediate.origin)
        XCTAssertEqual(material.frame.width, intermediate.width)
        XCTAssertEqual(material.contentView?.frame.size, material.bounds.size)
        XCTAssertEqual(opacityAnimation.duration, spring.duration)
        XCTAssertEqual(opacityAnimation.toValue as? Float, 0)
        backdrop.update(configuration: configuration, rect: idle, path: idlePath,
                        previous: nil, notchRect: idle, spring: nil)
        XCTAssertTrue(nativeGlass(in: backdrop) === material)

        backdrop.update(configuration: configuration, rect: expanded, path: expandedPath,
                        previous: idlePath, notchRect: idle, spring: spring)
        let originalCollapseDeadline = expectation(description: "Old cleanup deadline passed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { originalCollapseDeadline.fulfill() }
        wait(for: [originalCollapseDeadline], timeout: 1)
        XCTAssertTrue(nativeGlass(in: backdrop) === material)
        XCTAssertEqual(backdrop.debugClipBounds, expanded)
    }

    private func alpha(at point: CGPoint, in gradient: CAGradientLayer) throws -> UInt8 {
        var pixel = [UInt8](repeating: 0, count: 4)
        try pixel.withUnsafeMutableBytes { bytes in
            let context = try XCTUnwrap(CGContext(data: bytes.baseAddress, width: 1, height: 1, bitsPerComponent: 8,
                                                   bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                                                   bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.translateBy(x: -point.x, y: -point.y)
            gradient.render(in: context)
        }
        return pixel[3]
    }

    @available(macOS 26.0, *)
    private func nativeGlass(in view: NSView) -> NSGlassEffectView? {
        if let effect = view as? NSGlassEffectView { return effect }
        return view.subviews.lazy.compactMap { self.nativeGlass(in: $0) }.first
    }
}
