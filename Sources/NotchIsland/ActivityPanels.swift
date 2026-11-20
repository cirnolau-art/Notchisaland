import AppKit

/// Shared type, spacing and surfaces keep all secondary panels visually quiet.
class ActivityPanel: FlippedView {
    @discardableResult func text(_ string: String, _ rect: NSRect, size: CGFloat = 12, weight: NSFont.Weight = .regular, alpha: CGFloat = 1) -> NSTextField {
        let label = NSTextField(labelWithString: string); label.frame = rect; label.font = .systemFont(ofSize: size, weight: weight)
        label.textColor = .white.withAlphaComponent(alpha); label.lineBreakMode = .byTruncatingTail
        addSubview(label); return label
    }
    @discardableResult func action(_ title: String = "", symbol: String? = nil, help: String, rect: NSRect, run: @escaping () -> Void) -> ActionButton {
        let button = ActionButton(title: title, symbol: symbol, help: help) { _ in run() }; button.frame = rect; addSubview(button); return button
    }
    func icon(_ name: String, _ rect: NSRect, alpha: CGFloat = 0.8) {
        let image = NSImageView(frame: rect); image.image = NSImage(systemSymbolName: name, accessibilityDescription: nil); image.contentTintColor = .white.withAlphaComponent(alpha); addSubview(image)
    }
}

final class AudioPanelView: ActivityPanel {
    var onSelect: ((UInt32) -> Void)?
    var onVolume: ((Double) -> Void)?
    var onInteraction: ((Bool) -> Void)?
    private let list = NSScrollView()
    private var key = ""
    private var adjusting = false
    private let slider = InteractionSlider(frame: .zero)
    private var volumeLabel: NSTextField!
    private var note: NSTextField!
    override init(frame: NSRect) {
        super.init(frame: frame)
        let width = bounds.width
        text("声音输出", NSRect(x: 26, y: 7, width: width - 52, height: 24), size: 17, weight: .semibold)
        list.frame = NSRect(x: 16, y: 44, width: width - 32, height: 150); list.drawsBackground = false; list.hasVerticalScroller = true; list.scrollerStyle = .overlay; addSubview(list)
        icon("speaker.wave.2.fill", NSRect(x: 27, y: 210, width: 17, height: 17))
        volumeLabel = text("—", NSRect(x: width - 71, y: 211, width: 44, height: 17), size: 11, alpha: 0.55)
        volumeLabel.alignment = .right; volumeLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        slider.frame = NSRect(x: 58, y: 208, width: width - 144, height: 21); slider.minValue = 0; slider.maxValue = 1; slider.isContinuous = true
        slider.target = self; slider.action = #selector(volumeChanged); slider.setAccessibilityLabel("输出音量")
        slider.onInteraction = { [weak self] active in self?.adjusting = active; self?.onInteraction?(active) }; addSubview(slider)
        note = text("", NSRect(x: 27, y: 247, width: width - 54, height: 17), size: 11, alpha: 0.42)
    }
    required init?(coder: NSCoder) { fatalError() }
    @objc private func volumeChanged() { onVolume?(slider.doubleValue) }
    func update(outputs: [AudioOutput], selected: UInt32, switching: UInt32?, volume: Double?, available: Bool, error: String?) {
        let newKey = "\(outputs)|\(selected)|\(String(describing: switching))"
        if newKey != key {
            key = newKey
            let document = FlippedView(frame: NSRect(x: 0, y: 0, width: list.bounds.width - 4, height: CGFloat(max(1, outputs.count)) * 50))
            for (index, output) in outputs.enumerated() {
                let row = ActivityPanel(frame: NSRect(x: 0, y: index * 50, width: Int(document.bounds.width), height: 48))
                row.wantsLayer = true; row.layer?.cornerRadius = 12
                if output.id == selected { row.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.075).cgColor }
                row.icon(output.symbol, NSRect(x: 12, y: 15, width: 24, height: 24))
                row.text(output.name, NSRect(x: 49, y: 8, width: row.bounds.width - 95, height: 20), size: 12, weight: .medium)
                row.text(switching == output.id ? "正在切换…" : output.canAdjustVolume ? "支持调节音量" : "固定音量 · 在设备上调节", NSRect(x: 49, y: 30, width: row.bounds.width - 95, height: 15), size: 10, alpha: 0.45)
                if output.id == selected { row.icon("checkmark", NSRect(x: row.bounds.width - 32, y: 18, width: 14, height: 14)) }
                let hit = row.action(help: "使用 \(output.name) · \(output.canAdjustVolume ? "可调音量" : "固定音量")", rect: row.bounds) { [weak self] in self?.onSelect?(output.id) }
                hit.isEnabled = switching == nil
                document.addSubview(row)
            }
            if outputs.isEmpty { document.addSubview(NSTextField(labelWithString: "未找到可用的输出设备")) }
            list.documentView = document
            if let index = outputs.firstIndex(where: { $0.id == selected }) { document.scrollToVisible(NSRect(x: 0, y: index * 50, width: Int(document.bounds.width), height: 50)) }
        }
        let supports = outputs.first { $0.id == selected }?.canAdjustVolume == true
        slider.isEnabled = supports && available && switching == nil
        if !adjusting { slider.setDisplayedValue(volume ?? 0, animated: true) }
        volumeLabel.stringValue = supports ? volume.map { "\(Int(($0 * 100).rounded()))%" } ?? "—" : "固定"
        note.stringValue = error ?? (supports ? "声音将从所选设备播放" : "此输出不提供系统音量控制")
    }
}

