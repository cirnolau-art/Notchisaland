import XCTest
import AppKit
@testable import NotchIsland

final class PolishTests: XCTestCase {
    func testPreludeDoesNotExposeBackgroundDuringRepeatedPlayerUpdates() {
        let view = IslandView(frame: CGRect(origin: .zero, size: IslandWindow.windowSize))
        view.compactMediaVisible = true
        view.mediaInfo = MediaInfo(title: "Prelude", isPlaying: false, duration: 40, elapsed: 2,
                                   lyrics: [.init(time: 10, text: "First line")])
        for _ in 0..<8 { view.render(.idle(.time("")), animated: false) }
        let strip = view.subviews.compactMap { $0 as? CompactLyricsView }.first
        XCTAssertTrue(strip == nil || strip!.isHidden)
        XCTAssertNil(strip?.layer?.animation(forKey: "lyricVisibility"), "Prelude repeatedly starts a visibility animation")
    }

    func testNativeGlassDefaultsToStandardWithoutAnArtificialRim() {
        XCTAssertEqual(IslandBackdropConfiguration(style: .glass, opacity: 0).material, .regular)
        XCTAssertEqual(IslandBackdropConfiguration.defaultRim, 0)
    }
}

final class LyricRenderingPolicyTests: XCTestCase {
    func testWordFadeIsContinuousAndUsesRealSegmentEnd() {
        let line = LyricLine(time: 10, text: "星光", segments: [.init(time: 10, text: "星", endTime: 11), .init(time: 12, text: "光", endTime: 13)])
        let cues = LyricHighlight.cues(for: line, next: 14, style: .appleMusic)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].progress(at: 9), 0)
        XCTAssertEqual(cues[0].progress(at: 10.1), 0.5, accuracy: 0.001)
        XCTAssertEqual(cues[0].progress(at: 11), 1)
        XCTAssertEqual(cues[1].progress(at: 11), 0)
    }
    func testEfficientAndWholeLineLyricsNeverInventWordTiming() {
        let line = LyricLine(time: 3, text: "Stay here")
        XCTAssertEqual(LyricHighlight.cues(for: line, next: 10, style: .appleMusic).count, 1)
        XCTAssertEqual(LyricHighlight.cues(for: line, next: 10, style: .efficient).first?.progress(at: 3), 1)
    }
    func testHDRLimitsAndLegacyAppearanceDecode() throws {
        XCTAssertEqual(LyricHDR.requestedGain(enabled: true, strength: 1, potential: 1), 1)
        XCTAssertGreaterThan(LyricHDR.requestedGain(enabled: true, strength: 0.35, potential: 8), 1,
                             "An EDR-capable screen needs an initial request when current headroom is still 1")
        XCTAssertEqual(LyricHDR.requestedGain(enabled: false, strength: 1, potential: 8), 1)
        XCTAssertEqual(LyricHDR.requestedGain(enabled: true, strength: 1, potential: 1.4), 1.4, accuracy: 0.001)
        XCTAssertLessThanOrEqual(LyricHDR.requestedGain(enabled: true, strength: 1, potential: 8), 2)
        XCTAssertEqual(LyricHDR.requestedGain(enabled: true, strength: 1, potential: 8, usesDisplayPeak: true), 8)
        XCTAssertEqual(LyricHDR.requestedGain(enabled: true, strength: 0.5, potential: 8, usesDisplayPeak: true), 4.5)
        let data = try PropertyListSerialization.data(fromPropertyList: ["width": 142.0, "glow": 0.7], format: .binary, options: 0)
        let old = try PropertyListDecoder().decode(LyricsAppearance.self, from: data)
        XCTAssertEqual(old.width, 142); XCTAssertEqual(old.glow, 0.7)
        XCTAssertFalse(old.hdrEnabled)
        XCTAssertEqual(old.flowStyle, .off)
        var selected = old
        selected.flowStyle = .artwork
        let encoded = try PropertyListEncoder().encode(selected)
        XCTAssertEqual(try PropertyListDecoder().decode(LyricsAppearance.self, from: encoded), selected)
    }
}

