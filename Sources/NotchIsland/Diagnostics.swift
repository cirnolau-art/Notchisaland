import AppKit
import ApplicationServices

/// Opt-in, reproducible local verification. It never exports real notification text.
enum IslandDiagnostics {
    static func notifications() -> Never {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        guard AXIsProcessTrusted() else { print("FAIL: Accessibility is not authorized for this process"); exit(2) }
        let window = IslandWindow(); window.reposition()
        let bridge = NotificationBridge()
        let title = "NotchIsland 通知链路验证"
        let body = "这是一条本机诊断通知"
        var count = 0, payloadValid = false, identity = ""
        bridge.onNotification = { item in
            guard item.title == title else { return }
            count += 1; payloadValid = item.body == body && item.source != "通知" && item.dismissNativeBanner != nil; identity = item.identity
            (window.contentView as? IslandView)?.render(.notification(item))
            window.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let view = window.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    try? bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: "/tmp/notchisland-live-notification.png"))
                }
                item.dismissNativeBanner?()
            }
        }
        bridge.setEnabled(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", "display notification \"\(body)\" with title \"\(title)\""]
            try? process.run()
        }
        RunLoop.main.run(until: Date().addingTimeInterval(7))
        let stillVisible = !identity.isEmpty && liveBannerIDs().contains(identity)
        print("notification diagnostic: count=\(count) payload=\(payloadValid) nativeBannerRemoved=\(!stillVisible)")
        bridge.setEnabled(false); window.orderOut(nil)
        exit(count == 1 && payloadValid && !stillVisible ? 0 : 1)
    }
    private static func liveBannerIDs() -> Set<String> {
        func value(_ e: AXUIElement, _ key: String) -> CFTypeRef? { var result: CFTypeRef?; AXUIElementCopyAttributeValue(e, key as CFString, &result); return result }
        var ids = Set<String>()
        var budget = 250, visited = Set<CFHashCode>()
        func visit(_ e: AXUIElement, _ depth: Int) {
            guard depth < 10, budget > 0, visited.insert(CFHash(e)).inserted else { return }; budget -= 1
            let id = value(e, kAXIdentifierAttribute) as? String ?? ""
            if id.hasPrefix("widget-") { return }
            if value(e, kAXSubroleAttribute) as? String == "AXNotificationCenterBanner" { ids.insert(id); return }
            for child in (value(e, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(64) { visit(child, depth + 1) }
        }
        if let process = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.notificationcenterui" }) {
            let app = AXUIElementCreateApplication(process.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.08)
            for window in (value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).prefix(48) { visit(window, 0) }
        }
        return ids
    }
    static func audio() -> Never {
        _ = NSApplication.shared
        let monitor = AudioOutputMonitor(); monitor.start()
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        for output in monitor.outputs { print("output \(output.id == monitor.selected ? "selected" : "available"): \(output.name), adjustable=\(output.canAdjustVolume), symbol=\(output.symbol)") }
        exit(monitor.outputs.isEmpty ? 1 : 0)
    }
}
