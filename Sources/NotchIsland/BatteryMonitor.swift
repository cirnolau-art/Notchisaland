import AppKit
import IOKit.ps

/// 电源状态监听：接通/断开电源时弹出提示。
final class BatteryMonitor {
    var onPowerChange: ((Bool, Int) -> Void)?

    private var lastCharging: Bool?
    private var lastPercent: Int = 0

    private var source: CFRunLoopSource?
    private var enabled = false
    func setEnabled(_ value: Bool) {
        if value { start() }
        else { enabled = false; if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) }; source = nil; lastCharging = nil }
    }
    deinit { if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .defaultMode) } }
    func start() {
        guard !enabled else { return }; enabled = true
        let callback: @convention(c) (UnsafeMutableRawPointer?) -> Void = { ctx in
            guard let ctx else { return }
            let mon = Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            DispatchQueue.main.async { mon.poll(notifyAlways: false) }
        }
        if let src = IOPSNotificationCreateRunLoopSource(callback, Unmanaged.passUnretained(self).toOpaque()) {
            let source = src.takeRetainedValue(); self.source = source
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
        } else {
            print("[Battery] failed to create run loop source")
        }
        poll(notifyAlways: false)
    }

    /// 读取当前电池状态
    private func read() -> (charging: Bool, percent: Int)? {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue() else { return nil }
        guard let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
            guard let provides = desc[kIOPSPowerSourceStateKey] as? String else { continue }
            _ = provides
            let capacity = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let charging = (desc[kIOPSIsChargingKey] as? Bool ?? false) ||
                (provides == kIOPSACPowerValue)
            return (charging, capacity)
        }
        return nil
    }

    private func poll(notifyAlways: Bool) {
        guard enabled, let (charging, pct) = read() else { return }
        defer {
            lastCharging = charging
            lastPercent = pct
        }
        let changed = lastCharging != nil && charging != lastCharging
        if changed || notifyAlways {
            onPowerChange?(charging, pct)
        }
    }
}