final class LyricPixelTests: XCTestCase {
    func testFlowFreezesWhenPausedAndReleasesWhenHidden() throws {
        guard !IslandPreferences.shared.reduceMotion else { throw XCTSkip("Reduce Motion is enabled") }
        for compact in [true, false] {
            let row = LyricTextView(frame: CGRect(x: 0, y: 0, width: 150, height: 30))
            var appearance = LyricsAppearance()
            appearance.flowStyle = .rgb
            let line = LyricLine(time: 1, text: "星光")
            func sample(running: Bool, style: LyricsAnimationStyle = .appleMusic) {
                row.update(line: line, next: 8, elapsed: 2, style: style, appearance: appearance,
                           font: .systemFont(ofSize: 15), active: true, centered: true, running: running,
                           compact: compact)
            }
            sample(running: true)
            XCTAssertTrue(row.debugFlowActive)
            XCTAssertTrue(row.debugFlowAnimating)
            XCTAssertTrue(row.debugGlowActive)
            sample(running: false)
            XCTAssertTrue(row.debugFlowActive)
            XCTAssertFalse(row.debugFlowAnimating)
            sample(running: true, style: .efficient)
            XCTAssertFalse(row.debugFlowActive)
            sample(running: true)
            row.suspend(release: true)
            XCTAssertFalse(row.debugFlowActive)
            XCTAssertFalse(row.debugFlowAnimating)
        }
    }

    func testHDRGlyphPayloadContainsExtendedLinearPixelsAndTransparentBackground() throws {
        let raster = try XCTUnwrap(LyricRaster(line: "星光 ABC", font: .systemFont(ofSize: 16), size: CGSize(width: 180, height: 32), scale: 2, centered: true))
        let image = try XCTUnwrap(raster.image(color: .white, gain: 1.6))
        XCTAssertEqual(image.contentHeadroom, 1.6, accuracy: 0.001)
        XCTAssertEqual(image.bitsPerComponent, 16)
        let data = try XCTUnwrap(image.dataProvider?.data) as Data
        let values = data.withUnsafeBytes { Array($0.bindMemory(to: Float16.self)) }
        XCTAssertGreaterThan(values.max() ?? 0, 1.5, "SDR clipping destroyed the HDR payload")
        XCTAssertEqual(values[0], 0); XCTAssertEqual(values[3], 0, "HDR introduced an opaque rectangle")
        XCTAssertTrue(values.allSatisfy { $0.isFinite })
    }
    func testOrdinaryLyricsUseByteTextures() throws {
        let raster = try XCTUnwrap(LyricRaster(line: "星光 ABC", font: .systemFont(ofSize: 16), size: CGSize(width: 180, height: 32), scale: 2, centered: true))
        let image = try XCTUnwrap(raster.image(color: .white, gain: 1))
        XCTAssertEqual(image.bitsPerComponent, 8)
    }
    func testReducedMotionHighlightsTheStartingWordImmediately() {
        let key = "notchisland.gentleMotion"
        let oldPreference = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.set(true, forKey: key)
        defer { UserDefaults.standard.set(oldPreference, forKey: key) }
        let row = LyricTextView(frame: CGRect(x: 0, y: 0, width: 150, height: 30))
        let line = LyricLine(time: 10, text: "星光", segments: [.init(time: 10, text: "星", endTime: 11), .init(time: 12, text: "光", endTime: 13)])
        row.update(line: line, next: 15, elapsed: 10, style: .appleMusic, appearance: LyricsAppearance(), font: .systemFont(ofSize: 15), active: true, centered: true, running: true)
        XCTAssertEqual(row.debugGlyphAlphas, [1, 0.44])
        XCTAssertFalse(row.debugHasGlyphAnimations)
    }
    func testFontMetricsCenterActualGlyphsAtAllSupportedSizes() throws {
        for size in [11.0, 12, 16] {
            var appearance = LyricsAppearance(); appearance.size = size
            let height = CompactLyricsView.stripHeight(for: appearance)
            let raster = try XCTUnwrap(LyricRaster(line: "测试 Ab9", font: .systemFont(ofSize: size), size: CGSize(width: 180, height: height), scale: 2, centered: true))
            let rows = (0..<raster.height).filter { y in
                (0..<raster.width).contains { x in raster.pixels[(y * raster.width + x) * 4 + 3] > 25 }
            }
            let first = try XCTUnwrap(rows.first), last = try XCTUnwrap(rows.last)
            XCTAssertLessThan(abs(Double(first + last + 1) / 2 - Double(raster.height) / 2), 4.5)
        }
    }
    func testPauseAndHideStopGlyphAnimationsAndReleasePixels() {
        let row = LyricTextView(frame: CGRect(x: 0, y: 0, width: 150, height: 30))
        let line = LyricLine(time: 10, text: "星光", segments: [.init(time: 10, text: "星", endTime: 11), .init(time: 12, text: "光", endTime: 13)])
        row.update(line: line, next: 15, elapsed: 10.1, style: .appleMusic, appearance: LyricsAppearance(), font: .systemFont(ofSize: 15), active: true, centered: true, running: true)
        row.update(line: line, next: 15, elapsed: 10.1, style: .appleMusic, appearance: LyricsAppearance(), font: .systemFont(ofSize: 15), active: true, centered: true, running: false)
        XCTAssertFalse(row.debugHasGlyphAnimations)
        row.suspend(release: true)
        XCTAssertTrue(row.layer?.sublayers?.allSatisfy { $0.contents == nil } ?? false)
    }
}

