import AppKit
import XCTest
@testable import NotchIsland

final class NotificationPlacementTests: XCTestCase {
    func testLeftRightAndNarrowScreenAvoidNotchAndExpandedIsland() throws {
        // Coordinates include a display to the left and above the primary one.
        let visible = CGRect(x: -1512, y: 480, width: 1512, height: 930)
        let island = CGRect(x: visible.midX - 220, y: visible.maxY - 280, width: 440, height: 310)
        for side in NotificationSide.allCases {
            let frame = try XCTUnwrap(side.cardFrame(in: visible, avoiding: island))
            XCTAssertTrue(visible.contains(frame))
            XCTAssertFalse(frame.intersects(island))
            if side == .left { XCTAssertLessThan(frame.maxX, island.minX) }
            else { XCTAssertGreaterThan(frame.minX, island.maxX) }
        }
        let narrow = CGRect(x: 0, y: 100, width: 800, height: 600)
        let panel = CGRect(x: 180, y: 396, width: 440, height: 326)
        for side in NotificationSide.allCases {
            let frame = try XCTUnwrap(side.cardFrame(in: narrow, avoiding: panel))
            XCTAssertTrue(narrow.contains(frame))
            XCTAssertLessThan(frame.maxY, panel.minY)
        }
        XCTAssertNil(NotificationSide.left.cardFrame(in: CGRect(x: 0, y: 0, width: 500, height: 120),
                                                      avoiding: CGRect(x: 30, y: 0, width: 440, height: 120)))
    }

    @MainActor func testPreviewAndDeliveryUseSelectedWindowPreservePrivacyAndDrainQueue() throws {
        _ = NSApplication.shared
        guard NSScreen.main != nil else { throw XCTSkip("AppKit window server unavailable") }
        let defaults = UserDefaults.standard
        let old = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        var overrides = old
        func configure(_ placement: NotificationPlacement, _ side: NotificationSide, preview: Bool) {
            overrides["notchisland.notificationPlacement"] = placement.rawValue
            overrides["notchisland.notificationSide"] = side.rawValue
            overrides["notchisland.notificationPreview"] = preview
            defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
            defaults.setVolatileDomain(overrides, forName: UserDefaults.argumentDomain)
        }
        defer {
            defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
            defaults.setVolatileDomain(old, forName: UserDefaults.argumentDomain)
        }
        configure(.sides, .right, preview: false)
        let controller = IslandController.shared
        controller.startDebug()
        defer { controller.window.orderOut(nil) }
        controller.previewNotification()
        let window = try XCTUnwrap(NSApp.windows.compactMap { $0 as? SideNotificationWindow }.first(where: \.isPresenting))
        defer { window.cancel() }
        XCTAssertTrue(window.isVisible)
        XCTAssertGreaterThan(window.level.rawValue, controller.window.level.rawValue)
        let view = try XCTUnwrap(controller.debugView)
        let occupied = try XCTUnwrap(view.occupiedScreenFrame)
        XCTAssertFalse(occupied.intersects(window.frame))
        let initialFrame = window.frame
        func fields() -> [String] { window.contentView?.subviews.compactMap { ($0 as? NSTextField)?.stringValue } ?? [] }
        XCTAssertFalse(fields().contains(IslandNotification.demo.title))
        configure(.sides, .left, preview: true)
        controller.reconcileNotificationPresentation()
        XCTAssertLessThan(window.frame.minX, initialFrame.minX)
        XCTAssertTrue(fields().contains(IslandNotification.demo.title))
        view.render(.workspace(.audio, false), animated: false)
        XCTAssertFalse(window.frame.intersects(try XCTUnwrap(view.occupiedScreenFrame)))
        configure(.island, .right, preview: true)
        controller.reconcileNotificationPresentation()
        XCTAssertFalse(window.isPresenting)
        XCTAssertTrue(controller.window.isVisible)
        configure(.sides, .right, preview: true)
        controller.reconcileNotificationPresentation()
        XCTAssertTrue(window.isPresenting)
        var first = IslandNotification.demo
        first.identity = "first-notice"
        var second = IslandNotification.demo
        second.identity = "second-notice"
        var acknowledged = [String]()
        first.dismissNativeBanner = { if window.isVisible { acknowledged.append("first") } }
        second.dismissNativeBanner = { if window.isVisible { acknowledged.append("second") } }
        controller.notificationBridge.onNotification?(first)
        controller.notificationBridge.onNotification?(second)
        XCTAssertTrue(acknowledged.isEmpty)
        let close = try XCTUnwrap(window.contentView?.subviews.compactMap { $0 as? NSButton }.first)
        close.performClick(nil)
        XCTAssertEqual(window.item?.identity, first.identity)
        XCTAssertEqual(acknowledged, ["first"])
        close.performClick(nil)
        XCTAssertEqual(window.item?.identity, second.identity)
        XCTAssertEqual(acknowledged, ["first", "second"])
    }
}
