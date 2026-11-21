import AppKit
import CoreAudio

/// CoreAudio I/O and property callbacks stay off the animation/event-tap thread.
final class VolumeMonitor {
    var onVolumeChange: ((Double, Bool) -> Void)?
    var onAvailabilityChange: (() -> Void)?
    private let io = DispatchQueue(label: "notchisland.audio.io", qos: .userInteractive)
    private var deviceID: AudioObjectID = 0
    private var deviceListener: AudioObjectPropertyListenerBlock?
    private var systemListener: AudioObjectPropertyListenerBlock?
    private var attachedAddresses: [AudioObjectPropertyAddress] = []
    private var volumeBeforeMute = 0.5
    private var cachedVolume: Double?
    private var cachedMuted = false
    private(set) var canAdjust = false
    private var settleUntil = Date.distantPast
    private var writeWork: DispatchWorkItem?
    private var revision = 0
    private var started = false
    private var reportPending = false
    private var defaultAddress: AudioObjectPropertyAddress {
        .init(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    func start() {
        guard !started else { return }; started = true
        io.async { [weak self] in
            guard let self else { return }
            let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.changeDevice() }
            self.systemListener = listener
            var address = self.defaultAddress
            AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, self.io, listener)
            self.changeDevice()
        }
    }
    private func changeDevice() {
        if let deviceListener {
            for var address in attachedAddresses { AudioObjectRemovePropertyListenerBlock(deviceID, &address, io, deviceListener) }
        }
        attachedAddresses.removeAll(); deviceListener = nil; deviceID = 0
        var address = defaultAddress; var size = UInt32(MemoryLayout<AudioObjectID>.size); var id: AudioObjectID = 0
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id) == noErr, id != 0 else {
            DispatchQueue.main.async { [weak self] in self?.canAdjust = false; self?.cachedVolume = nil; self?.onAvailabilityChange?() }; return
        }
        deviceID = id
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleRead() }
        deviceListener = listener
        var adjustable = false
        for selector in [kAudioDevicePropertyVolumeScalar, kAudioDevicePropertyMute] {
            for element: AudioObjectPropertyElement in [0, 1, 2] {
                var address = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
                guard AudioObjectHasProperty(id, &address) else { continue }
                if AudioObjectAddPropertyListenerBlock(id, &address, io, listener) == noErr { attachedAddresses.append(address) }
                var settable: DarwinBoolean = false
                if selector == kAudioDevicePropertyVolumeScalar, AudioObjectIsPropertySettable(id, &address, &settable) == noErr, settable.boolValue { adjustable = true }
            }
        }
        let value = readVolume(), muted = readMuted()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.canAdjust = adjustable; self.cachedVolume = value; self.cachedMuted = muted; self.settleUntil = .distantPast
            self.onAvailabilityChange?()
        }
    }
    private func readVolume() -> Double? {
        guard deviceID != 0 else { return nil }
        for element: AudioObjectPropertyElement in [0, 1, 2] {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var value: Float32 = 0; var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr { return Double(value) }
        }
        return nil
    }
    private func readMuted() -> Bool {
        for element: AudioObjectPropertyElement in [0, 1, 2] {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var value: UInt32 = 0; var size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value) == noErr { return value != 0 }
        }
        return readVolume() == 0
    }
    private func writeVolume(_ volume: Double) -> Bool {
        var success = false
        for element: AudioObjectPropertyElement in [0, 1, 2] {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyVolumeScalar, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var settable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr, settable.boolValue else { continue }
            var value = Float32(min(1, max(0, volume)))
            if AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr { success = true; if element == 0 { break } }
        }
        return success
    }
    @discardableResult private func writeMuted(_ muted: Bool) -> Bool {
        var success = false
        for element: AudioObjectPropertyElement in [0, 1, 2] {
            var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: element)
            var settable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(deviceID, &address, &settable) == noErr, settable.boolValue else { continue }
            var value: UInt32 = muted ? 1 : 0
            if AudioObjectSetPropertyData(deviceID, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr { success = true; if element == 0 { break } }
        }
        return success
    }
    private func scheduleRead() {
        guard !reportPending else { return }; reportPending = true
        io.asyncAfter(deadline: .now() + 0.025) { [weak self] in
            guard let self else { return }; self.reportPending = false
            let value = self.readVolume(), muted = self.readMuted()
            DispatchQueue.main.async {
                guard Date() >= self.settleUntil, let value else { return }
                guard self.cachedVolume.map({ abs($0 - value) > 0.001 }) != false || muted != self.cachedMuted else { return }
                self.cachedVolume = value; self.cachedMuted = muted; self.onVolumeChange?(value, muted)
            }
        }
    }
    func currentVolume() -> Double? { cachedVolume }
    var isMuted: Bool { cachedMuted }
    @discardableResult func setVolume(_ volume: Double) -> Bool { apply(volume, muted: false) }
    private func apply(_ volume: Double, muted: Bool) -> Bool {
        guard volume.isFinite, canAdjust else { return false }
        let value = min(1, max(0, volume)); cachedVolume = value; cachedMuted = muted
        settleUntil = Date().addingTimeInterval(0.16); revision += 1
        let expected = revision
        onVolumeChange?(value, muted)
        writeWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let success: Bool
            if muted { success = self.writeMuted(true) || self.writeVolume(0) }
            else { success = self.writeVolume(value); if success { self.writeMuted(false) } }
            DispatchQueue.main.async {
                if !success, self.revision == expected { self.canAdjust = false; self.settleUntil = .distantPast; self.report() }
            }
        }
        writeWork = work; io.asyncAfter(deadline: .now() + 0.006, execute: work)
        return true
    }
    @discardableResult func nudge(_ delta: Double) -> Bool {
        guard let current = cachedVolume else { return false }
        return apply(current + delta, muted: false)
    }
    @discardableResult func toggleMute() -> Bool {
        guard let current = cachedVolume else { return false }
        if !cachedMuted { volumeBeforeMute = current }
        return apply(cachedMuted ? max(current, volumeBeforeMute) : current, muted: !cachedMuted)
    }
    func report() { io.async { [weak self] in self?.scheduleRead() } }
}
