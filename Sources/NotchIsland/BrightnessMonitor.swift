import AppKit

/// DisplayServices calls can block on hardware. Keep them on a serial I/O queue.
final class BrightnessMonitor {
    var onBrightnessChange: ((Double) -> Void)?
    private typealias GetFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float32>) -> Int32
    private typealias SetFn = @convention(c) (CGDirectDisplayID, Float32) -> Int32
    private var getFn: GetFn?
    private var setFn: SetFn?
    private var timer: Timer?
    private var displayID: CGDirectDisplayID = 0
    private var cached: Double?
    private(set) var canAdjust = false
    private let io = DispatchQueue(label: "notchisland.brightness.io", qos: .userInteractive)
    private var polling = false
    private var settleUntil = Date.distantPast
    private var writeWork: DispatchWorkItem?
    private var enabled = false
    private var generation = 0
    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        if value { start() }
        else { enabled = false; generation += 1; timer?.invalidate(); timer = nil; writeWork?.cancel(); canAdjust = false; cached = nil }
    }
    func start() {
        guard timer == nil else { return }; enabled = true; generation += 1
        if getFn == nil, let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) {
            if let pointer = dlsym(handle, "DisplayServicesGetBrightness") { getFn = unsafeBitCast(pointer, to: GetFn.self) }
            if let pointer = dlsym(handle, "DisplayServicesSetBrightness") { setFn = unsafeBitCast(pointer, to: SetFn.self) }
        }
        poll()
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.poll() }
        timer.tolerance = 0.3; self.timer = timer; RunLoop.main.add(timer, forMode: .common)
    }
    deinit { timer?.invalidate() }
    private func poll() {
        guard enabled, !polling, let getFn else { return }; polling = true
        let generation = self.generation
        let id = IslandPreferences.shared.screen?.displayID ?? CGMainDisplayID()
        let changedDisplay = id != displayID; displayID = id
        io.async { [weak self] in
            var value: Float32 = 0
            let success = getFn(id, &value) == 0
            DispatchQueue.main.async {
                guard let self else { return }; self.polling = false
                guard self.enabled, generation == self.generation else { return }
                self.canAdjust = success && self.setFn != nil
                guard success, Date() >= self.settleUntil else { return }
                let previous = self.cached; self.cached = Double(value)
                if !changedDisplay, let previous, abs(previous - Double(value)) > 0.002 { self.onBrightnessChange?(Double(value)) }
            }
        }
    }
    func read() -> Double? { cached }
    @discardableResult func nudge(_ delta: Double) -> Bool {
        guard let current = cached else { return false }
        return setBrightness(current + delta)
    }
    @discardableResult func setBrightness(_ value: Double) -> Bool {
        guard value.isFinite, canAdjust, let setFn else { return false }
        let value = max(0, min(1, value)); cached = value; settleUntil = Date().addingTimeInterval(0.18)
        let id = displayID
        onBrightnessChange?(value)
        writeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            let success = setFn(id, Float32(value)) == 0
            if !success { DispatchQueue.main.async { self?.canAdjust = false; self?.settleUntil = .distantPast } }
        }
        writeWork = work; io.asyncAfter(deadline: .now() + 0.006, execute: work)
        return true
    }
}
