import XCTest
@testable import NotchIsland

private final class AirPodsMonitorFixture {
    let address = "aa:bb:cc:dd:ee:ff"
    private let lock = NSLock()
    private var selected: String?
    private var batteryAvailable = true
    private var reads = 0
    func selectAirPods() { lock.lock(); selected = address; lock.unlock() }
    func setBatteryAvailable(_ value: Bool) { lock.lock(); batteryAvailable = value; lock.unlock() }
    func output() -> (address: String?, available: Bool) {
        lock.lock(); defer { lock.unlock() }; return (selected, true)
    }
    func battery() -> [AirPodsSnapshot] {
        lock.lock(); defer { lock.unlock() }; reads += 1
        guard batteryAvailable else { return [] }
        return [.init(name: "AirPods Pro", address: address, connected: selected != nil, left: 80, right: 78, caseBattery: 90)]
    }
    var batteryReads: Int { lock.lock(); defer { lock.unlock() }; return reads }
    func monitor() -> AirPodsMonitor {
        AirPodsMonitor(outputReader: output, batteryReader: battery, observesSystem: false,
                       recoveryQuietPeriod: 0, outputFallbackInterval: 0.1)
    }
}

final class AirPodsMonitorTests: XCTestCase {
    @MainActor
    func testFallbackFindsMissedRouteEventAndBusyUIIsRetriedUntilAccepted() async throws {
        let fixture = AirPodsMonitorFixture(), loaded = expectation(description: "baseline battery"), shown = expectation(description: "card accepted")
        let monitor = fixture.monitor()
        var hasLoaded = false, attempts = 0, presentations = 0
        monitor.onChange = { _, automatic in
            XCTAssertFalse(automatic)
            if !hasLoaded { hasLoaded = true; loaded.fulfill() }
        }
        monitor.onPresentation = { snapshot in
            attempts += 1
            XCTAssertEqual(snapshot.address, fixture.address)
            guard attempts > 1 else { return false } // An existing HUD has not finished yet.
            presentations += 1; shown.fulfill(); return true
        }
        monitor.setEnabled(true); defer { monitor.setEnabled(false) }
        await fulfillment(of: [loaded], timeout: 1)
        fixture.selectAirPods() // Deliberately omit audioOutputDidChange().
        await fulfillment(of: [shown], timeout: 4)
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(attempts, 2); XCTAssertEqual(presentations, 1)
        XCTAssertLessThanOrEqual(fixture.batteryReads, 3, "Unchanged route checks must not poll system_profiler")
    }

    @MainActor
    func testAlreadySelectedStartupAndRepeatedSilentReadsNeverPresent() async throws {
        let fixture = AirPodsMonitorFixture(); fixture.selectAirPods()
        let monitor = fixture.monitor()
        var presentations = 0
        monitor.onPresentation = { _ in presentations += 1; return true }
        monitor.setEnabled(true); defer { monitor.setEnabled(false) }
        try await Task.sleep(for: .milliseconds(2500))
        XCTAssertEqual(presentations, 0)
        XCTAssertLessThanOrEqual(fixture.batteryReads, 2)
        XCTAssertEqual(monitor.snapshot?.left, 80)
    }

    @MainActor
    func testDelayedBatteryReportCanCompleteTheCurrentActivation() async throws {
        let fixture = AirPodsMonitorFixture(); fixture.setBatteryAvailable(false)
        let monitor = fixture.monitor(), loaded = expectation(description: "empty baseline"), shown = expectation(description: "delayed battery displayed")
        var baselineLoaded = false
        monitor.onChange = { _, _ in if !baselineLoaded { baselineLoaded = true; loaded.fulfill() } }
        monitor.onPresentation = { snapshot in
            XCTAssertEqual(snapshot.left, 80); XCTAssertEqual(snapshot.right, 78); XCTAssertEqual(snapshot.caseBattery, 90)
            shown.fulfill(); return true
        }
        monitor.setEnabled(true); defer { monitor.setEnabled(false) }
        await fulfillment(of: [loaded], timeout: 1)
        fixture.selectAirPods()
        try await Task.sleep(for: .milliseconds(700))
        fixture.setBatteryAvailable(true)
        await fulfillment(of: [shown], timeout: 4)
        XCTAssertGreaterThanOrEqual(fixture.batteryReads, 3)
        XCTAssertLessThanOrEqual(fixture.batteryReads, 5)
    }

    @MainActor
    func testDisablingWhileSettlingCancelsTheCardAndFallback() async throws {
        let fixture = AirPodsMonitorFixture(), monitor = fixture.monitor()
        var presentations = 0
        monitor.onPresentation = { _ in presentations += 1; return true }
        monitor.setEnabled(true)
        try await Task.sleep(for: .milliseconds(250))
        fixture.selectAirPods()
        try await Task.sleep(for: .milliseconds(300))
        monitor.setEnabled(false)
        let reads = fixture.batteryReads
        try await Task.sleep(for: .milliseconds(2200))
        XCTAssertEqual(presentations, 0); XCTAssertEqual(fixture.batteryReads, reads)
    }
}
