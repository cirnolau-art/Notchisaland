import XCTest
@testable import NotchIsland

final class ConnectedActivityTests: XCTestCase {
    func testDisconnectEventOverridesStaleProfilerConnectionAndAddressFormatsMatch() {
        let stale = AirPodsSnapshot(name: "AirPods Pro", address: "AA:BB", connected: true, left: 75)
        let disconnected = AirPodsProfileParser.applyingConnections([stale], connectedAddresses: ["aa-bb"], disconnectedAddress: "aa-bb")
        XCTAssertFalse(disconnected[0].connected)
        var cached = stale; cached.connected = false
        XCTAssertTrue(AirPodsProfileParser.applyingConnections([cached], connectedAddresses: ["aa-bb"], disconnectedAddress: nil)[0].connected)
    }
    func testBatteryPercentIncludesZeroAndRejectsUnknown() {
        XCTAssertEqual(AirPodsProfileParser.percent("0%"), 0)
        XCTAssertEqual(AirPodsProfileParser.percent(" 81% "), 81)
        XCTAssertEqual(AirPodsProfileParser.percent(75), 75)
        for invalid in ["—", "Unknown", "101%", "-1%", ""] { XCTAssertNil(AirPodsProfileParser.percent(invalid)) }
    }
    func testBluetoothProfileKeepsConnectionAndThreeBatteryValues() throws {
        let profile: [String: Any] = ["SPBluetoothDataType": [["device_connected": [["Renamed earbuds": ["device_address": "AA:BB", "device_batteryLevelLeft": "75%", "device_batteryLevelRight": "74%", "device_batteryLevelCase": "81%"]]], "device_not_connected": [["AirPods Pro": ["device_address": "CC:DD", "device_batteryLevelLeft": "0%"]], ["Keyboard": ["device_address": "EE:FF"]]]]]]
        let values = AirPodsProfileParser.parse(try JSONSerialization.data(withJSONObject: profile))
        XCTAssertEqual(values.count, 2)
        let connected = try XCTUnwrap(values.first(where: \.connected))
        XCTAssertEqual(connected.left, 75); XCTAssertEqual(connected.right, 74); XCTAssertEqual(connected.caseBattery, 81)
        XCTAssertEqual(AirPodsProfileParser.select(values, previousAddress: "CC:DD")?.address, "AA:BB")
        XCTAssertEqual(values.first(where: { !$0.connected })?.left, 0)
        XCTAssertNil(values.first(where: { !$0.connected })?.caseBattery)
    }
    func testCachedBatteryDoesNotMakeDisconnectedHeadphonesLookConnected() {
        let cached = AirPodsSnapshot(name: "AirPods Pro", address: "A", connected: false, left: 75, right: 75, caseBattery: 81)
        XCTAssertEqual(AirPodsProfileParser.select([cached], previousAddress: nil), cached)
        XCTAssertFalse(cached.connected)
    }
    func testMissingCaseReportPreservesLastKnownValueForSameDeviceOnly() {
        let cached = AirPodsSnapshot(name: "AirPods Pro", address: "A", connected: false, left: 75, right: 75, caseBattery: 81)
        let new = AirPodsSnapshot(name: "AirPods Pro", address: "A", connected: true, left: 72)
        let merged = new.preservingKnownBattery(from: cached)
        XCTAssertEqual(merged.left, 72); XCTAssertEqual(merged.right, 75); XCTAssertEqual(merged.caseBattery, 81)
        XCTAssertTrue(merged.connected)
        XCTAssertEqual(merged.cachedFields, ["right", "case"])
        var other = new; other.address = "B"
        XCTAssertNil(other.preservingKnownBattery(from: cached).caseBattery)
    }
    func testMalformedBluetoothReportFailsWithoutInventingBattery() {
        XCTAssertTrue(AirPodsProfileParser.parse(Data("bad json".utf8)).isEmpty)
        XCTAssertNil(AirPodsProfileParser.select([], previousAddress: nil))
    }
    func testBannerTextExcludesButtonsAndRelativeTime() throws {
        let content = try XCTUnwrap(BannerTextParser.parse(["日历", "刚刚", "设计评审", "10 分钟后开始", "关闭", "选项", "10 分钟后开始"]))
        XCTAssertEqual(content.source, "日历"); XCTAssertEqual(content.title, "设计评审"); XCTAssertEqual(content.body, "10 分钟后开始")
        XCTAssertNil(BannerTextParser.parse(["关闭", "Notification Center", "刚刚"]))
        XCTAssertNil(BannerTextParser.parse(["只有一个字段"]))
    }
    func testNotificationDeduplicationExpiresAndDistinctNoticesRemainIndependent() {
        var filter = NotificationDeduplicator()
        let now = Date(timeIntervalSince1970: 100)
        XCTAssertTrue(filter.accept("one", at: now))
        XCTAssertFalse(filter.accept("one", at: now.addingTimeInterval(1)))
        XCTAssertTrue(filter.accept("two", at: now.addingTimeInterval(1)))
        XCTAssertTrue(filter.accept("one", at: now.addingTimeInterval(31)))
    }
    func testGlassSettingsStayIndependentOfBlackModeAndEachOther() throws {
        let name = "NotchIsland.appearance.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let preferences = IslandPreferences(defaults: defaults)
        XCTAssertEqual(preferences.backgroundStyle, .black)
        preferences.glassBlur = 0.25; preferences.glassOpacity = 0.65
        preferences.backgroundStyle = .glass; preferences.backgroundStyle = .black
        XCTAssertEqual(preferences.glassBlur, 0.25); XCTAssertEqual(preferences.glassOpacity, 0.65)
        preferences.glassOpacity = 0.1
        XCTAssertEqual(preferences.glassBlur, 0.25)
        let restored = IslandPreferences(defaults: defaults)
        XCTAssertEqual(restored.glassOpacity, 0.1)
        preferences.glassBlur = 3; preferences.glassOpacity = -1
        XCTAssertEqual(preferences.glassBlur, 1); XCTAssertEqual(preferences.glassOpacity, 0)
    }
}
