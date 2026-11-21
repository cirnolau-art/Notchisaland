import AppKit

/// Explicit isolated on-screen QA fixture, never used during normal app startup.
/// Renders a real window behind the island without changing the user's wallpaper.
enum PolishPreview {
    private static var background: NSWindow?
    private static var monitor: Any?
    static func run(_ controller: IslandController) {
        guard let view = controller.debugView, let screen = view.window?.screen else { return }
        let panel = NSWindow(contentRect: CGRect(x: screen.frame.minX, y: screen.frame.maxY - 540, width: screen.frame.width, height: 540),
                             styleMask: .borderless, backing: .buffered, defer: false)
        panel.level = NSWindow.Level(rawValue: controller.window.level.rawValue - 1)
        panel.contentView = WallpaperFixture(frame: CGRect(origin: .zero, size: panel.frame.size))
        panel.isReleasedWhenClosed = false; panel.ignoresMouseEvents = true; panel.orderFrontRegardless()
        background = panel
        view.window?.ignoresMouseEvents = false
        let lyric = "你慢慢地走来"
        let segments = lyric.enumerated().map { LyricSegment(time: 2 + Double($0.offset) * 0.8, text: String($0.element), endTime: 2 + Double($0.offset + 1) * 0.8) }
        let info = MediaInfo(title: "界面与动画检查", artist: "隔离测试 · 不连接播放器",
                             artwork: SnapshotMode.makeArtwork(), isPlaying: true, duration: 90, elapsed: 2.1,
                             lyrics: [.init(time: 0, text: "穿过旷野的风"), .init(time: 2, text: lyric, segments: segments),
                                      .init(time: 8, text: "把星光放在手心"), .init(time: 12, text: "Stay here, let the music carry on"),
                                      .init(time: 18, text: "这是一个用于检查自动换行与平滑滚动的长歌词句子"), .init(time: 28, text: "最后一行")])
        view.mediaInfo = info; view.compactMediaVisible = true
        IslandPreferences.shared.lyricsPlacement = .side
        IslandPreferences.shared.expandedLyricsPlacement = .below
        IslandPreferences.shared.lyricsAnimation = .appleMusic
        var appearance = LyricsAppearance(); appearance.hdrEnabled = true; appearance.hdrStrength = 0.6; appearance.glow = 0.2
        IslandPreferences.shared.lyricsAppearance = appearance
        view.backdropOverride = .init(style: .glass, opacity: IslandBackdropConfiguration.defaultDarkening)
        view.applyAppearance()
        view.render(.workspace(.music, false))
        view.onExpand = { view.render(.workspace(.music, false)) }
        view.onDismiss = { view.render(.idle(.time(""))) }
        func showBackdrop(_ configuration: IslandBackdropConfiguration) {
            view.backdropOverride = configuration
            view.applyAppearance()
            view.render(.workspace(.music, false), animated: false)
        }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            switch event.charactersIgnoringModifiers {
            case "r", "a", "s":
                var appearance = IslandPreferences.shared.lyricsAppearance
                appearance.flowStyle = event.charactersIgnoringModifiers == "r" ? .rgb
                    : event.charactersIgnoringModifiers == "a" ? .artwork : .off
                IslandPreferences.shared.lyricsAppearance = appearance
                view.applyAppearance()
            case "p":
                if var sample = view.mediaInfo?.interpolated() {
                    sample.isPlaying.toggle()
                    sample.sampledAt = Date()
                    view.mediaInfo = sample
                    view.playbackPositionDidChange()
                }
            case "1": view.compactMediaVisible = true; view.render(.workspace(.music, false))
            case "2": view.compactMediaVisible = true; view.render(.idle(.time("")))
            case "3": view.compactMediaVisible = false; view.render(.idle(.time("")))
            case "4":
                view.mediaInfo?.elapsed = 0; view.mediaInfo?.sampledAt = Date()
                view.mediaInfo?.lyrics = [.init(time: 30, text: "前奏期间不应显示背景")]
                view.render(.idle(.time("")))
            case "5":
                showBackdrop(.init(style: .black, opacity: 0))
            case "6":
                showBackdrop(.init(style: .glass, opacity: IslandBackdropConfiguration.defaultDarkening))
            case "7":
                showBackdrop(.init(style: .glass, material: .clear, opacity: IslandBackdropConfiguration.defaultDarkening))
            case "8":
                showBackdrop(.init(style: .glass, material: .transparent, opacity: 0))
            case "9":
                var configuration = view.backdropOverride ?? .current
                configuration.showsGradient.toggle()
                showBackdrop(configuration)
            case "0":
                panel.orderOut(nil)
                controller.window.orderOut(nil)
                SettingsWindowController.shared.window?.appearance = NSAppearance(
                    named: CommandLine.arguments.contains("--preview-light") ? .aqua : .darkAqua)
                SettingsWindowController.shared.snapshotPage(1, glass: true)
                SettingsWindowController.shared.show()
            case "q": NSApp.terminate(nil)
            default: return event
            }
            return nil
        }
        controller.window.orderFrontRegardless(); controller.window.makeKey()
        NSApp.activate(ignoringOtherApps: true)
        print("[Preview] 1 expanded / 2 compact / 3 idle / 4 prelude / 5 black / 6 regular / 7 clear / 8 untinted / 9 gradient / 0 settings / q quit")
        print("[Preview] r RGB lyrics / a artwork lyrics / s normal lyrics / p pause or resume")
        print("[EDR] current=\(screen.maximumExtendedDynamicRangeColorComponentValue) potential=\(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            print("[EDR] after compositing current=\(screen.maximumExtendedDynamicRangeColorComponentValue)")
        }
    }
}

private final class WallpaperFixture: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let light = CommandLine.arguments.contains("--preview-light")
        let colors: [NSColor] = light ? [.init(srgbRed: 0.85, green: 0.94, blue: 1, alpha: 1), .init(srgbRed: 0.92, green: 0.77, blue: 0.61, alpha: 1)]
            : [.init(srgbRed: 0.04, green: 0.10, blue: 0.19, alpha: 1), .init(srgbRed: 0.22, green: 0.10, blue: 0.18, alpha: 1)]
        NSGradient(colors: colors)?.draw(in: bounds, angle: 18)
        for index in 0..<9 {
            NSColor.white.withAlphaComponent(light ? 0.4 : 0.07).setFill()
            NSBezierPath(roundedRect: CGRect(x: bounds.midX - 450 + CGFloat(index) * 110, y: 30, width: 54, height: bounds.height - 50), xRadius: 26, yRadius: 26).fill()
        }
    }
}
