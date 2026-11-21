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
    func testCachedBatteryWinsOverAnOldPairWithoutBattery() {
        let oldPair = AirPodsSnapshot(name: "Old AirPods", address: "AA:BB", connected: false)
        let currentPair = AirPodsSnapshot(name: "Current AirPods Pro", address: "CC:DD", connected: false, left: 79, right: 80, caseBattery: 91)
        XCTAssertEqual(AirPodsProfileParser.select([oldPair, currentPair], previousAddress: "aa-bb")?.address, "CC:DD")
    }
    func testBasicProfileRetainsHardwareAddressAlongsideCachedBattery() throws {
        let profile: [String: Any] = ["SPBluetoothDataType": [["device_not_connected": [["AirPods Pro": [
            "device_address": "AA:BB:CC:DD:EE:FF", "device_productID": "0x2027",
            "device_batteryLevelLeft": "79%", "device_batteryLevelRight": "80%", "device_batteryLevelCase": "91%"
        ]]]]]]
        let snapshot = try XCTUnwrap(AirPodsProfileParser.parse(JSONSerialization.data(withJSONObject: profile)).first)
        XCTAssertEqual(snapshot.address, "AA:BB:CC:DD:EE:FF")
        XCTAssertEqual(snapshot.left, 79); XCTAssertEqual(snapshot.right, 80); XCTAssertEqual(snapshot.caseBattery, 91)
        XCTAssertFalse(snapshot.connected)
        let selected = AirPodsProfileParser.applyingConnections([snapshot], connectedAddresses: ["aa-bb-cc-dd-ee-ff"], disconnectedAddress: nil)
        XCTAssertTrue(try XCTUnwrap(selected.first).connected)
    }
    func testBatteryCacheSurvivesHardwareAddressFormattingChanges() {
        let previous = AirPodsSnapshot(name: "AirPods Pro", address: "AA-BB-CC-DD-EE-FF", connected: false, left: 79, right: 80, caseBattery: 91)
        let current = AirPodsSnapshot(name: "AirPods Pro", address: "aa:bb:cc:dd:ee:ff", connected: true, left: 78)
        let result = current.preservingKnownBattery(from: previous)
        XCTAssertEqual(result.left, 78); XCTAssertEqual(result.right, 80); XCTAssertEqual(result.caseBattery, 91)
        XCTAssertEqual(result.cachedFields, ["right", "case"])
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
        XCTAssertEqual(preferences.glassMaterial, .regular)
        preferences.glassMaterial = .clear; preferences.glassOpacity = 0.65
        preferences.backgroundStyle = .glass; preferences.backgroundStyle = .black
        XCTAssertEqual(preferences.glassMaterial, .clear); XCTAssertEqual(preferences.glassOpacity, 0.65)
        preferences.glassOpacity = 0.1
        XCTAssertEqual(preferences.glassMaterial, .clear)
        let restored = IslandPreferences(defaults: defaults)
        XCTAssertEqual(restored.glassOpacity, 0.1)
        XCTAssertEqual(restored.glassMaterial, .clear)
        preferences.glassOpacity = -1
        XCTAssertEqual(preferences.glassOpacity, 0)
    }
    func testNaturalScrollingUsesEventDirectionUnlessOverridden() {
        for eventIsInverted in [false, true] {
            XCTAssertEqual(IslandPreferences.scrollDirectionMultiplier(naturalScrolling: nil, eventIsInverted: eventIsInverted), 1)
            XCTAssertEqual(IslandPreferences.scrollDirectionMultiplier(naturalScrolling: eventIsInverted, eventIsInverted: eventIsInverted), 1)
            XCTAssertEqual(IslandPreferences.scrollDirectionMultiplier(naturalScrolling: !eventIsInverted, eventIsInverted: eventIsInverted), -1)
        }
    }

    func testNaturalScrollingPreservesLegacyInversionAndCanRestoreSystemDirection() throws {
        let name = "NotchIsland.scroll.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }

        let preferences = IslandPreferences(defaults: defaults)
        XCTAssertNil(preferences.naturalScrolling)
        defaults.set(false, forKey: "notchisland.invertScrollV2")
        XCTAssertNil(preferences.naturalScrolling)
        defaults.set(true, forKey: "notchisland.invertScrollV2")
        XCTAssertEqual(preferences.naturalScrolling, false)

        preferences.naturalScrolling = true
        XCTAssertEqual(IslandPreferences(defaults: defaults).naturalScrolling, true)
        preferences.naturalScrolling = nil
        XCTAssertNil(IslandPreferences(defaults: defaults).naturalScrolling)
    }
}
