import XCTest
@testable import NotchIsland

final class LyricsTests: XCTestCase {
    func testLRCParserSortsMultipleTimestampsAndMilliseconds() {
        let lines = LyricsParser.parse("[00:12.50]第二句\n[00:01.00][00:02.00]第一句")
        XCTAssertEqual(lines.map(\.text), ["第一句", "第一句", "第二句"])
        XCTAssertEqual(lines[0].time, 1, accuracy: 0.001)
        XCTAssertEqual(lines[2].time, 12.5, accuracy: 0.001)
    }
    func testEnhancedLRCUsesProvidedWordBoundariesPreservingSpaces() throws {
        let lines = LyricsParser.parse("[00:10.20][00:20.20] <00:10.20>Stay <00:10.81>here <00:11.15>")
        let line = try XCTUnwrap(lines.first)
        XCTAssertEqual(line.text, "Stay here")
        XCTAssertEqual(line.segments.map(\.text), ["Stay ", "here"])
        XCTAssertEqual(line.segments[1].time, 10.81, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(line.segments[1].endTime), 11.15, accuracy: 0.001)
        XCTAssertEqual(lines[1].segments[1].time, 20.81, accuracy: 0.001)
    }
    func testMalformedOrSingleTimestampKeepsAWholeLine() {
        let lines = LyricsParser.parse("[00:10]<00:11>一<00:09>二\n[00:20]<00:20>整句<00:22>")
        XCTAssertEqual(lines.map(\.text), ["一二", "整句"])
        XCTAssertTrue(lines.allSatisfy { $0.segments.isEmpty })
    }
    func testYRCUsesMillisecondStartsAndDurationsAndIgnoresMetadata() throws {
        let lines = LyricsParser.parseYRC("""
        {"t":0,"c":[{"tx":"作词"}]}
        [14000,2100](14000,900,0)看(15020,1080,0)海
        [17000,1000](18100,100,0)不(18150,900,0)对
        """)
        XCTAssertEqual(lines.map(\.text), ["看海", "不对"])
        XCTAssertEqual(lines[0].segments.map(\.text), ["看", "海"])
        XCTAssertEqual(lines[0].segments[1].time, 15.02, accuracy: 0.001)
        XCTAssertEqual(try XCTUnwrap(lines[0].segments[0].endTime), 14.9, accuracy: 0.001)
        XCTAssertTrue(lines[1].segments.isEmpty)
    }
    func testMediaInfoChoosesCurrentAndNextLineFromInterpolatedElapsed() {
        var info = MediaInfo(title: "Test", isPlaying: false, duration: 30, elapsed: 3)
        info.lyrics = [LyricLine(time: 0, text: "一"), LyricLine(time: 5, text: "二"), LyricLine(time: 10, text: "三")]
        XCTAssertEqual(info.lyricLine().current?.text, "一")
        XCTAssertEqual(info.lyricLine().next?.text, "二")
        info.elapsed = 6
        XCTAssertEqual(info.lyricLine().current?.text, "二")
    }
    func testLongLineWrapsToDisplayWidthAndKeepsWordTiming() throws {
        var wrapper = LyricsWrapping()
        let line = LyricLine(time: 10, text: "这是一个很长的歌词句子需要在刘海宽度内自动换行",
                             segments: [
                                LyricSegment(time: 10, text: "这是一个很长的"),
                                LyricSegment(time: 11, text: "歌词句子需要在"),
                                LyricSegment(time: 12, text: "刘海宽度内自动换行")
                             ])
        let lines = wrapper.lines(for: [line, LyricLine(time: 20, text: "下一句")],
                                 width: 92, font: .systemFont(ofSize: 16), duration: 30)
        XCTAssertGreaterThan(lines.count, 2)
        XCTAssertEqual(lines.map(\.text).joined(), line.text + "下一句")
        XCTAssertEqual(lines.first?.segments.first?.time, 10)
        XCTAssertTrue(lines.dropFirst().dropLast().allSatisfy { $0.time >= 10 && $0.time < 20 })
    }
    func testIdleBluetoothConnectionCannotSubstituteForAnActiveAudioOutput() {
        var policy = AirPodsPresentationPolicy()
        let now = Date(timeIntervalSince1970: 100)
        policy.observeOutput(nil, at: now)
        let snapshot = AirPodsSnapshot(name: "AirPods Pro", address: "aa:bb:cc:dd:ee:ff", connected: true, left: 80)
        XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: ["aa:bb:cc:dd:ee:ff"], at: now.addingTimeInterval(2)))
        XCTAssertFalse(policy.takePresentation(for: snapshot, confirmedConnections: ["aa:bb:cc:dd:ee:ff"], at: now.addingTimeInterval(3.1)))
    }
}
