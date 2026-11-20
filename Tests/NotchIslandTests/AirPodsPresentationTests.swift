import XCTest
@testable import NotchIsland

final class AirPodsPresentationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1000)
    private let address = "aa:bb:cc:dd:ee:ff"
    private var connected: Set<String> { [address] }
    private var snapshot: AirPodsSnapshot { .init(name: "AirPods Pro", address: address, connected: true, left: 75, right: 74, caseBattery: 81) }
    func testStartupAlreadySelectedAndRepeatedBatteryReadsNeverPresent() {
        var policy = AirPodsPresentationPolicy(); policy.observeOutput(address, at: start)
        for second in stride(from: 1, through: 600, by: 60) {
            let now = start.addingTimeInterval(Double(second))
            policy.observeOutput(address, at: now)
            XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: now))
        }
    }
    func testStableNewAudioRoutePresentsOnceAndBatteryChangesStaySilent() {
        var policy = AirPodsPresentationPolicy(); policy.observeOutput(nil, at: start)
        policy.observeOutput(address, at: start.addingTimeInterval(1))
        XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(2)))
        XCTAssertTrue(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(3)))
        var changed = snapshot; changed.left = 70
        XCTAssertFalse(policy.takePresentation(for: changed, confirmedConnections: connected, at: start.addingTimeInterval(64)))
    }
    func testReportRecoveryConnectionWithoutRouteAndUnrelatedDevicesNeverPresent() {
        var policy = AirPodsPresentationPolicy(); policy.observeOutput(nil, at: start)
        var disconnected = snapshot; disconnected.connected = false
        XCTAssertFalse(policy.takePresentation(for: disconnected, confirmedConnections: [], at: start.addingTimeInterval(1)))
        XCTAssertFalse(policy.takePresentation(for: nil, confirmedConnections: connected, at: start.addingTimeInterval(2)))
        XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(3)))
        policy.observeOutput("11:22:33:44:55:66", at: start.addingTimeInterval(4))
        XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(6)))
    }
    func testActualBluetoothConnectionIsRequiredAndAddressFormatsAreEquivalent() {
        var policy = AirPodsPresentationPolicy(); policy.observeOutput(nil, at: start)
        policy.observeOutput("AA-BB-CC-DD-EE-FF", at: start.addingTimeInterval(1))
        XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: [], at: start.addingTimeInterval(3)))
        var alternate = snapshot; alternate.address = "AA-BB-CC-DD-EE-FF"
        XCTAssertTrue(policy.takePresentation(for: alternate, confirmedConnections: ["AA-BB-CC-DD-EE-FF"], at: start.addingTimeInterval(4)))
        policy.observeOutput(address, at: start.addingTimeInterval(5))
        XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(7)))
    }
    func testInitialRouteNegotiationSettlesOnceAndBriefReconnectDoesNotRepeat() {
        var policy = AirPodsPresentationPolicy(); policy.observeOutput(nil, at: start)
        policy.observeOutput(address, at: start.addingTimeInterval(1))
        policy.observeOutput(nil, at: start.addingTimeInterval(2))
        policy.observeOutput(address, at: start.addingTimeInterval(3))
        XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(4)))
        XCTAssertTrue(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(5)))
        XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(6)))
        policy.disconnected(address, at: start.addingTimeInterval(200))
        policy.observeOutput(nil, at: start.addingTimeInterval(200))
        policy.observeOutput(address, at: start.addingTimeInterval(202))
        XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(205)))
    }
    func testWakeAndStartupRecoveryQuietlyAbsorbDelayedAutomaticRouteRestore() {
        var policy = AirPodsPresentationPolicy(); policy.resetBaseline(at: start)
        policy.observeOutput(nil, at: start.addingTimeInterval(1))
        policy.observeOutput(address, at: start.addingTimeInterval(4))
        XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(7)))
        policy.observeOutput(address, at: start.addingTimeInterval(20))
        XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(22)))
        policy.observeOutput(nil, at: start.addingTimeInterval(40))
        policy.observeOutput(address, at: start.addingTimeInterval(80))
        XCTAssertTrue(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(82)))
    }
    func testFailedRouteReadNeverCreatesAnApparentNewConnection() {
        var policy = AirPodsPresentationPolicy(); policy.observeOutput(address, at: start)
        policy.outputUnavailable(); policy.observeOutput(address, at: start.addingTimeInterval(60))
        XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(62)))
        policy.observeOutput(nil, at: start.addingTimeInterval(63))
        policy.observeOutput(address, at: start.addingTimeInterval(95)); policy.outputUnavailable()
        XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(97)))
    }
    func testDisconnectAndOutputDepartureCancelPendingCard() {
        var policy = AirPodsPresentationPolicy(); policy.observeOutput(nil, at: start)
        policy.observeOutput(address, at: start.addingTimeInterval(1)); policy.disconnected(address, at: start.addingTimeInterval(2))
        XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(3)))
        policy.observeOutput(nil, at: start.addingTimeInterval(4))
        policy.observeOutput(address, at: start.addingTimeInterval(40)); policy.observeOutput(nil, at: start.addingTimeInterval(41))
        XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(43)))
    }
    func testWakeReenableAndExpiredCandidatesDoNotReplayOldEvents() {
        var policy = AirPodsPresentationPolicy(); policy.observeOutput(nil, at: start)
        policy.observeOutput(address, at: start.addingTimeInterval(1)); policy.resetBaseline(at: start.addingTimeInterval(2))
        policy.observeOutput(address, at: start.addingTimeInterval(20))
        XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(23)))
        policy.observeOutput(nil, at: start.addingTimeInterval(30))
        policy.observeOutput(address, at: start.addingTimeInterval(61))
        XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(82)))
    }
    func testTemporaryRouteReadFailureRequiresReconfirmationWithoutLosingANewActivation() {
        var policy = AirPodsPresentationPolicy(); policy.observeOutput(nil, at: start)
        policy.observeOutput(address, at: start.addingTimeInterval(1))
        policy.outputUnavailable()
        XCTAssertEqual(policy.pendingAddress(at: start.addingTimeInterval(3)), address)
        XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(3)))
        policy.observeOutput(address, at: start.addingTimeInterval(4))
        XCTAssertTrue(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(4)))
    }
    func testDelayedBatteryAndBusyUIKeepEventEligibleUntilAccepted() {
        var policy = AirPodsPresentationPolicy(); policy.observeOutput(nil, at: start)
        policy.observeOutput(address, at: start.addingTimeInterval(1))
        XCTAssertNil(policy.deadline(for: nil, confirmedConnections: connected, at: start.addingTimeInterval(4)))
        XCTAssertEqual(policy.pendingAddress(at: start.addingTimeInterval(14)), address)
        let ready = start.addingTimeInterval(14)
        XCTAssertNotNil(policy.deadline(for: snapshot, confirmedConnections: connected, at: ready))
        // Checking readiness is not delivery. A HUD can finish without starting cooldown.
        XCTAssertNotNil(policy.deadline(for: snapshot, confirmedConnections: connected, at: ready.addingTimeInterval(2)))
        XCTAssertTrue(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: ready.addingTimeInterval(2)))
        XCTAssertNil(policy.pendingAddress(at: ready.addingTimeInterval(3)))
    }
    func testStartupStableRouteBrieflyRestoringRemainsSilent() {
        var policy = AirPodsPresentationPolicy(); policy.observeOutput(address, at: start)
        policy.observeOutput(nil, at: start.addingTimeInterval(60))
        policy.observeOutput(address, at: start.addingTimeInterval(61))
        XCTAssertNil(policy.pendingAddress(at: start.addingTimeInterval(63)))
        XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(63)))
    }
    func testGenuineLaterUseCanPresentAgainAfterCooldown() {
        var policy = AirPodsPresentationPolicy(); policy.observeOutput(nil, at: start)
        policy.observeOutput(address, at: start.addingTimeInterval(1))
        XCTAssertTrue(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(3)))
        policy.observeOutput(nil, at: start.addingTimeInterval(4))
        policy.observeOutput(address, at: start.addingTimeInterval(40))
        XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(42)))
        policy.observeOutput(nil, at: start.addingTimeInterval(50))
        policy.observeOutput(address, at: start.addingTimeInterval(180))
        XCTAssertTrue(policy.takePresentation(for: snapshot, confirmedConnections: connected, at: start.addingTimeInterval(182)))
    }
    func testCoreAudioUIDAddressParsingFailsQuietlyForUnverifiableDevices() {
        XCTAssertEqual(AirPodsAudioRoute.address(fromDeviceUID: "AA-BB-CC-DD-EE-FF:output"), address)
        XCTAssertEqual(AirPodsAudioRoute.address(fromDeviceUID: "Bluetooth:aa:bb:cc:dd:ee:ff:input"), address)
        XCTAssertNil(AirPodsAudioRoute.address(fromDeviceUID: "BuiltInSpeakerDevice"))
        XCTAssertNil(AirPodsAudioRoute.address(fromDeviceUID: "AirPods Pro"))
        XCTAssertNil(AirPodsAudioRoute.address(fromDeviceUID: "AA:BB:CC"))
    }
}
