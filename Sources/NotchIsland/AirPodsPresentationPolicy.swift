import Foundation

/// A Bluetooth link or a battery report does not imply that the earbuds are being worn.
/// Only a stable transition of the Mac's actual audio output can request an automatic card.
struct AirPodsPresentationPolicy {
    static let recoveryQuietPeriod: TimeInterval = 10
    static let settlingDelay: TimeInterval = 2
    static let briefReconnect: TimeInterval = 30
    static let cooldown: TimeInterval = 120
    static let candidateLifetime: TimeInterval = 20
    private var quietUntil = Date.distantPast
    private var outputInitialized = false
    private var outputAddress: String?
    private var outputBeganAt: Date?
    private var routeConfirmed = false
    private var candidate: (address: String, changedAt: Date)?
    private var leftOutputAt: [String: Date] = [:]
    private var disconnectedAt: [String: Date] = [:]
    private var lastShownAt: [String: Date] = [:]

    mutating func resetBaseline(at now: Date = Date(), quietPeriod: TimeInterval = Self.recoveryQuietPeriod) {
        quietUntil = now.addingTimeInterval(quietPeriod)
        outputInitialized = false; outputAddress = nil; outputBeganAt = nil; routeConfirmed = false; candidate = nil
        leftOutputAt.removeAll(); disconnectedAt.removeAll()
        // Keep the short cooldown through sleep and preference toggles.
    }
    mutating func observeOutput(_ address: String?, at now: Date = Date()) {
        let address = address.map(AirPodsProfileParser.normalizedAddress)
        routeConfirmed = true
        lastShownAt = lastShownAt.filter { now.timeIntervalSince($0.value) < Self.cooldown }
        guard now >= quietUntil else {
            if address != outputAddress { outputBeganAt = now }
            outputInitialized = true; outputAddress = address; candidate = nil
            return
        }
        guard outputInitialized else { outputInitialized = true; outputAddress = address; outputBeganAt = now; return }
        guard address != outputAddress else { return }
        // Route negotiation can briefly expose AirPods, then the speaker, then
        // AirPods again. Only a previously stable session counts as a reconnect.
        if let previous = outputAddress, let began = outputBeganAt, now.timeIntervalSince(began) >= Self.settlingDelay {
            leftOutputAt[previous] = now
        }
        outputAddress = address; outputBeganAt = now; candidate = nil
        guard let address,
              leftOutputAt[address].map({ now.timeIntervalSince($0) >= Self.briefReconnect }) ?? true,
              disconnectedAt[address].map({ now.timeIntervalSince($0) >= Self.briefReconnect }) ?? true,
              lastShownAt[address].map({ now.timeIntervalSince($0) >= Self.cooldown }) ?? true else { return }
        candidate = (address, now)
    }
    mutating func outputUnavailable() { routeConfirmed = false }
    mutating func disconnected(_ address: String, at now: Date = Date()) {
        let address = AirPodsProfileParser.normalizedAddress(address)
        if outputAddress != address || outputBeganAt.map({ now.timeIntervalSince($0) >= Self.settlingDelay }) == true {
            disconnectedAt[address] = now
        }
        if outputAddress == address { outputAddress = nil; outputBeganAt = nil; routeConfirmed = false }
        if candidate?.address == address { candidate = nil }
    }
    func pendingAddress(at now: Date = Date()) -> String? {
        guard let candidate, now.timeIntervalSince(candidate.changedAt) <= Self.candidateLifetime else { return nil }
        return candidate.address
    }
    func deadline(for snapshot: AirPodsSnapshot?, confirmedConnections: Set<String>, at now: Date = Date()) -> Date? {
        guard routeConfirmed, let candidate, let snapshot, snapshot.connected,
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
