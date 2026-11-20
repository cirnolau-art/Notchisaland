import AppKit
import CoreAudio

struct AudioOutput: Equatable, Identifiable {
    let id: AudioDeviceID
    let name: String
    let transport: UInt32
    let canAdjustVolume: Bool
    var symbol: String {
        if name.localizedCaseInsensitiveContains("airpods") || name.localizedCaseInsensitiveContains("pods pro") { return "airpodspro" }
        if transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE { return "headphones" }
        if transport == kAudioDeviceTransportTypeBuiltIn { return "laptopcomputer" }
        if transport == kAudioDeviceTransportTypeHDMI || transport == kAudioDeviceTransportTypeDisplayPort { return "display" }
        if transport == kAudioDeviceTransportTypeAirPlay { return "airplay.audio" }
        return "hifispeaker.fill"
    }
}

/// CoreAudio listeners replace device polling. Device IDs are never persisted across boots.
final class AudioOutputMonitor {
    var onChange: (() -> Void)?
    private(set) var outputs: [AudioOutput] = []
    private(set) var selected: AudioDeviceID = 0
    private(set) var switching: AudioDeviceID?
    private(set) var error: String?
    private let queue = DispatchQueue(label: "notchisland.audio.outputs", qos: .userInitiated)
    private var listener: AudioObjectPropertyListenerBlock?
    private var deviceListeners: [(AudioDeviceID, AudioObjectPropertyAddress)] = [] // queue only
    private var refreshPending = false
    private var started = false // main thread
    private var generation = 0 // main thread
    private var listening = false // queue only
    private var listeningGeneration = 0 // queue only
    func setEnabled(_ value: Bool) {
        if value { start(); return }
        guard started else { return }; started = false; generation += 1
        outputs = []; selected = 0; switching = nil; error = nil
        queue.async { [weak self] in
            guard let self else { return }; self.listening = false
            if let listener = self.listener {
                for selector in self.selectors { var address = Self.address(selector); AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, self.queue, listener) }
                for (id, var address) in self.deviceListeners { AudioObjectRemovePropertyListenerBlock(id, &address, self.queue, listener) }
            }
            self.deviceListeners.removeAll(); self.listener = nil
        }
        onChange?()
    }
    private let selectors = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice]
    func start() {
        guard !started else { return }; started = true; generation += 1
        let generation = self.generation
        queue.async { [weak self] in
            guard let self else { return }
            self.listening = true; self.listeningGeneration = generation
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRefresh() }
            self.listener = listener
            for selector in self.selectors { var address = Self.address(selector); AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, self.queue, listener) }
            self.read()
        }
    }
    private static func address(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal, element: UInt32 = 0) -> AudioObjectPropertyAddress { .init(mSelector: selector, mScope: scope, mElement: element) }
    private func scheduleRefresh() {
        guard !refreshPending else { return }; refreshPending = true
        queue.asyncAfter(deadline: .now() + 0.08) { [weak self] in self?.refreshPending = false; self?.read() }
    }
    func refresh() { queue.async { [weak self] in self?.read() } }
    private func read() {
        guard listening else { return }; let generation = listeningGeneration
        var address = Self.address(kAudioHardwarePropertyDevices), size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return }
        if let listener {
            for (id, var property) in deviceListeners { AudioObjectRemovePropertyListenerBlock(id, &property, queue, listener) }
            deviceListeners.removeAll()
        }
        var devices: [AudioOutput] = []
        for id in ids {
            var streams = Self.address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput), bytes: UInt32 = 0
            guard AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &bytes) == noErr, bytes > 0 else { continue }
            var alive: UInt32 = 1; var valueSize = UInt32(MemoryLayout<UInt32>.size)
            var aliveAddress = Self.address(kAudioDevicePropertyDeviceIsAlive)
            _ = AudioObjectGetPropertyData(id, &aliveAddress, 0, nil, &valueSize, &alive)
            guard alive != 0 else { continue }
            var nameReference: Unmanaged<CFString>?; var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var nameAddress = Self.address(kAudioObjectPropertyName)
            _ = AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &nameReference)
            let name = nameReference.map { $0.takeRetainedValue() as String } ?? "音频设备"
            var transport: UInt32 = 0; valueSize = UInt32(MemoryLayout<UInt32>.size)
            var transportAddress = Self.address(kAudioDevicePropertyTransportType)
            _ = AudioObjectGetPropertyData(id, &transportAddress, 0, nil, &valueSize, &transport)
            let canAdjust = (0...2).contains { channel in
                var property = Self.address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: UInt32(channel))
                var settable: DarwinBoolean = false
                return AudioObjectHasProperty(id, &property) && AudioObjectIsPropertySettable(id, &property, &settable) == noErr && settable.boolValue
            }
            devices.append(.init(id: id, name: name, transport: transport, canAdjustVolume: canAdjust))
            if let listener {
                for selector in [kAudioObjectPropertyName, kAudioDevicePropertyDeviceIsAlive, kAudioDevicePropertyStreams] {
                    var property = Self.address(selector, scope: selector == kAudioDevicePropertyStreams ? kAudioDevicePropertyScopeOutput : kAudioObjectPropertyScopeGlobal)
                    if AudioObjectAddPropertyListenerBlock(id, &property, queue, listener) == noErr { deviceListeners.append((id, property)) }
                }
            }
        }
        var defaultID: AudioDeviceID = 0; size = UInt32(MemoryLayout<AudioDeviceID>.size)
        address = Self.address(kAudioHardwarePropertyDefaultOutputDevice)
        _ = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &defaultID)
        devices.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.started, generation == self.generation else { return }
            let changed = self.outputs != devices || self.selected != defaultID
            self.outputs = devices; self.selected = defaultID
            if self.switching == defaultID { self.switching = nil }
            if changed { self.onChange?() }
        }
    }
    func select(_ id: AudioDeviceID) {
        guard started, switching == nil, outputs.contains(where: { $0.id == id }), id != selected else { return }
        switching = id; error = nil; onChange?()
        queue.async { [weak self] in
            guard let self else { return }
            guard self.listening else { return }
            var address = Self.address(kAudioHardwarePropertyDefaultOutputDevice), device = id
            let result = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &device)
            self.read()
            DispatchQueue.main.async {
                self.switching = nil
                if result != noErr || self.selected != id { self.error = "未能切换，请确认设备仍然连接" }
                self.onChange?()
            }
        }
    }
}
