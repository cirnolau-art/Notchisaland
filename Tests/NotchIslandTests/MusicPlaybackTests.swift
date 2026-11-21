import XCTest
@testable import NotchIsland

final class MusicPlaybackTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testPlaybackNotificationShowsTrackWithoutAQueryResult() throws {
        var playback = MusicPlaybackState()
        let event = try XCTUnwrap(MusicPlaybackEvent(
            userInfo: ["Name": "Song", "Artist": "Artist", "Player State": "Playing", "Total Time": 210_000]
        ))
        playback.apply(event, from: "Music", at: start)

        let song = try XCTUnwrap(playback.selected)
        XCTAssertEqual(song.title, "Song")
        XCTAssertEqual(song.artist, "Artist")
        XCTAssertEqual(song.duration, 210)
        XCTAssertTrue(song.isPlaying)

        var compact = CompactMediaActivity()
        compact.update(hasMedia: !song.title.isEmpty, playing: song.isPlaying, at: start)
        XCTAssertTrue(compact.isVisible(at: start))
    }

    func testLateQueryCannotUndoPauseAndEnrichmentKeepsTrackIdentity() throws {
        var playback = MusicPlaybackState()
        let playing = try XCTUnwrap(MusicPlaybackEvent(userInfo: ["Name": "Song", "Player State": "Playing"]))
        playback.apply(playing, from: "Music", at: start)
        let trackID = try XCTUnwrap(playback.selected?.trackID)
        let revision = playback.revision

        let paused = try XCTUnwrap(MusicPlaybackEvent(userInfo: ["Player State": "Paused"]))
        playback.apply(paused, from: "Music", at: start.addingTimeInterval(3))
        let reading = MediaInfo(title: "Song", artist: "Artist", isPlaying: true, album: "Album",
                                duration: 220, elapsed: 2, source: "Music", trackID: "new")
        playback.applyReading(reading, from: "Music", startedAt: revision)
        XCTAssertEqual(playback.selected?.isPlaying, false)
        XCTAssertEqual(playback.selected?.elapsed, 3)

        var updated = reading
        updated.isPlaying = false
        playback.applyReading(updated, from: "Music", startedAt: playback.revision)
        XCTAssertEqual(playback.selected?.artist, "Artist")
        XCTAssertEqual(playback.selected?.trackID, trackID)
    }

    func testSpotifyUnitsAndStopWithoutMetadata() throws {
        var playback = MusicPlaybackState()
        let event = try XCTUnwrap(MusicPlaybackEvent(
            userInfo: ["Name": "Song", "Player State": "Playing", "Duration": 198_000, "Playback Position": 23.5]
        ))
        playback.apply(event, from: "Spotify", at: start)
        XCTAssertEqual(playback.selected?.duration, 198)
        XCTAssertEqual(playback.selected?.elapsed, 23.5)
        let revision = playback.revision

        let stopped = try XCTUnwrap(MusicPlaybackEvent(userInfo: ["Player State": "Stopped"]))
        playback.apply(stopped, from: "Spotify", at: start.addingTimeInterval(1))
        playback.applyReading(MediaInfo(title: "Song", isPlaying: true, source: "Spotify"),
                              from: "Spotify", startedAt: revision)
        XCTAssertNil(playback.selected)
    }
}
