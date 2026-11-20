import AppKit

struct IslandQuickAction: Codable, Equatable, Identifiable {
    enum Kind: String, Codable { case application, folder, shortcut }
    var id = UUID()
    var title: String
    var kind: Kind
    var target: String
    var symbol: String { switch kind { case .application: return "app"; case .folder: return "folder"; case .shortcut: return "bolt.fill" } }
    var subtitle: String { switch kind { case .application: return "应用"; case .folder: return "文件夹"; case .shortcut: return "快捷指令" } }
    var launchURL: URL? {
        switch kind {
        case .application, .folder: return URL(fileURLWithPath: target)
        case .shortcut:
            var components = URLComponents(); components.scheme = "shortcuts"; components.host = "run-shortcut"
            components.queryItems = [.init(name: "name", value: target)]; return components.url
        }
    }
}

final class QuickActions {
    var onChange: (() -> Void)?
    private(set) var actions: [IslandQuickAction]
    private(set) var shortcutNames: [String] = []
    private(set) var loading = false
    private(set) var status = ""
    private let defaults: UserDefaults
    private let key = "notchisland.quickActions.v1"
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode([IslandQuickAction].self, from: data) { actions = Array(saved.prefix(6)) }
        else {
            actions = [IslandQuickAction(title: "下载", kind: .folder, target: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads").path), IslandQuickAction(title: "文稿", kind: .folder, target: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents").path), IslandQuickAction(title: "系统设置", kind: .application, target: "/System/Applications/System Settings.app")]
        }
    }
    @discardableResult func add(_ action: IslandQuickAction) -> Bool {
        guard actions.count < 6, !actions.contains(where: { $0.kind == action.kind && $0.target == action.target }) else { return false }
        actions.append(action); save(); return true
    }
    func remove(_ id: UUID) { actions.removeAll { $0.id == id }; save() }
    func move(_ id: UUID, by offset: Int) {
        guard let from = actions.firstIndex(where: { $0.id == id }), actions.indices.contains(from + offset) else { return }
        actions.swapAt(from, from + offset); save()
    }
    private func save() { if let data = try? JSONEncoder().encode(actions) { defaults.set(data, forKey: key) }; onChange?() }
    func execute(_ action: IslandQuickAction, completion: @escaping (String?) -> Void) {
        guard let url = action.launchURL else { completion("无法打开这个操作"); return }
        if action.kind != .shortcut, !FileManager.default.fileExists(atPath: action.target) { completion("项目已移动或删除，请在设置里重新添加"); return }
        if action.kind == .application {
            NSWorkspace.shared.openApplication(at: url, configuration: .init()) { _, error in DispatchQueue.main.async { completion(error?.localizedDescription) } }
        } else { completion(NSWorkspace.shared.open(url) ? nil : "系统无法打开这个项目") }
    }
    func choose(_ kind: IslandQuickAction.Kind) {
        guard actions.count < 6 else { return }
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false
        panel.canChooseDirectories = kind == .folder; panel.canChooseFiles = kind == .application
        panel.treatsFilePackagesAsDirectories = false
        panel.title = kind == .folder ? "选择常用文件夹" : "选择应用"
        panel.prompt = "添加"
        if kind == .application { panel.directoryURL = URL(fileURLWithPath: "/Applications"); panel.allowedContentTypes = [.applicationBundle] }
        panel.begin { [weak self] result in
            guard result == .OK, let url = panel.url else { return }
            _ = self?.add(.init(title: FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: ""), kind: kind, target: url.path))
        }
    }
    func loadShortcuts() {
        guard !loading else { return }; loading = true; status = "正在读取快捷指令…"; onChange?()
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let task = Process(), pipe = Pipe()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/shortcuts"); task.arguments = ["list"]
            task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
            do {
                try task.run()
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 6) { if task.isRunning { task.terminate() } }
                let data = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
                let names = task.terminationStatus == 0 ? (String(data: data, encoding: .utf8) ?? "").split(whereSeparator: \.isNewline).map(String.init).sorted() : []
                DispatchQueue.main.async {
                    self?.loading = false; self?.shortcutNames = names
                    self?.status = task.terminationStatus == 0 ? (names.isEmpty ? "还没有快捷指令，请先在快捷指令 App 中创建" : "已读取 \(names.count) 个快捷指令") : "未能读取，请先打开系统快捷指令 App 后重试"
                    self?.onChange?()
                }
            } catch { DispatchQueue.main.async { self?.loading = false; self?.status = error.localizedDescription; self?.onChange?() } }
        }
    }
}
