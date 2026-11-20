import AppKit
import ApplicationServices

struct SystemFocusMode: Equatable {
    let name: String
    let symbol: String
    let reducesInterruptions: Bool

    static func resolve(identifier: String, name: String? = nil, symbol: String? = nil) -> Self {
        let builtIns = [
            "com.apple.donotdisturb.mode.default": ("勿扰模式", "moon.fill"),
            "com.apple.focus.work": ("工作", "person.lanyardcard.fill"),
            "com.apple.focus.personal-time": ("个人", "person.fill"),
            "com.apple.focus.sleep-mode": ("睡眠", "bed.double.fill"),
            "com.apple.focus.driving": ("驾驶", "car.fill"),
            "com.apple.focus.fitness": ("健身", "figure.run"),
            "com.apple.focus.gaming": ("游戏", "gamecontroller.fill"),
            "com.apple.focus.reading": ("阅读", "book.fill"),
            "com.apple.focus.reduce-interruptions": ("减少打扰", "sparkles")
        ]
        let known = builtIns[identifier.lowercased()]
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let intelligent = identifier.lowercased().hasSuffix(".reduce-interruptions") ||
            (identifier.isEmpty && ["reduce interruptions", "减少打扰", "减少干扰", "減少干擾", "減少打擾"].contains(name?.lowercased() ?? ""))
        return Self(name: name.flatMap { $0.isEmpty ? nil : $0 } ?? known?.0 ?? "专注模式",
                    symbol: intelligent ? "sparkles" : symbol ?? known?.1 ?? "moon.fill",
                    reducesInterruptions: intelligent)
    }
}

enum SystemFocusState: Equatable {
    case unavailable, needsAccessibility, menuItemUnavailable, inactive, active(SystemFocusMode)

    var mode: SystemFocusMode? { if case .active(let mode) = self { return mode }; return nil }
    var title: String {
        switch self {
        case .unavailable: return "等待系统专注状态"
        case .needsAccessibility: return "需要辅助功能权限"
        case .menuItemUnavailable: return "未读取到专注状态"
        case .inactive: return "专注模式已关闭"
        case .active(let mode): return mode.name
        }
    }

