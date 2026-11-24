import AppKit
import XCTest
@testable import NotchIsland

final class IslandAnimationTests: XCTestCase {
    func testLyricsArrivingDuringPlaybackPreserveTheExpandedControlsAndFrame() throws {
        let view = IslandView(frame: CGRect(origin: .zero, size: IslandWindow.windowSize))
        view.enabledTabsOverride = [.music]
        let preferences = IslandPreferences.shared
        let oldPlacement = preferences.expandedLyricsPlacement
        preferences.expandedLyricsPlacement = .below
        defer { preferences.expandedLyricsPlacement = oldPlacement }

        let track = MediaInfo(title: "Track", isPlaying: true, duration: 60, elapsed: 8)
        view.render(.music(track), animated: false)
        let slider = try XCTUnwrap(descendants(view).compactMap { $0 as? InteractionSlider }.first)
        let frame = view.debugVisibleRect

        view.mediaInfo?.lyrics = [.init(time: 2, text: "First line")]
        view.render(.workspace(.music, false))

        XCTAssertEqual(view.debugVisibleRect, frame)
        XCTAssertTrue(slider === descendants(view).compactMap { $0 as? InteractionSlider }.first)
        XCTAssertTrue(descendants(view).compactMap { $0 as? LyricTextView }.contains { $0.stringValue == "First line" })
    }

