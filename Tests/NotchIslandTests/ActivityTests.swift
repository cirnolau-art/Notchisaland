import XCTest
@testable import NotchIsland

final class ActivityTests: XCTestCase {
    let start = Date(timeIntervalSince1970: 1_000_000)
    func testTimerUsesDeadlineAcrossSleep() {
        let timer = TimerSession(seconds: 1500, now: start)
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(900)), 600)
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(2000)), 0)
    }
    func testPauseResumeDoesNotConsumePausedTime() {
        var timer = TimerSession(seconds: 300, now: start)
        timer.pause(at: start.addingTimeInterval(100))
        XCTAssertTrue(timer.isPaused)
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(900)), 200)
        timer.resume(at: start.addingTimeInterval(1000))
        XCTAssertEqual(timer.remaining(at: start.addingTimeInterval(1050)), 150)
    }
    func testRepeatedPauseResumeIsIdempotent() {
        var timer = TimerSession(seconds: 100, now: start)
        timer.pause(at: start.addingTimeInterval(10)); timer.pause(at: start.addingTimeInterval(50))
        XCTAssertEqual(timer.remaining(at: start), 90)
        timer.resume(at: start.addingTimeInterval(100)); timer.resume(at: start.addingTimeInterval(150))
        XCTAssertEqual(timer.deadline, start.addingTimeInterval(190))
    }
    func testAddingTimeWorksRunningAndPaused() {
        var timer = TimerSession(seconds: 300, now: start)
        timer.add(seconds: 60)
        XCTAssertEqual(timer.remaining(at: start), 360)
        timer.pause(at: start.addingTimeInterval(30)); timer.add(seconds: 60)
        XCTAssertEqual(timer.remaining(at: start), 390)
        XCTAssertEqual(timer.duration, 420)
    }
    func testTimerPersistencePreservesPausedState() throws {
        var timer = TimerSession(seconds: 1500, label: "专注时间", now: start)
        timer.pause(at: start.addingTimeInterval(120))
        let restored = try JSONDecoder().decode(TimerSession.self, from: JSONEncoder().encode(timer))
        XCTAssertEqual(timer, restored)
        XCTAssertEqual(restored.remaining(at: start.addingTimeInterval(10000)), 1380)
    }
    func testTransientRestoresSelectedPanel() {
        var policy = PresentationPolicy(); policy.open(.files)
        XCTAssertTrue(policy.showTransient()); XCTAssertEqual(policy.surface, .panel(.files))
        policy.expireTransient()
        XCTAssertFalse(policy.transientVisible); XCTAssertEqual(policy.surface, .panel(.files))
    }
    func testAlarmCannotBeCoveredOrDismissedByNormalEvents() {
        var policy = PresentationPolicy(); policy.open(.music); policy.ring()
        XCTAssertFalse(policy.showTransient())
        policy.open(.timer); policy.close()
        XCTAssertEqual(policy.surface, .alert)
        policy.stopAlert(); XCTAssertEqual(policy.surface, .idle)
    }
    func testOpeningPanelClearsPendingHUD() {
        var policy = PresentationPolicy(); XCTAssertTrue(policy.showTransient())
        policy.open(.timer); XCTAssertFalse(policy.transientVisible)
        XCTAssertEqual(policy.surface, .panel(.timer))
    }
    func testTabSwitchingWrapsBothWays() {
        XCTAssertEqual(IslandTab.music.moved(by: -1), .clipboard)
        XCTAssertEqual(IslandTab.clipboard.moved(by: 1), .music)
        XCTAssertEqual(IslandTab.timer.moved(by: 1), .audio)
    }
    func testPlayingSpotifyWinsOverPausedMusic() {
        let music = MediaInfo(title: "Paused", isPlaying: false, source: "Music")
        let spotify = MediaInfo(title: "Playing", isPlaying: true, source: "Spotify")
        XCTAssertEqual(MediaSourcePolicy.select([music, spotify], lastActive: "Music")?.source, "Spotify")
    }
    func testMostRecentlyActivePlayerWinsAndUnavailablePlayerFallsBack() {
        let music = MediaInfo(title: "Music", isPlaying: true, source: "Music")
        let spotify = MediaInfo(title: "Spotify", isPlaying: true, source: "Spotify")
        XCTAssertEqual(MediaSourcePolicy.select([music, spotify], lastActive: "Spotify")?.source, "Spotify")
        XCTAssertEqual(MediaSourcePolicy.select([music, spotify], lastActive: "Music")?.source, "Music")
        XCTAssertEqual(MediaSourcePolicy.select([spotify], lastActive: "Music")?.source, "Spotify")
        XCTAssertNil(MediaSourcePolicy.select([], lastActive: ""))
    }
    func testPausedMusicDoesNotWidenNotchOnLaunch() {
        var activity = CompactMediaActivity()
        activity.update(hasMedia: true, playing: false, at: start)
        XCTAssertFalse(activity.isVisible(at: start))
    }
    func testPausedWaveformHasGraceThenRetractsWithoutResetOnPoll() {
        var activity = CompactMediaActivity()
        activity.update(hasMedia: true, playing: true, at: start)
        activity.update(hasMedia: true, playing: false, at: start.addingTimeInterval(1))
        activity.update(hasMedia: true, playing: false, at: start.addingTimeInterval(2))
        XCTAssertTrue(activity.isVisible(at: start.addingTimeInterval(3.4)))
        XCTAssertFalse(activity.isVisible(at: start.addingTimeInterval(3.5)))
        XCTAssertEqual(activity.pausedAt, start.addingTimeInterval(1))
    }
    func testResumeAndMissingMediaClearPauseCountdown() {
        var activity = CompactMediaActivity()
        activity.update(hasMedia: true, playing: true, at: start)
        activity.update(hasMedia: true, playing: false, at: start.addingTimeInterval(1))
        activity.update(hasMedia: true, playing: true, at: start.addingTimeInterval(2))
        XCTAssertNil(activity.pausedAt)
        XCTAssertTrue(activity.isVisible(at: start.addingTimeInterval(100)))
        activity.update(hasMedia: false, playing: false, at: start.addingTimeInterval(3))
        XCTAssertFalse(activity.isVisible(at: start.addingTimeInterval(3)))
        XCTAssertNil(activity.pausedAt)
    }
    func testCapturedMediaKeyReleasesAreConsumedAsAPair() {
        var presses = MediaKeyPresses()
        XCTAssertTrue(presses.down(0, supported: true))
        XCTAssertTrue(presses.down(0, supported: true))
        XCTAssertTrue(presses.up(0))
        XCTAssertFalse(presses.up(0))
        XCTAssertFalse(presses.down(2, supported: false))
        XCTAssertFalse(presses.up(2))
    }
    func testDeviceChangeDuringPressStillConsumesItsRelease() {
        var presses = MediaKeyPresses()
        XCTAssertTrue(presses.down(1, supported: true))
        XCTAssertTrue(presses.down(1, supported: false))
        XCTAssertTrue(presses.up(1))
        XCTAssertFalse(presses.down(1, supported: false))
    }
    func testMediaProgressInterpolationClampsAtDuration() {
        var info = MediaInfo(title: "Test", isPlaying: true, duration: 200, elapsed: 195)
        info.sampledAt = start
        XCTAssertEqual(info.interpolated(at: start.addingTimeInterval(10)).elapsed, 200)
        info.isPlaying = false
        XCTAssertEqual(info.interpolated(at: start.addingTimeInterval(10)).elapsed, 195)
    }
    func testFileShelfDeduplicatesAndNeverDeletesOriginals() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let name = "NotchIsland.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let url = root.appendingPathComponent("file.txt"); try Data("hello".utf8).write(to: url)
        let shelf = FileShelf(defaults: defaults)
        XCTAssertEqual(shelf.add([url, url]), 1)
        let restored = FileShelf(defaults: defaults)
        XCTAssertEqual(restored.items.count, 1)
        XCTAssertEqual(restored.items.first?.url.resolvingSymlinksInPath(), url.resolvingSymlinksInPath())
        shelf.clear()
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(shelf.items.isEmpty)
    }
    func testShelfCapMissingFilesAndInvalidURLs() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let name = "NotchIsland.tests.\(UUID().uuidString)"; let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let shelf = FileShelf(defaults: defaults)
        let urls = try (0..<35).map { index -> URL in let url = root.appendingPathComponent("\(index).txt"); try Data().write(to: url); return url }
        XCTAssertEqual(shelf.add(urls), 30)
        XCTAssertEqual(shelf.add([URL(string: "https://example.com")!, root.appendingPathComponent("missing")]), 0)
        let removed = shelf.items[0].url; try FileManager.default.removeItem(at: removed)
        XCTAssertEqual(shelf.readableItems.count, 29)
        shelf.removeMissing(); XCTAssertEqual(shelf.items.count, 29)
        XCTAssertTrue(FileManager.default.fileExists(atPath: urls[0].path))
    }
}