final class CalendarPanelView: ActivityPanel {
    var onOpen: ((IslandMeeting) -> Void)?
    var onEnable: (() -> Void)?
    private var meeting: IslandMeeting?
    private var countdown: NSTextField?
    private var progress: NSView?
    private var key = ""
    func update(meeting: IslandMeeting?, enabled: Bool, authorized: Bool, status: String) {
        self.meeting = meeting
        let newKey = "\(String(describing: meeting))|\(enabled)|\(authorized)|\(status)"
        guard newKey != key else { refreshTime(); return }; key = newKey
        subviews.forEach { $0.removeFromSuperview() }; countdown = nil; progress = nil
        let width = bounds.width
        text("接下来", NSRect(x: 26, y: 7, width: width - 52, height: 24), size: 17, weight: .semibold)
        if let meeting {
            text(meeting.calendar, NSRect(x: 26, y: 43, width: width - 120, height: 17), size: 11, alpha: 0.45)
            let title = text(meeting.title, NSRect(x: 26, y: 72, width: width - 52, height: 51), size: 22, weight: .semibold)
            title.maximumNumberOfLines = 2
            text(meeting.timeLabel, NSRect(x: 26, y: 135, width: width - 52, height: 19), size: 12, alpha: 0.62)
            text(meeting.location.isEmpty ? "系统日历" : meeting.location, NSRect(x: 26, y: 159, width: width - 52, height: 18), size: 11, alpha: 0.42)
            countdown = text("", NSRect(x: 26, y: 214, width: width - 183, height: 28), size: 18, weight: .medium)
            action(meeting.link == nil ? "打开日程" : "加入会议", symbol: meeting.link == nil ? "calendar" : "video", help: meeting.link == nil ? "在日历中查看" : "打开会议链接", rect: NSRect(x: width - 147, y: 210, width: 121, height: 36)) { [weak self] in self?.onOpen?(meeting) }.selected = true
            let track = NSView(frame: NSRect(x: 26, y: 264, width: width - 52, height: 2)); track.wantsLayer = true; track.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.1).cgColor; track.layer?.cornerRadius = 1; addSubview(track)
            let fill = NSView(frame: track.bounds); fill.wantsLayer = true; fill.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.7).cgColor; track.addSubview(fill); progress = fill
            refreshTime()
        } else {
            icon("calendar", NSRect(x: width / 2 - 21, y: 74, width: 42, height: 42), alpha: 0.6)
            let title = text(!enabled ? "把下一场日程放在眼前" : authorized ? "留一点空白给自己" : "连接你的日历", NSRect(x: 24, y: 137, width: width - 48, height: 25), size: 16, weight: .medium); title.alignment = .center
            let note = text(status, NSRect(x: 24, y: 174, width: width - 48, height: 21), size: 11, alpha: 0.45); note.alignment = .center
            if !enabled || !authorized {
                action("连接系统日历", symbol: "plus", help: "开启日程并请求日历访问权限", rect: NSRect(x: width / 2 - 83, y: 216, width: 166, height: 36)) { [weak self] in self?.onEnable?() }.selected = true
            }
        }
    }
    func refreshTime() {
        guard let meeting else { return }; countdown?.stringValue = meeting.countdown()
        let fraction = meeting.start > Date() ? 1 - min(1, max(0, meeting.start.timeIntervalSinceNow / 3600)) : min(1, max(0, Date().timeIntervalSince(meeting.start) / max(1, meeting.end.timeIntervalSince(meeting.start))))
        if let progress, let width = progress.superview?.bounds.width { progress.frame.size.width = width * fraction }
    }
}