    func testProgressRefreshRetainsAlbumArtAndPlaybackButtonImages() throws {
        let view = IslandView(frame: CGRect(origin: .zero, size: IslandWindow.windowSize))
        view.enabledTabsOverride = [.music]
        let context = try XCTUnwrap(CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 16,
                                             space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let art = try XCTUnwrap(context.makeImage())
        let info = MediaInfo(title: "Track", artwork: art, isPlaying: true, duration: 60, elapsed: 8)
        view.render(.music(info), animated: false)
        let album = try XCTUnwrap(descendants(view).compactMap { $0 as? NSImageView }.first { $0.frame.width == 60 })
        let image = try XCTUnwrap(album.image)
        let playback = try XCTUnwrap(descendants(view).compactMap { $0 as? ActionButton }.first { $0.toolTip == "播放或暂停" })
        let symbol = try XCTUnwrap(playback.image)

        view.mediaInfo?.elapsed = 9
        view.refreshContent()

        XCTAssertTrue(album.image === image)
        XCTAssertTrue(playback.image === symbol)
    }

    func testSameGeometryRefreshPreservesTheShapeAnimation() {
        let view = IslandView(frame: CGRect(origin: .zero, size: IslandWindow.windowSize))
        view.enabledTabsOverride = [.music]
        guard !IslandPreferences.shared.reduceMotion else { return }
        view.render(.workspace(.music, false))
        let shape = view.layer?.sublayers?.first { $0.animation(forKey: "morph") != nil }
        XCTAssertNotNil(shape)

        view.render(.workspace(.music, false), animated: false)

        XCTAssertNotNil(shape?.animation(forKey: "morph"))
    }

    func testCollapsingKeepsPanelControlsAndLyricsAnchored() throws {
        guard !IslandPreferences.shared.reduceMotion else { throw XCTSkip("Reduce Motion is enabled") }
        let view = IslandView(frame: CGRect(origin: .zero, size: IslandWindow.windowSize))
        view.enabledTabsOverride = [.music]
        let preferences = IslandPreferences.shared
        let oldPlacement = preferences.expandedLyricsPlacement
        preferences.expandedLyricsPlacement = .below
        defer { preferences.expandedLyricsPlacement = oldPlacement }
        let track = MediaInfo(title: "Track", duration: 60, elapsed: 8,
                              lyrics: [.init(time: 2, text: "First line")])

        view.render(.music(track), animated: false)
        let slider = try XCTUnwrap(descendants(view).compactMap { $0 as? InteractionSlider }.first)
        let body = try XCTUnwrap(slider.superview)
        let lyrics = try XCTUnwrap(view.subviews.compactMap { $0 as? LyricRollView }.first)
        let bodyFrame = body.frame
        let lyricsFrame = lyrics.frame

        view.render(.idle(.time("")))

        XCTAssertEqual(body.frame, bodyFrame)
        XCTAssertEqual(lyrics.frame, lyricsFrame)
        XCTAssertNil(body.layer?.animation(forKey: "contentMove"))
        XCTAssertNil(lyrics.layer?.animation(forKey: "panelTravel"))

        view.render(.music(track))

        XCTAssertTrue(slider.superview === body)
        XCTAssertTrue(lyrics.superview === view)
    }

    func testPlaybackSampleDoesNotCancelScrollForTheSameLyric() {
        let roll = LyricRollView(frame: CGRect(x: 0, y: 0, width: 200, height: 80), placement: .below)
        let appearance = LyricsAppearance()
        let first = LyricLine(time: 2, text: "First line")
        let second = LyricLine(time: 7, text: "Second line")
        roll.update(current: first, next: second, elapsed: 6, style: .appleMusic, appearance: appearance, animated: false)
        roll.update(current: second, next: nil, elapsed: 7, style: .appleMusic, appearance: appearance, animated: true)
        XCTAssertTrue(roll.hasScrollAnimation)

        roll.update(current: second, next: nil, elapsed: 7.1, style: .appleMusic, appearance: appearance, animated: false)

        XCTAssertTrue(roll.hasScrollAnimation)
    }

    func testLyricRowsRotateWithoutReplacingVisibleTextInPlace() {
        let roll = LyricRollView(frame: CGRect(x: 0, y: 0, width: 240, height: 96), placement: .below)
        let appearance = LyricsAppearance()
        let first = LyricLine(time: 2, text: "First line")
        let second = LyricLine(time: 7, text: "Second line")
        let third = LyricLine(time: 12, text: "Third line")

        roll.update(current: first, next: second, elapsed: 2, style: .appleMusic, appearance: appearance, animated: false)
        roll.update(current: second, next: third, elapsed: 7, style: .appleMusic, appearance: appearance, animated: true)

        let rows = roll.subviews.compactMap { $0 as? LyricTextView }
        XCTAssertEqual(Set(rows.map(\.stringValue).filter { !$0.isEmpty }), Set([first.text, second.text, third.text]))
        XCTAssertTrue(rows.contains { $0.stringValue == second.text && $0.debugRollBlurRadius == 0 })
        XCTAssertTrue(rows.contains { $0.stringValue == third.text && ($0.layer?.opacity ?? 0) < 1 })
        XCTAssertTrue(rows.contains { $0.stringValue == first.text && ($0.layer?.opacity ?? 0) < 1 })
        XCTAssertTrue(roll.hasScrollAnimation)

        roll.update(current: first, next: second, elapsed: 2.1, style: .appleMusic, appearance: appearance, animated: true)
        let reverseRows = roll.subviews.compactMap { $0 as? LyricTextView }
        XCTAssertTrue(reverseRows.contains { $0.stringValue == first.text && $0.debugRollBlurRadius == 0 })
        XCTAssertTrue(reverseRows.contains { $0.stringValue == second.text && ($0.layer?.opacity ?? 0) < 1 })
    }

    func testInitialExpandedRowsKeepTheUpcomingLineVisible() throws {
        let roll = LyricRollView(frame: CGRect(x: 0, y: 0, width: 240, height: 96), placement: .below)
        let appearance = LyricsAppearance()
        let first = LyricLine(time: 2, text: "First line")
        let second = LyricLine(time: 7, text: "Second line")

        roll.update(current: first, next: second, elapsed: 2, style: .appleMusic, appearance: appearance, animated: false)

        let upcoming = try XCTUnwrap(roll.subviews.compactMap { $0 as? LyricTextView }.first { $0.stringValue == second.text })
        XCTAssertFalse(upcoming.isHidden)
        XCTAssertGreaterThan(upcoming.layer?.opacity ?? 0, 0)
        XCTAssertEqual(upcoming.debugRollBlurRadius, 0)
    }

    func testLineTransitionLeavesTheNewCurrentLineVisible() throws {
        let roll = LyricRollView(frame: CGRect(x: 0, y: 0, width: 240, height: 96), placement: .below)
        let appearance = LyricsAppearance()
        let first = LyricLine(time: 2, text: "First line")
        let second = LyricLine(time: 7, text: "Second line")
        let third = LyricLine(time: 12, text: "Third line")

        roll.update(current: first, next: second, elapsed: 2, style: .appleMusic, appearance: appearance, animated: false)
        roll.update(current: second, next: third, elapsed: 7, style: .appleMusic, appearance: appearance, animated: true)

        let current = try XCTUnwrap(roll.subviews.compactMap { $0 as? LyricTextView }.first { $0.stringValue == second.text })
        XCTAssertFalse(current.isHidden)
        XCTAssertEqual(current.layer?.opacity ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(current.debugRollBlurRadius, 0, accuracy: 0.001)
    }

    func testExpandedRowsShowPreviousCurrentNextAndFarNext() throws {
        let roll = LyricRollView(frame: CGRect(x: 0, y: 0, width: 240, height: 130), placement: .below)
        let appearance = LyricsAppearance()
        let first = LyricLine(time: 2, text: "Previous")
        let second = LyricLine(time: 7, text: "Current")
        let third = LyricLine(time: 12, text: "Next")
        let fourth = LyricLine(time: 17, text: "Far next")

        roll.update(previous: first, current: second, next: third, nextNext: fourth,
                   elapsed: 7, style: .appleMusic, appearance: appearance, animated: false)

        let rows = roll.subviews.compactMap { $0 as? LyricTextView }
        XCTAssertEqual(Set(rows.map(\.stringValue)), Set([first.text, second.text, third.text, fourth.text]))
        XCTAssertTrue(rows.contains { $0.stringValue == second.text && $0.debugRollBlurRadius == 0 })
        for line in [first, third, fourth] {
            let row = try XCTUnwrap(rows.first { $0.stringValue == line.text })
            XCTAssertFalse(row.isHidden)
            XCTAssertEqual(row.debugRollBlurRadius, 0)
            let rowAlpha = CGFloat(row.layer?.opacity ?? 0)
            XCTAssertGreaterThanOrEqual((row.debugGlyphAlphas.first ?? 0) * rowAlpha, 0.60)
            XCTAssertLessThan(rowAlpha, 1)
        }
        XCTAssertTrue(rows.allSatisfy { $0.frame.minY >= 0 && $0.frame.maxY <= roll.bounds.height })
    }

    func testCompactLyricTransitionAnimatesVerticalScroll() throws {
        let roll = LyricRollView(frame: CGRect(x: 0, y: 0, width: 240, height: 32), placement: .compact)
        let appearance = LyricsAppearance()
        let first = LyricLine(time: 2, text: "First line")
        let second = LyricLine(time: 7, text: "Second line")
        let third = LyricLine(time: 12, text: "Third line")

        roll.update(current: first, next: second, elapsed: 2, style: .appleMusic, appearance: appearance, animated: false)
        roll.update(current: second, next: third, elapsed: 7, style: .appleMusic, appearance: appearance, animated: true)

        let rows = roll.subviews.compactMap { $0 as? LyricTextView }
        XCTAssertTrue(rows.contains { $0.stringValue == second.text && !$0.isHidden })
        XCTAssertTrue(rows.contains { $0.stringValue == first.text && $0.layer?.animation(forKey: "lyricScroll") != nil })
        XCTAssertTrue(roll.hasScrollAnimation)
    }

    func testExpandedPlayerFitsAllFourLyricRowsAtMaximumFontSize() throws {
        let preferences = IslandPreferences.shared
        let oldPlacement = preferences.expandedLyricsPlacement
        let oldAppearance = preferences.lyricsAppearance
        defer {
            preferences.expandedLyricsPlacement = oldPlacement
            preferences.lyricsAppearance = oldAppearance
        }
        var appearance = oldAppearance
        appearance.size = LyricsAppearance.fontSizeRange.upperBound
        preferences.lyricsAppearance = appearance
        let lines = (0..<4).map { LyricLine(time: Double($0 * 5), text: "Line \($0)") }
        for placement in [LyricsPlacement.below, .side] {
            preferences.expandedLyricsPlacement = placement
            let island = IslandView(frame: CGRect(origin: .zero, size: IslandWindow.windowSize))
            island.enabledTabsOverride = [.music]
            island.applyAppearance()
            island.render(.music(MediaInfo(title: "Test", duration: 30, elapsed: 6, lyrics: lines)), animated: false)
            island.layoutSubtreeIfNeeded()
            let roll = try XCTUnwrap(descendants(island).compactMap { $0 as? LyricRollView }.first { !$0.isCompact })
            let rows = roll.subviews.compactMap { $0 as? LyricTextView }.filter { !$0.isHidden }
            XCTAssertEqual(rows.count, 4)
            XCTAssertTrue(rows.allSatisfy { roll.bounds.contains($0.frame) && $0.debugRollBlurRadius == 0 })
            XCTAssertTrue(island.bounds.contains(roll.frame))
            XCTAssertTrue(island.bounds.contains(island.debugVisibleRect))
        }
    }

    private func descendants(_ view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants($0) }
    }
}