final class CompactVisibilityRegressionTests: XCTestCase {
    func testAnOldHideCannotRemoveRestoredLyrics() {
        let view = IslandView(frame: CGRect(origin: .zero, size: IslandWindow.windowSize))
        view.compactMediaVisible = true
        view.mediaInfo = MediaInfo(title: "Test", isPlaying: false, duration: 40, elapsed: 12, lyrics: [.init(time: 1, text: "歌词")])
        view.render(.idle(.time("")), animated: false)
        view.render(.inputSource("ABC"))
        view.render(.idle(.time("")))
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        let strip = view.subviews.compactMap { $0 as? CompactLyricsView }.first
        XCTAssertEqual(strip?.isHidden, false)
        XCTAssertEqual(strip?.layer?.opacity, 1)
    }
    func testCollapsingMusicPanelRestoresCompactPlayback() {
        let view = IslandView(frame: CGRect(origin: .zero, size: IslandWindow.windowSize))
        view.compactMediaVisible = true
        view.mediaInfo = MediaInfo(title: "Test", isPlaying: true, duration: 40, elapsed: 12, lyrics: [.init(time: 1, text: "歌词")])
        view.render(.workspace(.music, false), animated: false)
        view.render(.idle(.time("")), animated: false)
        XCTAssertEqual(view.debugVisibleRect.height, view.debugNotchRect.height)
        XCTAssertGreaterThan(view.debugVisibleRect.width, view.debugNotchRect.width)
        let strip = view.subviews.compactMap { $0 as? CompactLyricsView }.first
        XCTAssertEqual(strip?.isHidden, false)
    }
}

final class LyricGapTests: XCTestCase {
    func testExplicitWordEndClearsDuringLongInstrumentalGap() {
        let line = LyricLine(time: 2, text: "星光", segments: [.init(time: 2, text: "星", endTime: 3), .init(time: 3, text: "光", endTime: 4)])
        let info = MediaInfo(isPlaying: false, duration: 30, elapsed: 8, lyrics: [line, .init(time: 20, text: "下一句")])
        XCTAssertNil(info.lyricLine().current)
        XCTAssertEqual(info.lyricLine().next?.time, 20)
    }
    func testSongEndDoesNotLeaveTheLastLyricVisible() {
        let info = MediaInfo(isPlaying: false, duration: 30, elapsed: 30, lyrics: [.init(time: 20, text: "最后一句")])
        XCTAssertNil(info.lyricLine().current)
    }
    func testOrdinaryLRCDoesNotInventInstrumentalBoundaries() {
        let info = MediaInfo(isPlaying: false, duration: 30, elapsed: 8, lyrics: [.init(time: 2, text: "星光"), .init(time: 20, text: "下一句")])
        XCTAssertEqual(info.lyricLine().current?.text, "星光")
    }
}
