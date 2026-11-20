import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var alarmWindowController: AlarmWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SnapshotMode.enabled {
            IslandController.shared.startDebug()
            SnapshotMode.schedule()
            return
        }
        IslandController.shared.start()
        setupStatusItem()
    }

    // MARK: - 菜单栏

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            if let img = NSImage(systemSymbolName: "capsule.inset.filled", accessibilityDescription: "灵动岛") {
                button.image = img
            } else {
                button.title = "岛"
            }
        }
        rebuildMenu()
    }

    func rebuildMenu() {
        guard statusItem != nil else { return }
        let menu = NSMenu()

        let about = NSMenuItem(title: "关于灵动岛", action: #selector(showAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)

        menu.addItem(.separator())

        let settings = NSMenuItem(title: "设置…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let toggle = NSMenuItem(title: IslandController.shared.isHidden ? "显示灵动岛" : "隐藏灵动岛",
                                action: #selector(toggleIsland), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)

        for tab in IslandPreferences.shared.visibleTabs {
            let item = NSMenuItem(title: tab.title, action: #selector(showModule(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = tab.rawValue; menu.addItem(item)
        }
        if IslandPreferences.shared.airPodsEnabled {
            let item = NSMenuItem(title: "AirPods 电量", action: #selector(showAirPods), keyEquivalent: "")
            item.target = self; menu.addItem(item)
        }
        if IslandController.shared.alarmManager.isRinging {
            let stop = NSMenuItem(title: "停止响铃", action: #selector(stopRinging), keyEquivalent: "")
            stop.target = self; menu.addItem(stop)
        }

        menu.addItem(.separator())

        let alarms = NSMenuItem(title: "闹钟…", action: #selector(openAlarms), keyEquivalent: "")
        alarms.target = self
        if IslandPreferences.shared.isEnabled(.timer) { menu.addItem(alarms) }

        let timerMenu = NSMenu(title: "倒计时")
        for (label, secs) in [("5 分钟", 300), ("10 分钟", 600), ("15 分钟", 900), ("25 分钟", 1500), ("45 分钟", 2700), ("1 小时", 3600)] {
            let item = NSMenuItem(title: label, action: #selector(startTimer(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = secs
            if IslandPreferences.shared.isEnabled(.timer) { timerMenu.addItem(item) }
        }
        let controller = IslandController.shared
        if controller.alarmManager.timerRemaining != nil {
            let stop = NSMenuItem(title: "停止当前倒计时", action: #selector(stopTimer), keyEquivalent: "")
            stop.target = self
            timerMenu.addItem(.separator())
            timerMenu.addItem(stop)
        }
        let timerItem = NSMenuItem(title: "倒计时", action: nil, keyEquivalent: "")
        timerItem.submenu = timerMenu
        if IslandPreferences.shared.isEnabled(.timer) || controller.alarmManager.timerRemaining != nil { menu.addItem(timerItem) }

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    // MARK: - 动作

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "灵动岛",
            .applicationVersion: AppVersion.release,
            .version: AppVersion.build
        ])
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func toggleIsland() {
        IslandController.shared.setHidden(!IslandController.shared.isHidden)
        rebuildMenu()
    }

    @objc private func showMusic() {
        IslandController.shared.showMusic()
    }

    @objc private func showAirPods() { IslandController.shared.showAirPods() }
    @objc private func showFiles() { IslandController.shared.showPanel(.files) }
    @objc private func showFocus() { IslandController.shared.showPanel(.timer) }
    @objc private func showModule(_ sender: NSMenuItem) { if let raw = sender.representedObject as? Int, let tab = IslandTab(rawValue: raw) { IslandController.shared.showPanel(tab) } }
    @objc private func stopRinging() { IslandController.shared.alarmManager.stopRinging() }

    @objc private func openAlarms() {
        if alarmWindowController == nil {
            alarmWindowController = AlarmWindowController()
        }
        alarmWindowController?.show()
    }

    @objc private func startTimer(_ sender: NSMenuItem) {
        if let secs = sender.representedObject as? Int {
            IslandController.shared.alarmManager.startTimer(seconds: secs)
            rebuildMenu()
        }
    }

    @objc private func stopTimer() {
        IslandController.shared.alarmManager.cancelTimer()
        rebuildMenu()
    }

}

// MARK: - 闹钟管理窗口

final class AlarmWindowController: NSWindowController, NSWindowDelegate {
    private var manager: AlarmManager { IslandController.shared.alarmManager }

    convenience init() {
        let vc = AlarmViewController()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false
        )
        window.title = "闹钟"
        window.contentViewController = vc
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        self.init(window: window)
        window.delegate = self
        window.center()
    }

    func show() {
        (window?.contentViewController as? AlarmViewController)?.reload()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        (window?.contentViewController as? AlarmViewController)?.reloadParentMenu()
    }
}

final class AlarmViewController: NSViewController {
    private let stack = NSStackView()
    private var observers: [NSKeyValueObservation] = []

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 320, height: 380))
        buildUI()
    }

    private func buildUI() {
        for sub in view.subviews { sub.removeFromSuperview() }
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -16),
        ])

        reload()
    }

    func reload() {
        stack.arrangedSubviews.forEach { stack.removeView($0) }
        let manager = IslandController.shared.alarmManager

        if manager.alarms.isEmpty {
            let empty = NSTextField(labelWithString: "还没有闹钟，点下方添加")
            empty.textColor = .secondaryLabelColor
            empty.font = .systemFont(ofSize: 13)
            stack.addArrangedSubview(empty)
        }

        for (i, alarm) in manager.alarms.enumerated() {
            let row = makeRow(
                alarm: alarm,
                changeAction: { [weak self] in
                    self?.reload()
                    self?.reloadParentMenu()
                },
                toggleAction: { [weak self] in
                    self?.reload()
                },
                deleteAction: { [weak self] index in
                    IslandController.shared.alarmManager.remove(at: index)
                    self?.reload()
                    self?.reloadParentMenu()
                },
                index: i
            )
            stack.addArrangedSubview(row)
            stack.setCustomSpacing(8, after: row)
        }

        let add = NSButton(title: "＋ 添加闹钟", target: self, action: #selector(addAlarm))
        add.bezelStyle = .rounded
        add.controlSize = .regular
        stack.addArrangedSubview(add)
        stack.setCustomSpacing(4, after: add)
    }

    private func makeRow(
        alarm: Alarm,
        changeAction: @escaping () -> Void,
        toggleAction: @escaping () -> Void,
        deleteAction: @escaping (Int) -> Void,
        index: Int
    ) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        let height: CGFloat = 30

        let check = NSButton(checkboxWithTitle: "", target: self, action: #selector(rowToggle(_:)))
        check.state = alarm.enabled ? .on : .off
        check.tag = index
        check.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(check)

        let label = NSTextField(labelWithString: alarm.label)
        label.font = .monospacedDigitSystemFont(ofSize: 20, weight: .medium)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)

        let del = NSButton(image: NSImage(systemSymbolName: "minus.circle.fill", accessibilityDescription: "删除")!, target: self, action: #selector(rowDelete(_:)))
        del.bezelStyle = .texturedRounded
        del.isBordered = false
        del.tag = index
        del.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(del)

        NSLayoutConstraint.activate([
            container.heightAnchor.constraint(equalToConstant: height),
            check.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            check.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            label.leadingAnchor.constraint(equalTo: check.trailingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            del.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            del.centerYAnchor.constraint(equalTo: container.centerYAnchor),
        ])
        return container
    }

    @objc private func rowToggle(_ sender: NSButton) {
        IslandController.shared.alarmManager.toggle(at: sender.tag)
        reload()
    }

    @objc private func rowDelete(_ sender: NSButton) {
        IslandController.shared.alarmManager.remove(at: sender.tag)
        reload()
        reloadParentMenu()
    }

    @objc private func addAlarm() {
        let alert = NSAlert()
        alert.messageText = "添加闹钟"
        alert.informativeText = "设置响铃时间（每天重复）"
        alert.addButton(withTitle: "添加")
        alert.addButton(withTitle: "取消")

        let picker = NSDatePicker()
        picker.datePickerMode = .single
        picker.datePickerElements = [.hourMinute]
        picker.datePickerStyle = .textField
        picker.dateValue = Date()
        picker.frame = NSRect(x: 0, y: 0, width: 200, height: 24)
        alert.accessoryView = picker

        if alert.runModal() == .alertFirstButtonReturn {
            let comps = Calendar.current.dateComponents([.hour, .minute], from: picker.dateValue)
            let alarm = Alarm(hour: comps.hour ?? 0, minute: comps.minute ?? 0)
            IslandController.shared.alarmManager.add(alarm)
            reload()
            reloadParentMenu()
        }
    }

    func reloadParentMenu() {
        // 让状态栏菜单里倒计时状态保持最新
        (NSApp.delegate as? AppDelegate)?.rebuildMenu()
    }
}
