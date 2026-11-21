import AppKit
import QuartzCore
import CoreAudio

/// Isolated visual/interaction QA: no system listeners, player automation or real shelf data.
enum SnapshotMode {
    static var enabled: Bool { CommandLine.arguments.contains("--snapshot") }
    private static let defaultsSuite = "NotchIsland.snapshot.\(UUID().uuidString)"
    static let defaults = UserDefaults(suiteName: defaultsSuite)!
    static var outputDir: String {
        if let i = CommandLine.arguments.firstIndex(of: "--snapshot-output"), CommandLine.arguments.indices.contains(i + 1) { return CommandLine.arguments[i + 1] }
        return "/tmp/notchisland-v13-snapshots"
    }
    private static var failures = [String]()
    static func schedule() {
        try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
        let controller = IslandController.shared
        guard let view = controller.debugView else { exit(1) }
        view.enabledTabsOverride = IslandTab.allCases
        if CommandLine.arguments.contains("--polish-preview") { PolishPreview.run(controller); return }
        let board = NSPasteboard(name: .init("NotchIsland.snapshot.\(UUID())"))
        let clipboard = ClipboardHistory(board: board, frontApp: { "snapshot.demo" })
        clipboard.setEnabled(true, schedule: false); view.clipboard = clipboard
        clipboard.onChange = { [weak view] in view?.refreshClipboard() }
        let artwork = makeArtwork()
        var music = MediaInfo(title: "夜空中最亮的星", artist: "逃跑计划 · 世界", artwork: artwork, isPlaying: true, duration: 254, elapsed: 86, source: "Music", trackID: "sample")
        let timedLine = "你慢慢地走来".enumerated().map {
            LyricSegment(time: 84 + Double($0.offset) * 1.3, text: String($0.element))
        }
        music.lyrics = [LyricLine(time: 0, text: "穿过旷野的风"), LyricLine(time: 84, text: "你慢慢地走来", segments: timedLine),
                        LyricLine(time: 180, text: "把星光放在手心")]
        IslandPreferences.shared.lyricsPlacement = .below
        IslandPreferences.shared.lyricsAnimation = .appleMusic
        view.mediaInfo = music
        view.compactMediaVisible = true
        let notes = URL(fileURLWithPath: outputDir).appendingPathComponent("旅行灵感.txt")
        try? Data("Take a moment.\n".utf8).write(to: notes)
        let session = TimerSession(seconds: 1499, label: "专注时间")
        let states: [(String, IslandState)] = [
            ("01-compact", .idle(.music(music.title, artwork, nil, true))),
            ("02-preview", .workspace(.music, true)),
            ("03-music", .music(music)),
            ("48-player-side-lyrics", .music(music)),
            ("49-compact-side-lyrics", .idle(.music(music.title, artwork, nil, true))),
            ("54-custom-side-lyrics", .idle(.music(music.title, artwork, nil, true))),
            ("53-lyrics-efficient", .music(music)),
            ("55-attached-notification", .notification(.demo)),
            ("50-system-focus", .workspace(.focus, false)),
            ("51-compact-focus", .idle(.time(""))),
            ("52-system-focus-off", .workspace(.focus, false)),
            ("04-files-empty", .workspace(.files, false)),
            ("05-files", .workspace(.files, false)),
            ("06-timer-setup", .workspace(.timer, false)),
            ("07-timer-running", .workspace(.timer, false)),
            ("08-timer-paused", .workspace(.timer, false)),
            ("09-volume", .volume(0.62, false)),
            ("10-brightness", .brightness(0.8)),
            ("11-input", .inputSource("简体拼音")),
            ("12-power", .charging(true, 86)),
            ("13-alert", .timerDone("专注时间结束")),
            ("14-empty-music", .music(MediaInfo())),
            ("16-paused-music", .music({ var paused = music; paused.isPlaying = false; return paused }())),
            ("17-paused-compact", .idle(.music(music.title, artwork, nil, false))),
            ("18-retracted", .idle(.time(""))),
            ("19-airpods-connected", .airPods(.demo)),
            ("20-airpods-cached", .airPods(AirPodsSnapshot(name: "AirPods Pro", address: "cached", connected: false, left: 75, right: 75, caseBattery: 81))),
            ("21-airpods-unknown", .airPods(AirPodsSnapshot(name: "AirPods Pro", address: "unknown", connected: true))),
            ("22-notification", .notification(.demo)),
            ("23-notification-private", .notification(.demo)),
            ("24-glass-music", .music(music)),
            ("25-glass-airpods", .airPods(.demo)),
            ("26-glass-notification", .notification(.demo)),
            ("27-glass-retracted", .idle(.time(""))),
            ("31-audio", .workspace(.audio, false)),
            ("32-audio-fixed", .workspace(.audio, false)),
            ("33-calendar", .workspace(.calendar, false)),
            ("34-calendar-permission", .workspace(.calendar, false)),
            ("35-shortcuts", .workspace(.shortcuts, false)),
            ("36-glass-audio", .workspace(.audio, false)),
            ("37-glass-calendar", .workspace(.calendar, false)),
            ("38-glass-shortcuts", .workspace(.shortcuts, false)),
            ("41-clipboard-empty", .workspace(.clipboard, false)),
            ("42-clipboard", .workspace(.clipboard, false)),
            ("43-glass-clipboard", .workspace(.clipboard, false)),
            ("44-module-single", .workspace(.files, false)),
            ("45-modules-off", .workspace(.files, false)),
        ]
        var index = 0
        func step() {
            guard index < states.count else {
                runInteractionChecks(view) {
                    runPolishChecks(view)
                    runPlaybackCheck(controller, view: view)
                    runCollapseCheck(view)
                    clipboard.setEnabled(false); board.releaseGlobally()
                    saveSettings()
                    defaults.removePersistentDomain(forName: defaultsSuite)
                    let report = failures.isEmpty ? "PASS: visual states and interaction checks\n" : failures.joined(separator: "\n")
                    try? report.write(toFile: "\(outputDir)/verification.txt", atomically: true, encoding: .utf8)
                    print(report)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { exit(failures.isEmpty ? 0 : 1) }
                }
                return
            }
            let (name, state) = states[index]; index += 1
            view.updateFocus(["50-system-focus", "51-compact-focus"].contains(name)
                             ? .active(.resolve(identifier: "com.apple.focus.reduce-interruptions")) : .inactive)
            IslandPreferences.shared.expandedLyricsPlacement = name == "48-player-side-lyrics" ? .side : .below
            let customLyrics = name == "54-custom-side-lyrics"
            IslandPreferences.shared.lyricsPlacement = (name == "49-compact-side-lyrics" || customLyrics) ? .side : .below
            IslandPreferences.shared.lyricsAnimation = name == "53-lyrics-efficient" ? .efficient : .appleMusic
            IslandPreferences.shared.notificationPlacement = name == "55-attached-notification" ? .sides : .island
            IslandPreferences.shared.notificationPreview = !name.contains("private")
            IslandPreferences.shared.notificationWidth = name == "55-attached-notification" ? 470 : NotchNotificationLayout.defaultWidth
            IslandPreferences.shared.notificationDepth = name == "55-attached-notification" ? 82 : NotchNotificationLayout.defaultDepth
            var lyricsAppearance = LyricsAppearance()
            if customLyrics {
                lyricsAppearance.width = 258
                lyricsAppearance.opacity = 0.64
                lyricsAppearance.size = 15
                lyricsAppearance.weight = .bold
                lyricsAppearance.colorRGB = 0x92DFDF
                lyricsAppearance.glow = 0.85
            }
            IslandPreferences.shared.lyricsAppearance = lyricsAppearance
            view.applyAppearance()
            if name == "42-clipboard" {
                for text in ["https://developer.apple.com", "把常用的内容，放在顺手的位置。", "周末计划\n散步、咖啡，然后好好休息。"] {
                    board.clearContents(); board.setString(text, forType: .string); clipboard.capture()
                }
                if let artwork, let image = NSImage(cgImage: artwork, size: NSSize(width: 200, height: 200)).tiffRepresentation {
                    board.clearContents(); board.setData(image, forType: .tiff); clipboard.capture()
                }
            }
            if name == "44-module-single" { view.enabledTabsOverride = [.files] }
            if name == "45-modules-off" { view.enabledTabsOverride = [] }
            if name == "05-files" { _ = controller.fileShelf.add([notes]); view.refreshFiles() }
            if name == "07-timer-running" { view.timerSession = session; view.refreshTimer() }
            if name == "08-timer-paused" { var paused = session; paused.pause(); view.timerSession = paused; view.refreshTimer() }
            if name == "09-volume" { view.timerSession = nil }
            var info = music
            info.sampledAt = Date()
            if name.hasPrefix("16-") || name.hasPrefix("17-") || name.hasPrefix("18-") { info.isPlaying = false }
            view.mediaInfo = info
            view.compactMediaVisible = !name.contains("retracted")
            view.backdropOverride = .init(style: name.contains("glass") ? .glass : .black, opacity: IslandBackdropConfiguration.defaultDarkening)
            view.notificationPreviewOverride = name.contains("private") ? false : nil
            view.audioOutputs = [AudioOutput(id: 1, name: "MacBook Pro 扬声器", transport: kAudioDeviceTransportTypeBuiltIn, canAdjustVolume: true), AudioOutput(id: 2, name: "AirPods Pro", transport: kAudioDeviceTransportTypeBluetooth, canAdjustVolume: true), AudioOutput(id: 3, name: "Studio Display · HDMI", transport: kAudioDeviceTransportTypeHDMI, canAdjustVolume: false)]
            view.selectedOutput = name.contains("fixed") ? 3 : 2; view.outputVolume = name.contains("fixed") ? nil : 0.62; view.outputVolumeAvailable = !name.contains("fixed")
            view.nextMeeting = name.contains("permission") ? nil : .demo
            view.calendarEnabled = !name.contains("permission"); view.calendarAuthorized = !name.contains("permission")
            view.calendarStatus = name.contains("permission") ? "开启后，只读取你的日历" : "已连接系统日历"
            view.quickActions = [IslandQuickAction(title: "下载", kind: .folder, target: "/tmp"), IslandQuickAction(title: "文稿", kind: .folder, target: "/tmp"), IslandQuickAction(title: "系统设置", kind: .application, target: "/System/Applications/System Settings.app"), IslandQuickAction(title: "开始工作", kind: .shortcut, target: "demo"), IslandQuickAction(title: "备忘录", kind: .application, target: "/System/Applications/Notes.app"), IslandQuickAction(title: "今日计划", kind: .shortcut, target: "demo")]
            if case .music(let sample) = state, !sample.title.isEmpty { view.render(.music(info)) }
            else { view.render(state) }
            view.applyAppearance()
            view.refreshConnectedPanels()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.75) { save(view: view, name: name); step() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: step)
    }
    private static func runCollapseCheck(_ view: IslandView) {
        guard IslandPreferences.supportsGlass, !IslandPreferences.shared.reduceMotion,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency else { return }
        view.backdropOverride = .init(style: .glass, opacity: IslandBackdropConfiguration.defaultDarkening)
        view.compactMediaVisible = true
        IslandPreferences.shared.expandedLyricsPlacement = .below
        view.mediaInfo = MediaInfo(title: "过渡检查", isPlaying: true, duration: 60, elapsed: 3,
                                   lyrics: [.init(time: 2, text: "过渡中的歌词")])
        view.render(.workspace(.music, false), animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.07))
        let expanded = view.debugVisibleRect
        let settledPanel = view.debugPresentedPanel
        if settledPanel.body?.opacity != 1 || settledPanel.lyrics?.opacity != 1 {
            failures.append("Music controls and lyrics are not visible before collapse")
        }
        func sample(_ label: String) -> (rect: CGRect, alpha: CGFloat) {
            let outline = view.debugPresentedBackground
            let panel = view.debugPresentedPanel
            if let glass = view.debugPresentedGlass {
                print("[\(label)] outline=\(outline.rect), glass=\(glass.frame) alpha=\(glass.opacity), body=\(String(describing: panel.body)), lyrics=\(String(describing: panel.lyrics))")
                // The WindowServer can present the last AppKit layout for a refresh
                // while the outline is already interpolating its next frame.
                if abs(glass.frame.minY - outline.rect.minY) > 36 ||
                    abs(glass.frame.width - outline.rect.width) > 24 ||
                    abs(glass.frame.maxY - outline.rect.maxY) > 0.5 {
                    failures.append("\(label): native glass and outline are visibly out of sync")
                }
            } else {
                failures.append("\(label): no native glass during the transition")
            }
            if let body = panel.body, let original = settledPanel.body,
               abs(body.frame.maxY - original.frame.maxY) > 1 {
                failures.append("\(label): music controls moved vertically away from their anchor")
            }
            if outline.rect.height > compact.height + 36, (panel.body?.opacity ?? 0) == 0 {
                failures.append("\(label): music controls vanished before the outline closed")
            }
            if let lyrics = panel.lyrics, let original = settledPanel.lyrics,
               abs(lyrics.frame.maxY - original.frame.maxY) > 1 {
                failures.append("\(label): expanded lyrics moved vertically away from their anchor")
            }
            return outline
        }
        view.render(.idle(.time("")))
        let compact = view.debugVisibleRect
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        let first = sample("Collapse first")
        RunLoop.main.run(until: Date().addingTimeInterval(0.07))
        let second = sample("Collapse second")
        if !(expanded.height > first.rect.height && first.rect.height > second.rect.height &&
             second.rect.height > compact.height && first.alpha > 0 && second.alpha > first.alpha &&
             abs(first.rect.maxY - compact.maxY) < 0.5 && abs(second.rect.maxY - compact.maxY) < 0.5) {
            failures.append("Collapse does not interpolate size and black fill continuously")
        }
        print("[Collapse] height \(expanded.height) → \(first.rect.height) → \(second.rect.height) → \(compact.height), alpha \(first.alpha) → \(second.alpha)")
        view.render(.workspace(.music, false))
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        let reopened = sample("Reopen")
        if !(reopened.rect.height > second.rect.height && reopened.alpha < second.alpha) {
            failures.append("Reopening does not reverse the in-flight collapse")
        }
        view.compactMediaVisible = false
        view.render(.idle(.time("")), animated: false)
        if view.debugGlassActive || view.debugBackgroundAlpha != 1 {
            failures.append("Settled compact state is not solid black")
        }
        view.backdropOverride = nil
    }
    private static func runPlaybackCheck(_ controller: IslandController, view: IslandView) {
        IslandPreferences.shared.lyricsPlacement = .hidden
        IslandPreferences.shared.expandedLyricsPlacement = .hidden
        guard let event = MusicPlaybackEvent(userInfo: ["Name": "Playback fixture", "Player State": "Playing", "Total Time": 210_000]) else {
            failures.append("Music playback metadata could not be decoded")
            return
        }
        var playback = MusicPlaybackState()
        playback.apply(event, from: "Music")
        controller.debugAcceptPlaybackSample(playback.selected)
        if view.mediaInfo?.title != "Playback fixture" || view.debugVisibleRect.width <= view.debugNotchRect.width {
            failures.append("Playback event does not show compact music via the controller")
        }
        controller.debugAcceptPlaybackSample(nil)
        if view.compactMediaVisible {
            failures.append("Stopped track leaves compact media visible")
        }
    }
    private static func save(view: NSView, name: String) {
        view.layoutSubtreeIfNeeded(); view.displayIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { failures.append("Bitmap unavailable: \(name)"); return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { failures.append("PNG unavailable: \(name)"); return }
        do { try data.write(to: URL(fileURLWithPath: "\(outputDir)/\(name).png")) }
        catch { failures.append(error.localizedDescription) }
        print("[Snapshot] \(name)")
    }
    private static func saveSettings() {
        let window = SettingsWindowController.shared.window
        window?.orderFrontRegardless()
        for (page, name) in [(0, "15-settings"), (1, "28-settings-appearance"), (2, "29-settings-connected"), (3, "47-settings-music"), (4, "39-settings-daily"), (5, "46-settings-modules")] {
            SettingsWindowController.shared.snapshotPage(page)
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            if let view = window?.contentView { save(view: view, name: name) }
        }
        SettingsWindowController.shared.snapshotPage(1, glass: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        if let view = window?.contentView { save(view: view, name: "30-settings-glass") }
        for (appearance, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            window?.appearance = NSAppearance(named: appearance)
            RunLoop.main.run(until: Date().addingTimeInterval(0.1))
            if let view = window?.contentView { save(view: view, name: "30-settings-glass-\(name)") }
        }
        window?.appearance = nil
        SettingsWindowController.shared.snapshotPage(1, legacy: true)
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        if let view = window?.contentView { save(view: view, name: "40-settings-macos15-layout") }
    }
    private static func runInteractionChecks(_ view: IslandView, completion: @escaping () -> Void) {
        func check(_ condition: Bool, _ label: String) { if !condition { failures.append(label) } }
        func descendants(_ root: NSView) -> [NSView] { root.subviews.flatMap { [$0] + descendants($0) } }
        view.enabledTabsOverride = IslandTab.allCases
        var lyricSample = MediaInfo(title: "时间轴", isPlaying: true, duration: 45, elapsed: 15)
        lyricSample.lyrics = [.init(time: 0, text: "第一行"), .init(time: 15.18, text: "第二行")]
        IslandPreferences.shared.lyricsAnimation = .efficient
        IslandPreferences.shared.gentleMotion = false
        view.mediaInfo = lyricSample; view.compactMediaVisible = true
        view.render(.idle(.time("")), animated: false)
        func hasVisibleLine(_ text: String) -> Bool {
            descendants(view).compactMap { $0 as? LyricTextView }.contains { $0.stringValue == text && !$0.isHiddenOrHasHiddenAncestor }
        }
        check(hasVisibleLine("第一行"), "Compact lyric did not follow the playback sample")
        IslandPreferences.shared.lyricsPlacement = .side
        view.refreshCompact()
        if let strip = descendants(view).compactMap({ $0 as? CompactLyricsView }).first {
            check(strip.frame.midX == view.debugVisibleRect.midX, "Side lyric wings are not symmetrical")
            let originalWidth = strip.sideExtension
            var customAppearance = LyricsAppearance()
            customAppearance.width = 136; customAppearance.glow = 0.8; customAppearance.colorRGB = 0x92DFDF
            IslandPreferences.shared.lyricsAppearance = customAppearance
            view.applyAppearance()
            check(strip.sideExtension < originalWidth && strip.frame.midX == view.debugVisibleRect.midX, "Side width changes moved the notch")
            let currentField = descendants(strip).compactMap { $0 as? LyricTextView }.first { $0.stringValue == "第一行" }
            check(currentField?.debugGlowActive == true, "Lyric glow not applied")
        } else { failures.append("Side lyric view missing") }
        RunLoop.main.run(until: Date().addingTimeInterval(0.24))
        check(hasVisibleLine("第二行"), "Compact lyric missed the next timestamp without a player refresh")
        let roll = descendants(view).compactMap { $0 as? LyricRollView }.first
        check(roll?.hasScrollAnimation == true || IslandPreferences.shared.reduceMotion, "Efficient lyric mode did not scroll")
        view.render(.notification(.demo), animated: false)
        check(!hasVisibleLine("第二行"), "Compact lyric obscures the notification")
        view.render(.idle(.time("")), animated: false)
        view.compactMediaVisible = false; view.refreshCompact()
        // Yield the main queue so the real delayed fade cleanup can execute.
        // A nested RunLoop inside this dispatch block cannot run another main-queue block.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.23) {
            check(!hasVisibleLine("第二行"), "Compact lyric did not retract after playback")
            lyricSample.elapsed = 15
            lyricSample.lyrics = [.init(time: 0, text: "第一行"),
                                  .init(time: 15.18, text: "星光", segments: [.init(time: 15.18, text: "星"), .init(time: 16, text: "光")])]
            lyricSample.sampledAt = Date()
            IslandPreferences.shared.lyricsAnimation = .appleMusic
            view.mediaInfo = lyricSample
            view.render(.workspace(.music, false), animated: false)
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            lyricSample.elapsed = 15.3
            lyricSample.sampledAt = Date()
            view.mediaInfo = lyricSample
            view.playbackPositionDidChange(animated: true)
            RunLoop.main.run(until: Date().addingTimeInterval(0.04))
            let playerRoll = descendants(view).compactMap { $0 as? LyricRollView }.first { !$0.isCompact && !$0.isHiddenOrHasHiddenAncestor }
            check(playerRoll?.hasScrollAnimation == true || IslandPreferences.shared.reduceMotion, "Apple Music lyric mode did not scroll")
            func colors(in text: String) -> [CGFloat] {
                descendants(view).compactMap { $0 as? LyricTextView }.first {
                    $0.stringValue == text && !$0.isHiddenOrHasHiddenAncestor
                }?.debugGlyphAlphas ?? []
            }
            let karaokeColors = colors(in: "星光")
            check(karaokeColors.count == 2 && karaokeColors[0] > karaokeColors[1], "Word timing did not highlight only the active segment")
            IslandPreferences.shared.lyricsAnimation = .efficient
            view.refreshCompact()
            let efficientColors = colors(in: "星光")
            check(efficientColors.count == 2 && efficientColors.allSatisfy { $0 > 0.9 }, "Efficient mode keeps per-word highlighting enabled")
            IslandPreferences.shared.lyricsAnimation = .appleMusic
            view.notificationPreviewOverride = nil
            view.backdropOverride = .init(style: .black, opacity: 0.58)
            var selected: IslandTab?
            view.onSelectTab = { selected = $0 }
            view.render(.workspace(.music, false), animated: false)
            check(!descendants(view).contains(where: { $0 is NSPopUpButton }), "Player picker still present")
            let buttons = descendants(view).compactMap { $0 as? ActionButton }
            buttons.first(where: { $0.toolTip == "暂存" })?.performClick(nil)
            check(selected == .files, "File tab did not dispatch")
            var starts: [Int] = []
            view.onTimerStart = { seconds, _ in starts.append(seconds) }
            view.timerSession = nil; view.render(.workspace(.timer, false), animated: false)
            descendants(view).compactMap { $0 as? ActionButton }.first(where: { $0.toolTip == "开始 25 分钟计时" })?.performClick(nil)
            check(starts == [1500], "25-minute preset failed")
            for tab in IslandTab.allCases {
                view.render(.workspace(tab, false), animated: false)
                check(view.debugVisibleRect.minY >= 0, "Panel exceeds window bounds: \(tab)")
                check(descendants(view).compactMap { $0 as? ActionButton }.filter { IslandTab.allCases.map(\.title).contains($0.toolTip ?? "") }.count == IslandTab.allCases.count, "Missing navigation item: \(tab)")
            }
            view.enabledTabsOverride = [.files]
            view.render(.workspace(.files, false), animated: false)
            let enabledButtons = descendants(view).compactMap { $0 as? ActionButton }.filter { IslandTab.allCases.map(\.title).contains($0.toolTip ?? "") }
            check(enabledButtons.count == 1 && enabledButtons.first?.toolTip == "暂存", "Disabled modules remain visible")
            view.enabledTabsOverride = []
            view.render(.workspace(.files, false), animated: false)
            check(!descendants(view).compactMap { $0 as? ActionButton }.contains { IslandTab.allCases.map(\.title).contains($0.toolTip ?? "") }, "All-off state retains module navigation")
            check(descendants(view).compactMap { $0 as? ActionButton }.contains { $0.toolTip == "打开设置" }, "All-off state has no settings escape")
            view.enabledTabsOverride = IslandTab.allCases
            view.render(.workspace(.clipboard, false), animated: false)
            let copy = descendants(view).compactMap { $0 as? ActionButton }.first { $0.toolTip == "重新复制这条记录" }
            check(copy != nil, "Clipboard rows missing")
            copy?.performClick(nil)
            check(descendants(view).compactMap { ($0 as? NSTextField)?.stringValue }.contains("已复制 · 切换到目标应用后粘贴"), "Clipboard copy feedback missing")
            view.render(.workspace(.audio, false), animated: false)
            let audioSliders = descendants(view).compactMap { $0 as? InteractionSlider }
            view.refreshConnectedPanels()
            check(audioSliders.first === descendants(view).compactMap { $0 as? InteractionSlider }.first, "Audio property refresh replaces active slider")
            view.selectedOutput = 3; view.outputVolumeAvailable = false; view.refreshConnectedPanels()
            check(descendants(view).compactMap { $0 as? InteractionSlider }.first?.isEnabled == false, "Fixed-volume output exposes an enabled slider")
            // An in-flight animation must be interrupted from its presentation state.
            for i in 0..<24 { view.render(i % 2 == 0 ? .workspace(.music, false) : .idle(.time("12:00"))) }
            check(!view.debugGeometry().isEmpty, "Rapid transition geometry unavailable")
            if let window = view.window {
                let blank = window.convertPoint(toScreen: NSPoint(x: 2, y: 2))
                check(!view.containsVisiblePoint(blank), "Transparent window corner captures interaction")
            }
            view.render(.volume(0.25, false), animated: false)
            let firstSlider = descendants(view).compactMap { $0 as? InteractionSlider }.first
            view.render(.volume(0.75, false), animated: false)
            let secondSlider = descendants(view).compactMap { $0 as? InteractionSlider }.first
            check(firstSlider != nil && firstSlider === secondSlider, "HUD update replaced an active slider")
            check(secondSlider?.doubleValue == 0.75, "HUD slider did not update")
            view.relayout()
            let relayoutSlider = descendants(view).compactMap { $0 as? InteractionSlider }.first
            check(secondSlider === relayoutSlider && relayoutSlider?.doubleValue == 0.75, "Relayout lost HUD slider reference or value")
            check(view.debugVisibleRect.height == view.debugNotchRect.height, "Volume HUD thickens the physical notch")
            view.render(.brightness(0.5), animated: false)
            check(view.debugVisibleRect.height == view.debugNotchRect.height, "Brightness HUD thickens the physical notch")
            view.mediaInfo = MediaInfo(title: "Test", isPlaying: true)
            view.compactMediaVisible = true
            view.render(.workspace(.music, false), animated: false)
            check(view.debugWaveAnimating || IslandPreferences.shared.reduceMotion, "Playing waveform did not animate")
            view.mediaInfo?.isPlaying = false
            view.refreshCompact()
            check(!view.debugWaveAnimating && view.debugWaveIsFlat, "Pause inside expanded panel leaves waveform running")
            view.compactMediaVisible = false
            view.timerSession = nil
            view.render(.idle(.time("")), animated: false)
            check(view.debugVisibleRect == view.debugNotchRect, "Idle footprint does not match physical notch")
            if let window = view.window, let screen = IslandPreferences.shared.screen {
                window.orderFrontRegardless(); NSApp.activate(ignoringOtherApps: true)
                RunLoop.main.run(until: Date().addingTimeInterval(0.15))
                check(abs(window.frame.maxY - screen.frame.maxY) < 0.5, "Window moved below menu bar after activation")
                check(window.level.rawValue > Int(CGWindowLevelForKey(.mainMenuWindow)), "Floating panel was lowered beneath the menu bar")
                let top = window.convertPoint(toScreen: view.convert(NSPoint(x: view.bounds.midX, y: view.bounds.maxY), to: nil))
                check(abs(top.y - screen.frame.maxY) < 0.5, "Content top does not touch the screen edge")
                print("[Geometry] screen=\(screen.frame) window=\(window.frame) top=\(top) notch=\(view.debugNotchRect)")
            }
            view.backdropOverride = .init(style: .glass, opacity: 0.58)
            view.render(.notification(.demo), animated: false)
            if #available(macOS 26.0, *), !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
                check(view.debugGlassActive, "Native Apple glass was not created for expanded content")
                view.render(.idle(.time("")))
                view.render(.notification(.demo))
                check(view.debugGlassClipBounds == view.debugVisibleRect, "Reopening during collapse leaves the glass mask retracted")
            }
            view.render(.idle(.time("")), animated: false)
            check(!view.debugGlassActive, "Idle notch retains a native glass compositor")
            view.render(.airPods(.demo), animated: false)
            check(descendants(view).contains { $0 is AirPodsConnectionView }, "AirPods connection card missing")
            view.setActivityVisible(false)
            check(!view.debugGlassActive && !view.debugWaveAnimating, "Hidden island retains active glass or waveform")
            view.setActivityVisible(true)
            view.backdropOverride = .init(style: .black, opacity: 0.1)
            view.render(.notification(.demo), animated: false)
            check(!view.debugGlassActive, "Black mode depends on glass parameters")
            let privacyNotice = IslandNotification(source: "Preview", title: "SECRET_TITLE", body: "SECRET_BODY", identity: "private-check")
            view.notificationPreviewOverride = true
            view.render(.notification(privacyNotice), animated: false)
            view.notificationPreviewOverride = false
            view.render(.notification(privacyNotice), animated: false)
            let strings = descendants(view).compactMap { ($0 as? NSTextField)?.stringValue }
            check(!strings.contains("SECRET_TITLE") && !strings.contains("SECRET_BODY"), "Notification privacy setting exposes notification content")
            view.notificationPreviewOverride = nil
            view.render(.workspace(.files, false), animated: false)
            if let row = descendants(view).compactMap({ $0 as? ShelfRowView }).first {
                check(row.hitTest(NSPoint(x: 60, y: 15)) === row, "File label blocks row dragging")
            } else { failures.append("File row missing from populated shelf") }
            view.render(.idle(.time("12:00")), animated: false)
            completion()
        }
    }
    private static func runPolishChecks(_ view: IslandView) {
        func check(_ condition: Bool, _ label: String) { if !condition { failures.append(label) } }
        func rows(_ root: NSView) -> [LyricTextView] {
            root.subviews.flatMap { [$0 as? LyricTextView].compactMap { $0 } + rows($0) }
        }
        IslandPreferences.shared.lyricsPlacement = .side
        IslandPreferences.shared.lyricsAnimation = .appleMusic
        var appearance = LyricsAppearance(); appearance.hdrEnabled = true; appearance.hdrStrength = 0.6
        IslandPreferences.shared.lyricsAppearance = appearance
        view.applyAppearance()
        var info = MediaInfo(title: "回归测试", isPlaying: true, duration: 40, elapsed: 0,
                             lyrics: [.init(time: 8, text: "第一句", segments: [.init(time: 8, text: "第一", endTime: 9), .init(time: 9, text: "句", endTime: 10)]), .init(time: 20, text: "下一句")])
        view.mediaInfo = info; view.compactMediaVisible = true
        for _ in 0..<8 { view.render(.idle(.time("")), animated: false) }
        let strip = view.subviews.compactMap { $0 as? CompactLyricsView }.first
        check(strip?.isHidden != false, "Prelude exposes an empty lyric background")
        info.elapsed = 8.05; info.sampledAt = Date(); view.mediaInfo = info
        view.render(.idle(.time("")), animated: false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.03))
        let row = rows(view).first { $0.stringValue == "第一句" && !$0.isHiddenOrHasHiddenAncestor }
        let first = row?.debugGlyphAlphas.first ?? 0
        RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        let second = row?.debugGlyphAlphas.first ?? 0
        check(IslandPreferences.shared.reduceMotion || second > first, "Individual glyph opacity does not transition continuously")
        let supportsEDR = (view.window?.screen?.maximumPotentialExtendedDynamicRangeColorComponentValue ?? 1) > 1
        if supportsEDR { check((row?.hdrGain ?? 1) > 1, "Saved HDR preference does not request EDR for compact lyrics") }
        print("[Polish] glyph opacity \(first) -> \(second), gain=\(row?.hdrGain ?? 1)")
        view.backdropOverride = nil
        IslandPreferences.shared.backgroundStyle = .glass
        view.render(.workspace(.music, false), animated: false)
        check(view.debugVisibleRect.height > view.debugNotchRect.height, "Music panel failed to expand")
        if IslandPreferences.supportsGlass && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency {
            check(view.debugGlassActive, "Saved glass preference does not activate native glass in the music panel")
            check(view.debugBackgroundAlpha == 0, "Glass panel still has an opaque base fill")
            IslandPreferences.shared.glassMaterial = .transparent
            view.applyAppearance()
            check(view.debugGlassActive && view.debugBackgroundAlpha == 0, "Untinted clear glass is missing or has a solid background")
            IslandPreferences.shared.glassMaterial = .regular
            view.applyAppearance()
        }
        if supportsEDR {
            let expandedRow = rows(view).first { $0.stringValue == "第一句" && !$0.isHiddenOrHasHiddenAncestor && $0 !== row }
            check((expandedRow?.hdrGain ?? 1) > 1, "Saved HDR preference does not request EDR in the expanded player")
            var ancestor = expandedRow?.layer
            while let layer = ancestor {
                check(layer.mask == nil, "Expanded HDR lyrics have an ancestor layer mask")
                ancestor = layer.superlayer
            }
            print("[Polish] expanded requested EDR gain=\(expandedRow?.hdrGain ?? 1)")
        }
        IslandPreferences.shared.backgroundStyle = .black
        view.applyAppearance()
        check(!view.debugGlassActive, "Changing the saved preference to black retains native glass")
        IslandPreferences.shared.backgroundStyle = .glass
        view.applyAppearance()
        view.setActivityVisible(false)
        check(!view.debugLyricTimerActive && rows(view).allSatisfy { !$0.debugHasGlyphAnimations }, "Hidden island retains glyph animation work")
        view.setActivityVisible(true)
        view.render(.idle(.time("")), animated: false)
        check(view.debugVisibleRect.width > view.debugNotchRect.width, "Collapsing the panel hides the active track")
        check(!view.debugGlassActive && view.debugBackgroundAlpha == 1, "Compact playback is not solid black")
        view.compactMediaVisible = false
        view.render(.idle(.time("")), animated: false)
        check(view.debugVisibleRect == view.debugNotchRect && !view.debugGlassActive && !view.debugLyricTimerActive, "Idle notch retains activity rendering")
    }
    static func makeArtwork() -> CGImage? {
        let image = NSImage(size: NSSize(width: 200, height: 200))
        image.lockFocus()
        NSGradient(colors: [NSColor(calibratedRed: 0.1, green: 0.38, blue: 0.43, alpha: 1), NSColor(calibratedRed: 0.09, green: 0.13, blue: 0.26, alpha: 1)])?.draw(in: NSRect(x: 0, y: 0, width: 200, height: 200), angle: 65)
        NSColor(calibratedRed: 0.76, green: 0.95, blue: 0.81, alpha: 0.9).setFill(); NSBezierPath(ovalIn: NSRect(x: 112, y: 109, width: 42, height: 42)).fill()
        NSColor(calibratedWhite: 0.04, alpha: 0.6).setFill()
        let hill = NSBezierPath(); hill.move(to: .zero); hill.curve(to: NSPoint(x: 200, y: 30), controlPoint1: NSPoint(x: 65, y: 120), controlPoint2: NSPoint(x: 110, y: 72)); hill.line(to: NSPoint(x: 200, y: 0)); hill.close(); hill.fill()
        image.unlockFocus()
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }
}