    static func read(assertions: Data?, configurations: Data?) -> Self {
        func record(_ data: Data?) -> [String: Any]? {
            guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return (json["data"] as? [[String: Any]])?.first
        }
        guard let store = record(assertions) else { return .unavailable }
        guard let records = store["storeAssertionRecords"] as? [[String: Any]] else { return .unavailable }
        guard !records.isEmpty else { return .inactive }
        let identifiers = records.compactMap { ($0["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"] as? String }
        guard let identifier = identifiers.first(where: { !$0.isEmpty }) else { return .unavailable }
        let modes = record(configurations)?["modeConfigurations"] as? [String: [String: Any]]
        let mode = modes?[identifier]?["mode"] as? [String: Any]
        return .active(.resolve(identifier: identifier, name: mode?["name"] as? String, symbol: mode?["symbolImageName"] as? String))
    }

    private static let controlCenter = Bundle(url: URL(fileURLWithPath: "/System/Library/CoreServices/ControlCenter.app"))

    private static func menuLabels(_ key: String, alternatives: [String], tables: [String] = ["Focus"]) -> [String] {
        let systemLabels = tables.compactMap { controlCenter?.localizedString(forKey: key, value: "", table: $0) }
        return alternatives + systemLabels.filter { $0 != key && !$0.isEmpty }.map { $0.lowercased() }
    }

    private static let focusLabels = menuLabels("Focus", alternatives: ["focus", "focus mode", "专注模式", "專注模式", "集中モード", "집중 모드"],
                                                tables: ["Focus", "ControlCenterDisplayableModule"])
    private static let enabledLabels = menuLabels("FOCUS_MODE_ON",
                                                  alternatives: ["on", "enabled", "active", "开启", "打开", "已开启", "已打开", "啟用", "已啟用", "開啟", "已開啟", "オン", "켬"])
    private static let disabledLabels = menuLabels("FOCUS_MODE_OFF",
                                                   alternatives: ["off", "disabled", "inactive", "关闭", "已关闭", "關閉", "已關閉", "停用", "已停用", "オフ", "끔"])

    private static func menuParts(_ description: String) -> [String] {
        let parts = description.components(separatedBy: CharacterSet(charactersIn: ",，、:：\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parts
    }

    static func menuItemDescription(_ description: String) -> Self {
        let parts = menuParts(description)
        guard !parts.isEmpty else { return .unavailable }
        let normalized = parts.map { $0.lowercased() }
        if normalized.contains(where: disabledLabels.contains) { return .inactive }
        let names = zip(parts, normalized).filter { !focusLabels.contains($0.1) && !enabledLabels.contains($0.1) }
        if let name = names.first?.0 { return .active(.resolve(identifier: "", name: name)) }
        return normalized.contains(where: enabledLabels.contains) ? .active(.resolve(identifier: "")) : .inactive
    }

    static func menuItemState(labels: [String]) -> Self {
        let states = labels.map(menuItemDescription)
        if let description = labels.first, menuParts(description).contains(where: { disabledLabels.contains($0.lowercased()) }) { return .inactive }
        if let active = states.first(where: { $0.mode != nil && $0.mode != .resolve(identifier: "") }) { return active }
        return states.first(where: { $0 != .unavailable }) ?? .unavailable
    }

    static func preferredState(store: Self, menu: Self, event: Self) -> Self {
        if store.mode != nil { return store }
        if menu.mode != nil { return menu }
        if store == .inactive || menu == .inactive { return .inactive }
        return event != .unavailable ? event : menu
    }
}

/// Watches only while the module is enabled. Directory events cover atomic replacement;
/// file events also cover an in-place write. An inaccessible store never implies Focus is off.
final class SystemFocusMonitor {
    private let directory: URL
    private let center: DistributedNotificationCenter
    private var observers: [NSObjectProtocol] = []
    private var sources: [DispatchSourceFileSystemObject] = []
    private let queue = DispatchQueue(label: "notchisland.focus.read", qos: .utility)
    private var pending: DispatchWorkItem?
    private var menuRefresh: Timer?
    private var revision = 0
    private var enabled = false
    private var eventState = SystemFocusState.unavailable
    private(set) var state = SystemFocusState.unavailable
    var onChange: ((SystemFocusState) -> Void)?

    init(directory: URL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/DoNotDisturb/DB"),
         center: DistributedNotificationCenter = .default()) {
        self.directory = directory
        self.center = center
    }

    func setEnabled(_ value: Bool) {
        guard enabled != value else { return }
        enabled = value
        if value {
            for (name, active) in [("_NSDoNotDisturbEnabledNotification", true), ("_NSDoNotDisturbDisabledNotification", false)] {
                let observer = center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                    guard let self, self.enabled else { return }
                    self.eventState = active ? .active(.resolve(identifier: "")) : .inactive
                    self.refresh(after: 0.35)
                }
                observers.append(observer)
            }
            refresh()
        } else {
            revision += 1
            stopWatching()
            eventState = .unavailable
            publish(.unavailable)
        }
    }

    func didWake() {
        eventState = .unavailable
        refresh()
    }

    func refresh(after delay: TimeInterval = 0) {
        guard enabled else { return }
        revision += 1
        let requested = revision
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.enabled, requested == self.revision else { return }
            let assertions = self.directory.appendingPathComponent("Assertions.json")
            let configurations = self.directory.appendingPathComponent("ModeConfigurations.json")
            self.watch([self.directory, assertions, configurations])
            self.queue.async { [weak self] in
                let active = try? Data(contentsOf: assertions)
                let metadata = active == nil ? nil : try? Data(contentsOf: configurations)
                let stored = SystemFocusState.read(assertions: active, configurations: metadata)
                let menu = stored.mode == nil ? Self.readMenuBar() : .unavailable
                DispatchQueue.main.async {
                    guard let self, self.enabled, requested == self.revision else { return }
                    // Retry on permission changes even when System Settings keeps
                    // focus and the accessory app never receives didBecomeActive.
                    self.refreshMenuPeriodically(stored == .unavailable)
                    self.publish(SystemFocusState.preferredState(store: stored, menu: menu, event: self.eventState))
                }
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    static func readMenuBar() -> SystemFocusState {
        guard AXIsProcessTrusted() else { return .needsAccessibility }
        func read(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
        }
        let focusIdentifiers = ["com.apple.menuextra.focusmode", "com.apple.menuextra.focusmodes", "com.apple.controlcenter.focusmodes"]
        var budget = 120
        let deadline = ProcessInfo.processInfo.systemUptime + 0.8
        func search(_ element: AXUIElement, depth: Int) -> SystemFocusState {
            guard depth <= 5, budget > 0, ProcessInfo.processInfo.systemUptime < deadline else { return .unavailable }
            budget -= 1
            if let identifier = read(element, kAXIdentifierAttribute) as? String,
               focusIdentifiers.contains(identifier.lowercased()) {
                let labels = [kAXDescriptionAttribute, kAXTitleAttribute, kAXValueAttribute].compactMap { read(element, $0) as? String }
                return SystemFocusState.menuItemState(labels: labels)
            }
            for child in (read(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(36) {
                let result = search(child, depth: depth + 1)
                if result != .unavailable { return result }
            }
            return .unavailable
        }
        for bundleID in ["com.apple.MenuBarAgent", "com.apple.controlcenter", "com.apple.systemuiserver"] {
            for process in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                let app = AXUIElementCreateApplication(process.processIdentifier)
                AXUIElementSetMessagingTimeout(app, 0.08)
                for attribute in [kAXExtrasMenuBarAttribute, kAXMenuBarAttribute] {
                    guard let bar = read(app, attribute), CFGetTypeID(bar) == AXUIElementGetTypeID() else { continue }
                    let result = search(bar as! AXUIElement, depth: 0)
                    if result != .unavailable { return result }
                }
            }
        }
        return .menuItemUnavailable
    }

    private func refreshMenuPeriodically(_ active: Bool) {
        if !active { menuRefresh?.invalidate(); menuRefresh = nil }
        else if menuRefresh == nil {
            let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
            timer.tolerance = 1
            menuRefresh = timer
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func watch(_ urls: [URL]) {
        let old = sources
        sources = urls.compactMap { url in
            let descriptor = open(url.path, O_EVTONLY | O_CLOEXEC)
            guard descriptor >= 0 else { return nil }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete, .revoke], queue: .main)
            source.setEventHandler { [weak self] in self?.refresh(after: 0.12) }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            return source
        }
        old.forEach { $0.cancel() }
    }

    private func publish(_ value: SystemFocusState) {
        guard state != value else { return }
        state = value
        onChange?(value)
    }

    private func stopWatching() {
        refreshMenuPeriodically(false)
        pending?.cancel(); pending = nil
        sources.forEach { $0.cancel() }; sources.removeAll()
        observers.forEach(center.removeObserver); observers.removeAll()
    }

    deinit { stopWatching() }
}
