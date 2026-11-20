import AppKit
import Carbon.HIToolbox

/// 输入法切换监听：kTISNotifySelectedKeyboardInputSourceChanged + TIS 当前输入源查询。
final class InputSourceMonitor {
    var onInputSourceChange: ((String) -> Void)?

    private var selfPtr: UnsafeMutableRawPointer { Unmanaged.passUnretained(self).toOpaque() }
    private var debounceWork: DispatchWorkItem?
    private var currentSourceID: String = ""

    private var enabled = false
    func setEnabled(_ value: Bool) { if value { start() } else { stop() } }
    func stop() {
        guard enabled else { return }; enabled = false; debounceWork?.cancel(); debounceWork = nil
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetLocalCenter(), selfPtr)
    }
    deinit { CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetLocalCenter(), selfPtr); debounceWork?.cancel() }
    func start() {
        guard !enabled else { return }; enabled = true
        let center = CFNotificationCenterGetLocalCenter()
        CFNotificationCenterAddObserver(
            center,
            Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let mon = Unmanaged<InputSourceMonitor>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { mon.queueRead() }
            },
            "TISNotifySelectedKeyboardInputSourceChanged" as CFString,
            nil,
            .deliverImmediately
        )
        // 初始记录当前输入法，避免启动时误报
        if let (name, id) = Self.currentKeyboardSource() {
            currentSourceID = id
            print("[Input] initial source: \(name) (\(id))")
        }
    }

    private func queueRead() {
        guard enabled else { return }
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.readAndNotify()
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: work)
    }

    private func readAndNotify() {
        guard enabled else { return }
        guard let (name, id) = Self.currentKeyboardSource() else { return }
        if id == currentSourceID { return }
        currentSourceID = id
        onInputSourceChange?(name)
    }

    /// 返回 (显示名, inputSourceID)
    static func currentKeyboardSource() -> (String, String)? {
        guard let unmanaged = TISCopyCurrentKeyboardInputSource() else { return nil }
        let source = unmanaged.takeRetainedValue()
        // 类别过滤：只响应键盘类输入源（过滤墨迹、面板等）
        if let categoryPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceCategory) {
            let category = Unmanaged<CFString>.fromOpaque(categoryPtr).takeUnretainedValue() as String
            guard category == (kTISCategoryKeyboardInputSource as String) else { return nil }
        }
        var name = ""
        if let namePtr = TISGetInputSourceProperty(source, kTISPropertyLocalizedName) {
            name = Unmanaged<CFString>.fromOpaque(namePtr).takeUnretainedValue() as String
        }
        var id = ""
        if let idPtr = TISGetInputSourceProperty(source, kTISPropertyInputSourceID) {
            id = Unmanaged<CFString>.fromOpaque(idPtr).takeUnretainedValue() as String
        }
        guard !name.isEmpty else { return nil }
        return (name, id)
    }
}
