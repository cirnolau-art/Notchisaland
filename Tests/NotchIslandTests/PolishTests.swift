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

    func testCharacterCuesSplitAWordIntoLeftToRightGlyphTiming() {
        let line = LyricLine(time: 10, text: "星光", segments: [.init(time: 10, text: "星光", endTime: 12)])
        let cues = LyricHighlight.cues(for: line, next: 14, style: .appleMusic)

        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].range, NSRange(location: 0, length: 1))
        XCTAssertEqual(cues[1].range, NSRange(location: 1, length: 1))
        XCTAssertLessThan(cues[0].start, cues[1].start)
    }

    func testHighlightedGlyphsUseFeatherAndLiftAnimations() {
        let row = LyricTextView(frame: CGRect(x: 0, y: 0, width: 180, height: 32))
        let line = LyricLine(time: 1, text: "星光", segments: [
            .init(time: 1, text: "星光", endTime: 3)
        ])
        row.update(line: line, next: 4, elapsed: 1.05, style: .appleMusic,
                   appearance: LyricsAppearance(), font: .systemFont(ofSize: 18),
                   active: true, centered: true, running: true)

        XCTAssertTrue(row.debugHasFeatherMasks)
        XCTAssertTrue(row.debugHasGlyphLiftAnimations)
    }
    func testEfficientAndWholeLineLyricsNeverInventWordTiming() {
        let line = LyricLine(time: 3, text: "Stay here")
        XCTAssertEqual(LyricHighlight.cues(for: line, next: 10, style: .appleMusic).count, 1)
        XCTAssertEqual(LyricHighlight.cues(for: line, next: 10, style: .efficient).first?.progress(at: 3), 1)
    }
    func testUntimedOrUnreliableLyricsSwitchToASingleStaticLine() throws {
        let timed = try XCTUnwrap(LyricsParser.parse("[00:01]<00:01>星<00:02>光<00:03>").first)
        let plain = try XCTUnwrap(LyricsParser.parse("[00:04]只有整句").first)
        let invalid = LyricLine(time: 4, text: "星光夜", segments: [
            .init(time: 4, text: "星", endTime: 5), .init(time: 5, text: "夜", endTime: 6)
        ])
        var appearance = LyricsAppearance()
        appearance.flowStyle = .rgb
        appearance.hdrEnabled = true
        for compact in [false, true] {
            let row = LyricTextView(frame: CGRect(x: 0, y: 0, width: 180, height: 32))
            func show(_ line: LyricLine, elapsed: TimeInterval) {
                row.update(line: line, next: 8, elapsed: elapsed, style: .appleMusic,
                           appearance: appearance, font: .systemFont(ofSize: 18),
                           active: true, centered: true, running: true, compact: compact)
            }
            show(timed, elapsed: 1)
            XCTAssertTrue(row.debugHasFeatherMasks)
            for line in [plain, invalid] {
                show(line, elapsed: line.time)
                XCTAssertFalse(row.debugHasGlyphAnimations)
                XCTAssertFalse(row.debugHasFeatherMasks)
                XCTAssertFalse(row.debugHasGlyphLiftAnimations)
                XCTAssertTrue(row.debugFlowActive)
                XCTAssertTrue(row.debugFlowAnimating)
                XCTAssertEqual(row.hdrGain, 1)
                XCTAssertEqual(row.debugGlyphAlphas, Array(repeating: 1, count: line.text.utf16.count))
            }
        }
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
    func testUntimedLyricsKeepRGBFlowWithoutWordEffects() {
        let row = LyricTextView(frame: CGRect(x: 0, y: 0, width: 180, height: 32))
        var appearance = LyricsAppearance()
        appearance.flowStyle = .rgb
        let line = LyricLine(time: 1, text: "整句歌词")

        row.update(line: line, next: 8, elapsed: 2, style: .appleMusic,
                   appearance: appearance, font: .systemFont(ofSize: 16),
                   active: true, centered: true, running: true)

        XCTAssertTrue(row.debugFlowActive)
        XCTAssertTrue(row.debugFlowAnimating)
        XCTAssertFalse(row.debugHasFeatherMasks)
        XCTAssertFalse(row.debugHasGlyphLiftAnimations)
    }

    func testFlowFreezesWhenPausedAndReleasesWhenHidden() throws {
        guard !IslandPreferences.shared.reduceMotion else { throw XCTSkip("Reduce Motion is enabled") }
        for compact in [true, false] {
            let row = LyricTextView(frame: CGRect(x: 0, y: 0, width: 150, height: 30))
            var appearance = LyricsAppearance()
            appearance.flowStyle = .rgb
            let line = LyricLine(time: 1, text: "星光", segments: [
                .init(time: 1, text: "星", endTime: 1.5), .init(time: 1.5, text: "光", endTime: 2)
            ])
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
        XCTAssertEqual(row.debugGlyphAlphas.first ?? 0, 1, accuracy: 0.001)
        XCTAssertEqual(row.debugGlyphAlphas.last ?? 0, 0.44, accuracy: 0.001)
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
