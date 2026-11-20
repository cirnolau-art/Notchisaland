import AppKit
import CoreBluetooth
import CoreAudio
import IOBluetooth

/// Connection and audio-route events are independent from silent battery refreshes.
final class AirPodsMonitor: NSObject {
    var onChange: ((AirPodsSnapshot?, Bool) -> Void)?
    /// Return true only after the card is actually accepted by the UI. Busy surfaces
    /// can defer a current event briefly without consuming its per-device cooldown.
    var onPresentation: ((AirPodsSnapshot) -> Bool)?
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
    private let audioQueueKey = DispatchSpecificKey<UInt8>()
    private var audioFallback: Timer?
    // The following listener registrations are owned exclusively by audioQueue.
    private var audioObservationRunning = false
    private var systemOutputListener: AudioObjectPropertyListenerBlock?
    private var systemOutputProperties: [AudioObjectPropertyAddress] = []
    private var observedOutput: AudioObjectID = 0
    private var outputDeviceListener: AudioObjectPropertyListenerBlock?
    private var outputDeviceProperties: [AudioObjectPropertyAddress] = []
    private var audioReadRevision = 0
    private var presentationPolicy = AirPodsPresentationPolicy()
    private var presentationWork: DispatchWorkItem?
    private var automaticPresentationSuspended = false
    private var outputAddress: String?
    private var hydrationAddress: String?
    private var hydrationAttempts = 0
    private var lastHydrationAttempt = Date.distantPast
    private var loggedActivation = false
    private var loggedBusyDelivery = false
    private let outputReader: (() -> (address: String?, available: Bool))?
    private let batteryReader: (() -> [AirPodsSnapshot])?
    private let observesSystem: Bool
    private let recoveryQuietPeriod: TimeInterval
    private let outputFallbackInterval: TimeInterval
    /// An alive default audio device is direct evidence of an active route, even if
    /// IOBluetooth's paired-device enumeration has not caught up yet.
    private var confirmedPresentationConnections: Set<String> {
        connectedAddresses.union(outputAddress.map { [$0] } ?? [])
    }
    override convenience init() {
        self.init(outputReader: nil, batteryReader: nil, observesSystem: true,
                  recoveryQuietPeriod: AirPodsPresentationPolicy.recoveryQuietPeriod, outputFallbackInterval: 5)
    }
    init(outputReader: (() -> (address: String?, available: Bool))?, batteryReader: (() -> [AirPodsSnapshot])?,
         observesSystem: Bool, recoveryQuietPeriod: TimeInterval, outputFallbackInterval: TimeInterval) {
        self.outputReader = outputReader; self.batteryReader = batteryReader; self.observesSystem = observesSystem
        self.recoveryQuietPeriod = recoveryQuietPeriod; self.outputFallbackInterval = outputFallbackInterval
        super.init()
        audioQueue.setSpecific(key: audioQueueKey, value: 1)
    }
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
        presentationPolicy.resetBaseline(quietPeriod: recoveryQuietPeriod); presentationWork?.cancel(); presentationWork = nil
        automaticPresentationSuspended = false; audioReadRevision += 1; outputAddress = nil
        hydrationAddress = nil; hydrationAttempts = 0
        loggedActivation = false; loggedBusyDelivery = false
        if value {
            disconnectedAddress = nil
            if observesSystem { audioQueue.async { [weak self] in self?.startAudioObservation() } }
            startAudioFallback()
            audioOutputDidChange()
            refresh()
        } else {
            audioFallback?.invalidate(); audioFallback = nil
            audioQueue.async { [weak self] in self?.stopAudioObservation() }
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
        audioFallback?.invalidate()
        if DispatchQueue.getSpecific(key: audioQueueKey) != nil { stopAudioObservation() }
        else { audioQueue.sync { stopAudioObservation() } }
    }
    private func installBluetoothIfNeeded() {
        guard enabled, observesSystem, !bluetoothReady, !installingBluetooth else { return }
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
        let expected = generation, revision = connectionRevision
        bluetoothQueue.async { [weak self] in
            guard let self else { return }
            // A failed enumeration is unknown; a successful list with no connected
            // devices is a real empty baseline. Do not retain stale links forever.
            guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
            let devices = paired.filter { $0.isConnected() }
            let addresses = Set(devices.compactMap(\.addressString).map(AirPodsProfileParser.normalizedAddress))
            let registrations = devices.compactMap { $0.register(forDisconnectNotification: self, selector: #selector(self.disconnected(_:device:))) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { registrations.forEach { $0.unregister() }; return }
                guard self.enabled, expected == self.generation else {
                    self.bluetoothQueue.async { registrations.forEach { $0.unregister() } }; return
                }
                guard revision == self.connectionRevision else {
                    self.bluetoothQueue.async { registrations.forEach { $0.unregister() } }
                    self.refreshConnections(); return
                }
                let previous = self.disconnections
                self.disconnections = registrations
                self.bluetoothQueue.async { previous.forEach { $0.unregister() } }
                let initial = !self.connectionsInitialized
                self.connectionsInitialized = true
                for address in self.connectedAddresses.subtracting(addresses) where address != self.outputAddress {
                    self.presentationPolicy.disconnected(address)
                }
                if initial || self.connectedAddresses != addresses {
                    self.connectedAddresses = addresses; self.connectionRevision += 1; self.refresh()
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
            if disconnectedAddress.map(AirPodsProfileParser.normalizedAddress) == normalized { disconnectedAddress = nil }
        }
        connectionRevision += 1; refreshConnections()
        // Opening the case can create a Bluetooth link without starting listening.
        // Recheck the actual route; the connection itself never requests a card.
        audioOutputDidChange()
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
        if outputAddress == normalized { outputAddress = nil }
        if connectedAddresses.remove(normalized) != nil {
            presentationPolicy.disconnected(normalized); connectionRevision += 1
        }
        evaluateAutomaticPresentation()
        guard var current = snapshot, AirPodsProfileParser.normalizedAddress(current.address) == normalized else { return }
        disconnectedAddress = address
        current.connected = false; snapshot = current; onChange?(current, false)
        timer?.invalidate(); timer = nil; refresh()
    }
    @discardableResult func refresh() -> Bool {
        guard enabled else { return false }
        installBluetoothIfNeeded()
        guard !inFlight else { refreshAgain = true; return false }; inFlight = true
        let expected = generation, revision = connectionRevision, previous = snapshot, disconnected = disconnectedAddress
        let addresses = connectedAddresses, activeOutput = outputAddress
        let preferredAddress = activeOutput ?? previous?.address
        queue.async { [weak self] in
            var reports: [AirPodsSnapshot] = []
            if let batteryReader = self?.batteryReader { reports = batteryReader() }
            else {
                let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
                // `mini` removes device_address on current macOS, leaving battery data
                // keyed by the display name and making it impossible to match CoreAudio.
                process.arguments = ["SPBluetoothDataType", "-json", "-detailLevel", "basic"]
                let pipe = Pipe(); process.standardOutput = pipe; process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 5, execute: timeout)
                    let data = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit(); timeout.cancel()
                    if process.terminationStatus == 0 { reports = AirPodsProfileParser.parse(data) }
                } catch { }
            }
            let activeConnections = addresses.union(activeOutput.map { [$0] } ?? [])
            reports = AirPodsProfileParser.applyingConnections(reports, connectedAddresses: activeConnections, disconnectedAddress: disconnected)
            var result = AirPodsProfileParser.select(reports, previousAddress: preferredAddress)
            if result == nil, var cached = previous {
                cached.connected = activeConnections.contains(AirPodsProfileParser.normalizedAddress(cached.address))
                result = AirPodsProfileParser.applyingConnections([cached], connectedAddresses: activeConnections, disconnectedAddress: disconnected).first
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
        return true
    }
    /// Called by our HAL observers and the existing volume monitor. Repeated events
    /// refresh the same baseline and never manufacture another activation.
    func audioOutputDidChange() { readAudioOutput(confirmPresentation: false) }
    func suspendAutomaticPresentation() {
        automaticPresentationSuspended = true
        audioFallback?.invalidate(); audioFallback = nil
        presentationPolicy.resetBaseline(quietPeriod: recoveryQuietPeriod); presentationWork?.cancel(); presentationWork = nil
        audioReadRevision += 1; outputAddress = nil; hydrationAddress = nil
        loggedActivation = false; loggedBusyDelivery = false
    }
    func didWake() {
        suspendAutomaticPresentation(); automaticPresentationSuspended = false
        guard enabled else { return }
        startAudioFallback()
        audioOutputDidChange(); refreshConnections(); refresh()
    }
    private func readAudioOutput(confirmPresentation: Bool) {
        guard enabled, !automaticPresentationSuspended else { return }
        audioReadRevision += 1
        let expected = generation, revision = audioReadRevision
        audioQueue.async { [weak self] in
            guard let self else { return }
            let route: OutputReading
            if let read = self.outputReader?() { route = .init(output: read.available ? .selected(read.address) : .unavailable, device: 0) }
            else { route = Self.currentOutput() }
            self.observeOutputDevice(route.device)
            DispatchQueue.main.async {
                guard self.enabled, !self.automaticPresentationSuspended, expected == self.generation, revision == self.audioReadRevision else { return }
                var resolvedAddress: String?
                var changed = false
                switch route.output {
                case .unavailable:
                    self.presentationPolicy.outputUnavailable(); self.evaluateAutomaticPresentation(minimumDelay: 0.8); return
                case .selected(nil):
                    // A known non-Bluetooth output means the user is not listening
                    // through AirPods; cancel a pending connection card.
                    let hadAirPodsOutput = self.outputAddress != nil
                    self.outputAddress = nil; self.hydrationAddress = nil
                    self.presentationPolicy.observeOutput(nil); self.presentationWork?.cancel(); self.presentationWork = nil
                    if self.loggedActivation { print("[AirPods] activation canceled: output changed") }
                    self.loggedActivation = false; self.loggedBusyDelivery = false
                    if hadAirPodsOutput { self.refresh() }
                    return
                case .selected(let address):
                    resolvedAddress = address
                    changed = self.outputAddress != address
                    self.outputAddress = address
                    if self.disconnectedAddress.map(AirPodsProfileParser.normalizedAddress) == address { self.disconnectedAddress = nil }
                    self.presentationPolicy.observeOutput(address)
                case .bluetoothUnresolved:
                    // An unidentified Bluetooth route cannot authorize an AirPods
                    // card. Fail quietly rather than reusing a previous output.
                    self.outputAddress = nil
                    self.presentationPolicy.outputUnavailable(); self.evaluateAutomaticPresentation(minimumDelay: 0.8); return
                }
                if changed {
                    self.hydrationAddress = resolvedAddress; self.hydrationAttempts = 0; self.lastHydrationAttempt = .distantPast
                    if self.presentationPolicy.pendingAddress() != nil, !self.loggedActivation {
                        self.loggedActivation = true; self.loggedBusyDelivery = false
                        print("[AirPods] output activation detected; confirming battery and stability")
                    }
                }
                if let address = resolvedAddress, var current = self.snapshot,
                   AirPodsProfileParser.normalizedAddress(current.address) == address, !current.connected {
                    // The alive route proves connection; retain usable cached battery
                    // while the system's new battery report catches up.
                    current.connected = true
                    for (key, value) in [("left", current.left), ("right", current.right), ("case", current.caseBattery)] where value != nil { current.cachedFields.insert(key) }
                    self.snapshot = current; self.onChange?(current, false)
                }
                if confirmPresentation {
                    if let snapshot = self.snapshot,
                       let deadline = self.presentationPolicy.deadline(for: snapshot, confirmedConnections: self.confirmedPresentationConnections), deadline <= Date(),
                       self.onPresentation?(snapshot) == true {
                        _ = self.presentationPolicy.takePresentation(for: snapshot, confirmedConnections: self.confirmedPresentationConnections)
                        self.loggedActivation = false; self.loggedBusyDelivery = false
                        print("[AirPods] activation card displayed")
                    } else {
                        if self.presentationPolicy.deadline(for: self.snapshot, confirmedConnections: self.confirmedPresentationConnections).map({ $0 <= Date() }) == true,
                           !self.loggedBusyDelivery {
                            self.loggedBusyDelivery = true; print("[AirPods] current activation waiting for the interface")
                        }
                        self.requestPendingBattery()
                        self.evaluateAutomaticPresentation(minimumDelay: 0.5)
                    }
                } else {
                    // A route refresh is cheap. Query system_profiler only for a
                    // transition or missing data during the bounded activation burst.
                    if changed { self.requestPendingBattery(force: true) }
                    else { self.requestPendingBattery() }
                    self.evaluateAutomaticPresentation()
                }
            }
        }
    }
    private func requestPendingBattery(force: Bool = false) {
        guard let address = outputAddress, hydrationAddress == address,
              force || presentationPolicy.pendingAddress() != nil,
              hydrationAttempts < 4, Date().timeIntervalSince(lastHydrationAttempt) >= 2 else { return }
        let matches = snapshot.map { AirPodsProfileParser.normalizedAddress($0.address) == address && $0.hasBattery } == true
        guard force || !matches else { return }
        lastHydrationAttempt = Date()
        if refresh() { hydrationAttempts += 1 }
    }
    private func evaluateAutomaticPresentation(minimumDelay: TimeInterval = 0) {
        presentationWork?.cancel(); presentationWork = nil
        guard enabled, !automaticPresentationSuspended else { return }
        guard presentationPolicy.pendingAddress() != nil else {
            if loggedActivation { print("[AirPods] activation expired without display") }
            loggedActivation = false; loggedBusyDelivery = false
            return
        }
        let deadline = presentationPolicy.deadline(for: snapshot, confirmedConnections: confirmedPresentationConnections)
        let delay = max(minimumDelay, deadline.map { max(0, $0.timeIntervalSinceNow) } ?? 0.8)
        let expected = generation
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.enabled, expected == self.generation else { return }
            self.readAudioOutput(confirmPresentation: true)
        }
        presentationWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }
    private enum OutputRoute { case unavailable, selected(String?), bluetoothUnresolved }
    private struct OutputReading { let output: OutputRoute; let device: AudioObjectID }
    private static func currentOutput() -> OutputReading {
        var property = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device: AudioDeviceID = 0, size = UInt32(MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &property, 0, nil, &size, &device) == noErr, device != 0 else { return .init(output: .unavailable, device: 0) }
        property.mSelector = kAudioDevicePropertyDeviceIsAlive
        var alive: UInt32 = 0; size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &alive) == noErr else { return .init(output: .unavailable, device: device) }
        guard alive != 0 else { return .init(output: .selected(nil), device: device) }
        property.mSelector = kAudioDevicePropertyTransportType
        var transport: UInt32 = 0; size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &transport) == noErr else { return .init(output: .unavailable, device: device) }
        guard transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE else { return .init(output: .selected(nil), device: device) }
        property.mSelector = kAudioDevicePropertyDeviceUID
        var uid: Unmanaged<CFString>?; size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &property, 0, nil, &size, &uid) == noErr,
              let uid else { return .init(output: .unavailable, device: device) }
        let address = AirPodsAudioRoute.address(fromDeviceUID: uid.takeRetainedValue() as String)
        return .init(output: address.map(OutputRoute.selected) ?? .bluetoothUnresolved, device: device)
    }
    private func startAudioFallback() {
        guard enabled, !automaticPresentationSuspended, audioFallback == nil else { return }
        // Some Bluetooth drivers omit a default-device callback during automatic
        // switching. This reads only HAL properties; it never polls battery data.
        let timer = Timer(timeInterval: outputFallbackInterval, repeats: true) { [weak self] _ in self?.audioOutputDidChange() }
        timer.tolerance = min(1, outputFallbackInterval * 0.2); audioFallback = timer; RunLoop.main.add(timer, forMode: .common)
    }
    private func startAudioObservation() {
        guard !audioObservationRunning else { return }; audioObservationRunning = true
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in self?.audioOutputDidChange() }
        }
        systemOutputListener = listener
        for selector in [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice, kAudioHardwarePropertyDevices] {
            var property = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &property, audioQueue, listener) == noErr {
                systemOutputProperties.append(property)
            }
        }
    }
    private func observeOutputDevice(_ device: AudioObjectID) {
        guard audioObservationRunning, device != observedOutput else { return }
        removeOutputDeviceObservation(); observedOutput = device
        guard device != 0 else { return }
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async { [weak self] in self?.audioOutputDidChange() }
        }
        outputDeviceListener = listener
        for selector in [kAudioDevicePropertyDeviceIsAlive, kAudioDevicePropertyDeviceUID, kAudioDevicePropertyTransportType, kAudioDevicePropertyDeviceIsRunningSomewhere] {
            var property = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            guard AudioObjectHasProperty(device, &property) else { continue }
            if AudioObjectAddPropertyListenerBlock(device, &property, audioQueue, listener) == noErr { outputDeviceProperties.append(property) }
        }
    }
    private func removeOutputDeviceObservation() {
        if let listener = outputDeviceListener {
            for var property in outputDeviceProperties { AudioObjectRemovePropertyListenerBlock(observedOutput, &property, audioQueue, listener) }
        }
        outputDeviceListener = nil; outputDeviceProperties.removeAll(); observedOutput = 0
    }
    private func stopAudioObservation() {
        audioObservationRunning = false; removeOutputDeviceObservation()
        if let listener = systemOutputListener {
            for var property in systemOutputProperties { AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &property, audioQueue, listener) }
        }
        systemOutputListener = nil; systemOutputProperties.removeAll()
    }
    private func scheduleRefresh(after seconds: TimeInterval) {
        refreshWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh() }; refreshWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}
