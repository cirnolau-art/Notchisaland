import Foundation

/// Persistent timer state uses a deadline, so sleep and a busy run loop cannot slow it down.
struct TimerSession: Codable, Equatable {
    var duration: TimeInterval
    var deadline: Date?
    var pausedRemaining: TimeInterval?
    var label: String

    init(seconds: TimeInterval, label: String = "倒计时", now: Date = Date()) {
        duration = max(1, seconds)
        deadline = now.addingTimeInterval(duration)
        pausedRemaining = nil
        self.label = label
    }
    var isPaused: Bool { deadline == nil }
    func remaining(at now: Date = Date()) -> TimeInterval {
        max(0, deadline.map { $0.timeIntervalSince(now) } ?? pausedRemaining ?? 0)
    }
    mutating func pause(at now: Date = Date()) {
        guard deadline != nil else { return }
        pausedRemaining = remaining(at: now)
        deadline = nil
    }
    mutating func resume(at now: Date = Date()) {
        guard let remaining = pausedRemaining else { return }
        deadline = now.addingTimeInterval(remaining)
        pausedRemaining = nil
    }
    mutating func add(seconds: TimeInterval) {
        duration += seconds
        if let end = deadline { deadline = end.addingTimeInterval(seconds) }
        else { pausedRemaining = max(0, (pausedRemaining ?? 0) + seconds) }
    }
}

enum IslandTab: Int, CaseIterable {
    case music, files, timer, audio, calendar, shortcuts, clipboard, focus
    var title: String {
        switch self { case .music: return "音乐"; case .files: return "暂存"; case .timer: return "计时"; case .audio: return "声音"; case .calendar: return "日程"; case .shortcuts: return "快捷"; case .clipboard: return "剪贴板"; case .focus: return "专注" }
    }
    var symbol: String {
        switch self { case .music: return "music.note"; case .files: return "tray"; case .timer: return "timer"; case .audio: return "hifispeaker"; case .calendar: return "calendar"; case .shortcuts: return "square.grid.2x2"; case .clipboard: return "doc.on.clipboard"; case .focus: return "moon.fill" }
    }
    func moved(by delta: Int, among tabs: [IslandTab] = Self.allCases) -> IslandTab {
        guard !tabs.isEmpty else { return self }
        guard let index = tabs.firstIndex(of: self) else { return tabs[0] }
        return tabs[((index + delta) % tabs.count + tabs.count) % tabs.count]
    }
    var detail: String {
        switch self {
        case .music: return "正在播放、媒体控制与进度"
        case .files: return "拖入暂存、拖出使用与空格预览"
        case .timer: return "专注计时与倒计时；关闭后已有计时仍会提醒"
        case .audio: return "选择输出设备并调节音量"
        case .calendar: return "下一场日程与会议提醒，需另行连接日历"
        case .shortcuts: return "常用应用、文件夹与快捷指令"
        case .clipboard: return "最近 30 条文字与图片，仅保存在内存，关闭即清空"
        case .focus: return "当前系统专注模式与减少打扰状态"
        }
    }
}

/// Low-priority HUDs never dismiss a ringing alarm. A transient preserves the underlying panel.
struct PresentationPolicy {
    enum Surface: Equatable { case idle, panel(IslandTab), alert }
    private(set) var surface: Surface = .idle
    private(set) var transientVisible = false
    mutating func open(_ tab: IslandTab) { guard surface != .alert else { return }; surface = .panel(tab); transientVisible = false }
    /// Preferences can change the panel underneath a transient without dismissing that activity.
    mutating func reconcileTabs(_ tabs: [IslandTab]) {
        guard case .panel(let current) = surface, !tabs.contains(current) else { return }
        surface = tabs.first.map { .panel($0) } ?? .idle
    }
    mutating func close() { guard surface != .alert else { return }; surface = .idle; transientVisible = false }
    mutating func showTransient() -> Bool {
        guard surface != .alert else { return false }
        transientVisible = true
        return true
    }
    mutating func expireTransient() { transientVisible = false }
    mutating func ring() { surface = .alert; transientVisible = false }
    mutating func stopAlert() { surface = .idle; transientVisible = false }
}

/// Keep the paused waveform briefly, then restore the physical notch footprint.
struct CompactMediaActivity {
    static let pauseGrace: TimeInterval = 2.5
    private(set) var pausedAt: Date?
    private(set) var playing = false
    private(set) var hasMedia = false
    mutating func update(hasMedia: Bool, playing: Bool, at now: Date = Date()) {
        if self.playing && !playing && hasMedia { pausedAt = now }
        if playing || !hasMedia { pausedAt = nil }
        self.playing = playing; self.hasMedia = hasMedia
    }
    func isVisible(at now: Date = Date()) -> Bool {
        playing || (hasMedia && pausedAt.map { now.timeIntervalSince($0) < Self.pauseGrace } == true)
    }
}

/// Treat key-up as part of a captured press; never leak its release to the system HUD.
struct MediaKeyPresses {
    private(set) var captured = Set<Int>()
    mutating func down(_ key: Int, supported: Bool) -> Bool {
        if captured.contains(key) { return true }
        if supported { captured.insert(key) }
        return supported
    }
    mutating func up(_ key: Int) -> Bool { captured.remove(key) != nil }
}