final class QuickActionsPanelView: ActivityPanel {
    private var previousActions: [IslandQuickAction]?
    private var previousStatus: String?
    func update(actions: [IslandQuickAction], run: @escaping (IslandQuickAction) -> Void, configure: @escaping () -> Void, status: String?) {
        guard previousActions != actions || previousStatus != status else { return }
        previousActions = actions; previousStatus = status
        subviews.forEach { $0.removeFromSuperview() }
        let width = bounds.width
        text("快捷操作", NSRect(x: 26, y: 7, width: width - 100, height: 24), size: 17, weight: .semibold)
        action(symbol: "slider.horizontal.3", help: "管理快捷操作", rect: NSRect(x: width - 52, y: 4, width: 30, height: 30), run: configure)
        let tileWidth = (width - 60) / 3
        for (index, item) in actions.prefix(6).enumerated() {
            let x = 22 + CGFloat(index % 3) * (tileWidth + 8), y = 55 + CGFloat(index / 3) * 91
            let tile = ActivityPanel(frame: NSRect(x: x, y: y, width: tileWidth, height: 82)); tile.wantsLayer = true; tile.layer?.cornerRadius = 14; tile.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.045).cgColor
            if item.kind == .application, FileManager.default.fileExists(atPath: item.target) {
                let icon = NSImageView(frame: NSRect(x: tileWidth / 2 - 16, y: 10, width: 32, height: 32))
                icon.image = NSWorkspace.shared.icon(forFile: item.target); icon.imageScaling = .scaleProportionallyUpOrDown; tile.addSubview(icon)
            } else { tile.icon(item.kind == .application ? "app.fill" : item.symbol, NSRect(x: tileWidth / 2 - 12, y: 14, width: 24, height: 24)) }
            let title = tile.text(item.title, NSRect(x: 8, y: 50, width: tileWidth - 16, height: 18), size: 11, weight: .medium); title.alignment = .center
            tile.action(help: "\(item.title) · \(item.subtitle)", rect: tile.bounds) { run(item) }; addSubview(tile)
        }
        if actions.isEmpty {
            let empty = text("把常用应用、文件夹和快捷指令放在这里", NSRect(x: 24, y: 110, width: width - 48, height: 24), size: 12, alpha: 0.6); empty.alignment = .center
            action("添加快捷操作", symbol: "plus", help: "打开快捷操作设置", rect: NSRect(x: width / 2 - 85, y: 156, width: 170, height: 38), run: configure).selected = true
        }
        text(status ?? "轻点即达 · 最多 6 个常用操作", NSRect(x: 26, y: 252, width: width - 52, height: 17), size: 11, alpha: 0.42)
    }
}
