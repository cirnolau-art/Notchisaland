import AppKit
import CoreGraphics

/// The tap only classifies events. Hardware I/O and UI updates run after it returns.
final class MediaKeyInterceptor {
    var canHandleVolume: (() -> Bool)?
    var canHandleBrightness: (() -> Bool)?
    var onVolumeNudge: ((Double) -> Bool)?
    var onBrightnessNudge: ((Double) -> Bool)?
    var onMuteToggle: (() -> Bool)?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var presses = MediaKeyPresses()
    private var wantsEnabled = false
    private var retryTimer: Timer?
    private var loggedUntrusted = false
    static var isTrusted: Bool { AXIsProcessTrusted() }
    static func requestTrust() -> Bool {
        AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
    }
    var isActive: Bool { tap.map { CGEvent.tapIsEnabled(tap: $0) } ?? false }
    @discardableResult func start() -> Bool {
        wantsEnabled = true
        if retryTimer == nil {
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
                guard let self, self.wantsEnabled else { return }
                if Self.isTrusted { if !self.isActive { _ = self.install() } }
                else if self.tap != nil { self.removeTap() }
            }
            timer.tolerance = 0.5; retryTimer = timer; RunLoop.main.add(timer, forMode: .common)
        }
        return install()
    }
    private func install() -> Bool {
        if isActive { return true }
        guard Self.isTrusted else {
            if !loggedUntrusted { print("[MediaKeys] 等待系统辅助功能授权，当前未拦截按键"); loggedUntrusted = true }
            return false
        }
        removeTap(); loggedUntrusted = false
        for location in [CGEventTapLocation.cghidEventTap, .cgSessionEventTap] {
            let pointer = Unmanaged.passUnretained(self).toOpaque()
            guard let tap = CGEvent.tapCreate(tap: location, place: .headInsertEventTap, options: .defaultTap,
                                             eventsOfInterest: CGEventMask(1 << 14), callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                return Unmanaged<MediaKeyInterceptor>.fromOpaque(context).takeUnretainedValue().handle(type: type, event: event)
            }, userInfo: pointer) else { continue }
            self.tap = tap
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
            print("[MediaKeys] 接管成功 location=\(location.rawValue)")
            return true
        }
        print("[MediaKeys] 系统未允许创建事件 tap")
        return false
    }
    func stop() { wantsEnabled = false; retryTimer?.invalidate(); retryTimer = nil; removeTap() }
    private func removeTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil; presses = MediaKeyPresses()
    }
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap, wantsEnabled { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        guard type.rawValue == 14, let e = NSEvent(cgEvent: event), e.subtype.rawValue == 8 else { return Unmanaged.passUnretained(event) }
        let key = (e.data1 >> 16) & 0xFFFF
        let phase = (e.data1 >> 8) & 0xFF
        if phase == 0x0B { return presses.up(key) ? nil : Unmanaged.passUnretained(event) }
        guard phase == 0x0A else { return Unmanaged.passUnretained(event) }
        let flags = event.flags
        let option = flags.contains(.maskAlternate), shift = flags.contains(.maskShift)
        let settingsShortcut = (option && !shift) || flags.contains(.maskControl) || flags.contains(.maskCommand)
        let supported = !settingsShortcut && (([0, 1, 7].contains(key) && canHandleVolume?() == true) || ([2, 3].contains(key) && canHandleBrightness?() == true))
        let repeating = presses.captured.contains(key)
        guard presses.down(key, supported: supported) else { return Unmanaged.passUnretained(event) }
        guard supported, key != 7 || !repeating else { return nil }
        let step = (option && shift) ? 1.0 / 64 : 1.0 / 16
        DispatchQueue.main.async { [weak self] in
            guard let self, self.wantsEnabled, self.isActive else { return }
            switch key {
            case 0: _ = self.onVolumeNudge?(step)
            case 1: _ = self.onVolumeNudge?(-step)
            case 2: _ = self.onBrightnessNudge?(step)
            case 3: _ = self.onBrightnessNudge?(-step)
            case 7: _ = self.onMuteToggle?()
            default: break
            }
        }
        return nil
    }
}
