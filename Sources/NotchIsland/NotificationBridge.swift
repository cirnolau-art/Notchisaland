import AppKit
import ApplicationServices

/// Reads live Accessibility banners only. Notification history and databases are never read.
final class NotificationBridge {
    var onNotification: ((IslandNotification) -> Void)?
    private(set) var status = "通知接管未启用"
    private let queue = DispatchQueue(label: "notchisland.notifications.ax", qos: .utility)
    private var observer: AXObserver?
    private var application: AXUIElement?
    private var observedPID: pid_t = 0
    private var workspaceObservers: [NSObjectProtocol] = []
    private var retry: Timer?
    private var scanWork: DispatchWorkItem?
    private var enabled = false
    private var generation = 0
    private var deduplication = NotificationDeduplicator() // utility queue only
    private var transferred = 0
    var isActive: Bool { observer != nil }

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value; generation += 1
        if value {
            for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
                workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in self?.installIfPossible() })
            }
            let timer = Timer(timeInterval: 8, repeats: true) { [weak self] _ in self?.installIfPossible() }
            timer.tolerance = 3; retry = timer; RunLoop.main.add(timer, forMode: .common)
            installIfPossible()
        } else {
            removeObserver(); retry?.invalidate(); retry = nil
            workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }; workspaceObservers.removeAll()
            status = "通知接管未启用"
        }
    }
    deinit {
        retry?.invalidate(); removeObserver()
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
    }
    func reconnect() { guard enabled else { return }; removeObserver(); installIfPossible() }
    private func removeObserver() {
        generation += 1; scanWork?.cancel(); scanWork = nil
        if let observer { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
        observer = nil; application = nil; observedPID = 0
    }
    private func installIfPossible() {
        guard enabled else { return }
        guard AXIsProcessTrusted() else { removeObserver(); status = "需要辅助功能权限 · 请检查已安装的灵动岛"; return }
        guard let process = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == "com.apple.notificationcenterui" }) else { removeObserver(); status = "等待系统通知中心"; return }
        if observer != nil, observedPID == process.processIdentifier { return }
        removeObserver(); observedPID = process.processIdentifier
        let app = AXUIElementCreateApplication(observedPID); AXUIElementSetMessagingTimeout(app, 0.08)
        var result: AXObserver?
        let callback: AXObserverCallback = { _, _, _, context in
            guard let context else { return }
            Unmanaged<NotificationBridge>.fromOpaque(context).takeUnretainedValue().scheduleScan()
        }
        guard AXObserverCreate(observedPID, callback, &result) == .success, let result else { status = "系统通知观察器暂不可用"; return }
        observer = result; application = app
        let pointer = Unmanaged.passUnretained(self).toOpaque()
        var attached = false
        for event in [kAXWindowCreatedNotification, kAXCreatedNotification, kAXLayoutChangedNotification, kAXTitleChangedNotification] {
            if AXObserverAddNotification(result, app, event as CFString, pointer) == .success { attached = true }
        }
        guard attached else { removeObserver(); status = "系统未开放通知横幅事件"; return }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(result), .commonModes)
        status = "正在监听 · 等待系统横幅（遵循专注模式）"
        print("[Notifications] AX observer attached pid=\(observedPID)")
        scheduleScan()
    }
    private func scheduleScan() {
        guard enabled, let application, observer != nil else { return }
        if CommandLine.arguments.contains("--diagnose-notifications") { print("[Notifications] scan requested") }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier != observedPID else { return }
        scanWork?.cancel()
        let expected = generation
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let screens = NSScreen.screens.map { CGRect(x: $0.frame.minX, y: primaryTop - $0.frame.maxY, width: $0.frame.width, height: $0.frame.height) }
        let work = DispatchWorkItem { [weak self] in self?.scan(application, generation: expected, screens: screens) }
        scanWork = work; queue.asyncAfter(deadline: .now() + 0.08, execute: work)
    }
    private static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }; return value
    }
    private static func text(_ element: AXUIElement, _ key: String) -> String { value(element, key) as? String ?? "" }
    private static func children(_ element: AXUIElement) -> [AXUIElement] { value(element, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
    private static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = value(element, kAXPositionAttribute), let s = value(element, kAXSizeAttribute), CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(p, to: AXValue.self), .cgPoint, &position), AXValueGetValue(unsafeBitCast(s, to: AXValue.self), .cgSize, &size) else { return nil }
        return CGRect(origin: position, size: size)
    }
    private func scan(_ app: AXUIElement, generation expected: Int, screens: [CGRect]) {
        let windows = Self.value(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        var deliveries: [IslandNotification] = []
        var historyWindows = 0
        func visit(_ element: AXUIElement, depth: Int, budget: inout Int) {
            guard depth < 12, budget > 0 else { return }; budget -= 1
            let identifier = Self.text(element, kAXIdentifierAttribute)
            guard !identifier.hasPrefix("widget-"), identifier != "widgets-overlay-view" else { return }
            let subrole = Self.text(element, kAXSubroleAttribute)
            let modern = subrole == "AXNotificationCenterBanner" || subrole == "AXNotificationCenterAlert"
            // New macOS banners live INSIDE a full-screen scroll area. Never reject their container.
            // History alerts have a different subrole; only explicit banners may cross that boundary.
            if subrole.contains("NotificationCenter"), !modern, subrole != "AXNotificationCenterAlertStack" { return }
            let bounds = Self.frame(element)
            let legacyCandidate = !modern && Self.text(element, kAXRoleAttribute) == kAXGroupRole && bounds.map { b in
                b.width >= 220 && b.width <= 620 && b.height >= 45 && b.height <= 300 && screens.contains { s in b.minY >= s.minY && b.minY < s.minY + 120 && abs(b.maxX - s.maxX) < 60 }
            } == true
            if modern || legacyCandidate {
                var labels: [String] = [], title = "", body = "", header = "", close: AXUIElement?
                var remaining = 60
                func collect(_ node: AXUIElement, _ level: Int) {
                    guard level < 7, remaining > 0 else { return }; remaining -= 1
                    let role = Self.text(node, kAXRoleAttribute), id = Self.text(node, kAXIdentifierAttribute)
                    if role == kAXButtonRole, [Self.text(node, kAXDescriptionAttribute), Self.text(node, kAXTitleAttribute), id].contains(where: BannerSemantics.isDismissAction) { close = node }
                    if role == kAXStaticTextRole || role == kAXHeadingRole {
                        let string = [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute].map { Self.text(node, $0) }.first { !$0.isEmpty } ?? ""
                        labels.append(string)
                        if id == "title" { title = string }; if id == "body" { body = string }
                        if id == "header" { header = string }
                    }
                    for child in Self.children(node) { collect(child, level + 1) }
                }
                collect(element, 0)
                var names: CFArray?; AXUIElementCopyActionNames(element, &names)
                let dismissAction = (names as? [String] ?? []).first(where: BannerSemantics.isDismissAction)
                let payload: (source: String, title: String, body: String)?
                if modern {
                    let description = (Self.value(element, "AXAttributedDescription") as? NSAttributedString)?.string ?? Self.text(element, kAXDescriptionAttribute)
                    if !header.isEmpty { payload = BannerSemantics.modernPayload(title: title, body: body, description: description, header: header) }
                    else if title.isEmpty, let old = BannerTextParser.parse(labels) { payload = old }
                    else { payload = BannerSemantics.modernPayload(title: title, body: body, description: description) }
                } else { payload = close == nil ? nil : BannerTextParser.parse(labels) }
                if let payload {
                    let identity = identifier.isEmpty ? "\(CFHash(element))|\(payload.source)|\(payload.title)|\(payload.body)" : identifier
                    if deduplication.accept(identity) {
                        var item = IslandNotification(source: payload.source, title: payload.title, body: payload.body, identity: identity)
                        if let dismissAction {
                            item.dismissNativeBanner = { [weak self] in self?.dismiss(element, action: dismissAction, generation: expected) }
                        } else if let close { item.dismissNativeBanner = { [weak self] in self?.dismiss(close, action: kAXPressAction, generation: expected) } }
                        deliveries.append(item)
                    }
                    return
                }
            }
            for child in Self.children(element) { visit(child, depth: depth + 1, budget: &budget) }
        }
        // Each window gets its own budget; desktop widgets must not starve the actual banner window.
        func isHistoryPanel(_ node: AXUIElement, depth: Int, budget: inout Int) -> Bool {
            guard depth < 9, budget > 0 else { return false }; budget -= 1
            let id = Self.text(node, kAXIdentifierAttribute)
            if id == "widget-editor-button", let bounds = Self.frame(node), bounds.width > 8, bounds.height > 8, screens.contains(where: { $0.intersects(bounds) }) { return true }
            if id.hasPrefix("widget-") { return false }
            return Self.children(node).contains { isHistoryPanel($0, depth: depth + 1, budget: &budget) }
        }
        for window in windows.prefix(48) {
            var panelBudget = 100
            guard !isHistoryPanel(window, depth: 0, budget: &panelBudget) else { historyWindows += 1; continue }
            var budget = 140; visit(window, depth: 0, budget: &budget)
        }
        if CommandLine.arguments.contains("--diagnose-notifications") { print("[Notifications] scan windows=\(windows.count) history=\(historyWindows) deliveries=\(deliveries.count)") }
        guard !deliveries.isEmpty else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.enabled, expected == self.generation else { return }
            for var item in deliveries {
                let source = NSWorkspace.shared.runningApplications.first { $0.localizedName?.localizedCaseInsensitiveCompare(item.source) == .orderedSame }
                item.icon = source?.icon
                if let source { item.openApplication = { source.activate(options: []) } }
                self.transferred += 1; self.status = "已识别 \(self.transferred) 条横幅 · 最近 \(DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .short))"
                print("[Notifications] banner detected; dismiss=\(item.dismissNativeBanner != nil)")
                self.onNotification?(item)
            }
        }
    }
    private func dismiss(_ element: AXUIElement, action: String, generation expected: Int) {
        guard enabled, generation == expected else { return }
        queue.async {
            let result = AXUIElementPerformAction(element, action as CFString)
            print("[Notifications] dismiss result=\(result.rawValue)")
        }
    }
}

enum BannerSemantics {
    static func isDismissAction(_ value: String) -> Bool {
        let name = value.components(separatedBy: "\n").first?.replacingOccurrences(of: "Name:", with: "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        return ["close", "dismiss", "关闭", "清除", "关闭通知", "close notification", "dismiss notification"].contains(name)
    }
    static func modernPayload(title: String, body: String, description: String, header: String = "") -> (source: String, title: String, body: String)? {
        guard !title.isEmpty || !body.isEmpty else { return nil }
        var source = header.isEmpty ? "通知" : String(header.prefix(80))
        if header.isEmpty, !title.isEmpty, let range = description.range(of: title), range.lowerBound > description.startIndex {
            let prefix = String(description[..<range.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
            if !prefix.isEmpty { source = String(prefix.prefix(80)) }
        }
        return (source, String((title.isEmpty ? "新通知" : title).prefix(200)), String(body.prefix(1000)))
    }
}
