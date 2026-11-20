import AppKit
import XCTest
@testable import NotchIsland

final class NotificationPlacementTests: XCTestCase {
    func testCompactBannerRespectsScreenAndSizeLimits() {
        let compact = NotchNotificationLayout(notch: 200, available: 800, width: 350, depth: 58)
        XCTAssertEqual(compact.width, 350)
        XCTAssertEqual(compact.depth, 58)
        let narrow = NotchNotificationLayout(notch: 180, available: 500, width: 700, depth: 5)
        XCTAssertEqual(narrow.width, 500)
        XCTAssertEqual(narrow.depth, 46)
    }

    @MainActor func testAttachedPreviewAndDeliveriesShareIslandAndPreservePrivacy() throws {
        _ = NSApplication.shared
        guard NSScreen.main != nil else { throw XCTSkip("AppKit window server unavailable") }
        let defaults = UserDefaults.standard
        let old = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defer {
            defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
            defaults.setVolatileDomain(old, forName: UserDefaults.argumentDomain)
        }
        func configure(_ placement: NotificationPlacement, preview: Bool, depth: Double = 56) {
            var values = old
            values["notchisland.notificationPlacement"] = placement.rawValue
            values["notchisland.notificationPreview"] = preview
            values["notchisland.notificationDepth"] = depth
            defaults.removeVolatileDomain(forName: UserDefaults.argumentDomain)
            defaults.setVolatileDomain(values, forName: UserDefaults.argumentDomain)
        }
        func descendants(_ root: NSView) -> [NSView] { root.subviews.flatMap { [$0] + descendants($0) } }
        configure(.sides, preview: false)
        let controller = IslandController.shared
        controller.startDebug()
        let island = try XCTUnwrap(controller.debugView)
        defer { island.onDismissActivity?(); controller.window.orderOut(nil) }
        controller.previewNotification()
        XCTAssertTrue(controller.window.isVisible)
        XCTAssertEqual(island.debugVisibleRect.height - island.debugNotchRect.height, 56)
        func labels() -> [NSTextField] { descendants(island).compactMap { $0 as? NSTextField } }
        XCTAssertFalse(labels().contains(where: { $0.stringValue == IslandNotification.demo.title }))
        let source = try XCTUnwrap(labels().first(where: { $0.stringValue == IslandNotification.demo.source }))
        XCTAssertGreaterThanOrEqual(source.convert(source.bounds, to: island).minX, island.debugNotchRect.maxX)
        configure(.sides, preview: true, depth: 86)
        controller.reconcileNotificationPresentation()
        XCTAssertEqual(island.debugVisibleRect.height - island.debugNotchRect.height, 86)
        let message = try XCTUnwrap(labels().first(where: { $0.stringValue == IslandNotification.demo.body }))
        XCTAssertLessThanOrEqual(message.convert(message.bounds, to: island).maxY, island.debugNotchRect.minY)
        configure(.island, preview: true)
        controller.reconcileNotificationPresentation()
        XCTAssertEqual(island.debugVisibleRect.height - island.debugNotchRect.height, 154)
        configure(.sides, preview: true)
        controller.reconcileNotificationPresentation()

        var first = IslandNotification.demo
        first.identity = "first-notice"
        var second = IslandNotification.demo
        second.identity = "second-notice"
        var acknowledged = [String]()
        first.dismissNativeBanner = { if controller.window.isVisible { acknowledged.append("first") } }
        second.dismissNativeBanner = { if controller.window.isVisible { acknowledged.append("second") } }
        controller.notificationBridge.onNotification?(first)
        controller.notificationBridge.onNotification?(second)
        XCTAssertTrue(acknowledged.isEmpty)
        island.onDismissActivity?()
        XCTAssertEqual(acknowledged, ["first"])
        island.onDismissActivity?()
        XCTAssertEqual(acknowledged, ["first", "second"])
    }
}
