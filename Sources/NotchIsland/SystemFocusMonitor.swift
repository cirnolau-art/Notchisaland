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
    case unavailable, inactive, active(SystemFocusMode)

    var mode: SystemFocusMode? { if case .active(let mode) = self { return mode }; return nil }
    var title: String {
        switch self {
        case .unavailable: return "等待系统专注状态"
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
        guard let value = store["storeAssertionRecords"] else { return .inactive }
        guard let records = value as? [[String: Any]] else { return .unavailable }
        guard !records.isEmpty else { return .inactive }
        let identifiers = records.compactMap { ($0["assertionDetails"] as? [String: Any])?["assertionDetailsModeIdentifier"] as? String }
        guard let identifier = identifiers.first(where: { !$0.isEmpty }) else { return .unavailable }
        let modes = record(configurations)?["modeConfigurations"] as? [String: [String: Any]]
        let mode = modes?[identifier]?["mode"] as? [String: Any]
        return .active(.resolve(identifier: identifier, name: mode?["name"] as? String, symbol: mode?["symbolImageName"] as? String))
    }

    static func menuItemDescription(_ description: String) -> Self {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let generic = ["Focus", "专注模式", "專注模式"]
        if generic.contains(where: { $0.caseInsensitiveCompare(text) == .orderedSame }) { return .inactive }
        for label in generic {
            for delimiter in [", ", "，", ": ", "："] {
                if text.hasPrefix(label + delimiter) {
                    let title = String(text.dropFirst(label.count + delimiter.count))
                    if ["Off", "关闭", "已关闭", "關閉", "已關閉"].contains(title) { return .inactive }
                    if ["On", "开启", "已开启", "開啟", "已開啟"].contains(title) { return .active(.resolve(identifier: "")) }
                    return title.isEmpty ? .unavailable : .active(.resolve(identifier: "", name: title))
                }
            }
        }
        return .unavailable
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
                let menu = stored == .unavailable ? Self.readMenuBar() : .unavailable
                DispatchQueue.main.async {
                    guard let self, self.enabled, requested == self.revision else { return }
                    self.refreshMenuPeriodically(stored == .unavailable && AXIsProcessTrusted())
                    if stored != .unavailable { self.publish(stored) }
                    else if menu != .unavailable { self.publish(menu) }
                    else { self.publish(self.eventState) }
                }
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static func readMenuBar() -> SystemFocusState {
        guard AXIsProcessTrusted() else { return .unavailable }
        func read(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
            var value: CFTypeRef?
            return AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success ? value : nil
        }
        func search(_ element: AXUIElement, depth: Int) -> SystemFocusState {
            if read(element, kAXIdentifierAttribute) as? String == "com.apple.menuextra.focusmode" {
                return SystemFocusState.menuItemDescription(read(element, kAXDescriptionAttribute) as? String ?? "")
            }
            guard depth < 2 else { return .unavailable }
            for child in (read(element, kAXChildrenAttribute) as? [AXUIElement] ?? []).prefix(48) {
                let result = search(child, depth: depth + 1)
                if result != .unavailable { return result }
            }
            return .unavailable
        }
        for bundleID in ["com.apple.MenuBarAgent", "com.apple.controlcenter"] {
            guard let process = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { continue }
            let app = AXUIElementCreateApplication(process.processIdentifier)
            AXUIElementSetMessagingTimeout(app, 0.08)
            if let bar = read(app, kAXExtrasMenuBarAttribute), CFGetTypeID(bar) == AXUIElementGetTypeID() {
                let result = search(bar as! AXUIElement, depth: 0)
                if result != .unavailable { return result }
            }
        }
        return .unavailable
    }

    private func refreshMenuPeriodically(_ active: Bool) {
        if !active { menuRefresh?.invalidate(); menuRefresh = nil }
        else if menuRefresh == nil {
            let timer = Timer(timeInterval: 12, repeats: true) { [weak self] _ in self?.refresh() }
            timer.tolerance = 3
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
