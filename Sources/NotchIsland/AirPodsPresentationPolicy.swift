import Foundation

/// A Bluetooth link or a battery report does not imply that the earbuds are being worn.
/// Only a stable transition of the Mac's actual audio output can request an automatic card.
struct AirPodsPresentationPolicy {
    static let recoveryQuietPeriod: TimeInterval = 10
    static let settlingDelay: TimeInterval = 2
    static let briefReconnect: TimeInterval = 30
    static let cooldown: TimeInterval = 120
    static let candidateLifetime: TimeInterval = 12
    private var quietUntil = Date.distantPast
    private var outputInitialized = false
    private var outputAddress: String?
    private var candidate: (address: String, changedAt: Date)?
    private var leftOutputAt: [String: Date] = [:]
    private var disconnectedAt: [String: Date] = [:]
    private var lastShownAt: [String: Date] = [:]

    mutating func resetBaseline(at now: Date = Date()) {
        quietUntil = now.addingTimeInterval(Self.recoveryQuietPeriod)
        outputInitialized = false; outputAddress = nil; candidate = nil
        leftOutputAt.removeAll(); disconnectedAt.removeAll()
        // Keep the short cooldown through sleep and preference toggles.
    }
    mutating func observeOutput(_ address: String?, at now: Date = Date()) {
        let address = address.map(AirPodsProfileParser.normalizedAddress)
        lastShownAt = lastShownAt.filter { now.timeIntervalSince($0.value) < Self.cooldown }
        guard now >= quietUntil else {
            outputInitialized = true; outputAddress = address; candidate = nil
            return
        }
        guard outputInitialized else { outputInitialized = true; outputAddress = address; return }
        guard address != outputAddress else { return }
        if let previous = outputAddress { leftOutputAt[previous] = now }
        outputAddress = address; candidate = nil
        guard let address,
              leftOutputAt[address].map({ now.timeIntervalSince($0) >= Self.briefReconnect }) ?? true,
              disconnectedAt[address].map({ now.timeIntervalSince($0) >= Self.briefReconnect }) ?? true,
              lastShownAt[address].map({ now.timeIntervalSince($0) >= Self.cooldown }) ?? true else { return }
        candidate = (address, now)
    }
    mutating func outputUnavailable() { candidate = nil }
    /// A real IOBluetooth connect callback is a reliable start-of-use signal even when
    /// CoreAudio's device UID omits the MAC address on older macOS releases.
    mutating func connectionEvent(_ address: String, at now: Date = Date()) {
        let address = AirPodsProfileParser.normalizedAddress(address)
        lastShownAt = lastShownAt.filter { now.timeIntervalSince($0.value) < Self.cooldown }
        guard now >= quietUntil,
              leftOutputAt[address].map({ now.timeIntervalSince($0) >= Self.briefReconnect }) ?? true,
              disconnectedAt[address].map({ now.timeIntervalSince($0) >= Self.briefReconnect }) ?? true,
              lastShownAt[address].map({ now.timeIntervalSince($0) >= Self.cooldown }) ?? true else { return }
        outputInitialized = true; outputAddress = address; candidate = (address, now)
    }
    mutating func disconnected(_ address: String, at now: Date = Date()) {
        let address = AirPodsProfileParser.normalizedAddress(address)
        disconnectedAt[address] = now
        if candidate?.address == address { candidate = nil }
    }
    func deadline(for snapshot: AirPodsSnapshot?, confirmedConnections: Set<String>, at now: Date = Date()) -> Date? {
        guard let candidate, let snapshot, snapshot.connected,
              AirPodsProfileParser.normalizedAddress(snapshot.address) == candidate.address,
              outputAddress == candidate.address,
              confirmedConnections.contains(where: { AirPodsProfileParser.normalizedAddress($0) == candidate.address }),
              now.timeIntervalSince(candidate.changedAt) <= Self.candidateLifetime else { return nil }
        return candidate.changedAt.addingTimeInterval(Self.settlingDelay)
    }
    mutating func takePresentation(for snapshot: AirPodsSnapshot?, confirmedConnections: Set<String>, at now: Date = Date()) -> Bool {
        guard let deadline = deadline(for: snapshot, confirmedConnections: confirmedConnections, at: now), now >= deadline,
              let candidate else { return false }
        self.candidate = nil; lastShownAt[candidate.address] = now
        return true
    }
}

/// CoreAudio Bluetooth UIDs contain the hardware address. Names are deliberately not used:
/// two devices may share a name, and a missing address should fail quietly.
enum AirPodsAudioRoute {
    static func address(fromDeviceUID uid: String) -> String? {
        let pattern = "(?i)(?<![0-9a-f])(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}(?![0-9a-f])"
        guard let range = uid.range(of: pattern, options: .regularExpression) else { return nil }
        return AirPodsProfileParser.normalizedAddress(String(uid[range]))
    }
}
