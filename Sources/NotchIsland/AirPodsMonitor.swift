import AppKit
import CoreBluetooth
import CoreAudio
import IOBluetooth

/// Connection and audio-route events are independent from silent battery refreshes.
final class AirPodsMonitor: NSObject {
    var onChange: ((AirPodsSnapshot?, Bool) -> Void)?
    private(set) var snapshot: AirPodsSnapshot?
    private let queue = DispatchQueue(label: "notchisland.airpods", qos: .utility)
    private let bluetoothQueue = DispatchQueue(label: "notchisland.airpods.connections", qos: .utility)
    private var connection: IOBluetoothUserNotification?
    private var disconnections: [IOBluetoothUserNotification] = []
    private var connectedAddresses = Set<String>()
    private var installingBluetooth = false
    private var bluetoothReady = false
    private var timer: Timer?
    private var refreshWork: DispatchWorkItem?
    private var enabled = false
    private var inFlight = false
    private var refreshAgain = false
    private var generation = 0
    private var connectionRevision = 0
    private var disconnectedAddress: String?
    private var connectionsInitialized = false
    private let audioQueue = DispatchQueue(label: "notchisland.airpods.audio-route", qos: .utility)
    private var audioReadRevision = 0
    private var presentationPolicy = AirPodsPresentationPolicy()
    private var presentationWork: DispatchWorkItem?
    private var automaticPresentationSuspended = false
    var status: String {
        guard enabled else { return "AirPods 连接提示未启用" }
        switch CBManager.authorization {
        case .denied, .restricted: return "需要在系统隐私设置中允许蓝牙权限"
        case .notDetermined: return "等待系统蓝牙授权，可先预览动画"
        default: break
        }
        if let snapshot { return "\(snapshot.name) · \(snapshot.connected ? "已连接" : "未连接，保留上次电量")" }
        return bluetoothReady ? "等待 AirPods 连接" : "正在连接系统蓝牙服务"
    }
    var capabilityDescription: String {
        guard let snapshot else { return "仅对系统能识别的 AirPods 报告电量；其他耳机尚未验证。" }
        let fields = [("左耳", snapshot.left), ("右耳", snapshot.right), ("耳机盒", snapshot.caseBattery)].map { name, value in "\(name)\(value == nil ? "暂不可读" : "可读")" }.joined(separator: "、")
        return "系统报告：\(fields)\(snapshot.connected ? "。" : "（缓存，未连接）。")其他耳机尚未验证。"
    }
    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }; enabled = value; generation += 1
        presentationPolicy.resetBaseline(); presentationWork?.cancel(); presentationWork = nil
        automaticPresentationSuspended = false; audioReadRevision += 1
        if value {
            disconnectedAddress = nil
            audioOutputDidChange()
            refresh()
        } else {
            let registrations = disconnections + [connection].compactMap { $0 }
            connection = nil; disconnections.removeAll(); connectedAddresses.removeAll(); bluetoothReady = false; connectionsInitialized = false
            bluetoothQueue.async { registrations.forEach { $0.unregister() } }
            timer?.invalidate(); timer = nil; refreshWork?.cancel(); refreshWork = nil
        }
    }
    deinit {
        let registrations = disconnections + [connection].compactMap { $0 }
        bluetoothQueue.async { registrations.forEach { $0.unregister() } }
        timer?.invalidate(); refreshWork?.cancel(); presentationWork?.cancel()
    }
    private func installBluetoothIfNeeded() {
        guard enabled, !bluetoothReady, !installingBluetooth else { return }
        guard CBManager.authorization != .denied, CBManager.authorization != .restricted else { return }
        installingBluetooth = true
        let expected = generation
        // IOBluetooth may wait for the initial system permission response. Never do that on AppKit's thread.
        bluetoothQueue.async { [weak self] in
            guard let self else { return }
            let connection = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(self.connected(_:device:)))
            DispatchQueue.main.async { [weak self] in
                guard let self else { connection?.unregister(); return }
                self.installingBluetooth = false
                guard self.enabled, expected == self.generation else {
                    self.bluetoothQueue.async { connection?.unregister() }
                    self.installBluetoothIfNeeded(); return
                }
                self.connection = connection; self.bluetoothReady = connection != nil
                if self.bluetoothReady { self.refreshConnections() }
            }
        }
    }
    private func refreshConnections() {
        guard enabled, bluetoothReady else { return }
        let expected = generation
        bluetoothQueue.async { [weak self] in
            guard let self else { return }
            let devices = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] ?? []).filter { $0.isConnected() }
            let addresses = Set(devices.compactMap(\.addressString).map(AirPodsProfileParser.normalizedAddress))
            let registrations = devices.compactMap { $0.register(forDisconnectNotification: self, selector: #selector(self.disconnected(_:device:))) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { registrations.forEach { $0.unregister() }; return }
                guard self.enabled, expected == self.generation else {
                    self.bluetoothQueue.async { registrations.forEach { $0.unregister() } }; return
                }
                let previous = self.disconnections
                self.disconnections = registrations
                self.bluetoothQueue.async { previous.forEach { $0.unregister() } }
                let initial = !self.connectionsInitialized
                self.connectionsInitialized = true
                // Some macOS versions briefly return no paired address while the
                // Bluetooth service is waking. Do not erase a real connect callback.
                if !addresses.isEmpty {
                    for address in self.connectedAddresses.subtracting(addresses) { self.presentationPolicy.disconnected(address) }
                    if initial || self.connectedAddresses != addresses {
                        self.connectedAddresses = addresses; self.connectionRevision += 1; self.refresh()
                    }
                }
                self.evaluateAutomaticPresentation()
            }
        }
    }
    @objc private func connected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let address = device.addressString
        DispatchQueue.main.async { [weak self] in self?.didConnect(address: address) }
    }
    private func didConnect(address: String?) {
        guard enabled else { return }
        if let address {
            let normalized = AirPodsProfileParser.normalizedAddress(address)
            connectedAddresses.insert(normalized)
            presentationPolicy.connectionEvent(normalized)
            if disconnectedAddress.map(AirPodsProfileParser.normalizedAddress) == normalized { disconnectedAddress = nil }
        }
        connectionRevision += 1; refreshConnections()
        // A renamed pair may not contain “AirPods”; a connection is cheap enough to rescan once.
        refresh(); scheduleRefresh(after: 2)
    }
    @objc private func disconnected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let address = device.addressString
        DispatchQueue.main.async { [weak self] in self?.didDisconnect(address: address) }
    }
    private func didDisconnect(address: String?) {
        guard enabled, let address else { return }
        let normalized = AirPodsProfileParser.normalizedAddress(address)
        if connectedAddresses.remove(normalized) != nil {
            presentationPolicy.disconnected(normalized); connectionRevision += 1
        }
        evaluateAutomaticPresentation()
        guard var current = snapshot, AirPodsProfileParser.normalizedAddress(current.address) == normalized else { return }
        disconnectedAddress = address
        current.connected = false; snapshot = current; onChange?(current, false)
        timer?.invalidate(); timer = nil; refresh()
    }
    func refresh() {
        guard enabled else { return }
        installBluetoothIfNeeded()
        guard !inFlight else { refreshAgain = true; return }; inFlight = true
        let expected = generation, revision = connectionRevision, previous = snapshot, disconnected = disconnectedAddress
        let addresses = connectedAddresses, connectionsKnown = connectionsInitialized
        queue.async { [weak self] in
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "mini"]
            let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
            var reports: [AirPodsSnapshot] = []
            do {
                try process.run()
                let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: timeout)
                let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); timeout.cancel()
                if process.terminationStatus == 0 { reports = AirPodsProfileParser.parse(data) }
            } catch { }
            if connectionsKnown && !addresses.isEmpty {
                reports = reports.map { report in
                    var report = report
                    report.connected = addresses.contains(AirPodsProfileParser.normalizedAddress(report.address))
                    return report
                }
            }
            reports = AirPodsProfileParser.applyingConnections(reports, connectedAddresses: addresses, disconnectedAddress: disconnected)
            var result = AirPodsProfileParser.select(reports, previousAddress: previous?.address)
            if result == nil, var cached = previous {
                if connectionsKnown && !addresses.isEmpty { cached.connected = addresses.contains(AirPodsProfileParser.normalizedAddress(cached.address)) }
                result = AirPodsProfileParser.applyingConnections([cached], connectedAddresses: addresses, disconnectedAddress: disconnected).first
            }
            DispatchQueue.main.async {
                guard let self else { return }; self.inFlight = false
                guard self.enabled else { return }
                guard expected == self.generation, revision == self.connectionRevision else { self.refreshAgain = false; self.refresh(); return }
                result = result?.preservingKnownBattery(from: previous)
                self.snapshot = result
                self.onChange?(result, false) // A battery query can never manufacture a connection animation.
                self.evaluateAutomaticPresentation()
                self.timer?.invalidate(); self.timer = nil
                if result?.connected == true {
                    let timer = Timer(timeInterval: 60, repeats: false) { [weak self] _ in self?.refreshConnections(); self?.refresh() }
                    timer.tolerance = 10; self.timer = timer; RunLoop.main.add(timer, forMode: .common)
                }
                if self.refreshAgain { self.refreshAgain = false; self.refresh() }
            }
        }
    }
    /// Called by the existing CoreAudio default-output listener; no extra polling or listener.
    func audioOutputDidChange() { readAudioOutput(confirmPresentation: false) }
    func suspendAutomaticPresentation() {
        automaticPresentationSuspended = true
        presentationPolicy.resetBaseline(); presentationWork?.cancel(); presentationWork = nil
        audioReadRevision += 1
    }
    func didWake() {
        suspendAutomaticPresentation(); automaticPresentationSuspended = false
        guard enabled else { return }
        audioOutputDidChange(); refreshConnections(); refresh()
    }
    private func readAudioOutput(confirmPresentation: Bool) {
        guard enabled, !automaticPresentationSuspended else { return }
        audioReadRevision += 1
        let expected = generation, revision = audioReadRevision
        audioQueue.async { [weak self] in
            let route = Self.currentOutput()
            DispatchQueue.main.async {
                guard let self, self.enabled, !self.automaticPresentationSuspended, expected == self.generation, revision == self.audioReadRevision else { return }
                var resolvedAddress: String?
                switch route {
                case .unavailable:
                    self.presentationPolicy.outputUnavailable(); self.presentationWork?.cancel(); self.presentationWork = nil; return
                case .selected(nil):
                    // A known non-Bluetooth output means the user is not listening
                    // through AirPods; cancel a pending connection card.
                    self.presentationPolicy.observeOutput(nil); self.presentationWork?.cancel(); self.presentationWork = nil; return
                case .selected(let address):
                    resolvedAddress = address
                    self.presentationPolicy.observeOutput(address)
                case .bluetoothUnresolved:
                    // Keep a real IOBluetooth connection candidate when CoreAudio
                    // cannot expose a MAC on this macOS release.
                    break
                }
                if confirmPresentation {
                    if self.presentationPolicy.takePresentation(for: self.snapshot, confirmedConnections: self.connectedAddresses) {
                        self.onChange?(self.snapshot, true)
                    }
                } else {
                    self.evaluateAutomaticPresentation()
                    // Route changes can precede the updated Bluetooth battery report.
                    if resolvedAddress != nil { self.refresh() }
                }
            }
        }
    }
    private func evaluateAutomaticPresentation() {
        presentationWork?.cancel(); presentationWork = nil
        guard enabled, !automaticPresentationSuspended, connectionsInitialized,
              let deadline = presentationPolicy.deadline(for: snapshot, confirmedConnections: connectedAddresses) else { return }
        let expected = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.enabled, expected == self.generation else { return }
            self.readAudioOutput(confirmPresentation: true)
        }
        presentationWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0, deadline.timeIntervalSinceNow), execute: work)
    }
    private enum OutputRoute { case unavailable, selected(String?), bluetoothUnresolved }
    private static func currentOutput() -> OutputRoute {
        var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device: AudioDeviceID = 0, size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &device) == noErr, device != 0 else { return .unavailable }
        property.mSelector = kAudioDevicePropertyTransportType
        var transport: UInt32 = 0; size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &transport) == noErr else { return .unavailable }
        guard transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE else { return .selected(nil) }
        property.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?; size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &uid) == noErr,
              let uid else { return .unavailable }
        let address = AirPodsAudioRoute.address(fromDeviceUID: uid.takeRetainedValue() as String)
        return address.map(OutputRoute.selected) ?? .bluetoothUnresolved
    }
    private func scheduleRefresh(after seconds: TimeInterval) {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }; refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
