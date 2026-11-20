import XCTest
@testable import NotchIsland

final class LyricsTests: XCTestCase {
    func testLRCParserSortsMultipleTimestampsAndMilliseconds() {
        let lines = LyricsParser.parse("[00:12.50]第二句\n[00:01.00][00:02.00]第一句")
        XCTAssertEqual(lines.map(\.text), ["第一句", "第一句", "第二句"])
        XCTAssertEqual(lines[0].time, 1, accuracy: 0.001)
        XCTAssertEqual(lines[2].time, 12.5, accuracy: 0.001)
    }
    func testMediaInfoChoosesCurrentAndNextLineFromInterpolatedElapsed() {
        var info = MediaInfo(title: "Test", isPlaying: false, duration: 30, elapsed: 3)
        info.lyrics = [LyricLine(time: 0, text: "一"), LyricLine(time: 5, text: "二"), LyricLine(time: 10, text: "三")]
        XCTAssertEqual(info.lyricLine().current?.text, "一")
        XCTAssertEqual(info.lyricLine().next?.text, "二")
        info.elapsed = 6
        XCTAssertEqual(info.lyricLine().current?.text, "二")
    }
    func testConnectionEventIsEligibleAfterStableConfirmation() {
        var policy = AirPodsPresentationPolicy()
        let now = Date(timeIntervalSince1970: 100)
        policy.observeOutput(nil, at: now)
        policy.connectionEvent("AA:BB:CC:DD:EE:FF", at: now.addingTimeInterval(1))
        let snapshot = AirPodsSnapshot(name: "AirPods Pro", address: "aa:bb:cc:dd:ee:ff", connected: true, left: 80)
        XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: ["aa:bb:cc:dd:ee:ff"], at: now.addingTimeInterval(2)))
        XCTAssertTrue(policy.takePresentation(for: snapshot, confirmedConnections: ["aa:bb:cc:dd:ee:ff"], at: now.addingTimeInterval(3.1)))
    }
}
